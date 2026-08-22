#pragma once

#include <cmath>
#include <cstdint>
#include <algorithm>
#include <vector>

namespace sauti::dsp {

// Professional Lookahead Peak Limiter with smooth soft-knee envelope follower
class MasterLimiterDSP {
public:
    MasterLimiterDSP() {
        setSampleRate(48000.0f);
        reset();
    }

    void setSampleRate(float sampleRate) {
        if (sampleRate <= 0.0f) sampleRate = 48000.0f;
        if (std::abs(sample_rate_ - sampleRate) < 0.1f) return;
        sample_rate_ = sampleRate;
        updateTimeConstants();
    }

    void setEnabled(bool enabled) {
        enabled_ = enabled;
        if (!enabled) {
            reset();
        }
    }

    bool isEnabled() const { return enabled_; }

    // Ceiling in dBFS (e.g. -0.1 dB to prevent inter-sample true-peak DAC overs)
    void setCeilingDb(float ceilingDb) {
        ceiling_db_ = std::clamp(ceilingDb, -12.0f, 0.0f);
        ceiling_linear_ = std::pow(10.0f, ceiling_db_ / 20.0f);
    }

    float getCeilingDb() const { return ceiling_db_; }

    // Master Output Gain in dB (-12.0 dB to +12.0 dB)
    void setOutputGainDb(float gainDb) {
        output_gain_db_ = std::clamp(gainDb, -24.0f, 12.0f);
        output_gain_linear_ = std::pow(10.0f, output_gain_db_ / 20.0f);
    }

    float getOutputGainDb() const { return output_gain_db_; }

    // Release time in milliseconds (typically 20 ms to 300 ms, default 60 ms)
    void setReleaseMs(float releaseMs) {
        release_ms_ = std::clamp(releaseMs, 5.0f, 1000.0f);
        updateTimeConstants();
    }

    float getReleaseMs() const { return release_ms_; }

    void reset() {
        lookahead_buf_l_.assign(lookahead_samples_, 0.0f);
        lookahead_buf_r_.assign(lookahead_samples_, 0.0f);
        lookahead_pos_ = 0;
        envelope_ = 0.0f;
        current_gain_ = 1.0f;
    }

    float getCurrentGainReductionDb() const {
        if (current_gain_ >= 0.999f) return 0.0f;
        return 20.0f * std::log10(std::max(current_gain_, 0.0001f));
    }

    // Process interleaved stereo samples: [L0, R0, L1, R1, ...]
    void process(float* interleaved_samples, uint32_t frame_count) {
        if (!enabled_ || frame_count == 0 || !interleaved_samples) return;

        for (uint32_t i = 0; i < frame_count; i++) {
            float in_l = interleaved_samples[2 * i];
            float in_r = interleaved_samples[2 * i + 1];

            // 1. Peak Envelope Detection across both channels
            float peak = std::max(std::abs(in_l), std::abs(in_r));

            if (peak > envelope_) {
                envelope_ = attack_coeff_ * envelope_ + (1.0f - attack_coeff_) * peak;
            } else {
                envelope_ = release_coeff_ * envelope_ + (1.0f - release_coeff_) * peak;
            }

            // 2. Compute Gain Reduction (Soft-Knee Peak Clamping)
            float target_gain = 1.0f;
            if (envelope_ > ceiling_linear_) {
                target_gain = ceiling_linear_ / envelope_;
            }

            // Smooth gain changes to eliminate harmonic distortion during gain reduction
            current_gain_ += 0.05f * (target_gain - current_gain_);

            // 3. Read delayed sample from lookahead ring buffer
            float delayed_l = lookahead_buf_l_[lookahead_pos_];
            float delayed_r = lookahead_buf_r_[lookahead_pos_];

            // Write current input into lookahead buffer
            lookahead_buf_l_[lookahead_pos_] = in_l;
            lookahead_buf_r_[lookahead_pos_] = in_r;

            lookahead_pos_ = (lookahead_pos_ + 1) % lookahead_samples_;

            // 4. Apply gain reduction and master output volume
            float out_l = delayed_l * current_gain_ * output_gain_linear_;
            float out_r = delayed_r * current_gain_ * output_gain_linear_;

            // Final safety ceiling hard-protection
            interleaved_samples[2 * i]     = std::clamp(out_l, -ceiling_linear_, ceiling_linear_);
            interleaved_samples[2 * i + 1] = std::clamp(out_r, -ceiling_linear_, ceiling_linear_);
        }
    }

private:
    bool enabled_ = true;
    float sample_rate_ = 48000.0f;

    float ceiling_db_ = -0.1f;
    float ceiling_linear_ = 0.988553f; // ~ -0.1 dBFS
    float output_gain_db_ = 0.0f;
    float output_gain_linear_ = 1.0f;

    float release_ms_ = 60.0f;
    float attack_coeff_ = 0.1f;
    float release_coeff_ = 0.999f;

    float envelope_ = 0.0f;
    float current_gain_ = 1.0f;

    // Lookahead ring buffer (~1.5 ms lookahead)
    size_t lookahead_samples_ = 72; // 72 samples @ 48kHz is 1.5ms
    std::vector<float> lookahead_buf_l_;
    std::vector<float> lookahead_buf_r_;
    size_t lookahead_pos_ = 0;

    void updateTimeConstants() {
        // ~1.5ms lookahead buffer size for current sample rate
        lookahead_samples_ = std::max(static_cast<size_t>(sample_rate_ * 0.0015f), static_cast<size_t>(16));
        lookahead_buf_l_.assign(lookahead_samples_, 0.0f);
        lookahead_buf_r_.assign(lookahead_samples_, 0.0f);
        lookahead_pos_ = 0;

        // Attack: ~1.0 ms
        attack_coeff_ = std::exp(-1.0f / (sample_rate_ * 0.001f));

        // Release: release_ms_
        release_coeff_ = std::exp(-1.0f / (sample_rate_ * (release_ms_ * 0.001f)));
    }
};

} // namespace sauti::dsp
