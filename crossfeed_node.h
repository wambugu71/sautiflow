#pragma once

#include <cmath>
#include <cstdint>
#include <vector>
#include <algorithm>
#include "dsp/denormals.h"
#include "dsp/open_stage_dsp.h"

enum class CrossfeedAlgorithm
{
    Off = 0,
    Simple = 1,
    BS2B = 2,
    Meier = 3,
    Natural = 4,
    RACE = 5,
    OpenStage = 6
};

class CrossfeedNode
{
public:
    static constexpr size_t MAX_DELAY_SAMPLES = 4096; // ~21.3ms at 192kHz per channel

    CrossfeedNode()
    {
        setSampleRate(48000.0);
        reset();
    }

    void setAlgorithm(CrossfeedAlgorithm algo)
    {
        if (targetAlgorithm == algo)
            return;
        targetAlgorithm = algo;
        // Switch immediately. The previous logic deferred the switch until
        // currentMix < 0.001, which (with any normal mix setting) meant a
        // runtime algorithm change was silently ignored forever.
        // Reset only the per-algorithm filter/delay state so stale samples
        // from the old topology are not smeared into the new one.
        resetFiltersOnly();
        currentAlgorithm = targetAlgorithm;
        updateCoefficients();
    }

    void setSampleRate(double rate)
    {
        if (rate <= 0.0)
            rate = 48000.0;
        if (std::abs(sampleRate - rate) < 0.1)
            return;

        sampleRate = rate;
        openStage.setSampleRate(rate);
        updateCoefficients();
    }

    void setMix(float m)
    {
        targetMix = std::max(0.0f, std::min(m, 1.0f));
        openStage.setMix(targetMix);
    }

    void setDelayMs(float dMs)
    {
        targetDelayMs = std::max(0.02f, std::min(dMs, 5.0f));
    }

    void setCutoffHz(float cutoff)
    {
        targetCutoffHz = std::max(100.0f, std::min(cutoff, 16000.0f));
    }

    void setOutputCompensation(bool enabled)
    {
        outputCompensationEnabled = enabled;
    }

    void setAngle(float degrees)
    {
        openStage.setAngle(degrees);
    }

    float getAngle() const
    {
        return openStage.getAngle();
    }

    void setGainDb(float gainDb)
    {
        openStage.setGainDb(gainDb);
    }

    float getGainDb() const
    {
        return openStage.getGainDb();
    }

    void setRaceParams(float delayMs, float alpha, float lpfHz)
    {
        setDelayMs(delayMs);
        setMix(alpha);
        setCutoffHz(lpfHz);
    }

    CrossfeedAlgorithm getAlgorithm() const { return targetAlgorithm; }
    float getMix() const { return targetMix; }
    float getDelayMs() const { return targetDelayMs; }
    float getCutoffHz() const { return targetCutoffHz; }
    bool getOutputCompensation() const { return outputCompensationEnabled; }

    double getLatencySamples() const
    {
        if (currentAlgorithm == CrossfeedAlgorithm::Off || currentMix < 0.0001f)
        {
            return 0.0;
        }
        if (currentAlgorithm == CrossfeedAlgorithm::OpenStage)
        {
            return openStage.getItdSeconds() * sampleRate;
        }
        return (double)(currentDelayMs * 0.001f) * sampleRate;
    }

    void reset()
    {
        resetFiltersOnly();

        currentMix = targetMix;
        currentDelayMs = targetDelayMs;
        currentCutoffHz = targetCutoffHz;
        currentAlgorithm = targetAlgorithm;
        openStage.reset();

        updateCoefficients();
    }

private:
    void resetFiltersOnly()
    {
        std::fill(delayRingBufferL, delayRingBufferL + MAX_DELAY_SAMPLES, 0.0f);
        std::fill(delayRingBufferR, delayRingBufferR + MAX_DELAY_SAMPLES, 0.0f);
        writeIdx = 0;

        lpfStateL[0] = lpfStateL[1] = 0.0f;
        lpfStateR[0] = lpfStateR[1] = 0.0f;
        directHpfStateL = directHpfStateR = 0.0f;
        bs2bAsisL = bs2bAsisR = 0.0f;
        bs2bHiStateL = bs2bHiStateR = 0.0f;
        bs2bLoStateL = bs2bLoStateR = 0.0f;

        raceLpfOutL = raceLpfOutR = 0.0f;
        raceBassState = 0.0f;
        openStage.reset();
    }

public:
    template <typename SampleT>
    void process(SampleT *interleavedStereo, uint32_t frames, int channels = 2)
    {
        if (!interleavedStereo || frames == 0 || channels < 2)
            return;

        if (targetAlgorithm == CrossfeedAlgorithm::Off && currentMix < 0.0001f)
        {
            currentAlgorithm = CrossfeedAlgorithm::Off;
            return;
        }

        sauti::dsp::ScopedDenormalsDisable denormalsScope;

        const float alphaSmooth = 1.0f - std::exp(-1.0f / (0.010f * (float)sampleRate)); // 10ms smooth time

        for (uint32_t i = 0; i < frames; ++i)
        {
            // Smoothly interpolate parameters
            currentMix += alphaSmooth * (targetMix - currentMix);
            currentDelayMs += alphaSmooth * (targetDelayMs - currentDelayMs);
            currentCutoffHz += alphaSmooth * (targetCutoffHz - currentCutoffHz);

            if (currentAlgorithm == CrossfeedAlgorithm::Off)
            {
                continue;
            }

            // Recalculate coefficients if smoothed cutoff/mix changed significantly
            if (std::abs(lastCoeffCutoff - currentCutoffHz) > 0.05f || std::abs(lastCoeffMix - currentMix) > 0.001f)
            {
                updateCoefficients();
            }

            const size_t base = (size_t)i * (size_t)channels;
            const float inL = static_cast<float>(interleavedStereo[base]);
            const float inR = static_cast<float>(interleavedStereo[base + 1]);

            // Fractional delay calculation in samples
            const double delaySamples = (double)(currentDelayMs * 0.001f) * sampleRate;
            const double clampedDelay = std::max(0.01, std::min(delaySamples, (double)(MAX_DELAY_SAMPLES - 2)));

            float outL = inL;
            float outR = inR;

            switch (currentAlgorithm)
            {
            case CrossfeedAlgorithm::Simple:
            {
                // Simple Reference: Pure fractional ITD delay line + linear crossfeed
                delayRingBufferL[writeIdx] = inL;
                delayRingBufferR[writeIdx] = inR;

                const double readPos = (double)writeIdx + (double)MAX_DELAY_SAMPLES - clampedDelay;
                const size_t i0 = ((size_t)std::floor(readPos)) % MAX_DELAY_SAMPLES;
                const size_t i1 = (i0 + 1) % MAX_DELAY_SAMPLES;
                const float frac = (float)(readPos - std::floor(readPos));

                const float delayedL = (1.0f - frac) * delayRingBufferL[i0] + frac * delayRingBufferL[i1];
                const float delayedR = (1.0f - frac) * delayRingBufferR[i0] + frac * delayRingBufferR[i1];

                const float crossGain = currentMix * 0.30f;
                float directGain = 1.0f;
                if (outputCompensationEnabled)
                {
                    directGain = 1.0f / std::sqrt(1.0f + crossGain * crossGain);
                }

                outL = directGain * inL + crossGain * delayedR;
                outR = directGain * inR + crossGain * delayedL;
                break;
            }

            case CrossfeedAlgorithm::BS2B:
            {
                // Bauer BS2B algorithm with exact libbs2b coefficients
                const float a0_lo = bs2b_a0_lo;
                const float b1_lo = bs2b_b1_lo;
                const float a0_hi = bs2b_a0_hi;
                const float a1_hi = bs2b_a1_hi;
                const float b1_hi = bs2b_b1_hi;
                const float bs2bGain = outputCompensationEnabled ? bs2b_gain : 1.0f;

                // Low-pass filtered crossfeed path (inherently adds ~1/(2*pi*fcut) group delay)
                bs2bLoStateL = sauti::dsp::sanitizeSample(a0_lo * inL + b1_lo * bs2bLoStateL);
                bs2bLoStateR = sauti::dsp::sanitizeSample(a0_lo * inR + b1_lo * bs2bLoStateR);

                // High-pass filtered direct path
                const float hiL = sauti::dsp::sanitizeSample(a0_hi * inL + a1_hi * bs2bAsisL + b1_hi * bs2bHiStateL);
                const float hiR = sauti::dsp::sanitizeSample(a0_hi * inR + a1_hi * bs2bAsisR + b1_hi * bs2bHiStateR);
                bs2bAsisL = inL;
                bs2bAsisR = inR;
                bs2bHiStateL = hiL;
                bs2bHiStateR = hiR;

                // Push low-pass filtered signal into delay ring buffer
                delayRingBufferL[writeIdx] = bs2bLoStateL;
                delayRingBufferR[writeIdx] = bs2bLoStateR;

                // Supplemental delay: subtract filter group delay so total ITD precisely matches currentDelayMs
                constexpr double kTwoPi = 6.283185307179586;
                const double filterDelayMs = 1000.0 / (kTwoPi * (double)currentCutoffHz);
                const double extraDelayMs = std::max(0.0, (double)currentDelayMs - filterDelayMs);
                const double extraDelaySamples = (extraDelayMs * 0.001) * sampleRate;
                const double clampedExtraDelay = std::max(0.0, std::min(extraDelaySamples, (double)(MAX_DELAY_SAMPLES - 2)));

                const double readPos = (double)writeIdx + (double)MAX_DELAY_SAMPLES - clampedExtraDelay;
                const size_t i0 = ((size_t)std::floor(readPos)) % MAX_DELAY_SAMPLES;
                const size_t i1 = (i0 + 1) % MAX_DELAY_SAMPLES;
                const float frac = (float)(readPos - std::floor(readPos));

                const float delayedL = (1.0f - frac) * delayRingBufferL[i0] + frac * delayRingBufferL[i1];
                const float delayedR = (1.0f - frac) * delayRingBufferR[i0] + frac * delayRingBufferR[i1];

                // Combine direct high-shelf + cross low-pass (delayed)
                // Note: updateCoefficients() already scales g_lo and g_hi smoothly by currentMix
                // (so currentMix = 0 yields g_lo = 0, g_hi = 0, bs2b_gain = 1.0 -> exact bypass).
                // Avoiding a second linear dry/wet mix eliminates high-frequency phase comb filtering!
                outL = (hiL + delayedR) * bs2bGain;
                outR = (hiR + delayedL) * bs2bGain;
                break;
            }

            case CrossfeedAlgorithm::Meier:
            {
                // Jan Meier natural crossfeed: 1-pole RC lowpass (exact -3dB at currentCutoffHz)
                // + complementary direct high-shelf enhancement + ITD delay compensation
                const float lpfAlpha = meierLpfAlpha;
                lpfStateL[0] = sauti::dsp::sanitizeSample(lpfStateL[0] + lpfAlpha * (inL - lpfStateL[0]));
                lpfStateR[0] = sauti::dsp::sanitizeSample(lpfStateR[0] + lpfAlpha * (inR - lpfStateR[0]));

                const float crossL = lpfStateL[0];
                const float crossR = lpfStateR[0];

                const float crossGain = currentMix * 0.35f;

                // Direct channel complementary treble preservation (maintains flat diffuse-field power)
                const float highBoost = crossGain * 0.50f;
                const float directL = inL + highBoost * (inL - crossL);
                const float directR = inR + highBoost * (inR - crossR);

                // Push lowpassed signal to delay buffer
                delayRingBufferL[writeIdx] = crossL;
                delayRingBufferR[writeIdx] = crossR;

                // Compensate for the 1-pole RC filter's intrinsic low-frequency group delay (~1/(2*pi*fc))
                constexpr double kTwoPi = 6.283185307179586;
                const double filterDelayMs = 1000.0 / (kTwoPi * (double)currentCutoffHz);
                const double extraDelayMs = std::max(0.0, (double)currentDelayMs - filterDelayMs);
                const double extraDelaySamples = (extraDelayMs * 0.001) * sampleRate;
                const double clampedMeierDelay = std::max(0.0, std::min(extraDelaySamples, (double)(MAX_DELAY_SAMPLES - 2)));

                // Read fractional delayed low-pass sample
                const double readPos = (double)writeIdx + (double)MAX_DELAY_SAMPLES - clampedMeierDelay;
                const size_t i0 = ((size_t)std::floor(readPos)) % MAX_DELAY_SAMPLES;
                const size_t i1 = (i0 + 1) % MAX_DELAY_SAMPLES;
                const float frac = (float)(readPos - std::floor(readPos));

                const float delayedL = (1.0f - frac) * delayRingBufferL[i0] + frac * delayRingBufferL[i1];
                const float delayedR = (1.0f - frac) * delayRingBufferR[i0] + frac * delayRingBufferR[i1];

                float meierComp = 1.0f;
                if (outputCompensationEnabled)
                {
                    meierComp = 1.0f / std::sqrt(1.0f + highBoost * highBoost + crossGain * crossGain);
                }

                outL = (directL + crossGain * delayedR) * meierComp;
                outR = (directR + crossGain * delayedL) * meierComp;
                break;
            }

            case CrossfeedAlgorithm::Natural:
            {
                // Custom Natural Crossfeed: 2-pole Butterworth TPT SVF + fractional delay + energy normalization
                const float a1 = svf_a1;
                const float a2 = svf_a2;
                const float a3 = svf_a3;

                // SVF LPF step
                float v3L = inL - lpfStateL[1];
                float v1L = a1 * lpfStateL[0] + a2 * v3L;
                float v2L = lpfStateL[1] + a2 * lpfStateL[0] + a3 * v3L;
                lpfStateL[0] = sauti::dsp::sanitizeSample(2.0f * v1L - lpfStateL[0]);
                lpfStateL[1] = sauti::dsp::sanitizeSample(2.0f * v2L - lpfStateL[1]);
                const float lpfOutL = v2L;

                float v3R = inR - lpfStateR[1];
                float v1R = a1 * lpfStateR[0] + a2 * v3R;
                float v2R = lpfStateR[1] + a2 * lpfStateR[0] + a3 * v3R;
                lpfStateR[0] = sauti::dsp::sanitizeSample(2.0f * v1R - lpfStateR[0]);
                lpfStateR[1] = sauti::dsp::sanitizeSample(2.0f * v2R - lpfStateR[1]);
                const float lpfOutR = v2R;

                // Push LPF output to fractional delay buffer
                delayRingBufferL[writeIdx] = lpfOutL;
                delayRingBufferR[writeIdx] = lpfOutR;

                // Read fractional delayed LPF sample
                const double readPos = (double)writeIdx + (double)MAX_DELAY_SAMPLES - clampedDelay;
                const size_t i0 = ((size_t)std::floor(readPos)) % MAX_DELAY_SAMPLES;
                const size_t i1 = (i0 + 1) % MAX_DELAY_SAMPLES;
                const float frac = (float)(readPos - std::floor(readPos));

                const float delayedL = (1.0f - frac) * delayRingBufferL[i0] + frac * delayRingBufferL[i1];
                const float delayedR = (1.0f - frac) * delayRingBufferR[i0] + frac * delayRingBufferR[i1];

                const float crossGain = currentMix * 0.30f;
                float directGain = 1.0f;
                if (outputCompensationEnabled)
                {
                    directGain = 1.0f / std::sqrt(1.0f + crossGain * crossGain);
                }

                outL = directGain * inL + crossGain * delayedR;
                outR = directGain * inR + crossGain * delayedL;
                break;
            }

            case CrossfeedAlgorithm::RACE:
            {
                // Ambiophonics R.A.C.E. (Recursive Ambiophonic Crosstalk Elimination)
                // Uses cached 1-pole head-shadow and center-bass coefficients from updateCoefficients()
                const float midSignal = 0.5f * (inL + inR);
                raceBassState = sauti::dsp::sanitizeSample(raceBassA0 * midSignal + raceBassB1 * raceBassState);

                // Read sub-sample fractional delayed contralateral recursive state from delay ring buffer
                const double readPos = (double)writeIdx + (double)MAX_DELAY_SAMPLES - clampedDelay;
                const size_t i0 = ((size_t)std::floor(readPos)) % MAX_DELAY_SAMPLES;
                const size_t i1 = (i0 + 1) % MAX_DELAY_SAMPLES;
                const float frac = (float)(readPos - std::floor(readPos));

                const float delayedOutL = (1.0f - frac) * delayRingBufferL[i0] + frac * delayRingBufferL[i1];
                const float delayedOutR = (1.0f - frac) * delayRingBufferR[i0] + frac * delayRingBufferR[i1];

                // Low-pass filter the delayed contralateral signals (head shadow modeling)
                raceLpfOutR = sauti::dsp::sanitizeSample(raceA0 * delayedOutR + raceB1 * raceLpfOutR);
                raceLpfOutL = sauti::dsp::sanitizeSample(raceA0 * delayedOutL + raceB1 * raceLpfOutL);

                // Subtract contralateral crosstalk (anti-phase) with center-bass reinforcement
                // Clamp recursive feedback factor to <= 0.92 for unconditional IIR stability
                const float alpha = std::min(currentMix, 0.92f);
                float recL = inL - alpha * raceLpfOutR + (alpha * 0.35f) * raceBassState;
                float recR = inR - alpha * raceLpfOutL + (alpha * 0.35f) * raceBassState;

                // Soft-knee safety clamp on recursive state to prevent runaway feedback
                if (std::abs(recL) > 0.98f)
                {
                    const float sign = (recL > 0.0f) ? 1.0f : -1.0f;
                    const float excess = std::abs(recL) - 0.98f;
                    recL = sign * (0.98f + 0.02f * std::tanh(excess / 0.02f));
                }
                if (std::abs(recR) > 0.98f)
                {
                    const float sign = (recR > 0.0f) ? 1.0f : -1.0f;
                    const float excess = std::abs(recR) - 0.98f;
                    recR = sign * (0.98f + 0.02f * std::tanh(excess / 0.02f));
                }

                // Feed back unattenuated recursive state into ring buffer so output compensation
                // does not weaken the effective cancellation factor alpha
                delayRingBufferL[writeIdx] = recL;
                delayRingBufferR[writeIdx] = recR;

                // Apply output headroom compensation outside the recursive loop
                if (outputCompensationEnabled)
                {
                    const float raceComp = 1.0f / std::sqrt(1.0f + 0.60f * alpha * alpha);
                    outL = recL * raceComp;
                    outR = recR * raceComp;
                }
                else
                {
                    outL = recL;
                    outR = recR;
                }
                break;
            }

            case CrossfeedAlgorithm::OpenStage:
            {
                openStage.setMixImmediate(currentMix);
                openStage.processSample(inL, inR, outL, outR);
                break;
            }

            default:
                outL = inL;
                outR = inR;
                break;
            }

            interleavedStereo[base] = static_cast<SampleT>(outL);
            interleavedStereo[base + 1] = static_cast<SampleT>(outR);

            writeIdx = (writeIdx + 1) % MAX_DELAY_SAMPLES;
        }
    }

private:
    void updateCoefficients()
    {
        constexpr double pi = 3.14159265358979323846;
        const double fcut = (double)currentCutoffHz;
        const double mix = std::clamp((double)currentMix, 0.0, 1.0);
        const double feed = mix * 6.5 + 3.0; // Map 0..1 mix to 3.0..9.5 dB feed

        const double level = feed / 10.0;
        const double gb_lo = level * -5.0 / 6.0 - 3.0;
        const double gb_hi = level / 6.0 - 3.0;

        // Scale BS2B crossfeed and high-boost gains smoothly by mix so mix=0 is exact unity bypass
        // without requiring a parallel dry/wet blend that would cause high-shelf phase comb filtering
        const double g_lo_full = std::pow(10.0, gb_lo / 20.0);
        const double g_hi_full = 1.0 - std::pow(10.0, gb_hi / 20.0);
        const double g_lo = g_lo_full * mix;
        const double g_hi = g_hi_full * mix;
        const double fc_hi = fcut * std::pow(2.0, (gb_lo - 20.0 * std::log10(std::max(1.0e-6, g_hi_full))) / 12.0);

        double x = std::exp(-2.0 * pi * fcut / sampleRate);
        bs2b_b1_lo = (float)x;
        bs2b_a0_lo = (float)(g_lo * (1.0 - x));

        x = std::exp(-2.0 * pi * fc_hi / sampleRate);
        bs2b_b1_hi = (float)x;
        bs2b_a0_hi = (float)(1.0 - g_hi * (1.0 - x));
        bs2b_a1_hi = (float)(-x);

        bs2b_gain = (float)(1.0 / (1.0 - g_hi + g_lo));

        // Jan Meier exact 1-pole matched-Z coefficient (-3 dB at fcut)
        // Note: Using w/(1+w) without a (z+1) numerator halved the -3 dB cutoff to 0.5*fcut.
        meierLpfAlpha = (float)(1.0 - std::exp(-2.0 * pi * fcut / sampleRate));

        // Custom Natural 2-pole Butterworth SVF coefficients
        const double g_nat = std::tan(pi * fcut / sampleRate);
        constexpr double k_nat = 1.4142135623730951; // Q = 0.7071
        const double a1_nat = 1.0 / (1.0 + g_nat * (g_nat + k_nat));
        const double a2_nat = g_nat * a1_nat;
        const double a3_nat = g_nat * a2_nat;
        svf_a1 = (float)a1_nat;
        svf_a2 = (float)a2_nat;
        svf_a3 = (float)a3_nat;

        // Precompute RACE 1-pole head-shadow and center-bass coefficients (avoids per-sample std::exp)
        const double x_race = std::exp(-2.0 * pi * fcut / sampleRate);
        raceA0 = (float)(1.0 - x_race);
        raceB1 = (float)x_race;

        const double x_bass = std::exp(-2.0 * pi * 160.0 / sampleRate);
        raceBassA0 = (float)(1.0 - x_bass);
        raceBassB1 = (float)x_bass;

        lastCoeffCutoff = currentCutoffHz;
        lastCoeffMix = currentMix;
    }

    double sampleRate = 48000.0;
    CrossfeedAlgorithm targetAlgorithm = CrossfeedAlgorithm::Off;
    CrossfeedAlgorithm currentAlgorithm = CrossfeedAlgorithm::Off;

    float targetMix = 0.5f;
    float currentMix = 0.5f;

    float targetDelayMs = 0.40f; // Default ~0.4ms ITD
    float currentDelayMs = 0.40f;

    float targetCutoffHz = 700.0f; // Default 700Hz
    float currentCutoffHz = 700.0f;

    float lastCoeffCutoff = 0.0f;
    float lastCoeffMix = -1.0f;

    bool outputCompensationEnabled = true;

    // Delay ring buffers
    float delayRingBufferL[MAX_DELAY_SAMPLES] = {};
    float delayRingBufferR[MAX_DELAY_SAMPLES] = {};
    size_t writeIdx = 0;

    // Filter states
    float lpfStateL[2] = {};
    float lpfStateR[2] = {};
    float directHpfStateL = 0.0f;
    float directHpfStateR = 0.0f;

    // BS2B filter states
    float bs2b_a0_lo = 0.0f;
    float bs2b_b1_lo = 0.0f;
    float bs2b_a0_hi = 0.0f;
    float bs2b_a1_hi = 0.0f;
    float bs2b_b1_hi = 0.0f;
    float bs2b_gain = 1.0f;
    float bs2bAsisL = 0.0f;
    float bs2bAsisR = 0.0f;
    float bs2bHiStateL = 0.0f;
    float bs2bHiStateR = 0.0f;
    float bs2bLoStateL = 0.0f;
    float bs2bLoStateR = 0.0f;

    // RACE filter states and cached coefficients
    float raceLpfOutL = 0.0f;
    float raceLpfOutR = 0.0f;
    float raceBassState = 0.0f;
    float raceA0 = 0.0f;
    float raceB1 = 0.0f;
    float raceBassA0 = 0.0f;
    float raceBassB1 = 0.0f;

    // Cached filter coefficients
    float meierLpfAlpha = 0.0f;
    float svf_a1 = 0.0f;
    float svf_a2 = 0.0f;
    float svf_a3 = 0.0f;

    // OpenStage DSP engine
    sauti::dsp::OpenStageDSP openStage;
};
