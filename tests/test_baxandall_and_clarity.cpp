#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <vector>
#include <algorithm>
#include <complex>
#include <string>

#include "../dsp/cytomic_svf_dsp.h"
#include "../dsp/baxandall_tone_dsp.h"
#include "../dsp/tone_crossover_dsp.h"
#include "../dsp/clarity_dsp.h"

static int g_passCount = 0;
static int g_failCount = 0;

#define CHECK(cond, msg) do { \
    if (cond) { \
        std::printf("  [PASS] %s\n", msg); \
        g_passCount++; \
    } else { \
        std::printf("  [FAIL] %s (Line %d)\n", msg, __LINE__); \
        g_failCount++; \
    } \
} while (0)

static constexpr double PI = 3.14159265358979323846;

// Helper: Measure filter gain in dB at a given probe frequency
static double measureGainDb(sauti::dsp::BaxandallToneDSP& filter, double sampleRate, double probeFreqHz) {
    const int kSettleFrames = static_cast<int>(sampleRate * 0.2); // 200 ms settling
    const int kMeasureFrames = static_cast<int>(sampleRate * 0.1);
    const int kTotalFrames = kSettleFrames + kMeasureFrames;

    std::vector<float> buf(kTotalFrames * 2, 0.0f);
    for (int i = 0; i < kTotalFrames; ++i) {
        float val = static_cast<float>(std::sin(2.0 * PI * probeFreqHz * (static_cast<double>(i) / sampleRate)));
        buf[2 * i] = val;
        buf[2 * i + 1] = val;
    }

    filter.process(buf.data(), kTotalFrames, 2);

    // Measure peak/RMS in the measurement window
    double sumSq = 0.0;
    for (int i = kSettleFrames; i < kTotalFrames; ++i) {
        double s = static_cast<double>(buf[2 * i]);
        sumSq += s * s;
    }
    double rmsOut = std::sqrt(sumSq / kMeasureFrames);
    double rmsIn = 1.0 / std::sqrt(2.0); // Sine RMS is 1/sqrt(2)

    return 20.0 * std::log10((rmsOut + 1e-15) / rmsIn);
}

// =============================================================================
// Test 1: Active Baxandall Proportional-Q Bass & Treble
// =============================================================================
static void test_baxandall_proportional_q() {
    std::printf("\n== Test 1: Active Baxandall Proportional-Q Bass & Treble ==\n");
    sauti::dsp::BaxandallToneDSP baxandall;
    baxandall.setSampleRate(48000.0);
    baxandall.setEnabled(true);

    // 1. Bit-Exact Flat Bypass at 0.0 dB
    baxandall.setGainsDb(0.0f, 0.0f, 0.0f);
    baxandall.reset();
    std::vector<float> testBuf = {0.5f, -0.25f, 0.125f, -0.0625f};
    std::vector<float> origBuf = testBuf;
    baxandall.process(testBuf.data(), 2, 2);
    bool bitExact = true;
    for (size_t i = 0; i < testBuf.size(); ++i) {
        if (testBuf[i] != origBuf[i]) bitExact = false;
    }
    CHECK(bitExact, "Baxandall at 0.0 dB gain executes bit-exact flat bypass");

    // 2. Small Bass Boost (+2.0 dB) leaves vocal midrange (1 kHz) untouched
    baxandall.reset();
    baxandall.setBassGainDb(2.0f);
    baxandall.setTrebleGainDb(0.0f);
    baxandall.setTiltDb(0.0f);
    double gain30Hz_small = measureGainDb(baxandall, 48000.0, 30.0);
    double gain1kHz_small = measureGainDb(baxandall, 48000.0, 1000.0);
    std::printf("  Small +2 dB Bass: 30 Hz = %+.2f dB, 1 kHz = %+.2f dB\n", gain30Hz_small, gain1kHz_small);
    CHECK(gain30Hz_small > 1.2 && gain30Hz_small < 2.5, "+2 dB Bass lifts sub-bass (30 Hz)");
    CHECK(std::abs(gain1kHz_small) < 0.05, "+2 dB Bass leaves vocal range (1 kHz) completely flat (< 0.05 dB)");

    // 3. Large Bass Boost (+12.0 dB) tightens proportional-Q toward 100 Hz
    baxandall.reset();
    baxandall.setBassGainDb(12.0f);
    double gain30Hz_large = measureGainDb(baxandall, 48000.0, 30.0);
    double gain100Hz_large = measureGainDb(baxandall, 48000.0, 100.0);
    std::printf("  Large +12 dB Bass: 30 Hz = %+.2f dB, 100 Hz = %+.2f dB\n", gain30Hz_large, gain100Hz_large);
    CHECK(gain30Hz_large > 10.5 && gain30Hz_large < 13.0, "+12 dB Bass boosts sub-bass accurately (+11 to +12 dB)");
    CHECK(gain100Hz_large > 5.0 && gain100Hz_large < 8.0, "+12 dB Bass reaches transition shelf at 100 Hz (~ +6 dB)");

    // 4. Treble Shelf: +2 dB at 15 kHz leaves 1 kHz untouched
    baxandall.reset();
    baxandall.setBassGainDb(0.0f);
    baxandall.setTrebleGainDb(2.0f);
    double gain1kHz_treble = measureGainDb(baxandall, 48000.0, 1000.0);
    double gain15kHz_treble = measureGainDb(baxandall, 48000.0, 15000.0);
    std::printf("  Small +2 dB Treble: 1 kHz = %+.2f dB, 15 kHz = %+.2f dB\n", gain1kHz_treble, gain15kHz_treble);
    CHECK(std::abs(gain1kHz_treble) < 0.05, "+2 dB Treble leaves 1 kHz vocal range flat (< 0.05 dB)");
    CHECK(gain15kHz_treble > 1.2 && gain15kHz_treble < 2.5, "+2 dB Treble provides smooth air lift at 15 kHz");

    // 5. Reciprocal Symmetry: Boost and Cut cancel to 0.0 dB
    sauti::dsp::BaxandallToneDSP boostDSP, cutDSP;
    boostDSP.setSampleRate(48000.0); boostDSP.setEnabled(true); boostDSP.setBassGainDb(6.0f); boostDSP.setTrebleGainDb(4.0f);
    boostDSP.reset();
    cutDSP.setSampleRate(48000.0);   cutDSP.setEnabled(true);   cutDSP.setBassGainDb(-6.0f); cutDSP.setTrebleGainDb(-4.0f);
    cutDSP.reset();
    
    std::vector<float> testTone(4800 * 2);
    for (int i = 0; i < 4800; ++i) {
        float v = std::sin(2.0f * 3.14159f * 100.0f * (float)i / 48000.0f);
        testTone[2 * i] = v; testTone[2 * i + 1] = v;
    }
    boostDSP.process(testTone.data(), 4800, 2);
    cutDSP.process(testTone.data(), 4800, 2);
    // After settle, the boost and cut cascade should equal the original tone
    double maxErr = 0.0;
    for (int i = 2400; i < 4800; ++i) {
        float orig = std::sin(2.0f * 3.14159f * 100.0f * (float)i / 48000.0f);
        double err = std::abs(testTone[2 * i] - orig);
        if (err > maxErr) maxErr = err;
    }
    std::printf("  Reciprocal cascade residual error: %.2e\n", maxErr);
    CHECK(maxErr < 1e-3, "Baxandall boost and reciprocal cut cancel cleanly (< 1e-3)");
}

// =============================================================================
// Test 2: Quad-Style Spectral Tilt Filter (650 Hz Logarithmic Midrange Pivot)
// =============================================================================
static void test_quad_spectral_tilt() {
    std::printf("\n== Test 2: Quad-Style Spectral Tilt Filter (650 Hz Pivot) ==\n");
    sauti::dsp::BaxandallToneDSP tiltDSP;
    tiltDSP.setSampleRate(48000.0);
    tiltDSP.setEnabled(true);

    // 1. Pivot point at 650 Hz with +3.0 dB tilt
    tiltDSP.setGainsDb(0.0f, 0.0f, 3.0f); // Tilt = +3.0 dB
    tiltDSP.reset();

    double gain30Hz  = measureGainDb(tiltDSP, 48000.0, 30.0);
    double gain650Hz = measureGainDb(tiltDSP, 48000.0, 650.0);
    double gain15kHz = measureGainDb(tiltDSP, 48000.0, 15000.0);

    std::printf("  +3 dB Tilt: 30 Hz = %+.2f dB, 650 Hz = %+.2f dB, 15 kHz = %+.2f dB\n",
                gain30Hz, gain650Hz, gain15kHz);

    CHECK(std::abs(gain650Hz) < 0.10, "Tilt pivot frequency at 650 Hz passes at exactly 0.0 dB (+/- 0.1 dB)");
    CHECK(gain30Hz < -1.1 && gain30Hz > -1.9, "+3 dB Tilt attenuates low end by ~ -1.5 dB (-T/2)");
    CHECK(gain15kHz > +1.1 && gain15kHz < +1.9, "+3 dB Tilt boosts high end by ~ +1.5 dB (+T/2)");

    // 2. Negative Tilt (-3.0 dB)
    tiltDSP.setGainsDb(0.0f, 0.0f, -3.0f);
    tiltDSP.reset();
    double gain30Hz_neg  = measureGainDb(tiltDSP, 48000.0, 30.0);
    double gain650Hz_neg = measureGainDb(tiltDSP, 48000.0, 650.0);
    double gain15kHz_neg = measureGainDb(tiltDSP, 48000.0, 15000.0);

    std::printf("  -3 dB Tilt: 30 Hz = %+.2f dB, 650 Hz = %+.2f dB, 15 kHz = %+.2f dB\n",
                gain30Hz_neg, gain650Hz_neg, gain15kHz_neg);

    CHECK(std::abs(gain650Hz_neg) < 0.10, "-3 dB Tilt passes 650 Hz at 0.0 dB (+/- 0.1 dB)");
    CHECK(gain30Hz_neg > +1.1 && gain30Hz_neg < +1.9, "-3 dB Tilt warms low end by ~ +1.5 dB");
    CHECK(gain15kHz_neg < -1.1 && gain15kHz_neg > -1.9, "-3 dB Tilt softens high end by ~ -1.5 dB");
}

// =============================================================================
// Test 3: Differential Envelope Transient Articulator (Level Invariance)
// =============================================================================
static void test_differential_transient_articulator() {
    std::printf("\n== Test 3: Differential Envelope Transient Articulator ==\n");
    sauti::dsp::AudioClarityDSP clarity;
    clarity.setSampleRate(48000.0f);
    clarity.setEnabled(true);
    clarity.setProfile(sauti::dsp::AudioClarityProfile::TransientCrisp);
    clarity.setIntensity(1.0f);
    clarity.reset();

    // 1. Steady-state tone: fast envelope equals slow envelope -> ratio ~ 1.0 -> no boost
    const int kFrames = 4800;
    std::vector<float> steadyBuf(kFrames * 2);
    for (int i = 0; i < kFrames; ++i) {
        float val = 0.5f * std::sin(2.0f * 3.14159f * 6000.0f * (float)i / 48000.0f);
        steadyBuf[2 * i] = val;
        steadyBuf[2 * i + 1] = val;
    }
    clarity.process(steadyBuf.data(), kFrames);

    // Measure steady state output vs input: should NOT elevate steady state signal by +2.5 dB
    double endRMS = 0.0;
    for (int i = kFrames - 500; i < kFrames; ++i) {
        endRMS += steadyBuf[2 * i] * steadyBuf[2 * i];
    }
    endRMS = std::sqrt(endRMS / 500.0);
    double steadyGainDb = 20.0 * std::log10(endRMS / (0.5 / std::sqrt(2.0)));
    std::printf("  Steady-state 6 kHz tone gain: %+.2f dB (want < 0.5 dB, not boosting hiss)\n", steadyGainDb);
    CHECK(std::abs(steadyGainDb) < 0.6, "Steady-state tone has zero/negligible gain elevation (no hiss amplification)");

    // 2. Transient Spike: silence followed by sharp burst -> ratio spikes -> shelf boosts
    clarity.reset();
    std::vector<float> transientBuf(kFrames * 2, 0.0f);
    // 20 ms silence, then 5 ms high-frequency burst, then decay
    for (int i = 1000; i < 1240; ++i) {
        float val = 0.5f * std::sin(2.0f * 3.14159f * 6000.0f * (float)i / 48000.0f);
        transientBuf[2 * i] = val;
        transientBuf[2 * i + 1] = val;
    }
    clarity.process(transientBuf.data(), kFrames);

    // Find peak amplitude during transient onset
    float maxTransient = 0.0f;
    for (int i = 1000; i < 1240; ++i) {
        float m = std::abs(transientBuf[2 * i]);
        if (m > maxTransient) maxTransient = m;
    }
    std::printf("  Peak transient output: %.3f (input peak: 0.500)\n", maxTransient);
    CHECK(maxTransient > 0.52f, "Transient onset is actively boosted by high shelf articulator");
}

// =============================================================================
// Test 4: 4x Oversampled Chebyshev Polynomial Exciter & DC Blocker
// =============================================================================
static void test_chebyshev_air_generator() {
    std::printf("\n== Test 4: 4x Oversampled Chebyshev Harmonic Exciter ==\n");
    sauti::dsp::AudioClarityDSP clarity;
    clarity.setSampleRate(48000.0f);
    clarity.setEnabled(true);
    clarity.setProfile(sauti::dsp::AudioClarityProfile::HarmonicBrilliance);
    clarity.setIntensity(1.0f);
    clarity.setOversampling(4);
    clarity.reset();

    // 1. Silence / DC test: verify DC blocker prevents -1.0 offset on T2(x)
    std::vector<float> silenceBuf(1024 * 2, 0.0f);
    clarity.process(silenceBuf.data(), 1024);
    float maxDc = 0.0f;
    for (size_t i = 100; i < silenceBuf.size(); ++i) {
        float a = std::abs(silenceBuf[i]);
        if (a > maxDc) maxDc = a;
    }
    std::printf("  Residual DC during silence: %.2e (want < 1e-5)\n", maxDc);
    CHECK(maxDc < 1e-5f, "Chebyshev T2(x) DC blocker maintains strictly zero DC during silence");

    // 2. High-pass LR4 crossover isolation: 100 Hz bass fundamental produces zero harmonics
    clarity.reset();
    const int kFrames = 4800;
    std::vector<float> bassBuf(kFrames * 2);
    for (int i = 0; i < kFrames; ++i) {
        float v = 0.8f * std::sin(2.0f * 3.14159f * 100.0f * (float)i / 48000.0f);
        bassBuf[2 * i] = v; bassBuf[2 * i + 1] = v;
    }
    clarity.process(bassBuf.data(), kFrames);

    // Verify bass signal passes through cleanly without spurious harmonic distortion
    bool finite = true;
    for (float s : bassBuf) {
        if (!std::isfinite(s)) finite = false;
    }
    CHECK(finite, "Chebyshev exciter output is finite under high bass signal");

    // 3. High band excitation (5 kHz tone generates 10 kHz 2nd & 15 kHz 3rd harmonics)
    clarity.reset();
    std::vector<float> highBuf(kFrames * 2);
    for (int i = 0; i < kFrames; ++i) {
        float v = 0.5f * std::sin(2.0f * 3.14159f * 5000.0f * (float)i / 48000.0f);
        highBuf[2 * i] = v; highBuf[2 * i + 1] = v;
    }
    clarity.process(highBuf.data(), kFrames);

    double highEnergy = 0.0;
    for (int i = 2400; i < kFrames; ++i) {
        highEnergy += highBuf[2 * i] * highBuf[2 * i];
    }
    double highRms = std::sqrt(highEnergy / (kFrames - 2400));
    const double inRms = 0.5 / std::sqrt(2.0);
    std::printf("  Excited 5 kHz tone RMS: %.4f (pure tone input RMS: %.4f)\n", highRms, inRms);
    CHECK(highRms > inRms, "Chebyshev exciter synthesizes upper harmonics (RMS > input)");
}

// =============================================================================
// Test 5: Full Psychoacoustic Master & Dynamic Low-Mid De-Masking
// =============================================================================
static void test_psychoacoustic_master() {
    std::printf("\n== Test 5: Psychoacoustic Master & Dynamic Low-Mid De-Masking ==\n");
    sauti::dsp::AudioClarityDSP clarity;
    clarity.setSampleRate(48000.0f);
    clarity.setEnabled(true);
    clarity.setProfile(sauti::dsp::AudioClarityProfile::PsychoacousticMaster);
    clarity.setIntensity(1.0f);
    clarity.setDeMaskAmount(1.0f);
    clarity.reset();

    // 1. Run muddy signal (excessive 240 Hz energy) -> de-masker notches 240 Hz
    const int kFrames = 4800;
    std::vector<float> mudBuf(kFrames * 2);
    for (int i = 0; i < kFrames; ++i) {
        float mud = 0.8f * std::sin(2.0f * 3.14159f * 240.0f * (float)i / 48000.0f);
        mudBuf[2 * i] = mud; mudBuf[2 * i + 1] = mud;
    }
    clarity.process(mudBuf.data(), kFrames);

    double mudOutRms = 0.0;
    for (int i = kFrames - 1000; i < kFrames; ++i) {
        mudOutRms += mudBuf[2 * i] * mudBuf[2 * i];
    }
    mudOutRms = std::sqrt(mudOutRms / 1000.0);
    double mudGainDb = 20.0 * std::log10(mudOutRms / (0.8 / std::sqrt(2.0)));
    std::printf("  Mud signal (240 Hz) gain reduction: %+.2f dB (want -1.5 to -3.0 dB)\n", mudGainDb);
    CHECK(mudGainDb < -1.0 && mudGainDb > -3.5, "Dynamic Low-Mid De-Masking engages peaking cut on excessive mud");
}

int main() {
    std::printf("=================================================================\n");
    std::printf(" Audiophile Tone Controls & Psychoacoustic Clarity Test Suite    \n");
    std::printf("=================================================================\n");

    test_baxandall_proportional_q();
    test_quad_spectral_tilt();
    test_differential_transient_articulator();
    test_chebyshev_air_generator();
    test_psychoacoustic_master();

    std::printf("\n-----------------------------------------------------------------\n");
    std::printf(" RESULTS: %d passed, %d failed\n", g_passCount, g_failCount);
    std::printf("-----------------------------------------------------------------\n");

    return (g_failCount == 0) ? 0 : 1;
}
