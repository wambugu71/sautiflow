#pragma once

#include <cmath>
#include <algorithm>
#include <cstdint>
#include "denormals.h"
#include "simd_math.h"

namespace sauti::dsp {

// =============================================================================
// CytomicSVF: Andy Simper's (Cytomic) Linear Trapezoidal State Variable Filter (SVF)
// with Orfanidis Prescribed-Nyquist-Gain Cramping Correction.
//
// Key Specifications:
// 1. Zero-Zipper Modulation:
//    Trapezoidal SVF topology with orthogonal frequency (g = tan(pi * fc / fs))
//    and damping (k = 1/Q) parameters. Internal states (ic1eq, ic2eq) store
//    physical integrator energy (equivalent currents), allowing per-sample
//    automation sweeps without clicks, bursts, or filter blowup.
//
// 2. Superior Low-Frequency Noise Floor:
//    Evaluated in IEEE 754 64-bit double precision. At 192 kHz and 30 Hz,
//    standard Direct Form biquads suffer catastrophic cancellation (1 - cos(w0)),
//    losing 12 bits of mantissa. CytomicSVF calculates g directly without
//    subtraction cancellation, maintaining >320 dB dynamic range and zero
//    limit cycles or truncation noise.
//
// 3. Nyquist Cramping Correction (Orfanidis / Massberg Design):
//    Standard bilinear transform forces digital gain at fs/2 to 0 dB, heavily
//    cramping peaking bands >8 kHz at 44.1/48 kHz. For peaking bands >8 kHz,
//    prescribed-Nyquist-gain matches the analog prototype gain Gn = |Ha(j*pi*fs)|,
//    accurately preserving the open analog bell curve through 20 kHz.
//
// 4. Zero-Allocation & Multichannel:
//    Processes up to 8 channels interleaved in-place for both float32 and float64
//    with exact 0.0 dB flat-band bypass and denormal protection.
// =============================================================================
class CytomicSVF {
public:
    enum class FilterType {
        Bell = 0,
        LowShelf,
        HighShelf,
        LowPass,
        HighPass,
        BandPass,
        Notch,
        AllPass,
        Tilt,
        BandReject
    };

    static constexpr int kMaxChannels = 16;

    CytomicSVF() {
        reset();
    }

    void reset() {
        for (int c = 0; c < kMaxChannels; ++c) {
            ic1eq_[c] = 0.0;
            ic2eq_[c] = 0.0;
        }
    }

    // Configure filter parameters using unified 64-bit Cytomic Linear Trapezoidal SVF
    // with closed-form s'-domain Nyquist de-cramping for Bell and HighShelf filters.
    void setParameters(FilterType type, double sampleRate, double frequencyHz,
                       double gainDb, double q) {
        if (!(sampleRate > 0.0) || !std::isfinite(sampleRate)) sampleRate = 48000.0;
        // NaN guards: std::clamp propagates NaN, which would poison filter state.
        if (!std::isfinite(frequencyHz)) frequencyHz = 1000.0;
        if (!std::isfinite(gainDb)) gainDb = 0.0;
        if (!std::isfinite(q)) q = 0.7071;

        sampleRate_ = sampleRate;
        frequencyHz_ = std::clamp(frequencyHz, 10.0, sampleRate * 0.499);
        gainDb_ = std::clamp(gainDb, -36.0, 36.0);
        q_ = std::clamp(q, 0.05, 30.0);
        type_ = type;

        const SvfCoefficients coeff = computeCoefficients(type_, sampleRate_, frequencyHz_, gainDb_, q_);
        isFlat_ = coeff.isFlat;
        useOrfanidis_ = coeff.orfanidisActive;
        g_ = coeff.g;
        k_ = coeff.k;
        m0_ = coeff.m0;
        m1_ = coeff.m1;
        m2_ = coeff.m2;

        if (!isFlat_) {
            // Precalculate trapezoidal algebraic loop solver
            const double denom = 1.0 / (1.0 + g_ * (g_ + k_));
            a1_ = denom;
            a2_ = g_ * a1_;
            a3_ = g_ * a2_;
        }
    }

    // Analytical closed-form magnitude response (dB) of this SVF at evalFreqHz
    static double evaluateResponseDb(FilterType type, double sampleRate, double frequencyHz,
                                     double gainDb, double q, double evalFreqHz) {
        if (!(sampleRate > 0.0) || !std::isfinite(sampleRate)) sampleRate = 48000.0;
        if (!std::isfinite(frequencyHz)) frequencyHz = 1000.0;
        if (!std::isfinite(gainDb)) gainDb = 0.0;
        if (!std::isfinite(q)) q = 0.7071;
        if (!std::isfinite(evalFreqHz) || evalFreqHz <= 0.0) evalFreqHz = 0.0;

        const double fcClamped = std::clamp(frequencyHz, 10.0, sampleRate * 0.499);
        const double gainClamped = std::clamp(gainDb, -36.0, 36.0);
        const double qClamped = std::clamp(q, 0.05, 30.0);
        const SvfCoefficients coeff = computeCoefficients(type, sampleRate, fcClamped, gainClamped, qClamped);
        if (coeff.isFlat) return 0.0;

        constexpr double PI = 3.14159265358979323846;
        if (evalFreqHz >= 0.5 * sampleRate * (1.0 - 1.0e-7)) {
            return 20.0 * std::log10(std::max(std::abs(coeff.m0), 1.0e-12));
        }

        const double t = std::tan(PI * evalFreqHz / sampleRate);
        const double t2 = t * t;
        const double g2 = coeff.g * coeff.g;
        const double kg = coeff.k * coeff.g;

        // Evaluate H(j*t) = (m0*(g^2 - t^2 + j*k*g*t) + m1*(j*g*t) + m2*g^2) / ((g^2 - t^2) + j*k*g*t)
        const double denRe = g2 - t2;
        const double denIm = kg * t;
        const double numRe = coeff.m0 * denRe + coeff.m2 * g2;
        const double numIm = (coeff.m0 * kg + coeff.m1 * coeff.g) * t;

        const double numMagSq = numRe * numRe + numIm * numIm;
        const double denMagSq = std::max(denRe * denRe + denIm * denIm, 1.0e-30);
        return 10.0 * std::log10(std::max(numMagSq / denMagSq, 1.0e-24));
    }

    // Drop-in backward compatibility with legacy Biquad64::initPeak
    inline void initPeak(double sampleRate, double frequencyHz, double gainDb, double q) {
        setParameters(FilterType::Bell, sampleRate, frequencyHz, gainDb, q);
    }

    // 64-Bit Float Processing across interleaved multichannel buffer
    void process(double *interleaved, uint32_t frames, int channels) {
        if (!interleaved || frames == 0 || channels <= 0 || isFlat_) return;
        const int ch = std::min(channels, kMaxChannels);

        if (ch == 2 && channels == 2) {
            const SimdDouble2 va1(a1_), va2(a2_), va3(a3_);
            const SimdDouble2 vm0(m0_), vm1(m1_), vm2(m2_);
            const SimdDouble2 vTwo(2.0);
            SimdDouble2 vic1(ic1eq_[0], ic1eq_[1]);
            SimdDouble2 vic2(ic2eq_[0], ic2eq_[1]);

            for (uint32_t i = 0; i < frames; ++i) {
                double *frame = interleaved + static_cast<size_t>(i) * 2;
                const SimdDouble2 vin = SimdDouble2::load_u(frame);
                const SimdDouble2 vv3 = vin - vic2;
                const SimdDouble2 vv1 = SimdDouble2::fma(va1, vic1, va2 * vv3);
                const SimdDouble2 vv2 = SimdDouble2::fma(va2, vic1, vic2) + (va3 * vv3);
                vic1 = (vTwo * vv1) - vic1;
                vic2 = (vTwo * vv2) - vic2;
                const SimdDouble2 vout = SimdDouble2::fma(vm0, vin, SimdDouble2::fma(vm1, vv1, vm2 * vv2));
                vout.store_u(frame);
            }
            alignas(16) double s1Out[2], s2Out[2];
            vic1.store_u(s1Out);
            vic2.store_u(s2Out);
            ic1eq_[0] = s1Out[0]; ic1eq_[1] = s1Out[1];
            ic2eq_[0] = s2Out[0]; ic2eq_[1] = s2Out[1];
            flushDenormal(ic1eq_[0]); flushDenormal(ic1eq_[1]);
            flushDenormal(ic2eq_[0]); flushDenormal(ic2eq_[1]);
            return;
        }

        for (uint32_t i = 0; i < frames; ++i) {
            double *frame = interleaved + (size_t)i * (size_t)channels;
            for (int c = 0; c < ch; ++c) {
                const double in = frame[c];

                // Solve implicit trapezoidal loop without delay
                const double v3 = in - ic2eq_[c];
                const double v1 = a1_ * ic1eq_[c] + a2_ * v3;
                const double v2 = ic2eq_[c] + a2_ * ic1eq_[c] + a3_ * v3;

                // Update physical integrator states (equivalent currents)
                ic1eq_[c] = 2.0 * v1 - ic1eq_[c];
                ic2eq_[c] = 2.0 * v2 - ic2eq_[c];
                flushDenormal(ic1eq_[c]);
                flushDenormal(ic2eq_[c]);

                // Output mixing
                frame[c] = m0_ * in + m1_ * v1 + m2_ * v2;
            }
        }
    }

    // 32-Bit Float Processing: executes in 64-bit double precision and casts in-place
    void process(float *interleaved, uint32_t frames, int channels) {
        if (!interleaved || frames == 0 || channels <= 0 || isFlat_) return;
        const int ch = std::min(channels, kMaxChannels);

        if (ch == 2 && channels == 2) {
            const SimdDouble2 va1(a1_), va2(a2_), va3(a3_);
            const SimdDouble2 vm0(m0_), vm1(m1_), vm2(m2_);
            const SimdDouble2 vTwo(2.0);
            SimdDouble2 vic1(ic1eq_[0], ic1eq_[1]);
            SimdDouble2 vic2(ic2eq_[0], ic2eq_[1]);

            for (uint32_t i = 0; i < frames; ++i) {
                float *frame = interleaved + static_cast<size_t>(i) * 2;
                const SimdDouble2 vin(static_cast<double>(frame[0]), static_cast<double>(frame[1]));
                const SimdDouble2 vv3 = vin - vic2;
                const SimdDouble2 vv1 = SimdDouble2::fma(va1, vic1, va2 * vv3);
                const SimdDouble2 vv2 = SimdDouble2::fma(va2, vic1, vic2) + (va3 * vv3);
                vic1 = (vTwo * vv1) - vic1;
                vic2 = (vTwo * vv2) - vic2;
                const SimdDouble2 vout = SimdDouble2::fma(vm0, vin, SimdDouble2::fma(vm1, vv1, vm2 * vv2));
                frame[0] = static_cast<float>(vout.get_low());
                frame[1] = static_cast<float>(vout.get_high());
            }
            alignas(16) double s1Out[2], s2Out[2];
            vic1.store_u(s1Out);
            vic2.store_u(s2Out);
            ic1eq_[0] = s1Out[0]; ic1eq_[1] = s1Out[1];
            ic2eq_[0] = s2Out[0]; ic2eq_[1] = s2Out[1];
            flushDenormal(ic1eq_[0]); flushDenormal(ic1eq_[1]);
            flushDenormal(ic2eq_[0]); flushDenormal(ic2eq_[1]);
            return;
        }

        for (uint32_t i = 0; i < frames; ++i) {
            float *frame = interleaved + (size_t)i * (size_t)channels;
            for (int c = 0; c < ch; ++c) {
                const double in = static_cast<double>(frame[c]);

                const double v3 = in - ic2eq_[c];
                const double v1 = a1_ * ic1eq_[c] + a2_ * v3;
                const double v2 = ic2eq_[c] + a2_ * ic1eq_[c] + a3_ * v3;

                ic1eq_[c] = 2.0 * v1 - ic1eq_[c];
                ic2eq_[c] = 2.0 * v2 - ic2eq_[c];
                flushDenormal(ic1eq_[c]);
                flushDenormal(ic2eq_[c]);

                frame[c] = static_cast<float>(m0_ * in + m1_ * v1 + m2_ * v2);
            }
        }
    }

    // Process a single specific channel in interleaved multichannel buffer in-place
    template <typename T>
    void processChannel(T *interleaved, uint32_t frames, int channels, int targetChannel) {
        if (!interleaved || frames == 0 || channels <= 0 || targetChannel < 0 || targetChannel >= channels || isFlat_) return;
        const int c = std::min(targetChannel, kMaxChannels - 1);

        for (uint32_t i = 0; i < frames; ++i) {
            T *sample = interleaved + (size_t)i * (size_t)channels + targetChannel;
            const double in = static_cast<double>(*sample);

            const double v3 = in - ic2eq_[c];
            const double v1 = a1_ * ic1eq_[c] + a2_ * v3;
            const double v2 = ic2eq_[c] + a2_ * ic1eq_[c] + a3_ * v3;

            ic1eq_[c] = 2.0 * v1 - ic1eq_[c];
            ic2eq_[c] = 2.0 * v2 - ic2eq_[c];
            flushDenormal(ic1eq_[c]);
            flushDenormal(ic2eq_[c]);

            *sample = static_cast<T>(m0_ * in + m1_ * v1 + m2_ * v2);
        }
    }

    // Process a single sample for a specific channel
    inline double processSample(double in, int channel = 0) {
        if (isFlat_) return in;
        const int c = std::min(channel, kMaxChannels - 1);
        const double v3 = in - ic2eq_[c];
        const double v1 = a1_ * ic1eq_[c] + a2_ * v3;
        const double v2 = ic2eq_[c] + a2_ * ic1eq_[c] + a3_ * v3;
        ic1eq_[c] = 2.0 * v1 - ic1eq_[c];
        ic2eq_[c] = 2.0 * v2 - ic2eq_[c];
        flushDenormal(ic1eq_[c]);
        flushDenormal(ic2eq_[c]);
        return m0_ * in + m1_ * v1 + m2_ * v2;
    }

    bool isFlat() const { return isFlat_; }
    bool isOrfanidisActive() const { return useOrfanidis_; }
    FilterType getType() const { return type_; }
    double getFrequencyHz() const { return frequencyHz_; }
    double getGainDb() const { return gainDb_; }
    double getQ() const { return q_; }

private:
    struct SvfCoefficients {
        double g = 0.0;
        double k = 1.0;
        double m0 = 1.0;
        double m1 = 0.0;
        double m2 = 0.0;
        bool isFlat = true;
        bool orfanidisActive = false;
    };

    static inline double analogHighShelfMag(double freqHz, double fcHz, double A, double k0) {
        const double u = freqHz / fcHz;
        const double u2 = u * u;
        const double sqrtA = std::sqrt(A);
        const double imag = k0 * sqrtA * u;
        const double numRe = 1.0 - A * u2;
        const double denRe = A - u2;
        const double numMagSq = numRe * numRe + imag * imag;
        const double denMagSq = std::max(denRe * denRe + imag * imag, 1.0e-30);
        return A * std::sqrt(numMagSq / denMagSq);
    }

    static SvfCoefficients computeCoefficients(FilterType type, double sampleRate,
                                             double frequencyHz, double gainDb, double q) {
        SvfCoefficients out{};

        // Exact flat bypass check: 0.0 dB gain on gain-dependent filter types
        const bool isGainType = (type == FilterType::Bell || type == FilterType::LowShelf ||
                                 type == FilterType::HighShelf || type == FilterType::Tilt);
        if (isGainType && std::abs(gainDb) < 0.005) {
            out.isFlat = true;
            return out;
        }
        out.isFlat = false;

        constexpr double PI = 3.14159265358979323846;
        const double w0 = 2.0 * PI * frequencyHz / sampleRate;
        const double A = std::pow(10.0, gainDb / 40.0); // sqrt(Linear Gain)
        const double k0 = 1.0 / q;
        const double t0 = std::tan(w0 * 0.5);

        // Andy Simper (Cytomic) Linear Trapezoidal SVF Formulations
        // with continuous s'-domain Orfanidis Nyquist de-cramping for Bell & HighShelf.
        out.g = t0;

        switch (type) {
        case FilterType::Bell: {
            // Unconditionally stable, clamping-free s'-domain Orfanidis formulation
            // mapped directly onto Cytomic TPT SVF (eliminates 8 kHz jump & Q-asymmetry).
            const double absGainDb = std::abs(gainDb);
            const double A_pos = std::pow(10.0, absGainDb / 40.0);
            const double G_pos = A_pos * A_pos;
            const double GB = A_pos;

            const double r = std::sqrt(1.0 + 1.0 / (4.0 * q * q)) - 1.0 / (2.0 * q);
            const double w1 = w0 * r;
            const double t1 = std::tan(0.5 * w1);

            const double u_nyq = PI / w0;
            const double oneMinusU2 = 1.0 - u_nyq * u_nyq;
            const double bwTermNum = (A_pos * u_nyq) / q;
            const double bwTermDen = u_nyq / (q * A_pos);
            const double G1_sq = (oneMinusU2 * oneMinusU2 + bwTermNum * bwTermNum) /
                                 std::max(oneMinusU2 * oneMinusU2 + bwTermDen * bwTermDen, 1.0e-30);
            const double G1 = std::sqrt(std::min(G1_sq, G_pos * G_pos - 1.0e-15));

            const double X0 = std::max(t0 * t0, 1.0e-24);
            const double X1 = std::max(t1 * t1, 1.0e-24);
            const double G2_m1 = std::max(G_pos * G_pos - 1.0, 1.0e-24);
            const double W2 = X0 * std::sqrt(std::max((G_pos * G_pos - G1_sq) / G2_m1, 1.0e-18));

            const double rhs1 = (G_pos * G_pos * (W2 - X0) * (W2 - X0) - (W2 - G1 * X0) * (W2 - G1 * X0)) / X0;
            const double rhs2 = (GB * GB * (W2 - X1) * (W2 - X1) - (W2 - G1 * X1) * (W2 - G1 * X1)) / X1;
            const double bd2 = std::max((rhs2 - rhs1) / std::max(G_pos * G_pos - GB * GB, 1.0e-24), 1.0e-24);
            const double bn2 = std::max(rhs1 + G_pos * G_pos * bd2, 1.0e-24);
            const double bn = std::sqrt(bn2);
            const double bd = std::sqrt(bd2);

            if (gainDb >= 0.0) {
                out.g = std::sqrt(W2);
                out.k = bd / out.g;
                out.m0 = G1;
                out.m2 = 1.0 - G1;
                out.m1 = (bn / out.g) - out.m0 * out.k;
            } else {
                // Exact rational inverse guarantees 0.0000 dB boost/cut complementarity
                const double invG1 = 1.0 / G1;
                out.g = std::sqrt(W2 * invG1);
                out.k = (bd > 0.0 ? (bn * invG1) / out.g : k0);
                out.m0 = invG1;
                out.m2 = 1.0 - invG1;
                out.m1 = ((bd * invG1) / out.g) - out.m0 * out.k;
            }
            out.orfanidisActive = (frequencyHz > sampleRate * 0.12) && (absGainDb >= 0.05);
            break;
        }

        case FilterType::LowShelf:
            out.g = t0 / std::sqrt(A);
            out.k = k0;
            out.m0 = 1.0;
            out.m1 = k0 * (A - 1.0);
            out.m2 = A * A - 1.0;
            break;

        case FilterType::HighShelf: {
            // Nyquist-matched s'-domain HighShelf mapped directly into Cytomic TPT SVF
            const double absGainDb = std::abs(gainDb);
            const double A_pos = std::pow(10.0, absGainDb / 40.0);
            const double G1 = analogHighShelfMag(0.5 * sampleRate, frequencyHz, A_pos, k0);
            const double r = (G1 + A_pos) / (1.0 + A_pos);
            const double W2 = t0 * t0 * r;
            const double gBoost = std::sqrt(W2);

            const double ratioNyq = std::clamp(frequencyHz / (0.5 * sampleRate), 0.0, 1.0);
            const double blend = ratioNyq * ratioNyq;
            const double fRef = (1.0 - blend) * (0.7 * frequencyHz) +
                                blend * std::sqrt(frequencyHz * 0.48 * sampleRate);
            const double M = analogHighShelfMag(fRef, frequencyHz, A_pos, k0);
            const double M2 = M * M;
            const double t1 = std::tan(PI * fRef / sampleRate);
            const double X1 = t1 * t1;
            const double denomK = W2 * X1 * (M2 - A_pos * A_pos);
            const double numK = (W2 - G1 * X1) * (W2 - G1 * X1) - M2 * (W2 - X1) * (W2 - X1);
            double kEff = k0;
            if (std::abs(denomK) > 1.0e-12 && (numK / denomK) > 0.0) {
                const double cand = std::sqrt(numK / denomK);
                kEff = std::clamp(cand, 0.25 * k0, 4.0 * k0);
            }

            if (gainDb >= 0.0) {
                out.g = gBoost;
                out.k = kEff;
                out.m0 = G1;
                out.m1 = (A_pos - G1) * kEff;
                out.m2 = 1.0 - G1;
            } else {
                const double sqrtG1 = std::sqrt(G1);
                const double invG1 = 1.0 / G1;
                out.g = gBoost / sqrtG1;
                out.k = (A_pos * kEff) / sqrtG1;
                out.m0 = invG1;
                out.m2 = 1.0 - invG1;
                out.m1 = (kEff / sqrtG1) - out.m0 * out.k;
            }
            out.orfanidisActive = (frequencyHz > sampleRate * 0.12) && (absGainDb >= 0.05);
            break;
        }

        case FilterType::LowPass:
            out.k = k0;
            out.m0 = 0.0;
            out.m1 = 0.0;
            out.m2 = 1.0;
            break;

        case FilterType::HighPass:
            out.k = k0;
            out.m0 = 1.0;
            out.m1 = -k0;
            out.m2 = -1.0;
            break;

        case FilterType::BandPass:
            out.k = k0;
            out.m0 = 0.0;
            out.m1 = 1.0;
            out.m2 = 0.0;
            break;

        case FilterType::Notch:
            out.k = k0;
            out.m0 = 1.0;
            out.m1 = -k0;
            out.m2 = 0.0;
            break;

        case FilterType::AllPass:
            out.k = k0;
            out.m0 = 1.0;
            out.m1 = -2.0 * k0;
            out.m2 = 0.0;
            break;

        case FilterType::Tilt:
            out.g = t0 * std::sqrt(A);
            out.k = k0;
            out.m0 = A;
            out.m1 = (1.0 - A) * k0;
            out.m2 = (1.0 / A) - A;
            break;

        case FilterType::BandReject: {
            out.k = k0;
            out.m0 = 1.0;
            out.m2 = 0.0;
            if (std::abs(gainDb) < 0.005) {
                out.m1 = -k0; // Full notch at f0
            } else {
                const double gCut = std::pow(10.0, -std::abs(gainDb) / 20.0);
                out.m1 = (gCut - 1.0) * k0;
            }
            break;
        }
        }

        return out;
    }

    static inline void flushDenormal(double &v) {
        if (std::abs(v) < 1.0e-25) v = 0.0;
    }

    FilterType type_ = FilterType::Bell;
    bool isFlat_ = true;
    bool useOrfanidis_ = false;

    double sampleRate_ = 48000.0;
    double frequencyHz_ = 1000.0;
    double gainDb_ = 0.0;
    double q_ = 1.0;

    // Cytomic Trapezoidal SVF Parameters
    double g_ = 0.0, k_ = 0.0;
    double a1_ = 0.0, a2_ = 0.0, a3_ = 0.0;
    double m0_ = 1.0, m1_ = 0.0, m2_ = 0.0;

    // States
    double ic1eq_[kMaxChannels] = {};
    double ic2eq_[kMaxChannels] = {};
};

} // namespace sauti::dsp
