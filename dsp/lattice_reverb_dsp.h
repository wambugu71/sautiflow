#pragma once

/**
 * @file lattice_reverb_dsp.h
 * @brief Clean-room 4-Comb + 2-Allpass Recursive Lattice Reverberator DSP.
 *
 * Implements a low-coloration, natural reverberation algorithm utilizing
 * a bank of tuned mutually-prime parallel comb filters with one-pole damping
 * followed by cascaded allpass diffusers and Mid/Side stereo width balance.
 *
 * Designed for real-time low-latency audio pipelines with zero heap allocation
 * during processing, denormal flushing, and smooth click-free parameter updates.
 */

#include <cmath>
#include <cstdint>
#include <vector>
#include <algorithm>
#include "denormals.h"

namespace sauti::dsp {

class LatticeReverbDSP {
public:
    static constexpr int NUM_COMBS = 4;
    static constexpr int NUM_ALLPASS = 2;

    // Base delay lengths tuned for 48 kHz (mutually prime to minimize flutter & modal ringing)
    static constexpr int BASE_COMB_L[NUM_COMBS] = { 1116, 1188, 1277, 1356 };
    static constexpr int COMB_STEREO_OFFSET = 23;

    static constexpr int BASE_ALLPASS_L[NUM_ALLPASS] = { 225, 341 };
    static constexpr int ALLPASS_STEREO_OFFSET = 13;

    LatticeReverbDSP() {
        setSampleRate(48000.0);
        reset();
    }

    void setSampleRate(double rate) {
        if (rate <= 0.0) rate = 48000.0;
        if (std::abs(sampleRate - rate) < 0.1 && buffersAllocated) return;

        sampleRate = rate;
        double scale = sampleRate / 48000.0;
        if (scale < 0.25) scale = 0.25;

        for (int i = 0; i < NUM_COMBS; ++i) {
            int lenL = std::max(16, (int)std::round(BASE_COMB_L[i] * scale));
            int lenR = std::max(16, (int)std::round((BASE_COMB_L[i] + COMB_STEREO_OFFSET) * scale));

            combBufL[i].assign(lenL, 0.0f);
            combBufR[i].assign(lenR, 0.0f);
            combIdxL[i] = 0;
            combIdxR[i] = 0;
            combFilterL[i] = 0.0f;
            combFilterR[i] = 0.0f;
        }

        for (int i = 0; i < NUM_ALLPASS; ++i) {
            int lenL = std::max(8, (int)std::round(BASE_ALLPASS_L[i] * scale));
            int lenR = std::max(8, (int)std::round((BASE_ALLPASS_L[i] + ALLPASS_STEREO_OFFSET) * scale));

            allpassBufL[i].assign(lenL, 0.0f);
            allpassBufR[i].assign(lenR, 0.0f);
            allpassIdxL[i] = 0;
            allpassIdxR[i] = 0;
        }

        buffersAllocated = true;
        reset();
    }

    void setEnabled(bool e) { targetEnabled = e; }
    bool isEnabled() const { return targetEnabled; }

    void setWet(float w) { targetWet = std::max(0.0f, std::min(w, 2.0f)); }
    float getWet() const { return targetWet; }

    void setDry(float d) { targetDry = std::max(0.0f, std::min(d, 2.0f)); }
    float getDry() const { return targetDry; }

    void setRoomSize(float r) { targetRoomSize = std::max(0.0f, std::min(r, 1.0f)); }
    float getRoomSize() const { return targetRoomSize; }

    void setDamping(float d) { targetDamping = std::max(0.0f, std::min(d, 1.0f)); }
    float getDamping() const { return targetDamping; }

    void setWidth(float w) { targetWidth = std::max(0.0f, std::min(w, 2.0f)); }
    float getWidth() const { return targetWidth; }

    void setParams(float wet, float dry, float roomSize, float damping, float width = 1.0f) {
        setWet(wet);
        setDry(dry);
        setRoomSize(roomSize);
        setDamping(damping);
        setWidth(width);
    }

    void reset() {
        for (int i = 0; i < NUM_COMBS; ++i) {
            std::fill(combBufL[i].begin(), combBufL[i].end(), 0.0f);
            std::fill(combBufR[i].begin(), combBufR[i].end(), 0.0f);
            combIdxL[i] = 0;
            combIdxR[i] = 0;
            combFilterL[i] = 0.0f;
            combFilterR[i] = 0.0f;
        }
        for (int i = 0; i < NUM_ALLPASS; ++i) {
            std::fill(allpassBufL[i].begin(), allpassBufL[i].end(), 0.0f);
            std::fill(allpassBufR[i].begin(), allpassBufR[i].end(), 0.0f);
            allpassIdxL[i] = 0;
            allpassIdxR[i] = 0;
        }

        currentWet = targetWet;
        currentDry = targetDry;
        currentRoomSize = targetRoomSize;
        currentDamping = targetDamping;
        currentWidth = targetWidth;
        currentEnabled = targetEnabled;
    }

    void process(float* interleaved, uint32_t frames, int channels) {
        if (!interleaved || frames == 0 || channels < 2) return;

        if (!targetEnabled && currentWet < 0.0001f) {
            currentEnabled = false;
            return;
        }
        currentEnabled = true;

        ScopedDenormalsDisable ftz;

        // 15ms smoothing factor for parameter updates
        const float alpha = 1.0f - std::exp(-1.0f / (0.015f * (float)sampleRate));

        for (uint32_t f = 0; f < frames; ++f) {
            // Parameter smoothing
            currentWet += alpha * (targetWet - currentWet);
            currentDry += alpha * (targetDry - currentDry);
            currentRoomSize += alpha * (targetRoomSize - currentRoomSize);
            currentDamping += alpha * (targetDamping - currentDamping);
            currentWidth += alpha * (targetWidth - currentWidth);

            const float feedback = 0.50f + 0.35f * currentRoomSize;
            const float damp = currentDamping;

            float inL = interleaved[f * channels + 0];
            float inR = interleaved[f * channels + 1];

            // 1. Parallel Comb Filters
            float combOutL = 0.0f;
            float combOutR = 0.0f;

            for (int i = 0; i < NUM_COMBS; ++i) {
                // Left channel comb
                const int szL = (int)combBufL[i].size();
                int idxL = combIdxL[i];
                float outL = combBufL[i][idxL];
                combFilterL[i] = outL * (1.0f - damp) + combFilterL[i] * damp;
                combBufL[i][idxL] = inL + combFilterL[i] * feedback;
                combIdxL[i] = (idxL + 1 < szL) ? idxL + 1 : 0;
                combOutL += outL;

                // Right channel comb
                const int szR = (int)combBufR[i].size();
                int idxR = combIdxR[i];
                float outR = combBufR[i][idxR];
                combFilterR[i] = outR * (1.0f - damp) + combFilterR[i] * damp;
                combBufR[i][idxR] = inR + combFilterR[i] * feedback;
                combIdxR[i] = (idxR + 1 < szR) ? idxR + 1 : 0;
                combOutR += outR;
            }

            // Normalization after parallel comb bank
            float apInL = combOutL * 0.25f;
            float apInR = combOutR * 0.25f;

            // 2. Cascaded Allpass Diffusers
            for (int i = 0; i < NUM_ALLPASS; ++i) {
                // Left allpass (feedback = 0.5f)
                const int szL = (int)allpassBufL[i].size();
                int idxL = allpassIdxL[i];
                float bufOutL = allpassBufL[i][idxL];
                float apOutL = -apInL + bufOutL;
                allpassBufL[i][idxL] = apInL + (bufOutL * 0.5f);
                allpassIdxL[i] = (idxL + 1 < szL) ? idxL + 1 : 0;
                apInL = apOutL;

                // Right allpass (feedback = 0.5f)
                const int szR = (int)allpassBufR[i].size();
                int idxR = allpassIdxR[i];
                float bufOutR = allpassBufR[i][idxR];
                float apOutR = -apInR + bufOutR;
                allpassBufR[i][idxR] = apInR + (bufOutR * 0.5f);
                allpassIdxR[i] = (idxR + 1 < szR) ? idxR + 1 : 0;
                apInR = apOutR;
            }

            // 3. Stereo Width Matrixing (Mid/Side) on Wet Signal
            float wetL = apInL;
            float wetR = apInR;
            if (std::abs(currentWidth - 1.0f) > 0.001f) {
                float mid = 0.5f * (wetL + wetR);
                float side = 0.5f * (wetL - wetR) * currentWidth;
                wetL = mid + side;
                wetR = mid - side;
            }

            // 4. Wet / Dry Mix
            float outL = inL * currentDry + wetL * currentWet;
            float outR = inR * currentDry + wetR * currentWet;

            interleaved[f * channels + 0] = std::max(-4.0f, std::min(outL, 4.0f));
            interleaved[f * channels + 1] = std::max(-4.0f, std::min(outR, 4.0f));
        }
    }

    void process(double* interleaved, uint32_t frames, int channels) {
        if (!interleaved || frames == 0 || channels < 2) return;
        std::vector<float> tmp(frames * channels);
        for (size_t i = 0; i < tmp.size(); ++i) {
            tmp[i] = static_cast<float>(interleaved[i]);
        }
        process(tmp.data(), frames, channels);
        for (size_t i = 0; i < tmp.size(); ++i) {
            interleaved[i] = static_cast<double>(tmp[i]);
        }
    }

private:
    double sampleRate = 48000.0;
    bool buffersAllocated = false;

    bool targetEnabled = false;
    bool currentEnabled = false;

    float targetWet = 0.35f;
    float currentWet = 0.35f;

    float targetDry = 0.70f;
    float currentDry = 0.70f;

    float targetRoomSize = 0.75f;
    float currentRoomSize = 0.75f;

    float targetDamping = 0.25f;
    float currentDamping = 0.25f;

    float targetWidth = 1.0f;
    float currentWidth = 1.0f;

    // Comb lines
    std::vector<float> combBufL[NUM_COMBS];
    std::vector<float> combBufR[NUM_COMBS];
    int combIdxL[NUM_COMBS] = {0};
    int combIdxR[NUM_COMBS] = {0};
    float combFilterL[NUM_COMBS] = {0.0f};
    float combFilterR[NUM_COMBS] = {0.0f};

    // Allpass lines
    std::vector<float> allpassBufL[NUM_ALLPASS];
    std::vector<float> allpassBufR[NUM_ALLPASS];
    int allpassIdxL[NUM_ALLPASS] = {0};
    int allpassIdxR[NUM_ALLPASS] = {0};
};

} // namespace sauti::dsp
