#pragma once

#include <cmath>
#include <cstdint>
#include <algorithm>
#include "oversampler.h"

namespace sauti::dsp {

enum class AnalogWarmthProfile {
    Triode12AX7 = 0,     // Warm, rich even-order harmonic saturation (Classic Class-A Tube)
    MagneticTape = 1,    // Soft-knee magnetic compression + subtle high-frequency smoothing
    VintagePreamp = 2    // Clean, punchy analog console drive with subtle harmonic presence
};

// =============================================================================
// AnalogWarmthDSP: High-Fidelity Non-Linear Analog Modeling Suite
// Wrapped in 2x Polyphase Half-Band Oversampling to eliminate harmonic aliasing,
// with De-Zippered Parameter Smoothing and Anti-Pop Crossfading.
// =============================================================================
class AnalogWarmthDSP {
public:
    AnalogWarmthDSP() {
        setSampleRate(48000.0f);
        reset();
    }

    void setSampleRate(float sampleRate) {
        if (sampleRate <= 0.0f) sampleRate = 48000.0f;
        if (std::abs(sample_rate_ - sampleRate) < 0.1f) return;
        sample_rate_ = sampleRate;
        sample_period_ = 1.0f / sample_rate_;
        // 30ms parameter smoothing coefficient at 2x oversampled rate
        smoothing_coeff_ = 1.0f - std::exp(-1.0f / (0.030f * sample_rate_ * 2.0f));
        dc_r_ = 1.0f - (2.0f * 3.14159265358979323846f * 10.0f / sample_rate_);
        updateTapeFilter();
        oversampler_.init(static_cast<int>(sample_rate_), 4096);
    }

    void setEnabled(bool enabled) {
        if (enabled_ != enabled) {
            if (enabled) {
                anti_pop_ = 0.0f;
            }
            enabled_ = enabled;
        }
    }

    bool isEnabled() const { return enabled_; }

    void setProfile(AnalogWarmthProfile profile) {
        if (profile_ != profile) {
            profile_ = profile;
            reset();
        }
    }

    AnalogWarmthProfile getProfile() const { return profile_; }

    // Drive / Warmth amount [0.0, 1.0]
    void setDrive(float drive) {
        target_drive_ = std::clamp(drive, 0.0f, 1.0f);
    }

    float getDrive() const { return target_drive_; }

    void reset() {
        current_drive_ = target_drive_;
        tape_prev_l_ = 0.0f;
        tape_prev_r_ = 0.0f;
        dc_x_l_ = 0.0f; dc_y_l_ = 0.0f;
        dc_x_r_ = 0.0f; dc_y_r_ = 0.0f;
        anti_pop_ = 0.0f;
        oversampler_.reset();
    }

    // Process interleaved stereo samples: [L0, R0, L1, R1, ...]
    void process(float* interleaved_samples, uint32_t frame_count) {
        if (!enabled_ || frame_count == 0 || !interleaved_samples) return;

        // 1. Upsample 2x to oversampled domain
        float* oversampled = oversampler_.upsample(interleaved_samples, frame_count);
        if (!oversampled) return;

        const uint32_t oversampled_frames = frame_count * 2;

        // 2. Process nonlinear saturation profiles at 2x rate
        for (uint32_t i = 0; i < oversampled_frames; i++) {
            // Parameter de-zippering / smoothing per 2x sample
            current_drive_ += smoothing_coeff_ * (target_drive_ - current_drive_);

            float in_l = oversampled[2 * i];
            float in_r = oversampled[2 * i + 1];
            float out_l = in_l;
            float out_r = in_r;

            switch (profile_) {
                case AnalogWarmthProfile::Triode12AX7:
                    out_l = processTriode(in_l);
                    out_r = processTriode(in_r);
                    break;
                case AnalogWarmthProfile::MagneticTape:
                    out_l = processTape(in_l, tape_prev_l_);
                    out_r = processTape(in_r, tape_prev_r_);
                    break;
                case AnalogWarmthProfile::VintagePreamp:
                    out_l = processPreamp(in_l);
                    out_r = processPreamp(in_r);
                    break;
            }

            oversampled[2 * i]     = out_l;
            oversampled[2 * i + 1] = out_r;
        }

        // 3. Decimate and anti-alias filter back to 1x rate
        oversampler_.downsample(oversampled, interleaved_samples, frame_count);

        // 4. Post-processing at native rate (DC blocking & anti-pop crossfading)
        for (uint32_t i = 0; i < frame_count; i++) {
            float in_l = interleaved_samples[2 * i];
            float in_r = interleaved_samples[2 * i + 1];
            float out_l = in_l;
            float out_r = in_r;

            if (profile_ == AnalogWarmthProfile::Triode12AX7) {
                // The asymmetric triode transfer injects a DC bias. Block it per
                // channel with a gentle 10 Hz one-pole highpass.
                out_l = dc_block(out_l, dc_x_l_, dc_y_l_, dc_r_);
                out_r = dc_block(out_r, dc_x_r_, dc_y_r_, dc_r_);
            }

            // Anti-pop smooth crossfade on activation / preset change
            if (anti_pop_ < 1.0f) {
                out_l = in_l + anti_pop_ * (out_l - in_l);
                out_r = in_r + anti_pop_ * (out_r - in_r);
                anti_pop_ = std::min(1.0f, anti_pop_ + sample_period_ * 4.0f);
            }

            interleaved_samples[2 * i]     = out_l;
            interleaved_samples[2 * i + 1] = out_r;
        }
    }

private:
    bool enabled_ = false;
    AnalogWarmthProfile profile_ = AnalogWarmthProfile::Triode12AX7;
    float sample_rate_ = 48000.0f;
    float sample_period_ = 1.0f / 48000.0f;

    float target_drive_ = 0.5f;
    float current_drive_ = 0.5f;
    float smoothing_coeff_ = 0.001f;
    float anti_pop_ = 0.0f;

    // 2x Polyphase Half-Band Oversampler
    PolyphaseOversampler2x oversampler_;

    // Tape simulation high-frequency damping
    float tape_prev_l_ = 0.0f;
    float tape_prev_r_ = 0.0f;
    float tape_damping_ = 0.15f;

    // Per-channel DC blocker (10 Hz one-pole highpass) for the triode stage
    float dc_x_l_ = 0.0f, dc_y_l_ = 0.0f;
    float dc_x_r_ = 0.0f, dc_y_r_ = 0.0f;
    float dc_r_ = 0.99869f;

    // y[n] = x[n] - x[n-1] + R * y[n-1]
    static inline float dc_block(float x, float& x1, float& y1, float R) {
        const float y = x - x1 + R * y1 + 1.0e-20f; // denormal flush
        x1 = x;
        y1 = y;
        return y;
    }

    // Fast rational Padé approximation for hyperbolic tangent (~5x faster than std::tanh)
    static inline float fast_tanh(float x) {
        if (x < -3.0f) return -1.0f;
        if (x > 3.0f) return 1.0f;
        float x2 = x * x;
        return x * (27.0f + x2) / (27.0f + 9.0f * x2);
    }

    // 1. 12AX7 Triode Vacuum Tube (Asymmetric Even-Order Harmonics)
    inline float processTriode(float x) {
        float gain = 1.0f + current_drive_ * 2.5f;
        float driven = x * gain;

        // Asymmetric transfer function: positive swings compress differently than negative swings
        // Generates musical 2nd (octave) & 3rd harmonics
        float out;
        if (driven > 0.0f) {
            out = fast_tanh(driven);
        } else {
            // Negative swing has a softer, extended knee (classic triode grid characteristic)
            float neg = driven * 0.85f;
            out = fast_tanh(neg) / 0.85f;
        }

        // Add subtle quadratic even-harmonic warmth
        out += (driven * driven * 0.08f * current_drive_);

        // Level compensation so volume stays consistent
        float comp = 1.0f / (1.0f + current_drive_ * 0.5f);
        return out * comp;
    }

    // 2. Magnetic Tape Saturation (Symmetric Soft Hysteresis Compression + High-Frequency Smoothing)
    inline float processTape(float x, float& prev_state) {
        float gain = 1.0f + current_drive_ * 2.0f;
        float driven = x * gain;

        // Tape S-curve saturation
        float sat = fast_tanh(driven);

        // Gentle high-frequency damping (simulating tape head magnetic gap losses at 2x rate)
        float smoothed = sat * (1.0f - tape_damping_) + prev_state * tape_damping_;
        prev_state = sat;

        float comp = 1.0f / (1.0f + current_drive_ * 0.4f);
        return smoothed * comp;
    }

    // 3. Vintage Console Preamp (Subtle Class-A Harmonic Excitation)
    inline float processPreamp(float x) {
        float drive_scale = current_drive_ * 0.5f;
        float x2 = x * x;
        float x3 = x2 * x;

        // 3-term polynomial saturation: y = x - 0.15*x^2 - 0.1*x^3
        float out = x - (x2 * 0.15f * drive_scale) - (x3 * 0.10f * drive_scale);
        return std::clamp(out, -1.0f, 1.0f);
    }

    void updateTapeFilter() {
        // High-frequency damping calibrated for 2x oversampled rate
        tape_damping_ = std::clamp(6000.0f / (sample_rate_ * 2.0f), 0.025f, 0.25f);
    }
};

} // namespace sauti::dsp
