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

    // Backward-compatible aliases
    SubBassResonant = 0,
    PunchyBass = 1
};

// =============================================================================
// 63-Tap Polyphase Filter
//
// The kernel is no longer a hardcoded table: the previous constants summed to
// ~0.20 (-14 dB passband loss) and were non-symmetric (nonlinear phase), which
// attenuated and phase-smeared the entire signal in Pure Bass+ mode. A unity-
// gain, linear-phase Blackman-windowed sinc low-pass is designed at runtime in
// updateFilters() instead (see buildPolyphaseKernel).
// =============================================================================

// =============================================================================
// HarmonicBassDSP: High-Fidelity Clean-Room Dynamic Bass & Subwoofer Suite
// =============================================================================
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
        // Linear scale matching dynamic bass multiplier [0.0 .. 3.5x]
        bass_factor_ = boost_ * 3.5f;
        updateFilters();
    }

    float getBoost() const { return boost_; }

    void reset() {
        anti_pop_ = 0.0f;
        bass_factor_smoothed_ = bass_factor_;
        smoothing_coeff_ = 1.0f - std::exp(-1.0f / (0.030f * sample_rate_)); // 30ms smoothing
        
        // 18 Hz DC blocker coefficient
        constexpr double PI = 3.14159265358979323846;
        dc_block_coeff_ = static_cast<float>(std::exp(-2.0 * PI * 18.0 / static_cast<double>(sample_rate_)));
        dc_x1_ = 0.0f;
        dc_y1_ = 0.0f;

        // Reset Natural / Pure Bass Direct Form I Biquad
        mono_lp_biquad_.reset();

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

    // Direct Form I Butterworth Biquad (Natural & Pure Bass)
    BiquadDirectFormI mono_lp_biquad_;

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
        const float y = dc_block_coeff_ * (dc_y1_ + bass - dc_x1_);
        dc_x1_ = bass;
        dc_y1_ = y;

        // 2. Stage 1 Soft-Clip on DC-blocked bass signal alone (knee = 0.8)
        bass = softClip(y, 0.8f);

        // 3. Stage 2 Soft-Clip on summed stereo channels (knee = 0.95)
        samples[2 * i]     = softClip(samples[2 * i] + bass, 0.95f);
        samples[2 * i + 1] = softClip(samples[2 * i + 1] + bass, 0.95f);
    }

    // =========================================================================
    // Mode 0: Natural Mono Bass (Mono Butterworth Q=0.53 + Soft Clip Injection)
    // =========================================================================
    void processNaturalBass(float* samples, uint32_t frame_count) {
        for (uint32_t i = 0; i < frame_count; i++) {
            bass_factor_smoothed_ += (bass_factor_ - bass_factor_smoothed_) * smoothing_coeff_;

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

            // 2. Push lowpass bass into a delay line and tap it exactly on the
            // FIR's constant 31-sample group delay (phase-aligned injection).
            bass_delay_ring_[bass_delay_head_] = lp_bass;
            const size_t delayed_idx = (bass_delay_head_ + 32) % 63; // written 31 frames ago
            const float delayed_bass = bass_delay_ring_[delayed_idx];
            bass_delay_head_ = (bass_delay_head_ + 1) % 63;

            // 3. Polyphase 63-tap FIR convolution on Left channel.
            // Walk the ring backwards without modulo-per-tap (the old
            // (head + 63 - j) % 63 form cost a division per tap).
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

            // Write polyphase phase-shaped audio. The FIR is a unity-gain,
            // linear-phase filter, so replacing the signal is now transparent
            // up to its constant 31-sample group delay (compensated by the
            // aligned bass delay line below).
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

            // 4. Synthesize 2nd (T2 = 2x^2 - 1) and 3rd (T3 = 4x^3 - 3x) Order Harmonics (0.7 * T2 + 0.3 * T3)
            auto chebyshev_h3 = [](double x) {
                double t2 = 2.0 * x * x - 1.0;
                double t3 = 4.0 * x * x * x - 3.0 * x;
                return 0.7 * t2 + 0.3 * t3;
            };

            double h_l = chebyshev_h3(norm_l) * harm_envelope_;
            double h_r = chebyshev_h3(norm_r) * harm_envelope_;

            // 5. High-Pass Filter Harmonics above cutoff (so energy is in audible speaker range)
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

    void updateFilters() {
        // 1. Natural & Pure Bass Low-Pass Filter (Butterworth Q = 0.53 critically damped)
        mono_lp_biquad_.setLowPass(cutoff_hz_, sample_rate_, 0.53f);
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
    }

    // =========================================================================
    // Runtime-designed 63-tap linear-phase FIR for Pure Bass+ mode.
    // Blackman-windowed sinc, normalized to unity DC gain and symmetric about
    // the center tap (constant ~31-sample group delay). Replaces the old
    // corrupt hardcoded table (-14 dB gain, nonlinear phase).
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
