#pragma once

#include <algorithm>
#include <array>
#include <atomic>
#include <cmath>
#include <cstddef>
#include <cstdint>

#include "denormals.h"
#include "oversampler.h"
#include "simd_math.h"

namespace sauti::dsp {

// =============================================================================
// MasterLimiterDSP: Professional 4x True-Peak Lookahead Mastering Limiter
//
// Features:
//   - Lock-free atomic parameter updates and deferred RT-safe reset/reconfig
//   - Zero heap allocations after construction (fixed capacity up to 384+ kHz)
//   - O(1) monotonic-deque hold + 1-pole release + causal boxcar ramp envelope
//   - Exact delay alignment between 4x polyphase true-peak detector (~20-sample
//     group delay) and lookahead audio delay line (1.5 ms, 72 samples @ 48 kHz)
//   - Pre-detector drive / post-limiter trim split for output_gain_db so
//     positive gain boosts drive into the limiter without post-limiter clipping
//   - Linked multichannel peak detection (1..8 channels) with 64-bit internal
//     precision and bit-transparent unity passthrough below ceiling
// =============================================================================
class MasterLimiterDSP {
public:
    static constexpr int kMaxChannels = 8;
    static constexpr int kMaxStereoPairs = kMaxChannels / 2;
    static constexpr size_t kOversamplerDelay = 20;
    static constexpr size_t kMinLookaheadSamples = 24;
    static constexpr size_t kMaxLookaheadSamples = 640;
    static constexpr size_t kDelayCap = 1024; // Power of 2 > kMaxLookaheadSamples
    static constexpr size_t kDelayMask = kDelayCap - 1;
    static constexpr size_t kEnvCap = 1024;   // Power of 2 > kMaxLookaheadSamples
    static constexpr size_t kEnvMask = kEnvCap - 1;

    MasterLimiterDSP() {
        applySampleRateConfig(48000.0f);
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
        const size_t new_la = computeLookaheadSamples(sampleRate);
        lookahead_samples_.store(new_la, std::memory_order_release);
        reconfig_requested_.store(true, std::memory_order_release);
        initialized_.store(true, std::memory_order_release);
    }

    void setEnabled(bool enabled) {
        const bool was_enabled = enabled_.exchange(enabled, std::memory_order_acq_rel);
        if (!enabled) {
            current_gain_.store(1.0f, std::memory_order_relaxed);
            reset_requested_.store(true, std::memory_order_release);
        } else if (!was_enabled) {
            reset_requested_.store(true, std::memory_order_release);
        }
    }

    bool isEnabled() const {
        return enabled_.load(std::memory_order_acquire);
    }

    void setCeilingDb(float ceilingDb) {
        if (!std::isfinite(ceilingDb)) ceilingDb = -0.1f;
        const float clamped = std::clamp(ceilingDb, -12.0f, 0.0f);
        ceiling_db_.store(clamped, std::memory_order_relaxed);
        const double lin = (std::abs(clamped) < 1e-6f)
            ? 1.0
            : std::pow(10.0, static_cast<double>(clamped) / 20.0);
        target_ceiling_linear_.store(lin, std::memory_order_release);
    }

    float getCeilingDb() const {
        return ceiling_db_.load(std::memory_order_relaxed);
    }

    void setOutputGainDb(float gainDb) {
        if (!std::isfinite(gainDb)) gainDb = 0.0f;
        const float clamped = std::clamp(gainDb, -24.0f, 12.0f);
        output_gain_db_.store(clamped, std::memory_order_relaxed);
        const double lin = (std::abs(clamped) < 1e-6f)
            ? 1.0
            : std::pow(10.0, static_cast<double>(clamped) / 20.0);
        target_output_gain_linear_.store(lin, std::memory_order_release);
    }

    float getOutputGainDb() const {
        return output_gain_db_.load(std::memory_order_relaxed);
    }

    void setReleaseMs(float releaseMs) {
        if (!std::isfinite(releaseMs)) releaseMs = 50.0f;
        release_ms_.store(std::clamp(releaseMs, 5.0f, 1000.0f), std::memory_order_release);
    }

    float getReleaseMs() const {
        return release_ms_.load(std::memory_order_relaxed);
    }

    size_t getLatencySamples() const {
        return lookahead_samples_.load(std::memory_order_acquire);
    }

    void reset() {
        current_gain_.store(1.0f, std::memory_order_relaxed);
        reset_requested_.store(true, std::memory_order_release);
    }

    float getCurrentGainReductionDb() const {
        if (!enabled_.load(std::memory_order_relaxed)) {
            return 0.0f;
        }
        const float g = current_gain_.load(std::memory_order_relaxed);
        if (g >= 0.9999f) return 0.0f;
        return 20.0f * std::log10(std::max(g, 0.0001f));
    }

    float getCurrentLinearGain() const {
        if (!enabled_.load(std::memory_order_relaxed)) {
            return 1.0f;
        }
        return current_gain_.load(std::memory_order_relaxed);
    }

    void process(float* interleaved_samples, uint32_t frame_count, int channels = 2) {
        processImpl<float>(interleaved_samples, frame_count, channels);
    }

    void process(double* interleaved_samples, uint32_t frame_count, int channels = 2) {
        processImpl<double>(interleaved_samples, frame_count, channels);
    }

private:
    static size_t computeLookaheadSamples(float sampleRate) noexcept {
        const size_t raw = static_cast<size_t>(sampleRate * 0.0015f);
        return std::clamp(raw, kMinLookaheadSamples, kMaxLookaheadSamples);
    }

    void applySampleRateConfig(float sampleRate) noexcept {
        active_sample_rate_ = static_cast<double>(sampleRate);
        active_lookahead_ = computeLookaheadSamples(sampleRate);
        lookahead_samples_.store(active_lookahead_, std::memory_order_release);
        target_sample_rate_.store(sampleRate, std::memory_order_relaxed);
        initialized_.store(true, std::memory_order_release);

        // Ramp length matches the slack between lookahead delay and the
        // 4x polyphase oversampler group delay (52 samples @ 48 kHz -> max
        // single-sample gain step <= 1/52 = 0.01923 < 0.02).
        // Hold length covers [n - 1 .. n + 2] across all 4 fractional phases.
        ramp_len_ = (active_lookahead_ > kOversamplerDelay)
            ? (active_lookahead_ - kOversamplerDelay)
            : 4;
        hold_len_ = std::min(ramp_len_ + 4, kEnvCap - 1);
        inv_ramp_len_ = 1.0 / static_cast<double>(ramp_len_);

        smoothing_coeff_ = 1.0 - std::exp(-1.0 / (0.030 * active_sample_rate_));
        updateReleaseCoeff(release_ms_.load(std::memory_order_relaxed));
    }

    void updateReleaseCoeff(float releaseMs) noexcept {
        active_release_ms_ = releaseMs;
        const double release_sec = static_cast<double>(releaseMs) * 0.001;
        release_coeff_ = 1.0 - std::exp(-1.0 / std::max(1.0, release_sec * active_sample_rate_));
    }

    void resetInternal() noexcept {
        for (int c = 0; c < kMaxChannels; ++c) {
            delay_line_[c].fill(0.0);
        }
        delay_idx_ = 0;

        for (int p = 0; p < kMaxStereoPairs; ++p) {
            os_stage1_[p].reset();
            os_stage2_[p].reset();
        }

        deque_head_ = 0;
        deque_tail_ = 0;
        sample_clock_ = 0;
        release_env_ = 1.0;

        ma_buf_.fill(0.0);
        ma_idx_ = 0;
        deficit_sum_ = 0.0;

        current_ceiling_linear_ = target_ceiling_linear_.load(std::memory_order_acquire);
        current_output_gain_linear_ = target_output_gain_linear_.load(std::memory_order_acquire);
        has_processed_ = false;
        current_gain_.store(1.0f, std::memory_order_relaxed);
    }

    template <typename SampleT>
    void processImpl(SampleT* interleaved_samples, uint32_t frame_count, int channels) {
        if (!interleaved_samples || frame_count == 0) {
            return;
        }
        if (!enabled_.load(std::memory_order_acquire)) {
            return;
        }

        ScopedDenormalsDisable denormals_guard;

        const int ch = std::clamp(channels, 1, kMaxChannels);
        bool need_reset = reset_requested_.exchange(false, std::memory_order_acq_rel);

        if (reconfig_requested_.exchange(false, std::memory_order_acq_rel)) {
            const float new_sr = target_sample_rate_.load(std::memory_order_acquire);
            if (std::abs(static_cast<double>(new_sr) - active_sample_rate_) >= 0.1) {
                applySampleRateConfig(new_sr);
                need_reset = true;
            }
        }

        if (ch != active_channels_) {
            active_channels_ = ch;
            need_reset = true;
        }

        if (need_reset) {
            resetInternal();
        }

        const float req_release = release_ms_.load(std::memory_order_acquire);
        if (std::abs(req_release - active_release_ms_) > 1e-4f) {
            updateReleaseCoeff(req_release);
        }

        const double target_ceil = target_ceiling_linear_.load(std::memory_order_acquire);
        const double target_out_gain = target_output_gain_linear_.load(std::memory_order_acquire);

        if (!has_processed_) {
            current_ceiling_linear_ = target_ceil;
            current_output_gain_linear_ = target_out_gain;
            has_processed_ = true;
        }

        const int num_pairs = (ch + 1) / 2;
        const size_t lookahead = active_lookahead_;
        const size_t hold_len = hold_len_;
        const size_t ramp_len = ramp_len_;
        const double inv_ramp = inv_ramp_len_;
        const double smooth_c = smoothing_coeff_;
        const double rel_c = release_coeff_;

        double last_gain = 1.0;

        for (uint32_t i = 0; i < frame_count; ++i) {
            // 1. Parameter smoothing (snaps cleanly to exact target when settled)
            const double ceil_diff = target_ceil - current_ceiling_linear_;
            if (std::abs(ceil_diff) > 1e-12) {
                current_ceiling_linear_ += smooth_c * ceil_diff;
            } else {
                current_ceiling_linear_ = target_ceil;
            }

            const double gain_diff = target_out_gain - current_output_gain_linear_;
            if (std::abs(gain_diff) > 1e-12) {
                current_output_gain_linear_ += smooth_c * gain_diff;
            } else {
                current_output_gain_linear_ = target_out_gain;
            }

            const double ceil = current_ceiling_linear_;
            const double pre_drive = (current_output_gain_linear_ > 1.0)
                ? current_output_gain_linear_
                : 1.0;
            const double post_trim = (current_output_gain_linear_ < 1.0)
                ? current_output_gain_linear_
                : 1.0;

            SampleT* frame_ptr = interleaved_samples + static_cast<size_t>(i) * static_cast<size_t>(ch);

            // 2. Push pre-driven input into delay line and fetch delayed audio
            double driven[kMaxChannels];
            double delayed[kMaxChannels];
            const size_t read_idx = (delay_idx_ - lookahead) & kDelayMask;

            for (int c = 0; c < ch; ++c) {
                double s = static_cast<double>(frame_ptr[c]);
                if (!std::isfinite(s)) s = 0.0;
                const double d = (pre_drive == 1.0) ? s : (s * pre_drive);
                driven[c] = d;
                delay_line_[c][delay_idx_] = d;
                delayed[c] = delay_line_[c][read_idx];
            }

            // 3. 4x True-Peak detection (time-aligned at oversampler delay; NO undelayed raw peak)
            double true_peak = 0.0;
            for (int p = 0; p < num_pairs; ++p) {
                const int c0 = p * 2;
                const int c1 = c0 + 1;
                const double in_l = driven[c0];
                const double in_r = (c1 < ch) ? driven[c1] : 0.0;

                double u2_l0, u2_r0, u2_l1, u2_r1;
                os_stage1_[p].upsample2xFrame(in_l, in_r, u2_l0, u2_r0, u2_l1, u2_r1);

                double u4_l0, u4_r0, u4_l1, u4_r1;
                double u4_l2, u4_r2, u4_l3, u4_r3;
                os_stage2_[p].upsample2xFrame(u2_l0, u2_r0, u4_l0, u4_r0, u4_l1, u4_r1);
                os_stage2_[p].upsample2xFrame(u2_l1, u2_r1, u4_l2, u4_r2, u4_l3, u4_r3);

                const double peak_l = std::max(
                    std::max(std::abs(u4_l0), std::abs(u4_l1)),
                    std::max(std::abs(u4_l2), std::abs(u4_l3)));
                if (peak_l > true_peak) true_peak = peak_l;

                if (c1 < ch) {
                    const double peak_r = std::max(
                        std::max(std::abs(u4_r0), std::abs(u4_r1)),
                        std::max(std::abs(u4_r2), std::abs(u4_r3)));
                    if (peak_r > true_peak) true_peak = peak_r;
                }
            }

            // 4. Instantaneous required gain
            double g_req = 1.0;
            if (true_peak > ceil) {
                g_req = std::max(ceil / true_peak, 1.0e-6);
            }

            // 5. O(1) monotonic-deque sliding minimum over hold_len samples
            while (deque_tail_ != deque_head_) {
                const size_t back_slot = (deque_tail_ - 1) & kEnvMask;
                if (deque_val_[back_slot] >= g_req) {
                    deque_tail_ = back_slot;
                } else {
                    break;
                }
            }
            deque_idx_[deque_tail_] = sample_clock_;
            deque_val_[deque_tail_] = g_req;
            deque_tail_ = (deque_tail_ + 1) & kEnvMask;

            while (deque_head_ != deque_tail_ &&
                   (sample_clock_ - deque_idx_[deque_head_]) >= hold_len) {
                deque_head_ = (deque_head_ + 1) & kEnvMask;
            }
            const double g_min = deque_val_[deque_head_];

            // 6. Instantaneous attack / 1-pole exponential release envelope
            if (g_min < release_env_) {
                release_env_ = g_min;
            } else {
                release_env_ += rel_c * (g_min - release_env_);
                if (release_env_ > 1.0 - 1.0e-12) {
                    release_env_ = 1.0;
                }
            }

            // 7. Causal boxcar moving-average ramp in deficit domain (bit-exact 1.0 at rest)
            const double deficit = 1.0 - release_env_;
            const double old_deficit = ma_buf_[ma_idx_];
            ma_buf_[ma_idx_] = deficit;
            if (++ma_idx_ >= ramp_len) {
                ma_idx_ = 0;
            }
            deficit_sum_ += (deficit - old_deficit);

            if ((sample_clock_ & 4095ULL) == 0ULL) {
                double exact_sum = 0.0;
                for (size_t k = 0; k < ramp_len; ++k) {
                    exact_sum += ma_buf_[k];
                }
                deficit_sum_ = exact_sum;
            }
            if (deficit_sum_ < 1.0e-15) {
                deficit_sum_ = 0.0;
            }

            double gain = 1.0 - deficit_sum_ * inv_ramp;
            if (gain < 1.0e-6) gain = 1.0e-6;
            else if (gain > 1.0) gain = 1.0;
            last_gain = gain;

            // 8. Apply linked gain + post-trim + safety ceiling guard
            const double total_gain = (post_trim == 1.0) ? gain : (gain * post_trim);
            const double hard_ceil = (post_trim == 1.0) ? ceil : (ceil * post_trim);

            if (total_gain == 1.0) {
                for (int c = 0; c < ch; ++c) {
                    double out = delayed[c];
                    if (out > hard_ceil) out = hard_ceil;
                    else if (out < -hard_ceil) out = -hard_ceil;
                    frame_ptr[c] = static_cast<SampleT>(out);
                }
            } else {
                for (int c = 0; c < ch; ++c) {
                    double out = delayed[c] * total_gain;
                    if (out > hard_ceil) out = hard_ceil;
                    else if (out < -hard_ceil) out = -hard_ceil;
                    frame_ptr[c] = static_cast<SampleT>(out);
                }
            }

            delay_idx_ = (delay_idx_ + 1) & kDelayMask;
            ++sample_clock_;
        }

        current_gain_.store(static_cast<float>(last_gain), std::memory_order_relaxed);
    }

    // Lock-free atomic parameters (written by UI/control thread, read by RT audio thread)
    std::atomic<bool> enabled_{false};
    std::atomic<bool> initialized_{false};
    std::atomic<bool> reset_requested_{false};
    std::atomic<bool> reconfig_requested_{false};

    std::atomic<float> target_sample_rate_{48000.0f};
    std::atomic<size_t> lookahead_samples_{72};
    std::atomic<float> ceiling_db_{-0.1f};
    std::atomic<double> target_ceiling_linear_{0.9885530946569389};
    std::atomic<float> output_gain_db_{0.0f};
    std::atomic<double> target_output_gain_linear_{1.0};
    std::atomic<float> release_ms_{50.0f};
    std::atomic<float> current_gain_{1.0f};

    // Audio-thread-only DSP state
    double active_sample_rate_{48000.0};
    float active_release_ms_{50.0f};
    int active_channels_{2};
    size_t active_lookahead_{72};
    size_t hold_len_{56};
    size_t ramp_len_{52};
    double inv_ramp_len_{1.0 / 52.0};
    double smoothing_coeff_{0.0};
    double release_coeff_{0.0};

    double current_ceiling_linear_{0.9885530946569389};
    double current_output_gain_linear_{1.0};
    bool has_processed_{false};

    // Pre-allocated multichannel audio delay line
    std::array<std::array<double, kDelayCap>, kMaxChannels> delay_line_{};
    size_t delay_idx_{0};

    // Pre-allocated 4x polyphase true-peak oversamplers (up to 4 stereo pairs = 8 ch)
    std::array<HalfBandFilter2xT<double>, kMaxStereoPairs> os_stage1_{};
    std::array<HalfBandFilter2xT<double>, kMaxStereoPairs> os_stage2_{};

    // Pre-allocated O(1) monotonic deque for hold window
    std::array<uint64_t, kEnvCap> deque_idx_{};
    std::array<double, kEnvCap> deque_val_{};
    size_t deque_head_{0};
    size_t deque_tail_{0};
    uint64_t sample_clock_{0};

    // Envelope release & causal moving-average ramp
    double release_env_{1.0};
    std::array<double, kEnvCap> ma_buf_{};
    size_t ma_idx_{0};
    double deficit_sum_{0.0};
};

} // namespace sauti::dsp
