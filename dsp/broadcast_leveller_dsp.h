#pragma once

#include <algorithm>
#include <atomic>
#include <cmath>
#include <cstdint>

#include "bs1770_kweight.h"
#include "denormals.h"
#include "simd_math.h"

namespace sauti::dsp {

// =============================================================================
// BroadcastLevellerDSP: EBU R128 / ITU-R BS.1770 Real-Time Slow-Window AGC
//
// Features:
// - Eliminates long-term volume disparity on live radio streams, podcasts, and
//   shuffle playlists by riding gain at a psychoacoustically transparent slew
//   rate (0.5 - 1.5 dB/sec).
// - True ITU-R BS.1770-4 K-weighted internal loudness detector (sum of
//   weighted channel powers, avoiding stereo -3.01 dB bias).
// - Silence / Noise Floor Freeze with 2.0 dB hysteresis band to prevent rapid
//   gate chatter near the noise floor.
// - Positive-boost peak headroom guard (~ -0.5 dBFS) to avoid pushing transients
//   into hard digital clipping.
// - Lock-free atomics and deferred RT-safe state resets.
// =============================================================================
class BroadcastLevellerDSP {
public:
    static constexpr int kMaxChannels = BS1770KWeightFilter::kMaxChannels;

    BroadcastLevellerDSP() {
        applySampleRateInternal(48000.0f);
        resetInternal();
    }

    void setSampleRate(float sampleRate) {
        if (!std::isfinite(sampleRate) || sampleRate <= 0.0f) {
            sampleRate = 48000.0f;
        }
        const float prev = target_sample_rate_.load(std::memory_order_relaxed);
        if (initialized_.load(std::memory_order_acquire) && std::abs(prev - sampleRate) < 0.1f) {
            return;
        }
        target_sample_rate_.store(sampleRate, std::memory_order_relaxed);
        reconfig_requested_.store(true, std::memory_order_release);
        initialized_.store(true, std::memory_order_release);
    }

    float getSampleRate() const {
        return target_sample_rate_.load(std::memory_order_relaxed);
    }

    void setEnabled(bool enabled) {
        const bool was_enabled = enabled_.exchange(enabled, std::memory_order_acq_rel);
        if (!enabled) {
            current_gain_db_.store(0.0f, std::memory_order_relaxed);
            reset_requested_.store(true, std::memory_order_release);
        } else if (!was_enabled) {
            reset_requested_.store(true, std::memory_order_release);
        }
    }

    bool isEnabled() const {
        return enabled_.load(std::memory_order_acquire);
    }

    void setParams(float target_lufs,
                   float max_rise_db_sec,
                   float max_fall_db_sec,
                   float max_boost_db,
                   float max_attenuation_db,
                   float silence_gate_lufs) {
        if (!std::isfinite(target_lufs)) target_lufs = -16.0f;
        if (!std::isfinite(max_rise_db_sec)) max_rise_db_sec = 0.75f;
        if (!std::isfinite(max_fall_db_sec)) max_fall_db_sec = 1.50f;
        if (!std::isfinite(max_boost_db)) max_boost_db = 9.0f;
        if (!std::isfinite(max_attenuation_db)) max_attenuation_db = 12.0f;
        if (!std::isfinite(silence_gate_lufs)) silence_gate_lufs = -45.0f;

        target_lufs_.store(std::clamp(target_lufs, -36.0f, -6.0f), std::memory_order_release);
        max_rise_db_sec_.store(std::clamp(max_rise_db_sec, 0.1f, 6.0f), std::memory_order_release);
        max_fall_db_sec_.store(std::clamp(max_fall_db_sec, 0.1f, 12.0f), std::memory_order_release);
        max_boost_db_.store(std::clamp(max_boost_db, 0.0f, 18.0f), std::memory_order_release);
        max_attenuation_db_.store(std::clamp(max_attenuation_db, 0.0f, 24.0f), std::memory_order_release);
        silence_gate_lufs_.store(std::clamp(silence_gate_lufs, -70.0f, -24.0f), std::memory_order_release);
    }

    void getParams(float *out_target_lufs,
                   float *out_max_rise_db_sec,
                   float *out_max_fall_db_sec,
                   float *out_max_boost_db,
                   float *out_max_attenuation_db,
                   float *out_silence_gate_lufs) const {
        if (out_target_lufs) *out_target_lufs = target_lufs_.load(std::memory_order_relaxed);
        if (out_max_rise_db_sec) *out_max_rise_db_sec = max_rise_db_sec_.load(std::memory_order_relaxed);
        if (out_max_fall_db_sec) *out_max_fall_db_sec = max_fall_db_sec_.load(std::memory_order_relaxed);
        if (out_max_boost_db) *out_max_boost_db = max_boost_db_.load(std::memory_order_relaxed);
        if (out_max_attenuation_db) *out_max_attenuation_db = max_attenuation_db_.load(std::memory_order_relaxed);
        if (out_silence_gate_lufs) *out_silence_gate_lufs = silence_gate_lufs_.load(std::memory_order_relaxed);
    }

    float getCurrentGainDb() const {
        if (!enabled_.load(std::memory_order_relaxed)) {
            return 0.0f;
        }
        return current_gain_db_.load(std::memory_order_relaxed);
    }

    void reset() {
        current_gain_db_.store(0.0f, std::memory_order_relaxed);
        reset_requested_.store(true, std::memory_order_release);
    }

    // Process 32-bit float interleaved samples in-place.
    // external_short_term_lufs: Pass real-time short-term LUFS from BS.1770 meter (or < -90 to use internal measurement).
    void process(float *buffer, size_t frame_count, int channels, float external_short_term_lufs = -100.0f) {
        processImpl<float>(buffer, frame_count, channels, external_short_term_lufs);
    }

    // Process 64-bit double interleaved samples in-place.
    void process(double *buffer, size_t frame_count, int channels, float external_short_term_lufs = -100.0f) {
        processImpl<double>(buffer, frame_count, channels, external_short_term_lufs);
    }

private:
    void applySampleRateInternal(float sampleRate) noexcept {
        active_sample_rate_ = sampleRate;
        target_sample_rate_.store(sampleRate, std::memory_order_relaxed);
        initialized_.store(true, std::memory_order_release);

        internal_window_samples_ = static_cast<size_t>(active_sample_rate_ * 3.0f);
        if (internal_window_samples_ == 0) internal_window_samples_ = 48000 * 3;
        kweight_.updateSampleRate(static_cast<double>(active_sample_rate_));
    }

    void resetInternal() noexcept {
        current_gain_db_.store(0.0f, std::memory_order_relaxed);
        target_gain_db_ = 0.0f;
        current_gain_linear_ = 1.0f;
        is_frozen_ = false;
        internal_sum_sq_ = 0.0;
        internal_sample_count_ = 0.0;
        internal_short_term_lufs_ = -100.0f;
        kweight_.reset();
    }

    template <typename SampleT>
    void processImpl(SampleT *buffer, size_t frame_count, int channels, float external_short_term_lufs) {
        if (!enabled_.load(std::memory_order_acquire) || buffer == nullptr || frame_count == 0 || channels <= 0) {
            return;
        }

        ScopedDenormalsDisable denormalGuard;

        bool need_reset = reset_requested_.exchange(false, std::memory_order_acq_rel);
        if (reconfig_requested_.exchange(false, std::memory_order_acq_rel)) {
            const float new_sr = target_sample_rate_.load(std::memory_order_acquire);
            if (std::abs(new_sr - active_sample_rate_) >= 0.1f) {
                applySampleRateInternal(new_sr);
                need_reset = true;
            }
        }
        if (channels != active_channels_) {
            active_channels_ = channels;
            need_reset = true;
        }
        if (need_reset) {
            resetInternal();
        }

        // Measure input peak and optional internal K-weighted BS.1770 loudness
        double block_peak = 0.0;
        for (size_t i = 0; i < frame_count * static_cast<size_t>(channels); ++i) {
            const double a = std::abs(static_cast<double>(buffer[i]));
            if (std::isfinite(a) && a > block_peak) {
                block_peak = a;
            }
        }

        float effective_lufs = external_short_term_lufs;
        if (effective_lufs < -90.0f) {
            effective_lufs = computeInternalLufs(buffer, frame_count, channels);
        }

        computeBlockGain(effective_lufs, frame_count);

        const double start_gain = static_cast<double>(current_gain_linear_);
        float cur_db = current_gain_db_.load(std::memory_order_relaxed);
        double end_gain = std::pow(10.0, static_cast<double>(cur_db) / 20.0);

        // Positive-boost peak headroom guard (~ -0.5 dBFS = 0.944061 linear)
        constexpr double kHeadroomCeiling = 0.9440608762859234;
        if (end_gain > 1.0 && block_peak * end_gain > kHeadroomCeiling) {
            const double safe_gain = std::max(1.0, kHeadroomCeiling / block_peak);
            end_gain = safe_gain;
            const float safe_db = static_cast<float>(20.0 * std::log10(safe_gain));
            if (safe_db < cur_db) {
                current_gain_db_.store(safe_db, std::memory_order_relaxed);
            }
        }

        const double gain_step = (end_gain - start_gain) / static_cast<double>(frame_count);
        double g = start_gain;

        for (size_t i = 0; i < frame_count; ++i) {
            SampleT *frame = buffer + i * static_cast<size_t>(channels);
            for (int c = 0; c < channels; ++c) {
                double s = static_cast<double>(frame[c]);
                if (!std::isfinite(s)) s = 0.0;
                frame[c] = static_cast<SampleT>(s * g);
            }
            g += gain_step;
        }

        current_gain_linear_ = static_cast<float>(end_gain);
    }

    template <typename T>
    float computeInternalLufs(const T *buf, size_t frame_count, int channels) {
        const int ch = std::clamp(channels, 1, kMaxChannels);
        double block_energy = 0.0;
        for (size_t i = 0; i < frame_count; ++i) {
            double frame_energy = 0.0;
            for (int c = 0; c < ch; ++c) {
                const double s = static_cast<double>(buf[i * static_cast<size_t>(channels) + c]);
                const double y = kweight_.processSample(c, s);
                frame_energy += BS1770KWeightFilter::channelWeight(c, ch) * y * y;
            }
            // ITU-R BS.1770-4 sums weighted channel powers (no / channels division)
            block_energy += frame_energy;
        }

        // Exponentially-leaky 3-second mean-square (tau = window * 0.5)
        const double tau = static_cast<double>(internal_window_samples_) * 0.5;
        const double decay = std::exp(-static_cast<double>(frame_count) / tau);
        internal_sum_sq_ = internal_sum_sq_ * decay + block_energy;
        internal_sample_count_ = internal_sample_count_ * decay + static_cast<double>(frame_count);

        // Require ~94 ms of history (window/32) before trusting the estimate
        const double min_fill = static_cast<double>(internal_window_samples_) / 32.0;
        if (internal_sample_count_ >= min_fill) {
            const double mean_pwr = internal_sum_sq_ / internal_sample_count_;
            if (mean_pwr > 1.0e-12) {
                internal_short_term_lufs_ = static_cast<float>(-0.691 + 10.0 * std::log10(mean_pwr));
            } else {
                internal_short_term_lufs_ = -100.0f;
            }
        }
        return internal_short_term_lufs_;
    }

    void computeBlockGain(float effective_lufs, size_t frame_count) {
        const float silence_gate = silence_gate_lufs_.load(std::memory_order_relaxed);
        constexpr float kHysteresisDb = 2.0f;

        // 1. Silence / Noise Gate Freeze with 2.0 dB hysteresis band
        if (!is_frozen_) {
            if (effective_lufs <= silence_gate) {
                is_frozen_ = true;
                target_gain_db_ = current_gain_db_.load(std::memory_order_relaxed);
                return;
            }
        } else {
            if (effective_lufs <= silence_gate + kHysteresisDb) {
                target_gain_db_ = current_gain_db_.load(std::memory_order_relaxed);
                return;
            }
            is_frozen_ = false;
        }

        // 2. Compute desired correction gain in dB
        const float target_lufs = target_lufs_.load(std::memory_order_relaxed);
        const float max_att = max_attenuation_db_.load(std::memory_order_relaxed);
        const float max_boost = max_boost_db_.load(std::memory_order_relaxed);
        float desired_gain_db = target_lufs - effective_lufs;
        desired_gain_db = std::clamp(desired_gain_db, -max_att, max_boost);
        target_gain_db_ = desired_gain_db;

        // 3. Slew rate limiter: step smoothly toward target
        const float dt = static_cast<float>(frame_count) / active_sample_rate_;
        float cur = current_gain_db_.load(std::memory_order_relaxed);

        if (target_gain_db_ > cur) {
            const float max_rise = max_rise_db_sec_.load(std::memory_order_relaxed) * dt;
            cur = std::min(target_gain_db_, cur + max_rise);
        } else if (target_gain_db_ < cur) {
            const float max_fall = max_fall_db_sec_.load(std::memory_order_relaxed) * dt;
            cur = std::max(target_gain_db_, cur - max_fall);
        }
        current_gain_db_.store(cur, std::memory_order_relaxed);
    }

    std::atomic<bool> enabled_{false};
    std::atomic<bool> initialized_{false};
    std::atomic<bool> reset_requested_{false};
    std::atomic<bool> reconfig_requested_{false};

    std::atomic<float> target_sample_rate_{48000.0f};
    float active_sample_rate_{48000.0f};
    int active_channels_{2};

    // Controls
    std::atomic<float> target_lufs_{-16.0f};          // Target broadcast / streaming level
    std::atomic<float> max_rise_db_sec_{0.75f};       // Upward slew rate (0.75 dB/sec = transparent)
    std::atomic<float> max_fall_db_sec_{1.50f};       // Downward slew rate (1.5 dB/sec)
    std::atomic<float> max_boost_db_{9.0f};           // Max permissible upward gain
    std::atomic<float> max_attenuation_db_{12.0f};    // Max permissible downward attenuation
    std::atomic<float> silence_gate_lufs_{-45.0f};    // Level below which gain freezes

    // Real-time state
    std::atomic<float> current_gain_db_{0.0f};
    float target_gain_db_{0.0f};
    float current_gain_linear_{1.0f};
    bool is_frozen_{false};

    // Internal BS.1770 K-weighted detector state
    BS1770KWeightFilter kweight_;
    size_t internal_window_samples_{48000 * 3};
    double internal_sum_sq_{0.0};
    double internal_sample_count_{0.0};
    float internal_short_term_lufs_{-100.0f};
};

} // namespace sauti::dsp
