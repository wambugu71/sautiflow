#pragma once

#include <cmath>
#include <cstdint>
#include <algorithm>
#include <vector>
#include <atomic>
#include "oversampler.h"
#include "simd_math.h"

namespace sauti::dsp {

// =============================================================================
// MasterLimiterDSP: True Lookahead Brickwall Peak Limiter with 4x Oversampled
// True-Peak Detection, Sliding-Window Lookahead Gain Ramp, and Single-Pole Release
// =============================================================================
class MasterLimiterDSP {
public:
    MasterLimiterDSP() {
        setSampleRate(48000.0f);
        reset();
    }

    void setSampleRate(float sampleRate) {
        if (sampleRate <= 0.0f) sampleRate = 48000.0f;
        if (std::abs(sample_rate_ - sampleRate) < 0.1f && initialized_) return;
        sample_rate_ = sampleRate;
        smoothing_coeff_ = 1.0f - std::exp(-1.0f / (0.030f * sample_rate_)); // 30ms parameter smoothing
        updateTimeConstants();
        initialized_ = true;
    }

    void setEnabled(bool enabled) {
        enabled_.store(enabled, std::memory_order_release);
        if (!enabled) {
            reset();
        }
    }

    bool isEnabled() const { return enabled_.load(std::memory_order_relaxed); }

    // Ceiling in dBFS (e.g. -0.1 dB to prevent inter-sample true-peak DAC overs)
    void setCeilingDb(float ceilingDb) {
        ceiling_db_ = std::clamp(ceilingDb, -12.0f, 0.0f);
        target_ceiling_linear_.store(std::pow(10.0f, ceiling_db_ / 20.0f), std::memory_order_release);
    }

    float getCeilingDb() const { return ceiling_db_; }

    // Master Output Gain in dB (-24.0 dB to +12.0 dB)
    void setOutputGainDb(float gainDb) {
        output_gain_db_ = std::clamp(gainDb, -24.0f, 12.0f);
        target_output_gain_linear_.store(std::pow(10.0f, output_gain_db_ / 20.0f), std::memory_order_release);
    }

    float getOutputGainDb() const { return output_gain_db_; }

    // Release time in milliseconds (typically 5 ms to 1000 ms, default 60 ms)
    void setReleaseMs(float releaseMs) {
        release_ms_.store(std::clamp(releaseMs, 5.0f, 1000.0f), std::memory_order_relaxed);
        updateReleaseCoeff();
    }

    float getReleaseMs() const { return release_ms_.load(std::memory_order_relaxed); }

    size_t getLatencySamples() const { return lookahead_samples_; }

    void reset() {
        filter1_.reset();
        filter2_.reset();
        filter1_64_.reset();
        filter2_64_.reset();
        std::fill(audio_buf_l_.begin(), audio_buf_l_.end(), 0.0f);
        std::fill(audio_buf_r_.begin(), audio_buf_r_.end(), 0.0f);
        std::fill(audio_buf_l64_.begin(), audio_buf_l64_.end(), 0.0);
        std::fill(audio_buf_r64_.begin(), audio_buf_r64_.end(), 0.0);
        delay_pos_ = 0;
        std::fill(lookahead_gain_.begin(), lookahead_gain_.end(), 1.0f);
        current_gain_.store(1.0f, std::memory_order_relaxed);
        current_output_gain_linear_ = target_output_gain_linear_.load(std::memory_order_relaxed);
        current_ceiling_linear_ = target_ceiling_linear_.load(std::memory_order_relaxed);
    }

    float getCurrentGainReductionDb() const {
        const float g = current_gain_.load(std::memory_order_relaxed);
        if (g >= 0.999f) return 0.0f;
        return 20.0f * std::log10(std::max(g, 0.0001f));
    }

    float getCurrentLinearGain() const {
        return current_gain_.load(std::memory_order_relaxed);
    }

    // Process interleaved stereo samples (32-bit float): [L0, R0, L1, R1, ...]
    void process(float* interleaved_samples, uint32_t frame_count) {
        if (!enabled_.load(std::memory_order_relaxed) || frame_count == 0 || !interleaved_samples) return;

        const float target_ceiling = target_ceiling_linear_.load(std::memory_order_relaxed);
        const float target_out_gain = target_output_gain_linear_.load(std::memory_order_relaxed);
        const float rel_coeff = release_coeff_.load(std::memory_order_relaxed);
        const float inv_ramp = (ramp_samples_ > 1) ? (1.0f / static_cast<float>(ramp_samples_ - 1)) : 1.0f;
        float cur_gain = current_gain_.load(std::memory_order_relaxed);

        for (uint32_t i = 0; i < frame_count; i++) {
            current_output_gain_linear_ += smoothing_coeff_ * (target_out_gain - current_output_gain_linear_);
            current_ceiling_linear_     += smoothing_coeff_ * (target_ceiling - current_ceiling_linear_);

            const float in_l = interleaved_samples[2 * i];
            const float in_r = interleaved_samples[2 * i + 1];

            // 1. 4x Oversampled True Peak Detection across both channels
            float l0, r0, l1, r1;
            filter1_.upsample2xFrame(in_l, in_r, l0, r0, l1, r1);
            float l00, r00, l01, r01;
            filter2_.upsample2xFrame(l0, r0, l00, r00, l01, r01);
            float l10, r10, l11, r11;
            filter2_.upsample2xFrame(l1, r1, l10, r10, l11, r11);

            const SimdFloat4 v_sub0(std::abs(l00), std::abs(r00), std::abs(l01), std::abs(r01));
            const SimdFloat4 v_sub1(std::abs(l10), std::abs(r10), std::abs(l11), std::abs(r11));
            const SimdFloat4 v_max_sub = SimdFloat4::max(v_sub0, v_sub1);
            const float peak_sub = std::max(std::max(v_max_sub.get(0), v_max_sub.get(1)),
                                            std::max(v_max_sub.get(2), v_max_sub.get(3)));
            const float true_peak = std::max(peak_sub, std::max(std::abs(in_l), std::abs(in_r)));

            // 2. Read delayed sample from lookahead audio ring buffer
            const float delayed_l = audio_buf_l_[delay_pos_];
            const float delayed_r = audio_buf_r_[delay_pos_];
            audio_buf_l_[delay_pos_] = in_l;
            audio_buf_r_[delay_pos_] = in_r;
            delay_pos_ = (delay_pos_ + 1) % lookahead_samples_;

            // 3. Compute required gain reduction for true-peak
            float target_gain = 1.0f;
            if (true_peak > current_ceiling_linear_) {
                target_gain = current_ceiling_linear_ / true_peak;
            }

            // 4. Update sliding-window lookahead ramp
            if (target_gain < 1.0f && ramp_samples_ > 1) {
                const float diff = 1.0f - target_gain;
                for (size_t k = 0; k < ramp_samples_; ++k) {
                    const float ramp_k = target_gain + diff * static_cast<float>(ramp_samples_ - 1 - k) * inv_ramp;
                    if (ramp_k < lookahead_gain_[k]) {
                        lookahead_gain_[k] = ramp_k;
                    }
                }
            }

            // 5. Read target gain scheduled for sample exiting now
            const float scheduled_gain = lookahead_gain_[0];

            for (size_t k = 0; k < ramp_samples_ - 1; ++k) {
                lookahead_gain_[k] = lookahead_gain_[k + 1];
            }
            lookahead_gain_[ramp_samples_ - 1] = 1.0f;

            // Attack is governed by the smooth lookahead ramp; release via 1-pole filter
            if (scheduled_gain < cur_gain) {
                cur_gain = scheduled_gain;
            } else {
                cur_gain += rel_coeff * (scheduled_gain - cur_gain);
            }

            // 6. Vectorized output scaling and safety ceiling clamping
            const float total_gain = cur_gain * current_output_gain_linear_;
            const SimdFloat4 v_delayed(delayed_l, delayed_r, 0.0f, 0.0f);
            const SimdFloat4 v_scaled = v_delayed * SimdFloat4(total_gain);
            const SimdFloat4 v_ceil(current_ceiling_linear_);
            const SimdFloat4 v_neg_ceil(-current_ceiling_linear_);
            const SimdFloat4 v_clamped = SimdFloat4::min(v_ceil, SimdFloat4::max(v_neg_ceil, v_scaled));

            interleaved_samples[2 * i]     = v_clamped.get(0);
            interleaved_samples[2 * i + 1] = v_clamped.get(1);
        }

        current_gain_.store(cur_gain, std::memory_order_relaxed);
    }

    // Process interleaved stereo samples (64-bit double): [L0, R0, L1, R1, ...]
    void process(double* interleaved_samples, uint32_t frame_count) {
        if (!enabled_.load(std::memory_order_relaxed) || frame_count == 0 || !interleaved_samples) return;

        const float target_ceiling = target_ceiling_linear_.load(std::memory_order_relaxed);
        const float target_out_gain = target_output_gain_linear_.load(std::memory_order_relaxed);
        const float rel_coeff = release_coeff_.load(std::memory_order_relaxed);
        const float inv_ramp = (ramp_samples_ > 1) ? (1.0f / static_cast<float>(ramp_samples_ - 1)) : 1.0f;
        float cur_gain = current_gain_.load(std::memory_order_relaxed);

        for (uint32_t i = 0; i < frame_count; i++) {
            current_output_gain_linear_ += smoothing_coeff_ * (target_out_gain - current_output_gain_linear_);
            current_ceiling_linear_     += smoothing_coeff_ * (target_ceiling - current_ceiling_linear_);

            const double in_l = interleaved_samples[2 * i];
            const double in_r = interleaved_samples[2 * i + 1];

            // 1. 4x Oversampled True Peak Detection in 64-bit double
            double l0, r0, l1, r1;
            filter1_64_.upsample2xFrame(in_l, in_r, l0, r0, l1, r1);
            double l00, r00, l01, r01;
            filter2_64_.upsample2xFrame(l0, r0, l00, r00, l01, r01);
            double l10, r10, l11, r11;
            filter2_64_.upsample2xFrame(l1, r1, l10, r10, l11, r11);

            const SimdDouble2 v_sub0(std::abs(l00), std::abs(r00));
            const SimdDouble2 v_sub1(std::abs(l01), std::abs(r01));
            const SimdDouble2 v_sub2(std::abs(l10), std::abs(r10));
            const SimdDouble2 v_sub3(std::abs(l11), std::abs(r11));
            const SimdDouble2 m01 = SimdDouble2::max(v_sub0, v_sub1);
            const SimdDouble2 m23 = SimdDouble2::max(v_sub2, v_sub3);
            const SimdDouble2 m_all = SimdDouble2::max(m01, m23);
            const double peak_sub = std::max(m_all.get(0), m_all.get(1));
            const double true_peak = std::max(peak_sub, std::max(std::abs(in_l), std::abs(in_r)));

            // 2. Read delayed sample from lookahead ring buffer
            const double delayed_l = audio_buf_l64_[delay_pos_];
            const double delayed_r = audio_buf_r64_[delay_pos_];
            audio_buf_l64_[delay_pos_] = in_l;
            audio_buf_r64_[delay_pos_] = in_r;
            delay_pos_ = (delay_pos_ + 1) % lookahead_samples_;

            // 3. Compute required gain reduction for true-peak
            float target_gain = 1.0f;
            if (true_peak > static_cast<double>(current_ceiling_linear_)) {
                target_gain = current_ceiling_linear_ / static_cast<float>(true_peak);
            }

            // 4. Update sliding-window lookahead ramp
            if (target_gain < 1.0f && ramp_samples_ > 1) {
                const float diff = 1.0f - target_gain;
                for (size_t k = 0; k < ramp_samples_; ++k) {
                    const float ramp_k = target_gain + diff * static_cast<float>(ramp_samples_ - 1 - k) * inv_ramp;
                    if (ramp_k < lookahead_gain_[k]) {
                        lookahead_gain_[k] = ramp_k;
                    }
                }
            }

            // 5. Read target gain scheduled for sample exiting now
            const float scheduled_gain = lookahead_gain_[0];

            for (size_t k = 0; k < ramp_samples_ - 1; ++k) {
                lookahead_gain_[k] = lookahead_gain_[k + 1];
            }
            lookahead_gain_[ramp_samples_ - 1] = 1.0f;

            if (scheduled_gain < cur_gain) {
                cur_gain = scheduled_gain;
            } else {
                cur_gain += rel_coeff * (scheduled_gain - cur_gain);
            }

            // 6. Vectorized gain scaling and safety ceiling clamping in 64-bit double
            const double total_gain = static_cast<double>(cur_gain) * static_cast<double>(current_output_gain_linear_);
            const SimdDouble2 v_delayed(delayed_l, delayed_r);
            const SimdDouble2 v_scaled = v_delayed * SimdDouble2(total_gain);
            const SimdDouble2 v_ceil(static_cast<double>(current_ceiling_linear_));
            const SimdDouble2 v_neg_ceil(-static_cast<double>(current_ceiling_linear_));
            const SimdDouble2 v_clamped = SimdDouble2::min(v_ceil, SimdDouble2::max(v_neg_ceil, v_scaled));

            interleaved_samples[2 * i]     = v_clamped.get(0);
            interleaved_samples[2 * i + 1] = v_clamped.get(1);
        }

        current_gain_.store(cur_gain, std::memory_order_relaxed);
    }

private:
    std::atomic<bool> enabled_{false};
    bool initialized_ = false;
    float sample_rate_ = 48000.0f;

    float ceiling_db_ = -0.1f;
    std::atomic<float> target_ceiling_linear_{0.988553f}; // ~ -0.1 dBFS
    float current_ceiling_linear_ = 0.988553f;

    float output_gain_db_ = 0.0f;
    std::atomic<float> target_output_gain_linear_{1.0f};
    float current_output_gain_linear_ = 1.0f;

    float smoothing_coeff_ = 0.002f;

    std::atomic<float> release_ms_{60.0f};
    std::atomic<float> release_coeff_{0.001f};

    std::atomic<float> current_gain_{1.0f};

    // 4x polyphase FIR upsamplers for true peak detection
    HalfBandFilter2xT<float> filter1_;
    HalfBandFilter2xT<float> filter2_;
    HalfBandFilter2xT<double> filter1_64_;
    HalfBandFilter2xT<double> filter2_64_;
    static constexpr size_t OVERSAMPLER_DELAY = 20;

    // Lookahead audio ring buffer (~1.5 ms lookahead)
    size_t lookahead_samples_ = 72;
    size_t ramp_samples_ = 52;
    std::vector<float> audio_buf_l_;
    std::vector<float> audio_buf_r_;
    std::vector<double> audio_buf_l64_;
    std::vector<double> audio_buf_r64_;
    size_t delay_pos_ = 0;

    // Sliding-window lookahead scheduled gain buffer
    std::vector<float> lookahead_gain_;

    void updateReleaseCoeff() {
        const float r_ms = release_ms_.load(std::memory_order_relaxed);
        release_coeff_.store(1.0f - std::exp(-1.0f / (sample_rate_ * (r_ms * 0.001f))), std::memory_order_relaxed);
    }

    void updateTimeConstants() {
        lookahead_samples_ = std::max(static_cast<size_t>(sample_rate_ * 0.0015f), static_cast<size_t>(24));
        ramp_samples_ = (lookahead_samples_ > OVERSAMPLER_DELAY) ? (lookahead_samples_ - OVERSAMPLER_DELAY) : 4;
        audio_buf_l_.assign(lookahead_samples_, 0.0f);
        audio_buf_r_.assign(lookahead_samples_, 0.0f);
        audio_buf_l64_.assign(lookahead_samples_, 0.0);
        audio_buf_r64_.assign(lookahead_samples_, 0.0);
        lookahead_gain_.assign(ramp_samples_, 1.0f);
        delay_pos_ = 0;
        updateReleaseCoeff();
    }
};

} // namespace sauti::dsp
