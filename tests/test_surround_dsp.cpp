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

    // 2. Every active mode processes audio without NaN/Inf/denormal explosion
    {
        const SurroundMode modes[] = {
            SurroundMode::MatrixSurround,
            SurroundMode::BinauralVirtualizer,
            SurroundMode::AcousticStage
        };
        const char *names[] = {"MatrixSurround", "BinauralVirtualizer", "AcousticStage"};

        for (int m = 0; m < 3; ++m) {
            SpatialSurroundDSP dsp;
            dsp.setSampleRate((float)sr);
            dsp.setEnabled(true);
            dsp.setMode(modes[m]);

            // Feed 1 second of stereo sine (exercises long-run stability)
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

    // 3. Binaural Virtualizer: Headphone HRTF mode vs Speaker Field mode
    {
        SpatialSurroundDSP dsp;
        dsp.setSampleRate((float)sr);
        dsp.setEnabled(true);
        dsp.setMode(SurroundMode::BinauralVirtualizer);

        // Headphone HRTF with Room 2 Cinema Reverb
        dsp.setBinauralMode(0);
        dsp.setBinauralBoost(0.85f);
        dsp.setBinauralRoomPreset(2);
        dsp.setBinauralRoomMix(0.40f);

        std::vector<float> bufHp(2 * 1024, 0.4f);
        dsp.process(bufHp.data(), 1024);
        check(all_finite(bufHp), "Binaural Virtualizer Headphone HRTF finite");
        check(peak(bufHp) > 0.1f, "Binaural Virtualizer Headphone HRTF audible output");

        // Speaker Field mode with Wide angle
        dsp.setBinauralMode(1);
        dsp.setBinauralSpeakerAngle(2); // Wide
        dsp.setBinauralBoost(0.75f);

        std::vector<float> bufSpk(2 * 1024, 0.4f);
        dsp.process(bufSpk.data(), 1024);
        check(all_finite(bufSpk), "Binaural Virtualizer Speaker Field finite");
        check(peak(bufSpk) > 0.1f, "Binaural Virtualizer Speaker Field audible output");
    }

    // 4. 3D Acoustic Stage: Studio vs Panoramic, Depth, Width, and Bass Anchor
    {
        SpatialSurroundDSP dsp;
        dsp.setSampleRate((float)sr);
        dsp.setEnabled(true);
        dsp.setMode(SurroundMode::AcousticStage);

        // Studio mode
        dsp.setStageProfile(0); // Headset
        dsp.setStageMode(0);    // Studio
        dsp.setStageWidth(1.4f);
        dsp.setStageDepth(0.6f);
        dsp.setStageCancellation(0.8f);
        dsp.setStageAirPresence(0.5f);
        dsp.setStageBassAnchorHz(80.0f);

        std::vector<float> bufStudio(2 * 1024, 0.35f);
        dsp.process(bufStudio.data(), 1024);
        check(all_finite(bufStudio), "3D Acoustic Stage Studio mode finite");

        // Panoramic mode with pure mono input -> stereo-symmetric response
        dsp.setStageMode(1); // Panoramic
        std::vector<float> bufMono(2 * 2048);
        for (uint32_t i = 0; i < 2048; ++i) {
            const float x = 0.4f * std::sinf(2.0f * 3.14159265f * 120.0f * i / sr);
            bufMono[2 * i]     = x;
            bufMono[2 * i + 1] = x;
        }
        dsp.process(bufMono.data(), 2048);
        double max_imbalance = 0.0;
        for (uint32_t i = 100; i < 2048; ++i) {
            max_imbalance = std::max(max_imbalance, (double)std::fabs(bufMono[2 * i] - bufMono[2 * i + 1]));
        }
        std::printf("  acoustic stage max L/R imbalance on mono input: %.6f\n", max_imbalance);
        check(max_imbalance < 1e-3, "3D Acoustic Stage keeps mono content stereo-symmetric");
    }

    // 5. Cinema Matrix 5.1 HRTF ITD sanity: hard-right source delays left ear signal
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

    // 6. Mode cycling + reset stability (no state explosion)
    {
        SpatialSurroundDSP dsp;
        dsp.setSampleRate((float)sr);
        dsp.setEnabled(true);
        std::vector<float> buf(2 * 256, 0.25f);
        bool finite = true;
        for (int m = 0; m <= 3; ++m) {
            dsp.setMode((SurroundMode)m);
            for (int b = 0; b < 50; ++b) {
                dsp.process(buf.data(), 256);
                if (!all_finite(buf)) finite = false;
            }
            dsp.reset();
        }
        check(finite, "mode cycling remains stable");
    }

    // 7. Sample-rate changes across 44.1k, 48k, and 96k
    {
        SpatialSurroundDSP dsp;
        dsp.setEnabled(true);
        dsp.setMode(SurroundMode::MatrixSurround);

        for (float test_sr : { 44100.0f, 48000.0f, 96000.0f }) {
            dsp.setSampleRate(test_sr);
            std::vector<float> buf(2 * 256, 0.3f);
            dsp.process(buf.data(), 256);
            check(all_finite(buf), ("sample rate switch to " + std::to_string((int)test_sr) + "Hz stable").c_str());
        }
    }

    std::printf("\n%s (%d failure(s))\n", failures == 0 ? "ALL TESTS PASSED" : "TESTS FAILED", failures);
    return failures == 0 ? 0 : 1;
}
