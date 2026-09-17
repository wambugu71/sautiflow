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

        if (sampleRate_ > 0.0) {
            updateFilters(currentAngle_);
        }
    }

    // Process interleaved stereo 32-bit float audio in-place
    void process(float* interleavedStereo, uint32_t frames, int channels = 2) {
        if (!interleavedStereo || frames == 0 || channels < 2) return;

        // Fast-path bypass check when completely faded out
        if (!enabled_ && currentWetLevel_ < 0.0001f) {
            currentWetLevel_ = 0.0f;
            return;
        }

        ScopedDenormalsDisable denormalsScope;

        for (uint32_t i = 0; i < frames; ++i) {
            // 1. Parameter smoothing (de-zippering)
            currentMix_ += paramSmoothAlpha_ * (targetMix_ - currentMix_);
            currentGainLinear_ += paramSmoothAlpha_ * (targetGainLinear_ - currentGainLinear_);

            if (std::abs(targetAngle_ - currentAngle_) > 0.02f) {
                currentAngle_ += paramSmoothAlpha_ * (targetAngle_ - currentAngle_);
                updateFilters(currentAngle_);
            }

            // 2. Anti-pop click-free bypass ramping
            if (currentWetLevel_ < targetWetLevel_) {
                currentWetLevel_ = std::min(targetWetLevel_, currentWetLevel_ + bypassFadeRate_);
            } else if (currentWetLevel_ > targetWetLevel_) {
                currentWetLevel_ = std::max(targetWetLevel_, currentWetLevel_ - bypassFadeRate_);
            }

            const size_t baseIdx = static_cast<size_t>(i) * static_cast<size_t>(channels);
            const float inL = interleavedStereo[baseIdx];
            const float inR = interleavedStereo[baseIdx + 1];

            processSample(inL, inR, interleavedStereo[baseIdx], interleavedStereo[baseIdx + 1]);
        }
    }

    // Process a single stereo sample pair in-place or out-of-place
    inline void processSample(float inL, float inR, float& outL, float& outR) noexcept {
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
        float b0 = 1.0f, b1 = 0.0f, b2 = 0.0f;
        float a1 = 0.0f, a2 = 0.0f;
    };

    struct Biquad {
        BiquadCoeffs c;
        float s1 = 0.0f;
        float s2 = 0.0f;

        inline float process(float x) noexcept {
            const float y = x * c.b0 + s1;
            s1 = x * c.b1 - y * c.a1 + s2;
            s2 = x * c.b2 - y * c.a2;
            // Denormal clamping on internal memory
            if (std::fabs(s1) < 1.0e-25f) s1 = 0.0f;
            if (std::fabs(s2) < 1.0e-25f) s2 = 0.0f;
            return y;
        }

        void reset() noexcept {
            s1 = 0.0f;
            s2 = 0.0f;
        }
    };

    // -------------------------------------------------------------------------
    // Acoustic Physics Calculations
    // -------------------------------------------------------------------------

    // Computes Interaural Time Difference (seconds) using spherical head geometry
    static float computeITD(float angleDegrees) noexcept {
        constexpr float kDegToRad = 3.14159265358979323846f / 180.0f;
        constexpr float kInvC = 1.0f / kSpeedOfSoundMps;
        constexpr float w = kDefaultHeadWidthMeters;
        constexpr float d = kDefaultSpeakerDistanceM;

        const float halfTheta = (angleDegrees * 0.5f) * kDegToRad;
        const float sinHalfTheta = std::sin(halfTheta);

        // Law of Cosines distance from virtual speaker to left vs right ear
        const float dFarSq  = d * d + (w * w * 0.25f) + (w * d * sinHalfTheta);
        const float dNearSq = d * d + (w * w * 0.25f) - (w * d * sinHalfTheta);

        const float dFar  = std::sqrt(std::max(0.0f, dFarSq));
        const float dNear = std::sqrt(std::max(0.0f, dNearSq));

        return (dFar - dNear) * kInvC;
    }

    // Calculates the low-frequency DC phase/group delay (seconds) of a biquad
    static float computeBiquadDcPhaseDelay(const BiquadCoeffs& c, float fs) noexcept {
        const float bSum = c.b0 + c.b1 + c.b2;
        const float aSum = 1.0f + c.a1 + c.a2;

        if (std::abs(bSum) < 1.0e-6f || std::abs(aSum) < 1.0e-6f || fs <= 0.0f) {
            return 0.0f;
        }

        const float numWeighted = c.b1 + 2.0f * c.b2;
        const float denWeighted = c.a1 + 2.0f * c.a2;
        return ((numWeighted / bSum) - (denWeighted / aSum)) / fs;
    }

    // Normalizes b0, b1, b2, a1, a2 by dividing through by a0
    static BiquadCoeffs normalizeCoeffs(float b0, float b1, float b2,
                                        float a0, float a1, float a2) noexcept {
        const float invA0 = (std::abs(a0) > 1.0e-12f) ? (1.0f / a0) : 1.0f;
        return { b0 * invA0, b1 * invA0, b2 * invA0, a1 * invA0, a2 * invA0 };
    }

    // RBJ Low Shelf Biquad Filter with post-gain scaling
    static BiquadCoeffs makeLowShelf(float fs, float fc, float shelfGainDb,
                                     float slope, float postGainDb) noexcept {
        constexpr float kTwoPi = 6.28318530717958647692f;
        const float A = std::pow(10.0f, shelfGainDb / 40.0f);
        const float omega = std::clamp(kTwoPi * fc / fs, 0.0001f, 3.14159f * 0.95f);
        const float cosW = std::cos(omega);
        const float sinW = std::sin(omega);

        // RBJ slope parameterization: 1/Q = sqrt((A + 1/A)*(1/S - 1) + 2)
        const float invQ = std::sqrt(std::max(0.0f, (A + 1.0f / A) * (1.0f / slope - 1.0f) + 2.0f));
        const float alpha = sinW * 0.5f * invQ;
        const float twoSqrtAAlpha = 2.0f * std::sqrt(A) * alpha;

        const float postGainLinear = std::pow(10.0f, postGainDb / 20.0f);
        const float plus  = A + 1.0f;
        const float minus = A - 1.0f;
        const float plusCos  = plus * cosW;
        const float minusCos = minus * cosW;

        const float b0 = A * (plus - minusCos + twoSqrtAAlpha) * postGainLinear;
        const float b1 = 2.0f * A * (minus - plusCos) * postGainLinear;
        const float b2 = A * (plus - minusCos - twoSqrtAAlpha) * postGainLinear;

        const float a0 = plus + minusCos + twoSqrtAAlpha;
        const float a1 = -2.0f * (minus + plusCos);
        const float a2 = plus + minusCos - twoSqrtAAlpha;

        return normalizeCoeffs(b0, b1, b2, a0, a1, a2);
    }

    // RBJ High Shelf Biquad Filter with post-gain scaling
    static BiquadCoeffs makeHighShelf(float fs, float fc, float shelfGainDb,
                                      float slope, float postGainDb) noexcept {
        constexpr float kTwoPi = 6.28318530717958647692f;
        const float A = std::pow(10.0f, shelfGainDb / 40.0f);
        const float omega = std::clamp(kTwoPi * fc / fs, 0.0001f, 3.14159f * 0.95f);
        const float cosW = std::cos(omega);
        const float sinW = std::sin(omega);

        const float invQ = std::sqrt(std::max(0.0f, (A + 1.0f / A) * (1.0f / slope - 1.0f) + 2.0f));
        const float alpha = sinW * 0.5f * invQ;
        const float twoSqrtAAlpha = 2.0f * std::sqrt(A) * alpha;

        const float postGainLinear = std::pow(10.0f, postGainDb / 20.0f);
        const float plus  = A + 1.0f;
        const float minus = A - 1.0f;
        const float plusCos  = plus * cosW;
        const float minusCos = minus * cosW;

        const float b0 = A * (plus + minusCos + twoSqrtAAlpha) * postGainLinear;
        const float b1 = -2.0f * A * (minus + plusCos) * postGainLinear;
        const float b2 = A * (plus + minusCos - twoSqrtAAlpha) * postGainLinear;

        const float a0 = plus - minusCos + twoSqrtAAlpha;
        const float a1 = 2.0f * (minus - plusCos);
        const float a2 = plus - minusCos - twoSqrtAAlpha;

        return normalizeCoeffs(b0, b1, b2, a0, a1, a2);
    }

    // 2nd-Order Bilinear All-Pass Filter for phase delay
    // Cascades two identical 1st-order bilinear allpass sections, total delay = delaySeconds
    static BiquadCoeffs makeAllPass(float fs, float delaySeconds) noexcept {
        if (delaySeconds <= 0.0f || fs <= 0.0f) {
            return { 1.0f, 0.0f, 0.0f, 0.0f, 0.0f };
        }

        const float k = delaySeconds * 0.5f * fs;
        const float v = (1.0f - k) / (1.0f + k);

        // H_ap(z) = ((v + z^-1)/(1 + v*z^-1))^2 = (v^2 + 2v*z^-1 + z^-2) / (1 + 2v*z^-1 + v^2*z^-2)
        return normalizeCoeffs(v * v, 2.0f * v, 1.0f, 1.0f, 2.0f * v, v * v);
    }

    // Recalculates all filter coefficients based on current sample rate and speaker angle
    void updateFilters(float angleDegrees) noexcept {
        if (sampleRate_ <= 0.0) return;

        const float fs = static_cast<float>(sampleRate_);
        const float itd = computeITD(angleDegrees);

        // Head shadow acoustic cutoff frequencies
        constexpr float kShelfSlope = 0.4f;
        constexpr float kLowGainDb  = 9.0f;
        constexpr float kHighGainDb = 3.0f;

        const float lowCutoff = std::min(0.5f / std::max(itd, 1.0e-5f), 2000.0f);
        const float highCutoff = lowCutoff / 3.0f;

        // Ipsilateral direct treble enhancement
        const BiquadCoeffs hsCoeffs = makeHighShelf(fs, highCutoff, kHighGainDb, kShelfSlope, -kHighGainDb);

        // Contralateral head shadow low-shelf
        const BiquadCoeffs lsCoeffs = makeLowShelf(fs, lowCutoff, kLowGainDb, kShelfSlope, -(kHighGainDb + kLowGainDb));

        // Group delay compensation through 2nd-order allpass
        const float shelfDelay = computeBiquadDcPhaseDelay(lsCoeffs, fs);
        const float residualDelay = std::max(0.0f, itd - shelfDelay);
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

    // Direct Form II biquad filter pairs (L, R)
    Biquad highShelf_[2];
    Biquad lowShelf_[2];
    Biquad allPass_[2];
};

} // namespace sauti::dsp
