#pragma once

/**
 * @file lattice_reverb_dsp.h
 * @brief Clean-room Gardner Nested Stereo Allpass Lattice Reverberator DSP.
 *
 * Implements a true nested allpass lattice topology (Gardner 1992/1997) with:
 * - Zero parallel combs (eliminates hollow comb ringing & metallic flutter)
 * - Matched-Z 90 Hz input highpass + subtle stereo cross-feed
 * - Early outer/inner nested allpass diffusers per channel
 * - Cross-coupled stereo nested allpass feedback lattice with quadrature
 *   LFO modulation & 4-point Catmull-Rom cubic interpolation
 * - Sample-rate-invariant matched-Z 1-pole damping + 45 Hz loop DC blocker
 * - Steady-state wet RMS normalization & full F32/F64 precision without
 *   per-sample pow/exp or audio-thread heap allocations
 */

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <vector>
#include "denormals.h"

namespace sauti::dsp {

class LatticeReverbDSP {
public:
    static constexpr int BASE_EARLY_OUTER_L = 521;
    static constexpr int BASE_EARLY_OUTER_R = 563;
    static constexpr int BASE_EARLY_INNER_A_L = 173;
    static constexpr int BASE_EARLY_INNER_A_R = 191;
    static constexpr int BASE_EARLY_INNER_B_L = 257;
    static constexpr int BASE_EARLY_INNER_B_R = 271;

    static constexpr int BASE_MAIN_OUTER_L = 1093;
    static constexpr int BASE_MAIN_OUTER_R = 1151;
    static constexpr int BASE_MAIN_INNER_L = 431;
    static constexpr int BASE_MAIN_INNER_R = 461;

    static constexpr int BASE_LOOP_DEL_L = 1607;
    static constexpr int BASE_LOOP_DEL_R = 1693;

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

        auto scaledLen = [scale](int base, int minVal) -> int {
            return std::max(minVal, (int)std::lround((double)base * scale));
        };

        const int modHeadroom = (int)std::ceil(4.0 * scale) + 12;

        earlyOuterL.resize(scaledLen(BASE_EARLY_OUTER_L, 16));
        earlyOuterR.resize(scaledLen(BASE_EARLY_OUTER_R, 16));
        earlyInnerAL.init(scaledLen(BASE_EARLY_INNER_A_L, 8), 0.55f);
        earlyInnerAR.init(scaledLen(BASE_EARLY_INNER_A_R, 8), 0.55f);
        earlyInnerBL.init(scaledLen(BASE_EARLY_INNER_B_L, 8), 0.45f);
        earlyInnerBR.init(scaledLen(BASE_EARLY_INNER_B_R, 8), 0.45f);

        mainOuterNomL = scaledLen(BASE_MAIN_OUTER_L, 32);
        mainOuterNomR = scaledLen(BASE_MAIN_OUTER_R, 32);
        mainOuterL.resize(mainOuterNomL + modHeadroom);
        mainOuterR.resize(mainOuterNomR + modHeadroom);
        mainInnerL.init(scaledLen(BASE_MAIN_INNER_L, 16), 0.55f);
        mainInnerR.init(scaledLen(BASE_MAIN_INNER_R, 16), 0.55f);

        loopDelL.resize(scaledLen(BASE_LOOP_DEL_L, 32));
        loopDelR.resize(scaledLen(BASE_LOOP_DEL_R, 32));

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

    void setDamping(float d) {
        targetDamping = std::clamp(d, 0.0f, 1.0f);
        updateCoefficients();
    }
    float getDamping() const { return targetDamping; }

    void setWidth(float w) { targetWidth = std::clamp(w, 0.0f, 2.0f); }
    float getWidth() const { return targetWidth; }

    void setParams(float wet, float dry, float roomSize, float damping, float width = 1.0f) {
        targetWet = std::clamp(wet, 0.0f, 2.0f);
        targetDry = std::clamp(dry, 0.0f, 2.0f);
        targetRoomSize = std::clamp(roomSize, 0.0f, 1.0f);
        targetDamping = std::clamp(damping, 0.0f, 1.0f);
        targetWidth = std::clamp(width, 0.0f, 2.0f);
        updateCoefficients();
    }

    void reset() {
        earlyOuterL.clear();
        earlyOuterR.clear();
        earlyInnerAL.clear();
        earlyInnerAR.clear();
        earlyInnerBL.clear();
        earlyInnerBR.clear();

        mainOuterL.clear();
        mainOuterR.clear();
        mainInnerL.clear();
        mainInnerR.clear();

        loopDelL.clear();
        loopDelR.clear();

        inHpfStateL = inHpfStateR = 0.0f;
        dampLpfStateL = dampLpfStateR = 0.0f;
        loopHpfStateL = loopHpfStateR = 0.0f;
        fbStateL = fbStateR = 0.0f;

        lfoPhaseL = 0.0f;
        lfoPhaseR = 1.57079632679f;

        currentWet = targetWet;
        currentDry = targetDry;
        currentWidth = targetWidth;
        currentDecay = targetDecay;
        currentDampCoeff = targetDampCoeff;
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
    struct RingLine {
        std::vector<float> buf;
        int writeIdx = 0;

        void resize(int len) {
            buf.assign(std::max(8, len), 0.0f);
            writeIdx = 0;
        }

        void clear() {
            std::fill(buf.begin(), buf.end(), 0.0f);
            writeIdx = 0;
        }

        float readOldest() const {
            return buf[writeIdx];
        }

        float readCubic(float delaySamples) const {
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

        void write(float v) {
            buf[writeIdx] = v;
            if (++writeIdx >= (int)buf.size()) writeIdx = 0;
        }
    };

    struct SimpleAllpass {
        std::vector<float> buf;
        int idx = 0;
        float gain = 0.5f;

        void init(int len, float g) {
            buf.assign(std::max(4, len), 0.0f);
            idx = 0;
            gain = g;
        }

        void clear() {
            std::fill(buf.begin(), buf.end(), 0.0f);
            idx = 0;
        }

        float process(float x) {
            const float d = buf[idx];
            const float y = -gain * x + d;
            float next = x + gain * y;
            flush_denormal(next);
            buf[idx] = next;
            if (++idx >= (int)buf.size()) idx = 0;
            return y;
        }
    };

    void updateCoefficients() {
        if (sampleRate <= 0.0) return;
        constexpr float twoPi = 6.28318530717958647692f;
        // Room/chamber RT60 curve: 0.18s .. 5.04s (0.50 -> ~0.95s, 0.75 -> ~2.19s)
        // Mean half-loop delay @ 48 kHz = ((431+1093+1607) + (461+1151+1693)) / (2*48000) = 0.0670417s
        const float targetRT60 = 0.18f * std::pow(28.0f, targetRoomSize);
        targetDecay = std::min(0.975f, std::pow(10.0f, -3.0f * 0.0670417f / targetRT60));

        // Sample-rate-invariant matched-Z 1-pole damping
        if (targetDamping <= 0.0001f) {
            targetDampCoeff = 1.0f;
        } else {
            const float dampHz = 18000.0f * std::pow(0.0667f, targetDamping);
            const float w = std::min(3.0f, twoPi * dampHz / (float)sampleRate);
            targetDampCoeff = 1.0f - std::exp(-w);
        }

        inHpfCoeff = 1.0f - std::exp(-std::min(3.0f, twoPi * 90.0f / (float)sampleRate));
        loopHpfCoeff = 1.0f - std::exp(-std::min(3.0f, twoPi * 45.0f / (float)sampleRate));
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
        const float lfoIncL = (twoPi * 0.47f) / (float)sampleRate;
        const float lfoIncR = (twoPi * 0.61f) / (float)sampleRate;
        const float modDepth = 4.0f * (float)(sampleRate / 48000.0);

        for (uint32_t f = 0; f < frames; ++f) {
            currentWet += (targetWet - currentWet) * smoothAlpha;
            currentDry += (targetDry - currentDry) * smoothAlpha;
            currentWidth += (targetWidth - currentWidth) * smoothAlpha;
            currentDecay += (targetDecay - currentDecay) * smoothAlpha;
            currentDampCoeff += (targetDampCoeff - currentDampCoeff) * smoothAlpha;

            const size_t base = (size_t)f * (size_t)channels;
            const double rawInL = static_cast<double>(interleaved[base]);
            const double rawInR = static_cast<double>(interleaved[base + 1]);
            const float inL = static_cast<float>(rawInL);
            const float inR = static_cast<float>(rawInR);

            // 1. Input 90 Hz HPF + subtle stereo cross-feed
            inHpfStateL += inHpfCoeff * (inL - inHpfStateL);
            inHpfStateR += inHpfCoeff * (inR - inHpfStateR);
            flush_denormal(inHpfStateL);
            flush_denormal(inHpfStateR);
            const float hpL = inL - inHpfStateL;
            const float hpR = inR - inHpfStateR;

            const float xL = 0.85f * hpL + 0.15f * hpR;
            const float xR = 0.85f * hpR + 0.15f * hpL;

            // 2. Early Outer Nested Allpass (outer g=0.50 enclosing 2 inner APs)
            float dEarlyL = earlyOuterL.readOldest();
            float aEarlyL = earlyInnerBL.process(earlyInnerAL.process(dEarlyL));
            float vEarlyL = xL + 0.50f * aEarlyL;
            flush_denormal(vEarlyL);
            earlyOuterL.write(vEarlyL);
            const float earlyOutL = aEarlyL - 0.50f * vEarlyL;

            float dEarlyR = earlyOuterR.readOldest();
            float aEarlyR = earlyInnerBR.process(earlyInnerAR.process(dEarlyR));
            float vEarlyR = xR + 0.50f * aEarlyR;
            flush_denormal(vEarlyR);
            earlyOuterR.write(vEarlyR);
            const float earlyOutR = aEarlyR - 0.50f * vEarlyR;

            // 3. Quadrature LFO Modulation
            const float modL = std::sin(lfoPhaseL) * modDepth;
            const float modR = std::sin(lfoPhaseR) * modDepth;
            lfoPhaseL += lfoIncL;
            if (lfoPhaseL >= twoPi) lfoPhaseL -= twoPi;
            lfoPhaseR += lfoIncR;
            if (lfoPhaseR >= twoPi) lfoPhaseR -= twoPi;

            // 4. Cross-Coupled Stereo Nested Allpass Lattice Loop
            const float loopInL = earlyOutL + fbStateR * currentDecay;
            const float loopInR = earlyOutR + fbStateL * currentDecay;

            float dMainL = mainOuterL.readCubic((float)mainOuterNomL + modL);
            float aMainL = mainInnerL.process(dMainL);
            float vMainL = loopInL + 0.50f * aMainL;
            flush_denormal(vMainL);
            mainOuterL.write(vMainL);
            const float mainApOutL = aMainL - 0.50f * vMainL;

            float dMainR = mainOuterR.readCubic((float)mainOuterNomR + modR);
            float aMainR = mainInnerR.process(dMainR);
            float vMainR = loopInR + 0.50f * aMainR;
            flush_denormal(vMainR);
            mainOuterR.write(vMainR);
            const float mainApOutR = aMainR - 0.50f * vMainR;

            // Loop delay + matched-Z LPF damping + 45 Hz loop DC blocker
            const float loopDelOutL = loopDelL.readOldest();
            loopDelL.write(mainApOutL);
            dampLpfStateL += currentDampCoeff * (loopDelOutL - dampLpfStateL);
            flush_denormal(dampLpfStateL);
            loopHpfStateL += loopHpfCoeff * (dampLpfStateL - loopHpfStateL);
            flush_denormal(loopHpfStateL);
            fbStateL = dampLpfStateL - loopHpfStateL;

            const float loopDelOutR = loopDelR.readOldest();
            loopDelR.write(mainApOutR);
            dampLpfStateR += currentDampCoeff * (loopDelOutR - dampLpfStateR);
            flush_denormal(dampLpfStateR);
            loopHpfStateR += loopHpfCoeff * (dampLpfStateR - loopHpfStateR);
            flush_denormal(loopHpfStateR);
            fbStateR = dampLpfStateR - loopHpfStateR;

            // 5. Multi-Tap Lattice Output with Steady-State RMS Normalization
            const float wetNorm = 0.55f * std::sqrt(std::max(0.08f, 1.0f - 0.80f * currentDecay * currentDecay));
            const float wetL = (0.30f * earlyOutL + 0.45f * mainApOutL + 0.35f * loopDelOutL - 0.18f * loopDelOutR) * wetNorm;
            const float wetR = (0.30f * earlyOutR + 0.45f * mainApOutR + 0.35f * loopDelOutR - 0.18f * loopDelOutL) * wetNorm;

            // 6. Mid/Side Stereo Width Balance
            const float mid = 0.5f * (wetL + wetR);
            const float side = 0.5f * (wetL - wetR) * currentWidth;
            const float outL = mid + side;
            const float outR = mid - side;

            if (mixDry) {
                interleaved[base]     = static_cast<T>(rawInL * static_cast<double>(currentDry) + static_cast<double>(outL) * static_cast<double>(currentWet));
                interleaved[base + 1] = static_cast<T>(rawInR * static_cast<double>(currentDry) + static_cast<double>(outR) * static_cast<double>(currentWet));
            } else {
                interleaved[base]     = static_cast<T>(static_cast<double>(outL) * static_cast<double>(currentWet));
                interleaved[base + 1] = static_cast<T>(static_cast<double>(outR) * static_cast<double>(currentWet));
            }
        }
    }

    double sampleRate = 48000.0;
    bool buffersAllocated = false;

    bool targetEnabled = false;
    bool currentEnabled = false;

    float targetWet = 0.28f;
    float currentWet = 0.28f;

    float targetDry = 0.90f;
    float currentDry = 0.90f;

    float targetRoomSize = 0.50f;
    float targetDamping = 0.30f;

    float targetWidth = 1.0f;
    float currentWidth = 1.0f;

    float targetDecay = 0.615f;
    float currentDecay = 0.615f;
    float targetDampCoeff = 0.55f;
    float currentDampCoeff = 0.55f;
    float inHpfCoeff = 0.01f;
    float loopHpfCoeff = 0.005f;

    // Early nested allpass lines
    RingLine earlyOuterL, earlyOuterR;
    SimpleAllpass earlyInnerAL, earlyInnerAR;
    SimpleAllpass earlyInnerBL, earlyInnerBR;

    // Main cross-coupled nested allpass loop
    RingLine mainOuterL, mainOuterR;
    SimpleAllpass mainInnerL, mainInnerR;
    int mainOuterNomL = 1093;
    int mainOuterNomR = 1151;

    RingLine loopDelL, loopDelR;

    float inHpfStateL = 0.0f, inHpfStateR = 0.0f;
    float dampLpfStateL = 0.0f, dampLpfStateR = 0.0f;
    float loopHpfStateL = 0.0f, loopHpfStateR = 0.0f;
    float fbStateL = 0.0f, fbStateR = 0.0f;

    float lfoPhaseL = 0.0f;
    float lfoPhaseR = 1.57079632679f;
};

} // namespace sauti::dsp
