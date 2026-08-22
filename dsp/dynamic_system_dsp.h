#pragma once

#include <cmath>
#include <cstdint>
#include <algorithm>
#include <cstring>

namespace sauti::dsp {

enum class TransducerProfile {
    Earphone = 0,           // In-Ear Monitors: Fast punchy sub-lows (40 Hz - 160 Hz)
    Headphone = 1,          // Over-Ear: Full-body warm acoustic bass (30 Hz - 220 Hz)
    HighEndReference = 2,   // Open-Back / Planar: Linear deep sub-bass (20 Hz - 120 Hz)
    SpeakerMonitor = 3      // Bookshelf / Portable: Excursion protection + psychoacoustic presence
};

class DynamicSystemDSP {
public:
    DynamicSystemDSP() {
        setSampleRate(48000.0f);
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
        if (profile_ != profile) {
            profile_ = profile;
            reset();
            updateCoefficients();
        }
    }

    TransducerProfile getProfile() const { return profile_; }

    // Dynamic strength / drive [0.0, 1.0]
    void setStrength(float strength) {
        strength_ = std::clamp(strength, 0.0f, 1.0f);
        updateCoefficients();
    }

    float getStrength() const { return strength_; }

    void reset() {
        std::memset(&left_ladder_, 0, sizeof(left_ladder_));
        std::memset(&right_ladder_, 0, sizeof(right_ladder_));
        updateCoefficients();
    }

    // Process interleaved stereo samples: [L0, R0, L1, R1, ...]
    void process(float* interleaved_samples, uint32_t frame_count) {
        if (!enabled_ || frame_count == 0 || !interleaved_samples) return;

        const float bass_drive = 1.0f + strength_ * 1.5f;

        for (uint32_t i = 0; i < frame_count; i++) {
            float in_l = interleaved_samples[2 * i];
            float in_r = interleaved_samples[2 * i + 1];

            float low_l, high_l, mid_l;
            processLadder(&left_ladder_, in_l, low_l, high_l, mid_l);

            float low_r, high_r, mid_r;
            processLadder(&right_ladder_, in_r, low_r, high_r, mid_r);

            // Apply non-linear warm saturation to the isolated low band
            float sat_low_l = std::tanh(low_l * bass_drive);
            float sat_low_r = std::tanh(low_r * bass_drive);

            // Reconstruct the transducer-optimized signal
            interleaved_samples[2 * i]     = sat_low_l + (mid_l * side_gain_x_) + (high_l * side_gain_y_);
            interleaved_samples[2 * i + 1] = sat_low_r + (mid_r * side_gain_x_) + (high_r * side_gain_y_);
        }
    }

private:
    struct LadderState {
        float x[4];     // 4-stage low-pass poles for lower crossover
        float y[4];     // 4-stage low-pass poles for upper crossover
        float in_delay[3];
    };

    bool enabled_ = false;
    TransducerProfile profile_ = TransducerProfile::Headphone;
    float sample_rate_ = 48000.0f;
    float strength_ = 0.5f;

    float lower_omega_ = 0.01f;
    float upper_omega_ = 0.5f;
    float side_gain_x_ = 1.0f;
    float side_gain_y_ = 1.0f;

    LadderState left_ladder_{};
    LadderState right_ladder_{};

    static constexpr float kDenormalPreventer = 1e-25f;

    void processLadder(LadderState* ladder, float sample, float& out_low, float& out_high, float& out_mid) {
        float oldest_in = ladder->in_delay[2];
        ladder->in_delay[2] = ladder->in_delay[1];
        ladder->in_delay[1] = ladder->in_delay[0];
        ladder->in_delay[0] = sample;

        // 4-Pole Lower Ladder (24 dB/octave slope)
        ladder->x[0] += lower_omega_ * (sample - ladder->x[0]) + kDenormalPreventer;
        ladder->x[1] += lower_omega_ * (ladder->x[0] - ladder->x[1]) + kDenormalPreventer;
        ladder->x[2] += lower_omega_ * (ladder->x[1] - ladder->x[2]) + kDenormalPreventer;
        ladder->x[3] += lower_omega_ * (ladder->x[2] - ladder->x[3]) + kDenormalPreventer;

        // 4-Pole Upper Ladder (24 dB/octave slope)
        ladder->y[0] += upper_omega_ * (sample - ladder->y[0]) + kDenormalPreventer;
        ladder->y[1] += upper_omega_ * (ladder->y[0] - ladder->y[1]) + kDenormalPreventer;
        ladder->y[2] += upper_omega_ * (ladder->y[1] - ladder->y[2]) + kDenormalPreventer;
        ladder->y[3] += upper_omega_ * (ladder->y[2] - ladder->y[3]) + kDenormalPreventer;

        out_low  = ladder->x[3];                  // 4th-order low-pass output
        out_high = oldest_in - ladder->y[3];       // High-pass residual
        out_mid  = ladder->y[3] - ladder->x[3];   // Band-pass output
    }

    void updateCoefficients() {
        constexpr float PI = 3.14159265358979323846f;

        float f_low = 60.0f;
        float f_high = 6000.0f;

        switch (profile_) {
            case TransducerProfile::Earphone:
                f_low = 100.0f;
                f_high = 7000.0f;
                side_gain_x_ = 1.0f + strength_ * 0.2f;
                side_gain_y_ = 1.0f + strength_ * 0.35f;
                break;
            case TransducerProfile::Headphone:
                f_low = 65.0f;
                f_high = 8000.0f;
                side_gain_x_ = 1.0f;
                side_gain_y_ = 1.0f + strength_ * 0.2f;
                break;
            case TransducerProfile::HighEndReference:
                f_low = 40.0f;
                f_high = 9500.0f;
                side_gain_x_ = 1.0f;
                side_gain_y_ = 1.0f;
                break;
            case TransducerProfile::SpeakerMonitor:
                f_low = 120.0f;
                f_high = 5000.0f;
                side_gain_x_ = 1.05f + strength_ * 0.3f;
                side_gain_y_ = 1.1f + strength_ * 0.4f;
                break;
        }

        // Calculate discrete integrator step angles (omega)
        float nyquist = sample_rate_ * 0.5f;
        lower_omega_ = std::clamp(2.0f * PI * f_low / sample_rate_, 0.0001f, 0.95f);
        upper_omega_ = std::clamp(2.0f * PI * f_high / sample_rate_, 0.0001f, 0.95f);
    }
};

} // namespace sauti::dsp
