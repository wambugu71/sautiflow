#pragma once

#include <cmath>
#include <algorithm>
#include <cstdint>
#include <atomic>
#include "cytomic_svf_dsp.h"
#include "denormals.h"

namespace sauti::dsp {

// =============================================================================
// BaxandallToneDSP: Book-Accurate Active Baxandall & Quad Spectral Tilt
//
// 1. Active Proportional-Q Baxandall Bass/Treble:
//    - Based on Peter J. Baxandall's classic 1952 negative feedback tone network.
//    - Sliding turnover frequency & proportional-Q:
//        * At small gains (+/- 1 to 2 dB), turnover shifts outward (bass down
//          to ~35 Hz, treble up to ~15 kHz) with gentle slope (Q ~ 0.42-0.45),
//          leaving the critical 200 Hz - 4 kHz vocal/instrument range untouched.
//        * As gain increases to +/- 15 dB, turnover tightens to nominal corner
//          (100 Hz bass, 8 kHz treble) and slope sharpens (Q -> 0.707).
//    - Reciprocal symmetry: exact mathematical inverse for boost and cut.
//
// 2. Quad-Style Spectral Tilt Filter (650 Hz Logarithmic Midrange Pivot):
//    - Geometric mean of audible spectrum: sqrt(20 Hz * 20000 Hz) ~ 632.45 Hz ~ 650 Hz.
//    - Symmetrical 5 octaves below 650 Hz and 5 octaves above 650 Hz.
//    - Implemented as reciprocal dual-shelf filter (LowShelf at -T/2 dB,
//      HighShelf at +T/2 dB, both at 650 Hz with wide-skirt Q = 0.42).
//    - Phase cancellation: Opposite phase trajectories cancel around 650 Hz,
//      yielding a linear dB/octave seesaw with near-zero phase distortion.
//
// 3. Audio Performance:
//    - Evaluated in 64-bit double precision Andy Simper Cytomic SVF.
//    - Zero dynamic memory allocations in process loops.
//    - De-zippered per-sample exponential parameter smoothing (~25 ms).
// =============================================================================
class BaxandallToneDSP {
public:
    static constexpr int kMaxChannels = 8;
    static constexpr double kPivotFrequencyHz = 650.0;
    static constexpr double kMaxGainDb = 15.0;
    static constexpr double kMaxTiltDb = 6.0;

    BaxandallToneDSP() {
        setSampleRate(48000.0);
        reset();
    }

    void setSampleRate(double sampleRate) {
        if (sampleRate <= 0.0) sampleRate = 48000.0;
        sampleRate_ = sampleRate;
        updateSmoothingAlpha();
        updateFilters();
    }

    double getSampleRate() const { return sampleRate_; }

    void setEnabled(bool enabled) {
        enabled_.store(enabled, std::memory_order_release);
        if (!enabled) {
            reset();
        }
    }

    bool isEnabled() const { return enabled_.load(std::memory_order_relaxed); }

    void reset() {
        for (int c = 0; c < kMaxChannels; ++c) {
            bassShelf_[c].reset();
            trebleShelf_[c].reset();
            tiltLow_[c].reset();
            tiltHigh_[c].reset();
        }
        curBassDb_ = targetBassDb_.load(std::memory_order_relaxed);
        curTrebleDb_ = targetTrebleDb_.load(std::memory_order_relaxed);
        curTiltDb_ = targetTiltDb_.load(std::memory_order_relaxed);
        updateFilters();
    }

    // Setters (-15 dB to +15 dB for tone, -6 dB to +6 dB for tilt)
    void setBassGainDb(float gainDb) {
        float clamped = std::clamp(gainDb, -static_cast<float>(kMaxGainDb), static_cast<float>(kMaxGainDb));
        targetBassDb_.store(clamped, std::memory_order_relaxed);
    }
    float getBassGainDb() const { return targetBassDb_.load(std::memory_order_relaxed); }

    void setTrebleGainDb(float gainDb) {
        float clamped = std::clamp(gainDb, -static_cast<float>(kMaxGainDb), static_cast<float>(kMaxGainDb));
        targetTrebleDb_.store(clamped, std::memory_order_relaxed);
    }
    float getTrebleGainDb() const { return targetTrebleDb_.load(std::memory_order_relaxed); }

    void setTiltDb(float tiltDb) {
        float clamped = std::clamp(tiltDb, -static_cast<float>(kMaxTiltDb), static_cast<float>(kMaxTiltDb));
        targetTiltDb_.store(clamped, std::memory_order_relaxed);
    }
    float getTiltDb() const { return targetTiltDb_.load(std::memory_order_relaxed); }

    void setGainsDb(float bassDb, float trebleDb, float tiltDb = 0.0f) {
        setBassGainDb(bassDb);
        setTrebleGainDb(trebleDb);
        setTiltDb(tiltDb);
    }

    bool hasActiveTone() const {
        return std::abs(targetBassDb_.load(std::memory_order_relaxed)) > 0.005f ||
               std::abs(targetTrebleDb_.load(std::memory_order_relaxed)) > 0.005f;
    }

    bool hasActiveTilt() const {
        return std::abs(targetTiltDb_.load(std::memory_order_relaxed)) > 0.005f;
    }

    // Interleaved 32-bit float processing
    void process(float* buffer, uint32_t frames, int channels = 2) {
        if (!isEnabled() || !buffer || frames == 0 || channels < 1) return;
        const int chs = std::min(channels, kMaxChannels);

        const double tgtBass = targetBassDb_.load(std::memory_order_relaxed);
        const double tgtTreble = targetTrebleDb_.load(std::memory_order_relaxed);
        const double tgtTilt = targetTiltDb_.load(std::memory_order_relaxed);

        for (uint32_t i = 0; i < frames; ++i) {
            curBassDb_   += gainSmoothAlpha_ * (tgtBass   - curBassDb_);
            curTrebleDb_ += gainSmoothAlpha_ * (tgtTreble - curTrebleDb_);
            curTiltDb_   += gainSmoothAlpha_ * (tgtTilt   - curTiltDb_);

            if (std::abs(curBassDb_   - lastCalculatedBassDb_)   > 0.02 ||
                std::abs(curTrebleDb_ - lastCalculatedTrebleDb_) > 0.02 ||
                std::abs(curTiltDb_   - lastCalculatedTiltDb_)   > 0.02) {
                updateFilters();
            }

            for (int c = 0; c < chs; ++c) {
                const size_t idx = static_cast<size_t>(i) * channels + c;
                double x = static_cast<double>(buffer[idx]);

                if (hasActiveTone_) {
                    x = bassShelf_[c].processSample(x);
                    x = trebleShelf_[c].processSample(x);
                }

                if (hasActiveTilt_) {
                    x = tiltLow_[c].processSample(x);
                    x = tiltHigh_[c].processSample(x);
                }

                buffer[idx] = static_cast<float>(x);
            }
        }
    }

    // Interleaved 64-bit double processing
    void process(double* buffer, uint32_t frames, int channels = 2) {
        if (!isEnabled() || !buffer || frames == 0 || channels < 1) return;
        const int chs = std::min(channels, kMaxChannels);

        const double tgtBass = targetBassDb_.load(std::memory_order_relaxed);
        const double tgtTreble = targetTrebleDb_.load(std::memory_order_relaxed);
        const double tgtTilt = targetTiltDb_.load(std::memory_order_relaxed);

        for (uint32_t i = 0; i < frames; ++i) {
            curBassDb_   += gainSmoothAlpha_ * (tgtBass   - curBassDb_);
            curTrebleDb_ += gainSmoothAlpha_ * (tgtTreble - curTrebleDb_);
            curTiltDb_   += gainSmoothAlpha_ * (tgtTilt   - curTiltDb_);

            if (std::abs(curBassDb_   - lastCalculatedBassDb_)   > 0.02 ||
                std::abs(curTrebleDb_ - lastCalculatedTrebleDb_) > 0.02 ||
                std::abs(curTiltDb_   - lastCalculatedTiltDb_)   > 0.02) {
                updateFilters();
            }

            for (int c = 0; c < chs; ++c) {
                const size_t idx = static_cast<size_t>(i) * channels + c;
                double x = buffer[idx];

                if (hasActiveTone_) {
                    x = bassShelf_[c].processSample(x);
                    x = trebleShelf_[c].processSample(x);
                }

                if (hasActiveTilt_) {
                    x = tiltLow_[c].processSample(x);
                    x = tiltHigh_[c].processSample(x);
                }

                buffer[idx] = x;
            }
        }
    }

private:
    void updateSmoothingAlpha() {
        constexpr double kSmoothingMs = 25.0; // 25ms click-free time constant
        gainSmoothAlpha_ = 1.0 - std::exp(-1.0 / (sampleRate_ * (kSmoothingMs * 0.001)));
    }

    void updateFilters() {
        lastCalculatedBassDb_ = curBassDb_;
        lastCalculatedTrebleDb_ = curTrebleDb_;
        lastCalculatedTiltDb_ = curTiltDb_;

        hasActiveTone_ = (std::abs(curBassDb_) > 0.005 || std::abs(curTrebleDb_) > 0.005);
        hasActiveTilt_ = (std::abs(curTiltDb_) > 0.005);

        // --- Active Baxandall Proportional-Q Scaling ---
        // Bass:
        // Nominal corner: 100 Hz, Q: 0.7071
        // Fringe corner:  35 Hz,  Q: 0.4200
        const double uBass = std::clamp(std::abs(curBassDb_) / kMaxGainDb, 0.0, 1.0);
        const double bassFc = 35.0 + (100.0 - 35.0) * std::pow(uBass, 0.6);
        const double bassQ  = 0.4200 + (0.70710678 - 0.4200) * std::pow(uBass, 0.75);

        // Treble:
        // Nominal corner: 8000 Hz,  Q: 0.7071
        // Fringe corner:  15000 Hz, Q: 0.4500
        const double uTreble = std::clamp(std::abs(curTrebleDb_) / kMaxGainDb, 0.0, 1.0);
        const double trebleFc = 15000.0 - (15000.0 - 8000.0) * std::pow(uTreble, 0.6);
        const double trebleQ  = 0.4500 + (0.70710678 - 0.4500) * std::pow(uTreble, 0.75);

        for (int c = 0; c < kMaxChannels; ++c) {
            bassShelf_[c].setParameters(CytomicSVF::FilterType::LowShelf, sampleRate_, bassFc, curBassDb_, bassQ);
            trebleShelf_[c].setParameters(CytomicSVF::FilterType::HighShelf, sampleRate_, trebleFc, curTrebleDb_, trebleQ);
        }

        // --- Quad Spectral Tilt Filter ---
        // Dual reciprocal shelves pivoted at 650 Hz (wide skirt Q = 0.42)
        const double halfTilt = curTiltDb_ * 0.5;
        constexpr double kTiltQ = 0.42;

        for (int c = 0; c < kMaxChannels; ++c) {
            tiltLow_[c].setParameters(CytomicSVF::FilterType::LowShelf, sampleRate_, kPivotFrequencyHz, -halfTilt, kTiltQ);
            tiltHigh_[c].setParameters(CytomicSVF::FilterType::HighShelf, sampleRate_, kPivotFrequencyHz, +halfTilt, kTiltQ);
        }
    }

    double sampleRate_ = 48000.0;
    std::atomic<bool> enabled_{false};

    std::atomic<float> targetBassDb_{0.0f};
    std::atomic<float> targetTrebleDb_{0.0f};
    std::atomic<float> targetTiltDb_{0.0f};

    double curBassDb_ = 0.0;
    double curTrebleDb_ = 0.0;
    double curTiltDb_ = 0.0;

    double lastCalculatedBassDb_ = -999.0;
    double lastCalculatedTrebleDb_ = -999.0;
    double lastCalculatedTiltDb_ = -999.0;

    double gainSmoothAlpha_ = 0.05;

    bool hasActiveTone_ = false;
    bool hasActiveTilt_ = false;

    CytomicSVF bassShelf_[kMaxChannels];
    CytomicSVF trebleShelf_[kMaxChannels];
    CytomicSVF tiltLow_[kMaxChannels];
    CytomicSVF tiltHigh_[kMaxChannels];
};

} // namespace sauti::dsp
