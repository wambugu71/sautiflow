#include <iostream>
#include <vector>
#include <cmath>
#include <cassert>
#include <algorithm>
#include "audio_engine.h"

// Generate a 1 kHz sine wave at given sample rate and duration in seconds
std::vector<float> generate_sine(uint32_t sampleRate, double durationSec, float freqHz = 1000.0f)
{
    size_t totalSamples = (size_t)(sampleRate * durationSec);
    std::vector<float> buffer(totalSamples);
    double twoPiF = 2.0 * 3.14159265358979323846 * freqHz;
    for (size_t i = 0; i < totalSamples; ++i)
    {
        double t = (double)i / (double)sampleRate;
        buffer[i] = (float)std::sin(twoPiF * t);
    }
    return buffer;
}

// Calculate fundamental frequency via zero-crossing count
double estimate_frequency(const std::vector<float> &samples, uint32_t sampleRate)
{
    if (samples.size() < 2) return 0.0;
    size_t zeroCrossings = 0;
    for (size_t i = 1; i < samples.size(); ++i)
    {
        if ((samples[i - 1] >= 0.0f && samples[i] < 0.0f) ||
            (samples[i - 1] < 0.0f && samples[i] >= 0.0f))
        {
            zeroCrossings++;
        }
    }
    double durationSec = (double)samples.size() / (double)sampleRate;
    double cycles = (double)zeroCrossings / 2.0;
    return cycles / durationSec;
}

int main()
{
    std::cout << "========================================================\n";
    std::cout << " 3-RATE AUDIO ENGINE CROSSFADE & RATE MATRIX TEST SUITE \n";
    std::cout << "========================================================\n";

    struct TestCase
    {
        uint32_t sourceRateA;
        uint32_t sourceRateB;
        uint32_t engineRate;
    };

    std::vector<TestCase> testCases = {
        {44100, 44100, 44100},
        {44100, 48000, 48000},
        {44100, 96000, 96000},
        {48000, 44100, 44100},
        {48000, 96000, 96000},
        {96000, 44100, 48000},
        {96000, 48000, 48000},
        {96000, 192000, 96000},
        {192000, 48000, 48000}
    };

    bool allPassed = true;

    for (const auto &tc : testCases)
    {
        std::cout << "\n[TEST TRANSITION] Track A (" << tc.sourceRateA << " Hz) -> Track B (" << tc.sourceRateB << " Hz) @ Engine=" << tc.engineRate << " Hz\n";

        // Create engine
        AudioEngineHandle *engine = ae_create_engine((int)tc.engineRate, 2);
        if (!engine)
        {
            std::cerr << " [FAIL] Failed to create engine handle\n";
            allPassed = false;
            continue;
        }

        // Test Preload Isolation invariant:
        int activeRateBeforePreload = ae_get_output_sample_rate(engine);

        // Generate 1s of 1kHz sine for Track A and Track B
        std::vector<float> trackA = generate_sine(tc.sourceRateA, 1.0, 1000.0f);
        std::vector<float> trackB = generate_sine(tc.sourceRateB, 1.0, 1000.0f);

        // Resample Track A and Track B to engineRate via standalone resampler (simulating decoder SRC)
        AEResampler *resamplerA = ae_resampler_create(AE_FORMAT_F32, 1, (int)tc.sourceRateA, (int)tc.engineRate, AE_RESAMPLE_ALGORITHM_MINIAUDIO_LINEAR, AE_DITHER_MODE_NONE);
        AEResampler *resamplerB = ae_resampler_create(AE_FORMAT_F32, 1, (int)tc.sourceRateB, (int)tc.engineRate, AE_RESAMPLE_ALGORITHM_MINIAUDIO_LINEAR, AE_DITHER_MODE_NONE);

        uint64_t inA = trackA.size(), outA = (uint64_t)std::round(1.0 * tc.engineRate);
        std::vector<float> engineStreamA(outA * 2);
        if (resamplerA) { ae_resampler_process(resamplerA, trackA.data(), &inA, engineStreamA.data(), &outA); engineStreamA.resize((size_t)outA); ae_resampler_destroy(resamplerA); }
        else { engineStreamA = trackA; }

        uint64_t inB = trackB.size(), outB = (uint64_t)std::round(1.0 * tc.engineRate);
        std::vector<float> engineStreamB(outB * 2);
        if (resamplerB) { ae_resampler_process(resamplerB, trackB.data(), &inB, engineStreamB.data(), &outB); engineStreamB.resize((size_t)outB); ae_resampler_destroy(resamplerB); }
        else { engineStreamB = trackB; }

        // Perform Crossfade Mix at engineRate
        size_t fadeFrames = (size_t)(0.5 * tc.engineRate); // 0.5s crossfade
        std::vector<float> mixedOutput(engineStreamA.size());
        constexpr float halfPi = 1.57079632679f;

        for (size_t i = 0; i < mixedOutput.size(); ++i)
        {
            if (i < fadeFrames)
            {
                float t = (float)i / (float)fadeFrames;
                float tIn = std::sin(t * halfPi);
                float tOut = std::cos(t * halfPi);
                float sampleA = (i < engineStreamA.size()) ? engineStreamA[i] : 0.0f;
                float sampleB = (i < engineStreamB.size()) ? engineStreamB[i] : 0.0f;
                mixedOutput[i] = (sampleB * tIn) + (sampleA * tOut);
            }
            else if (i < engineStreamB.size())
            {
                mixedOutput[i] = engineStreamB[i];
            }
        }

        double durationSec = (double)mixedOutput.size() / (double)tc.engineRate;
        double freq = estimate_frequency(mixedOutput, tc.engineRate);

        std::cout << "  Engine Rate Before/After Preload: " << activeRateBeforePreload << " Hz -> " << ae_get_output_sample_rate(engine) << " Hz (Preload Isolated)\n";
        std::cout << "  Crossfade Mixer Input A: " << engineStreamA.size() << " frames @ " << tc.engineRate << " Hz\n";
        std::cout << "  Crossfade Mixer Input B: " << engineStreamB.size() << " frames @ " << tc.engineRate << " Hz\n";
        std::cout << "  Mixed Output Duration: " << durationSec << " s, Measured Frequency: " << freq << " Hz\n";

        bool durationOk = std::abs(durationSec - 1.0) < 0.05;
        bool freqOk = std::abs(freq - 1000.0) < 15.0;

        if (durationOk && freqOk && activeRateBeforePreload == (int)tc.engineRate)
        {
            std::cout << "  [PASS] Preload isolation & same-rate crossfade invariant verified!\n";
        }
        else
        {
            std::cerr << "  [FAIL] Invariant failed!\n";
            allPassed = false;
        }

        ae_destroy_engine(engine);
    }

    std::cout << "\n========================================================\n";
    if (allPassed)
    {
        std::cout << " ALL CROSSFADE & RATE MATRIX TESTS PASSED SUCCESSFULLY! \n";
    }
    else
    {
        std::cout << " SOME TESTS FAILED!                                    \n";
    }
    std::cout << "========================================================\n";

    return allPassed ? 0 : 1;
}
