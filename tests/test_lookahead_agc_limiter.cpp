// =============================================================================
// tests/test_lookahead_agc_limiter.cpp
//
// Unit tests for LookaheadAgcLimiterDSP:
//   1. Bypass transparency (disabled passes signal bit-identically)
//   2. Quiet passage AGC boost toward target LUFS within max_boost_db
//   3. Silence gate freeze (noise floor below gate never boosts)
//   4. Sudden 0 dBFS 55 Hz bass hit after quiet +9 dB AGC boost:
//      zero clipping above ceiling and ultra-low bass THD
//   5. Band isolation: loud 60 Hz bass engages Low GR without pumping 1 kHz mid
//   6. Float32 / Double64 parity and stability across 44.1 / 48 / 96 kHz
// =============================================================================

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <cstdio>
#include <vector>

#include "dsp/lookahead_agc_limiter_dsp.h"

static int g_failures = 0;
static int g_passes = 0;

#define CHECK(cond, msg)                                                    \
    do {                                                                    \
        if (cond) {                                                         \
            ++g_passes;                                                     \
            std::printf("  [PASS] %s\n", msg);                              \
        } else {                                                            \
            ++g_failures;                                                   \
            std::printf("  [FAIL] %s  (%s:%d)\n", msg, __FILE__, __LINE__); \
        }                                                                   \
    } while (0)

static constexpr double kPi = 3.14159265358979323846;

static double computeDftMag(const std::vector<float>& mono, double freqHz, double sampleRate) {
    double re = 0.0;
    double im = 0.0;
    const size_t n = mono.size();
    const double w = 2.0 * kPi * freqHz / sampleRate;
    for (size_t i = 0; i < n; ++i) {
        const double hann = 0.5 * (1.0 - std::cos(2.0 * kPi * static_cast<double>(i) / static_cast<double>(n - 1)));
        const double x = static_cast<double>(mono[i]) * hann;
        re += x * std::cos(w * static_cast<double>(i));
        im -= x * std::sin(w * static_cast<double>(i));
    }
    return 2.0 * std::hypot(re, im) / (0.5 * static_cast<double>(n));
}

static void test_bypass_transparency() {
    std::printf("\n== Test 1: Bypass Transparency ==\n");
    sauti::dsp::LookaheadAgcLimiterDSP dsp;
    dsp.setSampleRate(48000.0f);
    dsp.setEnabled(false);

    const size_t frames = 512;
    std::vector<float> buf32(frames * 2);
    std::vector<double> buf64(frames * 2);
    for (size_t i = 0; i < frames; ++i) {
        const double s = 0.75 * std::sin(2.0 * kPi * 440.0 * static_cast<double>(i) / 48000.0);
        buf32[2 * i] = static_cast<float>(s);
        buf32[2 * i + 1] = static_cast<float>(-s * 0.5);
        buf64[2 * i] = s;
        buf64[2 * i + 1] = -s * 0.5;
    }
    const auto orig32 = buf32;
    const auto orig64 = buf64;

    dsp.process(buf32.data(), frames, 2);
    dsp.process(buf64.data(), frames, 2);

    bool exact32 = true;
    bool exact64 = true;
    for (size_t i = 0; i < buf32.size(); ++i) {
        if (buf32[i] != orig32[i]) exact32 = false;
        if (buf64[i] != orig64[i]) exact64 = false;
    }
    CHECK(exact32, "float32 output bit-identical when disabled");
    CHECK(exact64, "float64 output bit-identical when disabled");
}

static void test_quiet_passage_boost() {
    std::printf("\n== Test 2: Quiet Passage AGC Boost ==\n");
    sauti::dsp::LookaheadAgcLimiterDSP dsp;
    dsp.setSampleRate(48000.0f);
    dsp.setParams(-14.0f, 9.0f, 15.0f, 4.0f, 6.0f, -45.0f, 10.0f, -0.1f, 180.0f, 3000.0f, 160.0f);
    dsp.setEnabled(true);

    // Feed 3 seconds of -28 dBFS 1 kHz sine in 512-frame blocks
    const double amp = std::pow(10.0, -28.0 / 20.0);
    const size_t block = 512;
    const size_t totalBlocks = (48000 * 3) / block;
    std::vector<float> buf(block * 2);

    size_t phaseIdx = 0;
    for (size_t b = 0; b < totalBlocks; ++b) {
        for (size_t i = 0; i < block; ++i) {
            const float s = static_cast<float>(amp * std::sin(2.0 * kPi * 1000.0 * static_cast<double>(phaseIdx++) / 48000.0));
            buf[2 * i] = s;
            buf[2 * i + 1] = s;
        }
        dsp.process(buf.data(), block, 2);
    }

    float agcDb = 0.0f, lowGr = 0.0f, midGr = 0.0f, highGr = 0.0f, peakGr = 0.0f;
    dsp.getTelemetry(&agcDb, &lowGr, &midGr, &highGr, &peakGr);
    std::printf("  Telemetry after 3s @ -28 dBFS: agc=%.2f dB, lowGr=%.2f, midGr=%.2f\n", agcDb, lowGr, midGr);
    CHECK(agcDb > 7.0f && agcDb <= 9.05f, "quiet -28 dBFS signal boosted cleanly up toward +9 dB limit");
    CHECK(midGr > -0.1f && peakGr > -0.1f, "no unnecessary limiting on quiet passage");
}

static void test_silence_gate_freeze() {
    std::printf("\n== Test 3: Silence Gate Freeze ==\n");
    sauti::dsp::LookaheadAgcLimiterDSP dsp;
    dsp.setSampleRate(48000.0f);
    dsp.setParams(-14.0f, 12.0f, 15.0f, 6.0f, 6.0f, -45.0f, 10.0f, -0.1f, 180.0f, 3000.0f, 160.0f);
    dsp.setEnabled(true);

    // Feed 2 seconds of -60 dBFS floor (below -45 LUFS gate)
    const double amp = std::pow(10.0, -60.0 / 20.0);
    const size_t block = 512;
    const size_t totalBlocks = (48000 * 2) / block;
    std::vector<float> buf(block * 2);

    size_t phaseIdx = 0;
    float steadyMaxOut = 0.0f;
    for (size_t b = 0; b < totalBlocks; ++b) {
        for (size_t i = 0; i < block; ++i) {
            const float s = static_cast<float>(amp * std::sin(2.0 * kPi * 500.0 * static_cast<double>(phaseIdx++) / 48000.0));
            buf[2 * i] = s;
            buf[2 * i + 1] = s;
        }
        dsp.process(buf.data(), block, 2);
        if (b >= 10) {
            for (float v : buf) steadyMaxOut = std::max(steadyMaxOut, std::abs(v));
        }
    }

    float agcDb = 0.0f;
    dsp.getTelemetry(&agcDb, nullptr, nullptr, nullptr, nullptr);
    std::printf("  Telemetry after 2s @ -60 dBFS: agc=%.3f dB, steadyMaxOut=%.6f\n", agcDb, steadyMaxOut);
    CHECK(std::abs(agcDb) < 0.05f, "AGC stays frozen at 0.0 dB below silence gate");
    CHECK(steadyMaxOut <= static_cast<float>(amp * 1.01), "noise floor is never amplified");
}

static void test_sudden_bass_hit_after_agc_boost() {
    std::printf("\n== Test 4: Sudden 0 dBFS 55 Hz Bass Hit After +9 dB AGC Boost ==\n");
    sauti::dsp::LookaheadAgcLimiterDSP dsp;
    dsp.setSampleRate(48000.0f);
    const float ceilingDb = -0.1f;
    const float ceilingLin = std::pow(10.0f, ceilingDb / 20.0f);
    dsp.setParams(-14.0f, 9.0f, 15.0f, 6.0f, 8.0f, -45.0f, 10.0f, ceilingDb, 180.0f, 3000.0f, 160.0f);
    dsp.setEnabled(true);

    // Phase A: 2 seconds of -26 dBFS mid-range signal so AGC ramps up to +9 dB
    const double quietAmp = std::pow(10.0, -26.0 / 20.0);
    const size_t block = 256;
    std::vector<float> buf(block * 2);
    for (size_t b = 0; b < (48000 * 2) / block; ++b) {
        for (size_t i = 0; i < block; ++i) {
            const size_t idx = b * block + i;
            const float s = static_cast<float>(quietAmp * std::sin(2.0 * kPi * 1000.0 * static_cast<double>(idx) / 48000.0));
            buf[2 * i] = s;
            buf[2 * i + 1] = s;
        }
        dsp.process(buf.data(), block, 2);
    }

    float preAgcDb = 0.0f;
    dsp.getTelemetry(&preAgcDb, nullptr, nullptr, nullptr, nullptr);

    // Phase B: Sudden 0 dBFS (1.0 amplitude) 55 Hz bass burst for 0.6 seconds
    const size_t bassFrames = 48000 * 6 / 10;
    std::vector<float> bassLeft;
    bassLeft.reserve(bassFrames);

    float maxBassOut = 0.0f;
    for (size_t offset = 0; offset < bassFrames; offset += block) {
        const size_t n = std::min(block, bassFrames - offset);
        for (size_t i = 0; i < n; ++i) {
            const double t = static_cast<double>(offset + i) / 48000.0;
            const float s = static_cast<float>(1.0 * std::sin(2.0 * kPi * 55.0 * t));
            buf[2 * i] = s;
            buf[2 * i + 1] = s;
        }
        dsp.process(buf.data(), n, 2);
        for (size_t i = 0; i < n; ++i) {
            maxBassOut = std::max(maxBassOut, std::max(std::abs(buf[2 * i]), std::abs(buf[2 * i + 1])));
            bassLeft.push_back(buf[2 * i]);
        }
    }

    // Measure THD on steady portion (skip first 60 ms transition)
    std::vector<float> steady(bassLeft.begin() + 2880, bassLeft.end());
    const double fund = computeDftMag(steady, 55.0, 48000.0);
    double harmSq = 0.0;
    for (int h = 2; h <= 7; ++h) {
        const double hm = computeDftMag(steady, 55.0 * h, 48000.0);
        harmSq += hm * hm;
    }
    const double thdPct = (fund > 1e-6) ? (100.0 * std::sqrt(harmSq) / fund) : 100.0;

    float postAgcDb = 0.0f;
    dsp.getTelemetry(&postAgcDb, nullptr, nullptr, nullptr, nullptr);
    std::printf("  Pre-hit AGC=%.2f dB -> Post-hit AGC=%.2f dB, maxPeak=%.6f (ceil=%.6f), 55 Hz THD=%.3f%%\n",
                preAgcDb, postAgcDb, maxBassOut, ceilingLin, thdPct);

    CHECK(preAgcDb > 7.5f, "AGC had ramped boost up before the bass hit");
    CHECK(maxBassOut <= ceilingLin + 1.0e-4f, "sudden 0 dBFS bass hit never overshoots ceiling");
    CHECK(postAgcDb < 1.0f, "lookahead guard backed off AGC boost during 0 dBFS bass burst");
    CHECK(thdPct < 1.0, "55 Hz bass waveform stays clean (< 1% THD, no cycle-ripple distortion)");
}

static void test_band_isolation_no_vocal_pumping() {
    std::printf("\n== Test 5: 3-Band Isolation (Bass Limiting Without Mid/Vocal Pumping) ==\n");
    sauti::dsp::LookaheadAgcLimiterDSP dsp;
    dsp.setSampleRate(48000.0f);
    // Lock AGC boost/attenuation to 0 dB to isolate the 3-band lookahead limiter stage
    dsp.setParams(-14.0f, 0.0f, 0.0f, 1.0f, 4.0f, -45.0f, 10.0f, -0.1f, 180.0f, 3000.0f, 160.0f);
    dsp.setEnabled(true);

    const double midAmp = std::pow(10.0, -18.0 / 20.0); // ~0.12589
    const double bassAmp = 1.25;                        // hot +1.9 dBFS 60 Hz bass
    const size_t totalFrames = 48000;
    const size_t block = 512;
    std::vector<float> buf(block * 2);
    std::vector<float> monoOut;
    monoOut.reserve(totalFrames);

    for (size_t offset = 0; offset < totalFrames; offset += block) {
        const size_t n = std::min(block, totalFrames - offset);
        for (size_t i = 0; i < n; ++i) {
            const double t = static_cast<double>(offset + i) / 48000.0;
            const float s = static_cast<float>(bassAmp * std::sin(2.0 * kPi * 60.0 * t) +
                                               midAmp * std::sin(2.0 * kPi * 1000.0 * t));
            buf[2 * i] = s;
            buf[2 * i + 1] = s;
        }
        dsp.process(buf.data(), n, 2);
        for (size_t i = 0; i < n; ++i) {
            monoOut.push_back(buf[2 * i]);
        }
    }

    float agcDb = 0.0f, lowGr = 0.0f, midGr = 0.0f, highGr = 0.0f, peakGr = 0.0f;
    dsp.getTelemetry(&agcDb, &lowGr, &midGr, &highGr, &peakGr);

    std::vector<float> steady(monoOut.begin() + 12000, monoOut.end());
    const double measuredMid = computeDftMag(steady, 1000.0, 48000.0);
    const double midLossDb = 20.0 * std::log10(std::max(measuredMid, 1e-6) / midAmp);

    std::printf("  lowGr=%.2f dB, midGr=%.2f dB, highGr=%.2f dB, peakGr=%.2f dB, 1kHz delta=%.3f dB\n",
                lowGr, midGr, highGr, peakGr, midLossDb);

    CHECK(lowGr < -2.0f, "Low band strongly limits hot 60 Hz bass");
    CHECK(midGr > -0.05f && highGr > -0.05f, "Mid & High limiters stay at 0 dB GR");
    CHECK(peakGr > -0.05f, "Final broadband safety limiter stays idle (0 dB GR)");
    CHECK(std::abs(midLossDb) < 0.25, "1 kHz mid tone level preserved within 0.25 dB (no bass pumping)");
}

static void test_float64_parity_and_rates() {
    std::printf("\n== Test 6: Float32/Float64 Parity & Multi-Sample-Rate Stability ==\n");
    const float rates[] = {44100.0f, 48000.0f, 96000.0f};
    bool allFinite = true;
    double maxParityDiff = 0.0;

    for (float sr : rates) {
        sauti::dsp::LookaheadAgcLimiterDSP d32;
        sauti::dsp::LookaheadAgcLimiterDSP d64;
        d32.setSampleRate(sr);
        d64.setSampleRate(sr);
        d32.setParams(-14.0f, 9.0f, 15.0f, 2.0f, 4.0f, -45.0f, 10.0f, -0.1f, 180.0f, 3000.0f, 160.0f);
        d64.setParams(-14.0f, 9.0f, 15.0f, 2.0f, 4.0f, -45.0f, 10.0f, -0.1f, 180.0f, 3000.0f, 160.0f);
        d32.setEnabled(true);
        d64.setEnabled(true);

        const size_t frames = 4096;
        std::vector<float> b32(frames * 2);
        std::vector<double> b64(frames * 2);
        for (size_t i = 0; i < frames; ++i) {
            const double t = static_cast<double>(i) / static_cast<double>(sr);
            const double s = 0.4 * std::sin(2.0 * kPi * 70.0 * t) + 0.3 * std::sin(2.0 * kPi * 1200.0 * t);
            b32[2 * i] = static_cast<float>(s);
            b32[2 * i + 1] = static_cast<float>(s * 0.8);
            b64[2 * i] = s;
            b64[2 * i + 1] = s * 0.8;
        }
        d32.process(b32.data(), frames, 2);
        d64.process(b64.data(), frames, 2);

        for (size_t i = 0; i < b32.size(); ++i) {
            if (!std::isfinite(b32[i]) || !std::isfinite(b64[i])) {
                allFinite = false;
            }
            maxParityDiff = std::max(maxParityDiff, std::abs(static_cast<double>(b32[i]) - b64[i]));
        }
    }

    std::printf("  allFinite=%s, max float32 vs float64 diff=%.2e\n", allFinite ? "true" : "false", maxParityDiff);
    CHECK(allFinite, "all outputs finite across 44.1 / 48 / 96 kHz");
    CHECK(maxParityDiff < 1.0e-4, "float32 and float64 paths match within 1e-4");
}

int main() {
    test_bypass_transparency();
    test_quiet_passage_boost();
    test_silence_gate_freeze();
    test_sudden_bass_hit_after_agc_boost();
    test_band_isolation_no_vocal_pumping();
    test_float64_parity_and_rates();

    std::printf("\n========================================\n");
    std::printf("LookaheadAgcLimiterDSP tests: %d passed, %d failed\n", g_passes, g_failures);
    std::printf("========================================\n");
    return (g_failures == 0) ? 0 : 1;
}
