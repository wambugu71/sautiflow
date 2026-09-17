#pragma once

#include <cmath>
#include <cstdint>
#include <algorithm>
#include <array>
#include <vector>
#include "denormals.h"
#include "simd_math.h"

namespace sauti::dsp {

// =============================================================================
// TapeDriftDSP: Vintage Tape Wow, Flutter & Mechanical Pitch Drift
//
// Features:
// - Physical analog tape & vinyl pitch modulation model:
//     - Wow (0.2–3.0 Hz): Slow cyclic motor speed / warped vinyl wobble.
//     - Flutter (5.0–30.0 Hz): Rapid scrape flutter across playback heads.
//     - Drift (0.05–0.5 Hz): Organic random mechanical wander.
// - 4-Point 3rd-Order Catmull-Rom / Hermite cubic fractional delay interpolation
//   for pristine, artifact-free, aliasing-free continuous delay modulation.
// - Stereo Quadrature Spread: Independent L/R modulation phase producing
//   expansive, warm analog soundstages.
// - Tape Head Damping: 1-pole smooth high-frequency roll-off mimicking
//   magnetic tape head absorption.
// - Curated Presets: SubtleHiFi, VintageReelToReel, WarpedVinyl, CassetteLoFi.
// - Dual 32-bit float and 64-bit double in-place processing paths.
// =============================================================================

enum class TapeDriftPreset {
    SubtleHiFi = 0,
    VintageReelToReel = 1,
    WarpedVinyl = 2,
    CassetteLoFi = 3,
    Custom = 4
};

class TapeDriftDSP {
public:
    static constexpr size_t kBufferSize = 16384;
    static constexpr size_t kBufferMask = kBufferSize - 1;
    static constexpr size_t kMaxChannels = 2;

    TapeDriftDSP() {
        setSampleRate(48000.0f);
        setPreset(TapeDriftPreset::SubtleHiFi);
        reset();
    }

    void setSampleRate(float sampleRate) {
        if (sampleRate <= 0.0f) sampleRate = 48000.0f;
        sample_rate_ = sampleRate;
        updateRates();
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

    void setPreset(TapeDriftPreset preset) {
        preset_ = preset;
        switch (preset) {
        case TapeDriftPreset::SubtleHiFi:
            wow_rate_hz_ = 0.8f;
            wow_depth_ms_ = 0.35f;
            flutter_rate_hz_ = 12.0f;
            flutter_depth_ms_ = 0.08f;
            drift_depth_ms_ = 0.10f;
            stereo_phase_deg_ = 45.0f;
            hf_damping_hz_ = 18000.0f;
            break;
        case TapeDriftPreset::VintageReelToReel:
            wow_rate_hz_ = 1.0f;
            wow_depth_ms_ = 0.90f;
            flutter_rate_hz_ = 16.0f;
            flutter_depth_ms_ = 0.22f;
            drift_depth_ms_ = 0.30f;
            stereo_phase_deg_ = 60.0f;
            hf_damping_hz_ = 15000.0f;
            break;
        case TapeDriftPreset::WarpedVinyl:
            wow_rate_hz_ = 0.555f; // 33.33 RPM / 60 = 0.555 Hz
            wow_depth_ms_ = 2.2f;
            flutter_rate_hz_ = 7.5f;
            flutter_depth_ms_ = 0.12f;
            drift_depth_ms_ = 0.20f;
            stereo_phase_deg_ = 90.0f;
            hf_damping_hz_ = 16000.0f;
            break;
        case TapeDriftPreset::CassetteLoFi:
            wow_rate_hz_ = 1.6f;
            wow_depth_ms_ = 2.0f;
            flutter_rate_hz_ = 22.0f;
            flutter_depth_ms_ = 0.55f;
            drift_depth_ms_ = 0.70f;
            stereo_phase_deg_ = 90.0f;
            hf_damping_hz_ = 10000.0f;
            break;
        case TapeDriftPreset::Custom:
            break;
        }
        updateRates();
    }

    TapeDriftPreset getPreset() const { return preset_; }

    void setParams(float wow_rate_hz,
                   float wow_depth_ms,
                   float flutter_rate_hz,
                   float flutter_depth_ms,
                   float drift_depth_ms,
                   float stereo_phase_deg,
                   float hf_damping_hz) {
        wow_rate_hz_ = std::clamp(wow_rate_hz, 0.1f, 5.0f);
        wow_depth_ms_ = std::clamp(wow_depth_ms, 0.0f, 10.0f);
        flutter_rate_hz_ = std::clamp(flutter_rate_hz, 2.0f, 40.0f);
        flutter_depth_ms_ = std::clamp(flutter_depth_ms, 0.0f, 3.0f);
        drift_depth_ms_ = std::clamp(drift_depth_ms, 0.0f, 5.0f);
        stereo_phase_deg_ = std::clamp(stereo_phase_deg, 0.0f, 180.0f);
        hf_damping_hz_ = std::clamp(hf_damping_hz, 2000.0f, 22000.0f);
        preset_ = TapeDriftPreset::Custom;

        updateRates();
    }

    void getParams(float *out_wow_rate_hz,
                   float *out_wow_depth_ms,
                   float *out_flutter_rate_hz,
                   float *out_flutter_depth_ms,
                   float *out_drift_depth_ms,
                   float *out_stereo_phase_deg,
                   float *out_hf_damping_hz) const {
        if (out_wow_rate_hz) *out_wow_rate_hz = wow_rate_hz_;
        if (out_wow_depth_ms) *out_wow_depth_ms = wow_depth_ms_;
        if (out_flutter_rate_hz) *out_flutter_rate_hz = flutter_rate_hz_;
        if (out_flutter_depth_ms) *out_flutter_depth_ms = flutter_depth_ms_;
        if (out_drift_depth_ms) *out_drift_depth_ms = drift_depth_ms_;
        if (out_stereo_phase_deg) *out_stereo_phase_deg = stereo_phase_deg_;
        if (out_hf_damping_hz) *out_hf_damping_hz = hf_damping_hz_;
    }

    void reset() {
        for (size_t c = 0; c < kMaxChannels; ++c) {
            buffer_[c].fill(0.0);
            hf_state_[c] = 0.0;
        }
        write_pos_ = 0;
        wow_phase_ = 0.0;
        flutter_phase_ = 0.0;
        drift_val_ = 0.0;
        drift_target_ = 0.0;
        drift_counter_ = 0;
    }

    // Process 32-bit float interleaved samples in-place
    void process(float *buffer, size_t frame_count, int channels) {
        if (!enabled_ || buffer == nullptr || frame_count == 0 || channels <= 0) {
            return;
        }

        const size_t ch = std::min(static_cast<size_t>(channels), kMaxChannels);
        ScopedDenormalsDisable denormalGuard;

        const double nominal_delay_samples = 0.015 * static_cast<double>(sample_rate_); // 15 ms center delay
        const double wow_amp = (static_cast<double>(wow_depth_ms_) * 0.001) * static_cast<double>(sample_rate_);
        const double flutter_amp = (static_cast<double>(flutter_depth_ms_) * 0.001) * static_cast<double>(sample_rate_);
        const double drift_amp = (static_cast<double>(drift_depth_ms_) * 0.001) * static_cast<double>(sample_rate_);
        const double phase_offset = static_cast<double>(stereo_phase_deg_) * (3.14159265358979323846 / 180.0);

        for (size_t i = 0; i < frame_count; ++i) {
            // 1. Advance LFOs
            wow_phase_ += wow_phase_inc_;
            if (wow_phase_ >= 6.283185307179586) wow_phase_ -= 6.283185307179586;

            flutter_phase_ += flutter_phase_inc_;
            if (flutter_phase_ >= 6.283185307179586) flutter_phase_ -= 6.283185307179586;

            // Random drift slow walk
            if (++drift_counter_ >= drift_update_interval_) {
                drift_counter_ = 0;
                // Simple pseudo-random step [-1.0, 1.0]
                drift_seed_ = (drift_seed_ * 1103515245u + 12345u) & 0x7fffffffu;
                drift_target_ = (static_cast<double>(drift_seed_) / 1073741824.0) - 1.0;
            }
            drift_val_ += 0.0005 * (drift_target_ - drift_val_);

            // 2. Write input samples to circular buffer
            for (size_t c = 0; c < ch; ++c) {
                buffer_[c][write_pos_] = static_cast<double>(buffer[i * (size_t)channels + c]);
            }

            // 3. Read interpolated delayed samples per channel
            for (size_t c = 0; c < ch; ++c) {
                const double ch_phase_offset = (c == 1) ? phase_offset : 0.0;
                const double wow_mod = std::sin(wow_phase_ + ch_phase_offset) * wow_amp;
                const double flutter_mod = std::sin(flutter_phase_ + ch_phase_offset * 1.5) * flutter_amp;
                const double drift_mod = drift_val_ * drift_amp;

                const double total_delay = std::clamp(nominal_delay_samples + wow_mod + flutter_mod + drift_mod,
                                                      2.0, static_cast<double>(kBufferSize - 8));

                const double read_pos = static_cast<double>(write_pos_) - total_delay;
                const int64_t i_read = static_cast<int64_t>(std::floor(read_pos));
                const double frac = read_pos - static_cast<double>(i_read);

                // 4-point Hermite cubic interpolation
                const size_t idx_m1 = static_cast<size_t>(i_read - 1) & kBufferMask;
                const size_t idx_0  = static_cast<size_t>(i_read)     & kBufferMask;
                const size_t idx_p1 = static_cast<size_t>(i_read + 1) & kBufferMask;
                const size_t idx_p2 = static_cast<size_t>(i_read + 2) & kBufferMask;

                const double ym1 = buffer_[c][idx_m1];
                const double y0  = buffer_[c][idx_0];
                const double y1  = buffer_[c][idx_p1];
                const double y2  = buffer_[c][idx_p2];

                double delayed = hermite4(ym1, y0, y1, y2, frac);

                // 4. High-frequency tape damping filter
                if (hf_damping_hz_ < 20000.0f) {
                    hf_state_[c] += hf_alpha_ * (delayed - hf_state_[c]);
                    delayed = hf_state_[c];
                }

                buffer[i * (size_t)channels + c] = static_cast<float>(delayed);
            }

            write_pos_ = (write_pos_ + 1) & kBufferMask;
        }
    }

    // Process 64-bit double interleaved samples in-place
    void process(double *buffer, size_t frame_count, int channels) {
        if (!enabled_ || buffer == nullptr || frame_count == 0 || channels <= 0) {
            return;
        }

        const size_t ch = std::min(static_cast<size_t>(channels), kMaxChannels);
        ScopedDenormalsDisable denormalGuard;

        const double nominal_delay_samples = 0.015 * static_cast<double>(sample_rate_);
        const double wow_amp = (static_cast<double>(wow_depth_ms_) * 0.001) * static_cast<double>(sample_rate_);
        const double flutter_amp = (static_cast<double>(flutter_depth_ms_) * 0.001) * static_cast<double>(sample_rate_);
        const double drift_amp = (static_cast<double>(drift_depth_ms_) * 0.001) * static_cast<double>(sample_rate_);
        const double phase_offset = static_cast<double>(stereo_phase_deg_) * (3.14159265358979323846 / 180.0);

        for (size_t i = 0; i < frame_count; ++i) {
            wow_phase_ += wow_phase_inc_;
            if (wow_phase_ >= 6.283185307179586) wow_phase_ -= 6.283185307179586;

            flutter_phase_ += flutter_phase_inc_;
            if (flutter_phase_ >= 6.283185307179586) flutter_phase_ -= 6.283185307179586;

            if (++drift_counter_ >= drift_update_interval_) {
                drift_counter_ = 0;
                drift_seed_ = (drift_seed_ * 1103515245u + 12345u) & 0x7fffffffu;
                drift_target_ = (static_cast<double>(drift_seed_) / 1073741824.0) - 1.0;
            }
            drift_val_ += 0.0005 * (drift_target_ - drift_val_);

            for (size_t c = 0; c < ch; ++c) {
                buffer_[c][write_pos_] = buffer[i * (size_t)channels + c];
            }

            for (size_t c = 0; c < ch; ++c) {
                const double ch_phase_offset = (c == 1) ? phase_offset : 0.0;
                const double wow_mod = std::sin(wow_phase_ + ch_phase_offset) * wow_amp;
                const double flutter_mod = std::sin(flutter_phase_ + ch_phase_offset * 1.5) * flutter_amp;
                const double drift_mod = drift_val_ * drift_amp;

                const double total_delay = std::clamp(nominal_delay_samples + wow_mod + flutter_mod + drift_mod,
                                                      2.0, static_cast<double>(kBufferSize - 8));

                const double read_pos = static_cast<double>(write_pos_) - total_delay;
                const int64_t i_read = static_cast<int64_t>(std::floor(read_pos));
                const double frac = read_pos - static_cast<double>(i_read);

                const size_t idx_m1 = static_cast<size_t>(i_read - 1) & kBufferMask;
                const size_t idx_0  = static_cast<size_t>(i_read)     & kBufferMask;
                const size_t idx_p1 = static_cast<size_t>(i_read + 1) & kBufferMask;
                const size_t idx_p2 = static_cast<size_t>(i_read + 2) & kBufferMask;

                const double ym1 = buffer_[c][idx_m1];
                const double y0  = buffer_[c][idx_0];
                const double y1  = buffer_[c][idx_p1];
                const double y2  = buffer_[c][idx_p2];

                double delayed = hermite4(ym1, y0, y1, y2, frac);

                if (hf_damping_hz_ < 20000.0f) {
                    hf_state_[c] += hf_alpha_ * (delayed - hf_state_[c]);
                    delayed = hf_state_[c];
                }

                buffer[i * (size_t)channels + c] = delayed;
            }

            write_pos_ = (write_pos_ + 1) & kBufferMask;
        }
    }

private:
    static inline double hermite4(double ym1, double y0, double y1, double y2, double frac) {
        const double c0 = y0;
        const double c1 = 0.5 * (y1 - ym1);
        const double c2 = ym1 - 2.5 * y0 + 2.0 * y1 - 0.5 * y2;
        const double c3 = 0.5 * (y2 - ym1) + 1.5 * (y0 - y1);
        return ((c3 * frac + c2) * frac + c1) * frac + c0;
    }

    void updateRates() {
        constexpr double TWO_PI = 6.28318530717958647692;
        wow_phase_inc_ = (TWO_PI * static_cast<double>(wow_rate_hz_)) / static_cast<double>(sample_rate_);
        flutter_phase_inc_ = (TWO_PI * static_cast<double>(flutter_rate_hz_)) / static_cast<double>(sample_rate_);

        // Damping 1-pole filter alpha
        const double fc = std::clamp(static_cast<double>(hf_damping_hz_), 1000.0, static_cast<double>(sample_rate_ * 0.45));
        const double w0 = TWO_PI * fc / static_cast<double>(sample_rate_);
        hf_alpha_ = w0 / (w0 + 1.0);

        drift_update_interval_ = static_cast<uint32_t>(sample_rate_ * 0.1); // 100 ms
        if (drift_update_interval_ == 0) drift_update_interval_ = 1;
    }

    bool enabled_ = false;
    float sample_rate_ = 48000.0f;
    TapeDriftPreset preset_ = TapeDriftPreset::SubtleHiFi;

    float wow_rate_hz_ = 0.8f;
    float wow_depth_ms_ = 0.35f;
    float flutter_rate_hz_ = 12.0f;
    float flutter_depth_ms_ = 0.08f;
    float drift_depth_ms_ = 0.10f;
    float stereo_phase_deg_ = 45.0f;
    float hf_damping_hz_ = 18000.0f;

    // Modulator phase & state
    double wow_phase_ = 0.0;
    double wow_phase_inc_ = 0.0;
    double flutter_phase_ = 0.0;
    double flutter_phase_inc_ = 0.0;

    uint32_t drift_seed_ = 987654321u;
    double drift_val_ = 0.0;
    double drift_target_ = 0.0;
    uint32_t drift_counter_ = 0;
    uint32_t drift_update_interval_ = 4800;

    double hf_alpha_ = 1.0;
    std::array<double, kMaxChannels> hf_state_{0.0, 0.0};

    // Circular delay buffer
    size_t write_pos_ = 0;
    std::array<std::array<double, kBufferSize>, kMaxChannels> buffer_{};
};

} // namespace sauti::dsp
