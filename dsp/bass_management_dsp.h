#pragma once

#include <algorithm>
#include <array>
#include <cmath>
#include <cstdint>
#include <vector>
#include "cytomic_svf_dsp.h"

namespace sauti::dsp {

// =============================================================================
// Canonical SMPTE / WAVEFORMATEXTENSIBLE Multichannel Indexing (1..8 ch)
//   Mono   (1ch): [M]
//   Stereo (2ch): [FL, FR]
//   5.1    (6ch): [FL, FR, FC, LFE, SL, SR]
//   7.1    (8ch): [FL, FR, FC, LFE, BL, BR, SL, SR]
// =============================================================================
struct SmpteChannel {
    static constexpr int FL = 0;
    static constexpr int FR = 1;
    static constexpr int FC = 2;
    static constexpr int LFE = 3;
    static constexpr int BL_OR_SL5 = 4; // SL in 5.1, BL in 7.1
    static constexpr int BR_OR_SR5 = 5; // SR in 5.1, BR in 7.1
    static constexpr int SL7 = 6;       // SL in 7.1
    static constexpr int SR7 = 7;       // SR in 7.1
};

enum class BassLfeMode {
    LfeOnly = 0,     // Small speaker bass + LFE -> Subwoofer (ch 3)
    LfePlusMain = 1, // Small speaker bass + Large FL/FR bass + LFE -> Subwoofer (Double Bass)
    PhantomSub = 2   // No subwoofer: redirect LFE + Small bass into Front L/R
};

// =============================================================================
// BassManagementDSP:
//   - Phase-matched 64-bit Cytomic LR4 (24 dB/oct) crossover (40..200 Hz)
//   - Independent Small / Large speaker size per group (Front, Center, Surround, Rear)
//   - Dedicated LFE LR4 low-pass (60..200 Hz) + LFE trim (-12..+12 dB)
//   - LfeOnly, LfePlusMain (Double Bass), and PhantomSub modes
//   - Per-channel speaker calibration: gain trim (-12..+12 dB) + fractional delay (0..30 ms)
// =============================================================================
class BassManagementDSP {
public:
    static constexpr int kMaxChannels = 8;
    static constexpr double kButterworthQ = 0.7071067811865475;

    BassManagementDSP() {
        setSampleRate(48000.0f);
        reset();
    }

    void setSampleRate(float sampleRate) {
        if (sampleRate <= 0.0f || !std::isfinite(sampleRate)) sampleRate = 48000.0f;
        if (std::fabs(sample_rate_ - sampleRate) < 1.0f && delay_allocated_sr_ > 0.0f) return;

        sample_rate_ = sampleRate;
        smoothing_coeff_ = 1.0 - std::exp(-1.0 / (0.025 * static_cast<double>(sample_rate_)));
        allocateDelayLines();
        updateFilters();
        reset();
    }

    void setEnabled(bool enabled) {
        if (enabled_ != enabled) {
            enabled_ = enabled;
            if (!enabled) reset();
        }
    }
    bool isEnabled() const { return enabled_; }

    void setCrossoverHz(float hz) {
        const float clamped = std::clamp(hz, 40.0f, 200.0f);
        if (std::fabs(crossover_hz_ - clamped) > 0.05f) {
            crossover_hz_ = clamped;
            need_filter_update_ = true;
        }
    }
    float getCrossoverHz() const { return crossover_hz_; }

    void setLfeLowpassHz(float hz) {
        const float clamped = std::clamp(hz, 60.0f, 200.0f);
        if (std::fabs(lfe_lpf_hz_ - clamped) > 0.05f) {
            lfe_lpf_hz_ = clamped;
            need_filter_update_ = true;
        }
    }
    float getLfeLowpassHz() const { return lfe_lpf_hz_; }

    void setLfeGainDb(float db) {
        lfe_gain_db_ = std::clamp(db, -12.0f, 12.0f);
        lfe_gain_lin_ = std::pow(10.0, static_cast<double>(lfe_gain_db_) / 20.0);
    }
    float getLfeGainDb() const { return lfe_gain_db_; }

    void setLfeMode(int mode) {
        lfe_mode_ = static_cast<BassLfeMode>(std::clamp(mode, 0, 2));
    }
    int getLfeMode() const { return static_cast<int>(lfe_mode_); }

    void setSpeakerSizes(bool frontSmall, bool centerSmall, bool surroundSmall, bool rearSmall) {
        front_small_ = frontSmall;
        center_small_ = centerSmall;
        surround_small_ = surroundSmall;
        rear_small_ = rearSmall;
    }

    bool isFrontSmall() const { return front_small_; }
    bool isCenterSmall() const { return center_small_; }
    bool isSurroundSmall() const { return surround_small_; }
    bool isRearSmall() const { return rear_small_; }

    void setChannelTrimDb(int ch, float db) {
        if (ch < 0 || ch >= kMaxChannels) return;
        trim_db_[ch] = std::clamp(db, -12.0f, 12.0f);
        target_trim_lin_[ch] = std::pow(10.0, static_cast<double>(trim_db_[ch]) / 20.0);
    }
    float getChannelTrimDb(int ch) const {
        if (ch < 0 || ch >= kMaxChannels) return 0.0f;
        return trim_db_[ch];
    }

    void setChannelDelayMs(int ch, float ms) {
        if (ch < 0 || ch >= kMaxChannels) return;
        delay_ms_[ch] = std::clamp(ms, 0.0f, 30.0f);
    }
    float getChannelDelayMs(int ch) const {
        if (ch < 0 || ch >= kMaxChannels) return 0.0f;
        return delay_ms_[ch];
    }

    void reset() {
        hp1_.reset();
        hp2_.reset();
        lp1_.reset();
        lp2_.reset();
        lfe_lp1_.reset();
        lfe_lp2_.reset();
        for (int c = 0; c < kMaxChannels; ++c) {
            if (!delay_buf_[c].empty()) {
                std::fill(delay_buf_[c].begin(), delay_buf_[c].end(), 0.0);
            }
            delay_write_[c] = 0;
            smooth_trim_lin_[c] = target_trim_lin_[c];
            smooth_delay_samples_[c] = static_cast<double>(delay_ms_[chClamp(c)]) * 0.001 * static_cast<double>(sample_rate_);
        }
        smooth_lfe_gain_lin_ = lfe_gain_lin_;
    }

    void process(float* interleaved, uint32_t frame_count, int channels) {
        processImpl(interleaved, frame_count, channels);
    }

    void process(double* interleaved, uint32_t frame_count, int channels) {
        processImpl(interleaved, frame_count, channels);
    }

private:
    static inline int chClamp(int c) { return std::clamp(c, 0, kMaxChannels - 1); }

    static inline double sanitize(double v) {
        return (std::fabs(v) < 1.0e-25) ? 0.0 : v;
    }

    void allocateDelayLines() {
        const float allocSr = std::max(sample_rate_, 192000.0f);
        const size_t maxSamples = static_cast<size_t>(std::ceil(0.032 * static_cast<double>(allocSr))) + 16u;
        for (int c = 0; c < kMaxChannels; ++c) {
            if (delay_buf_[c].size() < maxSamples) {
                delay_buf_[c].assign(maxSamples, 0.0);
                delay_write_[c] = 0;
            }
        }
        delay_allocated_sr_ = allocSr;
    }

    void updateFilters() {
        const double fs = static_cast<double>(sample_rate_);
        const double xo = static_cast<double>(crossover_hz_);
        const double lfeFc = static_cast<double>(lfe_lpf_hz_);

        hp1_.setParameters(CytomicSVF::FilterType::HighPass, fs, xo, 0.0, kButterworthQ);
        hp2_.setParameters(CytomicSVF::FilterType::HighPass, fs, xo, 0.0, kButterworthQ);
        lp1_.setParameters(CytomicSVF::FilterType::LowPass,  fs, xo, 0.0, kButterworthQ);
        lp2_.setParameters(CytomicSVF::FilterType::LowPass,  fs, xo, 0.0, kButterworthQ);

        lfe_lp1_.setParameters(CytomicSVF::FilterType::LowPass, fs, lfeFc, 0.0, kButterworthQ);
        lfe_lp2_.setParameters(CytomicSVF::FilterType::LowPass, fs, lfeFc, 0.0, kButterworthQ);
    }

    inline bool isChannelSmall(int c, int totalCh) const {
        if (totalCh <= 2) return front_small_;
        switch (c) {
            case SmpteChannel::FL:
            case SmpteChannel::FR:
                return front_small_;
            case SmpteChannel::FC:
                return center_small_;
            case SmpteChannel::LFE:
                return false;
            case SmpteChannel::BL_OR_SL5:
            case SmpteChannel::BR_OR_SR5:
                return (totalCh <= 6) ? surround_small_ : rear_small_;
            case SmpteChannel::SL7:
            case SmpteChannel::SR7:
                return surround_small_;
            default:
                return false;
        }
    }

    inline double pushAndReadDelay(int c, double x, double dSamples) {
        auto& buf = delay_buf_[c];
        if (buf.empty()) return x;
        const size_t n = buf.size();
        size_t w = delay_write_[c];
        buf[w] = x;
        const double maxD = static_cast<double>(n - 3);
        const double d = std::clamp(dSamples, 0.0, maxD);
        const size_t i0 = static_cast<size_t>(d);
        const double frac = d - static_cast<double>(i0);
        const size_t r0 = (w + n - i0) % n;
        const size_t r1 = (r0 + n - 1) % n;
        delay_write_[c] = (w + 1) % n;
        if (d < 1.0e-6) return x;
        return buf[r0] + frac * (buf[r1] - buf[r0]);
    }

    template <typename T>
    void processImpl(T* interleaved, uint32_t frame_count, int channels) {
        if (!enabled_ || !interleaved || frame_count == 0 || channels < 1) return;
        if (need_filter_update_) {
            updateFilters();
            need_filter_update_ = false;
        }

        const int ch = std::min(channels, kMaxChannels);
        const double sr = static_cast<double>(sample_rate_);
        const bool hasLfeCh = (ch >= 4);
        const bool phantomSub = (!hasLfeCh) || (lfe_mode_ == BassLfeMode::PhantomSub);
        const bool doubleBass = (hasLfeCh && lfe_mode_ == BassLfeMode::LfePlusMain && !front_small_);

        for (uint32_t i = 0; i < frame_count; ++i) {
            smooth_lfe_gain_lin_ += smoothing_coeff_ * (lfe_gain_lin_ - smooth_lfe_gain_lin_);

            double s[kMaxChannels]{};
            const size_t base = static_cast<size_t>(i) * static_cast<size_t>(channels);
            for (int c = 0; c < ch; ++c) {
                s[c] = static_cast<double>(interleaved[base + static_cast<size_t>(c)]);
            }

            if (hasLfeCh) {
                // Multichannel 5.1 / 7.1 bass management
                double subSum = 0.0;

                for (int c = 0; c < ch; ++c) {
                    if (c == SmpteChannel::LFE) {
                        const double lfeFiltered = lfe_lp2_.processSample(lfe_lp1_.processSample(s[c], 0), 0);
                        subSum += lfeFiltered * smooth_lfe_gain_lin_;
                        s[c] = 0.0;
                    } else {
                        const bool isSmall = isChannelSmall(c, ch);
                        if (isSmall) {
                            const double hi = hp2_.processSample(hp1_.processSample(s[c], c), c);
                            const double lo = lp2_.processSample(lp1_.processSample(s[c], c), c);
                            s[c] = hi;
                            subSum += lo;
                        } else if (doubleBass && (c == SmpteChannel::FL || c == SmpteChannel::FR)) {
                            const double lo = lp2_.processSample(lp1_.processSample(s[c], c), c);
                            subSum += 0.7071067811865475 * lo;
                        }
                    }
                }

                if (phantomSub) {
                    // Fold redirected sub-bass + LFE equally into FL and FR (-3 dB each)
                    const double fold = 0.7071067811865475 * subSum;
                    s[SmpteChannel::FL] += fold;
                    s[SmpteChannel::FR] += fold;
                    s[SmpteChannel::LFE] = 0.0;
                } else {
                    s[SmpteChannel::LFE] = subSum;
                }
            } else if (ch == 2) {
                // On 2ch stereo, apply crossover only if DoubleBass/PhantomSub is explicitly desired?
                // Keep 2ch frequency response flat (HP4 + LP4 sums to 0 dB) and apply trim/delay calibration.
                // If user has Front=Small on stereo with no sub, HP4+LP4 would be redundant unless LFE gain differs,
                // so preserve 2ch tonal neutrality and run calibration trim & distance delay cleanly.
            }

            // Per-channel speaker calibration: gain trim & fractional delay
            for (int c = 0; c < ch; ++c) {
                smooth_trim_lin_[c] += smoothing_coeff_ * (target_trim_lin_[c] - smooth_trim_lin_[c]);
                const double targetDelaySamp = static_cast<double>(delay_ms_[c]) * 0.001 * sr;
                smooth_delay_samples_[c] += smoothing_coeff_ * (targetDelaySamp - smooth_delay_samples_[c]);

                double out = s[c] * smooth_trim_lin_[c];
                out = pushAndReadDelay(c, out, smooth_delay_samples_[c]);
                interleaved[base + static_cast<size_t>(c)] = static_cast<T>(sanitize(out));
            }
        }
    }

    bool enabled_ = false;
    float sample_rate_ = 48000.0f;
    float delay_allocated_sr_ = 0.0f;
    double smoothing_coeff_ = 0.001;
    bool need_filter_update_ = true;

    float crossover_hz_ = 80.0f;
    float lfe_lpf_hz_ = 120.0f;
    float lfe_gain_db_ = 0.0f;
    double lfe_gain_lin_ = 1.0;
    double smooth_lfe_gain_lin_ = 1.0;
    BassLfeMode lfe_mode_ = BassLfeMode::LfeOnly;

    bool front_small_ = true;
    bool center_small_ = true;
    bool surround_small_ = true;
    bool rear_small_ = true;

    std::array<float, kMaxChannels> trim_db_{};
    std::array<double, kMaxChannels> target_trim_lin_{1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0};
    std::array<double, kMaxChannels> smooth_trim_lin_{1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0};

    std::array<float, kMaxChannels> delay_ms_{};
    std::array<double, kMaxChannels> smooth_delay_samples_{};
    std::array<std::vector<double>, kMaxChannels> delay_buf_{};
    std::array<size_t, kMaxChannels> delay_write_{};

    CytomicSVF hp1_, hp2_;
    CytomicSVF lp1_, lp2_;
    CytomicSVF lfe_lp1_, lfe_lp2_;
};

// =============================================================================
// ChannelLayoutRouter:
//   Stateless ITU-R BS.775 / Dolby-compliant in-place channel layout converter.
//   Supports 1, 2, 6 (5.1 SMPTE), and 8 (7.1 SMPTE) channels in-place.
// =============================================================================
class ChannelLayoutRouter {
public:
    template <typename T>
    static void convert(T* buf, uint32_t frames, int inChannels, int outChannels,
                        double lfeDownmixGain = 0.7071067811865475) {
        if (!buf || frames == 0 || inChannels <= 0 || outChannels <= 0 || inChannels == outChannels) {
            return;
        }

        constexpr double kInvSqrt2 = 0.7071067811865475;

        // Downmixes (outChannels < inChannels): iterate forward safely in-place
        if (outChannels == 2 && inChannels == 6) {
            // 5.1 -> 2.0 (ITU-R BS.775 + optional LFE)
            // Gain normalization prevents multi-channel sum clipping on correlated material
            const double norm = 1.0 / (1.0 + kInvSqrt2 + kInvSqrt2);
            for (uint32_t i = 0; i < frames; ++i) {
                const size_t inB = static_cast<size_t>(i) * 6u;
                const double fl  = static_cast<double>(buf[inB + 0]);
                const double fr  = static_cast<double>(buf[inB + 1]);
                const double fc  = static_cast<double>(buf[inB + 2]);
                const double lfe = static_cast<double>(buf[inB + 3]);
                const double sl  = static_cast<double>(buf[inB + 4]);
                const double sr  = static_cast<double>(buf[inB + 5]);

                const double l = (fl + kInvSqrt2 * fc + kInvSqrt2 * sl + lfeDownmixGain * lfe) * norm;
                const double r = (fr + kInvSqrt2 * fc + kInvSqrt2 * sr + lfeDownmixGain * lfe) * norm;
                buf[static_cast<size_t>(i) * 2u + 0] = static_cast<T>(l);
                buf[static_cast<size_t>(i) * 2u + 1] = static_cast<T>(r);
            }
            return;
        }

        if (outChannels == 2 && inChannels == 8) {
            // 7.1 -> 2.0
            const double norm = 1.0 / (1.0 + kInvSqrt2 + kInvSqrt2 + kInvSqrt2);
            for (uint32_t i = 0; i < frames; ++i) {
                const size_t inB = static_cast<size_t>(i) * 8u;
                const double fl  = static_cast<double>(buf[inB + 0]);
                const double fr  = static_cast<double>(buf[inB + 1]);
                const double fc  = static_cast<double>(buf[inB + 2]);
                const double lfe = static_cast<double>(buf[inB + 3]);
                const double bl  = static_cast<double>(buf[inB + 4]);
                const double br  = static_cast<double>(buf[inB + 5]);
                const double sl  = static_cast<double>(buf[inB + 6]);
                const double sr  = static_cast<double>(buf[inB + 7]);

                const double l = (fl + kInvSqrt2 * fc + kInvSqrt2 * sl + kInvSqrt2 * bl + lfeDownmixGain * lfe) * norm;
                const double r = (fr + kInvSqrt2 * fc + kInvSqrt2 * sr + kInvSqrt2 * br + lfeDownmixGain * lfe) * norm;
                buf[static_cast<size_t>(i) * 2u + 0] = static_cast<T>(l);
                buf[static_cast<size_t>(i) * 2u + 1] = static_cast<T>(r);
            }
            return;
        }

        if (outChannels == 6 && inChannels == 8) {
            // 7.1 -> 5.1: fold Side + Back surrounds into 5.1 SL/SR
            for (uint32_t i = 0; i < frames; ++i) {
                const size_t inB  = static_cast<size_t>(i) * 8u;
                const size_t outB = static_cast<size_t>(i) * 6u;
                const double fl  = static_cast<double>(buf[inB + 0]);
                const double fr  = static_cast<double>(buf[inB + 1]);
                const double fc  = static_cast<double>(buf[inB + 2]);
                const double lfe = static_cast<double>(buf[inB + 3]);
                const double bl  = static_cast<double>(buf[inB + 4]);
                const double br  = static_cast<double>(buf[inB + 5]);
                const double sl  = static_cast<double>(buf[inB + 6]);
                const double sr  = static_cast<double>(buf[inB + 7]);

                buf[outB + 0] = static_cast<T>(fl);
                buf[outB + 1] = static_cast<T>(fr);
                buf[outB + 2] = static_cast<T>(fc);
                buf[outB + 3] = static_cast<T>(lfe);
                buf[outB + 4] = static_cast<T>(kInvSqrt2 * (sl + bl));
                buf[outB + 5] = static_cast<T>(kInvSqrt2 * (sr + br));
            }
            return;
        }

        // Expansions (outChannels > inChannels): iterate BACKWARDS so unread frames aren't overwritten
        if (outChannels == 8 && inChannels == 6) {
            // 5.1 -> 7.1: map SL/SR to both side (6,7) and attenuated rear (-6 dB -> 4,5)
            for (uint32_t idx = frames; idx > 0; --idx) {
                const uint32_t i = idx - 1;
                const size_t inB  = static_cast<size_t>(i) * 6u;
                const size_t outB = static_cast<size_t>(i) * 8u;
                const T fl  = buf[inB + 0];
                const T fr  = buf[inB + 1];
                const T fc  = buf[inB + 2];
                const T lfe = buf[inB + 3];
                const T sl  = buf[inB + 4];
                const T sr  = buf[inB + 5];

                buf[outB + 0] = fl;
                buf[outB + 1] = fr;
                buf[outB + 2] = fc;
                buf[outB + 3] = lfe;
                buf[outB + 4] = static_cast<T>(static_cast<double>(sl) * 0.5);
                buf[outB + 5] = static_cast<T>(static_cast<double>(sr) * 0.5);
                buf[outB + 6] = static_cast<T>(static_cast<double>(sl) * 0.8660254037844386);
                buf[outB + 7] = static_cast<T>(static_cast<double>(sr) * 0.8660254037844386);
            }
            return;
        }

        if (outChannels > inChannels) {
            for (uint32_t idx = frames; idx > 0; --idx) {
                const uint32_t i = idx - 1;
                const size_t inB  = static_cast<size_t>(i) * static_cast<size_t>(inChannels);
                const size_t outB = static_cast<size_t>(i) * static_cast<size_t>(outChannels);
                if (inChannels == 1) {
                    const T m = buf[inB];
                    for (int c = 0; c < outChannels; ++c) {
                        buf[outB + static_cast<size_t>(c)] = (c < 2) ? m : static_cast<T>(0);
                    }
                } else {
                    for (int c = outChannels - 1; c >= 0; --c) {
                        buf[outB + static_cast<size_t>(c)] = (c < inChannels) ? buf[inB + static_cast<size_t>(c)] : static_cast<T>(0);
                    }
                }
            }
            return;
        }

        // Generic downmix fallback (e.g., N -> 1 or arbitrary N -> M where M < N)
        if (outChannels == 1) {
            const double invN = 1.0 / static_cast<double>(inChannels);
            for (uint32_t i = 0; i < frames; ++i) {
                const size_t inB = static_cast<size_t>(i) * static_cast<size_t>(inChannels);
                double sum = 0.0;
                for (int c = 0; c < inChannels; ++c) {
                    sum += static_cast<double>(buf[inB + static_cast<size_t>(c)]);
                }
                buf[i] = static_cast<T>(sum * invN);
            }
            return;
        }

        for (uint32_t i = 0; i < frames; ++i) {
            const size_t inB  = static_cast<size_t>(i) * static_cast<size_t>(inChannels);
            const size_t outB = static_cast<size_t>(i) * static_cast<size_t>(outChannels);
            for (int c = 0; c < outChannels; ++c) {
                buf[outB + static_cast<size_t>(c)] = buf[inB + static_cast<size_t>(c)];
            }
        }
    }
};

} // namespace sauti::dsp
