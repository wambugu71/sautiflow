#pragma once

#include <cmath>
#include <algorithm>
#include <cstdint>
#include <vector>
#include <cstring>
#include "cytomic_svf_dsp.h"
#include "denormals.h"

namespace sauti::dsp {

// =============================================================================
// GraphicEqDSP: Audiophile Matrix-Compensated & Parallel Graphic Equalizer
//
// Solves the classical "Cascaded Biquad Ripple" and "Skirt Gain Accumulation"
// problem documented by Rämö & Välimäki (IEEE TASLP 2014, AES 2013) and Orfanidis:
//
// 1. Interaction Matrix Decoupling (B^-1 * g_target):
//    Computes an M x M leakage matrix B where B[i][j] measures how much band j
//    leaks into band i's center frequency. When sliders move, solves the linear
//    system:
//        g_optimized = B^-1 * g_target
//    This pulls back individual filter gains so the composite frequency curve
//    passes exactly through the user's slider positions with minimal inter-band ripple.
//
// 2. Topology Selection:
//    - MatrixCompensatedCascade (Default): Zero-ripple cascaded Cytomic SVFs with
//      Orfanidis Nyquist de-cramping for high frequency bands.
//    - SymmetricParallel: Constant-Q parallel filter bank eliminating serial phase
//      delay accumulation for maximum transient transparency.
//    - LegacyCascade: Direct uncompensated biquad cascade for A/B comparison.
//
// 3. Auto-Q Optimization:
//    Automatically computes ideal Constant-Q values for 10-band (1-octave, Q=1.414),
//    16-band (2/3-octave, Q=2.14), 31/32-band (1/3-octave, Q=4.32), or arbitrary
//    logarithmically-spaced user frequency curves.
//
// 4. Performance & Safety:
//    - Exact 0.0 dB flat-band bypass (bit-exact unity passthrough, 0 CPU).
//    - Zero runtime allocation during audio processing.
//    - IEEE 754 64-bit double precision filter state calculation.
//    - Seamless float32 and float64 multichannel processing up to 8 channels.
// =============================================================================
class GraphicEqDSP {
public:
    static constexpr int kMaxBands = 32;
    static constexpr int kMaxChannels = CytomicSVF::kMaxChannels;

    enum class EqTopology {
        MatrixCompensatedCascade = 0,
        SymmetricParallel = 1,
        LegacyCascade = 2
    };

    GraphicEqDSP() {
        reset();
    }

    void init(int band_count, const float* frequencies, const float* q_factors = nullptr,
              double sample_rate = 48000.0, EqTopology topology = EqTopology::MatrixCompensatedCascade) {
        if (band_count <= 0) {
            band_count_ = 0;
            return;
        }

        band_count_ = std::clamp(band_count, 1, kMaxBands);
        sample_rate_ = (sample_rate > 0.0) ? sample_rate : 48000.0;
        topology_ = topology;

        frequencies_.resize(band_count_);
        q_factors_.resize(band_count_);
        target_gains_db_.assign(band_count_, 0.0);
        optimized_gains_db_.assign(band_count_, 0.0);
        parallel_scales_.assign(band_count_, 0.0);
        filters_.resize(band_count_);

        for (int i = 0; i < band_count_; ++i) {
            frequencies_[i] = (frequencies && frequencies[i] > 10.0f)
                                  ? (double)frequencies[i]
                                  : (20.0 * std::pow(1000.0, (double)i / std::max(1, band_count_ - 1)));
            frequencies_[i] = std::clamp(frequencies_[i], 10.0, sample_rate_ * 0.499);
        }

        if (q_factors) {
            for (int i = 0; i < band_count_; ++i) {
                q_factors_[i] = std::clamp((double)q_factors[i], 0.1, 30.0);
            }
        } else {
            // Compute auto-Q based on adjacent band spacing (logarithmic bandwidth)
            calculateAutoQ();
        }

        computeInteractionMatrix();
        updateFilterParameters();
        reset();
    }

    void setSampleRate(double sample_rate) {
        if (sample_rate <= 0.0 || std::abs(sample_rate_ - sample_rate) < 0.1) return;
        sample_rate_ = sample_rate;
        if (band_count_ > 0) {
            computeInteractionMatrix();
            updateFilterParameters();
        }
    }

    double getSampleRate() const { return sample_rate_; }

    void setTopology(EqTopology topology) {
        if (topology_ == topology) return;
        topology_ = topology;
        updateFilterParameters();
    }

    EqTopology getTopology() const { return topology_; }

    void setBandGain(int band_index, double gain_db) {
        if (band_index < 0 || band_index >= band_count_) return;
        target_gains_db_[band_index] = std::clamp(gain_db, -24.0, 24.0);
        updateFilterParameters();
    }

    double getBandGain(int band_index) const {
        if (band_index < 0 || band_index >= band_count_) return 0.0;
        return target_gains_db_[band_index];
    }

    double getOptimizedGain(int band_index) const {
        if (band_index < 0 || band_index >= band_count_) return 0.0;
        return optimized_gains_db_[band_index];
    }

    void setAllGains(const float* gains_db) {
        if (!gains_db || band_count_ <= 0) return;
        for (int i = 0; i < band_count_; ++i) {
            target_gains_db_[i] = std::clamp((double)gains_db[i], -24.0, 24.0);
        }
        updateFilterParameters();
    }

    void setAllGains(const double* gains_db) {
        if (!gains_db || band_count_ <= 0) return;
        for (int i = 0; i < band_count_; ++i) {
            target_gains_db_[i] = std::clamp(gains_db[i], -24.0, 24.0);
        }
        updateFilterParameters();
    }

    int getBandCount() const { return band_count_; }

    double getFrequency(int band_index) const {
        if (band_index < 0 || band_index >= band_count_) return 0.0;
        return frequencies_[band_index];
    }

    double getQ(int band_index) const {
        if (band_index < 0 || band_index >= band_count_) return 1.0;
        return q_factors_[band_index];
    }

    bool isFlat() const { return isFlat_; }

    void reset() {
        for (auto& f : filters_) f.reset();
        for (int c = 0; c < kMaxChannels; ++c) {
            parallel_scratch_[c] = 0.0;
        }
    }

    // Process interleaved float32 audio
    void process(float* frames, size_t frame_count, int channels) {
        if (!frames || frame_count == 0 || channels <= 0 || band_count_ <= 0 || isFlat_) {
            return;
        }
        const int ch = std::min(channels, kMaxChannels);

        if (topology_ == EqTopology::SymmetricParallel) {
            processParallel(frames, frame_count, ch);
        } else {
            processCascade(frames, frame_count, ch);
        }
    }

    // Process interleaved float64 audio (true double-precision engine)
    void process(double* frames, size_t frame_count, int channels) {
        if (!frames || frame_count == 0 || channels <= 0 || band_count_ <= 0 || isFlat_) {
            return;
        }
        const int ch = std::min(channels, kMaxChannels);

        if (topology_ == EqTopology::SymmetricParallel) {
            processParallel(frames, frame_count, ch);
        } else {
            processCascade(frames, frame_count, ch);
        }
    }

    // Process a single channel in interleaved float32 audio
    void processChannel(float* frames, size_t frame_count, int channels, int channel_index) {
        if (!frames || frame_count == 0 || channels <= 0 || channel_index < 0 || channel_index >= channels || band_count_ <= 0 || isFlat_) {
            return;
        }

        if (topology_ == EqTopology::SymmetricParallel) {
            processParallelChannel(frames, frame_count, channels, channel_index);
        } else {
            processCascadeChannel(frames, frame_count, channels, channel_index);
        }
    }

    // Process a single channel in interleaved float64 audio
    void processChannel(double* frames, size_t frame_count, int channels, int channel_index) {
        if (!frames || frame_count == 0 || channels <= 0 || channel_index < 0 || channel_index >= channels || band_count_ <= 0 || isFlat_) {
            return;
        }

        if (topology_ == EqTopology::SymmetricParallel) {
            processParallelChannel(frames, frame_count, channels, channel_index);
        } else {
            processCascadeChannel(frames, frame_count, channels, channel_index);
        }
    }

    // Analytical evaluation of composite response in dB at any arbitrary test frequency
    double evaluateCompositeResponseDb(double eval_freq_hz) const {
        if (band_count_ <= 0) return 0.0;
        if (isFlat_) return 0.0;

        if (topology_ == EqTopology::SymmetricParallel) {
            double sum_re = 1.0;
            double sum_im = 0.0;
            for (int j = 0; j < band_count_; ++j) {
                const double scale = parallel_scales_[j];
                if (std::abs(scale) < 1e-12) continue;
                double bp_re = 0.0, bp_im = 0.0;
                evaluateBandPassComplex(frequencies_[j], q_factors_[j], eval_freq_hz, sample_rate_, bp_re, bp_im);
                // parallel_scales_[j] multiplies the unnormalized SVF BandPass (which has peak Q_j)
                const double w_norm = scale * q_factors_[j];
                sum_re += w_norm * bp_re;
                sum_im += w_norm * bp_im;
            }
            const double mag_sq = std::max(sum_re * sum_re + sum_im * sum_im, 1e-15);
            return 10.0 * std::log10(mag_sq);
        }

        double total_db = 0.0;
        for (int j = 0; j < band_count_; ++j) {
            const double gain = (topology_ == EqTopology::LegacyCascade)
                                    ? target_gains_db_[j]
                                    : optimized_gains_db_[j];
            total_db += evaluateSingleFilterDb(frequencies_[j], q_factors_[j], gain, eval_freq_hz, sample_rate_);
        }
        return total_db;
    }

private:
    int band_count_ = 0;
    double sample_rate_ = 48000.0;
    EqTopology topology_ = EqTopology::MatrixCompensatedCascade;
    bool isFlat_ = true;

    std::vector<double> frequencies_;
    std::vector<double> q_factors_;
    std::vector<double> target_gains_db_;
    std::vector<double> optimized_gains_db_;
    std::vector<double> parallel_scales_;

    // Leakage Interaction Matrix B and its Inverse B^-1
    double B_[kMaxBands][kMaxBands]{};
    double invB_[kMaxBands][kMaxBands]{};

    // Parallel BandPass complex interaction matrix H_BP and real-part inverse
    double parRe_[kMaxBands][kMaxBands]{};
    double parIm_[kMaxBands][kMaxBands]{};
    double invParRe_[kMaxBands][kMaxBands]{};

    // Cytomic SVF filter stages (processes both float32 and float64 in 64-bit internal state)
    std::vector<CytomicSVF> filters_;

    // Parallel processing scratch buffers
    double parallel_scratch_[kMaxChannels]{};

    // Auto-Q determination based on octave bandwidth between adjacent bands
    void calculateAutoQ() {
        if (band_count_ <= 0) return;
        if (band_count_ == 1) {
            q_factors_[0] = 1.4142;
            return;
        }

        for (int i = 0; i < band_count_; ++i) {
            double ratio = 2.0;
            if (i == 0) {
                ratio = frequencies_[1] / frequencies_[0];
            } else if (i == band_count_ - 1) {
                ratio = frequencies_[band_count_ - 1] / frequencies_[band_count_ - 2];
            } else {
                ratio = std::sqrt(frequencies_[i + 1] / frequencies_[i - 1]);
            }

            if (ratio <= 1.001) ratio = 1.001;
            const double N = std::log2(ratio);
            const double two_pow_N = std::pow(2.0, N);
            const double denom = two_pow_N - 1.0;
            if (denom > 1e-5) {
                q_factors_[i] = std::clamp(std::sqrt(two_pow_N) / denom, 0.5, 12.0);
            } else {
                q_factors_[i] = 1.4142;
            }
        }
    }

    // Exact closed-form dB response matching active CytomicSVF Bell filter (including Nyquist de-cramping)
    static double evaluateSingleFilterDb(double f0, double q, double gain_db, double f_eval, double fs) {
        return CytomicSVF::evaluateResponseDb(CytomicSVF::FilterType::Bell, fs, f0, gain_db, q, f_eval);
    }

    // Unity-peak CytomicSVF BandPass complex transfer function (k * v1 / in) at eval_freq_hz
    static void evaluateBandPassComplex(double f0, double q, double f_eval, double fs, double& out_re, double& out_im) {
        if (fs <= 0.0) fs = 48000.0;
        constexpr double kPi = 3.14159265358979323846;
        const double g = std::tan(kPi * std::clamp(f0, 10.0, fs * 0.499) / fs);
        const double k = 1.0 / std::max(q, 0.05);
        const double w = 2.0 * kPi * std::clamp(f_eval, 1.0, fs * 0.4999) / fs;

        // Bilinear s_bar = (1 - z^-1) / (1 + z^-1) = j * tan(w / 2)
        const double t = std::tan(w * 0.5);
        // H_BP_norm(e^jw) = (j * g * k * t) / ((g^2 - t^2) + j * (g * k * t))
        const double a = g * g - t * t;
        const double b = g * k * t;
        const double den = a * a + b * b;
        if (den <= 1e-30) {
            out_re = 1.0;
            out_im = 0.0;
            return;
        }
        out_re = (b * b) / den;
        out_im = (a * b) / den;
    }

    // Computes M x M leakage matrix B and its analytical inverse B^-1
    void computeInteractionMatrix() {
        if (band_count_ <= 0) return;

        const double g_ref = 1.0; // Reference 1 dB test impulse
        for (int j = 0; j < band_count_; ++j) {
            for (int i = 0; i < band_count_; ++i) {
                if (i == j) {
                    B_[i][j] = 1.0;
                } else {
                    const double leak_db = evaluateSingleFilterDb(frequencies_[j], q_factors_[j], g_ref, frequencies_[i], sample_rate_);
                    B_[i][j] = leak_db / g_ref;
                }
                evaluateBandPassComplex(frequencies_[j], q_factors_[j], frequencies_[i], sample_rate_, parRe_[i][j], parIm_[i][j]);
            }
        }

        // Invert B and parRe using Gaussian elimination with partial pivoting
        invertMatrix(band_count_, B_, invB_);
        invertMatrix(band_count_, parRe_, invParRe_);
    }

    // High-precision zero-allocation Gauss-Jordan inversion with partial pivoting
    static bool invertMatrix(int n, const double src[kMaxBands][kMaxBands], double dst[kMaxBands][kMaxBands]) {
        double aug[kMaxBands][2 * kMaxBands];
        for (int i = 0; i < n; ++i) {
            for (int j = 0; j < n; ++j) {
                aug[i][j] = src[i][j];
                aug[i][j + n] = (i == j) ? 1.0 : 0.0;
            }
        }

        for (int i = 0; i < n; ++i) {
            // Find pivot
            int pivot_row = i;
            double max_val = std::abs(aug[i][i]);
            for (int r = i + 1; r < n; ++r) {
                double val = std::abs(aug[r][i]);
                if (val > max_val) {
                    max_val = val;
                    pivot_row = r;
                }
            }

            if (pivot_row != i) {
                for (int c = 0; c < 2 * n; ++c) {
                    std::swap(aug[i][c], aug[pivot_row][c]);
                }
            }

            double pivot = aug[i][i];
            if (std::abs(pivot) < 1e-12) {
                pivot = (pivot >= 0.0) ? 1e-12 : -1e-12; // Numerical safety stabilizer
            }
            const double inv_pivot = 1.0 / pivot;

            for (int c = 0; c < 2 * n; ++c) {
                aug[i][c] *= inv_pivot;
            }

            for (int r = 0; r < n; ++r) {
                if (r != i) {
                    const double factor = aug[r][i];
                    for (int c = 0; c < 2 * n; ++c) {
                        aug[r][c] -= factor * aug[i][c];
                    }
                }
            }
        }

        for (int i = 0; i < n; ++i) {
            for (int j = 0; j < n; ++j) {
                dst[i][j] = aug[i][j + n];
            }
        }
        return true;
    }

    // Solves for decoupled gains g_optimized = B^-1 * g_target and updates SVF stages
    void updateFilterParameters() {
        if (band_count_ <= 0) {
            isFlat_ = true;
            return;
        }

        bool all_zero = true;
        for (int i = 0; i < band_count_; ++i) {
            if (std::abs(target_gains_db_[i]) >= 0.005) {
                all_zero = false;
                break;
            }
        }

        if (all_zero) {
            optimized_gains_db_.assign(band_count_, 0.0);
            parallel_scales_.assign(band_count_, 0.0);
            for (int i = 0; i < band_count_; ++i) {
                filters_[i].setParameters(CytomicSVF::FilterType::Bell, sample_rate_, frequencies_[i], 0.0, q_factors_[i]);
            }
            isFlat_ = true;
            return;
        }

        isFlat_ = false;

        if (topology_ == EqTopology::LegacyCascade) {
            // Uncompensated direct assignment
            for (int i = 0; i < band_count_; ++i) {
                optimized_gains_db_[i] = target_gains_db_[i];
                parallel_scales_[i] = 0.0;
                filters_[i].setParameters(CytomicSVF::FilterType::Bell, sample_rate_, frequencies_[i], target_gains_db_[i], q_factors_[i]);
            }
        } else if (topology_ == EqTopology::SymmetricParallel) {
            // Solve complex parallel bandpass interaction: |1 + H_BP * w| = 10^(g_target / 20)
            double target_mag[kMaxBands]{};
            double weights[kMaxBands]{};
            for (int i = 0; i < band_count_; ++i) {
                target_gains_db_[i] = std::clamp(target_gains_db_[i], -24.0, 24.0);
                target_mag[i] = std::pow(10.0, target_gains_db_[i] / 20.0);
            }

            // Initial linear solution using real part of H_BP: parRe * w = target_mag - 1
            for (int i = 0; i < band_count_; ++i) {
                double sum = 0.0;
                for (int j = 0; j < band_count_; ++j) {
                    sum += invParRe_[i][j] * (target_mag[j] - 1.0);
                }
                weights[i] = sum;
            }

            // Fixed-point complex magnitude refinement (accounts for quadrature skirt phase)
            for (int iter = 0; iter < 12; ++iter) {
                double err[kMaxBands]{};
                for (int i = 0; i < band_count_; ++i) {
                    double re = 1.0;
                    double im = 0.0;
                    for (int j = 0; j < band_count_; ++j) {
                        re += parRe_[i][j] * weights[j];
                        im += parIm_[i][j] * weights[j];
                    }
                    const double mag = std::sqrt(re * re + im * im);
                    const double sign_re = (re >= 0.0) ? 1.0 : -1.0;
                    err[i] = (target_mag[i] - mag) * sign_re;
                }
                for (int i = 0; i < band_count_; ++i) {
                    double dw = 0.0;
                    for (int j = 0; j < band_count_; ++j) {
                        dw += invParRe_[i][j] * err[j];
                    }
                    weights[i] += dw;
                }
            }

            for (int i = 0; i < band_count_; ++i) {
                const double lin_gain = std::max(0.015, 1.0 + weights[i]);
                optimized_gains_db_[i] = std::clamp(20.0 * std::log10(lin_gain), -36.0, 36.0);
                // SVF BandPass (m1=1) has peak gain Q; scale by 1/Q for unity-peak basis
                parallel_scales_[i] = (std::abs(weights[i]) >= 1e-6)
                                          ? (weights[i] / q_factors_[i])
                                          : 0.0;
                filters_[i].setParameters(CytomicSVF::FilterType::BandPass, sample_rate_, frequencies_[i], optimized_gains_db_[i], q_factors_[i]);
            }
        } else {
            // Matrix-Compensated Cascade decoupling: g_opt = invB * g_target
            for (int i = 0; i < band_count_; ++i) {
                double sum = 0.0;
                for (int j = 0; j < band_count_; ++j) {
                    sum += invB_[i][j] * target_gains_db_[j];
                }
                // Clamp within safe physical filter bounds [-36, +36] dB
                optimized_gains_db_[i] = std::clamp(sum, -36.0, 36.0);
                parallel_scales_[i] = 0.0;
                filters_[i].setParameters(CytomicSVF::FilterType::Bell, sample_rate_, frequencies_[i], optimized_gains_db_[i], q_factors_[i]);
            }
        }
    }

    template <typename T>
    void processCascade(T* frames, size_t frame_count, int channels) {
        for (int i = 0; i < band_count_; ++i) {
            if (filters_[i].isFlat()) continue;
            filters_[i].process(frames, (uint32_t)frame_count, channels);
        }
    }

    template <typename T>
    void processParallel(T* frames, size_t frame_count, int channels) {
        // Parallel filter bank: y[n] = x[n] + sum_m( ((10^(g_m/20) - 1) / Q_m) * BP_m(x[n]) )
        // Zero-allocation evaluation using per-channel SVF states
        for (size_t s = 0; s < frame_count; ++s) {
            T* frame = frames + s * (size_t)channels;
            for (int c = 0; c < channels; ++c) {
                const double dry = static_cast<double>(frame[c]);
                double acc = dry;
                for (int m = 0; m < band_count_; ++m) {
                    const double scale = parallel_scales_[m];
                    if (scale == 0.0) continue;
                    acc += filters_[m].processSample(dry, c) * scale;
                }
                frame[c] = static_cast<T>(acc);
            }
        }
    }

    template <typename T>
    void processCascadeChannel(T* frames, size_t frame_count, int channels, int channel_index) {
        for (int i = 0; i < band_count_; ++i) {
            if (filters_[i].isFlat()) continue;
            filters_[i].processChannel(frames, (uint32_t)frame_count, channels, channel_index);
        }
    }

    template <typename T>
    void processParallelChannel(T* frames, size_t frame_count, int channels, int channel_index) {
        for (size_t s = 0; s < frame_count; ++s) {
            T& sample = frames[s * (size_t)channels + (size_t)channel_index];
            const double dry = static_cast<double>(sample);
            double acc = dry;
            for (int m = 0; m < band_count_; ++m) {
                const double scale = parallel_scales_[m];
                if (scale == 0.0) continue;
                acc += filters_[m].processSample(dry, channel_index) * scale;
            }
            sample = static_cast<T>(acc);
        }
    }
};

} // namespace sauti::dsp
