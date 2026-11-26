#pragma once

/**
 * @file diffusion_reverb_dsp.h
 * @brief Clean-room Multi-Stage Givens-Hadamard Diffusion Network Reverberator DSP.
 *
 * Implements an authentic multi-stage orthonormal diffusion reverberator:
 * - 70 Hz matched-Z input HPF + 4-channel orthogonal stereo expansion
 * - 4 cascaded 4-channel prime-delay Givens-Hadamard diffusion stages
 *   (orthonormal M(theta) morphing smoothly with Diffusion 0..1)
 * - 4-channel room-size-scaled modulated Hadamard feedback loop with
 *   4-point Catmull-Rom cubic interpolation
 * - Independent Room Size (physical delay scaling) and Decay Time (RT60)
 * - Jot (1991) delay-proportional sample-rate-invariant damping + 50 Hz DC blocker
 * - Full F32/F64 precision without audio-thread allocations or per-sample pow/exp
 */

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <vector>
#include "denormals.h"

namespace sauti::dsp {

class DiffusionReverbDSP {
public:
    static constexpr int NUM_CHANNELS = 4;
    static constexpr int NUM_DIFF_STAGES = 4;

    // 4 cascaded prime-delay diffusion stages tuned for 48 kHz
    static constexpr int BASE_DIFF_DELAYS[NUM_DIFF_STAGES][NUM_CHANNELS] = {
        {  149,  211,  283,  359 },
        {  431,  521,  613,  709 },
        {  811,  929, 1061, 1193 },
        { 1307, 1453, 1609, 1777 }
    };

    static constexpr float DIFF_SIGNS[NUM_DIFF_STAGES][NUM_CHANNELS] = {
        {  1.0f, -1.0f,  1.0f, -1.0f },
        {  1.0f,  1.0f, -1.0f, -1.0f },
        { -1.0f,  1.0f,  1.0f, -1.0f },
        {  1.0f, -1.0f, -1.0f,  1.0f }
    };

    // Modulated Hadamard feedback loop base delays (48 kHz, mutually prime)
    static constexpr int BASE_LOOP_DELAYS[NUM_CHANNELS] = {
        1613, 2129, 2719, 3463
    };

    static constexpr float LOOP_LFO_RATES[NUM_CHANNELS] = {
        0.43f, 0.59f, 0.73f, 0.89f
    };

    DiffusionReverbDSP() {
        setSampleRate(48000.0);
        reset();
    }

    void setSampleRate(double rate) {
        if (rate <= 0.0) rate = 48000.0;
        if (std::abs(sampleRate - rate) < 0.1 && buffersAllocated) return;

        sampleRate = rate;
        double scale = sampleRate / 48000.0;
        if (scale < 0.25) scale = 0.25;

        for (int s = 0; s < NUM_DIFF_STAGES; ++s) {
            for (int c = 0; c < NUM_CHANNELS; ++c) {
                int len = std::max(8, (int)std::lround((double)BASE_DIFF_DELAYS[s][c] * scale));
                diffBuf[s][c].assign(len, 0.0f);
                diffIdx[s][c] = 0;
            }
        }

        const int modHeadroom = (int)std::ceil(4.0 * scale) + 12;
        for (int c = 0; c < NUM_CHANNELS; ++c) {
            baseLoopLen[c] = std::max(32, (int)std::lround((double)BASE_LOOP_DELAYS[c] * scale));
            const int allocSize = (int)std::ceil((double)baseLoopLen[c] * 1.40) + modHeadroom;
            loopBuf[c].assign(allocSize, 0.0f);
            loopIdx[c] = 0;
            loopDampState[c] = 0.0f;
            loopHpfState[c] = 0.0f;
            lfoPhase[c] = (float)c * 1.57079632679f;
        }

        buffersAllocated = true;
        updateCoefficients();
        reset();
    }

    void setEnabled(bool e) { targetEnabled = e; }
    bool isEnabled() const { return targetEnabled; }

    void setWet(float w) { targetWet = std::clamp(w, 0.0f, 2.0f); }
    float getWet() const { return targetWet; }

    void setDry(float d) { targetDry = std::clamp(d, 0.0f, 2.0f); }
    float getDry() const { return targetDry; }

    void setRoomSize(float r) {
        targetRoomSize = std::clamp(r, 0.0f, 1.0f);
        updateCoefficients();
    }
    float getRoomSize() const { return targetRoomSize; }

    void setDecayTimeMs(float ms) {
        targetDecayTimeMs = std::clamp(ms, 100.0f, 15000.0f);
        updateCoefficients();
    }
    float getDecayTimeMs() const { return targetDecayTimeMs; }

    void setDiffusion(float diff) { targetDiffusion = std::clamp(diff, 0.0f, 1.0f); }
    float getDiffusion() const { return targetDiffusion; }

    void setDamping(float d) {
        targetDamping = std::clamp(d, 0.0f, 1.0f);
        updateCoefficients();
    }
    float getDamping() const { return targetDamping; }

    void setWidth(float w) { targetWidth = std::clamp(w, 0.0f, 2.0f); }
    float getWidth() const { return targetWidth; }

    void setParams(float wet, float dry, float roomSize, float decayTimeMs, float diffusion, float damping, float width = 1.0f) {
        targetWet = std::clamp(wet, 0.0f, 2.0f);
        targetDry = std::clamp(dry, 0.0f, 2.0f);
        targetRoomSize = std::clamp(roomSize, 0.0f, 1.0f);
        targetDecayTimeMs = std::clamp(decayTimeMs, 100.0f, 15000.0f);
        targetDiffusion = std::clamp(diffusion, 0.0f, 1.0f);
        targetDamping = std::clamp(damping, 0.0f, 1.0f);
        targetWidth = std::clamp(width, 0.0f, 2.0f);
        updateCoefficients();
    }

    void reset() {
        for (int s = 0; s < NUM_DIFF_STAGES; ++s) {
            for (int c = 0; c < NUM_CHANNELS; ++c) {
                std::fill(diffBuf[s][c].begin(), diffBuf[s][c].end(), 0.0f);
                diffIdx[s][c] = 0;
            }
        }
        for (int c = 0; c < NUM_CHANNELS; ++c) {
            std::fill(loopBuf[c].begin(), loopBuf[c].end(), 0.0f);
            loopIdx[c] = 0;
            loopDampState[c] = 0.0f;
            loopHpfState[c] = 0.0f;
            lfoPhase[c] = (float)c * 1.57079632679f;
            currentLoopDecay[c] = targetLoopDecay[c];
            currentDampCoeff[c] = targetDampCoeff[c];
        }

        inHpfStateL = 0.0f;
        inHpfStateR = 0.0f;

        currentWet = targetWet;
        currentDry = targetDry;
        currentRoomSize = targetRoomSize;
        currentDiffusion = targetDiffusion;
        currentWidth = targetWidth;
        currentEnabled = targetEnabled;
    }

    void process(float* interleaved, uint32_t frames, int channels) {
        processImpl(interleaved, frames, channels, true);
    }

    void process(double* interleaved, uint32_t frames, int channels) {
        processImpl(interleaved, frames, channels, true);
    }

    void processWetOnly(float* interleaved, uint32_t frames, int channels) {
        processImpl(interleaved, frames, channels, false);
    }

    void processWetOnly(double* interleaved, uint32_t frames, int channels) {
        processImpl(interleaved, frames, channels, false);
    }

private:
    void updateCoefficients() {
        if (!buffersAllocated || sampleRate <= 0.0) return;

        constexpr double pi = 3.14159265358979323846;
        constexpr double twoPi = 2.0 * pi;

        const float targetSizeScale = 0.45f + 0.90f * targetRoomSize;
        const float rt60Sec = std::max(0.1f, targetDecayTimeMs * 0.001f);
        const float hfRatio = 1.0f - targetDamping * 0.88f;
        const float rt60Hf = std::max(0.05f, rt60Sec * hfRatio);
        const double wRef = std::min(0.95 * pi, twoPi * 10000.0 / sampleRate);

        for (int c = 0; c < NUM_CHANNELS; ++c) {
            const float delaySec = ((float)baseLoopLen[c] * targetSizeScale) / (float)sampleRate;
            targetLoopDecay[c] = std::min(0.990f, std::pow(10.0f, -3.0f * delaySec / rt60Sec));

            if (targetDamping <= 0.0001f) {
                targetDampCoeff[c] = 1.0f;
            } else {
                const float alpha = std::clamp(
                    std::pow(10.0f, -3.0f * delaySec * (1.0f / rt60Hf - 1.0f / rt60Sec)),
                    0.05f, 0.9999f);
                const float a2 = std::min(0.9998f, alpha * alpha);
                const float B = (1.0f - a2 * std::cos((float)wRef)) / (1.0f - a2);
                const float pole = std::clamp(B - std::sqrt(std::max(0.0f, B * B - 1.0f)), 0.0f, 0.98f);
                targetDampCoeff[c] = 1.0f - pole;
            }
        }

        inHpfCoeff = 1.0f - std::exp(-std::min(3.0f, (float)(twoPi * 70.0 / sampleRate)));
        loopHpfCoeff = 1.0f - std::exp(-std::min(3.0f, (float)(twoPi * 50.0 / sampleRate)));
    }

    static float readLoopCubic(const std::vector<float>& buf, int writeIdx, float delaySamples) {
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
    void processImpl(T* interleaved, uint32_t frames, int channels, bool mixDry) {
        if (!interleaved || frames == 0 || channels < 2 || !buffersAllocated) return;

        if (!targetEnabled && currentWet < 0.0001f) {
            currentEnabled = false;
            return;
        }
        currentEnabled = true;

        ScopedDenormalsDisable ftz;

        const float smoothAlpha = 1.0f - std::exp(-1.0f / (0.015f * (float)sampleRate));
        constexpr float twoPi = 6.28318530717958647692f;
        constexpr float piOver4 = 0.78539816339744830962f;
        const float modDepth = 3.0f * (float)(sampleRate / 48000.0);

        float lfoInc[NUM_CHANNELS];
        for (int c = 0; c < NUM_CHANNELS; ++c) {
            lfoInc[c] = (twoPi * LOOP_LFO_RATES[c]) / (float)sampleRate;
        }

        float diffAngle = currentDiffusion * piOver4;
        float cosDiff = std::cos(diffAngle);
        float sinDiff = std::sin(diffAngle);

        for (uint32_t f = 0; f < frames; ++f) {
            currentWet += smoothAlpha * (targetWet - currentWet);
            currentDry += smoothAlpha * (targetDry - currentDry);
            currentRoomSize += smoothAlpha * (targetRoomSize - currentRoomSize);
            currentWidth += smoothAlpha * (targetWidth - currentWidth);

            // Update Givens rotation angle once per 32-sample sub-block when moving
            if ((f & 31u) == 0u && std::abs(targetDiffusion - currentDiffusion) > 1.0e-5f) {
                const float subAlpha = 1.0f - std::pow(1.0f - smoothAlpha, 32.0f);
                currentDiffusion += subAlpha * (targetDiffusion - currentDiffusion);
                diffAngle = currentDiffusion * piOver4;
                cosDiff = std::cos(diffAngle);
                sinDiff = std::sin(diffAngle);
            } else if ((f & 31u) == 0u) {
                currentDiffusion = targetDiffusion;
            }

            for (int c = 0; c < NUM_CHANNELS; ++c) {
                currentLoopDecay[c] += smoothAlpha * (targetLoopDecay[c] - currentLoopDecay[c]);
                currentDampCoeff[c] += smoothAlpha * (targetDampCoeff[c] - currentDampCoeff[c]);
            }

            const size_t base = (size_t)f * (size_t)channels;
            const double rawInL = static_cast<double>(interleaved[base]);
            const double rawInR = static_cast<double>(interleaved[base + 1]);
            const float inL = static_cast<float>(rawInL);
            const float inR = static_cast<float>(rawInR);

            // 1. 70 Hz matched-Z input HPF + 4-channel orthogonal stereo expansion
            inHpfStateL += inHpfCoeff * (inL - inHpfStateL);
            inHpfStateR += inHpfCoeff * (inR - inHpfStateR);
            flush_denormal(inHpfStateL);
            flush_denormal(inHpfStateR);
            const float hpL = inL - inHpfStateL;
            const float hpR = inR - inHpfStateR;

            float vec[NUM_CHANNELS] = {
                hpL * 0.5f,
                hpR * 0.5f,
                (hpL + hpR) * 0.35355339f,
                (hpL - hpR) * 0.35355339f
            };

            // 2. 4 Cascaded Orthonormal Givens-Hadamard Pre-Diffusion Stages
            for (int s = 0; s < NUM_DIFF_STAGES; ++s) {
                float d[NUM_CHANNELS];
                for (int c = 0; c < NUM_CHANNELS; ++c) {
                    const int sz = (int)diffBuf[s][c].size();
                    const int idx = diffIdx[s][c];
                    d[c] = diffBuf[s][c][idx] * DIFF_SIGNS[s][c];
                    float wVal = vec[c];
                    flush_denormal(wVal);
                    diffBuf[s][c][idx] = wVal;
                    diffIdx[s][c] = (idx + 1 < sz) ? idx + 1 : 0;
                }

                // Exact orthonormal 2-stage Givens-Hadamard scatter M(theta)
                const float t0 = cosDiff * d[0] - sinDiff * d[1];
                const float t1 = sinDiff * d[0] + cosDiff * d[1];
                const float t2 = cosDiff * d[2] - sinDiff * d[3];
                const float t3 = sinDiff * d[2] + cosDiff * d[3];

                vec[0] = cosDiff * t0 - sinDiff * t2;
                vec[2] = sinDiff * t0 + cosDiff * t2;
                vec[1] = cosDiff * t1 - sinDiff * t3;
                vec[3] = sinDiff * t1 + cosDiff * t3;
            }

            // 3. 4-Channel Room-Size-Scaled Modulated Hadamard Feedback Loop
            const float sizeScale = 0.45f + 0.90f * currentRoomSize;
            float loopOut[NUM_CHANNELS];

            for (int c = 0; c < NUM_CHANNELS; ++c) {
                const float lfoVal = std::sin(lfoPhase[c]);
                lfoPhase[c] += lfoInc[c];
                if (lfoPhase[c] >= twoPi) lfoPhase[c] -= twoPi;

                const float delaySamples = (float)baseLoopLen[c] * sizeScale + lfoVal * modDepth;
                const float delSample = readLoopCubic(loopBuf[c], loopIdx[c], delaySamples);

                // Jot delay-proportional lowpass + 50 Hz loop DC blocker
                loopDampState[c] += currentDampCoeff[c] * (delSample - loopDampState[c]);
                flush_denormal(loopDampState[c]);
                loopHpfState[c] += loopHpfCoeff * (loopDampState[c] - loopHpfState[c]);
                flush_denormal(loopHpfState[c]);
                const float conditioned = loopDampState[c] - loopHpfState[c];

                loopOut[c] = conditioned * currentLoopDecay[c];
            }

            // Orthonormal 4x4 FWHT (0.5 * H_4)
            const float s01 = loopOut[0] + loopOut[1];
            const float d01 = loopOut[0] - loopOut[1];
            const float s23 = loopOut[2] + loopOut[3];
            const float d23 = loopOut[2] - loopOut[3];

            const float fwht[NUM_CHANNELS] = {
                (s01 + s23) * 0.5f,
                (d01 + d23) * 0.5f,
                (s01 - s23) * 0.5f,
                (d01 - d23) * 0.5f
            };

            for (int c = 0; c < NUM_CHANNELS; ++c) {
                const int sz = (int)loopBuf[c].size();
                float writeVal = vec[c] + fwht[c];
                flush_denormal(writeVal);
                loopBuf[c][loopIdx[c]] = writeVal;
                loopIdx[c] = (loopIdx[c] + 1 < sz) ? loopIdx[c] + 1 : 0;
            }

            // 4. Steady-State RMS-Normalized Stereo Extraction
            const float avgG = 0.25f * (currentLoopDecay[0] + currentLoopDecay[1] + currentLoopDecay[2] + currentLoopDecay[3]);
            const float wetNorm = 0.42f * std::sqrt(std::max(0.08f, 1.0f - 0.78f * avgG * avgG));
            float wetL = (loopOut[0] + loopOut[2] + 0.25f * vec[0]) * wetNorm;
            float wetR = (loopOut[1] - loopOut[3] + 0.25f * vec[1]) * wetNorm;

            // 5. Mid/Side Stereo Width Balance
            if (std::abs(currentWidth - 1.0f) > 0.001f) {
                const float mid = 0.5f * (wetL + wetR);
                const float side = 0.5f * (wetL - wetR) * currentWidth;
                wetL = mid + side;
                wetR = mid - side;
            }

            if (mixDry) {
                interleaved[base]     = static_cast<T>(rawInL * static_cast<double>(currentDry) + static_cast<double>(wetL) * static_cast<double>(currentWet));
                interleaved[base + 1] = static_cast<T>(rawInR * static_cast<double>(currentDry) + static_cast<double>(wetR) * static_cast<double>(currentWet));
            } else {
                interleaved[base]     = static_cast<T>(static_cast<double>(wetL) * static_cast<double>(currentWet));
                interleaved[base + 1] = static_cast<T>(static_cast<double>(wetR) * static_cast<double>(currentWet));
            }
        }
    }

    double sampleRate = 48000.0;
    bool buffersAllocated = false;

    bool targetEnabled = false;
    bool currentEnabled = false;

    float targetWet = 0.35f;
    float currentWet = 0.35f;

    float targetDry = 0.70f;
    float currentDry = 0.70f;

    float targetRoomSize = 0.70f;
    float currentRoomSize = 0.70f;

    float targetDecayTimeMs = 1500.0f;

    float targetDiffusion = 0.65f;
    float currentDiffusion = 0.65f;

    float targetDamping = 0.25f;
    float targetWidth = 1.0f;
    float currentWidth = 1.0f;

    std::vector<float> diffBuf[NUM_DIFF_STAGES][NUM_CHANNELS];
    int diffIdx[NUM_DIFF_STAGES][NUM_CHANNELS] = {{0}};

    std::vector<float> loopBuf[NUM_CHANNELS];
    int baseLoopLen[NUM_CHANNELS] = {0};
    int loopIdx[NUM_CHANNELS] = {0};
    float loopDampState[NUM_CHANNELS] = {0.0f};
    float loopHpfState[NUM_CHANNELS] = {0.0f};
    float lfoPhase[NUM_CHANNELS] = {0.0f};

    float targetLoopDecay[NUM_CHANNELS] = {0.85f, 0.85f, 0.85f, 0.85f};
    float currentLoopDecay[NUM_CHANNELS] = {0.85f, 0.85f, 0.85f, 0.85f};
    float targetDampCoeff[NUM_CHANNELS] = {0.65f, 0.65f, 0.65f, 0.65f};
    float currentDampCoeff[NUM_CHANNELS] = {0.65f, 0.65f, 0.65f, 0.65f};

    float inHpfStateL = 0.0f;
    float inHpfStateR = 0.0f;
    float inHpfCoeff = 0.01f;
    float loopHpfCoeff = 0.005f;
};

} // namespace sauti::dsp
