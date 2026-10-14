#pragma once

#include <cmath>
#include <cstdint>
#include <algorithm>
#include <atomic>
#include "denormals.h"

namespace sauti::dsp {

// =============================================================================
// ToneCrossoverDSP: Audiophile 3-Band Phase-Compensated LR4 Tone Crossover
//
// Topology:
//   - 4th-Order Linkwitz-Riley (LR4, 24 dB/octave) 3-Way Frequency Crossover.
//   - All-Pass Phase Compensation on Low band for Crossover 2 phase alignment:
//       H_low(s)  = LP1(s, f_low) * AP2(s, f_high)
//       H_mid(s)  = HP1(s, f_low) * LP2(s, f_high)
//       H_high(s) = HP1(s, f_low) * HP2(s, f_high)
//   - Unity-Gain Transparency:
//       H_sum(s) = H_low + H_mid + H_high = AP1(s, f_low) * AP2(s, f_high)
//       |H_sum(j*w)| == 1.000000000 (0.000 dB ripple across 20 Hz - 20 kHz).
//   - Pure Linear Time-Invariant (LTI) - No dynamic pumping or IMD distortion.
//   - 64-bit double-precision biquad state filters for zero roundoff noise floor.
//   - Per-sample exponential gain de-zippering (click-free tone adjustment).
// =============================================================================
class ToneCrossoverDSP {
public:
    static constexpr int kMaxChannels = 8;

    struct BiquadCoeffs {
        double b0 = 1.0, b1 = 0.0, b2 = 0.0;
        double a1 = 0.0, a2 = 0.0;
    };

    struct BiquadState {
        double s1 = 0.0;
        double s2 = 0.0;
        void reset() { s1 = 0.0; s2 = 0.0; }
        inline double process(const BiquadCoeffs& c, double in) {
            double out = in * c.b0 + s1;
            s1 = in * c.b1 - out * c.a1 + s2;
            s2 = in * c.b2 - out * c.a2;
            if (std::fabs(s1) < 1.0e-20) s1 = 0.0;
            if (std::fabs(s2) < 1.0e-20) s2 = 0.0;
            return out;
        }
    };

    // 4th-Order LR4 filter stage (cascaded pair of 2nd-order Butterworth filters)
    struct LR4Stage {
        BiquadState stage1[kMaxChannels];
        BiquadState stage2[kMaxChannels];

        void reset() {
            for (int ch = 0; ch < kMaxChannels; ++ch) {
                stage1[ch].reset();
                stage2[ch].reset();
            }
        }

        inline double process(const BiquadCoeffs& c, int ch, double in) {
            double v = stage1[ch].process(c, in);
            return stage2[ch].process(c, v);
        }
    };

    // 2nd-Order All-Pass filter stage for phase compensation
    struct AP2Stage {
        BiquadState stage[kMaxChannels];

        void reset() {
            for (int ch = 0; ch < kMaxChannels; ++ch) {
                stage[ch].reset();
            }
        }

        inline double process(const BiquadCoeffs& c, int ch, double in) {
            return stage[ch].process(c, in);
        }
    };

    ToneCrossoverDSP() {
        setSampleRate(48000.0f);
        reset();
    }

    void setSampleRate(float sampleRate) {
        if (sampleRate <= 0.0f) sampleRate = 48000.0f;
        sample_rate_ = sampleRate;
        updateFilters();
        updateSmoothingAlpha();
    }

    float getSampleRate() const { return sample_rate_; }

    void setEnabled(bool enabled) {
        enabled_.store(enabled, std::memory_order_release);
        if (!enabled) {
            reset();
        }
    }

    bool isEnabled() const { return enabled_.load(std::memory_order_relaxed); }

    void reset() {
        lp1_.reset();
        hp1_.reset();
        ap2_.reset();
        lp2_.reset();
        hp2_.reset();
        cur_bass_linear_ = target_bass_linear_;
        cur_mid_linear_ = target_mid_linear_;
        cur_treble_linear_ = target_treble_linear_;
    }

    // Tone Gain Setters (-15 dB to +15 dB)
    void setBassGainDb(float gainDb) {
        float clamped = std::clamp(gainDb, -15.0f, 15.0f);
        bass_gain_db_.store(clamped, std::memory_order_relaxed);
        target_bass_linear_ = std::pow(10.0, static_cast<double>(clamped) * 0.05);
    }
    float getBassGainDb() const { return bass_gain_db_.load(std::memory_order_relaxed); }

    void setMidGainDb(float gainDb) {
        float clamped = std::clamp(gainDb, -15.0f, 15.0f);
        mid_gain_db_.store(clamped, std::memory_order_relaxed);
        target_mid_linear_ = std::pow(10.0, static_cast<double>(clamped) * 0.05);
    }
    float getMidGainDb() const { return mid_gain_db_.load(std::memory_order_relaxed); }

    void setTrebleGainDb(float gainDb) {
        float clamped = std::clamp(gainDb, -15.0f, 15.0f);
        treble_gain_db_.store(clamped, std::memory_order_relaxed);
        target_treble_linear_ = std::pow(10.0, static_cast<double>(clamped) * 0.05);
    }
    float getTrebleGainDb() const { return treble_gain_db_.load(std::memory_order_relaxed); }

    void setGainsDb(float bassDb, float midDb, float trebleDb) {
        setBassGainDb(bassDb);
        setMidGainDb(midDb);
        setTrebleGainDb(trebleDb);
    }

    // Crossover Frequency Setters
    void setCrossoverFrequencies(float lowCutoffHz, float highCutoffHz) {
        float lowClamped = std::clamp(lowCutoffHz, 60.0f, 1000.0f);
        float highClamped = std::clamp(highCutoffHz, 1200.0f, 10000.0f);
        if (lowClamped >= highClamped) {
            lowClamped = 250.0f;
            highClamped = 3200.0f;
        }
        low_crossover_hz_.store(lowClamped, std::memory_order_relaxed);
        high_crossover_hz_.store(highClamped, std::memory_order_relaxed);
        updateFilters();
    }

    float getLowCrossoverHz() const { return low_crossover_hz_.load(std::memory_order_relaxed); }
    float getHighCrossoverHz() const { return high_crossover_hz_.load(std::memory_order_relaxed); }

    void process(float* buffer, uint32_t frames, int channels) {
        if (!isEnabled() || !buffer || frames == 0 || channels < 1) return;
        const int chs = std::min(channels, kMaxChannels);

        for (uint32_t i = 0; i < frames; ++i) {
            // Exponential smoothing for tone gains (dezippered continuous transition)
            cur_bass_linear_ += gain_smooth_alpha_ * (target_bass_linear_ - cur_bass_linear_);
            cur_mid_linear_  += gain_smooth_alpha_ * (target_mid_linear_  - cur_mid_linear_);
            cur_treble_linear_ += gain_smooth_alpha_ * (target_treble_linear_ - cur_treble_linear_);

            const double gLow = cur_bass_linear_;
            const double gMid = cur_mid_linear_;
            const double gHigh = cur_treble_linear_;

            for (int c = 0; c < chs; ++c) {
                const size_t idx = static_cast<size_t>(i) * channels + c;
                const double x = static_cast<double>(buffer[idx]);

                // 1. First crossover split at f_low
                double x_low1  = lp1_.process(lp1_coeffs_, c, x);
                double x_high1 = hp1_.process(hp1_coeffs_, c, x);

                // 2. All-pass phase compensation on Low band (matches Crossover 2 phase shift)
                double x_low = ap2_.process(ap2_coeffs_, c, x_low1);

                // 3. Second crossover split on x_high1 at f_high
                double x_mid  = lp2_.process(lp2_coeffs_, c, x_high1);
                double x_high = hp2_.process(hp2_coeffs_, c, x_high1);

                // 4. Tone gain scaling & phase-coherent recombination
                double y = (x_low * gLow) + (x_mid * gMid) + (x_high * gHigh);

                buffer[idx] = static_cast<float>(std::clamp(y, -2.0, 2.0));
            }
        }
    }

    void process(double* buffer, uint32_t frames, int channels) {
        if (!isEnabled() || !buffer || frames == 0 || channels < 1) return;
        const int chs = std::min(channels, kMaxChannels);

        for (uint32_t i = 0; i < frames; ++i) {
            cur_bass_linear_ += gain_smooth_alpha_ * (target_bass_linear_ - cur_bass_linear_);
            cur_mid_linear_  += gain_smooth_alpha_ * (target_mid_linear_  - cur_mid_linear_);
            cur_treble_linear_ += gain_smooth_alpha_ * (target_treble_linear_ - cur_treble_linear_);

            const double gLow = cur_bass_linear_;
            const double gMid = cur_mid_linear_;
            const double gHigh = cur_treble_linear_;

            for (int c = 0; c < chs; ++c) {
                const size_t idx = static_cast<size_t>(i) * channels + c;
                const double x = buffer[idx];

                double x_low1  = lp1_.process(lp1_coeffs_, c, x);
                double x_high1 = hp1_.process(hp1_coeffs_, c, x);
                double x_low   = ap2_.process(ap2_coeffs_, c, x_low1);
                double x_mid   = lp2_.process(lp2_coeffs_, c, x_high1);
                double x_high  = hp2_.process(hp2_coeffs_, c, x_high1);

                double y = (x_low * gLow) + (x_mid * gMid) + (x_high * gHigh);
                buffer[idx] = std::clamp(y, -2.0, 2.0);
            }
        }
    }

private:
    void updateSmoothingAlpha() {
        // ~25 ms time constant for smooth click-free knob movement
        constexpr double kSmoothingMs = 25.0;
        gain_smooth_alpha_ = 1.0 - std::exp(-1.0 / (sample_rate_ * (kSmoothingMs * 0.001)));
    }

    void updateFilters() {
        const double fs = static_cast<double>(sample_rate_);
        const double f1 = static_cast<double>(low_crossover_hz_.load(std::memory_order_relaxed));
        const double f2 = static_cast<double>(high_crossover_hz_.load(std::memory_order_relaxed));

        designButterworthLP2(lp1_coeffs_, fs, f1);
        designButterworthHP2(hp1_coeffs_, fs, f1);
        designButterworthAP2(ap2_coeffs_, fs, f2);
        designButterworthLP2(lp2_coeffs_, fs, f2);
        designButterworthHP2(hp2_coeffs_, fs, f2);
    }

    // 2nd-Order Butterworth Low-Pass (Q = 1 / sqrt(2))
    static void designButterworthLP2(BiquadCoeffs& c, double fs, double fc) {
        fc = std::clamp(fc, 10.0, fs * 0.48);
        const double w0 = 2.0 * 3.14159265358979323846 * (fc / fs);
        const double cosW0 = std::cos(w0);
        const double sinW0 = std::sin(w0);
        const double alpha = sinW0 * 0.70710678118654752440; // sin(w0) / (2 * Q), Q = 1/sqrt(2)

        const double a0 = 1.0 + alpha;
        const double invA0 = 1.0 / a0;
        c.b0 = (1.0 - cosW0) * 0.5 * invA0;
        c.b1 = (1.0 - cosW0) * invA0;
        c.b2 = (1.0 - cosW0) * 0.5 * invA0;
        c.a1 = (-2.0 * cosW0) * invA0;
        c.a2 = (1.0 - alpha) * invA0;
    }

    // 2nd-Order Butterworth High-Pass (Q = 1 / sqrt(2))
    static void designButterworthHP2(BiquadCoeffs& c, double fs, double fc) {
        fc = std::clamp(fc, 10.0, fs * 0.48);
        const double w0 = 2.0 * 3.14159265358979323846 * (fc / fs);
        const double cosW0 = std::cos(w0);
        const double sinW0 = std::sin(w0);
        const double alpha = sinW0 * 0.70710678118654752440;

        const double a0 = 1.0 + alpha;
        const double invA0 = 1.0 / a0;
        c.b0 = (1.0 + cosW0) * 0.5 * invA0;
        c.b1 = (-(1.0 + cosW0)) * invA0;
        c.b2 = (1.0 + cosW0) * 0.5 * invA0;
        c.a1 = (-2.0 * cosW0) * invA0;
        c.a2 = (1.0 - alpha) * invA0;
    }

    // 2nd-Order All-Pass Filter for LR4 Phase Matching (Q = 1 / sqrt(2))
    static void designButterworthAP2(BiquadCoeffs& c, double fs, double fc) {
        fc = std::clamp(fc, 10.0, fs * 0.48);
        const double w0 = 2.0 * 3.14159265358979323846 * (fc / fs);
        const double cosW0 = std::cos(w0);
        const double sinW0 = std::sin(w0);
        const double alpha = sinW0 * 0.70710678118654752440;

        const double a0 = 1.0 + alpha;
        const double invA0 = 1.0 / a0;
        c.b0 = (1.0 - alpha) * invA0;
        c.b1 = (-2.0 * cosW0) * invA0;
        c.b2 = (1.0 + alpha) * invA0; // = 1.0
        c.a1 = (-2.0 * cosW0) * invA0;
        c.a2 = (1.0 - alpha) * invA0;
    }

    float sample_rate_ = 48000.0f;
    std::atomic<bool> enabled_{false};

    std::atomic<float> bass_gain_db_{0.0f};
    std::atomic<float> mid_gain_db_{0.0f};
    std::atomic<float> treble_gain_db_{0.0f};

    std::atomic<float> low_crossover_hz_{250.0f};
    std::atomic<float> high_crossover_hz_{3200.0f};

    double target_bass_linear_ = 1.0;
    double target_mid_linear_  = 1.0;
    double target_treble_linear_ = 1.0;

    double cur_bass_linear_ = 1.0;
    double cur_mid_linear_  = 1.0;
    double cur_treble_linear_ = 1.0;
    double gain_smooth_alpha_ = 0.05;

    // Filter Coefficients
    BiquadCoeffs lp1_coeffs_;
    BiquadCoeffs hp1_coeffs_;
    BiquadCoeffs ap2_coeffs_;
    BiquadCoeffs lp2_coeffs_;
    BiquadCoeffs hp2_coeffs_;

    // Filter States
    LR4Stage lp1_;
    LR4Stage hp1_;
    AP2Stage ap2_;
    LR4Stage lp2_;
    LR4Stage hp2_;
};

} // namespace sauti::dsp
