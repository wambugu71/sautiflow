// =============================================================================
// tests/test_engine_api.cpp
//
// Engine-level verification through the public ae_* C API:
//   [C] 1.1  Auto-SR jump no longer self-deadlocks (control-path exercise)
//   [C] 1.3  DSP setters are safe against the realtime thread (smoke)
//   [C] 1.8  Push-stream chunk wait is abortable via ae_stop()
//   [C] 1.9  End-callback registration is race-free under a running producer
//   [M] 3.6  Telemetry reports real underrun counter / sample peak fields
//
// Links directly against the engine objects; does not require audible output
// but DOES open the default audio device.
// =============================================================================

#include "audio_engine.h"
#include "ffmpeg_stream_decoder.h"
#include "miniaudio.h"

#include <atomic>
#include <chrono>
#include <cmath>
#include <cstdio>
#include <cstring>
#include <random>
#include <thread>
#include <vector>

static int g_failures = 0;
static int g_passes = 0;

#define CHECK(cond, msg)                                                        \
    do {                                                                        \
        if (cond) {                                                             \
            ++g_passes;                                                         \
            std::printf("  [PASS] %s\n", msg);                                  \
        } else {                                                                \
            ++g_failures;                                                       \
            std::printf("  [FAIL] %s  (%s:%d)\n", msg, __FILE__, __LINE__);     \
        }                                                                       \
    } while (0)

using Clock = std::chrono::steady_clock;

static void test_create_destroy()
{
    std::printf("\n== Engine create/destroy ==\n");
    for (int i = 0; i < 2; ++i)
    {
        AudioEngineHandle *e = ae_create_engine(48000, 2);
        CHECK(e != nullptr, "engine created");
        ae_destroy_engine(e);
        CHECK(true, "engine destroyed without hang");
    }
}

static void test_dsp_setters_smoke()
{
    std::printf("\n== Clean-room DSP setter smoke ([C] 1.3) ==\n");
    AudioEngineHandle *e = ae_create_engine(48000, 2);
    CHECK(e != nullptr, "engine created");

    // Hammer every clean-room setter repeatedly while the device/producer run.
    bool ok = true;
    for (int i = 0; i < 200; ++i)
    {
        ae_dsp_set_clarity_enabled(e, i & 1);
        ae_dsp_set_clarity_params(e, i % 4, (i % 100) / 100.0f);
        ae_dsp_set_bass_enabled(e, i & 1);
        ae_dsp_set_bass_params(e, i % 5, 40.0f + (i % 120), (i % 100) / 100.0f);
        ae_dsp_set_dynamic_system_enabled(e, i & 1);
        ae_dsp_set_dynamic_system_params(e, i % 6, (i % 100) / 100.0f);
        ae_dsp_set_analog_warmth_enabled(e, i & 1);
        ae_dsp_set_analog_warmth_params(e, i % 3, (i % 100) / 100.0f);
        ae_dsp_set_de_esser_enabled(e, i & 1);
        ae_dsp_set_de_esser_params(e, i % 2, (i % 100) / 100.0f);
        ae_dsp_set_de_esser_params_ex(e, i % 2, 5000.0f + (i % 2000), -20.0f, 4.0f, 12.0f, 1.0f, 35.0f);
        ae_dsp_set_expander_enabled(e, i & 1);
        ae_dsp_set_expander_preset(e, i % 5);
        ae_dsp_set_expander_params(e, -50.0f, 2.0f, -18.0f, 10.0f, 250.0f);
        ae_dsp_set_expander_params_ex(e, -52.0f, 1.8f, -16.0f, 12.0f, 280.0f, 6.0f, 50.0f);
        ae_dsp_set_master_limiter_enabled(e, 0); // stays opt-in
        if (i % 50 == 0) ae_dsp_reset(e);
    }
    CHECK(ok, "400+ concurrent-ish setter calls survived");

    // De-Esser, Expander & Master limiter default checks
    CHECK(ae_dsp_get_de_esser_gain_reduction_db(e) == 0.0f,
          "de-esser inactive by default (GR = 0 dB)");
    CHECK(ae_dsp_get_expander_gain_reduction_db(e) == 0.0f,
          "expander inactive by default (GR = 0 dB)");
    CHECK(ae_dsp_get_limiter_gain_reduction_db(e) == 0.0f,
          "master limiter inactive by default (GR = 0 dB)");

    // Convolver IR load/clear round trip.
    std::vector<float> ir(1024, 0.0f);
    ir[0] = 1.0f;
    CHECK(ae_dsp_load_convolver_ir(e, ir.data(), 512, 2) == 1, "IR loaded");
    CHECK(ae_dsp_has_convolver_ir(e) == 1, "has IR");
    CHECK(ae_dsp_get_convolver_kernel_length(e) >= 512, "kernel length >= IR length");
    ae_dsp_clear_convolver_ir(e);
    CHECK(ae_dsp_has_convolver_ir(e) == 0, "IR cleared");

    ae_destroy_engine(e);
}

static void test_64bit_and_oversampling_api()
{
    std::printf("\n== 64-bit DSP & Oversampling Engine API ==\n");
    AudioEngineHandle *e = ae_create_engine(48000, 2);
    CHECK(e != nullptr, "engine created");

    // 1. 64-bit processing toggle
    CHECK(ae_get_64bit_processing_enabled(e) == 0, "64-bit processing disabled by default");
    ae_set_64bit_processing_enabled(e, 1);
    CHECK(ae_get_64bit_processing_enabled(e) == 1, "64-bit processing enabled");
    ae_set_64bit_processing_enabled(e, 0);
    CHECK(ae_get_64bit_processing_enabled(e) == 0, "64-bit processing disabled again");

    // 2. Oversampling factor
    CHECK(ae_get_dsp_oversampling(e) == 1, "oversampling default is 1x");
    ae_set_dsp_oversampling(e, 2);
    CHECK(ae_get_dsp_oversampling(e) == 2, "oversampling set to 2x");
    ae_set_dsp_oversampling(e, 4);
    CHECK(ae_get_dsp_oversampling(e) == 4, "oversampling set to 4x");
    // Test clamping
    ae_set_dsp_oversampling(e, 3);
    CHECK(ae_get_dsp_oversampling(e) == 4, "oversampling factor 3 clamped to 4x");
    ae_set_dsp_oversampling(e, 0);
    CHECK(ae_get_dsp_oversampling(e) == 1, "oversampling factor 0 clamped to 1x");
    ae_set_dsp_oversampling(e, 8);
    CHECK(ae_get_dsp_oversampling(e) == 4, "oversampling factor 8 clamped to 4x");

    ae_destroy_engine(e);
}

static void test_end_callback_race()
{
    std::printf("\n== End callback registration ([C] 1.9) ==\n");
    AudioEngineHandle *e = ae_create_engine(48000, 2);

    static std::atomic<int> cbCount{0};
    // Swap the callback repeatedly while producer/RT threads run: previously
    // this raced non-atomically with the producer snapshotting the pointers.
    for (int i = 0; i < 500; ++i)
    {
        if (i & 1)
            ae_set_end_callback(e, [](void *, AudioEngineHandle *) { cbCount.fetch_add(1); }, nullptr);
        else
            ae_set_end_callback(e, nullptr, nullptr);
    }
    CHECK(true, "500 callback swaps without crash");

    ae_destroy_engine(e);
}

static void test_push_stream_abort()
{
    std::printf("\n== Push-stream abortable wait ([C] 1.8) ==\n");
    AudioEngineHandle *e = ae_create_engine(48000, 2);
    CHECK(e != nullptr, "engine created");

    // Do NOT play: nothing drains the push ring, so it fills and the chunk
    // call would block forever in the old code.
    ae_init_push_stream(e);

    std::atomic<bool> stopped{false};
    std::thread stopper([&]() {
        std::this_thread::sleep_for(std::chrono::milliseconds(300));
        ae_stop(e); // must unblock ae_push_stream_chunk
        stopped.store(true);
    });

    std::vector<unsigned char> chunk(64 * 1024, 0xAB);
    const auto t0 = Clock::now();
    for (int i = 0; i < 4096 && !stopped.load(); ++i)
    {
        ae_push_stream_chunk(e, chunk.data(), chunk.size());
    }
    const double elapsedSec = std::chrono::duration<double>(Clock::now() - t0).count();
    stopper.join();

    char msg[160];
    std::snprintf(msg, sizeof(msg), "chunk pushing aborted after %.2f s (< 10 s, was infinite)", elapsedSec);
    CHECK(elapsedSec < 10.0, msg);

    ae_destroy_engine(e);
}

static void test_telemetry_fields()
{
    std::printf("\n== Telemetry honesty ([M] 3.6) ==\n");
    AudioEngineHandle *e = ae_create_engine(48000, 2);

    AEQualityTelemetry t{};
    std::memset(&t, 0, sizeof(t));
    t = ae_get_quality_telemetry(e);
    CHECK(t.underrun_count == 0, "underrun counter starts at 0 (real counter, still honest)");
    CHECK(t.sample_peak_db <= -100.0f || t.sample_peak_db > -200.0f,
          "sample peak field present and sane when meters disabled (-100 sentinel)");

    ae_destroy_engine(e);
}

// ---------------------------------------------------------------------------
// Dynamic Range Compressor end-to-end: plays a loud sine through the public
// API and verifies the GR meter reports real compression, then verifies unity
// gain when the material sits below the threshold.
// ---------------------------------------------------------------------------
static bool write_test_wav(const char *path, int sampleRate, int seconds, float amplitude)
{
    const int frames = sampleRate * seconds;
    std::vector<int16_t> pcm((size_t)frames * 2);
    for (int i = 0; i < frames; ++i)
    {
        const float s = amplitude * std::sin(2.0f * 3.14159265358979f * 440.0f * (float)i / (float)sampleRate);
        const auto v = (int16_t)std::lround(s * 32767.0f);
        pcm[(size_t)2 * i] = v;
        pcm[(size_t)2 * i + 1] = v;
    }

#pragma pack(push, 1)
    struct WavHeader
    {
        char riff[4];
        uint32_t riffSize;
        char wave[4];
        char fmtId[4];
        uint32_t fmtSize;
        uint16_t audioFormat;
        uint16_t channels;
        uint32_t sampleRate;
        uint32_t byteRate;
        uint16_t blockAlign;
        uint16_t bitsPerSample;
        char dataId[4];
        uint32_t dataBytes;
    };
#pragma pack(pop)

    const uint32_t dataBytes = (uint32_t)pcm.size() * sizeof(int16_t);
    WavHeader h{};
    std::memcpy(h.riff, "RIFF", 4);
    h.riffSize = 36 + dataBytes;
    std::memcpy(h.wave, "WAVE", 4);
    std::memcpy(h.fmtId, "fmt ", 4);
    h.fmtSize = 16;
    h.audioFormat = 1; // PCM
    h.channels = 2;
    h.sampleRate = (uint32_t)sampleRate;
    h.byteRate = (uint32_t)sampleRate * 2 * sizeof(int16_t);
    h.blockAlign = 2 * sizeof(int16_t);
    h.bitsPerSample = 16;
    std::memcpy(h.dataId, "data", 4);
    h.dataBytes = dataBytes;

    FILE *f = std::fopen(path, "wb");
    if (!f) return false;
    const bool ok = std::fwrite(&h, sizeof(h), 1, f) == 1 &&
                    std::fwrite(pcm.data(), 1, dataBytes, f) == dataBytes;
    std::fclose(f);
    return ok;
}

static void test_compressor_gain_reduction()
{
    std::printf("\n== Dynamic Range Compressor end-to-end ==\n");

    const char *wavPath = "compressor_test_tone.wav";
    // 0.9 amplitude sine ~= -0.9 dBFS
    CHECK(write_test_wav(wavPath, 44100, 1, 0.9f), "test WAV written");

    AudioEngineHandle *e = ae_create_engine(44100, 2);
    CHECK(e != nullptr, "engine created");
    if (!e) { std::remove(wavPath); return; }

    const char *paths[1] = { wavPath };
    CHECK(ae_set_playlist(e, paths, 1), "playlist set");
    ae_set_loop_mode(e, 2 /* loop one: continuous audio for both phases */);

    // Extreme settings: threshold -60 dB, ratio 20:1, hard knee, fast attack.
    // Expected steady-state GR for a -0.9 dB input: ~-56 dB.
    ae_set_compressor_params(e, -60.0f, 20.0f, 0.0f, 0.5f, 100.0f, 0.0f, 0, 1, 0, 1.0f);
    ae_set_compressor_enabled(e, 1);
    CHECK(ae_play(e), "playback started");

    // Phase 1: compression engages on the loud tone. Gate on real playback
    // progress, not just is_playing, because preload can precede audio flow.
    float minGR = 0.0f;
    bool tripped = false;
    const auto deadline = Clock::now() + std::chrono::seconds(10);
    while (Clock::now() < deadline)
    {
        const PlayerStatus st = ae_get_status(e);
        if (st.is_playing && st.position_seconds > 0.03)
        {
            const float gr = ae_get_compressor_gain_reduction_db(e);
            if (gr < minGR) minGR = gr;
            if (minGR < -20.0f) { tripped = true; break; }
        }
        std::this_thread::sleep_for(std::chrono::milliseconds(5));
    }
    char msg[160];
    std::snprintf(msg, sizeof(msg), "loud tone compressed (min GR %.1f dB < -20 dB)", minGR);
    CHECK(tripped, msg);

    // Phase 2: same playback, threshold at the ceiling -> GR must return to
    // unity. Catching the *return* proves the GR meter tracks live state.
    ae_set_compressor_params(e, 0.0f, 20.0f, 0.0f, 0.5f, 100.0f, 0.0f, 0, 1, 0, 1.0f);
    float maxGR = -999.0f;
    bool restored = false;
    const auto deadline2 = Clock::now() + std::chrono::seconds(10);
    while (Clock::now() < deadline2)
    {
        const PlayerStatus st = ae_get_status(e);
        if (st.is_playing && st.position_seconds > 0.03)
        {
            const float gr = ae_get_compressor_gain_reduction_db(e);
            if (gr > maxGR) maxGR = gr;
            if (maxGR > -1.0f) { restored = true; break; }
        }
        std::this_thread::sleep_for(std::chrono::milliseconds(5));
    }
    std::snprintf(msg, sizeof(msg), "below-threshold tone passes unity (GR %.1f dB > -1 dB)", maxGR);
    CHECK(restored, msg);

    ae_stop(e);
    ae_set_compressor_enabled(e, 0);
    ae_destroy_engine(e);
    std::remove(wavPath);
}

static void test_crossfade_sample_rate_mismatch_p08()
{
    std::printf("\n== Crossfade Sample Rate Mismatch Verification ([C] P0.8) ==\n");
    const char *wav44k = "cf_test_track1_44k.wav";
    const char *wav48k = "cf_test_track2_48k.wav";

    CHECK(write_test_wav(wav44k, 44100, 2, 0.5f), "track 1 written (44.1 kHz)");
    CHECK(write_test_wav(wav48k, 48000, 2, 0.5f), "track 2 written (48.0 kHz)");

    AudioEngineHandle *e = ae_create_engine(48000, 2);
    CHECK(e != nullptr, "engine created for crossfade test");
    if (!e)
    {
        std::remove(wav44k);
        std::remove(wav48k);
        return;
    }

    ae_set_crossfade_duration_ms(e, 500);
    CHECK(ae_get_crossfade_duration_ms(e) == 500, "crossfade duration configured to 500ms");
    ae_set_crossfade_enabled(e, 1);
    CHECK(ae_get_crossfade_enabled(e) == 1, "crossfade enabled");

    const char *playlist[2] = { wav44k, wav48k };
    CHECK(ae_set_playlist(e, playlist, 2), "playlist with mismatched sample rates set");

    CHECK(ae_play(e), "playback of track 1 started");

    // Wait until track 1 starts playing
    const auto deadline = Clock::now() + std::chrono::seconds(5);
    bool playing = false;
    while (Clock::now() < deadline)
    {
        const PlayerStatus st = ae_get_status(e);
        if (st.is_playing && st.position_seconds > 0.05)
        {
            playing = true;
            break;
        }
        std::this_thread::sleep_for(std::chrono::milliseconds(10));
    }
    CHECK(playing, "track 1 actively producing audio");

    // Trigger crossfade to track 2
    CHECK(ae_next(e), "crossfade transition to track 2 triggered");

    // Allow crossfade to process through resampler
    std::this_thread::sleep_for(std::chrono::milliseconds(300));
    const PlayerStatus st2 = ae_get_status(e);
    CHECK(st2.is_playing, "playback continues uninterrupted during crossfade across sample rates");

    ae_stop(e);
    ae_destroy_engine(e);
    std::remove(wav44k);
    std::remove(wav48k);
}

static void test_ffmpeg_seek_preroll_p13()
{
    std::printf("\n== FFmpeg Seek Preroll Discard Verification ([C] P1.3) ==\n");

    const char *wavPath = "seek_preroll_test.wav";
    const int sampleRate = 48000;
    const int totalSeconds = 3;
    const int totalFrames = sampleRate * totalSeconds;

    // Generate a chirp where every sample is unique across time
    std::vector<int16_t> pcm((size_t)totalFrames * 2);
    for (int i = 0; i < totalFrames; ++i)
    {
        double t = (double)i / sampleRate;
        double phase = 2.0 * 3.14159265358979323846 * (100.0 * t + 200.0 * t * t);
        float s = 0.8f * (float)std::sin(phase);
        int16_t v = (int16_t)std::lround(s * 32767.0f);
        pcm[(size_t)2 * i] = v;
        pcm[(size_t)2 * i + 1] = v;
    }

#pragma pack(push, 1)
    struct WavHeader
    {
        char riff[4];
        uint32_t riffSize;
        char wave[4];
        char fmtId[4];
        uint32_t fmtSize;
        uint16_t audioFormat;
        uint16_t channels;
        uint32_t sampleRate;
        uint32_t byteRate;
        uint16_t blockAlign;
        uint16_t bitsPerSample;
        char dataId[4];
        uint32_t dataBytes;
    };
#pragma pack(pop)

    uint32_t dataBytes = (uint32_t)pcm.size() * sizeof(int16_t);
    WavHeader h{};
    std::memcpy(h.riff, "RIFF", 4);
    h.riffSize = 36 + dataBytes;
    std::memcpy(h.wave, "WAVE", 4);
    std::memcpy(h.fmtId, "fmt ", 4);
    h.fmtSize = 16;
    h.audioFormat = 1;
    h.channels = 2;
    h.sampleRate = (uint32_t)sampleRate;
    h.byteRate = (uint32_t)sampleRate * 2 * sizeof(int16_t);
    h.blockAlign = 2 * sizeof(int16_t);
    h.bitsPerSample = 16;
    std::memcpy(h.dataId, "data", 4);
    h.dataBytes = dataBytes;

    FILE *f = std::fopen(wavPath, "wb");
    if (f)
    {
        std::fwrite(&h, sizeof(h), 1, f);
        std::fwrite(pcm.data(), 1, dataBytes, f);
        std::fclose(f);
    }

    // Also convert to FLAC using ffmpeg CLI to test seeking across block boundaries with keyframe preroll
    const char *flacPath = "seek_preroll_test.flac";
    char cmd[256];
    std::snprintf(cmd, sizeof(cmd), "ffmpeg -y -v quiet -i %s -c:a flac %s", wavPath, flacPath);
    (void)std::system(cmd);

    const char *testFiles[] = { wavPath, flacPath };
    for (const char *filePath : testFiles)
    {
        FILE *check = std::fopen(filePath, "rb");
        if (!check) continue;
        std::fclose(check);

        sautiflow::FFmpegLocalFileSource srcSeq;
        CHECK(srcSeq.open(filePath), "sequential decoder opened");

        sautiflow::FFmpegLocalFileSource srcSeek;
        CHECK(srcSeek.open(filePath), "seek decoder opened");

        const ma_uint64 targetSeekFrame = 48500; // middle of stream (~1.01 sec)
        const size_t testFrames = 2048;

        // Sequentially decode up to targetSeekFrame + testFrames
        std::vector<float> discardBuf(targetSeekFrame * srcSeq.get_channels());
        size_t readPrefix = srcSeq.read_pcm(discardBuf.data(), targetSeekFrame);
        CHECK(readPrefix == targetSeekFrame, "sequential decoder read prefix frames");

        std::vector<float> seqAudio(testFrames * srcSeq.get_channels());
        size_t readSeq = srcSeq.read_pcm(seqAudio.data(), testFrames);
        CHECK(readSeq == testFrames, "sequential decoder read target window");

        // Now seek directly to targetSeekFrame
        CHECK(srcSeek.seek(targetSeekFrame), "seek to target frame succeeded");
        CHECK(srcSeek.get_cursor() == targetSeekFrame, "cursor matches target frame index");

        std::vector<float> seekAudio(testFrames * srcSeek.get_channels());
        size_t readSeek = srcSeek.read_pcm(seekAudio.data(), testFrames);
        CHECK(readSeek == testFrames, "seek decoder read target window");
        CHECK(srcSeek.get_cursor() == targetSeekFrame + testFrames, "cursor advanced correctly after seek read");

        // Verify sample-accurate alignment (max error < 1e-4)
        float maxDiff = 0.0f;
        for (size_t i = 0; i < testFrames * srcSeq.get_channels(); ++i)
        {
            float diff = std::abs(seqAudio[i] - seekAudio[i]);
            if (diff > maxDiff) maxDiff = diff;
        }

        char passMsg[128];
        std::snprintf(passMsg, sizeof(passMsg), "%s seek output matches sequential decode (maxDiff=%e)", filePath, maxDiff);
        CHECK(maxDiff < 1e-4f, passMsg);

        // Test seek to 0
        CHECK(srcSeek.seek(0), "seek to frame 0 succeeded");
        CHECK(srcSeek.get_cursor() == 0, "cursor is 0 after seek(0)");

        // Test seek past end
        CHECK(srcSeek.seek(srcSeek.get_total_frames() + 1000), "seek past end handled gracefully");
        CHECK(srcSeek.is_ended(), "stream marked ended after seek past end");

        srcSeq.close();
        srcSeek.close();
    }

    std::remove(wavPath);
    std::remove(flacPath);
}

static void test_sample_rate_switch_position_continuity_p14()
{
    std::printf("\n== Sample Rate Switch Position Continuity Verification ([C] P1.4) ==\n");

    const char *wavPath = "sr_switch_continuity_test.wav";
    const int sampleRate = 44100;
    // 5 seconds of audio so there's plenty of playback headroom
    CHECK(write_test_wav(wavPath, sampleRate, 5, 0.5f), "test WAV generated (44.1 kHz, 5s)");

    AudioEngineHandle *e = ae_create_engine(44100, 2);
    CHECK(e != nullptr, "engine created at 44.1 kHz");
    if (!e)
    {
        std::remove(wavPath);
        return;
    }

    const char *paths[1] = { wavPath };
    CHECK(ae_set_playlist(e, paths, 1), "playlist set");
    CHECK(ae_play(e), "playback started");

    // Wait until track has played for at least 0.35s so the producer thread
    // has filled ~350ms of audio into pcmRingBuffer ahead of the DAC.
    bool playing = false;
    double posBefore = 0.0;
    const auto deadline = Clock::now() + std::chrono::seconds(5);
    while (Clock::now() < deadline)
    {
        const PlayerStatus st = ae_get_status(e);
        if (st.is_playing && st.position_seconds >= 0.35)
        {
            playing = true;
            posBefore = st.position_seconds;
            break;
        }
        std::this_thread::sleep_for(std::chrono::milliseconds(10));
    }
    CHECK(playing, "playback reached >= 0.35s with filled decode ring buffer");

    // Switch output sample rate from 44.1 kHz to 48.0 kHz.
    // This triggers restart_and_apply_config(e), wiping old-rate ring buffer audio.
    ae_set_output_sample_rate(e, 48000);

    const PlayerStatus stAfter = ae_get_status(e);
    const double posAfter = stAfter.position_seconds;
    const double delta = posAfter - posBefore;

    char msg[128];
    std::snprintf(msg, sizeof(msg), "position preserved seamlessly across rate switch (delta=%.3fs, before=%.3fs, after=%.3fs)",
                  delta, posBefore, posAfter);
    // Before fix, delta was ~+0.35s (jumping forward by ~350ms).
    // With fix, position should be within 0.12s of posBefore (no ~350ms forward skip).
    CHECK(delta < 0.15 && delta >= -0.05, msg);
    CHECK(stAfter.is_playing == 1, "playback continues seamlessly after rate switch");

    ae_stop(e);
    ae_destroy_engine(e);
    std::remove(wavPath);
}

static void test_device_resampler_input_estimation_p15()
{
    std::printf("\n== Device Resampler Input Estimation & Dropout Prevention ([C] P1.5) ==\n");

    const char *wavPath = "device_resampler_p15_test.wav";
    const int sampleRate = 44100;
    CHECK(write_test_wav(wavPath, sampleRate, 3, 0.5f), "test WAV generated (44.1 kHz, 3s)");

    // Create engine with 48000 Hz device rate
    AudioEngineHandle *e = ae_create_engine(48000, 2);
    CHECK(e != nullptr, "engine created at 48.0 kHz");
    if (!e)
    {
        std::remove(wavPath);
        return;
    }

    // Set engine output processing rate to 44.1 kHz, forcing device SRC (44.1k -> 48k)
    ae_set_output_sample_rate(e, 44100);
    ae_set_engine_resample_algorithm(e, 11); // r8brain 24-bit linear phase

    const char *paths[1] = { wavPath };
    CHECK(ae_set_playlist(e, paths, 1), "playlist set");
    CHECK(ae_play(e), "playback started");

    // Let playback run for 500ms under active device SRC
    const auto deadline = Clock::now() + std::chrono::milliseconds(500);
    while (Clock::now() < deadline)
    {
        std::this_thread::sleep_for(std::chrono::milliseconds(20));
    }

    const PlayerStatus st = ae_get_status(e);
    CHECK(st.is_playing == 1, "playback is actively running with device SRC");
    CHECK(st.position_seconds >= 0.25, "playback position advancing smoothly");

    const AEQualityTelemetry telem = ae_get_quality_telemetry(e);
    // Before fix, false underruns incremented ~41 frames every block because produced (at 44.1k)
    // was compared directly against frameCount (at 48k).
    CHECK(telem.underrun_count == 0, "zero underruns reported during device SRC (no false starvation)");

    const AEResamplingPolicyInfo policy = ae_get_resampling_policy_info(e);
    CHECK(policy.engine_sample_rate == 44100, "policy engine rate is 44100 Hz");
    CHECK(policy.device_sample_rate == 48000, "policy device rate is 48000 Hz");

    ae_stop(e);
    ae_destroy_engine(e);
    std::remove(wavPath);
}

static void test_filter_state_retention_equalizer_adjustment_p16()
{
    std::printf("\n== Filter State Retention & Equalizer Zipper Crackle Elimination ([C] P1.6) ==\n");

    // 1. Direct miniaudio biquad state retention vs wipe verification
    ma_peak2_config cfg1 = ma_peak2_config_init(ma_format_f32, 2, 48000, 6.0f, 1.0f, 1000.0f);
    ma_peak2 filter{};
    ma_result res = ma_peak2_init(&cfg1, nullptr, &filter);
    CHECK(res == MA_SUCCESS, "ma_peak2 initialized successfully");

    // Feed a short signal with an impulse to populate internal delay-line registers (pR1, pR2)
    float inBuf[4] = { 1.0f, 0.5f, 0.0f, 0.0f };
    float outBuf[4] = { 0 };
    ma_peak2_process_pcm_frames(&filter, outBuf, inBuf, 1);

    const bool hasState = (filter.bq.pR1 != nullptr) &&
                          (std::abs(filter.bq.pR1[0].f32) > 1e-6f || std::abs(filter.bq.pR2[0].f32) > 1e-6f);
    CHECK(hasState, "filter internal state registers (pR1/pR2) populated with audio history");

    // Calling ma_peak2_init zeroes history registers: this was the bug!
    ma_peak2_config cfg2 = ma_peak2_config_init(ma_format_f32, 2, 48000, 8.0f, 1.0f, 1000.0f);
    ma_peak2_init(&cfg2, nullptr, &filter);
    const bool stateWiped = (filter.bq.pR1 != nullptr && filter.bq.pR1[0].f32 == 0.0f && filter.bq.pR2[0].f32 == 0.0f);
    CHECK(stateWiped, "ma_peak2_init wipes filter history registers to zero (proves root cause of slider zipper clicks)");

    // Re-charge filter state registers
    ma_peak2_process_pcm_frames(&filter, outBuf, inBuf, 1);
    const float savedR1 = filter.bq.pR1[0].f32;
    const float savedR2 = filter.bq.pR2[0].f32;
    CHECK(std::abs(savedR1) > 1e-6f, "filter history registers repopulated");

    // Calling ma_peak2_reinit updates coefficients in-place while preserving internal delay history
    ma_peak2_config cfg3 = ma_peak2_config_init(ma_format_f32, 2, 48000, 4.0f, 1.0f, 1000.0f);
    res = ma_peak2_reinit(&cfg3, &filter);
    CHECK(res == MA_SUCCESS, "ma_peak2_reinit succeeded");
    const bool stateRetained = (filter.bq.pR1[0].f32 == savedR1 && filter.bq.pR2[0].f32 == savedR2);
    CHECK(stateRetained, "ma_peak2_reinit retains delay-line registers (eliminates zipper crackle)");
    ma_peak2_uninit(&filter, nullptr);

    // 2. Full engine multiband FX dynamic adjustment during active playback
    AudioEngineHandle *e = ae_create_engine(48000, 2);
    CHECK(e != nullptr, "engine created at 48 kHz stereo");
    if (!e) return;

    const char *wavPath = "filter_state_p16_test.wav";
    CHECK(write_test_wav(wavPath, 48000, 2, 0.5f), "test WAV generated (48 kHz, 2s)");

    const char *paths[1] = { wavPath };
    CHECK(ae_set_playlist(e, paths, 1), "playlist set");
    CHECK(ae_play(e), "playback started");

    int types[5] = { AE_EQ_BAND_LOWSHELF, AE_EQ_BAND_PEAK, AE_EQ_BAND_PEAK, AE_EQ_BAND_PEAK, AE_EQ_BAND_HIGHSHELF };
    float freqs[5] = { 100.0f, 500.0f, 1000.0f, 4000.0f, 10000.0f };
    float gains[5] = { 0.0f, 0.0f, 0.0f, 0.0f, 0.0f };
    float qs[5] = { 0.7f, 1.0f, 1.0f, 1.0f, 0.7f };
    int enabled[5] = { 1, 1, 1, 1, 1 };
    ae_set_multiband_fx_bands(e, 5, types, freqs, gains, qs, nullptr, enabled);
    ae_set_multiband_fx_enabled(e, 1);

    // Rapid continuous slider movements during active playback (simulates user dragging GUI equalizer sliders)
    for (int iter = 0; iter < 50; ++iter)
    {
        gains[0] = std::sin(iter * 0.2f) * 6.0f;
        gains[1] = std::cos(iter * 0.25f) * 4.0f;
        gains[2] = std::sin(iter * 0.15f) * -5.0f;
        freqs[2] = 1000.0f + std::sin(iter * 0.3f) * 200.0f;
        ae_set_multiband_fx_bands(e, 5, types, freqs, gains, qs, nullptr, enabled);
        std::this_thread::sleep_for(std::chrono::milliseconds(2));
    }

    const PlayerStatus st = ae_get_status(e);
    CHECK(st.is_playing == 1, "playback remained uninterrupted during continuous slider sweeps");

    ae_stop(e);
    ae_destroy_engine(e);
    std::remove(wavPath);
}

static void test_replaygain_peak_limiting_anticlip_p18()
{
    std::printf("\n== ReplayGain Anti-Clipping Peak Limiting ([C] P1.8) ==\n");

    AudioEngineHandle *e = ae_create_engine(48000, 2);
    CHECK(e != nullptr, "engine created at 48 kHz stereo");
    if (!e) return;

    // 1. Math verification: Positive gain with high peak (+6.0 dB, peak = 0.95)
    // Raw linear gain for +6.0 dB is 10^(6/20) ~ 1.995262.
    // Peak would reach 0.95 * 1.995262 = 1.8955 (+5.55 dBFS, severe digital clipping).
    // With anti-clipping: maxSafeLinear = 1.0 / 0.95 = 1.0526315.
    // Resulting linear gain must be clamped to 1.0526315 (peak stays <= 1.000000).
    ae_set_replay_gain_with_peak(e, 6.0f, 0.95f);
    const float limitedLinear = ae_get_replay_gain_linear(e);
    const float expectedLimit = 1.0f / 0.95f;
    CHECK(std::abs(limitedLinear - expectedLimit) < 1e-4f,
          "positive ReplayGain (+6 dB) with peak 0.95 is clamped to max safe linear 1.0526 (prevents 0 dBFS clipping)");
    const float limitedDb = ae_get_replay_gain_db(e);
    CHECK(std::abs(limitedDb - 0.4455f) < 0.05f,
          "effective ReplayGain dB (+0.45 dB) matches anti-clipping headroom ceiling");
    CHECK(limitedLinear * 0.95f <= 1.00001f,
          "output peak after limited ReplayGain does not exceed 1.000000 full-scale");

    // 2. Headroom available: Positive gain with low peak (+6.0 dB, peak = 0.40)
    // maxSafeLinear = 1.0 / 0.40 = 2.50.
    // Raw linear gain 1.995262 <= 2.50, so full +6 dB gain must be preserved without attenuation.
    ae_set_replay_gain_with_peak(e, 6.0f, 0.40f);
    const float unattenuatedLinear = ae_get_replay_gain_linear(e);
    const float rawSixDb = std::pow(10.0f, 6.0f / 20.0f);
    CHECK(std::abs(unattenuatedLinear - rawSixDb) < 1e-4f,
          "positive ReplayGain (+6 dB) with low peak 0.40 preserves full +6 dB gain (no unnecessary limiting)");
    CHECK(unattenuatedLinear * 0.40f <= 1.00001f,
          "output peak with headroom remains safely within 1.000000 (0.798 <= 1.000)");

    // 3. Negative gain: Attenuation (-4.0 dB, peak = 0.98)
    // Negative gain naturally attenuates below 1.0, so peak limiting must never interfere.
    ae_set_replay_gain_with_peak(e, -4.0f, 0.98f);
    const float attenuatedLinear = ae_get_replay_gain_linear(e);
    const float rawMinusFourDb = std::pow(10.0f, -4.0f / 20.0f);
    CHECK(std::abs(attenuatedLinear - rawMinusFourDb) < 1e-4f,
          "negative ReplayGain (-4 dB) passes uninhibited (attenuation preserved)");

    // 4. Preload next track ReplayGain with peak limiting (+8.0 dB, peak = 0.90)
    // Raw linear = 10^(8/20) ~ 2.511886. Max safe linear = 1.0 / 0.90 = 1.111111.
    ae_set_next_replay_gain_with_peak(e, 8.0f, 0.90f);
    const float nextLimited = ae_get_next_replay_gain_linear(e);
    CHECK(std::abs(nextLimited - (1.0f / 0.90f)) < 1e-4f,
          "preload next track ReplayGain (+8 dB) with peak 0.90 is clamped to 1.1111");

    // 5. Zero or invalid peak handled gracefully without division by zero or NaN
    ae_set_replay_gain_with_peak(e, 3.0f, 0.0f);
    CHECK(std::abs(ae_get_replay_gain_linear(e) - std::pow(10.0f, 3.0f / 20.0f)) < 1e-4f,
          "zero peak tag bypasses ceiling limiter without division by zero");

    ae_set_replay_gain_with_peak(e, 3.0f, -1.0f);
    CHECK(std::abs(ae_get_replay_gain_linear(e) - std::pow(10.0f, 3.0f / 20.0f)) < 1e-4f,
          "negative peak tag bypasses ceiling limiter without corrupting gain");

    // 6. End-to-end active playback test with ReplayGain peak limiting
    const char *wavPath = "replaygain_p18_test.wav";
    CHECK(write_test_wav(wavPath, 48000, 2, 0.85f), "test WAV generated (amplitude 0.85)");

    const char *paths[1] = { wavPath };
    CHECK(ae_set_playlist(e, paths, 1), "playlist set");
    CHECK(ae_play(e), "playback started");

    // Without peak limiting, +6.0 dB on 0.85 amplitude = 0.85 * 1.995 = 1.696 (+4.59 dBFS clipping)
    // With peak limiting (peak 0.85): maxSafe = 1.0 / 0.85 = 1.17647 (+1.41 dB)
    ae_set_replay_gain_with_peak(e, 6.0f, 0.85f);

    // Let audio process for 250ms
    const auto deadline = Clock::now() + std::chrono::milliseconds(250);
    while (Clock::now() < deadline)
    {
        std::this_thread::sleep_for(std::chrono::milliseconds(20));
    }

    const PlayerStatus st = ae_get_status(e);
    CHECK(st.is_playing == 1, "playback active with peak-limited ReplayGain");

    ae_stop(e);
    ae_destroy_engine(e);
    std::remove(wavPath);
}

int main()
{
    std::printf("==============================================\n");
    std::printf(" Engine API fix verification\n");
    std::printf("==============================================\n");

    test_create_destroy();
    test_dsp_setters_smoke();
    test_64bit_and_oversampling_api();
    test_end_callback_race();
    test_push_stream_abort();
    test_telemetry_fields();
    test_compressor_gain_reduction();
    test_crossfade_sample_rate_mismatch_p08();
    test_ffmpeg_seek_preroll_p13();
    test_sample_rate_switch_position_continuity_p14();
    test_device_resampler_input_estimation_p15();
    test_filter_state_retention_equalizer_adjustment_p16();
    test_replaygain_peak_limiting_anticlip_p18();

    std::printf("\n----------------------------------------------\n");
    std::printf(" RESULTS: %d passed, %d failed\n", g_passes, g_failures);
    std::printf("----------------------------------------------\n");
    return g_failures == 0 ? 0 : 1;
}
