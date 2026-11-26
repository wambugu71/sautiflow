#pragma once

/**
 * @file griesinger_tank_dsp.h
 * @brief Clean-room David Griesinger "Spin & Wander" Concert Hall Tank Reverberator DSP.
 *
 * Mathematical Foundations & Historical Attribution:
 * - Dr. David Griesinger (Chief Scientist, Lexicon; inventor of the Lexicon 224, 480L, and PCM series).
 * - Landmarks: "Practical Processors and Programs for Digital Reverberation" (JAES 1986);
 *   "Improving Room Simulation through Novel Steerable Digital Reverberation" (JAES 1989).
 *
 * Architecture & The "Spin & Wander" Engine:
 * 1. 70 Hz matched-Z input HPF + Dual-Channel Cascaded Input Diffusers (4 prime allpasses/ch).
 * 2. Distinct large-hall Figure-8 Tank Loops (Tank 1 <-> Tank 2, tuned @ 29.761 kHz)
 *    with 50 Hz loop DC blocker and sample-rate-invariant matched-Z damping.
 * 3. "Spin" Quadrature Modulation (0.75 Hz & 1.10 Hz) + authentic slow "Wander" random walk
 *    (0.85 s target interval, 0.45 s smoothing -> <1.5 cents organic drift, zero FM grit).
 * 4. 4-point Catmull-Rom cubic interpolation + sample-rate-scaled modulation headroom
 *    (safe across 11 kHz .. 384 kHz).
 * 5. 12-Tap mutually prime in-bounds output matrix + M/S stereo width.
 */

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <vector>
#include "denormals.h"

namespace sauti::dsp {

class GriesingerTankDSP {
public:
    static constexpr int NUM_DIFFUSERS = 4;

    // Distinct stereo prime input diffusers @ 29.761 kHz
    static constexpr int BASE_DIFF_L[NUM_DIFFUSERS] = { 173, 131, 419, 313 };
    static constexpr int BASE_DIFF_R[NUM_DIFFUSERS] = { 181, 137, 433, 331 };
    static constexpr float DIFF_COEFFS[NUM_DIFFUSERS] = { 0.70f, 0.70f, 0.60f, 0.60f };

    // Large Concert Hall tank loop delay lines @ 29.761 kHz (all prime, distinct from Dattorro)
    static constexpr int BASE_TANK1_AP1  = 823;
    static constexpr int BASE_TANK1_DEL1 = 5233;
    static constexpr int BASE_TANK1_AP2  = 2129;
    static constexpr int BASE_TANK1_DEL2 = 4391;

    static constexpr int BASE_TANK2_AP1  = 1091;
    static constexpr int BASE_TANK2_DEL1 = 4937;
    static constexpr int BASE_TANK2_AP2  = 2909;
    static constexpr int BASE_TANK2_DEL2 = 3853;

    // Mutually prime output taps strictly within each buffer's length
    static constexpr int BASE_TAPS_T1_D1[3] = { 317, 2411, 4219 }; // < 5233
    static constexpr int BASE_TAPS_T1_D2[3] = { 491, 1877, 3673 }; // < 4391
    static constexpr int BASE_TAPS_T2_D1[3] = { 409, 2683, 4057 }; // < 4937
    static constexpr int BASE_TAPS_T2_D2[3] = { 353, 1759, 3299 }; // < 3853

    GriesingerTankDSP() {
        setSampleRate(48000.0);
        reset();
    }

    void setSampleRate(double rate) {
        if (rate <= 0.0) rate = 48000.0;
        if (std::abs(sampleRate - rate) < 0.1 && buffersAllocated) return;

        sampleRate = rate;
        double scale = sampleRate / 29761.0;
        if (scale < 0.25) scale = 0.25;

        for (int i = 0; i < NUM_DIFFUSERS; ++i) {
            int lenL = std::max(16, (int)std::lround((double)BASE_DIFF_L[i] * scale));
            int lenR = std::max(16, (int)std::lround((double)BASE_DIFF_R[i] * scale));
            diffBufL[i].assign(lenL, 0.0f);
            diffBufR[i].assign(lenR, 0.0f);
            diffIdxL[i] = 0;
            diffIdxR[i] = 0;
        }

        // Max excursion: spinDepth (6) + wanderDepth (10) = 16 samples @ 29.761 kHz
        const int modHeadroom = (int)std::ceil(16.0 * scale) + 12;

        t1_ap1_len = std::max(32, (int)std::lround((double)BASE_TANK1_AP1 * scale));
        t1_del1_len = std::max(64, (int)std::lround((double)BASE_TANK1_DEL1 * scale));
        t1_ap2_len = std::max(32, (int)std::lround((double)BASE_TANK1_AP2 * scale));
        t1_del2_len = std::max(64, (int)std::lround((double)BASE_TANK1_DEL2 * scale));

        t1_ap1_buf.assign(t1_ap1_len + modHeadroom, 0.0f);
        t1_del1_buf.assign(t1_del1_len, 0.0f);
        t1_ap2_buf.assign(t1_ap2_len, 0.0f);
        t1_del2_buf.assign(t1_del2_len, 0.0f);

        t2_ap1_len = std::max(32, (int)std::lround((double)BASE_TANK2_AP1 * scale));
        t2_del1_len = std::max(64, (int)std::lround((double)BASE_TANK2_DEL1 * scale));
        t2_ap2_len = std::max(32, (int)std::lround((double)BASE_TANK2_AP2 * scale));
        t2_del2_len = std::max(64, (int)std::lround((double)BASE_TANK2_DEL2 * scale));

        t2_ap1_buf.assign(t2_ap1_len + modHeadroom, 0.0f);
        t2_del1_buf.assign(t2_del1_len, 0.0f);
        t2_ap2_buf.assign(t2_ap2_len, 0.0f);
        t2_del2_buf.assign(t2_del2_len, 0.0f);

        for (int i = 0; i < 3; ++i) {
            tapT1D1[i] = std::min(t1_del1_len - 1, (int)std::lround((double)BASE_TAPS_T1_D1[i] * scale));
            tapT1D2[i] = std::min(t1_del2_len - 1, (int)std::lround((double)BASE_TAPS_T1_D2[i] * scale));
            tapT2D1[i] = std::min(t2_del1_len - 1, (int)std::lround((double)BASE_TAPS_T2_D1[i] * scale));
            tapT2D2[i] = std::min(t2_del2_len - 1, (int)std::lround((double)BASE_TAPS_T2_D2[i] * scale));
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
        for (int i = 0; i < NUM_DIFFUSERS; ++i) {
            std::fill(diffBufL[i].begin(), diffBufL[i].end(), 0.0f);
            std::fill(diffBufR[i].begin(), diffBufR[i].end(), 0.0f);
            diffIdxL[i] = 0;
            diffIdxR[i] = 0;
        }

        std::fill(t1_ap1_buf.begin(), t1_ap1_buf.end(), 0.0f);
        std::fill(t1_del1_buf.begin(), t1_del1_buf.end(), 0.0f);
        std::fill(t1_ap2_buf.begin(), t1_ap2_buf.end(), 0.0f);
        std::fill(t1_del2_buf.begin(), t1_del2_buf.end(), 0.0f);

        std::fill(t2_ap1_buf.begin(), t2_ap1_buf.end(), 0.0f);
        std::fill(t2_del1_buf.begin(), t2_del1_buf.end(), 0.0f);
        std::fill(t2_ap2_buf.begin(), t2_ap2_buf.end(), 0.0f);
        std::fill(t2_del2_buf.begin(), t2_del2_buf.end(), 0.0f);

        t1_ap1_idx = t1_del1_idx = t1_ap2_idx = t1_del2_idx = 0;
        t2_ap1_idx = t2_del1_idx = t2_ap2_idx = t2_del2_idx = 0;

        inHpfStateL = inHpfStateR = 0.0f;
        t1_damp_state = t2_damp_state = 0.0f;
        t1_hpf_state = t2_hpf_state = 0.0f;
        t1_last_out = t2_last_out = 0.0f;

        spinPhase1 = 0.0f;
        spinPhase2 = 1.57079632679f;

        wanderVal1 = wanderVal2 = 0.0f;
        wanderTarget1 = wanderTarget2 = 0.0f;
        wanderCounter = 0;

        currentWet = targetWet;
        currentDry = targetDry;
        currentWidth = targetWidth;
        currentDecayGain_ = targetDecayGain_;
        currentDampCoeff_ = targetDampCoeff_;
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

    static inline float readTap(const std::vector<float>& buf, int writeIdx, int offset, int len) {
        int rIdx = writeIdx - offset;
        if (rIdx < 0) rIdx += len;
        return buf[rIdx];
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
        const float spinInc1 = (twoPi * 0.75f) / (float)sampleRate;
        const float spinInc2 = (twoPi * 1.10f) / (float)sampleRate;
        const float rateScale = (float)(sampleRate / 29761.0);
        const float spinDepth = 6.0f * rateScale;
        const float wanderDepth = 10.0f * rateScale;
        // Authentic slow Lexicon Wander (~0.85s target period, 0.45s lowpass tracking)
        const int wanderPeriod = std::max(1024, (int)std::round(0.85 * sampleRate));
        const float wanderSmooth = 1.0f - std::exp(-1.0f / (0.45f * (float)sampleRate));

        for (uint32_t f = 0; f < frames; ++f) {
            currentWet += (targetWet - currentWet) * smoothCoeff;
            currentDry += (targetDry - currentDry) * smoothCoeff;
            currentWidth += (targetWidth - currentWidth) * smoothCoeff;
            currentDecayGain_ += (targetDecayGain_ - currentDecayGain_) * smoothCoeff;
            currentDampCoeff_ += (targetDampCoeff_ - currentDampCoeff_) * smoothCoeff;

            const size_t idx = (size_t)f * (size_t)channels;
            const double rawInL = static_cast<double>(interleaved[idx]);
            const double rawInR = static_cast<double>(interleaved[idx + 1]);
            const float inL = static_cast<float>(rawInL);
            const float inR = static_cast<float>(rawInR);

            // 1. 70 Hz matched-Z input HPF + 4 cascaded input diffusers per channel
            inHpfStateL += inHpfCoeff_ * (inL - inHpfStateL);
            inHpfStateR += inHpfCoeff_ * (inR - inHpfStateR);
            flush_denormal(inHpfStateL);
            flush_denormal(inHpfStateR);
            float dInL = inL - inHpfStateL;
            float dInR = inR - inHpfStateR;

            for (int i = 0; i < NUM_DIFFUSERS; ++i) {
                const float coeff = DIFF_COEFFS[i];

                const int szL = (int)diffBufL[i].size();
                const float bufL = diffBufL[i][diffIdxL[i]];
                const float yL = -coeff * dInL + bufL;
                float nextL = dInL + coeff * yL;
                flush_denormal(nextL);
                diffBufL[i][diffIdxL[i]] = nextL;
                diffIdxL[i] = (diffIdxL[i] + 1 < szL) ? diffIdxL[i] + 1 : 0;
                dInL = yL;

                const int szR = (int)diffBufR[i].size();
                const float bufR = diffBufR[i][diffIdxR[i]];
                const float yR = -coeff * dInR + bufR;
                float nextR = dInR + coeff * yR;
                flush_denormal(nextR);
                diffBufR[i][diffIdxR[i]] = nextR;
                diffIdxR[i] = (diffIdxR[i] + 1 < szR) ? diffIdxR[i] + 1 : 0;
                dInR = yR;
            }

            // 2. Advance "Spin" LFOs and slow "Wander" random-walk drift
            const float spinVal1 = std::sin(spinPhase1);
            const float spinVal2 = std::sin(spinPhase2);
            spinPhase1 += spinInc1;
            if (spinPhase1 >= twoPi) spinPhase1 -= twoPi;
            spinPhase2 += spinInc2;
            if (spinPhase2 >= twoPi) spinPhase2 -= twoPi;

            if (++wanderCounter >= wanderPeriod) {
                wanderCounter = 0;
                prngSeed = prngSeed * 1664525u + 1013904223u;
                wanderTarget1 = ((float)(prngSeed & 0xFFFF) / 32768.0f) - 1.0f;
                prngSeed = prngSeed * 1664525u + 1013904223u;
                wanderTarget2 = ((float)(prngSeed & 0xFFFF) / 32768.0f) - 1.0f;
            }
            wanderVal1 += (wanderTarget1 - wanderVal1) * wanderSmooth;
            wanderVal2 += (wanderTarget2 - wanderVal2) * wanderSmooth;

            const float totalMod1 = spinVal1 * spinDepth + wanderVal1 * wanderDepth;
            const float totalMod2 = spinVal2 * spinDepth + wanderVal2 * wanderDepth;

            // 3. Cross-Coupled Figure-8 Tank Loop Processing
            const float t1_in = dInL + t2_last_out * currentDecayGain_;
            const float t2_in = dInR + t1_last_out * currentDecayGain_;

            // === TANK 1 LOOP ===
            // Modulated Allpass 1 with alternating sign: H(z) = (g + z^-D)/(1 + g z^-D)
            const int t1Ap1Size = (int)t1_ap1_buf.size();
            const float t1_ap1_del_out = readCubic(t1_ap1_buf, t1_ap1_idx, (float)t1_ap1_len + totalMod1);
            float t1_ap1_out = 0.70f * t1_in + t1_ap1_del_out;
            flush_denormal(t1_ap1_out);
            float t1_ap1_next = t1_in - 0.70f * t1_ap1_out;
            flush_denormal(t1_ap1_next);
            t1_ap1_buf[t1_ap1_idx] = t1_ap1_next;
            t1_ap1_idx = (t1_ap1_idx + 1 < t1Ap1Size) ? t1_ap1_idx + 1 : 0;

            const float t1_del1_out = t1_del1_buf[t1_del1_idx];
            t1_del1_buf[t1_del1_idx] = t1_ap1_out;
            t1_del1_idx = (t1_del1_idx + 1 < t1_del1_len) ? t1_del1_idx + 1 : 0;

            t1_damp_state += currentDampCoeff_ * (t1_del1_out - t1_damp_state);
            flush_denormal(t1_damp_state);
            t1_hpf_state += loopHpfCoeff_ * (t1_damp_state - t1_hpf_state);
            flush_denormal(t1_hpf_state);
            const float t1_filt = t1_damp_state - t1_hpf_state;

            const float t1_ap2_buf_out = t1_ap2_buf[t1_ap2_idx];
            float t1_ap2_out = -0.5f * t1_filt + t1_ap2_buf_out;
            flush_denormal(t1_ap2_out);
            float t1_ap2_next = t1_filt + 0.5f * t1_ap2_out;
            flush_denormal(t1_ap2_next);
            t1_ap2_buf[t1_ap2_idx] = t1_ap2_next;
            t1_ap2_idx = (t1_ap2_idx + 1 < t1_ap2_len) ? t1_ap2_idx + 1 : 0;

            t1_last_out = t1_del2_buf[t1_del2_idx];
            t1_del2_buf[t1_del2_idx] = t1_ap2_out;
            t1_del2_idx = (t1_del2_idx + 1 < t1_del2_len) ? t1_del2_idx + 1 : 0;

            // === TANK 2 LOOP ===
            const int t2Ap1Size = (int)t2_ap1_buf.size();
            const float t2_ap1_del_out = readCubic(t2_ap1_buf, t2_ap1_idx, (float)t2_ap1_len + totalMod2);
            float t2_ap1_out = 0.70f * t2_in + t2_ap1_del_out;
            flush_denormal(t2_ap1_out);
            float t2_ap1_next = t2_in - 0.70f * t2_ap1_out;
            flush_denormal(t2_ap1_next);
            t2_ap1_buf[t2_ap1_idx] = t2_ap1_next;
            t2_ap1_idx = (t2_ap1_idx + 1 < t2Ap1Size) ? t2_ap1_idx + 1 : 0;

            const float t2_del1_out = t2_del1_buf[t2_del1_idx];
            t2_del1_buf[t2_del1_idx] = t2_ap1_out;
            t2_del1_idx = (t2_del1_idx + 1 < t2_del1_len) ? t2_del1_idx + 1 : 0;

            t2_damp_state += currentDampCoeff_ * (t2_del1_out - t2_damp_state);
            flush_denormal(t2_damp_state);
            t2_hpf_state += loopHpfCoeff_ * (t2_damp_state - t2_hpf_state);
            flush_denormal(t2_hpf_state);
            const float t2_filt = t2_damp_state - t2_hpf_state;

            const float t2_ap2_buf_out = t2_ap2_buf[t2_ap2_idx];
            float t2_ap2_out = -0.5f * t2_filt + t2_ap2_buf_out;
            flush_denormal(t2_ap2_out);
            float t2_ap2_next = t2_filt + 0.5f * t2_ap2_out;
            flush_denormal(t2_ap2_next);
            t2_ap2_buf[t2_ap2_idx] = t2_ap2_next;
            t2_ap2_idx = (t2_ap2_idx + 1 < t2_ap2_len) ? t2_ap2_idx + 1 : 0;

            t2_last_out = t2_del2_buf[t2_del2_idx];
            t2_del2_buf[t2_del2_idx] = t2_ap2_out;
            t2_del2_idx = (t2_del2_idx + 1 < t2_del2_len) ? t2_del2_idx + 1 : 0;

            // 4. 12-Tap In-Bounds Output Matrix Extraction
            const float wetL = (
                  readTap(t1_del1_buf, t1_del1_idx, tapT1D1[0], t1_del1_len)
                + readTap(t1_del1_buf, t1_del1_idx, tapT1D1[1], t1_del1_len)
                - readTap(t1_del2_buf, t1_del2_idx, tapT1D2[0], t1_del2_len)
                + readTap(t2_del1_buf, t2_del1_idx, tapT2D1[0], t2_del1_len)
                - readTap(t2_del2_buf, t2_del2_idx, tapT2D2[1], t2_del2_len)
                - readTap(t2_del2_buf, t2_del2_idx, tapT2D2[2], t2_del2_len)) * 0.28f;

            const float wetR = (
                  readTap(t2_del1_buf, t2_del1_idx, tapT2D1[1], t2_del1_len)
                + readTap(t2_del1_buf, t2_del1_idx, tapT2D1[2], t2_del1_len)
                - readTap(t2_del2_buf, t2_del2_idx, tapT2D2[0], t2_del2_len)
                + readTap(t1_del1_buf, t1_del1_idx, tapT1D1[2], t1_del1_len)
                - readTap(t1_del2_buf, t1_del2_idx, tapT1D2[1], t1_del2_len)
                - readTap(t1_del2_buf, t1_del2_idx, tapT1D2[2], t1_del2_len)) * 0.28f;

            // 5. True Stereo Width M/S Balance
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
        // Mean half-tank delay @ 29.761 kHz = 12683 / 29761 = 0.42616s
        const float targetRT60 = 0.35f * std::pow(40.0f, targetRoomSize);
        targetDecayGain_ = std::min(0.985f, std::pow(10.0f, -3.0f * 0.42616f / targetRT60));

        if (targetDamping <= 0.0001f) {
            targetDampCoeff_ = 1.0f;
        } else {
            const float dampHz = 18000.0f * std::pow(0.0667f, targetDamping);
            const float w = std::min(3.0f, twoPi * dampHz / (float)sampleRate);
            targetDampCoeff_ = 1.0f - std::exp(-w);
        }

        inHpfCoeff_ = 1.0f - std::exp(-std::min(3.0f, twoPi * 70.0f / (float)sampleRate));
        loopHpfCoeff_ = 1.0f - std::exp(-std::min(3.0f, twoPi * 50.0f / (float)sampleRate));
    }

    double sampleRate = 48000.0;
    bool buffersAllocated = false;

    std::vector<float> diffBufL[NUM_DIFFUSERS];
    std::vector<float> diffBufR[NUM_DIFFUSERS];
    int diffIdxL[NUM_DIFFUSERS] = {0};
    int diffIdxR[NUM_DIFFUSERS] = {0};

    std::vector<float> t1_ap1_buf, t1_del1_buf, t1_ap2_buf, t1_del2_buf;
    int t1_ap1_len = 0, t1_del1_len = 0, t1_ap2_len = 0, t1_del2_len = 0;
    int t1_ap1_idx = 0, t1_del1_idx = 0, t1_ap2_idx = 0, t1_del2_idx = 0;

    std::vector<float> t2_ap1_buf, t2_del1_buf, t2_ap2_buf, t2_del2_buf;
    int t2_ap1_len = 0, t2_del1_len = 0, t2_ap2_len = 0, t2_del2_len = 0;
    int t2_ap1_idx = 0, t2_del1_idx = 0, t2_ap2_idx = 0, t2_del2_idx = 0;

    float inHpfStateL = 0.0f, inHpfStateR = 0.0f;
    float t1_damp_state = 0.0f, t2_damp_state = 0.0f;
    float t1_hpf_state = 0.0f, t2_hpf_state = 0.0f;
    float t1_last_out = 0.0f, t2_last_out = 0.0f;

    int tapT1D1[3] = {0};
    int tapT1D2[3] = {0};
    int tapT2D1[3] = {0};
    int tapT2D2[3] = {0};

    float spinPhase1 = 0.0f;
    float spinPhase2 = 1.57079632679f;
    float wanderVal1 = 0.0f, wanderVal2 = 0.0f;
    float wanderTarget1 = 0.0f, wanderTarget2 = 0.0f;
    int wanderCounter = 0;
    uint32_t prngSeed = 123456789u;

    float targetDecayGain_ = 0.75f;
    float currentDecayGain_ = 0.75f;
    float targetDampCoeff_ = 0.55f;
    float currentDampCoeff_ = 0.55f;
    float inHpfCoeff_ = 0.01f;
    float loopHpfCoeff_ = 0.006f;

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
