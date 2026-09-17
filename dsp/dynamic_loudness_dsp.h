#pragma once

#include <cmath>
#include <cstdint>
#include <algorithm>
#include <array>
#include "denormals.h"
#include "simd_math.h"

namespace sauti::dsp {

inline float clampf(float v, float lo, float hi) {
    return std::clamp(v, lo, hi);
}

// =============================================================================
// DynamicLoudnessDSP: ISO 226:2003 / Fletcher-Munson Equal-Loudness Contour Engine
//
// Features:
// - Acoustically calibrated low-shelf (80-100 Hz) and high-shelf (8-10 kHz)
//   filters that dynamically boost bass and treble as master listening volume
//   is reduced below reference.
// - At reference level (e.g. 0.0 dBFS / unity), response is completely flat (0 dB boost).
// - Sub-block parameter smoothing (30ms tau) and Transposed Direct Form II (TDF2)
//   double-precision state buffers ensure zero clicks, zippering, or phase pops
//   during rapid volume slider adjustments.
// - Full real-time safety: allocation-free processing, denormal flushing, and
//   denormal-safe biquad state reset.
// =============================================================================
class DynamicLoudnessDSP {
public:
    static constexpr size_t MAX_CHANNELS = 16;
    static constexpr size_t SUB_BLOCK_SIZE = 32;

    DynamicLoudnessDSP() {
        setSampleRate(48000.0f);
        reset();
    }

    void setSampleRate(float sampleRate) {
        if (sampleRate <= 0.0f) sampleRate = 48000.0f;
        if (std::abs(sample_rate_ - sampleRate) < 0.1f && initialized_) return;
        sample_rate_ = sampleRate;
        // 30ms time constant for volume & contour tracking
        smoothing_coeff_ = 1.0f - std::exp(-1.0f / (0.030f * sample_rate_));
        initialized_ = true;
        recalculateCoefficients(current_bass_gain_db_, current_treble_gain_db_);
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

    void setParams(float ref_level_db,
                   float max_bass_boost_db,
                   float max_treble_boost_db,
                   float bass_freq_hz,
                   float treble_freq_hz) {
        ref_level_db_ = clampf(ref_level_db, -60.0f, 12.0f);
        max_bass_boost_db_ = clampf(max_bass_boost_db, 0.0f, 24.0f);
        max_treble_boost_db_ = clampf(max_treble_boost_db, 0.0f, 18.0f);
        bass_freq_hz_ = clampf(bass_freq_hz, 20.0f, 500.0f);
        treble_freq_hz_ = clampf(treble_freq_hz, 2000.0f, 20000.0f);
    }

    void getParams(float *out_ref_level_db,
                   float *out_max_bass_boost_db,
                   float *out_max_treble_boost_db,
                   float *out_bass_freq_hz,
                   float *out_treble_freq_hz) const {
        if (out_ref_level_db) *out_ref_level_db = ref_level_db_;
        if (out_max_bass_boost_db) *out_max_bass_boost_db = max_bass_boost_db_;
        if (out_max_treble_boost_db) *out_max_treble_boost_db = max_treble_boost_db_;
        if (out_bass_freq_hz) *out_bass_freq_hz = bass_freq_hz_;
        if (out_treble_freq_hz) *out_treble_freq_hz = treble_freq_hz_;
    }

    // Reports the currently applied real-time compensation gain
    void getCurrentBoost(float *out_bass_boost_db, float *out_treble_boost_db) const {
        if (out_bass_boost_db) *out_bass_boost_db = current_bass_gain_db_;
        if (out_treble_boost_db) *out_treble_boost_db = current_treble_gain_db_;
    }

    void reset() {
        for (size_t c = 0; c < MAX_CHANNELS; ++c) {
            s1_bass_[c] = 0.0;
            s2_bass_[c] = 0.0;
            s1_treble_[c] = 0.0;
            s2_treble_[c] = 0.0;
        }
        current_bass_gain_db_ = 0.0f;
        current_treble_gain_db_ = 0.0f;
        target_bass_gain_db_ = 0.0f;
        target_treble_gain_db_ = 0.0f;
        recalculateCoefficients(0.0f, 0.0f);
    }

    // Process 32-bit float interleaved samples in-place.
    // current_volume_linear: master fader linear gain (e.g. 1.0 = 0 dB, 0.1 = -20 dB).
    void process(float *buffer, size_t frame_count, int channels, float current_volume_linear) {
        if (!enabled_ || buffer == nullptr || frame_count == 0 || channels <= 0) {
            return;
        }

        const size_t ch = std::min(static_cast<size_t>(channels), MAX_CHANNELS);
        ScopedDenormalsDisable denormalGuard;

        // Calculate target volume in dB
        const float vol_clamped = std::max(current_volume_linear, 1.0e-4f); // floor at -80 dB
        const float current_vol_db = 20.0f * std::log10(vol_clamped);

        // ISO 226 equal-loudness slopes:
        // When listening below reference (e.g. 0 dB), bass drops faster than mids.
        // Bass sensitivity slope ~0.26 dB boost per dB of attenuation below reference.
        // Treble sensitivity slope ~0.12 dB boost per dB of attenuation below reference.
        const float attenuation_db = std::max(0.0f, ref_level_db_ - current_vol_db);
        target_bass_gain_db_ = std::min(max_bass_boost_db_, attenuation_db * 0.26f);
        target_treble_gain_db_ = std::min(max_treble_boost_db_, attenuation_db * 0.12f);

        // Sub-block processing for click-free coefficient updating
        size_t frames_remaining = frame_count;
        float *ptr = buffer;

        while (frames_remaining > 0) {
            const size_t sub_frames = std::min(frames_remaining, SUB_BLOCK_SIZE);

            // Smooth current gains toward target
            const float diff_bass = target_bass_gain_db_ - current_bass_gain_db_;
            const float diff_treble = target_treble_gain_db_ - current_treble_gain_db_;

            if (std::abs(diff_bass) > 1.0e-4f || std::abs(diff_treble) > 1.0e-4f) {
                current_bass_gain_db_ += smoothing_coeff_ * static_cast<float>(sub_frames) * diff_bass;
                current_treble_gain_db_ += smoothing_coeff_ * static_cast<float>(sub_frames) * diff_treble;
                recalculateCoefficients(current_bass_gain_db_, current_treble_gain_db_);
            }

            // If boost is virtually zero and filters are cleared, bypass this sub-block
            const bool is_flat = (current_bass_gain_db_ < 0.02f) && (current_treble_gain_db_ < 0.02f);
            if (is_flat && statesAreZero(ch)) {
                ptr += sub_frames * ch;
                frames_remaining -= sub_frames;
                continue;
            }

            // Process sub-block samples
            for (size_t f = 0; f < sub_frames; ++f) {
                for (size_t c = 0; c < ch; ++c) {
                    double sample = static_cast<double>(ptr[c]);

                    // 1. Low Shelf (Bass) TDF2
                    double out_bass = b0_bass_ * sample + s1_bass_[c];
                    s1_bass_[c] = b1_bass_ * sample - a1_bass_ * out_bass + s2_bass_[c];
                    s2_bass_[c] = b2_bass_ * sample - a2_bass_ * out_bass;

                    // 2. High Shelf (Treble) TDF2
                    double out_treble = b0_treble_ * out_bass + s1_treble_[c];
                    s1_treble_[c] = b1_treble_ * out_bass - a1_treble_ * out_treble + s2_treble_[c];
                    s2_treble_[c] = b2_treble_ * out_bass - a2_treble_ * out_treble;

                    ptr[c] = static_cast<float>(out_treble);
                }
                ptr += ch;
            }

            frames_remaining -= sub_frames;
        }
    }

    // Process 64-bit double interleaved samples in-place
    void process(double *buffer, size_t frame_count, int channels, double current_volume_linear) {
        if (!enabled_ || buffer == nullptr || frame_count == 0 || channels <= 0) {
            return;
        }

        const size_t ch = std::min(static_cast<size_t>(channels), MAX_CHANNELS);
        ScopedDenormalsDisable denormalGuard;

        const float vol_clamped = static_cast<float>(std::max(current_volume_linear, 1.0e-4));
        const float current_vol_db = 20.0f * std::log10(vol_clamped);

        const float attenuation_db = std::max(0.0f, ref_level_db_ - current_vol_db);
        target_bass_gain_db_ = std::min(max_bass_boost_db_, attenuation_db * 0.26f);
        target_treble_gain_db_ = std::min(max_treble_boost_db_, attenuation_db * 0.12f);

        size_t frames_remaining = frame_count;
        double *ptr = buffer;

        while (frames_remaining > 0) {
            const size_t sub_frames = std::min(frames_remaining, SUB_BLOCK_SIZE);

            const float diff_bass = target_bass_gain_db_ - current_bass_gain_db_;
            const float diff_treble = target_treble_gain_db_ - current_treble_gain_db_;

            if (std::abs(diff_bass) > 1.0e-4f || std::abs(diff_treble) > 1.0e-4f) {
                current_bass_gain_db_ += smoothing_coeff_ * static_cast<float>(sub_frames) * diff_bass;
                current_treble_gain_db_ += smoothing_coeff_ * static_cast<float>(sub_frames) * diff_treble;
                recalculateCoefficients(current_bass_gain_db_, current_treble_gain_db_);
            }

            const bool is_flat = (current_bass_gain_db_ < 0.02f) && (current_treble_gain_db_ < 0.02f);
            if (is_flat && statesAreZero(ch)) {
                ptr += sub_frames * ch;
                frames_remaining -= sub_frames;
                continue;
            }

            for (size_t f = 0; f < sub_frames; ++f) {
                for (size_t c = 0; c < ch; ++c) {
                    double sample = ptr[c];

                    double out_bass = b0_bass_ * sample + s1_bass_[c];
                    s1_bass_[c] = b1_bass_ * sample - a1_bass_ * out_bass + s2_bass_[c];
                    s2_bass_[c] = b2_bass_ * sample - a2_bass_ * out_bass;

                    double out_treble = b0_treble_ * out_bass + s1_treble_[c];
                    s1_treble_[c] = b1_treble_ * out_bass - a1_treble_ * out_treble + s2_treble_[c];
                    s2_treble_[c] = b2_treble_ * out_bass - a2_treble_ * out_treble;

                    ptr[c] = out_treble;
                }
                ptr += ch;
            }

            frames_remaining -= sub_frames;
        }
    }

private:
    bool statesAreZero(size_t ch) const {
        for (size_t c = 0; c < ch; ++c) {
            if (std::abs(s1_bass_[c]) > 1.0e-12 || std::abs(s2_bass_[c]) > 1.0e-12 ||
                std::abs(s1_treble_[c]) > 1.0e-12 || std::abs(s2_treble_[c]) > 1.0e-12) {
                return false;
            }
        }
        return true;
    }

    void recalculateCoefficients(float bass_gain_db, float treble_gain_db) {
        constexpr double PI = 3.14159265358979323846;

        // 1. Low Shelf (Cookbook formula)
        {
            const double A = std::pow(10.0, static_cast<double>(bass_gain_db) / 40.0);
            const double w0 = 2.0 * PI * static_cast<double>(bass_freq_hz_) / static_cast<double>(sample_rate_);
            const double cosw0 = std::cos(w0);
            const double sinw0 = std::sin(w0);
            // S = 1.0 shelf slope
            const double alpha = 0.5 * sinw0 * std::sqrt((A + 1.0 / A) * (1.0 - 1.0) + 2.0); // = sinw0 * sqrt(2)/2
            const double two_sqrtA_alpha = 2.0 * std::sqrt(A) * alpha;

            const double a0 = (A + 1.0) + (A - 1.0) * cosw0 + two_sqrtA_alpha;
            const double inv_a0 = (std::abs(a0) > 1.0e-12) ? (1.0 / a0) : 1.0;

            b0_bass_ = (A * ((A + 1.0) - (A - 1.0) * cosw0 + two_sqrtA_alpha)) * inv_a0;
            b1_bass_ = (2.0 * A * ((A - 1.0) - (A + 1.0) * cosw0)) * inv_a0;
            b2_bass_ = (A * ((A + 1.0) - (A - 1.0) * cosw0 - two_sqrtA_alpha)) * inv_a0;
            a1_bass_ = (-2.0 * ((A - 1.0) + (A + 1.0) * cosw0)) * inv_a0;
            a2_bass_ = ((A + 1.0) + (A - 1.0) * cosw0 - two_sqrtA_alpha) * inv_a0;
        }

        // 2. High Shelf (Cookbook formula)
        {
            const double A = std::pow(10.0, static_cast<double>(treble_gain_db) / 40.0);
            const double w0 = 2.0 * PI * static_cast<double>(treble_freq_hz_) / static_cast<double>(sample_rate_);
            const double cosw0 = std::cos(w0);
            const double sinw0 = std::sin(w0);
            const double alpha = 0.5 * sinw0 * std::sqrt((A + 1.0 / A) * (1.0 - 1.0) + 2.0);
            const double two_sqrtA_alpha = 2.0 * std::sqrt(A) * alpha;

            const double a0 = (A + 1.0) - (A - 1.0) * cosw0 + two_sqrtA_alpha;
            const double inv_a0 = (std::abs(a0) > 1.0e-12) ? (1.0 / a0) : 1.0;

            b0_treble_ = (A * ((A + 1.0) + (A - 1.0) * cosw0 + two_sqrtA_alpha)) * inv_a0;
            b1_treble_ = (-2.0 * A * ((A - 1.0) + (A + 1.0) * cosw0)) * inv_a0;
            b2_treble_ = (A * ((A + 1.0) - (A - 1.0) * cosw0 - two_sqrtA_alpha)) * inv_a0;
            a1_treble_ = (2.0 * ((A - 1.0) - (A + 1.0) * cosw0)) * inv_a0;
            a2_treble_ = ((A + 1.0) - (A - 1.0) * cosw0 - two_sqrtA_alpha) * inv_a0;
        }
    }

    bool enabled_ = false;
    bool initialized_ = false;
    float sample_rate_ = 48000.0f;
    float smoothing_coeff_ = 0.001f;

    // Controls
    float ref_level_db_ = 0.0f;           // Flat reference volume level (0 dB)
    float max_bass_boost_db_ = 9.0f;      // Max bass shelf lift
    float max_treble_boost_db_ = 4.5f;    // Max treble shelf lift
    float bass_freq_hz_ = 90.0f;          // Bass corner frequency
    float treble_freq_hz_ = 9000.0f;      // Treble corner frequency

    // Real-time tracking state
    float current_bass_gain_db_ = 0.0f;
    float current_treble_gain_db_ = 0.0f;
    float target_bass_gain_db_ = 0.0f;
    float target_treble_gain_db_ = 0.0f;

    // Filter coefficients
    double b0_bass_ = 1.0, b1_bass_ = 0.0, b2_bass_ = 0.0, a1_bass_ = 0.0, a2_bass_ = 0.0;
    double b0_treble_ = 1.0, b1_treble_ = 0.0, b2_treble_ = 0.0, a1_treble_ = 0.0, a2_treble_ = 0.0;

    // Filter states (TDF2 per channel)
    std::array<double, MAX_CHANNELS> s1_bass_{{0.0}};
    std::array<double, MAX_CHANNELS> s2_bass_{{0.0}};
    std::array<double, MAX_CHANNELS> s1_treble_{{0.0}};
    std::array<double, MAX_CHANNELS> s2_treble_{{0.0}};
};

} // namespace sauti::dsp
