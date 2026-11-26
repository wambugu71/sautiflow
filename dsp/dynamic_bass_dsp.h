#pragma once

#include <cmath>
#include <cstdint>
#include <algorithm>
#include <vector>
#include <array>
#include <cstring>
#include "denormals.h"
#include "simd_math.h"
#include "cytomic_svf_dsp.h"

namespace sauti::dsp {

enum class BassEnhanceProfile {
    NaturalBass = 0,        // Natural Mono Bass: Butterworth Q=0.53 + 18Hz DC-block + dual-stage soft clipping
    PureBass = 1,           // Pure Bass+ Mono: 63-tap Linear-Phase SIMD FIR + time-aligned mono injection
    Subwoofer = 2,          // Subwoofer: Dual-stage Cytomic SVF peaking + differential lowpass
    HarmonicExciter = 3,    // Psychoacoustic Bass: DC-free Chebyshev 2f+3f synthesizer + post-LPF
    PultecDeep = 4,         // Pultec EQP-1A Low-End Trick: LowShelf boost + proportional mud scoop
    DynamicMultiPole = 5,   // Phase-Coherent LR4 Multi-Band Bass Matrix with 19 Hardware Tuning Presets

    // Backward-compatible aliases
    SubBassResonant = 0,
    PunchyBass = 1
};

// =============================================================================
// Acoustic Tuning Presets (for Mode 5: DynamicMultiPole)
// =============================================================================
struct DynamicBassPreset {
    const char* name;
    float x_low;
    float x_high;
    float y_low;
    float y_high;
    float side_gain_x;
    float side_gain_y;
};

inline constexpr std::array<DynamicBassPreset, 19> kDynamicBassPresets = {{
    { "Smooth Natural Sub",   140.0f, 6200.0f, 40.0f,  65.0f, 0.10f, 0.80f },
    { "Punchy In-Ear",        180.0f, 5800.0f, 55.0f,  85.0f, 0.10f, 0.70f },
    { "Warm Over-Ear",        300.0f, 5600.0f, 60.0f, 105.0f, 0.15f, 0.50f },
    { "Deep Acoustic",        260.0f, 5400.0f, 50.0f,  95.0f, 0.20f, 0.60f },
    { "Wide Dynamic",         280.0f, 5600.0f, 45.0f,  85.0f, 0.30f, 0.55f },
    { "Sub-Bass Boom",        240.0f, 6200.0f, 38.0f,  78.0f, 0.10f, 0.95f },
    { "Tight Sub",            240.0f, 6200.0f, 45.0f,  85.0f, 0.10f, 0.55f },
    { "Solid Impact",         280.0f, 6200.0f, 50.0f,  90.0f, 0.20f, 0.40f },
    { "Clean Kick",           250.0f, 6200.0f, 55.0f,  95.0f, 0.20f, 0.25f },
    { "Rich Low-End",         320.0f, 6200.0f, 50.0f,  95.0f, 0.25f, 0.60f },
    { "Club PA Punch",        320.0f, 6200.0f, 45.0f,  90.0f, 0.30f, 0.65f },
    { "Basshead Heavy",       280.0f, 6200.0f, 55.0f, 105.0f, 0.20f, 0.85f },
    { "Resonant Rumble",      260.0f, 6200.0f, 40.0f,  85.0f, 0.15f, 0.90f },
    { "Cinema Sub",           260.0f, 6200.0f, 45.0f,  90.0f, 0.10f, 0.85f },
    { "Car Audio Slam",       280.0f, 6200.0f, 40.0f,  85.0f, 0.15f, 0.80f },
    { "Audiophile Reference", 220.0f, 6200.0f, 45.0f,  85.0f, 0.10f, 0.65f },
    { "Studio Monitor Lows",  240.0f, 6200.0f, 50.0f,  95.0f, 0.10f, 0.55f },
    { "Deep Sub Extension",   220.0f, 6200.0f, 35.0f,  75.0f, 0.05f, 1.00f },
    { "Ultimate Subwoofer",   260.0f, 6200.0f, 45.0f,  95.0f, 0.10f, 0.90f }
}};

// =============================================================================
// HarmonicBassDSP: High-Fidelity Clean-Room Dynamic Bass & Subwoofer Suite
// =============================================================================
class HarmonicBassDSP {
public:
    HarmonicBassDSP() {
        setSampleRate(48000.0f);
        setProfile(BassEnhanceProfile::NaturalBass);
        setPreset(18); // Default to Ultimate Subwoofer preset
        reset();
    }

    void setSampleRate(float sampleRate) {
        if (sampleRate <= 0.0f) sampleRate = 48000.0f;
        if (initialized_ && std::abs(sample_rate_ - sampleRate) < 0.1f) return;
        sample_rate_ = sampleRate;
        sample_period_ = 1.0f / sample_rate_;
        anti_pop_step_ = 1.0f / (0.020f * sample_rate_); // 20ms smooth enable/disable ramp
        updateFilters();
        reset();
        initialized_ = true;
    }

    void setEnabled(bool enabled) {
        enabled_ = enabled;
    }

    bool isEnabled() const { return enabled_; }

    bool isActive() const { return enabled_ || anti_pop_ > 0.0f; }

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

    // Boost factor [0.0, 1.0]
    void setBoost(float boost) {
        boost_ = std::clamp(boost, 0.0f, 1.0f);
        gain_db_ = boost_ * 18.0f;
        bass_factor_ = boost_ * 3.5f;
        target_bass_gain_ = std::pow(10.0f, gain_db_ / 20.0f);
        updateFilters();
    }

    float getBoost() const { return boost_; }

    // Logarithmic gain in dB [0.0 .. 18.0 dB]
    void setGainDb(float gain_db) {
        gain_db_ = std::clamp(gain_db, 0.0f, 18.0f);
        boost_ = gain_db_ / 18.0f;
        bass_factor_ = boost_ * 3.5f;
        target_bass_gain_ = std::pow(10.0f, gain_db_ / 20.0f);
        updateFilters();
    }

    float getGainDb() const {
        return gain_db_;
    }

    // Set one of the 19 pre-tuned acoustic profiles (0..18)
    void setPreset(int preset_index) {
        preset_index = std::clamp(preset_index, 0, static_cast<int>(kDynamicBassPresets.size()) - 1);
        current_preset_ = preset_index;
        const auto& p = kDynamicBassPresets[static_cast<size_t>(preset_index)];
        x_low_ = p.x_low;
        x_high_ = p.x_high;
        y_low_ = p.y_low;
        y_high_ = p.y_high;
        target_side_gain_x_ = p.side_gain_x;
        target_side_gain_y_ = p.side_gain_y;
        updateFilters();
    }

    int getPreset() const { return current_preset_; }

    static const char* getPresetName(int preset_index) {
        if (preset_index < 0 || preset_index >= static_cast<int>(kDynamicBassPresets.size())) {
            return "Unknown Preset";
        }
        return kDynamicBassPresets[static_cast<size_t>(preset_index)].name;
    }

    void setAntiPop(bool enable) {
        anti_pop_enabled_ = enable;
        if (!enable) anti_pop_ = 1.0f;
    }

    bool isAntiPopEnabled() const { return anti_pop_enabled_; }

    void setMonoMode(bool mono) {
        if (mono_mode_ != mono) {
            mono_mode_ = mono;
            updateFilters();
        }
    }

    bool isMonoMode() const { return mono_mode_; }

    void reset() {
        anti_pop_ = anti_pop_enabled_ ? 0.0f : 1.0f;
        bass_factor_smoothed_ = bass_factor_;
        current_boost_ = boost_;
        cached_boost_ = -1.0f;
        current_bass_gain_ = target_bass_gain_;
        current_side_gain_x_ = target_side_gain_x_;
        current_side_gain_y_ = target_side_gain_y_;
        current_x_low_ = target_x_low_;
        current_y_low_ = target_y_low_;
        current_y_high_ = target_y_high_;
        cached_x_low_ = -1.0f;
        cached_y_low_ = -1.0f;
        cached_y_high_ = -1.0f;

        smoothing_coeff_ = 1.0f - std::exp(-1.0f / (0.030f * sample_rate_)); // 30ms smoothing
        anti_pop_step_ = 1.0f / (0.020f * sample_rate_);

        // 18 Hz DC blocker coefficient
        constexpr double PI = 3.14159265358979323846;
        dc_block_coeff_ = static_cast<float>(std::exp(-2.0 * PI * 18.0 / static_cast<double>(sample_rate_)));
        dc_x1_[0] = dc_x1_[1] = 0.0;
        dc_y1_[0] = dc_y1_[1] = 0.0;

        // Reset Natural / Pure Bass Direct Form I Biquad
        mono_lp_biquad_.reset();
        biquad_stereo_[0].reset();
        biquad_stereo_[1].reset();

        // Reset Polyphase FIR history buffers and delay line
        fir_head_ = 0;
        for (auto& v : fir_hist_) v = SimdDouble2(0.0);

        bass_delay_head_ = 0;
        std::memset(bass_delay_ring_, 0, sizeof(bass_delay_ring_));

        // Reset Subwoofer SVFs
        sub_peak_.reset();
        sub_peak_low_.reset();
        sub_lowpass_.reset();
        recalcSubwooferFilters();

        // Reset Harmonic Exciter states
        harm_envelope_ = 1e-10;
        t2_dc_l_ = 0.0;
        t2_dc_r_ = 0.0;
        harm_lp_l_.reset();
        harm_lp_r_.reset();
        harm_hp_l_.reset();
        harm_hp_r_.reset();
        harm_post_lp_l_.reset();
        harm_post_lp_r_.reset();

        // Reset Pultec filter states
        pultec_boost_svf_.reset();
        pultec_scoop_svf_.reset();
        recalcPultecFilters();

        // Reset Multi-Pole LR4 crossovers
        split_xlow_.reset();
        split_ylow_.reset();
        split_yhigh_.reset();
        ap_ubass_ylow_.reset();
        ap_up_ylow_.reset();
        ap_up_yhigh_.reset();
        applyMultiPoleFrequencies();
    }

    // Process interleaved stereo samples: [L0, R0, L1, R1, ...]
    void process(float* samples, uint32_t frame_count) {
        processImpl(samples, frame_count);
    }

    // Process interleaved stereo 64-bit double samples: [L0, R0, L1, R1, ...]
    void process(double* samples, uint32_t frame_count) {
        processImpl(samples, frame_count);
    }

private:
    template <typename T>
    void processImpl(T* samples, uint32_t frame_count) {
        if ((!enabled_ && anti_pop_ <= 0.0f) || frame_count == 0 || !samples) return;

        ScopedDenormalsDisable denormals;

        switch (profile_) {
            case BassEnhanceProfile::NaturalBass:
                processNaturalBass(samples, frame_count);
                break;
            case BassEnhanceProfile::PureBass:
                processPureBassPlus(samples, frame_count);
                break;
            case BassEnhanceProfile::Subwoofer:
                processSubwoofer(samples, frame_count);
                break;
            case BassEnhanceProfile::HarmonicExciter:
                processHarmonicExciter(samples, frame_count);
                break;
            case BassEnhanceProfile::PultecDeep:
                processPultecDeep(samples, frame_count);
                break;
            case BassEnhanceProfile::DynamicMultiPole:
                processDynamicMultiPole(samples, frame_count);
                break;
        }
    }

    // =========================================================================
    // Direct Form I Biquad Implementation
    // =========================================================================
    struct BiquadDirectFormI {
        double a1_ = 0.0, a2_ = 0.0;
        double b0_ = 1.0, b1_ = 0.0, b2_ = 0.0;
        double x1_ = 0.0, x2_ = 0.0, y1_ = 0.0, y2_ = 0.0;

        void reset() {
            x1_ = x2_ = y1_ = y2_ = 0.0;
        }

        inline double process(double sample) {
            double out = sample * b0_ + x1_ * b1_ + x2_ * b2_ + y1_ * a1_ + y2_ * a2_;
            x2_ = x1_;
            x1_ = sample;
            y2_ = y1_;
            y1_ = out;
            return out;
        }

        void setCoeffs(double a0, double a1, double a2, double b0, double b1, double b2) {
            a1_ = -(a1 / a0);
            a2_ = -(a2 / a0);
            b0_ = b0 / a0;
            b1_ = b1 / a0;
            b2_ = b2 / a0;
        }

        void setLowPass(float frequency, float sampling_rate, float q_factor = 0.53f) {
            constexpr double PI = 3.14159265358979323846;
            const double omega = 2.0 * PI * static_cast<double>(frequency) / static_cast<double>(sampling_rate);
            const double sin_omega = std::sin(omega);
            const double cos_omega = std::cos(omega);

            const double alpha = sin_omega / (static_cast<double>(q_factor) + static_cast<double>(q_factor));
            const double a0 = alpha + 1.0;
            const double a1 = cos_omega * -2.0;
            const double a2 = 1.0 - alpha;
            const double b0 = (1.0 - cos_omega) / 2.0;
            const double b1 = 1.0 - cos_omega;
            const double b2 = (1.0 - cos_omega) / 2.0;

            setCoeffs(a0, a1, a2, b0, b1, b2);
        }

        void setHighPass(float frequency, float sampling_rate, float q_factor = 0.7071f) {
            constexpr double PI = 3.14159265358979323846;
            const double omega = 2.0 * PI * static_cast<double>(frequency) / static_cast<double>(sampling_rate);
            const double sin_omega = std::sin(omega);
            const double cos_omega = std::cos(omega);

            const double alpha = sin_omega / (static_cast<double>(q_factor) + static_cast<double>(q_factor));
            const double a0 = alpha + 1.0;
            const double a1 = cos_omega * -2.0;
            const double a2 = 1.0 - alpha;
            const double b0 = (1.0 + cos_omega) / 2.0;
            const double b1 = -(1.0 + cos_omega);
            const double b2 = (1.0 + cos_omega) / 2.0;

            setCoeffs(a0, a1, a2, b0, b1, b2);
        }
    };

    // =========================================================================
    // Stereo 64-bit TPT SVF + LR4 Crossover Helpers (for Mode 5)
    // =========================================================================
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

    bool enabled_ = false;
    bool initialized_ = false;
    BassEnhanceProfile profile_ = BassEnhanceProfile::NaturalBass;
    int current_preset_ = 18;
    float sample_rate_ = 48000.0f;
    float sample_period_ = 1.0f / 48000.0f;
    float cutoff_hz_ = 60.0f;
    float boost_ = 0.5f;
    float gain_db_ = 9.0f;
    bool anti_pop_enabled_ = true;
    bool mono_mode_ = true;

    // Gain smoothing and Anti-Pop
    float anti_pop_ = 0.0f;
    float anti_pop_step_ = 1.0f / (0.020f * 48000.0f);
    float bass_factor_ = 1.75f;
    float bass_factor_smoothed_ = 1.75f;
    float current_boost_ = 0.5f;
    float cached_boost_ = -1.0f;
    float smoothing_coeff_ = 0.001f;

    // 18 Hz DC Blocker states (Stereo, 64-bit)
    float dc_block_coeff_ = 0.997f;
    double dc_x1_[2] = {0.0, 0.0};
    double dc_y1_[2] = {0.0, 0.0};

    // Direct Form I Butterworth Biquads (Natural & Pure Bass)
    BiquadDirectFormI mono_lp_biquad_;
    BiquadDirectFormI biquad_stereo_[2];

    // Polyphase 63-Tap FIR Filter States (Pure Bass+, 64-bit Stereo SIMD)
    SimdDouble2 fir_hist_[126]{};
    size_t fir_head_ = 0;
    double polyphase_kernel_[64] = {0.0};

    // 31-Sample Latency Compensation Delay Line (Pure Bass+, 64-bit)
    double bass_delay_ring_[63] = {0.0};
    size_t bass_delay_head_ = 0;

    // Subwoofer 64-bit Cytomic SVFs (zero-zipper)
    CytomicSVF sub_peak_;
    CytomicSVF sub_peak_low_;
    CytomicSVF sub_lowpass_;

    // Psychoacoustic Bass States
    double harm_envelope_ = 1e-10;
    double harm_attack_coeff_ = 0.01;
    double harm_release_coeff_ = 0.0001;
    double t2_dc_coeff_ = 0.002;
    double t2_dc_l_ = 0.0;
    double t2_dc_r_ = 0.0;
    BiquadDirectFormI harm_lp_l_, harm_lp_r_;
    BiquadDirectFormI harm_hp_l_, harm_hp_r_;
    BiquadDirectFormI harm_post_lp_l_, harm_post_lp_r_;

    // Pultec Low-End Trick 64-bit Cytomic SVF Stages
    CytomicSVF pultec_boost_svf_;
    CytomicSVF pultec_scoop_svf_;

    // Multi-Pole LR4 Bass Matrix Parameters
    float x_low_ = 260.0f;
    float x_high_ = 6200.0f;
    float y_low_ = 45.0f;
    float y_high_ = 95.0f;
    float target_side_gain_x_ = 0.10f;
    float current_side_gain_x_ = 0.10f;
    float target_side_gain_y_ = 0.90f;
    float current_side_gain_y_ = 0.90f;
    float target_bass_gain_ = 2.818f;
    float current_bass_gain_ = 2.818f;

    float target_x_low_ = 260.0f;
    float current_x_low_ = 260.0f;
    float cached_x_low_ = -1.0f;
    float target_y_low_ = 45.0f;
    float current_y_low_ = 45.0f;
    float cached_y_low_ = -1.0f;
    float target_y_high_ = 95.0f;
    float current_y_high_ = 95.0f;
    float cached_y_high_ = -1.0f;

    StereoLr4Split split_xlow_{};
    StereoLr4Split split_ylow_{};
    StereoLr4Split split_yhigh_{};
    StereoTptSvf ap_ubass_ylow_{};
    StereoTptSvf ap_up_ylow_{};
    StereoTptSvf ap_up_yhigh_{};

    inline void stepAntiPop() {
        if (!anti_pop_enabled_) {
            anti_pop_ = enabled_ ? 1.0f : 0.0f;
            return;
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
    }

    // =========================================================================
    // Rational Algebraic Soft-Clipper with Knee (clean, warm, zero harsh harmonics)
    // =========================================================================
    static inline double softClip(const double v, const double knee) {
        const double drive = std::fabs(v);
        if (drive <= knee) return v;
        const double over = drive - knee;
        const double shaped = knee + over / std::sqrt(1.0 + over * over);
        return v * (shaped / drive);
    }

    // =========================================================================
    // 18 Hz DC Blocker & Dual-Stage Soft Clip Mix
    // =========================================================================
    template <typename T>
    inline void shapeMix(double bass, T* samples, const uint32_t i) {
        const double y = static_cast<double>(dc_block_coeff_) * (dc_y1_[0] + bass - dc_x1_[0]);
        dc_x1_[0] = bass;
        dc_y1_[0] = y;

        bass = softClip(y, 0.8);

        samples[2 * i]     = static_cast<T>(static_cast<double>(samples[2 * i]) + bass);
        samples[2 * i + 1] = static_cast<T>(static_cast<double>(samples[2 * i + 1]) + bass);
    }

    template <typename T>
    inline void shapeMixStereo(double bass_l, double bass_r, T* samples, const uint32_t i) {
        const double dc_c = static_cast<double>(dc_block_coeff_);
        const double y_l = dc_c * (dc_y1_[0] + bass_l - dc_x1_[0]);
        dc_x1_[0] = bass_l;
        dc_y1_[0] = y_l;

        const double y_r = dc_c * (dc_y1_[1] + bass_r - dc_x1_[1]);
        dc_x1_[1] = bass_r;
        dc_y1_[1] = y_r;

        bass_l = softClip(y_l, 0.8);
        bass_r = softClip(y_r, 0.8);

        samples[2 * i]     = static_cast<T>(static_cast<double>(samples[2 * i]) + bass_l);
        samples[2 * i + 1] = static_cast<T>(static_cast<double>(samples[2 * i + 1]) + bass_r);
    }

    // =========================================================================
    // Mode 0: Natural Mono Bass (Mono Butterworth Q=0.53 + Soft Clip Injection)
    // =========================================================================
    template <typename T>
    void processNaturalBass(T* samples, uint32_t frame_count) {
        for (uint32_t i = 0; i < frame_count; i++) {
            bass_factor_smoothed_ += (bass_factor_ - bass_factor_smoothed_) * smoothing_coeff_;
            stepAntiPop();

            if (mono_mode_) {
                const double mono_in = (static_cast<double>(samples[2 * i]) +
                                        static_cast<double>(samples[2 * i + 1])) * 0.5;
                double bass = mono_lp_biquad_.process(mono_in) * static_cast<double>(bass_factor_smoothed_);
                bass *= static_cast<double>(anti_pop_);
                shapeMix(bass, samples, i);
            } else {
                double bass_l = biquad_stereo_[0].process(static_cast<double>(samples[2 * i])) * static_cast<double>(bass_factor_smoothed_);
                double bass_r = biquad_stereo_[1].process(static_cast<double>(samples[2 * i + 1])) * static_cast<double>(bass_factor_smoothed_);
                const double ap = static_cast<double>(anti_pop_);
                bass_l *= ap;
                bass_r *= ap;
                shapeMixStereo(bass_l, bass_r, samples, i);
            }
        }
    }

    // =========================================================================
    // Mode 1: Pure Bass+ Mono (63-Tap Stereo SIMD Polyphase FIR + Aligned Bass)
    // =========================================================================
    template <typename T>
    void processPureBassPlus(T* samples, uint32_t frame_count) {
        for (uint32_t i = 0; i < frame_count; i++) {
            const double in_l = static_cast<double>(samples[2 * i]);
            const double in_r = static_cast<double>(samples[2 * i + 1]);

            // 1. Mono summation and lowpass extraction
            const double mono_in = (in_l + in_r) * 0.5;
            const double lp_bass = mono_lp_biquad_.process(mono_in);

            // 2. Push lowpass bass into delay line and tap at constant 31-sample group delay
            bass_delay_ring_[bass_delay_head_] = lp_bass;
            const size_t delayed_idx = (bass_delay_head_ + 32) % 63;
            const double delayed_bass = bass_delay_ring_[delayed_idx];
            bass_delay_head_ = (bass_delay_head_ + 1) % 63;

            // 3. Vectorized Stereo 63-tap FIR convolution (SimdDouble2)
            fir_head_ = (fir_head_ == 0) ? 62 : (fir_head_ - 1);
            const SimdDouble2 vin(in_l, in_r);
            fir_hist_[fir_head_] = vin;
            fir_hist_[fir_head_ + 63] = vin;

            SimdDouble2 fir_acc(0.0);
            for (size_t j = 0; j < 63; ++j) {
                fir_acc += SimdDouble2(polyphase_kernel_[j]) * fir_hist_[fir_head_ + j];
            }

            samples[2 * i]     = static_cast<T>(fir_acc.get_low());
            samples[2 * i + 1] = static_cast<T>(fir_acc.get_high());

            // 4. Smooth gain and inject time-aligned mono bass
            bass_factor_smoothed_ += (bass_factor_ - bass_factor_smoothed_) * smoothing_coeff_;
            stepAntiPop();
            const double driven_bass = delayed_bass * static_cast<double>(bass_factor_smoothed_) * static_cast<double>(anti_pop_);

            shapeMix(driven_bass, samples, i);
        }
    }

    // =========================================================================
    // Mode 2: Subwoofer (Smoothed Cytomic SVF Dual Peak + Differential LPF)
    // =========================================================================
    template <typename T>
    void processSubwoofer(T* samples, uint32_t frame_count) {
        for (uint32_t i = 0; i < frame_count; i++) {
            current_boost_ += smoothing_coeff_ * (boost_ - current_boost_);
            if ((i & 31) == 0 && std::abs(current_boost_ - cached_boost_) > 0.002f) {
                recalcSubwooferFilters();
            }
            stepAntiPop();

            const double in_l = static_cast<double>(samples[2 * i]);
            const double in_r = static_cast<double>(samples[2 * i + 1]);

            double tmp_l = sub_peak_.processSample(in_l, 0);
            tmp_l = sub_peak_low_.processSample(tmp_l, 0);
            tmp_l = sub_lowpass_.processSample(tmp_l - in_l, 0);

            double tmp_r = sub_peak_.processSample(in_r, 1);
            tmp_r = sub_peak_low_.processSample(tmp_r, 1);
            tmp_r = sub_lowpass_.processSample(tmp_r - in_r, 1);

            const double ap = static_cast<double>(anti_pop_);
            if (mono_mode_) {
                const double sub_mono = ((tmp_l + tmp_r) * 0.5) * 0.6 * ap;
                shapeMix(sub_mono, samples, i);
            } else {
                const double sub_l = tmp_l * 0.6 * ap;
                const double sub_r = tmp_r * 0.6 * ap;
                shapeMixStereo(sub_l, sub_r, samples, i);
            }
        }
    }

    // =========================================================================
    // Mode 3: Psychoacoustic Bass (DC-Free Envelope-Tracked Chebyshev 2f+3f)
    // =========================================================================
    template <typename T>
    void processHarmonicExciter(T* samples, uint32_t frame_count) {
        for (uint32_t i = 0; i < frame_count; i++) {
            current_boost_ += smoothing_coeff_ * (boost_ - current_boost_);
            stepAntiPop();
            const double intensity = static_cast<double>(current_boost_) * 0.85 * static_cast<double>(anti_pop_);

            const double in_l = static_cast<double>(samples[2 * i]);
            const double in_r = static_cast<double>(samples[2 * i + 1]);

            // 1. Extract fundamental sub-bass
            const double bass_l = harm_lp_l_.process(in_l);
            const double bass_r = harm_lp_r_.process(in_r);

            // 2. Dynamic Envelope Follower
            const double abs_l = std::fabs(bass_l);
            const double abs_r = std::fabs(bass_r);
            const double peak = (abs_l > abs_r) ? abs_l : abs_r;

            if (peak > harm_envelope_) {
                harm_envelope_ += harm_attack_coeff_ * (peak - harm_envelope_);
            } else {
                harm_envelope_ += harm_release_coeff_ * (peak - harm_envelope_);
            }
            if (harm_envelope_ < 1e-10) harm_envelope_ = 1e-10;

            // 3. Normalize into Chebyshev range [-1, 1]
            const double norm_l = std::clamp(bass_l / harm_envelope_, -1.0, 1.0);
            const double norm_r = std::clamp(bass_r / harm_envelope_, -1.0, 1.0);

            // 4. DC-free 2nd (x^2 - DC_avg(x^2)) and 3rd (4x^3 - 3x) Order Harmonics
            const double x2_l = norm_l * norm_l;
            t2_dc_l_ += t2_dc_coeff_ * (x2_l - t2_dc_l_);
            const double t2_l = 2.0 * (x2_l - t2_dc_l_);
            const double t3_l = 4.0 * norm_l * x2_l - 3.0 * norm_l;

            const double x2_r = norm_r * norm_r;
            t2_dc_r_ += t2_dc_coeff_ * (x2_r - t2_dc_r_);
            const double t2_r = 2.0 * (x2_r - t2_dc_r_);
            const double t3_r = 4.0 * norm_r * x2_r - 3.0 * norm_r;

            double h_l = (0.7 * t2_l + 0.3 * t3_l) * harm_envelope_;
            double h_r = (0.7 * t2_r + 0.3 * t3_r) * harm_envelope_;

            // 5. Band-limit harmonics: HPF above cutoff + Post-LPF to suppress vocal-band buzz
            h_l = harm_post_lp_l_.process(harm_hp_l_.process(h_l));
            h_r = harm_post_lp_r_.process(harm_hp_r_.process(h_r));

            if (mono_mode_) {
                const double mono_harm = ((h_l + h_r) * 0.5) * intensity;
                shapeMix(mono_harm, samples, i);
            } else {
                shapeMixStereo(h_l * intensity, h_r * intensity, samples, i);
            }
        }
    }

    // =========================================================================
    // Mode 4: Pultec EQP-1A Low-End Trick (Smoothed 64-bit Cytomic SVF)
    // =========================================================================
    template <typename T>
    void processPultecDeep(T* samples, uint32_t frame_count) {
        for (uint32_t i = 0; i < frame_count; i++) {
            current_boost_ += smoothing_coeff_ * (boost_ - current_boost_);
            if ((i & 31) == 0 && std::abs(current_boost_ - cached_boost_) > 0.002f) {
                recalcPultecFilters();
            }
            stepAntiPop();

            const double in_l = static_cast<double>(samples[2 * i]);
            const double in_r = static_cast<double>(samples[2 * i + 1]);
            const double ap = static_cast<double>(anti_pop_);

            // 1. Stereo Mud Scoop Bell Filter
            const double s_out_l = pultec_scoop_svf_.processSample(in_l, 0);
            const double s_out_r = pultec_scoop_svf_.processSample(in_r, 1);

            samples[2 * i]     = static_cast<T>(in_l + ap * (s_out_l - in_l));
            samples[2 * i + 1] = static_cast<T>(in_r + ap * (s_out_r - in_r));

            // 2. Low-Shelf Sub Boost (mono or stereo)
            if (mono_mode_) {
                const double mono_in = (in_l + in_r) * 0.5;
                const double b_out = pultec_boost_svf_.processSample(mono_in, 0);
                const double mono_bass = (b_out - mono_in) * 0.8 * ap;
                shapeMix(mono_bass, samples, i);
            } else {
                const double b_l = pultec_boost_svf_.processSample(in_l, 0);
                const double b_r = pultec_boost_svf_.processSample(in_r, 1);
                shapeMixStereo((b_l - in_l) * 0.8 * ap, (b_r - in_r) * 0.8 * ap, samples, i);
            }
        }
    }

    // =========================================================================
    // Mode 5: Dynamic Multi-Pole Resonator (Phase-Coherent Stereo LR4 Matrix)
    // =========================================================================
    template <typename T>
    void processDynamicMultiPole(T* samples, uint32_t frame_count) {
        for (uint32_t i = 0; i < frame_count; i++) {
            current_bass_gain_   += smoothing_coeff_ * (target_bass_gain_ - current_bass_gain_);
            current_side_gain_x_ += smoothing_coeff_ * (target_side_gain_x_ - current_side_gain_x_);
            current_side_gain_y_ += smoothing_coeff_ * (target_side_gain_y_ - current_side_gain_y_);
            current_x_low_       += smoothing_coeff_ * (target_x_low_ - current_x_low_);
            current_y_low_       += smoothing_coeff_ * (target_y_low_ - current_y_low_);
            current_y_high_      += smoothing_coeff_ * (target_y_high_ - current_y_high_);

            if ((i & 31) == 0) {
                if (std::abs(current_x_low_ - cached_x_low_) > 0.25f ||
                    std::abs(current_y_low_ - cached_y_low_) > 0.25f ||
                    std::abs(current_y_high_ - cached_y_high_) > 0.25f) {
                    applyMultiPoleFrequencies();
                }
            }
            stepAntiPop();

            const double in_l = static_cast<double>(samples[2 * i]);
            const double in_r = static_cast<double>(samples[2 * i + 1]);
            const SimdDouble2 vin(in_l, in_r);

            SimdDouble2 x_lo, x_hi;
            split_xlow_.process(vin, x_lo, x_hi);

            SimdDouble2 y_lm, b_ubass_raw;
            split_yhigh_.process(x_lo, y_lm, b_ubass_raw);

            SimdDouble2 b_sub, b_punch;
            split_ylow_.process(y_lm, b_sub, b_punch);
            const SimdDouble2 b_ubass = ap_ubass_ylow_.processAp(b_ubass_raw);

            // Band gains: exact 1.0 unity identity at 0 dB gain
            const double drive = std::max(0.0, static_cast<double>(current_bass_gain_) - 1.0);
            const double g_sub = 1.0 + drive * (0.30 + 0.70 * static_cast<double>(current_side_gain_y_));
            const double g_punch = 1.0 + drive;
            const double g_ubass = 1.0 + drive * (0.40 * static_cast<double>(current_side_gain_x_));

            const SimdDouble2 lo = (SimdDouble2(g_sub) * b_sub) +
                                   (SimdDouble2(g_punch) * b_punch) +
                                   (SimdDouble2(g_ubass) * b_ubass);
            const SimdDouble2 up = ap_up_yhigh_.processAp(ap_up_ylow_.processAp(x_hi));
            const SimdDouble2 v_out = lo + up;

            double out_l = v_out.get_low();
            double out_r = v_out.get_high();

            if (anti_pop_ < 1.0f) {
                const double ap = static_cast<double>(anti_pop_);
                out_l = in_l + ap * (out_l - in_l);
                out_r = in_r + ap * (out_r - in_r);
            }

            samples[2 * i]     = static_cast<T>(out_l);
            samples[2 * i + 1] = static_cast<T>(out_r);
        }
    }

    void recalcSubwooferFilters() {
        cached_boost_ = current_boost_;
        const double sub_fc1 = static_cast<double>(cutoff_hz_);
        const double sub_fc2 = std::clamp(sub_fc1 * 1.8, 60.0, 180.0);
        const double gain_db = static_cast<double>(current_boost_) * 16.0;
        const double gain_upper_db = static_cast<double>(current_boost_) * 8.0;

        sub_peak_.setParameters(CytomicSVF::FilterType::Bell, sample_rate_, sub_fc1, gain_db, 0.95);
        sub_peak_low_.setParameters(CytomicSVF::FilterType::Bell, sample_rate_, sub_fc2, gain_upper_db, 1.4);

        const double sub_lp_fc = mono_mode_ ? 380.0 : 120.0;
        sub_lowpass_.setParameters(CytomicSVF::FilterType::LowPass, sample_rate_, sub_lp_fc, 0.0, 0.65);
    }

    void recalcPultecFilters() {
        cached_boost_ = current_boost_;
        const double pultec_boost_db = static_cast<double>(current_boost_) * 12.0;
        pultec_boost_svf_.setParameters(CytomicSVF::FilterType::LowShelf, sample_rate_,
                                        static_cast<double>(cutoff_hz_), pultec_boost_db, 0.70710678);

        const double scoop_fc = std::clamp(static_cast<double>(cutoff_hz_) * 5.0, 200.0, 400.0);
        const double pultec_scoop_db = -static_cast<double>(current_boost_) * 4.5;
        pultec_scoop_svf_.setParameters(CytomicSVF::FilterType::Bell, sample_rate_,
                                        scoop_fc, pultec_scoop_db, 1.2);
    }

    void applyMultiPoleFrequencies() {
        cached_x_low_ = current_x_low_;
        cached_y_low_ = current_y_low_;
        cached_y_high_ = current_y_high_;

        const double fs = static_cast<double>(sample_rate_);
        const double yl = std::clamp(static_cast<double>(current_y_low_), 20.0, 140.0);
        const double yh = std::clamp(std::max(static_cast<double>(current_y_high_), yl + 15.0), 35.0, 300.0);
        const double xl = std::clamp(std::max(static_cast<double>(current_x_low_), yh + 20.0), 60.0, 1500.0);

        split_ylow_.setFrequency(yl, fs);
        split_yhigh_.setFrequency(yh, fs);
        split_xlow_.setFrequency(xl, fs);

        ap_ubass_ylow_.setFrequency(yl, fs);
        ap_up_ylow_.setFrequency(yl, fs);
        ap_up_yhigh_.setFrequency(yh, fs);
    }

    void updateFilters() {
        // 1. Natural & Pure Bass Low-Pass Filter (Butterworth Q = 0.53 critically damped)
        mono_lp_biquad_.setLowPass(cutoff_hz_, sample_rate_, 0.53f);
        biquad_stereo_[0].setLowPass(cutoff_hz_, sample_rate_, 0.53f);
        biquad_stereo_[1].setLowPass(cutoff_hz_, sample_rate_, 0.53f);
        buildPolyphaseKernel();

        // 2. Subwoofer SVFs
        recalcSubwooferFilters();

        // 3. Psychoacoustic Bass Filters (full 30-160 Hz range + post-waveshaper LPF)
        const float harm_cutoff = std::clamp(cutoff_hz_, 30.0f, 160.0f);
        const float post_lp_fc = std::clamp(harm_cutoff * 3.5f, 160.0f, 380.0f);
        harm_lp_l_.setLowPass(harm_cutoff, sample_rate_, 0.7071f);
        harm_lp_r_.setLowPass(harm_cutoff, sample_rate_, 0.7071f);
        harm_hp_l_.setHighPass(harm_cutoff, sample_rate_, 0.7071f);
        harm_hp_r_.setHighPass(harm_cutoff, sample_rate_, 0.7071f);
        harm_post_lp_l_.setLowPass(post_lp_fc, sample_rate_, 0.7071f);
        harm_post_lp_r_.setLowPass(post_lp_fc, sample_rate_, 0.7071f);

        // Envelope follower ballistics & 15 Hz T2 DC tracker
        harm_attack_coeff_ = 1.0 - std::exp(-1.0 / (static_cast<double>(sample_rate_) * 0.00208333));
        harm_release_coeff_ = 1.0 - std::exp(-1.0 / (static_cast<double>(sample_rate_) * 0.208333));
        constexpr double kPi = 3.14159265358979323846;
        t2_dc_coeff_ = 1.0 - std::exp(-2.0 * kPi * 15.0 / static_cast<double>(sample_rate_));

        // 4. Pultec EQP-1A SVFs
        recalcPultecFilters();

        // 5. Dynamic Multi-Pole LR4 target frequencies
        const float yl = std::clamp(y_low_, 20.0f, 140.0f);
        const float yh = std::clamp(std::max(y_high_, yl + 15.0f), 35.0f, 300.0f);
        const float xl = std::clamp(std::max(x_low_, yh + 20.0f), 60.0f, 1500.0f);
        target_y_low_ = yl;
        target_y_high_ = yh;
        target_x_low_ = xl;
    }

    // =========================================================================
    // Runtime-designed 63-tap linear-phase FIR for Pure Bass+ mode.
    // Blackman-windowed sinc, normalized to unity DC gain and symmetric about
    // the center tap (constant 31-sample group delay).
    // =========================================================================
    void buildPolyphaseKernel() {
        constexpr int N = 63;
        constexpr int M = N / 2;
        constexpr double kPi = 3.14159265358979323846;
        const double fc = 0.492;

        double sum = 0.0;
        for (int n = 0; n < N; ++n) {
            const double x = static_cast<double>(n - M);
            double v;
            if (std::fabs(x) < 1e-9) {
                v = 2.0 * fc;
            } else {
                v = std::sin(2.0 * kPi * fc * x) / (kPi * x);
            }
            const double w = 0.42
                - 0.5 * std::cos(2.0 * kPi * static_cast<double>(n) / static_cast<double>(N - 1))
                + 0.08 * std::cos(4.0 * kPi * static_cast<double>(n) / static_cast<double>(N - 1));
            v *= w;
            polyphase_kernel_[static_cast<size_t>(n)] = v;
            sum += v;
        }

        if (sum > 1e-9) {
            const double inv = 1.0 / sum;
            for (int n = 0; n < N; ++n) {
                polyphase_kernel_[static_cast<size_t>(n)] *= inv;
            }
        } else {
            std::memset(polyphase_kernel_, 0, sizeof(polyphase_kernel_));
            polyphase_kernel_[M] = 1.0;
        }
    }
};

} // namespace sauti::dsp
