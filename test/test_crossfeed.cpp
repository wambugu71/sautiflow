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
    // Expected amplitude at -3 dB corner: crossGain (0.35) * (1 / sqrt(2)) = 0.247487
    const float expectedCornerAmp = 0.35f * 0.70710678f;
    assert(std::abs(maxCrossR - expectedCornerAmp) < 0.015f);
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

    std::cout << "\nRunning PDC Latency Reporting Tests:\n";
    CrossfeedNode pdcNode;
    assert(pdcNode.getLatencySamples() == 0.0);
    pdcNode.setAlgorithm(CrossfeedAlgorithm::Simple);
    pdcNode.setMix(0.5f);
    pdcNode.setDelayMs(0.5f);
    pdcNode.setSampleRate(48000.0);
    pdcNode.reset();
    double expectedPdc = 0.5 * 0.001 * 48000.0;
    assert(std::abs(pdcNode.getLatencySamples() - expectedPdc) < 1e-4);
    pdcNode.setAlgorithm(CrossfeedAlgorithm::Off);
    assert(pdcNode.getLatencySamples() == 0.0);
    std::cout << "  [PASS] Node getLatencySamples() verified (0.5ms @ 48kHz = " << expectedPdc << " samples)\n";

    std::cout << "\nAll Crossfeed DSP Node tests passed successfully!\n";
    return 0;
}
