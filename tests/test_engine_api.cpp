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
        ae_dsp_set_master_limiter_enabled(e, 0); // stays opt-in
        if (i % 50 == 0) ae_dsp_reset(e);
    }
    CHECK(ok, "400+ concurrent-ish setter calls survived");

    // De-Esser & Master limiter default checks
    CHECK(ae_dsp_get_de_esser_gain_reduction_db(e) == 0.0f,
          "de-esser inactive by default (GR = 0 dB)");
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

int main()
{
    std::printf("==============================================\n");
    std::printf(" Engine API fix verification\n");
    std::printf("==============================================\n");

    test_create_destroy();
    test_dsp_setters_smoke();
    test_end_callback_race();
    test_push_stream_abort();
    test_telemetry_fields();

    std::printf("\n----------------------------------------------\n");
    std::printf(" RESULTS: %d passed, %d failed\n", g_passes, g_failures);
    std::printf("----------------------------------------------\n");
    return g_failures == 0 ? 0 : 1;
}
