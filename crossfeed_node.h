#pragma once

#include <cmath>
#include <cstdint>
#include <vector>
#include <algorithm>

enum class CrossfeedAlgorithm
{
    Off = 0,
    Simple = 1,
    BS2B = 2,
    Meier = 3,
    Natural = 4,
    RACE = 5
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
        updateCoefficients();
    }

    void setMix(float m)
    {
        targetMix = std::max(0.0f, std::min(m, 1.0f));
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
        if (targetAlgorithm == CrossfeedAlgorithm::Off || targetMix < 0.0001f)
        {
            return 0.0;
        }
        return (double)(targetDelayMs * 0.001f) * sampleRate;
    }

    void reset()
    {
        resetFiltersOnly();

        currentMix = targetMix;
        currentDelayMs = targetDelayMs;
        currentCutoffHz = targetCutoffHz;
        currentAlgorithm = targetAlgorithm;

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
    }

public:

    void process(float *interleavedStereo, uint32_t frames, int channels = 2)
    {
        if (!interleavedStereo || frames == 0 || channels < 2)
            return;

        if (targetAlgorithm == CrossfeedAlgorithm::Off && currentMix < 0.0001f)
        {
            currentAlgorithm = CrossfeedAlgorithm::Off;
            return;
        }

        constexpr float kTwoPi = 6.283185307179586f;
        const float alphaSmooth = 1.0f - std::exp(-1.0f / (0.010f * (float)sampleRate)); // 10ms smooth time

        for (uint32_t i = 0; i < frames; ++i)
        {
            // Smoothly interpolate parameters
            currentMix += alphaSmooth * (targetMix - currentMix);
            currentDelayMs += alphaSmooth * (targetDelayMs - currentDelayMs);
            currentCutoffHz += alphaSmooth * (targetCutoffHz - currentCutoffHz);

            // Algorithm switches are applied directly by setAlgorithm(); no
            // deferred switching here (the old currentMix < 0.001 gate meant
            // runtime changes never took effect with a normal mix level).

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
            const float inL = interleavedStereo[base];
            const float inR = interleavedStereo[base + 1];

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
                const float bs2bGain = bs2b_gain;

                // Low-pass filtered crossfeed path (inherently adds ~1/(2*pi*fcut) group delay)
                bs2bLoStateL = a0_lo * inL + b1_lo * bs2bLoStateL;
                bs2bLoStateR = a0_lo * inR + b1_lo * bs2bLoStateR;

                // High-pass filtered direct path
                const float hiL = a0_hi * inL + a1_hi * bs2bAsisL + b1_hi * bs2bHiStateL;
                const float hiR = a0_hi * inR + a1_hi * bs2bAsisR + b1_hi * bs2bHiStateR;
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

                // Combine direct high + cross low (delayed)
                float bs2bOutL = (hiL + delayedR) * bs2bGain;
                float bs2bOutR = (hiR + delayedL) * bs2bGain;

                // Blend dry and wet according to mix parameter
                outL = inL * (1.0f - currentMix) + bs2bOutL * currentMix;
                outR = inR * (1.0f - currentMix) + bs2bOutR * currentMix;
                break;
            }

            case CrossfeedAlgorithm::Meier:
            {
                // Jan Meier style crossfeed: 1-pole lowpass + direct treble boost + ITD delay
                const float lpfAlpha = meierLpfAlpha;
                lpfStateL[0] += lpfAlpha * (inL - lpfStateL[0]);
                lpfStateR[0] += lpfAlpha * (inR - lpfStateR[0]);

                const float crossL = lpfStateL[0];
                const float crossR = lpfStateR[0];

                // Direct channel gentle treble enhancement
                const float directL = inL + 0.15f * (inL - crossL);
                const float directR = inR + 0.15f * (inR - crossR);

                // Push lowpassed signal to delay buffer
                delayRingBufferL[writeIdx] = crossL;
                delayRingBufferR[writeIdx] = crossR;

                // Read fractional delayed low-pass sample
                const double readPos = (double)writeIdx + (double)MAX_DELAY_SAMPLES - clampedDelay;
                const size_t i0 = ((size_t)std::floor(readPos)) % MAX_DELAY_SAMPLES;
                const size_t i1 = (i0 + 1) % MAX_DELAY_SAMPLES;
                const float frac = (float)(readPos - std::floor(readPos));

                const float delayedL = (1.0f - frac) * delayRingBufferL[i0] + frac * delayRingBufferL[i1];
                const float delayedR = (1.0f - frac) * delayRingBufferR[i0] + frac * delayRingBufferR[i1];

                const float crossGain = currentMix * 0.35f;
                float meierComp = 1.0f;
                if (outputCompensationEnabled)
                {
                    meierComp = 1.0f / std::sqrt(1.0f + 0.0225f + crossGain * crossGain);
                }

                outL = (directL + crossGain * delayedR) * meierComp;
                outR = (directR + crossGain * delayedL) * meierComp;
                break;
            }

            case CrossfeedAlgorithm::Natural:
            {
                // Custom Natural Crossfeed: 2-pole Butterworth SVF + fractional delay + energy normalization
                const float a1 = svf_a1;
                const float a2 = svf_a2;
                const float a3 = svf_a3;

                // SVF LPF step
                float v3L = inL - lpfStateL[1];
                float v1L = a1 * lpfStateL[0] + a2 * v3L;
                float v2L = lpfStateL[1] + a2 * lpfStateL[0] + a3 * v3L;
                lpfStateL[0] = 2.0f * v1L - lpfStateL[0];
                lpfStateL[1] = 2.0f * v2L - lpfStateL[1];
                const float lpfOutL = v2L;

                float v3R = inR - lpfStateR[1];
                float v1R = a1 * lpfStateR[0] + a2 * v3R;
                float v2R = lpfStateR[1] + a2 * lpfStateR[0] + a3 * v3R;
                lpfStateR[0] = 2.0f * v1R - lpfStateR[0];
                lpfStateR[1] = 2.0f * v2R - lpfStateR[1];
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
                // Head-shadow 1-pole lowpass filter for contralateral cancellation signal
                constexpr double kPi = 3.14159265358979323846;
                const double x_race = std::exp(-2.0 * kPi * (double)currentCutoffHz / sampleRate);
                const float raceA0 = (float)(1.0 - x_race);
                const float raceB1 = (float)x_race;

                // Center-bass preservation filter (~160 Hz 1-pole lowpass on mid/mono signal)
                // Prevents the mono cancellation drop (1 / (1 + alpha)) from hollowing out bass
                const double x_bass = std::exp(-2.0 * kPi * 160.0 / sampleRate);
                const float bassA0 = (float)(1.0 - x_bass);
                const float bassB1 = (float)x_bass;
                const float midSignal = 0.5f * (inL + inR);
                raceBassState = bassA0 * midSignal + bassB1 * raceBassState;

                // Read sub-sample fractional delayed contralateral output from delay ring buffer
                const double readPos = (double)writeIdx + (double)MAX_DELAY_SAMPLES - clampedDelay;
                const size_t i0 = ((size_t)std::floor(readPos)) % MAX_DELAY_SAMPLES;
                const size_t i1 = (i0 + 1) % MAX_DELAY_SAMPLES;
                const float frac = (float)(readPos - std::floor(readPos));

                const float delayedOutL = (1.0f - frac) * delayRingBufferL[i0] + frac * delayRingBufferL[i1];
                const float delayedOutR = (1.0f - frac) * delayRingBufferR[i0] + frac * delayRingBufferR[i1];

                // Low-pass filter the delayed contralateral signals (head shadow modeling)
                raceLpfOutR = raceA0 * delayedOutR + raceB1 * raceLpfOutR;
                raceLpfOutL = raceA0 * delayedOutL + raceB1 * raceLpfOutL;

                // Subtract contralateral crosstalk (anti-phase) with center-bass reinforcement
                const float alpha = currentMix;
                float rawOutL = inL - alpha * raceLpfOutR + (alpha * 0.35f) * raceBassState;
                float rawOutR = inR - alpha * raceLpfOutL + (alpha * 0.35f) * raceBassState;

                // Output headroom compensation: keeps RMS energy balanced without distortion
                if (outputCompensationEnabled)
                {
                    const float raceComp = 1.0f / std::sqrt(1.0f + 0.60f * alpha * alpha);
                    rawOutL *= raceComp;
                    rawOutR *= raceComp;
                }

                // Transparent soft-knee safety clamp: 100% linear up to 0.98f; smoothly saturates any overs
                if (std::abs(rawOutL) > 0.98f)
                {
                    const float sign = (rawOutL > 0.0f) ? 1.0f : -1.0f;
                    const float excess = std::abs(rawOutL) - 0.98f;
                    rawOutL = sign * (0.98f + 0.02f * std::tanh(excess / 0.02f));
                }
                if (std::abs(rawOutR) > 0.98f)
                {
                    const float sign = (rawOutR > 0.0f) ? 1.0f : -1.0f;
                    const float excess = std::abs(rawOutR) - 0.98f;
                    rawOutR = sign * (0.98f + 0.02f * std::tanh(excess / 0.02f));
                }

                outL = rawOutL;
                outR = rawOutR;

                // Feed back outputs into ring buffer for recursive cancellation
                delayRingBufferL[writeIdx] = outL;
                delayRingBufferR[writeIdx] = outR;
                break;
            }

            default:
                outL = inL;
                outR = inR;
                break;
            }

            interleavedStereo[base] = outL;
            interleavedStereo[base + 1] = outR;

            writeIdx = (writeIdx + 1) % MAX_DELAY_SAMPLES;
        }
    }

private:
    void updateCoefficients()
    {
        constexpr double pi = 3.14159265358979323846;
        const double fcut = (double)currentCutoffHz;
        const double feed = (double)(currentMix * 6.5f + 3.0f); // Map 0..1 mix to 3.0..9.5 dB feed

        const double level = feed / 10.0;
        const double gb_lo = level * -5.0 / 6.0 - 3.0;
        const double gb_hi = level / 6.0 - 3.0;

        const double g_lo = std::pow(10.0, gb_lo / 20.0);
        const double g_hi = 1.0 - std::pow(10.0, gb_hi / 20.0);
        const double fc_hi = fcut * std::pow(2.0, (gb_lo - 20.0 * std::log10(g_hi)) / 12.0);

        double x = std::exp(-2.0 * pi * fcut / sampleRate);
        bs2b_b1_lo = (float)x;
        bs2b_a0_lo = (float)(g_lo * (1.0 - x));

        x = std::exp(-2.0 * pi * fc_hi / sampleRate);
        bs2b_b1_hi = (float)x;
        bs2b_a0_hi = (float)(1.0 - g_hi * (1.0 - x));
        bs2b_a1_hi = (float)(-x);

        bs2b_gain = (float)(1.0 / (1.0 - g_hi + g_lo));

        // Jan Meier bilinear transform coefficients
        const double w_meier = std::tan(pi * fcut / sampleRate);
        meierLpfAlpha = (float)(w_meier / (1.0 + w_meier));

        // Custom Natural 2-pole Butterworth SVF coefficients
        const double g_nat = std::tan(pi * fcut / sampleRate);
        constexpr double k_nat = 1.4142135623730951; // Q = 0.7071
        const double a1_nat = 1.0 / (1.0 + g_nat * (g_nat + k_nat));
        const double a2_nat = g_nat * a1_nat;
        const double a3_nat = g_nat * a2_nat;
        svf_a1 = (float)a1_nat;
        svf_a2 = (float)a2_nat;
        svf_a3 = (float)a3_nat;

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

    // RACE filter states
    float raceLpfOutL = 0.0f;
    float raceLpfOutR = 0.0f;
    float raceBassState = 0.0f;

    // Cached filter coefficients
    float meierLpfAlpha = 0.0f;
    float svf_a1 = 0.0f;
    float svf_a2 = 0.0f;
    float svf_a3 = 0.0f;
};
