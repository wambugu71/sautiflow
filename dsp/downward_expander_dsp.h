#pragma once

#include <cmath>
#include <cstdint>
#include <algorithm>

#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

namespace sauti::dsp {

enum class ExpanderPreset {
    VinylClean = 0,      // Ideal for vinyl rips: suppresses groove noise & rumble
    TapeHiss = 1,        // Ideal for cassette / reel-to-reel tape hiss reduction
    GentleExpansion = 2, // Ultra-transparent downward expansion for subtle cleaning
    DynamicGate = 3,     // Fast, firm noise gate for speech or noisy recordings
    Custom = 4           // User-defined manual parameter tuning
};

// =============================================================================
// DownwardExpanderDSP: High-Fidelity Downward Expander & Adaptive Noise Reducer
//
// Features:
// - Downward expansion below threshold with progressive soft-knee attenuation.
// - Configurable gain reduction floor (Range limit) prevents unnatural pumping
//   and avoids dropping audio into absolute digital black.
// - 2nd-order Butterworth sidechain HPF to eliminate turntable rumble and
//   mechanical sub-bass thumps from falsely triggering/opening the expander.
// - Envelope follower with smooth attack/release ballistics.
// - Parameter de-zippering and anti-pop enable/disable smoothing.
// - Allocation-free realtime audio processing.
// =============================================================================
class DownwardExpanderDSP {
public:
    DownwardExpanderDSP() {
        setSampleRate(48000.0f);
        setPreset(ExpanderPreset::VinylClean);
        reset();
    }

    void setSampleRate(float sampleRate) {
        if (sampleRate <= 0.0f) sampleRate = 48000.0f;
        if (std::abs(sample_rate_ - sampleRate) < 0.1f) return;
        sample_rate_ = sampleRate;
        smoothing_coeff_ = 1.0f - std::exp(-1.0f / (0.020f * sample_rate_)); // 20ms gain smoothing
        updateTimeConstants();
        updateSidechainFilter();
    }

    void setEnabled(bool enabled) {
        if (enabled_ != enabled) {
            enabled_ = enabled;
        }
    }

    bool isEnabled() const { return enabled_; }

    void setPreset(ExpanderPreset preset) {
        preset_ = preset;
        switch (preset) {
            case ExpanderPreset::VinylClean:
                threshold_db_ = -52.0f;
                ratio_ = 1.8f;
                max_reduction_db_ = -16.0f;
                attack_ms_ = 12.0f;
                release_ms_ = 280.0f;
                knee_db_ = 6.0f;
                sidechain_hpf_hz_ = 50.0f;
                break;
            case ExpanderPreset::TapeHiss:
                threshold_db_ = -50.0f;
                ratio_ = 2.0f;
                max_reduction_db_ = -18.0f;
                attack_ms_ = 10.0f;
                release_ms_ = 220.0f;
                knee_db_ = 6.0f;
                sidechain_hpf_hz_ = 40.0f;
                break;
            case ExpanderPreset::GentleExpansion:
                threshold_db_ = -46.0f;
                ratio_ = 1.4f;
                max_reduction_db_ = -12.0f;
                attack_ms_ = 20.0f;
                release_ms_ = 400.0f;
                knee_db_ = 8.0f;
                sidechain_hpf_hz_ = 30.0f;
                break;
            case ExpanderPreset::DynamicGate:
                threshold_db_ = -38.0f;
                ratio_ = 6.0f;
                max_reduction_db_ = -36.0f;
                attack_ms_ = 2.0f;
                release_ms_ = 100.0f;
                knee_db_ = 3.0f;
                sidechain_hpf_hz_ = 60.0f;
                break;
            case ExpanderPreset::Custom:
                break;
        }
        updateTimeConstants();
        updateSidechainFilter();
    }

    ExpanderPreset getPreset() const { return preset_; }

    void setThresholdDb(float thresholdDb) {
        threshold_db_ = std::clamp(thresholdDb, -80.0f, -10.0f);
        preset_ = ExpanderPreset::Custom;
    }

    float getThresholdDb() const { return threshold_db_; }

    void setRatio(float ratio) {
        ratio_ = std::clamp(ratio, 1.0f, 20.0f);
        preset_ = ExpanderPreset::Custom;
    }

    float getRatio() const { return ratio_; }

    // Maximum allowed attenuation in dB (e.g. -18.0 dB floor)
    void setRangeDb(float rangeDb) {
        max_reduction_db_ = std::clamp(rangeDb, -60.0f, 0.0f);
        preset_ = ExpanderPreset::Custom;
    }

    float getRangeDb() const { return max_reduction_db_; }

    void setAttackMs(float attackMs) {
        attack_ms_ = std::clamp(attackMs, 0.1f, 100.0f);
        preset_ = ExpanderPreset::Custom;
        updateTimeConstants();
    }

    float getAttackMs() const { return attack_ms_; }

    void setReleaseMs(float releaseMs) {
        release_ms_ = std::clamp(releaseMs, 10.0f, 2000.0f);
        preset_ = ExpanderPreset::Custom;
        updateTimeConstants();
    }

    float getReleaseMs() const { return release_ms_; }

    void setKneeDb(float kneeDb) {
        knee_db_ = std::clamp(kneeDb, 0.0f, 18.0f);
        preset_ = ExpanderPreset::Custom;
    }

    float getKneeDb() const { return knee_db_; }

    void setSidechainHpfHz(float hpfHz) {
        sidechain_hpf_hz_ = std::clamp(hpfHz, 0.0f, 200.0f);
        preset_ = ExpanderPreset::Custom;
        updateSidechainFilter();
    }

    float getSidechainHpfHz() const { return sidechain_hpf_hz_; }

    void reset() {
        envelope_ = 0.0f;
        gain_linear_ = 1.0f;
        anti_pop_ = enabled_ ? 1.0f : 0.0f;
        current_gr_db_ = 0.0f;
        hp_x1_l_ = hp_x2_l_ = hp_y1_l_ = hp_y2_l_ = 0.0f;
        hp_x1_r_ = hp_x2_r_ = hp_y1_r_ = hp_y2_r_ = 0.0f;
    }

    float getCurrentGainReductionDb() const {
        return current_gr_db_;
    }

    // Process interleaved stereo samples: [L0, R0, L1, R1, ...]
    void process(float* interleaved_samples, uint32_t frame_count) {
        if (!interleaved_samples || frame_count == 0) return;

        // If disabled and fully smoothed to identity pass, return early
        if (!enabled_ && anti_pop_ <= 1e-4f) {
            anti_pop_ = 0.0f;
            current_gr_db_ = 0.0f;
            gain_linear_ = 1.0f;
            return;
        }

        const float half_knee = knee_db_ * 0.5f;

        for (uint32_t i = 0; i < frame_count; ++i) {
            // Anti-pop crossfade smoothing
            if (enabled_ && anti_pop_ < 1.0f) {
                anti_pop_ += smoothing_coeff_ * (1.0f - anti_pop_);
                if (anti_pop_ > 0.999f) anti_pop_ = 1.0f;
            } else if (!enabled_ && anti_pop_ > 0.0f) {
                anti_pop_ += smoothing_coeff_ * (0.0f - anti_pop_);
                if (anti_pop_ < 0.001f) anti_pop_ = 0.0f;
            }

            float in_l = interleaved_samples[2 * i];
            float in_r = interleaved_samples[2 * i + 1];

            // 1. Sidechain High-Pass Filtering (to reject turntable rumble / sub-bass)
            float sc_l = in_l;
            float sc_r = in_r;

            if (sidechain_hpf_hz_ >= 15.0f) {
                // Left channel biquad
                float y_l = hp_b0_ * in_l + hp_b1_ * hp_x1_l_ + hp_b2_ * hp_x2_l_
                          - hp_a1_ * hp_y1_l_ - hp_a2_ * hp_y2_l_;
                hp_x2_l_ = hp_x1_l_; hp_x1_l_ = in_l;
                hp_y2_l_ = hp_y1_l_; hp_y1_l_ = y_l;
                sc_l = y_l;

                // Right channel biquad
                float y_r = hp_b0_ * in_r + hp_b1_ * hp_x1_r_ + hp_b2_ * hp_x2_r_
                          - hp_a1_ * hp_y1_r_ - hp_a2_ * hp_y2_r_;
                hp_x2_r_ = hp_x1_r_; hp_x1_r_ = in_r;
                hp_y2_r_ = hp_y1_r_; hp_y1_r_ = y_r;
                sc_r = y_r;
            }

            // 2. Peak Envelope Detection (Stereo Linked)
            float peak = std::max(std::abs(sc_l), std::abs(sc_r));

            if (peak > envelope_) {
                envelope_ += attack_coeff_ * (peak - envelope_);
            } else {
                envelope_ += release_coeff_ * (peak - envelope_);
            }

            // Convert envelope to dBFS
            float env_db = (envelope_ > 1e-6f) ? 20.0f * std::log10(envelope_) : -120.0f;

            // 3. Smooth Soft-Knee Downward Expansion Gain Computer
            float target_gr_db = 0.0f;
            float delta = env_db - threshold_db_;

            if (knee_db_ > 0.0f && delta > -half_knee && delta < half_knee) {
                // Soft-knee transition zone: quadratic interpolation
                // Seamlessly meets unity gain at (threshold + half_knee) and linear slope at (threshold - half_knee)
                float dist_from_upper = threshold_db_ + half_knee - env_db;
                target_gr_db = -((ratio_ - 1.0f) / (2.0f * knee_db_)) * (dist_from_upper * dist_from_upper);
            } else if (delta <= (knee_db_ > 0.0f ? -half_knee : 0.0f)) {
                // Linear downward expansion region below threshold
                target_gr_db = (ratio_ - 1.0f) * delta;
            }

            // Clamp by user-defined floor / range limit (e.g. max -16 dB reduction)
            target_gr_db = std::clamp(target_gr_db, max_reduction_db_, 0.0f);

            // Compute target linear gain with anti-pop bypass crossfade
            float target_gain_linear = std::pow(10.0f, (target_gr_db * anti_pop_) / 20.0f);

            // 4. Per-sample smooth gain application (eliminates zipper noise)
            gain_linear_ += smoothing_coeff_ * (target_gain_linear - gain_linear_);

            interleaved_samples[2 * i]     *= gain_linear_;
            interleaved_samples[2 * i + 1] *= gain_linear_;
        }

        current_gr_db_ = (gain_linear_ > 1e-4f) ? 20.0f * std::log10(gain_linear_) : -80.0f;
    }

private:
    void updateTimeConstants() {
        attack_coeff_  = 1.0f - std::exp(-1.0f / (std::max(attack_ms_, 0.1f) * 0.001f * sample_rate_));
        release_coeff_ = 1.0f - std::exp(-1.0f / (std::max(release_ms_, 1.0f) * 0.001f * sample_rate_));
    }

    void updateSidechainFilter() {
        if (sidechain_hpf_hz_ < 15.0f) {
            hp_b0_ = 1.0f; hp_b1_ = 0.0f; hp_b2_ = 0.0f;
            hp_a1_ = 0.0f; hp_a2_ = 0.0f;
            return;
        }

        // 2nd-order Butterworth High-Pass Filter
        const float fc = std::clamp(sidechain_hpf_hz_, 15.0f, sample_rate_ * 0.45f);
        const float omega = 2.0f * static_cast<float>(M_PI) * fc / sample_rate_;
        const float cos_w = std::cos(omega);
        const float sin_w = std::sin(omega);
        const float alpha = sin_w / (2.0f * 0.70710678f); // Q = 0.7071

        const float a0 = 1.0f + alpha;
        hp_b0_ = ((1.0f + cos_w) * 0.5f) / a0;
        hp_b1_ = (-(1.0f + cos_w)) / a0;
        hp_b2_ = ((1.0f + cos_w) * 0.5f) / a0;
        hp_a1_ = (-2.0f * cos_w) / a0;
        hp_a2_ = (1.0f - alpha) / a0;
    }

    bool enabled_{false};
    float sample_rate_{48000.0f};
    ExpanderPreset preset_{ExpanderPreset::VinylClean};

    float threshold_db_{-52.0f};
    float ratio_{1.8f};
    float max_reduction_db_{-16.0f};
    float knee_db_{6.0f};
    float attack_ms_{12.0f};
    float release_ms_{280.0f};
    float sidechain_hpf_hz_{50.0f};

    // Filter & Ballistics coefficients
    float attack_coeff_{0.0f};
    float release_coeff_{0.0f};
    float smoothing_coeff_{0.01f};

    float hp_b0_{1.0f}, hp_b1_{0.0f}, hp_b2_{0.0f};
    float hp_a1_{0.0f}, hp_a2_{0.0f};

    // Filter states
    float hp_x1_l_{0.0f}, hp_x2_l_{0.0f}, hp_y1_l_{0.0f}, hp_y2_l_{0.0f};
    float hp_x1_r_{0.0f}, hp_x2_r_{0.0f}, hp_y1_r_{0.0f}, hp_y2_r_{0.0f};

    // Runtime state
    float envelope_{0.0f};
    float gain_linear_{1.0f};
    float anti_pop_{0.0f};
    float current_gr_db_{0.0f};
};

} // namespace sauti::dsp
