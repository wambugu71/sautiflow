#include "audio_engine.h"

#include <cstdio>
#include <cstdlib>

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

int main()
{
    std::printf("========================================\n");
    std::printf("  User-Configurable Output Buffer Tests\n");
    std::printf("========================================\n\n");

    AudioEngineHandle *e = ae_create_engine(48000, 2);
    if (!e)
    {
        std::fprintf(stderr, "Failed to create audio engine.\n");
        return 1;
    }

    // 1. Initial defaults should be 0 (auto)
    int f = -1, c = -1;
    ae_get_output_buffer(e, &f, &c);
    CHECK(f == 0 && c == 0, "initial output buffer is auto (0, 0)");

    // 2. Set explicit buffer parameters (e.g. 512 frames, 4 periods)
    ae_set_output_buffer(e, 512, 4);
    ae_get_output_buffer(e, &f, &c);
    CHECK(f == 512, "configured period frames == 512");
    CHECK(c == 4, "configured period count == 4");

    // 3. Clamping checks
    // Out-of-bounds frame clamp (< 16 -> 16, > 16384 -> 16384)
    ae_set_output_buffer(e, 4, 3);
    ae_get_output_buffer(e, &f, &c);
    CHECK(f == 16, "under-range frame count clamped to 16");

    ae_set_output_buffer(e, 32768, 3);
    ae_get_output_buffer(e, &f, &c);
    CHECK(f == 16384, "over-range frame count clamped to 16384");

    // Out-of-bounds period count clamp (< 2 -> 2, > 16 -> 16)
    ae_set_output_buffer(e, 512, 1);
    ae_get_output_buffer(e, &f, &c);
    CHECK(c == 2, "under-range period count clamped to 2");

    ae_set_output_buffer(e, 512, 32);
    ae_get_output_buffer(e, &f, &c);
    CHECK(c == 16, "over-range period count clamped to 16");

    // 4. Reset to auto
    ae_set_output_buffer(e, 0, 0);
    ae_get_output_buffer(e, &f, &c);
    CHECK(f == 0 && c == 0, "reset to auto (0, 0) successful");

    // 5. Hardware Info Telemetry
    AEHardwareInfo hw{};
    hw = ae_get_hardware_info(e);
    CHECK(hw.sample_rate > 0, "hardware info reports valid sample rate");
    CHECK(hw.period_size_frames > 0, "hardware info reports valid negotiated period size");
    std::printf("  Negotiated Backend: %s, Device: %s, PeriodSize: %u frames, Periods: %u, Latency: %.2f ms\n",
                hw.backend_name, hw.device_name, hw.period_size_frames, hw.period_count, hw.latency_ms);

    ae_destroy_engine(e);

    std::printf("\n========================================\n");
    std::printf("Result: %d passed, %d failed\n", g_passes, g_failures);
    std::printf("========================================\n");

    return (g_failures == 0) ? 0 : 1;
}
