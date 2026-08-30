#pragma once

#include <cmath>
#include <cstdint>
#include <algorithm>
#include <vector>
#include <array>
#include <cstring>

namespace sauti::dsp {

enum class BassEnhanceProfile {
    NaturalBass = 0,        // Natural Mono Bass: Butterworth Q=0.53 + 18Hz DC-block + dual-stage soft clipping
    PureBass = 1,           // Pure Bass+ Mono: 63-tap Polyphase FIR + phase-aligned delay-line mono injection
    Subwoofer = 2,          // Subwoofer Mono: Dual-stage 44Hz/80Hz bandwidth peaking + 380Hz diff lowpass
    HarmonicExciter = 3,    // Psychoacoustic Bass: Envelope-tracked Chebyshev harmonic synthesizer (2f + 3f)
    PultecDeep = 4,         // Pultec EQP-1A Low-End Trick: Deep 45 Hz mono boost + 300 Hz mud scoop
    DynamicMultiPole = 5,   // 4-Pole Cascaded Multi-Band Ladder Resonator with 19 Hardware Tuning Presets

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
    { "Smooth Natural Sub",   140.0f,  6200.0f, 40.0f, 60.0f,  0.10f, 0.80f },
    { "Punchy In-Ear",        180.0f,  5800.0f, 55.0f, 80.0f,  0.10f, 0.70f },
    { "Warm Over-Ear",        300.0f,  5600.0f, 60.0f, 105.0f, 0.10f, 0.50f },
    { "Deep Acoustic",        600.0f,  5400.0f, 60.0f, 105.0f, 0.10f, 0.20f },
    { "Wide Dynamic",         100.0f,  5600.0f, 40.0f, 80.0f,  0.50f, 0.50f },
    { "Sub-Bass Boom",        1200.0f, 6200.0f, 40.0f, 80.0f,  0.00f, 0.20f },
    { "Tight Sub",            1000.0f, 6200.0f, 40.0f, 80.0f,  0.00f, 0.10f },
    { "Solid Impact",         800.0f,  6200.0f, 40.0f, 80.0f,  0.10f, 0.00f },
    { "Clean Kick",           400.0f,  6200.0f, 40.0f, 80.0f,  0.10f, 0.00f },
    { "Rich Low-End",         1200.0f, 6200.0f, 50.0f, 90.0f,  0.15f, 0.10f },
    { "Club PA Punch",        1000.0f, 6200.0f, 50.0f, 90.0f,  0.30f, 0.10f },
    { "Basshead Heavy",       1100.0f, 6200.0f, 60.0f, 100.0f, 0.20f, 0.00f },
    { "Resonant Rumble",      1200.0f, 6200.0f, 50.0f, 100.0f, 0.10f, 0.50f },
    { "Cinema Sub",           1200.0f, 6200.0f, 60.0f, 100.0f, 0.00f, 0.30f },
    { "Car Audio Slam",       1200.0f, 6200.0f, 40.0f, 80.0f,  0.00f, 0.30f },
    { "Audiophile Reference", 1000.0f, 6200.0f, 60.0f, 100.0f, 0.00f, 0.00f },
    { "Studio Monitor Lows",  1000.0f, 6200.0f, 60.0f, 120.0f, 0.00f, 0.00f },
    { "Deep Sub Extension",   1000.0f, 6200.0f, 80.0f, 140.0f, 0.00f, 0.00f },
    { "Ultimate Subwoofer",   800.0f,  6200.0f, 80.0f, 140.0f, 0.00f, 0.00f }
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
        // Linear scale matching dynamic bass multiplier [0.0 .. 3.5x]
        bass_factor_ = boost_ * 3.5f;
        target_bass_gain_ = 1.0f + boost_ * 4.0f;
        updateFilters();
    }

    float getBoost() const { return boost_; }

    // Gain in dB [0.0 .. 24.0 dB]
    void setGainDb(float gain_db) {
        gain_db = std::clamp(gain_db, 0.0f, 24.0f);
        setBoost(gain_db / 24.0f);
    }

    float getGainDb() const {
        return boost_ * 24.0f;
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
        mono_mode_ = mono;
    }

    bool isMonoMode() const { return mono_mode_; }

    void reset() {
        anti_pop_ = anti_pop_enabled_ ? 0.0f : 1.0f;
        bass_factor_smoothed_ = bass_factor_;
        current_bass_gain_ = target_bass_gain_;
        current_side_gain_x_ = target_side_gain_x_;
        current_side_gain_y_ = target_side_gain_y_;
        current_low_ang_x_ = target_low_ang_x_;
        current_upp_ang_x_ = target_upp_ang_x_;
        current_low_ang_y_ = target_low_ang_y_;
        current_upp_ang_y_ = target_upp_ang_y_;

        smoothing_coeff_ = 1.0f - std::exp(-1.0f / (0.030f * sample_rate_)); // 30ms smoothing
        
        // 18 Hz DC blocker coefficient
        constexpr double PI = 3.14159265358979323846;
        dc_block_coeff_ = static_cast<float>(std::exp(-2.0 * PI * 18.0 / static_cast<double>(sample_rate_)));
        dc_x1_[0] = dc_x1_[1] = 0.0f;
        dc_y1_[0] = dc_y1_[1] = 0.0f;

        // Reset Natural / Pure Bass Direct Form I Biquad
        mono_lp_biquad_.reset();
        biquad_stereo_[0].reset();
        biquad_stereo_[1].reset();

        // Reset Polyphase FIR history buffers and delay line
        fir_head_l_ = 0;
        fir_head_r_ = 0;
        std::memset(fir_hist_l_, 0, sizeof(fir_hist_l_));
        std::memset(fir_hist_r_, 0, sizeof(fir_hist_r_));

        bass_delay_head_ = 0;
        std::memset(bass_delay_ring_, 0, sizeof(bass_delay_ring_));

        // Reset Subwoofer filters
        sub_peak_l_.reset();
        sub_peak_r_.reset();
        sub_peak_low_l_.reset();
        sub_peak_low_r_.reset();
        sub_lowpass_l_.reset();
        sub_lowpass_r_.reset();

        // Reset Harmonic Exciter states
        harm_envelope_ = 1e-10;
        harm_lp_l_.reset();
        harm_lp_r_.reset();
        harm_hp_l_.reset();
        harm_hp_r_.reset();

        // Reset Pultec filter states
        pultec_boost_x1_ = pultec_boost_x2_ = pultec_boost_y1_ = pultec_boost_y2_ = 0.0f;
        pultec_scoop_x1_l_ = pultec_scoop_x2_l_ = pultec_scoop_y1_l_ = pultec_scoop_y1_r_ = 0.0f;
        pultec_scoop_x1_r_ = pultec_scoop_x2_r_ = pultec_scoop_y2_l_ = pultec_scoop_y2_r_ = 0.0f;

        // Reset Multi-Pole Ladder filters
        ladder_x_[0] = LadderChannel{};
        ladder_x_[1] = LadderChannel{};
        ladder_y_[0] = LadderChannel{};
        ladder_y_[1] = LadderChannel{};
        dynamic_lp_biquad_.reset();
    }

    // Process interleaved stereo samples: [L0, R0, L1, R1, ...]
    void process(float* samples, uint32_t frame_count) {
        if (!enabled_ || frame_count == 0 || !samples) return;

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

private:
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
    // Multi-Type Parametric Biquad Filter (for Subwoofer & Resonance Bands)
    // =========================================================================
    struct MultiBiquadFilter {
        enum FilterType {
            LOW_PASS,
            HIGH_PASS,
            BAND_PASS,
            PEAK,
            LOW_SHELF,
            HIGH_SHELF
        };

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

        void refreshFilter(FilterType type, float gain_amp, float frequency, float sampling_rate, float q_factor, bool is_bandwidth) {
            double gain;
            if (type == PEAK || type == LOW_SHELF || type == HIGH_SHELF) {
                gain = std::pow(10.0, static_cast<double>(gain_amp) / 40.0);
            } else {
                gain = std::pow(10.0, static_cast<double>(gain_amp) / 20.0);
            }

            constexpr double PI = 3.14159265358979323846;
            const double omega = 2.0 * PI * static_cast<double>(frequency) / static_cast<double>(sampling_rate);
            const double sin_omega = std::sin(omega);
            const double cos_omega = std::cos(omega);

            double y = 0.0;
            double z = -1.0;

            if (type == LOW_SHELF || type == HIGH_SHELF) {
                y = sin_omega / 2.0 * std::sqrt((1.0 / gain + gain) * (1.0 / static_cast<double>(q_factor) - 1.0) + 2.0);
                z = std::sqrt(gain) * 2.0 * y;
            } else if (is_bandwidth) {
                y = std::sinh(static_cast<double>(q_factor) * std::log(2.0) * omega / 2.0 / sin_omega) * sin_omega;
            } else {
                y = sin_omega / (static_cast<double>(q_factor) + static_cast<double>(q_factor));
            }

            double a0 = 1.0, a1 = 0.0, a2 = 0.0;
            double b0 = 1.0, b1 = 0.0, b2 = 0.0;

            switch (type) {
                case LOW_PASS:
                    a0 = 1.0 + y;
                    a1 = -2.0 * cos_omega;
                    a2 = 1.0 - y;
                    b0 = (1.0 - cos_omega) / 2.0;
                    b1 = 1.0 - cos_omega;
                    b2 = (1.0 - cos_omega) / 2.0;
                    break;
                case HIGH_PASS:
                    a0 = 1.0 + y;
                    a1 = -2.0 * cos_omega;
                    a2 = 1.0 - y;
                    b0 = (1.0 + cos_omega) / 2.0;
                    b1 = -(1.0 + cos_omega);
                    b2 = (1.0 + cos_omega) / 2.0;
                    break;
                case PEAK:
                    a0 = 1.0 + y / gain;
                    a1 = -2.0 * cos_omega;
                    a2 = 1.0 - y / gain;
                    b0 = 1.0 + y * gain;
                    b1 = -2.0 * cos_omega;
                    b2 = 1.0 - y * gain;
                    break;
                case LOW_SHELF: {
                    const double tmp1 = gain + 1.0 - (gain - 1.0) * cos_omega;
                    const double tmp2 = gain + 1.0 + (gain - 1.0) * cos_omega;
                    a1 = (gain - 1.0 + (gain + 1.0) * cos_omega) * -2.0;
                    a2 = tmp2 - z;
                    b1 = gain * 2.0 * (gain - 1.0 - (gain + 1.0) * cos_omega);
                    a0 = tmp2 + z;
                    b0 = (tmp1 + z) * gain;
                    b2 = (tmp1 - z) * gain;
                    break;
                }
                default:
                    break;
            }

            a1_ = -(a1 / a0);
            a2_ = -(a2 / a0);
            b0_ = b0 / a0;
            b1_ = b1 / a0;
            b2_ = b2 / a0;
        }
    };

    // =========================================================================
    // 4-Pole Ladder Channel (for Dynamic Multi-Pole Resonator)
    // =========================================================================
    struct LadderChannel {
        float in[3]{};
        float x[4]{};
        float y[4]{};
    };

    bool enabled_ = false;
    BassEnhanceProfile profile_ = BassEnhanceProfile::NaturalBass;
    int current_preset_ = 18;
    float sample_rate_ = 48000.0f;
    float sample_period_ = 1.0f / 48000.0f;
    float cutoff_hz_ = 60.0f;
    float boost_ = 0.5f;
    bool anti_pop_enabled_ = true;
    bool mono_mode_ = true;

    // Gain smoothing and Anti-Pop
    float anti_pop_ = 0.0f;
    float bass_factor_ = 1.75f;
    float bass_factor_smoothed_ = 1.75f;
    float smoothing_coeff_ = 0.001f;

    // 18 Hz DC Blocker states (Stereo)
    float dc_block_coeff_ = 0.997f;
    float dc_x1_[2] = {0.0f, 0.0f};
    float dc_y1_[2] = {0.0f, 0.0f};

    // Direct Form I Butterworth Biquads (Natural & Pure Bass)
    BiquadDirectFormI mono_lp_biquad_;
    BiquadDirectFormI biquad_stereo_[2];

    // Polyphase 63-Tap FIR Filter States (Pure Bass+)
    float fir_hist_l_[63] = {0.0f};
    float fir_hist_r_[63] = {0.0f};
    size_t fir_head_l_ = 0;
    size_t fir_head_r_ = 0;
    float polyphase_kernel_[63] = {0.0f};

    // 63-Sample Latency Compensation Delay Line (Pure Bass+)
    float bass_delay_ring_[63] = {0.0f};
    size_t bass_delay_head_ = 0;

    // Subwoofer MultiBiquads (44Hz Peak + 80Hz LowPeak + 380Hz LowPass)
    MultiBiquadFilter sub_peak_l_, sub_peak_r_;
    MultiBiquadFilter sub_peak_low_l_, sub_peak_low_r_;
    MultiBiquadFilter sub_lowpass_l_, sub_lowpass_r_;

    // Psychoacoustic Bass States
    double harm_envelope_ = 1e-10;
    BiquadDirectFormI harm_lp_l_, harm_lp_r_;
    BiquadDirectFormI harm_hp_l_, harm_hp_r_;

    // Pultec Low-End Trick Coefficients
    float pultec_boost_b0_ = 1.0f, pultec_boost_b1_ = 0.0f, pultec_boost_b2_ = 0.0f;
    float pultec_boost_a1_ = 0.0f, pultec_boost_a2_ = 0.0f;
    float pultec_boost_x1_ = 0.0f, pultec_boost_x2_ = 0.0f, pultec_boost_y1_ = 0.0f, pultec_boost_y2_ = 0.0f;

    float pultec_scoop_b0_ = 1.0f, pultec_scoop_b1_ = 0.0f, pultec_scoop_b2_ = 0.0f;
    float pultec_scoop_a1_ = 0.0f, pultec_scoop_a2_ = 0.0f;
    float pultec_scoop_x1_l_ = 0.0f, pultec_scoop_x2_l_ = 0.0f, pultec_scoop_y1_l_ = 0.0f, pultec_scoop_y1_r_ = 0.0f;
    float pultec_scoop_x1_r_ = 0.0f, pultec_scoop_x2_r_ = 0.0f, pultec_scoop_y2_l_ = 0.0f, pultec_scoop_y2_r_ = 0.0f;

    // Multi-Pole Dynamic Resonator Parameters
    float x_low_ = 800.0f;
    float x_high_ = 6200.0f;
    float y_low_ = 80.0f;
    float y_high_ = 140.0f;
    float target_side_gain_x_ = 0.0f;
    float current_side_gain_x_ = 0.0f;
    float target_side_gain_y_ = 0.0f;
    float current_side_gain_y_ = 0.0f;
    float target_bass_gain_ = 2.8f;
    float current_bass_gain_ = 2.8f;
    float target_low_ang_x_ = 0.05f;
    float current_low_ang_x_ = 0.05f;
    float target_upp_ang_x_ = 0.35f;
    float current_upp_ang_x_ = 0.35f;
    float target_low_ang_y_ = 0.01f;
    float current_low_ang_y_ = 0.01f;
    float target_upp_ang_y_ = 0.02f;
    float current_upp_ang_y_ = 0.02f;

    LadderChannel ladder_x_[2]{};
    LadderChannel ladder_y_[2]{};
    BiquadDirectFormI dynamic_lp_biquad_;

    static constexpr float kDenormal = 1e-25f;

    // =========================================================================
    // Rational Algebraic Soft-Clipper with Knee (clean, warm, zero harsh harmonics)
    // =========================================================================
    static inline float softClip(const float v, const float knee) {
        const float drive = std::fabs(v);
        if (drive <= knee) return v;
        const float over = drive - knee;
        const float shaped = knee + over / std::sqrt(1.0f + over * over);
        return v * (shaped / drive);
    }

    // =========================================================================
    // 18 Hz DC Blocker & Dual-Stage Soft Clip Mix
    // =========================================================================
    inline void shapeMix(float bass, float* samples, const uint32_t i) {
        // 1. 18 Hz High-Pass DC Blocker
        const float y = dc_block_coeff_ * (dc_y1_[0] + bass - dc_x1_[0]);
        dc_x1_[0] = bass;
        dc_y1_[0] = y;

        // 2. Stage 1 Soft-Clip on DC-blocked bass signal alone (knee = 0.8)
        bass = softClip(y, 0.8f);

        // 3. Stage 2 Soft-Clip on summed stereo channels (knee = 0.95)
        samples[2 * i]     = softClip(samples[2 * i] + bass, 0.95f);
        samples[2 * i + 1] = softClip(samples[2 * i + 1] + bass, 0.95f);
    }

    inline void shapeMixStereo(float bass_l, float bass_r, float* samples, const uint32_t i) {
        // 1. 18 Hz High-Pass DC Blocker per channel
        const float y_l = dc_block_coeff_ * (dc_y1_[0] + bass_l - dc_x1_[0]);
        dc_x1_[0] = bass_l;
        dc_y1_[0] = y_l;

        const float y_r = dc_block_coeff_ * (dc_y1_[1] + bass_r - dc_x1_[1]);
        dc_x1_[1] = bass_r;
        dc_y1_[1] = y_r;

        // 2. Stage 1 Soft-Clip on bass channels
        bass_l = softClip(y_l, 0.8f);
        bass_r = softClip(y_r, 0.8f);

        // 3. Stage 2 Soft-Clip on output
        samples[2 * i]     = softClip(samples[2 * i] + bass_l, 0.95f);
        samples[2 * i + 1] = softClip(samples[2 * i + 1] + bass_r, 0.95f);
    }

    // =========================================================================
    // Mode 0: Natural Mono Bass (Mono Butterworth Q=0.53 + Soft Clip Injection)
    // =========================================================================
    void processNaturalBass(float* samples, uint32_t frame_count) {
        for (uint32_t i = 0; i < frame_count; i++) {
            bass_factor_smoothed_ += (bass_factor_ - bass_factor_smoothed_) * smoothing_coeff_;

            if (mono_mode_) {
                // Mono summation (L + R) / 2
                const double mono_in = (static_cast<double>(samples[2 * i]) +
                                        static_cast<double>(samples[2 * i + 1])) * 0.5;

                // Direct Form I Biquad Lowpass
                float bass = static_cast<float>(mono_lp_biquad_.process(mono_in)) * bass_factor_smoothed_;

                // Anti-pop smooth ramp
                if (anti_pop_ < 1.0f) {
                    bass *= anti_pop_;
                    anti_pop_ = std::min(1.0f, anti_pop_ + sample_period_ * 4.0f);
                }

                shapeMix(bass, samples, i);
            } else {
                float bass_l = static_cast<float>(biquad_stereo_[0].process(samples[2 * i])) * bass_factor_smoothed_;
                float bass_r = static_cast<float>(biquad_stereo_[1].process(samples[2 * i + 1])) * bass_factor_smoothed_;

                if (anti_pop_ < 1.0f) {
                    bass_l *= anti_pop_;
                    bass_r *= anti_pop_;
                    anti_pop_ = std::min(1.0f, anti_pop_ + sample_period_ * 4.0f);
                }

                shapeMixStereo(bass_l, bass_r, samples, i);
            }
        }
    }

    // =========================================================================
    // Mode 1: Pure Bass+ Mono (63-Tap Polyphase FIR + Aligned Mono Bass)
    // =========================================================================
    void processPureBassPlus(float* samples, uint32_t frame_count) {
        for (uint32_t i = 0; i < frame_count; i++) {
            const float in_l = samples[2 * i];
            const float in_r = samples[2 * i + 1];

            // 1. Mono summation and lowpass extraction
            const double mono_in = (static_cast<double>(in_l) + static_cast<double>(in_r)) * 0.5;
            const float lp_bass = static_cast<float>(mono_lp_biquad_.process(mono_in));

            // 2. Push lowpass bass into delay line and tap it at constant 31-sample group delay
            bass_delay_ring_[bass_delay_head_] = lp_bass;
            const size_t delayed_idx = (bass_delay_head_ + 32) % 63; // written 31 frames ago
            const float delayed_bass = bass_delay_ring_[delayed_idx];
            bass_delay_head_ = (bass_delay_head_ + 1) % 63;

            // 3. Polyphase 63-tap FIR convolution on Left channel
            fir_hist_l_[fir_head_l_] = in_l;
            float fir_out_l = 0.0f;
            size_t idx_l = fir_head_l_;
            for (size_t j = 0; j < 63; j++) {
                fir_out_l += polyphase_kernel_[j] * fir_hist_l_[idx_l];
                idx_l = (idx_l == 0) ? 62 : idx_l - 1;
            }
            fir_head_l_ = (fir_head_l_ + 1) % 63;

            // 4. Polyphase 63-tap FIR convolution on Right channel
            fir_hist_r_[fir_head_r_] = in_r;
            float fir_out_r = 0.0f;
            size_t idx_r = fir_head_r_;
            for (size_t j = 0; j < 63; j++) {
                fir_out_r += polyphase_kernel_[j] * fir_hist_r_[idx_r];
                idx_r = (idx_r == 0) ? 62 : idx_r - 1;
            }
            fir_head_r_ = (fir_head_r_ + 1) % 63;

            // Write polyphase phase-shaped audio
            samples[2 * i]     = fir_out_l;
            samples[2 * i + 1] = fir_out_r;

            // 5. Smooth gain and inject time-aligned mono bass
            bass_factor_smoothed_ += (bass_factor_ - bass_factor_smoothed_) * smoothing_coeff_;
            float driven_bass = delayed_bass * bass_factor_smoothed_;

            if (anti_pop_ < 1.0f) {
                driven_bass *= anti_pop_;
                anti_pop_ = std::min(1.0f, anti_pop_ + sample_period_ * 4.0f);
            }

            shapeMix(driven_bass, samples, i);
        }
    }

    // =========================================================================
    // Mode 2: Subwoofer Mono (44Hz/80Hz Dual Peak + 380Hz Differential Lowpass)
    // =========================================================================
    void processSubwoofer(float* samples, uint32_t frame_count) {
        for (uint32_t i = 0; i < frame_count; i++) {
            const float in_l = samples[2 * i];
            const float in_r = samples[2 * i + 1];

            // 1. Dual-peaking excursion on Left channel
            double tmp_l = sub_peak_l_.process(in_l);
            tmp_l = sub_peak_low_l_.process(tmp_l);
            tmp_l = sub_lowpass_l_.process(tmp_l - in_l);

            // 2. Dual-peaking excursion on Right channel
            double tmp_r = sub_peak_r_.process(in_r);
            tmp_r = sub_peak_low_r_.process(tmp_r);
            tmp_r = sub_lowpass_r_.process(tmp_r - in_r);

            // 3. Mono-anchored subwoofer excursion energy
            float sub_mono = static_cast<float>((tmp_l + tmp_r) * 0.5) * 0.6f;

            if (anti_pop_ < 1.0f) {
                sub_mono *= anti_pop_;
                anti_pop_ = std::min(1.0f, anti_pop_ + sample_period_ * 4.0f);
            }

            // Mix subwoofer differential into output with rational soft-clipping
            shapeMix(sub_mono, samples, i);
        }
    }

    // =========================================================================
    // Mode 3: Psychoacoustic Bass (Envelope-Tracked Chebyshev 2f+3f Synthesizer)
    // =========================================================================
    void processHarmonicExciter(float* samples, uint32_t frame_count) {
        const float intensity = boost_ * 0.85f;

        for (uint32_t i = 0; i < frame_count; i++) {
            const float in_l = samples[2 * i];
            const float in_r = samples[2 * i + 1];

            // 1. Extract fundamental sub-bass
            const double bass_l = harm_lp_l_.process(in_l);
            const double bass_r = harm_lp_r_.process(in_r);

            // 2. Dynamic Envelope Follower
            const double abs_l = std::fabs(bass_l);
            const double abs_r = std::fabs(bass_r);
            const double peak = (abs_l > abs_r) ? abs_l : abs_r;

            if (peak > harm_envelope_) {
                harm_envelope_ += 0.01 * (peak - harm_envelope_);
            } else {
                harm_envelope_ += 0.0001 * (peak - harm_envelope_);
            }
            if (harm_envelope_ < 1e-10) harm_envelope_ = 1e-10;

            // 3. Normalize into Chebyshev range [-1, 1]
            double norm_l = std::clamp(bass_l / harm_envelope_, -1.0, 1.0);
            double norm_r = std::clamp(bass_r / harm_envelope_, -1.0, 1.0);

            // 4. Synthesize 2nd (T2 = 2x^2 - 1) and 3rd (T3 = 4x^3 - 3x) Order Harmonics
            auto chebyshev_h3 = [](double x) {
                double t2 = 2.0 * x * x - 1.0;
                double t3 = 4.0 * x * x * x - 3.0 * x;
                return 0.7 * t2 + 0.3 * t3;
            };

            double h_l = chebyshev_h3(norm_l) * harm_envelope_;
            double h_r = chebyshev_h3(norm_r) * harm_envelope_;

            // 5. High-Pass Filter Harmonics above cutoff
            h_l = harm_hp_l_.process(h_l);
            h_r = harm_hp_r_.process(h_r);

            // 6. Mono-summed harmonic injection
            float mono_harm = static_cast<float>((h_l + h_r) * 0.5) * intensity;

            if (anti_pop_ < 1.0f) {
                mono_harm *= anti_pop_;
                anti_pop_ = std::min(1.0f, anti_pop_ + sample_period_ * 4.0f);
            }

            shapeMix(mono_harm, samples, i);
        }
    }

    // =========================================================================
    // Mode 4: Pultec EQP-1A Low-End Trick in Mono Sub + Stereo Mud Scoop
    // =========================================================================
    void processPultecDeep(float* samples, uint32_t frame_count) {
        for (uint32_t i = 0; i < frame_count; i++) {
            const float in_l = samples[2 * i];
            const float in_r = samples[2 * i + 1];

            // 1. Mono Sub-Bass 45 Hz Low-Shelf Boost
            const float mono_in = (in_l + in_r) * 0.5f;
            const float b_out = pultec_boost_b0_ * mono_in + pultec_boost_b1_ * pultec_boost_x1_ + pultec_boost_b2_ * pultec_boost_x2_
                              - pultec_boost_a1_ * pultec_boost_y1_ - pultec_boost_a2_ * pultec_boost_y2_;
            pultec_boost_x2_ = pultec_boost_x1_; pultec_boost_x1_ = mono_in;
            pultec_boost_y2_ = pultec_boost_y1_; pultec_boost_y1_ = b_out;

            // 2. Stereo 300 Hz Mud Scoop Peak Filter
            const float s_out_l = pultec_scoop_b0_ * in_l + pultec_scoop_b1_ * pultec_scoop_x1_l_ + pultec_scoop_b2_ * pultec_scoop_x2_l_
                                - pultec_scoop_a1_ * pultec_scoop_y1_l_ - pultec_scoop_a2_ * pultec_scoop_y2_l_;
            pultec_scoop_x2_l_ = pultec_scoop_x1_l_; pultec_scoop_x1_l_ = in_l;
            pultec_scoop_y2_l_ = pultec_scoop_y1_l_; pultec_scoop_y1_l_ = s_out_l;

            const float s_out_r = pultec_scoop_b0_ * in_r + pultec_scoop_b1_ * pultec_scoop_x1_r_ + pultec_scoop_b2_ * pultec_scoop_x2_r_
                                - pultec_scoop_a1_ * pultec_scoop_y1_r_ - pultec_scoop_a2_ * pultec_scoop_y2_r_;
            pultec_scoop_x2_r_ = pultec_scoop_x1_r_; pultec_scoop_x1_r_ = in_r;
            pultec_scoop_y2_r_ = pultec_scoop_y1_r_; pultec_scoop_y1_r_ = s_out_r;

            samples[2 * i]     = s_out_l;
            samples[2 * i + 1] = s_out_r;

            float mono_bass = (b_out - mono_in) * 0.8f;

            if (anti_pop_ < 1.0f) {
                mono_bass *= anti_pop_;
                anti_pop_ = std::min(1.0f, anti_pop_ + sample_period_ * 4.0f);
            }

            shapeMix(mono_bass, samples, i);
        }
    }

    // =========================================================================
    // Mode 5: Dynamic Multi-Pole Resonator (Cascaded 4-Pole Ladder Network)
    // =========================================================================
    inline void processLadder(LadderChannel* ch, float sample, float low_ang, float upp_ang, float& out1, float& out2, float& out3) {
        const float oldest_sample = ch->in[2];
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

        out1 = ch->x[3];                 // Low-pass sub-band (fundamental bass)
        out2 = oldest_sample - ch->y[3]; // High-pass residual
        out3 = ch->y[3] - ch->x[3];      // Mid-frequency crossover band
    }

    void processDynamicMultiPole(float* samples, uint32_t frame_count) {
        for (uint32_t i = 0; i < frame_count; i++) {
            // Smooth parameters
            current_bass_gain_   += smoothing_coeff_ * (target_bass_gain_ - current_bass_gain_);
            current_side_gain_x_ += smoothing_coeff_ * (target_side_gain_x_ - current_side_gain_x_);
            current_side_gain_y_ += smoothing_coeff_ * (target_side_gain_y_ - current_side_gain_y_);
            current_low_ang_x_   += smoothing_coeff_ * (target_low_ang_x_ - current_low_ang_x_);
            current_upp_ang_x_   += smoothing_coeff_ * (target_upp_ang_x_ - current_upp_ang_x_);
            current_low_ang_y_   += smoothing_coeff_ * (target_low_ang_y_ - current_low_ang_y_);
            current_upp_ang_y_   += smoothing_coeff_ * (target_upp_ang_y_ - current_upp_ang_y_);

            const float in_l = samples[2 * i];
            const float in_r = samples[2 * i + 1];

            if (x_low_ <= 120.0f) {
                const double mono_in = (static_cast<double>(in_l) + static_cast<double>(in_r)) * 0.5;
                const float low_out = static_cast<float>(dynamic_lp_biquad_.process(mono_in));
                float out_l = in_l + low_out * (current_bass_gain_ - 1.0f);
                float out_r = in_r + low_out * (current_bass_gain_ - 1.0f);

                if (anti_pop_ < 1.0f) {
                    out_l = in_l + anti_pop_ * (out_l - in_l);
                    out_r = in_r + anti_pop_ * (out_r - in_r);
                    anti_pop_ = std::min(1.0f, anti_pop_ + sample_period_ * 4.0f);
                }

                samples[2 * i]     = softClip(out_l, 0.95f);
                samples[2 * i + 1] = softClip(out_r, 0.95f);
            } else {
                // 1. Stage 1 Ladder X (Channel Decomposition)
                float x1_l, x2_l, x3_l;
                processLadder(&ladder_x_[0], in_l, current_low_ang_x_, current_upp_ang_x_, x1_l, x2_l, x3_l);
                float x1_r, x2_r, x3_r;
                processLadder(&ladder_x_[1], in_r, current_low_ang_x_, current_upp_ang_x_, x1_r, x2_r, x3_r);

                // 2. Stage 2 Ladder Y (Dynamic Bass Resonance)
                float y1_l, y2_l, y3_l;
                processLadder(&ladder_y_[0], current_bass_gain_ * x1_l, current_low_ang_y_, current_upp_ang_y_, y1_l, y2_l, y3_l);
                float y1_r, y2_r, y3_r;
                processLadder(&ladder_y_[1], current_bass_gain_ * x1_r, current_low_ang_y_, current_upp_ang_y_, y1_r, y2_r, y3_r);

                // 3. Multi-Band Matrix Recombination
                float out_l = x2_l + y3_l + current_side_gain_x_ * y2_l + current_side_gain_y_ * y1_l + x3_l;
                float out_r = x2_r + y3_r + current_side_gain_x_ * y2_r + current_side_gain_y_ * y1_r + x3_r;

                if (anti_pop_ < 1.0f) {
                    out_l = in_l + anti_pop_ * (out_l - in_l);
                    out_r = in_r + anti_pop_ * (out_r - in_r);
                    anti_pop_ = std::min(1.0f, anti_pop_ + sample_period_ * 4.0f);
                }

                samples[2 * i]     = softClip(out_l, 0.95f);
                samples[2 * i + 1] = softClip(out_r, 0.95f);
            }
        }
    }

    void updateFilters() {
        // 1. Natural & Pure Bass Low-Pass Filter (Butterworth Q = 0.53 critically damped)
        mono_lp_biquad_.setLowPass(cutoff_hz_, sample_rate_, 0.53f);
        biquad_stereo_[0].setLowPass(cutoff_hz_, sample_rate_, 0.53f);
        biquad_stereo_[1].setLowPass(cutoff_hz_, sample_rate_, 0.53f);
        buildPolyphaseKernel();

        // 2. Subwoofer Configuration (44 Hz peak + 80 Hz low peak + 380 Hz lowpass)
        const float effective_gain = 1.0f + boost_ * 9.0f; // 1.0x to 10.0x excursion gain
        const float gain_db = 20.0f * std::log10(effective_gain);
        const float gain_lower_db = 20.0f * std::log10(std::max(1.0f, effective_gain / 4.0f));

        sub_peak_l_.refreshFilter(MultiBiquadFilter::PEAK, gain_db, 44.0f, sample_rate_, 0.75f, true);
        sub_peak_r_.refreshFilter(MultiBiquadFilter::PEAK, gain_db, 44.0f, sample_rate_, 0.75f, true);

        sub_peak_low_l_.refreshFilter(MultiBiquadFilter::PEAK, gain_lower_db, 80.0f, sample_rate_, 0.2f, true);
        sub_peak_low_r_.refreshFilter(MultiBiquadFilter::PEAK, gain_lower_db, 80.0f, sample_rate_, 0.2f, true);

        sub_lowpass_l_.refreshFilter(MultiBiquadFilter::LOW_PASS, 0.0f, 380.0f, sample_rate_, 0.6f, false);
        sub_lowpass_r_.refreshFilter(MultiBiquadFilter::LOW_PASS, 0.0f, 380.0f, sample_rate_, 0.6f, false);

        // 3. Psychoacoustic Bass Filters (Cutoff Lowpass + Cutoff Highpass)
        const float harm_cutoff = std::clamp(cutoff_hz_, 60.0f, 150.0f);
        harm_lp_l_.setLowPass(harm_cutoff, sample_rate_, 0.717f);
        harm_lp_r_.setLowPass(harm_cutoff, sample_rate_, 0.717f);
        harm_hp_l_.setHighPass(harm_cutoff, sample_rate_, 0.717f);
        harm_hp_r_.setHighPass(harm_cutoff, sample_rate_, 0.717f);

        // 4. Pultec EQP-1A Low-End Trick:
        // Deep 45 Hz Low-Shelf (+0 dB to +12 dB boost)
        const float pultec_boost_db = boost_ * 12.0f;
        calcLowshelf(45.0f, pultec_boost_db, pultec_boost_b0_, pultec_boost_b1_, pultec_boost_b2_, pultec_boost_a1_, pultec_boost_a2_);

        // 300 Hz Mud-Scoop (-0 dB to -4.5 dB cut at Q=1.2)
        const float pultec_scoop_db = -boost_ * 4.5f;
        calcPeakingEq(300.0f, 1.2f, pultec_scoop_db, pultec_scoop_b0_, pultec_scoop_b1_, pultec_scoop_b2_, pultec_scoop_a1_, pultec_scoop_a2_);

        // 5. Dynamic Multi-Pole Resonator Ladders
        const float coeff = 2.0f * 3.14159265358979323846f / sample_rate_;
        auto onePoleCoeff = [coeff](float f) {
            return std::clamp(1.0f - std::exp(-coeff * f), 0.0001f, 0.95f);
        };
        target_low_ang_x_ = onePoleCoeff(x_low_);
        target_upp_ang_x_ = onePoleCoeff(x_high_);
        target_low_ang_y_ = onePoleCoeff(y_low_);
        target_upp_ang_y_ = onePoleCoeff(y_high_);

        // 55 Hz Lowpass for low frequency fallback
        const float q_peak = std::clamp((target_bass_gain_ - 1.0f) / 20.0f * 1600.0f, 0.0f, 1600.0f);
        dynamic_lp_biquad_.setLowPass(55.0f, sample_rate_, q_peak / 666.0f + 0.5f);
    }

    // =========================================================================
    // Runtime-designed 63-tap linear-phase FIR for Pure Bass+ mode.
    // Blackman-windowed sinc, normalized to unity DC gain and symmetric about
    // the center tap (constant ~31-sample group delay).
    // =========================================================================
    void buildPolyphaseKernel() {
        constexpr int N = 63;
        constexpr int M = N / 2; // center tap -> 31-sample group delay
        constexpr double kPi = 3.14159265358979323846;
        const double fc = std::min(20000.0, 0.475 * (double)sample_rate_) / (double)sample_rate_; // normalized cutoff (< Nyquist)

        double sum = 0.0;
        for (int n = 0; n < N; ++n) {
            const double x = (double)(n - M);
            double v;
            if (std::fabs(x) < 1e-9) {
                v = 2.0 * fc;
            } else {
                v = std::sin(2.0 * kPi * fc * x) / (kPi * x);
            }
            // Blackman window
            const double w = 0.42
                - 0.5 * std::cos(2.0 * kPi * (double)n / (double)(N - 1))
                + 0.08 * std::cos(4.0 * kPi * (double)n / (double)(N - 1));
            v *= w;
            polyphase_kernel_[(size_t)n] = static_cast<float>(v);
            sum += v;
        }

        if (sum > 1e-9) {
            const float inv = static_cast<float>(1.0 / sum);
            for (int n = 0; n < N; ++n) {
                polyphase_kernel_[(size_t)n] *= inv;
            }
        } else {
            // Degenerate fallback: pure identity at the center tap.
            std::memset(polyphase_kernel_, 0, sizeof(polyphase_kernel_));
            polyphase_kernel_[M] = 1.0f;
        }
    }

    void calcLowshelf(float freq, float gain_db, float& b0, float& b1, float& b2, float& a1, float& a2) {
        constexpr double PI = 3.14159265358979323846;
        const double A = std::pow(10.0, static_cast<double>(gain_db) / 40.0);
        double w0 = 2.0 * PI * static_cast<double>(freq) / static_cast<double>(sample_rate_);
        if (w0 > PI * 0.95) w0 = PI * 0.95;
        const double cos_w0 = std::cos(w0);
        const double sin_w0 = std::sin(w0);
        const double alpha = sin_w0 / 2.0 * std::sqrt((A + 1.0 / A) * (1.0 / 0.7071 - 1.0) + 2.0);
        const double sqrt_A = 2.0 * std::sqrt(A) * alpha;

        const double a0 = (A + 1.0) + (A - 1.0) * cos_w0 + sqrt_A;
        b0 = static_cast<float>((A * ((A + 1.0) - (A - 1.0) * cos_w0 + sqrt_A)) / a0);
        b1 = static_cast<float>((2.0 * A * ((A - 1.0) - (A + 1.0) * cos_w0)) / a0);
        b2 = static_cast<float>((A * ((A + 1.0) - (A - 1.0) * cos_w0 - sqrt_A)) / a0);
        a1 = static_cast<float>((-2.0 * ((A - 1.0) + (A + 1.0) * cos_w0)) / a0);
        a2 = static_cast<float>(((A + 1.0) + (A - 1.0) * cos_w0 - sqrt_A) / a0);
    }

    void calcPeakingEq(float freq, float Q, float gain_db, float& b0, float& b1, float& b2, float& a1, float& a2) {
        constexpr double PI = 3.14159265358979323846;
        const double A = std::pow(10.0, static_cast<double>(gain_db) / 40.0);
        double w0 = 2.0 * PI * static_cast<double>(freq) / static_cast<double>(sample_rate_);
        if (w0 > PI * 0.95) w0 = PI * 0.95;
        const double cos_w0 = std::cos(w0);
        const double alpha = std::sin(w0) / (2.0 * static_cast<double>(Q));

        const double a0 = 1.0 + alpha / A;
        b0 = static_cast<float>((1.0 + alpha * A) / a0);
        b1 = static_cast<float>((-2.0 * cos_w0) / a0);
        b2 = static_cast<float>((1.0 - alpha * A) / a0);
        a1 = static_cast<float>((-2.0 * cos_w0) / a0);
        a2 = static_cast<float>((1.0 - alpha / A) / a0);
    }
};

} // namespace sauti::dsp
