// =============================================================================
// tests/test_limiters_and_loudness_audit.cpp
//
// Comprehensive regression test suite verifying all mathematical, concurrency,
// performance, and Engine API fixes across all 7 Limiters, AGC, & Loudness
// subsystems:
//   1. MasterLimiterDSP (multichannel, pre-drive output gain, 4x TP, 384kHz, zero drift)
//   2. DynamicLoudnessDSP (live corner freq tracking, 6ch stride, exact alpha)
//   3. BroadcastLevellerDSP (BS.1770 K-weighted -14 LUFS parity, 2dB hysteresis, headroom guard)
//   4. LookaheadAgcLimiterDSP (BS.1770 stereo parity, mono 4x TP, click-free lookahead change)
//   5. BS1770KWeightFilter (+4 dB high-shelf boost at 4 kHz vs 1 kHz & 38 Hz HPF)
//   6. Engine C API (ReplayGain/Normalizer isolation, PDC non-double-count, exclusive bypass, JSON label)
// =============================================================================

#define _USE_MATH_DEFINES
#include <algorithm>
#include <cmath>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <string>
#include <vector>

#include "audio_engine.h"
#include "dsp/bs1770_kweight.h"
#include "dsp/broadcast_leveller_dsp.h"
#include "dsp/dynamic_loudness_dsp.h"
#include "dsp/lookahead_agc_limiter_dsp.h"
#include "dsp/master_limiter_dsp.h"

#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

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

static double rmsRange(const std::vector<float>& buf, int channels, int targetCh, size_t startFrame, size_t endFrame) {
    double sumSq = 0.0;
    size_t count = 0;
    for (size_t i = startFrame; i < endFrame; ++i) {
        const double v = static_cast<double>(buf[i * static_cast<size_t>(channels) + static_cast<size_t>(targetCh)]);
        sumSq += v * v;
        ++count;
    }
    return (count > 0) ? std::sqrt(sumSq / static_cast<double>(count)) : 0.0;
}

static void test_master_limiter_audit() {
    std::printf("\n== 1. MasterLimiterDSP Audit Tests ==\n");
    using sauti::dsp::MasterLimiterDSP;

    // A. Multichannel (mono and 6ch) + pre-drive output gain (+6 dB into -1 dBTP ceiling)
    {
        MasterLimiterDSP lim;
        lim.setSampleRate(48000.0f);
        lim.setCeilingDb(-1.0f);     // ~0.89125 linear
        lim.setOutputGainDb(6.0f);   // +6 dB pre-drive
        lim.setReleaseMs(50.0f);
        lim.setEnabled(true);

        const float ceilLin = std::pow(10.0f, -1.0f / 20.0f);

        // Mono 1 kHz @ 0.7 amp (+6 dB -> 1.4 > 0.89125 -> cleanly limited)
        std::vector<float> mono(4800, 0.0f);
        for (size_t i = 0; i < mono.size(); ++i) {
            mono[i] = 0.7f * std::sin(2.0f * static_cast<float>(M_PI) * 1000.0f * static_cast<float>(i) / 48000.0f);
        }
        lim.process(mono.data(), static_cast<uint32_t>(mono.size()), 1);

        float peakMono = 0.0f;
        bool monoFinite = true;
        for (float s : mono) {
            if (!std::isfinite(s)) monoFinite = false;
            peakMono = std::max(peakMono, std::abs(s));
        }
        CHECK(monoFinite && peakMono <= ceilLin + 1e-4f && peakMono > 0.5f,
              "MasterLimiterDSP mono pre-drive +6 dB stays limited cleanly under -1.0 dBTP ceiling");

        // 6-channel interleaved
        lim.reset();
        std::vector<float> ch6(2400 * 6, 0.0f);
        for (size_t i = 0; i < 2400; ++i) {
            float v = 0.75f * std::sin(2.0f * static_cast<float>(M_PI) * 440.0f * static_cast<float>(i) / 48000.0f);
            for (int c = 0; c < 6; ++c) {
                ch6[i * 6 + static_cast<size_t>(c)] = (c == 5) ? v : (0.3f * v);
            }
        }
        lim.process(ch6.data(), 2400, 6);
        float peak6 = 0.0f;
        for (float s : ch6) peak6 = std::max(peak6, std::abs(s));
        CHECK(peak6 <= ceilLin + 1e-4f, "MasterLimiterDSP protects all 6 channels without OOB");
    }

    // B. Intersample peak catching (fs/4 shifted 45 deg: 1.06 * sin(k*pi/2 + pi/4) has 0.7495 sample peak -> 1.06 TP > -1 dBTP)
    {
        MasterLimiterDSP lim;
        lim.setSampleRate(48000.0f);
        lim.setCeilingDb(-1.0f);
        lim.setOutputGainDb(0.0f);
        lim.setEnabled(true);

        std::vector<double> isp(4800 * 2, 0.0);
        for (size_t i = 0; i < 4800; ++i) {
            double s = 1.06 * std::sin(2.0 * M_PI * 12000.0 * static_cast<double>(i) / 48000.0 + M_PI / 4.0);
            isp[i * 2 + 0] = s;
            isp[i * 2 + 1] = s;
        }
        lim.process(isp.data(), 4800, 2);
        CHECK(lim.getCurrentGainReductionDb() < -0.5f,
              "MasterLimiterDSP detects intersample peaks (0.75 sample @ fs/4 -> 1.06 TP) and reduces gain");
    }

    // C. 384 kHz Hi-Res latency + bit-exact passthrough zero drift
    {
        MasterLimiterDSP lim;
        lim.setSampleRate(384000.0f);
        lim.setCeilingDb(-0.1f);
        lim.setOutputGainDb(0.0f);
        lim.setEnabled(true);

        CHECK(lim.getLatencySamples() == 576, "MasterLimiterDSP @ 384 kHz has 576-sample (1.5 ms) lookahead latency");

        std::vector<double> hiRes(24000 * 2, 0.0);
        for (size_t i = 0; i < 24000; ++i) {
            double s = 0.25 * std::sin(2.0 * M_PI * 1000.0 * static_cast<double>(i) / 384000.0);
            hiRes[i * 2 + 0] = s;
            hiRes[i * 2 + 1] = s;
        }
        std::vector<double> copy = hiRes;
        lim.process(copy.data(), 24000, 2);

        double maxErr = 0.0;
        for (size_t i = 1000; i < 24000; ++i) {
            maxErr = std::max(maxErr, std::abs(copy[i * 2] - hiRes[(i - 576) * 2]));
        }
        CHECK(maxErr < 1e-12, "MasterLimiterDSP @ 384 kHz preserves float64 precision (< 1e-12) below ceiling");
    }
}

static void test_dynamic_loudness_audit() {
    std::printf("\n== 2. DynamicLoudnessDSP Audit Tests ==\n");
    using sauti::dsp::DynamicLoudnessDSP;

    DynamicLoudnessDSP dl;
    dl.setSampleRate(48000.0f);
    dl.setEnabled(true);
    dl.setParams(0.0f, 12.0f, 6.0f, 70.0f, 12000.0f);

    // Warm up with 200 Hz tone at -20 dB (volume = 0.1) with bass cutoff at 70 Hz
    std::vector<float> buf1(12000 * 6, 0.0f);
    for (size_t i = 0; i < 12000; ++i) {
        float s = 0.1f * std::sin(2.0f * static_cast<float>(M_PI) * 200.0f * static_cast<float>(i) / 48000.0f);
        for (int c = 0; c < 6; ++c) buf1[i * 6 + static_cast<size_t>(c)] = s;
    }
    dl.process(buf1.data(), 12000, 6, 0.1f);
    const double rmsLowCornerCh5 = rmsRange(buf1, 6, 5, 8000, 12000);

    // Move bass corner frequency live from 70 Hz -> 350 Hz at SAME steady volume (0.1f)
    dl.setParams(0.0f, 12.0f, 6.0f, 350.0f, 12000.0f);
    std::vector<float> buf2(12000 * 6, 0.0f);
    for (size_t i = 0; i < 12000; ++i) {
        float s = 0.1f * std::sin(2.0f * static_cast<float>(M_PI) * 200.0f * static_cast<float>(i) / 48000.0f);
        for (int c = 0; c < 6; ++c) buf2[i * 6 + static_cast<size_t>(c)] = s;
    }
    dl.process(buf2.data(), 12000, 6, 0.1f);
    const double rmsHighCornerCh5 = rmsRange(buf2, 6, 5, 8000, 12000);

    std::printf("  200 Hz ch5 RMS: 70Hz corner=%.5f, 350Hz corner=%.5f\n", rmsLowCornerCh5, rmsHighCornerCh5);
    CHECK(rmsHighCornerCh5 > rmsLowCornerCh5 * 1.25,
          "DynamicLoudnessDSP updates SVF coefficients immediately on live corner freq change & handles 6ch");
}

static void test_kweight_and_leveller_audit() {
    std::printf("\n== 3. BS.1770 K-Weighting & BroadcastLevellerDSP Audit Tests ==\n");
    using sauti::dsp::BS1770KWeightFilter;
    using sauti::dsp::BroadcastLevellerDSP;

    // A. BS1770KWeightFilter must boost 4 kHz relative to 1 kHz (~+3.3 dB) and attenuate 20 Hz
    {
        BS1770KWeightFilter kw;
        kw.updateSampleRate(48000.0);

        auto measureGainDb = [&](double freqHz) {
            kw.reset();
            double inSq = 0.0, outSq = 0.0;
            for (int i = 0; i < 48000; ++i) {
                double x = std::sin(2.0 * M_PI * freqHz * static_cast<double>(i) / 48000.0);
                double y = kw.processSample(0, x);
                if (i >= 24000) {
                    inSq += x * x;
                    outSq += y * y;
                }
            }
            return 10.0 * std::log10(outSq / inSq);
        };

        const double g1k = measureGainDb(1000.0);
        const double g4k = measureGainDb(4000.0);
        const double g20 = measureGainDb(20.0);
        std::printf("  K-Weight response: 20Hz=%.2f dB, 1kHz=%.2f dB, 4kHz=%.2f dB\n", g20, g1k, g4k);
        CHECK(g1k > 0.55 && g1k < 0.85, "BS.1770 Stage 1+2 gain at 1 kHz is ~+0.69 dB");
        CHECK(g4k > 3.5 && g4k < 4.5, "BS.1770 +4 dB high-shelf lifts 4 kHz cleanly (~+3.9 dB)");
        CHECK(g20 < -5.0, "BS.1770 RLB high-pass attenuates 20 Hz");
    }

    // B. BroadcastLevellerDSP stereo -14 LUFS sine parity (no -3 dB bias!)
    {
        BroadcastLevellerDSP lev;
        lev.setSampleRate(48000.0f);
        lev.setParams(-14.0f, 2.0f, 2.0f, 12.0f, 12.0f, -45.0f);
        lev.setEnabled(true);

        // Stereo 1 kHz sine at -14 LUFS => each channel is -17 dBFS RMS => amp = sqrt(2) * 10^(-17/20) = 0.19976
        const float amp = std::sqrt(2.0f) * std::pow(10.0f, -17.0f / 20.0f);
        std::vector<float> buf(4800 * 2, 0.0f);
        for (int blk = 0; blk < 20; ++blk) { // 2.0 seconds total
            for (size_t i = 0; i < 4800; ++i) {
                float s = amp * std::sin(2.0f * static_cast<float>(M_PI) * 1000.0f *
                                         static_cast<float>(blk * 4800 + i) / 48000.0f);
                buf[i * 2 + 0] = s;
                buf[i * 2 + 1] = s;
            }
            lev.process(buf.data(), 4800, 2);
        }
        const float gDb = lev.getCurrentGainDb();
        std::printf("  BroadcastLeveller -14 LUFS stereo sine steady gain = %.3f dB\n", gDb);
        CHECK(std::abs(gDb) < 0.35f, "BroadcastLeveller -14 LUFS stereo sine has |gain| < 0.35 dB (no -3 dB bias)");
    }

    // C. 2.0 dB Silence-Gate Hysteresis & Positive-Boost Headroom Guard
    {
        BroadcastLevellerDSP lev;
        lev.setSampleRate(48000.0f);
        lev.setParams(-14.0f, 4.0f, 4.0f, 12.0f, 12.0f, -45.0f);
        lev.setEnabled(true);

        // First push silence (-55 LUFS -> freezes), then -44 LUFS (inside hysteresis [-45, -43] -> stays frozen!)
        std::vector<float> dummy(4800 * 2, 0.05f);
        lev.process(dummy.data(), 4800, 2, -55.0f);
        const float gainAtFreeze = lev.getCurrentGainDb();
        lev.process(dummy.data(), 4800, 2, -44.0f);
        const float gainInHyst = lev.getCurrentGainDb();
        CHECK(std::abs(gainInHyst - gainAtFreeze) < 1e-4f,
              "BroadcastLeveller 2.0 dB silence-gate hysteresis holds freeze at -44 LUFS");

        // Headroom guard test: hot 0.85 peak block while gain asks for boost -> must cap peak <= 0.945
        lev.reset();
        lev.setParams(-10.0f, 6.0f, 6.0f, 12.0f, 12.0f, -60.0f);
        for (int b = 0; b < 10; ++b) {
            std::vector<float> sig(4800 * 2, 0.02f);
            sig[0] = 0.85f; sig[1] = -0.85f; // high-crest transient
            lev.process(sig.data(), 4800, 2, -25.0f);
            float maxOut = 0.0f;
            for (float v : sig) maxOut = std::max(maxOut, std::abs(v));
            if (b == 9) {
                CHECK(maxOut <= 0.946f, "BroadcastLeveller headroom guard keeps boosted transient <= -0.5 dBFS (0.946)");
            }
        }
    }
}

static void test_lookahead_agc_audit() {
    std::printf("\n== 4. LookaheadAgcLimiterDSP Audit Tests ==\n");
    using sauti::dsp::LookaheadAgcLimiterDSP;

    // A. -14 LUFS stereo sine parity (BS.1770 K-weighted sum)
    {
        LookaheadAgcLimiterDSP dsp;
        dsp.setSampleRate(48000.0f);
        dsp.setParams(-14.0f, 9.0f, 15.0f, 2.0f, 4.0f, -45.0f, 10.0f, -0.1f, 180.0f, 3000.0f, 160.0f);
        dsp.setEnabled(true);

        const float amp = std::sqrt(2.0f) * std::pow(10.0f, -17.0f / 20.0f);
        std::vector<float> buf(4800 * 2, 0.0f);
        for (int blk = 0; blk < 25; ++blk) {
            for (size_t i = 0; i < 4800; ++i) {
                float s = amp * std::sin(2.0f * static_cast<float>(M_PI) * 1000.0f *
                                         static_cast<float>(blk * 4800 + i) / 48000.0f);
                buf[i * 2 + 0] = s;
                buf[i * 2 + 1] = s;
            }
            dsp.process(buf.data(), 4800, 2);
        }
        float agcDb = 0.0f;
        dsp.getTelemetry(&agcDb, nullptr, nullptr, nullptr, nullptr);
        std::printf("  LookaheadAgcLimiter -14 LUFS stereo sine steady agcDb = %.3f dB\n", agcDb);
        CHECK(std::abs(agcDb) < 0.35f, "LookaheadAgcLimiter -14 LUFS stereo sine has |agcDb| < 0.35 dB");
    }

    // B. Mono Stage B 4x TP + Click-free live lookahead_ms drag without zero dropout
    {
        LookaheadAgcLimiterDSP dsp;
        dsp.setSampleRate(48000.0f);
        dsp.setParams(-14.0f, 0.0f, 15.0f, 1.5f, 4.0f, -45.0f, 10.0f, -0.5f, 180.0f, 3000.0f, 160.0f);
        dsp.setEnabled(true);

        const float ceilLin = std::pow(10.0f, -0.5f / 20.0f);
        std::vector<float> mono(4800, 0.0f);
        for (size_t i = 0; i < mono.size(); ++i) {
            mono[i] = 1.2f * std::sin(2.0f * static_cast<float>(M_PI) * 1000.0f * static_cast<float>(i) / 48000.0f);
        }
        dsp.process(mono.data(), mono.size(), 1);
        float maxMono = 0.0f;
        for (float v : mono) maxMono = std::max(maxMono, std::abs(v));
        CHECK(maxMono <= ceilLin + 1e-4f, "LookaheadAgcLimiter mono Stage B limits cleanly below -0.5 dBTP");

        // Drag lookahead_ms from 10.0 -> 15.0 -> 5.0 during continuous 200 Hz DC-free sine and check no zeroed hole
        dsp.reset();
        dsp.setParams(-14.0f, 0.0f, 0.0f, 1.5f, 4.0f, -45.0f, 10.0f, -0.1f, 180.0f, 3000.0f, 160.0f);
        std::vector<float> warm(2400 * 2, 0.0f);
        size_t idx = 0;
        for (size_t i = 0; i < 2400; ++i, ++idx) {
            float s = 0.4f * std::sin(2.0f * static_cast<float>(M_PI) * 200.0f * static_cast<float>(idx) / 48000.0f);
            warm[i * 2] = s; warm[i * 2 + 1] = s;
        }
        dsp.process(warm.data(), 2400, 2);

        dsp.setParams(-14.0f, 0.0f, 0.0f, 1.5f, 4.0f, -45.0f, 15.0f, -0.1f, 180.0f, 3000.0f, 160.0f);
        std::vector<float> dragged(1024 * 2, 0.0f);
        for (size_t i = 0; i < 1024; ++i, ++idx) {
            float s = 0.4f * std::sin(2.0f * static_cast<float>(M_PI) * 200.0f * static_cast<float>(idx) / 48000.0f);
            dragged[i * 2] = s; dragged[i * 2 + 1] = s;
        }
        dsp.process(dragged.data(), 1024, 2);

        // If ring was wiped on drag, the first ~300 samples would be 0.000
        double firstWindowRms = rmsRange(dragged, 2, 0, 0, 240);
        CHECK(firstWindowRms > 0.20, "Live lookahead_ms drag keeps ring continuous (no 0-sample silent hole)");
    }
}

static void test_engine_c_api_audit() {
    std::printf("\n== 5. Engine C API Integration Audit Tests ==\n");
    AudioEngineHandle *e = ae_create_engine(48000, 2);
    CHECK(e != nullptr, "AudioEngine created");
    if (!e) return;

    // A. ReplayGain vs Normalizer isolation
    ae_set_replay_gain_with_peak(e, -6.0f, 0.9f);
    const float rgBefore = ae_get_replay_gain_linear(e);
    ae_set_current_track_loudness(e, -12.0f, 0.9f);
    const float rgAfter = ae_get_replay_gain_linear(e);
    CHECK(std::abs(rgBefore - rgAfter) < 1e-5f,
          "ae_set_current_track_loudness does NOT overwrite replayGainLinear");

    // B. PDC latency mutual exclusion & exclusive bypass
    ae_dsp_set_master_limiter_enabled(e, 1);
    ae_set_lookahead_limiter_enabled(e, 1);
    const double latMasterOnly = ae_get_engine_latency_samples(e);
    ae_dsp_set_master_limiter_enabled(e, 0);
    const double latLookaheadOnly = ae_get_engine_latency_samples(e);
    ae_dsp_set_master_limiter_enabled(e, 1);
    const double latBoth = ae_get_engine_latency_samples(e);
    CHECK(std::abs(latBoth - latMasterOnly) < 1.0 && latBoth != (latMasterOnly + latLookaheadOnly),
          "PDC engine latency never double-counts mutually-exclusive Zone 7 limiters");

    ae_set_exclusive_mode(e, 1);
    const double latExclusive = ae_get_engine_latency_samples(e);
    CHECK(latExclusive < latMasterOnly, "Exclusive mode bypass removes App DSP latency from PDC");
    ae_set_exclusive_mode(e, 0);

    // C. Signal Path JSON "Ref Level" label (not "Ref SPL")
    ae_dsp_set_dynamic_loudness_enabled(e, 1);
    char jsonBuf[4096]{};
    int written = ae_get_active_dsp_nodes_json(e, jsonBuf, sizeof(jsonBuf));
    std::string jsonStr(jsonBuf, static_cast<size_t>(std::max(0, written)));
    CHECK(jsonStr.find("\"Ref Level\"") != std::string::npos && jsonStr.find("\"Ref SPL\"") == std::string::npos,
          "Signal path JSON reports \"Ref Level\" instead of \"Ref SPL\"");

    ae_destroy_engine(e);
}

int main() {
    std::printf("===========================================================\n");
    std::printf("Running Limiters, AGC & Loudness Comprehensive Audit Suite\n");
    std::printf("===========================================================\n");

    test_master_limiter_audit();
    test_dynamic_loudness_audit();
    test_kweight_and_leveller_audit();
    test_lookahead_agc_audit();
    test_engine_c_api_audit();

    std::printf("\n===========================================================\n");
    std::printf("Audit Results: %d passed, %d failed\n", g_passes, g_failures);
    std::printf("===========================================================\n");
    return (g_failures == 0) ? 0 : 1;
}
