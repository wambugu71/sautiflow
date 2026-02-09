#pragma once

#include <stdbool.h>

#if defined(_WIN32) || defined(_WIN64)
#define AE_API __declspec(dllexport)
#else
#define AE_API __attribute__((visibility("default")))
#endif

#ifdef __cplusplus
extern "C"
{
#endif

    typedef struct AudioEngineHandle AudioEngineHandle;

    typedef struct PlayerStatus
    {
        double position_seconds;
        double duration_seconds;
        int is_playing;
        int current_index;
        int playlist_count;
        int shuffle_enabled;
        int loop_mode; /* 0=off, 1=all, 2=one */
    } PlayerStatus;

    typedef enum AELoopMode
    {
        AE_LOOP_OFF = 0,
        AE_LOOP_ALL = 1,
        AE_LOOP_ONE = 2
    } AELoopMode;

    AE_API AudioEngineHandle *ae_create_engine(int sample_rate, int channels);
    AE_API void ae_destroy_engine(AudioEngineHandle *engine);

    AE_API bool ae_set_playlist(AudioEngineHandle *engine, const char **paths, int count);
    AE_API bool ae_add_to_playlist(AudioEngineHandle *engine, const char *path);
    AE_API bool ae_insert_to_playlist(AudioEngineHandle *engine, int index, const char *path);
    AE_API bool ae_remove_from_playlist(AudioEngineHandle *engine, int index);
    AE_API bool ae_move_playlist_item(AudioEngineHandle *engine, int from_index, int to_index);
    AE_API void ae_clear_playlist(AudioEngineHandle *engine);

    AE_API bool ae_play(AudioEngineHandle *engine);
    AE_API bool ae_pause(AudioEngineHandle *engine);
    AE_API bool ae_stop(AudioEngineHandle *engine);
    AE_API bool ae_seek(AudioEngineHandle *engine, double percent_0_to_1);
    AE_API bool ae_next(AudioEngineHandle *engine);
    AE_API bool ae_prev(AudioEngineHandle *engine);
    AE_API bool ae_jump_to(AudioEngineHandle *engine, int index);
    AE_API bool ae_jump_to_with_position(AudioEngineHandle *engine, int index, double position_seconds);

    AE_API void ae_set_loop_mode(AudioEngineHandle *engine, int loop_mode);
    AE_API void ae_set_shuffle_enabled(AudioEngineHandle *engine, int enabled);
    AE_API void ae_reshuffle(AudioEngineHandle *engine);

    AE_API PlayerStatus ae_get_status(AudioEngineHandle *engine);
    AE_API const char *ae_get_last_error(AudioEngineHandle *engine);
    AE_API void ae_clear_last_error(AudioEngineHandle *engine);

    AE_API void ae_set_reverb_enabled(AudioEngineHandle *engine, int enabled);
    AE_API void ae_set_reverb_params(AudioEngineHandle *engine, float mix, float feedback, float delay_ms);
    AE_API void ae_set_eq_enabled(AudioEngineHandle *engine, int enabled);
    AE_API void ae_set_eq_gains(AudioEngineHandle *engine, float low_gain, float mid_gain, float high_gain);
    AE_API void ae_set_gain(AudioEngineHandle *engine, float gain);
    AE_API void ae_set_pan(AudioEngineHandle *engine, float pan_minus1_to_plus1);
    AE_API void ae_set_lowpass_enabled(AudioEngineHandle *engine, int enabled);
    AE_API void ae_set_lowpass_cutoff(AudioEngineHandle *engine, float hz);
    AE_API void ae_set_highpass_enabled(AudioEngineHandle *engine, int enabled);
    AE_API void ae_set_highpass_cutoff(AudioEngineHandle *engine, float hz);
    AE_API void ae_set_delay_enabled(AudioEngineHandle *engine, int enabled);
    AE_API void ae_set_delay_params(AudioEngineHandle *engine, float mix, float feedback, float delay_ms);

#ifdef __cplusplus
}
#endif
