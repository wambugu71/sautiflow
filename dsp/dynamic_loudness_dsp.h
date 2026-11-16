#pragma once

#include <cmath>
#include <cstdint>
#include <algorithm>
#include <array>
#include <atomic>
#include "denormals.h"
#include "simd_math.h"
#include "cytomic_svf_dsp.h"

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
        enabled_.store(enabled, std::memory_order_release);
        if (!enabled) {
            reset();
        }
    }

    bool isEnabled() const { return enabled_.load(std::memory_order_relaxed); }

    void setParams(float ref_level_db,
                   float max_bass_boost_db,
                   float max_treble_boost_db,
                   float bass_freq_hz,
                   float treble_freq_hz) {
        ref_level_db_.store(clampf(ref_level_db, -60.0f, 12.0f), std::memory_order_release);
        max_bass_boost_db_.store(clampf(max_bass_boost_db, 0.0f, 24.0f), std::memory_order_release);
        max_treble_boost_db_.store(clampf(max_treble_boost_db, 0.0f, 18.0f), std::memory_order_release);
        bass_freq_hz_.store(clampf(bass_freq_hz, 20.0f, 500.0f), std::memory_order_release);
        treble_freq_hz_.store(clampf(treble_freq_hz, 2000.0f, 20000.0f), std::memory_order_release);
    }

    void getParams(float *out_ref_level_db,
                   float *out_max_bass_boost_db,
                   float *out_max_treble_boost_db,
                   float *out_bass_freq_hz,
                   float *out_treble_freq_hz) const {
        if (out_ref_level_db) *out_ref_level_db = ref_level_db_.load(std::memory_order_relaxed);
        if (out_max_bass_boost_db) *out_max_bass_boost_db = max_bass_boost_db_.load(std::memory_order_relaxed);
        if (out_max_treble_boost_db) *out_max_treble_boost_db = max_treble_boost_db_.load(std::memory_order_relaxed);
        if (out_bass_freq_hz) *out_bass_freq_hz = bass_freq_hz_.load(std::memory_order_relaxed);
        if (out_treble_freq_hz) *out_treble_freq_hz = treble_freq_hz_.load(std::memory_order_relaxed);
    }

    // Reports the currently applied real-time compensation gain
    void getCurrentBoost(float *out_bass_boost_db, float *out_treble_boost_db) const {
        if (out_bass_boost_db) *out_bass_boost_db = current_bass_gain_db_;
        if (out_treble_boost_db) *out_treble_boost_db = current_treble_gain_db_;
    }

    void reset() {
        bass_svf_.reset();
        treble_svf_.reset();
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
        const float max_bass = max_bass_boost_db_.load(std::memory_order_relaxed);
        const float max_treble = max_treble_boost_db_.load(std::memory_order_relaxed);
        const float ref_level = ref_level_db_.load(std::memory_order_relaxed);
        const float attenuation_db = std::max(0.0f, ref_level - current_vol_db);
        target_bass_gain_db_ = std::min(max_bass, attenuation_db * 0.26f);
        target_treble_gain_db_ = std::min(max_treble, attenuation_db * 0.12f);

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

            // If boost is virtually zero, reset and bypass this sub-block
            const bool is_flat = (current_bass_gain_db_ < 0.02f) && (current_treble_gain_db_ < 0.02f);
            if (is_flat) {
                bass_svf_.reset();
                treble_svf_.reset();
                ptr += sub_frames * ch;
                frames_remaining -= sub_frames;
                continue;
            }

            // Process sub-block samples via 64-bit Cytomic TPT SVF
            bass_svf_.process(ptr, static_cast<uint32_t>(sub_frames), channels);
            treble_svf_.process(ptr, static_cast<uint32_t>(sub_frames), channels);
            ptr += sub_frames * ch;

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

        const float max_bass = max_bass_boost_db_.load(std::memory_order_relaxed);
        const float max_treble = max_treble_boost_db_.load(std::memory_order_relaxed);
        const float ref_level = ref_level_db_.load(std::memory_order_relaxed);
        const float attenuation_db = std::max(0.0f, ref_level - current_vol_db);
        target_bass_gain_db_ = std::min(max_bass, attenuation_db * 0.26f);
        target_treble_gain_db_ = std::min(max_treble, attenuation_db * 0.12f);

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
            if (is_flat) {
                bass_svf_.reset();
                treble_svf_.reset();
                ptr += sub_frames * ch;
                frames_remaining -= sub_frames;
                continue;
            }

            bass_svf_.process(ptr, static_cast<uint32_t>(sub_frames), channels);
            treble_svf_.process(ptr, static_cast<uint32_t>(sub_frames), channels);
            ptr += sub_frames * ch;

            frames_remaining -= sub_frames;
        }
    }

private:
    void recalculateCoefficients(float bass_gain_db, float treble_gain_db) {
        const double bass_fc = static_cast<double>(bass_freq_hz_.load(std::memory_order_relaxed));
        const double treble_fc = static_cast<double>(treble_freq_hz_.load(std::memory_order_relaxed));
        bass_svf_.setParameters(CytomicSVF::FilterType::LowShelf, static_cast<double>(sample_rate_),
                                bass_fc, static_cast<double>(bass_gain_db), 0.70710678);
        treble_svf_.setParameters(CytomicSVF::FilterType::HighShelf, static_cast<double>(sample_rate_),
                                  treble_fc, static_cast<double>(treble_gain_db), 0.70710678);
    }

    std::atomic<bool> enabled_{false};
    bool initialized_ = false;
    float sample_rate_ = 48000.0f;
    float smoothing_coeff_ = 0.001f;

    // Controls
    std::atomic<float> ref_level_db_{0.0f};           // Flat reference volume level (0 dB)
    std::atomic<float> max_bass_boost_db_{9.0f};      // Max bass shelf lift
    std::atomic<float> max_treble_boost_db_{4.5f};    // Max treble shelf lift
    std::atomic<float> bass_freq_hz_{90.0f};          // Bass corner frequency
    std::atomic<float> treble_freq_hz_{9000.0f};      // Treble corner frequency

    // Real-time tracking state
    float current_bass_gain_db_ = 0.0f;
    float current_treble_gain_db_ = 0.0f;
    float target_bass_gain_db_ = 0.0f;
    float target_treble_gain_db_ = 0.0f;

    // 64-bit Cytomic TPT SVF filter stages (with Nyquist de-cramping on HighShelf)
    CytomicSVF bass_svf_;
    CytomicSVF treble_svf_;
};

} // namespace sauti::dsp
