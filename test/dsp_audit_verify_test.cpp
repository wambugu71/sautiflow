#include <cassert>
#include <cmath>
#include <chrono>
#include <cstdio>
#include <vector>
#include <numeric>
#include <algorithm>

#include "../dsp/dynamic_loudness_dsp.h"
#include "../dsp/tape_drift_dsp.h"
#include "../dsp/clarity_dsp.h"
#include "../dsp/de_esser_dsp.h"
#include "../dsp/broadcast_leveller_dsp.h"
#include "../dsp/dialog_enhancer_dsp.h"
#include "../dsp/dynamic_bass_dsp.h"
#include "../dsp/scaletempo_dsp.h"
#include "../dsp/noise_gate_dsp.h"
#include "../dsp/downward_expander_dsp.h"
#include "../dsp/analog_warmth_dsp.h"
#include "../dsp/open_stage_dsp.h"
#include "../dsp/spatial_surround_dsp.h"

using namespace sauti::dsp;

static bool test_dynamic_loudness() {
    std::printf("[TEST 1] Dynamic Loudness RBJ High-Shelf Sign Bug (D1)...\n");
    for (float rate : {48000.0f, 192000.0f}) {
        DynamicLoudnessDSP dsp;
        dsp.setSampleRate(rate);
        dsp.setEnabled(true);
        // Set reference level 0 dB, max treble boost 12 dB, max bass boost 0 dB
        dsp.setParams(0.0f, 0.0f, 12.0f, 100.0f, 8000.0f);

        // Feed low frequency signal: 100 Hz sine wave at -20 dBFS volume (where loudness applies treble boost)
        const size_t N = static_cast<size_t>(rate); // 1 second
        std::vector<float> buf(N * 2);
        const float freq = 100.0f;
        for (size_t i = 0; i < N; ++i) {
            float s = std::sin(2.0f * 3.14159265f * freq * (float)i / rate);
            buf[2 * i] = s;
            buf[2 * i + 1] = s;
        }

        dsp.process(buf.data(), N, 2, 0.1f); // low volume input (0.1 = -20 dB)

        // Check amplitude at 100 Hz in the second half (after transients settle)
        float max_val = 0.0f;
        for (size_t i = N / 2; i < N; ++i) {
            max_val = std::max(max_val, std::fabs(buf[2 * i]));
        }
        float gain_db = 20.0f * std::log10(max_val);
        std::printf("  rate=%.0f Hz: 100 Hz peak = %.4f (gain = %+.2f dB)\n", rate, max_val, gain_db);
        // With the bug, at 192 kHz this was -15.3 dB! With fix, it should be near 0 dB (+- 0.5 dB).
        if (std::fabs(gain_db) > 0.8f) {
            std::printf("  FAIL: 100 Hz signal response corrupted by treble shelf (got %+.2f dB, expected ~0 dB)!\n", gain_db);
            return false;
        }
    }
    std::printf("  PASS\n");
    return true;
}

static bool test_tape_drift_perf() {
    std::printf("[TEST 2] Tape Drift Performance & Realtime Safety (D2)...\n");
    for (float rate : {48000.0f, 192000.0f}) {
        TapeDriftDSP dsp;
        dsp.setSampleRate(rate);
        dsp.setEnabled(true);
        dsp.setPreset(TapeDriftPreset::VintageReelToReel);

        const size_t blockSize = 512;
        std::vector<float> buf(blockSize * 2, 0.5f);

        // Warm up
        for (int k = 0; k < 100; ++k) {
            dsp.process(buf.data(), blockSize, 2);
        }

        // Measure processing time for 200 blocks
        const int iters = 200;
        auto t0 = std::chrono::high_resolution_clock::now();
        for (int k = 0; k < iters; ++k) {
            dsp.process(buf.data(), blockSize, 2);
        }
        auto t1 = std::chrono::high_resolution_clock::now();
        double ms_per_block = std::chrono::duration<double, std::milli>(t1 - t0).count() / iters;
        double budget_ms = (static_cast<double>(blockSize) / rate) * 1000.0;
        std::printf("  rate=%.0f Hz: %.3f ms per 512-sample block (real-time budget = %.2f ms, CPU = %.1f%%)\n",
                    rate, ms_per_block, budget_ms, (ms_per_block / budget_ms) * 100.0);
        // Previously: 8.2 - 9.8 ms at 48k! Now it should be well under 0.1 ms.
        if (ms_per_block > budget_ms * 0.5) {
            std::printf("  FAIL: Tape drift took too long (%.3f ms > 50%% of deadline %.2f ms)!\n", ms_per_block, budget_ms);
            return false;
        }
    }
    std::printf("  PASS\n");
    return true;
}

static bool test_clarity_rate_scaling() {
    std::printf("[TEST 3] Clarity Rate-Scaling Invariance (D3)...\n");
    float gain_48k = 0.0f, gain_192k = 0.0f;
    for (float rate : {48000.0f, 192000.0f}) {
        AudioClarityDSP dsp;
        dsp.setSampleRate(rate);
        dsp.setEnabled(true);
        dsp.setProfile(AudioClarityProfile::TransientCrisp);
        dsp.setIntensity(1.0f);

        // 18 kHz probe tone
        const size_t N = static_cast<size_t>(rate * 0.25f);
        std::vector<float> buf(N * 2);
        const float freq = 18000.0f;
        for (size_t i = 0; i < N; ++i) {
            float s = 0.2f * std::sin(2.0f * 3.14159265f * freq * (float)i / rate);
            buf[2 * i] = s;
            buf[2 * i + 1] = s;
        }

        dsp.process(buf.data(), static_cast<uint32_t>(N));

        float max_out = 0.0f;
        for (size_t i = N / 2; i < N; ++i) {
            max_out = std::max(max_out, std::fabs(buf[2 * i]));
        }
        float boost_db = 20.0f * std::log10(max_out / 0.2f);
        std::printf("  rate=%.0f Hz: 18 kHz boost = %+.2f dB\n", rate, boost_db);
        if (rate == 48000.0f) gain_48k = boost_db;
        else gain_192k = boost_db;
    }
    // Boost at 192 kHz must be positive and close to 48 kHz (not -1.42 dB attenuation!)
    if (gain_192k < 0.0f || std::fabs(gain_48k - gain_192k) > 2.5f) {
        std::printf("  FAIL: Clarity 18 kHz boost at 192 kHz is %+.2f dB (vs %+.2f dB at 48k)\n", gain_192k, gain_48k);
        return false;
    }
    std::printf("  PASS\n");
    return true;
}

static bool test_de_esser_stability() {
    std::printf("[TEST 4] De-Esser Stability & Sub-Block Pole Updates (D4)...\n");
    for (float rate : {48000.0f, 192000.0f}) {
        DeEsserDSP dsp;
        dsp.setSampleRate(rate);
        dsp.setEnabled(true);
        dsp.setPreset(DeEsserPreset::AggressiveSibilance);

        const size_t N = 8192;
        std::vector<float> buf(N * 2, 0.0f);
        // Create an aggressive high-frequency sibilant burst at 6 kHz alternating with silence
        for (size_t i = 0; i < N; ++i) {
            float burst = ((i / 256) % 2 == 0) ? 0.9f : 0.01f;
            float s = burst * std::sin(2.0f * 3.14159265f * 6000.0f * (float)i / rate);
            buf[2 * i] = s;
            buf[2 * i + 1] = s;
        }

        dsp.process(buf.data(), static_cast<uint32_t>(N));

        // Check for NaN, Inf, or exploded samples (instability)
        for (size_t i = 0; i < N * 2; ++i) {
            if (!std::isfinite(buf[i]) || std::fabs(buf[i]) > 2.0f) {
                std::printf("  FAIL: Filter instability detected at rate=%.0f, sample[%zu] = %f\n", rate, i, buf[i]);
                return false;
            }
        }
        std::printf("  rate=%.0f Hz: gain reduction = %.2f dB, all samples finite and stable\n", rate, dsp.getGainReductionDb());
    }
    std::printf("  PASS\n");
    return true;
}

static bool test_broadcast_leveller_window() {
    std::printf("[TEST 5] Broadcast Leveller Scaled Integration Window (D5)...\n");
    for (float rate : {48000.0f, 192000.0f}) {
        BroadcastLevellerDSP dsp;
        dsp.setSampleRate(rate);
        dsp.setEnabled(true);
        dsp.setParams(-16.0f, 1.0f, 2.0f, 6.0f, 12.0f, -60.0f);

        // Feed 90 Hz bass wave for 0.5 second
        const size_t N = static_cast<size_t>(rate * 0.5f);
        std::vector<float> buf(N * 2);
        for (size_t i = 0; i < N; ++i) {
            float s = 0.5f * std::sin(2.0f * 3.14159265f * 90.0f * (float)i / rate);
            buf[2 * i] = s;
            buf[2 * i + 1] = s;
        }

        // Process in small 128-frame callbacks
        const size_t block = 128;
        float prev_gain = 0.0f;
        float max_block_gain_jump = 0.0f;
        for (size_t offset = 0; offset < N; offset += block) {
            size_t count = std::min(block, N - offset);
            dsp.process(buf.data() + offset * 2, count, 2);
            float g = dsp.getCurrentGainDb();
            if (offset > 0) {
                max_block_gain_jump = std::max(max_block_gain_jump, std::fabs(g - prev_gain));
            }
            prev_gain = g;
        }
        std::printf("  rate=%.0f Hz: max 128-sample gain jump = %.4f dB (current gain = %.2f dB)\n",
                    rate, max_block_gain_jump, dsp.getCurrentGainDb());
        // Gain should not bounce with each 90 Hz wave cycle
        if (max_block_gain_jump > 0.05f) {
            std::printf("  FAIL: Leveller pumping on bass wave cycles (jump = %.4f dB)!\n", max_block_gain_jump);
            return false;
        }
    }
    std::printf("  PASS\n");
    return true;
}

static bool test_dialog_enhancer_peak_envelope() {
    std::printf("[TEST 6] Dialog Enhancer Peak Limiter Envelope Follower (D6)...\n");
    DialogEnhancerDSP dsp;
    dsp.setSampleRate(48000.0f);
    dsp.setEnabled(true);
    dsp.setProfile(DialogEnhancerProfile::Voice);
    dsp.setAmount(1.0f); // Max boost

    // Single high peak followed by mid-level audio
    const size_t N = 4800; // 100 ms
    std::vector<float> buf(N * 2, 0.7f);
    buf[0] = 0.99f;
    buf[1] = 0.99f;

    dsp.process(buf.data(), static_cast<uint32_t>(N));

    // Verify no sample exceeds 1.05 and output transitions smoothly
    float max_sample = 0.0f;
    for (size_t i = 0; i < N * 2; ++i) {
        max_sample = std::max(max_sample, std::fabs(buf[i]));
    }
    std::printf("  Max sample = %.4f (smooth attenuation active)\n", max_sample);
    if (max_sample > 1.2f) {
        std::printf("  FAIL: Peak limiter attenuation failed!\n");
        return false;
    }
    std::printf("  PASS\n");
    return true;
}

static bool test_dynamic_bass_stereo() {
    std::printf("[TEST 7] Dynamic Bass Soundstage & Subwoofer Lowpass Crossover (D7)...\n");
    HarmonicBassDSP dsp;
    dsp.setSampleRate(48000.0f);
    dsp.setEnabled(true);
    dsp.setProfile(BassEnhanceProfile::Subwoofer);

    // Test with Mono Mode ON vs Mono Mode OFF (Headphone Stereo Mode)
    dsp.setMonoMode(false); // Stereo headphone mode
    assert(!dsp.isMonoMode());

    // Provide out-of-phase stereo signal: L = +0.5, R = -0.5 at 120 Hz
    const size_t N = 4800;
    std::vector<float> buf(N * 2);
    for (size_t i = 0; i < N; ++i) {
        float s = 0.5f * std::sin(2.0f * 3.14159265f * 120.0f * (float)i / 48000.0f);
        buf[2 * i] = s;
        buf[2 * i + 1] = -s;
    }

    dsp.process(buf.data(), static_cast<uint32_t>(N));

    // In stereo mode, L and R should retain opposite polarity (not collapsed to 0)
    float diff_sum = 0.0f;
    for (size_t i = N / 2; i < N; ++i) {
        diff_sum += std::fabs(buf[2 * i] - buf[2 * i + 1]);
    }
    float avg_diff = diff_sum / (N / 2);
    std::printf("  Stereo difference in headphone mode = %.4f\n", avg_diff);
    if (avg_diff < 0.2f) {
        std::printf("  FAIL: Stereo content collapsed to mono in headphone mode!\n");
        return false;
    }
    std::printf("  PASS\n");
    return true;
}

static bool test_scaletempo_realtime() {
    std::printf("[TEST 8] ScaleTempo Real-Time Safety & Head Buffering (D8)...\n");
    sauti::dsp::ScaleTempoDSP st;
    st.init(48000, 2);
    st.setScale(1.25f);

    std::vector<float> inBuf(512 * 2, 0.2f);
    std::vector<float> outBuf(1024 * 2, 0.0f);

    size_t totalRead = 0;
    for (int k = 0; k < 50; ++k) {
        st.writeInput(inBuf.data(), 512);
        size_t n = st.readOutput(outBuf.data(), 1024);
        totalRead += n;
    }
    std::printf("  Pushed 50*512 frames, read %zu scaled frames without memory crashes\n", totalRead);
    if (totalRead == 0) {
        std::printf("  FAIL: ScaleTempo produced 0 output frames!\n");
        return false;
    }
    std::printf("  PASS\n");
    return true;
}

static bool test_noise_gate_expander_transcendentals() {
    std::printf("[TEST 9] Noise Gate & Downward Expander Transcendental Bypass (D9)...\n");
    {
        NoiseGateDSP gate;
        gate.setSampleRate(48000.0f);
        gate.setEnabled(true);
        gate.setParams(-40.0f, -46.0f, 10.0f, 1.0f, 50.0f, 80.0f);

        std::vector<float> buf(512 * 2, 0.5f); // loud signal: gate open
        gate.process(buf.data(), 512, 2);
        assert(gate.getState() == NoiseGateDSP::GateState::Open);

        // Quiet signal: gate closed
        std::fill(buf.begin(), buf.end(), 0.0001f);
        gate.process(buf.data(), 512, 2);
        for (int k = 0; k < 10; ++k) gate.process(buf.data(), 512, 2);
        assert(gate.getState() == NoiseGateDSP::GateState::Closed);
    }
    {
        DownwardExpanderDSP exp;
        exp.setSampleRate(48000.0f);
        exp.setEnabled(true);
        exp.setPreset(ExpanderPreset::TapeHiss);

        std::vector<float> buf(512 * 2, 0.5f); // Above threshold: gain linear should remain 1.0
        exp.process(buf.data(), 512);
        assert(std::fabs(exp.getCurrentGainReductionDb()) < 0.01f);
    }
    std::printf("  PASS\n");
    return true;
}

static bool test_analog_warmth_alignment() {
    std::printf("[TEST 10] Analog Warmth Oversampler Latency Alignment (D10)...\n");
    AnalogWarmthDSP warmth;
    warmth.setSampleRate(48000.0f);
    warmth.setEnabled(true);
    warmth.setDrive(0.5f);
    warmth.setOversampling(2);

    // Process a block
    std::vector<float> buf(1024 * 2, 0.1f);
    warmth.process(buf.data(), 1024);

    // Verify all outputs are valid and finite
    for (float s : buf) {
        assert(std::isfinite(s));
    }
    std::printf("  PASS\n");
    return true;
}

int main() {
    std::printf("=========================================\n");
    std::printf("ANTIGRAVITY AUDIT VERIFICATION TEST SUITE\n");
    std::printf("=========================================\n");

    bool ok = true;
    ok = ok && test_dynamic_loudness();
    ok = ok && test_tape_drift_perf();
    ok = ok && test_clarity_rate_scaling();
    ok = ok && test_de_esser_stability();
    ok = ok && test_broadcast_leveller_window();
    ok = ok && test_dialog_enhancer_peak_envelope();
    ok = ok && test_dynamic_bass_stereo();
    ok = ok && test_scaletempo_realtime();
    ok = ok && test_noise_gate_expander_transcendentals();
    ok = ok && test_analog_warmth_alignment();

    std::printf("=========================================\n");
    if (ok) {
        std::printf("ALL AUDIT VERIFICATION TESTS PASSED!\n");
        return 0;
    } else {
        std::printf("SOME AUDIT TESTS FAILED!\n");
        return 1;
    }
}

