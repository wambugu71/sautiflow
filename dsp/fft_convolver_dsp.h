#pragma once

#include <cmath>
#include <cstdint>
#include <algorithm>
#include <vector>
#include <complex>
#include <mutex>
#include <atomic>
#include <cstring>
#include "simd_math.h"

namespace sauti::dsp {

// =============================================================================
// FFTConvolverDSP: Clean, High-Performance Partitioned Overlap-Add Convolver
// with Zero-Latency Seamless Dry/Wet Crossfading and Automatic Gain Normalization
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
        smoothing_coeff_ = 1.0f - std::exp(-1.0f / (0.030f * sample_rate_)); // 30ms level smoothing
        crossfade_step_ = 1.0f / (0.020f * sample_rate_);                   // 20ms de-zippered crossfade rate
    }

    void setEnabled(bool enabled) {
        // Do NOT wipe convolution state on enable: the 20ms anti-pop fade-in
        // already prevents clicks, and preserving warm buffers keeps the effect
        // sounding continuously applied across toggle/load cycles.
        enabled_.store(enabled, std::memory_order_release);
    }

    bool isEnabled() const { return enabled_.load(std::memory_order_relaxed); }

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

        // Calculate number of 512-sample segments
        uint32_t num_segments = (frame_count + BLOCK_SIZE - 1) / BLOCK_SIZE;
        if (num_segments > MAX_SEGMENTS) {
            num_segments = MAX_SEGMENTS;
        }

        // 1. Time-domain peak normalization: only ever attenuates IRs that would
        // exceed digital full scale. (An energy-based clamp was tried and removed:
        // it silently turned hot/long custom IRs down by many dB, making the
        // convolver sound like it was barely applied.) Any residual overload on
        // bass-heavy content through high-gain HRIRs is handled downstream by the
        // app's look-ahead limiter / loudness / master chain, not here.
        float max_peak = 0.0f;
        for (uint32_t i = 0; i < frame_count; i++) {
            float l = (channels == 1) ? ir_samples[i] : ir_samples[i * 2];
            float r = (channels == 1) ? ir_samples[i] : ir_samples[i * 2 + 1];
            max_peak = std::max(max_peak, std::max(std::abs(l), std::abs(r)));
        }

        float norm_scale = 1.0f;
        if (max_peak > 1.0f) {
            norm_scale = 1.0f / max_peak;
        }

        // 2. Pre-allocate and compute FFT partitions in local staging vectors OUTSIDE the lock
        std::vector<std::complex<float>> new_partitions_l(num_segments * FFT_SIZE);
        std::vector<std::complex<float>> new_partitions_r;
        if (channels == 2) {
            new_partitions_r.resize(num_segments * FFT_SIZE);
        }

        std::vector<float> time_block(FFT_SIZE, 0.0f);
        std::vector<std::complex<float>> freq_block(FFT_SIZE);

        for (uint32_t seg = 0; seg < num_segments; seg++) {
            uint32_t offset = seg * BLOCK_SIZE;

            // --- Left Channel (or Mono) ---
            std::fill(time_block.begin(), time_block.end(), 0.0f);
            for (size_t i = 0; i < BLOCK_SIZE; i++) {
                uint32_t frame_idx = offset + i;
                if (frame_idx < frame_count) {
                    float s = (channels == 1) ? ir_samples[frame_idx] : ir_samples[frame_idx * 2];
                    time_block[i] = s * norm_scale;
                }
            }
            forwardFFT(time_block.data(), freq_block.data());
            for (size_t k = 0; k < FFT_SIZE; k++) {
                new_partitions_l[seg * FFT_SIZE + k] = freq_block[k];
            }

            // --- Right Channel (if stereo) ---
            if (channels == 2) {
                std::fill(time_block.begin(), time_block.end(), 0.0f);
                for (size_t i = 0; i < BLOCK_SIZE; i++) {
                    uint32_t frame_idx = offset + i;
                    if (frame_idx < frame_count) {
                        float s = ir_samples[frame_idx * 2 + 1];
                        time_block[i] = s * norm_scale;
                    }
                }
                forwardFFT(time_block.data(), freq_block.data());
                for (size_t k = 0; k < FFT_SIZE; k++) {
                    new_partitions_r[seg * FFT_SIZE + k] = freq_block[k];
                }
            }
        }

        // 3. Swap into place under ir_mutex_ (microseconds).
        //
        // Two distinct cases:
        //  - COLD load (no IR yet): hard-reset buffers and restart the 20ms
        //    anti-pop fade from silence. Clean start, no stale state.
        //  - HOT swap (IR already active): do NOT wipe FDLs / output buffers and
        //    do NOT reset fade_progress_. Wiping state here is what made the
        //    effect "disappear": it dumped the wet tail and forced the convolver
        //    to rebuild from silence. Instead we keep the output continuously
        //    wet and start a short dip-and-return micro-fade (handled in
        //    process()) that masks the one-block partition transition and
        //    prevents the crackle a bare swap would cause.
        const bool is_hot_swap = has_ir_ && (segments_count_ > 0);
        {
            std::lock_guard<std::mutex> lock(ir_mutex_);
            segments_count_ = num_segments;
            ir_channels_ = channels;
            ir_partitions_l_ = std::move(new_partitions_l);
            ir_partitions_r_ = std::move(new_partitions_r);

            if (is_hot_swap) {
                // Keep history: only resize FDLs if the segment count changed,
                // and preserve as much prior spectrum as possible.
                if (fdl_l_.size() != segments_count_ * FFT_SIZE) {
                    fdl_l_.assign(segments_count_ * FFT_SIZE, std::complex<float>(0.0f, 0.0f));
                    fdl_r_.assign(segments_count_ * FFT_SIZE, std::complex<float>(0.0f, 0.0f));
                    fdl_head_ = 0;
                }
                swap_fade_active_ = true;
                swap_fade_hold_samples_ = static_cast<uint32_t>(0.005f * sample_rate_); // ~5ms at depth
            } else {
                fdl_l_.assign(segments_count_ * FFT_SIZE, std::complex<float>(0.0f, 0.0f));
                fdl_r_.assign(segments_count_ * FFT_SIZE, std::complex<float>(0.0f, 0.0f));
                fdl_head_ = 0;
                resetInternalBuffers();
                fade_progress_ = 0.0f;
            }
            has_ir_ = true;
        }
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
        fade_progress_ = 0.0f;
    }

    bool hasImpulseResponse() const { return has_ir_; }
    size_t getKernelLength() const { return segments_count_ * BLOCK_SIZE; }

    void reset() {
        std::lock_guard<std::mutex> lock(ir_mutex_);
        resetInternalBuffers();
        current_wet_level_ = target_wet_level_;
        current_dry_level_ = target_dry_level_;
        fade_progress_ = 0.0f;
    }

    // Process interleaved stereo samples: [L0, R0, L1, R1, ...]
    void process(float* interleaved_samples, uint32_t frame_count) {
        const bool is_enabled = enabled_.load(std::memory_order_relaxed);
        if (!is_enabled && fade_progress_ <= 0.0f) return;
        if (!has_ir_ || frame_count == 0 || !interleaved_samples) return;

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

                // Anti-pop smooth crossfade on activation / disablement
                if (is_enabled) {
                    if (fade_progress_ < 1.0f) {
                        fade_progress_ = std::min(1.0f, fade_progress_ + crossfade_step_);
                    }
                } else {
                    if (fade_progress_ > 0.0f) {
                        fade_progress_ = std::max(0.0f, fade_progress_ - crossfade_step_);
                    }
                }

                // IR hot-swap micro-fade: dip toward a reduced level, hold briefly
                // while the new partitions take over, then return. Masks the
                // one-block transition so swaps are click-free without ever
                // dropping the wet signal to silence.
                float swap_gain = 1.0f;
                if (swap_fade_active_) {
                    constexpr float SWAP_DIP = 0.35f; // dip to 35% wet during transition
                    if (swap_fade_hold_samples_ > 0) {
                        // Descending into the dip (fast, ~2x crossfade rate)
                        if (swap_gain_depth_ < 1.0f) {
                            swap_gain_depth_ = std::min(1.0f, swap_gain_depth_ + 2.0f * crossfade_step_);
                        } else {
                            swap_fade_hold_samples_--;
                        }
                        swap_gain = 1.0f - (1.0f - SWAP_DIP) * swap_gain_depth_;
                    } else {
                        // Returning to full wet
                        if (swap_gain_depth_ > 0.0f) {
                            swap_gain_depth_ = std::max(0.0f, swap_gain_depth_ - 2.0f * crossfade_step_);
                        } else {
                            swap_fade_active_ = false;
                        }
                        swap_gain = 1.0f - (1.0f - SWAP_DIP) * swap_gain_depth_;
                    }
                }

                // Seamless blend: 100% dry when fade == 0, full convolver mix when fade == 1
                const float fade = fade_progress_;
                const float eff_dry = (1.0f - fade) + (current_dry_level_ * fade);
                const float eff_wet = current_wet_level_ * fade * swap_gain;

                interleaved_samples[in_idx]     = (dry_in_l * eff_dry) + (wet_l * eff_wet);
                interleaved_samples[in_idx + 1] = (dry_in_r * eff_dry) + (wet_r * eff_wet);
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

    std::atomic<bool> enabled_{false};
    bool has_ir_{false};
    float fade_progress_{0.0f};
    float crossfade_step_{0.001f};

    // Hot-swap micro-fade state (dip-and-return on IR replacement)
    bool swap_fade_active_{false};
    float swap_gain_depth_{0.0f};
    uint32_t swap_fade_hold_samples_{0};

    float sample_rate_{48000.0f};
    float sample_period_{1.0f / 48000.0f};
    float target_wet_level_{1.0f};
    float current_wet_level_{1.0f};
    float target_dry_level_{0.0f};
    float current_dry_level_{0.0f};

    float smoothing_coeff_{0.002f};

    mutable std::mutex ir_mutex_;
    uint32_t segments_count_{0};
    uint32_t ir_channels_{1};

    // Partitioned Frequency Domain Impulse Response
    std::vector<std::complex<float>> ir_partitions_l_;
    std::vector<std::complex<float>> ir_partitions_r_;

    // Frequency Delay Lines
    std::vector<std::complex<float>> fdl_l_;
    std::vector<std::complex<float>> fdl_r_;
    size_t fdl_head_{0};

    // Time-domain overlap buffers
    float in_buf_l_[BLOCK_SIZE]{};
    float in_buf_r_[BLOCK_SIZE]{};
    float out_buf_l_[FFT_SIZE]{};
    float out_buf_r_[FFT_SIZE]{};
    size_t in_pos_{0};

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
        swap_fade_active_ = false;
        swap_gain_depth_ = 0.0f;
        swap_fade_hold_samples_ = 0;
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
        std::memcpy(&fdl_r_[fdl_head_ * FFT_SIZE], scratch_freq_r_, FFT_SIZE * sizeof(std::complex<float>));

        // 3. Frequency-domain complex multiply-accumulate across all IR partitions
        std::fill(accum_l_, accum_l_ + FFT_SIZE, std::complex<float>(0.0f, 0.0f));
        std::fill(accum_r_, accum_r_ + FFT_SIZE, std::complex<float>(0.0f, 0.0f));

        for (uint32_t seg = 0; seg < segments_count_; seg++) {
            size_t fdl_slot = (fdl_head_ + segments_count_ - seg) % segments_count_;
            const float* in_ptr_l = reinterpret_cast<const float*>(&fdl_l_[fdl_slot * FFT_SIZE]);
            const float* in_ptr_r = reinterpret_cast<const float*>(&fdl_r_[fdl_slot * FFT_SIZE]);
            const float* ir_ptr_l = reinterpret_cast<const float*>(&ir_partitions_l_[seg * FFT_SIZE]);
            const float* ir_ptr_r = (ir_channels_ == 2)
                ? reinterpret_cast<const float*>(&ir_partitions_r_[seg * FFT_SIZE])
                : ir_ptr_l; // reuse mono IR partition for right channel

            float* acc_ptr_l = reinterpret_cast<float*>(accum_l_);
            float* acc_ptr_r = reinterpret_cast<float*>(accum_r_);

            for (size_t k = 0; k < FFT_SIZE * 2; k += 4) {
                // Left Channel MAC
                const SimdFloat4 a_l = SimdFloat4::load_u(&in_ptr_l[k]);
                const SimdFloat4 b_l = SimdFloat4::load_u(&ir_ptr_l[k]);
                const SimdFloat4 acc_l = SimdFloat4::load_u(&acc_ptr_l[k]);
                SimdFloat4 res_l = SimdFloat4::complex_mul_accumulate_2(a_l, b_l, acc_l);
                res_l.store_u(&acc_ptr_l[k]);

                // Right Channel MAC
                const SimdFloat4 a_r = SimdFloat4::load_u(&in_ptr_r[k]);
                const SimdFloat4 b_r = SimdFloat4::load_u(&ir_ptr_r[k]);
                const SimdFloat4 acc_r = SimdFloat4::load_u(&acc_ptr_r[k]);
                SimdFloat4 res_r = SimdFloat4::complex_mul_accumulate_2(a_r, b_r, acc_r);
                res_r.store_u(&acc_ptr_r[k]);
            }
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

        // Add current IFFT output block using SIMD
        for (size_t i = 0; i < FFT_SIZE; i += 4) {
            SimdFloat4 out_l = SimdFloat4::load_u(&out_buf_l_[i]);
            SimdFloat4 scr_l = SimdFloat4::load_u(&scratch_time_l_[i]);
            (out_l + scr_l).store_u(&out_buf_l_[i]);

            SimdFloat4 out_r = SimdFloat4::load_u(&out_buf_r_[i]);
            SimdFloat4 scr_r = SimdFloat4::load_u(&scratch_time_r_[i]);
            (out_r + scr_r).store_u(&out_buf_r_[i]);
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
