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
// FFTConvolverDSP: 3-Stage Gardner Non-Uniform Partitioned Overlap-Add Convolver
// - 4-Path True-Stereo Matrix Convolution ([LL, LR, RL, RR]) + Mono & Stereo
// - Hermitian Half-Spectrum Storage & MACs (FFT_SIZE/2 + 1 bins)
// - Latency-Compensated Seamless Dry/Wet Crossfading (512 + extra_wet_delay)
// - Lock-Free Audio Fast-Path & Off-Lock Staging Hot-Swap
// =============================================================================
class FFTConvolverDSP {
public:
    static constexpr size_t BLOCK_SIZE = 512;
    static constexpr size_t FFT_SIZE = BLOCK_SIZE * 2; // Base latency block size (1024-pt FFT)

    // 3-Stage NUPOLS layout (all block sizes are powers of 2 and multiples of 512):
    //   Stage 0: 4 x  512 =   2,048 samples [0      ..  2,048), output delay = 0
    //   Stage 1: 4 x 2048 =   8,192 samples [2,048  .. 10,240), output delay = 512
    //   Stage 2: 64 x 8192 = 524,288 samples [10,240 .. 534,528), output delay = 2560
    // Total capacity: 534,528 samples (~11.1s @ 48kHz, ~5.57s @ 96kHz, ~2.78s @ 192kHz)
    static constexpr size_t STAGE0_BLOCK = 512;
    static constexpr size_t STAGE0_SEGMENTS = 4;
    static constexpr size_t STAGE1_BLOCK = 2048;
    static constexpr size_t STAGE1_SEGMENTS = 4;
    static constexpr size_t STAGE2_BLOCK = 8192;
    static constexpr size_t STAGE2_SEGMENTS = 64;
    static constexpr size_t MAX_INPUT_HIST = STAGE2_BLOCK; // 8192
    static constexpr size_t MAX_KERNEL_FRAMES =
        STAGE0_BLOCK * STAGE0_SEGMENTS +
        STAGE1_BLOCK * STAGE1_SEGMENTS +
        STAGE2_BLOCK * STAGE2_SEGMENTS; // 534,528

    FFTConvolverDSP() {
        setSampleRate(48000.0f);
        dry_delay_l_.assign(BLOCK_SIZE, 0.0);
        dry_delay_r_.assign(BLOCK_SIZE, 0.0);
        dry_delay_len_ = BLOCK_SIZE;
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

    bool isActive() const {
        return has_ir_.load(std::memory_order_acquire) &&
               (enabled_.load(std::memory_order_relaxed) || fade_progress_ > 0.0f);
    }

    void setWetLevel(float wet) {
        target_wet_level_.store(std::clamp(wet, 0.0f, 1.0f), std::memory_order_relaxed);
    }

    float getWetLevel() const { return target_wet_level_.load(std::memory_order_relaxed); }

    void setDryLevel(float dry) {
        target_dry_level_.store(std::clamp(dry, 0.0f, 1.0f), std::memory_order_relaxed);
    }

    float getDryLevel() const { return target_dry_level_.load(std::memory_order_relaxed); }

    // Load Impulse Response:
    //   channels == 1: mono (applied to both L and R)
    //   channels == 2: dual-mono stereo [L, R]
    //   channels == 4: true-stereo matrix [LL, LR, RL, RR]
    // extra_wet_delay_samples aligns dry delay compensation with any pre-padding
    // added during linear-phase IR resampling.
    bool loadImpulseResponse(const float* ir_samples,
                             uint32_t frame_count,
                             uint32_t channels,
                             uint32_t extra_wet_delay_samples = 0,
                             bool apply_peak_norm = true) {
        if (!ir_samples || frame_count == 0 || (channels != 1 && channels != 2 && channels != 4)) {
            clearImpulseResponse();
            return false;
        }

        const uint32_t loaded_frames = std::min<uint32_t>(
            frame_count, static_cast<uint32_t>(MAX_KERNEL_FRAMES));
        const bool truncated = (frame_count > loaded_frames);

        // 1. Optional time-domain peak normalization across all active channels
        // identically so interaural level differences (ILD) are preserved.
        float norm_scale = 1.0f;
        if (apply_peak_norm) {
            float max_peak = 0.0f;
            const size_t total_samples = static_cast<size_t>(loaded_frames) * channels;
            for (size_t i = 0; i < total_samples; ++i) {
                const float v = std::abs(ir_samples[i]);
                if (v > max_peak) max_peak = v;
            }
            if (max_peak > 1.0f) {
                norm_scale = 1.0f / max_peak;
            }
        }

        // 2. Build all 3 NUPOLS stages in local staging objects OUTSIDE ir_mutex_.
        StageData staged[3];
        buildStage(staged[0], STAGE0_BLOCK, 0, STAGE0_SEGMENTS, 0,
                   ir_samples, loaded_frames, channels, norm_scale);
        buildStage(staged[1], STAGE1_BLOCK, STAGE0_BLOCK * STAGE0_SEGMENTS, STAGE1_SEGMENTS, 512,
                   ir_samples, loaded_frames, channels, norm_scale);
        buildStage(staged[2], STAGE2_BLOCK,
                   STAGE0_BLOCK * STAGE0_SEGMENTS + STAGE1_BLOCK * STAGE1_SEGMENTS,
                   STAGE2_SEGMENTS, 2560,
                   ir_samples, loaded_frames, channels, norm_scale);

        const size_t new_dry_len = BLOCK_SIZE + static_cast<size_t>(extra_wet_delay_samples);
        std::vector<double> new_dry_l(new_dry_len, 0.0);
        std::vector<double> new_dry_r(new_dry_len, 0.0);

        // 3. Swap into place under ir_mutex_ (microseconds).
        {
            std::lock_guard<std::mutex> lock(ir_mutex_);
            const bool is_hot_swap = has_ir_.load(std::memory_order_acquire) && (loaded_frames_ > 0);

            input_frames_ = frame_count;
            loaded_frames_ = loaded_frames;
            was_truncated_ = truncated;
            ir_channels_ = channels;
            extra_wet_delay_samples_ = extra_wet_delay_samples;

            for (size_t s = 0; s < 3; ++s) {
                if (is_hot_swap &&
                    stages_[s].num_segments > 0 &&
                    stages_[s].num_segments == staged[s].num_segments &&
                    stages_[s].block_size == staged[s].block_size) {
                    // Preserve warm FDL & pending overlap-add tail on matching-shape hot swap
                    staged[s].fdl_l = std::move(stages_[s].fdl_l);
                    staged[s].fdl_r = std::move(stages_[s].fdl_r);
                    staged[s].fdl_head = stages_[s].fdl_head;
                    staged[s].out_ring_l = std::move(stages_[s].out_ring_l);
                    staged[s].out_ring_r = std::move(stages_[s].out_ring_r);
                }
                stages_[s] = std::move(staged[s]);
            }

            if (is_hot_swap) {
                if (dry_delay_len_ != new_dry_len) {
                    dry_delay_l_ = std::move(new_dry_l);
                    dry_delay_r_ = std::move(new_dry_r);
                    dry_delay_len_ = new_dry_len;
                    dry_delay_pos_ = 0;
                }
                swap_fade_active_ = true;
                swap_fade_hold_samples_ = static_cast<uint32_t>(0.005f * sample_rate_);
            } else {
                dry_delay_l_ = std::move(new_dry_l);
                dry_delay_r_ = std::move(new_dry_r);
                dry_delay_len_ = new_dry_len;
                dry_delay_pos_ = 0;
                resetInternalBuffers();
                fade_progress_ = 0.0f;
            }
            has_ir_.store(true, std::memory_order_release);
        }
        return true;
    }

    void clearImpulseResponse() {
        std::lock_guard<std::mutex> lock(ir_mutex_);
        has_ir_.store(false, std::memory_order_release);
        input_frames_ = 0;
        loaded_frames_ = 0;
        was_truncated_ = false;
        ir_channels_ = 1;
        extra_wet_delay_samples_ = 0;
        for (size_t s = 0; s < 3; ++s) {
            stages_[s] = StageData{};
        }
        dry_delay_l_.assign(BLOCK_SIZE, 0.0);
        dry_delay_r_.assign(BLOCK_SIZE, 0.0);
        dry_delay_len_ = BLOCK_SIZE;
        dry_delay_pos_ = 0;
        resetInternalBuffers();
        fade_progress_ = 0.0f;
    }

    bool hasImpulseResponse() const { return has_ir_.load(std::memory_order_acquire); }
    size_t getKernelLength() const {
        std::lock_guard<std::mutex> lock(ir_mutex_);
        return loaded_frames_;
    }
    uint32_t getInputFrames() const {
        std::lock_guard<std::mutex> lock(ir_mutex_);
        return input_frames_;
    }
    uint32_t getLoadedFrames() const {
        std::lock_guard<std::mutex> lock(ir_mutex_);
        return loaded_frames_;
    }
    bool wasTruncated() const {
        std::lock_guard<std::mutex> lock(ir_mutex_);
        return was_truncated_;
    }
    uint32_t getChannels() const {
        std::lock_guard<std::mutex> lock(ir_mutex_);
        return ir_channels_;
    }
    size_t getLatencySamples() const {
        std::lock_guard<std::mutex> lock(ir_mutex_);
        return BLOCK_SIZE + static_cast<size_t>(extra_wet_delay_samples_);
    }
    static constexpr size_t getMaxKernelFrames() { return MAX_KERNEL_FRAMES; }

    void reset() {
        std::lock_guard<std::mutex> lock(ir_mutex_);
        resetInternalBuffers();
        current_wet_level_ = target_wet_level_.load(std::memory_order_relaxed);
        current_dry_level_ = target_dry_level_.load(std::memory_order_relaxed);
        fade_progress_ = 0.0f;
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
    struct StageData {
        size_t block_size = 0;
        size_t fft_size = 0;
        size_t half_bins = 0;
        size_t ir_offset = 0;
        size_t num_segments = 0;
        size_t output_delay = 0;
        size_t ring_size = 0;
        size_t ring_mask = 0;
        size_t fdl_head = 0;

        // Partitioned Hermitian half-spectrum IRs (num_segments * half_bins)
        std::vector<std::complex<double>> ir_ll; // also mono
        std::vector<std::complex<double>> ir_rr; // stereo R or true-stereo RR
        std::vector<std::complex<double>> ir_lr; // true-stereo L -> R
        std::vector<std::complex<double>> ir_rl; // true-stereo R -> L

        // Frequency Delay Lines (num_segments * half_bins)
        std::vector<std::complex<double>> fdl_l;
        std::vector<std::complex<double>> fdl_r;

        // Overlap-add output rings indexed by global sample_clock_ & ring_mask
        std::vector<double> out_ring_l;
        std::vector<double> out_ring_r;

        // Scratch & twiddle tables (allocated off-lock when stage is active)
        std::vector<double> scratch_time_l;
        std::vector<double> scratch_time_r;
        std::vector<std::complex<double>> scratch_freq_l;
        std::vector<std::complex<double>> scratch_freq_r;
        std::vector<std::complex<double>> accum_l;
        std::vector<std::complex<double>> accum_r;
        std::vector<std::complex<double>> scratch_ifft;
        std::vector<std::complex<double>> twiddles;
        std::vector<size_t> bit_rev;
    };

    static size_t nextPow2(size_t v) {
        size_t p = 1;
        while (p < v) p <<= 1;
        return p;
    }

    static void initStageTables(StageData& st) {
        const size_t n = st.fft_size;
        st.twiddles.resize(n);
        st.bit_rev.resize(n);
        constexpr double PI = 3.14159265358979323846;
        for (size_t i = 0; i < n; ++i) {
            const double angle = -2.0 * PI * static_cast<double>(i) / static_cast<double>(n);
            st.twiddles[i] = std::complex<double>(std::cos(angle), std::sin(angle));
        }
        const size_t bits = static_cast<size_t>(std::round(std::log2(static_cast<double>(n))));
        for (size_t i = 0; i < n; ++i) {
            size_t rev = 0;
            for (size_t b = 0; b < bits; ++b) {
                if ((i >> b) & 1u) {
                    rev |= (static_cast<size_t>(1) << (bits - 1 - b));
                }
            }
            st.bit_rev[i] = rev;
        }

        st.scratch_time_l.assign(n, 0.0);
        st.scratch_time_r.assign(n, 0.0);
        st.scratch_freq_l.assign(n, std::complex<double>(0.0, 0.0));
        st.scratch_freq_r.assign(n, std::complex<double>(0.0, 0.0));
        st.accum_l.assign(n, std::complex<double>(0.0, 0.0));
        st.accum_r.assign(n, std::complex<double>(0.0, 0.0));
        st.scratch_ifft.assign(n, std::complex<double>(0.0, 0.0));
    }

    static void forwardFFT(const StageData& st,
                           const double* time_in,
                           std::complex<double>* freq_out) {
        const size_t n = st.fft_size;
        for (size_t i = 0; i < n; ++i) {
            freq_out[st.bit_rev[i]] = std::complex<double>(time_in[i], 0.0);
        }
        for (size_t len = 2; len <= n; len <<= 1) {
            const size_t half_len = len >> 1;
            const size_t step = n / len;
            for (size_t i = 0; i < n; i += len) {
                for (size_t j = 0; j < half_len; ++j) {
                    const std::complex<double> u = freq_out[i + j];
                    const std::complex<double> v = freq_out[i + j + half_len] * st.twiddles[j * step];
                    freq_out[i + j] = u + v;
                    freq_out[i + j + half_len] = u - v;
                }
            }
        }
    }

    static void inverseFFTHermitian(StageData& st,
                                    std::complex<double>* freq_half_in,
                                    double* time_out) {
        const size_t n = st.fft_size;
        // Reconstruct upper conjugate-symmetric bins from Hermitian half-spectrum
        for (size_t k = 1; k < st.block_size; ++k) {
            freq_half_in[n - k] = std::conj(freq_half_in[k]);
        }

        std::complex<double>* temp = st.scratch_ifft.data();
        for (size_t i = 0; i < n; ++i) {
            temp[st.bit_rev[i]] = freq_half_in[i];
        }
        for (size_t len = 2; len <= n; len <<= 1) {
            const size_t half_len = len >> 1;
            const size_t step = n / len;
            for (size_t i = 0; i < n; i += len) {
                for (size_t j = 0; j < half_len; ++j) {
                    const std::complex<double> u = temp[i + j];
                    const std::complex<double> tw = st.twiddles[j * step];
                    const std::complex<double> w(tw.real(), -tw.imag());
                    const std::complex<double> v = temp[i + j + half_len] * w;
                    temp[i + j] = u + v;
                    temp[i + j + half_len] = u - v;
                }
            }
        }
        const double inv_n = 1.0 / static_cast<double>(n);
        for (size_t i = 0; i < n; ++i) {
            time_out[i] = temp[i].real() * inv_n;
        }
    }

    static void buildStage(StageData& st,
                           size_t block_size,
                           size_t ir_offset,
                           size_t max_segments,
                           size_t output_delay,
                           const float* ir_samples,
                           uint32_t frame_count,
                           uint32_t channels,
                           float norm_scale) {
        if (frame_count <= ir_offset) {
            st = StageData{};
            return;
        }
        const size_t remaining = static_cast<size_t>(frame_count) - ir_offset;
        size_t num_seg = (remaining + block_size - 1) / block_size;
        if (num_seg > max_segments) num_seg = max_segments;
        if (num_seg == 0) {
            st = StageData{};
            return;
        }

        st.block_size = block_size;
        st.fft_size = block_size * 2;
        st.half_bins = block_size + 1;
        st.ir_offset = ir_offset;
        st.num_segments = num_seg;
        st.output_delay = output_delay;
        st.ring_size = nextPow2(output_delay + st.fft_size);
        st.ring_mask = st.ring_size - 1;
        st.fdl_head = 0;

        initStageTables(st);

        const size_t part_elems = num_seg * st.half_bins;
        st.ir_ll.resize(part_elems);
        if (channels >= 2) st.ir_rr.resize(part_elems);
        if (channels == 4) {
            st.ir_lr.resize(part_elems);
            st.ir_rl.resize(part_elems);
        }

        st.fdl_l.assign(part_elems, std::complex<double>(0.0, 0.0));
        st.fdl_r.assign(part_elems, std::complex<double>(0.0, 0.0));
        st.out_ring_l.assign(st.ring_size, 0.0);
        st.out_ring_r.assign(st.ring_size, 0.0);

        std::vector<double> time_block(st.fft_size, 0.0);
        std::vector<std::complex<double>> freq_block(st.fft_size);
        const double d_scale = static_cast<double>(norm_scale);

        auto encodeChannel = [&](uint32_t ch_idx, std::vector<std::complex<double>>& dst) {
            for (size_t seg = 0; seg < num_seg; ++seg) {
                const size_t seg_offset = ir_offset + seg * block_size;
                std::fill(time_block.begin(), time_block.end(), 0.0);
                for (size_t i = 0; i < block_size; ++i) {
                    const size_t frame_idx = seg_offset + i;
                    if (frame_idx < frame_count) {
                        time_block[i] = static_cast<double>(ir_samples[frame_idx * channels + ch_idx]) * d_scale;
                    }
                }
                forwardFFT(st, time_block.data(), freq_block.data());
                std::memcpy(&dst[seg * st.half_bins], freq_block.data(),
                            st.half_bins * sizeof(std::complex<double>));
            }
        };

        if (channels == 1) {
            encodeChannel(0, st.ir_ll);
        } else if (channels == 2) {
            encodeChannel(0, st.ir_ll);
            encodeChannel(1, st.ir_rr);
        } else { // channels == 4: [LL, LR, RL, RR]
            encodeChannel(0, st.ir_ll);
            encodeChannel(1, st.ir_lr);
            encodeChannel(2, st.ir_rl);
            encodeChannel(3, st.ir_rr);
        }
    }

    template <typename T>
    void processImpl(T* interleaved_samples, uint32_t frame_count) {
        const bool is_enabled = enabled_.load(std::memory_order_relaxed);
        if (!is_enabled && fade_progress_ <= 0.0f) return;
        if (!has_ir_.load(std::memory_order_acquire) || frame_count == 0 || !interleaved_samples) return;

        // Try lock without blocking the real-time audio thread
        std::unique_lock<std::mutex> lock(ir_mutex_, std::try_to_lock);
        if (!lock.owns_lock() || !has_ir_.load(std::memory_order_acquire) || loaded_frames_ == 0) return;

        uint32_t processed_frames = 0;
        const float targetWet = target_wet_level_.load(std::memory_order_relaxed);
        const float targetDry = target_dry_level_.load(std::memory_order_relaxed);
        const bool s1_active = (stages_[1].num_segments > 0);
        const bool s2_active = (stages_[2].num_segments > 0);

        while (processed_frames < frame_count) {
            const uint32_t cur_in_pos = static_cast<uint32_t>(sample_clock_ & (BLOCK_SIZE - 1));
            const uint32_t frames_to_copy = std::min(
                static_cast<uint32_t>(BLOCK_SIZE) - cur_in_pos,
                frame_count - processed_frames);

            for (uint32_t i = 0; i < frames_to_copy; ++i) {
                const uint32_t in_idx = (processed_frames + i) * 2;
                const double dry_in_l = static_cast<double>(interleaved_samples[in_idx]);
                const double dry_in_r = static_cast<double>(interleaved_samples[in_idx + 1]);

                // Dry delay compensation buffer (BLOCK_SIZE + extra_wet_delay_samples_)
                const double dry_delayed_l = dry_delay_l_[dry_delay_pos_];
                const double dry_delayed_r = dry_delay_r_[dry_delay_pos_];
                dry_delay_l_[dry_delay_pos_] = dry_in_l;
                dry_delay_r_[dry_delay_pos_] = dry_in_r;
                dry_delay_pos_ = (dry_delay_pos_ + 1 < dry_delay_len_) ? (dry_delay_pos_ + 1) : 0;

                // Record input sample into shared circular history
                const size_t hist_idx = sample_clock_ & (MAX_INPUT_HIST - 1);
                hist_in_l_[hist_idx] = dry_in_l;
                hist_in_r_[hist_idx] = dry_in_r;

                // Sum and clear wet outputs from all active NUPOLS stage rings
                double wet_l = 0.0;
                double wet_r = 0.0;
                if (stages_[0].num_segments > 0) {
                    const size_t r0 = sample_clock_ & stages_[0].ring_mask;
                    wet_l += stages_[0].out_ring_l[r0];
                    wet_r += stages_[0].out_ring_r[r0];
                    stages_[0].out_ring_l[r0] = 0.0;
                    stages_[0].out_ring_r[r0] = 0.0;
                }
                if (s1_active) {
                    const size_t r1 = sample_clock_ & stages_[1].ring_mask;
                    wet_l += stages_[1].out_ring_l[r1];
                    wet_r += stages_[1].out_ring_r[r1];
                    stages_[1].out_ring_l[r1] = 0.0;
                    stages_[1].out_ring_r[r1] = 0.0;
                }
                if (s2_active) {
                    const size_t r2 = sample_clock_ & stages_[2].ring_mask;
                    wet_l += stages_[2].out_ring_l[r2];
                    wet_r += stages_[2].out_ring_r[r2];
                    stages_[2].out_ring_l[r2] = 0.0;
                    stages_[2].out_ring_r[r2] = 0.0;
                }

                // De-zipper / smoothly interpolate wet & dry levels per sample
                current_wet_level_ += smoothing_coeff_ * (targetWet - current_wet_level_);
                current_dry_level_ += smoothing_coeff_ * (targetDry - current_dry_level_);

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

                // IR hot-swap micro-fade
                float swap_gain = 1.0f;
                if (swap_fade_active_) {
                    constexpr float SWAP_DIP = 0.35f;
                    if (swap_fade_hold_samples_ > 0) {
                        if (swap_gain_depth_ < 1.0f) {
                            swap_gain_depth_ = std::min(1.0f, swap_gain_depth_ + 2.0f * crossfade_step_);
                        } else {
                            swap_fade_hold_samples_--;
                        }
                        swap_gain = 1.0f - (1.0f - SWAP_DIP) * swap_gain_depth_;
                    } else {
                        if (swap_gain_depth_ > 0.0f) {
                            swap_gain_depth_ = std::max(0.0f, swap_gain_depth_ - 2.0f * crossfade_step_);
                        } else {
                            swap_fade_active_ = false;
                        }
                        swap_gain = 1.0f - (1.0f - SWAP_DIP) * swap_gain_depth_;
                    }
                }

                const double fade = static_cast<double>(fade_progress_);
                const double dry_mix_l = (1.0 - fade) * dry_in_l + (static_cast<double>(current_dry_level_) * fade) * dry_delayed_l;
                const double dry_mix_r = (1.0 - fade) * dry_in_r + (static_cast<double>(current_dry_level_) * fade) * dry_delayed_r;
                const double eff_wet = static_cast<double>(current_wet_level_) * fade * static_cast<double>(swap_gain);

                interleaved_samples[in_idx]     = static_cast<T>(dry_mix_l + (wet_l * eff_wet));
                interleaved_samples[in_idx + 1] = static_cast<T>(dry_mix_r + (wet_r * eff_wet));

                ++sample_clock_;
            }

            processed_frames += frames_to_copy;

            // All stage block sizes (512, 2048, 8192) are multiples of 512,
            // so triggers align cleanly with 512-sample chunk boundaries.
            if ((sample_clock_ & (STAGE0_BLOCK - 1)) == 0) {
                if (stages_[0].num_segments > 0) {
                    processStage(stages_[0]);
                }
                if (s1_active && (sample_clock_ & (STAGE1_BLOCK - 1)) == 0) {
                    processStage(stages_[1]);
                }
                if (s2_active && (sample_clock_ & (STAGE2_BLOCK - 1)) == 0) {
                    processStage(stages_[2]);
                }
            }
        }
    }

    void processStage(StageData& st) {
        const size_t b = st.block_size;
        const size_t hb = st.half_bins;
        const size_t num_seg = st.num_segments;

        // 1. Copy the latest b samples from shared circular input history and zero-pad.
        // Because sample_clock_ is a multiple of b and b divides MAX_INPUT_HIST (8192),
        // [hist_start .. hist_start + b - 1] is guaranteed contiguous in hist_in_.
        const size_t hist_start = (sample_clock_ - b) & (MAX_INPUT_HIST - 1);
        std::memcpy(st.scratch_time_l.data(), &hist_in_l_[hist_start], b * sizeof(double));
        std::memset(st.scratch_time_l.data() + b, 0, b * sizeof(double));

        std::memcpy(st.scratch_time_r.data(), &hist_in_r_[hist_start], b * sizeof(double));
        std::memset(st.scratch_time_r.data() + b, 0, b * sizeof(double));

        // 2. Forward FFT on input block and store Hermitian half-spectrum in FDL
        forwardFFT(st, st.scratch_time_l.data(), st.scratch_freq_l.data());
        forwardFFT(st, st.scratch_time_r.data(), st.scratch_freq_r.data());

        std::memcpy(&st.fdl_l[st.fdl_head * hb], st.scratch_freq_l.data(),
                    hb * sizeof(std::complex<double>));
        std::memcpy(&st.fdl_r[st.fdl_head * hb], st.scratch_freq_r.data(),
                    hb * sizeof(std::complex<double>));

        // 3. Hermitian half-spectrum MAC across all segments in this stage
        std::complex<double>* acc_l = st.accum_l.data();
        std::complex<double>* acc_r = st.accum_r.data();
        std::fill(acc_l, acc_l + hb, std::complex<double>(0.0, 0.0));
        std::fill(acc_r, acc_r + hb, std::complex<double>(0.0, 0.0));

        if (ir_channels_ == 4) {
            for (size_t seg = 0; seg < num_seg; ++seg) {
                const size_t fdl_slot = (st.fdl_head + num_seg - seg) % num_seg;
                const std::complex<double>* in_l = &st.fdl_l[fdl_slot * hb];
                const std::complex<double>* in_r = &st.fdl_r[fdl_slot * hb];
                const std::complex<double>* ir_ll = &st.ir_ll[seg * hb];
                const std::complex<double>* ir_lr = &st.ir_lr[seg * hb];
                const std::complex<double>* ir_rl = &st.ir_rl[seg * hb];
                const std::complex<double>* ir_rr = &st.ir_rr[seg * hb];

                for (size_t k = 0; k < hb; ++k) {
                    acc_l[k] += in_l[k] * ir_ll[k] + in_r[k] * ir_rl[k];
                    acc_r[k] += in_l[k] * ir_lr[k] + in_r[k] * ir_rr[k];
                }
            }
        } else {
            const bool is_stereo = (ir_channels_ == 2);
            for (size_t seg = 0; seg < num_seg; ++seg) {
                const size_t fdl_slot = (st.fdl_head + num_seg - seg) % num_seg;
                const std::complex<double>* in_l = &st.fdl_l[fdl_slot * hb];
                const std::complex<double>* in_r = &st.fdl_r[fdl_slot * hb];
                const std::complex<double>* ir_l = &st.ir_ll[seg * hb];
                const std::complex<double>* ir_r = is_stereo ? &st.ir_rr[seg * hb] : ir_l;

                for (size_t k = 0; k < hb; ++k) {
                    acc_l[k] += in_l[k] * ir_l[k];
                    acc_r[k] += in_r[k] * ir_r[k];
                }
            }
        }

        st.fdl_head = (st.fdl_head + 1) % num_seg;

        // 4. Inverse FFT (reconstructing conjugate upper half)
        inverseFFTHermitian(st, acc_l, st.scratch_time_l.data());
        inverseFFTHermitian(st, acc_r, st.scratch_time_r.data());

        // 5. Overlap-add into stage's output ring at sample_clock_ + output_delay
        const size_t write_base = sample_clock_ + st.output_delay;
        const size_t mask = st.ring_mask;
        const double* tl = st.scratch_time_l.data();
        const double* tr = st.scratch_time_r.data();
        double* rl = st.out_ring_l.data();
        double* rr = st.out_ring_r.data();

        for (size_t i = 0; i < st.fft_size; ++i) {
            const size_t idx = (write_base + i) & mask;
            rl[idx] += tl[i];
            rr[idx] += tr[i];
        }
    }

    void resetInternalBuffers() {
        std::memset(hist_in_l_, 0, sizeof(hist_in_l_));
        std::memset(hist_in_r_, 0, sizeof(hist_in_r_));
        if (!dry_delay_l_.empty()) std::fill(dry_delay_l_.begin(), dry_delay_l_.end(), 0.0);
        if (!dry_delay_r_.empty()) std::fill(dry_delay_r_.begin(), dry_delay_r_.end(), 0.0);
        dry_delay_pos_ = 0;
        sample_clock_ = 0;
        for (size_t s = 0; s < 3; ++s) {
            StageData& st = stages_[s];
            if (!st.fdl_l.empty()) std::fill(st.fdl_l.begin(), st.fdl_l.end(), std::complex<double>(0.0, 0.0));
            if (!st.fdl_r.empty()) std::fill(st.fdl_r.begin(), st.fdl_r.end(), std::complex<double>(0.0, 0.0));
            if (!st.out_ring_l.empty()) std::fill(st.out_ring_l.begin(), st.out_ring_l.end(), 0.0);
            if (!st.out_ring_r.empty()) std::fill(st.out_ring_r.begin(), st.out_ring_r.end(), 0.0);
            st.fdl_head = 0;
        }
        swap_fade_active_ = false;
        swap_gain_depth_ = 0.0f;
        swap_fade_hold_samples_ = 0;
    }

    std::atomic<bool> enabled_{false};
    std::atomic<bool> has_ir_{false}; // read lock-free by process() fast-path
    float fade_progress_{0.0f};
    float crossfade_step_{0.001f};

    // Hot-swap micro-fade state (dip-and-return on IR replacement)
    bool swap_fade_active_{false};
    float swap_gain_depth_{0.0f};
    uint32_t swap_fade_hold_samples_{0};

    float sample_rate_{48000.0f};
    float sample_period_{1.0f / 48000.0f};
    std::atomic<float> target_wet_level_{1.0f};
    float current_wet_level_{1.0f};
    std::atomic<float> target_dry_level_{0.0f};
    float current_dry_level_{0.0f};
    float smoothing_coeff_{0.002f};

    mutable std::mutex ir_mutex_;
    uint32_t input_frames_{0};
    uint32_t loaded_frames_{0};
    bool was_truncated_{false};
    uint32_t ir_channels_{1};
    uint32_t extra_wet_delay_samples_{0};

    StageData stages_[3]{};

    // Shared circular input history for all stages (8192 samples)
    double hist_in_l_[MAX_INPUT_HIST]{};
    double hist_in_r_[MAX_INPUT_HIST]{};
    size_t sample_clock_{0};

    // Dynamic dry delay compensation ring (BLOCK_SIZE + extra_wet_delay_samples_)
    std::vector<double> dry_delay_l_;
    std::vector<double> dry_delay_r_;
    size_t dry_delay_len_{BLOCK_SIZE};
    size_t dry_delay_pos_{0};
};

} // namespace sauti::dsp
