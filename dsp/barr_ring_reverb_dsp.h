#pragma once

/**
 * @file barr_ring_reverb_dsp.h
 * @brief Clean-room Keith Barr All-Pass Ring Reverberator DSP.
 *
 * Mathematical Foundations & Historical Attribution:
 * - Keith Barr (Founder of MXR & Alesis, Creator of the Spin Semiconductor FV-1 DSP chip).
 * - Architecture derived from Keith Barr's landmark all-pass loop topology (US Patent 4,868,881;
 *   Spin Semiconductor Reference Program `rom_rev2.spn` & Knowledge Base "All-Pass Loop Reverberators").
 * - Powering legendary hardware units: Alesis MidiVerb II ("Bloom"), Quadraverb, and Spin FV-1 boutique pedals.
 *
 * Architectural Topology:
 * 1. Dual-Channel Cascaded Input Diffusers:
 *    4 cascaded Schroeder/Barr all-pass diffusers per channel (total 8) to smear incoming transients.
 * 2. 4-Stage Closed Recirculating Ring (`2AP -> LPF -> HPF -> Delay` in feedback):
 *    - Stage 1..4 lengths calibrated at 32.768 kHz, scaled cleanly for 11 kHz .. 384 kHz.
 *    - Sample-rate-invariant matched-Z 1-pole damping + 60 Hz DC/mud blocker HPF per stage.
 * 3. Quadrature LFO Modulation:
 *    0.5 Hz sine/cosine quadrature modulation on ap1 and ap3 with 4-point Catmull-Rom cubic
 *    interpolation and sample-rate-scaled buffer headroom (zero wrap corruption up to 384 kHz).
 * 4. Alternating-Polarity Multi-Tap Decorrelated Output Extraction + M/S Stereo Width.
 */

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <vector>
#include "denormals.h"

namespace sauti::dsp {

class BarrRingReverbDSP {
public:
    static constexpr int NUM_INPUT_DIFFUSERS = 4;
    static constexpr int NUM_STAGES = 4;

    // Base delay lengths from Keith Barr's Spin Semiconductor rom_rev2.spn (native at 32.768 kHz)
    static constexpr int BASE_IN_DIFF_L[NUM_INPUT_DIFFUSERS] = { 156, 223, 332, 548 };
    static constexpr int BASE_IN_DIFF_R[NUM_INPUT_DIFFUSERS] = { 186, 253, 302, 498 };

    static constexpr int BASE_AP_A[NUM_STAGES]   = { 1251,  943, 1282, 1174 };
    static constexpr int BASE_AP_B[NUM_STAGES]   = { 1551, 1343, 1381, 1382 };
    static constexpr int BASE_DELAYS[NUM_STAGES] = { 2859, 3145, 2476, 3568 };

    // Multi-tap extraction offsets & alternating stereo polarity
    static constexpr int BASE_TAP_L[NUM_STAGES] = { 2630, 1943, 1200, 2016 };
    static constexpr int BASE_TAP_R[NUM_STAGES] = { 2420, 1631, 1163, 2330 };
    static constexpr float TAP_GAINS_L[NUM_STAGES] = { 0.8f,  0.7f, -0.6f,  0.5f };
    static constexpr float TAP_GAINS_R[NUM_STAGES] = { 0.8f, -0.7f,  0.6f, -0.5f };

    BarrRingReverbDSP() {
        setSampleRate(48000.0);
        reset();
    }

    void setSampleRate(double rate) {
        if (rate <= 0.0) rate = 48000.0;
        if (std::abs(sampleRate - rate) < 0.1 && buffersAllocated) return;

        sampleRate = rate;
        double scale = sampleRate / 32768.0;
        if (scale < 0.25) scale = 0.25;

        for (int i = 0; i < NUM_INPUT_DIFFUSERS; ++i) {
            int lenL = std::max(16, (int)std::lround((double)BASE_IN_DIFF_L[i] * scale));
            int lenR = std::max(16, (int)std::lround((double)BASE_IN_DIFF_R[i] * scale));
            inDiffBufL[i].assign(lenL, 0.0f);
            inDiffBufR[i].assign(lenR, 0.0f);
            inDiffIdxL[i] = 0;
            inDiffIdxR[i] = 0;
        }

        const int modHeadroom = (int)std::ceil(8.0 * scale) + 12;
        for (int i = 0; i < NUM_STAGES; ++i) {
            int lenApA = std::max(32, (int)std::lround((double)BASE_AP_A[i] * scale));
            int lenApB = std::max(32, (int)std::lround((double)BASE_AP_B[i] * scale));
            int lenDel = std::max(64, (int)std::lround((double)BASE_DELAYS[i] * scale));

            // Sample-rate-scaled headroom only on modulated stages (0 and 2)
            const int extraA = (i == 0 || i == 2) ? modHeadroom : 0;
            apBufA[i].assign(lenApA + extraA, 0.0f);
            apBufB[i].assign(lenApB, 0.0f);
            delBuf[i].assign(lenDel, 0.0f);

            apLenA[i] = lenApA;
            apLenB[i] = lenApB;
            delLen[i] = lenDel;

            apIdxA[i] = 0;
            apIdxB[i] = 0;
            delIdx[i] = 0;

            dampStateLpf[i] = 0.0f;
            dampStateHpf[i] = 0.0f;

            tapOffsetL[i] = std::min(lenDel - 1, (int)std::lround((double)BASE_TAP_L[i] * scale));
            tapOffsetR[i] = std::min(lenDel - 1, (int)std::lround((double)BASE_TAP_R[i] * scale));
        }

        buffersAllocated = true;
        updateCoefficients();
        reset();
    }

    void setEnabled(bool e) { targetEnabled = e; }
    bool isEnabled() const { return targetEnabled; }

    void setParams(float wet, float dry, float roomSize, float damping, float width = 1.0f) {
        targetWet = std::clamp(wet, 0.0f, 2.0f);
        targetDry = std::clamp(dry, 0.0f, 2.0f);
        targetRoomSize = std::clamp(roomSize, 0.0f, 1.0f);
        targetDamping = std::clamp(damping, 0.0f, 1.0f);
        targetWidth = std::clamp(width, 0.0f, 2.0f);
        updateCoefficients();
    }

    void setWet(float w) { targetWet = std::clamp(w, 0.0f, 2.0f); }
    void setDry(float d) { targetDry = std::clamp(d, 0.0f, 2.0f); }
    void setRoomSize(float r) {
        targetRoomSize = std::clamp(r, 0.0f, 1.0f);
        updateCoefficients();
    }
    void setDamping(float d) {
        targetDamping = std::clamp(d, 0.0f, 1.0f);
        updateCoefficients();
    }
    void setWidth(float w) { targetWidth = std::clamp(w, 0.0f, 2.0f); }

    float getWet() const { return targetWet; }
    float getDry() const { return targetDry; }
    float getRoomSize() const { return targetRoomSize; }
    float getDamping() const { return targetDamping; }
    float getWidth() const { return targetWidth; }

    void reset() {
        for (int i = 0; i < NUM_INPUT_DIFFUSERS; ++i) {
            std::fill(inDiffBufL[i].begin(), inDiffBufL[i].end(), 0.0f);
            std::fill(inDiffBufR[i].begin(), inDiffBufR[i].end(), 0.0f);
            inDiffIdxL[i] = 0;
            inDiffIdxR[i] = 0;
        }

        for (int i = 0; i < NUM_STAGES; ++i) {
            std::fill(apBufA[i].begin(), apBufA[i].end(), 0.0f);
            std::fill(apBufB[i].begin(), apBufB[i].end(), 0.0f);
            std::fill(delBuf[i].begin(), delBuf[i].end(), 0.0f);
            apIdxA[i] = 0;
            apIdxB[i] = 0;
            delIdx[i] = 0;
            dampStateLpf[i] = 0.0f;
            dampStateHpf[i] = 0.0f;
        }

        lfoPhase = 0.0f;
        currentWet = targetWet;
        currentDry = targetDry;
        currentWidth = targetWidth;
        currentKrt_ = targetKrt_;
        currentLpfCoeff_ = targetLpfCoeff_;
        currentEnabled = targetEnabled;
    }

    void process(float *interleaved, uint32_t frames, int channels) {
        processImpl(interleaved, frames, channels, true);
    }

    void process(double *interleaved, uint32_t frames, int channels) {
        processImpl(interleaved, frames, channels, true);
    }

    void processWetOnly(float *interleaved, uint32_t frames, int channels) {
        processImpl(interleaved, frames, channels, false);
    }

    void processWetOnly(double *interleaved, uint32_t frames, int channels) {
        processImpl(interleaved, frames, channels, false);
    }

private:
    static float readCubic(const std::vector<float>& buf, int writeIdx, float delaySamples) {
        const int sz = (int)buf.size();
        if (sz < 8) return buf[writeIdx];
        const float maxD = (float)(sz - 4);
        if (delaySamples < 3.0f) delaySamples = 3.0f;
        if (delaySamples > maxD) delaySamples = maxD;

        float readPos = (float)writeIdx - delaySamples;
        while (readPos < 0.0f) readPos += (float)sz;
        while (readPos >= (float)sz) readPos -= (float)sz;

        const int i0 = (int)readPos;
        const int i1 = (i0 + 1 >= sz) ? 0 : i0 + 1;
        const int im1 = (i0 - 1 < 0) ? sz - 1 : i0 - 1;
        const int i2 = (i1 + 1 >= sz) ? 0 : i1 + 1;
        const float frac = readPos - (float)i0;

        const float y0 = buf[im1];
        const float y1 = buf[i0];
        const float y2 = buf[i1];
        const float y3 = buf[i2];

        const float c0 = y1;
        const float c1 = 0.5f * (y2 - y0);
        const float c2 = y0 - 2.5f * y1 + 2.0f * y2 - 0.5f * y3;
        const float c3 = 0.5f * (y3 - y0) + 1.5f * (y1 - y2);
        return ((c3 * frac + c2) * frac + c1) * frac + c0;
    }

    template <typename T>
    void processImpl(T *interleaved, uint32_t frames, int channels, bool mixDry) {
        if (!interleaved || frames == 0 || channels < 2 || !buffersAllocated)
            return;

        if (!targetEnabled && currentWet < 0.0001f) {
            currentEnabled = false;
            return;
        }
        currentEnabled = true;

        ScopedDenormalsDisable ftz;

        const float smoothCoeff = 1.0f - std::exp(-1.0f / (0.015f * (float)sampleRate));
        constexpr float twoPi = 6.28318530717958647692f;
        const float lfoInc = (twoPi * 0.5f) / (float)sampleRate;
        const float modDepth = 8.0f * (float)(sampleRate / 32768.0);

        for (uint32_t f = 0; f < frames; ++f) {
            currentWet += (targetWet - currentWet) * smoothCoeff;
            currentDry += (targetDry - currentDry) * smoothCoeff;
            currentWidth += (targetWidth - currentWidth) * smoothCoeff;
            currentKrt_ += (targetKrt_ - currentKrt_) * smoothCoeff;
            currentLpfCoeff_ += (targetLpfCoeff_ - currentLpfCoeff_) * smoothCoeff;

            const size_t idx = (size_t)f * (size_t)channels;
            const double rawInL = static_cast<double>(interleaved[idx]);
            const double rawInR = static_cast<double>(interleaved[idx + 1]);
            const float inL = static_cast<float>(rawInL);
            const float inR = static_cast<float>(rawInR);

            // 1. Process 4 Cascaded Input Diffusers per channel
            float diffInL = inL * 0.6f;
            float diffInR = inR * 0.6f;

            for (int i = 0; i < NUM_INPUT_DIFFUSERS; ++i) {
                const int szL = (int)inDiffBufL[i].size();
                const float bufOutL = inDiffBufL[i][inDiffIdxL[i]];
                const float yL = -0.6f * diffInL + bufOutL;
                float nextL = diffInL + 0.6f * yL;
                flush_denormal(nextL);
                inDiffBufL[i][inDiffIdxL[i]] = nextL;
                inDiffIdxL[i] = (inDiffIdxL[i] + 1 < szL) ? inDiffIdxL[i] + 1 : 0;
                diffInL = yL;

                const int szR = (int)inDiffBufR[i].size();
                const float bufOutR = inDiffBufR[i][inDiffIdxR[i]];
                const float yR = -0.6f * diffInR + bufOutR;
                float nextR = diffInR + 0.6f * yR;
                flush_denormal(nextR);
                inDiffBufR[i][inDiffIdxR[i]] = nextR;
                inDiffIdxR[i] = (inDiffIdxR[i] + 1 < szR) ? inDiffIdxR[i] + 1 : 0;
                diffInR = yR;
            }

            // Advance Quadrature LFO
            const float sinVal = std::sin(lfoPhase);
            const float cosVal = std::cos(lfoPhase);
            lfoPhase += lfoInc;
            if (lfoPhase >= twoPi) lfoPhase -= twoPi;

            // 2. Closed Recirculating Ring Processing
            const float stageInputs[NUM_STAGES] = {
                delBuf[3][delIdx[3]] * currentKrt_ + diffInL,
                delBuf[0][delIdx[0]] * currentKrt_ + diffInR,
                delBuf[1][delIdx[1]] * currentKrt_ + diffInL,
                delBuf[2][delIdx[2]] * currentKrt_ + diffInR
            };

            const float modOffsets[NUM_STAGES] = {
                sinVal * modDepth,
                0.0f,
                cosVal * modDepth,
                0.0f
            };

            for (int s = 0; s < NUM_STAGES; ++s) {
                const float sig = stageInputs[s];

                // First allpass in stage (coeff 0.6; cubic interp only on modulated stages 0 & 2)
                const int apASize = (int)apBufA[s].size();
                const float apAOutVal = (s == 0 || s == 2)
                    ? readCubic(apBufA[s], apIdxA[s], (float)apLenA[s] + modOffsets[s])
                    : apBufA[s][apIdxA[s]];

                float yA = -0.6f * sig + apAOutVal;
                flush_denormal(yA);
                float nextA = sig + 0.6f * yA;
                flush_denormal(nextA);
                apBufA[s][apIdxA[s]] = nextA;
                apIdxA[s] = (apIdxA[s] + 1 < apASize) ? apIdxA[s] + 1 : 0;

                // Second allpass in stage (coeff 0.5)
                const float bufOutB = apBufB[s][apIdxB[s]];
                float yB = -0.5f * yA + bufOutB;
                flush_denormal(yB);
                float nextB = yA + 0.5f * yB;
                flush_denormal(nextB);
                apBufB[s][apIdxB[s]] = nextB;
                apIdxB[s] = (apIdxB[s] + 1 < apLenB[s]) ? apIdxB[s] + 1 : 0;

                // Sample-rate-invariant 1-Pole LPF damping + 60 Hz DC/mud blocker HPF
                dampStateLpf[s] += currentLpfCoeff_ * (yB - dampStateLpf[s]);
                flush_denormal(dampStateLpf[s]);
                dampStateHpf[s] += hpfCoeff_ * (dampStateLpf[s] - dampStateHpf[s]);
                flush_denormal(dampStateHpf[s]);
                const float stageOut = dampStateLpf[s] - dampStateHpf[s];

                // Write to main stage delay line
                delBuf[s][delIdx[s]] = stageOut;
                delIdx[s] = (delIdx[s] + 1 < delLen[s]) ? delIdx[s] + 1 : 0;
            }

            // 3. Alternating-Polarity Multi-Tap Extraction Matrix
            float wetL = 0.0f;
            float wetR = 0.0f;

            for (int s = 0; s < NUM_STAGES; ++s) {
                int readTapL = delIdx[s] - tapOffsetL[s];
                if (readTapL < 0) readTapL += delLen[s];
                wetL += delBuf[s][readTapL] * TAP_GAINS_L[s];

                int readTapR = delIdx[s] - tapOffsetR[s];
                if (readTapR < 0) readTapR += delLen[s];
                wetR += delBuf[s][readTapR] * TAP_GAINS_R[s];
            }

            wetL *= 0.32f;
            wetR *= 0.32f;

            // 4. Stereo Width M/S Balance
            const float mid = 0.5f * (wetL + wetR);
            const float side = 0.5f * (wetL - wetR) * currentWidth;
            const float outL = mid + side;
            const float outR = mid - side;

            if (mixDry) {
                interleaved[idx]     = static_cast<T>(rawInL * static_cast<double>(currentDry) + static_cast<double>(outL) * static_cast<double>(currentWet));
                interleaved[idx + 1] = static_cast<T>(rawInR * static_cast<double>(currentDry) + static_cast<double>(outR) * static_cast<double>(currentWet));
            } else {
                interleaved[idx]     = static_cast<T>(static_cast<double>(outL) * static_cast<double>(currentWet));
                interleaved[idx + 1] = static_cast<T>(static_cast<double>(outR) * static_cast<double>(currentWet));
            }
        }
    }

    void updateCoefficients() {
        if (sampleRate <= 0.0) return;
        constexpr float twoPi = 6.28318530717958647692f;
        // Total ring loop delay at 32.768 kHz is ~22367 samples (~0.6826s), ~0.1706s per stage
        const float targetRT60 = 0.35f * std::pow(40.0f, targetRoomSize);
        targetKrt_ = std::min(0.985f, std::pow(10.0f, -3.0f * 0.1706f / targetRT60));

        if (targetDamping <= 0.0001f) {
            targetLpfCoeff_ = 1.0f;
        } else {
            const float dampHz = 18000.0f * std::pow(0.0667f, targetDamping);
            const float w = std::min(3.0f, twoPi * dampHz / (float)sampleRate);
            targetLpfCoeff_ = 1.0f - std::exp(-w);
        }

        hpfCoeff_ = 1.0f - std::exp(-std::min(3.0f, twoPi * 60.0f / (float)sampleRate));
    }

    double sampleRate = 48000.0;
    bool buffersAllocated = false;

    std::vector<float> inDiffBufL[NUM_INPUT_DIFFUSERS];
    std::vector<float> inDiffBufR[NUM_INPUT_DIFFUSERS];
    int inDiffIdxL[NUM_INPUT_DIFFUSERS] = {0};
    int inDiffIdxR[NUM_INPUT_DIFFUSERS] = {0};

    std::vector<float> apBufA[NUM_STAGES];
    std::vector<float> apBufB[NUM_STAGES];
    std::vector<float> delBuf[NUM_STAGES];

    int apLenA[NUM_STAGES] = {0};
    int apLenB[NUM_STAGES] = {0};
    int delLen[NUM_STAGES] = {0};

    int apIdxA[NUM_STAGES] = {0};
    int apIdxB[NUM_STAGES] = {0};
    int delIdx[NUM_STAGES] = {0};

    float dampStateLpf[NUM_STAGES] = {0.0f};
    float dampStateHpf[NUM_STAGES] = {0.0f};

    int tapOffsetL[NUM_STAGES] = {0};
    int tapOffsetR[NUM_STAGES] = {0};

    float lfoPhase = 0.0f;
    float targetKrt_ = 0.70f;
    float currentKrt_ = 0.70f;
    float targetLpfCoeff_ = 0.65f;
    float currentLpfCoeff_ = 0.65f;
    float hpfCoeff_ = 0.008f;

    float targetWet = 0.35f;
    float targetDry = 1.0f;
    float targetRoomSize = 0.70f;
    float targetDamping = 0.30f;
    float targetWidth = 1.0f;
    bool targetEnabled = false;

    float currentWet = 0.35f;
    float currentDry = 1.0f;
    float currentWidth = 1.0f;
    bool currentEnabled = false;
};

} // namespace sauti::dsp
