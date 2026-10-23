#ifndef NOMINMAX
#define NOMINMAX
#endif
#if defined(_WIN32)
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <timeapi.h>
#include <GL/glew.h>
#include <GL/wglew.h>
#elif defined(__ANDROID__)
#include <jni.h>
#include <android/native_window.h>
#include <android/native_window_jni.h>
#include <EGL/egl.h>
#include <EGL/eglext.h>
#include <GLES3/gl3.h>
#include <android/log.h>
#define LOG_TAG "pmvis"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)
#elif defined(__APPLE__)
#include <TargetConditionals.h>
#if TARGET_OS_IPHONE
#include <OpenGLES/ES3/gl.h>
#include <OpenGLES/ES3/glext.h>
#include <objc/runtime.h>
#include <objc/message.h>
#else
#include <OpenGL/OpenGL.h>
#include <OpenGL/gl3.h>
#include <OpenGL/gl3ext.h>
#endif
#else // Linux / UNIX
#include <EGL/egl.h>
#include <EGL/eglext.h>
#ifndef GL_GLEXT_PROTOTYPES
#define GL_GLEXT_PROTOTYPES 1
#endif
#include <GL/gl.h>
#include <GL/glext.h>
#endif

#define MINIAUDIO_IMPLEMENTATION
#include "miniaudio.h"

#include <projectM-4/projectM.h>
#include "pmvis.h"

#include <atomic>
#include <chrono>
#include <cmath>
#include <condition_variable>
#include <cstring>
#include <iostream>
#include <memory>
#include <mutex>
#include <queue>
#include <string>
#include <thread>
#include <vector>

// Lock-Free SPSC Ring Buffer for Stereo Float PCM
class PcmRingBuffer {
public:
    explicit PcmRingBuffer(size_t capacity_frames = 16384)
        : m_capacity(capacity_frames * 2)
        , m_buffer(capacity_frames * 2, 0.0f)
        , m_write_pos(0)
        , m_read_pos(0) {}

    void Push(const float* interleaved_lr, size_t frames) {
        if (!interleaved_lr || frames == 0) return;
        size_t samples = frames * 2;
        size_t write_idx = m_write_pos.load(std::memory_order_relaxed);
        for (size_t i = 0; i < samples; ++i) {
            m_buffer[(write_idx + i) % m_capacity] = interleaved_lr[i];
        }
        m_write_pos.store(write_idx + samples, std::memory_order_release);
    }

    size_t PopLatest(float* out_interleaved_lr, size_t max_frames) {
        if (!out_interleaved_lr || max_frames == 0) return 0;
        size_t write_idx = m_write_pos.load(std::memory_order_acquire);
        size_t read_idx = m_read_pos.load(std::memory_order_relaxed);
        size_t available_samples = (write_idx > read_idx) ? (write_idx - read_idx) : 0;
        size_t max_samples = max_frames * 2;

        if (available_samples == 0) return 0;

        size_t samples_to_read = (available_samples > max_samples) ? max_samples : available_samples;
        size_t start_idx = write_idx - samples_to_read;

        for (size_t i = 0; i < samples_to_read; ++i) {
            out_interleaved_lr[i] = m_buffer[(start_idx + i) % m_capacity];
        }

        m_read_pos.store(write_idx, std::memory_order_relaxed);
        return samples_to_read / 2;
    }

private:
    const size_t m_capacity;
    std::vector<float> m_buffer;
    std::atomic<size_t> m_write_pos;
    std::atomic<size_t> m_read_pos;
};

// Lock-free, non-blocking Triple-buffered Pixel Sink
class PixelBufferSink {
public:
    PixelBufferSink()
        : m_width(0), m_height(0), m_frame_id(0)
        , m_write_idx(0), m_shared_idx(1), m_read_idx(2) {
        for (int i = 0; i < 3; ++i) {
            m_buffers[i].resize(1280 * 720 * 4, 0);
        }
    }

    void Resize(int w, int h) {
        std::lock_guard<std::mutex> lock(m_resize_mutex);
        m_width = w;
        m_height = h;
        size_t bytes = static_cast<size_t>(w * h * 4);
        for (int i = 0; i < 3; ++i) {
            m_buffers[i].assign(bytes, 0);
        }
    }

    // Called on render thread (OpenGL output)
    void Publish(const uint8_t* rgba, int w, int h) {
        if (!rgba || w <= 0 || h <= 0) return;
        size_t bytes = static_cast<size_t>(w * h * 4);

        if (w != m_width || h != m_height || m_buffers[m_write_idx].size() < bytes) {
            std::lock_guard<std::mutex> lock(m_resize_mutex);
            m_width = w;
            m_height = h;
            for (int i = 0; i < 3; ++i) {
                if (m_buffers[i].size() < bytes) {
                    m_buffers[i].resize(bytes, 0);
                }
            }
        }

        std::memcpy(m_buffers[m_write_idx].data(), rgba, bytes);

        // Atomically exchange write buffer index with shared index (zero locks, zero stalls!)
        int prev_shared = m_shared_idx.exchange(m_write_idx, std::memory_order_acq_rel);
        m_write_idx = prev_shared;
        m_frame_id.fetch_add(1, std::memory_order_release);
    }

    // Called on Dart / consumer UI thread (Completely lock-free & resize-safe!)
    bool CopyLatest(uint8_t* dst, size_t dst_max_bytes, int* out_w, int* out_h, uint64_t* out_frame_id, uint64_t last_consumed_id) {
        if (!dst || dst_max_bytes == 0) return false;

        std::unique_lock<std::mutex> lock(m_resize_mutex, std::try_to_lock);
        if (!lock.owns_lock()) {
            return false; // Safely skip frame while render thread is reallocating buffers
        }

        uint64_t current_id = m_frame_id.load(std::memory_order_acquire);
        if (current_id == last_consumed_id || m_width <= 0 || m_height <= 0) {
            return false;
        }

        // Atomically acquire the most recently published buffer
        int latest_idx = m_shared_idx.exchange(m_read_idx, std::memory_order_acq_rel);
        m_read_idx = latest_idx;

        size_t bytes = static_cast<size_t>(m_width * m_height * 4);
        if (bytes == 0 || m_buffers[m_read_idx].size() < bytes || bytes > dst_max_bytes) {
            return false;
        }

        *out_w = m_width;
        *out_h = m_height;
        *out_frame_id = current_id;
        std::memcpy(dst, m_buffers[m_read_idx].data(), bytes);
        return true;
    }

    uint64_t GetLatestFrameId() const {
        return m_frame_id.load(std::memory_order_relaxed);
    }

private:
    std::mutex m_resize_mutex;
    int m_width;
    int m_height;
    std::vector<uint8_t> m_buffers[3];
    int m_write_idx;
    std::atomic<int> m_shared_idx;
    int m_read_idx;
    std::atomic<uint64_t> m_frame_id;
};

// Command types for render thread
enum class CommandType {
    Resize,
    SetFps,
    SetMeshSize,
    SetSoftCutDuration,
    SetBatterySaver,
    LoadPresetFile,
    LoadPresetData,
    SetTexturePath,
    AttachNativeWindow,
    DetachNativeWindow,
    Stop
};

struct Command {
    CommandType type;
    int int_val1{0};
    int int_val2{0};
    double double_val{0.0};
    void* ptr_val{nullptr};
    std::string str_val;
    std::string str_val2;
};

// Implementation of PmVis
struct PmVis {
    // Threading & Lifecycle
    std::atomic<bool> is_running{true};
    std::thread render_thread;
    std::mutex cmd_mutex;
    std::condition_variable cmd_cv;
    std::queue<Command> cmd_queue;

    // Viewport dimensions & Optimization controls
    std::atomic<int> target_width{1280};
    std::atomic<int> target_height{720};
    std::atomic<int> target_fps{60};
    std::atomic<int> mesh_w{32};
    std::atomic<int> mesh_h{24};
    std::atomic<double> soft_cut_duration{1.5};
    std::atomic<bool> battery_saver{false};

    // Audio Pipeline
    PcmRingBuffer pcm_ring{16384};
    std::mutex audio_mutex;
    ma_device audio_device;
    ma_decoder audio_decoder;
    std::atomic<bool> has_audio_device{false};
    std::atomic<bool> has_decoder{false};
    std::atomic<bool> audio_is_playing{false};
    std::atomic<bool> use_synthetic_sine{false};
    std::atomic<float> sine_frequency{60.0f};
    std::atomic<float> audio_volume{1.0f};
    double sine_phase{0.0};

    // Pixel output & Telemetry
    PixelBufferSink pixel_sink;
    uint64_t last_consumed_frame_id{0};
    std::atomic<double> current_fps{0.0};
    std::atomic<double> current_frame_time_ms{0.0};
    std::atomic<double> last_bass{0.0};
    std::atomic<double> last_mid{0.0};
    std::atomic<double> last_treb{0.0};
    std::atomic<uint32_t> total_frames_rendered{0};
    std::atomic<uint32_t> pcm_frames_dropped{0};

    // OpenGL objects (owned solely by render thread)
#ifdef _WIN32
    HWND hwnd{NULL};
    HDC hdc{NULL};
    HGLRC gl_context{NULL};
#endif
    std::atomic<bool> has_surface{false};
    projectm_handle pm_handle{nullptr};
};

static const double TWO_PI = 6.283185307179586;

// Miniaudio callback
static void pmvis_audio_callback(ma_device* pDevice, void* pOutput, const void* pInput, ma_uint32 frameCount) {
    (void)pInput;
    if (!pDevice || !pOutput || frameCount == 0) return;
    PmVis* pmvis = static_cast<PmVis*>(pDevice->pUserData);
    if (!pmvis) return;

    float* pOut = static_cast<float*>(pOutput);
    float vol = pmvis->audio_volume.load(std::memory_order_relaxed);

    if (pmvis->has_decoder.load(std::memory_order_relaxed) &&
        !pmvis->use_synthetic_sine.load(std::memory_order_relaxed)) {
        std::unique_lock<std::mutex> lock(pmvis->audio_mutex, std::try_to_lock);
        if (lock.owns_lock() && pmvis->has_decoder.load(std::memory_order_relaxed) && pmvis->audio_is_playing.load(std::memory_order_relaxed)) {
            ma_uint64 framesRead = 0;
            ma_decoder_read_pcm_frames(&pmvis->audio_decoder, pOutput, frameCount, &framesRead);

            if (framesRead < frameCount) {
                ma_decoder_seek_to_pcm_frame(&pmvis->audio_decoder, 0);
                ma_uint64 extraFrames = 0;
                ma_decoder_read_pcm_frames(&pmvis->audio_decoder, pOut + (framesRead * 2), frameCount - framesRead, &extraFrames);
                framesRead += extraFrames;
            }

            // Apply volume
            for (ma_uint32 i = 0; i < frameCount * 2; ++i) {
                pOut[i] *= vol;
            }
            pmvis->pcm_ring.Push(pOut, frameCount);
        } else {
            std::memset(pOutput, 0, frameCount * 2 * sizeof(float));
        }
    } else if (pmvis->audio_is_playing.load(std::memory_order_relaxed)) {
        // Synthetic bass generator
        float freq = pmvis->sine_frequency.load(std::memory_order_relaxed);
        for (ma_uint32 i = 0; i < frameCount; ++i) {
            float sample = static_cast<float>(std::sin(pmvis->sine_phase) * 0.8f * vol);
            pmvis->sine_phase += (TWO_PI * freq) / pDevice->sampleRate;
            if (pmvis->sine_phase >= TWO_PI) pmvis->sine_phase -= TWO_PI;

            pOut[i * 2 + 0] = sample;
            pOut[i * 2 + 1] = sample;
        }
        pmvis->pcm_ring.Push(pOut, frameCount);
    } else {
        std::memset(pOutput, 0, frameCount * 2 * sizeof(float));
    }
}

#ifdef _WIN32
// Window procedure for hidden render window
static LRESULT CALLBACK PmVisHiddenWndProc(HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam) {
    return DefWindowProc(hwnd, msg, wParam, lParam);
}
#endif

// Render Thread Loop
static void RenderThreadFunc(PmVis* pmvis, int initial_width, int initial_height) {
#ifdef _WIN32
    timeBeginPeriod(1);
    // 1. Create hidden render window
    // Ensure hidden render window is created AT LEAST as large as the primary monitor
    // so the default OpenGL framebuffer backbuffer surface is never smaller than any requested viewport.
    int screen_w = GetSystemMetrics(SM_CXSCREEN);
    int screen_h = GetSystemMetrics(SM_CYSCREEN);
    int win_w = (initial_width > screen_w) ? initial_width : (screen_w > 1920 ? screen_w : 1920);
    int win_h = (initial_height > screen_h) ? initial_height : (screen_h > 1080 ? screen_h : 1080);

    HINSTANCE hInstance = GetModuleHandleA(NULL);
    WNDCLASSEXA wc = { sizeof(WNDCLASSEXA) };
    wc.style = CS_HREDRAW | CS_VREDRAW | CS_OWNDC;
    wc.lpfnWndProc = PmVisHiddenWndProc;
    wc.hInstance = hInstance;
    wc.lpszClassName = "PmVisHiddenClass";
    RegisterClassExA(&wc);

    pmvis->hwnd = CreateWindowExA(
        0, "PmVisHiddenClass", "PmVisHidden",
        WS_POPUP, 0, 0, win_w, win_h,
        NULL, NULL, hInstance, NULL
    );
    pmvis->hdc = GetDC(pmvis->hwnd);

    PIXELFORMATDESCRIPTOR pfd = { sizeof(PIXELFORMATDESCRIPTOR) };
    pfd.nVersion = 1;
    pfd.dwFlags = PFD_DRAW_TO_WINDOW | PFD_SUPPORT_OPENGL | PFD_DOUBLEBUFFER;
    pfd.iPixelType = PFD_TYPE_RGBA;
    pfd.cColorBits = 32;
    pfd.cDepthBits = 24;
    pfd.cStencilBits = 8;
    int pixelFormat = ChoosePixelFormat(pmvis->hdc, &pfd);
    SetPixelFormat(pmvis->hdc, pixelFormat, &pfd);

    HGLRC tempContext = wglCreateContext(pmvis->hdc);
    wglMakeCurrent(pmvis->hdc, tempContext);

    glewExperimental = GL_TRUE;
    glewInit();

    pmvis->gl_context = tempContext;
    if (wglewIsSupported("WGL_ARB_create_context")) {
        int attribs[] = {
            WGL_CONTEXT_MAJOR_VERSION_ARB, 3,
            WGL_CONTEXT_MINOR_VERSION_ARB, 3,
            WGL_CONTEXT_PROFILE_MASK_ARB, WGL_CONTEXT_CORE_PROFILE_BIT_ARB,
            0
        };
        HGLRC coreCtx = wglCreateContextAttribsARB(pmvis->hdc, 0, attribs);
        if (coreCtx) {
            wglMakeCurrent(NULL, NULL);
            wglDeleteContext(tempContext);
            pmvis->gl_context = coreCtx;
            wglMakeCurrent(pmvis->hdc, pmvis->gl_context);
        }
    }

    if (wglewIsSupported("WGL_EXT_swap_control")) {
        wglSwapIntervalEXT(0); // Disable offscreen VSync so render thread paces independently
    }
#elif defined(__ANDROID__)
    EGLDisplay egl_display = eglGetDisplay(EGL_DEFAULT_DISPLAY);
    eglInitialize(egl_display, nullptr, nullptr);

    const EGLint attribs[] = {
        EGL_RENDERABLE_TYPE, EGL_OPENGL_ES3_BIT,
        EGL_SURFACE_TYPE, EGL_WINDOW_BIT | EGL_PBUFFER_BIT,
        EGL_BLUE_SIZE, 8,
        EGL_GREEN_SIZE, 8,
        EGL_RED_SIZE, 8,
        EGL_ALPHA_SIZE, 8,
        EGL_DEPTH_SIZE, 24,
        EGL_NONE
    };

    EGLConfig egl_config;
    EGLint numConfigs = 0;
    eglChooseConfig(egl_display, attribs, &egl_config, 1, &numConfigs);

    const EGLint ctx_attribs[] = {
        EGL_CONTEXT_CLIENT_VERSION, 3,
        EGL_NONE
    };
    EGLContext egl_context = eglCreateContext(egl_display, egl_config, EGL_NO_CONTEXT, ctx_attribs);

    int max_pbuf_w = (initial_width > 1920) ? initial_width : 1920;
    int max_pbuf_h = (initial_height > 1080) ? initial_height : 1080;
    const EGLint pbuf_attribs[] = {
        EGL_WIDTH, max_pbuf_w,
        EGL_HEIGHT, max_pbuf_h,
        EGL_NONE
    };
    EGLSurface egl_pbuffer = eglCreatePbufferSurface(egl_display, egl_config, pbuf_attribs);
    EGLSurface egl_surface = egl_pbuffer;
    eglMakeCurrent(egl_display, egl_surface, egl_surface, egl_context);
    ANativeWindow* active_window = nullptr;
#elif defined(__APPLE__)
#if TARGET_OS_IPHONE
    Class eaglClass = objc_getClass("EAGLContext");
    SEL initSel = sel_registerName("initWithAPI:");
    SEL allocSel = sel_registerName("alloc");
    SEL setCurrentSel = sel_registerName("setCurrentContext:");
    typedef id (*AllocMsgSend)(id, SEL);
    typedef id (*InitMsgSend)(id, SEL, unsigned long);
    typedef bool (*SetCurrentMsgSend)(id, SEL, id);

    id uninitEagl = ((AllocMsgSend)objc_msgSend)((id)eaglClass, allocSel);
    // 3 = kEAGLRenderingAPIOpenGLES3
    id eagl_ctx = ((InitMsgSend)objc_msgSend)(uninitEagl, initSel, 3);
    if (eagl_ctx) {
        ((SetCurrentMsgSend)objc_msgSend)((id)eaglClass, setCurrentSel, eagl_ctx);
    }

    GLuint ios_fbo = 0;
    GLuint ios_rbo_color = 0;
    GLuint ios_rbo_depth = 0;
    glGenFramebuffers(1, &ios_fbo);
    glBindFramebuffer(GL_FRAMEBUFFER, ios_fbo);

    glGenRenderbuffers(1, &ios_rbo_color);
    glBindRenderbuffer(GL_RENDERBUFFER, ios_rbo_color);
    glRenderbufferStorage(GL_RENDERBUFFER, GL_RGBA8, initial_width, initial_height);
    glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_RENDERBUFFER, ios_rbo_color);

    glGenRenderbuffers(1, &ios_rbo_depth);
    glBindRenderbuffer(GL_RENDERBUFFER, ios_rbo_depth);
    glRenderbufferStorage(GL_RENDERBUFFER, GL_DEPTH24_STENCIL8, initial_width, initial_height);
    glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_DEPTH_STENCIL_ATTACHMENT, GL_RENDERBUFFER, ios_rbo_depth);
#else
    CGLPixelFormatAttribute cgl_attribs[] = {
        kCGLPFAOpenGLProfile, (CGLPixelFormatAttribute)kCGLOGLPVersion_3_2_Core,
        kCGLPFAColorSize, (CGLPixelFormatAttribute)24,
        kCGLPFAAlphaSize, (CGLPixelFormatAttribute)8,
        kCGLPFADepthSize, (CGLPixelFormatAttribute)24,
        kCGLPFAAccelerated,
        kCGLPFAAllowOfflineRenderers,
        (CGLPixelFormatAttribute)0
    };
    CGLPixelFormatObj pixFormat = nullptr;
    GLint numPixelFormats = 0;
    CGLError cgl_err = CGLChoosePixelFormat(cgl_attribs, &pixFormat, &numPixelFormats);
    if (cgl_err != kCGLNoError || !pixFormat) {
        CGLPixelFormatAttribute fallbackAttribs[] = {
            kCGLPFAOpenGLProfile, (CGLPixelFormatAttribute)kCGLOGLPVersion_3_2_Core,
            kCGLPFAColorSize, (CGLPixelFormatAttribute)24,
            kCGLPFAAlphaSize, (CGLPixelFormatAttribute)8,
            kCGLPFADepthSize, (CGLPixelFormatAttribute)24,
            kCGLPFAAllowOfflineRenderers,
            (CGLPixelFormatAttribute)0
        };
        CGLChoosePixelFormat(fallbackAttribs, &pixFormat, &numPixelFormats);
    }
    CGLContextObj cgl_context = nullptr;
    if (pixFormat) {
        CGLCreateContext(pixFormat, nullptr, &cgl_context);
        CGLDestroyPixelFormat(pixFormat);
        if (cgl_context) {
            CGLSetCurrentContext(cgl_context);
        }
    }
#endif
#else // Linux (EGL)
    EGLDisplay egl_display = eglGetDisplay(EGL_DEFAULT_DISPLAY);
    eglInitialize(egl_display, nullptr, nullptr);
    eglBindAPI(EGL_OPENGL_API);

    const EGLint egl_attribs[] = {
        EGL_RENDERABLE_TYPE, EGL_OPENGL_BIT,
        EGL_SURFACE_TYPE, EGL_PBUFFER_BIT,
        EGL_RED_SIZE, 8,
        EGL_GREEN_SIZE, 8,
        EGL_BLUE_SIZE, 8,
        EGL_ALPHA_SIZE, 8,
        EGL_DEPTH_SIZE, 24,
        EGL_NONE
    };

    EGLConfig egl_config = nullptr;
    EGLint numConfigs = 0;
    eglChooseConfig(egl_display, egl_attribs, &egl_config, 1, &numConfigs);

    const EGLint ctx_attribs[] = {
        EGL_CONTEXT_MAJOR_VERSION, 3,
        EGL_CONTEXT_MINOR_VERSION, 3,
        EGL_CONTEXT_OPENGL_PROFILE_MASK, EGL_CONTEXT_OPENGL_CORE_PROFILE_BIT,
        EGL_NONE
    };
    EGLContext egl_context = eglCreateContext(egl_display, egl_config, EGL_NO_CONTEXT, ctx_attribs);

    int max_pbuf_w = (initial_width > 1920) ? initial_width : 1920;
    int max_pbuf_h = (initial_height > 1080) ? initial_height : 1080;
    const EGLint pbuf_attribs[] = {
        EGL_WIDTH, max_pbuf_w,
        EGL_HEIGHT, max_pbuf_h,
        EGL_NONE
    };
    EGLSurface egl_surface = eglCreatePbufferSurface(egl_display, egl_config, pbuf_attribs);
    eglMakeCurrent(egl_display, egl_surface, egl_surface, egl_context);
#endif

    // 2. Initialize projectM
    pmvis->pm_handle = projectm_create();
    projectm_set_window_size(pmvis->pm_handle, initial_width, initial_height);
    projectm_set_fps(pmvis->pm_handle, pmvis->target_fps.load());
    projectm_set_beat_sensitivity(pmvis->pm_handle, 1.2f);
    projectm_set_mesh_size(pmvis->pm_handle, static_cast<size_t>(pmvis->mesh_w.load()), static_cast<size_t>(pmvis->mesh_h.load()));
    projectm_set_soft_cut_duration(pmvis->pm_handle, pmvis->soft_cut_duration.load());

    pmvis->pixel_sink.Resize(initial_width, initial_height);

    int cur_w = initial_width;
    int cur_h = initial_height;
    std::vector<uint8_t> read_buffer(initial_width * initial_height * 4);
    float pcm_feed_buf[576 * 2];

    // Asynchronous PBO double-buffering to eliminate synchronous GPU readback stalls
    GLuint pbos[2] = {0, 0};
    int pbo_read_idx = 0;
    int pbo_map_idx = 1;
#if defined(_WIN32)
    bool pbo_available = (glewIsSupported("GL_ARB_pixel_buffer_object") || glewIsSupported("GL_EXT_pixel_buffer_object") || GLEW_VERSION_2_1);
#elif defined(__ANDROID__)
    bool pbo_available = true; // Core in GLES 3.0
#elif defined(__APPLE__)
    bool pbo_available = true; // Core in OpenGL 3.2+ Core Profile
#else
    bool pbo_available = true; // Core in OpenGL 3.3 Core Profile
#endif

    bool pbo_primed = false;
    auto cleanup_pbos = [&]() {
        if (pbos[0] != 0) {
            glDeleteBuffers(2, pbos);
            pbos[0] = 0;
            pbos[1] = 0;
        }
        pbo_primed = false;
    };

    auto setup_pbos = [&](int w, int h) {
        if (!pbo_available || w <= 0 || h <= 0) return;
        cleanup_pbos();
        glGenBuffers(2, pbos);
        size_t size = static_cast<size_t>(w * h * 4);
        std::vector<uint8_t> clear_buf(size, 0);
        for (int i = 0; i < 2; ++i) {
            glBindBuffer(GL_PIXEL_PACK_BUFFER, pbos[i]);
            glBufferData(GL_PIXEL_PACK_BUFFER, size, clear_buf.data(), GL_STREAM_READ);
        }
        glBindBuffer(GL_PIXEL_PACK_BUFFER, 0);
        pbo_read_idx = 0;
        pbo_map_idx = 1;
        pbo_primed = false;
    };

    setup_pbos(cur_w, cur_h);

    auto prev_time = std::chrono::high_resolution_clock::now();
    auto fps_time = prev_time;
    int frames = 0;
    int silent_counter = 0;

    // 3. Main Loop
    while (pmvis->is_running.load(std::memory_order_acquire)) {
        auto frame_start = std::chrono::high_resolution_clock::now();

        // Process Commands
        std::queue<Command> local_queue;
        {
            std::lock_guard<std::mutex> lock(pmvis->cmd_mutex);
            std::swap(local_queue, pmvis->cmd_queue);
        }

        while (!local_queue.empty()) {
            const auto& cmd = local_queue.front();
            switch (cmd.type) {
            case CommandType::Resize:
                if (cmd.int_val1 == cur_w && cmd.int_val2 == cur_h) {
                    break;
                }
                cur_w = cmd.int_val1;
                cur_h = cmd.int_val2;
#ifdef _WIN32
                if (pmvis->hwnd) {
                    if (cur_w > win_w || cur_h > win_h) {
                        win_w = (cur_w > win_w) ? cur_w : win_w;
                        win_h = (cur_h > win_h) ? cur_h : win_h;
                        SetWindowPos(pmvis->hwnd, NULL, 0, 0, win_w, win_h, SWP_NOZORDER | SWP_NOACTIVATE | SWP_FRAMECHANGED);
                    }
                    MSG msg;
                    while (PeekMessageA(&msg, pmvis->hwnd, 0, 0, PM_REMOVE)) {
                        TranslateMessage(&msg);
                        DispatchMessageA(&msg);
                    }
                }
#elif defined(__ANDROID__)
                if (active_window) {
                    if (egl_surface != EGL_NO_SURFACE && egl_surface != egl_pbuffer) {
                        eglMakeCurrent(egl_display, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
                        eglDestroySurface(egl_display, egl_surface);
                        egl_surface = EGL_NO_SURFACE;
                    }
                    ANativeWindow_setBuffersGeometry(active_window, cur_w, cur_h, WINDOW_FORMAT_RGBA_8888);
                    egl_surface = eglCreateWindowSurface(egl_display, egl_config, static_cast<EGLNativeWindowType>(active_window), nullptr);
                    if (egl_surface != EGL_NO_SURFACE) {
                        eglMakeCurrent(egl_display, egl_surface, egl_surface, egl_context);
                    } else if (egl_pbuffer != EGL_NO_SURFACE) {
                        egl_surface = egl_pbuffer;
                        eglMakeCurrent(egl_display, egl_surface, egl_surface, egl_context);
                    }
                }
#elif defined(__APPLE__)
#if TARGET_OS_IPHONE
                if (ios_rbo_color) {
                    glBindRenderbuffer(GL_RENDERBUFFER, ios_rbo_color);
                    glRenderbufferStorage(GL_RENDERBUFFER, GL_RGBA8, cur_w, cur_h);
                }
                if (ios_rbo_depth) {
                    glBindRenderbuffer(GL_RENDERBUFFER, ios_rbo_depth);
                    glRenderbufferStorage(GL_RENDERBUFFER, GL_DEPTH24_STENCIL8, cur_w, cur_h);
                }
#endif
#endif
                projectm_set_window_size(pmvis->pm_handle, cur_w, cur_h);
                glDisable(GL_SCISSOR_TEST);
                glViewport(0, 0, cur_w, cur_h);
                glClearColor(0.0f, 0.0f, 0.0f, 1.0f);
                glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
                read_buffer.resize(cur_w * cur_h * 4);
                pmvis->pixel_sink.Resize(cur_w, cur_h);
                setup_pbos(cur_w, cur_h);
                break;
            case CommandType::SetFps:
                projectm_set_fps(pmvis->pm_handle, cmd.int_val1);
                break;
            case CommandType::SetMeshSize:
                if (pmvis->pm_handle) {
                    projectm_set_mesh_size(pmvis->pm_handle, static_cast<size_t>(cmd.int_val1), static_cast<size_t>(cmd.int_val2));
                }
                break;
            case CommandType::SetSoftCutDuration:
                if (pmvis->pm_handle) {
                    projectm_set_soft_cut_duration(pmvis->pm_handle, cmd.double_val);
                }
                break;
            case CommandType::SetBatterySaver:
                pmvis->battery_saver.store(cmd.int_val1 != 0);
                break;
            case CommandType::LoadPresetFile:
                projectm_load_preset_file(pmvis->pm_handle, cmd.str_val.c_str(), cmd.int_val1 != 0);
                break;
            case CommandType::LoadPresetData:
                projectm_load_preset_data(pmvis->pm_handle, cmd.str_val.c_str(), cmd.int_val1 != 0);
                break;
            case CommandType::SetTexturePath: {
                const char* paths[1] = { cmd.str_val.c_str() };
                projectm_set_texture_search_paths(pmvis->pm_handle, paths, 1);
                break;
            }
            case CommandType::AttachNativeWindow:
#ifdef __ANDROID__
                if (cmd.ptr_val) {
                    ANativeWindow* win = static_cast<ANativeWindow*>(cmd.ptr_val);
                    ANativeWindow_acquire(win);
                    ANativeWindow_setBuffersGeometry(win, cmd.int_val1, cmd.int_val2, WINDOW_FORMAT_RGBA_8888);
                    if (egl_surface != EGL_NO_SURFACE && egl_surface != egl_pbuffer) {
                        eglMakeCurrent(egl_display, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
                        eglDestroySurface(egl_display, egl_surface);
                    }
                    if (active_window) {
                        ANativeWindow_release(active_window);
                    }
                    active_window = win;
                    egl_surface = eglCreateWindowSurface(egl_display, egl_config, static_cast<EGLNativeWindowType>(active_window), nullptr);
                    if (egl_surface != EGL_NO_SURFACE) {
                        eglMakeCurrent(egl_display, egl_surface, egl_surface, egl_context);
                        cur_w = cmd.int_val1;
                        cur_h = cmd.int_val2;
                        projectm_set_window_size(pmvis->pm_handle, cur_w, cur_h);
                        glDisable(GL_SCISSOR_TEST);
                        glViewport(0, 0, cur_w, cur_h);
                        glClearColor(0.0f, 0.0f, 0.0f, 1.0f);
                        glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
                        read_buffer.resize(cur_w * cur_h * 4);
                        pmvis->pixel_sink.Resize(cur_w, cur_h);
                        setup_pbos(cur_w, cur_h);
                        pmvis->has_surface.store(true, std::memory_order_release);
                    }
                }
#endif
                break;
            case CommandType::DetachNativeWindow:
#ifdef __ANDROID__
                if (egl_surface != EGL_NO_SURFACE && egl_surface != egl_pbuffer) {
                    eglMakeCurrent(egl_display, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
                    eglDestroySurface(egl_display, egl_surface);
                    egl_surface = egl_pbuffer;
                    eglMakeCurrent(egl_display, egl_surface, egl_surface, egl_context);
                }
                if (active_window) {
                    ANativeWindow_release(active_window);
                    active_window = nullptr;
                }
                pmvis->has_surface.store(false, std::memory_order_release);
#endif
                break;
            case CommandType::Stop:
                pmvis->is_running.store(false, std::memory_order_release);
                break;
            }
            local_queue.pop();
        }

        if (!pmvis->is_running.load(std::memory_order_acquire)) break;

        // Drain audio and feed projectM
        bool has_audio_energy = false;
        size_t audio_frames = pmvis->pcm_ring.PopLatest(pcm_feed_buf, 576);
        if (audio_frames > 0) {
            projectm_pcm_add_float(pmvis->pm_handle, pcm_feed_buf, static_cast<unsigned int>(audio_frames), PROJECTM_STEREO);

            // Real-time 3-band energy approximation for HUD visual meters
            double b_acc = 0.0, m_acc = 0.0, t_acc = 0.0;
            double energy = 0.0;
            for (size_t i = 0; i < audio_frames; ++i) {
                float l = pcm_feed_buf[i * 2 + 0];
                float r = pcm_feed_buf[i * 2 + 1];
                float mono = (l + r) * 0.5f;
                float diff = (l - r) * 0.5f;
                b_acc += std::abs(mono);
                m_acc += std::abs(mono * 0.7f - diff * 0.3f);
                t_acc += std::abs(diff);
                energy += std::abs(mono);
            }
            double inv = 1.0 / audio_frames;
            if (energy * inv > 0.003) {
                has_audio_energy = true;
            }
            auto clamp1 = [](double v) { return v > 1.0 ? 1.0 : (v < 0.0 ? 0.0 : v); };
            pmvis->last_bass.store(clamp1(b_acc * inv * 2.5), std::memory_order_relaxed);
            pmvis->last_mid.store(clamp1(m_acc * inv * 2.2), std::memory_order_relaxed);
            pmvis->last_treb.store(clamp1(t_acc * inv * 3.0), std::memory_order_relaxed);
        } else {
            // Keep projectM audio pipeline active with continuous silence while paused or idle
            float silence_buf[576 * 2] = {0.0f};
            projectm_pcm_add_float(pmvis->pm_handle, silence_buf, 576, PROJECTM_STEREO);

            // Smooth decay of VU meters
            pmvis->last_bass.store(pmvis->last_bass.load() * 0.85, std::memory_order_relaxed);
            pmvis->last_mid.store(pmvis->last_mid.load() * 0.85, std::memory_order_relaxed);
            pmvis->last_treb.store(pmvis->last_treb.load() * 0.85, std::memory_order_relaxed);
        }

        if (has_audio_energy && pmvis->audio_is_playing.load(std::memory_order_relaxed)) {
            silent_counter = 0;
        } else {
            silent_counter++;
        }

        // Ensure viewport covers the active render dimensions and scissor is disabled
        glDisable(GL_SCISSOR_TEST);
        glViewport(0, 0, cur_w, cur_h);

        // Render Frame
        projectm_opengl_render_frame(pmvis->pm_handle);

#ifdef __ANDROID__
        if (egl_surface != EGL_NO_SURFACE && active_window != nullptr) {
            // Direct zero-copy GPU swap directly into Android Surface / Flutter Texture
            eglSwapBuffers(egl_display, egl_surface);
        } else
#endif
        {
            // Readback rendered frame from back buffer (Asynchronous PBO DMA if supported)
            if (pbo_available && pbos[0] != 0 && pbos[1] != 0) {
                glReadBuffer(GL_BACK);
                glBindBuffer(GL_PIXEL_PACK_BUFFER, pbos[pbo_read_idx]);
                glPixelStorei(GL_PACK_ALIGNMENT, 4);
                // Async non-blocking DMA transfer from GPU back buffer to PBO
                glReadPixels(0, 0, cur_w, cur_h, GL_RGBA, GL_UNSIGNED_BYTE, nullptr);

                if (pbo_primed) {
                    // Map and publish the other PBO which already finished DMA transfer
                    glBindBuffer(GL_PIXEL_PACK_BUFFER, pbos[pbo_map_idx]);
#if defined(__ANDROID__) || (defined(__APPLE__) && TARGET_OS_IPHONE)
                    const uint8_t* pbo_ptr = static_cast<const uint8_t*>(glMapBufferRange(GL_PIXEL_PACK_BUFFER, 0, cur_w * cur_h * 4, GL_MAP_READ_BIT));
#else
                    const uint8_t* pbo_ptr = static_cast<const uint8_t*>(glMapBuffer(GL_PIXEL_PACK_BUFFER, GL_READ_ONLY));
#endif
                    if (pbo_ptr) {
                        pmvis->pixel_sink.Publish(pbo_ptr, cur_w, cur_h);
                        glUnmapBuffer(GL_PIXEL_PACK_BUFFER);
                    }
                    glBindBuffer(GL_PIXEL_PACK_BUFFER, 0);
                } else {
                    pbo_primed = true;
                }

                std::swap(pbo_read_idx, pbo_map_idx);
            } else {
                glReadBuffer(GL_BACK);
                glPixelStorei(GL_PACK_ALIGNMENT, 4);
                glReadPixels(0, 0, cur_w, cur_h, GL_RGBA, GL_UNSIGNED_BYTE, read_buffer.data());
                pmvis->pixel_sink.Publish(read_buffer.data(), cur_w, cur_h);
            }

            // Present (swap)
#ifdef _WIN32
            SwapBuffers(pmvis->hdc);
#elif defined(__APPLE__)
#if TARGET_OS_IPHONE
            glFlush();
#else
            if (cgl_context) {
                CGLFlushDrawable(cgl_context);
            }
#endif
#elif !defined(__ANDROID__)
            if (egl_display != EGL_NO_DISPLAY && egl_surface != EGL_NO_SURFACE) {
                eglSwapBuffers(egl_display, egl_surface);
            }
#endif
        }

        // Telemetry calculation
        frames++;
        pmvis->total_frames_rendered.fetch_add(1, std::memory_order_relaxed);
        auto now = std::chrono::high_resolution_clock::now();
        double dt_ms = std::chrono::duration<double, std::milli>(now - prev_time).count();
        prev_time = now;
        pmvis->current_frame_time_ms.store(dt_ms, std::memory_order_relaxed);

        double elapsed = std::chrono::duration<double>(now - fps_time).count();
        if (elapsed >= 0.5) {
            pmvis->current_fps.store(frames / elapsed, std::memory_order_relaxed);
            frames = 0;
            fps_time = now;
        }

        // Target FPS frame pacing & Battery Saver throttling
        int target_fps = pmvis->target_fps.load(std::memory_order_relaxed);
        bool battery_mode = pmvis->battery_saver.load(std::memory_order_relaxed);
        if (battery_mode && silent_counter > 180) {
            target_fps = 15; // Power-saving idle frame rate
        }
        if (target_fps > 0) {
            double target_frame_ms = 1000.0 / target_fps;
            auto work_end = std::chrono::high_resolution_clock::now();
            double work_ms = std::chrono::duration<double, std::milli>(work_end - frame_start).count();
            if (work_ms < target_frame_ms) {
                double sleep_ms = target_frame_ms - work_ms;
                // High-precision sleep without CPU-pegging spin loop
                if (sleep_ms >= 1.0) {
                    std::this_thread::sleep_for(std::chrono::duration<double, std::milli>(sleep_ms));
                }
            }
        }
    }

    // Teardown GL
    cleanup_pbos();
    if (pmvis->pm_handle) {
        projectm_destroy(pmvis->pm_handle);
        pmvis->pm_handle = nullptr;
    }
#ifdef _WIN32
    wglMakeCurrent(NULL, NULL);
    wglDeleteContext(pmvis->gl_context);
    ReleaseDC(pmvis->hwnd, pmvis->hdc);
    DestroyWindow(pmvis->hwnd);
    timeEndPeriod(1);
#elif defined(__ANDROID__)
    if (active_window) {
        ANativeWindow_release(active_window);
        active_window = nullptr;
    }
    if (egl_surface != EGL_NO_SURFACE) {
        eglMakeCurrent(egl_display, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
        if (egl_surface != egl_pbuffer) {
            eglDestroySurface(egl_display, egl_surface);
        }
    }
    if (egl_pbuffer != EGL_NO_SURFACE) {
        eglDestroySurface(egl_display, egl_pbuffer);
    }
    if (egl_context != EGL_NO_CONTEXT) {
        eglDestroyContext(egl_display, egl_context);
    }
    eglTerminate(egl_display);
#elif defined(__APPLE__)
#if TARGET_OS_IPHONE
    if (ios_fbo != 0) {
        glDeleteFramebuffers(1, &ios_fbo);
        glDeleteRenderbuffers(1, &ios_rbo_color);
        glDeleteRenderbuffers(1, &ios_rbo_depth);
    }
    if (eagl_ctx) {
        ((SetCurrentMsgSend)objc_msgSend)((id)eaglClass, setCurrentSel, nil);
        SEL releaseSel = sel_registerName("release");
        typedef void (*ReleaseMsgSend)(id, SEL);
        ((ReleaseMsgSend)objc_msgSend)(eagl_ctx, releaseSel);
        eagl_ctx = nil;
    }
#else
    if (cgl_context) {
        CGLSetCurrentContext(nullptr);
        CGLDestroyContext(cgl_context);
        cgl_context = nullptr;
    }
#endif
#else // Linux
    if (egl_surface != EGL_NO_SURFACE) {
        eglMakeCurrent(egl_display, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
        eglDestroySurface(egl_display, egl_surface);
    }
    if (egl_context != EGL_NO_CONTEXT) {
        eglDestroyContext(egl_display, egl_context);
    }
    if (egl_display != EGL_NO_DISPLAY) {
        eglTerminate(egl_display);
    }
#endif
}

// --- Public C ABI Implementations ---

extern "C" {

PMVIS_EXPORT PmVis* pmvis_create(int width, int height) {
    PmVis* pmvis = new PmVis();
    pmvis->target_width = (width > 0) ? width : 1280;
    pmvis->target_height = (height > 0) ? height : 720;
    pmvis->target_fps = 60;

    // Note: Do not auto-start a hardware audio output device here.
    // When embedded in a player (like SautiPlay), audio samples are pushed directly
    // via pmvis_push_pcm, which prevents audio hardware contention and eliminates humming.
    // The device is lazily initialized only if pmvis_audio_play_file or play_sine is invoked.

    // Spawn render thread
    pmvis->render_thread = std::thread(RenderThreadFunc, pmvis, pmvis->target_width.load(), pmvis->target_height.load());
    return pmvis;
}

PMVIS_EXPORT void pmvis_destroy(PmVis* pmvis) {
    if (!pmvis) return;

    // Signal thread to stop
    {
        std::lock_guard<std::mutex> lock(pmvis->cmd_mutex);
        Command cmd;
        cmd.type = CommandType::Stop;
        pmvis->cmd_queue.push(cmd);
    }

    if (pmvis->render_thread.joinable()) {
        pmvis->render_thread.join();
    }

    if (pmvis->has_audio_device.load()) {
        ma_device_stop(&pmvis->audio_device);
        ma_device_uninit(&pmvis->audio_device);
        pmvis->has_audio_device.store(false);
    }
    if (pmvis->has_decoder.load()) {
        ma_decoder_uninit(&pmvis->audio_decoder);
        pmvis->has_decoder.store(false);
    }

    delete pmvis;
}

PMVIS_EXPORT int pmvis_set_size(PmVis* pmvis, int width, int height) {
    if (!pmvis || width <= 0 || height <= 0) return 0;
    if (pmvis->target_width.load() == width && pmvis->target_height.load() == height) {
        return 1;
    }
    pmvis->target_width.store(width, std::memory_order_relaxed);
    pmvis->target_height.store(height, std::memory_order_relaxed);

    std::lock_guard<std::mutex> lock(pmvis->cmd_mutex);
    Command cmd;
    cmd.type = CommandType::Resize;
    cmd.int_val1 = width;
    cmd.int_val2 = height;
    pmvis->cmd_queue.push(cmd);
    return 1;
}

PMVIS_EXPORT int pmvis_set_fps(PmVis* pmvis, int fps) {
    if (!pmvis || fps <= 0) return 0;
    pmvis->target_fps.store(fps, std::memory_order_relaxed);

    std::lock_guard<std::mutex> lock(pmvis->cmd_mutex);
    Command cmd;
    cmd.type = CommandType::SetFps;
    cmd.int_val1 = fps;
    pmvis->cmd_queue.push(cmd);
    return 1;
}

PMVIS_EXPORT int pmvis_load_preset_file(PmVis* pmvis, const char* path, int smooth_transition) {
    if (!pmvis || !path) return 0;

    std::lock_guard<std::mutex> lock(pmvis->cmd_mutex);
    Command cmd;
    cmd.type = CommandType::LoadPresetFile;
    cmd.str_val = path;
    cmd.int_val1 = smooth_transition;
    pmvis->cmd_queue.push(cmd);
    return 1;
}

PMVIS_EXPORT int pmvis_load_preset_data(PmVis* pmvis, const char* data, size_t length, int smooth_transition) {
    if (!pmvis || !data || length == 0) return 0;

    std::lock_guard<std::mutex> lock(pmvis->cmd_mutex);
    Command cmd;
    cmd.type = CommandType::LoadPresetData;
    cmd.str_val.assign(data, length);
    cmd.int_val1 = smooth_transition;
    pmvis->cmd_queue.push(cmd);
    return 1;
}

PMVIS_EXPORT void pmvis_set_texture_search_path(PmVis* pmvis, const char* dir) {
    if (!pmvis || !dir) return;

    std::lock_guard<std::mutex> lock(pmvis->cmd_mutex);
    Command cmd;
    cmd.type = CommandType::SetTexturePath;
    cmd.str_val = dir;
    pmvis->cmd_queue.push(cmd);
}

static bool EnsureAudioDevice(PmVis* pmvis) {
    if (pmvis->has_audio_device.load()) return true;
    ma_device_config config = ma_device_config_init(ma_device_type_playback);
    config.playback.format   = ma_format_f32;
    config.playback.channels = 2;
    config.sampleRate        = 44100;
    config.dataCallback      = pmvis_audio_callback;
    config.pUserData         = pmvis;

    if (ma_device_init(NULL, &config, &pmvis->audio_device) == MA_SUCCESS) {
        if (ma_device_start(&pmvis->audio_device) == MA_SUCCESS) {
            pmvis->has_audio_device.store(true);
            return true;
        }
        ma_device_uninit(&pmvis->audio_device);
    }
    return false;
}

PMVIS_EXPORT int pmvis_audio_play_file(PmVis* pmvis, const char* file_path) {
    if (!pmvis || !file_path) return 0;

    std::lock_guard<std::mutex> lock(pmvis->audio_mutex);
    if (!EnsureAudioDevice(pmvis)) return 0;

    if (pmvis->has_decoder.load()) {
        ma_decoder_uninit(&pmvis->audio_decoder);
        pmvis->has_decoder.store(false);
    }

    ma_decoder_config config = ma_decoder_config_init(ma_format_f32, 2, 44100);
    if (ma_decoder_init_file(file_path, &config, &pmvis->audio_decoder) != MA_SUCCESS) {
        return 0;
    }

    pmvis->has_decoder.store(true);
    pmvis->use_synthetic_sine.store(false);
    pmvis->audio_is_playing.store(true);
    return 1;
}

PMVIS_EXPORT int pmvis_audio_play_sine(PmVis* pmvis, float frequency_hz) {
    if (!pmvis) return 0;
    std::lock_guard<std::mutex> lock(pmvis->audio_mutex);
    if (!EnsureAudioDevice(pmvis)) return 0;

    pmvis->sine_frequency.store(frequency_hz > 0 ? frequency_hz : 60.0f);
    pmvis->use_synthetic_sine.store(true);
    pmvis->audio_is_playing.store(true);
    return 1;
}

PMVIS_EXPORT int pmvis_audio_pause(PmVis* pmvis) {
    if (!pmvis) return 0;
    pmvis->audio_is_playing.store(false);
    return 1;
}

PMVIS_EXPORT int pmvis_audio_resume(PmVis* pmvis) {
    if (!pmvis) return 0;
    pmvis->audio_is_playing.store(true);
    return 1;
}

PMVIS_EXPORT int pmvis_audio_stop(PmVis* pmvis) {
    if (!pmvis) return 0;
    std::lock_guard<std::mutex> lock(pmvis->audio_mutex);
    pmvis->audio_is_playing.store(false);
    if (pmvis->has_decoder.load()) {
        ma_decoder_seek_to_pcm_frame(&pmvis->audio_decoder, 0);
    }
    return 1;
}

PMVIS_EXPORT int pmvis_audio_set_volume(PmVis* pmvis, float volume) {
    if (!pmvis) return 0;
    pmvis->audio_volume.store(volume < 0.0f ? 0.0f : (volume > 2.0f ? 2.0f : volume));
    return 1;
}

PMVIS_EXPORT int pmvis_push_pcm(PmVis* pmvis, const float* interleaved_lr, unsigned int frames) {
    if (!pmvis || !interleaved_lr || frames == 0) return 0;
    pmvis->audio_is_playing.store(true, std::memory_order_relaxed);
    pmvis->pcm_ring.Push(interleaved_lr, frames);
    return 1;
}

PMVIS_EXPORT int pmvis_copy_frame_rgba(PmVis* pmvis, uint8_t* dst_buffer, size_t dst_max_bytes, int* out_width, int* out_height, uint64_t* out_frame_id) {
    if (!pmvis || !dst_buffer || dst_max_bytes == 0) return 0;

    if (pmvis->pixel_sink.CopyLatest(dst_buffer, dst_max_bytes, out_width, out_height, out_frame_id, pmvis->last_consumed_frame_id)) {
        pmvis->last_consumed_frame_id = *out_frame_id;
        return 1;
    }
    return 0;
}

PMVIS_EXPORT int pmvis_set_mesh_size(PmVis* pmvis, int width, int height) {
    if (!pmvis || width < 8 || height < 8) return 0;
    pmvis->mesh_w.store(width);
    pmvis->mesh_h.store(height);

    std::lock_guard<std::mutex> lock(pmvis->cmd_mutex);
    Command cmd;
    cmd.type = CommandType::SetMeshSize;
    cmd.int_val1 = width;
    cmd.int_val2 = height;
    pmvis->cmd_queue.push(cmd);
    return 1;
}

PMVIS_EXPORT int pmvis_set_soft_cut_duration(PmVis* pmvis, double seconds) {
    if (!pmvis || seconds < 0.0) return 0;
    pmvis->soft_cut_duration.store(seconds);

    std::lock_guard<std::mutex> lock(pmvis->cmd_mutex);
    Command cmd;
    cmd.type = CommandType::SetSoftCutDuration;
    cmd.double_val = seconds;
    pmvis->cmd_queue.push(cmd);
    return 1;
}

PMVIS_EXPORT int pmvis_set_battery_saver(PmVis* pmvis, int enabled) {
    if (!pmvis) return 0;
    pmvis->battery_saver.store(enabled != 0);

    std::lock_guard<std::mutex> lock(pmvis->cmd_mutex);
    Command cmd;
    cmd.type = CommandType::SetBatterySaver;
    cmd.int_val1 = enabled;
    pmvis->cmd_queue.push(cmd);
    return 1;
}

PMVIS_EXPORT int pmvis_get_stats(PmVis* pmvis, PmVisStats* out_stats) {
    if (!pmvis || !out_stats) return 0;

    out_stats->fps = pmvis->current_fps.load(std::memory_order_relaxed);
    out_stats->frame_time_ms = pmvis->current_frame_time_ms.load(std::memory_order_relaxed);
    out_stats->bass = pmvis->last_bass.load(std::memory_order_relaxed);
    out_stats->mid = pmvis->last_mid.load(std::memory_order_relaxed);
    out_stats->treb = pmvis->last_treb.load(std::memory_order_relaxed);
    out_stats->frames_rendered = pmvis->total_frames_rendered.load(std::memory_order_relaxed);
    out_stats->pcm_frames_dropped = pmvis->pcm_frames_dropped.load(std::memory_order_relaxed);
    out_stats->is_playing = pmvis->audio_is_playing.load(std::memory_order_relaxed) ? 1 : 0;
    return 1;
}

PMVIS_EXPORT int pmvis_attach_native_window(PmVis* pmvis, void* native_window, int width, int height) {
    if (!pmvis) return 0;
    std::lock_guard<std::mutex> lock(pmvis->cmd_mutex);
    Command cmd;
    cmd.type = CommandType::AttachNativeWindow;
    cmd.ptr_val = native_window;
    cmd.int_val1 = width;
    cmd.int_val2 = height;
    pmvis->cmd_queue.push(cmd);
    return 1;
}

PMVIS_EXPORT int pmvis_detach_native_window(PmVis* pmvis) {
    if (!pmvis) return 0;
    std::lock_guard<std::mutex> lock(pmvis->cmd_mutex);
    Command cmd;
    cmd.type = CommandType::DetachNativeWindow;
    pmvis->cmd_queue.push(cmd);
    return 1;
}

#ifdef __ANDROID__
extern "C" JNIEXPORT void JNICALL
Java_com_wambugu_projectm_1visualizer_ProjectmVisualizerPlugin_nativeAttachSurface(
    JNIEnv* env, jclass clazz, jlong handle, jobject jSurface, jint width, jint height) {
    PmVis* pmvis = reinterpret_cast<PmVis*>(handle);
    if (!pmvis) return;
    ANativeWindow* window = jSurface ? ANativeWindow_fromSurface(env, jSurface) : nullptr;
    pmvis_attach_native_window(pmvis, window, width, height);
}

extern "C" JNIEXPORT void JNICALL
Java_com_wambugu_projectm_1visualizer_ProjectmVisualizerPlugin_nativeDetachSurface(
    JNIEnv* env, jclass clazz, jlong handle) {
    PmVis* pmvis = reinterpret_cast<PmVis*>(handle);
    if (!pmvis) return;
    pmvis_detach_native_window(pmvis);
}
#endif

} // extern "C"
