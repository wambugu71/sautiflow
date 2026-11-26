#pragma once

#include <cmath>
#include <cstdint>
#include <algorithm>
#include <array>
#include <atomic>
#include "denormals.h"
#include "simd_math.h"

namespace sauti::dsp {

// =============================================================================
// NoiseGateDSP: Studio-Grade Noise Gate with Hysteresis & Hold Time
//
// Features:
// - Dual-threshold Hysteresis: Separate Open and Close thresholds completely
//   eliminate rapid gate "chatter" or fluttering on borderline decaying sounds.
// - Precision Hold Timer: Keeps the gate 100% open for a configurable duration
//   (e.g. 50-200 ms) after the signal drops below the close threshold,
//   preserving trailing breaths, guitar decays, and natural reverberation.
// - 2nd-Order Butterworth Sidechain HPF: Filters out low-frequency rumble,
//   footsteps, and DC thumps from keeping the gate falsely open.
// - Smooth exponential attack and release ballistics prevent clicks or pops.
// - Real-time gain reduction reporting for UI telemetry.
// - Supports both 32-bit float and 64-bit double processing paths.
// =============================================================================
class NoiseGateDSP {
public:
    enum class GateState {
        Closed = 0,
        Holding = 1,
        Open = 2
    };

    NoiseGateDSP() {
        setSampleRate(48000.0f);
        reset();
    }

    void setSampleRate(float sampleRate) {
        if (sampleRate <= 0.0f) sampleRate = 48000.0f;
        sample_rate_ = sampleRate;
        updateThresholds();
        updateTimeConstants();
        updateSidechainFilter();
    }

    float getSampleRate() const { return sample_rate_; }

    void setEnabled(bool enabled) {
        if (enabled_ != enabled) {
            enabled_ = enabled;
            if (enabled) {
                // Start Open at unity gain when enabled mid-stream so there is no sample-0 drop click
                state_ = GateState::Open;
                hold_counter_ = 0;
                current_gain_linear_ = 1.0f;
                sc_envelope_ = open_threshold_lin_;
                gr_telemetry_.store(0.0f, std::memory_order_relaxed);
            } else {
                reset();
            }
        }
    }

    bool isEnabled() const { return enabled_; }

    void setParams(float open_threshold_db,
                   float close_threshold_db,
                   float hold_ms,
                   float attack_ms,
                   float release_ms,
                   float sidechain_hpf_hz,
                   float floor_db = -80.0f) {
        open_threshold_db_ = std::clamp(open_threshold_db, -80.0f, 0.0f);
        close_threshold_db_ = std::clamp(close_threshold_db, -80.0f, open_threshold_db_);
        hold_ms_ = std::clamp(hold_ms, 0.0f, 1000.0f);
        attack_ms_ = std::clamp(attack_ms, 0.1f, 100.0f);
        release_ms_ = std::clamp(release_ms, 5.0f, 2000.0f);
        sidechain_hpf_hz_ = std::clamp(sidechain_hpf_hz, 20.0f, 1000.0f);
        floor_db_ = std::clamp(floor_db, -100.0f, -6.0f);

        updateThresholds();
        updateTimeConstants();
        updateSidechainFilter();
    }

    void getParams(float *out_open_threshold_db,
                   float *out_close_threshold_db,
                   float *out_hold_ms,
                   float *out_attack_ms,
                   float *out_release_ms,
                   float *out_sidechain_hpf_hz,
                   float *out_floor_db = nullptr) const {
        if (out_open_threshold_db) *out_open_threshold_db = open_threshold_db_;
        if (out_close_threshold_db) *out_close_threshold_db = close_threshold_db_;
        if (out_hold_ms) *out_hold_ms = hold_ms_;
        if (out_attack_ms) *out_attack_ms = attack_ms_;
        if (out_release_ms) *out_release_ms = release_ms_;
        if (out_sidechain_hpf_hz) *out_sidechain_hpf_hz = sidechain_hpf_hz_;
        if (out_floor_db) *out_floor_db = floor_db_;
    }

    float getGainReductionDb() const {
        return gr_telemetry_.load(std::memory_order_relaxed);
    }

    GateState getState() const {
        return state_;
    }

    void reset() {
        state_ = GateState::Closed;
        hold_counter_ = 0;
        current_gain_linear_ = 0.0f;
        sc_envelope_ = 0.0f;
        sidechain_s1_.fill(0.0);
        sidechain_s2_.fill(0.0);
        gr_telemetry_.store(enabled_ ? -100.0f : 0.0f, std::memory_order_relaxed);
    }

    // Process 32-bit float interleaved samples in-place
    void process(float *buffer, size_t frame_count, int channels) {
        if (!enabled_ || buffer == nullptr || frame_count == 0 || channels <= 0) {
            return;
        }

        ScopedDenormalsDisable denormalGuard;
        const float floor_lin = std::pow(10.0f, floor_db_ / 20.0f);
        const uint32_t hold_samples_total = static_cast<uint32_t>(hold_ms_ * 0.001f * sample_rate_);
        const int sc_ch = std::min(channels, 16);

        for (size_t i = 0; i < frame_count; ++i) {
            // 1. Per-channel 2nd-order Butterworth Sidechain HPF (TDF2) + linked peak detection
            //    Avoids mono-sum phase cancellation on wide or out-of-phase stereo material.
            float sc_abs = 0.0f;
            for (int c = 0; c < sc_ch; ++c) {
                const double sc_sample = static_cast<double>(buffer[i * (size_t)channels + c]);
                const double sc_filtered = sc_b0_ * sc_sample + sidechain_s1_[c];
                sidechain_s1_[c] = sc_b1_ * sc_sample - sc_a1_ * sc_filtered + sidechain_s2_[c];
                sidechain_s2_[c] = sc_b2_ * sc_sample - sc_a2_ * sc_filtered;
                const float ch_abs = static_cast<float>(std::abs(sc_filtered));
                if (ch_abs > sc_abs) sc_abs = ch_abs;
            }

            // 2. Peak Envelope Detector
            if (sc_abs > sc_envelope_) {
                sc_envelope_ += sc_env_attack_coeff_ * (sc_abs - sc_envelope_);
            } else {
                sc_envelope_ += sc_env_release_coeff_ * (sc_abs - sc_envelope_);
            }

            // Linear-domain comparisons (thresholds precomputed; no log10 per sample)
            const bool ge_open = sc_envelope_ >= open_threshold_lin_;
            const bool lt_close = sc_envelope_ < close_threshold_lin_;

            // 4. Hysteresis State Machine
            float target_gain_linear = floor_lin;

            switch (state_) {
            case GateState::Closed:
                if (ge_open) {
                    state_ = GateState::Open;
                    target_gain_linear = 1.0f;
                } else {
                    target_gain_linear = floor_lin;
                }
                break;

            case GateState::Open:
                if (lt_close) {
                    if (hold_samples_total > 0) {
                        state_ = GateState::Holding;
                        hold_counter_ = hold_samples_total;
                        target_gain_linear = 1.0f;
                    } else {
                        state_ = GateState::Closed;
                        target_gain_linear = floor_lin;
                    }
                } else {
                    target_gain_linear = 1.0f;
                }
                break;

            case GateState::Holding:
                if (ge_open) {
                    state_ = GateState::Open;
                    target_gain_linear = 1.0f;
                } else if (hold_counter_ > 0) {
                    hold_counter_--;
                    target_gain_linear = 1.0f;
                } else {
                    state_ = GateState::Closed;
                    target_gain_linear = floor_lin;
                }
                break;
            }

            // 4. Ballistics (Attack / Release)
            if (target_gain_linear > current_gain_linear_) {
                current_gain_linear_ += attack_coeff_ * (target_gain_linear - current_gain_linear_);
            } else {
                current_gain_linear_ += release_coeff_ * (target_gain_linear - current_gain_linear_);
            }

            // 5. Apply gain to all channels
            for (int c = 0; c < channels; ++c) {
                buffer[i * (size_t)channels + c] *= current_gain_linear_;
            }
        }

        const float gr_db = (current_gain_linear_ >= 0.999f)
                                ? 0.0f
                                : 20.0f * std::log10(std::max(current_gain_linear_, 1.0e-5f));
        gr_telemetry_.store(gr_db, std::memory_order_relaxed);
    }

    // Process 64-bit double interleaved samples in-place
    void process(double *buffer, size_t frame_count, int channels) {
        if (!enabled_ || buffer == nullptr || frame_count == 0 || channels <= 0) {
            return;
        }

        ScopedDenormalsDisable denormalGuard;
        const double floor_lin = std::pow(10.0, static_cast<double>(floor_db_) / 20.0);
        const uint32_t hold_samples_total = static_cast<uint32_t>(hold_ms_ * 0.001f * sample_rate_);
        const int sc_ch = std::min(channels, 16);

        for (size_t i = 0; i < frame_count; ++i) {
            float sc_abs = 0.0f;
            for (int c = 0; c < sc_ch; ++c) {
                const double sc_sample = buffer[i * (size_t)channels + c];
                const double sc_filtered = sc_b0_ * sc_sample + sidechain_s1_[c];
                sidechain_s1_[c] = sc_b1_ * sc_sample - sc_a1_ * sc_filtered + sidechain_s2_[c];
                sidechain_s2_[c] = sc_b2_ * sc_sample - sc_a2_ * sc_filtered;
                const float ch_abs = static_cast<float>(std::abs(sc_filtered));
                if (ch_abs > sc_abs) sc_abs = ch_abs;
            }

            if (sc_abs > sc_envelope_) {
                sc_envelope_ += sc_env_attack_coeff_ * (sc_abs - sc_envelope_);
            } else {
                sc_envelope_ += sc_env_release_coeff_ * (sc_abs - sc_envelope_);
            }

            // Linear-domain comparisons (thresholds precomputed; no log10 per sample)
            const bool ge_open = sc_envelope_ >= open_threshold_lin_;
            const bool lt_close = sc_envelope_ < close_threshold_lin_;

            float target_gain_linear = static_cast<float>(floor_lin);

            switch (state_) {
            case GateState::Closed:
                if (ge_open) {
                    state_ = GateState::Open;
                    target_gain_linear = 1.0f;
                } else {
                    target_gain_linear = static_cast<float>(floor_lin);
                }
                break;

            case GateState::Open:
                if (lt_close) {
                    if (hold_samples_total > 0) {
                        state_ = GateState::Holding;
                        hold_counter_ = hold_samples_total;
                        target_gain_linear = 1.0f;
                    } else {
                        state_ = GateState::Closed;
                        target_gain_linear = static_cast<float>(floor_lin);
                    }
                } else {
                    target_gain_linear = 1.0f;
                }
                break;

            case GateState::Holding:
                if (ge_open) {
                    state_ = GateState::Open;
                    target_gain_linear = 1.0f;
                } else if (hold_counter_ > 0) {
                    hold_counter_--;
                    target_gain_linear = 1.0f;
                } else {
                    state_ = GateState::Closed;
                    target_gain_linear = static_cast<float>(floor_lin);
                }
                break;
            }

            if (target_gain_linear > current_gain_linear_) {
                current_gain_linear_ += attack_coeff_ * (target_gain_linear - current_gain_linear_);
            } else {
                current_gain_linear_ += release_coeff_ * (target_gain_linear - current_gain_linear_);
            }

            const double g = static_cast<double>(current_gain_linear_);
            for (int c = 0; c < channels; ++c) {
                buffer[i * (size_t)channels + c] *= g;
            }
        }

        const float gr_db = (current_gain_linear_ >= 0.999f)
                                ? 0.0f
                                : 20.0f * std::log10(std::max(current_gain_linear_, 1.0e-5f));
        gr_telemetry_.store(gr_db, std::memory_order_relaxed);
    }

private:
    void updateThresholds() {
        open_threshold_lin_ = std::pow(10.0f, open_threshold_db_ / 20.0f);
        close_threshold_lin_ = std::pow(10.0f, close_threshold_db_ / 20.0f);
    }

    void updateTimeConstants() {
        attack_coeff_ = 1.0f - std::exp(-1.0f / (attack_ms_ * 0.001f * sample_rate_));
        release_coeff_ = 1.0f - std::exp(-1.0f / (release_ms_ * 0.001f * sample_rate_));
        sc_env_attack_coeff_ = 1.0f - std::exp(-1.0f / (0.5f * 0.001f * sample_rate_));
        sc_env_release_coeff_ = 1.0f - std::exp(-1.0f / (6.0f * 0.001f * sample_rate_));
    }

    void updateSidechainFilter() {
        constexpr double PI = 3.14159265358979323846;
        const double w0 = 2.0 * PI * static_cast<double>(sidechain_hpf_hz_) / static_cast<double>(sample_rate_);
        const double cosw0 = std::cos(w0);
        const double sinw0 = std::sin(w0);
        const double alpha = sinw0 * 0.7071067811865475; // Q = sqrt(2)/2

        const double a0 = 1.0 + alpha;
        const double inv_a0 = (std::abs(a0) > 1.0e-12) ? (1.0 / a0) : 1.0;

        sc_b0_ = ((1.0 + cosw0) * 0.5) * inv_a0;
        sc_b1_ = (-(1.0 + cosw0)) * inv_a0;
        sc_b2_ = ((1.0 + cosw0) * 0.5) * inv_a0;
        sc_a1_ = (-2.0 * cosw0) * inv_a0;
        sc_a2_ = (1.0 - alpha) * inv_a0;
    }

    bool enabled_ = false;
    float sample_rate_ = 48000.0f;

    // Parameters
    float open_threshold_db_ = -42.0f;
    float close_threshold_db_ = -48.0f;
    float open_threshold_lin_ = 0.0079432823f;  // 10^(-42/20)
    float close_threshold_lin_ = 0.0039810717f; // 10^(-48/20)
    float hold_ms_ = 80.0f;
    float attack_ms_ = 1.0f;
    float release_ms_ = 120.0f;
    float sidechain_hpf_hz_ = 80.0f;
    float floor_db_ = -80.0f;

    // Time coefficients
    float attack_coeff_ = 0.1f;
    float release_coeff_ = 0.001f;
    float sc_env_attack_coeff_ = 0.1f;
    float sc_env_release_coeff_ = 0.01f;

    // State
    GateState state_ = GateState::Closed;
    uint32_t hold_counter_ = 0;
    float current_gain_linear_ = 0.0f;
    float sc_envelope_ = 0.0f;
    std::atomic<float> gr_telemetry_{0.0f};

    // Sidechain HPF coefficients & per-channel state
    double sc_b0_ = 1.0, sc_b1_ = -2.0, sc_b2_ = 1.0, sc_a1_ = 0.0, sc_a2_ = 0.0;
    std::array<double, 16> sidechain_s1_{};
    std::array<double, 16> sidechain_s2_{};
};

} // namespace sauti::dsp
