#pragma once

#include <cmath>
#include <cstdint>
#include <algorithm>
#include <array>
#include <atomic>
#include <vector>
#include "denormals.h"
#include "simd_math.h"
#include "cytomic_svf_dsp.h"

namespace sauti::dsp {

// =============================================================================
// DynamicEqDSP: 6-Band Studio-Grade Dynamic Parametric Equalizer
//
// Features:
// - 6 independent, fully parametric dynamic bands across 20 Hz - 20 kHz.
// - Filter Types: Peak / Bell, Low-Shelf, High-Shelf.
// - Dynamic Modes:
//     - Static (traditional clean parametric EQ)
//     - Compress (dynamically cuts when band energy exceeds threshold)
//     - Expand (upward dynamic boost when band energy exceeds threshold)
// - Dedicated per-band 64-bit Cytomic TPT SVF sidechain filters with linked
//   multichannel peak detection (immune to L-R anti-phase cancellation).
// - Envelope follower with true attack (0.2-200 ms), release (5-2000 ms), and
//   soft knee (3 dB) for chatter-free dynamics without downstream smoothing lag.
// - Smoothed manual base-gain edits without resetting filter state across 0 dB.
// - Lock-free atomic per-band gain offset telemetry for real-time meters.
// - In-place 32-bit float and 64-bit double processing up to 16 channels.
// =============================================================================

enum class DynamicEqFilterType {
    Peak = 0,
    LowShelf = 1,
    HighShelf = 2
};

enum class DynamicEqMode {
    Static = 0,
    Compress = 1,
    Expand = 2
};

struct DynamicEqBandConfig {
    bool enabled = false;
    DynamicEqFilterType type = DynamicEqFilterType::Peak;
    DynamicEqMode mode = DynamicEqMode::Compress;
    float freq_hz = 1000.0f;
    float q = 1.0f;
    float base_gain_db = 0.0f;
    float threshold_db = -24.0f;
    float range_db = 6.0f;        // Max dynamic cut/boost magnitude in dB
    float ratio = 3.0f;
    float attack_ms = 2.0f;
    float release_ms = 60.0f;
};

class DynamicEqDSP {
public:
    static constexpr size_t kMaxBands = 6;
    static constexpr size_t kMaxChannels = CytomicSVF::kMaxChannels;
    static constexpr size_t kSubBlockSize = 16;
    static constexpr float kSoftKneeDb = 3.0f;

    DynamicEqDSP() {
        setSampleRate(48000.0f);
        bands_[0].config.type = DynamicEqFilterType::LowShelf;
        bands_[0].config.freq_hz = 60.0f;
        bands_[0].config.q = 0.707f;
        bands_[0].config.threshold_db = -20.0f;
        bands_[0].config.range_db = 6.0f;
        bands_[0].config.ratio = 3.0f;

        bands_[1].config.freq_hz = 180.0f;
        bands_[1].config.q = 1.2f;
        bands_[1].config.threshold_db = -20.0f;
        bands_[1].config.range_db = 5.0f;
        bands_[1].config.ratio = 2.5f;

        bands_[2].config.freq_hz = 600.0f;
        bands_[2].config.q = 1.4f;
        bands_[2].config.threshold_db = -22.0f;
        bands_[2].config.range_db = 5.0f;
        bands_[2].config.ratio = 2.5f;

        bands_[3].config.freq_hz = 2000.0f;
        bands_[3].config.q = 1.6f;
        bands_[3].config.threshold_db = -24.0f;
        bands_[3].config.range_db = 6.0f;
        bands_[3].config.ratio = 3.0f;

        bands_[4].config.freq_hz = 6000.0f;
        bands_[4].config.q = 2.0f;
        bands_[4].config.threshold_db = -24.0f;
        bands_[4].config.range_db = 6.0f;
        bands_[4].config.ratio = 3.5f;

        bands_[5].config.type = DynamicEqFilterType::HighShelf;
        bands_[5].config.freq_hz = 12000.0f;
        bands_[5].config.q = 0.707f;
        bands_[5].config.threshold_db = -22.0f;
        bands_[5].config.range_db = 4.0f;
        bands_[5].config.ratio = 2.0f;

        reset();
    }

    DynamicEqDSP(const DynamicEqDSP& other)
        : enabled_(other.enabled_.load(std::memory_order_relaxed)),
          sample_rate_(other.sample_rate_),
          bands_(other.bands_) {}

    DynamicEqDSP& operator=(const DynamicEqDSP& other) {
        if (this != &other) {
            enabled_.store(other.enabled_.load(std::memory_order_relaxed), std::memory_order_relaxed);
            sample_rate_ = other.sample_rate_;
            bands_ = other.bands_;
        }
        return *this;
    }

    void setSampleRate(float sampleRate) {
        if (sampleRate <= 0.0f) sampleRate = 48000.0f;
        sample_rate_ = sampleRate;
        for (size_t b = 0; b < kMaxBands; ++b) {
            updateBandConstants(b);
            updateSidechainCoeffs(b);
            updateAudioFilterCoeffs(b, bands_[b].current_gain_db);
        }
    }

    float getSampleRate() const { return sample_rate_; }

    void setEnabled(bool enabled) {
        const bool prev = enabled_.exchange(enabled, std::memory_order_release);
        if (prev && !enabled) {
            reset();
        }
    }

    bool isEnabled() const { return enabled_.load(std::memory_order_relaxed); }

    void setBandConfig(size_t band_index, const DynamicEqBandConfig &config) {
        if (band_index >= kMaxBands) return;
        auto &b = bands_[band_index];
        const bool wasEnabled = b.config.enabled;
        b.config = config;
        b.config.freq_hz = std::clamp(b.config.freq_hz, 20.0f, sample_rate_ * 0.48f);
        b.config.q = std::clamp(b.config.q, 0.1f, 15.0f);
        b.config.base_gain_db = std::clamp(b.config.base_gain_db, -24.0f, 24.0f);
        b.config.threshold_db = std::clamp(b.config.threshold_db, -60.0f, 0.0f);
        b.config.range_db = std::clamp(b.config.range_db, 0.0f, 24.0f);
        b.config.ratio = std::clamp(b.config.ratio, 1.0f, 20.0f);
        b.config.attack_ms = std::clamp(b.config.attack_ms, 0.2f, 200.0f);
        b.config.release_ms = std::clamp(b.config.release_ms, 5.0f, 2000.0f);

        // Snap only on initial activation or while global/band DSP is inactive;
        // smooth live edits to base_gain_db to prevent knob-drag clicks.
        if (!wasEnabled || !enabled_.load(std::memory_order_relaxed)) {
            b.current_base_gain_db = b.config.base_gain_db;
            b.current_gain_db = b.config.base_gain_db;
            if (!wasEnabled && b.config.enabled) {
                b.sc_svf.reset();
                b.svf.reset();
                b.sc_envelope = 0.0f;
                b.current_dyn_offset_db.store(0.0f, std::memory_order_relaxed);
            }
        }

        updateBandConstants(band_index);
        updateSidechainCoeffs(band_index);
        updateAudioFilterCoeffs(band_index, b.current_gain_db);
    }

    DynamicEqBandConfig getBandConfig(size_t band_index) const {
        if (band_index >= kMaxBands) return {};
        return bands_[band_index].config;
    }

    void setBandEnabled(size_t band_index, bool enabled) {
        if (band_index >= kMaxBands) return;
        const bool prev = bands_[band_index].config.enabled;
        bands_[band_index].config.enabled = enabled;
        if (prev && !enabled) {
            bands_[band_index].resetStates();
        }
    }

    bool isBandEnabled(size_t band_index) const {
        if (band_index >= kMaxBands) return false;
        return bands_[band_index].config.enabled;
    }

    // Lock-free telemetry read: returns current dynamic gain offset in dB
    float getBandGainOffsetDb(size_t band_index) const {
        if (band_index >= kMaxBands || !enabled_.load(std::memory_order_relaxed) || !bands_[band_index].config.enabled) {
            return 0.0f;
        }
        return bands_[band_index].current_dyn_offset_db.load(std::memory_order_relaxed);
    }

    void reset() {
        for (auto &b : bands_) {
            b.resetStates();
            updateAudioFilterCoeffs(static_cast<size_t>(&b - bands_.data()), b.current_gain_db);
        }
    }

    // Process 32-bit float interleaved samples in-place
    void process(float *buffer, size_t frame_count, int channels) {
        processImpl(buffer, frame_count, channels);
    }

    // Process 64-bit double interleaved samples in-place
    void process(double *buffer, size_t frame_count, int channels) {
        processImpl(buffer, frame_count, channels);
    }

private:
    struct BandState {
        DynamicEqBandConfig config;

        // Detector ballistics
        float attack_coeff = 0.1f;
        float release_coeff = 0.001f;
        float base_smooth_coeff = 0.02f;
        float sc_envelope = 0.0f;
        float current_base_gain_db = 0.0f;
        float current_gain_db = 0.0f;
        float last_computed_gain_db = -999.0f;
        std::atomic<float> current_dyn_offset_db{0.0f};

        // Sidechain filter stage (64-bit Cytomic TPT SVF + 0 dB BP peak normalization)
        double sc_norm_scale = 1.0;
        CytomicSVF sc_svf;

        // Audio filter stage (64-bit Cytomic TPT SVF with Nyquist de-cramping)
        CytomicSVF svf;

        BandState() = default;

        BandState(const BandState& other)
            : config(other.config),
              attack_coeff(other.attack_coeff),
              release_coeff(other.release_coeff),
              base_smooth_coeff(other.base_smooth_coeff),
              sc_envelope(other.sc_envelope),
              current_base_gain_db(other.current_base_gain_db),
              current_gain_db(other.current_gain_db),
              last_computed_gain_db(other.last_computed_gain_db),
              current_dyn_offset_db(other.current_dyn_offset_db.load(std::memory_order_relaxed)),
              sc_norm_scale(other.sc_norm_scale),
              sc_svf(other.sc_svf),
              svf(other.svf) {}

        BandState& operator=(const BandState& other) {
            if (this != &other) {
                config = other.config;
                attack_coeff = other.attack_coeff;
                release_coeff = other.release_coeff;
                base_smooth_coeff = other.base_smooth_coeff;
                sc_envelope = other.sc_envelope;
                current_base_gain_db = other.current_base_gain_db;
                current_gain_db = other.current_gain_db;
                last_computed_gain_db = other.last_computed_gain_db;
                current_dyn_offset_db.store(
                    other.current_dyn_offset_db.load(std::memory_order_relaxed),
                    std::memory_order_relaxed);
                sc_norm_scale = other.sc_norm_scale;
                sc_svf = other.sc_svf;
                svf = other.svf;
            }
            return *this;
        }

        void resetStates() {
            sc_envelope = 0.0f;
            current_base_gain_db = config.base_gain_db;
            current_gain_db = config.base_gain_db;
            last_computed_gain_db = -999.0f;
            current_dyn_offset_db.store(0.0f, std::memory_order_relaxed);
            sc_svf.reset();
            svf.reset();
        }
    };

    template <typename SampleT>
    void processImpl(SampleT *buffer, size_t frame_count, int channels) {
        if (!enabled_.load(std::memory_order_relaxed) || buffer == nullptr || frame_count == 0 || channels <= 0) {
            return;
        }

        const size_t ch = std::min(static_cast<size_t>(channels), kMaxChannels);
        ScopedDenormalsDisable denormalGuard;

        size_t frames_remaining = frame_count;
        SampleT *ptr = buffer;

        while (frames_remaining > 0) {
            const size_t sub_frames = std::min(frames_remaining, kSubBlockSize);

            // 1. Process per-channel sidechains & linked-peak detector envelopes over sub-block
            for (size_t b = 0; b < kMaxBands; ++b) {
                auto &band = bands_[b];
                if (!band.config.enabled) continue;

                float dyn_gain_db = 0.0f;
                if (band.config.mode != DynamicEqMode::Static) {
                    for (size_t f = 0; f < sub_frames; ++f) {
                        const SampleT *frame = ptr + f * static_cast<size_t>(channels);
                        float sc_peak = 0.0f;
                        for (size_t c = 0; c < ch; ++c) {
                            const double sc_val = band.sc_svf.processSample(static_cast<double>(frame[c]), static_cast<int>(c)) * band.sc_norm_scale;
                            const float sc_abs = static_cast<float>(std::abs(sc_val));
                            if (sc_abs > sc_peak) sc_peak = sc_abs;
                        }

                        if (sc_peak > band.sc_envelope) {
                            band.sc_envelope += band.attack_coeff * (sc_peak - band.sc_envelope);
                        } else {
                            band.sc_envelope += band.release_coeff * (sc_peak - band.sc_envelope);
                        }
                    }

                    // Soft-knee transfer curve (chatter-free near threshold)
                    const float sc_db = (band.sc_envelope > 1.0e-6f) ? (20.0f * std::log10(band.sc_envelope)) : -120.0f;
                    const float delta = sc_db - band.config.threshold_db;
                    constexpr float kHalfKnee = kSoftKneeDb * 0.5f;
                    float excess = 0.0f;
                    if (delta >= kHalfKnee) {
                        excess = delta;
                    } else if (delta > -kHalfKnee) {
                        const float x = delta + kHalfKnee;
                        excess = (x * x) / (2.0f * kSoftKneeDb);
                    }

                    if (band.config.mode == DynamicEqMode::Compress && excess > 0.0f) {
                        const float gr = -excess * (1.0f - 1.0f / band.config.ratio);
                        dyn_gain_db = std::max(gr, -band.config.range_db);
                    } else if (band.config.mode == DynamicEqMode::Expand && excess > 0.0f) {
                        const float boost = excess * (1.0f - 1.0f / band.config.ratio);
                        dyn_gain_db = std::min(boost, band.config.range_db);
                    }
                } else {
                    band.sc_envelope = 0.0f;
                }

                band.current_dyn_offset_db.store(dyn_gain_db, std::memory_order_relaxed);

                // Smooth manual base_gain_db edits (exact exponential over sub_frames),
                // without choking the attack/release envelope dynamics.
                const float base_diff = band.config.base_gain_db - band.current_base_gain_db;
                if (std::abs(base_diff) > 1.0e-4f) {
                    const float alpha_base = 1.0f - std::pow(1.0f - band.base_smooth_coeff, static_cast<float>(sub_frames));
                    band.current_base_gain_db += alpha_base * base_diff;
                } else {
                    band.current_base_gain_db = band.config.base_gain_db;
                }

                band.current_gain_db = std::clamp(band.current_base_gain_db + dyn_gain_db, -36.0f, 36.0f);

                // Update SVF coefficients only when gain moved meaningfully; never reset integrator states!
                if (std::abs(band.current_gain_db - band.last_computed_gain_db) > 0.015f) {
                    updateAudioFilterCoeffs(b, band.current_gain_db);
                    band.last_computed_gain_db = band.current_gain_db;
                }
            }

            // 2. Apply 64-bit Cytomic TPT SVF audio filters for all active bands
            for (size_t b = 0; b < kMaxBands; ++b) {
                auto &band = bands_[b];
                if (!band.config.enabled || band.svf.isFlat()) continue;
                band.svf.process(ptr, static_cast<uint32_t>(sub_frames), channels);
            }

            ptr += sub_frames * static_cast<size_t>(channels);
            frames_remaining -= sub_frames;
        }
    }

    void updateBandConstants(size_t b) {
        auto &band = bands_[b];
        const float atk = std::max(band.config.attack_ms, 0.2f);
        const float rel = std::max(band.config.release_ms, 2.0f);
        band.attack_coeff = 1.0f - std::exp(-1.0f / (atk * 0.001f * sample_rate_));
        band.release_coeff = 1.0f - std::exp(-1.0f / (rel * 0.001f * sample_rate_));
        band.base_smooth_coeff = 1.0f - std::exp(-1.0f / (0.003f * sample_rate_)); // 3 ms click-free base-gain trim smoother
    }

    void updateSidechainCoeffs(size_t b) {
        auto &band = bands_[b];
        const double fc = std::clamp(static_cast<double>(band.config.freq_hz), 20.0, static_cast<double>(sample_rate_) * 0.48);
        const double q = static_cast<double>(std::max(band.config.q, 0.1f));
        constexpr double kButterworthQ = 0.7071067811865475;

        if (band.config.type == DynamicEqFilterType::LowShelf) {
            band.sc_norm_scale = 1.0;
            band.sc_svf.setParameters(CytomicSVF::FilterType::LowPass, static_cast<double>(sample_rate_), fc, 0.0, kButterworthQ);
        } else if (band.config.type == DynamicEqFilterType::HighShelf) {
            band.sc_norm_scale = 1.0;
            band.sc_svf.setParameters(CytomicSVF::FilterType::HighPass, static_cast<double>(sample_rate_), fc, 0.0, kButterworthQ);
        } else {
            // Normalize Cytomic BandPass (peak = Q) by k = 1/Q for exact 0 dB center gain
            band.sc_norm_scale = 1.0 / q;
            band.sc_svf.setParameters(CytomicSVF::FilterType::BandPass, static_cast<double>(sample_rate_), fc, 0.0, q);
        }
    }

    void updateAudioFilterCoeffs(size_t b, float gain_db) {
        auto &band = bands_[b];
        const double fc = std::clamp(static_cast<double>(band.config.freq_hz), 20.0, static_cast<double>(sample_rate_) * 0.48);
        const double q = static_cast<double>(std::max(band.config.q, 0.1f));

        CytomicSVF::FilterType svfType = CytomicSVF::FilterType::Bell;
        if (band.config.type == DynamicEqFilterType::LowShelf) {
            svfType = CytomicSVF::FilterType::LowShelf;
        } else if (band.config.type == DynamicEqFilterType::HighShelf) {
            svfType = CytomicSVF::FilterType::HighShelf;
        }

        band.svf.setParameters(svfType, static_cast<double>(sample_rate_), fc, static_cast<double>(gain_db), q);
        // Never reset integrator states on isFlat() transition while modulating dynamically.
    }

    std::atomic<bool> enabled_{false};
    float sample_rate_ = 48000.0f;
    std::array<BandState, kMaxBands> bands_;
};

} // namespace sauti::dsp
