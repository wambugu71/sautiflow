#pragma once

#include <cmath>
#include <cstdint>
#include <algorithm>
#include <cstring>

namespace sauti::dsp {

enum class TransducerProfile {
    Earphone = 0,           // In-Ear Monitors: Fast punchy sub-lows & crystal vocal presence (55 Hz - 160 Hz)
    Headphone = 1,          // Over-Ear: Full-body warm acoustic bass & open staging (35 Hz - 130 Hz)
    HighEndReference = 2,   // Open-Back / Planar: Linear deep sub-bass & neutral clarity (25 Hz - 95 Hz)
    SpeakerMonitor = 3,     // Bookshelf / Portable: Excursion protection & dynamic punch (70 Hz - 190 Hz)
    ExtremeSubwoofer = 4,   // Club / Basshead Subwoofer: Deep visceral rumble & impact (30 Hz - 110 Hz)
    PureDynamic = 5         // Dynamic Transducer Punch: Tight kick transient & dynamic bass body (45 Hz - 140 Hz)
};

// =============================================================================
// DynamicSystemDSP: Dual-Cascade 4-Pole Transducer Simulation & Dynamic Resonance
// =============================================================================
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
        sample_period_ = 1.0f / sample_rate_;
        updateCoefficients();
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

    void setProfile(TransducerProfile profile) {
        if (profile_ != profile) {
            profile_ = profile;
            updatePresetParams();
            updateCoefficients();
        }
    }

    TransducerProfile getProfile() const { return profile_; }

    // Dynamic strength / drive [0.0, 1.0]
    void setStrength(float strength) {
        strength_ = std::clamp(strength, 0.0f, 1.0f);
        updatePresetParams();
        updateCoefficients();
    }

    float getStrength() const { return strength_; }

    void setBassGain(float gain) {
        target_bass_gain_ = std::max(0.0f, gain);
    }

    void setSideGain(float gain_low, float gain_high) {
        if (gain_low >= 0.0f) target_side_gain_x_ = gain_low;
        if (gain_high >= 0.0f) target_side_gain_y_ = gain_high;
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
        filter_x_[0] = LadderChannel{};
        filter_x_[1] = LadderChannel{};
        filter_y_[0] = LadderChannel{};
        filter_y_[1] = LadderChannel{};

        current_bass_gain_ = target_bass_gain_;
        current_side_gain_x_ = target_side_gain_x_;
        current_side_gain_y_ = target_side_gain_y_;
        current_low_ang_x_ = target_low_ang_x_;
        current_upp_ang_x_ = target_upp_ang_x_;
        current_low_ang_y_ = target_low_ang_y_;
        current_upp_ang_y_ = target_upp_ang_y_;

        anti_pop_ = 0.0f;
    }

    // Process interleaved stereo samples: [L0, R0, L1, R1, ...]
    void process(float* interleaved_samples, uint32_t frame_count) {
        if (!enabled_ || frame_count == 0 || !interleaved_samples) return;

        for (uint32_t i = 0; i < frame_count; i++) {
            // 1. Parameter de-zippering / smooth interpolation per sample
            current_bass_gain_   += smoothing_coeff_ * (target_bass_gain_ - current_bass_gain_);
            current_side_gain_x_ += smoothing_coeff_ * (target_side_gain_x_ - current_side_gain_x_);
            current_side_gain_y_ += smoothing_coeff_ * (target_side_gain_y_ - current_side_gain_y_);
            current_low_ang_x_   += smoothing_coeff_ * (target_low_ang_x_ - current_low_ang_x_);
            current_upp_ang_x_   += smoothing_coeff_ * (target_upp_ang_x_ - current_upp_ang_x_);
            current_low_ang_y_   += smoothing_coeff_ * (target_low_ang_y_ - current_low_ang_y_);
            current_upp_ang_y_   += smoothing_coeff_ * (target_upp_ang_y_ - current_upp_ang_y_);

            float in_l = interleaved_samples[2 * i];
            float in_r = interleaved_samples[2 * i + 1];

            // 2. Cascade Filter X on Left Channel (Stage 1: Multi-pole splitting)
            float x1_l, x2_l, x3_l;
            processLadder(&filter_x_[0], in_l, current_low_ang_x_, current_upp_ang_x_, x1_l, x2_l, x3_l);

            // 3. Cascade Filter X on Right Channel
            float x1_r, x2_r, x3_r;
            processLadder(&filter_x_[1], in_r, current_low_ang_x_, current_upp_ang_x_, x1_r, x2_r, x3_r);

            // 4. Drive bass band through Filter Y (Stage 2: Dynamic transducer resonance)
            float y1_l, y2_l, y3_l;
            processLadder(&filter_y_[0], current_bass_gain_ * x1_l, current_low_ang_y_, current_upp_ang_y_, y1_l, y2_l, y3_l);

            float y1_r, y2_r, y3_r;
            processLadder(&filter_y_[1], current_bass_gain_ * x1_r, current_low_ang_y_, current_upp_ang_y_, y1_r, y2_r, y3_r);

            // 5. Phase-aligned multi-band reconstruction
            float out_l = x2_l + y3_l + current_side_gain_x_ * y2_l + current_side_gain_y_ * y1_l + x3_l;
            float out_r = x2_r + y3_r + current_side_gain_x_ * y2_r + current_side_gain_y_ * y1_r + x3_r;

            // 6. Anti-pop smooth crossfade on activation
            if (anti_pop_ < 1.0f) {
                out_l = in_l + anti_pop_ * (out_l - in_l);
                out_r = in_r + anti_pop_ * (out_r - in_r);
                anti_pop_ = std::min(1.0f, anti_pop_ + sample_period_ * 4.0f);
            }

            // 7. Warm rational soft-clipping protection
            interleaved_samples[2 * i]     = softClip(out_l, 0.95f);
            interleaved_samples[2 * i + 1] = softClip(out_r, 0.95f);
        }
    }

private:
    struct LadderChannel {
        float in[3]{};
        float x[4]{};
        float y[4]{};
    };

    bool enabled_ = false;
    TransducerProfile profile_ = TransducerProfile::Headphone;
    float sample_rate_ = 48000.0f;
    float sample_period_ = 1.0f / 48000.0f;
    float strength_ = 0.5f;

    // Smoothed target parameters
    float target_bass_gain_ = 2.8f;
    float current_bass_gain_ = 2.8f;

    float target_side_gain_x_ = 1.0f;
    float current_side_gain_x_ = 1.0f;

    float target_side_gain_y_ = 1.0f;
    float current_side_gain_y_ = 1.0f;

    float x_low_ = 35.0f;
    float x_high_ = 130.0f;
    float y_low_ = 40.0f;
    float y_high_ = 12000.0f;

    float target_low_ang_x_ = 0.005f;
    float current_low_ang_x_ = 0.005f;

    float target_upp_ang_x_ = 0.02f;
    float current_upp_ang_x_ = 0.02f;

    float target_low_ang_y_ = 0.005f;
    float current_low_ang_y_ = 0.005f;

    float target_upp_ang_y_ = 0.5f;
    float current_upp_ang_y_ = 0.5f;

    float smoothing_coeff_ = 0.002f; // ~30ms smooth parameter ramp
    float anti_pop_ = 0.0f;

    LadderChannel filter_x_[2]{};
    LadderChannel filter_y_[2]{};

    static constexpr float kDenormal = 1e-25f;

    // Fast, clean rational soft clipper
    static inline float softClip(float v, float knee) {
        float drive = std::fabs(v);
        if (drive <= knee) return v;
        float over = drive - knee;
        float shaped = knee + over / std::sqrt(1.0f + over * over);
        return v * (shaped / drive);
    }

    inline void processLadder(LadderChannel* ch, float sample, float low_ang, float upp_ang, float& out1, float& out2, float& out3) {
        ch->in[2] = ch->in[1];
        ch->in[1] = ch->in[0];
        ch->in[0] = sample;

        // 4-Pole Low-Pass Ladder
        ch->x[0] += low_ang * (sample - ch->x[0]) + kDenormal;
        ch->x[1] += low_ang * (ch->x[0] - ch->x[1]) + kDenormal;
        ch->x[2] += low_ang * (ch->x[1] - ch->x[2]) + kDenormal;
        ch->x[3] += low_ang * (ch->x[2] - ch->x[3]) + kDenormal;

        // 4-Pole High-Pass / Upper Ladder
        ch->y[0] += upp_ang * (sample - ch->y[0]) + kDenormal;
        ch->y[1] += upp_ang * (ch->y[0] - ch->y[1]) + kDenormal;
        ch->y[2] += upp_ang * (ch->y[1] - ch->y[2]) + kDenormal;
        ch->y[3] += upp_ang * (ch->y[2] - ch->y[3]) + kDenormal;

        out1 = ch->x[3];            // Low-pass filtered sub-band
        out2 = sample - ch->y[3];   // High-pass residual, taken against the same
                                    // input sample for band alignment (the old
                                    // 3-sample-old input smeared the crossover)
        out3 = ch->y[3] - ch->x[3]; // Mid-frequency band
    }

    void updatePresetParams() {
        switch (profile_) {
            case TransducerProfile::Earphone:
                x_low_ = 140.0f;
                x_high_ = 90.0f;
                y_low_ = 45.0f;
                y_high_ = std::min(sample_rate_ * 0.25f, 16000.0f);
                target_bass_gain_ = 1.0f + strength_ * 3.4f;
                target_side_gain_x_ = 1.08f + strength_ * 0.15f;
                target_side_gain_y_ = 1.15f + strength_ * 0.25f;
                break;

            case TransducerProfile::Headphone:
                x_low_ = 130.0f;
                x_high_ = 80.0f;
                y_low_ = 40.0f;
                y_high_ = std::min(sample_rate_ * 0.25f, 18000.0f);
                target_bass_gain_ = 1.0f + strength_ * 3.0f;
                target_side_gain_x_ = 1.0f;
                target_side_gain_y_ = 1.05f + strength_ * 0.15f;
                break;

            case TransducerProfile::HighEndReference:
                x_low_ = 125.0f;
                x_high_ = 75.0f;
                y_low_ = 35.0f;
                y_high_ = std::min(sample_rate_ * 0.25f, 20000.0f);
                target_bass_gain_ = 1.0f + strength_ * 2.2f;
                target_side_gain_x_ = 1.0f;
                target_side_gain_y_ = 1.0f;
                break;

            case TransducerProfile::SpeakerMonitor:
                x_low_ = 160.0f;
                x_high_ = 100.0f;
                y_low_ = 50.0f;
                y_high_ = std::min(sample_rate_ * 0.25f, 15000.0f);
                target_bass_gain_ = 1.0f + strength_ * 3.6f;
                target_side_gain_x_ = 1.12f + strength_ * 0.2f;
                target_side_gain_y_ = 1.20f + strength_ * 0.3f;
                break;

            case TransducerProfile::ExtremeSubwoofer:
                x_low_ = 135.0f;
                x_high_ = 70.0f;
                y_low_ = 30.0f;
                y_high_ = std::min(sample_rate_ * 0.25f, 18000.0f);
                target_bass_gain_ = 1.2f + strength_ * 4.6f;
                target_side_gain_x_ = 1.05f + strength_ * 0.1f;
                target_side_gain_y_ = 1.15f + strength_ * 0.2f;
                break;

            case TransducerProfile::PureDynamic:
                x_low_ = 145.0f;
                x_high_ = 85.0f;
                y_low_ = 42.0f;
                y_high_ = std::min(sample_rate_ * 0.25f, 20000.0f);
                target_bass_gain_ = 1.0f + strength_ * 3.8f;
                target_side_gain_x_ = 1.0f;
                target_side_gain_y_ = 1.10f + strength_ * 0.2f;
                break;
        }
    }

    void updateCoefficients() {
        // Exact one-pole smoothing coefficient: a = 1 - exp(-2*PI*f/fs).
        // The previous linear f*PI/fs approximation overestimates the true
        // cutoff (~57% high at audio rates).
        const float coeff = 2.0f * 3.14159265358979323846f / sample_rate_;
        auto onePoleCoeff = [coeff](float f) {
            return std::clamp(1.0f - std::exp(-coeff * f), 0.0001f, 0.95f);
        };
        target_low_ang_x_ = onePoleCoeff(x_low_);
        target_upp_ang_x_ = onePoleCoeff(x_high_);
        target_low_ang_y_ = onePoleCoeff(y_low_);
        target_upp_ang_y_ = onePoleCoeff(y_high_);
    }
};

} // namespace sauti::dsp
