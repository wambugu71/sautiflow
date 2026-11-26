#pragma once

#include <cmath>
#include <cstdint>
#include <algorithm>
#include <atomic>
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
// Key Subsystems:
//   1. Vocal Formant Peaking Filter: 2400 Hz (Q = 1.25) primary speech intelligibility
//   2. Speech Body Formant Filter: 1200 Hz (Q = 1.0) vowel fullness & resonance
//   3. Speech Presence & Consonant Crispness Filter: 3800 Hz (Q = 1.3) articulation
//   4. Mid-Side Speech Isolation & Ratio-Gated Bandpass Ducking:
//      Extracts phantom center dialogue (M = (L+R)/2), detects speech activity via
//      a 300 Hz - 3.8 kHz bandpass sidechain ratio against wideband Mid energy,
//      and dynamically attenuates ambient/surround side content (S = (L-R)/2).
//   5. Stereo-linked headroom compensation & peak protection, de-zippered
//      parameter smoothing (30ms tau), and click-free enable/disable crossfade.
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
        anti_pop_step_ = 1.0f / (0.015f * sample_rate_); // 15ms anti-pop fade-in/out

        // Attack/release for speech envelope detection (fast 15ms attack, 120ms release)
        env_attack_coeff_ = 1.0f - std::exp(-1.0f / (0.015f * sample_rate_));
        env_release_coeff_ = 1.0f - std::exp(-1.0f / (0.120f * sample_rate_));

        // Peak protection ballistics (0.5ms attack, 50ms release)
        atten_attack_coeff_ = 1.0f - std::exp(-1.0f / (0.0005f * sample_rate_));
        atten_release_coeff_ = 1.0f - std::exp(-1.0f / (0.050f * sample_rate_));

        // Speech-band sidechain (300 Hz - 3800 Hz)
        sidechain_hp_.setParameters(CytomicSVF::FilterType::HighPass, sample_rate_, 300.0, 0.0, 0.70710678);
        sidechain_lp_.setParameters(CytomicSVF::FilterType::LowPass, sample_rate_, 3800.0, 0.0, 0.70710678);

        initialized_ = true;
        recalcBiquads();
    }

    void setEnabled(bool enabled) {
        enabled_ = enabled;
    }

    bool isEnabled() const { return enabled_; }

    bool isActive() const { return enabled_ || anti_pop_ > 0.0f; }

    void setProfile(DialogEnhancerProfile profile) {
        if (profile_ != profile) {
            profile_ = profile;
            applyProfileDefaults();
        }
    }

    DialogEnhancerProfile getProfile() const { return profile_; }

    // Dialogue Boost Amount: [0.0, 1.0] -> 0 dB to +11 dB formant gain
    void setAmount(float amount) {
        target_amount_ = std::clamp(amount, 0.0f, 1.0f);
        if (profile_ != DialogEnhancerProfile::Custom) {
            profile_ = DialogEnhancerProfile::Custom;
        }
    }

    float getAmount() const { return target_amount_; }

    // Dialogue Ducking: [0.0, 1.0] -> 0% to 65% background/side suppression
    void setDucking(float ducking) {
        target_ducking_ = std::clamp(ducking, 0.0f, 1.0f);
        if (profile_ != DialogEnhancerProfile::Custom) {
            profile_ = DialogEnhancerProfile::Custom;
        }
    }

    float getDucking() const { return target_ducking_; }

    // Vocal Clarity / High Formant Definition: [0.0, 1.0] -> 0 dB to +5 dB
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

    // Direct multi-parameter configuration (always honors passed values and smooths cleanly)
    void setParams(DialogEnhancerProfile profile, float amount, float ducking, float clarity, float centerFocus) {
        profile_ = profile;
        target_amount_ = std::clamp(amount, 0.0f, 1.0f);
        target_ducking_ = std::clamp(ducking, 0.0f, 1.0f);
        target_clarity_ = std::clamp(clarity, 0.0f, 1.0f);
        target_center_focus_ = std::clamp(centerFocus, 0.0f, 1.0f);
    }

    // Telemetry / metering: current ducking gain reduction in dB (thread-safe)
    float getGainReductionDb() const {
        return last_ducking_reduction_db_.load(std::memory_order_relaxed);
    }

    // Telemetry / verification: automatic headroom trim compensation
    float getHeadroomCompensation() const {
        return current_headroom_comp_;
    }

    float getHeadroomCompensationDb() const {
        return (current_headroom_comp_ > 0.0f) ? (20.0f * std::log10(current_headroom_comp_)) : -100.0f;
    }

    void reset() {
        current_amount_ = target_amount_;
        current_ducking_ = target_ducking_;
        current_clarity_ = target_clarity_;
        current_center_focus_ = target_center_focus_;

        formant_svf_.reset();
        body_svf_.reset();
        clarity_svf_.reset();
        sidechain_hp_.reset();
        sidechain_lp_.reset();

        speech_energy_env_ = 0.0f;
        fullband_mid_env_ = 0.0f;
        last_ducking_reduction_db_.store(0.0f, std::memory_order_relaxed);
        peak_atten_ = 1.0f;
        anti_pop_ = 0.0f;

        recalcBiquads();
        current_headroom_comp_ = target_headroom_comp_;
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
        if ((!enabled_ && anti_pop_ <= 0.0f) || frame_count == 0 || !interleaved_samples) return;

        ScopedDenormalsDisable denormals;

        for (uint32_t i = 0; i < frame_count; ++i) {
            // 1. Parameter de-zippering / smoothing
            current_amount_ += smoothing_coeff_ * (target_amount_ - current_amount_);
            current_ducking_ += smoothing_coeff_ * (target_ducking_ - current_ducking_);
            current_clarity_ += smoothing_coeff_ * (target_clarity_ - current_clarity_);
            current_center_focus_ += smoothing_coeff_ * (target_center_focus_ - current_center_focus_);

            // Recalculate coefficients at sub-block intervals (every 32 samples) if parameters shifted
            if ((i & 31) == 0) {
                if (std::abs(current_amount_ - cached_amount_) > 0.002f ||
                    std::abs(current_clarity_ - cached_clarity_) > 0.002f) {
                    recalcBiquads();
                }
            }
            current_headroom_comp_ += smoothing_coeff_ * (target_headroom_comp_ - current_headroom_comp_);

            if (enabled_) {
                if (anti_pop_ < 1.0f) {
                    anti_pop_ = std::min(1.0f, anti_pop_ + anti_pop_step_);
                }
            } else {
                if (anti_pop_ > 0.0f) {
                    anti_pop_ = std::max(0.0f, anti_pop_ - anti_pop_step_);
                }
            }

            const double in_l = static_cast<double>(interleaved_samples[2 * i]);
            const double in_r = static_cast<double>(interleaved_samples[2 * i + 1]);

            // 2. Mid-Side decomposition
            const double mid = 0.5 * (in_l + in_r);
            const double side = 0.5 * (in_l - in_r);

            // 3. Speech-band sidechain (300 Hz - 3.8 kHz) on pre-boost Mid vs wideband Mid
            const double speech_hp = sidechain_hp_.processSample(mid, 0);
            const double speech_band = sidechain_lp_.processSample(speech_hp, 0);

            const float abs_speech_band = static_cast<float>(std::fabs(speech_band));
            if (abs_speech_band > speech_energy_env_) {
                speech_energy_env_ += env_attack_coeff_ * (abs_speech_band - speech_energy_env_);
            } else {
                speech_energy_env_ += env_release_coeff_ * (abs_speech_band - speech_energy_env_);
            }

            const float abs_mid = static_cast<float>(std::fabs(mid));
            if (abs_mid > fullband_mid_env_) {
                fullband_mid_env_ += env_attack_coeff_ * (abs_mid - fullband_mid_env_);
            } else {
                fullband_mid_env_ += env_release_coeff_ * (abs_mid - fullband_mid_env_);
            }

            // 4. Multi-stage vocal formant enhancement on center/mid channel (64-bit Cytomic SVF)
            const double mid_formant = formant_svf_.processSample(mid, 0);
            const double mid_body = body_svf_.processSample(mid_formant, 0);
            const double mid_enhanced = clarity_svf_.processSample(mid_body, 0);

            // 5. Ratio-gated speech activity detector (prevents kick/bass from ducking sides)
            const float speech_ratio = speech_energy_env_ / (fullband_mid_env_ + 1e-6f);
            const float speech_level = std::clamp((speech_energy_env_ - 0.008f) * 8.0f, 0.0f, 1.0f);
            const float ratio_gate = std::clamp((speech_ratio - 0.25f) * 2.5f, 0.0f, 1.0f);
            const float speech_activity = speech_level * ratio_gate;

            const float max_ducking_linear = 1.0f - (current_ducking_ * 0.65f); // up to ~-9.1 dB ducking
            const float current_side_gain = 1.0f - speech_activity * (1.0f - max_ducking_linear);

            // Center focus: strengthens mid while narrowing side slightly
            const float mid_gain = 1.0f + current_center_focus_ * 0.25f;
            const float side_gain = current_side_gain * (1.0f - current_center_focus_ * 0.20f);

            // 6. Mid-Side synthesis BEFORE stereo-linked headroom/peak protection
            const double raw_mid = mid_enhanced * static_cast<double>(mid_gain);
            const double raw_side = side * static_cast<double>(side_gain);
            const double hc = static_cast<double>(current_headroom_comp_);
            const double raw_l = (raw_mid + raw_side) * hc;
            const double raw_r = (raw_mid - raw_side) * hc;

            // Stereo-linked peak protection preserves exact Mid/Side balance
            const float stereo_peak = static_cast<float>(std::max(std::fabs(raw_l), std::fabs(raw_r)));
            const float target_atten = (stereo_peak > 0.95f) ? (0.95f / stereo_peak) : 1.0f;
            if (target_atten < peak_atten_) {
                peak_atten_ += atten_attack_coeff_ * (target_atten - peak_atten_);
            } else {
                peak_atten_ += atten_release_coeff_ * (target_atten - peak_atten_);
            }
            const double dynamic_atten = static_cast<double>(peak_atten_);

            auto softCeiling = [](double x) {
                const double ax = std::fabs(x);
                if (ax <= 0.95) return x;
                const double over = (ax - 0.95) / 0.03;
                const double shaped = 0.95 + 0.03 * (over / std::sqrt(1.0 + over * over));
                return x * (shaped / ax);
            };

            const double proc_l = softCeiling(raw_l * dynamic_atten);
            const double proc_r = softCeiling(raw_r * dynamic_atten);

            // 7. Anti-pop crossfade with dry signal (skip arithmetic at steady-state 1.0)
            if (anti_pop_ >= 1.0f) {
                interleaved_samples[2 * i] = static_cast<T>(proc_l);
                interleaved_samples[2 * i + 1] = static_cast<T>(proc_r);
            } else {
                const double ap = static_cast<double>(anti_pop_);
                interleaved_samples[2 * i] = static_cast<T>(in_l + ap * (proc_l - in_l));
                interleaved_samples[2 * i + 1] = static_cast<T>(in_r + ap * (proc_r - in_r));
            }
        }

        // Store latest telemetry reduction (thread-safe atomic)
        if (enabled_ && current_ducking_ > 0.001f) {
            const float speech_ratio = speech_energy_env_ / (fullband_mid_env_ + 1e-6f);
            const float speech_level = std::clamp((speech_energy_env_ - 0.008f) * 8.0f, 0.0f, 1.0f);
            const float ratio_gate = std::clamp((speech_ratio - 0.25f) * 2.5f, 0.0f, 1.0f);
            const float speech_act = speech_level * ratio_gate;
            const float max_duck = 1.0f - (current_ducking_ * 0.65f);
            const float lin = 1.0f - speech_act * (1.0f - max_duck);
            last_ducking_reduction_db_.store((lin > 0.001f) ? (20.0f * std::log10(lin)) : -12.0f,
                                             std::memory_order_relaxed);
        } else {
            last_ducking_reduction_db_.store(0.0f, std::memory_order_relaxed);
        }
    }

    void applyProfileDefaults() {
        switch (profile_) {
            case DialogEnhancerProfile::Cinema:
                target_amount_ = 0.65f;
                target_ducking_ = 0.55f;
                target_clarity_ = 0.60f;
                target_center_focus_ = 0.70f;
                break;
            case DialogEnhancerProfile::Music:
                target_amount_ = 0.35f;
                target_ducking_ = 0.20f;
                target_clarity_ = 0.40f;
                target_center_focus_ = 0.35f;
                break;
            case DialogEnhancerProfile::Voice:
                target_amount_ = 0.85f;
                target_ducking_ = 0.65f;
                target_clarity_ = 0.75f;
                target_center_focus_ = 0.85f;
                break;
            case DialogEnhancerProfile::Night:
                target_amount_ = 0.60f;
                target_ducking_ = 0.65f;
                target_clarity_ = 0.50f;
                target_center_focus_ = 0.75f;
                break;
            case DialogEnhancerProfile::Custom:
                break;
        }
    }

    void recalcBiquads() {
        cached_amount_ = current_amount_;
        cached_clarity_ = current_clarity_;

        // 1. Primary vocal formant peak at 2400 Hz (64-bit Cytomic SVF)
        // Amount [0.0, 1.0] maps from 0.0 dB to +11.0 dB
        const float formant_gain_db = current_amount_ * 11.0f;
        formant_svf_.setParameters(CytomicSVF::FilterType::Bell, sample_rate_, 2400.0, formant_gain_db, 1.25);

        // 2. Vocal body formant peak at 1200 Hz for warm intelligible fullness
        const float body_gain_db = current_amount_ * 3.5f;
        body_svf_.setParameters(CytomicSVF::FilterType::Bell, sample_rate_, 1200.0, body_gain_db, 1.0);

        // 3. Consonant clarity & presence peak at 3800 Hz
        const float clarity_gain_db = current_clarity_ * 5.0f;
        clarity_svf_.setParameters(CytomicSVF::FilterType::Bell, sample_rate_, 3800.0, clarity_gain_db, 1.3);

        // Automatic headroom compensation from actual evaluated peak response across the 3 bands
        auto evalSumDb = [&](double evalHz) {
            return CytomicSVF::evaluateResponseDb(CytomicSVF::FilterType::Bell, sample_rate_, 2400.0, formant_gain_db, 1.25, evalHz)
                 + CytomicSVF::evaluateResponseDb(CytomicSVF::FilterType::Bell, sample_rate_, 1200.0, body_gain_db, 1.0, evalHz)
                 + CytomicSVF::evaluateResponseDb(CytomicSVF::FilterType::Bell, sample_rate_, 3800.0, clarity_gain_db, 1.3, evalHz);
        };
        const double actual_peak_db = std::max({evalSumDb(1200.0), evalSumDb(2400.0), evalSumDb(3800.0)});
        const double headroom_comp_db = (actual_peak_db > 12.0) ? (12.0 - actual_peak_db) : 0.0;
        target_headroom_comp_ = static_cast<float>(std::pow(10.0, headroom_comp_db / 20.0));
    }

    bool enabled_ = false;
    DialogEnhancerProfile profile_ = DialogEnhancerProfile::Cinema;
    bool initialized_ = false;

    float sample_rate_ = 48000.0f;
    float sample_period_ = 1.0f / 48000.0f;
    float smoothing_coeff_ = 0.05f;
    float anti_pop_step_ = 1.0f / (0.015f * 48000.0f);
    float env_attack_coeff_ = 0.1f;
    float env_release_coeff_ = 0.01f;
    float atten_attack_coeff_ = 0.04f;
    float atten_release_coeff_ = 0.0004f;

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
    float target_headroom_comp_ = 1.0f;
    float current_headroom_comp_ = 1.0f;

    // Vocal formant 64-bit Cytomic SVF stages
    CytomicSVF formant_svf_;
    CytomicSVF body_svf_;
    CytomicSVF clarity_svf_;

    // Speech-band sidechain filters (300 Hz - 3.8 kHz)
    CytomicSVF sidechain_hp_;
    CytomicSVF sidechain_lp_;

    // Speech envelope & telemetry
    float speech_energy_env_ = 0.0f;
    float fullband_mid_env_ = 0.0f;
    std::atomic<float> last_ducking_reduction_db_{0.0f};
    float anti_pop_ = 0.0f;

    // Smoothed peak-protection gain (1.0 = no attenuation).
    float peak_atten_ = 1.0f;
};

} // namespace sauti::dsp
