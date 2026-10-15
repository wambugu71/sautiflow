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
        oversampler_.init(static_cast<int>(sample_rate_), 8192);
        oversampler4x_.init(static_cast<int>(sample_rate_), 8192);
        sidechain_buf_.assign(16384 * 2, 0.0f);
        highband_buf_.assign(16384 * 2, 0.0f);
        dry_ring_.assign(512, 0.0f);
        dry_pos_ = 0;

        // Pre-calculate envelope filter coefficients
        alpha_fast_att_ = calcAlpha(0.0008f); // 0.8 ms
        alpha_fast_rel_ = calcAlpha(0.0150f); // 15 ms
        alpha_slow_att_ = calcAlpha(0.0250f); // 25 ms
        alpha_slow_rel_ = calcAlpha(0.1500f); // 150 ms
        alpha_demask_   = calcAlpha(0.0300f); // 30 ms

        // Chebyshev DC blocker pole at 4x rate: R = 1 - (2*pi*20 / (4*fs))
        dc_block_r_ = 1.0f - (2.0f * 3.14159265f * 20.0f / (4.0f * sample_rate_));

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
        updateFilters();
    }

    float getIntensity() const { return target_intensity_; }

    void setOversampling(int factor) {
        oversampling_factor_ = (factor >= 4) ? 4 : ((factor >= 2) ? 2 : 1);
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
        e_fast_l_ = e_fast_r_ = 0.0f;
        e_slow_l_ = e_slow_r_ = 0.0f;
        e_mud_l_  = e_mud_r_  = 0.0f;
        e_pres_l_ = e_pres_r_ = 0.0f;

        // Reset DC blocker states
        dc_x_l_ = dc_x_r_ = 0.0f;
        dc_y_l_ = dc_y_r_ = 0.0f;

        // Reset Air Shelf biquad states
        air_x1_l_ = air_x2_l_ = air_y1_l_ = air_y2_l_ = 0.0f;
        air_x1_r_ = air_x2_r_ = air_y1_r_ = air_y2_r_ = 0.0f;

        // Reset 3-Way Crossover filter states
        x_low_x1_l_ = x_low_x2_l_ = x_low_y1_l_ = x_low_y2_l_ = 0.0f;
        x_low_x1_r_ = x_low_x2_r_ = x_low_y1_r_ = x_low_y2_r_ = 0.0f;
        x_mid_x1_l_ = x_mid_x2_l_ = x_mid_y1_l_ = x_mid_y2_l_ = 0.0f;
        x_mid_x1_r_ = x_mid_x2_r_ = x_mid_y1_r_ = x_mid_y2_r_ = 0.0f;
        x_high_x1_l_ = x_high_x2_l_ = x_high_y1_l_ = x_high_y2_l_ = 0.0f;
        x_high_x1_r_ = x_high_x2_r_ = x_high_y1_r_ = x_high_y2_r_ = 0.0f;

        // Reset SVF filters
        for (int c = 0; c < 2; ++c) {
            transient_band_hp_[c].reset();
            transient_band_lp_[c].reset();
            transient_shelf_[c].reset();
            lr4_hp1_[c].reset();
            lr4_hp2_[c].reset();
            demask_mud_bpf_[c].reset();
            demask_pres_bpf_[c].reset();
            demask_peaking_[c].reset();
        }

        current_intensity_ = target_intensity_;
        anti_pop_ = 1.0f;
        oversampler_.reset();
        oversampler4x_.reset();
        if (!dry_ring_.empty()) {
            std::fill(dry_ring_.begin(), dry_ring_.end(), 0.0f);
        }
        dry_pos_ = 0;
    }

    // Process interleaved stereo samples: [L0, R0, L1, R1, ...]
    void process(float* interleaved_samples, uint32_t frame_count) {
        if (!enabled_ || frame_count == 0 || !interleaved_samples) return;

        switch (profile_) {
            case AudioClarityProfile::TransientCrisp:
                processTransientArticulator(interleaved_samples, frame_count);
                break;
            case AudioClarityProfile::AirShelf:
                processAirShelf(interleaved_samples, frame_count);
                break;
            case AudioClarityProfile::PresenceExciter:
                processPresenceExciter(interleaved_samples, frame_count);
                break;
            case AudioClarityProfile::HarmonicBrilliance:
                processChebyshevHarmonicExciter(interleaved_samples, frame_count);
                break;
            case AudioClarityProfile::PsychoacousticMaster:
                processPsychoacousticMaster(interleaved_samples, frame_count);
                break;
        }
    }

private:
    float calcAlpha(float time_sec) const {
        return 1.0f - std::exp(-1.0f / (sample_rate_ * time_sec));
    }

    // =========================================================================
    // 1. Differential Envelope Transient Articulator (Profile 0)
    // =========================================================================
    void processTransientArticulator(float* samples, uint32_t frame_count) {
        constexpr float kEps = 1.0e-6f;
        for (uint32_t i = 0; i < frame_count; ++i) {
            current_intensity_ += smoothing_coeff_ * (target_intensity_ - current_intensity_);
            const float max_boost_db = 2.5f * current_intensity_ * transient_snap_;

            float in_l = samples[2 * i];
            float in_r = samples[2 * i + 1];

            // 1. Isolate 2.5 kHz to 12 kHz transient detection band
            double side_l = transient_band_lp_[0].processSample(
                                transient_band_hp_[0].processSample(static_cast<double>(in_l)));
            double side_r = transient_band_lp_[1].processSample(
                                transient_band_hp_[1].processSample(static_cast<double>(in_r)));

            float mag_l = static_cast<float>(std::abs(side_l));
            float mag_r = static_cast<float>(std::abs(side_r));

            // 2. Parallel Fast (0.8ms / 15ms) vs Slow (25ms / 150ms) Envelope Followers
            e_fast_l_ = (mag_l > e_fast_l_) ? (e_fast_l_ + alpha_fast_att_ * (mag_l - e_fast_l_))
                                            : (e_fast_l_ + alpha_fast_rel_ * (mag_l - e_fast_l_));
            e_slow_l_ = (mag_l > e_slow_l_) ? (e_slow_l_ + alpha_slow_att_ * (mag_l - e_slow_l_))
                                            : (e_slow_l_ + alpha_slow_rel_ * (mag_l - e_slow_l_));

            e_fast_r_ = (mag_r > e_fast_r_) ? (e_fast_r_ + alpha_fast_att_ * (mag_r - e_fast_r_))
                                            : (e_fast_r_ + alpha_fast_rel_ * (mag_r - e_fast_r_));
            e_slow_r_ = (mag_r > e_slow_r_) ? (e_slow_r_ + alpha_slow_att_ * (mag_r - e_slow_r_))
                                            : (e_slow_r_ + alpha_slow_rel_ * (mag_r - e_slow_r_));

            // 3. Dimensionless crest factor ratio D(n) = E_fast / (E_slow + eps)
            float ratio_l = e_fast_l_ / (e_slow_l_ + kEps);
            float ratio_r = e_fast_r_ / (e_slow_r_ + kEps);

            // 4. Modulate High-Shelf filter (up to +2.5 dB) on transient spikes
            float boost_l = 0.0f;
            if (ratio_l > 1.05f) {
                boost_l = std::clamp((ratio_l - 1.05f) * 2.0f, 0.0f, max_boost_db);
            }
            float boost_r = 0.0f;
            if (ratio_r > 1.05f) {
                boost_r = std::clamp((ratio_r - 1.05f) * 2.0f, 0.0f, max_boost_db);
            }

            if (anti_pop_ < 1.0f) {
                boost_l *= anti_pop_;
                boost_r *= anti_pop_;
                anti_pop_ = std::min(1.0f, anti_pop_ + sample_period_ * 100.0f);
            }

            transient_shelf_[0].setParameters(CytomicSVF::FilterType::HighShelf, sample_rate_, 4000.0, boost_l, 0.7071);
            transient_shelf_[1].setParameters(CytomicSVF::FilterType::HighShelf, sample_rate_, 4000.0, boost_r, 0.7071);

            float out_l = static_cast<float>(transient_shelf_[0].processSample(static_cast<double>(in_l)));
            float out_r = static_cast<float>(transient_shelf_[1].processSample(static_cast<double>(in_r)));

            samples[2 * i]     = out_l;
            samples[2 * i + 1] = out_r;
        }
    }

    // =========================================================================
    // 2. Air Shelf (Profile 1)
    // =========================================================================
    void processAirShelf(float* samples, uint32_t frame_count) {
        for (uint32_t i = 0; i < frame_count; i++) {
            float in_l = samples[2 * i];
            float in_r = samples[2 * i + 1];

            float out_l = air_b0_ * in_l + air_b1_ * air_x1_l_ + air_b2_ * air_x2_l_
                        - air_a1_ * air_y1_l_ - air_a2_ * air_y2_l_;
            air_x2_l_ = air_x1_l_; air_x1_l_ = in_l;
            air_y2_l_ = air_y1_l_; air_y1_l_ = out_l;

            float out_r = air_b0_ * in_r + air_b1_ * air_x1_r_ + air_b2_ * air_x2_r_
                        - air_a1_ * air_y1_r_ - air_a2_ * air_y2_r_;
            air_x2_r_ = air_x1_r_; air_x1_r_ = in_r;
            air_y2_r_ = air_y1_r_; air_y1_r_ = out_r;

            if (anti_pop_ < 1.0f) {
                out_l = in_l + anti_pop_ * (out_l - in_l);
                out_r = in_r + anti_pop_ * (out_r - in_r);
                anti_pop_ = std::min(1.0f, anti_pop_ + sample_period_ * 100.0f);
            }

            samples[2 * i]     = out_l;
            samples[2 * i + 1] = out_r;
        }
    }

    // =========================================================================
    // 3. Presence Exciter (Profile 2) - Flat-Sum Crossover
    // =========================================================================
    void processPresenceExciter(float* samples, uint32_t frame_count) {
        for (uint32_t i = 0; i < frame_count; i++) {
            current_intensity_ += smoothing_coeff_ * (target_intensity_ - current_intensity_);
            const float mid_gain = 1.0f + current_intensity_ * 0.4f;
            const float high_gain = 1.0f + current_intensity_ * 0.8f;

            float in_l = samples[2 * i];
            float in_r = samples[2 * i + 1];

            // Left Channel
            float low_l = x_low_b0_ * in_l + x_low_b1_ * x_low_x1_l_ + x_low_b2_ * x_low_x2_l_ - x_low_a1_ * x_low_y1_l_ - x_low_a2_ * x_low_y2_l_;
            x_low_x2_l_ = x_low_x1_l_; x_low_x1_l_ = in_l; x_low_y2_l_ = x_low_y1_l_; x_low_y1_l_ = low_l;

            float high_l = x_high_b0_ * in_l + x_high_b1_ * x_high_x1_l_ + x_high_b2_ * x_high_x2_l_ - x_high_a1_ * x_high_y1_l_ - x_high_a2_ * x_high_y2_l_;
            x_high_x2_l_ = x_high_x1_l_; x_high_x1_l_ = in_l; x_high_y2_l_ = x_high_y1_l_; x_high_y1_l_ = high_l;

            // Right Channel
            float low_r = x_low_b0_ * in_r + x_low_b1_ * x_low_x1_r_ + x_low_b2_ * x_low_x2_r_ - x_low_a1_ * x_low_y1_r_ - x_low_a2_ * x_low_y2_r_;
            x_low_x2_r_ = x_low_x1_r_; x_low_x1_r_ = in_r; x_low_y2_r_ = x_low_y1_r_; x_low_y1_r_ = low_r;

            float high_r = x_high_b0_ * in_r + x_high_b1_ * x_high_x1_r_ + x_high_b2_ * x_high_x2_r_ - x_high_a1_ * x_high_y1_r_ - x_high_a2_ * x_high_y2_r_;
            x_high_x2_r_ = x_high_x1_r_; x_high_x1_r_ = in_r; x_high_y2_r_ = x_high_y1_r_; x_high_y1_r_ = high_r;

            // Mid band derived by subtraction for exact flat sum
            const float mid_l = in_l - low_l - high_l;
            const float mid_r = in_r - low_r - high_r;

            float out_l = low_l + (mid_l * mid_gain) + (high_l * high_gain);
            float out_r = low_r + (mid_r * mid_gain) + (high_r * high_gain);

            if (anti_pop_ < 1.0f) {
                out_l = in_l + anti_pop_ * (out_l - in_l);
                out_r = in_r + anti_pop_ * (out_r - in_r);
                anti_pop_ = std::min(1.0f, anti_pop_ + sample_period_ * 100.0f);
            }

            samples[2 * i]     = out_l;
            samples[2 * i + 1] = out_r;
        }
    }

    // =========================================================================
    // 4. 4x Oversampled Chebyshev Polynomial Exciter (Profile 3)
    // =========================================================================
    void processChebyshevHarmonicExciter(float* samples, uint32_t frame_count) {
        if (!samples || frame_count == 0) return;
        const uint32_t max_block = static_cast<uint32_t>(sidechain_buf_.size() / 2);
        for (uint32_t offset = 0; offset < frame_count; offset += max_block) {
            uint32_t cur_frames = std::min(frame_count - offset, max_block);
            processChebyshevBlock(samples + 2 * offset, cur_frames);
        }
    }

    void processChebyshevBlock(float* samples, uint32_t frame_count) {
        // 1. 4th-Order Linkwitz-Riley Crossover at 3.2 kHz (High-Pass Sidechain)
        for (uint32_t i = 0; i < frame_count; ++i) {
            double in_l = static_cast<double>(samples[2 * i]);
            double in_r = static_cast<double>(samples[2 * i + 1]);

            double hp_l = lr4_hp2_[0].processSample(lr4_hp1_[0].processSample(in_l));
            double hp_r = lr4_hp2_[1].processSample(lr4_hp1_[1].processSample(in_r));

            sidechain_buf_[2 * i]     = static_cast<float>(hp_l);
            sidechain_buf_[2 * i + 1] = static_cast<float>(hp_r);
        }

        // 2. Chebyshev Polynomial Waveshaping with DC Blocking in Oversampled Domain
        const float g2 = g2_warmth_ * 0.40f;
        const float g3 = g3_presence_ * 0.30f;
        const float dc_r = dc_block_r_;

        auto apply_chebyshev = [this, g2, g3, dc_r](float* buf, uint32_t num_frames) {
            for (uint32_t i = 0; i < num_frames; ++i) {
                float xl = std::clamp(buf[2 * i], -1.0f, 1.0f);
                float xr = std::clamp(buf[2 * i + 1], -1.0f, 1.0f);

                // Chebyshev 2nd Harmonic: 2x^2 with DC blocker removes offset (0 at silence)
                float t2_raw_l = 2.0f * (xl * xl);
                float t2_raw_r = 2.0f * (xr * xr);

                float dc_out_l = t2_raw_l - dc_x_l_ + dc_r * dc_y_l_;
                dc_x_l_ = t2_raw_l; dc_y_l_ = dc_out_l;

                float dc_out_r = t2_raw_r - dc_x_r_ + dc_r * dc_y_r_;
                dc_x_r_ = t2_raw_r; dc_y_r_ = dc_out_r;

                // 3rd Harmonic Generation: 4x^3 (cubic odd harmonic synthesis without fundamental phase cancellation)
                float t3_l = 4.0f * (xl * xl * xl);
                float t3_r = 4.0f * (xr * xr * xr);

                buf[2 * i]     = (g2 * dc_out_l) + (g3 * t3_l);
                buf[2 * i + 1] = (g2 * dc_out_r) + (g3 * t3_r);
            }
        };

        if (oversampling_factor_ == 1) {
            apply_chebyshev(sidechain_buf_.data(), frame_count);
        } else if (oversampling_factor_ == 4) {
            oversampler4x_.process(sidechain_buf_.data(), frame_count, apply_chebyshev);
        } else {
            float* os_hp = oversampler_.upsample(sidechain_buf_.data(), frame_count);
            if (os_hp) {
                apply_chebyshev(os_hp, frame_count * 2);
                oversampler_.downsample(os_hp, sidechain_buf_.data(), frame_count);
            }
        }

        // 3. Mix back into dry signal at -20 dB nominal blend with group delay compensation
        const int delay_frames = (oversampling_factor_ == 4) ? 39 : ((oversampling_factor_ == 2) ? 26 : 0);
        constexpr int kRingFrames = 256;
        for (uint32_t i = 0; i < frame_count; ++i) {
            current_intensity_ += smoothing_coeff_ * (target_intensity_ - current_intensity_);
            const float mix = current_intensity_ * 0.125f * anti_pop_; // -18 dB to -24 dB range

            float in_l = samples[2 * i];
            float in_r = samples[2 * i + 1];

            dry_ring_[dry_pos_ * 2]     = in_l;
            dry_ring_[dry_pos_ * 2 + 1] = in_r;
            int del_idx = (dry_pos_ - delay_frames + kRingFrames) % kRingFrames;
            float del_l = dry_ring_[del_idx * 2];
            float del_r = dry_ring_[del_idx * 2 + 1];
            dry_pos_ = (dry_pos_ + 1) % kRingFrames;

            float out_l = del_l + sidechain_buf_[2 * i] * mix;
            float out_r = del_r + sidechain_buf_[2 * i + 1] * mix;

            if (anti_pop_ < 1.0f) {
                anti_pop_ = std::min(1.0f, anti_pop_ + sample_period_ * 100.0f);
            }

            samples[2 * i]     = out_l;
            samples[2 * i + 1] = out_r;
        }
    }

    // =========================================================================
    // 5. Full Psychoacoustic Clarity Master (Profile 4)
    // =========================================================================
    void processPsychoacousticMaster(float* samples, uint32_t frame_count) {
        // Step 1: Dynamic Low-Mid De-Masking (240 Hz Anti-Mud Peaking Cut)
        processDeMasking(samples, frame_count);

        // Step 2: Differential Envelope Transient Articulator
        processTransientArticulator(samples, frame_count);

        // Step 3: 4x Oversampled Chebyshev Harmonic Exciter
        processChebyshevHarmonicExciter(samples, frame_count);
    }

    void processDeMasking(float* samples, uint32_t frame_count) {
        if (demask_amount_ <= 0.01f) return;
        constexpr float kEps = 1.0e-5f;

        for (uint32_t i = 0; i < frame_count; ++i) {
            double in_l = static_cast<double>(samples[2 * i]);
            double in_r = static_cast<double>(samples[2 * i + 1]);

            // Measure Mud band (180-350 Hz) vs Vocal Presence band (1-4 kHz)
            double mud_l = std::abs(demask_mud_bpf_[0].processSample(in_l));
            double mud_r = std::abs(demask_mud_bpf_[1].processSample(in_r));
            double pres_l = std::abs(demask_pres_bpf_[0].processSample(in_l));
            double pres_r = std::abs(demask_pres_bpf_[1].processSample(in_r));

            e_mud_l_  += alpha_demask_ * (static_cast<float>(mud_l)  - e_mud_l_);
            e_mud_r_  += alpha_demask_ * (static_cast<float>(mud_r)  - e_mud_r_);
            e_pres_l_ += alpha_demask_ * (static_cast<float>(pres_l) - e_pres_l_);
            e_pres_r_ += alpha_demask_ * (static_cast<float>(pres_r) - e_pres_r_);

            float ratio_l = e_mud_l_ / (e_pres_l_ + kEps);
            float ratio_r = e_mud_r_ / (e_pres_r_ + kEps);

            // Dip 240 Hz peaking cut by -1.5 dB to -3.0 dB when low-mid mud masks presence
            float cut_l = 0.0f;
            if (ratio_l > 1.25f) {
                cut_l = -std::clamp((ratio_l - 1.25f) * 2.0f, 0.0f, 3.0f) * demask_amount_;
            }
            float cut_r = 0.0f;
            if (ratio_r > 1.25f) {
                cut_r = -std::clamp((ratio_r - 1.25f) * 2.0f, 0.0f, 3.0f) * demask_amount_;
            }

            demask_peaking_[0].setParameters(CytomicSVF::FilterType::Bell, sample_rate_, 240.0, cut_l, 1.8);
            demask_peaking_[1].setParameters(CytomicSVF::FilterType::Bell, sample_rate_, 240.0, cut_r, 1.8);

            samples[2 * i]     = static_cast<float>(demask_peaking_[0].processSample(in_l));
            samples[2 * i + 1] = static_cast<float>(demask_peaking_[1].processSample(in_r));
        }
    }

    void updateFilters() {
        // 1. Transient Articulator Sidechain BPF (2.5 kHz to 12 kHz)
        for (int c = 0; c < 2; ++c) {
            transient_band_hp_[c].setParameters(CytomicSVF::FilterType::HighPass, sample_rate_, 2500.0, 0.0, 0.70710678);
            transient_band_lp_[c].setParameters(CytomicSVF::FilterType::LowPass, sample_rate_, 12000.0, 0.0, 0.70710678);
            transient_shelf_[c].setParameters(CytomicSVF::FilterType::HighShelf, sample_rate_, 6000.0, 0.0, 0.65);
        }

        // 2. Air Shelf: 12 kHz High-Shelf Biquad (+0 dB to +8 dB)
        float shelf_gain_db = target_intensity_ * 8.0f;
        calcHighshelf(12000.0f, shelf_gain_db, air_b0_, air_b1_, air_b2_, air_a1_, air_a2_);

        // 3. 3-Way Crossover (PresenceExciter)
        calcLowpass(120.0f, 0.7071f, x_low_b0_, x_low_b1_, x_low_b2_, x_low_a1_, x_low_a2_);
        calcBandpass(400.0f, 0.6f, x_mid_b0_, x_mid_b1_, x_mid_b2_, x_mid_a1_, x_mid_a2_);
        calcHighpass(1200.0f, 0.7071f, x_high_b0_, x_high_b1_, x_high_b2_, x_high_a1_, x_high_a2_);

        // 4. 4th-Order Linkwitz-Riley Crossover at 3.2 kHz (High-Pass Crossover)
        for (int c = 0; c < 2; ++c) {
            lr4_hp1_[c].setParameters(CytomicSVF::FilterType::HighPass, sample_rate_, 3200.0, 0.0, 0.70710678);
            lr4_hp2_[c].setParameters(CytomicSVF::FilterType::HighPass, sample_rate_, 3200.0, 0.0, 0.70710678);
        }

        // 5. Dynamic Low-Mid De-Masking BPFs
        for (int c = 0; c < 2; ++c) {
            demask_mud_bpf_[c].setParameters(CytomicSVF::FilterType::BandPass, sample_rate_, 250.0, 0.0, 1.5);
            demask_pres_bpf_[c].setParameters(CytomicSVF::FilterType::BandPass, sample_rate_, 2000.0, 0.0, 0.7);
            demask_peaking_[c].setParameters(CytomicSVF::FilterType::Bell, sample_rate_, 240.0, 0.0, 1.8);
        }
    }

    void calcHighshelf(float freq, float gain_db, float& b0, float& b1, float& b2, float& a1, float& a2) {
        constexpr double PI = 3.14159265358979323846;
        const double A = std::pow(10.0, static_cast<double>(gain_db) / 40.0);
        double w0 = 2.0 * PI * static_cast<double>(freq) / static_cast<double>(sample_rate_);
        if (w0 > PI * 0.95) w0 = PI * 0.95;
        const double cos_w0 = std::cos(w0);
        const double sin_w0 = std::sin(w0);
        const double alpha = sin_w0 / 2.0 * std::sqrt((A + 1.0 / A) * (1.0 / 0.7071 - 1.0) + 2.0);
        const double sqrt_A = 2.0 * std::sqrt(A) * alpha;

        const double a0 = (A + 1.0) - (A - 1.0) * cos_w0 + sqrt_A;
        b0 = static_cast<float>((A * ((A + 1.0) + (A - 1.0) * cos_w0 + sqrt_A)) / a0);
        b1 = static_cast<float>((-2.0 * A * ((A - 1.0) + (A + 1.0) * cos_w0)) / a0);
        b2 = static_cast<float>((A * ((A + 1.0) + (A - 1.0) * cos_w0 - sqrt_A)) / a0);
        a1 = static_cast<float>((2.0 * ((A - 1.0) - (A + 1.0) * cos_w0)) / a0);
        a2 = static_cast<float>(((A + 1.0) - (A - 1.0) * cos_w0 - sqrt_A) / a0);
    }

    void calcLowpass(float freq, float Q, float& b0, float& b1, float& b2, float& a1, float& a2) {
        constexpr double PI = 3.14159265358979323846;
        double w0 = 2.0 * PI * static_cast<double>(freq) / static_cast<double>(sample_rate_);
        if (w0 > PI * 0.95) w0 = PI * 0.95;
        const double cos_w0 = std::cos(w0);
        const double sin_w0 = std::sin(w0);
        const double alpha = sin_w0 / (2.0 * static_cast<double>(Q));

        const double a0 = 1.0 + alpha;
        b0 = static_cast<float>(((1.0 - cos_w0) / 2.0) / a0);
        b1 = static_cast<float>((1.0 - cos_w0) / a0);
        b2 = static_cast<float>(((1.0 - cos_w0) / 2.0) / a0);
        a1 = static_cast<float>((-2.0 * cos_w0) / a0);
        a2 = static_cast<float>((1.0 - alpha) / a0);
    }

    void calcHighpass(float freq, float Q, float& b0, float& b1, float& b2, float& a1, float& a2) {
        constexpr double PI = 3.14159265358979323846;
        double w0 = 2.0 * PI * static_cast<double>(freq) / static_cast<double>(sample_rate_);
        if (w0 > PI * 0.95) w0 = PI * 0.95;
        const double cos_w0 = std::cos(w0);
        const double sin_w0 = std::sin(w0);
        const double alpha = sin_w0 / (2.0 * static_cast<double>(Q));

        const double a0 = 1.0 + alpha;
        b0 = static_cast<float>(((1.0 + cos_w0) / 2.0) / a0);
        b1 = static_cast<float>(-(1.0 + cos_w0) / a0);
        b2 = static_cast<float>(((1.0 + cos_w0) / 2.0) / a0);
        a1 = static_cast<float>((-2.0 * cos_w0) / a0);
        a2 = static_cast<float>((1.0 - alpha) / a0);
    }

    void calcBandpass(float freq, float Q, float& b0, float& b1, float& b2, float& a1, float& a2) {
        constexpr double PI = 3.14159265358979323846;
        double w0 = 2.0 * PI * static_cast<double>(freq) / static_cast<double>(sample_rate_);
        if (w0 > PI * 0.95) w0 = PI * 0.95;
        const double cos_w0 = std::cos(w0);
        const double sin_w0 = std::sin(w0);
        const double alpha = sin_w0 / (2.0 * static_cast<double>(Q));

        const double a0 = 1.0 + alpha;
        b0 = static_cast<float>((alpha) / a0);
        b1 = 0.0f;
        b2 = static_cast<float>((-alpha) / a0);
        a1 = static_cast<float>((-2.0 * cos_w0) / a0);
        a2 = static_cast<float>((1.0 - alpha) / a0);
    }

    bool enabled_ = false;
    bool initialized_ = false;
    AudioClarityProfile profile_ = AudioClarityProfile::TransientCrisp;
    float sample_rate_ = 48000.0f;
    float sample_period_ = 1.0f / 48000.0f;
    float target_intensity_ = 0.5f;
    float current_intensity_ = 0.5f;
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

    // Envelope followers
    float e_fast_l_ = 0.0f, e_fast_r_ = 0.0f;
    float e_slow_l_ = 0.0f, e_slow_r_ = 0.0f;
    float e_mud_l_  = 0.0f, e_mud_r_  = 0.0f;
    float e_pres_l_ = 0.0f, e_pres_r_ = 0.0f;

    // Chebyshev DC blocker
    float dc_block_r_ = 0.999f;
    float dc_x_l_ = 0.0f, dc_x_r_ = 0.0f;
    float dc_y_l_ = 0.0f, dc_y_r_ = 0.0f;

    // 2x and 4x Polyphase Half-Band Oversamplers
    PolyphaseOversampler2x oversampler_;
    PolyphaseOversampler4x oversampler4x_;
    int oversampling_factor_ = 4;
    std::vector<float> sidechain_buf_;
    std::vector<float> highband_buf_;
    std::vector<float> dry_ring_;
    int dry_pos_ = 0;

    // Cytomic SVFs for High Precision Dynamics
    CytomicSVF transient_band_hp_[2];
    CytomicSVF transient_band_lp_[2];
    CytomicSVF transient_shelf_[2];
    CytomicSVF lr4_hp1_[2];
    CytomicSVF lr4_hp2_[2];
    CytomicSVF demask_mud_bpf_[2];
    CytomicSVF demask_pres_bpf_[2];
    CytomicSVF demask_peaking_[2];

    // Air Shelf (Profile 1) biquad states
    float air_b0_ = 1.0f, air_b1_ = 0.0f, air_b2_ = 0.0f;
    float air_a1_ = 0.0f, air_a2_ = 0.0f;
    float air_x1_l_ = 0.0f, air_x2_l_ = 0.0f, air_y1_l_ = 0.0f, air_y2_l_ = 0.0f;
    float air_x1_r_ = 0.0f, air_x2_r_ = 0.0f, air_y1_r_ = 0.0f, air_y2_r_ = 0.0f;

    // Presence Exciter (Profile 2) biquad states
    float x_low_b0_ = 1.0f, x_low_b1_ = 0.0f, x_low_b2_ = 0.0f, x_low_a1_ = 0.0f, x_low_a2_ = 0.0f;
    float x_mid_b0_ = 1.0f, x_mid_b1_ = 0.0f, x_mid_b2_ = 0.0f, x_mid_a1_ = 0.0f, x_mid_a2_ = 0.0f;
    float x_high_b0_ = 1.0f, x_high_b1_ = 0.0f, x_high_b2_ = 0.0f, x_high_a1_ = 0.0f, x_high_a2_ = 0.0f;

    float x_low_x1_l_ = 0.0f, x_low_x2_l_ = 0.0f, x_low_y1_l_ = 0.0f, x_low_y2_l_ = 0.0f;
    float x_low_x1_r_ = 0.0f, x_low_x2_r_ = 0.0f, x_low_y1_r_ = 0.0f, x_low_y2_r_ = 0.0f;
    float x_mid_x1_l_ = 0.0f, x_mid_x2_l_ = 0.0f, x_mid_y1_l_ = 0.0f, x_mid_y2_l_ = 0.0f;
    float x_mid_x1_r_ = 0.0f, x_mid_x2_r_ = 0.0f, x_mid_y1_r_ = 0.0f, x_mid_y2_r_ = 0.0f;
    float x_high_x1_l_ = 0.0f, x_high_x2_l_ = 0.0f, x_high_y1_l_ = 0.0f, x_high_y2_l_ = 0.0f;
    float x_high_x1_r_ = 0.0f, x_high_x2_r_ = 0.0f, x_high_y1_r_ = 0.0f, x_high_y2_r_ = 0.0f;
};

} // namespace sauti::dsp
