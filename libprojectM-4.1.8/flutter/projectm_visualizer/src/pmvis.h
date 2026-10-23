#ifndef PMVIS_H_
#define PMVIS_H_

#include <stddef.h>
#include <stdint.h>

#if defined(_WIN32)
  #if defined(DART_SHARED_LIB)
    #define PMVIS_EXPORT __declspec(dllexport)
  #else
    #define PMVIS_EXPORT
  #endif
#else
  #define PMVIS_EXPORT __attribute__((visibility("default")))
#endif

#ifdef __cplusplus
extern "C" {
#endif

typedef struct PmVis PmVis;

typedef struct PmVisStats {
    double fps;
    double frame_time_ms;
    double bass;
    double mid;
    double treb;
    uint32_t frames_rendered;
    uint32_t pcm_frames_dropped;
    int is_playing;
} PmVisStats;

// Lifecycle
PMVIS_EXPORT PmVis* pmvis_create(int width, int height);
PMVIS_EXPORT void pmvis_destroy(PmVis* pmvis);

// Configuration & Presets
PMVIS_EXPORT int pmvis_set_size(PmVis* pmvis, int width, int height);
PMVIS_EXPORT int pmvis_set_fps(PmVis* pmvis, int fps);
PMVIS_EXPORT int pmvis_load_preset_file(PmVis* pmvis, const char* path, int smooth_transition);
PMVIS_EXPORT int pmvis_load_preset_data(PmVis* pmvis, const char* data, size_t length, int smooth_transition);
PMVIS_EXPORT void pmvis_set_texture_search_path(PmVis* pmvis, const char* dir);

// Audio Engine (miniaudio embedded)
PMVIS_EXPORT int pmvis_audio_play_file(PmVis* pmvis, const char* file_path);
PMVIS_EXPORT int pmvis_audio_play_sine(PmVis* pmvis, float frequency_hz);
PMVIS_EXPORT int pmvis_audio_pause(PmVis* pmvis);
PMVIS_EXPORT int pmvis_audio_resume(PmVis* pmvis);
PMVIS_EXPORT int pmvis_audio_stop(PmVis* pmvis);
PMVIS_EXPORT int pmvis_audio_set_volume(PmVis* pmvis, float volume);

// External audio feed (if user supplies PCM directly)
PMVIS_EXPORT int pmvis_push_pcm(PmVis* pmvis, const float* interleaved_lr, unsigned int frames);

// Frame readout (for Flutter texture / pixel buffer)
// Returns 1 if a new frame was copied, 0 if no new frame since last call
PMVIS_EXPORT int pmvis_copy_frame_rgba(PmVis* pmvis, uint8_t* dst_buffer, size_t dst_max_bytes, int* out_width, int* out_height, uint64_t* out_frame_id);

// Optimization & Battery controls
PMVIS_EXPORT int pmvis_set_mesh_size(PmVis* pmvis, int width, int height);
PMVIS_EXPORT int pmvis_set_soft_cut_duration(PmVis* pmvis, double seconds);
PMVIS_EXPORT int pmvis_set_battery_saver(PmVis* pmvis, int enabled);

// Telemetry
PMVIS_EXPORT int pmvis_get_stats(PmVis* pmvis, PmVisStats* out_stats);

// Zero-Copy Hardware Surface (Android ANativeWindow / EGL)
PMVIS_EXPORT int pmvis_attach_native_window(PmVis* pmvis, void* native_window, int width, int height);
PMVIS_EXPORT int pmvis_detach_native_window(PmVis* pmvis);

#ifdef __cplusplus
}
#endif

#endif // PMVIS_H_
