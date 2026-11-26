#pragma once

#include <cmath>
#include <cstdint>
#include <algorithm>
#include <atomic>
#include <vector>
#include "denormals.h"
#include "simd_math.h"
#include "cytomic_svf_dsp.h"

namespace sauti::dsp {

enum class DeEsserMode {
    SplitBand = 0, // Dynamic High-Shelf compression on the 4–9 kHz sibilance band
    WideBand = 1   // Sibilance detection ducks wideband signal (classic analog opto-style)
};

enum class DeEsserPreset {
    GentleVocal = 0,        // SplitBand, 5500 Hz, -24 dB, 3.5:1, 8 dB max reduction, 1.5ms attack, 40ms release
    AggressiveSibilance = 1, // SplitBand, 6000 Hz, -30 dB, 6.0:1, 16 dB max reduction, 0.8ms attack, 30ms release
    VintageWideband = 2,    // WideBand, 5000 Hz, -22 dB, 4.0:1, 10 dB max reduction, 2.0ms attack, 50ms release
    PodcastSpeech = 3,      // SplitBand, 4500 Hz, -26 dB, 5.0:1, 14 dB max reduction, 1.0ms attack, 35ms release
    Custom = 4
};

// =============================================================================
// DeEsserDSP: High-Fidelity Clean-Room Split-Band & Wideband De-Esser
//
// Features:
// - Dynamic High-Shelf & WideBand modes for transparent sibilance attenuation.
// - 0 dB flat identity pass when inactive (zero phase distortion, zero ripple).
// - Dedicated high-pass / sibilance sidechain with ultra-fast attack (~1ms) and
//   smooth release (~35ms) envelope detection.
// - Soft-knee dynamic compression curve with configurable threshold, ratio,
//   and maximum gain-reduction range limit (prevents lisping/dulling).
// - De-zippered parameter smoothing and real-time gain reduction reporting.
// - Allocation-free realtime process loop.
// =============================================================================
class DeEsserDSP {
public:
    DeEsserDSP() {
        setSampleRate(48000.0f);
        reset();
    }

    void setSampleRate(float sampleRate) {
        if (sampleRate <= 0.0f) sampleRate = 48000.0f;
        if (initialized_ && std::abs(sample_rate_ - sampleRate) < 0.1f) return;
        sample_rate_ = sampleRate;
        sample_period_ = 1.0f / sample_rate_;
        smoothing_coeff_ = 1.0f - std::exp(-1.0f / (0.030f * sample_rate_)); // 30ms parameter smoothing
        updateSidechainFilter();
        updateTimeConstants();
        updateShelfCoeffs(0.0f);
        initialized_ = true;
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

    void setMode(DeEsserMode mode) {
        if (mode_ != mode) {
            mode_ = mode;
            anti_pop_ = 0.0f;
        }
    }

    DeEsserMode getMode() const { return mode_; }

    void setPreset(DeEsserPreset preset) {
        preset_ = preset;
        if (preset == DeEsserPreset::Custom) return;
        use_macro_intensity_ = false;
        switch (preset) {
            case DeEsserPreset::GentleVocal:
                mode_ = DeEsserMode::SplitBand;
                frequency_hz_ = 5500.0f;
                target_threshold_db_ = -24.0f;
                ratio_ = 3.5f;
                max_reduction_db_ = 8.0f;
                attack_ms_ = 1.5f;
                release_ms_ = 40.0f;
                break;
            case DeEsserPreset::AggressiveSibilance:
                mode_ = DeEsserMode::SplitBand;
                frequency_hz_ = 6000.0f;
                target_threshold_db_ = -30.0f;
                ratio_ = 6.0f;
                max_reduction_db_ = 16.0f;
                attack_ms_ = 0.8f;
                release_ms_ = 30.0f;
                break;
            case DeEsserPreset::VintageWideband:
                mode_ = DeEsserMode::WideBand;
                frequency_hz_ = 5000.0f;
                target_threshold_db_ = -22.0f;
                ratio_ = 4.0f;
                max_reduction_db_ = 10.0f;
                attack_ms_ = 2.0f;
                release_ms_ = 50.0f;
                break;
            case DeEsserPreset::PodcastSpeech:
                mode_ = DeEsserMode::SplitBand;
                frequency_hz_ = 4500.0f;
                target_threshold_db_ = -26.0f;
                ratio_ = 5.0f;
                max_reduction_db_ = 14.0f;
                attack_ms_ = 1.0f;
                release_ms_ = 35.0f;
                break;
            case DeEsserPreset::Custom:
                break;
        }
        current_threshold_db_ = target_threshold_db_;
        updateSidechainFilter();
        updateTimeConstants();
        updateShelfCoeffs(0.0f);
    }

    DeEsserPreset getPreset() const { return preset_; }

    // Macro intensity in range [0.0, 1.0]
    void setIntensity(float intensity) {
        target_intensity_ = std::clamp(intensity, 0.0f, 1.0f);
        use_macro_intensity_ = true;
        updateMacroParameters(target_intensity_);
    }

    float getIntensity() const { return target_intensity_; }

    // Detailed Parameters:
    void setFrequencyHz(float freqHz) {
        preset_ = DeEsserPreset::Custom;
        frequency_hz_ = std::clamp(freqHz, 2000.0f, 12000.0f);
        updateSidechainFilter();
        updateShelfCoeffs(-current_gr_db_, true);
    }

    float getFrequencyHz() const { return frequency_hz_; }

    void setThresholdDb(float thresholdDb) {
        preset_ = DeEsserPreset::Custom;
        use_macro_intensity_ = false;
        target_threshold_db_ = std::clamp(thresholdDb, -60.0f, 0.0f);
    }

    float getThresholdDb() const { return target_threshold_db_; }

    void setRatio(float ratio) {
        preset_ = DeEsserPreset::Custom;
        use_macro_intensity_ = false;
        ratio_ = std::clamp(ratio, 1.0f, 20.0f);
    }

    float getRatio() const { return ratio_; }

    void setMaxReductionDb(float maxReductionDb) {
        preset_ = DeEsserPreset::Custom;
        use_macro_intensity_ = false;
        max_reduction_db_ = std::clamp(maxReductionDb, 0.0f, 30.0f);
    }

    float getMaxReductionDb() const { return max_reduction_db_; }

    void setAttackMs(float attackMs) {
        preset_ = DeEsserPreset::Custom;
        attack_ms_ = std::clamp(attackMs, 0.1f, 50.0f);
        updateTimeConstants();
    }

    float getAttackMs() const { return attack_ms_; }

    void setReleaseMs(float releaseMs) {
        preset_ = DeEsserPreset::Custom;
        release_ms_ = std::clamp(releaseMs, 5.0f, 500.0f);
        updateTimeConstants();
    }

    float getReleaseMs() const { return release_ms_; }

    // C^1-Continuous Soft-Knee Gain Reduction Function
    static inline float computeKneeGainReduction(float env_db, float threshold_db, float ratio, float max_reduction_db, float knee_db = 4.0f) {
        const float diff = env_db - threshold_db;
        const float half_knee = knee_db * 0.5f;
        if (diff > half_knee) {
            float gr_db = diff * (1.0f - 1.0f / ratio);
            return std::min(gr_db, max_reduction_db);
        } else if (diff > -half_knee) {
            float knee_factor = diff + half_knee;
            float gr_db = (1.0f - 1.0f / ratio) * (knee_factor * knee_factor) / (2.0f * knee_db);
            return std::min(gr_db, max_reduction_db);
        }
        return 0.0f;
    }

    void reset() {
        // Reset dynamic shelf 64-bit Cytomic SVF state
        shelf_svf_.reset();

        // Reset Sidechain HPF + LPF states
        sc_x1_ = SimdDouble2(0.0);
        sc_x2_ = SimdDouble2(0.0);
        sc_y1_ = SimdDouble2(0.0);
        sc_y2_ = SimdDouble2(0.0);
        sc_lp_x1_ = SimdDouble2(0.0);
        sc_lp_x2_ = SimdDouble2(0.0);
        sc_lp_y1_ = SimdDouble2(0.0);
        sc_lp_y2_ = SimdDouble2(0.0);

        env_l_ = 0.0f;
        env_r_ = 0.0f;
        current_gr_db_ = 0.0f;
        gr_telemetry_.store(0.0f, std::memory_order_relaxed);
        current_intensity_ = target_intensity_;
        current_threshold_db_ = target_threshold_db_;
        knee_start_lin_ = std::pow(10.0f, (current_threshold_db_ - 2.0f) / 20.0f);
        prev_thresh_for_lin_ = current_threshold_db_;
        anti_pop_ = 0.0f;
        prev_shelf_gain_db_ = 999.0f;
        updateShelfCoeffs(0.0f, true);
        shelf_b0_ = tgt_shelf_b0_;
    }

    // Active interpolated and target high-shelf coefficients (for verification/telemetry)
    float getActiveShelfB0() const { return shelf_b0_; }
    float getTargetShelfB0() const { return tgt_shelf_b0_; }
    float getPrevShelfGainDb() const { return prev_shelf_gain_db_; }

    // Real-time gain reduction in dB for meters / UI (lock-free atomic read)
    float getGainReductionDb() const {
        return gr_telemetry_.load(std::memory_order_relaxed);
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
    template <typename T>
    void processImpl(T* interleaved_samples, uint32_t frame_count) {
        if (!enabled_ || frame_count == 0 || !interleaved_samples) return;
        ScopedDenormalsDisable denormalGuard;

        const SimdDouble2 v_sc_b0(sc_b0_);
        const SimdDouble2 v_sc_b1(sc_b1_);
        const SimdDouble2 v_sc_b2(sc_b2_);
        const SimdDouble2 v_sc_a1(sc_a1_);
        const SimdDouble2 v_sc_a2(sc_a2_);

        const SimdDouble2 v_lp_b0(sc_lp_b0_);
        const SimdDouble2 v_lp_b1(sc_lp_b1_);
        const SimdDouble2 v_lp_b2(sc_lp_b2_);
        const SimdDouble2 v_lp_a1(sc_lp_a1_);
        const SimdDouble2 v_lp_a2(sc_lp_a2_);

        for (uint32_t i = 0; i < frame_count; i++) {
            // Smooth macro intensity and threshold parameters
            current_intensity_    += smoothing_coeff_ * (target_intensity_ - current_intensity_);
            current_threshold_db_ += smoothing_coeff_ * (target_threshold_db_ - current_threshold_db_);

            if (use_macro_intensity_) {
                updateMacroParameters(current_intensity_);
                current_threshold_db_ = target_threshold_db_;
            }

            if (std::abs(current_threshold_db_ - prev_thresh_for_lin_) > 0.05f) {
                knee_start_lin_ = std::pow(10.0f, (current_threshold_db_ - 2.0f) / 20.0f);
                prev_thresh_for_lin_ = current_threshold_db_;
            }

            const double in_l = static_cast<double>(interleaved_samples[2 * i]);
            const double in_r = static_cast<double>(interleaved_samples[2 * i + 1]);

            // 1. Sidechain Bandpass Filter (2nd-order HPF -> 2nd-order LPF in 64-bit SimdDouble2)
            //    Rejects vocal fundamentals below fc AND ultrasonic cymbal/air energy above 11 kHz.
            const SimdDouble2 v_sc_in(in_l, in_r);
            const SimdDouble2 hp_y = (v_sc_b0 * v_sc_in) + (v_sc_b1 * sc_x1_) + (v_sc_b2 * sc_x2_)
                                   - (v_sc_a1 * sc_y1_) - (v_sc_a2 * sc_y2_);
            sc_x2_ = sc_x1_; sc_x1_ = v_sc_in;
            sc_y2_ = sc_y1_; sc_y1_ = hp_y;

            const SimdDouble2 sc_y = (v_lp_b0 * hp_y) + (v_lp_b1 * sc_lp_x1_) + (v_lp_b2 * sc_lp_x2_)
                                   - (v_lp_a1 * sc_lp_y1_) - (v_lp_a2 * sc_lp_y2_);
            sc_lp_x2_ = sc_lp_x1_; sc_lp_x1_ = hp_y;
            sc_lp_y2_ = sc_lp_y1_; sc_lp_y1_ = sc_y;

            const float sc_l = static_cast<float>(sc_y.get_low());
            const float sc_r = static_cast<float>(sc_y.get_high());

            // 2. Sidechain Envelope Detection (Attack / Release ballistics)
            float sc_abs_l = std::abs(sc_l);
            float sc_abs_r = std::abs(sc_r);

            if (sc_abs_l > env_l_) {
                env_l_ += attack_coeff_ * (sc_abs_l - env_l_);
            } else {
                env_l_ += release_coeff_ * (sc_abs_l - env_l_);
            }

            if (sc_abs_r > env_r_) {
                env_r_ += attack_coeff_ * (sc_abs_r - env_r_);
            } else {
                env_r_ += release_coeff_ * (sc_abs_r - env_r_);
            }

            // Coupled stereo detector peak
            float env_peak = std::max(env_l_, env_r_);

            // 3. Compute Target Gain Reduction with 4 dB Soft Knee (skip log10 below knee)
            float target_gr_db = 0.0f;
            if (env_peak > std::max(1e-5f, knee_start_lin_)) {
                const float env_db = 20.0f * std::log10(env_peak);
                target_gr_db = computeKneeGainReduction(env_db, current_threshold_db_, ratio_, max_reduction_db_);
            }

            // Fast 0.25 ms anti-zipper smoother (preserves true attack_ms_ / release_ms_ without 1.5x lag)
            current_gr_db_ += gr_anti_zipper_coeff_ * (target_gr_db - current_gr_db_);
            if (current_gr_db_ < 1e-4f && target_gr_db == 0.0f) {
                current_gr_db_ = 0.0f;
            }

            double out_l = in_l;
            double out_r = in_r;

            // 4. Output Processing based on Mode
            if (mode_ == DeEsserMode::SplitBand) {
                // 64-bit Cytomic TPT SVF dynamic HighShelf updated smoothly at control rate
                if ((i & 7u) == 0u || i + 1 == frame_count) {
                    updateShelfCoeffs(-current_gr_db_);
                    shelf_b0_ = tgt_shelf_b0_;
                }

                out_l = shelf_svf_.processSample(in_l, 0);
                out_r = shelf_svf_.processSample(in_r, 1);
            } else {
                // WideBand Mode: Direct linear attenuation (skip pow when idle)
                if (current_gr_db_ >= 0.005f) {
                    const double lin_gain = std::pow(10.0, static_cast<double>(-current_gr_db_) / 20.0);
                    out_l = in_l * lin_gain;
                    out_r = in_r * lin_gain;
                }
            }

            // Anti-pop crossfade on enable / reset
            if (anti_pop_ < 1.0f) {
                const double ap = static_cast<double>(anti_pop_);
                out_l = in_l + ap * (out_l - in_l);
                out_r = in_r + ap * (out_r - in_r);
                anti_pop_ = std::min(1.0f, anti_pop_ + sample_period_ * 50.0f);
            }

            interleaved_samples[2 * i]     = static_cast<T>(out_l);
            interleaved_samples[2 * i + 1] = static_cast<T>(out_r);
        }

        gr_telemetry_.store(current_gr_db_, std::memory_order_relaxed);
    }

    bool enabled_ = false;
    DeEsserMode mode_ = DeEsserMode::SplitBand;
    DeEsserPreset preset_ = DeEsserPreset::GentleVocal;
    bool initialized_ = false;
    float sample_rate_ = 48000.0f;
    float sample_period_ = 1.0f / 48000.0f;

    bool use_macro_intensity_ = true;
    float target_intensity_ = 0.5f;
    float current_intensity_ = 0.5f;

    float frequency_hz_ = 5500.0f;
    float target_threshold_db_ = -22.0f;
    float current_threshold_db_ = -22.0f;
    float ratio_ = 4.0f;
    float max_reduction_db_ = 12.0f;
    float attack_ms_ = 1.0f;
    float release_ms_ = 35.0f;

    float smoothing_coeff_ = 0.002f;
    float attack_coeff_ = 0.1f;
    float release_coeff_ = 0.001f;
    float gr_anti_zipper_coeff_ = 0.08f;
    float anti_pop_ = 0.0f;
    float current_gr_db_ = 0.0f;
    std::atomic<float> gr_telemetry_{0.0f};
    float knee_start_lin_ = 0.063f;
    float prev_thresh_for_lin_ = -22.0f;

    // Dynamic High-Shelf 64-bit Cytomic SVF & Telemetry
    CytomicSVF shelf_svf_;
    float shelf_b0_ = 1.0f;
    float tgt_shelf_b0_ = 1.0f;
    float tgt_shelf_b1_ = 0.0f, tgt_shelf_b2_ = 0.0f;
    float tgt_shelf_a1_ = 0.0f, tgt_shelf_a2_ = 0.0f;
    float prev_shelf_gain_db_ = 999.0f;

    // Sidechain HPF + LPF Coefficients (64-bit double precision) and states (SimdDouble2 stereo DFI)
    double sc_b0_ = 1.0, sc_b1_ = 0.0, sc_b2_ = 0.0, sc_a1_ = 0.0, sc_a2_ = 0.0;
    double sc_lp_b0_ = 1.0, sc_lp_b1_ = 0.0, sc_lp_b2_ = 0.0, sc_lp_a1_ = 0.0, sc_lp_a2_ = 0.0;
    SimdDouble2 sc_x1_{0.0};
    SimdDouble2 sc_x2_{0.0};
    SimdDouble2 sc_y1_{0.0};
    SimdDouble2 sc_y2_{0.0};
    SimdDouble2 sc_lp_x1_{0.0};
    SimdDouble2 sc_lp_x2_{0.0};
    SimdDouble2 sc_lp_y1_{0.0};
    SimdDouble2 sc_lp_y2_{0.0};

    // Envelope followers
    float env_l_ = 0.0f;
    float env_r_ = 0.0f;

    void updateMacroParameters(float intensity) {
        if (intensity <= 0.001f) {
            target_threshold_db_ = 0.0f;
            ratio_ = 1.0f;
            max_reduction_db_ = 0.0f;
        } else {
            // Map macro intensity (0.0, 1.0] to threshold, ratio, max reduction
            target_threshold_db_ = -10.0f - intensity * 30.0f; // -10 dB down to -40 dB
            ratio_ = 2.0f + intensity * 6.0f;                 // 2:1 up to 8:1
            max_reduction_db_ = 4.0f + intensity * 14.0f;      // 4 dB up to 18 dB
        }
    }

    void updateTimeConstants() {
        // Ballistics
        attack_coeff_ = 1.0f - std::exp(-1.0f / (sample_rate_ * (attack_ms_ * 0.001f)));
        release_coeff_ = 1.0f - std::exp(-1.0f / (sample_rate_ * (release_ms_ * 0.001f)));
        gr_anti_zipper_coeff_ = 1.0f - std::exp(-1.0f / (sample_rate_ * 0.00025f)); // 0.25ms anti-zipper
    }

    void updateSidechainFilter() {
        constexpr double PI = 3.14159265358979323846;
        const float fc = std::clamp(frequency_hz_, 1000.0f, sample_rate_ * 0.45f);

        // 2nd-order Butterworth High-Pass Filter at fc (64-bit precision)
        double w0 = 2.0 * PI * static_cast<double>(fc) / static_cast<double>(sample_rate_);
        if (w0 > PI * 0.95) w0 = PI * 0.95;
        const double cos_w0 = std::cos(w0);
        const double sin_w0 = std::sin(w0);
        const double alpha = sin_w0 / (2.0 * 0.7071067811865475);

        const double a0 = 1.0 + alpha;
        sc_b0_ = ((1.0 + cos_w0) / 2.0) / a0;
        sc_b1_ = -(1.0 + cos_w0) / a0;
        sc_b2_ = ((1.0 + cos_w0) / 2.0) / a0;
        sc_a1_ = (-2.0 * cos_w0) / a0;
        sc_a2_ = (1.0 - alpha) / a0;

        // 2nd-order Butterworth Low-Pass Filter at max(11 kHz, 1.35 * fc) to prevent cymbal false-triggers
        const float lp_fc = std::clamp(std::max(11000.0f, fc * 1.35f), 4000.0f, sample_rate_ * 0.45f);
        double w_lp = 2.0 * PI * static_cast<double>(lp_fc) / static_cast<double>(sample_rate_);
        if (w_lp > PI * 0.95) w_lp = PI * 0.95;
        const double cos_lp = std::cos(w_lp);
        const double sin_lp = std::sin(w_lp);
        const double alpha_lp = sin_lp / (2.0 * 0.7071067811865475);

        const double a0_lp = 1.0 + alpha_lp;
        sc_lp_b0_ = ((1.0 - cos_lp) / 2.0) / a0_lp;
        sc_lp_b1_ = (1.0 - cos_lp) / a0_lp;
        sc_lp_b2_ = ((1.0 - cos_lp) / 2.0) / a0_lp;
        sc_lp_a1_ = (-2.0 * cos_lp) / a0_lp;
        sc_lp_a2_ = (1.0 - alpha_lp) / a0_lp;
    }

    void updateShelfCoeffs(float gain_db, bool force = false) {
        const float clamped = (std::abs(gain_db) < 0.005f) ? 0.0f : gain_db;
        if (!force && std::abs(clamped - prev_shelf_gain_db_) < 0.01f) return;
        prev_shelf_gain_db_ = clamped;

        const double effective_gain = static_cast<double>(clamped);
        const double fc = static_cast<double>(std::clamp(frequency_hz_, 1000.0f, sample_rate_ * 0.45f));
        shelf_svf_.setParameters(CytomicSVF::FilterType::HighShelf, sample_rate_, fc, effective_gain, 0.70710678);

        tgt_shelf_b0_ = (clamped == 0.0f) ? 1.0f : static_cast<float>(std::pow(10.0, effective_gain / 20.0));
        tgt_shelf_b1_ = 0.0f;
        tgt_shelf_b2_ = 0.0f;
        tgt_shelf_a1_ = 0.0f;
        tgt_shelf_a2_ = 0.0f;
    }
};

} // namespace sauti::dsp
