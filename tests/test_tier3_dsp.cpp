#include <cstdio>
#include <cstdlib>
#include <cmath>
#include <vector>
#include <iostream>
#include <cassert>

#include "dsp/dynamic_eq_dsp.h"
#include "dsp/tape_drift_dsp.h"

static int g_tests_run = 0;
static int g_tests_failed = 0;

#define CHECK(cond, msg) \
    do { \
        g_tests_run++; \
        if (!(cond)) { \
            std::printf("  [FAIL] %s  (%s:%d)\n", msg, __FILE__, __LINE__); \
            g_tests_failed++; \
        } else { \
            std::printf("  [PASS] %s\n", msg); \
        } \
    } while (0)

static std::vector<float> generateSine(float freqHz, float sampleRate, size_t frameCount, float amp = 1.0f)
{
    std::vector<float> buf(frameCount * 2);
    for (size_t i = 0; i < frameCount; ++i) {
        float s = amp * std::sin(2.0f * 3.14159265358979323846f * freqHz * (float)i / sampleRate);
        buf[i * 2 + 0] = s;
        buf[i * 2 + 1] = s;
    }
    return buf;
}

// -----------------------------------------------------------------------------
// Test 1: DynamicEqDSP - Dynamic Frequency Compression & Expansion
// -----------------------------------------------------------------------------
static void test_dynamic_eq()
{
    std::printf("\n--- Test: DynamicEqDSP ---\n");
    sauti::dsp::DynamicEqDSP deq;
    deq.setSampleRate(48000.0f);

    CHECK(!deq.isEnabled(), "Default state is disabled");

    // 1. Bit-exact bypass when disabled
    {
        auto testBuf = generateSine(1000.0f, 48000.0f, 512, 0.5f);
        auto orig = testBuf;
        deq.process(testBuf.data(), 512, 2);
        bool match = true;
        for (size_t i = 0; i < testBuf.size(); ++i) {
            if (testBuf[i] != orig[i]) { match = false; break; }
        }
        CHECK(match, "Audio passes bit-exact when disabled");
    }

    deq.setEnabled(true);
    CHECK(deq.isEnabled(), "Enabled state is true");

    // 2. Static mode test: pure +6 dB boost at 1000 Hz
    {
        deq.reset();
        sauti::dsp::DynamicEqBandConfig cfg;
        cfg.enabled = true;
        cfg.type = sauti::dsp::DynamicEqFilterType::Peak;
        cfg.mode = sauti::dsp::DynamicEqMode::Static;
        cfg.freq_hz = 1000.0f;
        cfg.q = 1.0f;
        cfg.base_gain_db = 6.0f;
        deq.setBandConfig(0, cfg);

        auto testBuf = generateSine(1000.0f, 48000.0f, 1024, 0.1f);
        deq.process(testBuf.data(), 1024, 2);

        // Peak should be approximately doubled (+6 dB = ~2x linear gain)
        float maxPeak = 0.0f;
        for (size_t i = 512; i < 1024; ++i) { // Measure in steady state
            maxPeak = std::max(maxPeak, std::abs(testBuf[i * 2]));
        }
        CHECK(maxPeak > 0.18f && maxPeak < 0.22f, "Static +6 dB boost amplifies 1 kHz tone by ~2x");
    }

    // 3. Dynamic compression mode:
    // Band 1: 1000 Hz Peak, threshold = -30 dB (amp ~0.0316), range = 6 dB, ratio = 4:1
    {
        deq.reset();
        sauti::dsp::DynamicEqBandConfig cfg;
        cfg.enabled = true;
        cfg.type = sauti::dsp::DynamicEqFilterType::Peak;
        cfg.mode = sauti::dsp::DynamicEqMode::Compress;
        cfg.freq_hz = 1000.0f;
        cfg.q = 2.0f;
        cfg.base_gain_db = 0.0f;
        cfg.threshold_db = -30.0f;
        cfg.range_db = 6.0f;
        cfg.ratio = 4.0f;
        cfg.attack_ms = 1.0f;
        cfg.release_ms = 40.0f;
        deq.setBandConfig(0, cfg);

        // 3a. Quiet signal (-45 dB = 0.0056 amp) -> Below threshold
        auto quietBuf = generateSine(1000.0f, 48000.0f, 1024, 0.005f);
        deq.process(quietBuf.data(), 1024, 2);
        CHECK(deq.getBandGainOffsetDb(0) > -0.2f, "Quiet tone below threshold experiences virtually 0 dB attenuation");

        // 3b. Loud signal (-14 dB = 0.20 amp) -> Above threshold by ~16 dB
        // With ratio 4:1, delta = 16 dB -> gr = -16 * (1 - 1/4) = -12 dB, clamped to range 6 dB
        auto loudBuf = generateSine(1000.0f, 48000.0f, 2048, 0.20f);
        deq.process(loudBuf.data(), 2048, 2);
        float dynOffset = deq.getBandGainOffsetDb(0);
        CHECK(dynOffset < -4.5f && dynOffset >= -6.01f, "Loud tone triggers dynamic gain reduction up to range limit");
    }

    // 4. Low-Shelf and High-Shelf dynamic band configuration verification
    {
        sauti::dsp::DynamicEqBandConfig cfgLow;
        cfgLow.enabled = true;
        cfgLow.type = sauti::dsp::DynamicEqFilterType::LowShelf;
        cfgLow.freq_hz = 120.0f;
        deq.setBandConfig(1, cfgLow);
        CHECK(deq.getBandConfig(1).type == sauti::dsp::DynamicEqFilterType::LowShelf, "Low-Shelf band successfully configured");

        sauti::dsp::DynamicEqBandConfig cfgHigh;
        cfgHigh.enabled = true;
        cfgHigh.type = sauti::dsp::DynamicEqFilterType::HighShelf;
        cfgHigh.freq_hz = 8000.0f;
        deq.setBandConfig(2, cfgHigh);
        CHECK(deq.getBandConfig(2).type == sauti::dsp::DynamicEqFilterType::HighShelf, "High-Shelf band successfully configured");
    }

    // 5. 64-bit double processing verification
    {
        deq.reset();
        std::vector<double> buf64(1024 * 2, 0.25);
        deq.process(buf64.data(), 1024, 2);
        bool hasValues = true;
        for (double v : buf64) {
            if (std::isnan(v) || std::isinf(v)) { hasValues = false; break; }
        }
        CHECK(hasValues, "64-bit double processing produces valid, non-NaN output");
    }
}

// -----------------------------------------------------------------------------
// Test 2: TapeDriftDSP - Wow, Flutter & Tape Damping
// -----------------------------------------------------------------------------
static void test_tape_drift()
{
    std::printf("\n--- Test: TapeDriftDSP ---\n");
    sauti::dsp::TapeDriftDSP tape;
    tape.setSampleRate(48000.0f);

    CHECK(!tape.isEnabled(), "Default state is disabled");

    // 1. Bit-exact bypass when disabled
    {
        auto testBuf = generateSine(1000.0f, 48000.0f, 512, 0.5f);
        auto orig = testBuf;
        tape.process(testBuf.data(), 512, 2);
        bool match = true;
        for (size_t i = 0; i < testBuf.size(); ++i) {
            if (testBuf[i] != orig[i]) { match = false; break; }
        }
        CHECK(match, "Audio passes bit-exact when disabled");
    }

    tape.setEnabled(true);
    CHECK(tape.isEnabled(), "Enabled state is true");

    // 2. Preset switching verification
    tape.setPreset(sauti::dsp::TapeDriftPreset::VintageReelToReel);
    CHECK(tape.getPreset() == sauti::dsp::TapeDriftPreset::VintageReelToReel, "Preset set to VintageReelToReel");

    float wowRate, wowDepth, flutterRate, flutterDepth, driftDepth, stereoPhase, hfDamping;
    tape.getParams(&wowRate, &wowDepth, &flutterRate, &flutterDepth, &driftDepth, &stereoPhase, &hfDamping);
    CHECK(std::abs(wowRate - 1.0f) < 0.01f, "VintageReelToReel wow rate is 1.0 Hz");
    CHECK(std::abs(stereoPhase - 60.0f) < 0.01f, "VintageReelToReel stereo phase is 60 deg");

    // 3. Audio processing produces valid delayed & modulated output
    {
        tape.reset();
        auto testBuf = generateSine(440.0f, 48000.0f, 4800, 0.5f); // 100 ms
        tape.process(testBuf.data(), 4800, 2);

        bool finite = true;
        float energy = 0.0f;
        for (size_t i = 2000; i < testBuf.size(); ++i) { // Measure after initial buffer fill
            if (std::isnan(testBuf[i]) || std::isinf(testBuf[i])) finite = false;
            energy += std::abs(testBuf[i]);
        }
        CHECK(finite, "Modulated audio samples are finite and non-NaN");
        CHECK(energy > 10.0f, "Audio successfully transmitted through fractional delay buffer");
    }

    // 4. Stereo phase produces decorrelated channel outputs
    {
        tape.reset();
        tape.setParams(1.0f, 2.0f, 10.0f, 0.5f, 0.5f, 90.0f, 20000.0f); // 90 deg stereo phase
        auto monoSine = generateSine(1000.0f, 48000.0f, 2400, 0.5f);
        tape.process(monoSine.data(), 2400, 2);

        // Due to 90 deg phase offset, Left and Right channels should differ during active modulation
        float diffSum = 0.0f;
        for (size_t i = 1200; i < 2400; ++i) {
            diffSum += std::abs(monoSine[i * 2 + 0] - monoSine[i * 2 + 1]);
        }
        CHECK(diffSum > 1.0f, "Stereo phase offset generates decorrelated spatial audio");
    }

    // 5. High-frequency tape damping verification
    {
        tape.reset();
        tape.setParams(0.0f, 0.0f, 0.0f, 0.0f, 0.0f, 0.0f, 5000.0f); // Zero modulation, 5 kHz HF roll-off
        auto hfBuf = generateSine(15000.0f, 48000.0f, 2048, 0.5f); // 15 kHz tone
        tape.process(hfBuf.data(), 2048, 2);

        float peak = 0.0f;
        for (size_t i = 1500; i < 2048; ++i) {
            peak = std::max(peak, std::abs(hfBuf[i * 2]));
        }
        // At 15 kHz with 5 kHz 1-pole filter, gain is 5/sqrt(5^2 + 15^2) ≈ 5/15.8 ≈ 0.316 * 0.5 ≈ 0.158
        CHECK(peak < 0.25f, "HF damping filter attenuates 15 kHz high frequencies as expected");
    }

    // 6. 64-bit double processing verification
    {
        tape.reset();
        std::vector<double> buf64(1024 * 2, 0.3);
        tape.process(buf64.data(), 1024, 2);
        bool finite = true;
        for (double v : buf64) {
            if (std::isnan(v) || std::isinf(v)) { finite = false; break; }
        }
        CHECK(finite, "64-bit double processing produces valid, non-NaN output");
    }
}

int main()
{
    std::printf("=====================================================\n");
    std::printf("Running Tier 3 DSP Test Suite (Dynamic EQ & Tape Drift)\n");
    std::printf("=====================================================\n");

    test_dynamic_eq();
    test_tape_drift();

    std::printf("\n=====================================================\n");
    std::printf("Results: %d passed, %d failed\n", g_tests_run - g_tests_failed, g_tests_failed);
    std::printf("=====================================================\n");

    return (g_tests_failed == 0) ? 0 : 1;
}
