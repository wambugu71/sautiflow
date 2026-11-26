#pragma once

#include <cmath>
#include <cstdint>
#include <algorithm>
#include <vector>
#include "oversampler.h"
#include "cytomic_svf_dsp.h"
#include "simd_math.h"
#include "denormals.h"

namespace sauti::dsp {

enum class AudioClarityProfile {
    TransientCrisp = 0,       // Differential Envelope Transient Articulator (0.8ms/25ms envelope ratio)
    AirShelf = 1,             // 12 kHz ultra-high shelf for upper harmonic sparkle and breath
    PresenceExciter = 2,       // 3-way multi-band crossover with flat-sum reconstruction
    HarmonicBrilliance = 3,   // 4x Oversampled Chebyshev Polynomial Exciter (LR4 3.2kHz + T2/T3)
    PsychoacousticMaster = 4  // Full 3-Part Suite: De-Masking + Transient Articulation + Chebyshev Air
};

// =============================================================================
// AudioClarityDSP: Book-Accurate Psychoacoustic Detail & Clarity Engine
//
// 1. Differential Envelope Transient Articulator (Profile 0):
//    - Band-limited sidechain (2.5 kHz to 12 kHz).
//    - Fast envelope (tau_att = 0.8 ms, tau_rel = 15 ms).
//    - Slow envelope (tau_att = 25 ms, tau_rel = 150 ms).
//    - Level-invariant ratio D[n] = E_fast[n] / (E_slow[n] + eps).
//    - Dynamically modulates a 6 kHz high-shelf filter by up to +2.5 dB during
//      transient onsets (5-15 ms), with zero boost during sustain/silence to
//      prevent elevating background tape hiss or floor noise.
//
// 2. 4x Oversampled Chebyshev Polynomial Exciter (Profile 3):
//    - 4th-Order Linkwitz-Riley (LR4, 24 dB/oct) crossover high-pass at 3.2 kHz
//      to eliminate Intermodulation Distortion (IMD) with bass/mid fundamentals.
//    - 4x Polyphase Half-Band FIR oversampling (linear phase, >=96 dB stopband).
//    - Strictly orthogonal Chebyshev polynomials:
//        T2(x) = 2x^2 - 1  (Pure 2nd Harmonic: Warmth/Octave) + DC blocking
//        T3(x) = 4x^3 - 3x (Pure 3rd Harmonic: Presence/Sheen)
//    - Downsampled 4x and mixed back at -24 dB to -18 dB.
//
// 3. Dynamic Low-Mid De-Masking ("Mud" Remover) (In Profile 4):
//    - Detects acoustic upward spread of masking (Zwicker & Fastl).
//    - Energy ratio: R[n] = Energy(180-350 Hz) / (Energy(1-4 kHz) + eps).
//    - Dynamic peaking cut centered at 240 Hz (Q = 1.8) dipping by -1.5 to -3 dB
//      only when low-mid mud masks vocal presence, unmasking detail automatically.
// =============================================================================
class AudioClarityDSP {
public:
    AudioClarityDSP() {
        setSampleRate(48000.0f);
        reset();
    }

    void setSampleRate(float sampleRate) {
        if (sampleRate <= 0.0f) sampleRate = 48000.0f;
        if (initialized_ && std::abs(sample_rate_ - sampleRate) < 0.1f) return;
        sample_rate_ = sampleRate;
        sample_period_ = 1.0f / sample_rate_;
        smoothing_coeff_ = 1.0f - std::exp(-1.0f / (0.030f * sample_rate_)); // 30ms smoothing

        updateFilters();
        oversampler64_.init(static_cast<int>(sample_rate_), 8192);
        oversampler4x64_.init(static_cast<int>(sample_rate_), 8192);
        sidechain_buf_.assign(8192 * 2, 0.0);
        dry_ring_.assign(512, 0.0);
        dry_pos_ = 0;

        // Pre-calculate envelope filter coefficients
        alpha_fast_att_ = calcAlpha(0.0008f); // 0.8 ms
        alpha_fast_rel_ = calcAlpha(0.0150f); // 15 ms
        alpha_slow_att_ = calcAlpha(0.0250f); // 25 ms
        alpha_slow_rel_ = calcAlpha(0.1500f); // 150 ms
        alpha_demask_   = calcAlpha(0.0300f); // 30 ms

        // Chebyshev DC blocker pole at oversampled rate: R = exp(-2*pi*20 / (os*fs))
        updateDcBlocker();

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

    void setProfile(AudioClarityProfile profile) {
        if (profile_ != profile) {
            profile_ = profile;
            reset();
            updateFilters();
        }
    }

    AudioClarityProfile getProfile() const { return profile_; }

    // Intensity factor in range [0.0, 1.0]
    void setIntensity(float intensity) {
        target_intensity_ = std::clamp(intensity, 0.0f, 1.0f);
    }

    float getIntensity() const { return target_intensity_; }

    void setOversampling(int factor) {
        oversampling_factor_ = (factor >= 4) ? 4 : ((factor >= 2) ? 2 : 1);
        updateDcBlocker();
    }

    int getOversampling() const { return oversampling_factor_; }

    // Advanced Psychoacoustic Tuning Knobs
    void setWarmthDensity(float g2) { g2_warmth_ = std::clamp(g2, 0.0f, 1.0f); }
    float getWarmthDensity() const { return g2_warmth_; }

    void setPresenceSheen(float g3) { g3_presence_ = std::clamp(g3, 0.0f, 1.0f); }
    float getPresenceSheen() const { return g3_presence_; }

    void setTransientSnap(float snap) { transient_snap_ = std::clamp(snap, 0.0f, 1.0f); }
    float getTransientSnap() const { return transient_snap_; }

    void setDeMaskAmount(float amount) { demask_amount_ = std::clamp(amount, 0.0f, 1.0f); }
    float getDeMaskAmount() const { return demask_amount_; }

    void reset() {
        // Reset envelope states
        e_fast_ = 0.0f;
        e_slow_ = 0.0f;
        e_mud_  = 0.0f;
        e_pres_ = 0.0f;

        // Reset DC blocker and Chebyshev envelope states
        dc_x_l_ = dc_x_r_ = 0.0;
        dc_y_l_ = dc_y_r_ = 0.0;
        cheb_env_sq_l_ = cheb_env_sq_r_ = 0.0;

        // Reset SVF filters
        air_shelf_svf_.reset();
        presence_mid_svf_.reset();
        presence_high_svf_.reset();
        transient_shelf_svf_.reset();
        demask_peaking_svf_.reset();
        for (int c = 0; c < 2; ++c) {
            transient_band_hp_[c].reset();
            transient_band_lp_[c].reset();
            lr4_hp1_[c].reset();
            lr4_hp2_[c].reset();
            cheb_post_hp1_[c].reset();
            cheb_post_hp2_[c].reset();
            demask_mud_bpf_[c].reset();
            demask_pres_bpf_[c].reset();
        }

        current_intensity_ = target_intensity_;
        last_air_intensity_ = -1.0f;
        last_presence_intensity_ = -1.0f;
        last_boost_ = -1.0f;
        last_cut_ = 1.0f;
        anti_pop_ = 1.0f;
        oversampler64_.reset();
        oversampler4x64_.reset();
        if (!dry_ring_.empty()) {
            std::fill(dry_ring_.begin(), dry_ring_.end(), 0.0);
        }
        dry_pos_ = 0;
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

        switch (profile_) {
            case AudioClarityProfile::TransientCrisp:
                processTransientArticulator(interleaved_samples, frame_count, false, true);
                break;
            case AudioClarityProfile::AirShelf:
                processAirShelf(interleaved_samples, frame_count);
                break;
            case AudioClarityProfile::PresenceExciter:
                processPresenceExciter(interleaved_samples, frame_count);
                break;
            case AudioClarityProfile::HarmonicBrilliance:
                processChebyshevHarmonicExciter(interleaved_samples, frame_count, false);
                break;
            case AudioClarityProfile::PsychoacousticMaster:
                processPsychoacousticMaster(interleaved_samples, frame_count);
                break;
        }
    }
    float calcAlpha(float time_sec) const {
        return 1.0f - std::exp(-1.0f / (sample_rate_ * time_sec));
    }

    // =========================================================================
    // 1. Differential Envelope Transient Articulator (Profile 0)
    // =========================================================================
    template <typename T>
    void processTransientArticulator(T* samples, uint32_t frame_count,
                                     bool use_snap_knob = false, bool step_smoothing = true) {
        constexpr float kEps = 1.0e-6f;
        const float snap = use_snap_knob ? transient_snap_ : 1.0f;

        for (uint32_t i = 0; i < frame_count; ++i) {
            if (step_smoothing) {
                current_intensity_ += smoothing_coeff_ * (target_intensity_ - current_intensity_);
            }
            const float max_boost_db = 5.5f * current_intensity_ * snap;

            const double in_l = static_cast<double>(samples[2 * i]);
            const double in_r = static_cast<double>(samples[2 * i + 1]);

            // 1. Isolate 2.5 kHz to 12 kHz transient detection band
            double side_l = transient_band_lp_[0].processSample(
                                transient_band_hp_[0].processSample(in_l));
            double side_r = transient_band_lp_[1].processSample(
                                transient_band_hp_[1].processSample(in_r));

            // Stereo-linked detector prevents L/R image shift on asymmetric transients
            float mag = static_cast<float>(std::max(std::abs(side_l), std::abs(side_r)));

            // 2. Cascaded Fast (0.8ms / 15ms) -> Slow (25ms / 150ms) Envelope Followers
            //    Feeding e_fast_ into e_slow_ eliminates waveform-ripple bias between asymmetric
            //    peak detectors so steady-state tones/hiss converge strictly to ratio == 1.0.
            e_fast_ = (mag > e_fast_) ? (e_fast_ + alpha_fast_att_ * (mag - e_fast_))
                                      : (e_fast_ + alpha_fast_rel_ * (mag - e_fast_));
            e_slow_ = (e_fast_ > e_slow_) ? (e_slow_ + alpha_slow_att_ * (e_fast_ - e_slow_))
                                          : (e_slow_ + alpha_slow_rel_ * (e_fast_ - e_slow_));

            // 3. Dimensionless crest factor ratio D(n) = E_fast / (E_slow + eps)
            float ratio = e_fast_ / (e_slow_ + kEps);

            // 4. Modulate High-Shelf filter (up to +5.5 dB) on transient spikes
            float boost = 0.0f;
            if (ratio > 1.10f) {
                boost = std::clamp((ratio - 1.10f) * 4.0f, 0.0f, max_boost_db);
            }
            boost *= anti_pop_;

            if ((i & 15u) == 0u) {
                if (std::abs(boost - last_boost_) > 0.02f || (boost == 0.0f && last_boost_ > 0.0f)) {
                    transient_shelf_svf_.setParameters(CytomicSVF::FilterType::HighShelf,
                                                       sample_rate_, 4000.0,
                                                       static_cast<double>(boost), 0.7071);
                    last_boost_ = boost;
                }
            }

            if (step_smoothing && anti_pop_ < 1.0f) {
                anti_pop_ = std::min(1.0f, anti_pop_ + sample_period_ * 100.0f);
            }

            const double out_l = transient_shelf_svf_.processSample(in_l, 0);
            const double out_r = transient_shelf_svf_.processSample(in_r, 1);

            samples[2 * i]     = static_cast<T>(out_l);
            samples[2 * i + 1] = static_cast<T>(out_r);
        }
    }

    // =========================================================================
    // 2. Air Shelf (Profile 1) - 64-bit Cytomic SVF with Nyquist De-Cramping
    // =========================================================================
    template <typename T>
    void processAirShelf(T* samples, uint32_t frame_count) {
        for (uint32_t i = 0; i < frame_count; i++) {
            current_intensity_ += smoothing_coeff_ * (target_intensity_ - current_intensity_);
            if ((i & 15u) == 0u) {
                if (std::abs(current_intensity_ - last_air_intensity_) > 0.002f ||
                    (current_intensity_ < 1e-4f && last_air_intensity_ > 0.0f)) {
                    const double gain_db = (current_intensity_ < 1e-4f)
                                               ? 0.0
                                               : static_cast<double>(current_intensity_) * 8.0;
                    air_shelf_svf_.setParameters(CytomicSVF::FilterType::HighShelf,
                                                 sample_rate_, 12000.0,
                                                 gain_db, 0.70710678);
                    last_air_intensity_ = current_intensity_;
                }
            }

            const double in_l = static_cast<double>(samples[2 * i]);
            const double in_r = static_cast<double>(samples[2 * i + 1]);

            double out_l = air_shelf_svf_.processSample(in_l, 0);
            double out_r = air_shelf_svf_.processSample(in_r, 1);

            if (anti_pop_ < 1.0f) {
                const double pop = static_cast<double>(anti_pop_);
                out_l = in_l + pop * (out_l - in_l);
                out_r = in_r + pop * (out_r - in_r);
                anti_pop_ = std::min(1.0f, anti_pop_ + sample_period_ * 100.0f);
            }

            samples[2 * i]     = static_cast<T>(out_l);
            samples[2 * i + 1] = static_cast<T>(out_r);
        }
    }

    // =========================================================================
    // 3. Presence Exciter (Profile 2) - Phase-Coherent 64-bit Cytomic Dual-Shelf
    // =========================================================================
    template <typename T>
    void processPresenceExciter(T* samples, uint32_t frame_count) {
        for (uint32_t i = 0; i < frame_count; i++) {
            current_intensity_ += smoothing_coeff_ * (target_intensity_ - current_intensity_);
            if ((i & 15u) == 0u) {
                if (std::abs(current_intensity_ - last_presence_intensity_) > 0.002f ||
                    (current_intensity_ < 1e-4f && last_presence_intensity_ > 0.0f)) {
                    const double mid_db = (current_intensity_ < 1e-4f)
                                              ? 0.0
                                              : static_cast<double>(current_intensity_) * 2.5;
                    const double high_db = (current_intensity_ < 1e-4f)
                                               ? 0.0
                                               : static_cast<double>(current_intensity_) * 3.0;
                    presence_mid_svf_.setParameters(CytomicSVF::FilterType::HighShelf,
                                                    sample_rate_, 350.0, mid_db, 0.70710678);
                    presence_high_svf_.setParameters(CytomicSVF::FilterType::HighShelf,
                                                     sample_rate_, 2200.0, high_db, 0.70710678);
                    last_presence_intensity_ = current_intensity_;
                }
            }

            const double in_l = static_cast<double>(samples[2 * i]);
            const double in_r = static_cast<double>(samples[2 * i + 1]);

            double out_l = presence_high_svf_.processSample(presence_mid_svf_.processSample(in_l, 0), 0);
            double out_r = presence_high_svf_.processSample(presence_mid_svf_.processSample(in_r, 1), 1);

            if (anti_pop_ < 1.0f) {
                const double pop = static_cast<double>(anti_pop_);
                out_l = in_l + pop * (out_l - in_l);
                out_r = in_r + pop * (out_r - in_r);
                anti_pop_ = std::min(1.0f, anti_pop_ + sample_period_ * 100.0f);
            }

            samples[2 * i]     = static_cast<T>(out_l);
            samples[2 * i + 1] = static_cast<T>(out_r);
        }
    }

    // =========================================================================
    // 4. 4x Oversampled Chebyshev Polynomial Exciter (Profile 3)
    // =========================================================================
    template <typename T>
    void processChebyshevHarmonicExciter(T* samples, uint32_t frame_count, bool use_adv_knobs = false) {
        if (!samples || frame_count == 0) return;
        const uint32_t max_block = static_cast<uint32_t>(sidechain_buf_.size() / 2);
        for (uint32_t offset = 0; offset < frame_count; offset += max_block) {
            uint32_t cur_frames = std::min(frame_count - offset, max_block);
            processChebyshevBlock(samples + 2 * offset, cur_frames, use_adv_knobs);
        }
    }

    template <typename T>
    void processChebyshevBlock(T* samples, uint32_t frame_count, bool use_adv_knobs) {
        // 1. 4th-Order Linkwitz-Riley Crossover at 3.2 kHz (High-Pass Sidechain)
        for (uint32_t i = 0; i < frame_count; ++i) {
            const double in_l = static_cast<double>(samples[2 * i]);
            const double in_r = static_cast<double>(samples[2 * i + 1]);

            const double hp_l = lr4_hp2_[0].processSample(lr4_hp1_[0].processSample(in_l));
            const double hp_r = lr4_hp2_[1].processSample(lr4_hp1_[1].processSample(in_r));

            sidechain_buf_[2 * i]     = hp_l;
            sidechain_buf_[2 * i + 1] = hp_r;
        }

        // 2. Envelope-Normalized Chebyshev Polynomial Waveshaping in Oversampled Domain
        //    Prevents A^2 / A^3 amplitude collapse on realistic HF music levels (-30 to -12 dBFS).
        const double g2 = use_adv_knobs ? static_cast<double>(g2_warmth_) : 0.70;
        const double g3 = use_adv_knobs ? static_cast<double>(g3_presence_) : 0.60;
        const double dc_r = static_cast<double>(dc_block_r_);
        const double env_alpha = 1.0 - dc_r;

        auto apply_chebyshev = [this, g2, g3, dc_r, env_alpha](double* buf, uint32_t num_frames) {
            constexpr double kFloor = 0.015; // ~ -36.5 dBFS gate floor so tape hiss is never amplified
            for (uint32_t i = 0; i < num_frames; ++i) {
                const double xl = std::clamp(buf[2 * i], -1.0, 1.0);
                const double xr = std::clamp(buf[2 * i + 1], -1.0, 1.0);

                // Track peak envelope amplitude: 2 * mean(x^2) = A^2
                cheb_env_sq_l_ += env_alpha * (2.0 * xl * xl - cheb_env_sq_l_);
                cheb_env_sq_r_ += env_alpha * (2.0 * xr * xr - cheb_env_sq_r_);

                const double env_l = std::sqrt(std::max(cheb_env_sq_l_, 0.0));
                const double env_r = std::sqrt(std::max(cheb_env_sq_r_, 0.0));

                const double ul = std::clamp(xl / std::max(env_l, kFloor), -1.0, 1.0);
                const double ur = std::clamp(xr / std::max(env_r, kFloor), -1.0, 1.0);

                const double ul2 = ul * ul;
                const double ur2 = ur * ur;

                // Chebyshev 2nd Harmonic on normalized carrier: 2u^2 -> DC blocker -> scale by envelope
                const double t2_raw_l = 2.0 * ul2;
                const double t2_raw_r = 2.0 * ur2;

                const double dc_out_l = t2_raw_l - dc_x_l_ + dc_r * dc_y_l_;
                dc_x_l_ = t2_raw_l; dc_y_l_ = dc_out_l;

                const double dc_out_r = t2_raw_r - dc_x_r_ + dc_r * dc_y_r_;
                dc_x_r_ = t2_raw_r; dc_y_r_ = dc_out_r;

                const double h2_l = dc_out_l * env_l;
                const double h2_r = dc_out_r * env_r;

                // Chebyshev 3rd Harmonic on normalized carrier: T3(u) = 4u^3 - 3u -> scale by envelope
                const double h3_l = (4.0 * ul2 * ul - 3.0 * ul) * env_l;
                const double h3_r = (4.0 * ur2 * ur - 3.0 * ur) * env_r;

                buf[2 * i]     = (g2 * h2_l) + (g3 * h3_l);
                buf[2 * i + 1] = (g2 * h2_r) + (g3 * h3_r);
            }
        };

        if (oversampling_factor_ == 1) {
            apply_chebyshev(sidechain_buf_.data(), frame_count);
        } else if (oversampling_factor_ == 4) {
            oversampler4x64_.process(sidechain_buf_.data(), frame_count, apply_chebyshev);
        } else {
            double* os_hp = oversampler64_.upsample(sidechain_buf_.data(), frame_count);
            if (os_hp) {
                apply_chebyshev(os_hp, frame_count * 2);
                oversampler64_.downsample(os_hp, sidechain_buf_.data(), frame_count);
            }
        }

        // Post-waveshaper LR4 high-pass filter at 3.2 kHz strips demodulated AM baseband envelopes
        for (uint32_t i = 0; i < frame_count; ++i) {
            const double h_l = cheb_post_hp2_[0].processSample(cheb_post_hp1_[0].processSample(sidechain_buf_[2 * i]));
            const double h_r = cheb_post_hp2_[1].processSample(cheb_post_hp1_[1].processSample(sidechain_buf_[2 * i + 1]));
            sidechain_buf_[2 * i]     = h_l;
            sidechain_buf_[2 * i + 1] = h_r;
        }

        // 3. Mix back into dry signal with group delay compensation (40 frames for 4x, 26 for 2x)
        const int delay_frames = (oversampling_factor_ == 4) ? 40 : ((oversampling_factor_ == 2) ? 26 : 0);
        constexpr int kRingFrames = 256;
        for (uint32_t i = 0; i < frame_count; ++i) {
            current_intensity_ += smoothing_coeff_ * (target_intensity_ - current_intensity_);
            const double mix = static_cast<double>(current_intensity_) * 0.32 * static_cast<double>(anti_pop_);

            const double in_l = static_cast<double>(samples[2 * i]);
            const double in_r = static_cast<double>(samples[2 * i + 1]);

            dry_ring_[dry_pos_ * 2]     = in_l;
            dry_ring_[dry_pos_ * 2 + 1] = in_r;
            const int del_idx = (dry_pos_ - delay_frames + kRingFrames) % kRingFrames;
            const double del_l = dry_ring_[del_idx * 2];
            const double del_r = dry_ring_[del_idx * 2 + 1];
            dry_pos_ = (dry_pos_ + 1) % kRingFrames;

            const double out_l = del_l + sidechain_buf_[2 * i] * mix;
            const double out_r = del_r + sidechain_buf_[2 * i + 1] * mix;

            if (anti_pop_ < 1.0f) {
                anti_pop_ = std::min(1.0f, anti_pop_ + sample_period_ * 100.0f);
            }

            samples[2 * i]     = static_cast<T>(out_l);
            samples[2 * i + 1] = static_cast<T>(out_r);
        }
    }

    // =========================================================================
    // 5. Full Psychoacoustic Clarity Master (Profile 4)
    // =========================================================================
    template <typename T>
    void processPsychoacousticMaster(T* samples, uint32_t frame_count) {
        const float start_intensity = current_intensity_;
        const float start_anti_pop = anti_pop_;

        // Step 1: Dynamic Low-Mid De-Masking (240 Hz Anti-Mud Peaking Cut)
        processDeMasking(samples, frame_count);

        // Step 2: Differential Envelope Transient Articulator
        current_intensity_ = start_intensity;
        anti_pop_ = start_anti_pop;
        processTransientArticulator(samples, frame_count, true, true);

        // Step 3: 4x Oversampled Chebyshev Harmonic Exciter
        current_intensity_ = start_intensity;
        anti_pop_ = start_anti_pop;
        processChebyshevHarmonicExciter(samples, frame_count, true);
    }

    template <typename T>
    void processDeMasking(T* samples, uint32_t frame_count) {
        if (demask_amount_ <= 0.01f) return;
        constexpr float kEps = 1.0e-5f;
        // CytomicSVF::BandPass peak gain is Q (m1 = 1.0). Normalize detectors to 0 dB peak.
        constexpr double kMudNorm = 1.0 / 1.5;
        constexpr double kPresNorm = 1.0 / 0.7;

        for (uint32_t i = 0; i < frame_count; ++i) {
            current_intensity_ += smoothing_coeff_ * (target_intensity_ - current_intensity_);

            const double in_l = static_cast<double>(samples[2 * i]);
            const double in_r = static_cast<double>(samples[2 * i + 1]);

            // Measure normalized Mud band (180-350 Hz) vs Vocal Presence band (1-4 kHz)
            double mud_l  = std::abs(demask_mud_bpf_[0].processSample(in_l)) * kMudNorm;
            double mud_r  = std::abs(demask_mud_bpf_[1].processSample(in_r)) * kMudNorm;
            double pres_l = std::abs(demask_pres_bpf_[0].processSample(in_l)) * kPresNorm;
            double pres_r = std::abs(demask_pres_bpf_[1].processSample(in_r)) * kPresNorm;

            float mud_peak  = static_cast<float>(std::max(mud_l, mud_r));
            float pres_peak = static_cast<float>(std::max(pres_l, pres_r));

            e_mud_  += alpha_demask_ * (mud_peak  - e_mud_);
            e_pres_ += alpha_demask_ * (pres_peak - e_pres_);

            float ratio = e_mud_ / (e_pres_ + kEps);

            // Dip 240 Hz peaking cut by up to -3.0 dB when low-mid mud masks presence
            float cut = 0.0f;
            if (ratio > 1.25f) {
                cut = -std::clamp((ratio - 1.25f) * 2.0f, 0.0f, 3.0f)
                      * demask_amount_ * current_intensity_ * anti_pop_;
            }

            if ((i & 15u) == 0u) {
                if (std::abs(cut - last_cut_) > 0.02f || (cut == 0.0f && last_cut_ < 0.0f)) {
                    demask_peaking_svf_.setParameters(CytomicSVF::FilterType::Bell,
                                                      sample_rate_, 240.0,
                                                      static_cast<double>(cut), 1.8);
                    last_cut_ = cut;
                }
            }

            if (anti_pop_ < 1.0f) {
                anti_pop_ = std::min(1.0f, anti_pop_ + sample_period_ * 100.0f);
            }

            samples[2 * i]     = static_cast<T>(demask_peaking_svf_.processSample(in_l, 0));
            samples[2 * i + 1] = static_cast<T>(demask_peaking_svf_.processSample(in_r, 1));
        }
    }

    void updateDcBlocker() {
        const float os_rate = sample_rate_ * static_cast<float>(std::max(1, oversampling_factor_));
        dc_block_r_ = std::exp(-2.0f * 3.14159265f * 20.0f / os_rate);
    }

    void updateFilters() {
        // 1. Transient Articulator Sidechain BPF (2.5 kHz to 12 kHz)
        for (int c = 0; c < 2; ++c) {
            transient_band_hp_[c].setParameters(CytomicSVF::FilterType::HighPass, sample_rate_, 2500.0, 0.0, 0.70710678);
            transient_band_lp_[c].setParameters(CytomicSVF::FilterType::LowPass, sample_rate_, 12000.0, 0.0, 0.70710678);
        }
        transient_shelf_svf_.setParameters(CytomicSVF::FilterType::HighShelf, sample_rate_, 4000.0, 0.0, 0.7071);
        last_boost_ = 0.0f;

        // 2. Air Shelf: 12 kHz High-Shelf SVF (+0 dB to +8 dB)
        double shelf_gain_db = (current_intensity_ < 1e-4f) ? 0.0 : static_cast<double>(current_intensity_) * 8.0;
        air_shelf_svf_.setParameters(CytomicSVF::FilterType::HighShelf, sample_rate_, 12000.0, shelf_gain_db, 0.70710678);
        last_air_intensity_ = current_intensity_;

        // 3. Presence Exciter (Profile 2): Phase-coherent dual high shelves
        double mid_db = (current_intensity_ < 1e-4f) ? 0.0 : static_cast<double>(current_intensity_) * 2.5;
        double high_db = (current_intensity_ < 1e-4f) ? 0.0 : static_cast<double>(current_intensity_) * 3.0;
        presence_mid_svf_.setParameters(CytomicSVF::FilterType::HighShelf, sample_rate_, 350.0, mid_db, 0.70710678);
        presence_high_svf_.setParameters(CytomicSVF::FilterType::HighShelf, sample_rate_, 2200.0, high_db, 0.70710678);
        last_presence_intensity_ = current_intensity_;

        // 4. 4th-Order Linkwitz-Riley Crossover at 3.2 kHz (Pre- and Post-Shaper High-Pass)
        for (int c = 0; c < 2; ++c) {
            lr4_hp1_[c].setParameters(CytomicSVF::FilterType::HighPass, sample_rate_, 3200.0, 0.0, 0.70710678);
            lr4_hp2_[c].setParameters(CytomicSVF::FilterType::HighPass, sample_rate_, 3200.0, 0.0, 0.70710678);
            cheb_post_hp1_[c].setParameters(CytomicSVF::FilterType::HighPass, sample_rate_, 3200.0, 0.0, 0.70710678);
            cheb_post_hp2_[c].setParameters(CytomicSVF::FilterType::HighPass, sample_rate_, 3200.0, 0.0, 0.70710678);
        }

        // 5. Dynamic Low-Mid De-Masking BPFs
        for (int c = 0; c < 2; ++c) {
            demask_mud_bpf_[c].setParameters(CytomicSVF::FilterType::BandPass, sample_rate_, 250.0, 0.0, 1.5);
            demask_pres_bpf_[c].setParameters(CytomicSVF::FilterType::BandPass, sample_rate_, 2000.0, 0.0, 0.7);
        }
        demask_peaking_svf_.setParameters(CytomicSVF::FilterType::Bell, sample_rate_, 240.0, 0.0, 1.8);
        last_cut_ = 0.0f;
    }

    bool enabled_ = false;
    bool initialized_ = false;
    AudioClarityProfile profile_ = AudioClarityProfile::TransientCrisp;
    float sample_rate_ = 48000.0f;
    float sample_period_ = 1.0f / 48000.0f;
    float target_intensity_ = 0.5f;
    float current_intensity_ = 0.5f;
    float last_air_intensity_ = -1.0f;
    float last_presence_intensity_ = -1.0f;
    float last_boost_ = -1.0f;
    float last_cut_ = 1.0f;
    float smoothing_coeff_ = 0.002f;
    float anti_pop_ = 0.0f;

    // Advanced parameters
    float g2_warmth_ = 0.40f;
    float g3_presence_ = 0.30f;
    float transient_snap_ = 0.80f;
    float demask_amount_ = 0.60f;

    // Envelope time constants
    float alpha_fast_att_ = 0.0f;
    float alpha_fast_rel_ = 0.0f;
    float alpha_slow_att_ = 0.0f;
    float alpha_slow_rel_ = 0.0f;
    float alpha_demask_   = 0.0f;

    // Stereo-linked envelope followers
    float e_fast_ = 0.0f;
    float e_slow_ = 0.0f;
    float e_mud_  = 0.0f;
    float e_pres_ = 0.0f;

    // Chebyshev DC blocker & envelope tracker (64-bit precision)
    float dc_block_r_ = 0.999f;
    double dc_x_l_ = 0.0, dc_x_r_ = 0.0;
    double dc_y_l_ = 0.0, dc_y_r_ = 0.0;
    double cheb_env_sq_l_ = 0.0, cheb_env_sq_r_ = 0.0;

    // 2x and 4x Polyphase Half-Band Oversamplers (F64)
    PolyphaseOversampler2x64 oversampler64_;
    PolyphaseOversampler4x64 oversampler4x64_;
    int oversampling_factor_ = 4;
    std::vector<double> sidechain_buf_;
    std::vector<double> dry_ring_;
    int dry_pos_ = 0;

    // Cytomic SVFs for High Precision Dynamics
    CytomicSVF transient_band_hp_[2];
    CytomicSVF transient_band_lp_[2];
    CytomicSVF transient_shelf_svf_;
    CytomicSVF lr4_hp1_[2];
    CytomicSVF lr4_hp2_[2];
    CytomicSVF cheb_post_hp1_[2];
    CytomicSVF cheb_post_hp2_[2];
    CytomicSVF demask_mud_bpf_[2];
    CytomicSVF demask_pres_bpf_[2];
    CytomicSVF demask_peaking_svf_;

    // Air Shelf (Profile 1) & Presence Exciter (Profile 2) 64-bit Cytomic SVFs
    CytomicSVF air_shelf_svf_;
    CytomicSVF presence_mid_svf_;
    CytomicSVF presence_high_svf_;
};

} // namespace sauti::dsp
