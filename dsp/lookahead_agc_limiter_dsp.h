#pragma once

#include <algorithm>
#include <array>
#include <atomic>
#include <cmath>
#include <cstdint>
#include <vector>
#include "denormals.h"
#include "oversampler.h"
#include "simd_math.h"

namespace sauti::dsp {

// =============================================================================
// LookaheadAgcLimiterDSP: 3-Band Lookahead AGC + Bass-Safe Brickwall Limiter
//
// Solves the classic AGC distortion problem where slow-window AGC boosts quiet
// passages and then lets sudden bass hits / transients clip before gain falls:
// - Pre-delays audio through a phase-coherent 3-band LR4 crossover into a
//   configurable lookahead ring buffer (2.0 - 25.0 ms, default 10.0 ms).
// - Analyzes un-delayed ("future") audio ahead of time:
//   1. Lookahead AGC rides loudness smoothly toward target LUFS (with silence
//      gate freeze so background noise/hiss is never lifted).
//   2. Pre-emptive Headroom Guard detects upcoming peaks (especially heavy bass)
//      entering the lookahead window and smoothly ramps AGC boost back BEFORE
//      the note arrives at the output.
//   3. Per-Band Lookahead Limiters (Low / Mid / High) protect each band
//      independently with a dedicated slow bass release (60 - 400 ms) so low
//      notes never ripple inside a waveform cycle and never pump vocals/mids.
//   4. Final 4x oversampled True-Peak ceiling guard guarantees zero clipping.
// =============================================================================
class LookaheadAgcLimiterDSP {
public:
    static constexpr int kMaxChannels = 8;
    static constexpr float kMinLookaheadMs = 2.0f;
    static constexpr float kMaxLookaheadMs = 25.0f;

    LookaheadAgcLimiterDSP() {
        setSampleRate(48000.0f);
        reset();
    }

    void setSampleRate(float sampleRate) {
        if (sampleRate <= 0.0f) sampleRate = 48000.0f;
        if (std::abs(sample_rate_ - sampleRate) < 0.1f && initialized_) return;
        sample_rate_ = sampleRate;

        // Pre-allocate ring buffers for maximum lookahead + margin (zero RT allocs).
        max_delay_samples_ = static_cast<size_t>(std::ceil(sample_rate_ * (kMaxLookaheadMs * 0.001f))) + 8;
        max_delay_samples_ = std::max<size_t>(max_delay_samples_, 64);

        for (int b = 0; b < 3; ++b) {
            for (int c = 0; c < kMaxChannels; ++c) {
                delay_buf_[b][c].assign(max_delay_samples_, 0.0);
            }
            band_env_[b].allocate(max_delay_samples_ + 4);
        }
        for (int c = 0; c < kMaxChannels; ++c) {
            post_delay_buf_[c].assign(kStageBDelay + 4, 0.0);
        }
        agc_headroom_env_.allocate(max_delay_samples_ + 4);
        tp_safety_env_.allocate(kStageBDelay + 8);

        updateCrossoverCoeffs();
        updateTimingConstants(true);
        initialized_ = true;
    }

    float getSampleRate() const { return sample_rate_; }

    void setEnabled(bool enabled) {
        const bool wasEnabled = enabled_.exchange(enabled, std::memory_order_release);
        if (!enabled && wasEnabled) {
            reset();
        }
    }

    bool isEnabled() const { return enabled_.load(std::memory_order_relaxed); }

    void setParams(float target_lufs,
                   float max_boost_db,
                   float max_attenuation_db,
                   float agc_rise_db_sec,
                   float agc_fall_db_sec,
                   float silence_gate_lufs,
                   float lookahead_ms,
                   float ceiling_db,
                   float low_xover_hz,
                   float high_xover_hz,
                   float bass_release_ms) {
        float lx = std::clamp(low_xover_hz, 80.0f, 400.0f);
        float hx = std::clamp(high_xover_hz, 1500.0f, 6000.0f);
        if (lx >= hx - 200.0f) {
            lx = 180.0f;
            hx = 3000.0f;
        }

        target_lufs_.store(std::clamp(target_lufs, -30.0f, -6.0f), std::memory_order_release);
        max_boost_db_.store(std::clamp(max_boost_db, 0.0f, 18.0f), std::memory_order_release);
        max_attenuation_db_.store(std::clamp(max_attenuation_db, 0.0f, 24.0f), std::memory_order_release);
        agc_rise_db_sec_.store(std::clamp(agc_rise_db_sec, 0.2f, 8.0f), std::memory_order_release);
        agc_fall_db_sec_.store(std::clamp(agc_fall_db_sec, 0.5f, 24.0f), std::memory_order_release);
        silence_gate_lufs_.store(std::clamp(silence_gate_lufs, -70.0f, -24.0f), std::memory_order_release);
        lookahead_ms_.store(std::clamp(lookahead_ms, kMinLookaheadMs, kMaxLookaheadMs), std::memory_order_release);
        ceiling_db_.store(std::clamp(ceiling_db, -6.0f, -0.1f), std::memory_order_release);
        low_xover_hz_.store(lx, std::memory_order_release);
        high_xover_hz_.store(hx, std::memory_order_release);
        bass_release_ms_.store(std::clamp(bass_release_ms, 60.0f, 400.0f), std::memory_order_release);
        params_dirty_.store(true, std::memory_order_release);
    }

    void getParams(float* out_target_lufs,
                   float* out_max_boost_db,
                   float* out_max_attenuation_db,
                   float* out_agc_rise_db_sec,
                   float* out_agc_fall_db_sec,
                   float* out_silence_gate_lufs,
                   float* out_lookahead_ms,
                   float* out_ceiling_db,
                   float* out_low_xover_hz,
                   float* out_high_xover_hz,
                   float* out_bass_release_ms) const {
        if (out_target_lufs) *out_target_lufs = target_lufs_.load(std::memory_order_relaxed);
        if (out_max_boost_db) *out_max_boost_db = max_boost_db_.load(std::memory_order_relaxed);
        if (out_max_attenuation_db) *out_max_attenuation_db = max_attenuation_db_.load(std::memory_order_relaxed);
        if (out_agc_rise_db_sec) *out_agc_rise_db_sec = agc_rise_db_sec_.load(std::memory_order_relaxed);
        if (out_agc_fall_db_sec) *out_agc_fall_db_sec = agc_fall_db_sec_.load(std::memory_order_relaxed);
        if (out_silence_gate_lufs) *out_silence_gate_lufs = silence_gate_lufs_.load(std::memory_order_relaxed);
        if (out_lookahead_ms) *out_lookahead_ms = lookahead_ms_.load(std::memory_order_relaxed);
        if (out_ceiling_db) *out_ceiling_db = ceiling_db_.load(std::memory_order_relaxed);
        if (out_low_xover_hz) *out_low_xover_hz = low_xover_hz_.load(std::memory_order_relaxed);
        if (out_high_xover_hz) *out_high_xover_hz = high_xover_hz_.load(std::memory_order_relaxed);
        if (out_bass_release_ms) *out_bass_release_ms = bass_release_ms_.load(std::memory_order_relaxed);
    }

    void getTelemetry(float* out_agc_gain_db,
                      float* out_low_gr_db,
                      float* out_mid_gr_db,
                      float* out_high_gr_db,
                      float* out_peak_gr_db) const {
        if (out_agc_gain_db) *out_agc_gain_db = telemetry_agc_gain_db_.load(std::memory_order_relaxed);
        if (out_low_gr_db) *out_low_gr_db = telemetry_low_gr_db_.load(std::memory_order_relaxed);
        if (out_mid_gr_db) *out_mid_gr_db = telemetry_mid_gr_db_.load(std::memory_order_relaxed);
        if (out_high_gr_db) *out_high_gr_db = telemetry_high_gr_db_.load(std::memory_order_relaxed);
        if (out_peak_gr_db) *out_peak_gr_db = telemetry_peak_gr_db_.load(std::memory_order_relaxed);
    }

    size_t getLatencySamples() const { return lookahead_samples_; }

    void reset() {
        lp1_.reset();
        hp1_.reset();
        ap2_.reset();
        lp2_.reset();
        hp2_.reset();
        tp_filter1_.reset();
        tp_filter2_.reset();

        for (int b = 0; b < 3; ++b) {
            for (int c = 0; c < kMaxChannels; ++c) {
                std::fill(delay_buf_[b][c].begin(), delay_buf_[b][c].end(), 0.0);
            }
            band_env_[b].reset(1.0);
        }
        for (int c = 0; c < kMaxChannels; ++c) {
            std::fill(post_delay_buf_[c].begin(), post_delay_buf_[c].end(), 0.0);
        }
        agc_headroom_env_.reset(1.0);
        tp_safety_env_.reset(1.0);
        delay_pos_ = 0;
        post_delay_pos_ = 0;

        agc_gain_db_ = 0.0;
        agc_linear_ = 1.0;
        loudness_sum_sq_ = 0.0;
        loudness_sample_count_ = 0.0;
        future_short_term_lufs_ = -100.0;

        mid_peak_hold_ = 0.0;
        high_peak_hold_ = 0.0;
        final_safety_gain_ = 1.0;

        telemetry_agc_gain_db_.store(0.0f, std::memory_order_relaxed);
        telemetry_low_gr_db_.store(0.0f, std::memory_order_relaxed);
        telemetry_mid_gr_db_.store(0.0f, std::memory_order_relaxed);
        telemetry_high_gr_db_.store(0.0f, std::memory_order_relaxed);
        telemetry_peak_gr_db_.store(0.0f, std::memory_order_relaxed);
    }

    void process(float* buffer, size_t frame_count, int channels) {
        processImpl(buffer, frame_count, channels);
    }

    void process(double* buffer, size_t frame_count, int channels) {
        processImpl(buffer, frame_count, channels);
    }

private:
    struct BiquadCoeffs {
        double b0 = 1.0, b1 = 0.0, b2 = 0.0;
        double a1 = 0.0, a2 = 0.0;
    };

    struct BiquadState {
        double s1 = 0.0;
        double s2 = 0.0;
        void reset() { s1 = 0.0; s2 = 0.0; }
        inline double process(const BiquadCoeffs& c, double in) {
            const double out = in * c.b0 + s1;
            s1 = in * c.b1 - out * c.a1 + s2;
            s2 = in * c.b2 - out * c.a2;
            if (std::fabs(s1) < 1.0e-20) s1 = 0.0;
            if (std::fabs(s2) < 1.0e-20) s2 = 0.0;
            return out;
        }
    };

    struct LR4Stage {
        BiquadState stage1[kMaxChannels];
        BiquadState stage2[kMaxChannels];

        void reset() {
            for (int c = 0; c < kMaxChannels; ++c) {
                stage1[c].reset();
                stage2[c].reset();
            }
        }

        inline double process(const BiquadCoeffs& c, int ch, double in) {
            return stage2[ch].process(c, stage1[ch].process(c, in));
        }
    };

    struct AP2Stage {
        BiquadState stage[kMaxChannels];

        void reset() {
            for (int c = 0; c < kMaxChannels; ++c) {
                stage[c].reset();
            }
        }

        inline double process(const BiquadCoeffs& c, int ch, double in) {
            return stage[ch].process(c, in);
        }
    };

    // O(1) amortized sliding-window min-filter + 1-pole release + causal moving average.
    // Zero heap allocations in process().
    struct LookaheadEnvelope {
        std::vector<uint64_t> dq_idx;
        std::vector<double> dq_val;
        std::vector<double> ma_ring;
        size_t cap = 64;
        size_t win_len = 16;

        size_t dq_head = 0;
        size_t dq_tail = 0;
        size_t dq_size = 0;
        uint64_t sample_idx = 0;

        double rel_gain = 1.0;
        double rel_coeff = 0.001;
        size_t ma_pos = 0;
        double ma_sum = 16.0;
        uint32_t drift_counter = 0;

        void allocate(size_t max_cap) {
            cap = std::max<size_t>(max_cap, 32);
            dq_idx.assign(cap, 0);
            dq_val.assign(cap, 1.0);
            ma_ring.assign(cap, 1.0);
            reset(1.0);
        }

        void reset(double init_val = 1.0) {
            dq_head = 0;
            dq_tail = 0;
            dq_size = 0;
            sample_idx = 0;
            rel_gain = init_val;
            ma_pos = 0;
            std::fill(ma_ring.begin(), ma_ring.end(), init_val);
            ma_sum = init_val * static_cast<double>(win_len);
            drift_counter = 0;
        }

        void setParams(size_t new_win_len, double new_rel_coeff, bool hard_reset) {
            const size_t clamped_win = std::clamp<size_t>(new_win_len, 4, cap);
            rel_coeff = std::clamp(new_rel_coeff, 1.0e-6, 1.0);
            if (hard_reset || clamped_win != win_len) {
                win_len = clamped_win;
                const double fill_val = hard_reset ? 1.0 : rel_gain;
                dq_head = 0;
                dq_tail = 0;
                dq_size = 0;
                ma_pos = 0;
                for (size_t k = 0; k < win_len; ++k) {
                    ma_ring[k] = fill_val;
                }
                ma_sum = fill_val * static_cast<double>(win_len);
                drift_counter = 0;
            }
        }

        inline double process(double req_gain) {
            req_gain = std::clamp(req_gain, 1.0e-4, 1.0);
            const uint64_t cur_idx = sample_idx++;

            // 1. Pop expired samples from front of monotonic deque
            while (dq_size > 0 && (cur_idx - dq_idx[dq_head]) >= static_cast<uint64_t>(win_len)) {
                dq_head = (dq_head + 1) % cap;
                --dq_size;
            }

            // 2. Maintain monotonically non-decreasing deque for sliding minimum
            while (dq_size > 0) {
                const size_t back = (dq_tail + cap - 1) % cap;
                if (dq_val[back] >= req_gain) {
                    dq_tail = back;
                    --dq_size;
                } else {
                    break;
                }
            }

            dq_idx[dq_tail] = cur_idx;
            dq_val[dq_tail] = req_gain;
            dq_tail = (dq_tail + 1) % cap;
            ++dq_size;

            const double g_min = dq_val[dq_head];

            // 3. Instant hold / 1-pole exponential release
            if (g_min < rel_gain) {
                rel_gain = g_min;
            } else {
                rel_gain += rel_coeff * (g_min - rel_gain);
            }

            // 4. Exact causal moving average over win_len samples for smooth attack ramp
            ma_sum -= ma_ring[ma_pos];
            ma_ring[ma_pos] = rel_gain;
            ma_sum += rel_gain;
            ma_pos = (ma_pos + 1) % win_len;

            if (++drift_counter >= static_cast<uint32_t>(win_len)) {
                drift_counter = 0;
                double exact_sum = 0.0;
                for (size_t k = 0; k < win_len; ++k) {
                    exact_sum += ma_ring[k];
                }
                ma_sum = exact_sum;
            }

            return std::clamp(ma_sum / static_cast<double>(win_len), 1.0e-4, 1.0);
        }
    };

    static constexpr double kPi = 3.14159265358979323846;
    static constexpr double kInvSqrt2 = 0.70710678118654752440;
    static constexpr size_t kOversamplerDelay = 20;
    static constexpr size_t kStageBDelay = 32;

    static void designButterworthLP2(BiquadCoeffs& c, double fs, double fc) {
        fc = std::clamp(fc, 10.0, fs * 0.48);
        const double w0 = 2.0 * kPi * (fc / fs);
        const double cosW0 = std::cos(w0);
        const double sinW0 = std::sin(w0);
        const double alpha = sinW0 * kInvSqrt2;
        const double invA0 = 1.0 / (1.0 + alpha);
        c.b0 = (1.0 - cosW0) * 0.5 * invA0;
        c.b1 = (1.0 - cosW0) * invA0;
        c.b2 = (1.0 - cosW0) * 0.5 * invA0;
        c.a1 = (-2.0 * cosW0) * invA0;
        c.a2 = (1.0 - alpha) * invA0;
    }

    static void designButterworthHP2(BiquadCoeffs& c, double fs, double fc) {
        fc = std::clamp(fc, 10.0, fs * 0.48);
        const double w0 = 2.0 * kPi * (fc / fs);
        const double cosW0 = std::cos(w0);
        const double sinW0 = std::sin(w0);
        const double alpha = sinW0 * kInvSqrt2;
        const double invA0 = 1.0 / (1.0 + alpha);
        c.b0 = (1.0 + cosW0) * 0.5 * invA0;
        c.b1 = (-(1.0 + cosW0)) * invA0;
        c.b2 = (1.0 + cosW0) * 0.5 * invA0;
        c.a1 = (-2.0 * cosW0) * invA0;
        c.a2 = (1.0 - alpha) * invA0;
    }

    static void designButterworthAP2(BiquadCoeffs& c, double fs, double fc) {
        fc = std::clamp(fc, 10.0, fs * 0.48);
        const double w0 = 2.0 * kPi * (fc / fs);
        const double cosW0 = std::cos(w0);
        const double sinW0 = std::sin(w0);
        const double alpha = sinW0 * kInvSqrt2;
        const double invA0 = 1.0 / (1.0 + alpha);
        c.b0 = (1.0 - alpha) * invA0;
        c.b1 = (-2.0 * cosW0) * invA0;
        c.b2 = (1.0 + alpha) * invA0;
        c.a1 = (-2.0 * cosW0) * invA0;
        c.a2 = (1.0 - alpha) * invA0;
    }

    void updateCrossoverCoeffs() {
        const double fs = static_cast<double>(sample_rate_);
        const double f1 = static_cast<double>(low_xover_hz_.load(std::memory_order_relaxed));
        const double f2 = static_cast<double>(high_xover_hz_.load(std::memory_order_relaxed));
        designButterworthLP2(lp1_coeffs_, fs, f1);
        designButterworthHP2(hp1_coeffs_, fs, f1);
        designButterworthAP2(ap2_coeffs_, fs, f2);
        designButterworthLP2(lp2_coeffs_, fs, f2);
        designButterworthHP2(hp2_coeffs_, fs, f2);
        active_low_xover_hz_ = static_cast<float>(f1);
        active_high_xover_hz_ = static_cast<float>(f2);
    }

    void updateTimingConstants(bool hard_reset) {
        const double fs = static_cast<double>(sample_rate_);
        const float la_ms = lookahead_ms_.load(std::memory_order_relaxed);
        const size_t new_la = std::clamp<size_t>(
            static_cast<size_t>(std::llround(fs * (static_cast<double>(la_ms) * 0.001))),
            16,
            max_delay_samples_ - 1);

        if (hard_reset || new_la != lookahead_samples_) {
            lookahead_samples_ = new_la;
            stage_b_delay_ = (lookahead_samples_ >= 80) ? kStageBDelay : 0;
            stage_a_delay_ = lookahead_samples_ - stage_b_delay_;
            for (int b = 0; b < 3; ++b) {
                for (int c = 0; c < kMaxChannels; ++c) {
                    std::fill(delay_buf_[b][c].begin(), delay_buf_[b][c].end(), 0.0);
                }
            }
            for (int c = 0; c < kMaxChannels; ++c) {
                std::fill(post_delay_buf_[c].begin(), post_delay_buf_[c].end(), 0.0);
            }
            delay_pos_ = 0;
            post_delay_pos_ = 0;
        }

        const double bass_rel_s = static_cast<double>(bass_release_ms_.load(std::memory_order_relaxed)) * 0.001;
        const double bass_rel_coeff = 1.0 - std::exp(-1.0 / (fs * bass_rel_s));
        const double mid_rel_coeff  = 1.0 - std::exp(-1.0 / (fs * 0.080));
        const double high_rel_coeff = 1.0 - std::exp(-1.0 / (fs * 0.050));
        const double guard_rel_coeff = 1.0 - std::exp(-1.0 / (fs * std::max(bass_rel_s, 0.120)));

        const size_t env_win = stage_a_delay_ + 1;
        agc_headroom_env_.setParams(env_win, guard_rel_coeff, hard_reset);
        band_env_[0].setParams(env_win, bass_rel_coeff, hard_reset);
        band_env_[1].setParams(env_win, mid_rel_coeff, hard_reset);
        band_env_[2].setParams(env_win, high_rel_coeff, hard_reset);

        const size_t tp_win = (stage_b_delay_ > kOversamplerDelay)
            ? (stage_b_delay_ - kOversamplerDelay + 1)
            : 12;
        tp_safety_env_.setParams(tp_win, mid_rel_coeff, hard_reset);

        // Loudness detector (~1.5 s leaky short-term window) & fast peak hold (~30 ms decay)
        loudness_tau_samples_ = fs * 0.75; // half of 1.5 s rectangular equivalent
        loudness_min_fill_ = fs * 0.05;    // 50 ms warm-up before boosting
        peak_hold_decay_ = std::exp(-1.0 / (fs * 0.030));
        final_safety_rel_ = 1.0 - std::exp(-1.0 / (fs * 0.060));
    }

    void syncDirtyParams() {
        if (!params_dirty_.exchange(false, std::memory_order_acquire)) {
            return;
        }
        const float lx = low_xover_hz_.load(std::memory_order_relaxed);
        const float hx = high_xover_hz_.load(std::memory_order_relaxed);
        if (std::abs(lx - active_low_xover_hz_) > 0.5f || std::abs(hx - active_high_xover_hz_) > 0.5f) {
            updateCrossoverCoeffs();
        }
        updateTimingConstants(false);
    }

    template <typename SampleT>
    void processImpl(SampleT* buffer, size_t frame_count, int channels) {
        if (!enabled_.load(std::memory_order_relaxed) || !buffer || frame_count == 0 || channels <= 0) {
            return;
        }

        ScopedDenormalsDisable denormalGuard;
        syncDirtyParams();

        const int chs = std::min(channels, kMaxChannels);
        const double fs = static_cast<double>(sample_rate_);
        const double target_lufs = static_cast<double>(target_lufs_.load(std::memory_order_relaxed));
        const double max_boost_db = static_cast<double>(max_boost_db_.load(std::memory_order_relaxed));
        const double max_atten_db = static_cast<double>(max_attenuation_db_.load(std::memory_order_relaxed));
        const double rise_per_sample = static_cast<double>(agc_rise_db_sec_.load(std::memory_order_relaxed)) / fs;
        const double fall_per_sample = static_cast<double>(agc_fall_db_sec_.load(std::memory_order_relaxed)) / fs;
        const double silence_gate = static_cast<double>(silence_gate_lufs_.load(std::memory_order_relaxed));
        const double ceiling_db = static_cast<double>(ceiling_db_.load(std::memory_order_relaxed));
        const double ceiling_lin = std::pow(10.0, ceiling_db * 0.05);

        const double decay_1 = std::exp(-1.0 / loudness_tau_samples_);
        const bool use_4x_tp = (chs == 2) && (stage_b_delay_ > kOversamplerDelay);

        double min_low_gain = 1.0;
        double min_mid_gain = 1.0;
        double min_high_gain = 1.0;
        double min_peak_gain = 1.0;
        double last_effective_agc = agc_linear_;

        for (size_t i = 0; i < frame_count; ++i) {
            const size_t base_idx = i * static_cast<size_t>(channels);

            double frame_energy = 0.0;
            double in_peak = 0.0;
            double low_peak = 0.0;
            double mid_peak = 0.0;
            double high_peak = 0.0;
            double sum_peak = 0.0;

            double future_low[kMaxChannels];
            double future_mid[kMaxChannels];
            double future_high[kMaxChannels];

            // 1. Read un-delayed future frame & split via phase-coherent 3-band LR4 crossover
            for (int c = 0; c < chs; ++c) {
                const double x = static_cast<double>(buffer[base_idx + c]);
                frame_energy += x * x;
                in_peak = std::max(in_peak, std::abs(x));

                const double x_low1  = lp1_.process(lp1_coeffs_, c, x);
                const double x_high1 = hp1_.process(hp1_coeffs_, c, x);
                const double x_low   = ap2_.process(ap2_coeffs_, c, x_low1);
                const double x_mid   = lp2_.process(lp2_coeffs_, c, x_high1);
                const double x_high  = hp2_.process(hp2_coeffs_, c, x_high1);

                future_low[c] = x_low;
                future_mid[c] = x_mid;
                future_high[c] = x_high;

                low_peak = std::max(low_peak, std::abs(x_low));
                mid_peak = std::max(mid_peak, std::abs(x_mid));
                high_peak = std::max(high_peak, std::abs(x_high));
                sum_peak = std::max(sum_peak, std::abs(x_low + x_mid + x_high));
            }
            frame_energy /= static_cast<double>(chs);

            // 2. Lookahead Loudness Detector + Silence-Gated AGC
            loudness_sum_sq_ = loudness_sum_sq_ * decay_1 + frame_energy;
            loudness_sample_count_ = loudness_sample_count_ * decay_1 + 1.0;

            if (loudness_sample_count_ >= loudness_min_fill_) {
                const double mean_pwr = loudness_sum_sq_ / loudness_sample_count_;
                future_short_term_lufs_ = (mean_pwr > 1.0e-12)
                    ? (-0.691 + 10.0 * std::log10(mean_pwr))
                    : -100.0;
            }

            if (future_short_term_lufs_ > silence_gate) {
                const double desired_db = std::clamp(target_lufs - future_short_term_lufs_, -max_atten_db, max_boost_db);
                if (desired_db > agc_gain_db_) {
                    agc_gain_db_ = std::min(desired_db, agc_gain_db_ + rise_per_sample);
                } else if (desired_db < agc_gain_db_) {
                    agc_gain_db_ = std::max(desired_db, agc_gain_db_ - fall_per_sample);
                }
                agc_linear_ = std::pow(10.0, agc_gain_db_ * 0.05);
            }

            // 3. Pre-Emptive AGC Headroom Guard (only backs off AGC boost above unity/agc_floor,
            //    so loud bass notes never cause the AGC to pump quiet mids when AGC is at <= 0 dB).
            const double combined_future_peak = std::max(in_peak, sum_peak);
            double safe_lin = agc_linear_;
            if (combined_future_peak > 1.0e-7) {
                safe_lin = ceiling_lin / combined_future_peak;
            }
            if (low_peak > 1.0e-7) {
                safe_lin = std::min(safe_lin, (ceiling_lin * 0.96) / low_peak);
            }
            const double agc_floor = std::min(1.0, agc_linear_);
            const double target_effective_agc = std::clamp(safe_lin, agc_floor, agc_linear_);
            const double headroom_req = (agc_linear_ > 1.0e-6)
                ? std::clamp(target_effective_agc / agc_linear_, 1.0e-4, 1.0)
                : 1.0;
            const double effective_agc_lin = agc_linear_ * agc_headroom_env_.process(headroom_req);
            last_effective_agc = effective_agc_lin;

            // 4. Per-Band Lookahead Limiting (using projected post-guard AGC gain so there
            //    is no double-attenuation; Low leaves dynamic room for Mid+High to prevent vocal pumping).
            mid_peak_hold_  = std::max(mid_peak * target_effective_agc, mid_peak_hold_ * peak_hold_decay_);
            high_peak_hold_ = std::max(high_peak * target_effective_agc, high_peak_hold_ * peak_hold_decay_);

            const double other_headroom = std::min(ceiling_lin * 0.55, mid_peak_hold_ + high_peak_hold_);
            const double low_ceiling  = std::max(ceiling_lin * 0.40, ceiling_lin - other_headroom);
            const double mid_ceiling  = ceiling_lin * 0.98;
            const double high_ceiling = ceiling_lin * 0.96;

            const double proj_low  = low_peak * target_effective_agc;
            const double proj_mid  = mid_peak * target_effective_agc;
            const double proj_high = high_peak * target_effective_agc;

            const double req_low  = (proj_low > low_ceiling)   ? (low_ceiling / proj_low)   : 1.0;
            const double req_mid  = (proj_mid > mid_ceiling)   ? (mid_ceiling / proj_mid)   : 1.0;
            const double req_high = (proj_high > high_ceiling) ? (high_ceiling / proj_high) : 1.0;

            const double g_low  = band_env_[0].process(req_low);
            const double g_mid  = band_env_[1].process(req_mid);
            const double g_high = band_env_[2].process(req_high);

            min_low_gain = std::min(min_low_gain, g_low);
            min_mid_gain = std::min(min_mid_gain, g_mid);
            min_high_gain = std::min(min_high_gain, g_high);

            // 5. Stage A: Read delayed band samples and recombine
            double recombined[kMaxChannels];
            double recombined_peak = 0.0;

            for (int c = 0; c < chs; ++c) {
                const double d_low  = delay_buf_[0][c][delay_pos_];
                const double d_mid  = delay_buf_[1][c][delay_pos_];
                const double d_high = delay_buf_[2][c][delay_pos_];

                delay_buf_[0][c][delay_pos_] = future_low[c];
                delay_buf_[1][c][delay_pos_] = future_mid[c];
                delay_buf_[2][c][delay_pos_] = future_high[c];

                const double y_band = (d_low * g_low + d_mid * g_mid + d_high * g_high) * effective_agc_lin;
                recombined[c] = y_band;
                recombined_peak = std::max(recombined_peak, std::abs(y_band));
            }
            delay_pos_ = (delay_pos_ + 1) % stage_a_delay_;

            // 6. Stage B: Post-recombination 4x oversampled True-Peak Guard (stereo) + final brickwall safety
            double stage_b_out[kMaxChannels];
            double stage_b_peak = 0.0;
            double tp_guard_gain = 1.0;

            if (use_4x_tp) {
                double l0, r0, l1, r1;
                tp_filter1_.upsample2xFrame(recombined[0], recombined[1], l0, r0, l1, r1);
                double l00, r00, l01, r01, l10, r10, l11, r11;
                tp_filter2_.upsample2xFrame(l0, r0, l00, r00, l01, r01);
                tp_filter2_.upsample2xFrame(l1, r1, l10, r10, l11, r11);
                const SimdDouble2 m01 = SimdDouble2::max(
                    SimdDouble2(std::abs(l00), std::abs(r00)),
                    SimdDouble2(std::abs(l01), std::abs(r01)));
                const SimdDouble2 m23 = SimdDouble2::max(
                    SimdDouble2(std::abs(l10), std::abs(r10)),
                    SimdDouble2(std::abs(l11), std::abs(r11)));
                const SimdDouble2 m_all = SimdDouble2::max(m01, m23);
                const double tp_peak = std::max(recombined_peak, std::max(m_all.get(0), m_all.get(1)));
                const double tp_req = (tp_peak > ceiling_lin) ? (ceiling_lin / tp_peak) : 1.0;
                tp_guard_gain = tp_safety_env_.process(tp_req);

                for (int c = 0; c < chs; ++c) {
                    const double delayed_post = post_delay_buf_[c][post_delay_pos_];
                    post_delay_buf_[c][post_delay_pos_] = recombined[c];
                    stage_b_out[c] = delayed_post * tp_guard_gain;
                    stage_b_peak = std::max(stage_b_peak, std::abs(stage_b_out[c]));
                }
                post_delay_pos_ = (post_delay_pos_ + 1) % stage_b_delay_;
            } else {
                for (int c = 0; c < chs; ++c) {
                    stage_b_out[c] = recombined[c];
                }
                stage_b_peak = recombined_peak;
            }

            const double req_safety = (stage_b_peak > ceiling_lin) ? (ceiling_lin / stage_b_peak) : 1.0;
            if (req_safety < final_safety_gain_) {
                final_safety_gain_ = req_safety;
            } else {
                final_safety_gain_ += final_safety_rel_ * (req_safety - final_safety_gain_);
            }

            const double total_safety = final_safety_gain_ * tp_guard_gain;
            min_peak_gain = std::min(min_peak_gain, total_safety);

            for (int c = 0; c < chs; ++c) {
                const double y = std::clamp(stage_b_out[c] * final_safety_gain_, -ceiling_lin, ceiling_lin);
                buffer[base_idx + c] = static_cast<SampleT>(y);
            }
        }

        // Update atomic telemetry once per block
        const double eff_agc_db = 20.0 * std::log10(std::max(last_effective_agc, 1.0e-4));
        telemetry_agc_gain_db_.store(static_cast<float>(eff_agc_db), std::memory_order_relaxed);
        telemetry_low_gr_db_.store(toGrDb(min_low_gain), std::memory_order_relaxed);
        telemetry_mid_gr_db_.store(toGrDb(min_mid_gain), std::memory_order_relaxed);
        telemetry_high_gr_db_.store(toGrDb(min_high_gain), std::memory_order_relaxed);
        telemetry_peak_gr_db_.store(toGrDb(min_peak_gain), std::memory_order_relaxed);
    }

    static float toGrDb(double gain_linear) {
        if (gain_linear >= 0.999) return 0.0f;
        return static_cast<float>(20.0 * std::log10(std::max(gain_linear, 1.0e-4)));
    }

    std::atomic<bool> enabled_{false};
    std::atomic<bool> params_dirty_{false};
    bool initialized_ = false;
    float sample_rate_ = 48000.0f;

    // Parameters
    std::atomic<float> target_lufs_{-14.0f};
    std::atomic<float> max_boost_db_{9.0f};
    std::atomic<float> max_attenuation_db_{15.0f};
    std::atomic<float> agc_rise_db_sec_{1.5f};
    std::atomic<float> agc_fall_db_sec_{4.0f};
    std::atomic<float> silence_gate_lufs_{-45.0f};
    std::atomic<float> lookahead_ms_{10.0f};
    std::atomic<float> ceiling_db_{-0.1f};
    std::atomic<float> low_xover_hz_{180.0f};
    std::atomic<float> high_xover_hz_{3000.0f};
    std::atomic<float> bass_release_ms_{160.0f};

    float active_low_xover_hz_ = 180.0f;
    float active_high_xover_hz_ = 3000.0f;

    // Telemetry
    std::atomic<float> telemetry_agc_gain_db_{0.0f};
    std::atomic<float> telemetry_low_gr_db_{0.0f};
    std::atomic<float> telemetry_mid_gr_db_{0.0f};
    std::atomic<float> telemetry_high_gr_db_{0.0f};
    std::atomic<float> telemetry_peak_gr_db_{0.0f};

    // Crossover state (3-band phase-coherent LR4)
    BiquadCoeffs lp1_coeffs_;
    BiquadCoeffs hp1_coeffs_;
    BiquadCoeffs ap2_coeffs_;
    BiquadCoeffs lp2_coeffs_;
    BiquadCoeffs hp2_coeffs_;
    LR4Stage lp1_;
    LR4Stage hp1_;
    AP2Stage ap2_;
    LR4Stage lp2_;
    LR4Stage hp2_;

    // 4x oversamplers for stereo true-peak detection
    HalfBandFilter2xT<double> tp_filter1_;
    HalfBandFilter2xT<double> tp_filter2_;

    // Pre-allocated lookahead ring buffers [band][channel][frame]
    size_t max_delay_samples_ = 1208;
    size_t lookahead_samples_ = 480;
    size_t stage_a_delay_ = 448;
    size_t stage_b_delay_ = 32;
    size_t delay_pos_ = 0;
    size_t post_delay_pos_ = 0;
    std::array<std::array<std::vector<double>, kMaxChannels>, 3> delay_buf_;
    std::array<std::vector<double>, kMaxChannels> post_delay_buf_;

    // Lookahead envelopes
    LookaheadEnvelope agc_headroom_env_;
    std::array<LookaheadEnvelope, 3> band_env_;
    LookaheadEnvelope tp_safety_env_;

    // AGC & detector state
    double agc_gain_db_ = 0.0;
    double agc_linear_ = 1.0;
    double loudness_sum_sq_ = 0.0;
    double loudness_sample_count_ = 0.0;
    double loudness_tau_samples_ = 36000.0;
    double loudness_min_fill_ = 2400.0;
    double future_short_term_lufs_ = -100.0;

    double mid_peak_hold_ = 0.0;
    double high_peak_hold_ = 0.0;
    double peak_hold_decay_ = 0.999;

    double final_safety_gain_ = 1.0;
    double final_safety_rel_ = 0.001;
};

} // namespace sauti::dsp
