#pragma once

#include <cmath>
#include <cstdint>
#include <algorithm>
#include <vector>
#include <atomic>
#include "denormals.h"
#include "simd_math.h"
#include "cytomic_svf_dsp.h"

namespace sauti::dsp {

// =============================================================================
// StereoImagerMode: High-Fidelity Audiophile Stereo Processing Topologies
// =============================================================================
enum class StereoImagerMode {
    CleanMastering   = 0, // Pure symmetric Mid/Side expansion + sub-bass mono anchor
    Spatial3D        = 1, // Transient-gated Velvet Noise sparse decorrelation
    BlumleinShuffler = 2  // Low-frequency Gerzon/Blumlein acoustic shuffling matrix
};

// 64-Bit Direct Form I Biquad for sub-bass mono anchor filtering
struct StereoImagerBiquadDouble {
    double b0 = 1.0, b1 = 0.0, b2 = 0.0;
    double a1 = 0.0, a2 = 0.0;
    double x1 = 0.0, x2 = 0.0, y1 = 0.0, y2 = 0.0;

    void reset() {
        x1 = x2 = y1 = y2 = 0.0;
    }

    inline double process(double x) {
        const double y = b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2;
        x2 = x1; x1 = x;
        y2 = y1; y1 = (std::fabs(y) < 1.0e-25) ? 0.0 : y;
        return y1;
    }

    // 2nd-Order Butterworth Highpass (Q = 0.7071)
    void setHighpass(double fs, double fc) {
        if (fc <= 20.0 || fs <= 0.0) {
            b0 = 1.0; b1 = 0.0; b2 = 0.0;
            a1 = 0.0; a2 = 0.0;
            return;
        }
        constexpr double PI = 3.14159265358979323846;
        double w0 = 2.0 * PI * fc / fs;
        if (w0 > PI * 0.95) w0 = PI * 0.95;
        if (w0 < 1.0e-4) w0 = 1.0e-4;

        const double cos_w = std::cos(w0);
        const double sin_w = std::sin(w0);
        const double alpha = sin_w / (2.0 * 0.7071067811865475); // Q = 1/sqrt(2)

        const double a0 = 1.0 + alpha;
        b0 = (1.0 + cos_w) / (2.0 * a0);
        b1 = -(1.0 + cos_w) / a0;
        b2 = (1.0 + cos_w) / (2.0 * a0);
        a1 = (-2.0 * cos_w) / a0;
        a2 = (1.0 - alpha) / a0;
    }

    // 2nd-Order Butterworth Allpass (Q = 0.7071): exact phase match for LR4 LP + HP sum
    void setAllpass2ndOrder(double fs, double fc) {
        if (fc <= 20.0 || fs <= 0.0) {
            b0 = 1.0; b1 = 0.0; b2 = 0.0;
            a1 = 0.0; a2 = 0.0;
            return;
        }
        constexpr double PI = 3.14159265358979323846;
        double w0 = 2.0 * PI * fc / fs;
        if (w0 > PI * 0.95) w0 = PI * 0.95;
        if (w0 < 1.0e-4) w0 = 1.0e-4;

        const double cos_w = std::cos(w0);
        const double sin_w = std::sin(w0);
        const double alpha = sin_w / (2.0 * 0.7071067811865475);

        const double a0 = 1.0 + alpha;
        b0 = (1.0 - alpha) / a0;
        b1 = (-2.0 * cos_w) / a0;
        b2 = 1.0;
        a1 = (-2.0 * cos_w) / a0;
        a2 = (1.0 - alpha) / a0;
    }
};

// 64-bit Cytomic Trapezoidal SVF wrapper for filtering Side channel (air shelf, shuffler, HPF)
struct StereoImagerBiquad {
    CytomicSVF svf_;

    void reset() {
        svf_.reset();
    }

    inline float process(float x) {
        return static_cast<float>(svf_.processSample(static_cast<double>(x), 0));
    }

    inline double process(double x) {
        return svf_.processSample(x, 0);
    }

    // 2nd-Order Butterworth Highpass (Q = 0.7071)
    void setHighpass(double fs, double fc) {
        if (fc <= 20.0 || fs <= 0.0) {
            // Bypass
            svf_.setParameters(CytomicSVF::FilterType::Bell,
                               (fs > 0.0) ? fs : 48000.0, 1000.0, 0.0, 0.7071067811865475);
            return;
        }
        const double clampedFc = std::clamp(fc, 10.0, fs * 0.45);
        svf_.setParameters(CytomicSVF::FilterType::HighPass, fs, clampedFc, 0.0, 0.7071067811865475);
    }

    // 2nd-Order High-Shelf Filter with Nyquist de-cramping (64-bit Cytomic SVF)
    void setHighShelf(double fs, double fc, double gainDb) {
        if (fs <= 0.0) return;
        const double clampedFc = std::clamp(fc, 20.0, fs * 0.45);
        svf_.setParameters(CytomicSVF::FilterType::HighShelf, fs, clampedFc, gainDb, 0.7071067811865475);
    }

    // 2nd-Order Low-Shelf Filter (for Blumlein/Gerzon shuffler, 64-bit Cytomic SVF)
    void setLowShelf(double fs, double fc, double gainDb) {
        if (fs <= 0.0) return;
        const double clampedFc = std::clamp(fc, 20.0, fs * 0.45);
        svf_.setParameters(CytomicSVF::FilterType::LowShelf, fs, clampedFc, gainDb, 0.7071067811865475);
    }
};

// =============================================================================
// StereoImagerDSP: Audiophile Cleanroom Stereo Processing Suite
// =============================================================================
class StereoImagerDSP {
public:
    StereoImagerDSP() {
        setSampleRate(48000.0f);
        reset();
    }

    void setSampleRate(float sampleRate) {
        if (sampleRate <= 0.0f) sampleRate = 48000.0f;
        if (std::abs(sample_rate_ - sampleRate) < 0.1f && initialized_) return;

        sample_rate_ = sampleRate;
        sample_period_ = 1.0f / sample_rate_;

        // 35ms parameter de-zippering coefficient
        smooth_coeff_ = 1.0f - std::exp(-1.0f / (0.035f * sample_rate_));

        // Transient envelope follower (1ms attack, 25ms release)
        attack_coeff_  = 1.0f - std::exp(-1.0f / (0.001f * sample_rate_));
        release_coeff_ = 1.0f - std::exp(-1.0f / (0.025f * sample_rate_));

        // Reallocate delay buffer for Velvet Noise decorrelator (~20 ms max tap)
        const size_t maxDelaySamples = static_cast<size_t>(0.020f * sample_rate_) + 16u;
        velvet_buffer_.assign(maxDelaySamples, 0.0);
        velvet_write_ = 0;

        initVelvetTaps();
        updateFilters();
        initialized_ = true;
    }

    void setEnabled(bool enabled) {
        enabled_ = enabled;
        if (!enabled) {
            telemetry_correlation_.store(1.0f, std::memory_order_relaxed);
            telemetry_side_mid_ratio_.store(0.0f, std::memory_order_relaxed);
        }
    }

    bool isEnabled() const { return enabled_; }

    void setMode(StereoImagerMode mode) {
        if (mode_ != mode) {
            mode_ = mode;
            updateFilters();
        }
    }

    StereoImagerMode getMode() const { return mode_; }

    void setWidth(float width) {
        target_width_ = std::clamp(width, 0.0f, 3.5f);
    }

    float getWidth() const { return target_width_; }

    void setMonoBelowHz(float hz) {
        mono_below_user_set_ = true;
        float clamped = (hz <= 20.0f) ? 0.0f : std::clamp(hz, 40.0f, 400.0f);
        if (std::abs(mono_below_hz_ - clamped) > 1.0f) {
            mono_below_hz_ = clamped;
            updateFilters();
        }
    }

    float getMonoBelowHz() const { return mono_below_hz_; }

    void setAirBoostDb(float db) {
        float clamped = std::clamp(db, 0.0f, 6.0f);
        if (std::abs(air_boost_db_ - clamped) > 0.1f) {
            air_boost_db_ = clamped;
            updateFilters();
        }
    }

    float getAirBoostDb() const { return air_boost_db_; }

    void reset() {
        current_width_ = target_width_;
        transient_env_ = 0.0f;
        transient_gate_ = 1.0f;
        velvet_write_ = 0;
        std::fill(velvet_buffer_.begin(), velvet_buffer_.end(), 0.0f);
        elliptical_filter_.reset();
        elliptical_filter2_.reset();
        mid_allpass_filter_.reset();
        air_shelf_filter_.reset();
        shuffler_shelf_filter_.reset();
    }

    // Telemetry getters for live visualizer graph (lock-free)
    float getTelemetryPhaseCorrelation() const {
        return telemetry_correlation_.load(std::memory_order_relaxed);
    }

    float getTelemetrySideMidRatio() const {
        return telemetry_side_mid_ratio_.load(std::memory_order_relaxed);
    }

    // Process interleaved 32-bit float stereo samples: [L0, R0, L1, R1, ...]
    void process(float *samples, uint32_t frameCount, int channels) {
        processImpl(samples, frameCount, channels);
    }

    // Process interleaved 64-bit double stereo samples: [L0, R0, L1, R1, ...]
    void process(double *samples, uint32_t frameCount, int channels) {
        processImpl(samples, frameCount, channels);
    }

private:
    template <typename T>
    void processImpl(T *samples, uint32_t frameCount, int channels) {
        if (channels < 2 || !enabled_ || samples == nullptr || frameCount == 0) {
            return;
        }

        ScopedDenormalsDisable denormals;

        const size_t bufSize = velvet_buffer_.size();
        const bool hasVelvet = (mode_ == StereoImagerMode::Spatial3D) && (bufSize > 0);
        const bool hasShuffler = (mode_ == StereoImagerMode::BlumleinShuffler);
        const bool hasMonoAnchor = (effective_mono_hz_ > 25.0f);
        const bool hasAirShelf = (air_boost_db_ > 0.1f);

        // Check if block has any stereo difference so pure mono (L == R) remains bit-exact
        bool blockHasSide = false;
        for (uint32_t i = 0; i < frameCount; ++i) {
            const size_t idx = (size_t)i * (size_t)channels;
            if (std::fabs(static_cast<double>(samples[idx]) - static_cast<double>(samples[idx + 1])) > 1.0e-9) {
                blockHasSide = true;
                break;
            }
        }
        if (std::fabs(elliptical_filter_.y1) > 1.0e-9 || std::fabs(elliptical_filter2_.y1) > 1.0e-9) {
            blockHasSide = true;
        }

        // Telemetry energy accumulators for this processing block
        double sum_lr = 0.0;
        double sum_l2 = 0.0;
        double sum_r2 = 0.0;
        double sum_m2 = 0.0;
        double sum_s2 = 0.0;

        for (uint32_t i = 0; i < frameCount; ++i) {
            const size_t idx = (size_t)i * (size_t)channels;
            const double in_l = static_cast<double>(samples[idx]);
            const double in_r = static_cast<double>(samples[idx + 1]);

            // 1. Parameter de-zippering
            current_width_ += (target_width_ - current_width_) * smooth_coeff_;
            const double cur_w = static_cast<double>(current_width_);

            // 2. Symmetric Mid/Side decomposition
            double mid  = 0.5 * (in_l + in_r);
            double side = 0.5 * (in_l - in_r);

            // 3. Sub-Bass Mono Anchor (64-Bit Linkwitz-Riley 4th-Order Crossover on Side + Phase-Matched Allpass on Mid)
            if (hasMonoAnchor) {
                const double s_hp1 = elliptical_filter_.process(side);
                const double s_hp2 = elliptical_filter2_.process(s_hp1);
                side = s_hp2;
                const double m_ap = mid_allpass_filter_.process(mid);
                if (blockHasSide && !hasVelvet) {
                    mid = m_ap;
                }
            }

            // 4. Mode-Specific Spatialization
            if (hasVelvet) {
                // Mode 1: Transient-Gated Velvet Noise Decorrelator
                const float abs_mid = static_cast<float>(std::fabs(mid));
                if (abs_mid > transient_env_) {
                    transient_env_ += (abs_mid - transient_env_) * attack_coeff_;
                } else {
                    transient_env_ += (abs_mid - transient_env_) * release_coeff_;
                }

                // Detect sudden percussive delta
                const float delta = abs_mid - transient_env_;
                float target_gate = 1.0f;
                if (delta > 0.08f) {
                    target_gate = std::clamp(1.0f - (delta * 4.0f), 0.05f, 1.0f);
                }
                transient_gate_ += (target_gate - transient_gate_) * 0.05f;

                // Write mid to velvet delay buffer
                velvet_buffer_[velvet_write_] = mid;

                // 12-tap Velvet Noise convolution in 64-bit precision
                double decorr = 0.0;
                for (int t = 0; t < 12; ++t) {
                    int r = static_cast<int>(velvet_write_) - velvet_taps_[t];
                    if (r < 0) r += static_cast<int>(bufSize);
                    decorr += velvet_buffer_[r] * static_cast<double>(velvet_signs_[t]);
                }

                // Normalize and scale by transient gate (low comb-ripple level, only active when widening > 1.0)
                decorr *= (0.045 * static_cast<double>(transient_gate_));

                // Inject decorrelation symmetrically into the side channel when widening > 1.0
                side = (side * cur_w) + (decorr * std::clamp(cur_w - 1.0, 0.0, 1.5));

                velvet_write_++;
                if (velvet_write_ >= bufSize) velvet_write_ = 0;
            } else if (hasShuffler) {
                // Mode 2: Blumlein / Gerzon low-frequency shuffler
                side = shuffler_shelf_filter_.process(side) * cur_w;
            } else {
                // Mode 0: Clean Mastering (Pure symmetric Mid/Side expansion)
                side = side * cur_w;
            }

            // 5. High-Frequency Air Presence Contour (>8.5 kHz on Side)
            if (hasAirShelf) {
                side = air_shelf_filter_.process(side);
            }

            // 6. Recombine to Stereo L / R
            double out_l = mid + side;
            double out_r = mid - side;

            // 7. Knee-limited Soft Saturation Guard (Prevents digital overs >0.98)
            out_l = softClip(out_l);
            out_r = softClip(out_r);

            samples[idx]     = static_cast<T>(out_l);
            samples[idx + 1] = static_cast<T>(out_r);

            // Accumulate metrics
            sum_lr += out_l * out_r;
            sum_l2 += out_l * out_l;
            sum_r2 += out_r * out_r;
            sum_m2 += mid * mid;
            sum_s2 += side * side;
        }

        // Update block-averaged telemetry for UI
        if (frameCount > 0) {
            const double denom = std::sqrt(sum_l2 * sum_r2) + 1.0e-12;
            const float blockCorr = static_cast<float>(std::clamp(sum_lr / denom, -1.0, 1.0));
            const float blockRatio = static_cast<float>(std::clamp(sum_s2 / (sum_m2 + 1.0e-12), 0.0, 4.0));

            // Smoothly update atomics for UI thread
            float prevCorr = telemetry_correlation_.load(std::memory_order_relaxed);
            telemetry_correlation_.store(prevCorr + (blockCorr - prevCorr) * 0.15f, std::memory_order_relaxed);

            float prevRatio = telemetry_side_mid_ratio_.load(std::memory_order_relaxed);
            telemetry_side_mid_ratio_.store(prevRatio + (blockRatio - prevRatio) * 0.15f, std::memory_order_relaxed);
        }
    }

    float sample_rate_ = 48000.0f;
    float sample_period_ = 1.0f / 48000.0f;
    bool initialized_ = false;
    bool enabled_ = false;

    StereoImagerMode mode_ = StereoImagerMode::CleanMastering;
    float target_width_ = 1.2f;
    float current_width_ = 1.2f;
    float mono_below_hz_ = 150.0f;
    float effective_mono_hz_ = 150.0f;
    bool mono_below_user_set_ = false;
    float air_boost_db_ = 1.5f;

    float smooth_coeff_ = 0.001f;
    float attack_coeff_ = 0.02f;
    float release_coeff_ = 0.001f;
    float transient_env_ = 0.0f;
    float transient_gate_ = 1.0f;

    // Side-channel and Mid phase-compensation filters
    StereoImagerBiquadDouble elliptical_filter_;
    StereoImagerBiquadDouble elliptical_filter2_;
    StereoImagerBiquadDouble mid_allpass_filter_;
    StereoImagerBiquad air_shelf_filter_;
    StereoImagerBiquad shuffler_shelf_filter_;

    // Velvet Noise Decorrelator states (64-bit precision)
    std::vector<double> velvet_buffer_;
    size_t velvet_write_ = 0;
    int velvet_taps_[12] = {0};
    float velvet_signs_[12] = {0.0f};

    // Lock-free telemetry metrics
    std::atomic<float> telemetry_correlation_{1.0f};
    std::atomic<float> telemetry_side_mid_ratio_{0.2f};

    void initVelvetTaps() {
        // 12 pseudo-random non-uniform prime/irrational delay taps between 1.2ms and 13.5ms
        const float ms[12] = {
            1.31f, 2.17f, 3.49f, 4.23f, 5.87f, 6.71f,
            7.93f, 9.11f, 10.49f, 11.63f, 12.89f, 13.73f
        };
        // Alternating signs with zero DC bias: 6 positive, 6 negative
        const float signs[12] = {
            1.0f, -1.0f, -1.0f, 1.0f, -1.0f, 1.0f,
            1.0f, -1.0f, 1.0f, -1.0f, -1.0f, 1.0f
        };

        for (int i = 0; i < 12; ++i) {
            velvet_taps_[i] = std::max(1, static_cast<int>(ms[i] * 0.001f * sample_rate_));
            velvet_signs_[i] = signs[i];
        }
    }

    void updateFilters() {
        // 1. Mono Bass Anchor (4th-order Linkwitz-Riley HPF on Side + Phase-Matched Allpass on Mid)
        // In BlumleinShuffler mode, bypass the default 150 Hz anchor unless explicitly requested by user,
        // so the +4 dB low-frequency shuffler boost (<650 Hz) is not canceled by the 150 Hz cut.
        effective_mono_hz_ = (mode_ == StereoImagerMode::BlumleinShuffler && !mono_below_user_set_)
                                 ? 0.0f
                                 : mono_below_hz_;
        elliptical_filter_.setHighpass(sample_rate_, effective_mono_hz_);
        elliptical_filter2_.setHighpass(sample_rate_, effective_mono_hz_);
        mid_allpass_filter_.setAllpass2ndOrder(sample_rate_, effective_mono_hz_);

        // 2. High-Frequency Air Shelf (>8.5 kHz on Side)
        air_shelf_filter_.setHighShelf(sample_rate_, 8500.0, air_boost_db_);

        // 3. Blumlein Shuffler (+4 dB low-shelf below 650 Hz on Side)
        shuffler_shelf_filter_.setLowShelf(sample_rate_, 650.0, 4.0);
    }

    inline double softClip(double x) {
        if (x > 0.935) {
            return 0.935 + 0.050 * std::tanh((x - 0.935) / 0.050);
        } else if (x < -0.935) {
            return -0.935 + 0.050 * std::tanh((x + 0.935) / 0.050);
        }
        return x;
    }
};

} // namespace sauti::dsp
