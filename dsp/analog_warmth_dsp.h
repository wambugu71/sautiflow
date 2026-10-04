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
        // 30ms parameter smoothing coefficient at 2x oversampled rate
        smoothing_coeff_ = 1.0f - std::exp(-1.0f / (0.030f * sample_rate_ * 2.0f));
        dc_r_ = 1.0f - (2.0f * 3.14159265358979323846f * 10.0f / sample_rate_);
        updateTapeFilter();
        oversampler_.init(static_cast<int>(sample_rate_), 4096);
        oversampler4x_.init(static_cast<int>(sample_rate_), 4096);
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
        tape_prev_l_ = 0.0f;
        tape_prev_r_ = 0.0f;
        dc_x_l_ = 0.0f; dc_y_l_ = 0.0f;
        dc_x_r_ = 0.0f; dc_y_r_ = 0.0f;
        anti_pop_ = 0.0f;
        oversampler_.reset();
        oversampler4x_.reset();
        std::fill(dry_ring_.begin(), dry_ring_.end(), 0.0f);
        dry_pos_ = 0;
    }

    // Process interleaved stereo samples: [L0, R0, L1, R1, ...]
    void setOversampling(int factor) {
        oversampling_factor_ = (factor >= 4) ? 4 : ((factor >= 2) ? 2 : 1);
        updateTapeFilter();
    }

    int getOversampling() const { return oversampling_factor_; }
    float getTapeDamping() const { return tape_damping_; }

    // Public entry: records the dry history, then processes in chunks that fit
    // the oversampler's pre-allocated capacity. The history is also kept warm
    // while disabled so enabling crossfades from real preceding audio.
    void process(float* interleaved_samples, uint32_t frame_count) {
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

private:
    void processChunk(float* interleaved_samples, uint32_t frame_count, uint32_t chunk_start) {
        if (!enabled_ || frame_count == 0 || !interleaved_samples) return;

        if (oversampling_factor_ == 1) {
            // 1x Native processing
            for (uint32_t i = 0; i < frame_count; i++) {
                current_drive_ += smoothing_coeff_ * (target_drive_ - current_drive_);
                float in_l = interleaved_samples[2 * i];
                float in_r = interleaved_samples[2 * i + 1];
                float out_l = in_l;
                float out_r = in_r;

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
                interleaved_samples[2 * i]     = out_l;
                interleaved_samples[2 * i + 1] = out_r;
            }
        } else if (oversampling_factor_ == 4) {
            // 4x Polyphase Oversampled processing
            oversampler4x_.process(interleaved_samples, frame_count, [this](float* oversampled, uint32_t oversampled_frames) {
                for (uint32_t i = 0; i < oversampled_frames; i++) {
                    current_drive_ += smoothing_coeff_ * (target_drive_ - current_drive_);
                    float in_l = oversampled[2 * i];
                    float in_r = oversampled[2 * i + 1];
                    float out_l = in_l;
                    float out_r = in_r;

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
                    oversampled[2 * i]     = out_l;
                    oversampled[2 * i + 1] = out_r;
                }
            });
        } else {
            // 2x Polyphase Oversampled processing
            float* oversampled = oversampler_.upsample(interleaved_samples, frame_count);
            if (oversampled) {
                const uint32_t oversampled_frames = frame_count * 2;
                for (uint32_t i = 0; i < oversampled_frames; i++) {
                    current_drive_ += smoothing_coeff_ * (target_drive_ - current_drive_);
                    float in_l = oversampled[2 * i];
                    float in_r = oversampled[2 * i + 1];
                    float out_l = in_l;
                    float out_r = in_r;

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

                    oversampled[2 * i]     = out_l;
                    oversampled[2 * i + 1] = out_r;
                }
                oversampler_.downsample(oversampled, interleaved_samples, frame_count);
            }
        }

        // 4. Post-processing at native rate (DC blocking & anti-pop crossfading)
        uint32_t tap_a = 0, tap_b = 0;
        getDryTaps(tap_a, tap_b);
        for (uint32_t i = 0; i < frame_count; i++) {
            float out_l = interleaved_samples[2 * i];
            float out_r = interleaved_samples[2 * i + 1];

            if (profile_ == AnalogWarmthProfile::Triode12AX7) {
                // The asymmetric triode transfer injects a DC bias. Block it per
                // channel with a gentle 10 Hz one-pole highpass.
                out_l = dc_block(out_l, dc_x_l_, dc_y_l_, dc_r_);
                out_r = dc_block(out_r, dc_x_r_, dc_y_r_, dc_r_);
            }

            // Anti-pop smooth crossfade on activation / preset change. The dry
            // reference is delayed by the oversampler latency so both paths are
            // time-aligned (no comb filtering while mixing).
            if (anti_pop_ < 1.0f) {
                const uint32_t pa = (chunk_start + i - tap_a) & kDryRingMask;
                const uint32_t pb = (chunk_start + i - tap_b) & kDryRingMask;
                const float dry_l = 0.5f * (dry_ring_[2 * pa] + dry_ring_[2 * pb]);
                const float dry_r = 0.5f * (dry_ring_[2 * pa + 1] + dry_ring_[2 * pb + 1]);
                out_l = dry_l + anti_pop_ * (out_l - dry_l);
                out_r = dry_r + anti_pop_ * (out_r - dry_r);
                anti_pop_ = std::min(1.0f, anti_pop_ + sample_period_ * 4.0f);
            }

            interleaved_samples[2 * i]     = out_l;
            interleaved_samples[2 * i + 1] = out_r;
        }
    }

private:
    bool enabled_ = false;
    bool initialized_ = false;
    AnalogWarmthProfile profile_ = AnalogWarmthProfile::Triode12AX7;
    float sample_rate_ = 48000.0f;
    float sample_period_ = 1.0f / 48000.0f;

    float target_drive_ = 0.5f;
    float current_drive_ = 0.5f;
    float smoothing_coeff_ = 0.001f;
    float anti_pop_ = 0.0f;

    // 2x and 4x Polyphase Half-Band Oversamplers
    PolyphaseOversampler2x oversampler_;
    PolyphaseOversampler4x oversampler4x_;
    int oversampling_factor_ = 2;

    // Tape simulation high-frequency damping
    float tape_prev_l_ = 0.0f;
    float tape_prev_r_ = 0.0f;
    float tape_damping_ = 0.15f;

    // Per-channel DC blocker (10 Hz one-pole highpass) for the triode stage
    float dc_x_l_ = 0.0f, dc_y_l_ = 0.0f;
    float dc_x_r_ = 0.0f, dc_y_r_ = 0.0f;
    float dc_r_ = 0.99869f;

    // Dry-path history ring (stereo interleaved) used to align the dry signal
    // with the oversampler's round-trip latency during anti-pop crossfades.
    static constexpr uint32_t kDryRingFrames = 16384; // power of two
    static constexpr uint32_t kDryRingMask = kDryRingFrames - 1;
    static constexpr uint32_t kChunkFrames = 4096;   // matches oversampler init() capacity
    std::vector<float> dry_ring_ = std::vector<float>(static_cast<size_t>(kDryRingFrames) * 2, 0.0f);
    uint32_t dry_pos_ = 0;

    void pushDry(const float* samples, uint32_t frames) {
        for (uint32_t i = 0; i < frames; ++i) {
            const uint32_t p = (dry_pos_ + i) & kDryRingMask;
            dry_ring_[2 * p] = samples[2 * i];
            dry_ring_[2 * p + 1] = samples[2 * i + 1];
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
    static inline float dc_block(float x, float& x1, float& y1, float R) {
        const float y = x - x1 + R * y1 + 1.0e-20f; // denormal flush
        x1 = x;
        y1 = y;
        return y;
    }

    // Fast rational Padé approximation for hyperbolic tangent (~5x faster than std::tanh)
    static inline float fast_tanh(float x) {
        if (x < -3.0f) return -1.0f;
        if (x > 3.0f) return 1.0f;
        float x2 = x * x;
        return x * (27.0f + x2) / (27.0f + 9.0f * x2);
    }

    // 1. 12AX7 Triode Vacuum Tube (Asymmetric Even-Order Harmonics)
    inline float processTriode(float x) {
        float gain = 1.0f + current_drive_ * 2.5f;
        float driven = x * gain;

        // Asymmetric transfer function: positive swings compress differently than negative swings
        // Generates musical 2nd (octave) & 3rd harmonics
        float out;
        if (driven > 0.0f) {
            out = fast_tanh(driven);
        } else {
            // Negative swing has a softer, extended knee (classic triode grid characteristic)
            float neg = driven * 0.85f;
            out = fast_tanh(neg) / 0.85f;
        }

        // Add subtle quadratic even-harmonic warmth
        out += (driven * driven * 0.08f * current_drive_);

        // Level compensation so volume stays consistent
        float comp = 1.0f / (1.0f + current_drive_ * 0.5f);
        return out * comp;
    }

    // 2. Magnetic Tape Saturation (Symmetric Soft Hysteresis Compression + High-Frequency Smoothing)
    inline float processTape(float x, float& prev_state) {
        float gain = 1.0f + current_drive_ * 2.0f;
        float driven = x * gain;

        // Tape S-curve saturation
        float sat = fast_tanh(driven);

        // Gentle high-frequency damping (simulating tape head magnetic gap losses at 2x rate)
        float smoothed = sat * (1.0f - tape_damping_) + prev_state * tape_damping_;
        prev_state = sat;

        float comp = 1.0f / (1.0f + current_drive_ * 0.4f);
        return smoothed * comp;
    }

    // 3. Vintage Console Preamp (Subtle Class-A Harmonic Excitation)
    inline float processPreamp(float x) {
        float drive_scale = current_drive_ * 0.5f;
        float x2 = x * x;
        float x3 = x2 * x;

        // 3-term polynomial saturation: y = x - 0.15*x^2 - 0.1*x^3
        float out = x - (x2 * 0.15f * drive_scale) - (x3 * 0.10f * drive_scale);
        return std::clamp(out, -1.0f, 1.0f);
    }

    inline void processTriodeStereo(float in_l, float in_r, float& out_l, float& out_r) {
        out_l = processTriode(in_l);
        out_r = processTriode(in_r);
    }

    inline void processTapeStereo(float in_l, float in_r, float& out_l, float& out_r) {
        const float gain = 1.0f + current_drive_ * 2.0f;
        const SimdFloat4 in_v(in_l, in_r, 0.0f, 0.0f);
        const SimdFloat4 driven = in_v * SimdFloat4(gain);
        const SimdFloat4 sat = SimdFloat4::fast_tanh(driven);
        alignas(16) float sat_arr[4];
        sat.store_u(sat_arr);

        const float smoothed_l = sat_arr[0] * (1.0f - tape_damping_) + tape_prev_l_ * tape_damping_;
        const float smoothed_r = sat_arr[1] * (1.0f - tape_damping_) + tape_prev_r_ * tape_damping_;
        tape_prev_l_ = sat_arr[0];
        tape_prev_r_ = sat_arr[1];

        const float comp = 1.0f / (1.0f + current_drive_ * 0.4f);
        out_l = smoothed_l * comp;
        out_r = smoothed_r * comp;
    }

    inline void processPreampStereo(float in_l, float in_r, float& out_l, float& out_r) {
        const float drive_scale = current_drive_ * 0.5f;
        const SimdFloat4 x(in_l, in_r, 0.0f, 0.0f);
        const SimdFloat4 x2 = x * x;
        const SimdFloat4 x3 = x2 * x;
        const SimdFloat4 c15(0.15f * drive_scale);
        const SimdFloat4 c10(0.10f * drive_scale);
        SimdFloat4 out_v = x - (x2 * c15) - (x3 * c10);
        out_v = SimdFloat4::max(SimdFloat4(-1.0f), SimdFloat4::min(SimdFloat4(1.0f), out_v));
        alignas(16) float res[4];
        out_v.store_u(res);
        out_l = res[0];
        out_r = res[1];
    }

    void updateTapeFilter() {
        // High-frequency damping calibrated for active effective oversampling rate (1x, 2x, or 4x)
        const float os_mul = static_cast<float>(oversampling_factor_ > 0 ? oversampling_factor_ : 1);
        const float effective_sr = sample_rate_ * os_mul;
        tape_damping_ = std::clamp(6000.0f / effective_sr, 0.01f, 0.35f);
    }
};

} // namespace sauti::dsp
