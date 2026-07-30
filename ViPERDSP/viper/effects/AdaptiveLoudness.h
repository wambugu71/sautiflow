#pragma once

#include <cstdint>
#include <cmath>
#include <algorithm>

class AdaptiveLoudness {
public:
    enum AlcMode {
        NATURAL = 0,
        MILD = 1,
        PUNCHY = 2
    };

    AdaptiveLoudness();

    void Process(float *samples, uint32_t size);
    void Reset();

    void SetEnable(bool enable);
    void SetMode(AlcMode mode);
    void SetStrength(float strength);
    void SetVolumeAttenuationDb(float attenuation_db);
    void SetSamplingRate(uint32_t sampling_rate);

private:
    void UpdateCoefficients();

    struct BiquadState {
        double x1 = 0.0;
        double x2 = 0.0;
        double y1 = 0.0;
        double y2 = 0.0;
        double b0 = 1.0;
        double b1 = 0.0;
        double b2 = 0.0;
        double a1 = 0.0;
        double a2 = 0.0;

        void Reset() {
            x1 = x2 = y1 = y2 = 0.0;
        }

        inline double Process(double input) {
            double output = b0 * input + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2;
            x2 = x1;
            x1 = input;
            y2 = y1;
            y1 = output;
            return output;
        }

        void SetLowShelf(float freq_hz, float gain_db, float sampling_rate) {
            if (std::abs(gain_db) < 0.05f) {
                b0 = 1.0; b1 = 0.0; b2 = 0.0; a1 = 0.0; a2 = 0.0;
                return;
            }
            double A = std::pow(10.0, gain_db / 40.0);
            double w0 = 2.0 * 3.14159265358979323846 * freq_hz / sampling_rate;
            double cosw0 = std::cos(w0);
            double sinw0 = std::sin(w0);
            double alpha = sinw0 / 2.0 * std::sqrt((A + 1.0 / A) * (1.0 - 1.0) + 2.0); // S = 1
            if (alpha < 1e-6) alpha = sinw0 / 1.41421356;

            double beta = 2.0 * std::sqrt(A) * alpha;

            double a0 = (A + 1.0) + (A - 1.0) * cosw0 + beta;
            b0 = (A * ((A + 1.0) - (A - 1.0) * cosw0 + beta)) / a0;
            b1 = (2.0 * A * ((A - 1.0) - (A + 1.0) * cosw0)) / a0;
            b2 = (A * ((A + 1.0) - (A - 1.0) * cosw0 - beta)) / a0;
            a1 = (-2.0 * ((A - 1.0) + (A + 1.0) * cosw0)) / a0;
            a2 = ((A + 1.0) + (A - 1.0) * cosw0 - beta) / a0;
        }

        void SetHighShelf(float freq_hz, float gain_db, float sampling_rate) {
            if (std::abs(gain_db) < 0.05f) {
                b0 = 1.0; b1 = 0.0; b2 = 0.0; a1 = 0.0; a2 = 0.0;
                return;
            }
            double A = std::pow(10.0, gain_db / 40.0);
            double w0 = 2.0 * 3.14159265358979323846 * freq_hz / sampling_rate;
            double cosw0 = std::cos(w0);
            double sinw0 = std::sin(w0);
            double alpha = sinw0 / 2.0;
            double beta = 2.0 * std::sqrt(A) * alpha;

            double a0 = (A + 1.0) - (A - 1.0) * cosw0 + beta;
            b0 = (A * ((A + 1.0) + (A - 1.0) * cosw0 + beta)) / a0;
            b1 = (-2.0 * A * ((A - 1.0) + (A + 1.0) * cosw0)) / a0;
            b2 = (A * ((A + 1.0) + (A - 1.0) * cosw0 - beta)) / a0;
            a1 = (2.0 * ((A - 1.0) - (A + 1.0) * cosw0)) / a0;
            a2 = ((A + 1.0) - (A - 1.0) * cosw0 - beta) / a0;
        }
    };

    bool enable_;
    AlcMode mode_;
    float strength_;
    float attenuation_db_;
    uint32_t sampling_rate_;

    BiquadState low_shelf_l_;
    BiquadState low_shelf_r_;
    BiquadState high_shelf_l_;
    BiquadState high_shelf_r_;
};
