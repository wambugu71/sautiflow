#pragma once

#include <cmath>
#include <cstdint>
#include <algorithm>
#include <vector>

namespace sauti::dsp {

enum class BassEnhanceProfile {
    NaturalBass = 0,        // Natural Mono Bass: Butterworth Q=0.53 + smooth low-end injection
    PureBass = 1,           // Pure Bass: Resonant punch with tight transient impact
    Subwoofer = 2,          // Subwoofer Mono: Deep 35-65 Hz excursion power with 2.5x drive
    HarmonicExciter = 3,    // Harmonic Synthesizer: Missing fundamental (2nd + 3rd order harmonics)
    PultecDeep = 4,         // Pultec EQP-1A Trick: Deep 45 Hz mono boost + 300 Hz mud scoop

    // Backward-compatible aliases
    SubBassResonant = 0,
    PunchyBass = 1
};

class HarmonicBassDSP {
public:
    HarmonicBassDSP() {
        setSampleRate(48000.0f);
        setProfile(BassEnhanceProfile::NaturalBass);
        reset();
    }

    void setSampleRate(float sampleRate) {
        if (sampleRate <= 0.0f) sampleRate = 48000.0f;
        if (std::abs(sample_rate_ - sampleRate) < 0.1f) return;
        sample_rate_ = sampleRate;
        sample_period_ = 1.0f / sample_rate_;
        updateFilters();
        reset();
    }

    void setEnabled(bool enabled) {
        if (enabled_ != enabled) {
            if (enabled) {
                reset();
            }
            enabled_ = enabled;
        }
    }

    bool isEnabled() const { return enabled_; }

    void setProfile(BassEnhanceProfile profile) {
        if (profile_ != profile) {
            profile_ = profile;
            updateFilters();
            reset();
        }
    }

    BassEnhanceProfile getProfile() const { return profile_; }

    // Cutoff frequency in Hz (30 Hz to 160 Hz, default 60 Hz)
    void setCutoffFrequency(float freqHz) {
        cutoff_hz_ = std::clamp(freqHz, 30.0f, 160.0f);
        updateFilters();
    }

    float getCutoffFrequency() const { return cutoff_hz_; }

    // Boost factor [0.0, 1.0] -> maps to dynamic bass gain multiplier
    void setBoost(float boost) {
        boost_ = std::clamp(boost, 0.0f, 1.0f);
        bass_factor_ = boost_ * 3.5f;
        if (profile_ == BassEnhanceProfile::Subwoofer) {
            bass_factor_ *= 1.6f; // Extra excursion power for subwoofer mode
        }
        updateFilters();
    }

    float getBoost() const { return boost_; }

    void reset() {
        anti_pop_ = 0.0f;
        bass_factor_smoothed_ = bass_factor_;
        smoothing_coeff_ = 1.0f - std::exp(-1.0f / (0.030f * sample_rate_)); // 30ms smoothing
        
        // 18 Hz DC blocker coefficient
        constexpr float PI = 3.14159265358979323846f;
        dc_block_coeff_ = std::exp(-2.0f * PI * 18.0f / sample_rate_);
        dc_x1_ = 0.0f;
        dc_y1_ = 0.0f;

        // Reset mono lowpass biquad states
        lp_x1_ = lp_x2_ = lp_y1_ = lp_y2_ = 0.0f;

        // Reset harmonic exciter states
        harm_lp_x1_ = harm_lp_x2_ = harm_lp_y1_ = harm_lp_y2_ = 0.0f;
        harm_bp_x1_ = harm_bp_x2_ = harm_bp_y1_ = harm_bp_y2_ = 0.0f;

        // Reset Pultec filter states
        pultec_boost_x1_ = pultec_boost_x2_ = pultec_boost_y1_ = pultec_boost_y2_ = 0.0f;
        pultec_scoop_x1_l_ = pultec_scoop_x2_l_ = pultec_scoop_y1_l_ = pultec_scoop_y2_l_ = 0.0f;
        pultec_scoop_x1_r_ = pultec_scoop_x2_r_ = pultec_scoop_y1_r_ = pultec_scoop_y2_r_ = 0.0f;
    }

    // Process interleaved stereo samples: [L0, R0, L1, R1, ...]
    void process(float* samples, uint32_t frame_count) {
        if (!enabled_ || frame_count == 0 || !samples) return;

        // 1. Anti-Pop smooth ramp on activation
        if (anti_pop_ < 1.0f) {
            for (uint32_t i = 0; i < frame_count * 2; i += 2) {
                samples[i] *= anti_pop_;
                samples[i + 1] *= anti_pop_;

                anti_pop_ += sample_period_ * 4.0f;
                if (anti_pop_ > 1.0f) {
                    anti_pop_ = 1.0f;
                    break;
                }
            }
        }

        switch (profile_) {
            case BassEnhanceProfile::NaturalBass:
            case BassEnhanceProfile::PureBass:
            case BassEnhanceProfile::Subwoofer:
                processMonoBiquadBass(samples, frame_count);
                break;
            case BassEnhanceProfile::HarmonicExciter:
                processHarmonicExciter(samples, frame_count);
                break;
            case BassEnhanceProfile::PultecDeep:
                processPultecDeep(samples, frame_count);
                break;
        }
    }

private:
    bool enabled_ = false;
    BassEnhanceProfile profile_ = BassEnhanceProfile::NaturalBass;
    float sample_rate_ = 48000.0f;
    float sample_period_ = 1.0f / 48000.0f;
    float cutoff_hz_ = 60.0f;
    float boost_ = 0.5f;

    // Gain smoothing and Anti-Pop
    float anti_pop_ = 0.0f;
    float bass_factor_ = 1.75f;
    float bass_factor_smoothed_ = 1.75f;
    float smoothing_coeff_ = 0.001f;

    // 18 Hz DC Blocker states
    float dc_block_coeff_ = 0.997f;
    float dc_x1_ = 0.0f;
    float dc_y1_ = 0.0f;

    // --- Mono Low-Pass Biquad Coefficients ---
    float lp_b0_ = 1.0f, lp_b1_ = 0.0f, lp_b2_ = 0.0f;
    float lp_a1_ = 0.0f, lp_a2_ = 0.0f;
    float lp_x1_ = 0.0f, lp_x2_ = 0.0f, lp_y1_ = 0.0f, lp_y2_ = 0.0f;

    // --- Harmonic Exciter Filter Coefficients ---
    float harm_lp_b0_ = 1.0f, harm_lp_b1_ = 0.0f, harm_lp_b2_ = 0.0f;
    float harm_lp_a1_ = 0.0f, harm_lp_a2_ = 0.0f;
    float harm_lp_x1_ = 0.0f, harm_lp_x2_ = 0.0f, harm_lp_y1_ = 0.0f, harm_lp_y2_ = 0.0f;

    float harm_bp_b0_ = 1.0f, harm_bp_b1_ = 0.0f, harm_bp_b2_ = 0.0f;
    float harm_bp_a1_ = 0.0f, harm_bp_a2_ = 0.0f;
    float harm_bp_x1_ = 0.0f, harm_bp_x2_ = 0.0f, harm_bp_y1_ = 0.0f, harm_bp_y2_ = 0.0f;

    // --- Pultec Low-End Trick Coefficients ---
    float pultec_boost_b0_ = 1.0f, pultec_boost_b1_ = 0.0f, pultec_boost_b2_ = 0.0f;
    float pultec_boost_a1_ = 0.0f, pultec_boost_a2_ = 0.0f;
    float pultec_boost_x1_ = 0.0f, pultec_boost_x2_ = 0.0f, pultec_boost_y1_ = 0.0f, pultec_boost_y2_ = 0.0f;

    float pultec_scoop_b0_ = 1.0f, pultec_scoop_b1_ = 0.0f, pultec_scoop_b2_ = 0.0f;
    float pultec_scoop_a1_ = 0.0f, pultec_scoop_a2_ = 0.0f;
    float pultec_scoop_x1_l_ = 0.0f, pultec_scoop_x2_l_ = 0.0f, pultec_scoop_y1_l_ = 0.0f, pultec_scoop_y1_r_ = 0.0f;
    float pultec_scoop_x1_r_ = 0.0f, pultec_scoop_x2_r_ = 0.0f, pultec_scoop_y2_l_ = 0.0f, pultec_scoop_y2_r_ = 0.0f;

    // Rational Algebraic Soft-Clipper with Knee (clean, warm, zero harsh harmonics)
    static inline float softClip(float v, float knee) {
        float drive = std::fabs(v);
        if (drive <= knee) return v;
        float over = drive - knee;
        float shaped = knee + over / std::sqrt(1.0f + over * over);
        return v * (shaped / drive);
    }

    // DC Blocker & Dual-Stage Soft Clip Mix
    inline void shapeMix(float raw_bass, float* samples, uint32_t i) {
        // 1. 18 Hz DC Blocker High-Pass (strips subsonic DC offset)
        const float dc_out = dc_block_coeff_ * (dc_y1_ + raw_bass - dc_x1_);
        dc_x1_ = raw_bass;
        dc_y1_ = dc_out;

        // 2. Stage 1 Soft-Clip on the bass signal alone (knee = 0.8)
        float shaped_bass = softClip(dc_out, 0.8f);

        // 3. Stage 2 Soft-Clip on the summed stereo channels (knee = 0.95)
        samples[2 * i]     = softClip(samples[2 * i] + shaped_bass, 0.95f);
        samples[2 * i + 1] = softClip(samples[2 * i + 1] + shaped_bass, 0.95f);
    }

    // Process Natural / Pure / Subwoofer Mono Bass
    void processMonoBiquadBass(float* samples, uint32_t frame_count) {
        for (uint32_t i = 0; i < frame_count; i++) {
            // Smooth gain parameter to eliminate clicking
            bass_factor_smoothed_ += (bass_factor_ - bass_factor_smoothed_) * smoothing_coeff_;

            // Strict Mono Summation (L + R) / 2
            float mono_in = (samples[2 * i] + samples[2 * i + 1]) * 0.5f;

            // Direct Form I Mono Lowpass Filter
            float mono_sub = lp_b0_ * mono_in + lp_b1_ * lp_x1_ + lp_b2_ * lp_x2_
                           - lp_a1_ * lp_y1_ - lp_a2_ * lp_y2_;
            lp_x2_ = lp_x1_; lp_x1_ = mono_in;
            lp_y2_ = lp_y1_; lp_y1_ = mono_sub;

            // Scaled dynamic bass factor
            float driven_bass = mono_sub * bass_factor_smoothed_;

            // Apply DC blocker and dual-stage soft clipping
            shapeMix(driven_bass, samples, i);
        }
    }

    // Missing Fundamental Mono Harmonic Exciter (Synthesizes 2f and 3f upper harmonics in mono)
    void processHarmonicExciter(float* samples, uint32_t frame_count) {
        const float harmonic_drive = 1.5f + boost_ * 4.0f;
        const float harmonic_mix = boost_ * 1.8f;

        for (uint32_t i = 0; i < frame_count; i++) {
            bass_factor_smoothed_ += (bass_factor_ - bass_factor_smoothed_) * smoothing_coeff_;

            // True mono sum for fundamental extraction
            float mono_in = (samples[2 * i] + samples[2 * i + 1]) * 0.5f;

            // 1. Extract fundamental sub-bass (< 85 Hz)
            float sub = harm_lp_b0_ * mono_in + harm_lp_b1_ * harm_lp_x1_ + harm_lp_b2_ * harm_lp_x2_
                      - harm_lp_a1_ * harm_lp_y1_ - harm_lp_a2_ * harm_lp_y2_;
            harm_lp_x2_ = harm_lp_x1_; harm_lp_x1_ = mono_in;
            harm_lp_y2_ = harm_lp_y1_; harm_lp_y1_ = sub;

            // 2. Synthesize 2nd (even) & 3rd (odd) upper harmonics without DC bias
            float driven = sub * harmonic_drive;
            float h_even = driven * std::fabs(driven);
            float h_odd = std::tanh(driven * 1.4f);
            float raw_harmonics = (h_even * 0.55f + h_odd * 0.45f);

            // 3. Bandpass filter generated harmonics (80-250 Hz)
            float filtered_h = harm_bp_b0_ * raw_harmonics + harm_bp_b1_ * harm_bp_x1_ + harm_bp_b2_ * harm_bp_x2_
                             - harm_bp_a1_ * harm_bp_y1_ - harm_bp_a2_ * harm_bp_y2_;
            harm_bp_x2_ = harm_bp_x1_; harm_bp_x1_ = raw_harmonics;
            harm_bp_y2_ = harm_bp_y1_; harm_bp_y1_ = filtered_h;

            float bass_out = (sub * bass_factor_smoothed_ * 0.5f) + (filtered_h * harmonic_mix);
            shapeMix(bass_out, samples, i);
        }
    }

    // Pultec EQP-1A Low-End Trick in Mono Sub + Stereo Mud Scoop
    void processPultecDeep(float* samples, uint32_t frame_count) {
        for (uint32_t i = 0; i < frame_count; i++) {
            float in_l = samples[2 * i];
            float in_r = samples[2 * i + 1];

            // 1. Mono Sub-Bass 45 Hz Low-Shelf Boost
            float mono_in = (in_l + in_r) * 0.5f;
            float b_out = pultec_boost_b0_ * mono_in + pultec_boost_b1_ * pultec_boost_x1_ + pultec_boost_b2_ * pultec_boost_x2_
                        - pultec_boost_a1_ * pultec_boost_y1_ - pultec_boost_a2_ * pultec_boost_y2_;
            pultec_boost_x2_ = pultec_boost_x1_; pultec_boost_x1_ = mono_in;
            pultec_boost_y2_ = pultec_boost_y1_; pultec_boost_y1_ = b_out;

            // 2. Stereo 300 Hz Mud Scoop Peak Filter
            float s_out_l = pultec_scoop_b0_ * in_l + pultec_scoop_b1_ * pultec_scoop_x1_l_ + pultec_scoop_b2_ * pultec_scoop_x2_l_
                          - pultec_scoop_a1_ * pultec_scoop_y1_l_ - pultec_scoop_a2_ * pultec_scoop_y2_l_;
            pultec_scoop_x2_l_ = pultec_scoop_x1_l_; pultec_scoop_x1_l_ = in_l;
            pultec_scoop_y2_l_ = pultec_scoop_y1_l_; pultec_scoop_y1_l_ = s_out_l;

            float s_out_r = pultec_scoop_b0_ * in_r + pultec_scoop_b1_ * pultec_scoop_x1_r_ + pultec_scoop_b2_ * pultec_scoop_x2_r_
                          - pultec_scoop_a1_ * pultec_scoop_y1_r_ - pultec_scoop_a2_ * pultec_scoop_y2_r_;
            pultec_scoop_x2_r_ = pultec_scoop_x1_r_; pultec_scoop_x1_r_ = in_r;
            pultec_scoop_y2_r_ = pultec_scoop_y1_r_; pultec_scoop_y1_r_ = s_out_r;

            // Mix mono low-shelf into scooped stereo signal
            samples[2 * i]     = s_out_l;
            samples[2 * i + 1] = s_out_r;

            float mono_bass = (b_out - mono_in) * 0.8f;
            shapeMix(mono_bass, samples, i);
        }
    }

    void updateFilters() {
        float freq = cutoff_hz_;
        float Q = 0.53f; // Default ViPER Natural Bass Q

        switch (profile_) {
            case BassEnhanceProfile::NaturalBass:
                freq = cutoff_hz_;
                Q = 0.53f; // Critically damped
                break;
            case BassEnhanceProfile::PureBass:
                freq = cutoff_hz_ * 1.15f;
                Q = 0.85f + boost_ * 1.5f; // Punchy resonant transient
                break;
            case BassEnhanceProfile::Subwoofer:
                freq = std::clamp(cutoff_hz_ * 0.8f, 30.0f, 80.0f);
                Q = 0.7071f + boost_ * 1.2f;
                break;
            default:
                break;
        }

        calcLowpass(freq, Q, lp_b0_, lp_b1_, lp_b2_, lp_a1_, lp_a2_);

        // Psychoacoustic filters
        calcLowpass(85.0f, 0.7071f, harm_lp_b0_, harm_lp_b1_, harm_lp_b2_, harm_lp_a1_, harm_lp_a2_);
        calcBandpass(80.0f, 250.0f, harm_bp_b0_, harm_bp_b1_, harm_bp_b2_, harm_bp_a1_, harm_bp_a2_);

        // Pultec EQP-1A Low-End Trick:
        // 1. Deep 45 Hz Low-Shelf (+0 dB to +12 dB boost)
        float pultec_boost_db = boost_ * 12.0f;
        calcLowshelf(45.0f, pultec_boost_db, pultec_boost_b0_, pultec_boost_b1_, pultec_boost_b2_, pultec_boost_a1_, pultec_boost_a2_);

        // 2. 300 Hz Mud-Scoop (-0 dB to -4.5 dB cut at Q=1.2)
        float pultec_scoop_db = -boost_ * 4.5f;
        calcPeakingEq(300.0f, 1.2f, pultec_scoop_db, pultec_scoop_b0_, pultec_scoop_b1_, pultec_scoop_b2_, pultec_scoop_a1_, pultec_scoop_a2_);
    }

    void calcLowpass(float freq, float Q, float& b0, float& b1, float& b2, float& a1, float& a2) {
        constexpr float PI = 3.14159265358979323846f;
        float w0 = 2.0f * PI * freq / sample_rate_;
        if (w0 > PI * 0.95f) w0 = PI * 0.95f;
        float cos_w0 = std::cos(w0);
        float alpha = std::sin(w0) / (2.0f * Q);

        float a0 = 1.0f + alpha;
        b0 = ((1.0f - cos_w0) * 0.5f) / a0;
        b1 = (1.0f - cos_w0) / a0;
        b2 = b0;
        a1 = (-2.0f * cos_w0) / a0;
        a2 = (1.0f - alpha) / a0;
    }

    void calcBandpass(float f_low, float f_high, float& b0, float& b1, float& b2, float& a1, float& a2) {
        constexpr float PI = 3.14159265358979323846f;
        float center_freq = std::sqrt(f_low * f_high);
        float bandwidth = (f_high - f_low) / center_freq;
        float Q = 1.0f / bandwidth;

        float w0 = 2.0f * PI * center_freq / sample_rate_;
        if (w0 > PI * 0.95f) w0 = PI * 0.95f;
        float cos_w0 = std::cos(w0);
        float alpha = std::sin(w0) / (2.0f * Q);

        float a0 = 1.0f + alpha;
        b0 = alpha / a0;
        b1 = 0.0f;
        b2 = -b0;
        a1 = (-2.0f * cos_w0) / a0;
        a2 = (1.0f - alpha) / a0;
    }

    void calcLowshelf(float freq, float gain_db, float& b0, float& b1, float& b2, float& a1, float& a2) {
        constexpr float PI = 3.14159265358979323846f;
        float A = std::pow(10.0f, gain_db / 40.0f);
        float w0 = 2.0f * PI * freq / sample_rate_;
        if (w0 > PI * 0.95f) w0 = PI * 0.95f;
        float cos_w0 = std::cos(w0);
        float sin_w0 = std::sin(w0);
        float alpha = sin_w0 / 2.0f * std::sqrt((A + 1.0f / A) * (1.0f / 0.7071f - 1.0f) + 2.0f);
        float sqrt_A = 2.0f * std::sqrt(A) * alpha;

        float a0 = (A + 1.0f) + (A - 1.0f) * cos_w0 + sqrt_A;
        b0 = (A * ((A + 1.0f) - (A - 1.0f) * cos_w0 + sqrt_A)) / a0;
        b1 = (2.0f * A * ((A - 1.0f) - (A + 1.0f) * cos_w0)) / a0;
        b2 = (A * ((A + 1.0f) - (A - 1.0f) * cos_w0 - sqrt_A)) / a0;
        a1 = (-2.0f * ((A - 1.0f) + (A + 1.0f) * cos_w0)) / a0;
        a2 = ((A + 1.0f) + (A - 1.0f) * cos_w0 - sqrt_A) / a0;
    }

    void calcPeakingEq(float freq, float Q, float gain_db, float& b0, float& b1, float& b2, float& a1, float& a2) {
        constexpr float PI = 3.14159265358979323846f;
        float A = std::pow(10.0f, gain_db / 40.0f);
        float w0 = 2.0f * PI * freq / sample_rate_;
        if (w0 > PI * 0.95f) w0 = PI * 0.95f;
        float cos_w0 = std::cos(w0);
        float alpha = std::sin(w0) / (2.0f * Q);

        float a0 = 1.0f + alpha / A;
        b0 = (1.0f + alpha * A) / a0;
        b1 = (-2.0f * cos_w0) / a0;
        b2 = (1.0f - alpha * A) / a0;
        a1 = (-2.0f * cos_w0) / a0;
        a2 = (1.0f - alpha / A) / a0;
    }
};

} // namespace sauti::dsp
