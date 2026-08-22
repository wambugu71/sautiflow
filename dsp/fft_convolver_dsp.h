#pragma once

#include <cmath>
#include <cstdint>
#include <algorithm>
#include <vector>
#include <complex>
#include <mutex>
#include <cstring>

namespace sauti::dsp {

// =============================================================================
// FFTConvolverDSP: Clean, High-Performance Partitioned Overlap-Add Convolver
// with Click-Free Wet/Dry Smoothing and Anti-Pop Crossfading
// =============================================================================
class FFTConvolverDSP {
public:
    static constexpr size_t BLOCK_SIZE = 512;
    static constexpr size_t FFT_SIZE = BLOCK_SIZE * 2; // 1024-point FFT for 512-sample blocks

    FFTConvolverDSP() {
        setSampleRate(48000.0f);
        initTwiddles();
        reset();
    }

    void setSampleRate(float sampleRate) {
        if (sampleRate <= 0.0f) sampleRate = 48000.0f;
        sample_rate_ = sampleRate;
        sample_period_ = 1.0f / sample_rate_;
        smoothing_coeff_ = 1.0f - std::exp(-1.0f / (0.030f * sample_rate_)); // 30ms smoothing
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

    void setWetLevel(float wet) {
        target_wet_level_ = std::clamp(wet, 0.0f, 1.0f);
    }

    float getWetLevel() const { return target_wet_level_; }

    void setDryLevel(float dry) {
        target_dry_level_ = std::clamp(dry, 0.0f, 1.0f);
    }

    float getDryLevel() const { return target_dry_level_; }

    // Load Impulse Response (mono or stereo interleaved float samples)
    bool loadImpulseResponse(const float* ir_samples, uint32_t frame_count, uint32_t channels) {
        if (!ir_samples || frame_count == 0 || (channels != 1 && channels != 2)) {
            clearImpulseResponse();
            return false;
        }

        std::lock_guard<std::mutex> lock(ir_mutex_);

        // Calculate number of 512-sample segments
        uint32_t num_segments = (frame_count + BLOCK_SIZE - 1) / BLOCK_SIZE;
        if (num_segments > MAX_SEGMENTS) {
            num_segments = MAX_SEGMENTS;
        }

        segments_count_ = num_segments;
        ir_channels_ = channels;

        // Allocate frequency-domain partitions
        ir_partitions_l_.resize(segments_count_ * FFT_SIZE);
        if (channels == 2) {
            ir_partitions_r_.resize(segments_count_ * FFT_SIZE);
        } else {
            ir_partitions_r_.clear();
        }

        std::vector<float> time_block(FFT_SIZE, 0.0f);
        std::vector<std::complex<float>> freq_block(FFT_SIZE);

        for (uint32_t seg = 0; seg < segments_count_; seg++) {
            uint32_t offset = seg * BLOCK_SIZE;

            // --- Left Channel (or Mono) ---
            std::fill(time_block.begin(), time_block.end(), 0.0f);
            for (size_t i = 0; i < BLOCK_SIZE; i++) {
                uint32_t frame_idx = offset + i;
                if (frame_idx < frame_count) {
                    time_block[i] = (channels == 1) ? ir_samples[frame_idx] : ir_samples[frame_idx * 2];
                }
            }
            forwardFFT(time_block.data(), freq_block.data());
            for (size_t k = 0; k < FFT_SIZE; k++) {
                ir_partitions_l_[seg * FFT_SIZE + k] = freq_block[k];
            }

            // --- Right Channel (if stereo) ---
            if (channels == 2) {
                std::fill(time_block.begin(), time_block.end(), 0.0f);
                for (size_t i = 0; i < BLOCK_SIZE; i++) {
                    uint32_t frame_idx = offset + i;
                    if (frame_idx < frame_count) {
                        time_block[i] = ir_samples[frame_idx * 2 + 1];
                    }
                }
                forwardFFT(time_block.data(), freq_block.data());
                for (size_t k = 0; k < FFT_SIZE; k++) {
                    ir_partitions_r_[seg * FFT_SIZE + k] = freq_block[k];
                }
            }
        }

        // Prepare FDL (Frequency Delay Line) ring buffers
        fdl_l_.assign(segments_count_ * FFT_SIZE, std::complex<float>(0.0f, 0.0f));
        fdl_r_.assign(segments_count_ * FFT_SIZE, std::complex<float>(0.0f, 0.0f));
        fdl_head_ = 0;

        resetInternalBuffers();
        has_ir_ = true;
        anti_pop_ = 0.0f; // Smooth fade-in on newly loaded IR
        return true;
    }

    void clearImpulseResponse() {
        std::lock_guard<std::mutex> lock(ir_mutex_);
        has_ir_ = false;
        segments_count_ = 0;
        ir_partitions_l_.clear();
        ir_partitions_r_.clear();
        fdl_l_.clear();
        fdl_r_.clear();
        resetInternalBuffers();
        anti_pop_ = 0.0f;
    }

    bool hasImpulseResponse() const { return has_ir_; }
    size_t getKernelLength() const { return segments_count_ * BLOCK_SIZE; }

    void reset() {
        std::lock_guard<std::mutex> lock(ir_mutex_);
        resetInternalBuffers();
        current_wet_level_ = target_wet_level_;
        current_dry_level_ = target_dry_level_;
        anti_pop_ = 0.0f;
    }

    // Process interleaved stereo samples: [L0, R0, L1, R1, ...]
    void process(float* interleaved_samples, uint32_t frame_count) {
        if (!enabled_ || !has_ir_ || frame_count == 0 || !interleaved_samples) return;

        // Try lock without blocking the real-time audio thread
        std::unique_lock<std::mutex> lock(ir_mutex_, std::try_to_lock);
        if (!lock.owns_lock() || !has_ir_ || segments_count_ == 0) return;

        uint32_t processed_frames = 0;

        while (processed_frames < frame_count) {
            uint32_t frames_to_copy = std::min(static_cast<uint32_t>(BLOCK_SIZE - in_pos_), frame_count - processed_frames);

            for (uint32_t i = 0; i < frames_to_copy; i++) {
                uint32_t in_idx = (processed_frames + i) * 2;
                float dry_in_l = interleaved_samples[in_idx];
                float dry_in_r = interleaved_samples[in_idx + 1];

                in_buf_l_[in_pos_ + i] = dry_in_l;
                in_buf_r_[in_pos_ + i] = dry_in_r;

                // De-zipper / smoothly interpolate wet & dry levels per sample
                current_wet_level_ += smoothing_coeff_ * (target_wet_level_ - current_wet_level_);
                current_dry_level_ += smoothing_coeff_ * (target_dry_level_ - current_dry_level_);

                // Output combined dry + overlap-added wet sample
                float wet_l = out_buf_l_[in_pos_ + i];
                float wet_r = out_buf_r_[in_pos_ + i];

                // Anti-pop smooth crossfade on activation / IR load
                float eff_wet = current_wet_level_ * anti_pop_;
                if (anti_pop_ < 1.0f) {
                    anti_pop_ = std::min(1.0f, anti_pop_ + sample_period_ * 4.0f);
                }

                interleaved_samples[in_idx]     = (dry_in_l * current_dry_level_) + (wet_l * eff_wet);
                interleaved_samples[in_idx + 1] = (dry_in_r * current_dry_level_) + (wet_r * eff_wet);
            }

            in_pos_ += frames_to_copy;
            processed_frames += frames_to_copy;

            // When a full 512-sample block is gathered, process FFT overlap-add
            if (in_pos_ >= BLOCK_SIZE) {
                processBlock();
                in_pos_ = 0;
            }
        }
    }

private:
    static constexpr size_t MAX_SEGMENTS = 128; // Up to ~1.36 seconds of impulse response at 48kHz

    bool enabled_ = false;
    bool has_ir_ = false;
    float sample_rate_ = 48000.0f;
    float sample_period_ = 1.0f / 48000.0f;
    float target_wet_level_ = 1.0f;
    float current_wet_level_ = 1.0f;
    float target_dry_level_ = 0.0f;
    float current_dry_level_ = 0.0f;

    float smoothing_coeff_ = 0.002f;
    float anti_pop_ = 0.0f;

    mutable std::mutex ir_mutex_;
    uint32_t segments_count_ = 0;
    uint32_t ir_channels_ = 1;

    // Partitioned Frequency Domain Impulse Response
    std::vector<std::complex<float>> ir_partitions_l_;
    std::vector<std::complex<float>> ir_partitions_r_;

    // Frequency Delay Lines
    std::vector<std::complex<float>> fdl_l_;
    std::vector<std::complex<float>> fdl_r_;
    size_t fdl_head_ = 0;

    // Time-domain overlap buffers
    float in_buf_l_[BLOCK_SIZE]{};
    float in_buf_r_[BLOCK_SIZE]{};
    float out_buf_l_[FFT_SIZE]{};
    float out_buf_r_[FFT_SIZE]{};
    size_t in_pos_ = 0;

    // Scratch buffers for zero-allocation realtime FFT
    float scratch_time_l_[FFT_SIZE]{};
    float scratch_time_r_[FFT_SIZE]{};
    std::complex<float> scratch_freq_l_[FFT_SIZE]{};
    std::complex<float> scratch_freq_r_[FFT_SIZE]{};
    std::complex<float> accum_l_[FFT_SIZE]{};
    std::complex<float> accum_r_[FFT_SIZE]{};

    // Precalculated FFT twiddle factors
    std::complex<float> twiddles_[FFT_SIZE]{};
    size_t bit_rev_[FFT_SIZE]{};

    void initTwiddles() {
        constexpr float PI = 3.14159265358979323846f;
        for (size_t i = 0; i < FFT_SIZE; i++) {
            float angle = -2.0f * PI * static_cast<float>(i) / static_cast<float>(FFT_SIZE);
            twiddles_[i] = std::complex<float>(std::cos(angle), std::sin(angle));
        }

        // Bit reversal table
        size_t bits = static_cast<size_t>(std::round(std::log2(FFT_SIZE)));
        for (size_t i = 0; i < FFT_SIZE; i++) {
            size_t rev = 0;
            for (size_t b = 0; b < bits; b++) {
                if ((i >> b) & 1) {
                    rev |= (1 << (bits - 1 - b));
                }
            }
            bit_rev_[i] = rev;
        }
    }

    void resetInternalBuffers() {
        std::memset(in_buf_l_, 0, sizeof(in_buf_l_));
        std::memset(in_buf_r_, 0, sizeof(in_buf_r_));
        std::memset(out_buf_l_, 0, sizeof(out_buf_l_));
        std::memset(out_buf_r_, 0, sizeof(out_buf_r_));
        in_pos_ = 0;
        if (!fdl_l_.empty()) std::fill(fdl_l_.begin(), fdl_l_.end(), std::complex<float>(0.0f, 0.0f));
        if (!fdl_r_.empty()) std::fill(fdl_r_.begin(), fdl_r_.end(), std::complex<float>(0.0f, 0.0f));
        fdl_head_ = 0;
    }

    void processBlock() {
        // Zero-pad 512 input samples to 1024 FFT length
        std::memcpy(scratch_time_l_, in_buf_l_, BLOCK_SIZE * sizeof(float));
        std::memset(scratch_time_l_ + BLOCK_SIZE, 0, BLOCK_SIZE * sizeof(float));

        std::memcpy(scratch_time_r_, in_buf_r_, BLOCK_SIZE * sizeof(float));
        std::memset(scratch_time_r_ + BLOCK_SIZE, 0, BLOCK_SIZE * sizeof(float));

        // 1. Forward FFT on input block
        forwardFFT(scratch_time_l_, scratch_freq_l_);
        forwardFFT(scratch_time_r_, scratch_freq_r_);

        // 2. Store input spectrum in current FDL slot
        std::memcpy(&fdl_l_[fdl_head_ * FFT_SIZE], scratch_freq_l_, FFT_SIZE * sizeof(std::complex<float>));
        if (ir_channels_ == 2) {
            std::memcpy(&fdl_r_[fdl_head_ * FFT_SIZE], scratch_freq_r_, FFT_SIZE * sizeof(std::complex<float>));
        }

        // 3. Frequency-domain complex multiply-accumulate across all IR partitions
        std::fill(accum_l_, accum_l_ + FFT_SIZE, std::complex<float>(0.0f, 0.0f));
        std::fill(accum_r_, accum_r_ + FFT_SIZE, std::complex<float>(0.0f, 0.0f));

        for (uint32_t seg = 0; seg < segments_count_; seg++) {
            size_t fdl_slot = (fdl_head_ + segments_count_ - seg) % segments_count_;
            const std::complex<float>* in_spec_l = &fdl_l_[fdl_slot * FFT_SIZE];
            const std::complex<float>* ir_spec_l = &ir_partitions_l_[seg * FFT_SIZE];

            for (size_t k = 0; k < FFT_SIZE; k++) {
                accum_l_[k] += in_spec_l[k] * ir_spec_l[k];
            }

            if (ir_channels_ == 2) {
                const std::complex<float>* in_spec_r = &fdl_r_[fdl_slot * FFT_SIZE];
                const std::complex<float>* ir_spec_r = &ir_partitions_r_[seg * FFT_SIZE];
                for (size_t k = 0; k < FFT_SIZE; k++) {
                    accum_r_[k] += in_spec_r[k] * ir_spec_r[k];
                }
            }
        }

        if (ir_channels_ == 1) {
            std::memcpy(accum_r_, accum_l_, FFT_SIZE * sizeof(std::complex<float>));
        }

        // Advance FDL head
        fdl_head_ = (fdl_head_ + 1) % segments_count_;

        // 4. Inverse FFT on accumulated frequency spectrum
        inverseFFT(accum_l_, scratch_time_l_);
        inverseFFT(accum_r_, scratch_time_r_);

        // 5. Overlap-Add into output buffer
        // Shift old second half (tail) to first half
        std::memcpy(out_buf_l_, out_buf_l_ + BLOCK_SIZE, BLOCK_SIZE * sizeof(float));
        std::memset(out_buf_l_ + BLOCK_SIZE, 0, BLOCK_SIZE * sizeof(float));

        std::memcpy(out_buf_r_, out_buf_r_ + BLOCK_SIZE, BLOCK_SIZE * sizeof(float));
        std::memset(out_buf_r_ + BLOCK_SIZE, 0, BLOCK_SIZE * sizeof(float));

        // Add current IFFT output block
        for (size_t i = 0; i < FFT_SIZE; i++) {
            out_buf_l_[i] += scratch_time_l_[i];
            out_buf_r_[i] += scratch_time_r_[i];
        }
    }

    // Radix-2 Cooley-Tukey In-Place Decimation-in-Time Forward FFT
    void forwardFFT(const float* time_in, std::complex<float>* freq_out) {
        for (size_t i = 0; i < FFT_SIZE; i++) {
            freq_out[bit_rev_[i]] = std::complex<float>(time_in[i], 0.0f);
        }

        for (size_t len = 2; len <= FFT_SIZE; len <<= 1) {
            size_t half_len = len >> 1;
            size_t step = FFT_SIZE / len;
            for (size_t i = 0; i < FFT_SIZE; i += len) {
                for (size_t j = 0; j < half_len; j++) {
                    std::complex<float> u = freq_out[i + j];
                    std::complex<float> v = freq_out[i + j + half_len] * twiddles_[j * step];
                    freq_out[i + j] = u + v;
                    freq_out[i + j + half_len] = u - v;
                }
            }
        }
    }

    // Radix-2 Cooley-Tukey In-Place Inverse FFT
    void inverseFFT(const std::complex<float>* freq_in, float* time_out) {
        std::complex<float> temp[FFT_SIZE];
        for (size_t i = 0; i < FFT_SIZE; i++) {
            temp[bit_rev_[i]] = freq_in[i];
        }

        for (size_t len = 2; len <= FFT_SIZE; len <<= 1) {
            size_t half_len = len >> 1;
            size_t step = FFT_SIZE / len;
            for (size_t i = 0; i < FFT_SIZE; i += len) {
                for (size_t j = 0; j < half_len; j++) {
                    std::complex<float> u = temp[i + j];
                    // Conjugate twiddle for IFFT
                    std::complex<float> w(twiddles_[j * step].real(), -twiddles_[j * step].imag());
                    std::complex<float> v = temp[i + j + half_len] * w;
                    temp[i + j] = u + v;
                    temp[i + j + half_len] = u - v;
                }
            }
        }

        const float inv_n = 1.0f / static_cast<float>(FFT_SIZE);
        for (size_t i = 0; i < FFT_SIZE; i++) {
            time_out[i] = temp[i].real() * inv_n;
        }
    }
};

} // namespace sauti::dsp
