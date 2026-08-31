#pragma once

#include <cmath>
#include <cstdint>
#include <algorithm>
#include <array>
#include <cstring>

namespace sauti::dsp {

// =============================================================================
// Transducer & Hardware Simulation Profiles
// =============================================================================
enum class TransducerProfile {
    Earphone = 0,           // In-Ear Monitors: Fast punchy sub-lows & crystal vocal presence (180 Hz - 5800 Hz)
    Headphone = 1,          // Over-Ear: Full-body warm acoustic bass & open staging (300 Hz - 5600 Hz)
    HighEndReference = 2,   // Open-Back / Planar: Linear deep sub-bass & neutral clarity (140 Hz - 6200 Hz)
    SpeakerMonitor = 3,     // Bookshelf / Portable: Excursion protection & dynamic punch (400 Hz - 6200 Hz)
    ExtremeSubwoofer = 4,   // Club / Basshead Subwoofer: Deep visceral rumble & impact (800 Hz - 6200 Hz)
    PureDynamic = 5,        // Dynamic Transducer Punch: Tight kick transient & dynamic bass body (1000 Hz - 6200 Hz)

    // Extended Transducer Presets
    AudiophileReference = 6,
    StudioMonitorLows = 7,
    CinemaSubSlam = 8,
    CarAudioBass = 9,
    DeepAcousticWarmth = 10,
    CleanKickDrum = 11,
    ResonantRumble = 12,
    SubBassBoom = 13,
    SolidImpact = 14,
    RichLowEnd = 15,
    ClubPAPunch = 16,
    DeepSubExtension = 17,
    UltimateSubwoofer = 18
};

// =============================================================================
// Acoustic Tuning Presets (Dual-Cascade 4-Pole Multi-Band Matrix)
// =============================================================================
struct DynamicSystemPreset {
    const char* name;
    float x_low;       // Stage 1 low-bass crossover frequency (Hz)
    float x_high;      // Stage 1 upper-treble crossover frequency (Hz)
    float y_low;       // Stage 2 sub-bass cutoff frequency (Hz)
    float y_high;      // Stage 2 mid-bass cutoff frequency (Hz)
    float side_gain_x; // Resonant upper-bass transient contour
    float side_gain_y; // Infrasonic sub-rumble contour
    float max_drive;   // Maximum bass boost headroom multiplier
};

inline constexpr std::array<DynamicSystemPreset, 19> kDynamicSystemPresets = {{
    { "In-Ear Earbuds",       180.0f,  5800.0f, 55.0f, 80.0f,  0.10f, 0.70f, 3.4f }, // 0: Earphone
    { "Over-Ear Headphones",  300.0f,  5600.0f, 60.0f, 105.0f, 0.10f, 0.50f, 3.0f }, // 1: Headphone
    { "Studio Reference",     140.0f,  6200.0f, 40.0f, 60.0f,  0.10f, 0.80f, 2.2f }, // 2: HighEndReference
    { "Desktop Speakers",     400.0f,  6200.0f, 40.0f, 80.0f,  0.10f, 0.00f, 3.6f }, // 3: SpeakerMonitor
    { "Club Subwoofer",       800.0f,  6200.0f, 80.0f, 140.0f, 0.00f, 0.00f, 4.6f }, // 4: ExtremeSubwoofer
    { "Pure Dynamic",         1000.0f, 6200.0f, 50.0f, 90.0f,  0.30f, 0.10f, 3.8f }, // 5: PureDynamic
    { "Audiophile Open-Back", 1000.0f, 6200.0f, 60.0f, 100.0f, 0.00f, 0.00f, 2.5f }, // 6
    { "Studio Monitor Lows",  1000.0f, 6200.0f, 60.0f, 120.0f, 0.00f, 0.00f, 2.8f }, // 7
    { "Cinema Sub Slam",      1200.0f, 6200.0f, 60.0f, 100.0f, 0.00f, 0.30f, 4.2f }, // 8
    { "Car Audio Bass",       1200.0f, 6200.0f, 40.0f, 80.0f,  0.00f, 0.30f, 4.0f }, // 9
    { "Deep Acoustic Warmth", 600.0f,  5400.0f, 60.0f, 105.0f, 0.10f, 0.20f, 2.8f }, // 10
    { "Clean Kick Drum",      400.0f,  6200.0f, 40.0f, 80.0f,  0.10f, 0.00f, 3.2f }, // 11
    { "Resonant Rumble",      1200.0f, 6200.0f, 50.0f, 100.0f, 0.10f, 0.50f, 4.4f }, // 12
    { "Sub-Bass Boom",        1200.0f, 6200.0f, 40.0f, 80.0f,  0.00f, 0.20f, 4.8f }, // 13
    { "Solid Impact",         800.0f,  6200.0f, 40.0f, 80.0f,  0.10f, 0.00f, 3.5f }, // 14
    { "Rich Low-End",         1200.0f, 6200.0f, 50.0f, 90.0f,  0.15f, 0.10f, 3.6f }, // 15
    { "Club PA Punch",        1000.0f, 6200.0f, 50.0f, 90.0f,  0.30f, 0.10f, 4.0f }, // 16
    { "Deep Sub Extension",   1000.0f, 6200.0f, 80.0f, 140.0f, 0.00f, 0.00f, 4.5f }, // 17
    { "Ultimate Subwoofer",   800.0f,  6200.0f, 80.0f, 140.0f, 0.00f, 0.00f, 5.0f }  // 18
}};

// =============================================================================
// DynamicSystemDSP: Dual-Cascade 4-Pole Multi-Band Transducer Simulation & Bass Engine
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
        smoothing_coeff_ = 1.0f - std::exp(-1.0f / (0.030f * sample_rate_)); // ~30ms ramp
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
            preset_index_ = static_cast<int>(profile);
            updatePresetParams();
            updateCoefficients();
        }
    }

    TransducerProfile getProfile() const { return profile_; }

    void setPreset(int presetIndex) {
        if (presetIndex < 0) presetIndex = 0;
        if (presetIndex >= static_cast<int>(kDynamicSystemPresets.size())) {
            presetIndex = static_cast<int>(kDynamicSystemPresets.size()) - 1;
        }
        preset_index_ = presetIndex;
        profile_ = static_cast<TransducerProfile>(presetIndex);
        updatePresetParams();
        updateCoefficients();
    }

    int getPreset() const { return preset_index_; }

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
        if (low > 0.0f) x_low_ = low;
        if (high > 0.0f) x_high_ = high;
        updateCoefficients();
    }

    void setYCoeffs(float low, float high) {
        if (low > 0.0f) y_low_ = low;
        if (high > 0.0f) y_high_ = high;
        updateCoefficients();
    }

    void reset() {
        filter_x_[0] = LadderChannel{};
        filter_x_[1] = LadderChannel{};
        filter_y_[0] = LadderChannel{};
        filter_y_[1] = LadderChannel{};

        dynamic_lp_biquad_.reset();

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
            // 1. Parameter de-zippering / smooth exponential interpolation per sample
            current_bass_gain_   += smoothing_coeff_ * (target_bass_gain_ - current_bass_gain_);
            current_side_gain_x_ += smoothing_coeff_ * (target_side_gain_x_ - current_side_gain_x_);
            current_side_gain_y_ += smoothing_coeff_ * (target_side_gain_y_ - current_side_gain_y_);
            current_low_ang_x_   += smoothing_coeff_ * (target_low_ang_x_ - current_low_ang_x_);
            current_upp_ang_x_   += smoothing_coeff_ * (target_upp_ang_x_ - current_upp_ang_x_);
            current_low_ang_y_   += smoothing_coeff_ * (target_low_ang_y_ - current_low_ang_y_);
            current_upp_ang_y_   += smoothing_coeff_ * (target_upp_ang_y_ - current_upp_ang_y_);

            float in_l = interleaved_samples[2 * i];
            float in_r = interleaved_samples[2 * i + 1];

            float out_l = in_l;
            float out_r = in_r;

            if (x_low_ <= 120.0f) {
                // Sub-120Hz dynamic resonant path: variable-Q low-pass bass injection
                const double mono_in = (static_cast<double>(in_l) + static_cast<double>(in_r)) * 0.5;
                const float low_out = static_cast<float>(dynamic_lp_biquad_.process(mono_in));
                out_l = in_l + low_out * (current_bass_gain_ - 1.0f);
                out_r = in_r + low_out * (current_bass_gain_ - 1.0f);
            } else {
                // 2. Stage 1: 4-Pole Ladder X (Left & Right Channel Multi-Band Decomposition)
                float x1_l, x2_l, x3_l;
                processLadder(&filter_x_[0], in_l, current_low_ang_x_, current_upp_ang_x_, x1_l, x2_l, x3_l);

                float x1_r, x2_r, x3_r;
                processLadder(&filter_x_[1], in_r, current_low_ang_x_, current_upp_ang_x_, x1_r, x2_r, x3_r);

                // 3. Stage 2: 4-Pole Ladder Y (Dynamic Bass Resonance & Transducer Excitation)
                float y1_l, y2_l, y3_l;
                processLadder(&filter_y_[0], current_bass_gain_ * x1_l, current_low_ang_y_, current_upp_ang_y_, y1_l, y2_l, y3_l);

                float y1_r, y2_r, y3_r;
                processLadder(&filter_y_[1], current_bass_gain_ * x1_r, current_low_ang_y_, current_upp_ang_y_, y1_r, y2_r, y3_r);

                // 4. Phase-Aligned Matrix Reconstruction
                out_l = x2_l + y3_l + current_side_gain_x_ * y2_l + current_side_gain_y_ * y1_l + x3_l;
                out_r = x2_r + y3_r + current_side_gain_x_ * y2_r + current_side_gain_y_ * y1_r + x3_r;
            }

            // 5. Anti-pop smooth crossfade on activation / profile change
            if (anti_pop_ < 1.0f) {
                out_l = in_l + anti_pop_ * (out_l - in_l);
                out_r = in_r + anti_pop_ * (out_r - in_r);
                anti_pop_ = std::min(1.0f, anti_pop_ + sample_period_ * 4.0f);
            }

            // 6. Warm rational soft-clipping protection (0.95 knee)
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

    class DynamicBiquad {
    public:
        void reset() {
            x1_ = x2_ = y1_ = y2_ = 0.0;
        }

        void setLowPass(double freq, double sampleRate, double Q) {
            if (sampleRate <= 0.0) sampleRate = 48000.0;
            if (freq <= 0.0) freq = 55.0;
            if (freq >= sampleRate * 0.49) freq = sampleRate * 0.49;
            if (Q <= 0.01) Q = 0.7071;

            const double w0 = 2.0 * 3.14159265358979323846 * freq / sampleRate;
            const double alpha = std::sin(w0) / (2.0 * Q);
            const double cos_w0 = std::cos(w0);

            const double a0 = 1.0 + alpha;
            b0_ = ((1.0 - cos_w0) * 0.5) / a0;
            b1_ = (1.0 - cos_w0) / a0;
            b2_ = ((1.0 - cos_w0) * 0.5) / a0;
            a1_ = (-2.0 * cos_w0) / a0;
            a2_ = (1.0 - alpha) / a0;
        }

        inline double process(double in) {
            double out = b0_ * in + b1_ * x1_ + b2_ * x2_ - a1_ * y1_ - a2_ * y2_;
            x2_ = x1_;
            x1_ = in;
            y2_ = y1_;
            y1_ = out;
            return out;
        }

    private:
        double b0_ = 1.0, b1_ = 0.0, b2_ = 0.0;
        double a1_ = 0.0, a2_ = 0.0;
        double x1_ = 0.0, x2_ = 0.0, y1_ = 0.0, y2_ = 0.0;
    };

    bool enabled_ = false;
    TransducerProfile profile_ = TransducerProfile::Headphone;
    int preset_index_ = 1;
    float sample_rate_ = 48000.0f;
    float sample_period_ = 1.0f / 48000.0f;
    float strength_ = 0.5f;

    // Target parameters for smoothing
    float target_bass_gain_ = 2.5f;
    float current_bass_gain_ = 2.5f;

    float target_side_gain_x_ = 1.0f;
    float current_side_gain_x_ = 1.0f;

    float target_side_gain_y_ = 1.0f;
    float current_side_gain_y_ = 1.0f;

    float x_low_ = 300.0f;
    float x_high_ = 5600.0f;
    float y_low_ = 60.0f;
    float y_high_ = 105.0f;

    float target_low_ang_x_ = 0.038f;
    float current_low_ang_x_ = 0.038f;

    float target_upp_ang_x_ = 0.52f;
    float current_upp_ang_x_ = 0.52f;

    float target_low_ang_y_ = 0.0078f;
    float current_low_ang_y_ = 0.0078f;

    float target_upp_ang_y_ = 0.0136f;
    float current_upp_ang_y_ = 0.0136f;

    float smoothing_coeff_ = 0.00069f; // ~30ms smooth parameter ramp
    float anti_pop_ = 0.0f;

    LadderChannel filter_x_[2]{};
    LadderChannel filter_y_[2]{};
    DynamicBiquad dynamic_lp_biquad_{};

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

        // 4-Pole Low-Pass Ladder (x)
        ch->x[0] += low_ang * (sample - ch->x[0]) + kDenormal;
        ch->x[1] += low_ang * (ch->x[0] - ch->x[1]) + kDenormal;
        ch->x[2] += low_ang * (ch->x[1] - ch->x[2]) + kDenormal;
        ch->x[3] += low_ang * (ch->x[2] - ch->x[3]) + kDenormal;

        // 4-Pole High-Pass / Upper Ladder (y)
        ch->y[0] += upp_ang * (sample - ch->y[0]) + kDenormal;
        ch->y[1] += upp_ang * (ch->y[0] - ch->y[1]) + kDenormal;
        ch->y[2] += upp_ang * (ch->y[1] - ch->y[2]) + kDenormal;
        ch->y[3] += upp_ang * (ch->y[2] - ch->y[3]) + kDenormal;

        out1 = ch->x[3];            // Low-pass filtered sub-band
        out2 = sample - ch->y[3];   // High-pass residual (aligned against sample input)
        out3 = ch->y[3] - ch->x[3]; // Mid-frequency crossover band
    }

    void updatePresetParams() {
        size_t idx = static_cast<size_t>(preset_index_);
        if (idx >= kDynamicSystemPresets.size()) idx = 1; // Default to Over-Ear

        const auto& preset = kDynamicSystemPresets[idx];
        x_low_ = preset.x_low;
        x_high_ = preset.x_high;
        y_low_ = preset.y_low;
        y_high_ = preset.y_high;

        // At strength = 0.0f, all gains are 1.0f (exact 0 dB unity identity)
        // At strength > 0.0f, boost low bass and blend side gains
        target_bass_gain_ = 1.0f + strength_ * (preset.max_drive - 1.0f);
        target_side_gain_x_ = 1.0f + strength_ * (preset.side_gain_x - 1.0f);
        target_side_gain_y_ = 1.0f + strength_ * (preset.side_gain_y - 1.0f);
    }

    void updateCoefficients() {
        // Exact one-pole filter digital integrator: a = 1 - exp(-2*PI*f/fs)
        const float coeff = 2.0f * 3.14159265358979323846f / sample_rate_;
        auto onePoleCoeff = [coeff](float f) {
            return std::clamp(1.0f - std::exp(-coeff * f), 0.0001f, 0.95f);
        };
        target_low_ang_x_ = onePoleCoeff(x_low_);
        target_upp_ang_x_ = onePoleCoeff(x_high_);
        target_low_ang_y_ = onePoleCoeff(y_low_);
        target_upp_ang_y_ = onePoleCoeff(y_high_);

        // Sub-120Hz dynamic resonant biquad (55 Hz base with variable Q from bass gain)
        const float q_peak = std::clamp((target_bass_gain_ - 1.0f) / 20.0f * 1600.0f, 0.0f, 1600.0f);
        dynamic_lp_biquad_.setLowPass(55.0, static_cast<double>(sample_rate_), static_cast<double>(q_peak / 666.0f + 0.5f));
    }
};

} // namespace sauti::dsp
