#pragma once

#include <cmath>
#include <cstdint>
#include <algorithm>
#include <vector>
#include "denormals.h"

namespace sauti::dsp {

enum class DialogEnhancerProfile {
    Cinema = 0,    // Strong vocal formant emphasis + dynamic background ducking (ideal for movies)
    Music = 1,     // Natural vocal presence lift with subtle background attenuation
    Voice = 2,     // Maximum speech intelligibility (podcasts, news, audiobooks)
    Night = 3,     // Balanced dialogue boost with background sound containment
    Custom = 4     // Full manual user control over all parameters
};

// =============================================================================
// DialogEnhancerDSP: Clean-room dialogue booster & background noise ducking
// reconstructed from Dolby DAP / DS1 Dialog Enhancer architecture.
//
// Key Subsystems:
//   1. Vocal Formant Peaking Filter: 2400 Hz (Q = 1.25) primary speech intelligibility
//   2. Speech Body Formant Filter: 1200 Hz (Q = 1.0) vowel fullness & resonance
//   3. Speech Presence & Consonant Crispness Filter: 3800 Hz (Q = 1.3) articulation
//   4. Mid-Side Speech Isolation & Dynamic Ducking:
//      Extracts phantom center dialogue (M = (L+R)/2) and dynamically attenuates
//      ambient/surround side content (S = (L-R)/2) during dialogue presence.
//   5. De-zippered parameter smoothing (30ms tau) and anti-pop crossfading.
// =============================================================================
class DialogEnhancerDSP {
public:
    DialogEnhancerDSP() {
        setSampleRate(48000.0f);
        reset();
    }

    void setSampleRate(float sampleRate) {
        if (sampleRate <= 0.0f) sampleRate = 48000.0f;
        if (std::abs(sample_rate_ - sampleRate) < 0.1f) return;
        sample_rate_ = sampleRate;
        sample_period_ = 1.0f / sample_rate_;
        smoothing_coeff_ = 1.0f - std::exp(-1.0f / (0.030f * sample_rate_)); // 30ms smoothing

        // Attack/release for speech envelope detection (fast 15ms attack, 120ms release)
        env_attack_coeff_ = 1.0f - std::exp(-1.0f / (0.015f * sample_rate_));
        env_release_coeff_ = 1.0f - std::exp(-1.0f / (0.120f * sample_rate_));

        recalcBiquads();
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

    void setProfile(DialogEnhancerProfile profile) {
        if (profile_ != profile) {
            profile_ = profile;
            applyProfileDefaults();
        }
    }

    DialogEnhancerProfile getProfile() const { return profile_; }

    // Dialogue Boost Amount: [0.0, 1.0] -> 0 dB to +12 dB formant gain
    void setAmount(float amount) {
        target_amount_ = std::clamp(amount, 0.0f, 1.0f);
        if (profile_ != DialogEnhancerProfile::Custom) {
            profile_ = DialogEnhancerProfile::Custom;
        }
    }

    float getAmount() const { return target_amount_; }

    // Dialogue Ducking: [0.0, 1.0] -> 0% to 70% background/side suppression
    void setDucking(float ducking) {
        target_ducking_ = std::clamp(ducking, 0.0f, 1.0f);
        if (profile_ != DialogEnhancerProfile::Custom) {
            profile_ = DialogEnhancerProfile::Custom;
        }
    }

    float getDucking() const { return target_ducking_; }

    // Vocal Clarity / High Formant Definition: [0.0, 1.0]
    void setClarity(float clarity) {
        target_clarity_ = std::clamp(clarity, 0.0f, 1.0f);
        if (profile_ != DialogEnhancerProfile::Custom) {
            profile_ = DialogEnhancerProfile::Custom;
        }
    }

    float getClarity() const { return target_clarity_; }

    // Center Speech Focus (phantom center weighting): [0.0, 1.0]
    void setCenterFocus(float centerFocus) {
        target_center_focus_ = std::clamp(centerFocus, 0.0f, 1.0f);
        if (profile_ != DialogEnhancerProfile::Custom) {
            profile_ = DialogEnhancerProfile::Custom;
        }
    }

    float getCenterFocus() const { return target_center_focus_; }

    // Direct multi-parameter configuration
    void setParams(DialogEnhancerProfile profile, float amount, float ducking, float clarity, float centerFocus) {
        profile_ = profile;
        if (profile != DialogEnhancerProfile::Custom) {
            applyProfileDefaults();
        } else {
            target_amount_ = std::clamp(amount, 0.0f, 1.0f);
            target_ducking_ = std::clamp(ducking, 0.0f, 1.0f);
            target_clarity_ = std::clamp(clarity, 0.0f, 1.0f);
            target_center_focus_ = std::clamp(centerFocus, 0.0f, 1.0f);
        }
    }

    // Telemetry / metering: current ducking gain reduction in dB
    float getGainReductionDb() const {
        return last_ducking_reduction_db_;
    }

    void reset() {
        current_amount_ = target_amount_;
        current_ducking_ = target_ducking_;
        current_clarity_ = target_clarity_;
        current_center_focus_ = target_center_focus_;

        formant_x1_ = formant_x2_ = formant_y1_ = formant_y2_ = 0.0f;
        body_x1_ = body_x2_ = body_y1_ = body_y2_ = 0.0f;
        clarity_x1_ = clarity_x2_ = clarity_y1_ = clarity_y2_ = 0.0f;

        speech_energy_env_ = 0.0f;
        last_ducking_reduction_db_ = 0.0f;
        anti_pop_ = 0.0f;

        recalcBiquads();
    }

    // Process interleaved stereo samples: [L0, R0, L1, R1, ...]
    void process(float* interleaved_samples, uint32_t frame_count) {
        if (!enabled_ || frame_count == 0 || !interleaved_samples) return;

        ScopedDenormalsDisable denormals;

        const float anti_pop_step = 1.0f / (0.015f * sample_rate_); // 15ms anti-pop ramp

        for (uint32_t i = 0; i < frame_count; ++i) {
            // 1. Parameter de-zippering / smoothing
            current_amount_ += smoothing_coeff_ * (target_amount_ - current_amount_);
            current_ducking_ += smoothing_coeff_ * (target_ducking_ - current_ducking_);
            current_clarity_ += smoothing_coeff_ * (target_clarity_ - current_clarity_);
            current_center_focus_ += smoothing_coeff_ * (target_center_focus_ - current_center_focus_);

            // Recalculate coefficients if amount or clarity has shifted appreciably
            if (std::abs(current_amount_ - cached_amount_) > 0.005f ||
                std::abs(current_clarity_ - cached_clarity_) > 0.005f) {
                recalcBiquads();
            }

            if (anti_pop_ < 1.0f) {
                anti_pop_ = std::min(1.0f, anti_pop_ + anti_pop_step);
            }

            float in_l = interleaved_samples[2 * i];
            float in_r = interleaved_samples[2 * i + 1];

            // 2. Mid-Side decomposition
            float mid = 0.5f * (in_l + in_r);
            float side = 0.5f * (in_l - in_r);

            // 3. Multi-stage vocal formant enhancement on center/mid channel
            // Stage A: Main Vocal Formant Peaking Filter (2.4 kHz)
            float mid_formant = b0_formant_ * mid + b1_formant_ * formant_x1_ + b2_formant_ * formant_x2_
                                - a1_formant_ * formant_y1_ - a2_formant_ * formant_y2_;
            formant_x2_ = formant_x1_;
            formant_x1_ = mid;
            formant_y2_ = formant_y1_;
            formant_y1_ = mid_formant;

            // Stage B: Speech Body Peaking Filter (1.2 kHz)
            float mid_body = b0_body_ * mid_formant + b1_body_ * body_x1_ + b2_body_ * body_x2_
                             - a1_body_ * body_y1_ - a2_body_ * body_y2_;
            body_x2_ = body_x1_;
            body_x1_ = mid_formant;
            body_y2_ = body_y1_;
            body_y1_ = mid_body;

            // Stage C: Speech Articulation & Consonant Clarity Filter (3.8 kHz)
            float mid_enhanced = b0_clarity_ * mid_body + b1_clarity_ * clarity_x1_ + b2_clarity_ * clarity_x2_
                                 - a1_clarity_ * clarity_y1_ - a2_clarity_ * clarity_y2_;
            clarity_x2_ = clarity_x1_;
            clarity_x1_ = mid_body;
            clarity_y2_ = clarity_y1_;
            clarity_y1_ = mid_enhanced;

            // 4. Speech energy envelope detection for dynamic background ducking
            float abs_speech = std::fabs(mid_enhanced);
            if (abs_speech > speech_energy_env_) {
                speech_energy_env_ += env_attack_coeff_ * (abs_speech - speech_energy_env_);
            } else {
                speech_energy_env_ += env_release_coeff_ * (abs_speech - speech_energy_env_);
            }

            // Ducking attenuation curve: active above nominal dialogue threshold (-36 dB ~ 0.015)
            float speech_activity = std::clamp((speech_energy_env_ - 0.012f) * 6.0f, 0.0f, 1.0f);
            float max_ducking_linear = 1.0f - (current_ducking_ * 0.65f); // up to ~-9 dB ducking
            float current_side_gain = 1.0f - speech_activity * (1.0f - max_ducking_linear);

            // Center focus: strengthens mid while narrowing side slightly
            float mid_gain = 1.0f + current_center_focus_ * 0.25f;
            float side_gain = current_side_gain * (1.0f - current_center_focus_ * 0.20f);

            float out_mid = mid_enhanced * mid_gain;
            float out_side = side * side_gain;

            // 5. Mid-Side synthesis back to Left & Right
            float proc_l = out_mid + out_side;
            float proc_r = out_mid - out_side;

            // 6. Anti-pop crossfade with dry signal
            interleaved_samples[2 * i] = in_l + anti_pop_ * (proc_l - in_l);
            interleaved_samples[2 * i + 1] = in_r + anti_pop_ * (proc_r - in_r);
        }

        // Store latest telemetry reduction
        if (target_ducking_ > 0.001f) {
            float speech_act = std::clamp((speech_energy_env_ - 0.012f) * 6.0f, 0.0f, 1.0f);
            float max_duck = 1.0f - (current_ducking_ * 0.65f);
            float lin = 1.0f - speech_act * (1.0f - max_duck);
            last_ducking_reduction_db_ = (lin > 0.001f) ? (20.0f * std::log10(lin)) : -12.0f;
        } else {
            last_ducking_reduction_db_ = 0.0f;
        }
    }

private:
    void applyProfileDefaults() {
        switch (profile_) {
            case DialogEnhancerProfile::Cinema:
                target_amount_ = 0.65f;       // ~+7.5 dB boost
                target_ducking_ = 0.55f;      // moderate background ducking
                target_clarity_ = 0.60f;      // clear dialogue
                target_center_focus_ = 0.70f; // strong center focus
                break;
            case DialogEnhancerProfile::Music:
                target_amount_ = 0.35f;       // ~+4.0 dB vocal presence
                target_ducking_ = 0.20f;      // preserve musical backing
                target_clarity_ = 0.40f;      // natural vocal timbre
                target_center_focus_ = 0.35f; // broad soundstage
                break;
            case DialogEnhancerProfile::Voice:
                target_amount_ = 0.85f;       // ~+9.5 dB speech lift
                target_ducking_ = 0.65f;      // high ambient attenuation
                target_clarity_ = 0.75f;      // crisp articulation
                target_center_focus_ = 0.85f; // direct voice anchor
                break;
            case DialogEnhancerProfile::Night:
                target_amount_ = 0.50f;       // ~+6.0 dB boost
                target_ducking_ = 0.40f;      // soft suppression
                target_clarity_ = 0.45f;      // gentle presence
                target_center_focus_ = 0.50f; // balanced
                break;
            case DialogEnhancerProfile::Custom:
                break;
        }
        recalcBiquads();
    }

    static void calcPeakingBiquad(float f0, float gain_db, float q, float fs,
                                  float& b0, float& b1, float& b2, float& a1, float& a2) {
        if (std::abs(gain_db) < 0.05f) {
            b0 = 1.0f; b1 = 0.0f; b2 = 0.0f;
            a1 = 0.0f; a2 = 0.0f;
            return;
        }
        // Audio EQ Cookbook peaking formula (same as Dolby player reference)
        const double A = std::pow(10.0, static_cast<double>(gain_db) / 40.0);
        const double w0 = 2.0 * 3.14159265358979323846 * static_cast<double>(f0) / static_cast<double>(fs);
        const double alpha = std::sin(w0) / (2.0 * static_cast<double>(q));
        const double a0 = 1.0 + alpha / A;

        b0 = static_cast<float>((1.0 + alpha * A) / a0);
        b1 = static_cast<float>((-2.0 * std::cos(w0)) / a0);
        b2 = static_cast<float>((1.0 - alpha * A) / a0);
        a1 = static_cast<float>((-2.0 * std::cos(w0)) / a0);
        a2 = static_cast<float>((1.0 - alpha / A) / a0);
    }

    void recalcBiquads() {
        cached_amount_ = current_amount_;
        cached_clarity_ = current_clarity_;

        // 1. Primary vocal formant peak at 2400 Hz (Dolby DAP reference formant frequency)
        // Amount [0.0, 1.0] maps from 0.0 dB to +11.0 dB
        float formant_gain_db = current_amount_ * 11.0f;
        calcPeakingBiquad(2400.0f, formant_gain_db, 1.25f, sample_rate_,
                          b0_formant_, b1_formant_, b2_formant_, a1_formant_, a2_formant_);

        // 2. Vocal body formant peak at 1200 Hz for warm intelligible fullness
        float body_gain_db = current_amount_ * 3.5f;
        calcPeakingBiquad(1200.0f, body_gain_db, 1.0f, sample_rate_,
                          b0_body_, b1_body_, b2_body_, a1_body_, a2_body_);

        // 3. Consonant clarity & presence peak at 3800 Hz
        float clarity_gain_db = current_clarity_ * 5.0f;
        calcPeakingBiquad(3800.0f, clarity_gain_db, 1.3f, sample_rate_,
                          b0_clarity_, b1_clarity_, b2_clarity_, a1_clarity_, a2_clarity_);
    }

    bool enabled_ = false;
    DialogEnhancerProfile profile_ = DialogEnhancerProfile::Cinema;

    float sample_rate_ = 48000.0f;
    float sample_period_ = 1.0f / 48000.0f;
    float smoothing_coeff_ = 0.05f;
    float env_attack_coeff_ = 0.1f;
    float env_release_coeff_ = 0.01f;

    float target_amount_ = 0.65f;
    float current_amount_ = 0.65f;
    float cached_amount_ = -1.0f;

    float target_ducking_ = 0.55f;
    float current_ducking_ = 0.55f;

    float target_clarity_ = 0.60f;
    float current_clarity_ = 0.60f;
    float cached_clarity_ = -1.0f;

    float target_center_focus_ = 0.70f;
    float current_center_focus_ = 0.70f;

    // Filter coefficients: Formant (2.4 kHz)
    float b0_formant_ = 1.0f, b1_formant_ = 0.0f, b2_formant_ = 0.0f;
    float a1_formant_ = 0.0f, a2_formant_ = 0.0f;
    float formant_x1_ = 0.0f, formant_x2_ = 0.0f, formant_y1_ = 0.0f, formant_y2_ = 0.0f;

    // Filter coefficients: Body (1.2 kHz)
    float b0_body_ = 1.0f, b1_body_ = 0.0f, b2_body_ = 0.0f;
    float a1_body_ = 0.0f, a2_body_ = 0.0f;
    float body_x1_ = 0.0f, body_x2_ = 0.0f, body_y1_ = 0.0f, body_y2_ = 0.0f;

    // Filter coefficients: Clarity (3.8 kHz)
    float b0_clarity_ = 1.0f, b1_clarity_ = 0.0f, b2_clarity_ = 0.0f;
    float a1_clarity_ = 0.0f, a2_clarity_ = 0.0f;
    float clarity_x1_ = 0.0f, clarity_x2_ = 0.0f, clarity_y1_ = 0.0f, clarity_y2_ = 0.0f;

    // Speech envelope & telemetry
    float speech_energy_env_ = 0.0f;
    float last_ducking_reduction_db_ = 0.0f;
    float anti_pop_ = 0.0f;
};

} // namespace sauti::dsp
