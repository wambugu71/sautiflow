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
 *    4 cascaded Schroeder/Barr all-pass diffusers per channel (total 8) to smear incoming transients
 *    into a dense initial reflection cloud before injection into the ring.
 * 2. 4-Stage Closed Recirculating Ring (`2AP -> Delay -> 2AP -> Delay` in feedback):
 *    - Stage 1: Dual Allpasses (ap1: 1251, ap1b: 1551) -> Shelving Damping -> Delay 1 (2859 samples).
 *    - Stage 2: Dual Allpasses (ap2: 943, ap2b: 1343) -> Shelving Damping -> Delay 2 (3145 samples).
 *    - Stage 3: Dual Allpasses (ap3: 1282, ap3b: 1381) -> Shelving Damping -> Delay 3 (2476 samples).
 *    - Stage 4: Dual Allpasses (ap4: 1174, ap4b: 1382) -> Shelving Damping -> Delay 4 (3568 samples).
 *    - Closed feedback loop: Delay 4 feeds Stage 1, Delay 1 feeds Stage 2, Delay 2 feeds Stage 3, Delay 3 feeds Stage 4.
 * 3. Quadrature LFO Modulation:
 *    0.5 Hz sine/cosine quadrature modulation on ap1 and ap3, eliminating repetitive mechanical flutter
 *    and imparting the signature lush, dreamy acoustic wash.
 * 4. Multi-Tap Decorrelated Output Extraction:
 *    4 distinct weighted taps per stereo channel extracted from the 4 delay lines:
 *    - Left:  0.8*del1[2630] + 0.7*del2[1943] + 0.6*del3[1200] + 0.5*del4[2016]
 *    - Right: 0.8*del1[2420] + 0.7*del2[1631] + 0.6*del3[1163] + 0.5*del4[2330]
 * 5. Mid/Side Stereo Width Balance & Per-Sample Click-Free Wet/Dry Crossfader.
 */

#include <cmath>
#include <cstdint>
#include <vector>
#include <algorithm>
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

    // Multi-tap extraction offsets
    static constexpr int BASE_TAP_L[NUM_STAGES] = { 2630, 1943, 1200, 2016 };
    static constexpr int BASE_TAP_R[NUM_STAGES] = { 2420, 1631, 1163, 2330 };
    static constexpr float TAP_GAINS[NUM_STAGES] = { 0.8f, 0.7f, 0.6f, 0.5f };

    BarrRingReverbDSP() {
        setSampleRate(48000.0);
        reset();
    }

    void setSampleRate(double rate) {
        if (rate <= 0.0) rate = 48000.0;
        if (std::abs(sampleRate - rate) < 0.1 && buffersAllocated) return;

        sampleRate = rate;
        // Keith Barr's original FV-1 timing is calibrated at 32768 Hz
        double scale = sampleRate / 32768.0;
        if (scale < 0.25) scale = 0.25;

        for (int i = 0; i < NUM_INPUT_DIFFUSERS; ++i) {
            int lenL = std::max(16, (int)std::round(BASE_IN_DIFF_L[i] * scale));
            int lenR = std::max(16, (int)std::round(BASE_IN_DIFF_R[i] * scale));
            inDiffBufL[i].assign(lenL, 0.0f);
            inDiffBufR[i].assign(lenR, 0.0f);
            inDiffIdxL[i] = 0;
            inDiffIdxR[i] = 0;
        }

        for (int i = 0; i < NUM_STAGES; ++i) {
            int lenApA = std::max(32, (int)std::round(BASE_AP_A[i] * scale));
            int lenApB = std::max(32, (int)std::round(BASE_AP_B[i] * scale));
            int lenDel = std::max(64, (int)std::round(BASE_DELAYS[i] * scale));

            // Provide extra headroom (+32 samples) for LFO modulation on ap1 and ap3
            apBufA[i].assign(lenApA + 32, 0.0f);
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

            tapOffsetL[i] = std::min(lenDel - 1, (int)std::round(BASE_TAP_L[i] * scale));
            tapOffsetR[i] = std::min(lenDel - 1, (int)std::round(BASE_TAP_R[i] * scale));
        }

        buffersAllocated = true;
        updateCoefficients();
        reset();
    }

    void setEnabled(bool e) {
        targetEnabled = e;
        if (!e) currentEnabled = false;
    }

    bool isEnabled() const { return targetEnabled; }

    void setParams(float wet, float dry, float roomSize, float damping, float width = 1.0f) {
        setWet(wet);
        setDry(dry);
        setRoomSize(roomSize);
        setDamping(damping);
        setWidth(width);
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
        currentRoomSize = targetRoomSize;
        currentDamping = targetDamping;
        currentWidth = targetWidth;
        currentEnabled = targetEnabled;
    }

    void process(float *interleaved, uint32_t frames, int channels) {
        if (!interleaved || frames == 0 || channels < 2 || !buffersAllocated)
            return;

        if (!targetEnabled && currentWet < 0.0001f) {
            currentEnabled = false;
            return;
        }
        currentEnabled = true;

        const float smoothCoeff = 0.002f;
        const float twoPi = 6.28318530717958647692f;
        const float lfoInc = (twoPi * 0.5f) / (float)sampleRate; // 0.5 Hz LFO
        const float modDepth = 8.0f; // +/- 8 samples modulation

        for (uint32_t f = 0; f < frames; ++f) {
            currentWet += (targetWet - currentWet) * smoothCoeff;
            currentDry += (targetDry - currentDry) * smoothCoeff;
            currentWidth += (targetWidth - currentWidth) * smoothCoeff;

            uint32_t idx = f * channels;
            float inL = interleaved[idx];
            float inR = interleaved[idx + 1];

            // 1. Process 4 Cascaded Input Diffusers per channel
            float diffInL = inL * 0.6f;
            float diffInR = inR * 0.6f;

            for (int i = 0; i < NUM_INPUT_DIFFUSERS; ++i) {
                // Left allpass (Direct Form II): y[n] = -g*x[n] + buf; buf = x[n] + g*y[n]
                float bufOutL = inDiffBufL[i][inDiffIdxL[i]];
                float yL = -0.6f * diffInL + bufOutL;
                inDiffBufL[i][inDiffIdxL[i]] = diffInL + 0.6f * yL;
                inDiffIdxL[i] = (inDiffIdxL[i] + 1) % (int)inDiffBufL[i].size();
                diffInL = yL;

                // Right allpass
                float bufOutR = inDiffBufR[i][inDiffIdxR[i]];
                float yR = -0.6f * diffInR + bufOutR;
                inDiffBufR[i][inDiffIdxR[i]] = diffInR + 0.6f * yR;
                inDiffIdxR[i] = (inDiffIdxR[i] + 1) % (int)inDiffBufR[i].size();
                diffInR = yR;
            }

            // Advance Quadrature LFO
            float sinVal = std::sin(lfoPhase);
            float cosVal = std::cos(lfoPhase);
            lfoPhase += lfoInc;
            if (lfoPhase >= twoPi) lfoPhase -= twoPi;

            // 2. Closed Recirculating Ring Processing
            // In Keith Barr's rom_rev2.spn:
            // Stage 1 input = del4_out * krt + diffInL
            // Stage 2 input = del1_out * krt + diffInR
            // Stage 3 input = del2_out * krt + diffInL
            // Stage 4 input = del3_out * krt + diffInR

            float stageInputs[NUM_STAGES];
            stageInputs[0] = delBuf[3][delIdx[3]] * krt_ + diffInL;
            stageInputs[1] = delBuf[0][delIdx[0]] * krt_ + diffInR;
            stageInputs[2] = delBuf[1][delIdx[1]] * krt_ + diffInL;
            stageInputs[3] = delBuf[2][delIdx[2]] * krt_ + diffInR;

            float modOffsets[NUM_STAGES] = {
                sinVal * modDepth, // ap1 modulated by Sine
                0.0f,
                cosVal * modDepth, // ap3 modulated by Cosine (90 deg quadrature)
                0.0f
            };

            for (int s = 0; s < NUM_STAGES; ++s) {
                float sig = stageInputs[s];

                // First allpass in stage (coeff 0.6, with modulation on stages 0 & 2)
                int apASize = (int)apBufA[s].size();
                float readPos = (float)apIdxA[s] - ((float)apLenA[s] + modOffsets[s]);
                while (readPos < 0.0f) readPos += (float)apASize;
                while (readPos >= (float)apASize) readPos -= (float)apASize;

                int i0 = (int)readPos;
                int i1 = (i0 + 1 >= apASize) ? 0 : i0 + 1;
                float frac = readPos - (float)i0;
                float apAOutVal = apBufA[s][i0] + frac * (apBufA[s][i1] - apBufA[s][i0]);

                float yA = -0.6f * sig + apAOutVal;
                flush_denormal(yA);
                apBufA[s][apIdxA[s]] = sig + 0.6f * yA;
                apIdxA[s] = (apIdxA[s] + 1) % apASize;

                // Second allpass in stage (coeff 0.5)
                float bufOutB = apBufB[s][apIdxB[s]];
                float yB = -0.5f * yA + bufOutB;
                flush_denormal(yB);
                apBufB[s][apIdxB[s]] = yA + 0.5f * yB;
                apIdxB[s] = (apIdxB[s] + 1) % apLenB[s];

                // 1-Pole Lowpass damping absorption
                dampStateLpf[s] = dampStateLpf[s] + lpfCoeff_ * (yB - dampStateLpf[s]);
                flush_denormal(dampStateLpf[s]);

                // Write to main stage delay line
                delBuf[s][delIdx[s]] = dampStateLpf[s];
                delIdx[s] = (delIdx[s] + 1) % delLen[s];
            }

            // 3. Multi-Tap Extraction Matrix (Keith Barr rom_rev2 taps)
            float wetL = 0.0f;
            float wetR = 0.0f;

            for (int s = 0; s < NUM_STAGES; ++s) {
                int readTapL = delIdx[s] - tapOffsetL[s];
                if (readTapL < 0) readTapL += delLen[s];
                wetL += delBuf[s][readTapL] * TAP_GAINS[s];

                int readTapR = delIdx[s] - tapOffsetR[s];
                if (readTapR < 0) readTapR += delLen[s];
                wetR += delBuf[s][readTapR] * TAP_GAINS[s];
            }

            wetL *= 0.32f;
            wetR *= 0.32f;

            // 4. Stereo Width M/S Balance
            float mid = 0.5f * (wetL + wetR);
            float side = 0.5f * (wetL - wetR) * currentWidth;
            float outL = mid + side;
            float outR = mid - side;

            interleaved[idx]     = inL * currentDry + outL * currentWet;
            interleaved[idx + 1] = inR * currentDry + outR * currentWet;
        }
    }

private:
    void updateCoefficients() {
        // Keith Barr krt spans 0.2 to 0.94
        krt_ = 0.20f + targetRoomSize * 0.74f;

        // Damping lowpass filter coefficient (0.05 to 0.75)
        lpfCoeff_ = 1.0f - (0.05f + targetDamping * 0.70f);
    }

    double sampleRate = 48000.0;
    bool buffersAllocated = false;

    // Input diffusers
    std::vector<float> inDiffBufL[NUM_INPUT_DIFFUSERS];
    std::vector<float> inDiffBufR[NUM_INPUT_DIFFUSERS];
    int inDiffIdxL[NUM_INPUT_DIFFUSERS] = {0};
    int inDiffIdxR[NUM_INPUT_DIFFUSERS] = {0};

    // 4 Ring Stages
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
    float krt_ = 0.70f;
    float lpfCoeff_ = 0.50f;

    float targetWet = 0.35f;
    float targetDry = 1.0f;
    float targetRoomSize = 0.70f;
    float targetDamping = 0.30f;
    float targetWidth = 1.0f;
    bool targetEnabled = false;

    float currentWet = 0.35f;
    float currentDry = 1.0f;
    float currentRoomSize = 0.70f;
    float currentDamping = 0.30f;
    float currentWidth = 1.0f;
    bool currentEnabled = false;
};

} // namespace sauti::dsp
