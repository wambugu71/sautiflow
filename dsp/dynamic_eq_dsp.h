#pragma once

#include <cmath>
#include <cstdint>
#include <algorithm>
#include <array>
#include <vector>
#include "denormals.h"
#include "simd_math.h"

namespace sauti::dsp {

// =============================================================================
// DynamicEqDSP: 4-Band Studio-Grade Dynamic Parametric Equalizer
//
// Features:
// - 4 independent, fully parametric dynamic bands across 20 Hz – 20 kHz.
// - Filter Types: Peak / Bell, Low-Shelf, High-Shelf.
// - Dynamic Modes:
//     - Static (traditional clean parametric EQ)
//     - Compress (dynamically cuts when band energy exceeds threshold)
//     - Expand (dynamically boosts when band energy exceeds threshold)
// - Dedicated per-band sidechain filters (Bandpass, Low-pass, or High-pass)
//   isolating detection energy to the target frequency.
// - Envelope follower with configurable attack (0.5–100 ms) and release (5–1000 ms).
// - Sub-block processing (32 samples) with smooth parameter interpolation
//   guaranteeing click-free, zipper-free modulation.
// - Zero phase distortion / zero computation overhead when bands are 0 dB / inactive.
// - Real-time gain offset telemetry per band.
// - In-place 32-bit float and 64-bit double processing paths.
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
    static constexpr size_t kMaxChannels = 2;
    static constexpr size_t kSubBlockSize = 32;

    DynamicEqDSP() {
        setSampleRate(48000.0f);
        // Default 6-band configuration spanning full audible spectrum
        // Band 0: Sub / Low-end rumble & boom control (60 Hz, Low-Shelf)
        bands_[0].config.type = DynamicEqFilterType::LowShelf;
        bands_[0].config.freq_hz = 60.0f;
        bands_[0].config.q = 0.707f;
        bands_[0].config.threshold_db = -20.0f;
        bands_[0].config.range_db = 6.0f;
        bands_[0].config.ratio = 3.0f;

        // Band 1: Bass / warmth & punch tamer (180 Hz)
        bands_[1].config.freq_hz = 180.0f;
        bands_[1].config.q = 1.2f;
        bands_[1].config.threshold_db = -20.0f;
        bands_[1].config.range_db = 5.0f;
        bands_[1].config.ratio = 2.5f;

        // Band 2: Low-Mid boxiness & mud tamer (600 Hz)
        bands_[2].config.freq_hz = 600.0f;
        bands_[2].config.q = 1.4f;
        bands_[2].config.threshold_db = -22.0f;
        bands_[2].config.range_db = 5.0f;
        bands_[2].config.ratio = 2.5f;

        // Band 3: Core Mid clarity / bite controller (2000 Hz)
        bands_[3].config.freq_hz = 2000.0f;
        bands_[3].config.q = 1.6f;
        bands_[3].config.threshold_db = -24.0f;
        bands_[3].config.range_db = 6.0f;
        bands_[3].config.ratio = 3.0f;

        // Band 4: Presence / sibilance tamer (6000 Hz)
        bands_[4].config.freq_hz = 6000.0f;
        bands_[4].config.q = 2.0f;
        bands_[4].config.threshold_db = -24.0f;
        bands_[4].config.range_db = 6.0f;
        bands_[4].config.ratio = 3.5f;

        // Band 5: High-end air & brilliance (12000 Hz, High-Shelf)
        bands_[5].config.type = DynamicEqFilterType::HighShelf;
        bands_[5].config.freq_hz = 12000.0f;
        bands_[5].config.q = 0.707f;
        bands_[5].config.threshold_db = -22.0f;
        bands_[5].config.range_db = 4.0f;
        bands_[5].config.ratio = 2.0f;

        reset();
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
        if (enabled_ != enabled) {
            enabled_ = enabled;
            if (!enabled) {
                reset();
            }
        }
    }

    bool isEnabled() const { return enabled_; }

    void setBandConfig(size_t band_index, const DynamicEqBandConfig &config) {
        if (band_index >= kMaxBands) return;
        auto &b = bands_[band_index];
        b.config = config;
        b.config.freq_hz = std::clamp(b.config.freq_hz, 20.0f, sample_rate_ * 0.48f);
        b.config.q = std::clamp(b.config.q, 0.1f, 15.0f);
        b.config.base_gain_db = std::clamp(b.config.base_gain_db, -24.0f, 24.0f);
        b.config.threshold_db = std::clamp(b.config.threshold_db, -60.0f, 0.0f);
        b.config.range_db = std::clamp(b.config.range_db, 0.0f, 24.0f);
        b.config.ratio = std::clamp(b.config.ratio, 1.0f, 20.0f);
        b.config.attack_ms = std::clamp(b.config.attack_ms, 0.2f, 200.0f);
        b.config.release_ms = std::clamp(b.config.release_ms, 5.0f, 2000.0f);
        b.current_gain_db = b.config.base_gain_db;

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
        bands_[band_index].config.enabled = enabled;
        if (!enabled) {
            bands_[band_index].resetStates();
        }
    }

    bool isBandEnabled(size_t band_index) const {
        if (band_index >= kMaxBands) return false;
        return bands_[band_index].config.enabled;
    }

    // Returns current dynamic gain offset in dB for telemetry meters
    float getBandGainOffsetDb(size_t band_index) const {
        if (band_index >= kMaxBands || !enabled_ || !bands_[band_index].config.enabled) {
            return 0.0f;
        }
        return bands_[band_index].current_dyn_offset_db;
    }

    void reset() {
        for (auto &b : bands_) {
            b.resetStates();
        }
    }

    // Process 32-bit float interleaved samples in-place
    void process(float *buffer, size_t frame_count, int channels) {
        if (!enabled_ || buffer == nullptr || frame_count == 0 || channels <= 0) {
            return;
        }

        const size_t ch = std::min(static_cast<size_t>(channels), kMaxChannels);
        ScopedDenormalsDisable denormalGuard;

        size_t frames_remaining = frame_count;
        float *ptr = buffer;

        while (frames_remaining > 0) {
            const size_t sub_frames = std::min(frames_remaining, kSubBlockSize);

            // 1. Process sidechains & detector envelopes over sub-block
            for (size_t b = 0; b < kMaxBands; ++b) {
                auto &band = bands_[b];
                if (!band.config.enabled) continue;

                // Process sidechain over the sub-block to track peak envelope
                for (size_t f = 0; f < sub_frames; ++f) {
                    float mono_in = 0.0f;
                    for (size_t c = 0; c < ch; ++c) {
                        mono_in += ptr[f * (size_t)channels + c];
                    }
                    mono_in /= static_cast<float>(ch);

                    // Sidechain biquad (TDF2)
                    double sc_sample = static_cast<double>(mono_in);
                    double sc_filtered = band.sc_b0 * sc_sample + band.sc_s1;
                    band.sc_s1 = band.sc_b1 * sc_sample - band.sc_a1 * sc_filtered + band.sc_s2;
                    band.sc_s2 = band.sc_b2 * sc_sample - band.sc_a2 * sc_filtered;

                    // Peak envelope ballistics
                    float sc_abs = static_cast<float>(std::abs(sc_filtered));
                    if (sc_abs > band.sc_envelope) {
                        band.sc_envelope += band.attack_coeff * (sc_abs - band.sc_envelope);
                    } else {
                        band.sc_envelope += band.release_coeff * (sc_abs - band.sc_envelope);
                    }
                }

                // 2. Compute dynamic gain for the band
                float sc_db = (band.sc_envelope > 1.0e-6f) ? (20.0f * std::log10(band.sc_envelope)) : -120.0f;
                float delta = sc_db - band.config.threshold_db;
                float dyn_gain_db = 0.0f;

                if (band.config.mode == DynamicEqMode::Compress && delta > 0.0f) {
                    float gr = -delta * (1.0f - 1.0f / band.config.ratio);
                    dyn_gain_db = std::max(gr, -band.config.range_db);
                } else if (band.config.mode == DynamicEqMode::Expand && delta > 0.0f) {
                    float boost = delta * (1.0f - 1.0f / band.config.ratio);
                    dyn_gain_db = std::min(boost, band.config.range_db);
                }

                band.current_dyn_offset_db = dyn_gain_db;
                float target_total_db = band.config.base_gain_db + dyn_gain_db;

                // Smooth gain change
                float gain_diff = target_total_db - band.current_gain_db;
                band.current_gain_db += band.smoothing_coeff * static_cast<float>(sub_frames) * gain_diff;

                // Update filter coefficients if gain moved significantly
                if (std::abs(band.current_gain_db - band.last_computed_gain_db) > 0.02f) {
                    updateAudioFilterCoeffs(b, band.current_gain_db);
                    band.last_computed_gain_db = band.current_gain_db;
                }
            }

            // 3. Apply audio biquads for all active bands
            for (size_t b = 0; b < kMaxBands; ++b) {
                auto &band = bands_[b];
                if (!band.config.enabled) continue;

                // If gain is virtually 0 dB and states are zero, identity bypass this band
                if (std::abs(band.current_gain_db) < 0.01f && band.statesAreZero(ch)) {
                    continue;
                }

                for (size_t f = 0; f < sub_frames; ++f) {
                    for (size_t c = 0; c < ch; ++c) {
                        double in_s = static_cast<double>(ptr[f * (size_t)channels + c]);
                        double out_s = band.b0 * in_s + band.s1[c];
                        band.s1[c] = band.b1 * in_s - band.a1 * out_s + band.s2[c];
                        band.s2[c] = band.b2 * in_s - band.a2 * out_s;
                        ptr[f * (size_t)channels + c] = static_cast<float>(out_s);
                    }
                }
            }

            ptr += sub_frames * (size_t)channels;
            frames_remaining -= sub_frames;
        }
    }

    // Process 64-bit double interleaved samples in-place
    void process(double *buffer, size_t frame_count, int channels) {
        if (!enabled_ || buffer == nullptr || frame_count == 0 || channels <= 0) {
            return;
        }

        const size_t ch = std::min(static_cast<size_t>(channels), kMaxChannels);
        ScopedDenormalsDisable denormalGuard;

        size_t frames_remaining = frame_count;
        double *ptr = buffer;

        while (frames_remaining > 0) {
            const size_t sub_frames = std::min(frames_remaining, kSubBlockSize);

            for (size_t b = 0; b < kMaxBands; ++b) {
                auto &band = bands_[b];
                if (!band.config.enabled) continue;

                for (size_t f = 0; f < sub_frames; ++f) {
                    double mono_in = 0.0;
                    for (size_t c = 0; c < ch; ++c) {
                        mono_in += ptr[f * (size_t)channels + c];
                    }
                    mono_in /= static_cast<double>(ch);

                    double sc_filtered = band.sc_b0 * mono_in + band.sc_s1;
                    band.sc_s1 = band.sc_b1 * mono_in - band.sc_a1 * sc_filtered + band.sc_s2;
                    band.sc_s2 = band.sc_b2 * mono_in - band.sc_a2 * sc_filtered;

                    float sc_abs = static_cast<float>(std::abs(sc_filtered));
                    if (sc_abs > band.sc_envelope) {
                        band.sc_envelope += band.attack_coeff * (sc_abs - band.sc_envelope);
                    } else {
                        band.sc_envelope += band.release_coeff * (sc_abs - band.sc_envelope);
                    }
                }

                float sc_db = (band.sc_envelope > 1.0e-6f) ? (20.0f * std::log10(band.sc_envelope)) : -120.0f;
                float delta = sc_db - band.config.threshold_db;
                float dyn_gain_db = 0.0f;

                if (band.config.mode == DynamicEqMode::Compress && delta > 0.0f) {
                    float gr = -delta * (1.0f - 1.0f / band.config.ratio);
                    dyn_gain_db = std::max(gr, -band.config.range_db);
                } else if (band.config.mode == DynamicEqMode::Expand && delta > 0.0f) {
                    float boost = delta * (1.0f - 1.0f / band.config.ratio);
                    dyn_gain_db = std::min(boost, band.config.range_db);
                }

                band.current_dyn_offset_db = dyn_gain_db;
                float target_total_db = band.config.base_gain_db + dyn_gain_db;

                float gain_diff = target_total_db - band.current_gain_db;
                band.current_gain_db += band.smoothing_coeff * static_cast<float>(sub_frames) * gain_diff;

                if (std::abs(band.current_gain_db - band.last_computed_gain_db) > 0.02f) {
                    updateAudioFilterCoeffs(b, band.current_gain_db);
                    band.last_computed_gain_db = band.current_gain_db;
                }
            }

            for (size_t b = 0; b < kMaxBands; ++b) {
                auto &band = bands_[b];
                if (!band.config.enabled) continue;

                if (std::abs(band.current_gain_db) < 0.01f && band.statesAreZero(ch)) {
                    continue;
                }

                for (size_t f = 0; f < sub_frames; ++f) {
                    for (size_t c = 0; c < ch; ++c) {
                        double in_s = ptr[f * (size_t)channels + c];
                        double out_s = band.b0 * in_s + band.s1[c];
                        band.s1[c] = band.b1 * in_s - band.a1 * out_s + band.s2[c];
                        band.s2[c] = band.b2 * in_s - band.a2 * out_s;
                        ptr[f * (size_t)channels + c] = out_s;
                    }
                }
            }

            ptr += sub_frames * (size_t)channels;
            frames_remaining -= sub_frames;
        }
    }

private:
    struct BandState {
        DynamicEqBandConfig config;

        // Detector ballistics
        float attack_coeff = 0.1f;
        float release_coeff = 0.001f;
        float smoothing_coeff = 0.005f;
        float sc_envelope = 0.0f;
        float current_gain_db = 0.0f;
        float last_computed_gain_db = -999.0f;
        float current_dyn_offset_db = 0.0f;

        // Sidechain filter coefficients (TDF2)
        double sc_b0 = 1.0, sc_b1 = 0.0, sc_b2 = 0.0;
        double sc_a1 = 0.0, sc_a2 = 0.0;
        double sc_s1 = 0.0, sc_s2 = 0.0;

        // Audio filter coefficients (TDF2 normalized)
        double b0 = 1.0, b1 = 0.0, b2 = 0.0;
        double a1 = 0.0, a2 = 0.0;
        std::array<double, kMaxChannels> s1{0.0, 0.0};
        std::array<double, kMaxChannels> s2{0.0, 0.0};

        void resetStates() {
            sc_envelope = 0.0f;
            current_gain_db = config.base_gain_db;
            last_computed_gain_db = -999.0f;
            current_dyn_offset_db = 0.0f;
            sc_s1 = 0.0;
            sc_s2 = 0.0;
            s1.fill(0.0);
            s2.fill(0.0);
        }

        bool statesAreZero(size_t channels) const {
            for (size_t c = 0; c < channels; ++c) {
                if (std::abs(s1[c]) > 1.0e-9 || std::abs(s2[c]) > 1.0e-9) {
                    return false;
                }
            }
            return true;
        }
    };

    void updateBandConstants(size_t b) {
        auto &band = bands_[b];
        const float atk = std::max(band.config.attack_ms, 0.2f);
        const float rel = std::max(band.config.release_ms, 2.0f);
        band.attack_coeff = 1.0f - std::exp(-1.0f / (atk * 0.001f * sample_rate_));
        band.release_coeff = 1.0f - std::exp(-1.0f / (rel * 0.001f * sample_rate_));
        band.smoothing_coeff = 1.0f - std::exp(-1.0f / (0.015f * sample_rate_)); // 15 ms gain smoothing
    }

    void updateSidechainCoeffs(size_t b) {
        auto &band = bands_[b];
        constexpr double PI = 3.14159265358979323846;
        const double w0 = 2.0 * PI * static_cast<double>(band.config.freq_hz) / static_cast<double>(sample_rate_);
        const double cosw0 = std::cos(w0);
        const double sinw0 = std::sin(w0);
        const double q = static_cast<double>(std::max(band.config.q, 0.1f));

        if (band.config.type == DynamicEqFilterType::LowShelf) {
            // 2nd-order Butterworth Low-Pass Sidechain
            const double alpha = sinw0 * 0.7071067811865475;
            const double a0 = 1.0 + alpha;
            const double inv_a0 = 1.0 / a0;
            band.sc_b0 = ((1.0 - cosw0) * 0.5) * inv_a0;
            band.sc_b1 = (1.0 - cosw0) * inv_a0;
            band.sc_b2 = ((1.0 - cosw0) * 0.5) * inv_a0;
            band.sc_a1 = (-2.0 * cosw0) * inv_a0;
            band.sc_a2 = (1.0 - alpha) * inv_a0;
        } else if (band.config.type == DynamicEqFilterType::HighShelf) {
            // 2nd-order Butterworth High-Pass Sidechain
            const double alpha = sinw0 * 0.7071067811865475;
            const double a0 = 1.0 + alpha;
            const double inv_a0 = 1.0 / a0;
            band.sc_b0 = ((1.0 + cosw0) * 0.5) * inv_a0;
            band.sc_b1 = (-(1.0 + cosw0)) * inv_a0;
            band.sc_b2 = ((1.0 + cosw0) * 0.5) * inv_a0;
            band.sc_a1 = (-2.0 * cosw0) * inv_a0;
            band.sc_a2 = (1.0 - alpha) * inv_a0;
        } else {
            // 2nd-order Bandpass Sidechain (0 dB peak gain)
            const double alpha = sinw0 / (2.0 * q);
            const double a0 = 1.0 + alpha;
            const double inv_a0 = 1.0 / a0;
            band.sc_b0 = alpha * inv_a0;
            band.sc_b1 = 0.0;
            band.sc_b2 = -alpha * inv_a0;
            band.sc_a1 = (-2.0 * cosw0) * inv_a0;
            band.sc_a2 = (1.0 - alpha) * inv_a0;
        }
    }

    void updateAudioFilterCoeffs(size_t b, float gain_db) {
        auto &band = bands_[b];
        constexpr double PI = 3.14159265358979323846;

        if (std::abs(gain_db) < 0.005f) {
            band.b0 = 1.0; band.b1 = 0.0; band.b2 = 0.0;
            band.a1 = 0.0; band.a2 = 0.0;
            return;
        }

        const double w0 = 2.0 * PI * static_cast<double>(band.config.freq_hz) / static_cast<double>(sample_rate_);
        const double cosw0 = std::cos(w0);
        const double sinw0 = std::sin(w0);
        const double q = static_cast<double>(std::max(band.config.q, 0.1f));
        const double A = std::pow(10.0, static_cast<double>(gain_db) / 40.0);
        const double alpha = sinw0 / (2.0 * q);

        if (band.config.type == DynamicEqFilterType::Peak) {
            // RBJ Peaking EQ
            const double b0_un = 1.0 + alpha * A;
            const double b1_un = -2.0 * cosw0;
            const double b2_un = 1.0 - alpha * A;
            const double a0_un = 1.0 + alpha / A;
            const double a1_un = -2.0 * cosw0;
            const double a2_un = 1.0 - alpha / A;
            const double inv_a0 = 1.0 / a0_un;

            band.b0 = b0_un * inv_a0;
            band.b1 = b1_un * inv_a0;
            band.b2 = b2_un * inv_a0;
            band.a1 = a1_un * inv_a0;
            band.a2 = a2_un * inv_a0;
        } else if (band.config.type == DynamicEqFilterType::LowShelf) {
            // RBJ Low-Shelf
            const double two_sqrt_A_alpha = 2.0 * std::sqrt(A) * alpha;
            const double Ap1 = A + 1.0;
            const double Am1 = A - 1.0;

            const double b0_un = A * (Ap1 - Am1 * cosw0 + two_sqrt_A_alpha);
            const double b1_un = 2.0 * A * (Am1 - Ap1 * cosw0);
            const double b2_un = A * (Ap1 - Am1 * cosw0 - two_sqrt_A_alpha);
            const double a0_un = Ap1 + Am1 * cosw0 + two_sqrt_A_alpha;
            const double a1_un = -2.0 * (Am1 + Ap1 * cosw0);
            const double a2_un = Ap1 + Am1 * cosw0 - two_sqrt_A_alpha;
            const double inv_a0 = 1.0 / a0_un;

            band.b0 = b0_un * inv_a0;
            band.b1 = b1_un * inv_a0;
            band.b2 = b2_un * inv_a0;
            band.a1 = a1_un * inv_a0;
            band.a2 = a2_un * inv_a0;
        } else {
            // RBJ High-Shelf
            const double two_sqrt_A_alpha = 2.0 * std::sqrt(A) * alpha;
            const double Ap1 = A + 1.0;
            const double Am1 = A - 1.0;

            const double b0_un = A * (Ap1 + Am1 * cosw0 + two_sqrt_A_alpha);
            const double b1_un = -2.0 * A * (Am1 + Ap1 * cosw0);
            const double b2_un = A * (Ap1 + Am1 * cosw0 - two_sqrt_A_alpha);
            const double a0_un = Ap1 - Am1 * cosw0 + two_sqrt_A_alpha;
            const double a1_un = 2.0 * (Am1 - Ap1 * cosw0);
            const double a2_un = Ap1 - Am1 * cosw0 - two_sqrt_A_alpha;
            const double inv_a0 = 1.0 / a0_un;

            band.b0 = b0_un * inv_a0;
            band.b1 = b1_un * inv_a0;
            band.b2 = b2_un * inv_a0;
            band.a1 = a1_un * inv_a0;
            band.a2 = a2_un * inv_a0;
        }
    }

    bool enabled_ = false;
    float sample_rate_ = 48000.0f;
    std::array<BandState, kMaxBands> bands_;
};

} // namespace sauti::dsp
