// =============================================================================
// tests/test_tier1_dsp.cpp
//
// Unit tests for Tier 1 DSP enhancements:
//   1. DynamicLoudnessDSP (ISO 226 Equal-Loudness Contour Compensation)
//   2. AutoEqParser (AutoEQ / EqualizerAPO Parametric Profile Parser)
// =============================================================================

#include <cmath>
#include <cstdio>
#include <cstdint>
#include <vector>
#include <string>
#include <algorithm>
#include <cassert>

#include "dsp/dynamic_loudness_dsp.h"
#include "dsp/autoeq_parser.h"

static int g_passes = 0;
static int g_failures = 0;

#define CHECK(cond, msg)                                                        \
    do {                                                                        \
        if (cond) {                                                             \
            ++g_passes;                                                         \
            std::printf("  [PASS] %s\n", msg);                                  \
        } else {                                                                \
            ++g_failures;                                                       \
            std::printf("  [FAIL] %s  (%s:%d)\n", msg, __FILE__, __LINE__);     \
        }                                                                       \
    } while (0)

// Helper: generate sine wave frames (stereo)
static std::vector<float> generateSine(float freqHz, float sampleRate, size_t frameCount)
{
    std::vector<float> buf(frameCount * 2);
    for (size_t i = 0; i < frameCount; ++i) {
        float s = std::sin(2.0f * 3.14159265358979323846f * freqHz * (float)i / sampleRate);
        buf[i * 2 + 0] = s;
        buf[i * 2 + 1] = s;
    }
    return buf;
}

// Helper: compute RMS level in dB
static float computeRmsDb(const float *samples, size_t count)
{
    if (count == 0) return -120.0f;
    double sum = 0.0;
    for (size_t i = 0; i < count; ++i) {
        sum += (double)samples[i] * (double)samples[i];
    }
    double mean = sum / (double)count;
    if (mean <= 1.0e-12) return -120.0f;
    return (float)(10.0 * std::log10(mean));
}

// -----------------------------------------------------------------------------
// Test 1: DynamicLoudnessDSP - Reference Unity & Attenuation Contours
// -----------------------------------------------------------------------------
static void test_dynamic_loudness()
{
    std::printf("\n--- Test: DynamicLoudnessDSP ---\n");
    sauti::dsp::DynamicLoudnessDSP dsp;
    dsp.setSampleRate(48000.0f);
    dsp.setParams(0.0f, 9.0f, 4.5f, 90.0f, 9000.0f);

    CHECK(!dsp.isEnabled(), "Default state is disabled");

    // 1. Bypass when disabled
    {
        auto testBuf = generateSine(50.0f, 48000.0f, 512);
        auto orig = testBuf;
        dsp.process(testBuf.data(), 512, 2, 0.1f);
        bool match = true;
        for (size_t i = 0; i < testBuf.size(); ++i) {
            if (std::abs(testBuf[i] - orig[i]) > 1.0e-6f) {
                match = false;
                break;
            }
        }
        CHECK(match, "Audio passes bit-exact when disabled");
    }

    dsp.setEnabled(true);
    CHECK(dsp.isEnabled(), "Enabled state is true");

    // 2. Reference volume (1.0 = 0 dBFS): Response should be virtually flat (0 dB boost)
    {
        dsp.reset();
        // Warm up parameter smoothing
        std::vector<float> warmup(4096 * 2, 0.0f);
        dsp.process(warmup.data(), 4096, 2, 1.0f);

        float boostBass = 0.0f, boostTreble = 0.0f;
        dsp.getCurrentBoost(&boostBass, &boostTreble);
        CHECK(std::abs(boostBass) < 0.01f && std::abs(boostTreble) < 0.01f,
              "At 0 dBFS reference level, boost is 0.0 dB");

        // Verify 1 kHz sine passes at unity
        auto sine1k = generateSine(1000.0f, 48000.0f, 2048);
        float inRms = computeRmsDb(sine1k.data(), sine1k.size());
        dsp.process(sine1k.data(), 2048, 2, 1.0f);
        float outRms = computeRmsDb(sine1k.data(), sine1k.size());
        CHECK(std::abs(outRms - inRms) < 0.1f, "1 kHz tone has unity gain at 0 dB reference");
    }

    // 3. Attenuated volume (0.1 = -20 dBFS): Bass and Treble should elevate
    {
        dsp.reset();
        // Run enough frames for 30ms smoothing to converge to -20 dB target
        std::vector<float> warmup(8192 * 2, 0.0f);
        dsp.process(warmup.data(), 8192, 2, 0.1f);

        float boostBass = 0.0f, boostTreble = 0.0f;
        dsp.getCurrentBoost(&boostBass, &boostTreble);
        // At -20 dB attenuation, bass boost should be ~20 * 0.26 = 5.2 dB, treble ~20 * 0.12 = 2.4 dB
        CHECK(boostBass >= 4.5f && boostBass <= 6.0f, "At -20 dB volume, bass boost is ~5.2 dB");
        CHECK(boostTreble >= 2.0f && boostTreble <= 3.0f, "At -20 dB volume, treble boost is ~2.4 dB");

        // Verify bass tone (50 Hz) gets boosted relative to mid tone (1 kHz)
        auto sine50 = generateSine(50.0f, 48000.0f, 2048);
        float inRms50 = computeRmsDb(sine50.data(), sine50.size());
        dsp.process(sine50.data(), 2048, 2, 0.1f);
        float outRms50 = computeRmsDb(sine50.data(), sine50.size());
        float actualBassGain = outRms50 - inRms50;
        CHECK(actualBassGain > 3.5f, "50 Hz tone receives substantial low-shelf boost");

        // Verify 1 kHz tone remains relatively neutral
        auto sine1k = generateSine(1000.0f, 48000.0f, 2048);
        float inRms1k = computeRmsDb(sine1k.data(), sine1k.size());
        dsp.process(sine1k.data(), 2048, 2, 0.1f);
        float outRms1k = computeRmsDb(sine1k.data(), sine1k.size());
        CHECK(std::abs(outRms1k - inRms1k) < 0.8f, "1 kHz tone remains neutral in the shelf dip");
    }

    // 4. Extreme attenuation (0.001 = -60 dBFS): Boost should cap at max
    {
        std::vector<float> warmup(8192 * 2, 0.0f);
        dsp.process(warmup.data(), 8192, 2, 0.001f);

        float boostBass = 0.0f, boostTreble = 0.0f;
        dsp.getCurrentBoost(&boostBass, &boostTreble);
        CHECK(std::abs(boostBass - 9.0f) < 0.2f, "Bass boost accurately clamps at configured max (+9.0 dB)");
        CHECK(std::abs(boostTreble - 4.5f) < 0.2f, "Treble boost accurately clamps at configured max (+4.5 dB)");
    }

    // 5. 64-bit float processing verification
    {
        dsp.reset();
        std::vector<double> buf64(2048 * 2, 0.5);
        dsp.process(buf64.data(), 2048, 2, 0.1);
        bool hasValues = true;
        for (double v : buf64) {
            if (std::isnan(v) || std::isinf(v)) {
                hasValues = false;
                break;
            }
        }
        CHECK(hasValues, "64-bit double processing produces valid, non-NaN output");
    }
}

// -----------------------------------------------------------------------------
// Test 2: AutoEqParser - EqualizerAPO String Parsing
// -----------------------------------------------------------------------------
static void test_autoeq_parser()
{
    std::printf("\n--- Test: AutoEqParser ---\n");

    const std::string sampleAutoEq =
        "# AutoEQ export for Sennheiser HD 600 (Harman Over-Ear 2019 Target)\n"
        "Preamp: -6.5 dB\n"
        "\n"
        "Filter 1: ON PK Fc 31 Hz Gain -4.2 dB Q 1.41\n"
        "Filter 2: ON LSC Fc 105 Hz Gain 5.5 dB Q 0.71\n"
        "Filter 3: ON PK Fc 2400 Hz Gain -3.1 dB Q 2.0\n"
        "Filter 4: OFF HSC Fc 10000 Hz Gain -1.5 dB Q 0.71\n"
        "Filter 5: ON NOTCH Fc 60.0 Hz Gain 0.0 dB Q 10.0\n";

    auto profile = sauti::dsp::AutoEqParser::parseString(sampleAutoEq);

    CHECK(profile.isValid, "Profile marked valid");
    CHECK(std::abs(profile.preampDb - (-6.5f)) < 0.01f, "Preamp correctly parsed (-6.5 dB)");
    CHECK(profile.bandCount() == 5, "Parsed exactly 5 bands");

    if (profile.bandCount() == 5) {
        // Band 1: PK 31 Hz, -4.2 dB, Q 1.41
        CHECK(profile.bands[0].type == sauti::dsp::AUTOEQ_BAND_PEAK, "Band 1 is PEAK");
        CHECK(profile.bands[0].enabled == true, "Band 1 is ON");
        CHECK(std::abs(profile.bands[0].frequencyHz - 31.0f) < 0.1f, "Band 1 Fc = 31 Hz");
        CHECK(std::abs(profile.bands[0].gainDb - (-4.2f)) < 0.1f, "Band 1 Gain = -4.2 dB");
        CHECK(std::abs(profile.bands[0].q - 1.41f) < 0.02f, "Band 1 Q = 1.41");

        // Band 2: LSC 105 Hz, +5.5 dB, Q 0.71
        CHECK(profile.bands[1].type == sauti::dsp::AUTOEQ_BAND_LOWSHELF, "Band 2 is LOWSHELF");
        CHECK(std::abs(profile.bands[1].frequencyHz - 105.0f) < 0.1f, "Band 2 Fc = 105 Hz");
        CHECK(std::abs(profile.bands[1].gainDb - 5.5f) < 0.1f, "Band 2 Gain = 5.5 dB");

        // Band 3: PK 2400 Hz, -3.1 dB, Q 2.0
        CHECK(profile.bands[2].type == sauti::dsp::AUTOEQ_BAND_PEAK, "Band 3 is PEAK");
        CHECK(std::abs(profile.bands[2].frequencyHz - 2400.0f) < 0.1f, "Band 3 Fc = 2400 Hz");

        // Band 4: OFF HSC 10000 Hz, -1.5 dB
        CHECK(profile.bands[3].type == sauti::dsp::AUTOEQ_BAND_HIGHSHELF, "Band 4 is HIGHSHELF");
        CHECK(profile.bands[3].enabled == false, "Band 4 is OFF");
        CHECK(std::abs(profile.bands[3].frequencyHz - 10000.0f) < 0.1f, "Band 4 Fc = 10000 Hz");

        // Band 5: NOTCH 60 Hz, Q 10.0
        CHECK(profile.bands[4].type == sauti::dsp::AUTOEQ_BAND_NOTCH, "Band 5 is NOTCH");
        CHECK(std::abs(profile.bands[4].frequencyHz - 60.0f) < 0.1f, "Band 5 Fc = 60 Hz");
        CHECK(std::abs(profile.bands[4].q - 10.0f) < 0.1f, "Band 5 Q = 10.0");
    }

    // Test malformed / empty input
    auto emptyProfile = sauti::dsp::AutoEqParser::parseString("");
    CHECK(!emptyProfile.isValid, "Empty string profile is not valid");
    CHECK(emptyProfile.bandCount() == 0, "Empty profile has 0 bands");

    auto commentsOnly = sauti::dsp::AutoEqParser::parseString("# Just comments\n; Another comment\n// third comment\n");
    CHECK(!commentsOnly.isValid, "Comments-only profile is not valid");
}

int main()
{
    std::printf("=====================================================\n");
    std::printf("Running Tier 1 DSP Test Suite (Dynamic Loudness & AutoEQ)\n");
    std::printf("=====================================================\n");

    test_dynamic_loudness();
    test_autoeq_parser();

    std::printf("\n=====================================================\n");
    std::printf("Results: %d passed, %d failed\n", g_passes, g_failures);
    std::printf("=====================================================\n");

    return (g_failures == 0) ? 0 : 1;
}
