#pragma once

#include <cmath>
#include <cstdint>
#include <algorithm>
#include <array>
#include "denormals.h"
#include "simd_math.h"

namespace sauti::dsp {

// =============================================================================
// Transducer & Hardware Simulation Profiles
// =============================================================================
enum class TransducerProfile {
    Earphone = 0,           // In-Ear Monitors: Punchy sub-lows & balanced vocal clarity
    Headphone = 1,          // Over-Ear: Full-body warm acoustic bass & open staging
    HighEndReference = 2,   // Open-Back / Planar: Linear deep sub-bass & neutral clarity
    SpeakerMonitor = 3,     // Bookshelf / Portable: Excursion protection & dynamic punch
    ExtremeSubwoofer = 4,   // Club / Basshead Subwoofer: Deep visceral rumble & impact
    PureDynamic = 5,        // Dynamic Transducer Punch: Tight kick transient & dynamic bass body

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
    UltimateSubwoofer = 18,
    Custom = 19
};

// =============================================================================
// Acoustic Tuning Presets (Phase-Coherent 5-Band LR4 Crossover Matrix)
// =============================================================================
struct DynamicSystemPreset {
    const char* name;
    float x_low;       // Upper-bass / midrange crossover frequency (Hz)
    float x_high;      // Upper-treble air crossover frequency (Hz)
    float y_low;       // Sub-bass / punch crossover frequency (Hz)
    float y_high;      // Punch / upper-bass crossover frequency (Hz)
    float side_gain_x; // Upper-bass warmth contour [0.0 .. 1.0]
    float side_gain_y; // Sub-bass extension contour [0.0 .. 1.0]
    float max_drive;   // Maximum bass boost linear multiplier at 100% strength
};

inline constexpr std::array<DynamicSystemPreset, 19> kDynamicSystemPresets = {{
    { "In-Ear Earbuds",       180.0f, 5800.0f, 55.0f,  80.0f, 0.10f, 0.70f, 2.8f }, // 0: Earphone
    { "Over-Ear Headphones",  300.0f, 5600.0f, 60.0f, 105.0f, 0.10f, 0.50f, 2.6f }, // 1: Headphone
    { "Studio Reference",     140.0f, 6200.0f, 40.0f,  60.0f, 0.10f, 0.80f, 2.0f }, // 2: HighEndReference
    { "Desktop Speakers",     280.0f, 6200.0f, 45.0f,  85.0f, 0.15f, 0.25f, 3.0f }, // 3: SpeakerMonitor
    { "Club Subwoofer",       260.0f, 6200.0f, 55.0f, 110.0f, 0.10f, 0.75f, 3.8f }, // 4: ExtremeSubwoofer
    { "Pure Dynamic",         320.0f, 6200.0f, 50.0f,  90.0f, 0.30f, 0.45f, 3.2f }, // 5: PureDynamic
    { "Audiophile Open-Back", 220.0f, 6200.0f, 45.0f,  85.0f, 0.10f, 0.65f, 2.1f }, // 6
    { "Studio Monitor Lows",  240.0f, 6200.0f, 50.0f,  95.0f, 0.10f, 0.55f, 2.3f }, // 7
    { "Cinema Sub Slam",      260.0f, 6200.0f, 45.0f,  90.0f, 0.10f, 0.85f, 3.6f }, // 8
    { "Car Audio Bass",       280.0f, 6200.0f, 40.0f,  85.0f, 0.15f, 0.80f, 3.5f }, // 9
    { "Deep Acoustic Warmth", 300.0f, 5400.0f, 55.0f, 105.0f, 0.25f, 0.50f, 2.5f }, // 10
    { "Clean Kick Drum",      250.0f, 6200.0f, 55.0f,  95.0f, 0.20f, 0.25f, 2.9f }, // 11
    { "Resonant Rumble",      260.0f, 6200.0f, 40.0f,  85.0f, 0.15f, 0.90f, 3.7f }, // 12
    { "Sub-Bass Boom",        240.0f, 6200.0f, 38.0f,  78.0f, 0.10f, 0.95f, 4.0f }, // 13
    { "Solid Impact",         280.0f, 6200.0f, 50.0f,  90.0f, 0.20f, 0.40f, 3.1f }, // 14
    { "Rich Low-End",         320.0f, 6200.0f, 50.0f,  95.0f, 0.25f, 0.60f, 3.2f }, // 15
    { "Club PA Punch",        320.0f, 6200.0f, 45.0f,  90.0f, 0.30f, 0.65f, 3.5f }, // 16
    { "Deep Sub Extension",   220.0f, 6200.0f, 35.0f,  75.0f, 0.05f, 1.00f, 3.8f }, // 17
    { "Ultimate Subwoofer",   260.0f, 6200.0f, 45.0f,  95.0f, 0.10f, 0.90f, 4.2f }  // 18
}};

// =============================================================================
// DynamicSystemDSP: Phase-Coherent 5-Band LR4 Transducer Simulation (64-bit SIMD)
//
// Splits stereo audio using 4th-order Linkwitz-Riley (LR4) TPT State Variable
// crossovers with matched 2nd-order Butterworth all-pass phase aligners so all
// 5 bands (Sub, Punch, Upper-Bass, Mid, Air) sum back to an exact all-pass
// unity magnitude response (0.00 dB) with zero destructive phase notches.
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
        if (initialized_ && std::abs(sample_rate_ - sampleRate) < 0.1f) return;
        sample_rate_ = sampleRate;
        sample_period_ = 1.0f / sample_rate_;
        smoothing_coeff_ = 1.0f - std::exp(-1.0f / (0.030f * sample_rate_)); // 30ms ramp
        anti_pop_step_ = 1.0f / (0.015f * sample_rate_); // 15ms click-free fade-in/out
        updatePresetParams();
        updateCoefficients();
        initialized_ = true;
    }

    void setEnabled(bool enabled) {
        enabled_ = enabled;
    }

    bool isEnabled() const { return enabled_; }

    bool isActive() const { return enabled_ || anti_pop_ > 0.0f; }

    void setProfile(TransducerProfile profile) {
        if (profile_ != profile) {
            profile_ = profile;
            if (profile != TransducerProfile::Custom) {
                preset_index_ = std::clamp(static_cast<int>(profile), 0, static_cast<int>(kDynamicSystemPresets.size()) - 1);
                updatePresetParams();
                updateCoefficients();
            }
        }
    }

    TransducerProfile getProfile() const { return profile_; }

    void setPreset(int presetIndex) {
        presetIndex = std::clamp(presetIndex, 0, static_cast<int>(kDynamicSystemPresets.size()) - 1);
        preset_index_ = presetIndex;
        profile_ = static_cast<TransducerProfile>(presetIndex);
        updatePresetParams();
        updateCoefficients();
    }

    int getPreset() const { return preset_index_; }

    // Dynamic strength / drive [0.0, 1.0]
    void setStrength(float strength) {
        strength_ = std::clamp(strength, 0.0f, 1.0f);
        if (profile_ != TransducerProfile::Custom) {
            updatePresetParams();
            updateCoefficients();
        }
    }

    float getStrength() const { return strength_; }

    void setBassGain(float gain) {
        target_bass_gain_ = std::clamp(gain, 0.5f, 8.0f);
        target_air_gain_ = 1.0f + std::clamp((target_bass_gain_ - 1.0f) / 3.0f, 0.0f, 1.0f) * 0.15f;
    }

    void setSideGain(float gain_low, float gain_high) {
        if (gain_low >= 0.0f) target_side_gain_x_ = std::clamp(gain_low, 0.0f, 1.5f);
        if (gain_high >= 0.0f) target_side_gain_y_ = std::clamp(gain_high, 0.0f, 1.5f);
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

    // Atomic custom parameter update (avoids partial updates or intermediate preset fallback)
    void setCustomParams(float x_low, float x_high, float y_low, float y_high,
                         float side_gain_low, float side_gain_high, float bass_gain) {
        profile_ = TransducerProfile::Custom;
        if (x_low > 0.0f) x_low_ = x_low;
        if (x_high > 0.0f) x_high_ = x_high;
        if (y_low > 0.0f) y_low_ = y_low;
        if (y_high > 0.0f) y_high_ = y_high;
        target_side_gain_x_ = std::clamp(side_gain_low, 0.0f, 1.5f);
        target_side_gain_y_ = std::clamp(side_gain_high, 0.0f, 1.5f);
        target_bass_gain_ = std::clamp(bass_gain, 0.5f, 8.0f);
        target_air_gain_ = 1.0f + std::clamp((target_bass_gain_ - 1.0f) / 3.0f, 0.0f, 1.0f) * 0.15f;
        updateCoefficients();
    }

    void reset() {
        split_xlow_.reset();
        split_xhigh_.reset();
        split_ylow_.reset();
        split_yhigh_.reset();
        ap_ubass_ylow_.reset();
        ap_lo_xhigh_.reset();
        ap_up_ylow_.reset();
        ap_up_yhigh_.reset();

        current_bass_gain_ = target_bass_gain_;
        current_side_gain_x_ = target_side_gain_x_;
        current_side_gain_y_ = target_side_gain_y_;
        current_air_gain_ = target_air_gain_;
        current_x_low_ = target_x_low_;
        current_x_high_ = target_x_high_;
        current_y_low_ = target_y_low_;
        current_y_high_ = target_y_high_;
        cached_x_low_ = -1.0f;
        cached_x_high_ = -1.0f;
        cached_y_low_ = -1.0f;
        cached_y_high_ = -1.0f;
        applyCrossoverFrequencies();

        anti_pop_ = 0.0f;
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
    struct StereoTptSvf {
        static constexpr double kButterworthK = 1.4142135623730950488;
        double a1 = 0.0;
        double a2 = 0.0;
        double a3 = 0.0;
        SimdDouble2 ic1{0.0};
        SimdDouble2 ic2{0.0};

        void reset() {
            ic1 = SimdDouble2(0.0);
            ic2 = SimdDouble2(0.0);
        }

        void setFrequency(double fc, double fs) {
            constexpr double kPi = 3.14159265358979323846;
            const double clampedFc = std::clamp(fc, 15.0, fs * 0.45);
            const double g = std::tan(kPi * clampedFc / fs);
            a1 = 1.0 / (1.0 + g * (g + kButterworthK));
            a2 = g * a1;
            a3 = g * a2;
        }

        inline void processLpHp(const SimdDouble2& in, SimdDouble2& lp, SimdDouble2& hp) {
            const SimdDouble2 va1(a1), va2(a2), va3(a3);
            const SimdDouble2 vk(kButterworthK), vTwo(2.0);
            const SimdDouble2 v3 = in - ic2;
            const SimdDouble2 v1 = SimdDouble2::fma(va1, ic1, va2 * v3);
            const SimdDouble2 v2 = SimdDouble2::fma(va2, ic1, ic2) + (va3 * v3);
            ic1 = (vTwo * v1) - ic1;
            ic2 = (vTwo * v2) - ic2;
            lp = v2;
            hp = in - (vk * v1) - v2;
        }

        inline SimdDouble2 processAp(const SimdDouble2& in) {
            const SimdDouble2 va1(a1), va2(a2), va3(a3);
            const SimdDouble2 vTwoK(2.0 * kButterworthK), vTwo(2.0);
            const SimdDouble2 v3 = in - ic2;
            const SimdDouble2 v1 = SimdDouble2::fma(va1, ic1, va2 * v3);
            const SimdDouble2 v2 = SimdDouble2::fma(va2, ic1, ic2) + (va3 * v3);
            ic1 = (vTwo * v1) - ic1;
            ic2 = (vTwo * v2) - ic2;
            return in - (vTwoK * v1);
        }
    };

    struct StereoLr4Split {
        StereoTptSvf s1;
        StereoTptSvf s2_lp;
        StereoTptSvf s2_hp;

        void reset() {
            s1.reset();
            s2_lp.reset();
            s2_hp.reset();
        }

        void setFrequency(double fc, double fs) {
            s1.setFrequency(fc, fs);
            s2_lp.setFrequency(fc, fs);
            s2_hp.setFrequency(fc, fs);
        }

        inline void process(const SimdDouble2& in, SimdDouble2& lp4, SimdDouble2& hp4) {
            SimdDouble2 lp1, hp1, unused;
            s1.processLpHp(in, lp1, hp1);
            s2_lp.processLpHp(lp1, lp4, unused);
            s2_hp.processLpHp(hp1, unused, hp4);
        }
    };

    template <typename T>
    void processImpl(T* interleaved_samples, uint32_t frame_count) {
        if ((!enabled_ && anti_pop_ <= 0.0f) || frame_count == 0 || !interleaved_samples) return;

        ScopedDenormalsDisable denormals;

        for (uint32_t i = 0; i < frame_count; ++i) {
            // 1. Smooth parameter interpolation per sample (30ms tau)
            current_bass_gain_   += smoothing_coeff_ * (target_bass_gain_ - current_bass_gain_);
            current_side_gain_x_ += smoothing_coeff_ * (target_side_gain_x_ - current_side_gain_x_);
            current_side_gain_y_ += smoothing_coeff_ * (target_side_gain_y_ - current_side_gain_y_);
            current_air_gain_    += smoothing_coeff_ * (target_air_gain_ - current_air_gain_);
            current_x_low_       += smoothing_coeff_ * (target_x_low_ - current_x_low_);
            current_x_high_      += smoothing_coeff_ * (target_x_high_ - current_x_high_);
            current_y_low_       += smoothing_coeff_ * (target_y_low_ - current_y_low_);
            current_y_high_      += smoothing_coeff_ * (target_y_high_ - current_y_high_);

            if ((i & 31) == 0) {
                if (std::abs(current_x_low_ - cached_x_low_) > 0.25f ||
                    std::abs(current_x_high_ - cached_x_high_) > 0.25f ||
                    std::abs(current_y_low_ - cached_y_low_) > 0.25f ||
                    std::abs(current_y_high_ - cached_y_high_) > 0.25f) {
                    applyCrossoverFrequencies();
                }
            }

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
            const SimdDouble2 vin(in_l, in_r);

            // 2. Phase-coherent 5-band LR4 stereo decomposition
            SimdDouble2 x_lo, x_hi;
            split_xlow_.process(vin, x_lo, x_hi);

            SimdDouble2 y_lm, b_ubass_raw;
            split_yhigh_.process(x_lo, y_lm, b_ubass_raw);

            SimdDouble2 b_sub, b_punch;
            split_ylow_.process(y_lm, b_sub, b_punch);
            const SimdDouble2 b_ubass = ap_ubass_ylow_.processAp(b_ubass_raw);

            SimdDouble2 b_mid_raw, b_air_raw;
            split_xhigh_.process(x_hi, b_mid_raw, b_air_raw);

            // 3. Band gains (exact 1.0 unity identity at strength = 0)
            const double drive = std::max(0.0, static_cast<double>(current_bass_gain_) - 1.0);
            const double g_sub = 1.0 + drive * (0.30 + 0.70 * static_cast<double>(current_side_gain_y_));
            const double g_punch = 1.0 + drive;
            const double g_ubass = 1.0 + drive * (0.40 * static_cast<double>(current_side_gain_x_));
            const double g_air = static_cast<double>(current_air_gain_);

            // 4. All-pass matched recombination
            const SimdDouble2 lo = ap_lo_xhigh_.processAp(
                (SimdDouble2(g_sub) * b_sub) +
                (SimdDouble2(g_punch) * b_punch) +
                (SimdDouble2(g_ubass) * b_ubass));
            const SimdDouble2 up = ap_up_yhigh_.processAp(
                ap_up_ylow_.processAp(b_mid_raw + (SimdDouble2(g_air) * b_air_raw)));

            const SimdDouble2 v_out = lo + up;
            double out_l = v_out.get_low();
            double out_r = v_out.get_high();

            // 5. Anti-pop smooth crossfade on activation / deactivation
            if (anti_pop_ < 1.0f) {
                const double ap = static_cast<double>(anti_pop_);
                out_l = in_l + ap * (out_l - in_l);
                out_r = in_r + ap * (out_r - in_r);
            }

            interleaved_samples[2 * i]     = static_cast<T>(out_l);
            interleaved_samples[2 * i + 1] = static_cast<T>(out_r);
        }
    }

    void updatePresetParams() {
        size_t idx = static_cast<size_t>(preset_index_);
        if (idx >= kDynamicSystemPresets.size()) idx = 1;

        const auto& preset = kDynamicSystemPresets[idx];
        x_low_ = preset.x_low;
        x_high_ = preset.x_high;
        y_low_ = preset.y_low;
        y_high_ = preset.y_high;

        // At strength = 0.0f, all band gains are 1.0f (exact 0 dB unity all-pass identity)
        target_bass_gain_ = 1.0f + strength_ * (preset.max_drive - 1.0f);
        target_side_gain_x_ = preset.side_gain_x;
        target_side_gain_y_ = preset.side_gain_y;
        target_air_gain_ = 1.0f + strength_ * 0.15f;
    }

    void updateCoefficients() {
        const float yl = std::clamp(y_low_, 20.0f, 140.0f);
        const float yh = std::clamp(std::max(y_high_, yl + 15.0f), 35.0f, 300.0f);
        const float xl = std::clamp(std::max(x_low_, yh + 20.0f), 60.0f, 1500.0f);
        const float xh = std::clamp(std::max(x_high_, xl + 200.0f), 1500.0f, 16000.0f);

        target_y_low_ = yl;
        target_y_high_ = yh;
        target_x_low_ = xl;
        target_x_high_ = xh;
    }

    void applyCrossoverFrequencies() {
        cached_x_low_ = current_x_low_;
        cached_x_high_ = current_x_high_;
        cached_y_low_ = current_y_low_;
        cached_y_high_ = current_y_high_;

        const double fs = static_cast<double>(sample_rate_);
        const double yl = std::clamp(static_cast<double>(current_y_low_), 20.0, 140.0);
        const double yh = std::clamp(std::max(static_cast<double>(current_y_high_), yl + 15.0), 35.0, 300.0);
        const double xl = std::clamp(std::max(static_cast<double>(current_x_low_), yh + 20.0), 60.0, 1500.0);
        const double xh = std::clamp(std::max(static_cast<double>(current_x_high_), xl + 200.0), 1500.0, std::min(16000.0, fs * 0.45));

        split_ylow_.setFrequency(yl, fs);
        split_yhigh_.setFrequency(yh, fs);
        split_xlow_.setFrequency(xl, fs);
        split_xhigh_.setFrequency(xh, fs);

        ap_ubass_ylow_.setFrequency(yl, fs);
        ap_lo_xhigh_.setFrequency(xh, fs);
        ap_up_ylow_.setFrequency(yl, fs);
        ap_up_yhigh_.setFrequency(yh, fs);
    }

    bool enabled_ = false;
    bool initialized_ = false;
    TransducerProfile profile_ = TransducerProfile::Headphone;
    int preset_index_ = 1;
    float sample_rate_ = 48000.0f;
    float sample_period_ = 1.0f / 48000.0f;
    float strength_ = 0.5f;

    // Target and smoothed gains
    float target_bass_gain_ = 1.8f;
    float current_bass_gain_ = 1.8f;

    float target_side_gain_x_ = 0.10f;
    float current_side_gain_x_ = 0.10f;

    float target_side_gain_y_ = 0.50f;
    float current_side_gain_y_ = 0.50f;

    float target_air_gain_ = 1.075f;
    float current_air_gain_ = 1.075f;

    // Nominal & smoothed crossover frequencies
    float x_low_ = 300.0f;
    float x_high_ = 5600.0f;
    float y_low_ = 60.0f;
    float y_high_ = 105.0f;

    float target_x_low_ = 300.0f;
    float current_x_low_ = 300.0f;
    float cached_x_low_ = -1.0f;

    float target_x_high_ = 5600.0f;
    float current_x_high_ = 5600.0f;
    float cached_x_high_ = -1.0f;

    float target_y_low_ = 60.0f;
    float current_y_low_ = 60.0f;
    float cached_y_low_ = -1.0f;

    float target_y_high_ = 105.0f;
    float current_y_high_ = 105.0f;
    float cached_y_high_ = -1.0f;

    float smoothing_coeff_ = 0.00069f;
    float anti_pop_step_ = 1.0f / (0.015f * 48000.0f);
    float anti_pop_ = 0.0f;

    // 5-Band LR4 crossover tree + all-pass aligners (64-bit stereo SIMD)
    StereoLr4Split split_xlow_{};
    StereoLr4Split split_xhigh_{};
    StereoLr4Split split_ylow_{};
    StereoLr4Split split_yhigh_{};
    StereoTptSvf ap_ubass_ylow_{};
    StereoTptSvf ap_lo_xhigh_{};
    StereoTptSvf ap_up_ylow_{};
    StereoTptSvf ap_up_yhigh_{};
};

} // namespace sauti::dsp
