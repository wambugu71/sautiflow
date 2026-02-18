#pragma once

#include <stdbool.h>
#include <stdint.h>
#include <stddef.h>

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

    typedef enum AEAudioFormat
    {
        AE_FORMAT_F32 = 0,
        AE_FORMAT_S16 = 1,
        AE_FORMAT_U8 = 2
    } AEAudioFormat;

    typedef enum AEEqBandType
    {
        AE_EQ_BAND_PEAK = 0,
        AE_EQ_BAND_BANDPASS = 1,
        AE_EQ_BAND_NOTCH = 2,
        AE_EQ_BAND_LOWSHELF = 3,
        AE_EQ_BAND_HIGHSHELF = 4
    } AEEqBandType;

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
    AE_API int ae_is_network_streaming_supported(void);

    AE_API void ae_set_loop_mode(AudioEngineHandle *engine, int loop_mode);
    AE_API void ae_set_shuffle_enabled(AudioEngineHandle *engine, int enabled);
    AE_API void ae_reshuffle(AudioEngineHandle *engine);

    // Track transition controls.
    // Note: current implementation performs a short transition fade-in on track switches.
    AE_API void ae_set_crossfade_enabled(AudioEngineHandle *engine, int enabled);
    AE_API int ae_get_crossfade_enabled(AudioEngineHandle *engine);
    // Clamped to [0, 10000]. 0 disables transition fade.
    AE_API void ae_set_crossfade_duration_ms(AudioEngineHandle *engine, int duration_ms);
    AE_API int ae_get_crossfade_duration_ms(AudioEngineHandle *engine);

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
    AE_API void ae_set_bandpass_enabled(AudioEngineHandle *engine, int enabled);
    AE_API void ae_set_bandpass_params(AudioEngineHandle *engine, float cutoff_hz, float q);
    AE_API void ae_set_peak_eq_enabled(AudioEngineHandle *engine, int enabled);
    AE_API void ae_set_peak_eq_params(AudioEngineHandle *engine, float gain_db, float q, float frequency_hz);
    AE_API void ae_set_notch_enabled(AudioEngineHandle *engine, int enabled);
    AE_API void ae_set_notch_params(AudioEngineHandle *engine, float q, float frequency_hz);
    AE_API void ae_set_lowshelf_enabled(AudioEngineHandle *engine, int enabled);
    AE_API void ae_set_lowshelf_params(AudioEngineHandle *engine, float gain_db, float slope, float frequency_hz);
    AE_API void ae_set_highshelf_enabled(AudioEngineHandle *engine, int enabled);
    AE_API void ae_set_highshelf_params(AudioEngineHandle *engine, float gain_db, float slope, float frequency_hz);

    // Advanced Audio Controls
    AE_API void ae_set_output_format(AudioEngineHandle *engine, int format);
    AE_API int ae_get_output_format(AudioEngineHandle *engine);

    AE_API void ae_set_output_sample_rate(AudioEngineHandle *engine, int sample_rate);
    AE_API int ae_get_output_sample_rate(AudioEngineHandle *engine);

    AE_API void ae_set_output_channels(AudioEngineHandle *engine, int channels);
    AE_API int ae_get_output_channels(AudioEngineHandle *engine);

    // Push Stream API (Dart-driven streaming)
    AE_API void ae_init_push_stream(AudioEngineHandle *engine);
    // Use unsigned char instead of uint8_t as it is more standard and avoids <cstdint> vs <stdint.h> issues
    AE_API void ae_push_stream_chunk(AudioEngineHandle *engine, const unsigned char *data, size_t size);
    AE_API void ae_end_push_stream(AudioEngineHandle *engine); // Signal EOF or Abort
    AE_API int ae_get_push_stream_buffered_bytes(AudioEngineHandle *engine);

    // Multiband Equalizer
    // band_count: number of EQ bands
    // frequencies: array of center frequencies for each band (Hz)
    // q_factors: array of Q factors for each band (default 1.0 if null)
    AE_API void ae_init_multiband_eq(AudioEngineHandle *engine, int band_count, float *frequencies, float *q_factors);
    AE_API void ae_set_multiband_eq_enabled(AudioEngineHandle *engine, int enabled);
    AE_API void ae_set_multiband_eq_gain(AudioEngineHandle *engine, int band_index, float gain_db);
    AE_API float ae_get_multiband_eq_gain(AudioEngineHandle *engine, int band_index);

    // Unified multiband FX chain (mixed filter types).
    // band_count: number of bands in the chain.
    // types: array of AEEqBandType values (required).
    // frequencies: array of per-band center/cutoff frequencies (required).
    // q_factors: optional array; default 1.0 when null.
    // gains_db: optional array; default 0.0 when null.
    // slopes: optional array; default 1.0 when null.
    // enabled_flags: optional per-band enabled flags; default true when null.
    AE_API void ae_set_multiband_fx_enabled(AudioEngineHandle *engine, int enabled);
    AE_API void ae_set_multiband_fx_bands(
        AudioEngineHandle *engine,
        int band_count,
        const int *types,
        const float *frequencies,
        const float *q_factors,
        const float *gains_db,
        const float *slopes,
        const int *enabled_flags);
    AE_API void ae_clear_multiband_fx(AudioEngineHandle *engine);

    // Realtime analyzer frames (post-FX, mono mixdown).
    // frame_size: number of mono samples per analyzer snapshot.
    AE_API void ae_set_analyzer_enabled(AudioEngineHandle *engine, int enabled);
    AE_API void ae_configure_analyzer(AudioEngineHandle *engine, int frame_size);
    AE_API int ae_get_analyzer_frame_size(AudioEngineHandle *engine);
    // Copies latest analyzer snapshot into out_samples (up to max_samples).
    // Returns number of samples copied.
    AE_API int ae_poll_analyzer_frame(AudioEngineHandle *engine, float *out_samples, int max_samples);
    AE_API uint64_t ae_get_analyzer_dropped_frames(AudioEngineHandle *engine);

#ifdef __cplusplus
}
#endif
