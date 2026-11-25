#include <iostream>
#include <vector>
#include <cmath>
#include <cassert>
#include <iomanip>
#include "../crossfeed_node.h"

void test_algorithm_at_rates(CrossfeedAlgorithm algo, const char* name)
{
    const double rates[] = {44100.0, 48000.0, 88200.0, 96000.0, 176400.0, 192000.0};

    for (double sr : rates)
    {
        CrossfeedNode node;
        node.setSampleRate(sr);
        node.setAlgorithm(algo);
        node.setMix(0.5f);
        node.setDelayMs(0.40f); // 0.4ms
        node.setCutoffHz(700.0f);
        node.setOutputCompensation(true);

        // 1. Hard-left input test
        constexpr uint32_t numFrames = 1024;
        std::vector<float> buffer(numFrames * 2, 0.0f);
        for (uint32_t i = 0; i < numFrames; ++i)
        {
            buffer[i * 2] = 1.0f; // L = 1.0
            buffer[i * 2 + 1] = 0.0f; // R = 0.0
        }

        node.process(buffer.data(), numFrames, 2);

        // Check outputs
        bool hasL = false, hasR = false;
        bool hasNaN = false;
        for (uint32_t i = 100; i < numFrames; ++i)
        {
            float l = buffer[i * 2];
            float r = buffer[i * 2 + 1];
            if (std::isnan(l) || std::isnan(r) || std::isinf(l) || std::isinf(r))
            {
                hasNaN = true;
            }
            if (std::abs(l) > 0.001f) hasL = true;
            if (std::abs(r) > 0.001f) hasR = true;
        }

        assert(!hasNaN);
        if (algo != CrossfeedAlgorithm::Off)
        {
            assert(hasL);
            assert(hasR); // Hard-left input should crossfeed into Right channel
        }

        // 2. Mono symmetry test
        node.reset();
        std::vector<float> monoBuf(numFrames * 2, 0.5f); // L=0.5, R=0.5
        node.process(monoBuf.data(), numFrames, 2);
        for (uint32_t i = 100; i < numFrames; ++i)
        {
            float l = monoBuf[i * 2];
            float r = monoBuf[i * 2 + 1];
            assert(std::abs(l - r) < 1e-4f); // Symmetry check
        }
    }
    std::cout << "  [PASS] Algorithm " << name << " verified across all sample rates (44.1k - 192k)\n";
}

void test_delay_accuracy()
{
    const double rates[] = {44100.0, 48000.0, 96000.0, 192000.0};
    const float targetDelayMs = 0.50f; // 0.5 ms delay

    for (double sr : rates)
    {
        CrossfeedNode node;
        node.setSampleRate(sr);
        node.setAlgorithm(CrossfeedAlgorithm::Simple);
        node.setMix(1.0f);
        node.setDelayMs(targetDelayMs);
        node.reset(); // Snap smoothed parameters to target for instant impulse test

        constexpr uint32_t numFrames = 2048;
        std::vector<float> buffer(numFrames * 2, 0.0f);

        // Send a single impulse on Left channel at frame 0
        buffer[0] = 1.0f;
        buffer[1] = 0.0f;

        node.process(buffer.data(), numFrames, 2);

        // Find peak of crossfed signal in Right channel
        uint32_t maxIdxR = 0;
        float maxValR = 0.0f;
        for (uint32_t i = 0; i < numFrames; ++i)
        {
            float valR = buffer[i * 2 + 1];
            if (valR > maxValR)
            {
                maxValR = valR;
                maxIdxR = i;
            }
        }

        double measuredDelayMs = ((double)maxIdxR / sr) * 1000.0;
        double expectedSamples = targetDelayMs * 0.001 * sr;

        std::cout << "  [PASS] ITD Delay Test @ " << sr / 1000.0 << " kHz: expected "
                  << expectedSamples << " samples (" << targetDelayMs << " ms), measured peak at frame "
                  << maxIdxR << " (" << measuredDelayMs << " ms)\n";

        // Peak frame index should equal round(expectedSamples)
        assert(std::abs(maxIdxR - expectedSamples) <= 1.0);
    }
}

void test_sample_rate_transitions()
{
    CrossfeedNode node;
    node.setAlgorithm(CrossfeedAlgorithm::Natural);
    node.setMix(0.5f);
    node.setDelayMs(0.4f);
    node.setCutoffHz(700.0f);

    const double transitionRates[] = {44100.0, 96000.0, 44100.0, 48000.0, 192000.0, 48000.0};
    constexpr uint32_t framesPerBlock = 512;
    std::vector<float> buffer(framesPerBlock * 2, 0.5f);

    for (double sr : transitionRates)
    {
        node.setSampleRate(sr);
        for (int block = 0; block < 10; ++block)
        {
            std::fill(buffer.begin(), buffer.end(), 0.5f);
            node.process(buffer.data(), framesPerBlock, 2);
            for (float sample : buffer)
            {
                assert(!std::isnan(sample) && !std::isinf(sample));
            }
        }
    }
    std::cout << "  [PASS] Dynamic sample rate transitions (44.1k <-> 96k <-> 192k) verified\n";
}

void test_race_properties()
{
    std::cout << "\nRunning Ambiophonics RACE Specific DSP Tests:\n";
    const double sr = 48000.0;
    CrossfeedNode node;
    node.setSampleRate(sr);
    node.setAlgorithm(CrossfeedAlgorithm::RACE);
    node.setRaceParams(0.20f, 0.60f, 2500.0f); // 0.20ms, alpha=0.6, lpf=2500Hz
    node.setOutputCompensation(true);
    node.reset();

    constexpr uint32_t numFrames = 1024;
    std::vector<float> buffer(numFrames * 2, 0.0f);

    // 1. Anti-phase crosstalk verification:
    // A positive impulse on Left (1.0) must produce a NEGATIVE contralateral cancellation wave on Right
    buffer[0] = 1.0f;
    buffer[1] = 0.0f;
    node.process(buffer.data(), numFrames, 2);

    float minValR = 0.0f;
    uint32_t minIdxR = 0;
    for (uint32_t i = 0; i < numFrames; ++i)
    {
        float valR = buffer[i * 2 + 1];
        if (valR < minValR)
        {
            minValR = valR;
            minIdxR = i;
        }
    }
    // Verify that the crosstalk cancellation signal is strictly negative (anti-phase)
    assert(minValR < -0.05f);
    // Expected delay in samples: 0.20ms * 48 samples/ms = 9.6 samples -> peak around frame 10
    assert(minIdxR >= 9 && minIdxR <= 12);
    std::cout << "  [PASS] Anti-phase cancellation confirmed (peak negative wave = "
              << minValR << " at frame " << minIdxR << ")\n";

    // 2. High-alpha stress test (stability under high feedback):
    node.reset();
    node.setRaceParams(0.15f, 0.95f, 4000.0f); // aggressive 95% alpha
    node.reset();
    std::vector<float> noiseBuf(4096 * 2);
    for (size_t i = 0; i < noiseBuf.size(); ++i)
    {
        noiseBuf[i] = ((float)(rand() % 2000) - 1000.0f) / 1000.0f;
    }
    node.process(noiseBuf.data(), 4096, 2);

    float maxMag = 0.0f;
    for (float s : noiseBuf)
    {
        assert(!std::isnan(s) && !std::isinf(s));
        if (std::abs(s) > maxMag) maxMag = std::abs(s);
    }
    assert(maxMag <= 1.05f); // No runaway or instability
    std::cout << "  [PASS] High-feedback stability test (alpha=0.95, max amplitude = "
              << maxMag << " without blowup)\n";
}

void test_openstage_properties()
{
    std::cout << "\nRunning OpenStage Specific DSP Tests:\n";
    const double sr = 48000.0;

    // 1. Direct OpenStageDSP standalone test
    sauti::dsp::OpenStageDSP dsp;
    dsp.setSampleRate(sr);
    dsp.setAngle(60.0f);
    dsp.setGainDb(-1.0f);
    dsp.setMix(1.0f);
    dsp.setEnabled(true);
    dsp.reset();

    constexpr uint32_t numFrames = 1024;
    std::vector<float> buffer(numFrames * 2, 0.0f);

    // Hard-left impulse: Left=1.0, Right=0.0 at frame 0
    buffer[0] = 1.0f;
    buffer[1] = 0.0f;
    dsp.process(buffer.data(), numFrames, 2);

    // Check that direct sound appears on Left and crossfeed appears on Right
    float peakL = 0.0f, peakR = 0.0f;
    uint32_t peakIdxR = 0;
    for (uint32_t i = 0; i < numFrames; ++i)
    {
        float l = buffer[i * 2];
        float r = buffer[i * 2 + 1];
        assert(!std::isnan(l) && !std::isinf(l));
        assert(!std::isnan(r) && !std::isinf(r));
        if (std::abs(l) > peakL) peakL = std::abs(l);
        if (std::abs(r) > peakR) { peakR = std::abs(r); peakIdxR = i; }
    }
    assert(peakL > 0.5f);
    assert(peakR > 0.05f);
    std::cout << "  [PASS] OpenStage impulse response: Direct Peak=" << peakL 
              << ", Cross Peak=" << peakR << " at frame " << peakIdxR << "\n";

    // 2. Mono symmetry test across angle range (0°, 30°, 60°, 90°)
    for (float angle : {0.0f, 30.0f, 60.0f, 90.0f})
    {
        dsp.reset();
        dsp.setAngle(angle);
        std::vector<float> monoBuf(numFrames * 2, 0.5f);
        dsp.process(monoBuf.data(), numFrames, 2);
        for (uint32_t i = 50; i < numFrames; ++i)
        {
            float l = monoBuf[i * 2];
            float r = monoBuf[i * 2 + 1];
            assert(std::abs(l - r) < 1.0e-5f);
        }
    }
    std::cout << "  [PASS] OpenStage mono symmetry verified for angles 0°, 30°, 60°, 90°\n";

    // 3. CrossfeedNode integration test for OpenStage + Live parameter smoothing without reset()
    CrossfeedNode node;
    node.setSampleRate(sr);
    node.setAlgorithm(CrossfeedAlgorithm::OpenStage);
    node.setAngle(60.0f);
    node.setGainDb(0.0f);
    node.setMix(1.0f);
    node.reset();

    std::vector<float> nodeBuf(numFrames * 2, 0.0f);
    nodeBuf[0] = 1.0f;
    node.process(nodeBuf.data(), numFrames, 2);

    float nodePeakR = 0.0f;
    for (uint32_t i = 0; i < numFrames; ++i)
    {
        float r = nodeBuf[i * 2 + 1];
        if (std::abs(r) > nodePeakR) nodePeakR = std::abs(r);
    }
    assert(nodePeakR > 0.05f);
    std::cout << "  [PASS] CrossfeedNode::OpenStage routing verified (cross peak=" << nodePeakR << ")\n";

    // Verify live gain & angle updates take effect during playback WITHOUT calling reset()
    std::vector<float> settleBuf0(4800 * 2, 0.25f);
    node.process(settleBuf0.data(), 4800, 2);
    const float outAtZeroDb = settleBuf0[(4800 - 1) * 2];

    node.setGainDb(-6.0f); // -6 dB (~0.501x linear amplitude)
    node.setAngle(90.0f);
    std::vector<float> settleBuf(9600 * 2, 0.25f); // 200ms to fully settle 25ms smoother
    node.process(settleBuf.data(), 9600, 2);
    const float finalOutL = settleBuf[(9600 - 1) * 2];
    assert(finalOutL < outAtZeroDb * 0.55f && finalOutL > outAtZeroDb * 0.45f);
    std::cout << "  [PASS] CrossfeedNode::OpenStage live parameter smoothing verified (0dB="
              << outAtZeroDb << " -> -6dB=" << finalOutL << ")\n";
}

void test_meier_and_64bit_precision()
{
    std::cout << "\nRunning Meier -3dB Cutoff & 64-Bit Double Precision Tests:\n";
    const double sr = 48000.0;
    const float fcut = 700.0f;

    // 1. Verify Jan Meier 1-pole crossfeed path has exact -3 dB attenuation at cutoffHz
    CrossfeedNode node;
    node.setSampleRate(sr);
    node.setAlgorithm(CrossfeedAlgorithm::Meier);
    node.setCutoffHz(fcut);
    node.setMix(1.0f);
    node.setOutputCompensation(false);
    node.reset();

    constexpr uint32_t frames = 4800;
    constexpr double kTwoPi = 6.28318530717958647692;
    std::vector<float> sineBuf(frames * 2, 0.0f);
    for (uint32_t i = 0; i < frames; ++i)
    {
        sineBuf[i * 2] = static_cast<float>(std::sin(kTwoPi * fcut * i / sr)); // Left = sine at fcut
        sineBuf[i * 2 + 1] = 0.0f; // Right = 0
    }
    node.process(sineBuf.data(), frames, 2);

    float maxCrossR = 0.0f;
    for (uint32_t i = 2400; i < frames; ++i)
    {
        maxCrossR = std::max(maxCrossR, std::abs(sineBuf[i * 2 + 1]));
    }
    // Expected amplitude at -3 dB corner: crossGain (0.60) * (1 / sqrt(2)) = 0.424264
    const float expectedCornerAmp = 0.60f * 0.70710678f;
    assert(std::abs(maxCrossR - expectedCornerAmp) < 0.02f);
    std::cout << "  [PASS] Jan Meier -3dB cutoff accuracy @ 700 Hz: expected "
              << expectedCornerAmp << ", measured " << maxCrossR << "\n";

    // 2. Verify native 64-bit double processing overload across all algorithms
    for (auto algo : {CrossfeedAlgorithm::Simple, CrossfeedAlgorithm::BS2B, CrossfeedAlgorithm::Meier,
                      CrossfeedAlgorithm::Natural, CrossfeedAlgorithm::RACE, CrossfeedAlgorithm::OpenStage})
    {
        CrossfeedNode node64;
        node64.setSampleRate(sr);
        node64.setAlgorithm(algo);
        node64.setMix(0.6f);
        node64.reset();

        std::vector<double> buf64(512 * 2, 0.25);
        node64.process(buf64.data(), 512, 2);
        for (double v : buf64)
        {
            assert(!std::isnan(v) && !std::isinf(v));
        }
    }
    std::cout << "  [PASS] 64-bit double-precision process(double*) verified for all 6 algorithms\n";
}

namespace {
double measureSineRms(const std::vector<float>& buf, int chOffset, uint32_t startFrame, uint32_t endFrame)
{
    double sumSq = 0.0;
    const uint32_t count = endFrame - startFrame;
    for (uint32_t i = startFrame; i < endFrame; ++i)
    {
        const double v = static_cast<double>(buf[i * 2 + chOffset]);
        sumSq += v * v;
    }
    return std::sqrt(sumSq / static_cast<double>(count));
}
} // namespace

void test_bs2b_libbs2b_presets_and_flat_mono()
{
    std::cout << "\nRunning Exact libbs2b ILD & Flat Mono Sum Tests:\n";
    const double sr = 48000.0;
    constexpr double kTwoPi = 6.28318530717958647692;

    struct PresetCase { const char* name; float mix; float cutoff; double expectedIldDb; };
    const PresetCase cases[] = {
        {"Jan Meier (9.5 dB)", 0.30f, 650.0f, 9.5},
        {"Chu Moy (6.0 dB)",   0.65f, 700.0f, 6.0},
        {"Default (4.5 dB)",   0.80f, 700.0f, 4.5},
    };

    for (const auto& c : cases)
    {
        CrossfeedNode node;
        node.setSampleRate(sr);
        node.setAlgorithm(CrossfeedAlgorithm::BS2B);
        node.setMix(c.mix);
        node.setCutoffHz(c.cutoff);
        node.setOutputCompensation(true);
        node.reset();

        // Low-frequency (50 Hz) hard-left ILD verification
        constexpr uint32_t frames = 9600;
        std::vector<float> buf(frames * 2, 0.0f);
        for (uint32_t i = 0; i < frames; ++i)
        {
            buf[i * 2] = static_cast<float>(std::sin(kTwoPi * 50.0 * i / sr));
        }
        node.process(buf.data(), frames, 2);
        const double ampL = measureSineRms(buf, 0, frames / 2, frames);
        const double ampR = measureSineRms(buf, 1, frames / 2, frames);
        const double ildDb = 20.0 * std::log10(ampL / std::max(1e-9, ampR));
        assert(std::abs(ildDb - c.expectedIldDb) < 0.25);

        // Mono sum flatness across 100 Hz .. 8 kHz
        double minMonoDb = 100.0, maxMonoDb = -100.0;
        for (double f : {100.0, 500.0, 1000.0, 1500.0, 3000.0, 8000.0})
        {
            node.reset();
            std::vector<float> mono(frames * 2, 0.0f);
            for (uint32_t i = 0; i < frames; ++i)
            {
                const float s = static_cast<float>(std::sin(kTwoPi * f * i / sr));
                mono[i * 2] = s;
                mono[i * 2 + 1] = s;
            }
            const double inRms = measureSineRms(mono, 0, frames / 2, frames);
            node.process(mono.data(), frames, 2);
            const double outRms = measureSineRms(mono, 0, frames / 2, frames);
            const double db = 20.0 * std::log10(outRms / std::max(1e-9, inRms));
            minMonoDb = std::min(minMonoDb, db);
            maxMonoDb = std::max(maxMonoDb, db);
        }
        assert(minMonoDb > -2.0 && maxMonoDb < 0.5);
        std::cout << "  [PASS] BS2B " << c.name << ": ILD=" << ildDb
                  << " dB, Mono range=[" << minMonoDb << ", " << maxMonoDb << "] dB\n";
    }
}

void test_natural_group_delay_compensation()
{
    std::cout << "\nRunning Natural 2-Pole Group Delay Compensation Test:\n";
    const double sr = 48000.0;
    CrossfeedNode node;
    node.setSampleRate(sr);
    node.setAlgorithm(CrossfeedAlgorithm::Natural);
    node.setMix(0.50f);
    node.setDelayMs(0.40f);
    node.setCutoffHz(700.0f);
    node.reset();

    // Measure low-frequency pulse group centroid lag between contralateral & direct outputs
    constexpr uint32_t frames = 2048;
    std::vector<float> buf(frames * 2, 0.0f);
    for (uint32_t i = 100; i < 500; ++i)
    {
        const double t = static_cast<double>(i - 100) / 400.0;
        const double win = 0.5 * (1.0 - std::cos(2.0 * 3.14159265358979323846 * t));
        buf[i * 2] = static_cast<float>(win);
    }
    node.process(buf.data(), frames, 2);

    double numL = 0.0, denL = 0.0, numR = 0.0, denR = 0.0;
    for (uint32_t i = 0; i < frames; ++i)
    {
        const double l = static_cast<double>(buf[i * 2]);
        const double r = static_cast<double>(buf[i * 2 + 1]);
        numL += i * l; denL += l;
        numR += i * r; denR += r;
    }
    const double centroidDiffSamples = (numR / denR) - (numL / denL);
    const double measuredItdMs = (centroidDiffSamples / sr) * 1000.0;
    // Previously ~0.73ms without GD subtraction; now ~0.40ms (within +-0.08ms)
    assert(measuredItdMs > 0.32 && measuredItdMs < 0.48);
    std::cout << "  [PASS] Natural total ITD @ 700Hz / 0.40ms target = " << measuredItdMs << " ms\n";
}

void test_race_subbass_stability_and_isolation()
{
    std::cout << "\nRunning RACE Sub-Bass HPF & Parameter Isolation Tests:\n";
    const double sr = 48000.0;
    constexpr double kTwoPi = 6.28318530717958647692;

    CrossfeedNode node;
    node.setSampleRate(sr);
    node.setMix(0.50f);
    node.setDelayMs(0.40f);
    node.setCutoffHz(700.0f);

    // RACE parameter isolation check
    node.setRaceParams(0.12f, 0.75f, 3200.0f);
    node.setAlgorithm(CrossfeedAlgorithm::BS2B);
    assert(std::abs(node.getMix() - 0.50f) < 1e-4f);
    assert(std::abs(node.getDelayMs() - 0.40f) < 1e-4f);
    assert(std::abs(node.getCutoffHz() - 700.0f) < 1e-2f);

    // Switch to RACE and verify 60 Hz Side (out-of-phase) does NOT blow up
    node.setAlgorithm(CrossfeedAlgorithm::RACE);
    node.reset();

    constexpr uint32_t frames = 9600;
    std::vector<float> sideBuf(frames * 2, 0.0f);
    for (uint32_t i = 0; i < frames; ++i)
    {
        const float s = 0.5f * static_cast<float>(std::sin(kTwoPi * 60.0 * i / sr));
        sideBuf[i * 2] = s;
        sideBuf[i * 2 + 1] = -s;
    }
    const double inRms = measureSineRms(sideBuf, 0, frames / 2, frames);
    node.process(sideBuf.data(), frames, 2);
    const double sideOutRms = measureSineRms(sideBuf, 0, frames / 2, frames);
    const double sideGainDb = 20.0 * std::log10(sideOutRms / std::max(1e-9, inRms));
    assert(sideGainDb > -2.5 && sideGainDb < 1.0);
    std::cout << "  [PASS] RACE 60 Hz Side gain = " << sideGainDb << " dB (no LF explosion), param isolation verified\n";
}

void test_openstage_angles_and_mono_flatness()
{
    std::cout << "\nRunning OpenStage Angle Differentiation & Mono Flatness Tests:\n";
    const double sr = 48000.0;
    constexpr double kTwoPi = 6.28318530717958647692;

    sauti::dsp::OpenStageDSP d30, d60, d90;
    d30.setSampleRate(sr); d30.setAngle(30.0f); d30.reset();
    d60.setSampleRate(sr); d60.setAngle(60.0f); d60.reset();
    d90.setSampleRate(sr); d90.setAngle(90.0f); d90.reset();

    assert(d30.getItdMs() < d60.getItdMs() && d60.getItdMs() < d90.getItdMs());
    assert(d30.getHeadShadowCutoffHz() > d60.getHeadShadowCutoffHz() &&
           d60.getHeadShadowCutoffHz() > d90.getHeadShadowCutoffHz());

    // Mono sum flatness at 60 deg (gainDb = -1.0, mix = 1.0) across 100 Hz .. 8 kHz
    double minMonoDb = 100.0, maxMonoDb = -100.0;
    constexpr uint32_t frames = 4800;
    for (double f : {100.0, 300.0, 700.0, 1000.0, 2000.0, 4000.0, 8000.0})
    {
        d60.reset();
        std::vector<float> mono(frames * 2, 0.0f);
        for (uint32_t i = 0; i < frames; ++i)
        {
            const float s = static_cast<float>(std::sin(kTwoPi * f * i / sr));
            mono[i * 2] = s;
            mono[i * 2 + 1] = s;
        }
        const double inRms = measureSineRms(mono, 0, frames / 2, frames);
        d60.process(mono.data(), frames, 2);
        const double outRms = measureSineRms(mono, 0, frames / 2, frames);
        const double db = 20.0 * std::log10(outRms / std::max(1e-9, inRms));
        minMonoDb = std::min(minMonoDb, db);
        maxMonoDb = std::max(maxMonoDb, db);
    }
    assert(minMonoDb > -1.9 && maxMonoDb < 1.2);
    std::cout << "  [PASS] OpenStage 60° mono flatness = [" << minMonoDb << ", " << maxMonoDb
              << "] dB; ITD(30/60/90)=" << d30.getItdMs() << "/" << d60.getItdMs() << "/" << d90.getItdMs() << " ms\n";
}

int main()
{
    std::cout << "========================================================\n";
    std::cout << "  CROSSFEED DSP NODE VERIFICATION TEST SUITE            \n";
    std::cout << "========================================================\n";

    test_algorithm_at_rates(CrossfeedAlgorithm::Simple, "Simple");
    test_algorithm_at_rates(CrossfeedAlgorithm::BS2B, "BS2B");
    test_algorithm_at_rates(CrossfeedAlgorithm::Meier, "Meier");
    test_algorithm_at_rates(CrossfeedAlgorithm::Natural, "Natural");
    test_algorithm_at_rates(CrossfeedAlgorithm::RACE, "RACE");
    test_algorithm_at_rates(CrossfeedAlgorithm::OpenStage, "OpenStage");

    std::cout << "\nRunning Delay & Sample Rate Invariance Tests:\n";
    test_delay_accuracy();

    std::cout << "\nRunning Rate Transition Safety Tests:\n";
    test_sample_rate_transitions();

    test_race_properties();
    test_openstage_properties();
    test_meier_and_64bit_precision();
    test_bs2b_libbs2b_presets_and_flat_mono();
    test_natural_group_delay_compensation();
    test_race_subbass_stability_and_isolation();
    test_openstage_angles_and_mono_flatness();

    std::cout << "\nRunning PDC Latency Reporting Tests:\n";
    CrossfeedNode pdcNode;
    assert(pdcNode.getLatencySamples() == 0.0);
    pdcNode.setAlgorithm(CrossfeedAlgorithm::Simple);
    pdcNode.setMix(0.5f);
    pdcNode.setDelayMs(0.5f);
    pdcNode.setSampleRate(48000.0);
    pdcNode.reset();
    assert(pdcNode.getLatencySamples() == 0.0);
    pdcNode.setAlgorithm(CrossfeedAlgorithm::Off);
    assert(pdcNode.getLatencySamples() == 0.0);
    std::cout << "  [PASS] Node getLatencySamples() verified (0.0 samples zero-latency direct path)\n";

    std::cout << "\nAll Crossfeed DSP Node tests passed successfully!\n";
    return 0;
}
