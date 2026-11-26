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
    CleanMastering   = 0, // Pure symmetric Mid/Side expansion + LR4 mono-bass anchor
    Spatial3D        = 1, // Zero-ripple Hilbert quadrature + delay-scaled Velvet + transient gate
    BlumleinShuffler = 2  // Band-limited Gerzon (1986) complementary acoustic shuffler
};

// 4-stage Olli Niemitalo Hilbert Quadrature Pair (64-bit double precision)
// Provides +/- 0.7 deg 90-degree phase shift across 40 Hz..18 kHz with 0.00 dB magnitude ripple
struct ImagerHilbert4 {
    struct Section2 {
        double k = 0.0;
        double x1 = 0.0, x2 = 0.0;
        double y1 = 0.0, y2 = 0.0;

        void reset() { x1 = x2 = y1 = y2 = 0.0; }

        inline double process(double x)
        {
            double y = k * (x + y2) - x2;
            if (std::fabs(y) < 1.0e-25) y = 0.0;
            x2 = x1;
            x1 = x;
            y2 = y1;
            y1 = y;
            return y;
        }
    };

    Section2 branch_a[4];
    Section2 branch_b[4];
    double delay_a = 0.0;

    ImagerHilbert4()
    {
        constexpr double a_c[4] = {
            0.6923878, 0.9360654322959, 0.9882295226860, 0.9987488452737
        };
        constexpr double b_c[4] = {
            0.4021921162426, 0.8561710882420, 0.9722909545651, 0.9952884791278
        };
        for (int i = 0; i < 4; ++i) {
            branch_a[i].k = a_c[i] * a_c[i];
            branch_b[i].k = b_c[i] * b_c[i];
        }
        reset();
    }

    void reset()
    {
        for (int i = 0; i < 4; ++i) {
            branch_a[i].reset();
            branch_b[i].reset();
        }
        delay_a = 0.0;
    }

    inline void processPair(double x, double &out_a, double &out_b)
    {
        double a = delay_a;
        delay_a = x;
        double b = x;
        for (int i = 0; i < 4; ++i) {
            a = branch_a[i].process(a);
            b = branch_b[i].process(b);
        }
        // out_a and out_b have identical allpass magnitude and maintain +90 deg phase separation
        out_a = a;
        out_b = b;
    }

    inline double processInPhase(double x)
    {
        double a = delay_a;
        delay_a = x;
        for (int i = 0; i < 4; ++i) {
            a = branch_a[i].process(a);
        }
        return a;
    }
};

// =============================================================================
// StereoImagerDSP: Audiophile Cleanroom Stereo Processing Suite
// =============================================================================
class StereoImagerDSP {
public:
    static constexpr int kVelvetTaps = 24;

    StereoImagerDSP() {
        setSampleRate(48000.0f);
        reset();
    }

    void setSampleRate(float sampleRate) {
        if (sampleRate <= 0.0f) sampleRate = 48000.0f;
        if (std::abs(sample_rate_ - sampleRate) < 0.1f && initialized_) return;

        sample_rate_ = sampleRate;
        sample_period_ = 1.0f / sample_rate_;

        // Sample-rate-invariant smoothing and envelope constants
        smooth_coeff_  = 1.0f - std::exp(-1.0f / (0.035f * sample_rate_));
        fast_coeff_    = 1.0 - std::exp(-1.0 / (0.0015 * static_cast<double>(sample_rate_)));
        slow_coeff_    = 1.0 - std::exp(-1.0 / (0.0350 * static_cast<double>(sample_rate_)));
        gate_coeff_    = 1.0 - std::exp(-1.0 / (0.0080 * static_cast<double>(sample_rate_)));
        power_coeff_   = 1.0 - std::exp(-1.0 / (0.0800 * static_cast<double>(sample_rate_)));

        // Reallocate delay buffer for Velvet Noise decorrelator (40 ms covers 30 ms max span)
        const size_t maxDelaySamples = static_cast<size_t>(0.040f * sample_rate_) + 16u;
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
        float clamped = (hz <= 20.0f) ? 0.0f : std::clamp(hz, 21.0f, 400.0f);
        if (std::abs(mono_below_hz_ - clamped) > 0.5f) {
            mono_below_hz_ = clamped;
            updateFilters();
        }
    }

    float getMonoBelowHz() const { return mono_below_hz_; }

    void setAirBoostDb(float db) {
        float clamped = std::clamp(db, 0.0f, 6.0f);
        if (std::abs(air_boost_db_ - clamped) > 0.05f) {
            air_boost_db_ = clamped;
            updateFilters();
        }
    }

    float getAirBoostDb() const { return air_boost_db_; }

    void setDelayMs(float ms) {
        float clamped = std::clamp(ms, 5.0f, 30.0f);
        if (std::abs(delay_ms_ - clamped) > 0.05f) {
            delay_ms_ = clamped;
            initVelvetTaps();
        }
    }

    float getDelayMs() const { return delay_ms_; }

    void reset() {
        current_width_ = target_width_;
        last_shuf_width_ = -1.0;
        fast_env_ = 0.0;
        slow_env_ = 0.0;
        transient_gate_ = 1.0;
        env_base_e_ = 0.0;
        env_proc_e_ = 0.0;
        velvet_write_ = 0;
        std::fill(velvet_buffer_.begin(), velvet_buffer_.end(), 0.0);

        elliptical_hp1_.reset();
        elliptical_hp2_.reset();
        mid_allpass_.reset();
        decorr_hp1_.reset();
        decorr_hp2_.reset();
        decorr_lp_.reset();
        decorr_lp2_.reset();
        spatial_ap_hp_.reset();
        spatial_ap_lp_.reset();
        hilbert_.reset();
        hilbert_side_.reset();
        air_shelf_filter_.reset();
        shuffler_side_shelf_.reset();
        shuffler_mid_shelf_.reset();
        shuffler_sub_hp_.reset();
        updateShufflerShelves(static_cast<double>(current_width_));
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
        const bool hasMonoAnchor = (mono_below_hz_ > 20.0f);
        const bool hasAirShelf = (air_boost_db_ > 0.05f);
        const double velvet_norm_scale = 1.0 / std::sqrt(static_cast<double>(kVelvetTaps));

        // Telemetry energy accumulators for this processing block
        double sum_lr = 0.0;
        double sum_l2 = 0.0;
        double sum_r2 = 0.0;
        double sum_m2 = 0.0;
        double sum_s2 = 0.0;

        for (uint32_t i = 0; i < frameCount; ++i) {
            const size_t idx = static_cast<size_t>(i) * static_cast<size_t>(channels);
            const double in_l = static_cast<double>(samples[idx]);
            const double in_r = static_cast<double>(samples[idx + 1]);

            // 1. Parameter de-zippering
            current_width_ += (target_width_ - current_width_) * smooth_coeff_;
            const double cur_w = static_cast<double>(current_width_);

            // 2. Symmetric Mid/Side decomposition
            double mid  = 0.5 * (in_l + in_r);
            double side = 0.5 * (in_l - in_r);

            // 3. Sub-Bass Mono Anchor (64-bit Cytomic LR4 HPF on Side + Phase-Matched Allpass on Mid)
            // Applied unconditionally across ALL modes to eliminate phase-jump clicks and L/R inversions
            if (hasMonoAnchor) {
                side = elliptical_hp2_.processSample(elliptical_hp1_.processSample(side, 0), 0);
                mid  = mid_allpass_.processSample(mid, 0);
            }

            const double mid_base  = mid;
            const double side_base = side;

            // 4. Mode-Specific Spatialization
            if (hasVelvet) {
                // Mode 1: Spatial 3D
                // Match Mid & Side phase to Hilbert branch_a and LR4 250..9000 Hz band-limits
                double mid_i = 0.0, mid_q = 0.0;
                hilbert_.processPair(mid, mid_i, mid_q);
                const double side_i = hilbert_side_.processInPhase(side);

                mid  = spatial_ap_lp_.processSample(spatial_ap_hp_.processSample(mid_i, 0), 0);
                side = spatial_ap_lp_.processSample(spatial_ap_hp_.processSample(side_i, 1), 1);

                // Band-limit quadrature branch (LR4 HPF >=250 Hz, LR4 LPF 9 kHz)
                double q_bp = decorr_hp2_.processSample(decorr_hp1_.processSample(mid_q, 0), 0);
                q_bp = decorr_lp2_.processSample(decorr_lp_.processSample(q_bp, 0), 0);

                // Level-independent & SR-invariant transient gate (fast/slow envelope ratio)
                const double abs_bp = std::fabs(q_bp);
                fast_env_ += (abs_bp - fast_env_) * fast_coeff_;
                slow_env_ += (abs_bp - slow_env_) * slow_coeff_;
                if (fast_env_ < 1.0e-25) fast_env_ = 0.0;
                if (slow_env_ < 1.0e-25) slow_env_ = 0.0;

                const double ratio = fast_env_ / (slow_env_ + 1.0e-5);
                double target_gate = 1.0;
                if (ratio > 1.8) {
                    target_gate = std::clamp(1.0 - 0.55 * (ratio - 1.8), 0.15, 1.0);
                }
                transient_gate_ += (target_gate - transient_gate_) * gate_coeff_;

                // Subtle delay_ms-scaled 24-tap RMS-normalized Velvet ambience
                velvet_buffer_[velvet_write_] = q_bp;
                double velvet_sum = 0.0;
                for (int t = 0; t < kVelvetTaps; ++t) {
                    int r = static_cast<int>(velvet_write_) - velvet_taps_[t];
                    if (r < 0) r += static_cast<int>(bufSize);
                    velvet_sum += velvet_buffer_[r] * static_cast<double>(velvet_signs_[t]);
                }
                const double velvet_norm = velvet_sum * velvet_norm_scale;
                velvet_write_++;
                if (velvet_write_ >= bufSize) velvet_write_ = 0;

                const double decorr_amt = (cur_w <= 0.5) ? 0.0 : std::clamp((cur_w - 0.5) * 0.45, 0.0, 0.70);
                const double decorr_sig = (0.28 * q_bp + 0.05 * velvet_norm) * transient_gate_ * decorr_amt;

                // Pure Side injection -> 100% mono-sum cancellation (0.5*(L+R) == mid)
                side = (side * cur_w) + decorr_sig;
            } else if (hasShuffler) {
                // Mode 2: True Gerzon (1986) Band-Limited Complementary Blumlein Shuffler
                if (std::fabs(cur_w - last_shuf_width_) > 0.002) {
                    updateShufflerShelves(cur_w);
                }
                const double shuf_delta = shuffler_side_shelf_.processSample(side, 0) - side;
                // Sub-bass protection on boosted delta (<75 Hz) even if user sets Mono Bass = Off
                const double side_shuf = side + shuffler_sub_hp_.processSample(shuf_delta, 0);
                mid  = shuffler_mid_shelf_.processSample(mid, 0);
                side = side_shuf * cur_w;
            } else {
                // Mode 0: Clean Mastering (Pure symmetric Mid/Side expansion)
                side = side * cur_w;
            }

            // 5. Smooth Adaptive RMS Power Compensation (all modes when widening > 1.0)
            {
                const double e_base = mid_base * mid_base + side_base * side_base;
                const double e_proc = mid * mid + side * side;
                env_base_e_ += (e_base - env_base_e_) * power_coeff_;
                env_proc_e_ += (e_proc - env_proc_e_) * power_coeff_;
                if (env_base_e_ < 1.0e-25) env_base_e_ = 0.0;
                if (env_proc_e_ < 1.0e-25) env_proc_e_ = 0.0;

                if (cur_w > 1.0) {
                    const double power_norm = std::clamp(
                        std::sqrt((env_base_e_ + 1.0e-12) / (env_proc_e_ + 1.0e-12)),
                        0.55,
                        1.0
                    );
                    const double comp_blend = std::clamp((cur_w - 1.0) / 0.05, 0.0, 1.0);
                    const double eff_norm = 1.0 + comp_blend * (power_norm - 1.0);
                    mid  *= eff_norm;
                    side *= eff_norm;
                }
            }

            // 6. High-Frequency Air Presence Contour (>8.5 kHz on Side)
            if (hasAirShelf) {
                side = air_shelf_filter_.processSample(side, 0);
            }

            // 7. Recombine to Stereo L / R
            double out_l = mid + side;
            double out_r = mid - side;

            // 8. High-Headroom Soft Safety Guard (bit-exact passthrough up to 0.99 / -0.087 dBFS)
            out_l = softClip(out_l);
            out_r = softClip(out_r);

            samples[idx]     = static_cast<T>(out_l);
            samples[idx + 1] = static_cast<T>(out_r);

            // Accumulate telemetry metrics
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
    float mono_below_hz_ = 120.0f;
    float air_boost_db_ = 0.0f;
    float delay_ms_ = 15.0f;

    float smooth_coeff_ = 0.001f;
    double fast_coeff_ = 0.014;
    double slow_coeff_ = 0.0006;
    double gate_coeff_ = 0.0026;
    double power_coeff_ = 0.00026;

    double fast_env_ = 0.0;
    double slow_env_ = 0.0;
    double transient_gate_ = 1.0;
    double env_base_e_ = 0.0;
    double env_proc_e_ = 0.0;
    double last_shuf_width_ = -1.0;

    // 64-bit Cytomic SVF crossovers, phase compensation, air shelf & Gerzon shuffler
    CytomicSVF elliptical_hp1_;
    CytomicSVF elliptical_hp2_;
    CytomicSVF mid_allpass_;
    CytomicSVF decorr_hp1_;
    CytomicSVF decorr_hp2_;
    CytomicSVF decorr_lp_;
    CytomicSVF decorr_lp2_;
    CytomicSVF spatial_ap_hp_;
    CytomicSVF spatial_ap_lp_;
    CytomicSVF air_shelf_filter_;
    CytomicSVF shuffler_side_shelf_;
    CytomicSVF shuffler_mid_shelf_;
    CytomicSVF shuffler_sub_hp_;

    ImagerHilbert4 hilbert_;
    ImagerHilbert4 hilbert_side_;

    // Velvet Noise Decorrelator states (24 stratified taps spanning 1.2 ms .. delay_ms_)
    std::vector<double> velvet_buffer_;
    size_t velvet_write_ = 0;
    int velvet_taps_[kVelvetTaps] = {0};
    float velvet_signs_[kVelvetTaps] = {0.0f};

    // Lock-free telemetry metrics
    std::atomic<float> telemetry_correlation_{1.0f};
    std::atomic<float> telemetry_side_mid_ratio_{0.2f};

    void initVelvetTaps() {
        constexpr double kJitter[kVelvetTaps] = {
            0.31, 0.72, 0.19, 0.58, 0.83, 0.27, 0.64, 0.42,
            0.79, 0.21, 0.53, 0.68, 0.16, 0.74, 0.39, 0.84,
            0.29, 0.61, 0.47, 0.77, 0.23, 0.56, 0.81, 0.35
        };
        constexpr float kSigns[kVelvetTaps] = {
             1.0f, -1.0f, -1.0f,  1.0f, -1.0f,  1.0f,  1.0f, -1.0f,
             1.0f, -1.0f, -1.0f,  1.0f, -1.0f,  1.0f,  1.0f, -1.0f,
            -1.0f,  1.0f,  1.0f, -1.0f,  1.0f, -1.0f, -1.0f,  1.0f
        };

        const double min_ms = 1.2;
        const double span_ms = std::max(3.8, static_cast<double>(delay_ms_) - min_ms);
        const double step_ms = span_ms / static_cast<double>(kVelvetTaps);
        const int max_tap = std::max(1, static_cast<int>(velvet_buffer_.size()) - 2);

        for (int i = 0; i < kVelvetTaps; ++i) {
            const double tap_ms = min_ms + (static_cast<double>(i) + kJitter[i]) * step_ms;
            const int tap_smp = std::clamp(static_cast<int>(tap_ms * 0.001 * static_cast<double>(sample_rate_)), 1, max_tap);
            velvet_taps_[i] = tap_smp;
            velvet_signs_[i] = kSigns[i];
        }
    }

    void updateShufflerShelves(double cur_w) {
        const double fs = static_cast<double>(sample_rate_);
        const double shuf_db = (cur_w <= 1.0)
                                   ? (1.5 * std::max(0.0, cur_w))
                                   : (1.5 + 3.0 * std::clamp(cur_w - 1.0, 0.0, 1.0));
        shuffler_side_shelf_.setParameters(CytomicSVF::FilterType::LowShelf, fs, 600.0, shuf_db, 0.55);
        shuffler_mid_shelf_.setParameters(CytomicSVF::FilterType::LowShelf, fs, 600.0, -0.35 * shuf_db, 0.55);
        last_shuf_width_ = cur_w;
    }

    void updateFilters() {
        const double fs = static_cast<double>(sample_rate_);
        constexpr double Q_BW = 0.7071067811865475;

        // 1. Mono Bass Anchor (64-bit Cytomic LR4 HPF on Side + Phase-Matched 2nd-order Allpass on Mid)
        if (mono_below_hz_ > 20.0f) {
            const double fc = static_cast<double>(mono_below_hz_);
            elliptical_hp1_.setParameters(CytomicSVF::FilterType::HighPass, fs, fc, 0.0, Q_BW);
            elliptical_hp2_.setParameters(CytomicSVF::FilterType::HighPass, fs, fc, 0.0, Q_BW);
            mid_allpass_.setParameters(CytomicSVF::FilterType::AllPass, fs, fc, 0.0, Q_BW);
        }

        // 2. Spatial 3D Decorrelator Band-Limiting (LR4 HPF >=250 Hz, LR4 LPF 9 kHz) + Phase-Matched Allpasses
        const double decorr_hp_hz = std::min(std::max(250.0, static_cast<double>(mono_below_hz_)), fs * 0.42);
        const double decorr_lp_hz = std::min(9000.0, fs * 0.42);
        decorr_hp1_.setParameters(CytomicSVF::FilterType::HighPass, fs, decorr_hp_hz, 0.0, Q_BW);
        decorr_hp2_.setParameters(CytomicSVF::FilterType::HighPass, fs, decorr_hp_hz, 0.0, Q_BW);
        decorr_lp_.setParameters(CytomicSVF::FilterType::LowPass, fs, decorr_lp_hz, 0.0, Q_BW);
        decorr_lp2_.setParameters(CytomicSVF::FilterType::LowPass, fs, decorr_lp_hz, 0.0, Q_BW);
        spatial_ap_hp_.setParameters(CytomicSVF::FilterType::AllPass, fs, decorr_hp_hz, 0.0, Q_BW);
        spatial_ap_lp_.setParameters(CytomicSVF::FilterType::AllPass, fs, decorr_lp_hz, 0.0, Q_BW);

        // 3. High-Frequency Air Shelf (>8.5 kHz on Side)
        air_shelf_filter_.setParameters(CytomicSVF::FilterType::HighShelf, fs, 8500.0, static_cast<double>(air_boost_db_), Q_BW);

        // 4. Blumlein Sub-bass Delta Guard (<75 Hz) & Complementary Shelves
        shuffler_sub_hp_.setParameters(CytomicSVF::FilterType::HighPass, fs, 75.0, 0.0, Q_BW);
        updateShufflerShelves(static_cast<double>(current_width_));
    }

    inline double softClip(double x) {
        // Bit-exact linear passthrough up to 0.99 (-0.087 dBFS); smooth C1 guard only near 0 dBFS
        if (x > 0.99) {
            return 0.99 + 0.009 * std::tanh((x - 0.99) / 0.009);
        } else if (x < -0.99) {
            return -0.99 + 0.009 * std::tanh((x + 0.99) / 0.009);
        }
        return x;
    }
};

} // namespace sauti::dsp
