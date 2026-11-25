#pragma once

#include <cmath>
#include <cstdint>
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
    static constexpr size_t MAX_DELAY_SAMPLES = 1024; // ~5.33ms at 192kHz per channel (power of 2)
    static constexpr size_t DELAY_MASK = MAX_DELAY_SAMPLES - 1;

    CrossfeedNode()
    {
        setSampleRate(48000.0);
        reset();
    }

    void setAlgorithm(CrossfeedAlgorithm algo)
    {
        if (algo == CrossfeedAlgorithm::Off)
        {
            targetAlgorithm = CrossfeedAlgorithm::Off;
            enabled_ = false;
            targetBypassWet_ = 0.0;
            return;
        }

        if (targetAlgorithm == algo && enabled_)
            return;

        if (activeAlgorithm != algo)
        {
            resetFiltersOnly();
            activeAlgorithm = algo;
        }
        targetAlgorithm = algo;
        enabled_ = true;
        targetBypassWet_ = 1.0;
        forceCoeffUpdate_ = true;
        updateCoefficients();
    }

    void setEnabled(bool enabled)
    {
        enabled_ = enabled;
        if (!enabled)
        {
            targetBypassWet_ = 0.0;
        }
        else if (targetAlgorithm != CrossfeedAlgorithm::Off)
        {
            if (activeAlgorithm != targetAlgorithm)
            {
                resetFiltersOnly();
                activeAlgorithm = targetAlgorithm;
            }
            targetBypassWet_ = 1.0;
            forceCoeffUpdate_ = true;
            updateCoefficients();
        }
    }

    bool isEnabled() const
    {
        return enabled_ && targetAlgorithm != CrossfeedAlgorithm::Off;
    }

    bool isActive() const
    {
        return isEnabled() || (activeAlgorithm != CrossfeedAlgorithm::Off && currentBypassWet_ > 1.0e-4);
    }

    void setSampleRate(double rate)
    {
        if (rate <= 0.0)
            rate = 48000.0;
        if (std::abs(sampleRate - rate) < 0.1)
            return;

        sampleRate = rate;
        alphaSmooth_ = 1.0 - std::exp(-1.0 / (0.010 * sampleRate)); // 10ms smooth time
        openStage.setSampleRate(rate);
        forceCoeffUpdate_ = true;
        updateCoefficients();
    }

    void setMix(float m)
    {
        targetMix = static_cast<double>(std::clamp(m, 0.0f, 1.0f));
        openStage.setMix(static_cast<float>(targetMix));
    }

    void setDelayMs(float dMs)
    {
        targetDelayMs = static_cast<double>(std::clamp(dMs, 0.02f, 5.0f));
    }

    void setCutoffHz(float cutoff)
    {
        targetCutoffHz = static_cast<double>(std::clamp(cutoff, 100.0f, 16000.0f));
    }

    void setOutputCompensation(bool enabled)
    {
        if (outputCompensationEnabled != enabled)
        {
            outputCompensationEnabled = enabled;
            forceCoeffUpdate_ = true;
            updateCoefficients();
        }
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
        targetRaceDelayMs = static_cast<double>(std::clamp(delayMs, 0.02f, 2.0f));
        targetRaceAlpha = static_cast<double>(std::clamp(alpha, 0.0f, 1.0f));
        targetRaceLpfHz = static_cast<double>(std::clamp(lpfHz, 200.0f, 16000.0f));
    }

    CrossfeedAlgorithm getAlgorithm() const { return targetAlgorithm; }

    float getMix() const
    {
        return static_cast<float>((targetAlgorithm == CrossfeedAlgorithm::RACE) ? targetRaceAlpha : targetMix);
    }

    float getDelayMs() const
    {
        return static_cast<float>((targetAlgorithm == CrossfeedAlgorithm::RACE) ? targetRaceDelayMs : targetDelayMs);
    }

    float getCutoffHz() const
    {
        return static_cast<float>((targetAlgorithm == CrossfeedAlgorithm::RACE) ? targetRaceLpfHz : targetCutoffHz);
    }

    bool getOutputCompensation() const { return outputCompensationEnabled; }
    float getOpenStageItdMs() const { return openStage.getItdMs(); }
    float getOpenStageCutoffHz() const { return openStage.getHeadShadowCutoffHz(); }

    // Direct (ipsilateral) signal passes with zero algorithmic delay;
    // ITD is only applied on the contralateral path.
    double getLatencySamples() const
    {
        return 0.0;
    }

    void reset()
    {
        resetFiltersOnly();

        currentMix = targetMix;
        currentDelayMs = targetDelayMs;
        currentCutoffHz = targetCutoffHz;
        currentRaceDelayMs = targetRaceDelayMs;
        currentRaceAlpha = targetRaceAlpha;
        currentRaceLpfHz = targetRaceLpfHz;
        currentBypassWet_ = targetBypassWet_;
        activeAlgorithm = targetAlgorithm;
        openStage.reset();

        forceCoeffUpdate_ = true;
        updateCoefficients();
    }

private:
    void resetFiltersOnly()
    {
        std::fill(delayRingBufferL, delayRingBufferL + MAX_DELAY_SAMPLES, 0.0);
        std::fill(delayRingBufferR, delayRingBufferR + MAX_DELAY_SAMPLES, 0.0);
        writeIdx = 0;

        lpfStateL[0] = lpfStateL[1] = 0.0;
        lpfStateR[0] = lpfStateR[1] = 0.0;
        bs2bAsisL = bs2bAsisR = 0.0;
        bs2bHiStateL = bs2bHiStateR = 0.0;
        bs2bLoStateL = bs2bLoStateR = 0.0;

        raceLpfOutL = raceLpfOutR = 0.0;
        raceHpfStateL[0] = raceHpfStateL[1] = 0.0;
        raceHpfStateR[0] = raceHpfStateR[1] = 0.0;
        openStage.reset();
    }

public:
    template <typename SampleT>
    void process(SampleT *interleavedStereo, uint32_t frames, int channels = 2)
    {
        if (!interleavedStereo || frames == 0 || channels < 2)
            return;

        if (!isActive())
        {
            if (activeAlgorithm != CrossfeedAlgorithm::Off && currentBypassWet_ <= 1.0e-4)
            {
                currentBypassWet_ = 0.0;
                activeAlgorithm = CrossfeedAlgorithm::Off;
                resetFiltersOnly();
            }
            return;
        }

        sauti::dsp::ScopedDenormalsDisable denormalsScope;

        switch (activeAlgorithm)
        {
        case CrossfeedAlgorithm::Simple:
            processSimple(interleavedStereo, frames, channels);
            break;
        case CrossfeedAlgorithm::BS2B:
            processBS2B(interleavedStereo, frames, channels);
            break;
        case CrossfeedAlgorithm::Meier:
            processMeier(interleavedStereo, frames, channels);
            break;
        case CrossfeedAlgorithm::Natural:
            processNatural(interleavedStereo, frames, channels);
            break;
        case CrossfeedAlgorithm::RACE:
            processRace(interleavedStereo, frames, channels);
            break;
        case CrossfeedAlgorithm::OpenStage:
            processOpenStage(interleavedStereo, frames, channels);
            break;
        case CrossfeedAlgorithm::Off:
        default:
            break;
        }

        if (!enabled_ && currentBypassWet_ <= 1.0e-4)
        {
            currentBypassWet_ = 0.0;
            activeAlgorithm = CrossfeedAlgorithm::Off;
            resetFiltersOnly();
        }
    }

private:
    inline void advanceStandardSmoothers() noexcept
    {
        currentMix += alphaSmooth_ * (targetMix - currentMix);
        currentDelayMs += alphaSmooth_ * (targetDelayMs - currentDelayMs);
        currentCutoffHz += alphaSmooth_ * (targetCutoffHz - currentCutoffHz);
        currentBypassWet_ += alphaSmooth_ * (targetBypassWet_ - currentBypassWet_);

        if (forceCoeffUpdate_ ||
            std::abs(lastCoeffCutoff - currentCutoffHz) > 0.05 ||
            std::abs(lastCoeffMix - currentMix) > 0.0005 ||
            std::abs(lastCoeffDelay - currentDelayMs) > 0.0005)
        {
            updateCoefficients();
        }
    }

    inline double readDelayed(const double *ringBuf, double delaySamples) const noexcept
    {
        const size_t i0 = static_cast<size_t>(delaySamples);
        const double frac = delaySamples - static_cast<double>(i0);
        const size_t p0 = (writeIdx - i0) & DELAY_MASK;
        const size_t p1 = (p0 - 1) & DELAY_MASK;
        return ringBuf[p0] + frac * (ringBuf[p1] - ringBuf[p0]);
    }

    inline void applyBypassBlend(double inL, double inR, double wetL, double wetR,
                                 double &outL, double &outR) const noexcept
    {
        if (currentBypassWet_ >= 0.9999)
        {
            outL = wetL;
            outR = wetR;
        }
        else
        {
            const double dry = 1.0 - currentBypassWet_;
            outL = inL * dry + wetL * currentBypassWet_;
            outR = inR * dry + wetR * currentBypassWet_;
        }
    }

    template <typename SampleT>
    void processSimple(SampleT *interleavedStereo, uint32_t frames, int channels) noexcept
    {
        const size_t ch = static_cast<size_t>(channels);
        for (uint32_t i = 0; i < frames; ++i)
        {
            advanceStandardSmoothers();

            const size_t base = static_cast<size_t>(i) * ch;
            const double inL = static_cast<double>(interleavedStereo[base]);
            const double inR = static_cast<double>(interleavedStereo[base + 1]);

            delayRingBufferL[writeIdx] = inL;
            delayRingBufferR[writeIdx] = inR;

            const double delayedL = readDelayed(delayRingBufferL, cachedDelaySamples);
            const double delayedR = readDelayed(delayRingBufferR, cachedDelaySamples);

            const double wetL = cachedSimpleDirectGain * inL + cachedSimpleCrossGain * delayedR;
            const double wetR = cachedSimpleDirectGain * inR + cachedSimpleCrossGain * delayedL;

            double outL, outR;
            applyBypassBlend(inL, inR, wetL, wetR, outL, outR);

            interleavedStereo[base] = static_cast<SampleT>(outL);
            interleavedStereo[base + 1] = static_cast<SampleT>(outR);
            writeIdx = (writeIdx + 1) & DELAY_MASK;
        }
    }

    template <typename SampleT>
    void processBS2B(SampleT *interleavedStereo, uint32_t frames, int channels) noexcept
    {
        const size_t ch = static_cast<size_t>(channels);
        for (uint32_t i = 0; i < frames; ++i)
        {
            advanceStandardSmoothers();

            const size_t base = static_cast<size_t>(i) * ch;
            const double inL = static_cast<double>(interleavedStereo[base]);
            const double inR = static_cast<double>(interleavedStereo[base + 1]);

            // Pure pole-matched libbs2b filter network (no artificial delay line)
            bs2bLoStateL = sauti::dsp::sanitizeSample(bs2b_a0_lo * inL + bs2b_b1_lo * bs2bLoStateL);
            bs2bLoStateR = sauti::dsp::sanitizeSample(bs2b_a0_lo * inR + bs2b_b1_lo * bs2bLoStateR);

            const double hiL = sauti::dsp::sanitizeSample(bs2b_a0_hi * inL + bs2b_a1_hi * bs2bAsisL + bs2b_b1_hi * bs2bHiStateL);
            const double hiR = sauti::dsp::sanitizeSample(bs2b_a0_hi * inR + bs2b_a1_hi * bs2bAsisR + bs2b_b1_hi * bs2bHiStateR);
            bs2bAsisL = inL;
            bs2bAsisR = inR;
            bs2bHiStateL = hiL;
            bs2bHiStateR = hiR;

            const double wetL = (hiL + bs2bLoStateR) * bs2b_gain;
            const double wetR = (hiR + bs2bLoStateL) * bs2b_gain;

            double outL, outR;
            applyBypassBlend(inL, inR, wetL, wetR, outL, outR);

            interleavedStereo[base] = static_cast<SampleT>(outL);
            interleavedStereo[base + 1] = static_cast<SampleT>(outR);
        }
    }

    template <typename SampleT>
    void processMeier(SampleT *interleavedStereo, uint32_t frames, int channels) noexcept
    {
        const size_t ch = static_cast<size_t>(channels);
        for (uint32_t i = 0; i < frames; ++i)
        {
            advanceStandardSmoothers();

            const size_t base = static_cast<size_t>(i) * ch;
            const double inL = static_cast<double>(interleavedStereo[base]);
            const double inR = static_cast<double>(interleavedStereo[base + 1]);

            lpfStateL[0] = sauti::dsp::sanitizeSample(lpfStateL[0] + meierLpfAlpha * (inL - lpfStateL[0]));
            lpfStateR[0] = sauti::dsp::sanitizeSample(lpfStateR[0] + meierLpfAlpha * (inR - lpfStateR[0]));

            const double crossL = lpfStateL[0];
            const double crossR = lpfStateR[0];

            // Complementary direct treble preservation
            const double directL = inL + cachedMeierHighBoost * (inL - crossL);
            const double directR = inR + cachedMeierHighBoost * (inR - crossR);

            delayRingBufferL[writeIdx] = crossL;
            delayRingBufferR[writeIdx] = crossR;

            const double delayedL = readDelayed(delayRingBufferL, cachedMeierExtraDelaySamples);
            const double delayedR = readDelayed(delayRingBufferR, cachedMeierExtraDelaySamples);

            const double wetL = (directL + cachedMeierCrossGain * delayedR) * cachedMeierComp;
            const double wetR = (directR + cachedMeierCrossGain * delayedL) * cachedMeierComp;

            double outL, outR;
            applyBypassBlend(inL, inR, wetL, wetR, outL, outR);

            interleavedStereo[base] = static_cast<SampleT>(outL);
            interleavedStereo[base + 1] = static_cast<SampleT>(outR);
            writeIdx = (writeIdx + 1) & DELAY_MASK;
        }
    }

    template <typename SampleT>
    void processNatural(SampleT *interleavedStereo, uint32_t frames, int channels) noexcept
    {
        const size_t ch = static_cast<size_t>(channels);
        for (uint32_t i = 0; i < frames; ++i)
        {
            advanceStandardSmoothers();

            const size_t base = static_cast<size_t>(i) * ch;
            const double inL = static_cast<double>(interleavedStereo[base]);
            const double inR = static_cast<double>(interleavedStereo[base + 1]);

            // 2-pole Butterworth TPT SVF lowpass
            const double v3L = inL - lpfStateL[1];
            const double v1L = svf_a1 * lpfStateL[0] + svf_a2 * v3L;
            const double v2L = lpfStateL[1] + svf_a2 * lpfStateL[0] + svf_a3 * v3L;
            lpfStateL[0] = sauti::dsp::sanitizeSample(2.0 * v1L - lpfStateL[0]);
            lpfStateL[1] = sauti::dsp::sanitizeSample(2.0 * v2L - lpfStateL[1]);
            const double lpfOutL = v2L;

            const double v3R = inR - lpfStateR[1];
            const double v1R = svf_a1 * lpfStateR[0] + svf_a2 * v3R;
            const double v2R = lpfStateR[1] + svf_a2 * lpfStateR[0] + svf_a3 * v3R;
            lpfStateR[0] = sauti::dsp::sanitizeSample(2.0 * v1R - lpfStateR[0]);
            lpfStateR[1] = sauti::dsp::sanitizeSample(2.0 * v2R - lpfStateR[1]);
            const double lpfOutR = v2R;

            // Complementary direct treble preservation
            const double directL = inL + cachedNaturalHighBoost * (inL - lpfOutL);
            const double directR = inR + cachedNaturalHighBoost * (inR - lpfOutR);

            delayRingBufferL[writeIdx] = lpfOutL;
            delayRingBufferR[writeIdx] = lpfOutR;

            // Extra delay has 2-pole Butterworth DC group delay subtracted
            const double delayedL = readDelayed(delayRingBufferL, cachedNaturalExtraDelaySamples);
            const double delayedR = readDelayed(delayRingBufferR, cachedNaturalExtraDelaySamples);

            const double wetL = (directL + cachedNaturalCrossGain * delayedR) * cachedNaturalComp;
            const double wetR = (directR + cachedNaturalCrossGain * delayedL) * cachedNaturalComp;

            double outL, outR;
            applyBypassBlend(inL, inR, wetL, wetR, outL, outR);

            interleavedStereo[base] = static_cast<SampleT>(outL);
            interleavedStereo[base + 1] = static_cast<SampleT>(outR);
            writeIdx = (writeIdx + 1) & DELAY_MASK;
        }
    }

    template <typename SampleT>
    void processRace(SampleT *interleavedStereo, uint32_t frames, int channels) noexcept
    {
        const size_t ch = static_cast<size_t>(channels);
        constexpr double kButterworthQInv = 1.4142135623730951;

        for (uint32_t i = 0; i < frames; ++i)
        {
            currentRaceDelayMs += alphaSmooth_ * (targetRaceDelayMs - currentRaceDelayMs);
            currentRaceAlpha += alphaSmooth_ * (targetRaceAlpha - currentRaceAlpha);
            currentRaceLpfHz += alphaSmooth_ * (targetRaceLpfHz - currentRaceLpfHz);
            currentBypassWet_ += alphaSmooth_ * (targetBypassWet_ - currentBypassWet_);

            if (forceCoeffUpdate_ ||
                std::abs(lastRaceLpfHz - currentRaceLpfHz) > 0.05 ||
                std::abs(lastRaceAlpha - currentRaceAlpha) > 0.0005 ||
                std::abs(lastRaceDelayMs - currentRaceDelayMs) > 0.0005)
            {
                updateCoefficients();
            }

            const size_t base = static_cast<size_t>(i) * ch;
            const double inL = static_cast<double>(interleavedStereo[base]);
            const double inR = static_cast<double>(interleavedStereo[base + 1]);

            // Read contralateral recursive state (>= 1 sample delay before write)
            const double delayedOutL = readDelayed(delayRingBufferL, cachedRaceDelaySamples);
            const double delayedOutR = readDelayed(delayRingBufferR, cachedRaceDelaySamples);

            // Band-limit feedback path with 200 Hz 2-pole Butterworth HPF to prevent LF Side blowup
            const double hv3L = delayedOutL - raceHpfStateL[1];
            const double hv1L = raceHp_a1 * raceHpfStateL[0] + raceHp_a2 * hv3L;
            const double hv2L = raceHpfStateL[1] + raceHp_a2 * raceHpfStateL[0] + raceHp_a3 * hv3L;
            raceHpfStateL[0] = sauti::dsp::sanitizeSample(2.0 * hv1L - raceHpfStateL[0]);
            raceHpfStateL[1] = sauti::dsp::sanitizeSample(2.0 * hv2L - raceHpfStateL[1]);
            const double hpfOutL = delayedOutL - kButterworthQInv * hv1L - hv2L;

            const double hv3R = delayedOutR - raceHpfStateR[1];
            const double hv1R = raceHp_a1 * raceHpfStateR[0] + raceHp_a2 * hv3R;
            const double hv2R = raceHpfStateR[1] + raceHp_a2 * raceHpfStateR[0] + raceHp_a3 * hv3R;
            raceHpfStateR[0] = sauti::dsp::sanitizeSample(2.0 * hv1R - raceHpfStateR[0]);
            raceHpfStateR[1] = sauti::dsp::sanitizeSample(2.0 * hv2R - raceHpfStateR[1]);
            const double hpfOutR = delayedOutR - kButterworthQInv * hv1R - hv2R;

            // Head-shadow 1-pole LPF inside feedback loop
            raceLpfOutL = sauti::dsp::sanitizeSample(raceA0 * hpfOutL + raceB1 * raceLpfOutL);
            raceLpfOutR = sauti::dsp::sanitizeSample(raceA0 * hpfOutR + raceB1 * raceLpfOutR);

            double recL = inL - cachedRaceEffectiveAlpha * raceLpfOutR;
            double recR = inR - cachedRaceEffectiveAlpha * raceLpfOutL;

            // Soft-knee safety clamp on recursive state
            if (std::abs(recL) > 0.98)
            {
                const double sign = (recL > 0.0) ? 1.0 : -1.0;
                const double excess = std::abs(recL) - 0.98;
                recL = sign * (0.98 + 0.02 * std::tanh(excess / 0.02));
            }
            if (std::abs(recR) > 0.98)
            {
                const double sign = (recR > 0.0) ? 1.0 : -1.0;
                const double excess = std::abs(recR) - 0.98;
                recR = sign * (0.98 + 0.02 * std::tanh(excess / 0.02));
            }

            delayRingBufferL[writeIdx] = recL;
            delayRingBufferR[writeIdx] = recR;

            const double wetL = recL * cachedRaceComp;
            const double wetR = recR * cachedRaceComp;

            double outL, outR;
            applyBypassBlend(inL, inR, wetL, wetR, outL, outR);

            interleavedStereo[base] = static_cast<SampleT>(outL);
            interleavedStereo[base + 1] = static_cast<SampleT>(outR);
            writeIdx = (writeIdx + 1) & DELAY_MASK;
        }
    }

    template <typename SampleT>
    void processOpenStage(SampleT *interleavedStereo, uint32_t frames, int channels) noexcept
    {
        const size_t ch = static_cast<size_t>(channels);
        for (uint32_t i = 0; i < frames; ++i)
        {
            currentMix += alphaSmooth_ * (targetMix - currentMix);
            currentBypassWet_ += alphaSmooth_ * (targetBypassWet_ - currentBypassWet_);

            const size_t base = static_cast<size_t>(i) * ch;
            const double inL = static_cast<double>(interleavedStereo[base]);
            const double inR = static_cast<double>(interleavedStereo[base + 1]);

            openStage.setMixImmediate(static_cast<float>(currentMix));
            double wetL = inL;
            double wetR = inR;
            openStage.processSample(inL, inR, wetL, wetR);

            double outL, outR;
            applyBypassBlend(inL, inR, wetL, wetR, outL, outR);

            interleavedStereo[base] = static_cast<SampleT>(outL);
            interleavedStereo[base + 1] = static_cast<SampleT>(outR);
        }
    }

    void updateCoefficients() noexcept
    {
        constexpr double pi = 3.14159265358979323846;
        constexpr double kTwoPi = 6.28318530717958647692;
        constexpr double kButterworthQInv = 1.4142135623730951;

        const double maxSafeCutoff = std::max(200.0, sampleRate * 0.42);
        const double fcut = std::clamp(currentCutoffHz, 100.0, maxSafeCutoff);
        const double mix = std::clamp(currentMix, 0.0, 1.0);
        const double delayMs = std::clamp(currentDelayMs, 0.02, 5.0);

        switch (activeAlgorithm)
        {
        case CrossfeedAlgorithm::Simple:
        {
            cachedDelaySamples = std::clamp(delayMs * 0.001 * sampleRate, 0.01, static_cast<double>(MAX_DELAY_SAMPLES - 2));
            cachedSimpleCrossGain = mix * 0.55;
            cachedSimpleDirectGain = outputCompensationEnabled
                                         ? (1.0 / std::sqrt(1.0 + cachedSimpleCrossGain * cachedSimpleCrossGain))
                                         : 1.0;
            break;
        }

        case CrossfeedAlgorithm::BS2B:
        {
            // Exact libbs2b mapping: smaller feed dB = stronger crossfeed
            // mix=0.30 -> 9.5 dB (Jan Meier), mix=0.65 -> 6.0 dB (Chu Moy), mix=0.80 -> 4.5 dB (Default)
            const double level = std::clamp(12.5 - 10.0 * mix, 2.5, 15.0);
            const double fade = std::clamp(mix / 0.20, 0.0, 1.0);
            const double gb_lo = level * -5.0 / 6.0 - 3.0;
            const double gb_hi = level / 6.0 - 3.0;

            const double g_lo_full = std::pow(10.0, gb_lo / 20.0);
            const double g_hi_full = 1.0 - std::pow(10.0, gb_hi / 20.0);
            const double g_lo = g_lo_full * fade;
            const double g_hi = g_hi_full * fade;
            const double fc_hi = std::min(
                sampleRate * 0.45,
                fcut * std::pow(2.0, (gb_lo - 20.0 * std::log10(std::max(1.0e-6, g_hi_full))) / 12.0));

            const double x_lo = std::exp(-kTwoPi * fcut / sampleRate);
            bs2b_b1_lo = x_lo;
            bs2b_a0_lo = g_lo * (1.0 - x_lo);

            const double x_hi = std::exp(-kTwoPi * fc_hi / sampleRate);
            bs2b_b1_hi = x_hi;
            bs2b_a0_hi = 1.0 - g_hi * (1.0 - x_hi);
            bs2b_a1_hi = -x_hi;

            bs2b_gain = outputCompensationEnabled ? (1.0 / (1.0 - g_hi + g_lo)) : 1.0;
            break;
        }

        case CrossfeedAlgorithm::Meier:
        {
            meierLpfAlpha = 1.0 - std::exp(-kTwoPi * fcut / sampleRate);
            cachedMeierCrossGain = mix * 0.60;
            cachedMeierHighBoost = cachedMeierCrossGain * 0.70;
            cachedMeierComp = outputCompensationEnabled
                                  ? (1.0 / (1.0 + 0.5 * (cachedMeierCrossGain + cachedMeierHighBoost)))
                                  : 1.0;

            // Subtract net filter group delay (contra 1-pole LPF minus direct high-boost phase lead)
            const double filterDelayMs = (1.0 + cachedMeierHighBoost) * (1000.0 / (kTwoPi * fcut));
            const double extraDelayMs = std::max(0.0, delayMs - filterDelayMs);
            cachedMeierExtraDelaySamples = std::clamp(extraDelayMs * 0.001 * sampleRate, 0.0, static_cast<double>(MAX_DELAY_SAMPLES - 2));
            break;
        }

        case CrossfeedAlgorithm::Natural:
        {
            const double g_nat = std::tan(pi * fcut / sampleRate);
            const double a1_nat = 1.0 / (1.0 + g_nat * (g_nat + kButterworthQInv));
            const double a2_nat = g_nat * a1_nat;
            const double a3_nat = g_nat * a2_nat;
            svf_a1 = a1_nat;
            svf_a2 = a2_nat;
            svf_a3 = a3_nat;

            cachedNaturalCrossGain = mix * 0.60;
            cachedNaturalHighBoost = cachedNaturalCrossGain * 0.70;
            cachedNaturalComp = outputCompensationEnabled
                                    ? (1.0 / (1.0 + 0.5 * (cachedNaturalCrossGain + cachedNaturalHighBoost)))
                                    : 1.0;

            // Subtract net 2-pole Butterworth + direct high-boost group delay so total ITD matches delayMs
            const double svfDelayMs = (1.0 + cachedNaturalHighBoost) * ((1000.0 * kButterworthQInv) / (kTwoPi * fcut));
            const double extraDelayMs = std::max(0.0, delayMs - svfDelayMs);
            cachedNaturalExtraDelaySamples = std::clamp(extraDelayMs * 0.001 * sampleRate, 0.0, static_cast<double>(MAX_DELAY_SAMPLES - 2));
            break;
        }

        case CrossfeedAlgorithm::RACE:
        {
            const double raceFcut = std::clamp(currentRaceLpfHz, 200.0, maxSafeCutoff);
            const double x_race = std::exp(-kTwoPi * raceFcut / sampleRate);
            raceA0 = 1.0 - x_race;
            raceB1 = x_race;

            // 200 Hz 2-pole Butterworth HPF inside feedback loop
            const double g_hp = std::tan(pi * 200.0 / sampleRate);
            raceHp_a1 = 1.0 / (1.0 + g_hp * (g_hp + kButterworthQInv));
            raceHp_a2 = g_hp * raceHp_a1;
            raceHp_a3 = g_hp * raceHp_a2;

            cachedRaceDelaySamples = std::clamp(currentRaceDelayMs * 0.001 * sampleRate, 1.0, static_cast<double>(MAX_DELAY_SAMPLES - 2));
            cachedRaceEffectiveAlpha = std::clamp(currentRaceAlpha, 0.0, 0.85);
            cachedRaceComp = outputCompensationEnabled
                                 ? (1.0 / std::sqrt(1.0 + 0.35 * cachedRaceEffectiveAlpha * cachedRaceEffectiveAlpha))
                                 : 1.0;
            break;
        }

        case CrossfeedAlgorithm::OpenStage:
        case CrossfeedAlgorithm::Off:
        default:
            break;
        }

        lastCoeffCutoff = currentCutoffHz;
        lastCoeffMix = currentMix;
        lastCoeffDelay = currentDelayMs;
        lastRaceLpfHz = currentRaceLpfHz;
        lastRaceAlpha = currentRaceAlpha;
        lastRaceDelayMs = currentRaceDelayMs;
        forceCoeffUpdate_ = false;
    }

    double sampleRate = 48000.0;
    double alphaSmooth_ = 0.00208;
    CrossfeedAlgorithm targetAlgorithm = CrossfeedAlgorithm::Off;
    CrossfeedAlgorithm activeAlgorithm = CrossfeedAlgorithm::Off;
    bool enabled_ = false;
    double targetBypassWet_ = 0.0;
    double currentBypassWet_ = 0.0;

    // Standard crossfeed smoothed parameters (Simple, BS2B, Meier, Natural, OpenStage mix)
    double targetMix = 0.5;
    double currentMix = 0.5;
    double targetDelayMs = 0.40;
    double currentDelayMs = 0.40;
    double targetCutoffHz = 700.0;
    double currentCutoffHz = 700.0;

    // Isolated RACE smoothed parameters
    double targetRaceDelayMs = 0.166;
    double currentRaceDelayMs = 0.166;
    double targetRaceAlpha = 0.55;
    double currentRaceAlpha = 0.55;
    double targetRaceLpfHz = 2500.0;
    double currentRaceLpfHz = 2500.0;

    double lastCoeffCutoff = -1.0;
    double lastCoeffMix = -1.0;
    double lastCoeffDelay = -1.0;
    double lastRaceLpfHz = -1.0;
    double lastRaceAlpha = -1.0;
    double lastRaceDelayMs = -1.0;
    bool forceCoeffUpdate_ = true;

    bool outputCompensationEnabled = true;

    // 64-bit delay ring buffers
    double delayRingBufferL[MAX_DELAY_SAMPLES] = {};
    double delayRingBufferR[MAX_DELAY_SAMPLES] = {};
    size_t writeIdx = 0;

    // Cached per-algorithm gains & delays
    double cachedDelaySamples = 19.2;
    double cachedSimpleCrossGain = 0.275;
    double cachedSimpleDirectGain = 0.964;

    double cachedMeierCrossGain = 0.30;
    double cachedMeierHighBoost = 0.21;
    double cachedMeierComp = 0.797;
    double cachedMeierExtraDelaySamples = 8.2;

    double cachedNaturalCrossGain = 0.30;
    double cachedNaturalHighBoost = 0.21;
    double cachedNaturalComp = 0.797;
    double cachedNaturalExtraDelaySamples = 3.8;

    double cachedRaceDelaySamples = 7.968;
    double cachedRaceEffectiveAlpha = 0.55;
    double cachedRaceComp = 0.951;

    // Filter states (64-bit)
    double lpfStateL[2] = {};
    double lpfStateR[2] = {};

    // BS2B filter states & coefficients
    double bs2b_a0_lo = 0.0;
    double bs2b_b1_lo = 0.0;
    double bs2b_a0_hi = 1.0;
    double bs2b_a1_hi = 0.0;
    double bs2b_b1_hi = 0.0;
    double bs2b_gain = 1.0;
    double bs2bAsisL = 0.0;
    double bs2bAsisR = 0.0;
    double bs2bHiStateL = 0.0;
    double bs2bHiStateR = 0.0;
    double bs2bLoStateL = 0.0;
    double bs2bLoStateR = 0.0;

    // RACE filter states & cached coefficients
    double raceLpfOutL = 0.0;
    double raceLpfOutR = 0.0;
    double raceHpfStateL[2] = {};
    double raceHpfStateR[2] = {};
    double raceA0 = 0.0;
    double raceB1 = 0.0;
    double raceHp_a1 = 0.0;
    double raceHp_a2 = 0.0;
    double raceHp_a3 = 0.0;

    // Cached Meier & Natural filter coefficients
    double meierLpfAlpha = 0.0;
    double svf_a1 = 0.0;
    double svf_a2 = 0.0;
    double svf_a3 = 0.0;

    // OpenStage DSP engine
    sauti::dsp::OpenStageDSP openStage;
};
