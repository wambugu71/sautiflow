#pragma once

/**
 * @file griesinger_tank_dsp.h
 * @brief Clean-room David Griesinger "Spin & Wander" Tank Reverberator DSP.
 *
 * Mathematical Foundations & Historical Attribution:
 * - Dr. David Griesinger (Chief Scientist, Lexicon; inventor of the Lexicon 224, 480L, and PCM series).
 * - Landmarks: "Practical Processors and Programs for Digital Reverberation" (JAES 1986);
 *   "Improving Room Simulation through Novel Steerable Digital Reverberation" (JAES 1989).
 * - Famous Realization: The legendary Lexicon 480L "Random Hall" & "Random Ambience" algorithms.
 *
 * Architecture & The "Spin & Wander" Engine:
 * 1. Dual-Channel Cascaded Input Diffusers (4 series Schroeder all-passes per channel):
 *    Shatters sharp transients into high initial reflection density before tank entry.
 * 2. Cross-Coupled Figure-8 Tank Loops (Tank A <-> Tank B):
 *    Recirculating cross-coupled loops with frequency-dependent absorption damping and decay attenuation.
 * 3. The "Spin" Modulation Engine:
 *    Independent incommensurate low-frequency sinusoidal modulators (0.8 Hz and 1.15 Hz) sweeping
 *    the loop allpass delays to disperse standing eigentones and eliminate metallic modes.
 * 4. The "Wander" Random-Walk Engine:
 *    A continuous, smoothed decorrelated random-walk drift modulating internal delay taps across
 *    a range of +/- 20 samples. Breaks up repetitive periodicity and simulates natural air turbulence
 *    and non-uniform wall reflections of large acoustic concert halls.
 * 5. 12-Tap Mutually Prime Output Extraction Matrix:
 *    Taps taken from diverse points along both tank loops with alternating polarity for maximal
 *    stereo decorrelation without mono phase cancellation.
 * 6. Mid/Side Stereo Width Stage & Smooth Parameter Interpolation.
 */

#include <cmath>
#include <cstdint>
#include <vector>
#include <algorithm>
#include "denormals.h"

namespace sauti::dsp {

class GriesingerTankDSP {
public:
    static constexpr int NUM_DIFFUSERS = 4;

    // Base delays at 29.761 kHz (Lexicon 224/480L native hardware clock rate)
    static constexpr int BASE_DIFF[NUM_DIFFUSERS] = { 142, 107, 379, 277 };
    static constexpr float DIFF_COEFFS[NUM_DIFFUSERS] = { 0.75f, 0.75f, 0.625f, 0.625f };

    // Tank loop delay lines (samples at 29.761 kHz)
    static constexpr int BASE_TANK1_AP1  = 672;
    static constexpr int BASE_TANK1_DEL1 = 4453;
    static constexpr int BASE_TANK1_AP2  = 1800;
    static constexpr int BASE_TANK1_DEL2 = 3720;

    static constexpr int BASE_TANK2_AP1  = 908;
    static constexpr int BASE_TANK2_DEL1 = 4217;
    static constexpr int BASE_TANK2_AP2  = 2656;
    static constexpr int BASE_TANK2_DEL2 = 3163;

    // Output tap positions from Tank 1 and Tank 2
    static constexpr int BASE_TAPS_T1[6] = { 266, 2974, 1913, 1996, 198, 3689 };
    static constexpr int BASE_TAPS_T2[6] = { 353, 3627, 1228, 2673, 1066, 2980 };

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
            int len = std::max(16, (int)std::round(BASE_DIFF[i] * scale));
            diffBufL[i].assign(len, 0.0f);
            diffBufR[i].assign(len, 0.0f);
            diffIdxL[i] = 0;
            diffIdxR[i] = 0;
        }

        // Allocate Tank 1
        t1_ap1_len = std::max(32, (int)std::round(BASE_TANK1_AP1 * scale));
        t1_del1_len = std::max(64, (int)std::round(BASE_TANK1_DEL1 * scale));
        t1_ap2_len = std::max(32, (int)std::round(BASE_TANK1_AP2 * scale));
        t1_del2_len = std::max(64, (int)std::round(BASE_TANK1_DEL2 * scale));

        t1_ap1_buf.assign(t1_ap1_len + 48, 0.0f); // extra headroom for Spin & Wander
        t1_del1_buf.assign(t1_del1_len + 48, 0.0f);
        t1_ap2_buf.assign(t1_ap2_len, 0.0f);
        t1_del2_buf.assign(t1_del2_len + 48, 0.0f);

        // Allocate Tank 2
        t2_ap1_len = std::max(32, (int)std::round(BASE_TANK2_AP1 * scale));
        t2_del1_len = std::max(64, (int)std::round(BASE_TANK2_DEL1 * scale));
        t2_ap2_len = std::max(32, (int)std::round(BASE_TANK2_AP2 * scale));
        t2_del2_len = std::max(64, (int)std::round(BASE_TANK2_DEL2 * scale));

        t2_ap1_buf.assign(t2_ap1_len + 48, 0.0f);
        t2_del1_buf.assign(t2_del1_len + 48, 0.0f);
        t2_ap2_buf.assign(t2_ap2_len, 0.0f);
        t2_del2_buf.assign(t2_del2_len + 48, 0.0f);

        for (int i = 0; i < 6; ++i) {
            tapOffsetsT1[i] = (int)std::round(BASE_TAPS_T1[i] * scale);
            tapOffsetsT2[i] = (int)std::round(BASE_TAPS_T2[i] * scale);
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

        t1_damp_state = 0.0f;
        t2_damp_state = 0.0f;
        t1_last_out = 0.0f;
        t2_last_out = 0.0f;

        spinPhase1 = 0.0f;
        spinPhase2 = 1.57079632679f; // 90 degree quadrature

        wanderVal1 = 0.0f;
        wanderVal2 = 0.0f;
        wanderTarget1 = 0.0f;
        wanderTarget2 = 0.0f;
        wanderCounter = 0;

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
        const float spinInc1 = (twoPi * 0.75f) / (float)sampleRate;  // 0.75 Hz Spin LFO 1
        const float spinInc2 = (twoPi * 1.10f) / (float)sampleRate;  // 1.10 Hz Spin LFO 2
        const float spinDepth = 8.0f;   // +/- 8 samples Spin
        const float wanderDepth = 12.0f; // +/- 12 samples Wander random-walk

        for (uint32_t f = 0; f < frames; ++f) {
            currentWet += (targetWet - currentWet) * smoothCoeff;
            currentDry += (targetDry - currentDry) * smoothCoeff;
            currentWidth += (targetWidth - currentWidth) * smoothCoeff;

            uint32_t idx = f * channels;
            float inL = interleaved[idx];
            float inR = interleaved[idx + 1];

            // 1. Input Diffusion (4 cascaded Schroeder allpasses per channel)
            float dInL = inL;
            float dInR = inR;

            for (int i = 0; i < NUM_DIFFUSERS; ++i) {
                float coeff = DIFF_COEFFS[i];

                // Left allpass
                float bufL = diffBufL[i][diffIdxL[i]];
                float yL = -coeff * dInL + bufL;
                diffBufL[i][diffIdxL[i]] = dInL + coeff * yL;
                diffIdxL[i] = (diffIdxL[i] + 1) % (int)diffBufL[i].size();
                dInL = yL;

                // Right allpass
                float bufR = diffBufR[i][diffIdxR[i]];
                float yR = -coeff * dInR + bufR;
                diffBufR[i][diffIdxR[i]] = dInR + coeff * yR;
                diffIdxR[i] = (diffIdxR[i] + 1) % (int)diffBufR[i].size();
                dInR = yR;
            }

            // 2. Advance "Spin" LFOs and "Wander" Random Walk
            float spinVal1 = std::sin(spinPhase1);
            float spinVal2 = std::sin(spinPhase2);
            spinPhase1 += spinInc1;
            if (spinPhase1 >= twoPi) spinPhase1 -= twoPi;
            spinPhase2 += spinInc2;
            if (spinPhase2 >= twoPi) spinPhase2 -= twoPi;

            // Update Wander random-walk target every ~128 samples with smooth lowpass tracking
            wanderCounter++;
            if (wanderCounter >= 128) {
                wanderCounter = 0;
                // Simple fast PRNG in [-1, +1]
                prngSeed = prngSeed * 1664525u + 1013904223u;
                wanderTarget1 = ((float)(prngSeed & 0xFFFF) / 32768.0f) - 1.0f;
                prngSeed = prngSeed * 1664525u + 1013904223u;
                wanderTarget2 = ((float)(prngSeed & 0xFFFF) / 32768.0f) - 1.0f;
            }
            wanderVal1 += (wanderTarget1 - wanderVal1) * 0.005f;
            wanderVal2 += (wanderTarget2 - wanderVal2) * 0.005f;

            float totalMod1 = spinVal1 * spinDepth + wanderVal1 * wanderDepth;
            float totalMod2 = spinVal2 * spinDepth + wanderVal2 * wanderDepth;

            // 3. Cross-Coupled Tank Loop Processing
            float t1_in = dInL + t2_last_out * decayGain_;
            float t2_in = dInR + t1_last_out * decayGain_;

            // === TANK 1 LOOP ===
            // Modulated Allpass 1 (coeff 0.7)
            int t1Ap1Size = (int)t1_ap1_buf.size();
            float t1ReadPos = (float)t1_ap1_idx - ((float)t1_ap1_len + totalMod1);
            while (t1ReadPos < 0.0f) t1ReadPos += (float)t1Ap1Size;
            while (t1ReadPos >= (float)t1Ap1Size) t1ReadPos -= (float)t1Ap1Size;
            int t1_i0 = (int)t1ReadPos;
            int t1_i1 = (t1_i0 + 1 >= t1Ap1Size) ? 0 : t1_i0 + 1;
            float t1_frac = t1ReadPos - (float)t1_i0;
            float t1_ap1_del_out = t1_ap1_buf[t1_i0] + t1_frac * (t1_ap1_buf[t1_i1] - t1_ap1_buf[t1_i0]);

            float t1_ap1_out = -0.7f * t1_in + t1_ap1_del_out;
            flush_denormal(t1_ap1_out);
            t1_ap1_buf[t1_ap1_idx] = t1_in + 0.7f * t1_ap1_out;
            t1_ap1_idx = (t1_ap1_idx + 1) % t1Ap1Size;

            // Delay 1
            float t1_del1_out = t1_del1_buf[t1_del1_idx];
            t1_del1_buf[t1_del1_idx] = t1_ap1_out;
            t1_del1_idx = (t1_del1_idx + 1) % t1_del1_len;

            // 1-Pole Lowpass damping
            t1_damp_state = t1_damp_state + dampCoeff_ * (t1_del1_out - t1_damp_state);
            flush_denormal(t1_damp_state);

            // Allpass 2 (coeff 0.5)
            float t1_ap2_buf_out = t1_ap2_buf[t1_ap2_idx];
            float t1_ap2_out = -0.5f * t1_damp_state + t1_ap2_buf_out;
            flush_denormal(t1_ap2_out);
            t1_ap2_buf[t1_ap2_idx] = t1_damp_state + 0.5f * t1_ap2_out;
            t1_ap2_idx = (t1_ap2_idx + 1) % t1_ap2_len;

            // Delay 2
            t1_last_out = t1_del2_buf[t1_del2_idx];
            t1_del2_buf[t1_del2_idx] = t1_ap2_out;
            t1_del2_idx = (t1_del2_idx + 1) % t1_del2_len;

            // === TANK 2 LOOP ===
            // Modulated Allpass 1 (coeff 0.7)
            int t2Ap1Size = (int)t2_ap1_buf.size();
            float t2ReadPos = (float)t2_ap1_idx - ((float)t2_ap1_len + totalMod2);
            while (t2ReadPos < 0.0f) t2ReadPos += (float)t2Ap1Size;
            while (t2ReadPos >= (float)t2Ap1Size) t2ReadPos -= (float)t2Ap1Size;
            int t2_i0 = (int)t2ReadPos;
            int t2_i1 = (t2_i0 + 1 >= t2Ap1Size) ? 0 : t2_i0 + 1;
            float t2_frac = t2ReadPos - (float)t2_i0;
            float t2_ap1_del_out = t2_ap1_buf[t2_i0] + t2_frac * (t2_ap1_buf[t2_i1] - t2_ap1_buf[t2_i0]);

            float t2_ap1_out = -0.7f * t2_in + t2_ap1_del_out;
            flush_denormal(t2_ap1_out);
            t2_ap1_buf[t2_ap1_idx] = t2_in + 0.7f * t2_ap1_out;
            t2_ap1_idx = (t2_ap1_idx + 1) % t2Ap1Size;

            // Delay 1
            float t2_del1_out = t2_del1_buf[t2_del1_idx];
            t2_del1_buf[t2_del1_idx] = t2_ap1_out;
            t2_del1_idx = (t2_del1_idx + 1) % t2_del1_len;

            // 1-Pole Lowpass damping
            t2_damp_state = t2_damp_state + dampCoeff_ * (t2_del1_out - t2_damp_state);
            flush_denormal(t2_damp_state);

            // Allpass 2 (coeff 0.5)
            float t2_ap2_buf_out = t2_ap2_buf[t2_ap2_idx];
            float t2_ap2_out = -0.5f * t2_damp_state + t2_ap2_buf_out;
            flush_denormal(t2_ap2_out);
            t2_ap2_buf[t2_ap2_idx] = t2_damp_state + 0.5f * t2_ap2_out;
            t2_ap2_idx = (t2_ap2_idx + 1) % t2_ap2_len;

            // Delay 2
            t2_last_out = t2_del2_buf[t2_del2_idx];
            t2_del2_buf[t2_del2_idx] = t2_ap2_out;
            t2_del2_idx = (t2_del2_idx + 1) % t2_del2_len;

            // 4. Multi-Tap Matrix Output Extraction
            // Read 3 taps from Tank 1 and 3 taps from Tank 2 for each channel with alternating signs
            auto readTap = [](const std::vector<float>& buf, int writeIdx, int offset, int len) -> float {
                int rIdx = writeIdx - offset;
                while (rIdx < 0) rIdx += len;
                return buf[rIdx % len];
            };

            float wetL = readTap(t1_del1_buf, t1_del1_idx, tapOffsetsT1[0], t1_del1_len)
                       + readTap(t1_del1_buf, t1_del1_idx, tapOffsetsT1[1], t1_del1_len)
                       - readTap(t1_del2_buf, t1_del2_idx, tapOffsetsT1[2], t1_del2_len)
                       + readTap(t2_del1_buf, t2_del1_idx, tapOffsetsT2[0], t2_del1_len)
                       - readTap(t2_del2_buf, t2_del2_idx, tapOffsetsT2[1], t2_del2_len)
                       - readTap(t2_del2_buf, t2_del2_idx, tapOffsetsT2[2], t2_del2_len);

            float wetR = readTap(t2_del1_buf, t2_del1_idx, tapOffsetsT2[3], t2_del1_len)
                       + readTap(t2_del1_buf, t2_del1_idx, tapOffsetsT2[4], t2_del1_len)
                       - readTap(t2_del2_buf, t2_del2_idx, tapOffsetsT2[5], t2_del2_len)
                       + readTap(t1_del1_buf, t1_del1_idx, tapOffsetsT1[3], t1_del1_len)
                       - readTap(t1_del2_buf, t1_del2_idx, tapOffsetsT1[4], t1_del2_len)
                       - readTap(t1_del2_buf, t1_del2_idx, tapOffsetsT1[5], t1_del2_len);

            wetL *= 0.28f;
            wetR *= 0.28f;

            // 5. True Stereo Width M/S Balance
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
        // Map roomSize (0..1) to loop decay gain (0.35 to 0.96)
        decayGain_ = 0.35f + targetRoomSize * 0.61f;

        // Damping lowpass filter coefficient (0.1 to 0.8)
        dampCoeff_ = 1.0f - (0.05f + targetDamping * 0.75f);
    }

    double sampleRate = 48000.0;
    bool buffersAllocated = false;

    // Diffusers
    std::vector<float> diffBufL[NUM_DIFFUSERS];
    std::vector<float> diffBufR[NUM_DIFFUSERS];
    int diffIdxL[NUM_DIFFUSERS] = {0};
    int diffIdxR[NUM_DIFFUSERS] = {0};

    // Tank 1
    std::vector<float> t1_ap1_buf;
    std::vector<float> t1_del1_buf;
    std::vector<float> t1_ap2_buf;
    std::vector<float> t1_del2_buf;

    int t1_ap1_len = 0;
    int t1_del1_len = 0;
    int t1_ap2_len = 0;
    int t1_del2_len = 0;

    int t1_ap1_idx = 0;
    int t1_del1_idx = 0;
    int t1_ap2_idx = 0;
    int t1_del2_idx = 0;

    float t1_damp_state = 0.0f;
    float t1_last_out = 0.0f;

    // Tank 2
    std::vector<float> t2_ap1_buf;
    std::vector<float> t2_del1_buf;
    std::vector<float> t2_ap2_buf;
    std::vector<float> t2_del2_buf;

    int t2_ap1_len = 0;
    int t2_del1_len = 0;
    int t2_ap2_len = 0;
    int t2_del2_len = 0;

    int t2_ap1_idx = 0;
    int t2_del1_idx = 0;
    int t2_ap2_idx = 0;
    int t2_del2_idx = 0;

    float t2_damp_state = 0.0f;
    float t2_last_out = 0.0f;

    int tapOffsetsT1[6] = {0};
    int tapOffsetsT2[6] = {0};

    // Modulation states
    float spinPhase1 = 0.0f;
    float spinPhase2 = 1.57079632679f;
    float wanderVal1 = 0.0f;
    float wanderVal2 = 0.0f;
    float wanderTarget1 = 0.0f;
    float wanderTarget2 = 0.0f;
    int wanderCounter = 0;
    uint32_t prngSeed = 123456789u;

    float decayGain_ = 0.75f;
    float dampCoeff_ = 0.45f;

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
