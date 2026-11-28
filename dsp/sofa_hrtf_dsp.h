#pragma once

#include <algorithm>
#include <array>
#include <atomic>
#include <cmath>
#include <complex>
#include <cstdint>
#include <cstring>
#include <mutex>
#include <string>
#include <vector>
#include "simd_math.h"
#include "CDSPResampler.h"

#if defined(SAUTIFLOW_ENABLE_MYSOFA) && SAUTIFLOW_ENABLE_MYSOFA
#include "mysofa.h"
#endif

namespace sauti::dsp {

struct SofaHrtfMetadata {
    bool loaded = false;
    int native_sample_rate = 0;
    int engine_sample_rate = 0;
    int ir_length = 0;
    int num_measurements = 0;
    int latency_samples = 128;
    std::string name;
};

// =============================================================================
// SofaHrtfDSP: Real-Time Uniform Partitioned Multi-Source SOFA HRTF Renderer
//
// - Parses AES69 .sofa files (file path or memory buffer) via vendored libmysofa.
// - Resamples HRIRs off-thread with r8brain CDSPResampler24 on sample-rate change.
// - Supports 2-speaker (Stereo), 5-speaker (5.1), and 7-speaker (7.1) virtual
//   banks simultaneously, with latency-aligned LFE passthrough and dry alignment.
// - Exploits frequency-domain linearity: N forward 256-pt FFTs + MACs + only 2
//   inverse 256-pt FFTs (L/R ears), giving 128-sample (2.67 ms @ 48 kHz) latency.
// - Lock-free audio fast-path check and non-blocking try_to_lock hot-swap.
// =============================================================================
class SofaHrtfDSP {
public:
    static constexpr size_t BLOCK_SIZE = 128;
    static constexpr size_t FFT_SIZE = 256;
    static constexpr size_t HALF_BINS = BLOCK_SIZE + 1; // 129
    static constexpr size_t MAX_SPEAKERS = 7;
    static constexpr size_t MAX_SEGMENTS = 32; // up to 4096 samples (>21 ms @ 192 kHz)
    static constexpr size_t MAX_IR_FRAMES = BLOCK_SIZE * MAX_SEGMENTS;
    static constexpr size_t RING_SIZE = 512; // power of 2 >= FFT_SIZE
    static constexpr size_t RING_MASK = RING_SIZE - 1;

    SofaHrtfDSP() {
        initFftTables();
        setSampleRate(48000.0f);
    }

    void setSampleRate(float sampleRate) {
        if (sampleRate <= 0.0f || !std::isfinite(sampleRate)) sampleRate = 48000.0f;
        const bool srChanged = std::fabs(sample_rate_ - sampleRate) >= 1.0f;
        sample_rate_ = sampleRate;
        crossfade_step_ = 1.0f / (0.015f * sample_rate_);

        if (srChanged && !raw_sofa_bytes_.empty()) {
            rebuildFromRawBytes();
        }
    }

    void setStereoAngleDeg(float angleDeg) {
        const float clamped = std::clamp(angleDeg, 5.0f, 60.0f);
        if (std::fabs(stereo_angle_deg_ - clamped) < 0.25f) return;
        stereo_angle_deg_ = clamped;
        if (!raw_sofa_bytes_.empty()) {
            rebuildFromRawBytes();
        }
    }

    float getStereoAngleDeg() const { return stereo_angle_deg_; }

    bool loadFromFile(const char* filePath, float engineSampleRate, float stereoAngleDeg = 30.0f) {
        if (!filePath || filePath[0] == '\0') return false;
        std::FILE* f = std::fopen(filePath, "rb");
        if (!f) return false;
        std::fseek(f, 0, SEEK_END);
        const long sz = std::ftell(f);
        if (sz <= 0 || sz > 64L * 1024L * 1024L) {
            std::fclose(f);
            return false;
        }
        std::fseek(f, 0, SEEK_SET);
        std::vector<uint8_t> bytes(static_cast<size_t>(sz));
        const size_t got = std::fread(bytes.data(), 1, bytes.size(), f);
        std::fclose(f);
        if (got != bytes.size()) return false;
        return loadFromMemory(bytes.data(), bytes.size(), engineSampleRate, stereoAngleDeg);
    }

    bool loadFromMemory(const uint8_t* data, size_t byteCount, float engineSampleRate, float stereoAngleDeg = 30.0f) {
        if (!data || byteCount == 0) return false;
        if (engineSampleRate > 0.0f && std::isfinite(engineSampleRate)) {
            sample_rate_ = engineSampleRate;
            crossfade_step_ = 1.0f / (0.015f * sample_rate_);
        }
        stereo_angle_deg_ = std::clamp(stereoAngleDeg, 5.0f, 60.0f);

        std::vector<uint8_t> copy(data, data + byteCount);
        BankSet staged;
        SofaHrtfMetadata meta;
        if (!buildBanksFromMemory(copy.data(), copy.size(), sample_rate_, stereo_angle_deg_, staged, meta)) {
            return false;
        }

        {
            std::lock_guard<std::mutex> lock(bank_mutex_);
            raw_sofa_bytes_ = std::move(copy);
            installStagedBanksLocked(std::move(staged), meta);
        }
        return true;
    }

    void clear() {
        std::lock_guard<std::mutex> lock(bank_mutex_);
        has_bank_.store(false, std::memory_order_release);
        raw_sofa_bytes_.clear();
        banks_ = BankSet{};
        meta_ = SofaHrtfMetadata{};
        resetAudioBuffersLocked();
    }

    void reset() {
        std::lock_guard<std::mutex> lock(bank_mutex_);
        resetAudioBuffersLocked();
    }

    bool isLoaded() const { return has_bank_.load(std::memory_order_acquire); }

    SofaHrtfMetadata getMetadata() const {
        std::lock_guard<std::mutex> lock(bank_mutex_);
        return meta_;
    }

    size_t getLatencySamples() const {
        if (!has_bank_.load(std::memory_order_acquire)) return 0;
        std::lock_guard<std::mutex> lock(bank_mutex_);
        return BLOCK_SIZE + banks_.extra_dry_delay;
    }

    // Process interleaved audio (2ch, 6ch, or 8ch) into 2ch binaural stereo in-place.
    // Returns true if SOFA HRTF rendered the block, false if unavailable/contended.
    template <typename T>
    bool process(T* interleaved, uint32_t frameCount, int inChannels,
                 double lfeGain = 0.7071067811865475, double wetMix = 1.0) {
        if (!interleaved || frameCount == 0) return false;
        if (inChannels != 2 && inChannels != 6 && inChannels != 8) return false;
        if (!has_bank_.load(std::memory_order_acquire)) return false;

        std::unique_lock<std::mutex> lock(bank_mutex_, std::try_to_lock);
        if (!lock.owns_lock() || !has_bank_.load(std::memory_order_acquire)) return false;

        const Bank& bank = (inChannels == 2) ? banks_.bank2
                         : (inChannels == 6) ? banks_.bank5
                                             : banks_.bank7;
        if (bank.num_speakers == 0 || bank.num_segments == 0) return false;

        // If active speaker layout changed mid-stream, clear stale FDL state
        if (last_active_in_channels_ != inChannels) {
            resetAudioBuffersLocked();
            last_active_in_channels_ = inChannels;
        }

        const size_t nSpk = bank.num_speakers;
        const size_t dryDelayLen = BLOCK_SIZE + banks_.extra_dry_delay;
        const double wMix = std::clamp(wetMix, 0.0, 1.0);
        const double dMix = 1.0 - wMix;

        // Map SMPTE channels to speaker indices [0..nSpk-1], skipping LFE (ch 3)
        static constexpr int kMap2[2] = {0, 1};
        static constexpr int kMap6[5] = {0, 1, 2, 4, 5};
        static constexpr int kMap8[7] = {0, 1, 2, 4, 5, 6, 7};
        const int* chMap = (inChannels == 2) ? kMap2 : (inChannels == 6 ? kMap6 : kMap8);

        uint32_t processed = 0;
        while (processed < frameCount) {
            const uint32_t curPos = static_cast<uint32_t>(sample_clock_ & (BLOCK_SIZE - 1));
            const uint32_t chunk = std::min(static_cast<uint32_t>(BLOCK_SIZE) - curPos, frameCount - processed);

            for (uint32_t i = 0; i < chunk; ++i) {
                const uint32_t fIdx = processed + i;
                const size_t inBase = static_cast<size_t>(fIdx) * static_cast<size_t>(inChannels);
                const size_t outBase = static_cast<size_t>(fIdx) * 2u;
                const size_t histIdx = sample_clock_ & (BLOCK_SIZE - 1);

                for (size_t s = 0; s < nSpk; ++s) {
                    hist_in_[s][histIdx] = static_cast<double>(interleaved[inBase + static_cast<size_t>(chMap[s])]);
                }

                // Latency-aligned dry FL/FR and LFE passthrough
                double lfeDelayed = 0.0;
                double dryDelayedL = 0.0;
                double dryDelayedR = 0.0;
                if (dryDelayLen > 0) {
                    dryDelayedL = dry_delay_l_[dry_delay_pos_];
                    dryDelayedR = dry_delay_r_[dry_delay_pos_];
                    lfeDelayed  = lfe_delay_[dry_delay_pos_];

                    dry_delay_l_[dry_delay_pos_] = static_cast<double>(interleaved[inBase + 0]);
                    dry_delay_r_[dry_delay_pos_] = static_cast<double>(interleaved[inBase + 1]);
                    lfe_delay_[dry_delay_pos_]   = (inChannels >= 4) ? static_cast<double>(interleaved[inBase + 3]) : 0.0;
                    dry_delay_pos_ = (dry_delay_pos_ + 1 < dryDelayLen) ? (dry_delay_pos_ + 1) : 0;
                }

                const size_t ringIdx = sample_clock_ & RING_MASK;
                const double wetL = out_ring_l_[ringIdx];
                const double wetR = out_ring_r_[ringIdx];
                out_ring_l_[ringIdx] = 0.0;
                out_ring_r_[ringIdx] = 0.0;

                double swapGain = 1.0;
                if (swap_fade_active_) {
                    constexpr double kDip = 0.35;
                    if (swap_hold_samples_ > 0) {
                        swap_depth_ = std::min(1.0f, swap_depth_ + 2.0f * crossfade_step_);
                        if (swap_depth_ >= 1.0f) swap_hold_samples_--;
                    } else {
                        swap_depth_ = std::max(0.0f, swap_depth_ - 2.0f * crossfade_step_);
                        if (swap_depth_ <= 0.0f) swap_fade_active_ = false;
                    }
                    swapGain = 1.0 - (1.0 - kDip) * static_cast<double>(swap_depth_);
                }

                const double lfeContrib = (inChannels >= 4) ? (lfeDelayed * lfeGain) : 0.0;
                double outL = dMix * dryDelayedL + wMix * (wetL * swapGain + lfeContrib);
                double outR = dMix * dryDelayedR + wMix * (wetR * swapGain + lfeContrib);

                if (std::fabs(outL) < 1.0e-25) outL = 0.0;
                if (std::fabs(outR) < 1.0e-25) outR = 0.0;

                interleaved[outBase + 0] = static_cast<T>(outL);
                interleaved[outBase + 1] = static_cast<T>(outR);

                ++sample_clock_;
            }

            processed += chunk;

            if ((sample_clock_ & (BLOCK_SIZE - 1)) == 0) {
                convolveBlockLocked(bank);
            }
        }

        return true;
    }

private:
    struct SpeakerSpec {
        float az_deg = 0.0f;
        float el_deg = 0.0f;
    };

    struct Bank {
        size_t num_speakers = 0;
        size_t num_segments = 0;
        // [speaker * num_segments * HALF_BINS + seg * HALF_BINS + bin]
        std::vector<std::complex<double>> ir_l;
        std::vector<std::complex<double>> ir_r;
    };

    struct BankSet {
        Bank bank2;
        Bank bank5;
        Bank bank7;
        size_t extra_dry_delay = 0;
    };

    void initFftTables() {
        constexpr double PI = 3.14159265358979323846;
        for (size_t i = 0; i < FFT_SIZE; ++i) {
            const double angle = -2.0 * PI * static_cast<double>(i) / static_cast<double>(FFT_SIZE);
            twiddles_[i] = std::complex<double>(std::cos(angle), std::sin(angle));
        }
        constexpr size_t bits = 8; // log2(256)
        for (size_t i = 0; i < FFT_SIZE; ++i) {
            size_t rev = 0;
            for (size_t b = 0; b < bits; ++b) {
                if ((i >> b) & 1u) {
                    rev |= (static_cast<size_t>(1) << (bits - 1 - b));
                }
            }
            bit_rev_[i] = rev;
        }
        fdl_.assign(MAX_SPEAKERS * MAX_SEGMENTS * HALF_BINS, std::complex<double>(0.0, 0.0));
        dry_delay_l_.assign(BLOCK_SIZE, 0.0);
        dry_delay_r_.assign(BLOCK_SIZE, 0.0);
        lfe_delay_.assign(BLOCK_SIZE, 0.0);
    }

    void forwardFFT(const double* timeIn, std::complex<double>* freqOut) const {
        for (size_t i = 0; i < FFT_SIZE; ++i) {
            freqOut[bit_rev_[i]] = std::complex<double>(timeIn[i], 0.0);
        }
        for (size_t len = 2; len <= FFT_SIZE; len <<= 1) {
            const size_t halfLen = len >> 1;
            const size_t step = FFT_SIZE / len;
            for (size_t i = 0; i < FFT_SIZE; i += len) {
                for (size_t j = 0; j < halfLen; ++j) {
                    const std::complex<double> u = freqOut[i + j];
                    const std::complex<double> v = freqOut[i + j + halfLen] * twiddles_[j * step];
                    freqOut[i + j] = u + v;
                    freqOut[i + j + halfLen] = u - v;
                }
            }
        }
    }

    void inverseFFTHermitian(std::complex<double>* freqHalfIn, double* timeOut) {
        for (size_t k = 1; k < BLOCK_SIZE; ++k) {
            freqHalfIn[FFT_SIZE - k] = std::conj(freqHalfIn[k]);
        }
        std::complex<double>* temp = scratch_ifft_.data();
        for (size_t i = 0; i < FFT_SIZE; ++i) {
            temp[bit_rev_[i]] = freqHalfIn[i];
        }
        for (size_t len = 2; len <= FFT_SIZE; len <<= 1) {
            const size_t halfLen = len >> 1;
            const size_t step = FFT_SIZE / len;
            for (size_t i = 0; i < FFT_SIZE; i += len) {
                for (size_t j = 0; j < halfLen; ++j) {
                    const std::complex<double> u = temp[i + j];
                    const std::complex<double> tw = twiddles_[j * step];
                    const std::complex<double> w(tw.real(), -tw.imag());
                    const std::complex<double> v = temp[i + j + halfLen] * w;
                    temp[i + j] = u + v;
                    temp[i + j + halfLen] = u - v;
                }
            }
        }
        constexpr double invN = 1.0 / static_cast<double>(FFT_SIZE);
        for (size_t i = 0; i < FFT_SIZE; ++i) {
            timeOut[i] = temp[i].real() * invN;
        }
    }

    void convolveBlockLocked(const Bank& bank) {
        const size_t nSpk = bank.num_speakers;
        const size_t nSeg = bank.num_segments;

        std::fill(accum_l_.begin(), accum_l_.begin() + HALF_BINS, std::complex<double>(0.0, 0.0));
        std::fill(accum_r_.begin(), accum_r_.begin() + HALF_BINS, std::complex<double>(0.0, 0.0));

        // Frequency-domain linearity: N forward FFTs + MACs -> 2 inverse FFTs total
        for (size_t s = 0; s < nSpk; ++s) {
            std::memcpy(scratch_time_.data(), hist_in_[s].data(), BLOCK_SIZE * sizeof(double));
            std::memset(scratch_time_.data() + BLOCK_SIZE, 0, BLOCK_SIZE * sizeof(double));
            forwardFFT(scratch_time_.data(), scratch_freq_.data());

            const size_t fdlBase = s * nSeg * HALF_BINS;
            std::memcpy(&fdl_[fdlBase + fdl_head_ * HALF_BINS], scratch_freq_.data(),
                        HALF_BINS * sizeof(std::complex<double>));

            const size_t irBase = s * nSeg * HALF_BINS;
            for (size_t seg = 0; seg < nSeg; ++seg) {
                const size_t slot = (fdl_head_ + nSeg - seg) % nSeg;
                const std::complex<double>* x = &fdl_[fdlBase + slot * HALF_BINS];
                const std::complex<double>* hl = &bank.ir_l[irBase + seg * HALF_BINS];
                const std::complex<double>* hr = &bank.ir_r[irBase + seg * HALF_BINS];
                for (size_t k = 0; k < HALF_BINS; ++k) {
                    accum_l_[k] += x[k] * hl[k];
                    accum_r_[k] += x[k] * hr[k];
                }
            }
        }

        fdl_head_ = (fdl_head_ + 1) % nSeg;

        inverseFFTHermitian(accum_l_.data(), scratch_time_l_.data());
        inverseFFTHermitian(accum_r_.data(), scratch_time_r_.data());

        for (size_t i = 0; i < FFT_SIZE; ++i) {
            const size_t idx = (sample_clock_ + i) & RING_MASK;
            out_ring_l_[idx] += scratch_time_l_[i];
            out_ring_r_[idx] += scratch_time_r_[i];
        }
    }

    void rebuildFromRawBytes() {
        std::vector<uint8_t> rawCopy;
        float sr = 48000.0f;
        float angle = 30.0f;
        {
            std::lock_guard<std::mutex> lock(bank_mutex_);
            if (raw_sofa_bytes_.empty()) return;
            rawCopy = raw_sofa_bytes_;
            sr = sample_rate_;
            angle = stereo_angle_deg_;
        }
        BankSet staged;
        SofaHrtfMetadata meta;
        if (buildBanksFromMemory(rawCopy.data(), rawCopy.size(), sr, angle, staged, meta)) {
            std::lock_guard<std::mutex> lock(bank_mutex_);
            installStagedBanksLocked(std::move(staged), meta);
        }
    }

    void installStagedBanksLocked(BankSet&& staged, const SofaHrtfMetadata& meta) {
        const bool hotSwap = has_bank_.load(std::memory_order_acquire);
        const size_t newDryLen = BLOCK_SIZE + staged.extra_dry_delay;
        banks_ = std::move(staged);
        meta_ = meta;
        meta_.loaded = true;
        meta_.latency_samples = static_cast<int>(newDryLen);

        if (dry_delay_l_.size() != newDryLen) {
            dry_delay_l_.assign(newDryLen, 0.0);
            dry_delay_r_.assign(newDryLen, 0.0);
            lfe_delay_.assign(newDryLen, 0.0);
            dry_delay_pos_ = 0;
        }

        if (hotSwap) {
            swap_fade_active_ = true;
            swap_hold_samples_ = static_cast<uint32_t>(0.004f * sample_rate_);
        } else {
            resetAudioBuffersLocked();
        }
        has_bank_.store(true, std::memory_order_release);
    }

    void resetAudioBuffersLocked() {
        for (auto& h : hist_in_) h.fill(0.0);
        std::fill(fdl_.begin(), fdl_.end(), std::complex<double>(0.0, 0.0));
        out_ring_l_.fill(0.0);
        out_ring_r_.fill(0.0);
        std::fill(dry_delay_l_.begin(), dry_delay_l_.end(), 0.0);
        std::fill(dry_delay_r_.begin(), dry_delay_r_.end(), 0.0);
        std::fill(lfe_delay_.begin(), lfe_delay_.end(), 0.0);
        dry_delay_pos_ = 0;
        fdl_head_ = 0;
        sample_clock_ = 0;
        swap_fade_active_ = false;
        swap_depth_ = 0.0f;
        swap_hold_samples_ = 0;
    }

    bool buildBanksFromMemory(const uint8_t* data, size_t byteCount,
                              float engineSr, float stereoAngleDeg,
                              BankSet& outBanks, SofaHrtfMetadata& outMeta) const {
#if defined(SAUTIFLOW_ENABLE_MYSOFA) && SAUTIFLOW_ENABLE_MYSOFA
        int err = MYSOFA_OK;
        struct MYSOFA_HRTF* hrtf = mysofa_load_data(reinterpret_cast<const char*>(data), byteCount, &err);
        if (!hrtf || err != MYSOFA_OK) {
            if (hrtf) mysofa_free(hrtf);
            return false;
        }

        if (mysofa_check(hrtf) != MYSOFA_OK || hrtf->N == 0 || hrtf->R < 2 || hrtf->M == 0) {
            mysofa_free(hrtf);
            return false;
        }

        float nativeSr = 48000.0f;
        if (hrtf->DataSamplingRate.elements >= 1 && hrtf->DataSamplingRate.values &&
            hrtf->DataSamplingRate.values[0] > 0.0f) {
            nativeSr = hrtf->DataSamplingRate.values[0];
        }

        std::string title;
        auto tryAttr = [&](const char* key) {
            if (!title.empty()) return;
            char* val = mysofa_getAttribute(hrtf->attributes, const_cast<char*>(key));
            if (val && val[0] != '\0') title = val;
        };
        tryAttr("Title");
        tryAttr("DatabaseName");
        tryAttr("ListenerShortName");
        if (title.empty()) title = "Personal SOFA HRTF";

        mysofa_loudness(hrtf);
        mysofa_tocartesian(hrtf);

        struct MYSOFA_LOOKUP* lookup = mysofa_lookup_init(hrtf);
        if (!lookup) {
            mysofa_free(hrtf);
            return false;
        }
        struct MYSOFA_NEIGHBORHOOD* neigh = mysofa_neighborhood_init_withstepdefine(
            hrtf, lookup, MYSOFA_DEFAULT_NEIGH_STEP_ANGLE, MYSOFA_DEFAULT_NEIGH_STEP_RADIUS);

        const uint32_t rawN = hrtf->N;
        const bool needResample = (std::fabs(static_cast<double>(nativeSr) - static_cast<double>(engineSr)) > 1.0);
        const double srRatio = static_cast<double>(engineSr) / static_cast<double>(nativeSr);
        const uint32_t prePadIn = needResample ? 64u : 0u;
        const uint32_t prePadOut = needResample ? static_cast<uint32_t>(std::llround(static_cast<double>(prePadIn) * srRatio)) : 0u;
        outBanks.extra_dry_delay = prePadOut;

        struct RawPair {
            std::vector<double> l;
            std::vector<double> r;
            double delayLSec = 0.0;
            double delayRSec = 0.0;
            double nativeEnergy = 0.0;
        };

        auto extractPair = [&](const SpeakerSpec& spk) -> RawPair {
            RawPair p;
            // AES69 SOFA azimuth is CCW (+az = Left +Y, -az = Right -Y), opposite to our -Left/+Right sign.
            float c[3] = {-spk.az_deg, spk.el_deg, 1.5f};
            mysofa_s2c(c);
            int nearest = mysofa_lookup(lookup, c);
            if (nearest < 0) nearest = 0;
            int* neighborhood = neigh ? mysofa_neighborhood(neigh, nearest) : nullptr;
            std::vector<float> scratch(static_cast<size_t>(hrtf->R) * rawN, 0.0f);
            float delays[2] = {0.0f, 0.0f};
            float* res = mysofa_interpolate(hrtf, c, nearest, neighborhood, scratch.data(), delays);
            if (!res) res = scratch.data();

            p.delayLSec = std::isfinite(delays[0]) ? static_cast<double>(delays[0]) : 0.0;
            p.delayRSec = std::isfinite(delays[1]) ? static_cast<double>(delays[1]) : 0.0;

            for (uint32_t n = 0; n < rawN; ++n) {
                const double rawL = static_cast<double>(res[n]);
                const double rawR = static_cast<double>(res[rawN + n]);
                const double vl = std::isfinite(rawL) ? rawL : 0.0;
                const double vr = std::isfinite(rawR) ? rawR : 0.0;
                p.nativeEnergy += vl * vl + vr * vr;
            }

            if (!needResample) {
                p.l.resize(rawN);
                p.r.resize(rawN);
                for (uint32_t n = 0; n < rawN; ++n) {
                    const double vl = static_cast<double>(res[n]);
                    const double vr = static_cast<double>(res[rawN + n]);
                    p.l[n] = std::isfinite(vl) ? vl : 0.0;
                    p.r[n] = std::isfinite(vr) ? vr : 0.0;
                }
            } else {
                const uint32_t tailPadOut = 64u;
                const uint32_t totalIn = prePadIn + rawN;
                const uint32_t resampledCore = static_cast<uint32_t>(std::ceil(static_cast<double>(rawN) * srRatio));
                const uint32_t outLen = prePadOut + resampledCore + tailPadOut;
                const double tapGain = static_cast<double>(nativeSr) / static_cast<double>(engineSr);

                std::vector<double> inBuf(totalIn, 0.0);
                std::vector<double> outBuf(outLen, 0.0);
                r8b::CDSPResampler24 resampler(static_cast<double>(nativeSr), static_cast<double>(engineSr), 4096);

                for (uint32_t n = 0; n < rawN; ++n) {
                    const double vl = static_cast<double>(res[n]);
                    inBuf[prePadIn + n] = std::isfinite(vl) ? vl : 0.0;
                }
                resampler.clear();
                resampler.oneshot(inBuf.data(), static_cast<int>(totalIn), outBuf.data(), static_cast<int>(outLen));
                p.l.resize(outLen);
                for (uint32_t n = 0; n < outLen; ++n) p.l[n] = std::isfinite(outBuf[n]) ? (outBuf[n] * tapGain) : 0.0;

                std::fill(inBuf.begin(), inBuf.end(), 0.0);
                std::fill(outBuf.begin(), outBuf.end(), 0.0);
                for (uint32_t n = 0; n < rawN; ++n) {
                    const double vr = static_cast<double>(res[rawN + n]);
                    inBuf[prePadIn + n] = std::isfinite(vr) ? vr : 0.0;
                }
                resampler.clear();
                resampler.oneshot(inBuf.data(), static_cast<int>(totalIn), outBuf.data(), static_cast<int>(outLen));
                p.r.resize(outLen);
                for (uint32_t n = 0; n < outLen; ++n) p.r[n] = std::isfinite(outBuf[n]) ? (outBuf[n] * tapGain) : 0.0;
            }
            return p;
        };

        auto buildBank = [&](const std::vector<SpeakerSpec>& specs) -> Bank {
            Bank bk;
            bk.num_speakers = specs.size();
            std::vector<RawPair> pairs;
            pairs.reserve(specs.size());

            double minDelaySec = 1e9;
            for (const auto& spk : specs) {
                RawPair rp = extractPair(spk);
                minDelaySec = std::min(minDelaySec, std::min(rp.delayLSec, rp.delayRSec));
                pairs.push_back(std::move(rp));
            }
            if (!std::isfinite(minDelaySec) || minDelaySec > 1.0) minDelaySec = 0.0;

            size_t maxFinalLen = 0;
            std::vector<std::vector<double>> shiftedL(specs.size()), shiftedR(specs.size());
            for (size_t s = 0; s < specs.size(); ++s) {
                const double dL = std::clamp((pairs[s].delayLSec - minDelaySec) * static_cast<double>(engineSr), 0.0, 256.0);
                const double dR = std::clamp((pairs[s].delayRSec - minDelaySec) * static_cast<double>(engineSr), 0.0, 256.0);
                const size_t padL = static_cast<size_t>(std::ceil(dL)) + 2u;
                const size_t padR = static_cast<size_t>(std::ceil(dR)) + 2u;
                const size_t lenL = pairs[s].l.size() + padL;
                const size_t lenR = pairs[s].r.size() + padR;

                auto shiftFrac = [](const std::vector<double>& src, double d, size_t dstLen) {
                    std::vector<double> dst(dstLen, 0.0);
                    const size_t i0 = static_cast<size_t>(d);
                    const double frac = d - static_cast<double>(i0);
                    for (size_t n = 0; n < src.size(); ++n) {
                        const double v = src[n];
                        if (n + i0 < dstLen) dst[n + i0] += v * (1.0 - frac);
                        if (n + i0 + 1 < dstLen) dst[n + i0 + 1] += v * frac;
                    }
                    return dst;
                };

                shiftedL[s] = shiftFrac(pairs[s].l, dL, lenL);
                shiftedR[s] = shiftFrac(pairs[s].r, dR, lenR);
                maxFinalLen = std::max(maxFinalLen, std::max(lenL, lenR));
            }

            // Normalize bank energy from NATIVE frontal L/R speaker energy (index 0) so
            // unity passband gain stays rate-invariant across 44.1/48/96/192 kHz after tapGain scaling,
            // while preserving exact interaural level differences (ILD) across all speakers.
            const double refEnergy = pairs[0].nativeEnergy;
            const double normGain = (refEnergy > 1.0e-9) ? (1.0 / std::sqrt(0.5 * refEnergy)) : 1.0;

            const size_t clampedLen = std::min(maxFinalLen, MAX_IR_FRAMES);
            bk.num_segments = std::max<size_t>(1, (clampedLen + BLOCK_SIZE - 1) / BLOCK_SIZE);
            if (bk.num_segments > MAX_SEGMENTS) bk.num_segments = MAX_SEGMENTS;

            const size_t totalBins = bk.num_speakers * bk.num_segments * HALF_BINS;
            bk.ir_l.assign(totalBins, std::complex<double>(0.0, 0.0));
            bk.ir_r.assign(totalBins, std::complex<double>(0.0, 0.0));

            std::vector<double> timeBlock(FFT_SIZE, 0.0);
            std::vector<std::complex<double>> freqBlock(FFT_SIZE);

            for (size_t s = 0; s < bk.num_speakers; ++s) {
                for (size_t seg = 0; seg < bk.num_segments; ++seg) {
                    const size_t offset = seg * BLOCK_SIZE;
                    const size_t dstIdx = (s * bk.num_segments + seg) * HALF_BINS;

                    std::fill(timeBlock.begin(), timeBlock.end(), 0.0);
                    for (size_t n = 0; n < BLOCK_SIZE; ++n) {
                        if (offset + n < shiftedL[s].size() && offset + n < clampedLen) {
                            timeBlock[n] = shiftedL[s][offset + n] * normGain;
                        }
                    }
                    forwardFFT(timeBlock.data(), freqBlock.data());
                    std::memcpy(&bk.ir_l[dstIdx], freqBlock.data(), HALF_BINS * sizeof(std::complex<double>));

                    std::fill(timeBlock.begin(), timeBlock.end(), 0.0);
                    for (size_t n = 0; n < BLOCK_SIZE; ++n) {
                        if (offset + n < shiftedR[s].size() && offset + n < clampedLen) {
                            timeBlock[n] = shiftedR[s][offset + n] * normGain;
                        }
                    }
                    forwardFFT(timeBlock.data(), freqBlock.data());
                    std::memcpy(&bk.ir_r[dstIdx], freqBlock.data(), HALF_BINS * sizeof(std::complex<double>));
                }
            }
            return bk;
        };

        outBanks.bank2 = buildBank({
            {-stereoAngleDeg, 0.0f},
            {+stereoAngleDeg, 0.0f}
        });

        outBanks.bank5 = buildBank({
            { -30.0f, 0.0f}, // FL
            { +30.0f, 0.0f}, // FR
            {   0.0f, 0.0f}, // FC
            {-110.0f, 0.0f}, // SL
            {+110.0f, 0.0f}  // SR
        });

        outBanks.bank7 = buildBank({
            { -30.0f, 0.0f}, // FL
            { +30.0f, 0.0f}, // FR
            {   0.0f, 0.0f}, // FC
            {-150.0f, 0.0f}, // BL
            {+150.0f, 0.0f}, // BR
            { -90.0f, 0.0f}, // SL
            { +90.0f, 0.0f}  // SR
        });

        outMeta.loaded = true;
        outMeta.native_sample_rate = static_cast<int>(std::llround(nativeSr));
        outMeta.engine_sample_rate = static_cast<int>(std::llround(engineSr));
        outMeta.ir_length = static_cast<int>(outBanks.bank2.num_segments * BLOCK_SIZE);
        outMeta.num_measurements = static_cast<int>(hrtf->M);
        outMeta.latency_samples = static_cast<int>(BLOCK_SIZE + outBanks.extra_dry_delay);
        outMeta.name = title;

        if (neigh) mysofa_neighborhood_free(neigh);
        mysofa_lookup_free(lookup);
        mysofa_free(hrtf);
        return true;
#else
        (void)data; (void)byteCount; (void)engineSr; (void)stereoAngleDeg;
        (void)outBanks; (void)outMeta;
        return false;
#endif
    }

    mutable std::mutex bank_mutex_;
    std::atomic<bool> has_bank_{false};
    float sample_rate_ = 48000.0f;
    float stereo_angle_deg_ = 30.0f;
    float crossfade_step_ = 0.001f;
    int last_active_in_channels_ = 0;

    std::vector<uint8_t> raw_sofa_bytes_;
    BankSet banks_{};
    SofaHrtfMetadata meta_{};

    // Audio thread state (protected by try_to_lock on bank_mutex_)
    std::array<std::array<double, BLOCK_SIZE>, MAX_SPEAKERS> hist_in_{};
    std::vector<std::complex<double>> fdl_;
    size_t fdl_head_ = 0;
    size_t sample_clock_ = 0;
    std::array<double, RING_SIZE> out_ring_l_{};
    std::array<double, RING_SIZE> out_ring_r_{};

    std::vector<double> dry_delay_l_;
    std::vector<double> dry_delay_r_;
    std::vector<double> lfe_delay_;
    size_t dry_delay_pos_ = 0;

    bool swap_fade_active_ = false;
    float swap_depth_ = 0.0f;
    uint32_t swap_hold_samples_ = 0;

    // FFT tables & scratch (zero audio-thread allocation)
    std::array<std::complex<double>, FFT_SIZE> twiddles_{};
    std::array<size_t, FFT_SIZE> bit_rev_{};
    std::array<double, FFT_SIZE> scratch_time_{};
    std::array<double, FFT_SIZE> scratch_time_l_{};
    std::array<double, FFT_SIZE> scratch_time_r_{};
    std::array<std::complex<double>, FFT_SIZE> scratch_freq_{};
    std::array<std::complex<double>, FFT_SIZE> accum_l_{};
    std::array<std::complex<double>, FFT_SIZE> accum_r_{};
    std::array<std::complex<double>, FFT_SIZE> scratch_ifft_{};
};

} // namespace sauti::dsp
