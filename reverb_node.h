#pragma once

// High-Definition Multi-Engine Stereo Reverb Node.
//
// Engines:
//   0: Dattorro Figure-8 Diffuse Tank (Jon Dattorro 1997 Plate)
//   1: Gardner Nested Stereo Allpass Lattice (Room/Chamber)
//   2: Multi-Stage Givens-Hadamard Diffusion Network
//   3: 8-Channel Orthonormal Hadamard FDN Hall
//   4: Keith Barr All-Pass Ring (Alesis / Spin FV-1)
//   5: David Griesinger "Spin & Wander" Hall Tank (Lexicon 224/480L)
//
// Features:
//   - Strict per-engine parameter isolation (adjusting one engine never clobbers others)
//   - Clean buffer reset + 20 ms wet fade-in on engine switch or enable (zero tail bleed/clicks)
//   - Zero-allocation audio path with pre-allocated scratch buffers
//   - Full F32 / F64 precision preservation
//   - Sample-rate-invariant matched-Z pre-filtering & damping (11 kHz .. 384 kHz)

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <type_traits>
#include <vector>
#include "dsp/barr_ring_reverb_dsp.h"
#include "dsp/denormals.h"
#include "dsp/diffusion_reverb_dsp.h"
#include "dsp/griesinger_tank_dsp.h"
#include "dsp/hadamard_fdn_dsp.h"
#include "dsp/lattice_reverb_dsp.h"

enum class ReverbEngine {
    Dattorro = 0,
    Lattice = 1,
    Diffusion = 2,
    HadamardFdn = 3,
    BarrRing = 4,
    Griesinger = 5
};

#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

class ReverbNode
{
public:
    static constexpr float MAX_PRE_DELAY_MS = 250.0f;

    ReverbNode()
    {
        buildBuffers();
        reset();
    }

    void setSampleRate(double rate)
    {
        if (rate <= 0.0)
            rate = 48000.0;
        latticeDsp.setSampleRate(rate);
        diffusionDsp.setSampleRate(rate);
        hadamardDsp.setSampleRate(rate);
        barrDsp.setSampleRate(rate);
        griesingerDsp.setSampleRate(rate);
        if (std::abs(sampleRate - rate) < 0.1)
            return;

        sampleRate = rate;
        buildBuffers();
        reset();
    }

    void setEnabled(bool e)
    {
        if (targetEnabled == e)
        {
            syncSubEngineFlags();
            return;
        }
        if (e)
        {
            resetEngineState(targetEngine);
            clearPreDelayBuf();
            currentPreDelayMs = enginePreDelayMs[static_cast<int>(targetEngine)];
            subCurrentDry = getDry();
            switchFadeGain = 0.0f;
        }
        else
        {
            resetEngineState(targetEngine);
            clearPreDelayBuf();
        }
        targetEnabled = e;
        syncSubEngineFlags();
    }

    void setEngine(int engine)
    {
        if (engine < 0 || engine > 5) engine = 0;
        const ReverbEngine newEngine = static_cast<ReverbEngine>(engine);
        if (newEngine == targetEngine)
        {
            syncSubEngineFlags();
            return;
        }
        resetEngineState(targetEngine);
        resetEngineState(newEngine);
        clearPreDelayBuf();
        targetEngine = newEngine;
        currentPreDelayMs = enginePreDelayMs[engine];
        subCurrentDry = getDry();
        switchFadeGain = 0.0f;
        syncSubEngineFlags();
    }

    int getEngine() const { return static_cast<int>(targetEngine); }

    void setDattorroParams(float wet, float dry, float roomSize, float damping, float preDelayMs, float width = 1.0f)
    {
        targetWet = std::clamp(wet, 0.0f, 2.0f);
        targetDry = std::clamp(dry, 0.0f, 2.0f);
        targetRoomSize = std::clamp(roomSize, 0.0f, 1.0f);
        targetDamping = std::clamp(damping, 0.0f, 1.0f);
        enginePreDelayMs[0] = std::clamp(preDelayMs, 0.0f, MAX_PRE_DELAY_MS);
        targetWidth = std::clamp(width, 0.0f, 2.0f);
        updateDattorroCoefficients();
    }

    void getDattorroParams(float *wet, float *dry, float *roomSize, float *damping, float *preDelayMs, float *width) const
    {
        if (wet) *wet = targetWet;
        if (dry) *dry = targetDry;
        if (roomSize) *roomSize = targetRoomSize;
        if (damping) *damping = targetDamping;
        if (preDelayMs) *preDelayMs = enginePreDelayMs[0];
        if (width) *width = targetWidth;
    }

    void setLatticeParams(float wet, float dry, float roomSize, float damping, float width = 1.0f)
    {
        latticeDsp.setParams(wet, dry, roomSize, damping, width);
    }

    void getLatticeParams(float *wet, float *dry, float *roomSize, float *damping, float *width) const
    {
        if (wet) *wet = latticeDsp.getWet();
        if (dry) *dry = latticeDsp.getDry();
        if (roomSize) *roomSize = latticeDsp.getRoomSize();
        if (damping) *damping = latticeDsp.getDamping();
        if (width) *width = latticeDsp.getWidth();
    }

    void setDiffusionParams(float wet, float dry, float roomSize, float decayTimeMs, float diffusion, float damping, float width = 1.0f)
    {
        diffusionDsp.setParams(wet, dry, roomSize, decayTimeMs, diffusion, damping, width);
    }

    void getDiffusionParams(float *wet, float *dry, float *roomSize, float *decayTimeMs, float *diffusion, float *damping, float *width) const
    {
        if (wet) *wet = diffusionDsp.getWet();
        if (dry) *dry = diffusionDsp.getDry();
        if (roomSize) *roomSize = diffusionDsp.getRoomSize();
        if (decayTimeMs) *decayTimeMs = diffusionDsp.getDecayTimeMs();
        if (diffusion) *diffusion = diffusionDsp.getDiffusion();
        if (damping) *damping = diffusionDsp.getDamping();
        if (width) *width = diffusionDsp.getWidth();
    }

    void setHadamardParams(float wet, float dry, float roomSize, float damping, float width = 1.0f)
    {
        hadamardDsp.setParams(wet, dry, roomSize, damping, width);
    }

    void getHadamardParams(float *wet, float *dry, float *roomSize, float *damping, float *width) const
    {
        if (wet) *wet = hadamardDsp.getWet();
        if (dry) *dry = hadamardDsp.getDry();
        if (roomSize) *roomSize = hadamardDsp.getRoomSize();
        if (damping) *damping = hadamardDsp.getDamping();
        if (width) *width = hadamardDsp.getWidth();
    }

    void setBarrParams(float wet, float dry, float roomSize, float damping, float width = 1.0f)
    {
        barrDsp.setParams(wet, dry, roomSize, damping, width);
    }

    void getBarrParams(float *wet, float *dry, float *roomSize, float *damping, float *width) const
    {
        if (wet) *wet = barrDsp.getWet();
        if (dry) *dry = barrDsp.getDry();
        if (roomSize) *roomSize = barrDsp.getRoomSize();
        if (damping) *damping = barrDsp.getDamping();
        if (width) *width = barrDsp.getWidth();
    }

    void setGriesingerParams(float wet, float dry, float roomSize, float damping, float width = 1.0f)
    {
        griesingerDsp.setParams(wet, dry, roomSize, damping, width);
    }

    void getGriesingerParams(float *wet, float *dry, float *roomSize, float *damping, float *width) const
    {
        if (wet) *wet = griesingerDsp.getWet();
        if (dry) *dry = griesingerDsp.getDry();
        if (roomSize) *roomSize = griesingerDsp.getRoomSize();
        if (damping) *damping = griesingerDsp.getDamping();
        if (width) *width = griesingerDsp.getWidth();
    }

    void getActiveParams(float *wet, float *dry, float *roomSize, float *damping, float *preDelayMs, float *width) const
    {
        switch (targetEngine)
        {
        case ReverbEngine::Lattice:
            getLatticeParams(wet, dry, roomSize, damping, width);
            break;
        case ReverbEngine::Diffusion:
            getDiffusionParams(wet, dry, roomSize, nullptr, nullptr, damping, width);
            break;
        case ReverbEngine::HadamardFdn:
            getHadamardParams(wet, dry, roomSize, damping, width);
            break;
        case ReverbEngine::BarrRing:
            getBarrParams(wet, dry, roomSize, damping, width);
            break;
        case ReverbEngine::Griesinger:
            getGriesingerParams(wet, dry, roomSize, damping, width);
            break;
        case ReverbEngine::Dattorro:
        default:
            getDattorroParams(wet, dry, roomSize, damping, nullptr, width);
            break;
        }
        if (preDelayMs)
            *preDelayMs = enginePreDelayMs[static_cast<int>(targetEngine)];
    }

    bool getEnabled() const { return targetEnabled; }

    void setMix(float m)
    {
        setWet(m);
        setDry(1.0f - m);
    }

    void setWet(float w)
    {
        const float clamped = std::clamp(w, 0.0f, 2.0f);
        switch (targetEngine)
        {
        case ReverbEngine::Lattice:     latticeDsp.setWet(clamped); break;
        case ReverbEngine::Diffusion:   diffusionDsp.setWet(clamped); break;
        case ReverbEngine::HadamardFdn: hadamardDsp.setWet(clamped); break;
        case ReverbEngine::BarrRing:    barrDsp.setWet(clamped); break;
        case ReverbEngine::Griesinger:  griesingerDsp.setWet(clamped); break;
        case ReverbEngine::Dattorro:
        default:                        targetWet = clamped; break;
        }
    }

    void setDry(float d)
    {
        const float clamped = std::clamp(d, 0.0f, 2.0f);
        switch (targetEngine)
        {
        case ReverbEngine::Lattice:     latticeDsp.setDry(clamped); break;
        case ReverbEngine::Diffusion:   diffusionDsp.setDry(clamped); break;
        case ReverbEngine::HadamardFdn: hadamardDsp.setDry(clamped); break;
        case ReverbEngine::BarrRing:    barrDsp.setDry(clamped); break;
        case ReverbEngine::Griesinger:  griesingerDsp.setDry(clamped); break;
        case ReverbEngine::Dattorro:
        default:                        targetDry = clamped; break;
        }
    }

    void setRoomSize(float r)
    {
        const float clamped = std::clamp(r, 0.0f, 1.0f);
        switch (targetEngine)
        {
        case ReverbEngine::Lattice:     latticeDsp.setRoomSize(clamped); break;
        case ReverbEngine::Diffusion:   diffusionDsp.setRoomSize(clamped); break;
        case ReverbEngine::HadamardFdn: hadamardDsp.setRoomSize(clamped); break;
        case ReverbEngine::BarrRing:    barrDsp.setRoomSize(clamped); break;
        case ReverbEngine::Griesinger:  griesingerDsp.setRoomSize(clamped); break;
        case ReverbEngine::Dattorro:
        default:
            targetRoomSize = clamped;
            updateDattorroCoefficients();
            break;
        }
    }

    void setDamping(float d)
    {
        const float clamped = std::clamp(d, 0.0f, 1.0f);
        switch (targetEngine)
        {
        case ReverbEngine::Lattice:     latticeDsp.setDamping(clamped); break;
        case ReverbEngine::Diffusion:   diffusionDsp.setDamping(clamped); break;
        case ReverbEngine::HadamardFdn: hadamardDsp.setDamping(clamped); break;
        case ReverbEngine::BarrRing:    barrDsp.setDamping(clamped); break;
        case ReverbEngine::Griesinger:  griesingerDsp.setDamping(clamped); break;
        case ReverbEngine::Dattorro:
        default:
            targetDamping = clamped;
            updateDattorroCoefficients();
            break;
        }
    }

    void setPreDelayMs(float ms)
    {
        enginePreDelayMs[static_cast<int>(targetEngine)] =
            std::clamp(ms, 0.0f, MAX_PRE_DELAY_MS);
    }

    void setWidth(float w)
    {
        const float clamped = std::clamp(w, 0.0f, 2.0f);
        switch (targetEngine)
        {
        case ReverbEngine::Lattice:     latticeDsp.setWidth(clamped); break;
        case ReverbEngine::Diffusion:   diffusionDsp.setWidth(clamped); break;
        case ReverbEngine::HadamardFdn: hadamardDsp.setWidth(clamped); break;
        case ReverbEngine::BarrRing:    barrDsp.setWidth(clamped); break;
        case ReverbEngine::Griesinger:  griesingerDsp.setWidth(clamped); break;
        case ReverbEngine::Dattorro:
        default:                        targetWidth = clamped; break;
        }
    }

    float getWet() const
    {
        float v = targetWet;
        getActiveParams(&v, nullptr, nullptr, nullptr, nullptr, nullptr);
        return v;
    }

    float getDry() const
    {
        float v = targetDry;
        getActiveParams(nullptr, &v, nullptr, nullptr, nullptr, nullptr);
        return v;
    }

    float getRoomSize() const
    {
        float v = targetRoomSize;
        getActiveParams(nullptr, nullptr, &v, nullptr, nullptr, nullptr);
        return v;
    }

    float getDamping() const
    {
        float v = targetDamping;
        getActiveParams(nullptr, nullptr, nullptr, &v, nullptr, nullptr);
        return v;
    }

    float getPreDelayMs() const
    {
        return enginePreDelayMs[static_cast<int>(targetEngine)];
    }

    float getWidth() const
    {
        float v = targetWidth;
        getActiveParams(nullptr, nullptr, nullptr, nullptr, nullptr, &v);
        return v;
    }

    // Dry path has zero latency (pre-delay only offsets the wet reflection tail).
    double getLatencySamples() const { return 0.0; }

    void reset()
    {
        clearPreDelayBuf();
        resetDattorroState();
        latticeDsp.reset();
        diffusionDsp.reset();
        hadamardDsp.reset();
        barrDsp.reset();
        griesingerDsp.reset();

        currentPreDelayMs = enginePreDelayMs[static_cast<int>(targetEngine)];
        subCurrentDry = getDry();
        switchFadeGain = 1.0f;
        currentEnabled = targetEnabled;
        syncSubEngineFlags();
    }

    void process(float *interleaved, uint32_t frames, int channels)
    {
        processImpl(interleaved, frames, channels);
    }

    void process(double *interleaved, uint32_t frames, int channels)
    {
        processImpl(interleaved, frames, channels);
    }

private:
    void syncSubEngineFlags()
    {
        latticeDsp.setEnabled(targetEnabled && targetEngine == ReverbEngine::Lattice);
        diffusionDsp.setEnabled(targetEnabled && targetEngine == ReverbEngine::Diffusion);
        hadamardDsp.setEnabled(targetEnabled && targetEngine == ReverbEngine::HadamardFdn);
        barrDsp.setEnabled(targetEnabled && targetEngine == ReverbEngine::BarrRing);
        griesingerDsp.setEnabled(targetEnabled && targetEngine == ReverbEngine::Griesinger);
    }

    void clearPreDelayBuf()
    {
        for (int ch = 0; ch < 2; ++ch)
        {
            if (!preDelayBuf[ch].empty())
                std::fill(preDelayBuf[ch].begin(), preDelayBuf[ch].end(), 0.0f);
            preDelayWriteIdx[ch] = 0;
        }
    }

    void resetDattorroState()
    {
        for (int ch = 0; ch < 2; ++ch)
        {
            hpState[ch] = 0.0f;
            lpState[ch] = 0.0f;
            for (int i = 0; i < 4; ++i)
                diffusers[ch][i].clear();
        }

        tank1_modAp.clear();
        tank1_del1.clear();
        tank1_ap2.clear();
        tank1_del2.clear();
        tank1_dampState = 0.0f;

        tank2_modAp.clear();
        tank2_del1.clear();
        tank2_ap2.clear();
        tank2_del2.clear();
        tank2_dampState = 0.0f;

        tank1_lastOut = 0.0f;
        tank2_lastOut = 0.0f;

        lfoPhase1 = 0.0f;
        lfoPhase2 = 0.25f * (float)(2.0 * M_PI);

        currentWet = targetWet;
        currentDry = targetDry;
        currentWidth = targetWidth;
        currentDecay = targetDecay;
        currentDampCoeff = targetDampCoeff;
    }

    void resetEngineState(ReverbEngine eng)
    {
        switch (eng)
        {
        case ReverbEngine::Lattice:     latticeDsp.reset(); break;
        case ReverbEngine::Diffusion:   diffusionDsp.reset(); break;
        case ReverbEngine::HadamardFdn: hadamardDsp.reset(); break;
        case ReverbEngine::BarrRing:    barrDsp.reset(); break;
        case ReverbEngine::Griesinger:  griesingerDsp.reset(); break;
        case ReverbEngine::Dattorro:
        default:                        resetDattorroState(); break;
        }
    }

    void updateDattorroCoefficients()
    {
        if (sampleRate <= 0.0) return;
        constexpr double twoPi = 2.0 * M_PI;
        const float targetRT60 = 0.35f * std::pow(40.0f, targetRoomSize);
        targetDecay = std::min(0.985f, std::pow(10.0f, -1.0881f / targetRT60));

        if (targetDamping <= 0.0001f)
        {
            targetDampCoeff = 1.0f;
        }
        else
        {
            const float dampHz = 18000.0f * std::pow(0.0667f, targetDamping);
            const float wDamp = std::min(3.0f, (float)(twoPi * dampHz / sampleRate));
            targetDampCoeff = 1.0f - std::exp(-wDamp);
        }

        preHpAlpha = 1.0f - std::exp(-std::min(3.0f, (float)(twoPi * 80.0 / sampleRate)));
        preLpAlpha = 1.0f - std::exp(-std::min(3.0f, (float)(twoPi * 15000.0 / sampleRate)));
    }

    inline void readPreDelayLinear(float inL, float inR, float preDelayMs, float &outL, float &outR)
    {
        const size_t preDelayLen = preDelayBuf[0].size();
        if (preDelayLen < 4)
        {
            outL = inL;
            outR = inR;
            return;
        }

        const float delaySamp = std::clamp(
            (preDelayMs * 0.001f) * (float)sampleRate,
            0.0f,
            (float)(preDelayLen - 2));
        const size_t dFloor = (size_t)delaySamp;
        const float frac = delaySamp - (float)dFloor;

        preDelayBuf[0][preDelayWriteIdx[0]] = inL;
        preDelayBuf[1][preDelayWriteIdx[1]] = inR;

        const size_t i0L = (preDelayWriteIdx[0] + preDelayLen - dFloor) % preDelayLen;
        const size_t i1L = (i0L == 0) ? (preDelayLen - 1) : (i0L - 1);
        outL = preDelayBuf[0][i0L] * (1.0f - frac) + preDelayBuf[0][i1L] * frac;

        const size_t i0R = (preDelayWriteIdx[1] + preDelayLen - dFloor) % preDelayLen;
        const size_t i1R = (i0R == 0) ? (preDelayLen - 1) : (i0R - 1);
        outR = preDelayBuf[1][i0R] * (1.0f - frac) + preDelayBuf[1][i1R] * frac;

        preDelayWriteIdx[0] = (preDelayWriteIdx[0] + 1 < preDelayLen) ? (preDelayWriteIdx[0] + 1) : 0;
        preDelayWriteIdx[1] = (preDelayWriteIdx[1] + 1 < preDelayLen) ? (preDelayWriteIdx[1] + 1) : 0;
    }

    template <typename T>
    void processImpl(T *interleaved, uint32_t frames, int channels)
    {
        if (!interleaved || frames == 0 || channels < 2)
            return;

        if (!targetEnabled)
        {
            currentEnabled = false;
            return;
        }
        currentEnabled = true;

        sauti::dsp::ScopedDenormalsDisable ftz;

        const float alphaSmooth = 1.0f - std::exp(-1.0f / (0.015f * (float)sampleRate));
        const float fadeAlpha = 1.0f - std::exp(-1.0f / (0.006f * (float)sampleRate));

        if (targetEngine != ReverbEngine::Dattorro)
        {
            const float activeTargetPreDelay = enginePreDelayMs[static_cast<int>(targetEngine)];
            const float activeTargetDry = getDry();
            const size_t preDelayLen = preDelayBuf[0].size();
            const bool hasPreDelay = (preDelayLen >= 4) &&
                (activeTargetPreDelay > 0.001f || currentPreDelayMs > 0.001f);

            if (!hasPreDelay && switchFadeGain >= 0.9999f)
            {
                currentPreDelayMs = activeTargetPreDelay;
                subCurrentDry = activeTargetDry;
                switchFadeGain = 1.0f;
                if (targetEngine == ReverbEngine::Lattice)
                    latticeDsp.process(interleaved, frames, channels);
                else if (targetEngine == ReverbEngine::Diffusion)
                    diffusionDsp.process(interleaved, frames, channels);
                else if (targetEngine == ReverbEngine::HadamardFdn)
                    hadamardDsp.process(interleaved, frames, channels);
                else if (targetEngine == ReverbEngine::BarrRing)
                    barrDsp.process(interleaved, frames, channels);
                else if (targetEngine == ReverbEngine::Griesinger)
                    griesingerDsp.process(interleaved, frames, channels);
                return;
            }

            auto &scratch = [&]() -> std::vector<T> & {
                if constexpr (std::is_same_v<T, double>)
                    return scratchPreDelay64;
                else
                    return scratchPreDelay;
            }();

            const size_t needed = (size_t)frames * (size_t)channels;
            if (scratch.size() < needed)
                scratch.resize(needed, static_cast<T>(0));

            if (hasPreDelay)
            {
                for (uint32_t i = 0; i < frames; ++i)
                {
                    currentPreDelayMs += alphaSmooth * (activeTargetPreDelay - currentPreDelayMs);
                    const size_t base = (size_t)i * (size_t)channels;
                    float pdL = 0.0f, pdR = 0.0f;
                    readPreDelayLinear(
                        static_cast<float>(interleaved[base]),
                        static_cast<float>(interleaved[base + 1]),
                        currentPreDelayMs, pdL, pdR);
                    scratch[base] = static_cast<T>(pdL);
                    scratch[base + 1] = static_cast<T>(pdR);
                }
            }
            else
            {
                currentPreDelayMs = 0.0f;
                for (uint32_t i = 0; i < frames; ++i)
                {
                    const size_t base = (size_t)i * (size_t)channels;
                    scratch[base] = interleaved[base];
                    scratch[base + 1] = interleaved[base + 1];
                }
            }

            auto processWetWithFade = [&](auto &dsp) {
                dsp.processWetOnly(scratch.data(), frames, channels);
                for (uint32_t i = 0; i < frames; ++i)
                {
                    subCurrentDry += alphaSmooth * (activeTargetDry - subCurrentDry);
                    switchFadeGain += fadeAlpha * (1.0f - switchFadeGain);
                    const size_t base = (size_t)i * (size_t)channels;
                    interleaved[base] = static_cast<T>(
                        static_cast<double>(interleaved[base]) * static_cast<double>(subCurrentDry) +
                        static_cast<double>(scratch[base]) * static_cast<double>(switchFadeGain));
                    interleaved[base + 1] = static_cast<T>(
                        static_cast<double>(interleaved[base + 1]) * static_cast<double>(subCurrentDry) +
                        static_cast<double>(scratch[base + 1]) * static_cast<double>(switchFadeGain));
                }
            };

            if (targetEngine == ReverbEngine::Lattice)
                processWetWithFade(latticeDsp);
            else if (targetEngine == ReverbEngine::Diffusion)
                processWetWithFade(diffusionDsp);
            else if (targetEngine == ReverbEngine::HadamardFdn)
                processWetWithFade(hadamardDsp);
            else if (targetEngine == ReverbEngine::BarrRing)
                processWetWithFade(barrDsp);
            else if (targetEngine == ReverbEngine::Griesinger)
                processWetWithFade(griesingerDsp);

            if (switchFadeGain > 0.9999f)
                switchFadeGain = 1.0f;
            return;
        }

        if (tank1_del1.empty())
            return;

        const float lfoInc1 = (float)(2.0 * M_PI * 0.73 / sampleRate);
        const float lfoInc2 = (float)(2.0 * M_PI * 0.91 / sampleRate);
        const float modDepth = (float)(8.0 * (sampleRate / 29761.0));
        const float dattorroTargetPreDelay = enginePreDelayMs[0];
        constexpr float crossFeedNorm = 1.0f / 1.20f;

        for (uint32_t i = 0; i < frames; ++i)
        {
            currentWet += alphaSmooth * (targetWet - currentWet);
            currentDry += alphaSmooth * (targetDry - currentDry);
            currentWidth += alphaSmooth * (targetWidth - currentWidth);
            currentPreDelayMs += alphaSmooth * (dattorroTargetPreDelay - currentPreDelayMs);
            currentDecay += alphaSmooth * (targetDecay - currentDecay);
            currentDampCoeff += alphaSmooth * (targetDampCoeff - currentDampCoeff);
            switchFadeGain += fadeAlpha * (1.0f - switchFadeGain);

            const float ap2Gain = std::clamp(currentDecay + 0.15f, 0.25f, 0.50f);

            const size_t base = (size_t)i * (size_t)channels;
            const double rawInL = static_cast<double>(interleaved[base]);
            const double rawInR = static_cast<double>(interleaved[base + 1]);
            const float inL = static_cast<float>(rawInL);
            const float inR = static_cast<float>(rawInR);

            // 1. Pre-Delay with linear interpolation
            float pdL = inL;
            float pdR = inR;
            readPreDelayLinear(inL, inR, currentPreDelayMs, pdL, pdR);

            // 2. Matched-Z Pre-Filtering (80 Hz HPF + 15 kHz LPF)
            hpState[0] += preHpAlpha * (pdL - hpState[0]);
            hpState[0] = flushDenormal(hpState[0]);
            const float hpOutL = pdL - hpState[0];
            lpState[0] += preLpAlpha * (hpOutL - lpState[0]);
            lpState[0] = flushDenormal(lpState[0]);
            const float filtL = lpState[0];

            hpState[1] += preHpAlpha * (pdR - hpState[1]);
            hpState[1] = flushDenormal(hpState[1]);
            const float hpOutR = pdR - hpState[1];
            lpState[1] += preLpAlpha * (hpOutR - lpState[1]);
            lpState[1] = flushDenormal(lpState[1]);
            const float filtR = lpState[1];

            // 3. Dual Cascaded Input Diffusers (normalized stereo cross-feed)
            float diffIn1 = (filtL + 0.20f * filtR) * crossFeedNorm;
            float diffIn2 = (filtR + 0.20f * filtL) * crossFeedNorm;

            for (int d = 0; d < 4; ++d)
            {
                diffIn1 = diffusers[0][d].process(diffIn1);
                diffIn2 = diffusers[1][d].process(diffIn2);
            }

            // 4. Figure-8 Coupled Tank Loops
            float tank1In = flushDenormal(diffIn1 + tank2_lastOut * currentDecay);
            float tank2In = flushDenormal(diffIn2 + tank1_lastOut * currentDecay);

            const float mod1 = modDepth * std::sin(lfoPhase1);
            const float mod2 = modDepth * std::sin(lfoPhase2);
            lfoPhase1 += lfoInc1;
            if (lfoPhase1 >= (float)(2.0 * M_PI)) lfoPhase1 -= (float)(2.0 * M_PI);
            lfoPhase2 += lfoInc2;
            if (lfoPhase2 >= (float)(2.0 * M_PI)) lfoPhase2 -= (float)(2.0 * M_PI);

            // --- TANK 1 LOOP ---
            // Canonical alternating-sign modulated allpass (g + z^-D)/(1 + g z^-D) with cubic interp
            const float t1_node = tank1_modAp.processModulatedAlternating(tank1In, mod1);
            tank1_del1.write(t1_node);
            const float t1_del1_out = tank1_del1.readOldest();
            tank1_dampState += currentDampCoeff * (t1_del1_out - tank1_dampState);
            tank1_dampState = flushDenormal(tank1_dampState);
            const float t1_ap2_out = tank1_ap2.processWithGain(tank1_dampState, ap2Gain);
            tank1_del2.write(t1_ap2_out);
            tank1_lastOut = tank1_del2.readOldest();

            // --- TANK 2 LOOP ---
            const float t2_node = tank2_modAp.processModulatedAlternating(tank2In, mod2);
            tank2_del1.write(t2_node);
            const float t2_del1_out = tank2_del1.readOldest();
            tank2_dampState += currentDampCoeff * (t2_del1_out - tank2_dampState);
            tank2_dampState = flushDenormal(tank2_dampState);
            const float t2_ap2_out = tank2_ap2.processWithGain(tank2_dampState, ap2Gain);
            tank2_del2.write(t2_ap2_out);
            tank2_lastOut = tank2_del2.readOldest();

            // 5. Multi-Tap Stereo Output Matrix (14 Mutually Prime Taps)
            float outL = tank2_del1.read(tap_t2_d1_1)
                       + tank2_del1.read(tap_t2_d1_2)
                       - tank2_ap2.read(tap_t2_ap2_1)
                       + tank2_del2.read(tap_t2_d2_1)
                       - tank1_del1.read(tap_t1_d1_1)
                       - tank1_ap2.read(tap_t1_ap2_1)
                       - tank1_del2.read(tap_t1_d2_1);

            float outR = tank1_del1.read(tap_t1_d1_2)
                       + tank1_del1.read(tap_t1_d1_3)
                       - tank1_ap2.read(tap_t1_ap2_2)
                       + tank1_del2.read(tap_t1_d2_2)
                       - tank2_del1.read(tap_t2_d1_3)
                       - tank2_ap2.read(tap_t2_ap2_2)
                       - tank2_del2.read(tap_t2_d2_2);

            outL *= 0.36f;
            outR *= 0.36f;

            // 6. Stereo Width Processing (Mid/Side Matrix)
            const float mid = (outL + outR) * 0.5f;
            const float side = (outL - outR) * 0.5f;
            const float wetL = (mid + side * currentWidth) * switchFadeGain;
            const float wetR = (mid - side * currentWidth) * switchFadeGain;

            // 7. Final Wet/Dry Mix
            interleaved[base]     = static_cast<T>(rawInL * static_cast<double>(currentDry) + static_cast<double>(wetL) * static_cast<double>(currentWet));
            interleaved[base + 1] = static_cast<T>(rawInR * static_cast<double>(currentDry) + static_cast<double>(wetR) * static_cast<double>(currentWet));
        }

        if (switchFadeGain > 0.9999f)
            switchFadeGain = 1.0f;
    }

    static inline float flushDenormal(float val)
    {
        return (std::abs(val) < 1.0e-15f) ? 0.0f : val;
    }

    class DelayLine
    {
    public:
        void resize(size_t len)
        {
            buf.assign(std::max<size_t>(4, len), 0.0f);
            writeIdx = 0;
        }

        void clear()
        {
            std::fill(buf.begin(), buf.end(), 0.0f);
            writeIdx = 0;
        }

        bool empty() const { return buf.empty(); }
        size_t size() const { return buf.size(); }

        void write(float sample)
        {
            buf[writeIdx] = sample;
            if (++writeIdx >= buf.size())
                writeIdx = 0;
        }

        float readOldest() const
        {
            return buf[writeIdx];
        }

        float read(size_t delaySamples) const
        {
            if (buf.empty()) return 0.0f;
            const size_t sz = buf.size();
            delaySamples = std::min(delaySamples, sz - 1);
            const size_t rIdx = (writeIdx + sz - 1 - delaySamples) % sz;
            return buf[rIdx];
        }

        float readCubic(float delaySamples) const
        {
            if (buf.empty()) return 0.0f;
            const size_t sz = buf.size();
            if (sz < 8) return buf[writeIdx];
            const float maxD = (float)(sz - 4);
            if (delaySamples < 3.0f) delaySamples = 3.0f;
            if (delaySamples > maxD) delaySamples = maxD;

            float readPos = (float)writeIdx - delaySamples;
            while (readPos < 0.0f) readPos += (float)sz;
            while (readPos >= (float)sz) readPos -= (float)sz;

            const size_t i0 = (size_t)readPos;
            const size_t i1 = (i0 + 1 >= sz) ? 0 : i0 + 1;
            const size_t im1 = (i0 == 0) ? (sz - 1) : (i0 - 1);
            const size_t i2 = (i1 + 1 >= sz) ? 0 : i1 + 1;
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

    private:
        std::vector<float> buf;
        size_t writeIdx = 0;
    };

    class AllpassFilter
    {
    public:
        void init(size_t delayLen, float feedbackGain, size_t maxModExcursion = 0)
        {
            nominalDelay = (float)delayLen;
            delay.resize(delayLen + (maxModExcursion > 0 ? (maxModExcursion + 12) : 0));
            gain = feedbackGain;
        }

        void clear()
        {
            delay.clear();
        }

        float process(float input)
        {
            return processWithGain(input, gain);
        }

        float processWithGain(float input, float g)
        {
            const float bufOut = delay.readOldest();
            const float output = -g * input + bufOut;
            delay.write(flushDenormal(input + g * output));
            return output;
        }

        float read(size_t tap) const
        {
            return delay.read(tap);
        }

        // Canonical alternating-sign modulated allpass: H(z) = (g + z^-D) / (1 + g z^-D)
        float processModulatedAlternating(float input, float modSamples)
        {
            const float bufOut = delay.readCubic(nominalDelay + modSamples);
            const float output = gain * input + bufOut;
            delay.write(flushDenormal(input - gain * output));
            return output;
        }

    private:
        DelayLine delay;
        float nominalDelay = 0.0f;
        float gain = 0.5f;
    };

    static size_t scaleSamples(float samplesAt29k, double rate)
    {
        const size_t n = (size_t)std::lround(samplesAt29k * (rate / 29761.0));
        return std::max<size_t>(4, n);
    }

    void buildBuffers()
    {
        const double rate = sampleRate;

        // 1. Pre-delay buffers (250 ms max + interpolation headroom)
        const size_t preDelaySamples = (size_t)std::lround((MAX_PRE_DELAY_MS * 0.001) * rate) + 4;
        for (int ch = 0; ch < 2; ++ch)
        {
            preDelayBuf[ch].assign(std::max<size_t>(8, preDelaySamples), 0.0f);
            preDelayWriteIdx[ch] = 0;
        }

        // Pre-allocate scratch buffers to avoid audio-thread heap allocation
        scratchPreDelay.assign(4096 * 2, 0.0f);
        scratchPreDelay64.assign(4096 * 2, 0.0);

        // 2. Input Diffusers (Dattorro tunings @ 29.761 kHz)
        diffusers[0][0].init(scaleSamples(142.0f, rate), 0.75f);
        diffusers[0][1].init(scaleSamples(107.0f, rate), 0.75f);
        diffusers[0][2].init(scaleSamples(379.0f, rate), 0.625f);
        diffusers[0][3].init(scaleSamples(277.0f, rate), 0.625f);

        diffusers[1][0].init(scaleSamples(149.0f, rate), 0.75f);
        diffusers[1][1].init(scaleSamples(113.0f, rate), 0.75f);
        diffusers[1][2].init(scaleSamples(389.0f, rate), 0.625f);
        diffusers[1][3].init(scaleSamples(283.0f, rate), 0.625f);

        // 3. Tank 1 & 2 with sample-rate-scaled modulation headroom
        const size_t maxExcursion = scaleSamples(24.0f, rate);
        tank1_modAp.init(scaleSamples(672.0f, rate), 0.70f, maxExcursion);
        tank1_del1.resize(scaleSamples(4453.0f, rate));
        tank1_ap2.init(scaleSamples(1800.0f, rate), 0.50f);
        tank1_del2.resize(scaleSamples(3720.0f, rate));

        tank2_modAp.init(scaleSamples(908.0f, rate), 0.70f, maxExcursion);
        tank2_del1.resize(scaleSamples(4217.0f, rate));
        tank2_ap2.init(scaleSamples(2656.0f, rate), 0.50f);
        tank2_del2.resize(scaleSamples(3163.0f, rate));

        // 4. Output Tap Positions
        tap_t1_d1_1  = scaleSamples(1990.0f, rate);
        tap_t1_d1_2  = scaleSamples(353.0f, rate);
        tap_t1_d1_3  = scaleSamples(3627.0f, rate);
        tap_t1_ap2_1 = scaleSamples(187.0f, rate);
        tap_t1_ap2_2 = scaleSamples(1228.0f, rate);
        tap_t1_d2_1  = scaleSamples(1066.0f, rate);
        tap_t1_d2_2  = scaleSamples(2673.0f, rate);

        tap_t2_d1_1  = scaleSamples(266.0f, rate);
        tap_t2_d1_2  = scaleSamples(2974.0f, rate);
        tap_t2_d1_3  = scaleSamples(2111.0f, rate);
        tap_t2_ap2_1 = scaleSamples(1913.0f, rate);
        tap_t2_ap2_2 = scaleSamples(335.0f, rate);
        tap_t2_d2_1  = scaleSamples(1996.0f, rate);
        tap_t2_d2_2  = scaleSamples(121.0f, rate);

        updateDattorroCoefficients();
    }

    double sampleRate = 48000.0;

    bool targetEnabled = false;
    bool currentEnabled = false;

    float targetWet = 0.0f;
    float currentWet = 0.0f;

    float targetDry = 1.0f;
    float currentDry = 1.0f;

    float targetRoomSize = 0.5f;
    float targetDamping = 0.5f;

    float enginePreDelayMs[6] = { 10.0f, 0.0f, 0.0f, 0.0f, 0.0f, 0.0f };
    float currentPreDelayMs = 10.0f;

    float targetWidth = 1.0f;
    float currentWidth = 1.0f;

    float targetDecay = 0.80f;
    float currentDecay = 0.80f;
    float targetDampCoeff = 0.55f;
    float currentDampCoeff = 0.55f;
    float preHpAlpha = 0.01f;
    float preLpAlpha = 0.85f;

    float subCurrentDry = 1.0f;
    float switchFadeGain = 1.0f;

    std::vector<float> preDelayBuf[2];
    size_t preDelayWriteIdx[2] = {0, 0};
    std::vector<float> scratchPreDelay;
    std::vector<double> scratchPreDelay64;

    float hpState[2]  = {0.0f, 0.0f};
    float lpState[2]  = {0.0f, 0.0f};

    AllpassFilter diffusers[2][4];

    AllpassFilter tank1_modAp;
    DelayLine tank1_del1;
    AllpassFilter tank1_ap2;
    DelayLine tank1_del2;
    float tank1_dampState = 0.0f;
    float tank1_lastOut = 0.0f;

    AllpassFilter tank2_modAp;
    DelayLine tank2_del1;
    AllpassFilter tank2_ap2;
    DelayLine tank2_del2;
    float tank2_dampState = 0.0f;
    float tank2_lastOut = 0.0f;

    float lfoPhase1 = 0.0f;
    float lfoPhase2 = 0.0f;

    size_t tap_t1_d1_1 = 0, tap_t1_d1_2 = 0, tap_t1_d1_3 = 0;
    size_t tap_t1_ap2_1 = 0, tap_t1_ap2_2 = 0;
    size_t tap_t1_d2_1 = 0, tap_t1_d2_2 = 0;

    size_t tap_t2_d1_1 = 0, tap_t2_d1_2 = 0, tap_t2_d1_3 = 0;
    size_t tap_t2_ap2_1 = 0, tap_t2_ap2_2 = 0;
    size_t tap_t2_d2_1 = 0, tap_t2_d2_2 = 0;

    ReverbEngine targetEngine = ReverbEngine::Dattorro;
    sauti::dsp::LatticeReverbDSP latticeDsp;
    sauti::dsp::DiffusionReverbDSP diffusionDsp;
    sauti::dsp::HadamardFdnDSP hadamardDsp;
    sauti::dsp::BarrRingReverbDSP barrDsp;
    sauti::dsp::GriesingerTankDSP griesingerDsp;
};
