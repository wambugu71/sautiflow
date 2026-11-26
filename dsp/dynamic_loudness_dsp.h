#pragma once

#include <algorithm>
#include <array>
#include <atomic>
#include <cmath>
#include <cstdint>

#include "cytomic_svf_dsp.h"
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
// - Exact discrete exponential sub-block parameter smoothing (30ms tau) and
//   64-bit Cytomic TPT SVF filters.
// - Live corner-frequency tracking even when listening volume is steady.
// - RT-safe lock-free parameter atomics and deferred state resets.
// =============================================================================
class DynamicLoudnessDSP {
public:
    static constexpr size_t MAX_CHANNELS = 16;
    static constexpr size_t SUB_BLOCK_SIZE = 32;

    DynamicLoudnessDSP() {
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
            reported_bass_boost_db_.store(0.0f, std::memory_order_relaxed);
            reported_treble_boost_db_.store(0.0f, std::memory_order_relaxed);
            reset_requested_.store(true, std::memory_order_release);
        } else if (!was_enabled) {
            reset_requested_.store(true, std::memory_order_release);
        }
    }

    bool isEnabled() const {
        return enabled_.load(std::memory_order_acquire);
    }

    void setParams(float ref_level_db,
                   float max_bass_boost_db,
                   float max_treble_boost_db,
                   float bass_freq_hz,
                   float treble_freq_hz) {
        if (!std::isfinite(ref_level_db)) ref_level_db = 0.0f;
        if (!std::isfinite(max_bass_boost_db)) max_bass_boost_db = 9.0f;
        if (!std::isfinite(max_treble_boost_db)) max_treble_boost_db = 4.5f;
        if (!std::isfinite(bass_freq_hz)) bass_freq_hz = 90.0f;
        if (!std::isfinite(treble_freq_hz)) treble_freq_hz = 9000.0f;

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

    // Reports the currently applied real-time compensation gain (thread-safe)
    void getCurrentBoost(float *out_bass_boost_db, float *out_treble_boost_db) const {
        const bool active = enabled_.load(std::memory_order_relaxed);
        if (out_bass_boost_db) {
            *out_bass_boost_db = active ? reported_bass_boost_db_.load(std::memory_order_relaxed) : 0.0f;
        }
        if (out_treble_boost_db) {
            *out_treble_boost_db = active ? reported_treble_boost_db_.load(std::memory_order_relaxed) : 0.0f;
        }
    }

    void reset() {
        reported_bass_boost_db_.store(0.0f, std::memory_order_relaxed);
        reported_treble_boost_db_.store(0.0f, std::memory_order_relaxed);
        reset_requested_.store(true, std::memory_order_release);
    }

    // Process 32-bit float interleaved samples in-place.
    // current_volume_linear: master fader linear gain (e.g. 1.0 = 0 dB, 0.1 = -20 dB).
    void process(float *buffer, size_t frame_count, int channels, float current_volume_linear) {
        processImpl<float>(buffer, frame_count, channels, current_volume_linear);
    }

    // Process 64-bit double interleaved samples in-place.
    void process(double *buffer, size_t frame_count, int channels, double current_volume_linear) {
        processImpl<double>(buffer, frame_count, channels, static_cast<float>(current_volume_linear));
    }

private:
    void applySampleRateInternal(float sampleRate) noexcept {
        active_sample_rate_ = sampleRate;
        target_sample_rate_.store(sampleRate, std::memory_order_relaxed);
        initialized_.store(true, std::memory_order_release);
        sub_block_alpha_ = 1.0f - std::exp(-static_cast<float>(SUB_BLOCK_SIZE) / (0.030f * active_sample_rate_));
    }

    void resetInternal() noexcept {
        bass_svf_.reset();
        treble_svf_.reset();
        current_bass_gain_db_ = 0.0f;
        current_treble_gain_db_ = 0.0f;
        target_bass_gain_db_ = 0.0f;
        target_treble_gain_db_ = 0.0f;
        active_bass_freq_hz_ = bass_freq_hz_.load(std::memory_order_relaxed);
        active_treble_freq_hz_ = treble_freq_hz_.load(std::memory_order_relaxed);
        reported_bass_boost_db_.store(0.0f, std::memory_order_relaxed);
        reported_treble_boost_db_.store(0.0f, std::memory_order_relaxed);
        recalculateCoefficients(0.0f, 0.0f, active_bass_freq_hz_, active_treble_freq_hz_);
    }

    void recalculateCoefficients(float bass_gain_db,
                                 float treble_gain_db,
                                 float bass_freq_hz,
                                 float treble_freq_hz) noexcept {
        const double sr = static_cast<double>(active_sample_rate_);
        bass_svf_.setParameters(CytomicSVF::FilterType::LowShelf, sr,
                                static_cast<double>(bass_freq_hz),
                                static_cast<double>(bass_gain_db), 0.70710678);
        treble_svf_.setParameters(CytomicSVF::FilterType::HighShelf, sr,
                                  static_cast<double>(treble_freq_hz),
                                  static_cast<double>(treble_gain_db), 0.70710678);
    }

    template <typename SampleT>
    void processImpl(SampleT *buffer, size_t frame_count, int channels, float current_volume_linear) {
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

        // Calculate target volume in dB
        const float vol_safe = std::isfinite(current_volume_linear) ? current_volume_linear : 1.0f;
        const float vol_clamped = std::max(vol_safe, 1.0e-4f); // floor at -80 dB
        const float current_vol_db = 20.0f * std::log10(vol_clamped);

        // ISO 226 equal-loudness slopes (~0.26 dB bass, ~0.12 dB treble per dB attenuation below reference)
        const float max_bass = max_bass_boost_db_.load(std::memory_order_relaxed);
        const float max_treble = max_treble_boost_db_.load(std::memory_order_relaxed);
        const float ref_level = ref_level_db_.load(std::memory_order_relaxed);
        const float attenuation_db = std::max(0.0f, ref_level - current_vol_db);
        target_bass_gain_db_ = std::min(max_bass, attenuation_db * 0.26f);
        target_treble_gain_db_ = std::min(max_treble, attenuation_db * 0.12f);

        const float bass_freq = bass_freq_hz_.load(std::memory_order_relaxed);
        const float treble_freq = treble_freq_hz_.load(std::memory_order_relaxed);
        const int ch = std::min(channels, static_cast<int>(CytomicSVF::kMaxChannels));

        size_t frames_remaining = frame_count;
        SampleT *ptr = buffer;

        while (frames_remaining > 0) {
            const size_t sub_frames = std::min(frames_remaining, SUB_BLOCK_SIZE);
            const float alpha = (sub_frames == SUB_BLOCK_SIZE)
                ? sub_block_alpha_
                : (1.0f - std::exp(-static_cast<float>(sub_frames) / (0.030f * active_sample_rate_)));

            const float diff_bass = target_bass_gain_db_ - current_bass_gain_db_;
            const float diff_treble = target_treble_gain_db_ - current_treble_gain_db_;
            const bool freq_changed =
                (std::abs(bass_freq - active_bass_freq_hz_) > 0.1f) ||
                (std::abs(treble_freq - active_treble_freq_hz_) > 0.1f);

            if (std::abs(diff_bass) > 1.0e-4f || std::abs(diff_treble) > 1.0e-4f || freq_changed) {
                current_bass_gain_db_ = (std::abs(diff_bass) > 1.0e-4f)
                    ? (current_bass_gain_db_ + alpha * diff_bass)
                    : target_bass_gain_db_;
                current_treble_gain_db_ = (std::abs(diff_treble) > 1.0e-4f)
                    ? (current_treble_gain_db_ + alpha * diff_treble)
                    : target_treble_gain_db_;
                active_bass_freq_hz_ = bass_freq;
                active_treble_freq_hz_ = treble_freq;
                recalculateCoefficients(current_bass_gain_db_, current_treble_gain_db_,
                                        active_bass_freq_hz_, active_treble_freq_hz_);
            }

            const bool is_flat = (current_bass_gain_db_ < 0.02f) && (current_treble_gain_db_ < 0.02f);
            if (is_flat) {
                bass_svf_.reset();
                treble_svf_.reset();
            } else {
                if (current_bass_gain_db_ >= 0.02f) {
                    bass_svf_.process(ptr, static_cast<uint32_t>(sub_frames), ch);
                }
                if (current_treble_gain_db_ >= 0.02f) {
                    treble_svf_.process(ptr, static_cast<uint32_t>(sub_frames), ch);
                }
            }

            // Advance by full interleaved channel stride even if channels > kMaxChannels
            ptr += sub_frames * static_cast<size_t>(channels);
            frames_remaining -= sub_frames;
        }

        reported_bass_boost_db_.store(current_bass_gain_db_, std::memory_order_relaxed);
        reported_treble_boost_db_.store(current_treble_gain_db_, std::memory_order_relaxed);
    }

    std::atomic<bool> enabled_{false};
    std::atomic<bool> initialized_{false};
    std::atomic<bool> reset_requested_{false};
    std::atomic<bool> reconfig_requested_{false};

    std::atomic<float> target_sample_rate_{48000.0f};
    float active_sample_rate_{48000.0f};
    int active_channels_{2};
    float sub_block_alpha_{0.02198f};

    // Controls
    std::atomic<float> ref_level_db_{0.0f};           // Flat reference volume level (0 dB)
    std::atomic<float> max_bass_boost_db_{9.0f};      // Max bass shelf lift
    std::atomic<float> max_treble_boost_db_{4.5f};    // Max treble shelf lift
    std::atomic<float> bass_freq_hz_{90.0f};          // Bass corner frequency
    std::atomic<float> treble_freq_hz_{9000.0f};      // Treble corner frequency

    // Audio-thread tracking state
    float current_bass_gain_db_{0.0f};
    float current_treble_gain_db_{0.0f};
    float target_bass_gain_db_{0.0f};
    float target_treble_gain_db_{0.0f};
    float active_bass_freq_hz_{90.0f};
    float active_treble_freq_hz_{9000.0f};

    // Atomic telemetry readbacks
    std::atomic<float> reported_bass_boost_db_{0.0f};
    std::atomic<float> reported_treble_boost_db_{0.0f};

    // 64-bit Cytomic TPT SVF filter stages (with Nyquist de-cramping on HighShelf)
    CytomicSVF bass_svf_;
    CytomicSVF treble_svf_;
};

} // namespace sauti::dsp
