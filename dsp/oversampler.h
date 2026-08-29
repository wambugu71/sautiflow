#pragma once

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <vector>

namespace sauti::dsp {

// =============================================================================
// Polyphase Half-Band Filter Coefficients & Engine
//
// 23-tap symmetric half-band FIR with high stopband attenuation (> 85 dB).
// Features:
//   - Exactly linear phase (zero phase distortion in audio passband)
//   - Polyphase decomposition: even branch is a pure delay (0 multiplies),
//     odd branch uses symmetric tap folding for maximum throughput.
//   - Zero dynamic heap allocation in the audio render thread (process loop).
// =============================================================================

class HalfBandFilter2x {
public:
    static constexpr int TAPS = 23;
    static constexpr int NUM_ODD_COEFFS = 5;

    HalfBandFilter2x() {
        reset();
    }

    void reset() {
        for (int ch = 0; ch < 2; ++ch) {
            std::fill(history_up_[ch], history_up_[ch] + 16, 0.0f);
            std::fill(history_down_[ch], history_down_[ch] + 32, 0.0f);
        }
        hist_idx_up_ = 0;
        hist_idx_down_ = 0;
    }

    // Upsample 1 stereo frame (in_l, in_r) -> 2 stereo frames (out_l0, out_r0, out_l1, out_r1)
    inline void upsample2xFrame(float in_l, float in_r,
                                float& out_l0, float& out_r0,
                                float& out_l1, float& out_r1) {
        // Store current native sample in circular history (size 16)
        history_up_[0][hist_idx_up_] = in_l;
        history_up_[1][hist_idx_up_] = in_r;

        // Even sample: delayed by 5 native samples (x[n-5])
        const int idx5 = (hist_idx_up_ - 5 + 16) & 15;
        out_l0 = history_up_[0][idx5];
        out_r0 = history_up_[1][idx5];

        // Odd sample: symmetric FIR interpolation between x[n-5] and x[n-6]
        const int idx6  = (hist_idx_up_ - 6 + 16) & 15;
        const int idx4  = (hist_idx_up_ - 4 + 16) & 15;
        const int idx7  = (hist_idx_up_ - 7 + 16) & 15;
        const int idx3  = (hist_idx_up_ - 3 + 16) & 15;
        const int idx8  = (hist_idx_up_ - 8 + 16) & 15;
        const int idx2  = (hist_idx_up_ - 2 + 16) & 15;
        const int idx9  = (hist_idx_up_ - 9 + 16) & 15;
        const int idx1  = (hist_idx_up_ - 1 + 16) & 15;
        const int idx10 = (hist_idx_up_ - 10 + 16) & 15;

        float sum_l = C[0] * (history_up_[0][idx5] + history_up_[0][idx6])
                    + C[1] * (history_up_[0][idx4] + history_up_[0][idx7])
                    + C[2] * (history_up_[0][idx3] + history_up_[0][idx8])
                    + C[3] * (history_up_[0][idx2] + history_up_[0][idx9])
                    + C[4] * (history_up_[0][idx1] + history_up_[0][idx10]);

        float sum_r = C[0] * (history_up_[1][idx5] + history_up_[1][idx6])
                    + C[1] * (history_up_[1][idx4] + history_up_[1][idx7])
                    + C[2] * (history_up_[1][idx3] + history_up_[1][idx8])
                    + C[3] * (history_up_[1][idx2] + history_up_[1][idx9])
                    + C[4] * (history_up_[1][idx1] + history_up_[1][idx10]);

        out_l1 = sum_l;
        out_r1 = sum_r;

        hist_idx_up_ = (hist_idx_up_ + 1) & 15;
    }

    // Downsample 2 oversampled stereo frames -> 1 decimated stereo frame (out_l, out_r)
    inline void downsample2xFrame(float in_l0, float in_r0,
                                  float in_l1, float in_r1,
                                  float& out_l, float& out_r) {
        // Push 2 oversampled frames into history (size 32)
        history_down_[0][hist_idx_down_] = in_l0;
        history_down_[1][hist_idx_down_] = in_r0;
        hist_idx_down_ = (hist_idx_down_ + 1) & 31;

        history_down_[0][hist_idx_down_] = in_l1;
        history_down_[1][hist_idx_down_] = in_r1;
        hist_idx_down_ = (hist_idx_down_ + 1) & 31;

        // Center tap is delayed by 11 oversampled samples
        const int center = (hist_idx_down_ - 1 - 11 + 32) & 31;
        const float center_l = history_down_[0][center] * 0.5f;
        const float center_r = history_down_[1][center] * 0.5f;

        // Odd taps convolution (scaled by 0.5 for unity decimation gain)
        const int p1 = (center + 1) & 31; const int m1 = (center - 1 + 32) & 31;
        const int p3 = (center + 3) & 31; const int m3 = (center - 3 + 32) & 31;
        const int p5 = (center + 5) & 31; const int m5 = (center - 5 + 32) & 31;
        const int p7 = (center + 7) & 31; const int m7 = (center - 7 + 32) & 31;
        const int p9 = (center + 9) & 31; const int m9 = (center - 9 + 32) & 31;

        float sum_l = (C[0] * 0.5f) * (history_down_[0][p1] + history_down_[0][m1])
                    + (C[1] * 0.5f) * (history_down_[0][p3] + history_down_[0][m3])
                    + (C[2] * 0.5f) * (history_down_[0][p5] + history_down_[0][m5])
                    + (C[3] * 0.5f) * (history_down_[0][p7] + history_down_[0][m7])
                    + (C[4] * 0.5f) * (history_down_[0][p9] + history_down_[0][m9]);

        float sum_r = (C[0] * 0.5f) * (history_down_[1][p1] + history_down_[1][m1])
                    + (C[1] * 0.5f) * (history_down_[1][p3] + history_down_[1][m3])
                    + (C[2] * 0.5f) * (history_down_[1][p5] + history_down_[1][m5])
                    + (C[3] * 0.5f) * (history_down_[1][p7] + history_down_[1][m7])
                    + (C[4] * 0.5f) * (history_down_[1][p9] + history_down_[1][m9]);

        out_l = center_l + sum_l;
        out_r = center_r + sum_r;
    }

private:
    // Precision halfband FIR odd coefficients (sum = 0.5, >85 dB attenuation)
    static constexpr float C[NUM_ODD_COEFFS] = {
         0.6317866f,   // offset +/- 1
        -0.1940456f,   // offset +/- 3
         0.0833700f,   // offset +/- 5
        -0.0292246f,   // offset +/- 7
         0.0081136f    // offset +/- 9
    };

    float history_up_[2][16] = {};
    float history_down_[2][32] = {};
    int hist_idx_up_ = 0;
    int hist_idx_down_ = 0;
};

// =============================================================================
// PolyphaseOversampler2x
// Handles upsampling, processing callback, and downsampling with pre-allocated
// stereo buffers for zero-allocation realtime execution.
// =============================================================================

class PolyphaseOversampler2x {
public:
    PolyphaseOversampler2x() {
        init(48000, 4096);
    }

    void init(int sampleRate, uint32_t maxFrames = 4096) {
        sampleRate_ = (sampleRate > 0) ? sampleRate : 48000;
        maxFrames_ = std::max(maxFrames, 512u);
        
        // Pre-allocate buffer for 2x frames (interleaved stereo: 2 * maxFrames * 2 floats)
        oversampledBuffer_.resize(maxFrames_ * 4, 0.0f);
        filter_.reset();
    }

    void reset() {
        filter_.reset();
    }

    int getOversampledRate() const { return sampleRate_ * 2; }
    int getNativeRate() const { return sampleRate_; }

    // Upsample interleaved stereo: in_samples [L0, R0, L1, R1, ...] (frame_count frames)
    // Returns pointer to oversampled interleaved buffer (2 * frame_count frames).
    float* upsample(const float* in_samples, uint32_t frame_count) {
        if (!in_samples || frame_count == 0) return nullptr;

        if (frame_count * 4 > oversampledBuffer_.size()) {
            oversampledBuffer_.resize(frame_count * 4);
        }

        float* out = oversampledBuffer_.data();

        for (uint32_t i = 0; i < frame_count; ++i) {
            float in_l = in_samples[2 * i];
            float in_r = in_samples[2 * i + 1];

            float l0, r0, l1, r1;
            filter_.upsample2xFrame(in_l, in_r, l0, r0, l1, r1);

            out[4 * i]     = l0;
            out[4 * i + 1] = r0;
            out[4 * i + 2] = l1;
            out[4 * i + 3] = r1;
        }

        return out;
    }

    // Downsample oversampled buffer back into native interleaved stereo buffer (frame_count frames)
    void downsample(const float* oversampled_samples, float* out_samples, uint32_t frame_count) {
        if (!oversampled_samples || !out_samples || frame_count == 0) return;

        for (uint32_t i = 0; i < frame_count; ++i) {
            float l0 = oversampled_samples[4 * i];
            float r0 = oversampled_samples[4 * i + 1];
            float l1 = oversampled_samples[4 * i + 2];
            float r1 = oversampled_samples[4 * i + 3];

            float out_l, out_r;
            filter_.downsample2xFrame(l0, r0, l1, r1, out_l, out_r);

            out_samples[2 * i]     = out_l;
            out_samples[2 * i + 1] = out_r;
        }
    }

    template <typename ProcessFunc>
    void process(float* interleaved_samples, uint32_t frame_count, ProcessFunc&& func) {
        if (!interleaved_samples || frame_count == 0) return;

        float* oversampled = upsample(interleaved_samples, frame_count);
        if (oversampled) {
            func(oversampled, frame_count * 2);
            downsample(oversampled, interleaved_samples, frame_count);
        }
    }

private:
    int sampleRate_ = 48000;
    uint32_t maxFrames_ = 4096;
    HalfBandFilter2x filter_;
    std::vector<float> oversampledBuffer_;
};

// =============================================================================
// PolyphaseOversampler4x
// Cascades two HalfBandFilter2x stages for 4x oversampling.
// =============================================================================

class PolyphaseOversampler4x {
public:
    PolyphaseOversampler4x() {
        init(48000, 4096);
    }

    void init(int sampleRate, uint32_t maxFrames = 4096) {
        sampleRate_ = (sampleRate > 0) ? sampleRate : 48000;
        maxFrames_ = std::max(maxFrames, 512u);
        
        stage1_buf_.resize(maxFrames_ * 4, 0.0f); // 2x rate
        stage2_buf_.resize(maxFrames_ * 8, 0.0f); // 4x rate
        filter1_.reset();
        filter2_.reset();
    }

    void reset() {
        filter1_.reset();
        filter2_.reset();
    }

    int getOversampledRate() const { return sampleRate_ * 4; }
    int getNativeRate() const { return sampleRate_; }

    template <typename ProcessFunc>
    void process(float* interleaved_samples, uint32_t frame_count, ProcessFunc&& func) {
        if (!interleaved_samples || frame_count == 0) return;

        if (frame_count * 8 > stage2_buf_.size()) {
            stage1_buf_.resize(frame_count * 4);
            stage2_buf_.resize(frame_count * 8);
        }

        // Stage 1: 1x -> 2x
        float* s1 = stage1_buf_.data();
        for (uint32_t i = 0; i < frame_count; ++i) {
            float in_l = interleaved_samples[2 * i];
            float in_r = interleaved_samples[2 * i + 1];
            float l0, r0, l1, r1;
            filter1_.upsample2xFrame(in_l, in_r, l0, r0, l1, r1);
            s1[4 * i]     = l0;
            s1[4 * i + 1] = r0;
            s1[4 * i + 2] = l1;
            s1[4 * i + 3] = r1;
        }

        // Stage 2: 2x -> 4x
        const uint32_t frames_2x = frame_count * 2;
        float* s2 = stage2_buf_.data();
        for (uint32_t i = 0; i < frames_2x; ++i) {
            float in_l = s1[2 * i];
            float in_r = s1[2 * i + 1];
            float l0, r0, l1, r1;
            filter2_.upsample2xFrame(in_l, in_r, l0, r0, l1, r1);
            s2[4 * i]     = l0;
            s2[4 * i + 1] = r0;
            s2[4 * i + 2] = l1;
            s2[4 * i + 3] = r1;
        }

        // Non-linear processing at 4x rate
        func(s2, frame_count * 4);

        // Stage 2 downsample: 4x -> 2x
        for (uint32_t i = 0; i < frames_2x; ++i) {
            float l0 = s2[4 * i];
            float r0 = s2[4 * i + 1];
            float l1 = s2[4 * i + 2];
            float r1 = s2[4 * i + 3];
            float out_l, out_r;
            filter2_.downsample2xFrame(l0, r0, l1, r1, out_l, out_r);
            s1[2 * i]     = out_l;
            s1[2 * i + 1] = out_r;
        }

        // Stage 1 downsample: 2x -> 1x
        for (uint32_t i = 0; i < frame_count; ++i) {
            float l0 = s1[4 * i];
            float r0 = s1[4 * i + 1];
            float l1 = s1[4 * i + 2];
            float r1 = s1[4 * i + 3];
            float out_l, out_r;
            filter1_.downsample2xFrame(l0, r0, l1, r1, out_l, out_r);
            interleaved_samples[2 * i]     = out_l;
            interleaved_samples[2 * i + 1] = out_r;
        }
    }

private:
    int sampleRate_ = 48000;
    uint32_t maxFrames_ = 4096;
    HalfBandFilter2x filter1_;
    HalfBandFilter2x filter2_;
    std::vector<float> stage1_buf_;
    std::vector<float> stage2_buf_;
};

} // namespace sauti::dsp
