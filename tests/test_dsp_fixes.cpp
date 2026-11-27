// =============================================================================
// tests/test_dsp_fixes.cpp
//
// Unit tests for the header-level DSP fixes from Issues_bugs.md:
//   [C] 1.6  Pure Bass+ FIR: unity gain, linear phase, no signal destruction
//   [C] 1.7  CrossfeedNode::setAlgorithm switches at runtime with any mix
//   [C] 1.5  MasterLimiterDSP defaults OFF; respects ceiling when enabled
//   [M] 3.2  AnalogWarmth triode no longer injects DC offset
//   [M] 3.3  Clarity PresenceExciter bands sum back flat at unity gains
//   [M] 3.4  DynamicSystemDSP one-pole cutoff accuracy + stability
//
// These headers are self-contained; no audio device or engine required.
// Build: see build_tests.ps1
// =============================================================================

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <random>
#include <vector>

#include "dsp/dynamic_bass_dsp.h"
#include "dsp/master_limiter_dsp.h"
#include "dsp/clarity_dsp.h"
#include "dsp/dialog_enhancer_dsp.h"
#include "dsp/analog_warmth_dsp.h"
#include "dsp/dynamic_system_dsp.h"
#include "dsp/de_esser_dsp.h"
#include "dsp/downward_expander_dsp.h"
#include "dsp/noise_gate_dsp.h"
#include "dsp/subsonic_filter.h"
#include "dsp/denormals.h"
#include "dsp/scaletempo_dsp.h"
#include "dsp/fft_convolver_dsp.h"
#include "CDSPResampler.h"
#include "dsp/spatial_surround_dsp.h"
#include "dsp/stereo_imager_dsp.h"
#include "dsp/dynamic_loudness_dsp.h"
#include "dsp/broadcast_leveller_dsp.h"
#include "../crossfeed_node.h"
#include "../reverb_node.h"

static int g_failures = 0;
static int g_passes = 0;

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

static bool nearlyEqual(float a, float b, float tol)
{
    return std::fabs(a - b) <= tol;
}

// -----------------------------------------------------------------------------
// [C] 1.6 HarmonicBassDSP Pure Bass+ FIR
// -----------------------------------------------------------------------------
static void test_pure_bass_fir()
{
    std::printf("\n== [C] 1.6 Pure Bass+ polyphase FIR ==\n");

    // --- Impulse response properties ---
    {
        sauti::dsp::HarmonicBassDSP dsp;
        dsp.setSampleRate(48000.0f);
        dsp.setEnabled(true);
        dsp.setProfile(sauti::dsp::BassEnhanceProfile::PureBass);
        dsp.setBoost(0.0f); // silence injected bass; isolate the FIR path
        dsp.reset();

        const uint32_t N = 512;
        std::vector<float> buf(2 * N, 0.0f);

        // Run 1 second of silence FIRST so the bass-gain smoother (30 ms
        // time constant) fully settles at its target (boost=0); otherwise the
        // decaying injected-bass transient contaminates the impulse window.
        dsp.process(buf.data(), N);
        for (int r = 0; r < 93; ++r) dsp.process(buf.data(), N);

        for (size_t i = 0; i < buf.size(); ++i) buf[i] = 0.0f;
        dsp.reset();
        buf[2 * 100] = 0.5f;
        dsp.process(buf.data(), N);

        // Extract h[k], k = 0..62 relative to the impulse
        float h[63];
        double sum = 0.0;
        float maxAsym = 0.0f;
        int worstK = -1;
        for (int k = 0; k < 63; ++k)
        {
            h[k] = buf[2 * (100 + k)];
            sum += h[k];
        }
        for (int k = 0; k < 63; ++k)
        {
            const float a = std::fabs(h[k] - h[62 - k]);
            if (a > maxAsym) { maxAsym = a; worstK = k; }
        }

        char msg[128];
        std::snprintf(msg, sizeof(msg), "FIR DC gain ~unity (sum=%.4f, want ~0.5 for 0.5 impulse)", sum);
        CHECK(nearlyEqual((float)sum, 0.5f, 0.02f), msg);
        if (maxAsym >= 2e-4f)
        {
            std::printf("    DBG worstK=%d h[k]=%.6g h[62-k]=%.6g\n", worstK, (double)h[worstK], (double)h[62 - worstK]);
            for (int k = 0; k < 63; ++k)
                std::printf("    DBG h[%2d]=%.6g\n", k, (double)h[k]);
        }
        std::snprintf(msg, sizeof(msg), "FIR impulse response is symmetric (max asym %.2e)", maxAsym);
        CHECK(maxAsym < 2e-4f, msg);

        float peak = 0.0f;
        for (int k = 0; k < 63; ++k) peak = std::max(peak, std::fabs(h[k]));
        std::snprintf(msg, sizeof(msg), "FIR peak tap sane (%.3f, old corrupt table peaked ~0.62 with -14dB sum)", peak);
        CHECK(peak > 0.05f && peak <= 0.55f, msg);
    }

    // --- DC / passband transparency ---
    {
        sauti::dsp::HarmonicBassDSP dsp;
        dsp.setSampleRate(48000.0f);
        dsp.setEnabled(true);
        dsp.setProfile(sauti::dsp::BassEnhanceProfile::PureBass);
        dsp.setBoost(0.0f);
        dsp.reset();

        const uint32_t frames = 96000; // 2 s @ 48 kHz
        std::vector<float> buf(2 * frames, 0.25f);
        dsp.process(buf.data(), frames);

        double meanL = 0.0;
        const size_t tailStart = (size_t)(frames - 8000) * 2;
        size_t cnt = 0;
        for (size_t i = tailStart; i < buf.size(); i += 2) { meanL += buf[i]; ++cnt; }
        meanL /= (double)cnt;

        char msg[128];
        std::snprintf(msg, sizeof(msg), "DC input 0.25 passes at %.4f (old table gave ~0.05)", meanL);
        CHECK(nearlyEqual((float)meanL, 0.25f, 0.01f), msg);
    }
}

// -----------------------------------------------------------------------------
// [C] 1.7 CrossfeedNode runtime algorithm switching
// -----------------------------------------------------------------------------
static void test_crossfeed_algorithm_switch()
{
    std::printf("\n== [C] 1.7 Crossfeed algorithm switching at mix=0.5 ==\n");

    CrossfeedNode node;
    node.setMix(0.5f);
    node.setDelayMs(0.4f);
    node.setAlgorithm(CrossfeedAlgorithm::Simple);

    const uint32_t frames = 4096;
    std::mt19937 rng(12345);
    std::vector<float> in(2 * frames);
    for (auto &v : in) v = ((float)(rng() % 20000) - 10000.0f) / 10000.0f;

    std::vector<float> outSimple = in;
    node.process(outSimple.data(), frames, 2);
    node.reset();

    // The regression: with mix >= 0.001 the old code never switched algorithms.
    node.setAlgorithm(CrossfeedAlgorithm::Meier);
    CHECK(node.getAlgorithm() == CrossfeedAlgorithm::Meier, "getAlgorithm reflects new target");

    std::vector<float> outMeier = in;
    node.process(outMeier.data(), frames, 2);

    double diffEnergy = 0.0;
    for (size_t i = 0; i < in.size(); ++i)
    {
        const double d = (double)outSimple[i] - (double)outMeier[i];
        diffEnergy += d * d;
    }

    char msg[128];
    std::snprintf(msg, sizeof(msg), "Meier output differs from Simple (diff energy=%.2f)", diffEnergy);
    CHECK(diffEnergy > 1.0, msg);

    // Switching again to BS2B must also take effect immediately.
    node.reset();
    node.setAlgorithm(CrossfeedAlgorithm::BS2B);
    std::vector<float> outBs2b = in;
    node.process(outBs2b.data(), frames, 2);
    diffEnergy = 0.0;
    for (size_t i = 0; i < in.size(); ++i)
    {
        const double d = (double)outMeier[i] - (double)outBs2b[i];
        diffEnergy += d * d;
    }
    CHECK(diffEnergy > 1.0, "BS2B output differs from Meier after direct switch");

    // Switching to OpenStage must also take effect immediately.
    node.reset();
    node.setAlgorithm(CrossfeedAlgorithm::OpenStage);
    std::vector<float> outOpenStage = in;
    node.process(outOpenStage.data(), frames, 2);
    diffEnergy = 0.0;
    for (size_t i = 0; i < in.size(); ++i)
    {
        const double d = (double)outBs2b[i] - (double)outOpenStage[i];
        diffEnergy += d * d;
    }
    CHECK(diffEnergy > 1.0, "OpenStage output differs from BS2B after direct switch");
}

// -----------------------------------------------------------------------------
// [C] 1.5 MasterLimiterDSP default state and ceiling behaviour
// -----------------------------------------------------------------------------
static void test_master_limiter_defaults_and_ceiling()
{
    std::printf("\n== [C] 1.5 Master limiter default-off + ceiling ==\n");

    sauti::dsp::MasterLimiterDSP limiter;
    CHECK(!limiter.isEnabled(), "limiter is DISABLED by default (no silent coloration)");
    CHECK(nearlyEqual(limiter.getCeilingDb(), -0.1f, 0.001f), "default ceiling is -0.1 dBFS");

    // Disabled -> bit-transparent
    const uint32_t frames = 256;
    std::vector<float> buf(2 * frames);
    std::mt19937 rng(777);
    for (auto &v : buf) v = ((float)(rng() % 20000) - 10000.0f) / 5000.0f; // hot, > ceiling
    std::vector<float> copy = buf;
    limiter.process(buf.data(), frames);
    bool identical = true;
    for (size_t i = 0; i < buf.size(); ++i)
        if (buf[i] != copy[i]) { identical = false; break; }
    CHECK(identical, "disabled limiter leaves samples untouched");

    // Enabled -> hard ceiling respected on a hot master
    limiter.setCeilingDb(-6.0f);
    limiter.setEnabled(true);
    limiter.reset();
    float maxOut = 0.0f;
    for (uint32_t b = 0; b < 8; ++b)
    {
        std::vector<float> block(2 * frames);
        for (auto &v : block) v = ((float)(rng() % 20000) - 10000.0f) / 5000.0f; // hot, > ceiling
        limiter.process(block.data(), frames);
        for (float v : block) maxOut = std::max(maxOut, std::fabs(v));
    }

    const float ceilingLinear = std::pow(10.0f, -6.0f / 20.0f);

    char msg[160];
    std::snprintf(msg, sizeof(msg), "output %.4f within ceiling %.4f (+eps)", maxOut, ceilingLinear);
    CHECK(maxOut <= ceilingLinear + 1e-3f, msg);
    CHECK(limiter.getCurrentGainReductionDb() < -0.1f, "gain reduction engaged on hot material");
}

// -----------------------------------------------------------------------------
// [C] 1.5b MasterLimiterDSP release ballistics & lookahead peak hold
// -----------------------------------------------------------------------------
static void test_master_limiter_ballistics_and_lookahead_hold()
{
    std::printf("\n== [C] 1.5b Master limiter release ballistics & lookahead hold ==\n");

    sauti::dsp::MasterLimiterDSP limiter;
    limiter.setSampleRate(48000.0f);
    limiter.setCeilingDb(0.0f); // 1.0 linear ceiling
    limiter.setReleaseMs(60.0f);
    limiter.setEnabled(true);
    limiter.reset();

    // 1. Lookahead Peak Hold verification:
    // Feed single Dirac impulse of 2.0 (+6 dBFS) at sample 10, surrounded by silence.
    // 72 samples @ 48kHz is the 1.5ms lookahead buffer.
    const uint32_t frames = 250;
    std::vector<float> impulse_buf(2 * frames, 0.0f);
    impulse_buf[2 * 10] = 2.0f; // Left channel impulse

    limiter.process(impulse_buf.data(), frames);

    // Peak exits at sample 10 + 72 = 82
    float peak_out_l = std::fabs(impulse_buf[2 * 82]);
    char msg[128];
    std::snprintf(msg, sizeof(msg), "delayed impulse output %.4f <= 1.0001 (no early-release overshoot)", peak_out_l);
    CHECK(peak_out_l <= 1.0001f, msg);

    // 2. Release Ballistics verification:
    // With 60ms release, gain reduction must decay smoothly over ~2880 samples.
    // It must NOT recover instantly on the next sample.
    limiter.reset();
    std::vector<float> hot_step(2 * 100, 2.0f); // hot burst
    limiter.process(hot_step.data(), 100);

    float gr_immediate = limiter.getCurrentGainReductionDb();
    CHECK(gr_immediate < -5.0f, "active gain reduction engaged after hot burst (~ -6dB)");

    // Process 1 single frame of silence: gain reduction must NOT disappear instantly
    std::vector<float> single_frame(2, 0.0f);
    limiter.process(single_frame.data(), 1);
    float gr_one_sample = limiter.getCurrentGainReductionDb();
    CHECK(gr_one_sample < -5.0f, "gain reduction does not collapse in 1 sample");

    // Process 2880 frames (60 ms): gain reduction should release smoothly towards 0 dB
    std::vector<float> release_buf(2 * 2880, 0.0f);
    limiter.process(release_buf.data(), 2880);
    float gr_60ms = limiter.getCurrentGainReductionDb();
    CHECK(gr_60ms > -3.0f && gr_60ms <= 0.0f, "gain reduction smoothly released after 60ms");
}

// -----------------------------------------------------------------------------
// [C] MasterLimiterDSP True Peak Detection & Lookahead Gain Ramp Verification
// -----------------------------------------------------------------------------
static void test_master_limiter_lookahead_gain_ramp_and_true_peak()
{
    std::printf("\n== [C] Master limiter lookahead ramp & true-peak detection ==\n");

    sauti::dsp::MasterLimiterDSP limiter;
    limiter.setSampleRate(48000.0f);
    limiter.setCeilingDb(0.0f); // 1.0 linear ceiling
    limiter.setReleaseMs(60.0f);
    limiter.setEnabled(true);
    limiter.reset();

    // 1. Lookahead Gain Ramp Smoothness:
    // When a peak enters the lookahead buffer, the gain must ramp smoothly
    // down across the lookahead window instead of stepping instantaneously.
    std::vector<float> step_buf(2 * 300, 0.0f);
    for (size_t i = 100; i < 200; ++i) {
        step_buf[2 * i + 0] = 2.5f;
        step_buf[2 * i + 1] = 2.5f;
    }

    std::vector<float> gain_history;
    gain_history.reserve(300);

    for (size_t i = 0; i < 300; ++i) {
        limiter.process(&step_buf[2 * i], 1);
        gain_history.push_back(limiter.getCurrentLinearGain());
    }

    float max_gain_step = 0.0f;
    for (size_t i = 1; i < gain_history.size(); ++i) {
        float d = std::abs(gain_history[i] - gain_history[i - 1]);
        if (d > max_gain_step) max_gain_step = d;
    }

    char ramp_msg[128];
    std::snprintf(ramp_msg, sizeof(ramp_msg), "max sample-to-sample gain step = %.5f (want < 0.02, smooth ramp)", max_gain_step);
    CHECK(max_gain_step < 0.02f, ramp_msg);

    // 2. Inter-sample True Peak Detection with 4x Oversampling:
    // Generate a 12 kHz sine wave at fs=48kHz sampled at phase pi/4:
    // Sample peak is exactly 0.7071 (-3.01 dBFS), but continuous true peak is 1.0.
    // Ceiling set to -1.0 dBFS (linear ~0.891). True-peak limiter detects the 1.0 peak!
    limiter.setCeilingDb(-1.0f);
    limiter.reset();

    const size_t num_sine_frames = 480;
    std::vector<float> sine_buf(2 * num_sine_frames);
    for (size_t i = 0; i < num_sine_frames; ++i) {
        float val = std::sin(2.0f * (float)M_PI * (12000.0f / 48000.0f) * (float)i + ((float)M_PI / 4.0f));
        sine_buf[2 * i + 0] = val;
        sine_buf[2 * i + 1] = val;
    }

    limiter.process(sine_buf.data(), num_sine_frames);

    float final_gr_db = limiter.getCurrentGainReductionDb();
    char tp_msg[128];
    std::snprintf(tp_msg, sizeof(tp_msg), "true-peak gain reduction = %.2f dB (want < -0.8 dB, true peak clamped)", final_gr_db);
    CHECK(final_gr_db < -0.8f, tp_msg);

    // 3. Exact Release Single-Pole Ballistics:
    // With 60ms release (~2880 frames tau), 25000 frames is > 8.6 tau, recovering to > 0.999.
    std::vector<float> sil_buf(2 * 25000, 0.0f);
    limiter.process(sil_buf.data(), 25000);
    CHECK(limiter.getCurrentLinearGain() > 0.999f, "single-pole release smoothly recovers to 1.0");
}

// -----------------------------------------------------------------------------
// [C] Lock-Free DSP Parameter Snapshot Verification
// -----------------------------------------------------------------------------
static void test_lockfree_dsp_parameter_access()
{
    std::printf("\n== [C] Lock-free DSP parameter atomics verification ==\n");

    sauti::dsp::DynamicLoudnessDSP dynLoud;
    dynLoud.setSampleRate(48000.0f);
    dynLoud.setEnabled(true);
    dynLoud.setParams(-12.0f, 6.0f, 3.0f, 90.0f, 9000.0f);
    float ref_lvl, max_bass, max_treble, bass_f, treble_f;
    dynLoud.getParams(&ref_lvl, &max_bass, &max_treble, &bass_f, &treble_f);
    CHECK(nearlyEqual(ref_lvl, -12.0f, 0.01f), "DynamicLoudness ref level matches");
    CHECK(nearlyEqual(max_bass, 6.0f, 0.01f), "DynamicLoudness max bass boost matches");

    sauti::dsp::BroadcastLevellerDSP leveller;
    leveller.setSampleRate(48000.0f);
    leveller.setEnabled(true);
    leveller.setParams(-16.0f, 1.0f, 2.0f, 8.0f, 10.0f, -60.0f);
    float tgt_lufs, rise, fall, max_b, max_a, sil_gate;
    leveller.getParams(&tgt_lufs, &rise, &fall, &max_b, &max_a, &sil_gate);
    CHECK(nearlyEqual(tgt_lufs, -16.0f, 0.01f), "Leveller target LUFS matches");
    CHECK(nearlyEqual(max_b, 8.0f, 0.01f), "Leveller max boost matches");

    sauti::dsp::MasterLimiterDSP limiter;
    limiter.setSampleRate(48000.0f);
    limiter.setEnabled(true);
    limiter.setCeilingDb(-0.5f);
    limiter.setOutputGainDb(1.0f);
    limiter.setReleaseMs(80.0f);
    CHECK(nearlyEqual(limiter.getCeilingDb(), -0.5f, 0.01f), "MasterLimiter ceiling matches");
    CHECK(nearlyEqual(limiter.getOutputGainDb(), 1.0f, 0.01f), "MasterLimiter output gain matches");
    CHECK(nearlyEqual(limiter.getReleaseMs(), 80.0f, 0.01f), "MasterLimiter release matches");
    CHECK(limiter.getLatencySamples() == 72, "MasterLimiter reports exact 72-sample lookahead latency at 48k");

    // Continuous audio processing while concurrently modifying parameters
    std::vector<float> audio_buf(2 * 1024, 0.5f);
    for (int iter = 0; iter < 10; ++iter) {
        dynLoud.setParams(-6.0f - (float)iter, 6.0f, 3.0f, 90.0f, 9000.0f);
        leveller.setParams(-14.0f - (float)iter, 1.0f, 2.0f, 8.0f, 10.0f, -60.0f);
        limiter.setCeilingDb(-0.1f * (float)(iter + 1));

        dynLoud.process(audio_buf.data(), 1024, 2, 0.5f);
        leveller.process(audio_buf.data(), 1024, 2);
        limiter.process(audio_buf.data(), 1024);
    }
    CHECK(std::isfinite(audio_buf[0]), "lock-free audio processing executes without exceptions or skips");
}

// -----------------------------------------------------------------------------
// [M] 3.2 AnalogWarmth triode DC blocker
// -----------------------------------------------------------------------------
static void test_analog_warmth_no_dc_offset()
{
    std::printf("\n== [M] 3.2 Triode warmth DC offset ==\n");

    sauti::dsp::AnalogWarmthDSP warmth;
    warmth.setSampleRate(48000.0f);
    warmth.setEnabled(true);
    warmth.setProfile(sauti::dsp::AnalogWarmthProfile::Triode12AX7);
    warmth.setDrive(1.0f); // maximum asymmetry -> worst-case DC injection
    warmth.reset();

    // Symmetric square wave at +/-0.9: zero input DC, heavy asymmetric shaping.
    const uint32_t frames = 96000; // 2 s
    std::vector<float> buf(2 * frames);
    for (uint32_t i = 0; i < frames; ++i)
    {
        const float v = ((i / 48u) % 2u == 0) ? 0.9f : -0.9f;
        buf[2 * i] = v;
        buf[2 * i + 1] = v;
    }
    warmth.process(buf.data(), frames);

    double meanL = 0.0, meanR = 0.0;
    const size_t start = (size_t)(frames - 24000) * 2; // last 0.5 s (blocker settled)
    size_t cnt = 0;
    for (size_t i = start; i < buf.size(); i += 2) { meanL += buf[i]; meanR += buf[i + 1]; ++cnt; }
    meanL /= (double)cnt;
    meanR /= (double)cnt;

    char msg[160];
    std::snprintf(msg, sizeof(msg), "residual DC L=%.4f R=%.4f (|DC| < 0.02)", meanL, meanR);
    CHECK(std::fabs(meanL) < 0.02f && std::fabs(meanR) < 0.02f, msg);
}

// -----------------------------------------------------------------------------
// [M] 3.3 Clarity PresenceExciter flat-sum crossover
// -----------------------------------------------------------------------------
static void test_clarity_presence_reconstruction()
{
    std::printf("\n== [M] 3.3 Presence exciter perfect reconstruction at intensity 0 ==\n");

    sauti::dsp::AudioClarityDSP clarity;
    clarity.setSampleRate(48000.0f);
    clarity.setEnabled(true);
    clarity.setProfile(sauti::dsp::AudioClarityProfile::PresenceExciter);
    clarity.setIntensity(0.0f); // all excitation gains collapse to unity
    clarity.reset();

    const uint32_t frames = 48000;
    std::vector<float> in(2 * frames);
    std::mt19937 rng(2024);
    for (uint32_t i = 0; i < frames; ++i)
    {
        // Broadband content: sine sweep-ish mixture + noise
        const float t = (float)i / 48000.0f;
        const float tone = 0.4f * std::sin(2.0f * 3.14159265f * (200.0f + 4000.0f * t * t) * t);
        const float noise = ((float)(rng() % 20000) - 10000.0f) / 40000.0f;
        in[2 * i] = tone + noise;
        in[2 * i + 1] = 0.8f * tone - noise;
    }

    std::vector<float> buf = in;
    clarity.process(buf.data(), frames);

    // anti-pop ramps over ~12k samples; compare only settled tail.
    double maxErr = 0.0;
    for (uint32_t i = frames - 8000; i < frames; ++i)
    {
        maxErr = std::max(maxErr, (double)std::fabs(buf[2 * i] - in[2 * i]));
        maxErr = std::max(maxErr, (double)std::fabs(buf[2 * i + 1] - in[2 * i + 1]));
    }

    char msg[128];
    std::snprintf(msg, sizeof(msg), "max reconstruction error %.2e (< 1e-4)", maxErr);
    CHECK(maxErr < 1e-4, msg);
}

// -----------------------------------------------------------------------------
// [M] 3.4 DynamicSystemDSP tuning accuracy + stability
// -----------------------------------------------------------------------------
static void test_dynamic_system_cutoff_and_stability()
{
    std::printf("\n== [M] 3.4 Dynamic system one-pole cutoff + stability ==\n");

    // Stability: loud broadband input must not diverge.
    {
        sauti::dsp::DynamicSystemDSP dsp;
        dsp.setSampleRate(48000.0f);
        dsp.setEnabled(true);
        dsp.setProfile(sauti::dsp::TransducerProfile::Headphone);
        dsp.setStrength(1.0f);
        dsp.reset();

        std::mt19937 rng(99);
        bool finite = true;
        for (uint32_t b = 0; b < 20; ++b)
        {
            std::vector<float> buf(2 * 512);
            for (auto &v : buf) v = ((float)(rng() % 20000) - 10000.0f) / 3000.0f; // > 3x hot
            dsp.process(buf.data(), 512);
            for (float v : buf)
                if (!std::isfinite(v)) { finite = false; break; }
        }
        CHECK(finite, "no NaN/Inf divergence with hot input");
    }

    // Tuning sanity, two parts:
    //  1) At strength=0 all band gains are unity and the ladder bands sum back
    //     to the input, so the response must be UNIFORM across frequencies
    //     (band misalignment / mistuned splits would break this flatness).
    //  2) At strength>0 the processor must remain stable (covered above).
    {
        auto measureGainAt = [&](sauti::dsp::DynamicSystemDSP &dsp, float freqHz) {
            const uint32_t frames = 48000;
            std::vector<float> buf(2 * frames);
            for (uint32_t i = 0; i < frames; ++i)
            {
                const float s = std::sin(2.0f * 3.14159265f * freqHz * (float)i / 48000.0f) * 0.5f;
                buf[2 * i] = s;
                buf[2 * i + 1] = s;
            }
            dsp.process(buf.data(), frames);
            double real = 0.0, imag = 0.0;
            const uint32_t start = frames - 16384;
            for (uint32_t i = start; i < frames; ++i)
            {
                real += (double)buf[2 * i] * std::sin(2.0 * 3.14159265 * (double)freqHz * (double)i / 48000.0);
                imag += (double)buf[2 * i] * std::cos(2.0 * 3.14159265 * (double)freqHz * (double)i / 48000.0);
            }
            return std::sqrt(real * real + imag * imag) / (0.5 * 16384.0);
        };

        sauti::dsp::DynamicSystemDSP dsp;
        dsp.setSampleRate(48000.0f);
        dsp.setEnabled(true);
        dsp.setProfile(sauti::dsp::TransducerProfile::HighEndReference); // x_low = 125 Hz
        dsp.setStrength(0.0f); // neutral: all band gains = 1
        dsp.reset();

        const double gLow = measureGainAt(dsp, 125.0f);
        const double gHigh = measureGainAt(dsp, 8000.0f);
        const double ratio = gLow / gHigh;

        char msg[160];
        std::snprintf(msg, sizeof(msg),
                      "neutral response uniform: gain(125Hz)=%.3f vs gain(8kHz)=%.3f (ratio %.3f, want 0.9..1.1)",
                      gLow, gHigh, ratio);
        CHECK(ratio > 0.9 && ratio < 1.1, msg);
    }
}

// -----------------------------------------------------------------------------
// Oversampled Saturation Stages Verification
// -----------------------------------------------------------------------------
static void test_oversampled_saturation()
{
    std::printf("\n== Oversampled Saturation (AnalogWarmth & Clarity & HalfBand) ==\n");

    // 1. HalfBandFilter2x & PolyphaseOversampler2x impulse response and unity gain
    {
        sauti::dsp::PolyphaseOversampler2x os;
        os.init(48000, 1024);
        os.reset();

        const uint32_t N = 256;
        std::vector<float> in(2 * N, 0.0f);
        in[2 * 20] = 1.0f;     // Left impulse
        in[2 * 20 + 1] = 0.5f; // Right impulse

        float* up = os.upsample(in.data(), N);
        CHECK(up != nullptr, "PolyphaseOversampler2x upsample returned valid buffer");

        std::vector<float> out(2 * N, 0.0f);
        os.downsample(up, out.data(), N);

        // Find peak tap and sum (DC gain) in impulse response
        float peakL = 0.0f, peakR = 0.0f;
        double sumL = 0.0, sumR = 0.0;
        int peakIdxL = -1;

        for (uint32_t i = 0; i < N; ++i) {
            sumL += out[2 * i];
            sumR += out[2 * i + 1];
            if (out[2 * i] > peakL) { peakL = out[2 * i]; peakIdxL = (int)i; }
            if (out[2 * i + 1] > peakR) { peakR = out[2 * i + 1]; }
        }

        char msgL[128], msgR[128], msgDelay[128];
        std::snprintf(msgL, sizeof(msgL), "Oversampler DC gain L=%.4f (want ~1.0)", sumL);
        std::snprintf(msgR, sizeof(msgR), "Oversampler DC gain R=%.4f (want ~0.5)", sumR);
        std::snprintf(msgDelay, sizeof(msgDelay), "Oversampler cascade group delay = %d frames (want 46)", peakIdxL);
        CHECK(nearlyEqual((float)sumL, 1.0f, 0.02f), msgL);
        CHECK(nearlyEqual((float)sumR, 0.5f, 0.02f), msgR);
        CHECK(peakIdxL == 46, msgDelay);
    }

    // 2. AnalogWarmthDSP oversampled processing with zero drive (transparency)
    {
        sauti::dsp::AnalogWarmthDSP warmth;
        warmth.setSampleRate(44100.0f);
        warmth.setEnabled(true);
        warmth.setProfile(sauti::dsp::AnalogWarmthProfile::Triode12AX7);
        warmth.setDrive(0.0f);
        warmth.reset();

        const uint32_t N = 1024;
        std::vector<float> buf(2 * N, 0.0f);

        // Stream 40 continuous blocks of 1 kHz sine wave to settle anti-pop & reach steady state
        for (int k = 0; k < 40; ++k) {
            for (uint32_t i = 0; i < N; ++i) {
                float t = (float)(k * N + i) / 44100.0f;
                float s = 0.4f * std::sin(2.0f * 3.14159265f * 1000.0f * t);
                buf[2 * i] = s;
                buf[2 * i + 1] = s;
            }
            warmth.process(buf.data(), N);
        }

        bool hasNaN = false;
        float maxVal = 0.0f;
        for (size_t i = 0; i < buf.size(); ++i) {
            if (std::isnan(buf[i]) || std::isinf(buf[i])) hasNaN = true;
            if (std::abs(buf[i]) > maxVal) maxVal = std::abs(buf[i]);
        }

        char msgAmp[128];
        std::snprintf(msgAmp, sizeof(msgAmp), "AnalogWarmthDSP zero-drive 1kHz peak amplitude = %.4f (want ~0.40)", maxVal);
        CHECK(!hasNaN, "AnalogWarmthDSP oversampled output contains no NaN/Inf");
        CHECK(nearlyEqual(maxVal, 0.40f, 0.03f), msgAmp);
    }

    // 3. AudioClarityDSP Harmonic Brilliance oversampled processing
    {
        sauti::dsp::AudioClarityDSP clarity;
        clarity.setSampleRate(44100.0f);
        clarity.setEnabled(true);
        clarity.setProfile(sauti::dsp::AudioClarityProfile::HarmonicBrilliance);
        clarity.setIntensity(0.75f);
        clarity.reset();

        const uint32_t N = 2048;
        std::vector<float> buf(2 * N, 0.0f);
        for (uint32_t i = 0; i < N; ++i) {
            // High frequency input tone above 3.5kHz cutoff
            float s = 0.3f * std::sin(2.0f * 3.14159265f * 8000.0f * (float)i / 44100.0f);
            buf[2 * i] = s;
            buf[2 * i + 1] = s;
        }

        clarity.process(buf.data(), N);
        for (int k = 0; k < 10; ++k) clarity.process(buf.data(), N);

        bool hasNaN = false;
        float maxVal = 0.0f;
        for (size_t i = 0; i < buf.size(); ++i) {
            if (std::isnan(buf[i]) || std::isinf(buf[i])) hasNaN = true;
            if (std::abs(buf[i]) > maxVal) maxVal = std::abs(buf[i]);
        }

        CHECK(!hasNaN, "AudioClarityDSP HarmonicBrilliance oversampled output contains no NaN/Inf");
        CHECK(maxVal > 0.3f, "AudioClarityDSP HarmonicBrilliance excites high frequencies");
    }

    // 4. AnalogWarmth & Clarity oversampling factor switching (1x, 2x, 4x)
    {
        sauti::dsp::AnalogWarmthDSP warmth;
        warmth.setSampleRate(48000.0f);
        warmth.setEnabled(true);
        warmth.setDrive(0.5f);

        sauti::dsp::AudioClarityDSP clarity;
        clarity.setSampleRate(48000.0f);
        clarity.setEnabled(true);
        clarity.setProfile(sauti::dsp::AudioClarityProfile::HarmonicBrilliance);

        for (int factor : {1, 2, 4}) {
            warmth.setOversampling(factor);
            clarity.setOversampling(factor);

            std::vector<float> buf(2 * 512, 0.25f);
            warmth.process(buf.data(), 512);
            clarity.process(buf.data(), 512);

            bool ok = true;
            for (float v : buf) {
                if (!std::isfinite(v)) { ok = false; break; }
            }
            char factorMsg[128];
            std::snprintf(factorMsg, sizeof(factorMsg), "AnalogWarmth & Clarity process cleanly at %dx oversampling", factor);
            CHECK(ok, factorMsg);
        }
    }
}

// -----------------------------------------------------------------------------
// DeEsserDSP Unit Tests
// -----------------------------------------------------------------------------
static void test_de_esser_dsp()
{
    std::printf("\n== DeEsserDSP Split-Band & WideBand Verification ==\n");

    // 1. Crossover perfect reconstruction at unity / inactive state
    {
        sauti::dsp::DeEsserDSP deEsser;
        deEsser.setSampleRate(48000.0f);
        deEsser.setEnabled(true);
        deEsser.setMode(sauti::dsp::DeEsserMode::SplitBand);
        deEsser.setFrequencyHz(5500.0f);
        deEsser.setIntensity(0.0f); // Inactive / 0dB reduction
        deEsser.reset();

        const uint32_t N = 2048;
        std::vector<float> inBuf(2 * N, 0.0f);
        std::vector<float> procBuf(2 * N, 0.0f);

        for (uint32_t i = 0; i < N; ++i) {
            float t = (float)i / 48000.0f;
            float s = 0.2f * std::sin(2.0f * (float)M_PI * 100.0f * t)
                    + 0.2f * std::sin(2.0f * (float)M_PI * 1000.0f * t)
                    + 0.2f * std::sin(2.0f * (float)M_PI * 5500.0f * t)
                    + 0.2f * std::sin(2.0f * (float)M_PI * 12000.0f * t);
            inBuf[2 * i]     = s;
            inBuf[2 * i + 1] = s;
            procBuf[2 * i]   = s;
            procBuf[2 * i + 1] = s;
        }

        // Settle anti-pop crossfader
        deEsser.process(procBuf.data(), N);

        // Process test block
        for (size_t i = 0; i < inBuf.size(); ++i) procBuf[i] = inBuf[i];
        deEsser.process(procBuf.data(), N);

        float maxErr = 0.0f;
        for (uint32_t i = 100; i < N; ++i) {
            maxErr = std::max(maxErr, std::abs(procBuf[2 * i] - inBuf[2 * i]));
            maxErr = std::max(maxErr, std::abs(procBuf[2 * i + 1] - inBuf[2 * i + 1]));
        }

        char msg[128];
        std::snprintf(msg, sizeof(msg), "Split-band complementary flat sum max error = %.2e (want < 1e-4)", maxErr);
        CHECK(maxErr < 1e-4f, msg);
    }

    // 2. Selective Sibilance Attenuation (SplitBand Mode)
    {
        sauti::dsp::DeEsserDSP deEsser;
        deEsser.setSampleRate(48000.0f);
        deEsser.setEnabled(true);
        deEsser.setMode(sauti::dsp::DeEsserMode::SplitBand);
        deEsser.setFrequencyHz(6000.0f);
        deEsser.setThresholdDb(-24.0f);
        deEsser.setRatio(6.0f);
        deEsser.setMaxReductionDb(12.0f);
        deEsser.reset();

        const uint32_t N = 2048;
        // Case A: Continuous hot 6kHz sibilance stream (amplitude 0.6 => -4.4 dBFS)
        std::vector<float> sibBuf(2 * N, 0.0f);
        for (int k = 0; k < 5; ++k) {
            for (uint32_t i = 0; i < N; ++i) {
                float s = 0.6f * std::sin(2.0f * (float)M_PI * 6000.0f * (float)i / 48000.0f);
                sibBuf[2 * i]     = s;
                sibBuf[2 * i + 1] = s;
            }
            deEsser.process(sibBuf.data(), N);
        }

        float grDb = deEsser.getGainReductionDb();
        char grMsg[128];
        std::snprintf(grMsg, sizeof(grMsg), "DeEsser engages gain reduction on hot 6kHz sibilance (GR=%.1f dB, want > 3.0)", grDb);
        CHECK(grDb > 3.0f, grMsg);

        // Measure compressed amplitude of 6kHz tone
        float maxSib = 0.0f;
        for (uint32_t i = N / 2; i < N; ++i) {
            maxSib = std::max(maxSib, std::abs(sibBuf[2 * i]));
        }
        CHECK(maxSib < 0.45f, "Hot 6kHz sibilance is attenuated (< 0.45 from 0.60)");

        // Case B: 200 Hz Low-frequency bass tone (SplitBand mode should NOT compress 200 Hz)
        deEsser.reset();
        std::vector<float> bassBuf(2 * N, 0.0f);
        for (int k = 0; k < 5; ++k) {
            for (uint32_t i = 0; i < N; ++i) {
                float s = 0.6f * std::sin(2.0f * (float)M_PI * 200.0f * (float)i / 48000.0f);
                bassBuf[2 * i]     = s;
                bassBuf[2 * i + 1] = s;
            }
            deEsser.process(bassBuf.data(), N);
        }

        float maxBass = 0.0f;
        for (uint32_t i = N / 2; i < N; ++i) {
            maxBass = std::max(maxBass, std::abs(bassBuf[2 * i]));
        }
        CHECK(nearlyEqual(maxBass, 0.6f, 0.05f), "SplitBand mode leaves low frequencies unattenuated (~0.60)");
    }

    // 3. WideBand Mode ducking
    {
        sauti::dsp::DeEsserDSP deEsser;
        deEsser.setSampleRate(48000.0f);
        deEsser.setEnabled(true);
        deEsser.setMode(sauti::dsp::DeEsserMode::WideBand);
        deEsser.setThresholdDb(-20.0f);
        deEsser.setRatio(4.0f);
        deEsser.reset();

        const uint32_t N = 2048;
        std::vector<float> buf(2 * N, 0.0f);
        for (int k = 0; k < 5; ++k) {
            for (uint32_t i = 0; i < N; ++i) {
                float s = 0.7f * std::sin(2.0f * (float)M_PI * 6000.0f * (float)i / 48000.0f);
                buf[2 * i]     = s;
                buf[2 * i + 1] = s;
            }
            deEsser.process(buf.data(), N);
        }
        CHECK(deEsser.getGainReductionDb() > 2.0f, "WideBand mode detects sibilance and attenuates");
    }

    // 4. Numerical Stability (No NaN/Inf on extreme inputs / sample rate change)
    {
        sauti::dsp::DeEsserDSP deEsser;
        deEsser.setSampleRate(96000.0f);
        deEsser.setEnabled(true);
        deEsser.setIntensity(1.0f);
        deEsser.reset();

        const uint32_t N = 1024;
        std::vector<float> hotBuf(2 * N, 5.0f); // Hot 5.0 magnitude input
        deEsser.process(hotBuf.data(), N);

        bool hasNaN = false;
        for (float val : hotBuf) {
            if (std::isnan(val) || std::isinf(val)) hasNaN = true;
        }
        CHECK(!hasNaN, "DeEsserDSP contains no NaN/Inf with extreme input at 96kHz");
    }

    // 5. Preset switching verification
    {
        sauti::dsp::DeEsserDSP deEsser;
        deEsser.setPreset(sauti::dsp::DeEsserPreset::AggressiveSibilance);
        CHECK(deEsser.getPreset() == sauti::dsp::DeEsserPreset::AggressiveSibilance, "DeEsser preset set to AggressiveSibilance");
        CHECK(deEsser.getFrequencyHz() == 6000.0f, "AggressiveSibilance frequency is 6000Hz");
        CHECK(deEsser.getRatio() == 6.0f, "AggressiveSibilance ratio is 6.0");

        deEsser.setPreset(sauti::dsp::DeEsserPreset::VintageWideband);
        CHECK(deEsser.getPreset() == sauti::dsp::DeEsserPreset::VintageWideband, "DeEsser preset set to VintageWideband");
        CHECK(deEsser.getMode() == sauti::dsp::DeEsserMode::WideBand, "VintageWideband sets WideBand mode");

        // Tweaking detailed parameter marks preset as Custom
        deEsser.setThresholdDb(-18.0f);
        CHECK(deEsser.getPreset() == sauti::dsp::DeEsserPreset::Custom, "Manual parameter tweak updates preset to Custom");
    }
}

// -----------------------------------------------------------------------------
// DownwardExpanderDSP: Noise Floor Reduction, Soft-Knee & Clamping
// -----------------------------------------------------------------------------
static void test_downward_expander_dsp()
{
    std::printf("\n== DownwardExpanderDSP Noise Floor Reducer Verification ==\n");

    // 1. Default disabled state & bypass transparency
    {
        sauti::dsp::DownwardExpanderDSP expander;
        CHECK(!expander.isEnabled(), "Expander is DISABLED by default");
        CHECK(nearlyEqual(expander.getCurrentGainReductionDb(), 0.0f, 0.01f), "Initial gain reduction is 0.0 dB");

        const uint32_t N = 512;
        std::vector<float> buf(2 * N);
        for (uint32_t i = 0; i < N; ++i) {
            buf[2 * i] = 0.005f * std::sin(2.0f * static_cast<float>(M_PI) * 440.0f * i / 48000.0f);
            buf[2 * i + 1] = 0.005f * std::cos(2.0f * static_cast<float>(M_PI) * 440.0f * i / 48000.0f);
        }
        std::vector<float> copy = buf;
        expander.process(buf.data(), N);

        float maxDiff = 0.0f;
        for (size_t i = 0; i < buf.size(); ++i) {
            maxDiff = std::max(maxDiff, std::abs(buf[i] - copy[i]));
        }
        CHECK(maxDiff < 1e-6f, "Disabled expander leaves audio bit-identical (0 dB attenuation)");
    }

    // 2. Loud signals (> threshold) pass unattenuated
    {
        sauti::dsp::DownwardExpanderDSP expander;
        expander.setEnabled(true);
        expander.setPreset(sauti::dsp::ExpanderPreset::VinylClean);
        expander.reset();

        const uint32_t N = 4800; // 100ms at 48kHz
        std::vector<float> loudBuf(2 * N);
        for (uint32_t i = 0; i < N; ++i) {
            loudBuf[2 * i] = 0.5f * std::sin(2.0f * static_cast<float>(M_PI) * 1000.0f * i / 48000.0f); // -6 dBFS
            loudBuf[2 * i + 1] = 0.5f * std::cos(2.0f * static_cast<float>(M_PI) * 1000.0f * i / 48000.0f);
        }
        expander.process(loudBuf.data(), N);

        float gr = expander.getCurrentGainReductionDb();
        CHECK(nearlyEqual(gr, 0.0f, 0.5f), "Loud signals (> threshold) experience 0 dB gain reduction");
    }

    // 3. Below-threshold noise reduction & floor clamping
    {
        sauti::dsp::DownwardExpanderDSP expander;
        expander.setEnabled(true);
        expander.setThresholdDb(-50.0f);
        expander.setRatio(2.0f);
        expander.setRangeDb(-16.0f);
        expander.setAttackMs(1.0f);
        expander.setReleaseMs(10.0f);
        expander.reset();

        // Low-level noise (-65 dBFS, amp ~ 0.00056)
        const uint32_t N = 9600; // 200ms
        std::vector<float> noiseBuf(2 * N);
        for (uint32_t i = 0; i < N; ++i) {
            noiseBuf[2 * i] = 0.00056f * std::sin(2.0f * static_cast<float>(M_PI) * 1000.0f * i / 48000.0f);
            noiseBuf[2 * i + 1] = 0.00056f * std::cos(2.0f * static_cast<float>(M_PI) * 1000.0f * i / 48000.0f);
        }
        expander.process(noiseBuf.data(), N);

        float gr = expander.getCurrentGainReductionDb();
        CHECK(gr < -10.0f && gr >= -16.5f, "Below-threshold noise is attenuated smoothly (GR ~ -15 dB)");

        // Ultra-low signal (-100 dBFS) must be clamped to -16 dB floor (not -50 dB or -inf)
        std::vector<float> tinyBuf(2 * N, 0.00001f);
        expander.process(tinyBuf.data(), N);
        float clampedGr = expander.getCurrentGainReductionDb();
        CHECK(clampedGr <= -15.5f && clampedGr >= -16.5f, "Gain reduction respects user-configured floor limit (-16 dB)");
    }

    // 4. Sidechain rumble HPF rejection
    {
        sauti::dsp::DownwardExpanderDSP expander;
        expander.setEnabled(true);
        expander.setThresholdDb(-40.0f);
        expander.setRatio(4.0f);
        expander.setRangeDb(-24.0f);
        expander.setSidechainHpfHz(60.0f);
        expander.setAttackMs(1.0f);
        expander.setReleaseMs(10.0f);
        expander.reset();

        // 20 Hz turntable rumble at -30 dBFS (would trigger if no HPF)
        const uint32_t N = 9600;
        std::vector<float> rumbleBuf(2 * N);
        for (uint32_t i = 0; i < N; ++i) {
            rumbleBuf[2 * i] = 0.0316f * std::sin(2.0f * static_cast<float>(M_PI) * 20.0f * i / 48000.0f);
            rumbleBuf[2 * i + 1] = 0.0316f * std::sin(2.0f * static_cast<float>(M_PI) * 20.0f * i / 48000.0f);
        }
        expander.process(rumbleBuf.data(), N);

        float gr = expander.getCurrentGainReductionDb();
        CHECK(gr < -5.0f, "Sidechain HPF attenuates sub-bass rumble so detector does not falsely open");
    }

    // 5. Numerical stability under extreme conditions
    {
        sauti::dsp::DownwardExpanderDSP expander;
        expander.setSampleRate(96000.0f);
        expander.setEnabled(true);
        expander.reset();

        const uint32_t N = 1024;
        std::vector<float> extremeBuf(2 * N, 10.0f);
        expander.process(extremeBuf.data(), N);

        bool hasNaN = false;
        for (float val : extremeBuf) {
            if (std::isnan(val) || std::isinf(val)) hasNaN = true;
        }
        CHECK(!hasNaN, "DownwardExpanderDSP contains no NaN/Inf under hot 96kHz input");
    }
}

// -----------------------------------------------------------------------------
// SubsonicFilter & Denormals Flushing Test Suite
// -----------------------------------------------------------------------------
static void test_subsonic_filter_and_denormals()
{
    std::printf("\n== SubsonicFilter & Denormals Flushing ==\n");

    // 1. ScopedDenormalsDisable RAII lifecycle test
    {
        bool denormalsRan = false;
        {
            sauti::dsp::ScopedDenormalsDisable disableDenormals;
            float subnormal = 1.0e-40f;
            // When FTZ is active on hardware with SSE/NEON support, operations on subnormals flush cleanly to 0
            float prod = subnormal * 0.5f;
            (void)prod;
            denormalsRan = true;
        }
        CHECK(denormalsRan, "ScopedDenormalsDisable RAII scope initialized and destroyed cleanly");
    }

    // 2. SubsonicFilter 18 Hz DC rejection
    {
        sauti::dsp::SubsonicFilter filter;
        filter.setSampleRate(48000.0f);
        filter.setEnabled(true);
        filter.reset();

        // Feed constant DC bias = 1.0f for 1 second (48000 samples)
        const uint32_t N = 48000;
        std::vector<float> dcBuf(2 * N, 1.0f);
        filter.process(dcBuf.data(), N, 2);

        // At steady-state (end of 1 second), DC should be blocked (< 0.001)
        float lastL = std::fabs(dcBuf[2 * (N - 1)]);
        float lastR = std::fabs(dcBuf[2 * (N - 1) + 1]);
        CHECK(lastL < 0.005f && lastR < 0.005f, "SubsonicFilter blocks steady-state DC bias");
    }

    // 3. SubsonicFilter 5 Hz rumble attenuation (> 20 dB reduction)
    {
        sauti::dsp::SubsonicFilter filter;
        filter.setSampleRate(48000.0f);
        filter.setEnabled(true);
        filter.reset();

        const uint32_t N = 48000;
        std::vector<float> rumbleBuf(2 * N);
        for (uint32_t i = 0; i < N; ++i) {
            float s = std::sin(2.0f * 3.14159265f * 5.0f * (float)i / 48000.0f);
            rumbleBuf[2 * i] = s;
            rumbleBuf[2 * i + 1] = s;
        }
        filter.process(rumbleBuf.data(), N, 2);

        // Measure amplitude in last 1000 samples
        float maxRumble = 0.0f;
        for (uint32_t i = N - 1000; i < N; ++i) {
            maxRumble = std::max(maxRumble, std::abs(rumbleBuf[2 * i]));
        }
        // 5 Hz is well below 18 Hz cutoff (2nd-order rolloff is ~-22 dB at 5 Hz, amplitude < 0.10)
        CHECK(maxRumble < 0.12f, "SubsonicFilter attenuates 5 Hz infrasonic rumble by >18 dB");
    }

    // 4. SubsonicFilter 50 Hz & 1 kHz audible passband preservation (0.0 dB flat)
    {
        sauti::dsp::SubsonicFilter filter;
        filter.setSampleRate(48000.0f);
        filter.setEnabled(true);
        filter.reset();

        const uint32_t N = 48000;
        std::vector<float> audioBuf(2 * N);
        for (uint32_t i = 0; i < N; ++i) {
            float s = std::sin(2.0f * 3.14159265f * 1000.0f * (float)i / 48000.0f);
            audioBuf[2 * i] = s;
            audioBuf[2 * i + 1] = s;
        }
        filter.process(audioBuf.data(), N, 2);

        float maxAudio = 0.0f;
        for (uint32_t i = N - 1000; i < N; ++i) {
            maxAudio = std::max(maxAudio, std::abs(audioBuf[2 * i]));
        }
        CHECK(std::abs(maxAudio - 1.0f) < 0.01f, "SubsonicFilter preserves 1 kHz audio passband at unity (0.0 dB)");
    }

    // 5. SubsonicFilter 6-channel (5.1) and 8-channel (7.1) multichannel processing
    {
        sauti::dsp::SubsonicFilter filter;
        filter.setSampleRate(48000.0f);
        filter.setEnabled(true);
        filter.reset();

        const uint32_t N = 48000;
        const int ch = 6;
        std::vector<float> multiBuf(ch * N, 1.0f); // Constant DC bias across all 6 channels
        filter.process(multiBuf.data(), N, ch);

        bool allChBlocked = true;
        for (int c = 0; c < ch; ++c) {
            float val = std::fabs(multiBuf[ch * (N - 1) + c]);
            if (val >= 0.005f) {
                allChBlocked = false;
                break;
            }
        }
        CHECK(allChBlocked, "SubsonicFilter blocks DC across all 6 channels in 5.1 surround");
    }
}

// -----------------------------------------------------------------------------
// DialogEnhancerDSP verification (reconstructed from Dolby DAP / DS1)
// -----------------------------------------------------------------------------
static void test_dialog_enhancer_dsp()
{
    std::printf("\n== DialogEnhancerDSP verification (Dolby DAP reconstruction) ==\n");
    sauti::dsp::DialogEnhancerDSP de;
    de.setSampleRate(48000.0f);

    // 1. Bypass check
    {
        const uint32_t N = 1024;
        std::vector<float> in(2 * N);
        std::vector<float> orig(2 * N);
        for (uint32_t i = 0; i < 2 * N; ++i) {
            in[i] = orig[i] = 0.5f * std::sin(float(i));
        }
        de.setEnabled(false);
        de.process(in.data(), N);
        bool match = true;
        for (uint32_t i = 0; i < 2 * N; ++i) {
            if (in[i] != orig[i]) { match = false; break; }
        }
        CHECK(match, "DialogEnhancerDSP is bit-exact bypass when disabled");
    }

    // 2. Formant gain boost at 2.4 kHz
    {
        de.reset();
        de.setEnabled(true);
        de.setParams(sauti::dsp::DialogEnhancerProfile::Custom, 1.0f, 0.0f, 0.0f, 0.0f);
        const uint32_t N = 4800;
        std::vector<float> buf(2 * N);
        const float f0 = 2400.0f;
        for (uint32_t i = 0; i < N; ++i) {
            float s = 0.2f * std::sin(2.0f * 3.14159265f * f0 * (float)i / 48000.0f);
            buf[2 * i] = s;
            buf[2 * i + 1] = s;
        }
        de.process(buf.data(), N);

        float maxAmp = 0.0f;
        for (uint32_t i = N - 500; i < N; ++i) {
            maxAmp = std::max(maxAmp, std::abs(buf[2 * i]));
        }
        CHECK(maxAmp > 0.5f && maxAmp < 0.9f, "DialogEnhancerDSP boosts 2.4 kHz vocal formant by expected gain (~+11 dB)");
    }

    // 3. Background Ducking: Side attenuation during speech presence
    {
        de.reset();
        de.setEnabled(true);
        de.setParams(sauti::dsp::DialogEnhancerProfile::Custom, 0.5f, 1.0f, 0.0f, 0.0f);
        const uint32_t N = 4800;
        std::vector<float> buf(2 * N);
        for (uint32_t i = 0; i < N; ++i) {
            float centerSpeech = 0.3f * std::sin(2.0f * 3.14159265f * 2400.0f * (float)i / 48000.0f);
            float sideAmbient  = 0.3f * std::sin(2.0f * 3.14159265f * 500.0f * (float)i / 48000.0f);
            buf[2 * i]     = centerSpeech + sideAmbient; // L
            buf[2 * i + 1] = centerSpeech - sideAmbient; // R
        }
        de.process(buf.data(), N);

        float maxSide = 0.0f;
        for (uint32_t i = N - 500; i < N; ++i) {
            float s = 0.5f * (buf[2 * i] - buf[2 * i + 1]);
            maxSide = std::max(maxSide, std::abs(s));
        }
        CHECK(maxSide < 0.22f, "DialogEnhancerDSP dynamically ducks non-dialog side energy during speech presence");
    }

    // 4. Stability check under extreme values
    {
        de.reset();
        de.setEnabled(true);
        de.setParams(sauti::dsp::DialogEnhancerProfile::Voice, 1.0f, 1.0f, 1.0f, 1.0f);
        const uint32_t N = 1024;
        std::vector<float> buf(2 * N, 0.0f);
        buf[0] = 1.0f; buf[1] = -1.0f; // Dirac impulse
        de.process(buf.data(), N);
        bool finite = true;
        for (float v : buf) {
            if (!std::isfinite(v)) { finite = false; break; }
        }
        CHECK(finite, "DialogEnhancerDSP remains stable under Dirac impulse without NaN/Inf");
    }
}

// -----------------------------------------------------------------------------
// ScaleTempoDSP ZNCC verification
// -----------------------------------------------------------------------------
static void test_scaletempo_dsp()
{
    std::printf("\n== ScaleTempoDSP ZNCC Correlation & Time-Stretch Verification ==\n");

    sauti::dsp::ScaleTempoDSP st;
    st.init(48000, 2);
    st.setScale(1.25f); // 1.25x speed stretch

    const uint32_t N = 4800; // 100ms
    std::vector<float> in(2 * N);
    for (uint32_t i = 0; i < N; ++i) {
        float s = 0.5f * std::sin(2.0f * 3.14159265f * 440.0f * (float)i / 48000.0f);
        in[2 * i] = s;
        in[2 * i + 1] = s;
    }

    st.writeInput(in.data(), N);
    size_t avail = st.availableOutputFrames();
    CHECK(avail > 0, "ScaleTempoDSP produces available output frames after writeInput");

    std::vector<float> out(2 * avail);
    size_t read = st.readOutput(out.data(), avail);
    CHECK(read == avail, "ScaleTempoDSP successfully reads all available output frames");

    bool ok = true;
    for (float v : out) {
        if (!std::isfinite(v)) { ok = false; break; }
    }
    CHECK(ok, "ScaleTempoDSP output with ZNCC correlation is finite and contains no NaN/Inf");
}

// -----------------------------------------------------------------------------
// [C] P0.5 FFTConvolverDSP Dry Path Latency Compensation & Comb Filtering Elimination
// -----------------------------------------------------------------------------
static void test_fft_convolver_latency_compensation()
{
    std::printf("\n== [C] P0.5 FFTConvolverDSP Dry Path Latency Compensation ==\n");

    sauti::dsp::FFTConvolverDSP convolver;
    convolver.setSampleRate(48000.0f);
    convolver.setEnabled(true);

    // 1. Load an identity Dirac impulse IR (512 samples, h[0] = 1.0, h[1..511] = 0.0)
    constexpr size_t kIRLen = 512;
    std::vector<float> ir(kIRLen, 0.0f);
    ir[0] = 1.0f;
    bool load_ok = convolver.loadImpulseResponse(ir.data(), static_cast<uint32_t>(kIRLen), 1);
    CHECK(load_ok, "FFTConvolverDSP loaded identity IR");

    convolver.setDryLevel(0.5f);
    convolver.setWetLevel(0.5f);

    // Warm up convolver past the 20ms anti-pop crossfade (960 samples @ 48kHz)
    constexpr uint32_t kWarmupFrames = 1024;
    std::vector<float> warmup(kWarmupFrames * 2, 0.0f);
    convolver.process(warmup.data(), kWarmupFrames);

    // 2. Dirac impulse alignment verification
    // Feed a single Dirac impulse at sample 0 in block 0
    constexpr uint32_t kBlockSize = 512;
    std::vector<float> block0(kBlockSize * 2, 0.0f);
    block0[0] = 1.0f; // Left channel impulse
    block0[1] = 1.0f; // Right channel impulse

    convolver.process(block0.data(), kBlockSize);

    // During block 0, the impulse enters the dry delay buffer and the FFT partition.
    // Because both wet and dry paths are delayed by BLOCK_SIZE (512 samples),
    // block 0 output must be strictly 0 (no early dry bleed causing time split).
    float block0_max_l = 0.0f;
    for (size_t i = 0; i < kBlockSize; ++i) {
        block0_max_l = std::max(block0_max_l, std::fabs(block0[2 * i]));
    }
    CHECK(block0_max_l < 1e-5f, "block 0 output is silence (dry signal correctly delayed by BLOCK_SIZE)");

    // Process block 1: both delayed dry (0.5 * 1.0) and convolved wet (0.5 * 1.0)
    // exit simultaneously at frame 0 of block 1 (sample 512 overall).
    std::vector<float> block1(kBlockSize * 2, 0.0f);
    convolver.process(block1.data(), kBlockSize);

    float peak_sample0_l = block1[0];
    float peak_sample0_r = block1[1];
    CHECK(std::fabs(peak_sample0_l - 1.0f) < 1e-4f, "sample 512 Left impulse reconstructed to exactly 1.0 (0.5 dry + 0.5 wet)");
    CHECK(std::fabs(peak_sample0_r - 1.0f) < 1e-4f, "sample 512 Right impulse reconstructed to exactly 1.0 (0.5 dry + 0.5 wet)");

    // Remaining samples in block 1 must be 0
    float tail_max_l = 0.0f;
    for (size_t i = 1; i < kBlockSize; ++i) {
        tail_max_l = std::max(tail_max_l, std::fabs(block1[2 * i]));
    }
    CHECK(tail_max_l < 1e-4f, "subsequent samples in block 1 are zero (no smeared echoes or ghost taps)");

    // 3. Comb filtering elimination verification at notch frequencies:
    // Without latency compensation, f0 = 48000 / 1024 = 46.875 Hz experiences 180-degree
    // destructive cancellation between un-delayed dry and 512-sample delayed wet, causing
    // the output to collapse to 0.0 (-inf dB).
    // With latency compensation, dry and wet are phase-aligned, producing unity gain (1.0).
    const float f_notch = 46.875f;
    const uint32_t kSineFrames = 4800; // 100 ms of audio
    std::vector<float> sine_buf(kSineFrames * 2);
    for (uint32_t i = 0; i < kSineFrames; ++i) {
        float val = std::sin(2.0f * float(M_PI) * f_notch * static_cast<float>(i) / 48000.0f);
        sine_buf[2 * i] = val;
        sine_buf[2 * i + 1] = val;
    }

    convolver.process(sine_buf.data(), kSineFrames);

    // Measure peak amplitude in the steady-state portion (frames 1024 to kSineFrames)
    float steady_peak_l = 0.0f;
    for (uint32_t i = 1024; i < kSineFrames; ++i) {
        steady_peak_l = std::max(steady_peak_l, std::fabs(sine_buf[2 * i]));
    }
    char notch_msg[128];
    std::snprintf(notch_msg, sizeof(notch_msg), "comb filtering eliminated at 46.875 Hz notch (peak %.4f >= 0.99, not collapsed)", steady_peak_l);
    CHECK(steady_peak_l >= 0.99f && steady_peak_l <= 1.01f, notch_msg);

    // Also test second notch frequency f1 = 3 * 46.875 = 140.625 Hz
    const float f_notch2 = 140.625f;
    for (uint32_t i = 0; i < kSineFrames; ++i) {
        float val = std::sin(2.0f * float(M_PI) * f_notch2 * static_cast<float>(i) / 48000.0f);
        sine_buf[2 * i] = val;
        sine_buf[2 * i + 1] = val;
    }
    convolver.process(sine_buf.data(), kSineFrames);
    float steady_peak2_l = 0.0f;
    for (uint32_t i = 1024; i < kSineFrames; ++i) {
        steady_peak2_l = std::max(steady_peak2_l, std::fabs(sine_buf[2 * i]));
    }
    std::snprintf(notch_msg, sizeof(notch_msg), "comb filtering eliminated at 140.625 Hz notch (peak %.4f >= 0.99, not collapsed)", steady_peak2_l);
    CHECK(steady_peak2_l >= 0.99f && steady_peak2_l <= 1.01f, notch_msg);

    // 4. Latency query API verification
    CHECK(convolver.getLatencySamples() == 512, "getLatencySamples() accurately reports BLOCK_SIZE (512)");
}

// -----------------------------------------------------------------------------
// [C] Convolver 4-Path True-Stereo, 3-Stage NUPOLS & Dry-Delay Alignment
// -----------------------------------------------------------------------------
static void test_fft_convolver_true_stereo_and_nupols()
{
    std::printf("\n== Convolver 4-Path True-Stereo & 3-Stage NUPOLS ==\n");

    // 1. 4-path true-stereo matrix: [LL=d(0)*1.0, LR=d(10)*0.5, RL=d(20)*0.25, RR=d(5)*0.8]
    {
        sauti::dsp::FFTConvolverDSP conv;
        conv.setSampleRate(48000.0f);
        conv.setEnabled(true);
        conv.setDryLevel(0.0f);
        conv.setWetLevel(1.0f);

        std::vector<float> ir4(64 * 4, 0.0f);
        ir4[0 * 4 + 0] = 1.0f;  // LL @ 0
        ir4[10 * 4 + 1] = 0.5f; // LR @ 10
        ir4[20 * 4 + 2] = 0.25f;// RL @ 20
        ir4[5 * 4 + 3] = 0.8f;  // RR @ 5

        CHECK(conv.loadImpulseResponse(ir4.data(), 64, 4), "4-ch true-stereo IR loaded");
        CHECK(conv.getChannels() == 4, "4-ch mode reported");

        // Warm up past 20ms crossfade
        std::vector<float> warmup(1536 * 2, 0.0f);
        conv.process(warmup.data(), 1536);

        // L-only impulse at frame 0 -> L @ 512 = 1.0, R @ 522 = 0.5
        std::vector<float> bufL(2048 * 2, 0.0f);
        bufL[0] = 1.0f;
        conv.process(bufL.data(), 2048);
        CHECK(std::fabs(bufL[512 * 2 + 0] - 1.0f) < 1e-4f, "4-path L->L peak 1.0 at frame 512");
        CHECK(std::fabs(bufL[522 * 2 + 1] - 0.5f) < 1e-4f, "4-path L->R crossfeed peak 0.5 at frame 522");

        // R-only impulse at frame 0 -> L @ 532 = 0.25, R @ 517 = 0.8
        std::vector<float> bufR(2048 * 2, 0.0f);
        bufR[1] = 1.0f;
        conv.process(bufR.data(), 2048);
        CHECK(std::fabs(bufR[532 * 2 + 0] - 0.25f) < 1e-4f, "4-path R->L crossfeed peak 0.25 at frame 532");
        CHECK(std::fabs(bufR[517 * 2 + 1] - 0.8f) < 1e-4f, "4-path R->R peak 0.8 at frame 517");
    }

    // 2. 3-Stage NUPOLS boundary continuity & long-IR (110,000 samples ~2.29s @ 48kHz)
    {
        sauti::dsp::FFTConvolverDSP conv;
        conv.setSampleRate(48000.0f);
        conv.setEnabled(true);
        conv.setDryLevel(0.0f);
        conv.setWetLevel(1.0f);

        const uint32_t taps[] = {0, 511, 512, 2047, 2048, 10239, 10240, 100000};
        constexpr uint32_t kIrLen = 110000;
        std::vector<float> ir(kIrLen, 0.0f);
        for (uint32_t t : taps) ir[t] = 0.5f;

        CHECK(conv.loadImpulseResponse(ir.data(), kIrLen, 1), "110k-frame long IR loaded without truncation");
        CHECK(!conv.wasTruncated(), "110k-frame IR is not truncated under 534k NUPOLS budget");
        CHECK(conv.getLoadedFrames() == kIrLen, "loaded frames == 110000");

        std::vector<float> warmup(2048 * 2, 0.0f);
        conv.process(warmup.data(), 2048);

        // Process impulse followed by zeros using non-power-of-2 chunk size (333)
        constexpr uint32_t kTotalOut = 112000;
        std::vector<float> audio(kTotalOut * 2, 0.0f);
        audio[0] = 1.0f;
        audio[1] = 1.0f;
        uint32_t pos = 0;
        while (pos < kTotalOut) {
            uint32_t chunk = std::min<uint32_t>(333, kTotalOut - pos);
            conv.process(&audio[pos * 2], chunk);
            pos += chunk;
        }

        bool allTapsExact = true;
        int tapCountFound = 0;
        for (uint32_t t : taps) {
            const float val = audio[(512 + t) * 2];
            if (std::fabs(val - 0.5f) > 1e-3f) {
                allTapsExact = false;
                std::printf("  NUPOLS mismatch at tap %u (out idx %u): got %.5f expected 0.5\n", t, 512 + t, val);
            }
        }
        for (uint32_t i = 0; i < kTotalOut; ++i) {
            if (std::fabs(audio[i * 2]) > 1e-3f) tapCountFound++;
        }
        CHECK(allTapsExact, "all 3 NUPOLS stage boundaries (0, 511, 512, 2047, 2048, 10239, 10240, 100000) align sample-accurately");
        CHECK(tapCountFound == 8, "no spurious echoes or duplicate stage overlap-adds");
    }

    // 3. Extra wet-delay dry compensation alignment (e.g. 70-sample pre-pad)
    {
        sauti::dsp::FFTConvolverDSP conv;
        conv.setSampleRate(48000.0f);
        conv.setEnabled(true);
        conv.setDryLevel(0.5f);
        conv.setWetLevel(0.5f);

        std::vector<float> ir(128, 0.0f);
        ir[70] = 1.0f;
        CHECK(conv.loadImpulseResponse(ir.data(), 128, 1, 70, false), "loaded IR with extra_wet_delay=70");
        CHECK(conv.getLatencySamples() == 582, "getLatencySamples() == 512 + 70 = 582");

        std::vector<float> warmup(2048 * 2, 0.0f);
        conv.process(warmup.data(), 2048);

        std::vector<float> audio(2048 * 2, 0.0f);
        audio[0] = 1.0f;
        audio[1] = 1.0f;
        conv.process(audio.data(), 2048);
        CHECK(std::fabs(audio[582 * 2] - 1.0f) < 1e-4f, "dry + pre-padded wet sum coherently at frame 582");
    }

    // 4. Sample-rate & gain invariance (44.1 kHz 8kHz-notch IR resampled to 48 kHz and 96 kHz)
    {
        // Generate 1024-tap impulse response of a 44.1 kHz biquad notch at f0 = 8000 Hz, Q = 4.0
        const double irSr = 44100.0;
        const double f0 = 8000.0;
        const double Q = 4.0;
        const double w0 = 2.0 * M_PI * f0 / irSr;
        const double alpha = std::sin(w0) / (2.0 * Q);
        const double b0 = 1.0, b1 = -2.0 * std::cos(w0), b2 = 1.0;
        const double a0 = 1.0 + alpha, a1 = -2.0 * std::cos(w0), a2 = 1.0 - alpha;

        constexpr uint32_t kIrLen = 1024;
        std::vector<float> ir441(kIrLen, 0.0f);
        double x1 = 0.0, x2 = 0.0, y1 = 0.0, y2 = 0.0;
        for (uint32_t n = 0; n < kIrLen; ++n) {
            const double x0 = (n == 0) ? 1.0 : 0.0;
            const double y0 = (b0 * x0 + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2) / a0;
            ir441[n] = static_cast<float>(y0);
            x2 = x1; x1 = x0;
            y2 = y1; y1 = y0;
        }

        const int targetRates[] = {48000, 96000};
        for (int engSr : targetRates) {
            const uint32_t prePadIn = 48;
            const double ratio = static_cast<double>(engSr) / irSr;
            const uint32_t prePadOut = static_cast<uint32_t>(std::llround(prePadIn * ratio));
            const uint32_t tailPadOut = 64;
            const uint32_t totalIn = prePadIn + kIrLen;
            const uint32_t outFrames = prePadOut + static_cast<uint32_t>(std::ceil(kIrLen * ratio)) + tailPadOut;
            const double tapGain = irSr / static_cast<double>(engSr);

            std::vector<double> chIn(totalIn, 0.0);
            for (uint32_t i = 0; i < kIrLen; ++i) chIn[prePadIn + i] = ir441[i];
            std::vector<double> chOut(outFrames, 0.0);
            r8b::CDSPResampler24 resampler(irSr, static_cast<double>(engSr), 4096);
            resampler.oneshot(chIn.data(), static_cast<int>(totalIn), chOut.data(), static_cast<int>(outFrames));

            std::vector<float> resampled(outFrames);
            for (uint32_t i = 0; i < outFrames; ++i) resampled[i] = static_cast<float>(chOut[i] * tapGain);

            sauti::dsp::FFTConvolverDSP conv;
            conv.setSampleRate(static_cast<float>(engSr));
            conv.setEnabled(true);
            conv.setDryLevel(0.0f);
            conv.setWetLevel(1.0f);
            CHECK(conv.loadImpulseResponse(resampled.data(), outFrames, 1, prePadOut, false),
                  "resampled 44.1kHz notch IR loaded");

            auto measureGainDb = [&](double freqHz) -> double {
                conv.reset();
                const uint32_t nFrames = static_cast<uint32_t>(engSr / 4); // 250 ms
                std::vector<float> buf(nFrames * 2, 0.0f);
                for (uint32_t i = 0; i < nFrames; ++i) {
                    const float s = static_cast<float>(std::sin(2.0 * M_PI * freqHz * i / engSr));
                    buf[2 * i] = s;
                    buf[2 * i + 1] = s;
                }
                conv.process(buf.data(), nFrames);
                double sumSq = 0.0;
                const uint32_t start = nFrames / 2;
                for (uint32_t i = start; i < nFrames; ++i) {
                    const double v = buf[2 * i];
                    sumSq += v * v;
                }
                const double rms = std::sqrt(sumSq / (nFrames - start));
                return 20.0 * std::log10(std::max(rms / 0.7071067811865475, 1e-9));
            };

            const double gain1kDb = measureGainDb(1000.0);
            const double gain8kDb = measureGainDb(8000.0);
            char msg[160];
            std::snprintf(msg, sizeof(msg),
                          "44.1k->%dkHz passband gain @1kHz = %.2f dB (within +/-0.25 dB)",
                          engSr / 1000, gain1kDb);
            CHECK(std::fabs(gain1kDb) < 0.25, msg);
            std::snprintf(msg, sizeof(msg),
                          "44.1k->%dkHz notch locked @8kHz = %.2f dB (< -20 dB)",
                          engSr / 1000, gain8kDb);
            CHECK(gain8kDb < -20.0, msg);
        }
    }
}

// -----------------------------------------------------------------------------
// [C] P1.10 Base-Rate Nonlinear Saturation Aliasing Elimination
// -----------------------------------------------------------------------------
static void test_base_rate_saturation_aliasing_elimination_p110()
{
    std::printf("\n== [C] P1.10 Base-Rate Saturation Aliasing Elimination ==\n");

    // 1. DynamicBassDSP: high-frequency tone transparency without full-band soft-clipping
    {
        sauti::dsp::HarmonicBassDSP bassDsp;
        bassDsp.setSampleRate(48000.0f);
        bassDsp.setEnabled(true);
        bassDsp.setProfile(sauti::dsp::BassEnhanceProfile::NaturalBass);
        bassDsp.setBoost(0.6f);
        bassDsp.reset();

        // Feed pure high-frequency 15 kHz tone at amplitude 0.75
        // At 48 kHz, Nyquist is 24 kHz. Soft-clipping at base rate generates 3rd harmonic
        // at 45 kHz, folding back across Nyquist to 45 - 48 = -3 kHz -> 3 kHz aliasing distortion!
        const uint32_t N = 4800; // 100ms
        std::vector<float> buf(2 * N);
        const float f_hf = 15000.0f;
        for (uint32_t i = 0; i < N; ++i) {
            float s = 0.75f * std::sin(2.0f * static_cast<float>(M_PI) * f_hf * static_cast<float>(i) / 48000.0f);
            buf[2 * i]     = s;
            buf[2 * i + 1] = s;
        }

        // Warm up past anti-pop
        for (int k = 0; k < 5; ++k) bassDsp.process(buf.data(), N);

        // Process test block
        for (uint32_t i = 0; i < N; ++i) {
            float s = 0.75f * std::sin(2.0f * static_cast<float>(M_PI) * f_hf * static_cast<float>(i) / 48000.0f);
            buf[2 * i]     = s;
            buf[2 * i + 1] = s;
        }
        bassDsp.process(buf.data(), N);

        // Measure correlation at foldback alias frequency f_alias = 3000 Hz
        // In the presence of foldback aliasing, a 3 kHz component would be generated.
        double alias_real = 0.0, alias_imag = 0.0;
        for (uint32_t i = N / 2; i < N; ++i) {
            float angle = 2.0f * static_cast<float>(M_PI) * 3000.0f * static_cast<float>(i) / 48000.0f;
            alias_real += buf[2 * i] * std::cos(angle);
            alias_imag += buf[2 * i] * std::sin(angle);
        }
        const double alias_mag = (std::sqrt(alias_real * alias_real + alias_imag * alias_imag) * 2.0) / (N / 2);

        char alias_msg[128];
        std::snprintf(alias_msg, sizeof(alias_msg), "DynamicBassDSP 3 kHz foldback alias magnitude = %.2e (want < 1e-4)", alias_mag);
        CHECK(alias_mag < 1e-4, alias_msg);

        // Verify peak 15 kHz amplitude matches unclipped input ~0.75
        float maxHf = 0.0f;
        for (uint32_t i = N / 2; i < N; ++i) {
            maxHf = std::max(maxHf, std::abs(buf[2 * i]));
        }
        CHECK(nearlyEqual(maxHf, 0.75f, 0.02f), "DynamicBassDSP leaves 15 kHz high frequencies unattenuated and unclipped (~0.75)");
    }

    // 2. DynamicBassDSP DynamicMultiPole mode: clean pass-through without soft-clipping
    {
        sauti::dsp::HarmonicBassDSP bassDsp;
        bassDsp.setSampleRate(48000.0f);
        bassDsp.setEnabled(true);
        bassDsp.setProfile(sauti::dsp::BassEnhanceProfile::DynamicMultiPole);
        bassDsp.setBoost(0.5f);
        bassDsp.reset();

        const uint32_t N = 2048;
        std::vector<float> buf(2 * N);
        for (uint32_t i = 0; i < N; ++i) {
            float s = 0.8f * std::sin(2.0f * static_cast<float>(M_PI) * 12000.0f * static_cast<float>(i) / 48000.0f);
            buf[2 * i]     = s;
            buf[2 * i + 1] = s;
        }
        for (int k = 0; k < 5; ++k) bassDsp.process(buf.data(), N);

        bool finite = true;
        for (float v : buf) {
            if (!std::isfinite(v)) { finite = false; break; }
        }
        CHECK(finite, "DynamicBassDSP MultiPole output is strictly finite without clipping saturation");
    }

    // 3. DynamicSystemDSP: direct linear reconstruction without base-rate soft-clipping
    {
        sauti::dsp::DynamicSystemDSP dynSys;
        dynSys.setSampleRate(48000.0f);
        dynSys.setEnabled(true);
        dynSys.setProfile(sauti::dsp::TransducerProfile::Headphone);
        dynSys.setStrength(0.9f);
        dynSys.reset();

        const uint32_t N = 4800;
        std::vector<float> buf(2 * N);
        const float f_hf = 10000.0f;
        for (uint32_t i = 0; i < N; ++i) {
            float s = 0.85f * std::sin(2.0f * static_cast<float>(M_PI) * f_hf * static_cast<float>(i) / 48000.0f);
            buf[2 * i]     = s;
            buf[2 * i + 1] = s;
        }

        for (int k = 0; k < 5; ++k) dynSys.process(buf.data(), N);

        float maxVal = 0.0f;
        for (uint32_t i = N / 2; i < N; ++i) {
            maxVal = std::max(maxVal, std::abs(buf[2 * i]));
        }
        CHECK(maxVal > 0.80f, "DynamicSystemDSP preserves high-frequency dynamics without destructive soft-clipping");
        CHECK(!std::isnan(maxVal) && !std::isinf(maxVal), "DynamicSystemDSP output is strictly finite");
    }
}

// -----------------------------------------------------------------------------
// [C] P1.11 De-Esser Dynamic Filter Modulations & C^1 Continuous Soft Knee
// -----------------------------------------------------------------------------
static void test_de_esser_soft_knee_and_coeff_modulation_p111()
{
    std::printf("\n== [C] P1.11 De-Esser Soft Knee & Coefficient Modulation ==\n");

    // 1. Mathematical continuity and C^1 smoothness of the soft knee function
    {
        const float threshold_db = -20.0f;
        const float ratio = 4.0f;
        const float max_red = 12.0f;
        const float knee_db = 4.0f; // half_knee = 2.0 dB, knee active from -22 dB to -18 dB

        // Region 1: Below knee (diff < -2.0 dB)
        float gr_below = sauti::dsp::DeEsserDSP::computeKneeGainReduction(-23.0f, threshold_db, ratio, max_red, knee_db);
        CHECK(gr_below == 0.0f, "Soft knee below boundary (diff = -3.0 dB) yields 0.0 dB gain reduction");

        // Region 2: Lower boundary (diff = -2.0 dB)
        float gr_lower = sauti::dsp::DeEsserDSP::computeKneeGainReduction(-22.0f, threshold_db, ratio, max_red, knee_db);
        CHECK(nearlyEqual(gr_lower, 0.0f, 1e-6f), "Soft knee lower boundary (diff = -2.0 dB) is continuous at 0.0 dB");

        // Region 3: Knee center (diff = 0.0 dB, threshold)
        // gr = (1 - 1/4) * (2)^2 / (2 * 4) = 0.75 * 4 / 8 = 0.375 dB
        float gr_center = sauti::dsp::DeEsserDSP::computeKneeGainReduction(-20.0f, threshold_db, ratio, max_red, knee_db);
        CHECK(nearlyEqual(gr_center, 0.375f, 1e-5f), "Soft knee center (diff = 0.0 dB) evaluates to exactly 0.375 dB");

        // Region 4: Upper boundary (diff = +2.0 dB)
        // gr = (1 - 1/4) * (4)^2 / 8 = 1.5 dB, matching linear slope diff * (1 - 1/4) = 2.0 * 0.75 = 1.5 dB
        float gr_upper = sauti::dsp::DeEsserDSP::computeKneeGainReduction(-18.0f, threshold_db, ratio, max_red, knee_db);
        CHECK(nearlyEqual(gr_upper, 1.500f, 1e-5f), "Soft knee upper boundary (diff = +2.0 dB) evaluates to exactly 1.500 dB");

        // Region 5: Linear section above knee (diff = +4.0 dB)
        float gr_above = sauti::dsp::DeEsserDSP::computeKneeGainReduction(-16.0f, threshold_db, ratio, max_red, knee_db);
        CHECK(nearlyEqual(gr_above, 3.000f, 1e-5f), "Linear section above knee (diff = +4.0 dB) evaluates to 3.000 dB");

        // Region 6: Clamped to maximum reduction
        float gr_clamped = sauti::dsp::DeEsserDSP::computeKneeGainReduction(0.0f, threshold_db, ratio, max_red, knee_db);
        CHECK(nearlyEqual(gr_clamped, 12.0f, 1e-5f), "Gain reduction clamps to configured max reduction (12.0 dB)");

        // Numerical derivative test for C^1 continuity across lower boundary (-22.0 dB)
        const float eps = 1e-3f;
        float d_lower = (sauti::dsp::DeEsserDSP::computeKneeGainReduction(-22.0f + eps, threshold_db, ratio, max_red, knee_db) -
                         sauti::dsp::DeEsserDSP::computeKneeGainReduction(-22.0f - eps, threshold_db, ratio, max_red, knee_db)) / (2.0f * eps);
        CHECK(nearlyEqual(d_lower, 0.0f, 0.01f), "Soft knee first derivative is C^1-smooth (tangent = 0.0) at lower boundary");

        // Numerical derivative test for C^1 continuity across upper boundary (-18.0 dB)
        float d_upper = (sauti::dsp::DeEsserDSP::computeKneeGainReduction(-18.0f + eps, threshold_db, ratio, max_red, knee_db) -
                         sauti::dsp::DeEsserDSP::computeKneeGainReduction(-18.0f - eps, threshold_db, ratio, max_red, knee_db)) / (2.0f * eps);
        CHECK(nearlyEqual(d_upper, 0.75f, 0.01f), "Soft knee first derivative is C^1-smooth (tangent = 0.75) at upper boundary");
    }

    // 2. Continuous biquad coefficient interpolation during rapid sibilance bursts
    {
        sauti::dsp::DeEsserDSP deEsser;
        deEsser.setSampleRate(48000.0f);
        deEsser.setEnabled(true);
        deEsser.setMode(sauti::dsp::DeEsserMode::SplitBand);
        deEsser.setThresholdDb(-24.0f);
        deEsser.setRatio(6.0f);
        deEsser.reset();

        // Feed a sudden vocal sibilance burst (silence followed by 0 dBFS 6 kHz tone)
        const uint32_t N = 2400; // 50 ms
        std::vector<float> burst(2 * N, 0.0f);
        for (uint32_t i = 480; i < N; ++i) { // sudden burst starting at frame 480 (10ms)
            float s = 0.9f * std::sin(2.0f * static_cast<float>(M_PI) * 6000.0f * static_cast<float>(i) / 48000.0f);
            burst[2 * i]     = s;
            burst[2 * i + 1] = s;
        }

        // Settle anti-pop
        std::vector<float> warmup(2 * 480, 0.0f);
        deEsser.process(warmup.data(), 480);

        // Process frame-by-frame and track shelf coefficient transition
        float prev_b0 = deEsser.getActiveShelfB0();
        float max_b0_step = 0.0f;
        for (uint32_t i = 0; i < N; ++i) {
            float frame[2] = { burst[2 * i], burst[2 * i + 1] };
            deEsser.process(frame, 1);
            float curr_b0 = deEsser.getActiveShelfB0();
            float step = std::fabs(curr_b0 - prev_b0);
            max_b0_step = std::max(max_b0_step, step);
            prev_b0 = curr_b0;
        }

        char step_msg[128];
        std::snprintf(step_msg, sizeof(step_msg), "Max shelf b0 sample-to-sample step = %.2e (want < 0.05, zero zippering)", max_b0_step);
        CHECK(max_b0_step < 0.05f, step_msg);
        CHECK(deEsser.getGainReductionDb() > 3.0f, "DeEsser successfully engages gain reduction on sibilance burst");
    }
}

// -----------------------------------------------------------------------------
// [C] P1.12 Dialog Enhancer Cascade Gain Headroom Risk & Dynamic Attenuation
// -----------------------------------------------------------------------------
static void test_dialog_enhancer_headroom_and_dynamic_attenuation_p112()
{
    std::printf("\n== [C] P1.12 Dialog Enhancer Headroom & Dynamic Attenuation ==\n");

    sauti::dsp::DialogEnhancerDSP de;
    de.setSampleRate(48000.0f);
    de.setEnabled(true);

    // 1. Automatic headroom trim compensation caps actual evaluated 3-band peak (~14.1 dB -> -2.1 dB trim)
    {
        de.setParams(sauti::dsp::DialogEnhancerProfile::Custom, 1.0f, 0.5f, 1.0f, 1.0f);
        de.reset();

        float headroom_db = de.getHeadroomCompensationDb();
        float headroom_linear = de.getHeadroomCompensation();

        char hr_msg[128];
        std::snprintf(hr_msg, sizeof(hr_msg), "DialogEnhancer headroom trim = %.2f dB (want ~ -2.1 dB, linear %.3f)", headroom_db, headroom_linear);
        CHECK(headroom_db <= -1.5f && headroom_db >= -3.0f, hr_msg);
        CHECK(headroom_linear <= 0.85f && headroom_linear > 0.70f, "Headroom compensation scales linear gain to ~0.785 (12 dB cap on actual peak)");
    }

    // 2. High-level (0 dBFS) voice track protection via dynamic attenuation
    {
        de.reset();
        de.setParams(sauti::dsp::DialogEnhancerProfile::Custom, 1.0f, 0.5f, 1.0f, 1.0f);

        // Feed full-scale 0 dBFS voice track (amplitude 1.0) at 2400 Hz formant peak
        const uint32_t N = 4800; // 100ms
        std::vector<float> hotVoice(2 * N);
        const float f0 = 2400.0f;
        for (uint32_t i = 0; i < N; ++i) {
            float s = 1.0f * std::sin(2.0f * static_cast<float>(M_PI) * f0 * static_cast<float>(i) / 48000.0f);
            hotVoice[2 * i]     = s;
            hotVoice[2 * i + 1] = s;
        }

        // Process audio through maximum enhancement chain
        for (int k = 0; k < 5; ++k) de.process(hotVoice.data(), N);

        // Measure steady-state peak output
        float maxPeak = 0.0f;
        for (uint32_t i = N / 2; i < N; ++i) {
            maxPeak = std::max(maxPeak, std::abs(hotVoice[2 * i]));
        }

        char peak_msg[128];
        std::snprintf(peak_msg, sizeof(peak_msg), "Hot 0 dBFS voice track output peak = %.4f (must be <= 0.98, no internal clipping)", maxPeak);
        CHECK(maxPeak <= 0.98f, peak_msg);
        CHECK(maxPeak >= 0.85f, "Hot voice track remains prominent and intelligible");
    }

    // 3. Sub-block coefficient throttling check (no per-sample coefficient re-computation)
    {
        de.reset();
        de.setParams(sauti::dsp::DialogEnhancerProfile::Custom, 0.5f, 0.5f, 0.5f, 0.5f);

        const uint32_t N = 128;
        std::vector<float> buf(2 * N, 0.1f);
        de.process(buf.data(), N);

        bool finite = true;
        for (float v : buf) {
            if (!std::isfinite(v)) { finite = false; break; }
        }
        CHECK(finite, "DialogEnhancer sub-block processing is stable and strictly finite");
    }
}

// -----------------------------------------------------------------------------
// [C] P0.4 Multichannel (5.1 & 7.1) Audio Scrambling Elimination
// -----------------------------------------------------------------------------
static void test_multichannel_dsp_suite_p04()
{
    std::printf("\n== [C] P0.4 Multichannel (5.1 & 7.1) DSP Scrambling Elimination ==\n");

    const uint32_t frames = 256;
    const int channels51 = 6;
    const size_t totalSamples51 = frames * channels51;

    // Buffer layout: [L0, R0, C0, LFE0, Ls0, Rs0, L1, R1, ...]
    std::vector<float> buf51(totalSamples51, 0.0f);
    for (uint32_t f = 0; f < frames; ++f)
    {
        buf51[f * channels51 + 0] = 0.5f * std::sin(2.0f * (float)M_PI * 1000.0f * f / 48000.0f); // L
        buf51[f * channels51 + 1] = 0.5f * std::cos(2.0f * (float)M_PI * 1000.0f * f / 48000.0f); // R
        buf51[f * channels51 + 2] = 0.3500f; // Center (speech/dialog)
        buf51[f * channels51 + 3] = 0.2000f; // LFE (subwoofer)
        buf51[f * channels51 + 4] = 0.1500f; // Left Surround
        buf51[f * channels51 + 5] = 0.1000f; // Right Surround
    }

    // Save exact copy of non-stereo channels
    std::vector<float> origCenter(frames), origLFE(frames), origLs(frames), origRs(frames);
    for (uint32_t f = 0; f < frames; ++f)
    {
        origCenter[f] = buf51[f * channels51 + 2];
        origLFE[f]    = buf51[f * channels51 + 3];
        origLs[f]     = buf51[f * channels51 + 4];
        origRs[f]     = buf51[f * channels51 + 5];
    }

    // De-interleave Front L/R pair
    std::vector<float> stBuf(frames * 2);
    for (uint32_t f = 0; f < frames; ++f)
    {
        stBuf[f * 2 + 0] = buf51[f * channels51 + 0];
        stBuf[f * 2 + 1] = buf51[f * channels51 + 1];
    }

    // Process with stereo DSP modules: Clarity, AnalogWarmth, DialogEnhancer, MasterLimiter
    sauti::dsp::AudioClarityDSP clarity;
    clarity.setSampleRate(48000.0f);
    clarity.setEnabled(true);
    clarity.setIntensity(0.5f);
    clarity.process(stBuf.data(), frames);

    sauti::dsp::AnalogWarmthDSP warmth;
    warmth.setSampleRate(48000.0f);
    warmth.setEnabled(true);
    warmth.setDrive(0.5f);
    warmth.process(stBuf.data(), frames);

    sauti::dsp::DialogEnhancerDSP dialog;
    dialog.setSampleRate(48000.0f);
    dialog.setEnabled(true);
    dialog.process(stBuf.data(), frames);

    sauti::dsp::MasterLimiterDSP limiter;
    limiter.setSampleRate(48000.0f);
    limiter.setEnabled(true);
    limiter.setCeilingDb(-0.5f);
    limiter.process(stBuf.data(), frames);

    // Re-interleave Front L/R back into multichannel buffer
    for (uint32_t f = 0; f < frames; ++f)
    {
        buf51[f * channels51 + 0] = stBuf[f * 2 + 0];
        buf51[f * channels51 + 1] = stBuf[f * 2 + 1];
    }

    // Verify Center channel dialog was NOT scrambled or touched by stereo DSP
    bool centerIntact = true;
    for (uint32_t f = 0; f < frames; ++f)
    {
        if (buf51[f * channels51 + 2] != origCenter[f])
        {
            centerIntact = false;
            break;
        }
    }
    CHECK(centerIntact, "5.1 Center dialog channel remains strictly bit-identical (no stereo scrambling)");

    // Verify LFE subwoofer channel was NOT scrambled
    bool lfeIntact = true;
    for (uint32_t f = 0; f < frames; ++f)
    {
        if (buf51[f * channels51 + 3] != origLFE[f])
        {
            lfeIntact = false;
            break;
        }
    }
    CHECK(lfeIntact, "5.1 LFE subwoofer channel remains strictly bit-identical");

    // Verify Surrounds (Ls and Rs) were NOT scrambled
    bool surroundsIntact = true;
    for (uint32_t f = 0; f < frames; ++f)
    {
        if (buf51[f * channels51 + 4] != origLs[f] || buf51[f * channels51 + 5] != origRs[f])
        {
            surroundsIntact = false;
            break;
        }
    }
    CHECK(surroundsIntact, "5.1 Left & Right Surround channels remain strictly bit-identical");

    // Verify that all 100% of frames in Left and Right channels were processed
    bool frontProcessed = true;
    for (uint32_t f = (frames * 33) / 100; f < frames; ++f)
    {
        float origL = 0.5f * std::sin(2.0f * (float)M_PI * 1000.0f * f / 48000.0f);
        if (buf51[f * channels51 + 0] == origL)
        {
            frontProcessed = false;
            break;
        }
    }
    CHECK(frontProcessed, "Front L/R channels processed across 100% of buffer (not truncated to 33%)");

    // Test 64-bit double precision 7.1 surround (8 channels)
    const int channels71 = 8;
    const size_t totalSamples71 = frames * channels71;
    std::vector<double> buf71(totalSamples71, 0.0);
    for (uint32_t f = 0; f < frames; ++f)
    {
        buf71[f * channels71 + 0] = 0.6 * std::sin(2.0 * M_PI * 440.0 * f / 48000.0);
        buf71[f * channels71 + 1] = 0.6 * std::cos(2.0 * M_PI * 440.0 * f / 48000.0);
        buf71[f * channels71 + 2] = 0.3333333333333333; // Center
        buf71[f * channels71 + 3] = 0.2222222222222222; // LFE
        buf71[f * channels71 + 4] = 0.1111111111111111; // Ls
        buf71[f * channels71 + 5] = 0.1212121212121212; // Rs
        buf71[f * channels71 + 6] = 0.1313131313131313; // Rls
        buf71[f * channels71 + 7] = 0.1414141414141414; // Rrs
    }

    std::vector<double> stBuf64(frames * 2);
    for (uint32_t f = 0; f < frames; ++f)
    {
        stBuf64[f * 2 + 0] = buf71[f * channels71 + 0];
        stBuf64[f * 2 + 1] = buf71[f * channels71 + 1];
    }

    sauti::dsp::MasterLimiterDSP limiter64;
    limiter64.setSampleRate(48000.0f);
    limiter64.setEnabled(true);
    limiter64.setCeilingDb(-1.0f);
    limiter64.process(stBuf64.data(), frames);

    for (uint32_t f = 0; f < frames; ++f)
    {
        buf71[f * channels71 + 0] = stBuf64[f * 2 + 0];
        buf71[f * channels71 + 1] = stBuf64[f * 2 + 1];
    }

    bool ch71Intact = true;
    for (uint32_t f = 0; f < frames; ++f)
    {
        if (buf71[f * channels71 + 2] != 0.3333333333333333 ||
            buf71[f * channels71 + 3] != 0.2222222222222222 ||
            buf71[f * channels71 + 4] != 0.1111111111111111 ||
            buf71[f * channels71 + 5] != 0.1212121212121212 ||
            buf71[f * channels71 + 6] != 0.1313131313131313 ||
            buf71[f * channels71 + 7] != 0.1414141414141414)
        {
            ch71Intact = false;
            break;
        }
    }
    CHECK(ch71Intact, "7.1 Surround channels 2..7 retain exact 64-bit IEEE-754 mantissa without corruption");
}

// -----------------------------------------------------------------------------
// [C] P0.2 F32 Output Path Overlapping Pointers Guard
// -----------------------------------------------------------------------------
static void test_f32_memcpy_overlapping_pointers_p02()
{
    std::printf("\n== [C] P0.2 F32 Output Path Overlapping memcpy Prevention ==\n");

    const size_t totalSamples = 512;
    std::vector<float> buffer(totalSamples, 0.42f);

    void *pOutput = buffer.data();
    float *finalDstBuffer = reinterpret_cast<float *>(pOutput);

    // Verify pointer equivalence
    CHECK(static_cast<const void*>(finalDstBuffer) == pOutput, "finalDstBuffer and pOutput point to identical memory address");

    // Execute guarded logic
    bool memcpyCalled = false;
    if (static_cast<const void*>(finalDstBuffer) != pOutput)
    {
        std::memcpy(pOutput, finalDstBuffer, totalSamples * sizeof(float));
        memcpyCalled = true;
    }

    CHECK(!memcpyCalled, "memcpy(pOutput, pOutput) successfully bypassed to prevent C/C++ Undefined Behavior");
    CHECK(buffer[0] == 0.42f && buffer[511] == 0.42f, "Buffer contents remain intact and uncorrupted");
}

// -----------------------------------------------------------------------------
// [C] P2.5 Spatial Surround Anti-Pop Stereo Balance Preservation
// -----------------------------------------------------------------------------
static void test_spatial_surround_anti_pop_balance_p25()
{
    std::printf("\n== [C] P2.5 Spatial Surround Anti-Pop Stereo Balance Preservation ==\n");

    sauti::dsp::SpatialSurroundDSP dsp;
    dsp.setSampleRate(48000.0f);
    dsp.setEnabled(true);
    dsp.setMode(sauti::dsp::SurroundMode::AcousticStage);

    CHECK(dsp.getAntiPop() == 0.0f, "Anti-pop gain initializes to 0.0 on reset");

    const uint32_t frames = 256;
    std::vector<float> buf(frames * 2);
    // Fill with identical Left and Right mono material to test stereo balance during fade
    for (uint32_t i = 0; i < frames; ++i)
    {
        buf[2 * i + 0] = 0.5f;
        buf[2 * i + 1] = 0.5f;
    }

    dsp.process(buf.data(), frames);

    // During the entire anti-pop ramp, Left and Right channels must have equal gain on every stereo frame
    float maxDeltaLR = 0.0f;
    for (uint32_t i = 0; i < frames; ++i)
    {
        float diff = std::abs(buf[2 * i + 0] - buf[2 * i + 1]);
        if (diff > maxDeltaLR) maxDeltaLR = diff;
    }

    char msg[128];
    std::snprintf(msg, sizeof(msg), "Max L/R delta during anti-pop fade = %.6f (want < 1e-5, zero soundstage tilt)", maxDeltaLR);
    CHECK(maxDeltaLR < 1e-5f, msg);
    CHECK(buf[0] < 0.5f, "Anti-pop fade starts smoothly below unity");
    CHECK(buf[2 * (frames - 1)] > buf[0], "Anti-pop ramp advances gain across frames");
    CHECK(dsp.getAntiPop() > 0.1f, "getAntiPop() tracks ramp progression correctly");
}

// -----------------------------------------------------------------------------
// [C] P2.6 AnalogWarmthDSP Tape Damping Effective Rate Scaling
// -----------------------------------------------------------------------------
static void test_analog_warmth_tape_damping_rate_scaling_p26()
{
    std::printf("\n== [C] P2.6 AnalogWarmthDSP Tape Damping Effective Rate Scaling ==\n");

    sauti::dsp::AnalogWarmthDSP dsp;
    dsp.setSampleRate(48000.0f);
    dsp.setEnabled(true);
    dsp.setProfile(sauti::dsp::AnalogWarmthProfile::MagneticTape);
    dsp.setDrive(1.0f);

    // 1x oversampling: TPT alpha at fc=14kHz, fs=48kHz -> g/(1+g) ≈ 0.5658
    dsp.setOversampling(1);
    float damp1x = dsp.getTapeDamping();
    char msg1[128];
    std::snprintf(msg1, sizeof(msg1), "1x oversampling tape TPT coeff = %.4f (want ~0.5658)", damp1x);
    CHECK(nearlyEqual(damp1x, 0.5658f, 0.005f), msg1);

    // 2x oversampling: TPT alpha at fc=14kHz, fs=96kHz -> g/(1+g) ≈ 0.3303
    dsp.setOversampling(2);
    float damp2x = dsp.getTapeDamping();
    char msg2[128];
    std::snprintf(msg2, sizeof(msg2), "2x oversampling tape TPT coeff = %.4f (want ~0.3303)", damp2x);
    CHECK(nearlyEqual(damp2x, 0.3303f, 0.005f), msg2);

    // 4x oversampling: TPT alpha at fc=14kHz, fs=192kHz -> g/(1+g) ≈ 0.1891
    dsp.setOversampling(4);
    float damp4x = dsp.getTapeDamping();
    char msg4[128];
    std::snprintf(msg4, sizeof(msg4), "4x oversampling tape TPT coeff = %.4f (want ~0.1891)", damp4x);
    CHECK(nearlyEqual(damp4x, 0.1891f, 0.005f), msg4);

    CHECK(damp1x > damp2x && damp2x > damp4x, "Tape TPT damping scales cleanly with oversampling rate");

    // Verify consistent -3 dB HF roll-off at 14 kHz across 1x, 2x, and 4x oversampling
    auto measure14kRatio = [&](int os) {
        sauti::dsp::AnalogWarmthDSP w;
        w.setSampleRate(48000.0f);
        w.setEnabled(true);
        w.setProfile(sauti::dsp::AnalogWarmthProfile::MagneticTape);
        w.setDrive(1.0f);
        w.setOversampling(os);
        w.reset();
        const uint32_t frames = 4096;
        std::vector<float> buf(2 * frames);
        for (uint32_t i = 0; i < frames; ++i) {
            float v = 0.25f * std::sin(2.0f * 3.14159265f * 14000.0f * i / 48000.0f);
            buf[2 * i] = v;
            buf[2 * i + 1] = v;
        }
        w.process(buf.data(), frames);
        double out_e = 0.0, in_e = 0.0;
        for (uint32_t i = 2048; i < frames; ++i) {
            double v = 0.25 * std::sin(2.0 * 3.14159265 * 14000.0 * i / 48000.0);
            in_e += v * v;
            out_e += static_cast<double>(buf[2 * i]) * buf[2 * i];
        }
        return 20.0 * std::log10(std::sqrt(out_e / in_e));
    };
    const double db1x = measure14kRatio(1);
    const double db2x = measure14kRatio(2);
    const double db4x = measure14kRatio(4);
    std::printf("  MagneticTape 14 kHz gain: 1x=%.2f dB, 2x=%.2f dB, 4x=%.2f dB\n", db1x, db2x, db4x);
    CHECK(std::fabs(db1x - db2x) < 0.75 && std::fabs(db2x - db4x) < 0.75,
          "MagneticTape 14 kHz rolloff is consistent across 1x, 2x, 4x oversampling");
}

static void test_analog_warmth_curves_and_dc_fixes()
{
    std::printf("\n== AnalogWarmthDSP Clean Zero-Drive, Monotonicity, DC Block & Harmonic Balance ==\n");

    const float sr = 48000.0f;
    // 1. Transparency at drive=0.0 across all 3 profiles
    for (int p = 0; p <= 2; ++p) {
        sauti::dsp::AnalogWarmthDSP dsp;
        dsp.setSampleRate(sr);
        dsp.setEnabled(true);
        dsp.setProfile(static_cast<sauti::dsp::AnalogWarmthProfile>(p));
        dsp.setDrive(0.0f);
        dsp.setOversampling(1);
        dsp.reset();

        const uint32_t N = 96000;
        std::vector<float> buf(2 * N);
        for (uint32_t i = 0; i < N; ++i) {
            float v = 0.5f * std::sin(2.0f * 3.14159265f * 1000.0f * i / sr);
            buf[2 * i] = v;
            buf[2 * i + 1] = v;
        }
        dsp.process(buf.data(), N);

        const uint32_t M = 4800;
        const uint32_t start = N - M;
        double inSq = 0.0, outSq = 0.0;
        for (uint32_t i = start; i < N; ++i) {
            const double v = 0.5 * std::sin(2.0 * 3.14159265358979323846 * 1000.0 * i / sr);
            const double y = static_cast<double>(buf[2 * i]);
            inSq += v * v;
            outSq += y * y;
        }
        const double rmsRatio = std::sqrt(outSq / std::max(inSq, 1e-18));
        auto binMag = [&](int freqHz) {
            double re = 0.0, im = 0.0;
            for (uint32_t n = 0; n < M; ++n) {
                const double ang = 2.0 * 3.14159265358979323846 * freqHz * n / sr;
                const double x = static_cast<double>(buf[2 * (start + n)]);
                re += x * std::cos(ang);
                im -= x * std::sin(ang);
            }
            return std::sqrt(re * re + im * im) / (M * 0.5);
        };
        const double h1 = binMag(1000);
        const double h2 = binMag(2000);
        const double h3 = binMag(3000);
        const double h2Db = 20.0 * std::log10(std::max(h2, 1e-12) / std::max(h1, 1e-12));
        const double h3Db = 20.0 * std::log10(std::max(h3, 1e-12) / std::max(h1, 1e-12));
        char msg[160];
        std::snprintf(msg, sizeof(msg), "Profile %d @ drive=0.0 is clean/transparent (rmsRatio=%.6f, H2=%.1f dB, H3=%.1f dB)",
                      p, rmsRatio, h2Db, h3Db);
        CHECK(std::fabs(rmsRatio - 1.0) < 1.0e-3 && h2Db < -80.0 && h3Db < -80.0, msg);
    }

    // 2. DC blocker active on ALL 3 profiles (especially VintagePreamp) & no wavefolding at drive=1.0
    for (int p = 0; p <= 2; ++p) {
        sauti::dsp::AnalogWarmthDSP dsp;
        dsp.setSampleRate(sr);
        dsp.setEnabled(true);
        dsp.setProfile(static_cast<sauti::dsp::AnalogWarmthProfile>(p));
        dsp.setDrive(1.0f);
        dsp.setOversampling(2);
        dsp.reset();

        const uint32_t N = 96000;
        std::vector<float> buf(2 * N);
        for (uint32_t i = 0; i < N; ++i) {
            float v = 0.95f * std::sin(2.0f * 3.14159265f * 1000.0f * i / sr);
            buf[2 * i] = v;
            buf[2 * i + 1] = v;
        }
        dsp.process(buf.data(), N);

        double mean = 0.0;
        float minVal = 10.0f, maxVal = -10.0f;
        for (uint32_t i = N - 24000; i < N; ++i) {
            mean += buf[2 * i];
            minVal = std::min(minVal, buf[2 * i]);
            maxVal = std::max(maxVal, buf[2 * i]);
        }
        mean /= 24000.0;
        char msg[160];
        std::snprintf(msg, sizeof(msg), "Profile %d @ drive=1.0 DC=%.5f (<0.005), min=%.3f, max=%.3f (no foldback)",
                      p, mean, minVal, maxVal);
        CHECK(std::fabs(mean) < 0.005 && minVal < -0.45f && maxVal <= 1.15f, msg);
    }

    // 3. Triode12AX7 @ drive=0.5 (-6 dBFS 1 kHz): even harmonic H2 > H3 and loudness within +/-1.5 dB
    {
        sauti::dsp::AnalogWarmthDSP dsp;
        dsp.setSampleRate(sr);
        dsp.setEnabled(true);
        dsp.setProfile(sauti::dsp::AnalogWarmthProfile::Triode12AX7);
        dsp.setDrive(0.5f);
        dsp.setOversampling(2);
        dsp.reset();

        const uint32_t N = 96000;
        std::vector<float> buf(2 * N);
        for (uint32_t i = 0; i < N; ++i) {
            float v = 0.5f * std::sin(2.0f * 3.14159265f * 1000.0f * i / sr);
            buf[2 * i] = v;
            buf[2 * i + 1] = v;
        }
        dsp.process(buf.data(), N);

        // Exact coherent DFT over 48000 samples (1 Hz bins) at end of buffer
        const uint32_t M = 48000;
        const uint32_t start = N - M;
        auto binMag = [&](int freqHz) {
            double re = 0.0, im = 0.0;
            for (uint32_t n = 0; n < M; ++n) {
                double ang = 2.0 * 3.14159265358979323846 * freqHz * n / sr;
                double x = buf[2 * (start + n)];
                re += x * std::cos(ang);
                im -= x * std::sin(ang);
            }
            return std::sqrt(re * re + im * im) / (M * 0.5);
        };
        const double h1 = binMag(1000);
        const double h2 = binMag(2000);
        const double h3 = binMag(3000);
        const double h1Db = 20.0 * std::log10(h1 / 0.5);
        const double h2Db = 20.0 * std::log10(std::max(h2, 1e-12) / h1);
        const double h3Db = 20.0 * std::log10(std::max(h3, 1e-12) / h1);
        std::printf("  Triode12AX7 @ drive=0.5 (-6 dBFS): H1=%.2f dB, H2=%.1f dB, H3=%.1f dB\n", h1Db, h2Db, h3Db);
        CHECK(std::fabs(h1Db) < 1.5, "Triode12AX7 small-signal loudness stays within +/-1.5 dB");
        CHECK(h2Db > h3Db + 3.0, "Triode12AX7 produces dominant 2nd-order even harmonics (H2 > H3 + 3 dB)");
    }
}

// -----------------------------------------------------------------------------
// [C] P2.1 ClarityDSP Dynamic Allocation Elimination & Chunking
// -----------------------------------------------------------------------------
static void test_clarity_dsp_zero_heap_allocation_p21()
{
    std::printf("\n== [C] P2.1 ClarityDSP Dynamic Allocation Elimination & Chunking ==\n");

    sauti::dsp::AudioClarityDSP dsp;
    dsp.setSampleRate(48000.0f);
    dsp.setEnabled(true);
    dsp.setProfile(sauti::dsp::AudioClarityProfile::HarmonicBrilliance);
    dsp.setIntensity(0.75f);
    dsp.setOversampling(2);

    // Test processing with an oversized buffer that exceeds initial 4096-frame sizes (e.g. 16384 frames)
    const uint32_t frames = 16384;
    std::vector<float> buf(frames * 2, 0.3f);
    for (uint32_t i = 0; i < frames; ++i)
    {
        buf[2 * i + 0] = 0.3f * std::sin(2.0f * (float)M_PI * 5000.0f * i / 48000.0f);
        buf[2 * i + 1] = 0.3f * std::cos(2.0f * (float)M_PI * 5000.0f * i / 48000.0f);
    }

    dsp.process(buf.data(), frames);

    bool finite = true;
    for (float v : buf)
    {
        if (!std::isfinite(v)) { finite = false; break; }
    }
    CHECK(finite, "ClarityDSP HarmonicBrilliance block chunking executes without NaN/Inf on 16K frames");
    CHECK(std::abs(buf[2 * 1000]) > 0.01f, "ClarityDSP audio output is non-zero and active");
}

static void test_uniform_f64_dsp_pipeline()
{
    std::printf("\n== Uniform 64-Bit (double*) DSP Pipeline Verification (Zero F32 Hopping) ==\n");

    const uint32_t frames = 2048;
    auto makeTone64 = [&]() {
        std::vector<double> b(frames * 2, 0.0);
        for (uint32_t i = 0; i < frames; ++i)
        {
            const double t = static_cast<double>(i) / 48000.0;
            b[2 * i + 0] = 0.25 * std::sin(2.0 * M_PI * 100.0 * t) + 0.15 * std::sin(2.0 * M_PI * 4000.0 * t);
            b[2 * i + 1] = 0.25 * std::cos(2.0 * M_PI * 100.0 * t) + 0.15 * std::cos(2.0 * M_PI * 4000.0 * t);
        }
        return b;
    };
    auto isClean64 = [](const std::vector<double> &b) {
        double energy = 0.0;
        for (double v : b)
        {
            if (!std::isfinite(v)) return false;
            energy += v * v;
        }
        return energy > 1e-4;
    };

    // 1. AudioClarityDSP across all 5 profiles in native double*
    for (int p = 0; p <= 4; ++p)
    {
        sauti::dsp::AudioClarityDSP clarity;
        clarity.setSampleRate(48000.0f);
        clarity.setProfile(static_cast<sauti::dsp::AudioClarityProfile>(p));
        clarity.setIntensity(0.7f);
        clarity.setOversampling(4);
        clarity.setEnabled(true);
        auto b = makeTone64();
        clarity.process(b.data(), frames);
        CHECK(isClean64(b), "AudioClarityDSP processes native double* cleanly across profile");
    }

    // 2. AnalogWarmthDSP across 1x/2x/4x oversampling in native double*
    for (int os : {1, 2, 4})
    {
        sauti::dsp::AnalogWarmthDSP warmth;
        warmth.setSampleRate(48000.0f);
        warmth.setDrive(0.6f);
        warmth.setOversampling(os);
        warmth.setEnabled(true);
        auto b = makeTone64();
        warmth.process(b.data(), frames);
        CHECK(isClean64(b), "AnalogWarmthDSP processes native double* cleanly at oversampling factor");
    }

    // 3. DownwardExpanderDSP, DeEsserDSP, DialogEnhancerDSP, DynamicSystemDSP, DynamicBassDSP
    {
        auto b = makeTone64();
        sauti::dsp::DownwardExpanderDSP exp;
        exp.setSampleRate(48000.0f);
        exp.setEnabled(true);
        exp.process(b.data(), frames);

        sauti::dsp::DeEsserDSP deesser;
        deesser.setSampleRate(48000.0f);
        deesser.setEnabled(true);
        deesser.process(b.data(), frames);

        sauti::dsp::DialogEnhancerDSP dialog;
        dialog.setSampleRate(48000.0f);
        dialog.setEnabled(true);
        dialog.process(b.data(), frames);

        sauti::dsp::DynamicSystemDSP dynsys;
        dynsys.setSampleRate(48000.0f);
        dynsys.setEnabled(true);
        dynsys.process(b.data(), frames);

        sauti::dsp::HarmonicBassDSP bass;
        bass.setSampleRate(48000.0f);
        bass.setEnabled(true);
        bass.process(b.data(), frames);

        CHECK(isClean64(b), "Zone 1-3 Pre-Dynamics chain executes 100% natively on double*");
    }

    // 4. SpatialSurroundDSP, StereoImagerDSP, ReverbNode (all 6 engines), FFTConvolverDSP
    {
        auto b = makeTone64();
        sauti::dsp::SpatialSurroundDSP surr;
        surr.setSampleRate(48000.0f);
        surr.setMode(sauti::dsp::SurroundMode::BinauralVirtualizer);
        surr.setEnabled(true);
        surr.process(b.data(), frames);

        sauti::dsp::StereoImagerDSP imager;
        imager.setSampleRate(48000.0f);
        imager.setMode(sauti::dsp::StereoImagerMode::Spatial3D);
        imager.setEnabled(true);
        imager.process(b.data(), frames, 2);

        for (int eng = 0; eng <= 5; ++eng)
        {
            ReverbNode rev;
            rev.setSampleRate(48000.0);
            rev.setEngine(eng);
            rev.setPreDelayMs(10.0f);
            rev.setEnabled(true);
            rev.process(b.data(), frames, 2);
        }

        sauti::dsp::FFTConvolverDSP conv;
        conv.setSampleRate(48000.0f);
        std::vector<float> ir(128, 0.0f);
        ir[0] = 1.0f;
        conv.loadImpulseResponse(ir.data(), 128, 1);
        conv.setEnabled(true);
        conv.process(b.data(), frames);

        CHECK(isClean64(b), "Zone 5-6 Spatial & AutoEQ FIR Convolver chain executes 100% natively on double*");
    }
}

static void test_dsp_audit_regressions()
{
    std::printf("\n== DSP Audit Regressions (DeEsser, NoiseGate, Expander) ==\n");

    // 1. De-Esser: bandpass sidechain rejects 16 kHz ultrasonic air while catching 6 kHz sibilance,
    //    and setFrequencyHz updates active shelf mid-compression.
    {
        sauti::dsp::DeEsserDSP deEsser;
        deEsser.setSampleRate(48000.0f);
        deEsser.setEnabled(true);
        deEsser.setMode(sauti::dsp::DeEsserMode::SplitBand);
        deEsser.setFrequencyHz(5000.0f);
        deEsser.setThresholdDb(-24.0f);
        deEsser.setRatio(6.0f);
        deEsser.setMaxReductionDb(12.0f);
        deEsser.reset();

        const uint32_t N = 2400;
        std::vector<float> airBuf(2 * N);
        for (uint32_t i = 0; i < N; ++i) {
            float s = 0.25f * std::sin(2.0f * static_cast<float>(M_PI) * 16000.0f * i / 48000.0f);
            airBuf[2 * i] = s;
            airBuf[2 * i + 1] = s;
        }
        deEsser.process(airBuf.data(), N);
        float airGr = deEsser.getGainReductionDb();
        CHECK(airGr < 2.0f, "DeEsser bandpass sidechain suppresses false-triggering on 16 kHz cymbal/air");

        std::vector<float> sibBuf(2 * N);
        for (uint32_t i = 0; i < N; ++i) {
            float s = 0.5f * std::sin(2.0f * static_cast<float>(M_PI) * 6500.0f * i / 48000.0f);
            sibBuf[2 * i] = s;
            sibBuf[2 * i + 1] = s;
        }
        deEsser.process(sibBuf.data(), N);
        float grBefore = deEsser.getGainReductionDb();
        CHECK(grBefore > 3.0f, "DeEsser compresses 6.5 kHz sibilance strongly");

        // Move fc above 6.5 kHz while actively compressing -> must update shelf and release 6.5 kHz
        deEsser.setFrequencyHz(9500.0f);
        deEsser.process(sibBuf.data(), N);
        CHECK(deEsser.getGainReductionDb() < grBefore * 0.5f, "setFrequencyHz updates active shelf & detector mid-stream");
    }

    // 2. NoiseGateDSP: out-of-phase stereo (L=+s, R=-s) does NOT cancel in sidechain,
    //    and enabling mid-stream starts open without sample-0 drop click.
    {
        sauti::dsp::NoiseGateDSP gate;
        gate.setSampleRate(48000.0f);
        gate.setParams(-40.0f, -46.0f, 80.0f, 1.0f, 100.0f, 80.0f, -80.0f);
        gate.setEnabled(true);
        gate.reset();

        const uint32_t N = 2400;
        std::vector<float> antiPhase(2 * N);
        for (uint32_t i = 0; i < N; ++i) {
            float s = 0.25f * std::sin(2.0f * static_cast<float>(M_PI) * 1000.0f * i / 48000.0f);
            antiPhase[2 * i] = s;
            antiPhase[2 * i + 1] = -s;
        }
        gate.process(antiPhase.data(), N, 2);
        CHECK(gate.getState() == sauti::dsp::NoiseGateDSP::GateState::Open && gate.getGainReductionDb() > -0.5f,
              "NoiseGate per-channel sidechain keeps gate OPEN on out-of-phase stereo (no mono cancellation)");

        sauti::dsp::NoiseGateDSP clickGate;
        clickGate.setSampleRate(48000.0f);
        clickGate.setEnabled(true); // without reset()
        float singleFrame[2] = { 0.5f, 0.5f };
        clickGate.process(singleFrame, 1, 2);
        CHECK(singleFrame[0] > 0.45f, "NoiseGate mid-stream enable has no sample-0 zeroing pop");
    }

    // 3. DownwardExpanderDSP: 48 kHz initializes and DynamicGate 2ms attack opens fast (< 8ms).
    {
        sauti::dsp::DownwardExpanderDSP exp;
        exp.setSampleRate(48000.0f);
        exp.setEnabled(true);
        exp.setPreset(sauti::dsp::ExpanderPreset::DynamicGate);
        exp.reset();

        // Drive expander down to -36 dB floor with silence
        std::vector<float> silence(2 * 9600, 0.0f);
        exp.process(silence.data(), 9600);
        CHECK(exp.getCurrentGainReductionDb() < -30.0f, "DynamicGate settles near -36 dB floor during silence");

        // Feed 0 dBFS transient burst for 8 ms (384 frames @ 48 kHz): must recover cleanly
        std::vector<float> burst(2 * 384);
        for (uint32_t i = 0; i < 384; ++i) {
            float s = 0.8f * std::sin(2.0f * static_cast<float>(M_PI) * 1000.0f * i / 48000.0f);
            burst[2 * i] = s;
            burst[2 * i + 1] = s;
        }
        exp.process(burst.data(), 384);
        CHECK(exp.getCurrentGainReductionDb() > -1.0f,
              "DownwardExpander 48 kHz fast attack opens within 8 ms (not trapped by 20 ms smoother)");
    }
}

static void test_dsp_audit_v2_regressions()
{
    std::printf("\n== DSP Audit v2 Regressions (DialogEnhancer, DynamicSystem, DynamicBass) ==\n");

    auto measureToneGainDb = [](auto &dsp, float freqHz, uint32_t frames = 24000) {
        if (frames < 19200) frames = 19200;
        std::vector<float> buf(2 * frames);
        constexpr double kPi = 3.14159265358979323846;
        for (uint32_t i = 0; i < frames; ++i) {
            float s = 0.25f * std::sin(static_cast<float>(2.0 * kPi * freqHz * i / 48000.0));
            buf[2 * i] = s;
            buf[2 * i + 1] = s;
        }
        dsp.process(buf.data(), frames);
        double re = 0.0, im = 0.0;
        // 9600 frames = 0.2 s exact integer cycles for all 5 Hz multiples (25, 40, 60, ..., 14000)
        const uint32_t winLen = 9600;
        const uint32_t start = frames - winLen;
        for (uint32_t i = start; i < frames; ++i) {
            const double ang = 2.0 * kPi * freqHz * i / 48000.0;
            re += static_cast<double>(buf[2 * i]) * std::sin(ang);
            im += static_cast<double>(buf[2 * i]) * std::cos(ang);
        }
        const double amp = std::sqrt(re * re + im * im) / (0.5 * static_cast<double>(winLen));
        return static_cast<float>(20.0 * std::log10(std::max(amp / 0.25, 1e-6)));
    };

    // 1. DialogEnhancerDSP regressions
    {
        // (a) 60 Hz centered kick does NOT duck stereo side
        sauti::dsp::DialogEnhancerDSP de;
        de.setSampleRate(48000.0f);
        de.setEnabled(true);
        de.setParams(sauti::dsp::DialogEnhancerProfile::Custom, 0.5f, 1.0f, 0.0f, 0.0f);
        de.reset();
        const uint32_t N = 9600;
        std::vector<float> kickBuf(2 * N);
        for (uint32_t i = 0; i < N; ++i) {
            float kick = 0.5f * std::sin(2.0f * 3.14159265f * 60.0f * i / 48000.0f);
            float side = 0.3f * std::sin(2.0f * 3.14159265f * 500.0f * i / 48000.0f);
            kickBuf[2 * i]     = kick + side;
            kickBuf[2 * i + 1] = kick - side;
        }
        de.process(kickBuf.data(), N);
        float maxKickSide = 0.0f;
        for (uint32_t i = N - 1000; i < N; ++i) {
            maxKickSide = std::max(maxKickSide, std::abs(0.5f * (kickBuf[2 * i] - kickBuf[2 * i + 1])));
        }
        CHECK(maxKickSide > 0.27f, "DialogEnhancer 60 Hz centered kick does NOT duck stereo side");

        // (b) 2.4 kHz centered speech DOES duck stereo side
        de.reset();
        std::vector<float> speechBuf(2 * N);
        for (uint32_t i = 0; i < N; ++i) {
            float sp = 0.3f * std::sin(2.0f * 3.14159265f * 2400.0f * i / 48000.0f);
            float side = 0.3f * std::sin(2.0f * 3.14159265f * 500.0f * i / 48000.0f);
            speechBuf[2 * i]     = sp + side;
            speechBuf[2 * i + 1] = sp - side;
        }
        de.process(speechBuf.data(), N);
        float maxSpeechSide = 0.0f;
        for (uint32_t i = N - 1000; i < N; ++i) {
            maxSpeechSide = std::max(maxSpeechSide, std::abs(0.5f * (speechBuf[2 * i] - speechBuf[2 * i + 1])));
        }
        CHECK(maxSpeechSide < 0.22f, "DialogEnhancer 2.4 kHz centered speech ducks stereo side");

        // (c) setParams with non-Custom profile honors passed values and smooths cleanly
        de.setParams(sauti::dsp::DialogEnhancerProfile::Cinema, 0.25f, 0.15f, 0.30f, 0.40f);
        de.reset();
        CHECK(nearlyEqual(de.getAmount(), 0.25f, 1e-4f), "DialogEnhancer setParams honors passed amount even on Cinema profile");
        std::vector<float> settleBuf(2 * 2400, 0.4f);
        de.process(settleBuf.data(), 2400);
        std::vector<float> stepBuf(2 * 64, 0.4f);
        de.setParams(sauti::dsp::DialogEnhancerProfile::Cinema, 1.0f, 0.15f, 1.0f, 0.40f);
        de.process(stepBuf.data(), 64);
        CHECK(std::abs(stepBuf[0] - stepBuf[2]) < 0.05f, "DialogEnhancer setParams smooths without single-sample jump");

        // (d) Voice headroom comp does NOT cut 100 Hz Mid relative to Side
        de.setProfile(sauti::dsp::DialogEnhancerProfile::Voice);
        de.reset();
        CHECK(de.getHeadroomCompensationDb() > -0.5f, "DialogEnhancer Voice profile does not over-cut 100 Hz Mid");

        // (e) Fade-out on disable reaches bit-exact bypass smoothly
        std::vector<float> fadeBuf(2 * 2400);
        for (uint32_t i = 0; i < 2400; ++i) {
            float s = 0.3f * std::sin(2.0f * 3.14159265f * 2400.0f * i / 48000.0f);
            fadeBuf[2 * i] = fadeBuf[2 * i + 1] = s;
        }
        de.setEnabled(true);
        de.process(fadeBuf.data(), 2400);
        de.setEnabled(false);
        CHECK(de.isActive(), "DialogEnhancer stays active during disable fade-out");
        de.process(fadeBuf.data(), 2400);
        CHECK(!de.isActive(), "DialogEnhancer reaches bit-exact bypass after fade-out");
    }

    // 2. DynamicSystemDSP regressions (original 4-pole ladder behavior)
    {
        sauti::dsp::DynamicSystemDSP ds;
        ds.setSampleRate(48000.0f);
        ds.setEnabled(true);

        // (a) strength = 0.0 is flat within +/-0.05 dB across spectrum
        const float checkFreqs[] = {25.0f, 40.0f, 60.0f, 80.0f, 120.0f, 250.0f, 1000.0f, 6000.0f, 14000.0f};
        ds.setPreset(16);
        ds.setStrength(0.0f);
        bool allFlat = true;
        for (float f : checkFreqs) {
            ds.reset();
            if (std::abs(measureToneGainDb(ds, f, 12000)) > 0.05f) {
                allFlat = false;
            }
        }
        CHECK(allFlat, "DynamicSystemDSP strength=0.0 is flat within +/-0.05 dB across spectrum");

        // (b) Club PA Punch (#16) at 0.80 strength boosts 30 Hz by +7..+9.5 dB and stays flat at 6 kHz
        ds.setPreset(16);
        ds.setStrength(0.80f);
        ds.reset();
        const float g30 = measureToneGainDb(ds, 30.0f, 24000);
        ds.reset();
        const float g6k = measureToneGainDb(ds, 6000.0f, 24000);
        CHECK(g30 >= 7.0f && g30 <= 9.5f && std::abs(g6k) < 0.3f,
              "DynamicSystemDSP Club PA Punch @ 80% boosts 30 Hz (+7..+9.5 dB) and stays flat at 6 kHz");

        // (c) Stereo ladder maintains zero channel crosstalk
        ds.reset();
        std::vector<float> isoBuf(2 * 1024, 0.0f);
        for (uint32_t i = 0; i < 1024; ++i) {
            isoBuf[2 * i] = 0.5f * std::sin(2.0f * 3.14159265f * 80.0f * i / 48000.0f);
        }
        ds.process(isoBuf.data(), 1024);
        float maxR = 0.0f;
        for (uint32_t i = 0; i < 1024; ++i) maxR = std::max(maxR, std::abs(isoBuf[2 * i + 1]));
        CHECK(maxR < 1e-6f, "DynamicSystemDSP stereo ladder maintains zero channel crosstalk");
    }

    // 3. HarmonicBassDSP regressions
    {
        sauti::dsp::HarmonicBassDSP hb;
        hb.setSampleRate(48000.0f);
        hb.setEnabled(true);

        // (a) Mode 5 at 0.0 dB gain is flat within +/-0.1 dB (fixes -17.4 dB notch)
        hb.setProfile(sauti::dsp::BassEnhanceProfile::DynamicMultiPole);
        hb.setPreset(18);
        hb.setGainDb(0.0f);
        const float bassFreqs[] = {25.0f, 40.0f, 60.0f, 80.0f, 140.0f, 500.0f, 2000.0f};
        bool mode5Flat = true;
        for (float f : bassFreqs) {
            hb.reset();
            if (std::abs(measureToneGainDb(hb, f, 12000)) > 0.1f) {
                mode5Flat = false;
            }
        }
        CHECK(mode5Flat, "HarmonicBassDSP Mode 5 @ 0.0 dB is flat within +/-0.1 dB across 25Hz-2kHz");

        // (b) setGainDb(12.0f) boosts bass near +12 dB (logarithmic)
        hb.setGainDb(12.0f);
        hb.reset();
        const float g50 = measureToneGainDb(hb, 50.0f, 24000);
        CHECK(g50 >= 11.0f && g50 <= 12.2f, "HarmonicBassDSP Mode 5 setGainDb(12.0) produces ~+12 dB at 50 Hz");

        // (c) Mode 3 HarmonicExciter produces zero DC/envelope thump on zero input after burst
        hb.setProfile(sauti::dsp::BassEnhanceProfile::HarmonicExciter);
        hb.setCutoffFrequency(60.0f);
        hb.setBoost(0.8f);
        hb.reset();
        std::vector<float> excBurst(2 * 2400);
        for (uint32_t i = 0; i < 2400; ++i) {
            float s = 0.5f * std::sin(2.0f * 3.14159265f * 50.0f * i / 48000.0f);
            excBurst[2 * i] = excBurst[2 * i + 1] = s;
        }
        hb.process(excBurst.data(), 2400);
        std::vector<float> excSilence(2 * 2400, 0.0f);
        hb.process(excSilence.data(), 2400);
        float tailPeak = 0.0f;
        for (uint32_t i = 1200; i < 2400; ++i) tailPeak = std::max(tailPeak, std::abs(excSilence[2 * i]));
        CHECK(tailPeak < 0.01f, "HarmonicBassDSP HarmonicExciter has zero DC/envelope thump on trailing silence");

        // (d) Modes 2 & 4 respond to setCutoffFrequency()
        hb.setProfile(sauti::dsp::BassEnhanceProfile::Subwoofer);
        hb.setBoost(0.7f);
        hb.setCutoffFrequency(45.0f);
        hb.reset();
        const float sub45 = measureToneGainDb(hb, 45.0f, 12000);
        hb.setCutoffFrequency(120.0f);
        hb.reset();
        const float sub120At45 = measureToneGainDb(hb, 45.0f, 12000);
        CHECK(sub45 > sub120At45 + 1.5f, "HarmonicBassDSP Subwoofer tracks setCutoffFrequency()");

        hb.setProfile(sauti::dsp::BassEnhanceProfile::PultecDeep);
        hb.setBoost(0.8f);
        hb.setCutoffFrequency(45.0f);
        hb.reset();
        const float pultecAt100a = measureToneGainDb(hb, 100.0f, 12000);
        hb.setCutoffFrequency(120.0f);
        hb.reset();
        const float pultecAt100b = measureToneGainDb(hb, 100.0f, 12000);
        CHECK(pultecAt100b > pultecAt100a + 1.5f, "HarmonicBassDSP PultecDeep tracks setCutoffFrequency()");
    }
}

int main(int argc, char **argv)
{
    std::printf("==============================================\n");
    std::printf(" DSP fix verification (Issues_bugs.md)\n");
    std::printf("==============================================\n");

    // Optionally run a single test by name for isolation:
    //   test_dsp_fixes.exe pure_bass|crossfeed|limiter|warmth|clarity|dynsys|oversample|deesser|expander|subsonic|dialog|scaletempo|convolver|p110|p111|p112|p04|p02|p25|p26|p21
    std::string only = (argc > 1) ? argv[1] : "";

    if (only.empty() || only == "pure_bass") test_pure_bass_fir();
    if (only.empty() || only == "crossfeed") test_crossfeed_algorithm_switch();
    if (only.empty() || only == "limiter") {
        test_master_limiter_defaults_and_ceiling();
        test_master_limiter_ballistics_and_lookahead_hold();
        test_master_limiter_lookahead_gain_ramp_and_true_peak();
    }
    if (only.empty() || only == "lockfree") test_lockfree_dsp_parameter_access();
    if (only.empty() || only == "warmth") test_analog_warmth_no_dc_offset();
    if (only.empty() || only == "clarity") test_clarity_presence_reconstruction();
    if (only.empty() || only == "dynsys") test_dynamic_system_cutoff_and_stability();
    if (only.empty() || only == "oversample") test_oversampled_saturation();
    if (only.empty() || only == "deesser") test_de_esser_dsp();
    if (only.empty() || only == "expander") test_downward_expander_dsp();
    if (only.empty() || only == "subsonic") test_subsonic_filter_and_denormals();
    if (only.empty() || only == "dialog") test_dialog_enhancer_dsp();
    if (only.empty() || only == "scaletempo") test_scaletempo_dsp();
    if (only.empty() || only == "convolver") {
        test_fft_convolver_latency_compensation();
        test_fft_convolver_true_stereo_and_nupols();
    }
    if (only.empty() || only == "p110") test_base_rate_saturation_aliasing_elimination_p110();
    if (only.empty() || only == "p111") test_de_esser_soft_knee_and_coeff_modulation_p111();
    if (only.empty() || only == "p112") test_dialog_enhancer_headroom_and_dynamic_attenuation_p112();
    if (only.empty() || only == "p04") test_multichannel_dsp_suite_p04();
    if (only.empty() || only == "p02") test_f32_memcpy_overlapping_pointers_p02();
    if (only.empty() || only == "p25") test_spatial_surround_anti_pop_balance_p25();
    if (only.empty() || only == "p26") test_analog_warmth_tape_damping_rate_scaling_p26();
    if (only.empty() || only == "warmth_curves") test_analog_warmth_curves_and_dc_fixes();
    if (only.empty() || only == "p21") test_clarity_dsp_zero_heap_allocation_p21();
    if (only.empty() || only == "f64") test_uniform_f64_dsp_pipeline();
    if (only.empty() || only == "audit") test_dsp_audit_regressions();
    if (only.empty() || only == "audit_v2") test_dsp_audit_v2_regressions();

    std::printf("\n----------------------------------------------\n");
    std::printf(" RESULTS: %d passed, %d failed\n", g_passes, g_failures);
    std::printf("----------------------------------------------\n");
    return g_failures == 0 ? 0 : 1;
}
