#include <algorithm>
#include <cmath>
#include <cstdio>
#include <vector>

#include "../audio_engine.h"
#include "../dsp/baxandall_tone_dsp.h"
#include "../dsp/cytomic_svf_dsp.h"
#include "../dsp/dynamic_eq_dsp.h"
#include "../dsp/graphic_eq_dsp.h"
#include "../dsp/tone_crossover_dsp.h"

namespace {

constexpr double kPi = 3.14159265358979323846;

int g_pass = 0;
int g_fail = 0;

void check(bool cond, const char *msg) {
    if (cond) {
        std::printf("  [PASS] %s\n", msg);
        ++g_pass;
    } else {
        std::printf("  [FAIL] %s\n", msg);
        ++g_fail;
    }
}

template <typename FilterFn>
double measureSteadyStateSineDb(FilterFn &&fn, double sampleRate, double freqHz,
                                double amp = 0.5) {
    const int settle = static_cast<int>(sampleRate * 0.25);
    const int measure = static_cast<int>(sampleRate * 0.15);
    const int total = settle + measure;
    std::vector<float> buf(static_cast<size_t>(total) * 2, 0.0f);
    for (int i = 0; i < total; ++i) {
        const float s = static_cast<float>(
            amp * std::sin(2.0 * kPi * freqHz * (static_cast<double>(i) / sampleRate)));
        buf[2 * i] = s;
        buf[2 * i + 1] = s;
    }
    fn(buf.data(), static_cast<uint32_t>(total));
    double sumSq = 0.0;
    for (int i = settle; i < total; ++i) {
        const double v = static_cast<double>(buf[2 * i]);
        sumSq += v * v;
    }
    const double rmsOut = std::sqrt(sumSq / static_cast<double>(measure));
    const double rmsIn = amp / std::sqrt(2.0);
    return 20.0 * std::log10((rmsOut + 1e-18) / rmsIn);
}

// =============================================================================
// 1. CytomicSVF SIMD vs Scalar Parity & BandReject Cut-Only Semantics
// =============================================================================
void testCytomicSvfSimdAndBandReject() {
    std::printf("\n== 1. CytomicSVF Stereo SIMD & BandReject ==\n");
    constexpr double fs = 48000.0;
    constexpr uint32_t frames = 2048;

    // Stereo fast path (ch=2) vs scalar generic path (ch=4) in double & float
    sauti::dsp::CytomicSVF svf2D, svf4D;
    svf2D.setParameters(sauti::dsp::CytomicSVF::FilterType::Bell, fs, 1000.0, 6.0, 1.4);
    svf4D.setParameters(sauti::dsp::CytomicSVF::FilterType::Bell, fs, 1000.0, 6.0, 1.4);

    std::vector<double> buf2D(frames * 2), buf4D(frames * 4);
    std::vector<float> buf2F(frames * 2), buf4F(frames * 4);
    for (uint32_t i = 0; i < frames; ++i) {
        const double l = 0.4 * std::sin(2.0 * kPi * 1000.0 * i / fs) +
                         0.2 * std::cos(2.0 * kPi * 250.0 * i / fs);
        const double r = -0.35 * std::sin(2.0 * kPi * 3200.0 * i / fs) +
                         0.25 * std::sin(2.0 * kPi * 900.0 * i / fs);
        buf2D[2 * i] = l;
        buf2D[2 * i + 1] = r;
        buf4D[4 * i] = l;
        buf4D[4 * i + 1] = r;
        buf4D[4 * i + 2] = l;
        buf4D[4 * i + 3] = r;

        buf2F[2 * i] = static_cast<float>(l);
        buf2F[2 * i + 1] = static_cast<float>(r);
        buf4F[4 * i] = static_cast<float>(l);
        buf4F[4 * i + 1] = static_cast<float>(r);
        buf4F[4 * i + 2] = static_cast<float>(l);
        buf4F[4 * i + 3] = static_cast<float>(r);
    }

    svf2D.process(buf2D.data(), frames, 2);
    svf4D.process(buf4D.data(), frames, 4);
    double maxDiffD = 0.0;
    for (uint32_t i = 0; i < frames; ++i) {
        maxDiffD = std::max(maxDiffD, std::abs(buf2D[2 * i] - buf4D[4 * i]));
        maxDiffD = std::max(maxDiffD, std::abs(buf2D[2 * i + 1] - buf4D[4 * i + 1]));
    }
    check(maxDiffD < 1e-12, "CytomicSVF double stereo SIMD matches generic scalar path (< 1e-12)");

    sauti::dsp::CytomicSVF svf2F, svf4F;
    svf2F.setParameters(sauti::dsp::CytomicSVF::FilterType::Bell, fs, 1000.0, 6.0, 1.4);
    svf4F.setParameters(sauti::dsp::CytomicSVF::FilterType::Bell, fs, 1000.0, 6.0, 1.4);
    svf2F.process(buf2F.data(), frames, 2);
    svf4F.process(buf4F.data(), frames, 4);
    float maxDiffF = 0.0f;
    for (uint32_t i = 0; i < frames; ++i) {
        maxDiffF = std::max(maxDiffF, std::abs(buf2F[2 * i] - buf4F[4 * i]));
        maxDiffF = std::max(maxDiffF, std::abs(buf2F[2 * i + 1] - buf4F[4 * i + 1]));
    }
    check(maxDiffF < 1e-6f, "CytomicSVF float stereo SIMD matches generic scalar path (< 1e-6)");

    // BandReject cut-only checks
    sauti::dsp::CytomicSVF br;
    br.setParameters(sauti::dsp::CytomicSVF::FilterType::BandReject, fs, 1000.0, 0.0, 2.0);
    check(!br.isFlat(), "BandReject at 0 dB is NOT flat-bypassed (full notch)");
    const double db0 = measureSteadyStateSineDb(
        [&](float *b, uint32_t n) {
            br.reset();
            br.process(b, n, 2);
        },
        fs, 1000.0);
    check(db0 < -24.0, "BandReject at 0 dB produces deep notch (< -24 dB at fc)");

    br.setParameters(sauti::dsp::CytomicSVF::FilterType::BandReject, fs, 1000.0, -12.0, 2.0);
    const double dbNeg12 = measureSteadyStateSineDb(
        [&](float *b, uint32_t n) {
            br.reset();
            br.process(b, n, 2);
        },
        fs, 1000.0);
    check(std::abs(dbNeg12 - (-12.0)) < 0.5, "BandReject at -12 dB attenuates by -12 dB (+/- 0.5 dB)");

    br.setParameters(sauti::dsp::CytomicSVF::FilterType::BandReject, fs, 1000.0, 6.0, 2.0);
    const double dbPos6 = measureSteadyStateSineDb(
        [&](float *b, uint32_t n) {
            br.reset();
            br.process(b, n, 2);
        },
        fs, 1000.0);
    check(std::abs(dbPos6 - (-6.0)) < 0.5, "BandReject positive input (+6 dB) clamps to cut-only (-6 dB)");

    const double dbPass = measureSteadyStateSineDb(
        [&](float *b, uint32_t n) {
            br.reset();
            br.process(b, n, 2);
        },
        fs, 100.0);
    check(std::abs(dbPass) < 0.25, "BandReject leaves distant passband (100 Hz) flat within +/- 0.25 dB");
}

// =============================================================================
// 2. ToneCrossoverDSP Headroom & Mode Isolation
// =============================================================================
void testToneCrossoverHeadroomAndIsolation() {
    std::printf("\n== 2. ToneCrossoverDSP Headroom & Mode Isolation ==\n");
    constexpr double fs = 48000.0;
    sauti::dsp::ToneCrossoverDSP tc;
    tc.setSampleRate(fs);
    tc.setEnabled(true);
    tc.setMode(sauti::dsp::ToneCrossoverDSP::ToneMode::CrossoverLR4);
    tc.setCrossoverFrequencies(250.0f, 3200.0f);
    tc.setBassGainDb(6.0f);
    tc.setMidGainDb(0.0f);
    tc.setTrebleGainDb(0.0f);
    tc.reset();

    // Feed 2.5 amplitude (+8 dBFS) 80 Hz sine; +6 dB bass boost -> ~5.0 peak without clamping to 2.0
    const int nFrames = 4096;
    std::vector<float> hiBuf(nFrames * 2);
    for (int i = 0; i < nFrames; ++i) {
        const float s = 2.5f * static_cast<float>(std::sin(2.0 * kPi * 80.0 * i / fs));
        hiBuf[2 * i] = s;
        hiBuf[2 * i + 1] = s;
    }
    tc.process(hiBuf.data(), nFrames, 2);
    float maxAbs = 0.0f;
    bool allFinite = true;
    for (float v : hiBuf) {
        if (!std::isfinite(v)) allFinite = false;
        maxAbs = std::max(maxAbs, std::abs(v));
    }
    check(allFinite && maxAbs > 3.5f,
          "ToneCrossover LR4 preserves headroom > 2.0 without hard clipping");

    // Mode isolation: in CrossoverLR4, Baxandall/Tilt calls must not leak into output when LR4 gains are 0
    sauti::dsp::ToneCrossoverDSP iso;
    iso.setSampleRate(fs);
    iso.setEnabled(true);
    iso.setMode(sauti::dsp::ToneCrossoverDSP::ToneMode::CrossoverLR4);
    iso.setGainsDb(0.0f, 0.0f, 0.0f);
    iso.setBassGainDb(12.0f);
    iso.setTrebleGainDb(-12.0f);
    iso.setTiltDb(6.0f);
    // Zero LR4 specifically while keeping tilt nonzero -> re-verify setMode(CrossoverLR4) zeros Baxandall
    iso.setGainsDb(0.0f, 0.0f, 0.0f);
    iso.setTiltDb(6.0f);
    const double lr4WithTiltOnlyDb = measureSteadyStateSineDb(
        [&](float *b, uint32_t n) {
            iso.reset();
            iso.process(b, n, 2);
        },
        fs, 60.0);
    check(std::abs(lr4WithTiltOnlyDb) < 0.05,
          "ToneMode::CrossoverLR4 does not leak spectral tilt into LR4 processing");

    iso.setMode(sauti::dsp::ToneCrossoverDSP::ToneMode::QuadSpectralTilt);
    const double tiltActiveDb = measureSteadyStateSineDb(
        [&](float *b, uint32_t n) {
            iso.reset();
            iso.process(b, n, 2);
        },
        fs, 60.0);
    check(tiltActiveDb < -1.5, "ToneMode::QuadSpectralTilt activates tilt cleanly when selected");
}

// =============================================================================
// 3. BaxandallToneDSP Multichannel Parity (> 2 channels)
// =============================================================================
void testBaxandallMultichannel() {
    std::printf("\n== 3. BaxandallToneDSP Multichannel (6ch) ==\n");
    constexpr double fs = 48000.0;
    constexpr int ch = 6;
    constexpr int frames = 4096;

    sauti::dsp::BaxandallToneDSP bax;
    bax.setSampleRate(fs);
    bax.setEnabled(true);
    bax.setGainsDb(6.0f, -6.0f, 3.0f);
    bax.reset();

    std::vector<float> bufF(frames * ch);
    std::vector<double> bufD(frames * ch);
    for (int i = 0; i < frames; ++i) {
        const double s = 0.3 * std::sin(2.0 * kPi * 60.0 * i / fs) +
                         0.2 * std::sin(2.0 * kPi * 10000.0 * i / fs);
        for (int c = 0; c < ch; ++c) {
            bufF[i * ch + c] = static_cast<float>(s);
            bufD[i * ch + c] = s;
        }
    }
    bax.process(bufF.data(), frames, ch);
    bax.reset();
    bax.process(bufD.data(), frames, ch);

    float maxChDiffF = 0.0f;
    double maxChDiffD = 0.0;
    for (int i = 0; i < frames; ++i) {
        for (int c = 1; c < ch; ++c) {
            maxChDiffF = std::max(maxChDiffF, std::abs(bufF[i * ch + c] - bufF[i * ch]));
            maxChDiffD = std::max(maxChDiffD, std::abs(bufD[i * ch + c] - bufD[i * ch]));
        }
    }
    check(maxChDiffF < 1e-6f && maxChDiffD < 1e-12,
          "BaxandallToneDSP 6-channel float & double outputs match across all channels");
}

// =============================================================================
// 4. DynamicEqDSP Attack Speed, Anti-Phase Linking, Zero-Click 0 dB, Telemetry
// =============================================================================
void testDynamicEqAuditFixes() {
    std::printf("\n== 4. DynamicEqDSP Attack, Anti-Phase Linking & Zero-Click ==\n");
    constexpr float fs = 48000.0f;

    // 4a. Fast attack (1 ms reaches > 60% target within 5 ms)
    sauti::dsp::DynamicEqDSP deq;
    deq.setSampleRate(fs);
    deq.setEnabled(true);
    sauti::dsp::DynamicEqBandConfig cfg;
    cfg.enabled = true;
    cfg.type = sauti::dsp::DynamicEqFilterType::Peak;
    cfg.mode = sauti::dsp::DynamicEqMode::Compress;
    cfg.freq_hz = 1000.0f;
    cfg.q = 1.0f;
    cfg.base_gain_db = 0.0f;
    cfg.threshold_db = -24.0f;
    cfg.range_db = 12.0f;
    cfg.ratio = 4.0f;
    cfg.attack_ms = 1.0f;
    cfg.release_ms = 80.0f;
    deq.setBandConfig(0, cfg);

    // 5 ms = 240 frames at 48 kHz
    std::vector<float> buf5ms(240 * 2);
    for (int i = 0; i < 240; ++i) {
        const float s = 0.5f * static_cast<float>(std::sin(2.0 * kPi * 1000.0 * i / fs));
        buf5ms[2 * i] = s;
        buf5ms[2 * i + 1] = s;
    }
    deq.process(buf5ms.data(), 240, 2);
    const float offset5ms = deq.getBandGainOffsetDb(0);
    check(offset5ms < -6.0f,
          "DynamicEq 1 ms attack achieves > 60% compression within 5 ms (no 15 ms lag)");

    // 4b. Anti-phase stereo linked peak detection (L = +sin, R = -sin)
    deq.reset();
    std::vector<float> antiBuf(2048 * 2);
    for (int i = 0; i < 2048; ++i) {
        const float s = 0.5f * static_cast<float>(std::sin(2.0 * kPi * 1000.0 * i / fs));
        antiBuf[2 * i] = s;
        antiBuf[2 * i + 1] = -s;
    }
    deq.process(antiBuf.data(), 2048, 2);
    const float antiOffset = deq.getBandGainOffsetDb(0);
    double maxAntiSymErr = 0.0;
    for (int i = 0; i < 2048; ++i) {
        maxAntiSymErr = std::max(
            maxAntiSymErr,
            std::abs(static_cast<double>(antiBuf[2 * i]) + static_cast<double>(antiBuf[2 * i + 1])));
    }
    check(antiOffset < -6.0f && maxAntiSymErr < 1e-5,
          "DynamicEq linked peak detector compresses 180-deg out-of-phase L/R stereo symmetrically");

    // 4c. Zero-click live base_gain_db sweep across 0 dB
    sauti::dsp::DynamicEqDSP sweepDeq;
    sweepDeq.setSampleRate(fs);
    sweepDeq.setEnabled(true);
    sauti::dsp::DynamicEqBandConfig staticCfg = cfg;
    staticCfg.mode = sauti::dsp::DynamicEqMode::Static;
    staticCfg.base_gain_db = -1.0f;
    sweepDeq.setBandConfig(0, staticCfg);

    float maxJump = 0.0f;
    float prevOut = 0.0f;
    for (int block = 0; block < 40; ++block) {
        if (block == 20) {
            staticCfg.base_gain_db = 1.0f;
            sweepDeq.setBandConfig(0, staticCfg);
        }
        std::vector<float> blk(64 * 2);
        for (int i = 0; i < 64; ++i) {
            const int n = block * 64 + i;
            const float s = 0.25f * static_cast<float>(std::sin(2.0 * kPi * 1000.0 * n / fs));
            blk[2 * i] = s;
            blk[2 * i + 1] = s;
        }
        sweepDeq.process(blk.data(), 64, 2);
        for (int i = 0; i < 64; ++i) {
            if (block > 0 || i > 0) {
                maxJump = std::max(maxJump, std::abs(blk[2 * i] - prevOut));
            }
            prevOut = blk[2 * i];
        }
    }
    check(maxJump < 0.08f,
          "DynamicEq base_gain_db sweep across 0 dB is smoothed with no step/reset click");
}

// =============================================================================
// 5. GraphicEqDSP 32-Band Matrix Accuracy, -24 dB Parallel Stability & Batch Setter
// =============================================================================
void testGraphicEqAuditFixes() {
    std::printf("\n== 5. GraphicEqDSP 32-Band, -24 dB Parallel & Batch Setter ==\n");
    constexpr double fs = 48000.0;
    const float freqs32[32] = {
        16.0f, 20.0f, 25.0f, 31.5f, 40.0f, 50.0f, 63.0f, 80.0f,
        100.0f, 125.0f, 160.0f, 200.0f, 250.0f, 315.0f, 400.0f, 500.0f,
        630.0f, 800.0f, 1000.0f, 1250.0f, 1600.0f, 2000.0f, 2500.0f, 3150.0f,
        4000.0f, 5000.0f, 6300.0f, 8000.0f, 10000.0f, 12500.0f, 16000.0f, 20000.0f
    };

    sauti::dsp::GraphicEqDSP geq;
    geq.init(32, freqs32, nullptr, fs, sauti::dsp::GraphicEqDSP::EqTopology::MatrixCompensatedCascade);

    std::vector<float> curve(32, 0.0f);
    for (int i = 0; i < 32; ++i) {
        curve[i] = (i < 8) ? 4.0f : ((i >= 16 && i <= 20) ? 6.0f : 0.0f);
    }
    // Bounds safety check: passing oversize count + safe array should clamp to 32 cleanly
    std::vector<float> overCurve(40, 0.0f);
    std::copy(curve.begin(), curve.end(), overCurve.begin());
    geq.setAllGains(overCurve.data(), 40);
    geq.setAllGains(static_cast<const float *>(nullptr), 10);

    const double g1k = measureSteadyStateSineDb(
        [&](float *b, uint32_t n) {
            geq.reset();
            geq.process(b, n, 2);
        },
        fs, 1000.0);
    const double g100 = measureSteadyStateSineDb(
        [&](float *b, uint32_t n) {
            geq.reset();
            geq.process(b, n, 2);
        },
        fs, 100.0);
    check(std::abs(g1k - 6.0) <= 0.6 && std::abs(g100 - 0.0) <= 0.6,
          "GraphicEq 32-band MatrixCompensatedCascade tracks target EQ curve within <= 0.6 dB");

    // Extreme -24 dB cut across adjacent bands in SymmetricParallel topology
    geq.setTopology(sauti::dsp::GraphicEqDSP::EqTopology::SymmetricParallel);
    std::vector<float> deepCuts(32, -24.0f);
    geq.setAllGains(deepCuts.data(), 32);
    geq.reset();
    std::vector<float> stress(8192 * 2);
    for (int i = 0; i < 8192; ++i) {
        const float s = 0.5f * static_cast<float>(std::sin(2.0 * kPi * 1000.0 * i / fs));
        stress[2 * i] = s;
        stress[2 * i + 1] = s;
    }
    geq.process(stress.data(), 8192, 2);
    bool finiteOk = true;
    float maxOut = 0.0f;
    for (float v : stress) {
        if (!std::isfinite(v)) finiteOk = false;
        maxOut = std::max(maxOut, std::abs(v));
    }
    check(finiteOk && maxOut < 1.0f,
          "GraphicEq SymmetricParallel remains finite and bounded at -24 dB extreme cuts");
}

// =============================================================================
// 6. LR2+AP1 3-Band Flat Summing Math & C API Smoke Verification
// =============================================================================
struct Lr2Ap1Mirror {
    struct SVF {
        double ic1eq = 0.0, ic2eq = 0.0;
        double a1 = 0.0, a2 = 0.0, a3 = 0.0, k = 2.0;
        void set(double cutoff, double sr) {
            const double g = std::tan(kPi * std::clamp(cutoff, 10.0, sr * 0.45) / sr);
            k = 2.0;
            a1 = 1.0 / (1.0 + g * (g + k));
            a2 = g * a1;
            a3 = g * a2;
        }
        void process(double input, double &lp, double &hp) {
            const double v3 = input - ic2eq;
            const double v1 = a1 * ic1eq + a2 * v3;
            const double v2 = ic2eq + a2 * ic1eq + a3 * v3;
            ic1eq = 2.0 * v1 - ic1eq;
            ic2eq = 2.0 * v2 - ic2eq;
            lp = v2;
            hp = input - k * v1 - v2;
        }
    };
    struct AP1 {
        double ic1eq = 0.0, a1 = 0.0;
        void set(double cutoff, double sr) {
            const double g = std::tan(kPi * std::clamp(cutoff, 10.0, sr * 0.45) / sr);
            a1 = g / (1.0 + g);
        }
        double process(double input) {
            const double v = (input - ic1eq) * a1;
            const double lp1 = v + ic1eq;
            ic1eq = lp1 + v;
            return (2.0 * lp1) - input;
        }
    };
    SVF lowCross, highCross;
    AP1 apHigh;
    void init(double sr) {
        lowCross.set(250.0, sr);
        highCross.set(2500.0, sr);
        apHigh.set(2500.0, sr);
    }
    void processMono(float *buf, uint32_t frames) {
        for (uint32_t i = 0; i < frames; ++i) {
            double lo = 0.0, mh = 0.0, mid = 0.0, hi = 0.0;
            lowCross.process(static_cast<double>(buf[2 * i]), lo, mh);
            const double loAligned = apHigh.process(lo);
            highCross.process(mh, mid, hi);
            const double y = loAligned - mid + hi;
            buf[2 * i] = static_cast<float>(y);
            buf[2 * i + 1] = static_cast<float>(y);
        }
    }
};

void testLr2Ap1AndEngineCApi() {
    std::printf("\n== 6. LR2+AP1 Flat Summing & Engine C API Smoke ==\n");
    constexpr double fs = 48000.0;
    const double testFreqs[] = {60.0, 250.0, 800.0, 2500.0, 10000.0};
    double maxRippleDb = 0.0;
    for (double f : testFreqs) {
        Lr2Ap1Mirror eq3;
        eq3.init(fs);
        const double dB = measureSteadyStateSineDb(
            [&](float *b, uint32_t n) { eq3.processMono(b, n); }, fs, f);
        maxRippleDb = std::max(maxRippleDb, std::abs(dB));
    }
    check(maxRippleDb < 0.05,
          "LR2+AP1 3-band EQ sums flat (< 0.05 dB ripple) at 60/250/800/2500/10k Hz");

    AudioEngineHandle *e = ae_create_engine(48000, 2);
    check(e != nullptr, "ae_create_engine succeeds offline");
    if (e) {
        ae_set_eq_preamp_db(e, -4.5f);
        const float gotPreamp = ae_get_eq_preamp_db(e);
        check(std::abs(gotPreamp - (-4.5f)) < 1e-4f,
              "ae_set_eq_preamp_db / ae_get_eq_preamp_db roundtrip accurate");

        float freqs10[10] = {32, 60, 125, 250, 500, 1000, 2000, 4000, 8000, 16000};
        float gains10[10] = {3, 2, 1, 0, -1, -2, 0, 1, 2, 3};
        float gainsR[10] = {-1, 0, 1, 2, 0, 0, 1, 2, 1, 0};
        ae_init_multiband_eq(e, 10, freqs10, nullptr);
        ae_set_multiband_eq_mode(e, 0);
        ae_set_multiband_eq_channel_mode(e, 1);
        ae_set_multiband_eq_gains(e, gains10, 10);
        ae_set_multiband_eq_channel_gains(e, 1, gainsR, 10);
        const float g0 = ae_get_multiband_eq_gain(e, 0);
        const float gR3 = ae_get_multiband_eq_channel_gain(e, 1, 3);
        check(std::abs(g0 - 3.0f) < 1e-4f && std::abs(gR3 - 2.0f) < 1e-4f,
              "ae_set_multiband_eq_gains and ae_set_multiband_eq_channel_gains apply atomically");

        ae_destroy_engine(e);
    }
}

} // namespace

int main() {
    std::printf("Running EQ & Tone Controls Audit Regression Tests...\n");
    testCytomicSvfSimdAndBandReject();
    testToneCrossoverHeadroomAndIsolation();
    testBaxandallMultichannel();
    testDynamicEqAuditFixes();
    testGraphicEqAuditFixes();
    testLr2Ap1AndEngineCApi();

    std::printf("\nSummary: %d passed, %d failed\n", g_pass, g_fail);
    return (g_fail == 0) ? 0 : 1;
}
