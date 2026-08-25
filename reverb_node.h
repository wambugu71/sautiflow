#pragma once

// Freeverb-style stereo reverb node.
//
// Topology per channel: pre-delay -> 8 parallel Schroeder comb filters ->
// 4 series allpass filters. The right channel uses the same tunings offset
// by a fixed stereo-spread so the two channels decorrelate into a wide,
// natural-sounding tail instead of a mono smear.
//
// Parameters are target/current pairs smoothed per-sample (same scheme as
// CrossfeedNode) so runtime tweaks never zipper or click.

#include <cmath>
#include <cstdint>
#include <vector>
#include <algorithm>

class ReverbNode
{
public:
    static constexpr int NUM_COMBS = 8;
    static constexpr int NUM_ALLPASSES = 4;

    // Filter tunings sampled at 44100 Hz (classic Freeverb constants).
    static constexpr float COMB_TUNING[NUM_COMBS] = {
        1116.0f, 1188.0f, 1277.0f, 1356.0f, 1422.0f, 1491.0f, 1557.0f, 1617.0f};
    static constexpr float ALLPASS_TUNING[NUM_ALLPASSES] = {
        556.0f, 441.0f, 341.0f, 225.0f};
    static constexpr float STEREO_SPREAD = 23.0f; // samples @44.1k between L/R

    static constexpr float MAX_PRE_DELAY_MS = 250.0f;

    ReverbNode()
    {
        // Build directly: setSampleRate() early-returns when the requested
        // rate matches the default, which would leave every buffer empty.
        buildBuffers();
        reset();
    }

    void setSampleRate(double rate)
    {
        if (rate <= 0.0)
            rate = 48000.0;
        if (std::abs(sampleRate - rate) < 0.1)
            return;

        sampleRate = rate;
        buildBuffers();
        reset();
    }

    void setEnabled(bool e)
    {
        targetEnabled = e;
    }

    bool getEnabled() const { return targetEnabled; }

    void setMix(float m)
    {
        // Legacy crossfade mapping: mix blends between fully-dry and fully-wet.
        setWet(m);
        setDry(1.0f - m);
    }

    void setWet(float w)
    {
        // >1.0 allowed for send-style wet boost.
        targetWet = std::max(0.0f, std::min(w, 2.0f));
    }

    void setDry(float d)
    {
        // >1.0 allowed for dry make-up gain.
        targetDry = std::max(0.0f, std::min(d, 2.0f));
    }

    void setRoomSize(float r)
    {
        targetRoomSize = std::max(0.0f, std::min(r, 1.0f));
    }

    void setDamping(float d)
    {
        targetDamping = std::max(0.0f, std::min(d, 1.0f));
    }

    void setPreDelayMs(float ms)
    {
        targetPreDelayMs = std::max(0.0f, std::min(ms, MAX_PRE_DELAY_MS));
    }

    void setWidth(float w)
    {
        targetWidth = std::max(0.0f, std::min(w, 1.0f));
    }

    float getWet() const { return targetWet; }
    float getDry() const { return targetDry; }
    float getRoomSize() const { return targetRoomSize; }
    float getDamping() const { return targetDamping; }
    float getPreDelayMs() const { return targetPreDelayMs; }
    float getWidth() const { return targetWidth; }

    // Latency contributed by the pre-delay stage (samples).
    double getLatencySamples() const
    {
        if (!targetEnabled && currentWet < 0.0001f)
            return 0.0;
        return (double)(currentPreDelayMs * 0.001f) * sampleRate;
    }

    void reset()
    {
        for (int c = 0; c < 2; ++c)
        {
            for (int i = 0; i < NUM_COMBS; ++i)
            {
                if (comb[c][i].buf.empty())
                    continue;
                std::fill(comb[c][i].buf.begin(), comb[c][i].buf.end(), 0.0f);
                comb[c][i].idx = 0;
                comb[c][i].filterStore = 0.0f;
            }
            for (int i = 0; i < NUM_ALLPASSES; ++i)
            {
                if (allpass[c][i].buf.empty())
                    continue;
                std::fill(allpass[c][i].buf.begin(), allpass[c][i].buf.end(), 0.0f);
                allpass[c][i].idx = 0;
            }
            if (!preDelayBuf[c].empty())
            {
                std::fill(preDelayBuf[c].begin(), preDelayBuf[c].end(), 0.0f);
                preDelayIdx[c] = 0;
            }
        }

        currentWet = targetWet;
        currentDry = targetDry;
        currentRoomSize = targetRoomSize;
        currentDamping = targetDamping;
        currentPreDelayMs = targetPreDelayMs;
        currentWidth = targetWidth;
        currentEnabled = targetEnabled;
    }

    void process(float *interleaved, uint32_t frames, int channels)
    {
        if (!interleaved || frames == 0 || channels < 2)
            return;

        if (!targetEnabled && currentWet < 0.0001f)
        {
            currentEnabled = false;
            return;
        }
        currentEnabled = true;

        // Defensive: never touch the network if buffers were not built yet
        // (e.g. racing a sample-rate rebuild on the control thread).
        if (comb[0][0].buf.empty() || allpass[0][0].buf.empty())
            return;

        // 15ms parameter smoothing time constant.
        const float alphaSmooth =
            1.0f - std::exp(-1.0f / (0.015f * (float)sampleRate));

        const size_t preDelayLen = preDelayBuf[0].size();

        for (uint32_t i = 0; i < frames; ++i)
        {
            // Smooth parameters toward targets.
            currentWet += alphaSmooth * (targetWet - currentWet);
            currentDry += alphaSmooth * (targetDry - currentDry);
            currentRoomSize += alphaSmooth * (targetRoomSize - currentRoomSize);
            currentDamping += alphaSmooth * (targetDamping - currentDamping);
            currentPreDelayMs += alphaSmooth * (targetPreDelayMs - currentPreDelayMs);
            currentWidth += alphaSmooth * (targetWidth - currentWidth);

            // Freeverb mappings.
            const float feedback = 0.7f + currentRoomSize * 0.28f;   // 0.70..0.98 decay
            const float damp = currentDamping * 0.4f;                // 0..0.4 damping
            const float wetGain = currentWet * 0.30f;                // headroom-safe wet level
            const float dryGain = currentDry;
            const float wet1 = wetGain * (currentWidth / 2.0f + 0.5f);
            const float wet2 = wetGain * ((1.0f - currentWidth) / 2.0f);

            const size_t base = (size_t)i * (size_t)channels;
            const float inL = interleaved[base];
            const float inR = interleaved[base + 1];

            // Pre-delay (shared write index, per-channel buffers).
            float pdL = inL;
            float pdR = inR;
            if (preDelayLen > 0)
            {
                const size_t delaySamples = std::min(
                    preDelayLen - 1,
                    (size_t)((currentPreDelayMs * 0.001f) * (float)sampleRate));
                preDelayBuf[0][preDelayIdx[0]] = inL;
                preDelayBuf[1][preDelayIdx[1]] = inR;
                pdL = preDelayBuf[0]
                    [(preDelayIdx[0] + preDelayLen - delaySamples) % preDelayLen];
                pdR = preDelayBuf[1]
                    [(preDelayIdx[1] + preDelayLen - delaySamples) % preDelayLen];
                preDelayIdx[0] = (preDelayIdx[0] + 1) % preDelayLen;
                preDelayIdx[1] = (preDelayIdx[1] + 1) % preDelayLen;
            }

            float wetL = 0.0f;
            float wetR = 0.0f;

            // Parallel combs.
            for (int c = 0; c < NUM_COMBS; ++c)
            {
                wetL += processComb(comb[0][c], pdL, feedback, damp);
                wetR += processComb(comb[1][c], pdR, feedback, damp);
            }

            // Series allpasses.
            for (int c = 0; c < NUM_ALLPASSES; ++c)
            {
                wetL = processAllpass(allpass[0][c], wetL);
                wetR = processAllpass(allpass[1][c], wetR);
            }

            interleaved[base] = inL * dryGain + wetL * wet1 + wetR * wet2;
            interleaved[base + 1] = inR * dryGain + wetR * wet1 + wetL * wet2;
        }
    }

private:
    struct Comb
    {
        std::vector<float> buf;
        size_t idx = 0;
        float filterStore = 0.0f;
    };

    struct Allpass
    {
        std::vector<float> buf;
        size_t idx = 0;
    };

    static float processComb(Comb &c, float input, float feedback, float damp)
    {
        const float output = c.buf[c.idx];
        c.filterStore = output * (1.0f - damp) + c.filterStore * damp;
        c.buf[c.idx] = input + c.filterStore * feedback;
        if (++c.idx >= c.buf.size())
            c.idx = 0;
        return output;
    }

    static float processAllpass(Allpass &a, float input)
    {
        const float bufout = a.buf[a.idx];
        const float output = -input + bufout;
        a.buf[a.idx] = input + bufout * 0.5f;
        if (++a.idx >= a.buf.size())
            a.idx = 0;
        return output;
    }

    static size_t tuningToSamples(float tuning, double rate)
    {
        const size_t n = (size_t)std::lround(tuning * (rate / 44100.0));
        return std::max<size_t>(4, n);
    }

    void buildBuffers()
    {
        const double scale = sampleRate / 44100.0;
        const size_t spread = (size_t)std::lround(STEREO_SPREAD * scale);

        for (int ch = 0; ch < 2; ++ch)
        {
            const size_t offset = (ch == 0) ? 0 : spread;
            for (int i = 0; i < NUM_COMBS; ++i)
            {
                comb[ch][i].buf.assign(
                    tuningToSamples(COMB_TUNING[i], sampleRate) + offset, 0.0f);
                comb[ch][i].idx = 0;
                comb[ch][i].filterStore = 0.0f;
            }
            for (int i = 0; i < NUM_ALLPASSES; ++i)
            {
                allpass[ch][i].buf.assign(
                    tuningToSamples(ALLPASS_TUNING[i], sampleRate) + offset, 0.0f);
                allpass[ch][i].idx = 0;
            }

            const size_t preDelaySamples = (size_t)std::lround(
                (MAX_PRE_DELAY_MS * 0.001) * sampleRate);
            preDelayBuf[ch].assign(std::max<size_t>(1, preDelaySamples), 0.0f);
            preDelayIdx[ch] = 0;
        }
    }

    double sampleRate = 48000.0;

    bool targetEnabled = false;
    bool currentEnabled = false;

    float targetWet = 0.0f;
    float currentWet = 0.0f;

    float targetDry = 1.0f;
    float currentDry = 1.0f;

    float targetRoomSize = 0.5f;
    float currentRoomSize = 0.5f;

    float targetDamping = 0.5f;
    float currentDamping = 0.5f;

    float targetPreDelayMs = 20.0f;
    float currentPreDelayMs = 20.0f;

    float targetWidth = 1.0f;
    float currentWidth = 1.0f;

    Comb comb[2][NUM_COMBS];
    Allpass allpass[2][NUM_ALLPASSES];
    std::vector<float> preDelayBuf[2];
    size_t preDelayIdx[2] = {0, 0};
};
