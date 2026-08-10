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

int main()
{
    std::cout << "========================================================\n";
    std::cout << "  CROSSFEED DSP NODE VERIFICATION TEST SUITE            \n";
    std::cout << "========================================================\n";

    test_algorithm_at_rates(CrossfeedAlgorithm::Simple, "Simple");
    test_algorithm_at_rates(CrossfeedAlgorithm::BS2B, "BS2B");
    test_algorithm_at_rates(CrossfeedAlgorithm::Meier, "Meier");
    test_algorithm_at_rates(CrossfeedAlgorithm::Natural, "Natural");

    std::cout << "\nRunning Delay & Sample Rate Invariance Tests:\n";
    test_delay_accuracy();

    std::cout << "\nRunning Rate Transition Safety Tests:\n";
    test_sample_rate_transitions();

    std::cout << "\nAll Crossfeed DSP Node tests passed successfully!\n";
    return 0;
}
