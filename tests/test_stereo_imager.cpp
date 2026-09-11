// Smoke and acoustic verification test for dsp/stereo_imager_dsp.h
// Build: cl /EHsc /std:c++20 /O2 /I. /Idsp tests/test_stereo_imager.cpp
//    or: g++ -std=c++20 -O2 -I. -Idsp tests/test_stereo_imager.cpp -o test_stereo_imager

#include "../dsp/stereo_imager_dsp.h"
#include <cstdio>
#include <cmath>
#include <string>
#include <vector>
#include <algorithm>

using sauti::dsp::StereoImagerDSP;
using sauti::dsp::StereoImagerMode;

static int failures = 0;

static void check(bool cond, const char *msg)
{
    if (!cond) {
        std::printf("FAIL: %s\n", msg);
        failures++;
    } else {
        std::printf("PASS: %s\n", msg);
    }
}

static bool all_finite(const std::vector<float> &b)
{
    for (float v : b) {
        if (!std::isfinite(v)) return false;
    }
    return true;
}

static float peak(const std::vector<float> &b)
{
    float p = 0.0f;
    for (float v : b) p = std::max(p, std::fabs(v));
    return p;
}

int main()
{
    const uint32_t sr = 48000;

    std::printf("=== Running StereoImagerDSP Audiophile Verification Tests ===\n");

    // 1. Disabled DSP must be a bit-exact passthrough
    {
        StereoImagerDSP dsp;
        dsp.setSampleRate((float)sr);
        dsp.setEnabled(false);

        std::vector<float> buf(2 * 512);
        for (size_t i = 0; i < buf.size(); ++i) {
            buf[i] = ((static_cast<int>(i) * 37) % 1000) / 1000.0f - 0.5f;
        }
        auto ref = buf;
        dsp.process(buf.data(), 512, 2);
        check(buf == ref, "Disabled passthrough is bit-exact");
    }

    // 2. Clean Mastering mode on Pure Mono input (L = R) must be bit-exact
    {
        StereoImagerDSP dsp;
        dsp.setSampleRate((float)sr);
        dsp.setEnabled(true);
        dsp.setMode(StereoImagerMode::CleanMastering);
        dsp.setWidth(2.5f); // High width should not affect pure mono!
        dsp.setMonoBelowHz(150.0f);
        dsp.setAirBoostDb(0.0f);

        std::vector<float> buf(2 * 512);
        for (size_t i = 0; i < 512; ++i) {
            float val = 0.4f * std::sin(2.0f * 3.14159f * 440.0f * i / sr);
            buf[2 * i]     = val; // L
            buf[2 * i + 1] = val; // R = L
        }
        auto ref = buf;

        // Warm up smoothing
        for (int w = 0; w < 5; ++w) {
            auto temp = ref;
            dsp.process(temp.data(), 512, 2);
        }

        dsp.process(buf.data(), 512, 2);

        float maxDiff = 0.0f;
        for (size_t i = 0; i < buf.size(); ++i) {
            maxDiff = std::max(maxDiff, std::fabs(buf[i] - ref[i]));
        }
        check(maxDiff < 1.0e-5f, "Clean Mastering on pure mono signal is untouched (M/S identity)");
    }

    // 3. 100% Mono Sum Compatibility in Spatial 3D Velvet Mode
    {
        StereoImagerDSP dsp;
        dsp.setSampleRate((float)sr);
        dsp.setEnabled(true);
        dsp.setMode(StereoImagerMode::Spatial3D);
        dsp.setWidth(2.0f);
        dsp.setAirBoostDb(0.0f);

        std::vector<float> buf(2 * 1024);
        for (size_t i = 0; i < 1024; ++i) {
            float m = 0.3f * std::sin(2.0f * 3.14159f * 1000.0f * i / sr);
            buf[2 * i]     = m;
            buf[2 * i + 1] = m;
        }

        // Process buffer
        dsp.process(buf.data(), 1024, 2);

        // Mono sum: (L + R) / 2 must equal M bit-exact because Velvet decorrelation (+V on L, -V on R) cancels completely
        float maxMonoDiff = 0.0f;
        for (size_t i = 0; i < 1024; ++i) {
            float originalM = 0.3f * std::sin(2.0f * 3.14159f * 1000.0f * i / sr);
            float monoSum = 0.5f * (buf[2 * i] + buf[2 * i + 1]);
            maxMonoDiff = std::max(maxMonoDiff, std::fabs(monoSum - originalM));
        }
        check(maxMonoDiff < 1.0e-5f, "Spatial 3D Velvet decorrelation cancels 100% in mono sum (zero comb filtering)");
    }

    // 4. Sub-Bass Mono Anchor Test (Out-of-phase 50 Hz bass is attenuated on Side)
    {
        StereoImagerDSP dsp;
        dsp.setSampleRate((float)sr);
        dsp.setEnabled(true);
        dsp.setMode(StereoImagerMode::CleanMastering);
        dsp.setWidth(1.0f);
        dsp.setMonoBelowHz(200.0f); // Cut sub-bass stereo difference below 200 Hz
        dsp.setAirBoostDb(0.0f);

        // Feed purely out-of-phase 40 Hz signal: L = +0.5, R = -0.5
        // Side = 0.5, Mid = 0.0
        std::vector<float> buf(2 * 2048);
        for (size_t i = 0; i < 2048; ++i) {
            float s = 0.5f * std::sin(2.0f * 3.14159f * 40.0f * i / sr);
            buf[2 * i]     =  s;
            buf[2 * i + 1] = -s;
        }

        dsp.process(buf.data(), 2048, 2);

        // In the tail of the buffer (steady-state), out-of-phase bass should be attenuated >18 dB
        float tailPeak = 0.0f;
        for (size_t i = 1500; i < 2048; ++i) {
            tailPeak = std::max(tailPeak, std::fabs(buf[2 * i]));
        }
        // At 40Hz with a 200Hz 2nd-order Butterworth (12dB/oct), attenuation is ~28 dB (<0.08 of 0.5)
        check(tailPeak < 0.06f, "Sub-bass mono anchor eliminates out-of-phase low-end cancellation");
    }

    // 5. Soft-Knee Saturation Guard (Prevents digital overs)
    {
        StereoImagerDSP dsp;
        dsp.setSampleRate((float)sr);
        dsp.setEnabled(true);
        dsp.setWidth(3.5f); // Extreme width
        dsp.setAirBoostDb(6.0f);

        std::vector<float> buf(2 * 512);
        for (size_t i = 0; i < buf.size(); ++i) {
            buf[i] = 1.8f * std::sin(i * 0.1f); // Hot signal > 0 dBFS
        }

        dsp.process(buf.data(), 512, 2);
        float p = peak(buf);
        check(p <= 0.985f && all_finite(buf), "Soft-knee limiter caps output safely <= 0.985 with no NaN/Inf");
    }

    // 6. Lock-Free Real-Time Phase Correlation Telemetry
    {
        StereoImagerDSP dsp;
        dsp.setSampleRate((float)sr);
        dsp.setEnabled(true);

        // In-phase signal
        std::vector<float> inPhase(2 * 512);
        for (size_t i = 0; i < 512; ++i) {
            float v = 0.5f * std::sin(i * 0.05f);
            inPhase[2 * i] = v; inPhase[2 * i + 1] = v;
        }
        dsp.process(inPhase.data(), 512, 2);
        float corrIn = dsp.getTelemetryPhaseCorrelation();
        check(corrIn > 0.90f, "Telemetry detects +1.0 in-phase correlation");

        // Out-of-phase signal
        std::vector<float> antiPhase(2 * 512);
        for (size_t i = 0; i < 512; ++i) {
            float v = 0.5f * std::sin(i * 0.05f);
            antiPhase[2 * i] = v; antiPhase[2 * i + 1] = -v;
        }
        for (int rep = 0; rep < 5; ++rep) {
            auto b = antiPhase;
            dsp.process(b.data(), 512, 2);
        }
        float corrAnti = dsp.getTelemetryPhaseCorrelation();
        check(corrAnti < 0.0f, "Telemetry detects negative phase correlation for anti-phase input");
    }

    if (failures == 0) {
        std::printf("ALL TESTS PASSED SUCCESSFULLY! (0 failures)\n");
        return 0;
    } else {
        std::printf("TESTS FAILED: %d failures\n", failures);
        return 1;
    }
}
