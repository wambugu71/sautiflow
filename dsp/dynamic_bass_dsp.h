#pragma once

#include <cmath>
#include <cstdint>
#include <algorithm>
#include <vector>

namespace sauti::dsp {

enum class BassEnhanceProfile {
    SubBassResonant = 0,    // 55 Hz mono resonant low-pass with adaptive Q curve
    PunchyBass = 1,         // 80-110 Hz mid-bass punch with tighter transient response
    HarmonicExciter = 2,    // Missing fundamental synthesis (2nd + 3rd order harmonic generator)
    PultecDeep = 3          // Pultec EQP-1A Low-End Trick: Deep 45 Hz Sub Boost + 300 Hz Mud Scoop
};

class HarmonicBassDSP {
public:
    HarmonicBassDSP() {
        setSampleRate(48000.0f);
        reset();
    }

    void setSampleRate(float sampleRate) {
        if (sampleRate <= 0.0f) sampleRate = 48000.0f;
        if (std::abs(sample_rate_ - sampleRate) < 0.1f) return;
        sample_rate_ = sampleRate;
        updateFilters();
    }

    void setEnabled(bool enabled) {
        enabled_ = enabled;
        if (!enabled) {
            reset();
        }
    }

    bool isEnabled() const { return enabled_; }

    void setProfile(BassEnhanceProfile profile) {
        if (profile_ != profile) {
            profile_ = profile;
            reset();
            updateFilters();
        }
    }

    BassEnhanceProfile getProfile() const { return profile_; }

    // Cutoff frequency in Hz (typically 30 Hz to 120 Hz, default 55 Hz)
    void setCutoffFrequency(float freqHz) {
        cutoff_hz_ = std::clamp(freqHz, 30.0f, 160.0f);
        updateFilters();
    }

    float getCutoffFrequency() const { return cutoff_hz_; }

    // Boost factor [0.0, 1.0]
    void setBoost(float boost) {
        boost_ = std::clamp(boost, 0.0f, 1.0f);
        updateFilters();
    }

    float getBoost() const { return boost_; }

    void reset() {
        // Reset sub-bass lowpass states
        lp_x1_ = lp_x2_ = lp_y1_ = lp_y2_ = 0.0f;

        // Reset harmonic excitation states
        harm_lp_x1_ = harm_lp_x2_ = harm_lp_y1_ = harm_lp_y2_ = 0.0f;
        harm_bp_x1_l_ = harm_bp_x2_l_ = harm_bp_y1_l_ = harm_bp_y2_l_ = 0.0f;
        harm_bp_x1_r_ = harm_bp_x2_r_ = harm_bp_y1_r_ = harm_bp_y2_r_ = 0.0f;

        // Reset Pultec Low-End filter states
        pultec_boost_x1_l_ = pultec_boost_x2_l_ = pultec_boost_y1_l_ = pultec_boost_y2_l_ = 0.0f;
        pultec_boost_x1_r_ = pultec_boost_x2_r_ = pultec_boost_y1_r_ = pultec_boost_y2_r_ = 0.0f;

        pultec_scoop_x1_l_ = pultec_scoop_x2_l_ = pultec_scoop_y1_l_ = pultec_scoop_y2_l_ = 0.0f;
        pultec_scoop_x1_r_ = pultec_scoop_x2_r_ = pultec_scoop_y1_r_ = pultec_scoop_y2_r_ = 0.0f;
    }

    // Process interleaved stereo samples: [L0, R0, L1, R1, ...]
    void process(float* interleaved_samples, uint32_t frame_count) {
        if (!enabled_ || frame_count == 0 || !interleaved_samples) return;

        switch (profile_) {
            case BassEnhanceProfile::SubBassResonant:
            case BassEnhanceProfile::PunchyBass:
                processResonantSubBass(interleaved_samples, frame_count);
                break;
            case BassEnhanceProfile::HarmonicExciter:
                processHarmonicExciter(interleaved_samples, frame_count);
                break;
            case BassEnhanceProfile::PultecDeep:
                processPultecDeep(interleaved_samples, frame_count);
                break;
        }
    }

private:
    bool enabled_ = false;
    BassEnhanceProfile profile_ = BassEnhanceProfile::SubBassResonant;
    float sample_rate_ = 48000.0f;
    float cutoff_hz_ = 55.0f;
    float boost_ = 0.5f;

    // --- Resonant Low-Pass Filter Coefficients ---
    float lp_b0_ = 1.0f, lp_b1_ = 0.0f, lp_b2_ = 0.0f;
    float lp_a1_ = 0.0f, lp_a2_ = 0.0f;
    float lp_x1_ = 0.0f, lp_x2_ = 0.0f, lp_y1_ = 0.0f, lp_y2_ = 0.0f;

    // --- Harmonic Exciter Filter Coefficients ---
    float harm_lp_b0_ = 1.0f, harm_lp_b1_ = 0.0f, harm_lp_b2_ = 0.0f;
    float harm_lp_a1_ = 0.0f, harm_lp_a2_ = 0.0f;
    float harm_lp_x1_ = 0.0f, harm_lp_x2_ = 0.0f, harm_lp_y1_ = 0.0f, harm_lp_y2_ = 0.0f;

    float harm_bp_b0_ = 1.0f, harm_bp_b1_ = 0.0f, harm_bp_b2_ = 0.0f;
    float harm_bp_a1_ = 0.0f, harm_bp_a2_ = 0.0f;
    float harm_bp_x1_l_ = 0.0f, harm_bp_x2_l_ = 0.0f, harm_bp_y1_l_ = 0.0f, harm_bp_y2_l_ = 0.0f;
    float harm_bp_x1_r_ = 0.0f, harm_bp_x2_r_ = 0.0f, harm_bp_y1_r_ = 0.0f, harm_bp_y2_r_ = 0.0f;

    // --- Pultec Low-End Trick Coefficients ---
    // 1. Deep 45 Hz Low-Shelf Boost
    float pultec_boost_b0_ = 1.0f, pultec_boost_b1_ = 0.0f, pultec_boost_b2_ = 0.0f;
    float pultec_boost_a1_ = 0.0f, pultec_boost_a2_ = 0.0f;
    float pultec_boost_x1_l_ = 0.0f, pultec_boost_x2_l_ = 0.0f, pultec_boost_y1_l_ = 0.0f, pultec_boost_y2_l_ = 0.0f;
    float pultec_boost_x1_r_ = 0.0f, pultec_boost_x2_r_ = 0.0f, pultec_boost_y1_r_ = 0.0f, pultec_boost_y2_r_ = 0.0f;

    // 2. 300 Hz Mud-Scoop Peak Filter
    float pultec_scoop_b0_ = 1.0f, pultec_scoop_b1_ = 0.0f, pultec_scoop_b2_ = 0.0f;
    float pultec_scoop_a1_ = 0.0f, pultec_scoop_a2_ = 0.0f;
    float pultec_scoop_x1_l_ = 0.0f, pultec_scoop_x2_l_ = 0.0f, pultec_scoop_y1_l_ = 0.0f, pultec_scoop_y2_l_ = 0.0f;
    float pultec_scoop_x1_r_ = 0.0f, pultec_scoop_x2_r_ = 0.0f, pultec_scoop_y1_r_ = 0.0f, pultec_scoop_y2_r_ = 0.0f;

    void processResonantSubBass(float* samples, uint32_t frame_count) {
        const float bass_scale = boost_ * 1.8f;

        for (uint32_t i = 0; i < frame_count; i++) {
            float in_l = samples[2 * i];
            float in_r = samples[2 * i + 1];

            // Sub-bass phase coherence: mono sum
            float mono_in = (in_l + in_r) * 0.5f;

            // Direct Form I resonant low-pass
            float sub_bass = lp_b0_ * mono_in + lp_b1_ * lp_x1_ + lp_b2_ * lp_x2_
                           - lp_a1_ * lp_y1_ - lp_a2_ * lp_y2_;
            lp_x2_ = lp_x1_; lp_x1_ = mono_in;
            lp_y2_ = lp_y1_; lp_y1_ = sub_bass;

            // Soft-saturation to prevent digital clipping
            float sat_bass = std::tanh(sub_bass * bass_scale);

            samples[2 * i]     = in_l + sat_bass;
            samples[2 * i + 1] = in_r + sat_bass;
        }
    }

    void processHarmonicExciter(float* samples, uint32_t frame_count) {
        const float harmonic_drive = 1.0f + boost_ * 3.0f;
        const float harmonic_mix = boost_ * 1.2f;

        for (uint32_t i = 0; i < frame_count; i++) {
            float in_l = samples[2 * i];
            float in_r = samples[2 * i + 1];

            float mono_in = (in_l + in_r) * 0.5f;

            // 1. Extract fundamental sub-bass (< 80 Hz)
            float sub = harm_lp_b0_ * mono_in + harm_lp_b1_ * harm_lp_x1_ + harm_lp_b2_ * harm_lp_x2_
                      - harm_lp_a1_ * harm_lp_y1_ - harm_lp_a2_ * harm_lp_y2_;
            harm_lp_x2_ = harm_lp_x1_; harm_lp_x1_ = mono_in;
            harm_lp_y2_ = harm_lp_y1_; harm_lp_y1_ = sub;

            // 2. Synthesize 2nd (2f) & 3rd (3f) upper harmonics
            float driven = sub * harmonic_drive;
            float h2 = (driven * driven) * 0.5f;
            float h3 = (driven * driven * driven) * 0.25f;
            float raw_harmonics = h2 + h3;

            // 3. Bandpass filter harmonics (80-240 Hz)
            float filtered_h_l = harm_bp_b0_ * raw_harmonics + harm_bp_b1_ * harm_bp_x1_l_ + harm_bp_b2_ * harm_bp_x2_l_
                               - harm_bp_a1_ * harm_bp_y1_l_ - harm_bp_a2_ * harm_bp_y2_l_;
            harm_bp_x2_l_ = harm_bp_x1_l_; harm_bp_x1_l_ = raw_harmonics;
            harm_bp_y2_l_ = harm_bp_y1_l_; harm_bp_y1_l_ = filtered_h_l;

            samples[2 * i]     = in_l + (filtered_h_l * harmonic_mix);
            samples[2 * i + 1] = in_r + (filtered_h_l * harmonic_mix);
        }
    }

    void processPultecDeep(float* samples, uint32_t frame_count) {
        for (uint32_t i = 0; i < frame_count; i++) {
            float in_l = samples[2 * i];
            float in_r = samples[2 * i + 1];

            // Left Channel: Stage 1 Deep Low Shelf Boost
            float b_out_l = pultec_boost_b0_ * in_l + pultec_boost_b1_ * pultec_boost_x1_l_ + pultec_boost_b2_ * pultec_boost_x2_l_
                          - pultec_boost_a1_ * pultec_boost_y1_l_ - pultec_boost_a2_ * pultec_boost_y2_l_;
            pultec_boost_x2_l_ = pultec_boost_x1_l_; pultec_boost_x1_l_ = in_l;
            pultec_boost_y2_l_ = pultec_boost_y1_l_; pultec_boost_y1_l_ = b_out_l;

            // Left Channel: Stage 2 300Hz Boxiness / Mud Scoop
            float s_out_l = pultec_scoop_b0_ * b_out_l + pultec_scoop_b1_ * pultec_scoop_x1_l_ + pultec_scoop_b2_ * pultec_scoop_x2_l_
                          - pultec_scoop_a1_ * pultec_scoop_y1_l_ - pultec_scoop_a2_ * pultec_scoop_y2_l_;
            pultec_scoop_x2_l_ = pultec_scoop_x1_l_; pultec_scoop_x1_l_ = b_out_l;
            pultec_scoop_y2_l_ = pultec_scoop_y1_l_; pultec_scoop_y1_l_ = s_out_l;

            // Right Channel: Stage 1 Deep Low Shelf Boost
            float b_out_r = pultec_boost_b0_ * in_r + pultec_boost_b1_ * pultec_boost_x1_r_ + pultec_boost_b2_ * pultec_boost_x2_r_
                          - pultec_boost_a1_ * pultec_boost_y1_r_ - pultec_boost_a2_ * pultec_boost_y2_r_;
            pultec_boost_x2_r_ = pultec_boost_x1_r_; pultec_boost_x1_r_ = in_r;
            pultec_boost_y2_r_ = pultec_boost_y1_r_; pultec_boost_y1_r_ = b_out_r;

            // Right Channel: Stage 2 300Hz Boxiness / Mud Scoop
            float s_out_r = pultec_scoop_b0_ * b_out_r + pultec_scoop_b1_ * pultec_scoop_x1_r_ + pultec_scoop_b2_ * pultec_scoop_x2_r_
                          - pultec_scoop_a1_ * pultec_scoop_y1_r_ - pultec_scoop_a2_ * pultec_scoop_y2_r_;
            pultec_scoop_x2_r_ = pultec_scoop_x1_r_; pultec_scoop_x1_r_ = b_out_r;
            pultec_scoop_y2_r_ = pultec_scoop_y1_r_; pultec_scoop_y1_r_ = s_out_r;

            samples[2 * i]     = s_out_l;
            samples[2 * i + 1] = s_out_r;
        }
    }

    void updateFilters() {
        // Resonant low-pass filter
        float target_freq = (profile_ == BassEnhanceProfile::PunchyBass) ? (cutoff_hz_ * 1.3f) : cutoff_hz_;
        float Q = (profile_ == BassEnhanceProfile::PunchyBass) 
            ? (0.8f + boost_ * 2.2f) 
            : (0.55f + boost_ * 1.8f);

        calcLowpass(target_freq, Q, lp_b0_, lp_b1_, lp_b2_, lp_a1_, lp_a2_);

        // Psychoacoustic lowpass & bandpass
        calcLowpass(80.0f, 0.7071f, harm_lp_b0_, harm_lp_b1_, harm_lp_b2_, harm_lp_a1_, harm_lp_a2_);
        calcBandpass(80.0f, 240.0f, harm_bp_b0_, harm_bp_b1_, harm_bp_b2_, harm_bp_a1_, harm_bp_a2_);

        // Pultec EQP-1A Low-End Trick:
        // 1. Deep 45 Hz Low-Shelf (+0 dB to +10 dB boost)
        float pultec_boost_db = boost_ * 10.0f;
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
