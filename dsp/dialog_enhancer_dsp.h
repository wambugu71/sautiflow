#pragma once

#include <cmath>
#include <cstdint>
#include <algorithm>
#include <vector>
#include "denormals.h"
#include "cytomic_svf_dsp.h"

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
//
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
        if (initialized_ && std::abs(sample_rate_ - sampleRate) < 0.1f) return;
        sample_rate_ = sampleRate;
        sample_period_ = 1.0f / sample_rate_;
        smoothing_coeff_ = 1.0f - std::exp(-1.0f / (0.030f * sample_rate_)); // 30ms smoothing

        // Attack/release for speech envelope detection (fast 15ms attack, 120ms release)
        env_attack_coeff_ = 1.0f - std::exp(-1.0f / (0.015f * sample_rate_));
        env_release_coeff_ = 1.0f - std::exp(-1.0f / (0.120f * sample_rate_));

        initialized_ = true;
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
        current_amount_ = target_amount_;
        current_ducking_ = target_ducking_;
        current_clarity_ = target_clarity_;
        current_center_focus_ = target_center_focus_;
        recalcBiquads();
    }

    // Telemetry / metering: current ducking gain reduction in dB
    float getGainReductionDb() const {
        return last_ducking_reduction_db_;
    }

    // Telemetry / verification: automatic headroom trim compensation
    float getHeadroomCompensation() const {
        return headroom_comp_;
    }

    float getHeadroomCompensationDb() const {
        return (headroom_comp_ > 0.0f) ? (20.0f * std::log10(headroom_comp_)) : -100.0f;
    }

    void reset() {
        current_amount_ = target_amount_;
        current_ducking_ = target_ducking_;
        current_clarity_ = target_clarity_;
        current_center_focus_ = target_center_focus_;

        formant_svf_.reset();
        body_svf_.reset();
        clarity_svf_.reset();

        speech_energy_env_ = 0.0f;
        last_ducking_reduction_db_ = 0.0f;
        peak_atten_ = 1.0f;
        anti_pop_ = 0.0f;

        recalcBiquads();
    }

    // Process interleaved stereo samples: [L0, R0, L1, R1, ...]
    void process(float* interleaved_samples, uint32_t frame_count) {
        processImpl(interleaved_samples, frame_count);
    }

    // Process interleaved stereo 64-bit double samples: [L0, R0, L1, R1, ...]
    void process(double* interleaved_samples, uint32_t frame_count) {
        processImpl(interleaved_samples, frame_count);
    }

private:
    template <typename T>
    void processImpl(T* interleaved_samples, uint32_t frame_count) {
        if (!enabled_ || frame_count == 0 || !interleaved_samples) return;

        ScopedDenormalsDisable denormals;

        const float anti_pop_step = 1.0f / (0.015f * sample_rate_); // 15ms anti-pop ramp
        const float atten_release_coeff = 1.0f - std::exp(-1.0f / (0.050f * sample_rate_)); // 50 ms

        for (uint32_t i = 0; i < frame_count; ++i) {
            // 1. Parameter de-zippering / smoothing
            current_amount_ += smoothing_coeff_ * (target_amount_ - current_amount_);
            current_ducking_ += smoothing_coeff_ * (target_ducking_ - current_ducking_);
            current_clarity_ += smoothing_coeff_ * (target_clarity_ - current_clarity_);
            current_center_focus_ += smoothing_coeff_ * (target_center_focus_ - current_center_focus_);

            // Recalculate coefficients at sub-block intervals (every 32 samples) if parameters shifted
            if ((i & 31) == 0) {
                if (std::abs(current_amount_ - cached_amount_) > 0.005f ||
                    std::abs(current_clarity_ - cached_clarity_) > 0.005f) {
                    recalcBiquads();
                }
            }

            if (anti_pop_ < 1.0f) {
                anti_pop_ = std::min(1.0f, anti_pop_ + anti_pop_step);
            }

            const double in_l = static_cast<double>(interleaved_samples[2 * i]);
            const double in_r = static_cast<double>(interleaved_samples[2 * i + 1]);

            // 2. Mid-Side decomposition
            const double mid = 0.5 * (in_l + in_r);
            const double side = 0.5 * (in_l - in_r);

            // 3. Multi-stage vocal formant enhancement on center/mid channel (64-bit Cytomic SVF)
            const double mid_formant = formant_svf_.processSample(mid, 0);
            const double mid_body = body_svf_.processSample(mid_formant, 0);
            const double mid_enhanced = clarity_svf_.processSample(mid_body, 0);

            // 4. Speech energy envelope detection for dynamic background ducking
            const float abs_speech = static_cast<float>(std::fabs(mid_enhanced));
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

            // Dynamic headroom attenuation: prevents internal digital clipping on high-level voice tracks
            const float estimated_mid_peak = std::max(speech_energy_env_, abs_speech) * (mid_gain * headroom_comp_);
            float target_atten = 1.0f;
            if (estimated_mid_peak > 0.95f) {
                target_atten = 0.95f / estimated_mid_peak;
            }
            // Instant attack guarantees the ceiling; smooth release avoids the
            // per-sample gain jumps that flat-top waveforms (odd harmonics).
            if (target_atten < peak_atten_) {
                peak_atten_ = target_atten;
            } else {
                peak_atten_ += atten_release_coeff * (target_atten - peak_atten_);
            }
            const double dynamic_atten = static_cast<double>(peak_atten_);

            // Apply mid gain scaled by automatic headroom compensation and dynamic attenuation
            const double out_mid = mid_enhanced * (static_cast<double>(mid_gain) * static_cast<double>(headroom_comp_) * dynamic_atten);
            const double out_side = side * static_cast<double>(side_gain);

            // 5. Mid-Side synthesis back to Left & Right
            const double proc_l = out_mid + out_side;
            const double proc_r = out_mid - out_side;

            // 6. Anti-pop crossfade with dry signal
            const double ap = static_cast<double>(anti_pop_);
            interleaved_samples[2 * i] = static_cast<T>(in_l + ap * (proc_l - in_l));
            interleaved_samples[2 * i + 1] = static_cast<T>(in_r + ap * (proc_r - in_r));
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

    void recalcBiquads() {
        cached_amount_ = current_amount_;
        cached_clarity_ = current_clarity_;

        // 1. Primary vocal formant peak at 2400 Hz (64-bit Cytomic SVF)
        // Amount [0.0, 1.0] maps from 0.0 dB to +11.0 dB
        float formant_gain_db = current_amount_ * 11.0f;
        formant_svf_.setParameters(CytomicSVF::FilterType::Bell, sample_rate_, 2400.0, formant_gain_db, 1.25);

        // 2. Vocal body formant peak at 1200 Hz for warm intelligible fullness
        float body_gain_db = current_amount_ * 3.5f;
        body_svf_.setParameters(CytomicSVF::FilterType::Bell, sample_rate_, 1200.0, body_gain_db, 1.0);

        // 3. Consonant clarity & presence peak at 3800 Hz
        float clarity_gain_db = current_clarity_ * 5.0f;
        clarity_svf_.setParameters(CytomicSVF::FilterType::Bell, sample_rate_, 3800.0, clarity_gain_db, 1.3);

        // Automatic headroom compensation: caps combined 3-band boost to safe +12 dB headroom
        // preventing digital clipping when formant (+11dB), body (+3.5dB), and clarity (+5dB) peak together
        float total_boost_db = formant_gain_db + body_gain_db + clarity_gain_db;
        float headroom_comp_db = (total_boost_db > 12.0f) ? (12.0f - total_boost_db) : 0.0f;
        headroom_comp_ = std::pow(10.0f, headroom_comp_db / 20.0f);
    }

    bool enabled_ = false;
    DialogEnhancerProfile profile_ = DialogEnhancerProfile::Cinema;
    bool initialized_ = false;

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
    float headroom_comp_ = 1.0f;

    // Vocal formant 64-bit Cytomic SVF stages
    CytomicSVF formant_svf_;
    CytomicSVF body_svf_;
    CytomicSVF clarity_svf_;

    // Speech envelope & telemetry
    float speech_energy_env_ = 0.0f;
    float last_ducking_reduction_db_ = 0.0f;
    float anti_pop_ = 0.0f;

    // Smoothed headroom-protection gain (1.0 = no attenuation).
    float peak_atten_ = 1.0f;
};

} // namespace sauti::dsp
