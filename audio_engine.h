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
        AE_FORMAT_U8 = 2,
        AE_FORMAT_S24 = 3,
        AE_FORMAT_S32 = 4
    } AEAudioFormat;

    typedef enum AEResampleAlgorithm
    {
        AE_RESAMPLE_ALGORITHM_MINIAUDIO_LINEAR = 0,
        AE_RESAMPLE_ALGORITHM_SRC_SINC_BEST_QUALITY = 1,
        AE_RESAMPLE_ALGORITHM_SRC_SINC_MEDIUM_QUALITY = 2,
        AE_RESAMPLE_ALGORITHM_SRC_SINC_FASTEST = 3,
        AE_RESAMPLE_ALGORITHM_SRC_ZERO_ORDER_HOLD = 4,
        AE_RESAMPLE_ALGORITHM_SRC_LINEAR = 5,
        AE_RESAMPLE_ALGORITHM_CUSTOM = 6
    } AEResampleAlgorithm;

    typedef enum AEDitherMode
    {
        AE_DITHER_MODE_NONE = 0,
        AE_DITHER_MODE_RECTANGLE = 1,
        AE_DITHER_MODE_TRIANGLE = 2
    } AEDitherMode;

    typedef enum AEEqBandType
    {
        AE_EQ_BAND_PEAK = 0,
        AE_EQ_BAND_BANDPASS = 1,
        AE_EQ_BAND_NOTCH = 2,
        AE_EQ_BAND_LOWSHELF = 3,
        AE_EQ_BAND_HIGHSHELF = 4
    } AEEqBandType;

    typedef struct AEPipelineState
    {
        // Input true format
        int input_format;
        int input_sample_rate;
        int input_channels;

        // DSP/Processing requested format
        int processing_format;
        int processing_sample_rate;
        int processing_channels;

        // Real Output Target Config (what the OS hardware negotiated)
        int output_format;
        int output_sample_rate;
        int output_channels;

        // Effects Enabled Flags
        int eq_enabled;
        int reverb_enabled;
        int limiter_enabled;
        int stereo_widen_enabled;
        int spatialization_enabled;
        int delay_enabled;

        // Basic settings
        float gain;
        float pan;
        float pitch;
    } AEPipelineState;

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
    AE_API AEPipelineState ae_get_pipeline_state(AudioEngineHandle *engine);
    AE_API const char *ae_get_last_error(AudioEngineHandle *engine);
    AE_API void ae_clear_last_error(AudioEngineHandle *engine);

    AE_API void ae_set_reverb_enabled(AudioEngineHandle *engine, int enabled);
    AE_API void ae_set_reverb_params(AudioEngineHandle *engine, float mix, float feedback, float delay_ms);
    AE_API void ae_set_eq_enabled(AudioEngineHandle *engine, int enabled);
    AE_API void ae_set_eq_gains(AudioEngineHandle *engine, float low_gain, float mid_gain, float high_gain);
    AE_API void ae_set_gain(AudioEngineHandle *engine, float gain);
    AE_API void ae_set_replay_gain(AudioEngineHandle *engine, float gain_db);
    AE_API void ae_set_pan(AudioEngineHandle *engine, float pan_minus1_to_plus1);
    AE_API void ae_set_pitch(AudioEngineHandle *engine, float pitch);
    AE_API void ae_set_lowpass_enabled(AudioEngineHandle *engine, int enabled);
    AE_API void ae_set_lowpass_cutoff(AudioEngineHandle *engine, float hz);
    AE_API void ae_set_highpass_enabled(AudioEngineHandle *engine, int enabled);
    AE_API void ae_set_highpass_cutoff(AudioEngineHandle *engine, float hz);
    AE_API void ae_set_delay_enabled(AudioEngineHandle *engine, int enabled);
    AE_API void ae_set_delay_params(AudioEngineHandle *engine, float mix, float feedback, float delay_ms);
    AE_API void ae_set_stereo_widen(AudioEngineHandle *engine, int enabled, float width, float delay_ms);
    AE_API void ae_set_crossfeed_enabled(AudioEngineHandle *engine, int enabled);
    AE_API void ae_set_crossfeed_preset(AudioEngineHandle *engine, int preset);
    AE_API void ae_set_dynamic_bass_enabled(AudioEngineHandle *engine, int enabled);
    AE_API void ae_set_dynamic_bass_params(AudioEngineHandle *engine, int preset, float gain);

    // Crystalizer (audiophile transient reconstruction + air enhancement)
    // intensity: [0.0, 1.0] — reconstruction strength (default 0.5)
    // high_shelf_enabled: 1 = enable gentle 8kHz air shelf, 0 = off
    // high_shelf_gain_db: [0.0, 6.0] — shelf boost amount in dB (default 2.0)
    AE_API void ae_set_crystalizer_enabled(AudioEngineHandle *engine, int enabled);
    AE_API void ae_set_crystalizer_params(AudioEngineHandle *engine, float intensity, int high_shelf_enabled, float high_shelf_gain_db);
    AE_API float ae_get_crystalizer_intensity(AudioEngineHandle *engine);
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

    // Spatialization (3D Audio)
    AE_API void ae_set_spatialization_enabled(AudioEngineHandle *engine, int enabled);
    AE_API void ae_set_position(AudioEngineHandle *engine, float x, float y, float z);
    AE_API void ae_set_direction(AudioEngineHandle *engine, float x, float y, float z);
    AE_API void ae_set_velocity(AudioEngineHandle *engine, float x, float y, float z);
    // Attenuation models: 0=None, 1=Inverse, 2=Linear, 3=Exponential
    AE_API void ae_set_attenuation_model(AudioEngineHandle *engine, int model);
    AE_API void ae_set_rolloff(AudioEngineHandle *engine, float rolloff);
    AE_API void ae_set_min_gain(AudioEngineHandle *engine, float min_gain);
    AE_API void ae_set_max_gain(AudioEngineHandle *engine, float max_gain);
    AE_API void ae_set_min_distance(AudioEngineHandle *engine, float min_distance);
    AE_API void ae_set_max_distance(AudioEngineHandle *engine, float max_distance);
    AE_API void ae_set_doppler_factor(AudioEngineHandle *engine, float doppler_factor);

    // Fading & Scheduling
    // Wait fade: sets a target volume over ms time
    AE_API void ae_set_fade_in_milliseconds(AudioEngineHandle *engine, float volume_beg, float volume_end, int time_ms);
    // Scheduling start/stop using absolute engine time (pcm frames). -1 means no schedule.
    AE_API void ae_set_start_time_in_pcm_frames(AudioEngineHandle *engine, uint64_t absolute_time);
    AE_API void ae_set_stop_time_in_pcm_frames(AudioEngineHandle *engine, uint64_t absolute_time);
    AE_API uint64_t ae_get_engine_time_in_pcm_frames(AudioEngineHandle *engine);

    // End Callback processing
    typedef void (*AE_EndCallback)(void *pUserData, AudioEngineHandle *engine);
    AE_API void ae_set_end_callback(AudioEngineHandle *engine, AE_EndCallback callback, void *pUserData);

    // Advanced Audio Controls
    AE_API void ae_set_exclusive_mode(AudioEngineHandle *engine, int enabled);
    AE_API int ae_get_exclusive_mode(AudioEngineHandle *engine);

    AE_API void ae_set_output_format(AudioEngineHandle *engine, int format);
    AE_API int ae_get_output_format(AudioEngineHandle *engine);

    AE_API void ae_set_output_sample_rate(AudioEngineHandle *engine, int sample_rate);
    AE_API int ae_get_output_sample_rate(AudioEngineHandle *engine);

    AE_API void ae_set_output_channels(AudioEngineHandle *engine, int channels);
    AE_API int ae_get_output_channels(AudioEngineHandle *engine);

    AE_API void ae_set_engine_resample_algorithm(AudioEngineHandle *engine, int algorithm);
    AE_API int ae_get_engine_resample_algorithm(AudioEngineHandle *engine);

    AE_API void ae_set_engine_dither_mode(AudioEngineHandle *engine, int dither_mode);
    AE_API int ae_get_engine_dither_mode(AudioEngineHandle *engine);

    // Phase Inversion (Polarity Flip)
    AE_API void ae_set_phase_inversion(AudioEngineHandle *engine, int invert_left, int invert_right);
    AE_API void ae_get_phase_inversion(AudioEngineHandle *engine, int *out_invert_left, int *out_invert_right);

    // Audio Limiter & Clipping Detection
    AE_API void ae_set_limiter_enabled(AudioEngineHandle *engine, int enabled);
    AE_API void ae_set_limiter_params(AudioEngineHandle *engine, float threshold, float attack_ms, float release_ms);
    AE_API void ae_set_clipping_detection_enabled(AudioEngineHandle *engine, int enabled);
    AE_API uint64_t ae_get_clipped_samples_count(AudioEngineHandle *engine);
    AE_API void ae_reset_clipped_samples_count(AudioEngineHandle *engine);

    // Custom Real-Time Filter Parameters
    AE_API void ae_set_custom_lpf1_params(AudioEngineHandle *engine, int enabled, double cutoff_hz);
    AE_API void ae_set_custom_hpf1_params(AudioEngineHandle *engine, int enabled, double cutoff_hz);
    AE_API void ae_set_custom_biquad_params(AudioEngineHandle *engine, int enabled, double b0, double b1, double b2, double a0, double a1, double a2);

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

    // ==========================================
    // Standalone Filters & Resampler (miniaudio direct bindings)
    // ==========================================
    typedef struct AELpf1 AELpf1;
    typedef struct AELpf2 AELpf2;
    typedef struct AELpf AELpf;

    typedef struct AEHpf1 AEHpf1;
    typedef struct AEHpf2 AEHpf2;
    typedef struct AEHpf AEHpf;

    typedef struct AEBiquad AEBiquad;
    typedef struct AEResampler AEResampler;

    // LPF1
    AE_API AELpf1 *ae_lpf1_create(int format, int channels, int sample_rate, double cutoff_hz);
    AE_API void ae_lpf1_destroy(AELpf1 *filter);
    AE_API void ae_lpf1_reinit(AELpf1 *filter, int format, int channels, int sample_rate, double cutoff_hz);
    AE_API int ae_lpf1_process(AELpf1 *filter, void *out_frames, const void *in_frames, uint64_t frame_count);

    // LPF2
    AE_API AELpf2 *ae_lpf2_create(int format, int channels, int sample_rate, double cutoff_hz, double q);
    AE_API void ae_lpf2_destroy(AELpf2 *filter);
    AE_API void ae_lpf2_reinit(AELpf2 *filter, int format, int channels, int sample_rate, double cutoff_hz, double q);
    AE_API int ae_lpf2_process(AELpf2 *filter, void *out_frames, const void *in_frames, uint64_t frame_count);

    // LPF (High order Butterworth)
    AE_API AELpf *ae_lpf_create(int format, int channels, int sample_rate, double cutoff_hz, int order);
    AE_API void ae_lpf_destroy(AELpf *filter);
    AE_API void ae_lpf_reinit(AELpf *filter, int format, int channels, int sample_rate, double cutoff_hz, int order);
    AE_API int ae_lpf_process(AELpf *filter, void *out_frames, const void *in_frames, uint64_t frame_count);

    // HPF1
    AE_API AEHpf1 *ae_hpf1_create(int format, int channels, int sample_rate, double cutoff_hz);
    AE_API void ae_hpf1_destroy(AEHpf1 *filter);
    AE_API void ae_hpf1_reinit(AEHpf1 *filter, int format, int channels, int sample_rate, double cutoff_hz);
    AE_API int ae_hpf1_process(AEHpf1 *filter, void *out_frames, const void *in_frames, uint64_t frame_count);

    // HPF2
    AE_API AEHpf2 *ae_hpf2_create(int format, int channels, int sample_rate, double cutoff_hz, double q);
    AE_API void ae_hpf2_destroy(AEHpf2 *filter);
    AE_API void ae_hpf2_reinit(AEHpf2 *filter, int format, int channels, int sample_rate, double cutoff_hz, double q);
    AE_API int ae_hpf2_process(AEHpf2 *filter, void *out_frames, const void *in_frames, uint64_t frame_count);

    // HPF (High order Butterworth)
    AE_API AEHpf *ae_hpf_create(int format, int channels, int sample_rate, double cutoff_hz, int order);
    AE_API void ae_hpf_destroy(AEHpf *filter);
    AE_API void ae_hpf_reinit(AEHpf *filter, int format, int channels, int sample_rate, double cutoff_hz, int order);
    AE_API int ae_hpf_process(AEHpf *filter, void *out_frames, const void *in_frames, uint64_t frame_count);

    // Biquad
    AE_API AEBiquad *ae_biquad_create(int format, int channels, double b0, double b1, double b2, double a0, double a1, double a2);
    AE_API void ae_biquad_destroy(AEBiquad *filter);
    AE_API void ae_biquad_reinit(AEBiquad *filter, int format, int channels, double b0, double b1, double b2, double a0, double a1, double a2);
    AE_API int ae_biquad_process(AEBiquad *filter, void *out_frames, const void *in_frames, uint64_t frame_count);

    // Resampler
    AE_API AEResampler *ae_resampler_create(int format, int channels, int sample_rate_in, int sample_rate_out, int algorithm, int dither_mode);
    AE_API void ae_resampler_destroy(AEResampler *resampler);
    AE_API int ae_resampler_process(AEResampler *resampler, const void *in_frames, uint64_t *in_frame_count, void *out_frames, uint64_t *out_frame_count);
    AE_API void ae_resampler_set_rate(AEResampler *resampler, int sample_rate_in, int sample_rate_out);
    AE_API void ae_resampler_set_rate_ratio(AEResampler *resampler, float ratio_in_out);
    AE_API uint64_t ae_resampler_get_required_input_frame_count(AEResampler *resampler, uint64_t out_frame_count);
    AE_API uint64_t ae_resampler_get_expected_output_frame_count(AEResampler *resampler, uint64_t in_frame_count);
    AE_API uint64_t ae_resampler_get_input_latency(AEResampler *resampler);
    AE_API uint64_t ae_resampler_get_output_latency(AEResampler *resampler);

    // ViPER DSP Oversampling
    AE_API void ae_viper_set_oversampling(AudioEngineHandle *engine, int factor);

    // Native Track Inspection
    typedef struct AETrackInfo
    {
        int sample_rate;        // Native decoder sample rate (Hz)
        int bit_depth;          // Native decoder bit depth (bits)
        int channels;           // Native decoder channel count
        int bitrate_kbps;       // Native average bitrate (kbps)
        int is_float;           // 1 if 32-bit float, 0 if int PCM
        double duration_secs;   // Track duration in seconds
        int64_t file_size_bytes;// File size in bytes
        char format_name[32];   // Container/Codec name ("FLAC", "WAV", "MP3", "AAC", etc.)
    } AETrackInfo;

    AE_API AETrackInfo ae_inspect_file(const char *file_path);

    // Native Hardware Audio Engine Inspection
    typedef struct AEHardwareInfo
    {
        char backend_name[32];       // "WASAPI", "AAudio", "OpenSL ES", "ALSA", "PulseAudio", "Core Audio", etc.
        char device_name[256];       // Active soundcard friendly device name
        int output_format;           // AEAudioFormat Enum (0=F32, 1=S16, 2=U8, 3=S24, 4=S32)
        int bit_depth;               // Hardware bit depth (8, 16, 24, 32)
        int is_float;                // 1 if 32-bit Float PCM, 0 if Int PCM
        int sample_rate;             // Hardware output sample rate in Hz
        int channels;                // Hardware output channels
        uint32_t period_size_frames; // Hardware period frame size
        uint32_t period_count;       // Hardware period count
        double latency_ms;           // Real hardware buffer processing latency in milliseconds
        int is_exclusive_mode;       // 1 if exclusive mode (WASAPI/ALSA), 0 if shared mode
    } AEHardwareInfo;

    AE_API AEHardwareInfo ae_get_hardware_info(AudioEngineHandle *engine);
    AE_API void ae_register_android_jvm(void *vm);

#ifdef __cplusplus
}
#endif
