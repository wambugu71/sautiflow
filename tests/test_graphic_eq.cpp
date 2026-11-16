#define _USE_MATH_DEFINES
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <vector>
#include <algorithm>
#include <chrono>

#include "dsp/graphic_eq_dsp.h"

using namespace sauti::dsp;

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

// -----------------------------------------------------------------------------
// Test 1: Auto-Q Calculation for Standard ISO Grids
// -----------------------------------------------------------------------------
static void test_auto_q_calculation() {
    std::printf("\n== Test 1: Auto-Q Calculation for Standard ISO Grids ==\n");
    GraphicEqDSP eq;

    // 10-band octave ISO grid
    const float freqs10[10] = {31.5f, 63.0f, 125.0f, 250.0f, 500.0f, 1000.0f, 2000.0f, 4000.0f, 8000.0f, 16000.0f};
    eq.init(10, freqs10, nullptr, 48000.0);

    CHECK(eq.getBandCount() == 10, "Band count is 10");
    double q1k = eq.getQ(5); // 1 kHz band
    CHECK(std::abs(q1k - 1.4142) < 0.05, "10-band auto-Q is approximately 1.414 (1-octave)");
    std::printf("  [INFO] 10-Band Q at 1kHz: %.4f\n", q1k);

    // 32-band 1/3-octave ISO grid
    const float freqs32[32] = {
        16.0f, 20.0f, 25.0f, 31.5f, 40.0f, 50.0f, 63.0f, 80.0f, 100.0f, 125.0f,
        160.0f, 200.0f, 250.0f, 315.0f, 400.0f, 500.0f, 630.0f, 800.0f, 1000.0f, 1250.0f,
        1600.0f, 2000.0f, 2500.0f, 3150.0f, 4000.0f, 5000.0f, 6300.0f, 8000.0f, 10000.0f, 12500.0f,
        16000.0f, 20000.0f
    };
    eq.init(32, freqs32, nullptr, 48000.0);
    CHECK(eq.getBandCount() == 32, "Band count is 32");
    double q32_1k = eq.getQ(18); // 1 kHz band in 32-band grid
    CHECK(q32_1k >= 4.0 && q32_1k <= 4.6, "32-band auto-Q is approximately 4.3 (1/3-octave)");
    std::printf("  [INFO] 32-Band Q at 1kHz: %.4f\n", q32_1k);
}

// -----------------------------------------------------------------------------
// Test 2: Matrix Decoupling vs Uncompensated Cascaded Ripple
// -----------------------------------------------------------------------------
static void test_matrix_decoupling_anti_ripple() {
    std::printf("\n== Test 2: Matrix Decoupling Eliminates Skirt Accumulation ==\n");
    GraphicEqDSP eqComp;
    GraphicEqDSP eqLegacy;

    const float freqs10[10] = {31.5f, 63.0f, 125.0f, 250.0f, 500.0f, 1000.0f, 2000.0f, 4000.0f, 8000.0f, 16000.0f};
    eqComp.init(10, freqs10, nullptr, 48000.0, GraphicEqDSP::EqTopology::MatrixCompensatedCascade);
    eqLegacy.init(10, freqs10, nullptr, 48000.0, GraphicEqDSP::EqTopology::LegacyCascade);

    // Scenario: User boosts 3 adjacent bands (500 Hz, 1 kHz, 2 kHz) to +6.0 dB
    eqComp.setBandGain(4, 6.0); // 500 Hz
    eqComp.setBandGain(5, 6.0); // 1 kHz
    eqComp.setBandGain(6, 6.0); // 2 kHz

    eqLegacy.setBandGain(4, 6.0);
    eqLegacy.setBandGain(5, 6.0);
    eqLegacy.setBandGain(6, 6.0);

    // Evaluate response at 1 kHz
    double respComp1k = eqComp.evaluateCompositeResponseDb(1000.0);
    double respLegacy1k = eqLegacy.evaluateCompositeResponseDb(1000.0);

    std::printf("  [INFO] Uncompensated Legacy Cascade Response at 1 kHz: %.2f dB (ballooning from +6.0 dB!)\n", respLegacy1k);
    std::printf("  [INFO] Matrix-Compensated Response at 1 kHz:           %.2f dB (locked to +6.0 dB target)\n", respComp1k);

    CHECK(respLegacy1k > 8.0, "Legacy cascaded biquads suffer from severe gain accumulation (> 8.0 dB at 1 kHz)");
    CHECK(std::abs(respComp1k - 6.0) < 0.15, "Matrix-compensated response matches target (+6.0 dB) within 0.15 dB");

    // Also check 500 Hz and 2 kHz
    double respComp500 = eqComp.evaluateCompositeResponseDb(500.0);
    double respComp2k = eqComp.evaluateCompositeResponseDb(2000.0);
    CHECK(std::abs(respComp500 - 6.0) < 0.15, "Matrix-compensated response at 500 Hz matches target within 0.15 dB");
    CHECK(std::abs(respComp2k - 6.0) < 0.15, "Matrix-compensated response at 2000 Hz matches target within 0.15 dB");

    // Check neighboring band 250 Hz (should remain near 0 dB, not pumped up)
    double respComp250 = eqComp.evaluateCompositeResponseDb(250.0);
    std::printf("  [INFO] Matrix-Compensated Response at 250 Hz: %.2f dB\n", respComp250);
    CHECK(std::abs(respComp250) < 0.2, "Skirt leakage into non-boosted adjacent bands is eliminated (< 0.2 dB)");
}

// -----------------------------------------------------------------------------
// Test 3: Flat Bypass Bit-Exact Passthrough
// -----------------------------------------------------------------------------
static void test_flat_bypass_bit_exact() {
    std::printf("\n== Test 3: Flat Bypass Bit-Exact Passthrough at 0.0 dB ==\n");
    GraphicEqDSP eq;
    const float freqs10[10] = {31.5f, 63.0f, 125.0f, 250.0f, 500.0f, 1000.0f, 2000.0f, 4000.0f, 8000.0f, 16000.0f};
    eq.init(10, freqs10, nullptr, 48000.0);

    CHECK(eq.isFlat(), "EQ is initially flat");

    const size_t frames = 1024;
    const int channels = 2;
    std::vector<float> input(frames * channels);
    for (size_t i = 0; i < input.size(); ++i) {
        input[i] = ((float)(i % 100) / 50.0f) - 1.0f;
    }
    std::vector<float> output = input;

    eq.process(output.data(), frames, channels);

    bool bitExact = true;
    for (size_t i = 0; i < input.size(); ++i) {
        if (input[i] != output[i]) {
            bitExact = false;
            break;
        }
    }
    CHECK(bitExact, "Flat bypass preserves 100% bit-exact audio with zero calculations");
}

// -----------------------------------------------------------------------------
// Test 4: Audio Processing Stability in Float32 and Float64
// -----------------------------------------------------------------------------
static void test_audio_processing_stability() {
    std::printf("\n== Test 4: Audio Processing Stability in Float32 and Float64 ==\n");
    GraphicEqDSP eq;
    const float freqs10[10] = {31.5f, 63.0f, 125.0f, 250.0f, 500.0f, 1000.0f, 2000.0f, 4000.0f, 8000.0f, 16000.0f};
    eq.init(10, freqs10, nullptr, 48000.0);

    // Apply high-contrast EQ curve
    eq.setBandGain(0, 10.0);
    eq.setBandGain(1, -8.0);
    eq.setBandGain(2, 6.0);
    eq.setBandGain(3, -4.0);
    eq.setBandGain(4, 3.0);
    eq.setBandGain(5, 0.0);
    eq.setBandGain(6, -3.0);
    eq.setBandGain(7, 5.0);
    eq.setBandGain(8, -6.0);
    eq.setBandGain(9, 8.0);

    CHECK(!eq.isFlat(), "EQ is not flat after applying gains");

    const size_t frames = 48000; // 1 second
    const int channels = 2;
    std::vector<float> f32(frames * channels, 0.5f);
    std::vector<double> f64(frames * channels, 0.5);

    eq.process(f32.data(), frames, channels);
    eq.process(f64.data(), frames, channels);

    bool hasNaN = false;
    bool hasInf = false;
    for (float v : f32) {
        if (std::isnan(v)) hasNaN = true;
        if (std::isinf(v)) hasInf = true;
    }
    for (double v : f64) {
        if (std::isnan(v)) hasNaN = true;
        if (std::isinf(v)) hasInf = true;
    }

    CHECK(!hasNaN, "No NaN values in float32 or float64 processed streams");
    CHECK(!hasInf, "No Inf values in float32 or float64 processed streams");
}

// -----------------------------------------------------------------------------
// Test 5: Nyquist-Band Matrix Decoupling Alignment (32-Band @ 20 kHz)
// -----------------------------------------------------------------------------
static void test_nyquist_band_decoupling_alignment() {
    std::printf("\n== Test 5: Nyquist-Band Matrix Decoupling Alignment (32-Band @ 20 kHz) ==\n");
    const float freqs32[32] = {
        20.0f, 25.0f, 31.5f, 40.0f, 50.0f, 63.0f, 80.0f, 100.0f,
        125.0f, 160.0f, 200.0f, 250.0f, 315.0f, 400.0f, 500.0f, 630.0f,
        800.0f, 1000.0f, 1250.0f, 1600.0f, 2000.0f, 2500.0f, 3150.0f, 4000.0f,
        5000.0f, 6300.0f, 8000.0f, 10000.0f, 12500.0f, 16000.0f, 18000.0f, 20000.0f
    };

    GraphicEqDSP eqLegacy44k;
    eqLegacy44k.init(32, freqs32, nullptr, 44100.0, GraphicEqDSP::EqTopology::LegacyCascade);
    eqLegacy44k.setBandGain(31, 6.0);
    const double evalMatch = eqLegacy44k.evaluateCompositeResponseDb(20000.0);
    const double svfDirect = CytomicSVF::evaluateResponseDb(
        CytomicSVF::FilterType::Bell, 44100.0, 20000.0, 6.0, eqLegacy44k.getQ(31), 20000.0);
    CHECK(std::abs(evalMatch - svfDirect) < 1.0e-9,
          "GraphicEq single-band 20 kHz evaluation matches CytomicSVF::evaluateResponseDb exactly");
    CHECK(std::abs(evalMatch - 6.0) < 0.01,
          "GraphicEq 20 kHz band hits +6.0 dB at 44.1 kHz without cramping or clamping");

    const double sampleRates[2] = {44100.0, 48000.0};
    for (double fs : sampleRates) {
        GraphicEqDSP eqAll6;
        eqAll6.init(32, freqs32, nullptr, fs, GraphicEqDSP::EqTopology::MatrixCompensatedCascade);
        for (int b = 0; b < 32; ++b) eqAll6.setBandGain(b, 6.0);
        const double comp20k = eqAll6.evaluateCompositeResponseDb(20000.0);
        std::printf("  32-Band all +6 dB @ %.0f Hz -> composite 20 kHz = %+.3f dB\n", fs, comp20k);
        CHECK(std::abs(comp20k - 6.0) < 0.25,
              "32-band matrix decoupling holds 20 kHz at +6.0 dB (+/-0.25 dB)");

        GraphicEqDSP eqSingle12;
        eqSingle12.init(32, freqs32, nullptr, fs, GraphicEqDSP::EqTopology::MatrixCompensatedCascade);
        eqSingle12.setBandGain(31, 12.0);
        const double single20k = eqSingle12.evaluateCompositeResponseDb(20000.0);
        CHECK(std::abs(single20k - 12.0) < 0.25,
              "32-band single 20 kHz band @ +12 dB hits target without clamping");
    }

    // Verify steady-state time-domain 32-band 20 kHz boost @ 48 kHz
    GraphicEqDSP eqAudio;
    eqAudio.init(32, freqs32, nullptr, 48000.0, GraphicEqDSP::EqTopology::MatrixCompensatedCascade);
    eqAudio.setBandGain(31, 6.0);
    const uint32_t N = 24000;
    std::vector<double> audio(N * 2);
    for (uint32_t i = 0; i < N; ++i) {
        const double s = std::cos(2.0 * M_PI * 20000.0 * (double)i / 48000.0);
        audio[i * 2 + 0] = s;
        audio[i * 2 + 1] = s;
    }
    eqAudio.process(audio.data(), N, 2);
    const uint32_t win = 4800; // Exact 2000 cycles @ 20 kHz / 48 kHz
    double sumSq = 0.0;
    bool finiteOk = true;
    for (uint32_t i = N - win; i < N; ++i) {
        if (!std::isfinite(audio[i * 2])) finiteOk = false;
        sumSq += audio[i * 2] * audio[i * 2];
    }
    const double rmsAmp = std::sqrt(2.0 * sumSq / static_cast<double>(win));
    const double measuredDb = 20.0 * std::log10(std::max(rmsAmp, 1e-12));
    std::printf("  32-Band audio 20 kHz (+6 dB @ 48 kHz): measured = %+.3f dB\n", measuredDb);
    CHECK(finiteOk, "32-band 20 kHz steady-state audio contains no NaN/Inf");
    CHECK(std::abs(measuredDb - 6.0) < 0.25, "32-band steady-state 20 kHz audio hits +6.0 dB (+/-0.25 dB)");
}

int main() {
    std::printf("========================================================\n");
    std::printf("GraphicEqDSP Unit Verification Suite\n");
    std::printf("========================================================\n");

    test_auto_q_calculation();
    test_matrix_decoupling_anti_ripple();
    test_flat_bypass_bit_exact();
    test_audio_processing_stability();
    test_nyquist_band_decoupling_alignment();

    std::printf("\n========================================================\n");
    std::printf("Summary: %d Passed, %d Failed\n", g_passes, g_failures);
    std::printf("========================================================\n");

    return g_failures == 0 ? 0 : 1;
}
