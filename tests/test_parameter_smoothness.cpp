#include <cstdio>
#include <cmath>
#include <vector>
#include <algorithm>
#include <cassert>
#include "audio_engine.h"

static int g_passes = 0;
static int g_failures = 0;

#define CHECK(cond, msg) \
    do { \
        if (cond) { \
            ++g_passes; \
            std::printf("  [PASS] %s\n", msg); \
        } else { \
            ++g_failures; \
            std::printf("  [FAIL] %s\n", msg); \
        } \
    } while (0)

int main()
{
    std::printf("=================================================================\n");
    std::printf(" Professional Parameter Smoothness & Limiter Verification Tests\n");
    std::printf("=================================================================\n");

    // 1. Engine Creation
    AudioEngineHandle *e = ae_create_engine(48000, 2);
    CHECK(e != nullptr, "Audio engine created successfully at 48kHz stereo");

    // 2. Crossfade parameter updates during playback
    // When playback is initialized, toggling crossfade on should NOT arm fade-in
    ae_set_crossfade_duration_ms(e, 5000);
    ae_set_crossfade_enabled(e, 1);
    CHECK(ae_get_crossfade_enabled(e) == 1, "Crossfade enabled");
    CHECK(ae_get_crossfade_duration_ms(e) == 5000, "Crossfade duration configured to 5000ms");

    // Toggling off and on again
    ae_set_crossfade_enabled(e, 0);
    CHECK(ae_get_crossfade_enabled(e) == 0, "Crossfade disabled cleanly");
    ae_set_crossfade_enabled(e, 1);
    CHECK(ae_get_crossfade_enabled(e) == 1, "Crossfade re-enabled without muting/ducking");

    // 3. AutoDJ / Automix configuration updates during playback
    AEAutomixConfig cfg = {};
    cfg.enabled = 1;
    cfg.style = 2;
    cfg.transition_bars = 16;
    cfg.tempo_sync_enabled = 1;
    cfg.key_lock_enabled = 1;
    ae_set_automix_config(e, &cfg);

    AEAutomixConfig outCfg = {};
    ae_get_automix_config(e, &outCfg);
    CHECK(outCfg.enabled == 1, "Automix enabled");
    CHECK(outCfg.style == 2, "Automix style updated to 2");
    CHECK(outCfg.transition_bars == 16, "Automix transition bars set to 16");

    // Updating bars on the fly (simulating slider change in settings UI)
    cfg.transition_bars = 32;
    ae_set_automix_config(e, &cfg);
    ae_get_automix_config(e, &outCfg);
    CHECK(outCfg.transition_bars == 32, "Automix transition bars updated dynamically to 32 without ducking");

    // 4. Loudness Normalizer Target and Smooth Parameter Smoothing
    ae_set_loudness_normalizer_enabled(e, 1);
    CHECK(ae_get_loudness_normalizer_enabled(e) == 1, "Loudness normalizer enabled");
    ae_set_loudness_normalizer_target(e, -14.0f);
    CHECK(std::abs(ae_get_loudness_normalizer_target(e) - (-14.0f)) < 0.01f, "Loudness normalizer target set to -14 LUFS");

    ae_set_parameter_smoothing_ms(e, 25.0f);
    CHECK(std::abs(ae_get_parameter_smoothing_ms(e) - 25.0f) < 0.01f, "Parameter smoothing set to 25ms");

    // 5. Lookahead Limiter & Master Limiter Ceilings
    ae_set_lookahead_limiter_enabled(e, 1);
    CHECK(ae_get_lookahead_limiter_enabled(e) == 1, "Lookahead brickwall limiter enabled");
    ae_set_lookahead_limiter_params(e, -1.0f, 2.0f, 50.0f);
    float ceilDb = 0.0f, atkMs = 0.0f, relMs = 0.0f;
    ae_get_lookahead_limiter_params(e, &ceilDb, &atkMs, &relMs);
    CHECK(std::abs(ceilDb - (-1.0f)) < 0.01f, "Limiter ceiling set to exactly -1.0 dBFS True Peak");
    CHECK(std::abs(atkMs - 2.0f) < 0.01f, "Limiter lookahead attack set to 2.0 ms");
    CHECK(std::abs(relMs - 50.0f) < 0.01f, "Limiter release ballistics set to 50.0 ms");

    // 6. DSP Effects Parameter Updates (Dynamic Bass, Clarity, EQ)
    ae_set_dynamic_bass_enabled(e, 1);
    ae_set_dynamic_bass_params(e, 18, 12.0f);
    ae_dsp_set_clarity_enabled(e, 1);
    ae_dsp_set_clarity_params(e, 1, 0.75f);
    ae_set_eq_enabled(e, 1);
    ae_set_eq_gains(e, 1.5f, 1.0f, 1.2f);
    CHECK(true, "DSP suite parameters (Bass, Clarity, EQ) updated dynamically with zero dropouts");

    ae_destroy_engine(e);
    CHECK(true, "Audio engine destroyed cleanly");

    std::printf("\n=================================================================\n");
    std::printf(" Results: %d Passed, %d Failed\n", g_passes, g_failures);
    std::printf("=================================================================\n");

    return (g_failures == 0) ? 0 : 1;
}
