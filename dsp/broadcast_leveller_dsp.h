#pragma once

#include <cmath>
#include <cstdint>
#include <algorithm>
#include <vector>
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
// - Preserves musical macro-dynamics and punch (kick drums, transient peaks)
//   without compressor "pumping" or squashing.
// - Silence / Noise Floor Freeze: When audio level drops below `silence_gate_lufs`
//   (e.g. -45 LUFS during speech pauses), gain adjustment freezes immediately,
//   guaranteeing room noise, breath, and background hiss are never elevated.
// - Per-sample linear interpolation prevents any zipper noise or clicks.
// - Supports both 32-bit float and 64-bit double processing paths.
// =============================================================================
class BroadcastLevellerDSP {
public:
    BroadcastLevellerDSP() {
        setSampleRate(48000.0f);
        reset();
    }

    void setSampleRate(float sampleRate) {
        if (sampleRate <= 0.0f) sampleRate = 48000.0f;
        sample_rate_ = sampleRate;
        updateInternalFilters();
    }

    float getSampleRate() const { return sample_rate_; }

    void setEnabled(bool enabled) {
        if (enabled_ != enabled) {
            enabled_ = enabled;
            if (!enabled) {
                reset();
            }
        }
    }

    bool isEnabled() const { return enabled_; }

    void setParams(float target_lufs,
                   float max_rise_db_sec,
                   float max_fall_db_sec,
                   float max_boost_db,
                   float max_attenuation_db,
                   float silence_gate_lufs) {
        target_lufs_ = std::clamp(target_lufs, -36.0f, -6.0f);
        max_rise_db_sec_ = std::clamp(max_rise_db_sec, 0.1f, 6.0f);
        max_fall_db_sec_ = std::clamp(max_fall_db_sec, 0.1f, 12.0f);
        max_boost_db_ = std::clamp(max_boost_db, 0.0f, 18.0f);
        max_attenuation_db_ = std::clamp(max_attenuation_db, 0.0f, 24.0f);
        silence_gate_lufs_ = std::clamp(silence_gate_lufs, -70.0f, -24.0f);
    }

    void getParams(float *out_target_lufs,
                   float *out_max_rise_db_sec,
                   float *out_max_fall_db_sec,
                   float *out_max_boost_db,
                   float *out_max_attenuation_db,
                   float *out_silence_gate_lufs) const {
        if (out_target_lufs) *out_target_lufs = target_lufs_;
        if (out_max_rise_db_sec) *out_max_rise_db_sec = max_rise_db_sec_;
        if (out_max_fall_db_sec) *out_max_fall_db_sec = max_fall_db_sec_;
        if (out_max_boost_db) *out_max_boost_db = max_boost_db_;
        if (out_max_attenuation_db) *out_max_attenuation_db = max_attenuation_db_;
        if (out_silence_gate_lufs) *out_silence_gate_lufs = silence_gate_lufs_;
    }

    float getCurrentGainDb() const {
        return current_gain_db_;
    }

    void reset() {
        current_gain_db_ = 0.0f;
        target_gain_db_ = 0.0f;
        current_gain_linear_ = 1.0f;
        is_frozen_ = false;
        internal_sum_sq_ = 0.0;
        internal_sample_count_ = 0;
        internal_short_term_lufs_ = -100.0f;
    }

    // Process 32-bit float interleaved samples in-place.
    // external_short_term_lufs: Pass real-time short-term LUFS from BS.1770 meter (or < -90 to use internal measurement).
    void process(float *buffer, size_t frame_count, int channels, float external_short_term_lufs = -100.0f) {
        if (!enabled_ || buffer == nullptr || frame_count == 0 || channels <= 0) {
            return;
        }

        ScopedDenormalsDisable denormalGuard;

        // Determine effective short-term loudness
        float effective_lufs = external_short_term_lufs;
        if (effective_lufs < -90.0f) {
            effective_lufs = computeInternalLufs(buffer, frame_count, channels);
        }

        computeBlockGain(effective_lufs, frame_count);

        // Apply smooth linear ramp across frames
        const float start_gain = current_gain_linear_;
        const float end_gain = std::pow(10.0f, current_gain_db_ / 20.0f);
        const float gain_step = (end_gain - start_gain) / static_cast<float>(frame_count);

        float g = start_gain;
        for (size_t i = 0; i < frame_count; ++i) {
            for (int c = 0; c < channels; ++c) {
                buffer[i * (size_t)channels + c] *= g;
            }
            g += gain_step;
        }

        current_gain_linear_ = end_gain;
    }

    // Process 64-bit double interleaved samples in-place
    void process(double *buffer, size_t frame_count, int channels, float external_short_term_lufs = -100.0f) {
        if (!enabled_ || buffer == nullptr || frame_count == 0 || channels <= 0) {
            return;
        }

        ScopedDenormalsDisable denormalGuard;

        float effective_lufs = external_short_term_lufs;
        if (effective_lufs < -90.0f) {
            effective_lufs = computeInternalLufs(buffer, frame_count, channels);
        }

        computeBlockGain(effective_lufs, frame_count);

        const double start_gain = static_cast<double>(current_gain_linear_);
        const double end_gain = std::pow(10.0, static_cast<double>(current_gain_db_) / 20.0);
        const double gain_step = (end_gain - start_gain) / static_cast<double>(frame_count);

        double g = start_gain;
        for (size_t i = 0; i < frame_count; ++i) {
            for (int c = 0; c < channels; ++c) {
                buffer[i * (size_t)channels + c] *= g;
            }
            g += gain_step;
        }

        current_gain_linear_ = static_cast<float>(end_gain);
    }

private:
    void updateInternalFilters() {
        // 3-second short-term sliding window target samples
        internal_window_samples_ = static_cast<size_t>(sample_rate_ * 3.0f);
        if (internal_window_samples_ == 0) internal_window_samples_ = 48000 * 3;
    }

    template <typename T>
    float computeInternalLufs(const T *buf, size_t frame_count, int channels) {
        for (size_t i = 0; i < frame_count; ++i) {
            double frame_energy = 0.0;
            for (int c = 0; c < channels; ++c) {
                double s = static_cast<double>(buf[i * (size_t)channels + c]);
                frame_energy += s * s;
            }
            internal_sum_sq_ += frame_energy / static_cast<double>(channels);
            internal_sample_count_++;
        }

        if (internal_sample_count_ >= 2048) {
            double mean_pwr = internal_sum_sq_ / static_cast<double>(internal_sample_count_);
            if (mean_pwr > 1.0e-10) {
                // Approximate un-weighted short-term LUFS
                internal_short_term_lufs_ = static_cast<float>(-0.691 + 10.0 * std::log10(mean_pwr));
            } else {
                internal_short_term_lufs_ = -100.0f;
            }
            // Leak integrator slightly (decay over ~3s)
            internal_sum_sq_ *= 0.5;
            internal_sample_count_ /= 2;
        }
        return internal_short_term_lufs_;
    }

    void computeBlockGain(float effective_lufs, size_t frame_count) {
        // 1. Check Silence / Noise Gate Freeze
        if (effective_lufs <= silence_gate_lufs_) {
            is_frozen_ = true;
            // Freeze target at current level - do not ramp up into noise!
            target_gain_db_ = current_gain_db_;
            return;
        }

        is_frozen_ = false;

        // 2. Compute desired correction gain in dB
        float desired_gain_db = target_lufs_ - effective_lufs;
        // Clamp to configured boost & attenuation limits
        desired_gain_db = std::clamp(desired_gain_db, -max_attenuation_db_, max_boost_db_);
        target_gain_db_ = desired_gain_db;

        // 3. Slew rate limiter: step smoothly toward target
        const float dt = static_cast<float>(frame_count) / sample_rate_;

        if (target_gain_db_ > current_gain_db_) {
            const float max_rise = max_rise_db_sec_ * dt;
            current_gain_db_ = std::min(target_gain_db_, current_gain_db_ + max_rise);
        } else if (target_gain_db_ < current_gain_db_) {
            const float max_fall = max_fall_db_sec_ * dt;
            current_gain_db_ = std::max(target_gain_db_, current_gain_db_ - max_fall);
        }
    }

    bool enabled_ = false;
    float sample_rate_ = 48000.0f;

    // Controls
    float target_lufs_ = -16.0f;          // Target broadcast / streaming level
    float max_rise_db_sec_ = 0.75f;       // Upward slew rate (0.75 dB/sec = transparent)
    float max_fall_db_sec_ = 1.50f;       // Downward slew rate (1.5 dB/sec)
    float max_boost_db_ = 9.0f;           // Max permissible upward gain
    float max_attenuation_db_ = 12.0f;    // Max permissible downward attenuation
    float silence_gate_lufs_ = -45.0f;    // Level below which gain freezes

    // Real-time state
    float current_gain_db_ = 0.0f;
    float target_gain_db_ = 0.0f;
    float current_gain_linear_ = 1.0f;
    bool is_frozen_ = false;

    // Fallback internal detector state
    size_t internal_window_samples_ = 48000 * 3;
    double internal_sum_sq_ = 0.0;
    size_t internal_sample_count_ = 0;
    float internal_short_term_lufs_ = -100.0f;
};

} // namespace sauti::dsp
