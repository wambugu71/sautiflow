#pragma once

#include <cmath>
#include <cstdint>
#include <algorithm>
#include <vector>
#include "oversampler.h"

namespace sauti::dsp {

enum class AudioClarityProfile {
    TransientCrisp = 0,      // Rate-of-change pre-emphasis with Nyquist anti-aliasing reconstruction
    AirShelf = 1,            // 12 kHz ultra-high shelf for upper harmonic sparkle and breath
    PresenceExciter = 2,      // 3-way multi-band crossover with selective upper-mid and high excitation
    HarmonicBrilliance = 3   // Aural Exciter (3.5 kHz HPF sidechain -> oversampled non-linear harmonic synthesis)
};

// =============================================================================
// AudioClarityDSP: Professional High-Frequency Enhancer & Multi-Band Exciter
// with 2x Polyphase Half-Band Oversampling on Harmonic Brilliance,
// De-Zippered Parameter Smoothing, and Anti-Pop Crossfading.
// =============================================================================
class AudioClarityDSP {
public:
    AudioClarityDSP() {
        setSampleRate(48000.0f);
        reset();
    }

    void setSampleRate(float sampleRate) {
        if (sampleRate <= 0.0f) sampleRate = 48000.0f;
        if (std::abs(sample_rate_ - sampleRate) < 0.1f) return;
        sample_rate_ = sampleRate;
        sample_period_ = 1.0f / sample_rate_;
        smoothing_coeff_ = 1.0f - std::exp(-1.0f / (0.030f * sample_rate_)); // 30ms smoothing
        updateFilters();
        oversampler_.init(static_cast<int>(sample_rate_), 4096);
        sidechain_buf_.resize(4096 * 2, 0.0f);
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

    void setProfile(AudioClarityProfile profile) {
        if (profile_ != profile) {
            profile_ = profile;
            reset();
            updateFilters();
        }
    }

    AudioClarityProfile getProfile() const { return profile_; }

    // Intensity factor in range [0.0, 1.0]
    void setIntensity(float intensity) {
        target_intensity_ = std::clamp(intensity, 0.0f, 1.0f);
        updateFilters();
    }

    float getIntensity() const { return target_intensity_; }

    void reset() {
        prev_sample_l_ = 0.0f;
        prev_sample_r_ = 0.0f;
        
        // Reset 1st-order smoothing filter states
        smooth_state_l_ = 0.0f;
        smooth_state_r_ = 0.0f;

        // Reset Air Shelf biquad states
        air_x1_l_ = air_x2_l_ = air_y1_l_ = air_y2_l_ = 0.0f;
        air_x1_r_ = air_x2_r_ = air_y1_r_ = air_y2_r_ = 0.0f;

        // Reset 3-Way Crossover filter states
        x_low_x1_l_ = x_low_x2_l_ = x_low_y1_l_ = x_low_y2_l_ = 0.0f;
        x_low_x1_r_ = x_low_x2_r_ = x_low_y1_r_ = x_low_y2_r_ = 0.0f;

        x_mid_x1_l_ = x_mid_x2_l_ = x_mid_y1_l_ = x_mid_y2_l_ = 0.0f;
        x_mid_x1_r_ = x_mid_x2_r_ = x_mid_y1_r_ = x_mid_y2_r_ = 0.0f;

        x_high_x1_l_ = x_high_x2_l_ = x_high_y1_l_ = x_high_y2_l_ = 0.0f;
        x_high_x1_r_ = x_high_x2_r_ = x_high_y1_r_ = x_high_y2_r_ = 0.0f;

        // Reset Harmonic Brilliance sidechain states
        brill_hp_x1_l_ = brill_hp_x2_l_ = brill_hp_y1_l_ = brill_hp_y2_l_ = 0.0f;
        brill_hp_x1_r_ = brill_hp_x2_r_ = brill_hp_y1_r_ = brill_hp_y2_r_ = 0.0f;

        current_intensity_ = target_intensity_;
        anti_pop_ = 0.0f;
        oversampler_.reset();
    }

    // Process interleaved stereo samples: [L0, R0, L1, R1, ...]
    void process(float* interleaved_samples, uint32_t frame_count) {
        if (!enabled_ || frame_count == 0 || !interleaved_samples) return;

        switch (profile_) {
            case AudioClarityProfile::TransientCrisp:
                processTransientCrisp(interleaved_samples, frame_count);
                break;
            case AudioClarityProfile::AirShelf:
                processAirShelf(interleaved_samples, frame_count);
                break;
            case AudioClarityProfile::PresenceExciter:
                processPresenceExciter(interleaved_samples, frame_count);
                break;
            case AudioClarityProfile::HarmonicBrilliance:
                processHarmonicBrilliance(interleaved_samples, frame_count);
                break;
        }
    }

private:
    bool enabled_ = false;
    AudioClarityProfile profile_ = AudioClarityProfile::TransientCrisp;
    float sample_rate_ = 48000.0f;
    float sample_period_ = 1.0f / 48000.0f;
    float target_intensity_ = 0.5f;
    float current_intensity_ = 0.5f;
    float smoothing_coeff_ = 0.002f;
    float anti_pop_ = 0.0f;

    // 2x Polyphase Half-Band Oversampler for Harmonic Brilliance
    PolyphaseOversampler2x oversampler_;
    std::vector<float> sidechain_buf_;

    // --- Profile 1: Transient Crisp (Differential Enhancer + Reconstruction Filter) ---
    float prev_sample_l_ = 0.0f;
    float prev_sample_r_ = 0.0f;
    float smooth_b0_ = 1.0f;
    float smooth_b1_ = 0.0f;
    float smooth_a1_ = 0.0f;
    float smooth_state_l_ = 0.0f;
    float smooth_state_r_ = 0.0f;

    void processTransientCrisp(float* samples, uint32_t frame_count) {
        for (uint32_t i = 0; i < frame_count; i++) {
            current_intensity_ += smoothing_coeff_ * (target_intensity_ - current_intensity_);
            const float diff_scale = current_intensity_ * 1.5f;

            float in_l = samples[2 * i];
            float in_r = samples[2 * i + 1];

            // Transient differentiator
            float diff_l = (in_l - prev_sample_l_) * diff_scale;
            float diff_r = (in_r - prev_sample_r_) * diff_scale;
            prev_sample_l_ = in_l;
            prev_sample_r_ = in_r;

            float sharp_l = in_l + diff_l;
            float sharp_r = in_r + diff_r;

            // Direct Form I smoothing low-pass
            float out_l = sharp_l * smooth_b0_ + smooth_state_l_;
            smooth_state_l_ = sharp_l * smooth_b1_ - out_l * smooth_a1_;

            float out_r = sharp_r * smooth_b0_ + smooth_state_r_;
            smooth_state_r_ = sharp_r * smooth_b1_ - out_r * smooth_a1_;

            if (anti_pop_ < 1.0f) {
                out_l = in_l + anti_pop_ * (out_l - in_l);
                out_r = in_r + anti_pop_ * (out_r - in_r);
                anti_pop_ = std::min(1.0f, anti_pop_ + sample_period_ * 4.0f);
            }

            samples[2 * i]     = out_l;
            samples[2 * i + 1] = out_r;
        }
    }

    // --- Profile 2: Air Shelf (12 kHz High-Shelf Biquad) ---
    float air_b0_ = 1.0f, air_b1_ = 0.0f, air_b2_ = 0.0f;
    float air_a1_ = 0.0f, air_a2_ = 0.0f;
    float air_x1_l_ = 0.0f, air_x2_l_ = 0.0f, air_y1_l_ = 0.0f, air_y2_l_ = 0.0f;
    float air_x1_r_ = 0.0f, air_x2_r_ = 0.0f, air_y1_r_ = 0.0f, air_y2_r_ = 0.0f;

    void processAirShelf(float* samples, uint32_t frame_count) {
        for (uint32_t i = 0; i < frame_count; i++) {
            float in_l = samples[2 * i];
            float in_r = samples[2 * i + 1];

            float out_l = air_b0_ * in_l + air_b1_ * air_x1_l_ + air_b2_ * air_x2_l_
                        - air_a1_ * air_y1_l_ - air_a2_ * air_y2_l_;
            air_x2_l_ = air_x1_l_; air_x1_l_ = in_l;
            air_y2_l_ = air_y1_l_; air_y1_l_ = out_l;

            float out_r = air_b0_ * in_r + air_b1_ * air_x1_r_ + air_b2_ * air_x2_r_
                        - air_a1_ * air_y1_r_ - air_a2_ * air_y2_r_;
            air_x2_r_ = air_x1_r_; air_x1_r_ = in_r;
            air_y2_r_ = air_y1_r_; air_y1_r_ = out_r;

            if (anti_pop_ < 1.0f) {
                out_l = in_l + anti_pop_ * (out_l - in_l);
                out_r = in_r + anti_pop_ * (out_r - in_r);
                anti_pop_ = std::min(1.0f, anti_pop_ + sample_period_ * 4.0f);
            }

            samples[2 * i]     = out_l;
            samples[2 * i + 1] = out_r;
        }
    }

    // --- Profile 3: Presence Exciter (3-Way Crossover: Low <120Hz, Mid 120-1200Hz, High >1200Hz) ---
    float x_low_b0_ = 1.0f, x_low_b1_ = 0.0f, x_low_b2_ = 0.0f, x_low_a1_ = 0.0f, x_low_a2_ = 0.0f;
    float x_mid_b0_ = 1.0f, x_mid_b1_ = 0.0f, x_mid_b2_ = 0.0f, x_mid_a1_ = 0.0f, x_mid_a2_ = 0.0f;
    float x_high_b0_ = 1.0f, x_high_b1_ = 0.0f, x_high_b2_ = 0.0f, x_high_a1_ = 0.0f, x_high_a2_ = 0.0f;

    float x_low_x1_l_ = 0.0f, x_low_x2_l_ = 0.0f, x_low_y1_l_ = 0.0f, x_low_y2_l_ = 0.0f;
    float x_low_x1_r_ = 0.0f, x_low_x2_r_ = 0.0f, x_low_y1_r_ = 0.0f, x_low_y2_r_ = 0.0f;

    float x_mid_x1_l_ = 0.0f, x_mid_x2_l_ = 0.0f, x_mid_y1_l_ = 0.0f, x_mid_y2_l_ = 0.0f;
    float x_mid_x1_r_ = 0.0f, x_mid_x2_r_ = 0.0f, x_mid_y1_r_ = 0.0f, x_mid_y2_r_ = 0.0f;

    float x_high_x1_l_ = 0.0f, x_high_x2_l_ = 0.0f, x_high_y1_l_ = 0.0f, x_high_y2_l_ = 0.0f;
    float x_high_x1_r_ = 0.0f, x_high_x2_r_ = 0.0f, x_high_y1_r_ = 0.0f, x_high_y2_r_ = 0.0f;

    void processPresenceExciter(float* samples, uint32_t frame_count) {
        for (uint32_t i = 0; i < frame_count; i++) {
            current_intensity_ += smoothing_coeff_ * (target_intensity_ - current_intensity_);
            const float mid_gain = 1.0f + current_intensity_ * 0.4f;
            const float high_gain = 1.0f + current_intensity_ * 0.8f;

            float in_l = samples[2 * i];
            float in_r = samples[2 * i + 1];

            // Left Channel
            float low_l = x_low_b0_ * in_l + x_low_b1_ * x_low_x1_l_ + x_low_b2_ * x_low_x2_l_ - x_low_a1_ * x_low_y1_l_ - x_low_a2_ * x_low_y2_l_;
            x_low_x2_l_ = x_low_x1_l_; x_low_x1_l_ = in_l; x_low_y2_l_ = x_low_y1_l_; x_low_y1_l_ = low_l;

            float high_l = x_high_b0_ * in_l + x_high_b1_ * x_high_x1_l_ + x_high_b2_ * x_high_x2_l_ - x_high_a1_ * x_high_y1_l_ - x_high_a2_ * x_high_y2_l_;
            x_high_x2_l_ = x_high_x1_l_; x_high_x1_l_ = in_l; x_high_y2_l_ = x_high_y1_l_; x_high_y1_l_ = high_l;

            // Right Channel
            float low_r = x_low_b0_ * in_r + x_low_b1_ * x_low_x1_r_ + x_low_b2_ * x_low_x2_r_ - x_low_a1_ * x_low_y1_r_ - x_low_a2_ * x_low_y2_r_;
            x_low_x2_r_ = x_low_x1_r_; x_low_x1_r_ = in_r; x_low_y2_r_ = x_low_y1_r_; x_low_y1_r_ = low_r;

            float high_r = x_high_b0_ * in_r + x_high_b1_ * x_high_x1_r_ + x_high_b2_ * x_high_x2_r_ - x_high_a1_ * x_high_y1_r_ - x_high_a2_ * x_high_y2_r_;
            x_high_x2_r_ = x_high_x1_r_; x_high_x1_r_ = in_r; x_high_y2_r_ = x_high_y1_r_; x_high_y1_r_ = high_r;

            // Mid band derived by subtraction (in - low - high) for flat sum
            const float mid_l = in_l - low_l - high_l;
            const float mid_r = in_r - low_r - high_r;

            float out_l = low_l + (mid_l * mid_gain) + (high_l * high_gain);
            float out_r = low_r + (mid_r * mid_gain) + (high_r * high_gain);

            if (anti_pop_ < 1.0f) {
                out_l = in_l + anti_pop_ * (out_l - in_l);
                out_r = in_r + anti_pop_ * (out_r - in_r);
                anti_pop_ = std::min(1.0f, anti_pop_ + sample_period_ * 4.0f);
            }

            samples[2 * i]     = out_l;
            samples[2 * i + 1] = out_r;
        }
    }

    // --- Profile 4: Harmonic Brilliance (Aural Exciter: 3.5 kHz HPF -> 2x Oversampled Soft Asymmetric Saturation) ---
    float brill_hp_b0_ = 1.0f, brill_hp_b1_ = 0.0f, brill_hp_b2_ = 0.0f;
    float brill_hp_a1_ = 0.0f, brill_hp_a2_ = 0.0f;
    float brill_hp_x1_l_ = 0.0f, brill_hp_x2_l_ = 0.0f, brill_hp_y1_l_ = 0.0f, brill_hp_y2_l_ = 0.0f;
    float brill_hp_x1_r_ = 0.0f, brill_hp_x2_r_ = 0.0f, brill_hp_y1_r_ = 0.0f, brill_hp_y2_r_ = 0.0f;

    void processHarmonicBrilliance(float* samples, uint32_t frame_count) {
        if (sidechain_buf_.size() < frame_count * 2) {
            sidechain_buf_.resize(frame_count * 2);
        }

        // 1. High-pass filter sidechain at 3.5 kHz (native rate)
        for (uint32_t i = 0; i < frame_count; i++) {
            float in_l = samples[2 * i];
            float in_r = samples[2 * i + 1];

            float hp_l = brill_hp_b0_ * in_l + brill_hp_b1_ * brill_hp_x1_l_ + brill_hp_b2_ * brill_hp_x2_l_
                       - brill_hp_a1_ * brill_hp_y1_l_ - brill_hp_a2_ * brill_hp_y2_l_;
            brill_hp_x2_l_ = brill_hp_x1_l_; brill_hp_x1_l_ = in_l;
            brill_hp_y2_l_ = brill_hp_y1_l_; brill_hp_y1_l_ = hp_l;

            float hp_r = brill_hp_b0_ * in_r + brill_hp_b1_ * brill_hp_x1_r_ + brill_hp_b2_ * brill_hp_x2_r_
                       - brill_hp_a1_ * brill_hp_y1_r_ - brill_hp_a2_ * brill_hp_y2_r_;
            brill_hp_x2_r_ = brill_hp_x1_r_; brill_hp_x1_r_ = in_r;
            brill_hp_y2_r_ = brill_hp_y1_r_; brill_hp_y1_r_ = hp_r;

            sidechain_buf_[2 * i]     = hp_l;
            sidechain_buf_[2 * i + 1] = hp_r;
        }

        // 2. Upsample sidechain 2x
        float* os_hp = oversampler_.upsample(sidechain_buf_.data(), frame_count);
        if (!os_hp) return;

        const uint32_t os_frames = frame_count * 2;
        for (uint32_t i = 0; i < os_frames; i++) {
            float hp_l = os_hp[2 * i];
            float hp_r = os_hp[2 * i + 1];

            // Asymmetric even+odd harmonic saturation in the oversampled domain
            float harm_l = std::tanh(hp_l * 2.2f) + 0.25f * (hp_l * hp_l);
            float harm_r = std::tanh(hp_r * 2.2f) + 0.25f * (hp_r * hp_r);

            os_hp[2 * i]     = harm_l;
            os_hp[2 * i + 1] = harm_r;
        }

        // 3. Decimate and anti-alias filter generated harmonics back to native rate
        oversampler_.downsample(os_hp, sidechain_buf_.data(), frame_count);

        // 4. Mix back into dry signal at native rate with smoothed intensity
        for (uint32_t i = 0; i < frame_count; i++) {
            current_intensity_ += smoothing_coeff_ * (target_intensity_ - current_intensity_);
            const float mix = current_intensity_ * 0.45f;

            float in_l = samples[2 * i];
            float in_r = samples[2 * i + 1];

            float out_l = in_l + sidechain_buf_[2 * i] * mix;
            float out_r = in_r + sidechain_buf_[2 * i + 1] * mix;

            if (anti_pop_ < 1.0f) {
                out_l = in_l + anti_pop_ * (out_l - in_l);
                out_r = in_r + anti_pop_ * (out_r - in_r);
                anti_pop_ = std::min(1.0f, anti_pop_ + sample_period_ * 4.0f);
            }

            samples[2 * i]     = out_l;
            samples[2 * i + 1] = out_r;
        }
    }

    void updateFilters() {
        constexpr float PI = 3.14159265358979323846f;

        // 1. Transient Smoothing Filter: 1st-order low-pass at 18 kHz
        float fc = std::min(18000.0f, sample_rate_ * 0.45f);
        float w0 = 2.0f * PI * fc / sample_rate_;
        float gamma = std::cos(w0) / (1.0f + std::sin(w0));
        smooth_a1_ = -gamma;
        smooth_b0_ = (1.0f - gamma) * 0.5f;
        smooth_b1_ = (1.0f - gamma) * 0.5f;

        // 2. Air Shelf: 12 kHz High-Shelf Biquad (+0 dB to +8 dB)
        float shelf_gain_db = target_intensity_ * 8.0f;
        calcHighshelf(12000.0f, shelf_gain_db, air_b0_, air_b1_, air_b2_, air_a1_, air_a2_);

        // 3. 3-Way Crossover:
        calcLowpass(120.0f, 0.7071f, x_low_b0_, x_low_b1_, x_low_b2_, x_low_a1_, x_low_a2_);
        calcBandpass(400.0f, 0.6f, x_mid_b0_, x_mid_b1_, x_mid_b2_, x_mid_a1_, x_mid_a2_);
        calcHighpass(1200.0f, 0.7071f, x_high_b0_, x_high_b1_, x_high_b2_, x_high_a1_, x_high_a2_);

        // 4. Harmonic Brilliance 3.5 kHz HPF:
        calcHighpass(3500.0f, 0.7071f, brill_hp_b0_, brill_hp_b1_, brill_hp_b2_, brill_hp_a1_, brill_hp_a2_);
    }

    void calcHighshelf(float freq, float gain_db, float& b0, float& b1, float& b2, float& a1, float& a2) {
        constexpr double PI = 3.14159265358979323846;
        const double A = std::pow(10.0, static_cast<double>(gain_db) / 40.0);
        double w0 = 2.0 * PI * static_cast<double>(freq) / static_cast<double>(sample_rate_);
        if (w0 > PI * 0.95) w0 = PI * 0.95;
        const double cos_w0 = std::cos(w0);
        const double sin_w0 = std::sin(w0);
        const double alpha = sin_w0 / 2.0 * std::sqrt((A + 1.0 / A) * (1.0 / 0.7071 - 1.0) + 2.0);
        const double sqrt_A = 2.0 * std::sqrt(A) * alpha;

        const double a0 = (A + 1.0) - (A - 1.0) * cos_w0 + sqrt_A;
        b0 = static_cast<float>((A * ((A + 1.0) + (A - 1.0) * cos_w0 + sqrt_A)) / a0);
        b1 = static_cast<float>((-2.0 * A * ((A - 1.0) + (A + 1.0) * cos_w0)) / a0);
        b2 = static_cast<float>((A * ((A + 1.0) + (A - 1.0) * cos_w0 - sqrt_A)) / a0);
        a1 = static_cast<float>((2.0 * ((A - 1.0) - (A + 1.0) * cos_w0)) / a0);
        a2 = static_cast<float>(((A + 1.0) - (A - 1.0) * cos_w0 - sqrt_A) / a0);
    }

    void calcLowpass(float freq, float Q, float& b0, float& b1, float& b2, float& a1, float& a2) {
        constexpr double PI = 3.14159265358979323846;
        double w0 = 2.0 * PI * static_cast<double>(freq) / static_cast<double>(sample_rate_);
        if (w0 > PI * 0.95) w0 = PI * 0.95;
        const double cos_w0 = std::cos(w0);
        const double sin_w0 = std::sin(w0);
        const double alpha = sin_w0 / (2.0 * static_cast<double>(Q));

        const double a0 = 1.0 + alpha;
        b0 = static_cast<float>(((1.0 - cos_w0) / 2.0) / a0);
        b1 = static_cast<float>((1.0 - cos_w0) / a0);
        b2 = static_cast<float>(((1.0 - cos_w0) / 2.0) / a0);
        a1 = static_cast<float>((-2.0 * cos_w0) / a0);
        a2 = static_cast<float>((1.0 - alpha) / a0);
    }

    void calcHighpass(float freq, float Q, float& b0, float& b1, float& b2, float& a1, float& a2) {
        constexpr double PI = 3.14159265358979323846;
        double w0 = 2.0 * PI * static_cast<double>(freq) / static_cast<double>(sample_rate_);
        if (w0 > PI * 0.95) w0 = PI * 0.95;
        const double cos_w0 = std::cos(w0);
        const double sin_w0 = std::sin(w0);
        const double alpha = sin_w0 / (2.0 * static_cast<double>(Q));

        const double a0 = 1.0 + alpha;
        b0 = static_cast<float>(((1.0 + cos_w0) / 2.0) / a0);
        b1 = static_cast<float>(-(1.0 + cos_w0) / a0);
        b2 = static_cast<float>(((1.0 + cos_w0) / 2.0) / a0);
        a1 = static_cast<float>((-2.0 * cos_w0) / a0);
        a2 = static_cast<float>((1.0 - alpha) / a0);
    }

    void calcBandpass(float freq, float Q, float& b0, float& b1, float& b2, float& a1, float& a2) {
        constexpr double PI = 3.14159265358979323846;
        double w0 = 2.0 * PI * static_cast<double>(freq) / static_cast<double>(sample_rate_);
        if (w0 > PI * 0.95) w0 = PI * 0.95;
        const double cos_w0 = std::cos(w0);
        const double sin_w0 = std::sin(w0);
        const double alpha = sin_w0 / (2.0 * static_cast<double>(Q));

        const double a0 = 1.0 + alpha;
        b0 = static_cast<float>((alpha) / a0);
        b1 = 0.0f;
        b2 = static_cast<float>((-alpha) / a0);
        a1 = static_cast<float>((-2.0 * cos_w0) / a0);
        a2 = static_cast<float>((1.0 - alpha) / a0);
    }
};

} // namespace sauti::dsp
