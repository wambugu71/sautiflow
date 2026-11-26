#pragma once

/**
 * @file hadamard_fdn_dsp.h
 * @brief Clean-room 8-Channel Orthonormal Hadamard Feedback Delay Network (FDN) Reverb.
 *
 * Mathematical Foundations & Attribution:
 * - Jean-Marc Jot & Antoine Chaigne (1991): "Digital delay networks for designing artificial reverberators",
 *   90th Audio Engineering Society (AES) Convention.
 * - Davide Rocchesso & Julius O. Smith (1997): "Circulant and elliptic feedback delay networks for artificial
 *   reverberation", IEEE Transactions on Speech and Audio Processing.
 * - Sebastian J. Schlecht & Emanuel A. P. Habets (2017): "Feedback Delay Networks - A Comprehensive Review".
 *
 * Architecture:
 * 1. 70 Hz matched-Z input HPF + 2-stage stereo allpass pre-diffuser (smears early transients).
 * 2. 8 mutually-prime delay lines (L_0 .. L_7) with 4-point Catmull-Rom cubic modulation.
 * 3. Orthonormal Normalized Hadamard Feedback Matrix (1/sqrt(8) * H_8) via 3-stage FWHT-8.
 * 4. Jot (1991) delay-proportional sample-rate-invariant per-channel damping + 40 Hz loop DC blocker.
 * 5. Non-eigenvector balanced stereo injection and strictly orthogonal balanced output extraction
 *    (eliminates Walsh eigenvector collapse & low-frequency stereo imbalance).
 * 6. Zero heap allocations in the audio path, full F32/F64 precision, smoothed coefficients.
 */

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <vector>
#include "denormals.h"

namespace sauti::dsp {

class HadamardFdnDSP {
public:
    static constexpr int NUM_CHANNELS = 8;
    static constexpr int NUM_IN_DIFF = 2;
    static constexpr float SQRT_8_INV = 0.3535533905932737622f; // 1 / sqrt(8)

    // 2-stage stereo input allpass diffuser lengths @ 48 kHz
    static constexpr int BASE_IN_DIFF_L[NUM_IN_DIFF] = { 131, 227 };
    static constexpr int BASE_IN_DIFF_R[NUM_IN_DIFF] = { 157, 251 };

    // Base delay lengths tuned for 48 kHz (all mutually prime, spanning 27 ms to 75 ms)
    static constexpr int BASE_DELAYS[NUM_CHANNELS] = {
        1321, 1579, 1873, 2179, 2503, 2851, 3167, 3571
    };

    // Modulation rates (Hz) - mutually incommensurate prime frequencies
    static constexpr float MOD_RATES[NUM_CHANNELS] = {
        0.41f, 0.53f, 0.67f, 0.79f, 0.97f, 1.13f, 1.31f, 1.49f
    };

    HadamardFdnDSP() {
        setSampleRate(48000.0);
        reset();
    }

    void setSampleRate(double rate) {
        if (rate <= 0.0) rate = 48000.0;
        if (std::abs(sampleRate - rate) < 0.1 && buffersAllocated) return;

        sampleRate = rate;
        double scale = sampleRate / 48000.0;
        if (scale < 0.25) scale = 0.25;

        for (int i = 0; i < NUM_IN_DIFF; ++i) {
            int lenL = std::max(8, (int)std::lround((double)BASE_IN_DIFF_L[i] * scale));
            int lenR = std::max(8, (int)std::lround((double)BASE_IN_DIFF_R[i] * scale));
            inDiffBufL[i].assign(lenL, 0.0f);
            inDiffBufR[i].assign(lenR, 0.0f);
            inDiffIdxL[i] = 0;
            inDiffIdxR[i] = 0;
        }

        const int modHeadroom = (int)std::ceil(3.0 * scale) + 12;
        for (int i = 0; i < NUM_CHANNELS; ++i) {
            delayLengths[i] = std::max(32, (int)std::lround((double)BASE_DELAYS[i] * scale));
            int allocSize = delayLengths[i] + modHeadroom;
            delayBuffers[i].assign(allocSize, 0.0f);
            writeIndices[i] = 0;
            dampState[i] = 0.0f;
            loopHpfState[i] = 0.0f;
            lfoPhase[i] = (float)i * 0.785398163f; // 45 degree phase offset per channel
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
        for (int i = 0; i < NUM_IN_DIFF; ++i) {
            std::fill(inDiffBufL[i].begin(), inDiffBufL[i].end(), 0.0f);
            std::fill(inDiffBufR[i].begin(), inDiffBufR[i].end(), 0.0f);
            inDiffIdxL[i] = 0;
            inDiffIdxR[i] = 0;
        }
        for (int i = 0; i < NUM_CHANNELS; ++i) {
            std::fill(delayBuffers[i].begin(), delayBuffers[i].end(), 0.0f);
            writeIndices[i] = 0;
            dampState[i] = 0.0f;
            loopHpfState[i] = 0.0f;
            lfoPhase[i] = (float)i * 0.785398163f;
            currentDecayGain[i] = targetDecayGain[i];
            currentDampCoeff[i] = targetDampCoeff[i];
        }

        inHpfStateL = 0.0f;
        inHpfStateR = 0.0f;

        currentWet = targetWet;
        currentDry = targetDry;
        currentWidth = targetWidth;
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
        const float modDepthSamples = 2.5f * (float)(sampleRate / 48000.0);

        float lfoInc[NUM_CHANNELS];
        for (int i = 0; i < NUM_CHANNELS; ++i) {
            lfoInc[i] = (twoPi * MOD_RATES[i]) / (float)sampleRate;
        }

        float chDelayOut[NUM_CHANNELS];
        float fwhtStage1[NUM_CHANNELS];
        float fwhtStage2[NUM_CHANNELS];
        float matrixOut[NUM_CHANNELS];

        for (uint32_t f = 0; f < frames; ++f) {
            currentWet += (targetWet - currentWet) * smoothCoeff;
            currentDry += (targetDry - currentDry) * smoothCoeff;
            currentWidth += (targetWidth - currentWidth) * smoothCoeff;
            for (int i = 0; i < NUM_CHANNELS; ++i) {
                currentDecayGain[i] += (targetDecayGain[i] - currentDecayGain[i]) * smoothCoeff;
                currentDampCoeff[i] += (targetDampCoeff[i] - currentDampCoeff[i]) * smoothCoeff;
            }

            const size_t idx = (size_t)f * (size_t)channels;
            const double rawInL = static_cast<double>(interleaved[idx]);
            const double rawInR = static_cast<double>(interleaved[idx + 1]);
            const float inL = static_cast<float>(rawInL);
            const float inR = static_cast<float>(rawInR);

            // 0. 70 Hz input HPF + 2-stage stereo allpass pre-diffuser (g = 0.625)
            inHpfStateL += inHpfCoeff * (inL - inHpfStateL);
            inHpfStateR += inHpfCoeff * (inR - inHpfStateR);
            flush_denormal(inHpfStateL);
            flush_denormal(inHpfStateR);
            float diffL = inL - inHpfStateL;
            float diffR = inR - inHpfStateR;

            for (int d = 0; d < NUM_IN_DIFF; ++d) {
                const int szL = (int)inDiffBufL[d].size();
                const float bufL = inDiffBufL[d][inDiffIdxL[d]];
                const float yL = -0.625f * diffL + bufL;
                float nextL = diffL + 0.625f * yL;
                flush_denormal(nextL);
                inDiffBufL[d][inDiffIdxL[d]] = nextL;
                inDiffIdxL[d] = (inDiffIdxL[d] + 1 < szL) ? inDiffIdxL[d] + 1 : 0;
                diffL = yL;

                const int szR = (int)inDiffBufR[d].size();
                const float bufR = inDiffBufR[d][inDiffIdxR[d]];
                const float yR = -0.625f * diffR + bufR;
                float nextR = diffR + 0.625f * yR;
                flush_denormal(nextR);
                inDiffBufR[d][inDiffIdxR[d]] = nextR;
                inDiffIdxR[d] = (inDiffIdxR[d] + 1 < szR) ? inDiffIdxR[d] + 1 : 0;
                diffR = yR;
            }

            // 1. Read delay outputs with 4-point Catmull-Rom cubic modulation
            for (int i = 0; i < NUM_CHANNELS; ++i) {
                const float lfoVal = std::sin(lfoPhase[i]);
                lfoPhase[i] += lfoInc[i];
                if (lfoPhase[i] >= twoPi) lfoPhase[i] -= twoPi;

                const float modDelay = (float)delayLengths[i] + lfoVal * modDepthSamples;
                const float delayedSample = readCubic(delayBuffers[i], writeIndices[i], modDelay);

                // Jot delay-proportional 1-pole damping + 40 Hz loop DC blocker
                dampState[i] += currentDampCoeff[i] * (delayedSample - dampState[i]);
                flush_denormal(dampState[i]);
                loopHpfState[i] += loopHpfCoeff * (dampState[i] - loopHpfState[i]);
                flush_denormal(loopHpfState[i]);
                const float conditioned = dampState[i] - loopHpfState[i];

                // Apply per-channel RT60 loop decay attenuation
                chDelayOut[i] = conditioned * currentDecayGain[i];
            }

            // 2. 8-Channel Fast Walsh-Hadamard Transform (FWHT-8)
            fwhtStage1[0] = chDelayOut[0] + chDelayOut[1];
            fwhtStage1[1] = chDelayOut[0] - chDelayOut[1];
            fwhtStage1[2] = chDelayOut[2] + chDelayOut[3];
            fwhtStage1[3] = chDelayOut[2] - chDelayOut[3];
            fwhtStage1[4] = chDelayOut[4] + chDelayOut[5];
            fwhtStage1[5] = chDelayOut[4] - chDelayOut[5];
            fwhtStage1[6] = chDelayOut[6] + chDelayOut[7];
            fwhtStage1[7] = chDelayOut[6] - chDelayOut[7];

            fwhtStage2[0] = fwhtStage1[0] + fwhtStage1[2];
            fwhtStage2[1] = fwhtStage1[1] + fwhtStage1[3];
            fwhtStage2[2] = fwhtStage1[0] - fwhtStage1[2];
            fwhtStage2[3] = fwhtStage1[1] - fwhtStage1[3];
            fwhtStage2[4] = fwhtStage1[4] + fwhtStage1[6];
            fwhtStage2[5] = fwhtStage1[5] + fwhtStage1[7];
            fwhtStage2[6] = fwhtStage1[4] - fwhtStage1[6];
            fwhtStage2[7] = fwhtStage1[5] - fwhtStage1[7];

            matrixOut[0] = (fwhtStage2[0] + fwhtStage2[4]) * SQRT_8_INV;
            matrixOut[1] = (fwhtStage2[1] + fwhtStage2[5]) * SQRT_8_INV;
            matrixOut[2] = (fwhtStage2[2] + fwhtStage2[6]) * SQRT_8_INV;
            matrixOut[3] = (fwhtStage2[3] + fwhtStage2[7]) * SQRT_8_INV;
            matrixOut[4] = (fwhtStage2[0] - fwhtStage2[4]) * SQRT_8_INV;
            matrixOut[5] = (fwhtStage2[1] - fwhtStage2[5]) * SQRT_8_INV;
            matrixOut[6] = (fwhtStage2[2] - fwhtStage2[6]) * SQRT_8_INV;
            matrixOut[7] = (fwhtStage2[3] - fwhtStage2[7]) * SQRT_8_INV;

            // 3. Balanced non-Walsh stereo injection (no eigenvector collapse)
            //    pL = {+1, +1, +1, -1} on ch 0,2,4,6; pR = {+1, +1, -1, +1} on ch 1,3,5,7
            const float sL = (diffL + 0.20f * diffR) * 0.34f;
            const float sR = (diffR + 0.20f * diffL) * 0.34f;
            const float inVec[NUM_CHANNELS] = {
                 sL,  sR,
                 sL,  sR,
                 sL, -sR,
                -sL,  sR
            };

            for (int i = 0; i < NUM_CHANNELS; ++i) {
                const int sz = (int)delayBuffers[i].size();
                float writeVal = inVec[i] + matrixOut[i];
                flush_denormal(writeVal);
                delayBuffers[i][writeIndices[i]] = writeVal;
                writeIndices[i] = (writeIndices[i] + 1 < sz) ? writeIndices[i] + 1 : 0;
            }

            // 4. Strictly orthogonal, equal-gain balanced stereo output extraction
            //    c_L = [+1,+1,+1,-1,-1,-1,-1,+1], c_R = [+1,+1,-1,+1,+1,+1,-1,+1]
            //    c_L . c_R == 0; L-only -> (+2,+2); R-only -> (+2,+2); mono -> (+4,+4)
            const float wetL = ( chDelayOut[0] + chDelayOut[1] + chDelayOut[2] - chDelayOut[3]
                               - chDelayOut[4] - chDelayOut[5] - chDelayOut[6] + chDelayOut[7]) * 0.22f;
            const float wetR = ( chDelayOut[0] + chDelayOut[1] - chDelayOut[2] + chDelayOut[3]
                               + chDelayOut[4] + chDelayOut[5] - chDelayOut[6] + chDelayOut[7]) * 0.22f;

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
        if (!buffersAllocated || sampleRate <= 0.0) return;

        constexpr double pi = 3.14159265358979323846;
        constexpr double twoPi = 2.0 * pi;

        // Map roomSize (0..1) to RT60 decay time (0.35s .. 14.0s)
        const float rt60 = 0.35f * std::pow(40.0f, targetRoomSize);
        const float hfRatio = 1.0f - targetDamping * 0.88f;
        const float rt60Hf = std::max(0.05f, rt60 * hfRatio);
        const double wRef = std::min(0.95 * pi, twoPi * 10000.0 / sampleRate);

        for (int i = 0; i < NUM_CHANNELS; ++i) {
            const float delaySeconds = (float)delayLengths[i] / (float)sampleRate;
            // Jot & Chaigne exact attenuation: g = 10^(-3 * T / RT60)
            targetDecayGain[i] = std::min(0.995f, std::pow(10.0f, -3.0f * delaySeconds / rt60));

            if (targetDamping <= 0.0001f) {
                targetDampCoeff[i] = 1.0f;
            } else {
                const float alpha = std::clamp(
                    std::pow(10.0f, -3.0f * delaySeconds * (1.0f / rt60Hf - 1.0f / rt60)),
                    0.05f, 0.9999f);
                const float a2 = std::min(0.9998f, alpha * alpha);
                const float B = (1.0f - a2 * std::cos((float)wRef)) / (1.0f - a2);
                const float pole = std::clamp(B - std::sqrt(std::max(0.0f, B * B - 1.0f)), 0.0f, 0.98f);
                targetDampCoeff[i] = 1.0f - pole;
            }
        }

        inHpfCoeff = 1.0f - std::exp(-std::min(3.0f, (float)(twoPi * 70.0 / sampleRate)));
        loopHpfCoeff = 1.0f - std::exp(-std::min(3.0f, (float)(twoPi * 40.0 / sampleRate)));
    }

    double sampleRate = 48000.0;
    bool buffersAllocated = false;

    std::vector<float> inDiffBufL[NUM_IN_DIFF];
    std::vector<float> inDiffBufR[NUM_IN_DIFF];
    int inDiffIdxL[NUM_IN_DIFF] = {0};
    int inDiffIdxR[NUM_IN_DIFF] = {0};

    int delayLengths[NUM_CHANNELS] = {0};
    std::vector<float> delayBuffers[NUM_CHANNELS];
    int writeIndices[NUM_CHANNELS] = {0};
    float dampState[NUM_CHANNELS] = {0.0f};
    float loopHpfState[NUM_CHANNELS] = {0.0f};
    float lfoPhase[NUM_CHANNELS] = {0.0f};
    float targetDecayGain[NUM_CHANNELS] = {0.0f};
    float currentDecayGain[NUM_CHANNELS] = {0.0f};
    float targetDampCoeff[NUM_CHANNELS] = {0.0f};
    float currentDampCoeff[NUM_CHANNELS] = {0.0f};

    float inHpfStateL = 0.0f;
    float inHpfStateR = 0.0f;
    float inHpfCoeff = 0.01f;
    float loopHpfCoeff = 0.005f;

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
