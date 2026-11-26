#pragma once

#include <cmath>
#include <cstdint>
#include <algorithm>
#include <vector>
#include "oversampler.h"

namespace sauti::dsp {

enum class AnalogWarmthProfile {
    Triode12AX7 = 0,     // Warm, rich even-order harmonic saturation (Classic Class-A Tube)
    MagneticTape = 1,    // Soft-knee magnetic compression + subtle high-frequency smoothing
    VintagePreamp = 2    // Clean, punchy analog console drive with subtle harmonic presence
};

// =============================================================================
// AnalogWarmthDSP: High-Fidelity Non-Linear Analog Modeling Suite
// Wrapped in 2x Polyphase Half-Band Oversampling to eliminate harmonic aliasing,
// with De-Zippered Parameter Smoothing and Anti-Pop Crossfading.
// =============================================================================
class AnalogWarmthDSP {
public:
    AnalogWarmthDSP() {
        setSampleRate(48000.0f);
        reset();
    }

    void setSampleRate(float sampleRate) {
        if (sampleRate <= 0.0f) sampleRate = 48000.0f;
        if (initialized_ && std::abs(sample_rate_ - sampleRate) < 0.1f) return;
        sample_rate_ = sampleRate;
        sample_period_ = 1.0f / sample_rate_;
        dc_r_ = 1.0f - (2.0f * 3.14159265358979323846f * 10.0f / sample_rate_);
        updateTapeFilter();
        oversampler_.init(static_cast<int>(sample_rate_), 4096);
        oversampler4x_.init(static_cast<int>(sample_rate_), 4096);
        oversampler64_.init(static_cast<int>(sample_rate_), 4096);
        oversampler4x64_.init(static_cast<int>(sample_rate_), 4096);
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

    void setProfile(AnalogWarmthProfile profile) {
        if (profile_ != profile) {
            profile_ = profile;
            reset();
        }
    }

    AnalogWarmthProfile getProfile() const { return profile_; }

    // Drive / Warmth amount [0.0, 1.0]
    void setDrive(float drive) {
        target_drive_ = std::clamp(drive, 0.0f, 1.0f);
    }

    float getDrive() const { return target_drive_; }

    void reset() {
        current_drive_ = target_drive_;
        tape_prev_l_ = 0.0;
        tape_prev_r_ = 0.0;
        dc_x_l_ = 0.0; dc_y_l_ = 0.0;
        dc_x_r_ = 0.0; dc_y_r_ = 0.0;
        anti_pop_ = 0.0f;
        oversampler_.reset();
        oversampler4x_.reset();
        oversampler64_.reset();
        oversampler4x64_.reset();
        std::fill(dry_ring_.begin(), dry_ring_.end(), 0.0);
        dry_pos_ = 0;
    }

    // Process interleaved stereo samples: [L0, R0, L1, R1, ...]
    void setOversampling(int factor) {
        oversampling_factor_ = (factor >= 4) ? 4 : ((factor >= 2) ? 2 : 1);
        updateTapeFilter();
    }

    int getOversampling() const { return oversampling_factor_; }
    float getTapeDamping() const { return tape_damping_; }
    double getLatencySamples() const {
        if (oversampling_factor_ >= 4) return 40.0;
        if (oversampling_factor_ == 2) return 26.5;
        return 0.0;
    }

    // Public entry: records the dry history, then processes in chunks that fit
    // the oversampler's pre-allocated capacity. The history is also kept warm
    // while disabled so enabling crossfades from real preceding audio.
    void process(float* interleaved_samples, uint32_t frame_count) {
        processImpl(interleaved_samples, frame_count);
    }

    void process(double* interleaved_samples, uint32_t frame_count) {
        processImpl(interleaved_samples, frame_count);
    }

private:
    template <typename T>
    void processImpl(T* interleaved_samples, uint32_t frame_count) {
        if (frame_count == 0 || !interleaved_samples) return;

        if (!enabled_) {
            while (frame_count > 0) {
                const uint32_t n = std::min(frame_count, kChunkFrames);
                pushDry(interleaved_samples, n);
                interleaved_samples += 2 * static_cast<size_t>(n);
                frame_count -= n;
            }
            return;
        }

        while (frame_count > 0) {
            const uint32_t n = std::min(frame_count, kChunkFrames);
            const uint32_t chunk_start = dry_pos_;
            pushDry(interleaved_samples, n);
            processChunk(interleaved_samples, n, chunk_start);
            interleaved_samples += 2 * static_cast<size_t>(n);
            frame_count -= n;
        }
    }

    template <typename T>
    void processNonlinearBlock(T* buf, uint32_t frames) {
        for (uint32_t i = 0; i < frames; i++) {
            current_drive_ += smoothing_coeff_ * (target_drive_ - current_drive_);
            const double in_l = static_cast<double>(buf[2 * i]);
            const double in_r = static_cast<double>(buf[2 * i + 1]);
            double out_l = in_l;
            double out_r = in_r;

            switch (profile_) {
                case AnalogWarmthProfile::Triode12AX7:
                    processTriodeStereo(in_l, in_r, out_l, out_r);
                    break;
                case AnalogWarmthProfile::MagneticTape:
                    processTapeStereo(in_l, in_r, out_l, out_r);
                    break;
                case AnalogWarmthProfile::VintagePreamp:
                    processPreampStereo(in_l, in_r, out_l, out_r);
                    break;
            }
            buf[2 * i]     = static_cast<T>(out_l);
            buf[2 * i + 1] = static_cast<T>(out_r);
        }
    }

    template <typename T>
    void processChunk(T* interleaved_samples, uint32_t frame_count, uint32_t chunk_start) {
        if (!enabled_ || frame_count == 0 || !interleaved_samples) return;

        if (oversampling_factor_ == 1) {
            processNonlinearBlock(interleaved_samples, frame_count);
        } else if (oversampling_factor_ == 4) {
            if constexpr (std::is_same_v<T, double>) {
                oversampler4x64_.process(interleaved_samples, frame_count, [this](double* oversampled, uint32_t oversampled_frames) {
                    processNonlinearBlock(oversampled, oversampled_frames);
                });
            } else {
                oversampler4x_.process(interleaved_samples, frame_count, [this](float* oversampled, uint32_t oversampled_frames) {
                    processNonlinearBlock(oversampled, oversampled_frames);
                });
            }
        } else {
            if constexpr (std::is_same_v<T, double>) {
                double* oversampled = oversampler64_.upsample(interleaved_samples, frame_count);
                if (oversampled) {
                    processNonlinearBlock(oversampled, frame_count * 2);
                    oversampler64_.downsample(oversampled, interleaved_samples, frame_count);
                }
            } else {
                float* oversampled = oversampler_.upsample(interleaved_samples, frame_count);
                if (oversampled) {
                    processNonlinearBlock(oversampled, frame_count * 2);
                    oversampler_.downsample(oversampled, interleaved_samples, frame_count);
                }
            }
        }

        // 4. Post-processing at native rate (DC blocking & anti-pop crossfading)
        uint32_t tap_a = 0, tap_b = 0;
        getDryTaps(tap_a, tap_b);
        for (uint32_t i = 0; i < frame_count; i++) {
            double out_l = static_cast<double>(interleaved_samples[2 * i]);
            double out_r = static_cast<double>(interleaved_samples[2 * i + 1]);

            // All nonlinear warmth curves can inject even-order DC asymmetry;
            // block per channel with a 10 Hz one-pole highpass across all profiles.
            out_l = dc_block(out_l, dc_x_l_, dc_y_l_, static_cast<double>(dc_r_));
            out_r = dc_block(out_r, dc_x_r_, dc_y_r_, static_cast<double>(dc_r_));

            // Anti-pop smooth crossfade on activation / preset change (~25 ms). The dry
            // reference is delayed by the oversampler latency so both paths are
            // time-aligned (no comb filtering while mixing).
            if (anti_pop_ < 1.0f) {
                const uint32_t pa = (chunk_start + i - tap_a) & kDryRingMask;
                const uint32_t pb = (chunk_start + i - tap_b) & kDryRingMask;
                const double dry_l = 0.5 * (dry_ring_[2 * pa] + dry_ring_[2 * pb]);
                const double dry_r = 0.5 * (dry_ring_[2 * pa + 1] + dry_ring_[2 * pb + 1]);
                const double ap = static_cast<double>(anti_pop_);
                out_l = dry_l + ap * (out_l - dry_l);
                out_r = dry_r + ap * (out_r - dry_r);
                anti_pop_ = std::min(1.0f, anti_pop_ + sample_period_ * 40.0f);
            }

            interleaved_samples[2 * i]     = static_cast<T>(out_l);
            interleaved_samples[2 * i + 1] = static_cast<T>(out_r);
        }
    }

    bool enabled_ = false;
    bool initialized_ = false;
    AnalogWarmthProfile profile_ = AnalogWarmthProfile::Triode12AX7;
    float sample_rate_ = 48000.0f;
    float sample_period_ = 1.0f / 48000.0f;

    float target_drive_ = 0.5f;
    float current_drive_ = 0.5f;
    float smoothing_coeff_ = 0.001f;
    float anti_pop_ = 0.0f;

    // 2x and 4x Polyphase Half-Band Oversamplers (F32 and F64)
    PolyphaseOversampler2x oversampler_;
    PolyphaseOversampler4x oversampler4x_;
    PolyphaseOversampler2x64 oversampler64_;
    PolyphaseOversampler4x64 oversampler4x64_;
    int oversampling_factor_ = 2;

    // Tape simulation high-frequency damping
    double tape_prev_l_ = 0.0;
    double tape_prev_r_ = 0.0;
    float tape_damping_ = 0.15f;

    // Per-channel DC blocker (10 Hz one-pole highpass) for the triode stage
    double dc_x_l_ = 0.0, dc_y_l_ = 0.0;
    double dc_x_r_ = 0.0, dc_y_r_ = 0.0;
    float dc_r_ = 0.99869f;

    // Dry-path history ring (stereo interleaved) used to align the dry signal
    // with the oversampler's round-trip latency during anti-pop crossfades.
    static constexpr uint32_t kDryRingFrames = 16384; // power of two
    static constexpr uint32_t kDryRingMask = kDryRingFrames - 1;
    static constexpr uint32_t kChunkFrames = 4096;   // matches oversampler init() capacity
    std::vector<double> dry_ring_ = std::vector<double>(static_cast<size_t>(kDryRingFrames) * 2, 0.0);
    uint32_t dry_pos_ = 0;

    template <typename T>
    void pushDry(const T* samples, uint32_t frames) {
        for (uint32_t i = 0; i < frames; ++i) {
            const uint32_t p = (dry_pos_ + i) & kDryRingMask;
            dry_ring_[2 * p] = static_cast<double>(samples[2 * i]);
            dry_ring_[2 * p + 1] = static_cast<double>(samples[2 * i + 1]);
        }
        dry_pos_ = (dry_pos_ + frames) & kDryRingMask;
    }

    // Round-trip latency (native samples): 1x = 0, 2x = 26.5, 4x = 40.
    // The fractional 2x delay is realised as the mean of the 26- and 27-sample taps.
    void getDryTaps(uint32_t& tap_a, uint32_t& tap_b) const {
        if (oversampling_factor_ >= 4) { tap_a = tap_b = 40; }
        else if (oversampling_factor_ == 2) { tap_a = 26; tap_b = 27; }
        else { tap_a = tap_b = 0; }
    }

    // y[n] = x[n] - x[n-1] + R * y[n-1]
    static inline double dc_block(double x, double& x1, double& y1, double R) {
        const double y = x - x1 + R * y1 + 1.0e-25; // denormal flush
        x1 = x;
        y1 = y;
        return y;
    }

    // Monotonic, loudness-matched DC-biased saturator with unity gain at -6 dBFS
    static inline double shapeBiasedTanh(double x, double d, double g_base, double g_span, double b_span, double wet_scale) {
        if (d <= 1.0e-5) return x;
        const double g = g_base + g_span * d;
        const double b = b_span * d;
        const double tb = std::tanh(g * b);
        const double norm = std::tanh(g * (0.5 + b)) - std::tanh(g * (-0.5 + b));
        const double inv_norm = (norm > 1.0e-9) ? (1.0 / norm) : 1.0;
        const double y_sat = (std::tanh(g * (x + b)) - tb) * inv_norm;
        const double w = d * wet_scale;
        return (1.0 - w) * x + w * y_sat;
    }

    // 1. 12AX7 Triode Vacuum Tube (Monotonic Asymmetric Even-Order Harmonics)
    inline double processTriode(double x) {
        const double drive = static_cast<double>(current_drive_);
        return shapeBiasedTanh(x, drive, 1.0, 1.5, 0.36, 1.0);
    }

    inline void processTriodeStereo(double in_l, double in_r, double& out_l, double& out_r) {
        out_l = processTriode(in_l);
        out_r = processTriode(in_r);
    }

    // 2. Magnetic Tape (Soft Magnetic Saturation + Sample-Rate-Invariant TPT HF Damping)
    inline void processTapeStereo(double in_l, double in_r, double& out_l, double& out_r) {
        const double drive = static_cast<double>(current_drive_);
        const double sat_l = shapeBiasedTanh(in_l, drive, 1.0, 2.0, 0.05, 1.0);
        const double sat_r = shapeBiasedTanh(in_r, drive, 1.0, 2.0, 0.05, 1.0);

        const double a = static_cast<double>(tape_damping_);
        const double vl = (sat_l - tape_prev_l_) * a;
        const double lp_l = vl + tape_prev_l_;
        tape_prev_l_ = lp_l + vl;
        if (std::fabs(tape_prev_l_) < 1.0e-25) tape_prev_l_ = 0.0;

        const double vr = (sat_r - tape_prev_r_) * a;
        const double lp_r = vr + tape_prev_r_;
        tape_prev_r_ = lp_r + vr;
        if (std::fabs(tape_prev_r_) < 1.0e-25) tape_prev_r_ = 0.0;

        out_l = sat_l + drive * (lp_l - sat_l);
        out_r = sat_r + drive * (lp_r - sat_r);
    }

    // 3. Vintage Console Preamp (Balanced Harmonic Presence, No Hard Clipping)
    inline void processPreampStereo(double in_l, double in_r, double& out_l, double& out_r) {
        const double drive = static_cast<double>(current_drive_);
        out_l = shapeBiasedTanh(in_l, drive, 0.8, 1.1, 0.24, 0.85);
        out_r = shapeBiasedTanh(in_r, drive, 0.8, 1.1, 0.24, 0.85);
    }

    void updateTapeFilter() {
        // Calibrate parameter smoothing and 1st-order TPT bilinear LPF for active effective rate (1x, 2x, 4x)
        const int os_mul = (oversampling_factor_ > 0) ? oversampling_factor_ : 1;
        const double effective_sr = static_cast<double>(sample_rate_) * static_cast<double>(os_mul);
        smoothing_coeff_ = 1.0f - std::exp(-1.0f / (0.030f * static_cast<float>(effective_sr)));

        const double fc = std::min(14000.0, effective_sr * 0.42);
        const double g = std::tan(3.14159265358979323846 * fc / effective_sr);
        tape_damping_ = static_cast<float>(g / (1.0 + g));
    }
};

} // namespace sauti::dsp
