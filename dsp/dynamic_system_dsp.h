#pragma once

#include <cmath>
#include <cstdint>
#include <algorithm>
#include <cstring>

namespace sauti::dsp {

enum class TransducerProfile {
    Earphone = 0,           // In-Ear Monitors: Fast punchy sub-lows (55 Hz - 160 Hz)
    Headphone = 1,          // Over-Ear: Full-body warm acoustic bass (35 Hz - 130 Hz)
    HighEndReference = 2,   // Open-Back / Planar: Linear deep sub-bass (25 Hz - 95 Hz)
    SpeakerMonitor = 3,     // Bookshelf / Portable: Excursion protection + presence (70 Hz - 190 Hz)
    ExtremeSubwoofer = 4,   // Club / Basshead Subwoofer: Deep visceral rumble & impact (30 Hz - 110 Hz)
    PureDynamic = 5         // Pure ViPER-style punch: Tight kick transient & dynamic bass body (45 Hz - 140 Hz)
};

class DynamicSystemDSP {
public:
    DynamicSystemDSP() {
        setSampleRate(48000.0f);
        setProfile(TransducerProfile::Headphone);
        reset();
    }

    void setSampleRate(float sampleRate) {
        if (sampleRate <= 0.0f) sampleRate = 48000.0f;
        if (std::abs(sample_rate_ - sampleRate) < 0.1f) return;
        sample_rate_ = sampleRate;
        updateCoefficients();
    }

    void setEnabled(bool enabled) {
        enabled_ = enabled;
        if (!enabled) {
            reset();
        }
    }

    bool isEnabled() const { return enabled_; }

    void setProfile(TransducerProfile profile) {
        profile_ = profile;
        updatePresetParams();
        updateCoefficients();
    }

    TransducerProfile getProfile() const { return profile_; }

    // Dynamic strength / drive [0.0, 1.0]
    void setStrength(float strength) {
        strength_ = std::clamp(strength, 0.0f, 1.0f);
        updatePresetParams();
        updateCoefficients();
    }

    float getStrength() const { return strength_; }

    // Manual ViPER-compatible algorithm parameters
    void setBassGain(float gain) {
        bass_gain_ = std::max(0.0f, gain);
    }

    void setSideGain(float gain_low, float gain_high) {
        if (gain_low >= 0.0f) side_gain_x_ = gain_low;
        if (gain_high >= 0.0f) side_gain_y_ = gain_high;
    }

    void setXCoeffs(float low, float high) {
        x_low_ = low;
        x_high_ = high;
        updateCoefficients();
    }

    void setYCoeffs(float low, float high) {
        y_low_ = low;
        y_high_ = high;
        updateCoefficients();
    }

    void reset() {
        std::memset(&left_ladder_, 0, sizeof(left_ladder_));
        std::memset(&right_ladder_, 0, sizeof(right_ladder_));
        updateCoefficients();
    }

    // Process interleaved stereo samples: [L0, R0, L1, R1, ...]
    void process(float* interleaved_samples, uint32_t frame_count) {
        if (!enabled_ || frame_count == 0 || !interleaved_samples) return;

        const float sat_makeup = 1.0f + 0.25f * strength_;

        for (uint32_t i = 0; i < frame_count; i++) {
            float in_l = interleaved_samples[2 * i];
            float in_r = interleaved_samples[2 * i + 1];

            float low_l, high_l, mid_l;
            processLadder(&left_ladder_, in_l, low_l, high_l, mid_l);

            float low_r, high_r, mid_r;
            processLadder(&right_ladder_, in_r, low_r, high_r, mid_r);

            // 1. Dynamic Pre-Boost Bass Excursion Staging
            float driven_low_l = low_l * bass_gain_;
            float driven_low_r = low_r * bass_gain_;

            // 2. Smooth Acoustic Excursion Non-Linearity (simulates physical cone excursion saturation)
            float sat_low_l = std::tanh(driven_low_l) * sat_makeup;
            float sat_low_r = std::tanh(driven_low_r) * sat_makeup;

            // 3. Phase-Aligned 3-Band Reconstruction with Sideband Clarity Balance
            interleaved_samples[2 * i]     = sat_low_l + (mid_l * side_gain_x_) + (high_l * side_gain_y_);
            interleaved_samples[2 * i + 1] = sat_low_r + (mid_r * side_gain_x_) + (high_r * side_gain_y_);
        }
    }

private:
    struct LadderState {
        float x[4];     // 4-stage low-pass poles for lower crossover (Sub-Bass)
        float y[4];     // 4-stage low-pass poles for upper crossover (Presence)
        float in_delay[3];
    };

    bool enabled_ = false;
    TransducerProfile profile_ = TransducerProfile::Headphone;
    float sample_rate_ = 48000.0f;
    float strength_ = 0.5f;

    float bass_gain_ = 2.8f;
    float x_low_ = 35.0f;
    float x_high_ = 130.0f;
    float y_low_ = 5000.0f;
    float y_high_ = 18000.0f;

    float lower_omega_ = 0.01f;
    float upper_omega_ = 0.5f;
    float side_gain_x_ = 1.0f;
    float side_gain_y_ = 1.0f;

    LadderState left_ladder_{};
    LadderState right_ladder_{};

    static constexpr float kDenormalPreventer = 1e-25f;

    inline void processLadder(LadderState* ladder, float sample, float& out_low, float& out_high, float& out_mid) {
        float oldest_in = ladder->in_delay[2];
        ladder->in_delay[2] = ladder->in_delay[1];
        ladder->in_delay[1] = ladder->in_delay[0];
        ladder->in_delay[0] = sample;

        // 4-Pole Lower Ladder (24 dB/octave slope for pure sub-bass isolation)
        ladder->x[0] += lower_omega_ * (sample - ladder->x[0]) + kDenormalPreventer;
        ladder->x[1] += lower_omega_ * (ladder->x[0] - ladder->x[1]) + kDenormalPreventer;
        ladder->x[2] += lower_omega_ * (ladder->x[1] - ladder->x[2]) + kDenormalPreventer;
        ladder->x[3] += lower_omega_ * (ladder->x[2] - ladder->x[3]) + kDenormalPreventer;

        // 4-Pole Upper Ladder (24 dB/octave slope for air/presence isolation)
        ladder->y[0] += upper_omega_ * (sample - ladder->y[0]) + kDenormalPreventer;
        ladder->y[1] += upper_omega_ * (ladder->y[0] - ladder->y[1]) + kDenormalPreventer;
        ladder->y[2] += upper_omega_ * (ladder->y[1] - ladder->y[2]) + kDenormalPreventer;
        ladder->y[3] += upper_omega_ * (ladder->y[2] - ladder->y[3]) + kDenormalPreventer;

        out_low  = ladder->x[3];                  // 4th-order low-pass (Sub-Bass)
        out_high = oldest_in - ladder->y[3];       // High-pass residual (Air/Treble)
        out_mid  = ladder->y[3] - ladder->x[3];   // Band-pass output (Vocal & Instrument body)
    }

    void updatePresetParams() {
        switch (profile_) {
            case TransducerProfile::Earphone:
                x_low_ = 55.0f;
                x_high_ = 160.0f;
                y_low_ = 4500.0f;
                y_high_ = 16000.0f;
                bass_gain_ = 1.0f + strength_ * 3.4f;
                side_gain_x_ = 1.08f + strength_ * 0.15f;
                side_gain_y_ = 1.15f + strength_ * 0.25f;
                break;

            case TransducerProfile::Headphone:
                x_low_ = 35.0f;
                x_high_ = 130.0f;
                y_low_ = 5000.0f;
                y_high_ = 18000.0f;
                bass_gain_ = 1.0f + strength_ * 3.0f;
                side_gain_x_ = 1.0f;
                side_gain_y_ = 1.05f + strength_ * 0.15f;
                break;

            case TransducerProfile::HighEndReference:
                x_low_ = 25.0f;
                x_high_ = 95.0f;
                y_low_ = 6500.0f;
                y_high_ = 22000.0f;
                bass_gain_ = 1.0f + strength_ * 2.2f;
                side_gain_x_ = 1.0f;
                side_gain_y_ = 1.0f;
                break;

            case TransducerProfile::SpeakerMonitor:
                x_low_ = 70.0f;
                x_high_ = 190.0f;
                y_low_ = 4000.0f;
                y_high_ = 15000.0f;
                bass_gain_ = 1.0f + strength_ * 3.6f;
                side_gain_x_ = 1.12f + strength_ * 0.2f;
                side_gain_y_ = 1.20f + strength_ * 0.3f;
                break;

            case TransducerProfile::ExtremeSubwoofer:
                x_low_ = 30.0f;
                x_high_ = 110.0f;
                y_low_ = 4200.0f;
                y_high_ = 18000.0f;
                bass_gain_ = 1.2f + strength_ * 4.6f;
                side_gain_x_ = 1.05f + strength_ * 0.1f;
                side_gain_y_ = 1.15f + strength_ * 0.2f;
                break;

            case TransducerProfile::PureDynamic:
                x_low_ = 45.0f;
                x_high_ = 140.0f;
                y_low_ = 5200.0f;
                y_high_ = 20000.0f;
                bass_gain_ = 1.0f + strength_ * 3.8f;
                side_gain_x_ = 1.0f;
                side_gain_y_ = 1.10f + strength_ * 0.2f;
                break;
        }
    }

    void updateCoefficients() {
        constexpr float PI = 3.14159265358979323846f;
        lower_omega_ = std::clamp(2.0f * PI * x_high_ / sample_rate_, 0.0001f, 0.95f);
        upper_omega_ = std::clamp(2.0f * PI * y_low_ / sample_rate_, 0.0001f, 0.95f);
    }
};

} // namespace sauti::dsp
