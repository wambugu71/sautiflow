// Verification suite for dsp/spatial_surround_dsp.h
// Build: g++ -std=c++20 -O2 -Wall -I. -Idsp tests/test_surround_dsp.cpp -o tests/test_surround_dsp.exe

#include "../dsp/spatial_surround_dsp.h"
#include <cmath>
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

static double rms_ch(const std::vector<float> &b, int ch, uint32_t start_frame, uint32_t end_frame)
{
    double sum = 0.0;
    uint32_t count = 0;
    for (uint32_t i = start_frame; i < end_frame; ++i) {
        const double v = static_cast<double>(b[2 * i + ch]);
        sum += v * v;
        count++;
    }
    return std::sqrt(sum / std::max(1u, count));
}

int main()
{
    const uint32_t sr = 48000;
    constexpr float kPi = 3.14159265358979323846f;

    // 1. Disabled DSP must be a bit-exact passthrough
    {
        SpatialSurroundDSP dsp;
        dsp.setSampleRate(static_cast<float>(sr));
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
            dsp.setSampleRate(static_cast<float>(sr));
            dsp.setEnabled(true);
            dsp.setMode(modes[m]);

            std::vector<float> buf(2 * 1024);
            float peak_seen = 0.0f;
            bool finite = true;
            for (int blk = 0; blk < static_cast<int>(sr / 1024); ++blk) {
                for (uint32_t i = 0; i < 1024; ++i) {
                    const float t = static_cast<float>(blk * 1024 + i) / sr;
                    buf[2 * i]     = 0.5f * std::sinf(2.0f * kPi * 440.0f * t);
                    buf[2 * i + 1] = 0.5f * std::sinf(2.0f * kPi * 440.0f * t + 0.7f);
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
            check(peak_seen < 4.0f, lvl.c_str());
        }
    }

    // 3. HrtfSource physics: 0 deg exact symmetry, +90 deg ITD/ILD, +110 deg folded rear ITD/ILD
    {
        // 0 deg Center
        sauti::dsp::HrtfSource src0;
        src0.configure(0.0f, 0.0f, 8.75f, 1.0f, static_cast<float>(sr));
        std::vector<float> accL0(sr, 0.0f), accR0(sr, 0.0f);
        int first_l0 = -1, first_r0 = -1;
        for (uint32_t n = 0; n < sr; ++n) {
            float x = (n == 0) ? 1.0f : 0.0f;
            src0.process(x, 1.0f, accL0[n], accR0[n]);
            if (first_l0 < 0 && std::fabs(accL0[n]) > 1e-4f) first_l0 = static_cast<int>(n);
            if (first_r0 < 0 && std::fabs(accR0[n]) > 1e-4f) first_r0 = static_cast<int>(n);
        }
        check(first_l0 == 0 && first_r0 == 0, "HrtfSource(0 deg) has exact 0-sample ITD");

        // 5 kHz sine ILD check on 0 deg
        src0.reset();
        std::vector<float> buf0(2 * 2048, 0.0f);
        for (uint32_t n = 0; n < 2048; ++n) {
            float x = 0.5f * std::sinf(2.0f * kPi * 5000.0f * n / sr);
            src0.process(x, 1.0f, buf0[2 * n], buf0[2 * n + 1]);
        }
        const double ild0 = 20.0 * std::log10((rms_ch(buf0, 1, 512, 2048) + 1e-12) / (rms_ch(buf0, 0, 512, 2048) + 1e-12));
        check(std::fabs(ild0) < 0.01, "HrtfSource(0 deg) has < 0.01 dB L/R ILD");

        // +90 deg hard-right
        sauti::dsp::HrtfSource src90;
        src90.configure(90.0f, 0.0f, 8.75f, 1.0f, static_cast<float>(sr));
        std::vector<float> accL90(sr, 0.0f), accR90(sr, 0.0f);
        for (uint32_t n = 0; n < sr; ++n) {
            float x = (n == 0) ? 1.0f : 0.0f;
            src90.process(x, 1.0f, accL90[n], accR90[n]);
        }
        int first_l90 = -1, first_r90 = -1;
        for (uint32_t n = 0; n < sr; ++n) {
            if (first_r90 < 0 && std::fabs(accR90[n]) > 1e-4f) first_r90 = static_cast<int>(n);
            if (first_l90 < 0 && std::fabs(accL90[n]) > 1e-4f) first_l90 = static_cast<int>(n);
        }
        std::printf("  HrtfSource(+90 deg) arrival R=%d L=%d samples\n", first_r90, first_l90);
        check(first_r90 == 0, "hard-right source reaches right ear immediately");
        check(first_l90 > 25 && first_l90 < 38, "hard-right source left ear delayed by ITD (~31 samples @48k)");

        src90.reset();
        std::vector<float> buf90(2 * 2048, 0.0f);
        for (uint32_t n = 0; n < 2048; ++n) {
            float x = 0.5f * std::sinf(2.0f * kPi * 5000.0f * n / sr);
            src90.process(x, 1.0f, buf90[2 * n], buf90[2 * n + 1]);
        }
        const double ild90 = 20.0 * std::log10((rms_ch(buf90, 1, 512, 2048) + 1e-12) / (rms_ch(buf90, 0, 512, 2048) + 1e-12));
        std::printf("  HrtfSource(+90 deg) 5kHz ILD=%.2f dB\n", ild90);
        check(ild90 > 5.0, "HrtfSource(+90 deg) produces positive near-ear HF ILD (> 5 dB)");

        // +110 deg rear-right (folded Woodworth ITD and positive near-ear ILD)
        sauti::dsp::HrtfSource src110;
        src110.configure(110.0f, 10.0f, 8.75f, 0.8f, static_cast<float>(sr));
        std::vector<float> accL110(sr, 0.0f), accR110(sr, 0.0f);
        for (uint32_t n = 0; n < sr; ++n) {
            float x = (n == 0) ? 1.0f : 0.0f;
            src110.process(x, 1.0f, accL110[n], accR110[n]);
        }
        int first_l110 = -1, first_r110 = -1;
        for (uint32_t n = 0; n < sr; ++n) {
            if (first_r110 < 0 && std::fabs(accR110[n]) > 1e-4f) first_r110 = static_cast<int>(n);
            if (first_l110 < 0 && std::fabs(accL110[n]) > 1e-4f) first_l110 = static_cast<int>(n);
        }
        std::printf("  HrtfSource(+110 deg) arrival R=%d L=%d samples\n", first_r110, first_l110);
        check(first_r110 == 0 && first_l110 < first_l90 && first_l110 >= 22, "HrtfSource(+110 deg) folds ITD past 90 deg");

        src110.reset();
        std::vector<float> buf110(2 * 2048, 0.0f);
        for (uint32_t n = 0; n < 2048; ++n) {
            float x = 0.5f * std::sinf(2.0f * kPi * 5000.0f * n / sr);
            src110.process(x, 1.0f, buf110[2 * n], buf110[2 * n + 1]);
        }
        const double ild110 = 20.0 * std::log10((rms_ch(buf110, 1, 512, 2048) + 1e-12) / (rms_ch(buf110, 0, 512, 2048) + 1e-12));
        std::printf("  HrtfSource(+110 deg) 5kHz ILD=%.2f dB\n", ild110);
        check(ild110 > 5.0, "HrtfSource(+110 deg) maintains positive near-ear HF ILD (not inverted)");
    }

    // 4. Matrix 5.1 pure mono L/R symmetry and flat gain across frequencies
    {
        bool all_sym = true;
        bool all_flat = true;
        for (float f_hz : { 50.0f, 200.0f, 1000.0f, 2000.0f, 5000.0f }) {
            SpatialSurroundDSP dsp;
            dsp.setSampleRate(static_cast<float>(sr));
            dsp.setEnabled(true);
            dsp.setMode(SurroundMode::MatrixSurround);
            dsp.setCenterFocus(0.6f);
            dsp.setSurroundBoost(1.2f);

            const uint32_t N = 8192;
            std::vector<float> buf(2 * N);
            double in_rms_sum = 0.0;
            for (uint32_t i = 0; i < N; ++i) {
                float x = 0.4f * std::sinf(2.0f * kPi * f_hz * i / sr);
                buf[2 * i]     = x;
                buf[2 * i + 1] = x;
                if (i >= 4096) in_rms_sum += static_cast<double>(x) * x;
            }
            const double in_rms = std::sqrt(in_rms_sum / 4096.0);
            dsp.process(buf.data(), N);

            double max_lr = 0.0;
            for (uint32_t i = 4096; i < N; ++i) {
                max_lr = std::max(max_lr, static_cast<double>(std::fabs(buf[2 * i] - buf[2 * i + 1])));
            }
            const double out_l_rms = rms_ch(buf, 0, 4096, N);
            const double gain_db = 20.0 * std::log10((out_l_rms + 1e-12) / (in_rms + 1e-12));
            std::printf("  Matrix 5.1 mono @ %.0f Hz: gain=%+.2f dB, max|L-R|=%.6f\n", f_hz, gain_db, max_lr);
            if (max_lr >= 1e-4) all_sym = false;
            if (std::fabs(gain_db) > 2.5) all_flat = false;
        }
        check(all_sym, "Matrix 5.1 mono keeps exact L/R symmetry (< 1e-4)");
        check(all_flat, "Matrix 5.1 mono gain stays within +/- 2.5 dB across 50 Hz..5 kHz");
    }

    // 5. Binaural Headphone HRTF tonal balance & Speaker Field XTC (zero pan flip)
    {
        bool hp_flat = true;
        for (float f_hz : { 100.0f, 500.0f, 1000.0f, 3000.0f, 5000.0f, 10000.0f }) {
            SpatialSurroundDSP dsp;
            dsp.setSampleRate(static_cast<float>(sr));
            dsp.setEnabled(true);
            dsp.setMode(SurroundMode::BinauralVirtualizer);
            dsp.setBinauralMode(0);
            dsp.setBinauralBoost(0.65f);
            dsp.setBinauralRoomMix(0.0f);

            const uint32_t N = 6144;
            std::vector<float> buf(2 * N);
            double in_rms_sum = 0.0;
            for (uint32_t i = 0; i < N; ++i) {
                float x = 0.4f * std::sinf(2.0f * kPi * f_hz * i / sr);
                buf[2 * i]     = x;
                buf[2 * i + 1] = x;
                if (i >= 3072) in_rms_sum += static_cast<double>(x) * x;
            }
            const double in_rms = std::sqrt(in_rms_sum / 3072.0);
            dsp.process(buf.data(), N);
            const double gain_db = 20.0 * std::log10((rms_ch(buf, 0, 3072, N) + 1e-12) / (in_rms + 1e-12));
            std::printf("  Binaural HP mono @ %.0f Hz: gain=%+.2f dB\n", f_hz, gain_db);
            if (std::fabs(gain_db) > 3.0) hp_flat = false;
        }
        check(hp_flat, "Binaural Headphone HRTF mono response stays within +/- 3.0 dB");

        // Room mix 0 -> 0.5 must not emit stale audio from earlier loud audio
        {
            SpatialSurroundDSP dsp;
            dsp.setSampleRate(static_cast<float>(sr));
            dsp.setEnabled(true);
            dsp.setMode(SurroundMode::BinauralVirtualizer);
            dsp.setBinauralMode(0);
            dsp.setBinauralRoomPreset(2);
            dsp.setBinauralRoomMix(0.0f);

            std::vector<float> loud(2 * 2048, 0.8f);
            dsp.process(loud.data(), 2048);

            // Feed > 60 ms of silence at mix = 0 so continuous buffer clears old audio
            std::vector<float> silence1(2 * 4096, 0.0f);
            dsp.process(silence1.data(), 4096);

            dsp.setBinauralRoomMix(0.5f);
            std::vector<float> silence2(2 * 2048, 0.0f);
            dsp.process(silence2.data(), 2048);
            check(peak(silence2) < 1e-5f, "Binaural Room Mix 0 -> 0.5 emits zero stale buffered audio");
        }

        // Speaker Field mode: hard-Left signal never flips to Right across 250 Hz..5 kHz
        bool speaker_no_flip = true;
        for (float f_hz : { 250.0f, 1000.0f, 1600.0f, 3000.0f, 5000.0f }) {
            SpatialSurroundDSP dsp;
            dsp.setSampleRate(static_cast<float>(sr));
            dsp.setEnabled(true);
            dsp.setMode(SurroundMode::BinauralVirtualizer);
            dsp.setBinauralMode(1);
            dsp.setBinauralSpeakerAngle(1); // Standard 30 deg
            dsp.setBinauralBoost(0.65f);
            dsp.setBinauralShadowCutoff(3500.0f);

            const uint32_t N = 4096;
            std::vector<float> buf(2 * N, 0.0f);
            for (uint32_t i = 0; i < N; ++i) {
                buf[2 * i] = 0.5f * std::sinf(2.0f * kPi * f_hz * i / sr);
            }
            dsp.process(buf.data(), N);
            const double lr_db = 20.0 * std::log10((rms_ch(buf, 0, 2048, N) + 1e-12) / (rms_ch(buf, 1, 2048, N) + 1e-12));
            std::printf("  Binaural Speaker Hard-L @ %.0f Hz: L-R=%+.2f dB\n", f_hz, lr_db);
            if (lr_db <= 3.0) speaker_no_flip = false;
        }
        check(speaker_no_flip, "Binaural Speaker Field preserves L >> R on hard-Left (zero pan flip)");

        // Verify shadowCutoff measurably affects Speaker Field 4 kHz XTC response
        auto run_spk_4k = [&](float cutoff_hz) {
            SpatialSurroundDSP dsp;
            dsp.setSampleRate(static_cast<float>(sr));
            dsp.setEnabled(true);
            dsp.setMode(SurroundMode::BinauralVirtualizer);
            dsp.setBinauralMode(1);
            dsp.setBinauralBoost(0.8f);
            dsp.setBinauralShadowCutoff(cutoff_hz);
            const uint32_t N = 4096;
            std::vector<float> buf(2 * N, 0.0f);
            for (uint32_t i = 0; i < N; ++i) {
                buf[2 * i] = 0.5f * std::sinf(2.0f * kPi * 4000.0f * i / sr);
            }
            dsp.process(buf.data(), N);
            return rms_ch(buf, 1, 2048, N);
        };
        const double r_2k = run_spk_4k(2000.0f);
        const double r_6k = run_spk_4k(6000.0f);
        std::printf("  Binaural Speaker 4kHz R-bleed @ cutoff 2k=%.4f vs 6k=%.4f\n", r_2k, r_6k);
        check(std::fabs(r_6k - r_2k) > 0.02, "Binaural Speaker shadowCutoff knob controls XTC HF bandwidth");
    }

    // 6. 3D Acoustic Stage: Headset vs Speaker difference, unity bypass, mono symmetry, bass anchor
    {
        auto make_stereo = [&](uint32_t N) {
            std::vector<float> b(2 * N);
            for (uint32_t i = 0; i < N; ++i) {
                b[2 * i]     = 0.4f * std::sinf(2.0f * kPi * 1200.0f * i / sr);
                b[2 * i + 1] = 0.15f * std::cosf(2.0f * kPi * 1200.0f * i / sr);
            }
            return b;
        };

        SpatialSurroundDSP dspH, dspS;
        dspH.setSampleRate(static_cast<float>(sr));
        dspH.setEnabled(true);
        dspH.setMode(SurroundMode::AcousticStage);
        dspH.setStageProfile(0); // Headset
        dspH.setStageCancellation(0.8f);

        dspS.setSampleRate(static_cast<float>(sr));
        dspS.setEnabled(true);
        dspS.setMode(SurroundMode::AcousticStage);
        dspS.setStageProfile(1); // Speaker
        dspS.setStageCancellation(0.8f);

        auto bH = make_stereo(4096);
        auto bS = make_stereo(4096);
        dspH.process(bH.data(), 4096);
        dspS.process(bS.data(), 4096);
        double prof_diff = 0.0;
        for (uint32_t i = 2048; i < 4096; ++i) {
            prof_diff = std::max(prof_diff, static_cast<double>(std::fabs(bH[2 * i] - bS[2 * i])));
        }
        check(prof_diff > 0.01, "Acoustic Stage Headset vs Speaker profile produces distinct output");

        // Flat settings (cancel=0, width=1, depth=0, air=0) must be unity
        SpatialSurroundDSP dspFlat;
        dspFlat.setSampleRate(static_cast<float>(sr));
        dspFlat.setEnabled(true);
        dspFlat.setMode(SurroundMode::AcousticStage);
        dspFlat.setStageCancellation(0.0f);
        dspFlat.setStageWidth(1.0f);
        dspFlat.setStageDepth(0.0f);
        dspFlat.setStageAirPresence(0.0f);
        dspFlat.setStageBassAnchorHz(60.0f);

        std::vector<float> bufFlat(2 * 6144);
        double ref_rms_sum = 0.0;
        for (uint32_t i = 0; i < 6144; ++i) {
            float x = 0.4f * std::sinf(2.0f * kPi * 1000.0f * i / sr);
            bufFlat[2 * i]     = x;
            bufFlat[2 * i + 1] = 0.5f * x;
            if (i >= 3072) ref_rms_sum += static_cast<double>(x) * x;
        }
        dspFlat.process(bufFlat.data(), 6144);
        const double ref_rms = std::sqrt(ref_rms_sum / 3072.0);
        const double flat_db = 20.0 * std::log10((rms_ch(bufFlat, 0, 3072, 6144) + 1e-12) / (ref_rms + 1e-12));
        check(std::fabs(flat_db) < 0.2, "Acoustic Stage neutral settings (cancel=0, width=1, depth=0, air=0) preserve unity");

        // Mono symmetry + Bass anchor @ 50 Hz even with Panoramic + high width/cancel
        SpatialSurroundDSP dspMono;
        dspMono.setSampleRate(static_cast<float>(sr));
        dspMono.setEnabled(true);
        dspMono.setMode(SurroundMode::AcousticStage);
        dspMono.setStageProfile(1);
        dspMono.setStageMode(1); // Panoramic
        dspMono.setStageWidth(2.0f);
        dspMono.setStageDepth(0.8f);
        dspMono.setStageCancellation(1.0f);
        dspMono.setStageBassAnchorHz(80.0f);

        std::vector<float> bufMono(2 * 8192);
        double bass_in_sum = 0.0;
        for (uint32_t i = 0; i < 8192; ++i) {
            const float x = 0.4f * std::sinf(2.0f * kPi * 50.0f * i / sr);
            bufMono[2 * i]     = x;
            bufMono[2 * i + 1] = x;
            if (i >= 4096) bass_in_sum += static_cast<double>(x) * x;
        }
        const double bass_in_rms = std::sqrt(bass_in_sum / 4096.0);
        dspMono.process(bufMono.data(), 8192);
        double max_imbalance = 0.0;
        for (uint32_t i = 2048; i < 8192; ++i) {
            max_imbalance = std::max(max_imbalance, static_cast<double>(std::fabs(bufMono[2 * i] - bufMono[2 * i + 1])));
        }
        const double bass_db = 20.0 * std::log10((rms_ch(bufMono, 0, 4096, 8192) + 1e-12) / (bass_in_rms + 1e-12));
        std::printf("  Acoustic Stage 50Hz mono: gain=%+.2f dB, max|L-R|=%.6f\n", bass_db, max_imbalance);
        check(max_imbalance < 1e-4, "3D Acoustic Stage keeps mono content stereo-symmetric");
        check(std::fabs(bass_db) < 1.5, "3D Acoustic Stage Bass Anchor preserves unattenuated 50 Hz bass within +/- 1.5 dB");
    }

    // 7. Mode cycling + reset stability
    {
        SpatialSurroundDSP dsp;
        dsp.setSampleRate(static_cast<float>(sr));
        dsp.setEnabled(true);
        std::vector<float> buf(2 * 256, 0.25f);
        bool finite = true;
        for (int m = 0; m <= 3; ++m) {
            dsp.setMode(static_cast<SurroundMode>(m));
            for (int b = 0; b < 50; ++b) {
                dsp.process(buf.data(), 256);
                if (!all_finite(buf)) finite = false;
            }
            dsp.reset();
        }
        check(finite, "mode cycling remains stable");
    }

    // 8. Sample-rate changes across 44.1k, 48k, 96k, and 192k
    {
        for (SurroundMode m : { SurroundMode::MatrixSurround, SurroundMode::BinauralVirtualizer, SurroundMode::AcousticStage }) {
            SpatialSurroundDSP dsp;
            dsp.setEnabled(true);
            dsp.setMode(m);
            bool sr_ok = true;
            for (float test_sr : { 44100.0f, 48000.0f, 96000.0f, 192000.0f }) {
                dsp.setSampleRate(test_sr);
                std::vector<float> buf(2 * 512, 0.3f);
                dsp.process(buf.data(), 512);
                if (!all_finite(buf)) sr_ok = false;
            }
            check(sr_ok, "sample rate switches 44.1k/48k/96k/192k remain finite");
        }
    }

    std::printf("\n%s (%d failure(s))\n", failures == 0 ? "ALL TESTS PASSED" : "TESTS FAILED", failures);
    return failures == 0 ? 0 : 1;
}
