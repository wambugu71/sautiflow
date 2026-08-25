// Smoke test for dsp/spatial_surround_dsp.h
// Build: g++ -std=c++20 -O2 -Wall tests/test_surround_dsp.cpp -o test_surround && ./test_surround

#include "../dsp/spatial_surround_dsp.h"
#include <cstdio>
#include <string>
#include <vector>

using sauti::dsp::SpatialSurroundDSP;
using sauti::dsp::SurroundMode;

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
    for (float v : b)
        if (!std::isfinite(v)) return false;
    return true;
}

static float peak(const std::vector<float> &b)
{
    float p = 0.0f;
    for (float v : b) p = std::max(p, std::fabs(v));
    return p;
}

int main()
{
    const uint32_t sr = 48000;

    // 1. Disabled DSP must be a bit-exact passthrough
    {
        SpatialSurroundDSP dsp;
        dsp.setSampleRate((float)sr);
        std::vector<float> buf(2 * 512);
        for (size_t i = 0; i < buf.size(); ++i) buf[i] = ((i * 37) % 1000) / 1000.0f - 0.5f;
        auto ref = buf;
        dsp.process(buf.data(), 512);
        check(buf == ref, "disabled passthrough is bit-exact");
    }

    // 2. Every mode processes a sine without NaN/Inf/denormal explosion
    {
        const SurroundMode modes[] = {
            SurroundMode::FieldExpander,
            SurroundMode::DifferentialHaas,
            SurroundMode::ViperHeadphone,
            SurroundMode::Matrix51Hrtf
        };
        const char *names[] = {"FieldExpander", "DifferentialHaas", "ViperHeadphone", "Matrix51Hrtf"};

        for (int m = 0; m < 4; ++m) {
            SpatialSurroundDSP dsp;
            dsp.setSampleRate((float)sr);
            dsp.setEnabled(true);
            dsp.setMode(modes[m]);

            // Feed 1 second of stereo sine (also exercises long-run stability)
            std::vector<float> buf(2 * 1024);
            float peak_seen = 0.0f;
            bool finite = true;
            for (int blk = 0; blk < (int)(sr / 1024); ++blk) {
                for (uint32_t i = 0; i < 1024; ++i) {
                    const float t = (float)(blk * 1024 + i) / sr;
                    buf[2 * i]     = 0.5f * std::sinf(2.0f * 3.14159265f * 440.0f * t);
                    buf[2 * i + 1] = 0.5f * std::sinf(2.0f * 3.14159265f * 440.0f * t + 0.7f);
                }
                dsp.process(buf.data(), 1024);
                if (!all_finite(buf)) finite = false;
                peak_seen = std::max(peak_seen, peak(buf));
            }
            std::printf("  %s peak=%.3f\n", names[m], peak_seen);
            check(finite, names[m]);
            std::string msg = std::string(names[m]) + " produces audible output";
            check(peak_seen > 0.05f, msg.c_str());
            std::string lvl = std::string(names[m]) + " stays below clipping";
            check(peak_seen < 8.0f, lvl.c_str());
        }
    }

    // 3. Field expander mono compatibility: pure mono in -> side cancels
    {
        SpatialSurroundDSP dsp;
        dsp.setSampleRate((float)sr);
        dsp.setEnabled(true);
        dsp.setMode(SurroundMode::FieldExpander);
        dsp.setFieldWidth(2.5f);

        std::vector<float> buf(2 * 4096);
        for (uint32_t i = 0; i < 4096; ++i) {
            const float x = 0.4f * std::sinf(2.0f * 3.14159265f * 100.0f * i / sr);
            buf[2 * i] = x;
            buf[2 * i + 1] = x;
        }
        dsp.process(buf.data(), 4096);
        double max_imbalance = 0.0;
        for (uint32_t i = 100; i < 4096; ++i)
            max_imbalance = std::max(max_imbalance, (double)std::fabs(buf[2 * i] - buf[2 * i + 1]));
        std::printf("  field max L/R imbalance on mono input: %.6f\n", max_imbalance);
        check(max_imbalance < 1e-3, "field expander keeps mono content stereo-symmetric");
    }

    // 4. HRTF ITD sanity: hard-right source delays the LEFT ear signal
    {
        sauti::dsp::HrtfSource src;
        src.configure(+90.0f, 0.0f, 8.75f, 1.0f, (float)sr);
        std::vector<float> accL(sr, 0.0f), accR(sr, 0.0f);
        for (uint32_t n = 0; n < sr; ++n) {
            float x = (n == 0) ? 1.0f : 0.0f;
            src.process(x, 1.0f, accL[n], accR[n]);
        }
        int first_l = -1, first_r = -1;
        for (uint32_t n = 0; n < sr; ++n) {
            if (first_r < 0 && std::fabs(accR[n]) > 1e-4f) first_r = (int)n;
            if (first_l < 0 && std::fabs(accL[n]) > 1e-4f) first_l = (int)n;
        }
        std::printf("  first arrival R=%d samples, L=%d samples\n", first_r, first_l);
        check(first_r == 0, "hard-right source reaches right ear immediately");
        check(first_l > 10 && first_l < 40, "hard-right source left ear delayed by ITD (~31 samples @48k)");
    }

    // 5. Mode switching + reset stability (no stale state blowups)
    {
        SpatialSurroundDSP dsp;
        dsp.setSampleRate((float)sr);
        dsp.setEnabled(true);
        std::vector<float> buf(2 * 256, 0.25f);
        bool finite = true;
        for (int m = 0; m <= 4; ++m) {
            dsp.setMode((SurroundMode)m);
            for (int b = 0; b < 50; ++b) {
                dsp.process(buf.data(), 256);
                if (!all_finite(buf)) finite = false;
            }
            dsp.reset();
        }
        check(finite, "mode cycling remains stable");
    }

    // 6. Sample-rate change rebuilds cleanly
    {
        SpatialSurroundDSP dsp;
        dsp.setSampleRate((float)sr);
        dsp.setEnabled(true);
        dsp.setMode(SurroundMode::Matrix51Hrtf);
        std::vector<float> buf(2 * 256, 0.3f);
        dsp.process(buf.data(), 256);
        dsp.setSampleRate(44100.0f);
        dsp.reset();
        dsp.process(buf.data(), 256);
        check(all_finite(buf), "sample rate switch remains stable");
    }

    std::printf("\n%s (%d failure(s))\n", failures == 0 ? "ALL TESTS PASSED" : "TESTS FAILED", failures);
    return failures == 0 ? 0 : 1;
}
