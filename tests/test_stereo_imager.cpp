// Smoke and acoustic verification test for dsp/stereo_imager_dsp.h
// Build: g++ -std=c++20 -O2 -Wall -I. -Idsp tests/test_stereo_imager.cpp -o tests/test_stereo_imager.exe

#include "../dsp/stereo_imager_dsp.h"
#include <cstdio>
#include <cmath>
#include <string>
#include <vector>
#include <algorithm>

using sauti::dsp::StereoImagerDSP;
using sauti::dsp::StereoImagerMode;

static int failures = 0;

static void check(bool cond, const char *msg)
{
    if (!cond) {
        std::printf("FAIL: %s\n", msg);
        failures++;
    } else {
        std::printf("PASS: %s\n", msg);
    }
}

static bool all_finite(const std::vector<float> &b)
{
    for (float v : b) {
        if (!std::isfinite(v)) return false;
    }
    return true;
}

static float peak(const std::vector<float> &b)
{
    float p = 0.0f;
    for (float v : b) p = std::max(p, std::fabs(v));
    return p;
}

static double rms_ch(const std::vector<float> &b, int ch, size_t start_frame, size_t end_frame)
{
    double sum = 0.0;
    size_t count = 0;
    for (size_t i = start_frame; i < end_frame; ++i) {
        const double v = static_cast<double>(b[2 * i + ch]);
        sum += v * v;
        count++;
    }
    return std::sqrt(sum / std::max<size_t>(1, count));
}

static double rms_side(const std::vector<float> &b, size_t start_frame, size_t end_frame)
{
    double sum = 0.0;
    size_t count = 0;
    for (size_t i = start_frame; i < end_frame; ++i) {
        const double s = 0.5 * (static_cast<double>(b[2 * i]) - static_cast<double>(b[2 * i + 1]));
        sum += s * s;
        count++;
    }
    return std::sqrt(sum / std::max<size_t>(1, count));
}

int main()
{
    const uint32_t sr = 48000;
    constexpr float kPi = 3.14159265358979323846f;

    std::printf("=== Running StereoImagerDSP Audiophile Verification Tests ===\n");

    // 1. Disabled DSP must be a bit-exact passthrough
    {
        StereoImagerDSP dsp;
        dsp.setSampleRate(static_cast<float>(sr));
        dsp.setEnabled(false);

        std::vector<float> buf(2 * 512);
        for (size_t i = 0; i < buf.size(); ++i) {
            buf[i] = ((static_cast<int>(i) * 37) % 1000) / 1000.0f - 0.5f;
        }
        auto ref = buf;
        dsp.process(buf.data(), 512, 2);
        check(buf == ref, "Disabled passthrough is bit-exact");
    }

    // 2. Clean Mastering: bit-exact passthrough at unity up to -0.1 dBFS, and flat L==R on pure mono with Mono Bass active
    {
        StereoImagerDSP dsp;
        dsp.setSampleRate(static_cast<float>(sr));
        dsp.setEnabled(true);
        dsp.setMode(StereoImagerMode::CleanMastering);
        dsp.setWidth(1.0f);
        dsp.setMonoBelowHz(0.0f);
        dsp.setAirBoostDb(0.0f);
        dsp.reset();

        std::vector<float> hot(2 * 1024);
        for (size_t i = 0; i < 1024; ++i) {
            hot[2 * i]     = 0.985f * std::sin(2.0f * kPi * 1000.0f * i / sr);
            hot[2 * i + 1] = 0.985f * std::cos(2.0f * kPi * 1000.0f * i / sr);
        }
        auto refHot = hot;
        dsp.process(hot.data(), 1024, 2);
        float maxHotDiff = 0.0f;
        for (size_t i = 0; i < hot.size(); ++i) {
            maxHotDiff = std::max(maxHotDiff, std::fabs(hot[i] - refHot[i]));
        }
        check(maxHotDiff < 1.0e-5f, "Clean Mastering @ width=1.0 passes -0.1 dBFS (0.985) bit-exact without softClip distortion");

        // Pure mono with Mono Bass active (150 Hz) -> exact L==R and 0.00 dB RMS
        dsp.setWidth(2.5f);
        dsp.setMonoBelowHz(150.0f);
        dsp.reset();

        std::vector<float> mono(2 * 4096);
        double in_rms_sum = 0.0;
        for (size_t i = 0; i < 4096; ++i) {
            float val = 0.4f * std::sin(2.0f * kPi * 440.0f * i / sr);
            mono[2 * i]     = val;
            mono[2 * i + 1] = val;
            if (i >= 2048) in_rms_sum += static_cast<double>(val) * val;
        }
        const double in_rms = std::sqrt(in_rms_sum / 2048.0);
        dsp.process(mono.data(), 4096, 2);
        float maxLR = 0.0f;
        for (size_t i = 2048; i < 4096; ++i) {
            maxLR = std::max(maxLR, std::fabs(mono[2 * i] - mono[2 * i + 1]));
        }
        const double out_rms = rms_ch(mono, 0, 2048, 4096);
        check(maxLR < 1.0e-6f, "Clean Mastering on pure mono keeps exact L == R");
        check(std::fabs(out_rms / in_rms - 1.0) < 0.01, "Clean Mastering on pure mono with 150 Hz Mono Bass preserves flat 0.00 dB RMS");
    }

    // 3. Spatial 3D: Mono Sum Compatibility, Zero Comb Tilt, Sub-Bass Integrity, Delay Effect
    {
        // 3a. Stereo loudness invariance & clean mono-sum cancellation (monoBelowHz = 0)
        {
            StereoImagerDSP dsp;
            dsp.setSampleRate(static_cast<float>(sr));
            dsp.setEnabled(true);
            dsp.setMode(StereoImagerMode::Spatial3D);
            dsp.setWidth(2.0f);
            dsp.setMonoBelowHz(0.0f);
            dsp.setAirBoostDb(0.0f);

            std::vector<float> buf(2 * 4096);
            for (size_t i = 0; i < 4096; ++i) {
                float m = 0.3f * std::sin(2.0f * kPi * 1000.0f * i / sr);
                buf[2 * i]     = m;
                buf[2 * i + 1] = m;
            }
            dsp.process(buf.data(), 4096, 2);

            const double in_rms = 0.3 / std::sqrt(2.0);
            double mono_sum_sq = 0.0;
            double stereo_sq = 0.0;
            size_t count = 0;
            for (size_t i = 2048; i < 4096; ++i) {
                double l = static_cast<double>(buf[2 * i]);
                double r = static_cast<double>(buf[2 * i + 1]);
                double monoSum = 0.5 * (l + r);
                mono_sum_sq += monoSum * monoSum;
                stereo_sq += 0.5 * (l * l + r * r);
                count++;
            }
            const double mono_sum_rms = std::sqrt(mono_sum_sq / count);
            const double stereo_rms = std::sqrt(stereo_sq / count);
            std::printf("  Spatial 3D w=2.0: stereo_rms/in_rms=%.4f, mono_sum_rms/in_rms=%.4f\n",
                        stereo_rms / in_rms, mono_sum_rms / in_rms);
            check(std::fabs(stereo_rms / in_rms - 1.0) < 0.02, "Spatial 3D preserves constant total stereo RMS (<2%)");
            check((mono_sum_rms / in_rms) > 0.96 && (mono_sum_rms / in_rms) < 1.01, "Spatial 3D mono sum cancels decorrelation without comb nulls");
            check(rms_side(buf, 2048, 4096) > 0.02, "Spatial 3D widens 1 kHz mono input audibly");
        }

        // 3e. ImagerHilbert4 quadrature accuracy & Spatial 3D low L/R comb tilt across 400..7000 Hz
        {
            sauti::dsp::ImagerHilbert4 hilb;
            bool hilb_quad_ok = true;
            for (float f_hz : { 400.0f, 1000.0f, 3000.0f, 7000.0f, 12000.0f }) {
                hilb.reset();
                double dot_ab = 0.0, norm_a = 0.0, norm_b = 0.0;
                for (size_t i = 0; i < 4096; ++i) {
                    double x = std::sin(2.0 * kPi * f_hz * i / sr);
                    double a = 0.0, b = 0.0;
                    hilb.processPair(x, a, b);
                    if (i >= 2048) {
                        dot_ab += a * b;
                        norm_a += a * a;
                        norm_b += b * b;
                    }
                }
                double cos_phi = dot_ab / (std::sqrt(norm_a * norm_b) + 1e-18);
                double mag_ratio = std::sqrt(norm_a / (norm_b + 1e-18));
                if (std::fabs(cos_phi) > 0.0175 || std::fabs(mag_ratio - 1.0) > 0.005) {
                    hilb_quad_ok = false;
                }
            }
            check(hilb_quad_ok, "ImagerHilbert4 processPair maintains 90 deg (+/- 1 deg) and unity magnitude 400 Hz..12 kHz");

            double max_tilt_db = 0.0;
            for (float f_hz : { 400.0f, 1000.0f, 3000.0f, 7000.0f }) {
                StereoImagerDSP dsp;
                dsp.setSampleRate(static_cast<float>(sr));
                dsp.setEnabled(true);
                dsp.setMode(StereoImagerMode::Spatial3D);
                dsp.setWidth(2.0f);
                dsp.setMonoBelowHz(0.0f);
                dsp.setAirBoostDb(0.0f);

                std::vector<float> buf(2 * 4096);
                for (size_t i = 0; i < 4096; ++i) {
                    float m = 0.35f * std::sin(2.0f * kPi * f_hz * i / sr);
                    buf[2 * i] = m;
                    buf[2 * i + 1] = m;
                }
                dsp.process(buf.data(), 4096, 2);
                double lr_db = std::fabs(20.0 * std::log10((rms_ch(buf, 0, 2048, 4096) + 1e-12) / (rms_ch(buf, 1, 2048, 4096) + 1e-12)));
                max_tilt_db = std::max(max_tilt_db, lr_db);
                std::printf("  Spatial 3D L/R tilt @ %.0f Hz: %.3f dB\n", f_hz, lr_db);
            }
            check(max_tilt_db < 0.85, "Spatial 3D L/R comb tilt < 0.85 dB across 400..7000 Hz (was > 3 dB)");
        }

        // 3b. Zero 150 Hz L/R inversion at width = 1.0, 1.5, 2.0 when monoBelowHz = 150
        {
            bool no_inversion = true;
            for (float w : { 1.0f, 1.5f, 2.0f }) {
                StereoImagerDSP dsp;
                dsp.setSampleRate(static_cast<float>(sr));
                dsp.setEnabled(true);
                dsp.setMode(StereoImagerMode::Spatial3D);
                dsp.setWidth(w);
                dsp.setMonoBelowHz(150.0f);
                dsp.setAirBoostDb(0.0f);

                const size_t N = 4096;
                std::vector<float> buf(2 * N, 0.0f);
                for (size_t i = 0; i < N; ++i) {
                    buf[2 * i] = 0.5f * std::sin(2.0f * kPi * 150.0f * i / sr);
                }
                dsp.process(buf.data(), static_cast<uint32_t>(N), 2);
                const double l_rms = rms_ch(buf, 0, 2048, N);
                const double r_rms = rms_ch(buf, 1, 2048, N);
                const double lr_db = 20.0 * std::log10((l_rms + 1e-12) / (r_rms + 1e-12));
                std::printf("  Spatial 3D hard-L 150Hz @ w=%.1f: L-R=%+.2f dB\n", w, lr_db);
                if (lr_db <= 3.0) no_inversion = false;
            }
            check(no_inversion, "Spatial 3D has zero L/R inversion at monoBelowHz (150 Hz)");
        }

        // 3c. Sub-bass anchor integrity in Spatial 3D (50 Hz stereo input -> < -25 dB Side leakage)
        {
            StereoImagerDSP dsp;
            dsp.setSampleRate(static_cast<float>(sr));
            dsp.setEnabled(true);
            dsp.setMode(StereoImagerMode::Spatial3D);
            dsp.setWidth(2.0f);
            dsp.setMonoBelowHz(150.0f);
            dsp.setAirBoostDb(0.0f);

            const size_t N = 4096;
            std::vector<float> buf(2 * N, 0.0f);
            for (size_t i = 0; i < N; ++i) {
                buf[2 * i] = 0.5f * std::sin(2.0f * kPi * 50.0f * i / sr);
            }
            dsp.process(buf.data(), static_cast<uint32_t>(N), 2);
            const double m_rms = 0.25 / std::sqrt(2.0);
            const double s_rms = rms_side(buf, 2048, N);
            const double leak_db = 20.0 * std::log10((s_rms + 1e-12) / m_rms);
            std::printf("  Spatial 3D 50 Hz Side leakage (monoBelow=150 Hz): %.2f dB\n", leak_db);
            check(leak_db < -25.0, "Spatial 3D keeps 50 Hz sub-bass anchored (< -25 dB Side leak)");
        }

        // 3d. setDelayMs(6.0) vs setDelayMs(26.0) produces distinct decorrelated Side output
        {
            auto run_delay = [&](float d_ms) {
                StereoImagerDSP dsp;
                dsp.setSampleRate(static_cast<float>(sr));
                dsp.setEnabled(true);
                dsp.setMode(StereoImagerMode::Spatial3D);
                dsp.setWidth(2.0f);
                dsp.setMonoBelowHz(120.0f);
                dsp.setAirBoostDb(0.0f);
                dsp.setDelayMs(d_ms);
                std::vector<float> buf(2 * 2048);
                for (size_t i = 0; i < 2048; ++i) {
                    float m = 0.4f * std::sin(2.0f * kPi * 1200.0f * i / sr);
                    buf[2 * i]     = m;
                    buf[2 * i + 1] = m;
                }
                dsp.process(buf.data(), 2048, 2);
                return buf;
            };
            auto b6  = run_delay(6.0f);
            auto b26 = run_delay(26.0f);
            float max_d = 0.0f;
            for (size_t i = 512; i < 2048; ++i) {
                max_d = std::max(max_d, std::fabs(b6[2 * i] - b26[2 * i]));
            }
            check(max_d > 1.0e-3f, "Spatial 3D setDelayMs(6ms vs 26ms) measurably varies decorrelation");
        }
    }

    // 4. Sub-Bass Mono Anchor Test (Out-of-phase 40 Hz bass eliminated on Side)
    {
        StereoImagerDSP dsp;
        dsp.setSampleRate(static_cast<float>(sr));
        dsp.setEnabled(true);
        dsp.setMode(StereoImagerMode::CleanMastering);
        dsp.setWidth(1.0f);
        dsp.setMonoBelowHz(200.0f);
        dsp.setAirBoostDb(0.0f);

        std::vector<float> buf(2 * 2048);
        for (size_t i = 0; i < 2048; ++i) {
            float s = 0.5f * std::sin(2.0f * kPi * 40.0f * i / sr);
            buf[2 * i]     =  s;
            buf[2 * i + 1] = -s;
        }
        dsp.process(buf.data(), 2048, 2);

        float tailPeak = 0.0f;
        for (size_t i = 1500; i < 2048; ++i) {
            tailPeak = std::max(tailPeak, std::fabs(buf[2 * i]));
        }
        check(tailPeak < 0.02f, "Sub-bass mono anchor (LR4) eliminates out-of-phase 40 Hz cancellation");
    }

    // 5. Blumlein Shuffler: narrowing (width=0.5) attenuates Side, widening (width=1.5) expands cleanly with <75 Hz protection
    {
        auto test_blumlein = [&](float w, float f_hz) {
            StereoImagerDSP dsp;
            dsp.setSampleRate(static_cast<float>(sr));
            dsp.setEnabled(true);
            dsp.setMode(StereoImagerMode::BlumleinShuffler);
            dsp.setWidth(w);
            dsp.setMonoBelowHz(0.0f);
            dsp.setAirBoostDb(0.0f);
            const size_t N = 4096;
            std::vector<float> buf(2 * N);
            for (size_t i = 0; i < N; ++i) {
                float l = 0.5f * std::sin(2.0f * kPi * f_hz * i / sr);
                buf[2 * i]     = l;
                buf[2 * i + 1] = 0.0f;
            }
            dsp.process(buf.data(), static_cast<uint32_t>(N), 2);
            const double in_side_rms = 0.25 / std::sqrt(2.0);
            return rms_side(buf, 2048, N) / in_side_rms;
        };

        const double ratio_narrow_300 = test_blumlein(0.5f, 300.0f);
        const double ratio_wide_300   = test_blumlein(1.5f, 300.0f);
        const double ratio_wide_40    = test_blumlein(1.5f, 40.0f);
        std::printf("  Blumlein Side ratio: w=0.5@300Hz=%.3f, w=1.5@300Hz=%.3f, w=1.5@40Hz=%.3f\n",
                    ratio_narrow_300, ratio_wide_300, ratio_wide_40);
        check(ratio_narrow_300 < 0.90, "Blumlein @ width=0.5 narrows 300 Hz Side below input Side");
        check(ratio_wide_300 > 1.20 && ratio_wide_300 < 2.20, "Blumlein @ width=1.5 widens 300 Hz Side cleanly");
        check(ratio_wide_40 < 1.60, "Blumlein sub-bass guard keeps 40 Hz Side controlled even with Mono Bass off");
    }

    // 6. High-Headroom Safety Guard (caps extreme overs < 1.0)
    {
        StereoImagerDSP dsp;
        dsp.setSampleRate(static_cast<float>(sr));
        dsp.setEnabled(true);
        dsp.setWidth(3.5f);
        dsp.setAirBoostDb(6.0f);

        std::vector<float> buf(2 * 512);
        for (size_t i = 0; i < buf.size(); ++i) {
            buf[i] = 1.8f * std::sin(i * 0.1f);
        }

        dsp.process(buf.data(), 512, 2);
        float p = peak(buf);
        check(p <= 0.999f && all_finite(buf), "Safety guard caps extreme +5 dBFS overs safely < 1.0 with no NaN/Inf");
    }

    // 7. Lock-Free Real-Time Phase Correlation Telemetry
    {
        StereoImagerDSP dsp;
        dsp.setSampleRate(static_cast<float>(sr));
        dsp.setEnabled(true);

        std::vector<float> inPhase(2 * 512);
        for (size_t i = 0; i < 512; ++i) {
            float v = 0.5f * std::sin(i * 0.05f);
            inPhase[2 * i] = v; inPhase[2 * i + 1] = v;
        }
        dsp.process(inPhase.data(), 512, 2);
        float corrIn = dsp.getTelemetryPhaseCorrelation();
        check(corrIn > 0.90f, "Telemetry detects +1.0 in-phase correlation");

        std::vector<float> antiPhase(2 * 512);
        for (size_t i = 0; i < 512; ++i) {
            float v = 0.5f * std::sin(i * 0.05f);
            antiPhase[2 * i] = v; antiPhase[2 * i + 1] = -v;
        }
        for (int rep = 0; rep < 5; ++rep) {
            auto b = antiPhase;
            dsp.process(b.data(), 512, 2);
        }
        float corrAnti = dsp.getTelemetryPhaseCorrelation();
        check(corrAnti < 0.0f, "Telemetry detects negative phase correlation for anti-phase input");
    }

    if (failures == 0) {
        std::printf("ALL TESTS PASSED SUCCESSFULLY! (0 failures)\n");
        return 0;
    } else {
        std::printf("TESTS FAILED: %d failures\n", failures);
        return 1;
    }
}
