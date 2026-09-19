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
// with Zero-Latency Seamless Dry/Wet Crossfading, Double-Buffered Ping-Pong
// IR Swapping, and Spectral Peak-Frequency Normalization (Anti-Crackling/Anti-Pop)
// =============================================================================
class FFTConvolverDSP {
public:
    static constexpr size_t BLOCK_SIZE = 512;
    static constexpr size_t FFT_SIZE = BLOCK_SIZE * 2; // 1024-point FFT for 512-sample blocks
    static constexpr size_t MAX_SEGMENTS = 128;        // Up to ~1.36 seconds of impulse response at 48kHz
    static constexpr size_t ANALYSIS_FFT_SIZE = 4096;  // High-resolution spectral analysis for peak gain

    FFTConvolverDSP() {
        setSampleRate(48000.0f);
        initTwiddles();
        reset();
    }

    void setSampleRate(float sampleRate) {
        if (sampleRate <= 0.0f) sampleRate = 48000.0f;
        sample_rate_ = sampleRate;
        sample_period_ = 1.0f / sample_rate_;
        smoothing_coeff_ = 1.0f - std::exp(-1.0f / (0.020f * sample_rate_)); // 20ms level smoothing
        crossfade_step_ = 1.0f / (0.020f * sample_rate_);                   // 20ms seamless crossfade rate
    }

    void setEnabled(bool enabled) {
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

        // 1. Time-Domain Peak & RMS Energy
        float max_time_peak = 0.0f;
        float energy_sum = 0.0f;
        for (uint32_t i = 0; i < frame_count; i++) {
            float l = (channels == 1) ? ir_samples[i] : ir_samples[i * 2];
            float r = (channels == 1) ? ir_samples[i] : ir_samples[i * 2 + 1];
            max_time_peak = std::max(max_time_peak, std::max(std::abs(l), std::abs(r)));
            energy_sum += (l * l + r * r) * 0.5f;
        }

        // 2. High-Resolution Frequency-Domain Spectral Analysis to detect resonant boosts (e.g. Dolby/AutoEQ bass boosts)
        float max_freq_gain = analyzeMaxFrequencyGain(ir_samples, frame_count, channels);

        // Determine safe normalization scale so that the filter response NEVER clips digital full scale
        float norm_scale = 1.0f;
        if (max_time_peak > 1.0f) {
            norm_scale = std::min(norm_scale, 1.0f / max_time_peak);
        }
        if (max_freq_gain > 1.0f) {
            norm_scale = std::min(norm_scale, 1.0f / max_freq_gain);
        }
        if (energy_sum > 16.0f) {
            norm_scale = std::min(norm_scale, std::sqrt(16.0f / energy_sum));
        }

        uint32_t num_segments = (frame_count + BLOCK_SIZE - 1) / BLOCK_SIZE;
        if (num_segments > MAX_SEGMENTS) {
            num_segments = MAX_SEGMENTS;
        }

        // 3. Pre-allocate and compute FFT partitions in local staging vectors OUTSIDE the lock
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

        // 4. Double-Buffered Setup: Place into standby slot and initiate ping-pong crossfade
        {
            std::lock_guard<std::mutex> lock(ir_mutex_);
            int target_slot = 1 - active_slot_;
            Slot& target = slots_[target_slot];

            target.segments_count = num_segments;
            target.ir_channels = channels;
            target.partitions_l = std::move(new_partitions_l);
            target.partitions_r = std::move(new_partitions_r);
            target.fdl_l.assign(num_segments * FFT_SIZE, std::complex<float>(0.0f, 0.0f));
            target.fdl_r.assign(num_segments * FFT_SIZE, std::complex<float>(0.0f, 0.0f));
            target.fdl_head = 0;
            std::memset(target.out_buf_l, 0, sizeof(target.out_buf_l));
            std::memset(target.out_buf_r, 0, sizeof(target.out_buf_r));
            target.has_output = false;
            target.active = true;

            if (slots_[active_slot_].active && has_ir_) {
                // Smooth equal-power crossfade from active to standby
                crossfading_ = true;
                crossfade_progress_ = 0.0f;
                pending_slot_ = target_slot;
            } else {
                // Initial load: activate target slot directly
                active_slot_ = target_slot;
                crossfading_ = false;
                fade_progress_ = 0.0f;
            }
            has_ir_ = true;
        }
        return true;
    }

    void clearImpulseResponse() {
        std::lock_guard<std::mutex> lock(ir_mutex_);
        has_ir_ = false;
        slots_[0].reset();
        slots_[1].reset();
        crossfading_ = false;
        fade_progress_ = 0.0f;
    }

    bool hasImpulseResponse() const { return has_ir_; }

    size_t getKernelLength() const {
        std::lock_guard<std::mutex> lock(ir_mutex_);
        return slots_[active_slot_].segments_count * BLOCK_SIZE;
    }

    void reset() {
        std::lock_guard<std::mutex> lock(ir_mutex_);
        std::memset(in_buf_l_, 0, sizeof(in_buf_l_));
        std::memset(in_buf_r_, 0, sizeof(in_buf_r_));
        in_pos_ = 0;
        slots_[0].reset();
        slots_[1].reset();
        active_slot_ = 0;
        pending_slot_ = 1;
        crossfading_ = false;
        fade_progress_ = 0.0f;
        current_wet_level_ = target_wet_level_;
        current_dry_level_ = target_dry_level_;
    }

    // Process interleaved stereo samples: [L0, R0, L1, R1, ...]
    void process(float* interleaved_samples, uint32_t frame_count) {
        const bool is_enabled = enabled_.load(std::memory_order_relaxed);
        if (!is_enabled && fade_progress_ <= 0.0f) return;
        if (!has_ir_ || frame_count == 0 || !interleaved_samples) return;

        // Non-blocking try_lock on realtime audio thread
        std::unique_lock<std::mutex> lock(ir_mutex_, std::try_to_lock);
        if (!lock.owns_lock() || !has_ir_) return;

        uint32_t processed_frames = 0;

        while (processed_frames < frame_count) {
            uint32_t frames_to_copy = std::min(static_cast<uint32_t>(BLOCK_SIZE - in_pos_), frame_count - processed_frames);

            Slot& active = slots_[active_slot_];

            for (uint32_t i = 0; i < frames_to_copy; i++) {
                uint32_t in_idx = (processed_frames + i) * 2;
                float dry_in_l = interleaved_samples[in_idx];
                float dry_in_r = interleaved_samples[in_idx + 1];

                in_buf_l_[in_pos_ + i] = dry_in_l;
                in_buf_r_[in_pos_ + i] = dry_in_r;

                // De-zipper / smoothly interpolate wet & dry levels per sample
                current_wet_level_ += smoothing_coeff_ * (target_wet_level_ - current_wet_level_);
                current_dry_level_ += smoothing_coeff_ * (target_dry_level_ - current_dry_level_);

                float wet_l = 0.0f;
                float wet_r = 0.0f;

                if (crossfading_) {
                    Slot& pending = slots_[pending_slot_];
                    float alpha = crossfade_progress_;
                    float wet_a_l = active.out_buf_l[in_pos_ + i];
                    float wet_a_r = active.out_buf_r[in_pos_ + i];
                    float wet_b_l = pending.out_buf_l[in_pos_ + i];
                    float wet_b_r = pending.out_buf_r[in_pos_ + i];

                    wet_l = (1.0f - alpha) * wet_a_l + alpha * wet_b_l;
                    wet_r = (1.0f - alpha) * wet_a_r + alpha * wet_b_r;

                    crossfade_progress_ = std::min(1.0f, crossfade_progress_ + crossfade_step_);
                    if (crossfade_progress_ >= 1.0f) {
                        crossfading_ = false;
                        active.active = false;
                        active_slot_ = pending_slot_;
                    }
                } else {
                    wet_l = active.out_buf_l[in_pos_ + i];
                    wet_r = active.out_buf_r[in_pos_ + i];
                }

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

                // Seamless blend: 100% dry when fade == 0, full convolver mix when fade == 1
                const float fade = fade_progress_;
                const float eff_dry = (1.0f - fade) + (current_dry_level_ * fade);
                const float eff_wet = current_wet_level_ * fade;

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
    struct Slot {
        uint32_t segments_count{0};
        uint32_t ir_channels{1};
        std::vector<std::complex<float>> partitions_l;
        std::vector<std::complex<float>> partitions_r;
        std::vector<std::complex<float>> fdl_l;
        std::vector<std::complex<float>> fdl_r;
        size_t fdl_head{0};
        float out_buf_l[FFT_SIZE]{};
        float out_buf_r[FFT_SIZE]{};
        bool active{false};
        bool has_output{false};

        void reset() {
            segments_count = 0;
            active = false;
            has_output = false;
            fdl_head = 0;
            partitions_l.clear();
            partitions_r.clear();
            fdl_l.clear();
            fdl_r.clear();
            std::memset(out_buf_l, 0, sizeof(out_buf_l));
            std::memset(out_buf_r, 0, sizeof(out_buf_r));
        }
    };

    std::atomic<bool> enabled_{false};
    bool has_ir_{false};
    float fade_progress_{0.0f};
    float crossfade_step_{0.001f};

    float sample_rate_{48000.0f};
    float sample_period_{1.0f / 48000.0f};
    float target_wet_level_{1.0f};
    float current_wet_level_{1.0f};
    float target_dry_level_{0.0f};
    float current_dry_level_{0.0f};
    float smoothing_coeff_{0.002f};

    mutable std::mutex ir_mutex_;
    Slot slots_[2];
    int active_slot_{0};
    int pending_slot_{1};
    bool crossfading_{false};
    float crossfade_progress_{0.0f};

    // Time-domain input gathering buffer
    float in_buf_l_[BLOCK_SIZE]{};
    float in_buf_r_[BLOCK_SIZE]{};
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

    float analyzeMaxFrequencyGain(const float* ir, uint32_t frames, uint32_t channels) {
        constexpr size_t N = ANALYSIS_FFT_SIZE;
        constexpr float PI = 3.14159265358979323846f;

        std::vector<std::complex<float>> tw(N);
        for (size_t i = 0; i < N; i++) {
            float angle = -2.0f * PI * static_cast<float>(i) / static_cast<float>(N);
            tw[i] = std::complex<float>(std::cos(angle), std::sin(angle));
        }
        std::vector<size_t> brev(N);
        for (size_t i = 0; i < N; i++) {
            size_t rev = 0;
            for (size_t b = 0; b < 12; b++) {
                if ((i >> b) & 1) rev |= (1 << (11 - b));
            }
            brev[i] = rev;
        }

        float max_mag = 0.0f;
        for (uint32_t ch = 0; ch < channels; ch++) {
            std::vector<std::complex<float>> freq(N);
            for (size_t i = 0; i < N; i++) {
                float s = (i < frames) ? ((channels == 1) ? ir[i] : ir[i * 2 + ch]) : 0.0f;
                freq[brev[i]] = std::complex<float>(s, 0.0f);
            }
            for (size_t len = 2; len <= N; len <<= 1) {
                size_t half = len >> 1;
                size_t step = N / len;
                for (size_t i = 0; i < N; i += len) {
                    for (size_t j = 0; j < half; j++) {
                        std::complex<float> u = freq[i + j];
                        std::complex<float> v = freq[i + j + half] * tw[j * step];
                        freq[i + j] = u + v;
                        freq[i + j + half] = u - v;
                    }
                }
            }
            for (size_t i = 0; i < N / 2; i++) {
                max_mag = std::max(max_mag, std::abs(freq[i]));
            }
        }
        return max_mag;
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

        // 2. Process active slot
        processSlot(slots_[active_slot_]);

        // 3. If in crossfade, also process pending slot
        if (crossfading_) {
            processSlot(slots_[pending_slot_]);
        }
    }

    void processSlot(Slot& slot) {
        if (!slot.active || slot.segments_count == 0) return;

        // Store input spectrum in current FDL slot
        std::memcpy(&slot.fdl_l[slot.fdl_head * FFT_SIZE], scratch_freq_l_, FFT_SIZE * sizeof(std::complex<float>));
        std::memcpy(&slot.fdl_r[slot.fdl_head * FFT_SIZE], scratch_freq_r_, FFT_SIZE * sizeof(std::complex<float>));

        // Frequency-domain complex multiply-accumulate across all IR partitions
        std::fill(accum_l_, accum_l_ + FFT_SIZE, std::complex<float>(0.0f, 0.0f));
        std::fill(accum_r_, accum_r_ + FFT_SIZE, std::complex<float>(0.0f, 0.0f));

        for (uint32_t seg = 0; seg < slot.segments_count; seg++) {
            size_t slot_idx = (slot.fdl_head + slot.segments_count - seg) % slot.segments_count;
            const float* in_ptr_l = reinterpret_cast<const float*>(&slot.fdl_l[slot_idx * FFT_SIZE]);
            const float* in_ptr_r = reinterpret_cast<const float*>(&slot.fdl_r[slot_idx * FFT_SIZE]);
            const float* ir_ptr_l = reinterpret_cast<const float*>(&slot.partitions_l[seg * FFT_SIZE]);
            const float* ir_ptr_r = (slot.ir_channels == 2)
                ? reinterpret_cast<const float*>(&slot.partitions_r[seg * FFT_SIZE])
                : ir_ptr_l;

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
        slot.fdl_head = (slot.fdl_head + 1) % slot.segments_count;

        // Inverse FFT on accumulated frequency spectrum
        inverseFFT(accum_l_, scratch_time_l_);
        inverseFFT(accum_r_, scratch_time_r_);

        // Overlap-Add into output buffer
        std::memcpy(slot.out_buf_l, slot.out_buf_l + BLOCK_SIZE, BLOCK_SIZE * sizeof(float));
        std::memset(slot.out_buf_l + BLOCK_SIZE, 0, BLOCK_SIZE * sizeof(float));

        std::memcpy(slot.out_buf_r, slot.out_buf_r + BLOCK_SIZE, BLOCK_SIZE * sizeof(float));
        std::memset(slot.out_buf_r + BLOCK_SIZE, 0, BLOCK_SIZE * sizeof(float));

        for (size_t i = 0; i < FFT_SIZE; i += 4) {
            SimdFloat4 out_l = SimdFloat4::load_u(&slot.out_buf_l[i]);
            SimdFloat4 scr_l = SimdFloat4::load_u(&scratch_time_l_[i]);
            (out_l + scr_l).store_u(&slot.out_buf_l[i]);

            SimdFloat4 out_r = SimdFloat4::load_u(&slot.out_buf_r[i]);
            SimdFloat4 scr_r = SimdFloat4::load_u(&scratch_time_r_[i]);
            (out_r + scr_r).store_u(&slot.out_buf_r[i]);
        }
        slot.has_output = true;
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
