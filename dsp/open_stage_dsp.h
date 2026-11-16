#pragma once

#include <cmath>
#include <cstdint>
#include <algorithm>
#include "denormals.h"

namespace sauti::dsp {

// =============================================================================
// OpenStageDSP: Spherical-Head Acoustic Crossfeed Processor
//
// Solves headphone fatigue and unnatural "in-head" localization by rendering
// a natural acoustic soundstage via physical diffraction physics:
//
// 1. Interaural Time Difference (ITD):
//    Models acoustic transit time around a spherical human head (15 cm width)
//    from virtual loudspeakers placed at an adjustable stereo angle (0°–90°).
//    Uses exact trigonometric Law-of-Cosines distance calculations.
//
// 2. Frequency-Dependent Acoustic Head Shadow:
//    - Contralateral (cross-ear) path: Low-shelf filter (+9 dB boost, S=0.4,
//      -12 dB post-attenuation) replicating high-frequency head occlusion.
//    - Ipsilateral (direct) path: High-shelf filter (+3 dB boost, S=0.4,
//      -3 dB post-attenuation) preserving natural treble presence.
//
// 3. Bilinear All-Pass Phase Delay:
//    Calculates the low-shelf filter's intrinsic DC group delay and compensates
//    the remaining transit delay using a 2nd-order all-pass filter.
//
// 4. Zero-Latency In-Place Stereo Processing:
//    Uses Transposed Direct Form II biquads with denormal protection,
//    de-zippered parameter smoothing, and smooth anti-pop bypass crossfading.
// =============================================================================

inline float sanitizeSample(float v) noexcept {
    return (std::fabs(v) < 1.0e-25f) ? 0.0f : v;
}

class OpenStageDSP {
public:
    // Physical acoustics constants
    static constexpr float kDefaultHeadWidthMeters   = 0.15f;    // Average adult head diameter: 15 cm
    static constexpr float kDefaultSpeakerDistanceM  = 1.00f;    // Nearfield studio monitor distance: 1.0 m
    static constexpr float kSpeedOfSoundMps          = 340.0f;   // Speed of sound in air (m/s)

    // Parameter boundaries
    static constexpr float kMinAngleDegrees          = 0.0f;     // Mono forward center
    static constexpr float kMaxAngleDegrees          = 90.0f;    // Extreme wide lateral
    static constexpr float kDefaultAngleDegrees      = 60.0f;    // Standard equilateral triangle studio placement

    static constexpr float kMinGainDb                = -12.0f;
    static constexpr float kMaxGainDb                = 12.0f;
    static constexpr float kDefaultGainDb            = -1.0f;    // Volume compensation for crossfeed summing

    OpenStageDSP() {
        setSampleRate(48000.0);
        reset();
    }

    void setSampleRate(double rate) {
        if (rate <= 0.0) rate = 48000.0;
        if (initialized_ && std::abs(sampleRate_ - rate) < 0.1) return;

        sampleRate_ = rate;
        // 200 ms smooth transition for bypass (anti-pop)
        bypassFadeRate_ = static_cast<float>(1.0 / (0.200 * sampleRate_));
        // 25 ms smooth coefficient for real-time slider updates (de-zippering)
        paramSmoothAlpha_ = static_cast<float>(1.0 - std::exp(-1.0 / (0.025 * sampleRate_)));

        updateFilters(currentAngle_);
        initialized_ = true;
    }

    void setEnabled(bool enabled) {
        enabled_ = enabled;
        targetWetLevel_ = enabled ? 1.0f : 0.0f;
    }

    bool isEnabled() const { return enabled_; }

    // Virtual stereo speaker angle in degrees (0° - 90°, default 60°)
    void setAngle(float degrees) {
        targetAngle_ = std::clamp(degrees, kMinAngleDegrees, kMaxAngleDegrees);
    }

    float getAngle() const { return targetAngle_; }

    // Output compensation gain in dB (-12 dB to +12 dB, default -1 dB)
    void setGainDb(float gainDb) {
        targetGainDb_ = std::clamp(gainDb, kMinGainDb, kMaxGainDb);
        targetGainLinear_ = std::pow(10.0f, targetGainDb_ / 20.0f);
    }

    float getGainDb() const { return targetGainDb_; }

    // Overall crossfeed wet/dry mix [0.0 - 1.0]
    void setMix(float mix) {
        targetMix_ = std::clamp(mix, 0.0f, 1.0f);
    }

    float getMix() const { return targetMix_; }

    // Immediately sets the wet/dry mix without a secondary smoothing lag
    void setMixImmediate(float mix) noexcept {
        const float clamped = std::clamp(mix, 0.0f, 1.0f);
        targetMix_ = clamped;
        currentMix_ = clamped;
    }

    // Current physical Interaural Time Difference in seconds
    double getItdSeconds() const noexcept {
        return static_cast<double>(computeITD(currentAngle_));
    }

    // Current physical Interaural Time Difference in milliseconds
    float getItdMs() const noexcept {
        return computeITD(currentAngle_) * 1000.0f;
    }

    // Reset internal biquad histories and snap smoothed parameters
    void reset() {
        for (int ch = 0; ch < 2; ++ch) {
            highShelf_[ch].reset();
            lowShelf_[ch].reset();
            allPass_[ch].reset();
        }

        currentAngle_ = targetAngle_;
        currentGainDb_ = targetGainDb_;
        currentGainLinear_ = targetGainLinear_;
        currentMix_ = targetMix_;
        currentWetLevel_ = targetWetLevel_;
        sampleCounter_ = 0;

        if (sampleRate_ > 0.0) {
            updateFilters(currentAngle_);
        }
    }

    // Process interleaved stereo 32-bit float or 64-bit double audio in-place
    template <typename SampleT>
    void process(SampleT* interleavedStereo, uint32_t frames, int channels = 2) {
        if (!interleavedStereo || frames == 0 || channels < 2) return;

        // Fast-path bypass check when completely faded out
        if (!enabled_ && currentWetLevel_ < 0.0001f) {
            currentWetLevel_ = 0.0f;
            return;
        }

        ScopedDenormalsDisable denormalsScope;

        for (uint32_t i = 0; i < frames; ++i) {
            const size_t baseIdx = static_cast<size_t>(i) * static_cast<size_t>(channels);
            const float inL = static_cast<float>(interleavedStereo[baseIdx]);
            const float inR = static_cast<float>(interleavedStereo[baseIdx + 1]);

            float outL = inL;
            float outR = inR;
            processSample(inL, inR, outL, outR);

            interleavedStereo[baseIdx] = static_cast<SampleT>(outL);
            interleavedStereo[baseIdx + 1] = static_cast<SampleT>(outR);
        }
    }

    // Process a single stereo sample pair in-place or out-of-place, advancing smoothers
    inline void processSample(float inL, float inR, float& outL, float& outR) noexcept {
        // 1. Parameter smoothing (de-zippering)
        currentMix_ += paramSmoothAlpha_ * (targetMix_ - currentMix_);
        currentGainLinear_ += paramSmoothAlpha_ * (targetGainLinear_ - currentGainLinear_);

        // Block-interpolate crossfeed angle updates every 32 samples instead of per-sample
        if ((sampleCounter_++ & 31u) == 0u && std::abs(targetAngle_ - currentAngle_) > 0.02f) {
            currentAngle_ += std::min(1.0f, paramSmoothAlpha_ * 32.0f) * (targetAngle_ - currentAngle_);
            updateFilters(currentAngle_);
        }

        // 2. Anti-pop click-free bypass ramping
        if (currentWetLevel_ < targetWetLevel_) {
            currentWetLevel_ = std::min(targetWetLevel_, currentWetLevel_ + bypassFadeRate_);
        } else if (currentWetLevel_ > targetWetLevel_) {
            currentWetLevel_ = std::max(targetWetLevel_, currentWetLevel_ - bypassFadeRate_);
        }

        const float directL = highShelf_[0].process(inL);
        const float directR = highShelf_[1].process(inR);

        const float crossL = allPass_[0].process(lowShelf_[0].process(inR));
        const float crossR = allPass_[1].process(lowShelf_[1].process(inL));

        const float wetL = (directL + crossL) * currentGainLinear_;
        const float wetR = (directR + crossR) * currentGainLinear_;

        const float effectiveWet = currentWetLevel_ * currentMix_;
        const float effectiveDry = 1.0f - effectiveWet;

        outL = sanitizeSample(inL * effectiveDry + wetL * effectiveWet);
        outR = sanitizeSample(inR * effectiveDry + wetR * effectiveWet);
    }

private:
    // -------------------------------------------------------------------------
    // Biquad Transposed Direct Form II
    // Canonical 2-state storage with optimal numerical stability and low noise
    // -------------------------------------------------------------------------
    struct BiquadCoeffs {
        double b0 = 1.0, b1 = 0.0, b2 = 0.0;
        double a1 = 0.0, a2 = 0.0;
    };

    struct Biquad {
        BiquadCoeffs c;
        double s1 = 0.0;
        double s2 = 0.0;

        inline float process(float x) noexcept {
            const double xd = static_cast<double>(x);
            const double y = xd * c.b0 + s1;
            s1 = xd * c.b1 - y * c.a1 + s2;
            s2 = xd * c.b2 - y * c.a2;
            // Denormal clamping on internal memory
            if (std::fabs(s1) < 1.0e-25) s1 = 0.0;
            if (std::fabs(s2) < 1.0e-25) s2 = 0.0;
            return static_cast<float>(y);
        }

        void reset() noexcept {
            s1 = 0.0;
            s2 = 0.0;
        }
    };

    // -------------------------------------------------------------------------
    // Acoustic Physics Calculations
    // -------------------------------------------------------------------------

    // Computes Interaural Time Difference (seconds) using spherical head geometry
    static double computeITD(double angleDegrees) noexcept {
        constexpr double kDegToRad = 3.14159265358979323846 / 180.0;
        constexpr double kInvC = 1.0 / static_cast<double>(kSpeedOfSoundMps);
        constexpr double w = static_cast<double>(kDefaultHeadWidthMeters);
        constexpr double d = static_cast<double>(kDefaultSpeakerDistanceM);

        const double halfTheta = (angleDegrees * 0.5) * kDegToRad;
        const double sinHalfTheta = std::sin(halfTheta);

        // Law of Cosines distance from virtual speaker to left vs right ear
        const double dFarSq  = d * d + (w * w * 0.25) + (w * d * sinHalfTheta);
        const double dNearSq = d * d + (w * w * 0.25) - (w * d * sinHalfTheta);

        const double dFar  = std::sqrt(std::max(0.0, dFarSq));
        const double dNear = std::sqrt(std::max(0.0, dNearSq));

        return (dFar - dNear) * kInvC;
    }

    // Calculates the low-frequency DC phase/group delay (seconds) of a biquad
    static double computeBiquadDcPhaseDelay(const BiquadCoeffs& c, double fs) noexcept {
        const double bSum = c.b0 + c.b1 + c.b2;
        const double aSum = 1.0 + c.a1 + c.a2;

        if (std::abs(bSum) < 1.0e-9 || std::abs(aSum) < 1.0e-9 || fs <= 0.0) {
            return 0.0;
        }

        const double numWeighted = c.b1 + 2.0 * c.b2;
        const double denWeighted = c.a1 + 2.0 * c.a2;
        return ((numWeighted / bSum) - (denWeighted / aSum)) / fs;
    }

    // Normalizes b0, b1, b2, a1, a2 by dividing through by a0
    static BiquadCoeffs normalizeCoeffs(double b0, double b1, double b2,
                                        double a0, double a1, double a2) noexcept {
        const double invA0 = (std::abs(a0) > 1.0e-18) ? (1.0 / a0) : 1.0;
        return { b0 * invA0, b1 * invA0, b2 * invA0, a1 * invA0, a2 * invA0 };
    }

    // RBJ Low Shelf Biquad Filter with post-gain scaling (64-bit internal precision)
    static BiquadCoeffs makeLowShelf(double fs, double fc, double shelfGainDb,
                                     double slope, double postGainDb) noexcept {
        constexpr double kTwoPi = 6.28318530717958647692;
        constexpr double kPi = 3.14159265358979323846;
        const double A = std::pow(10.0, shelfGainDb / 40.0);
        const double omega = std::clamp(kTwoPi * fc / fs, 0.0001, kPi * 0.95);
        const double cosW = std::cos(omega);
        const double sinW = std::sin(omega);

        // RBJ slope parameterization: 1/Q = sqrt((A + 1/A)*(1/S - 1) + 2)
        const double invQ = std::sqrt(std::max(0.0, (A + 1.0 / A) * (1.0 / slope - 1.0) + 2.0));
        const double alpha = sinW * 0.5 * invQ;
        const double twoSqrtAAlpha = 2.0 * std::sqrt(A) * alpha;

        const double postGainLinear = std::pow(10.0, postGainDb / 20.0);
        const double plus  = A + 1.0;
        const double minus = A - 1.0;
        const double plusCos  = plus * cosW;
        const double minusCos = minus * cosW;

        const double b0 = A * (plus - minusCos + twoSqrtAAlpha) * postGainLinear;
        const double b1 = 2.0 * A * (minus - plusCos) * postGainLinear;
        const double b2 = A * (plus - minusCos - twoSqrtAAlpha) * postGainLinear;

        const double a0 = plus + minusCos + twoSqrtAAlpha;
        const double a1 = -2.0 * (minus + plusCos);
        const double a2 = plus + minusCos - twoSqrtAAlpha;

        return normalizeCoeffs(b0, b1, b2, a0, a1, a2);
    }

    // RBJ High Shelf Biquad Filter with post-gain scaling (64-bit internal precision)
    static BiquadCoeffs makeHighShelf(double fs, double fc, double shelfGainDb,
                                      double slope, double postGainDb) noexcept {
        constexpr double kTwoPi = 6.28318530717958647692;
        constexpr double kPi = 3.14159265358979323846;
        const double A = std::pow(10.0, shelfGainDb / 40.0);
        const double omega = std::clamp(kTwoPi * fc / fs, 0.0001, kPi * 0.95);
        const double cosW = std::cos(omega);
        const double sinW = std::sin(omega);

        const double invQ = std::sqrt(std::max(0.0, (A + 1.0 / A) * (1.0 / slope - 1.0) + 2.0));
        const double alpha = sinW * 0.5 * invQ;
        const double twoSqrtAAlpha = 2.0 * std::sqrt(A) * alpha;

        const double postGainLinear = std::pow(10.0, postGainDb / 20.0);
        const double plus  = A + 1.0;
        const double minus = A - 1.0;
        const double plusCos  = plus * cosW;
        const double minusCos = minus * cosW;

        const double b0 = A * (plus + minusCos + twoSqrtAAlpha) * postGainLinear;
        const double b1 = -2.0 * A * (minus + plusCos) * postGainLinear;
        const double b2 = A * (plus + minusCos - twoSqrtAAlpha) * postGainLinear;

        const double a0 = plus - minusCos + twoSqrtAAlpha;
        const double a1 = 2.0 * (minus - plusCos);
        const double a2 = plus - minusCos - twoSqrtAAlpha;

        return normalizeCoeffs(b0, b1, b2, a0, a1, a2);
    }

    // 2nd-Order Bilinear All-Pass Filter for phase delay (64-bit internal precision)
    // Cascades two identical 1st-order bilinear allpass sections, total delay = delaySeconds
    static BiquadCoeffs makeAllPass(double fs, double delaySeconds) noexcept {
        if (delaySeconds <= 0.0 || fs <= 0.0) {
            return { 1.0, 0.0, 0.0, 0.0, 0.0 };
        }

        const double k = delaySeconds * 0.5 * fs;
        const double v = (1.0 - k) / (1.0 + k);

        // H_ap(z) = ((v + z^-1)/(1 + v*z^-1))^2 = (v^2 + 2v*z^-1 + z^-2) / (1 + 2v*z^-1 + v^2*z^-2)
        return normalizeCoeffs(v * v, 2.0 * v, 1.0, 1.0, 2.0 * v, v * v);
    }

    // Recalculates all filter coefficients based on current sample rate and speaker angle
    void updateFilters(float angleDegrees) noexcept {
        if (sampleRate_ <= 0.0) return;

        const double fs = sampleRate_;
        const double itd = computeITD(static_cast<double>(angleDegrees));

        // Head shadow acoustic cutoff frequencies
        constexpr double kShelfSlope = 0.4;
        constexpr double kLowGainDb  = 9.0;
        constexpr double kHighGainDb = 3.0;

        const double lowCutoff = std::min(0.5 / std::max(itd, 1.0e-5), 2000.0);
        const double highCutoff = lowCutoff / 3.0;

        // Ipsilateral direct treble enhancement
        const BiquadCoeffs hsCoeffs = makeHighShelf(fs, highCutoff, kHighGainDb, kShelfSlope, -kHighGainDb);

        // Contralateral head shadow low-shelf
        const BiquadCoeffs lsCoeffs = makeLowShelf(fs, lowCutoff, kLowGainDb, kShelfSlope, -(kHighGainDb + kLowGainDb));

        // Group delay compensation through 2nd-order allpass
        const double shelfDelay = computeBiquadDcPhaseDelay(lsCoeffs, fs);
        const double residualDelay = std::max(0.0, itd - shelfDelay);
        const BiquadCoeffs apCoeffs = makeAllPass(fs, residualDelay);

        for (int ch = 0; ch < 2; ++ch) {
            highShelf_[ch].c = hsCoeffs;
            lowShelf_[ch].c  = lsCoeffs;
            allPass_[ch].c   = apCoeffs;
        }
    }

    // Engine state
    double sampleRate_        = 48000.0;
    bool initialized_         = false;
    bool enabled_             = true;

    float targetAngle_        = kDefaultAngleDegrees;
    float currentAngle_       = kDefaultAngleDegrees;

    float targetGainDb_       = kDefaultGainDb;
    float currentGainDb_      = kDefaultGainDb;
    float targetGainLinear_   = 0.8912509f; // 10^(-1/20)
    float currentGainLinear_  = 0.8912509f;

    float targetMix_          = 1.0f;
    float currentMix_         = 1.0f;

    float targetWetLevel_     = 1.0f;
    float currentWetLevel_    = 1.0f;
    float bypassFadeRate_     = 0.0001f;
    float paramSmoothAlpha_   = 0.001f;
    uint32_t sampleCounter_   = 0;

    // Direct Form II biquad filter pairs (L, R)
    Biquad highShelf_[2];
    Biquad lowShelf_[2];
    Biquad allPass_[2];
};

} // namespace sauti::dsp
