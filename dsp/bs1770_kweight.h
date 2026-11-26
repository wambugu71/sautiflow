#pragma once

#include <algorithm>
#include <array>
#include <cmath>

namespace sauti::dsp {

// =============================================================================
// BS1770KWeightFilter: ITU-R BS.1770-4 K-Weighting + Channel Power Weighting
//
// Stage 1: +4 dB high-shelf head/pinna compensation (~1681.97 Hz)
// Stage 2: 2nd-order RLB high-pass weighting (~38.135 Hz)
// Exact bilinear design for arbitrary sample rates (Brecht De Man / ITU-R BS.1770-4).
// =============================================================================
class BS1770KWeightFilter {
public:
    static constexpr int kMaxChannels = 8;

    BS1770KWeightFilter() {
        updateSampleRate(48000.0);
        reset();
    }

    void updateSampleRate(double sample_rate) noexcept {
        if (!std::isfinite(sample_rate) || sample_rate <= 0.0) {
            sample_rate = 48000.0;
        }
        if (initialized_ && std::abs(sample_rate - sample_rate_) < 0.1) {
            return;
        }
        sample_rate_ = sample_rate;
        initialized_ = true;

        constexpr double kPi = 3.14159265358979323846;
        // Clamp cutoff safely below Nyquist if ever given unusually low sample rates
        const double nyquist_guard = sample_rate * 0.45;

        // Stage 1: +4 dB High-Shelf Pre-Filter (acoustic head/pinna model)
        {
            const double f0 = std::min(1681.974450955533, nyquist_guard);
            constexpr double G = 3.999843853973347;
            constexpr double Q = 0.7071752369554196;
            const double K = std::tan(kPi * f0 / sample_rate);
            const double Vh = std::pow(10.0, G / 20.0);
            const double Vb = std::pow(Vh, 0.4996667741545416);
            const double K2 = K * K;
            const double a0 = 1.0 + K / Q + K2;

            hs_b0_ = (Vh + Vb * K / Q + K2) / a0;
            hs_b1_ = 2.0 * (K2 - Vh) / a0;
            hs_b2_ = (Vh - Vb * K / Q + K2) / a0;
            hs_a1_ = 2.0 * (K2 - 1.0) / a0;
            hs_a2_ = (1.0 - K / Q + K2) / a0;
        }

        // Stage 2: Revised Low-frequency B-weighting (RLB) High-Pass Filter
        // Normalized by 1/a0 so high-frequency passband gain is exactly 1.0 at all sample rates.
        {
            const double f0 = std::min(38.13547087602444, nyquist_guard);
            constexpr double Q = 0.5003270373238773;
            const double K = std::tan(kPi * f0 / sample_rate);
            const double K2 = K * K;
            const double a0 = 1.0 + K / Q + K2;

            hp_b0_ = 1.0 / a0;
            hp_b1_ = -2.0 / a0;
            hp_b2_ = 1.0 / a0;
            hp_a1_ = 2.0 * (K2 - 1.0) / a0;
            hp_a2_ = (1.0 - K / Q + K2) / a0;
        }
    }

    void reset() noexcept {
        for (int c = 0; c < kMaxChannels; ++c) {
            hs_z1_[c] = 0.0;
            hs_z2_[c] = 0.0;
            hp_z1_[c] = 0.0;
            hp_z2_[c] = 0.0;
        }
    }

    inline double processSample(int ch, double x) noexcept {
        if (ch < 0 || ch >= kMaxChannels) return x;
        if (!std::isfinite(x)) x = 0.0;

        // Stage 1: TDF-II High-Shelf
        const double y1 = hs_b0_ * x + hs_z1_[ch];
        hs_z1_[ch] = hs_b1_ * x - hs_a1_ * y1 + hs_z2_[ch];
        hs_z2_[ch] = hs_b2_ * x - hs_a2_ * y1;

        // Stage 2: TDF-II RLB High-Pass
        const double y2 = hp_b0_ * y1 + hp_z1_[ch];
        hp_z1_[ch] = hp_b1_ * y1 - hp_a1_ * y2 + hp_z2_[ch];
        hp_z2_[ch] = hp_b2_ * y1 - hp_a2_ * y2;
        return y2;
    }

    static inline double channelWeight(int ch, int total_channels) noexcept {
        if (total_channels <= 2) {
            return 1.0; // Mono / Stereo: L, R = 1.0
        }
        // Multichannel (5.1 / 7.1): L(0), R(1), C(2) = 1.0; LFE(3) = 0.0; Ls/Rs/Lrs/Rrs >= 4 = 1.41
        if (ch == 3 && total_channels >= 6) {
            return 0.0;
        }
        if (ch >= 4) {
            return 1.4125375446227544; // +1.5 dB per ITU-R BS.1770-4
        }
        return 1.0;
    }

private:
    double sample_rate_{48000.0};
    bool initialized_{false};

    double hs_b0_{1.0}, hs_b1_{0.0}, hs_b2_{0.0}, hs_a1_{0.0}, hs_a2_{0.0};
    double hp_b0_{1.0}, hp_b1_{0.0}, hp_b2_{0.0}, hp_a1_{0.0}, hp_a2_{0.0};

    std::array<double, kMaxChannels> hs_z1_{};
    std::array<double, kMaxChannels> hs_z2_{};
    std::array<double, kMaxChannels> hp_z1_{};
    std::array<double, kMaxChannels> hp_z2_{};
};

} // namespace sauti::dsp
