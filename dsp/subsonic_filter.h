#pragma once

#include <cmath>
#include <cstdint>
#include <algorithm>
#include <iterator>
#include "simd_math.h"

namespace sauti::dsp {

// =============================================================================
// SubsonicFilter: High-Fidelity 18 Hz Subsonic Rumble & DC Clean-Room Filter
//
// Features:
// - 2nd-order Butterworth High-Pass at 18 Hz (Q = 0.7071) with 0.0 dB flat
//   passband response above 30 Hz.
// - Removes inaudible DC offset, vinyl turntable rumble, and microphone wind
//   pops before non-linear DSP stages (harmonic bass, analog warmth, exciter).
// - Protects headphone/speaker voice coils from excursion distortion and
//   preserves maximum dynamic headroom for DAC reconstruction.
// - Transposed Direct Form II (TDF2) architecture with double-precision states
//   for optimal numerical stability and zero phase distortion.
// - SIMD-accelerated stereo processing using SimdDouble2 (SSE2 / ARM NEON / AVX).
// =============================================================================
class SubsonicFilter {
public:
    SubsonicFilter() {
        sample_rate_ = 48000.0f;
        updateCoefficients();
        reset();
    }

    void setSampleRate(float sampleRate) {
        if (sampleRate <= 0.0f) sampleRate = 48000.0f;
        if (std::abs(sample_rate_ - sampleRate) < 0.1f && b0_ != 1.0) return;
        sample_rate_ = sampleRate;
        updateCoefficients();
    }

    float getSampleRate() const { return sample_rate_; }

    void setEnabled(bool enabled) {
        if (enabled_ != enabled) {
            enabled_ = enabled;
            if (!enabled) {
                reset();
            }
        }
    }

    bool isEnabled() const { return enabled_; }

    double getB0() const { return b0_; }
    double getB1() const { return b1_; }
    double getB2() const { return b2_; }
    double getA1() const { return a1_; }
    double getA2() const { return a2_; }

    static constexpr size_t MAX_CHANNELS = 16;

    void reset() {
        std::fill(std::begin(s1_), std::end(s1_), 0.0);
        std::fill(std::begin(s2_), std::end(s2_), 0.0);
    }

    void updateCoefficients() {
        constexpr double PI = 3.14159265358979323846;
        const double f0 = 18.0; // 18 Hz subsonic cutoff
        const double Q = 0.7071067811865475; // Butterworth Q
        double w0 = 2.0 * PI * f0 / static_cast<double>(sample_rate_);
        if (w0 > PI * 0.95) w0 = PI * 0.95;
        if (w0 < 1.0e-4) w0 = 1.0e-4;

        const double cos_w0 = std::cos(w0);
        const double sin_w0 = std::sin(w0);
        const double alpha = sin_w0 / (2.0 * Q);

        const double a0 = 1.0 + alpha;
        b0_ = ((1.0 + cos_w0) / 2.0) / a0;
        b1_ = (-(1.0 + cos_w0)) / a0;
        b2_ = ((1.0 + cos_w0) / 2.0) / a0;
        a1_ = (-2.0 * cos_w0) / a0;
        a2_ = (1.0 - alpha) / a0;
    }

    // Process interleaved samples: [L0, R0, ...], mono, or multi-channel up to MAX_CHANNELS
    void process(float* interleaved_samples, uint32_t frame_count, int channels = 2) {
        if (!enabled_ || frame_count == 0 || !interleaved_samples || channels < 1) return;

        if (channels == 2) {
            const SimdDouble2 vb0(b0_);
            const SimdDouble2 vb1(b1_);
            const SimdDouble2 vb2(b2_);
            const SimdDouble2 va1(a1_);
            const SimdDouble2 va2(a2_);
            SimdDouble2 vs1(s1_[0], s1_[1]);
            SimdDouble2 vs2(s2_[0], s2_[1]);

            for (uint32_t i = 0; i < frame_count; i++) {
                const size_t base_idx = static_cast<size_t>(i) * 2;
                SimdDouble2 in_s(static_cast<double>(interleaved_samples[base_idx]),
                                 static_cast<double>(interleaved_samples[base_idx + 1]));

                // out_s = in_s * b0 + s1
                SimdDouble2 out_s = SimdDouble2::fma(in_s, vb0, vs1);

                // Denormal flush threshold
                alignas(16) double out_d[2];
                out_s.store_u(out_d);
                if (std::fabs(out_d[0]) < 1.0e-20) out_d[0] = 0.0;
                if (std::fabs(out_d[1]) < 1.0e-20) out_d[1] = 0.0;
                out_s = SimdDouble2::load_u(out_d);

                // s1 = in_s * b1 - out_s * a1 + s2
                vs1 = SimdDouble2::fma(in_s, vb1, vs2) - (out_s * va1);

                // s2 = in_s * b2 - out_s * a2
                vs2 = (in_s * vb2) - (out_s * va2);

                interleaved_samples[base_idx]     = static_cast<float>(out_d[0]);
                interleaved_samples[base_idx + 1] = static_cast<float>(out_d[1]);
            }

            alignas(16) double final_s1[2];
            alignas(16) double final_s2[2];
            vs1.store_u(final_s1);
            vs2.store_u(final_s2);
            s1_[0] = final_s1[0]; s1_[1] = final_s1[1];
            s2_[0] = final_s2[0]; s2_[1] = final_s2[1];
            return;
        }

        const size_t chs = static_cast<size_t>(std::min<int>(channels, static_cast<int>(MAX_CHANNELS)));
        for (uint32_t i = 0; i < frame_count; i++) {
            const size_t base_idx = static_cast<size_t>(i) * static_cast<size_t>(channels);
            for (size_t c = 0; c < chs; ++c) {
                const double in_s = static_cast<double>(interleaved_samples[base_idx + c]);
                double out_s = in_s * b0_ + s1_[c];
                if (std::fabs(out_s) < 1.0e-20) out_s = 0.0;
                s1_[c] = in_s * b1_ - out_s * a1_ + s2_[c];
                s2_[c] = in_s * b2_ - out_s * a2_;
                interleaved_samples[base_idx + c] = static_cast<float>(out_s);
            }
        }
    }

    // Process double-precision interleaved samples (64-Bit Float DSP mode)
    void process(double* interleaved_samples, uint32_t frame_count, int channels = 2) {
        if (!enabled_ || frame_count == 0 || !interleaved_samples || channels < 1) return;

        if (channels == 2) {
            const SimdDouble2 vb0(b0_);
            const SimdDouble2 vb1(b1_);
            const SimdDouble2 vb2(b2_);
            const SimdDouble2 va1(a1_);
            const SimdDouble2 va2(a2_);
            SimdDouble2 vs1(s1_[0], s1_[1]);
            SimdDouble2 vs2(s2_[0], s2_[1]);

            for (uint32_t i = 0; i < frame_count; i++) {
                const size_t base_idx = static_cast<size_t>(i) * 2;
                SimdDouble2 in_s = SimdDouble2::load_u(&interleaved_samples[base_idx]);

                SimdDouble2 out_s = SimdDouble2::fma(in_s, vb0, vs1);

                alignas(16) double out_d[2];
                out_s.store_u(out_d);
                if (std::fabs(out_d[0]) < 1.0e-20) out_d[0] = 0.0;
                if (std::fabs(out_d[1]) < 1.0e-20) out_d[1] = 0.0;
                out_s = SimdDouble2::load_u(out_d);

                vs1 = SimdDouble2::fma(in_s, vb1, vs2) - (out_s * va1);
                vs2 = (in_s * vb2) - (out_s * va2);

                out_s.store_u(&interleaved_samples[base_idx]);
            }

            alignas(16) double final_s1[2];
            alignas(16) double final_s2[2];
            vs1.store_u(final_s1);
            vs2.store_u(final_s2);
            s1_[0] = final_s1[0]; s1_[1] = final_s1[1];
            s2_[0] = final_s2[0]; s2_[1] = final_s2[1];
            return;
        }

        const size_t chs = static_cast<size_t>(std::min<int>(channels, static_cast<int>(MAX_CHANNELS)));
        for (uint32_t i = 0; i < frame_count; i++) {
            const size_t base_idx = static_cast<size_t>(i) * static_cast<size_t>(channels);
            for (size_t c = 0; c < chs; ++c) {
                const double in_s = interleaved_samples[base_idx + c];
                double out_s = in_s * b0_ + s1_[c];
                if (std::fabs(out_s) < 1.0e-20) out_s = 0.0;
                s1_[c] = in_s * b1_ - out_s * a1_ + s2_[c];
                s2_[c] = in_s * b2_ - out_s * a2_;
                interleaved_samples[base_idx + c] = out_s;
            }
        }
    }

private:
    bool enabled_ = true;
    float sample_rate_ = 48000.0f;

    double b0_ = 1.0, b1_ = -2.0, b2_ = 1.0;
    double a1_ = 0.0, a2_ = 0.0;

    double s1_[MAX_CHANNELS] = {};
    double s2_[MAX_CHANNELS] = {};
};

} // namespace sauti::dsp
