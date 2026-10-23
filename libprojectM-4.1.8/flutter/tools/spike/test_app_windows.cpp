#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <GL/glew.h>
#include <GL/wglew.h>

#define MINIAUDIO_IMPLEMENTATION
#include "miniaudio.h"

#include <projectM-4/projectM.h>

#include <iostream>
#include <vector>
#include <string>
#include <atomic>
#include <chrono>
#include <cmath>
#include <filesystem>

namespace fs = std::filesystem;

// --- Lock-Free SPSC Ring Buffer for Stereo Float PCM ---
class PcmRingBuffer {
public:
    explicit PcmRingBuffer(size_t capacity_frames = 16384)
        : m_capacity(capacity_frames * 2) // 2 channels (stereo)
        , m_buffer(capacity_frames * 2, 0.0f)
        , m_write_pos(0)
        , m_read_pos(0) {}

    // Called from miniaudio audio thread
    void Push(const float* interleaved_lr, size_t frames) {
        size_t samples = frames * 2;
        size_t write_idx = m_write_pos.load(std::memory_order_relaxed);
        for (size_t i = 0; i < samples; ++i) {
            m_buffer[(write_idx + i) % m_capacity] = interleaved_lr[i];
        }
        m_write_pos.store(write_idx + samples, std::memory_order_release);
    }

    // Called from render thread - pulls up to max_frames of the newest audio
    size_t PopLatest(float* out_interleaved_lr, size_t max_frames) {
        size_t write_idx = m_write_pos.load(std::memory_order_acquire);
        size_t read_idx = m_read_pos.load(std::memory_order_relaxed);
        
        size_t available_samples = (write_idx > read_idx) ? (write_idx - read_idx) : 0;
        size_t max_samples = max_frames * 2;

        if (available_samples == 0) {
            return 0;
        }

        size_t samples_to_read = (available_samples > max_samples) ? max_samples : available_samples;
        size_t start_idx = write_idx - samples_to_read; // always get the newest sound

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

// Global audio & state objects
static PcmRingBuffer g_pcm_ring(16384);
static ma_device g_audio_device;
static ma_decoder g_audio_decoder;
static bool g_has_decoder = false;
static std::atomic<bool> g_use_synthetic_sine(false);
static double g_sine_phase = 0.0;
static const double TWO_PI = 6.283185307179586;

// Miniaudio callback
static void audio_data_callback(ma_device* pDevice, void* pOutput, const void* pInput, ma_uint32 frameCount) {
    (void)pInput;
    float* pOutFloats = static_cast<float*>(pOutput);

    if (g_has_decoder && !g_use_synthetic_sine.load(std::memory_order_relaxed)) {
        ma_uint64 framesRead = 0;
        ma_decoder_read_pcm_frames(&g_audio_decoder, pOutput, frameCount, &framesRead);
        
        // Loop if end of file reached
        if (framesRead < frameCount) {
            ma_decoder_seek_to_pcm_frame(&g_audio_decoder, 0);
            ma_uint64 extraFrames = 0;
            ma_decoder_read_pcm_frames(&g_audio_decoder, pOutFloats + (framesRead * 2), frameCount - framesRead, &extraFrames);
            framesRead += extraFrames;
        }

        // Push to projectM ring buffer
        g_pcm_ring.Push(pOutFloats, frameCount);
    } else {
        // Generate synthetic test audio: 60Hz sub-bass
        for (ma_uint32 i = 0; i < frameCount; ++i) {
            float sample = static_cast<float>(std::sin(g_sine_phase) * 0.8);
            g_sine_phase += (TWO_PI * 60.0) / pDevice->sampleRate;
            if (g_sine_phase >= TWO_PI) g_sine_phase -= TWO_PI;

            pOutFloats[i * 2 + 0] = sample;
            pOutFloats[i * 2 + 1] = sample;
        }
        g_pcm_ring.Push(pOutFloats, frameCount);
    }
}

// Window Procedure
static bool g_running = true;
static bool g_vsync = true;
static int g_current_preset_idx = 0;
static std::vector<std::string> g_preset_files;
static projectm_handle g_pm = nullptr;

static void CyclePreset(int delta) {
    if (g_preset_files.empty() || !g_pm) return;
    g_current_preset_idx = (g_current_preset_idx + delta + (int)g_preset_files.size()) % (int)g_preset_files.size();
    const auto& path = g_preset_files[g_current_preset_idx];
    std::cout << "[Preset] Loading: " << path << std::endl;
    projectm_load_preset_file(g_pm, path.c_str(), false);
}

static LRESULT CALLBACK WndProc(HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam) {
    switch (msg) {
    case WM_SIZE: {
        int w = LOWORD(lParam);
        int h = HIWORD(lParam);
        if (g_pm && w > 0 && h > 0) {
            projectm_set_window_size(g_pm, (size_t)w, (size_t)h);
            glViewport(0, 0, w, h);
        }
        return 0;
    }
    case WM_KEYDOWN:
        if (wParam == VK_ESCAPE) {
            g_running = false;
            PostQuitMessage(0);
        } else if (wParam == VK_SPACE || wParam == VK_RIGHT) {
            CyclePreset(+1);
        } else if (wParam == VK_LEFT) {
            CyclePreset(-1);
        } else if (wParam == 'V') {
            g_vsync = !g_vsync;
            if (wglSwapIntervalEXT) {
                wglSwapIntervalEXT(g_vsync ? 1 : 0);
            }
            std::cout << "[VSync] " << (g_vsync ? "Enabled (locked to display rate)" : "Disabled (uncapped FPS)") << std::endl;
        } else if (wParam == 'S') {
            bool current = g_use_synthetic_sine.load();
            g_use_synthetic_sine.store(!current);
            std::cout << "[Audio] Switched to: " << (!current ? "Synthetic 60Hz Sine Bass" : "Audio File Decoder") << std::endl;
        }
        return 0;
    case WM_CLOSE:
    case WM_DESTROY:
        g_running = false;
        PostQuitMessage(0);
        return 0;
    default:
        return DefWindowProc(hwnd, msg, wParam, lParam);
    }
}

int main(int argc, char* argv[]) {
    std::cout << "=========================================================\n";
    std::cout << " libprojectM 4.1.8 + miniaudio.h High-FPS Native Test App\n";
    std::cout << " Target: 60 - 120+ Hz Real-Time Audio Visualization\n";
    std::cout << "=========================================================\n\n";

    // 1. Enumerate test presets
    std::string preset_dir = "presets/tests";
    if (fs::exists(preset_dir)) {
        for (const auto& entry : fs::directory_iterator(preset_dir)) {
            if (entry.path().extension() == ".milk") {
                g_preset_files.push_back(entry.path().string());
            }
        }
    }
    std::cout << "[Init] Found " << g_preset_files.size() << " test .milk presets.\n";

    // 2. Initialize miniaudio
    std::string audio_file = (argc > 1) ? argv[1] : "";
    if (!audio_file.empty() && fs::exists(audio_file)) {
        ma_decoder_config decoderConfig = ma_decoder_config_init(ma_format_f32, 2, 44100);
        if (ma_decoder_init_file(audio_file.c_str(), &decoderConfig, &g_audio_decoder) == MA_SUCCESS) {
            g_has_decoder = true;
            std::cout << "[Audio] Loaded file: " << audio_file << "\n";
        } else {
            std::cerr << "[Audio] Failed to open audio file, falling back to synthetic generator.\n";
            g_use_synthetic_sine = true;
        }
    } else {
        std::cout << "[Audio] No audio file specified. Using built-in 60Hz sine bass generator.\n";
        std::cout << "        Tip: Pass an mp3/wav path as argument 1: test_app_windows.exe track.mp3\n";
        g_use_synthetic_sine = true;
    }

    ma_device_config deviceConfig = ma_device_config_init(ma_device_type_playback);
    deviceConfig.playback.format   = ma_format_f32;
    deviceConfig.playback.channels = 2;
    deviceConfig.sampleRate        = 44100;
    deviceConfig.dataCallback      = audio_data_callback;

    if (ma_device_init(NULL, &deviceConfig, &g_audio_device) != MA_SUCCESS) {
        std::cerr << "[Audio] Error initializing miniaudio device!\n";
        return 1;
    }
    ma_device_start(&g_audio_device);
    std::cout << "[Audio] miniaudio playback device started @ 44.1kHz stereo.\n";

    // 3. Register Win32 Window Class & Create OpenGL 3.3 Core Window
    HINSTANCE hInstance = GetModuleHandle(NULL);
    WNDCLASSEX wc = { sizeof(WNDCLASSEX) };
    wc.style = CS_HREDRAW | CS_VREDRAW | CS_OWNDC;
    wc.lpfnWndProc = WndProc;
    wc.hInstance = hInstance;
    wc.hCursor = LoadCursor(NULL, IDC_ARROW);
    wc.lpszClassName = "ProjectMTestClass";
    RegisterClassEx(&wc);

    int windowWidth = 1280;
    int windowHeight = 720;
    RECT rect = { 0, 0, windowWidth, windowHeight };
    AdjustWindowRect(&rect, WS_OVERLAPPEDWINDOW, FALSE);

    HWND hwnd = CreateWindowEx(
        0, "ProjectMTestClass", "projectM 4.1.8 + miniaudio (Initializing...)",
        WS_OVERLAPPEDWINDOW | WS_VISIBLE,
        CW_USEDEFAULT, CW_USEDEFAULT, rect.right - rect.left, rect.bottom - rect.top,
        NULL, NULL, hInstance, NULL
    );

    HDC hdc = GetDC(hwnd);

    // Initial Pixel Format for WGL bootstrapping
    PIXELFORMATDESCRIPTOR pfd = { sizeof(PIXELFORMATDESCRIPTOR) };
    pfd.nVersion = 1;
    pfd.dwFlags = PFD_DRAW_TO_WINDOW | PFD_SUPPORT_OPENGL | PFD_DOUBLEBUFFER;
    pfd.iPixelType = PFD_TYPE_RGBA;
    pfd.cColorBits = 32;
    pfd.cDepthBits = 24;
    pfd.cStencilBits = 8;
    int pixelFormat = ChoosePixelFormat(hdc, &pfd);
    SetPixelFormat(hdc, pixelFormat, &pfd);

    HGLRC tempContext = wglCreateContext(hdc);
    wglMakeCurrent(hdc, tempContext);

    // Initialize GLEW to load OpenGL 3.3 Core and WGL extensions
    glewExperimental = GL_TRUE;
    GLenum glewErr = glewInit();
    if (glewErr != GLEW_OK) {
        std::cerr << "[OpenGL] GLEW Init Failed: " << glewGetErrorString(glewErr) << std::endl;
        return 1;
    }

    // Create real OpenGL 3.3 Core context
    HGLRC gl33Context = tempContext;
    if (wglewIsSupported("WGL_ARB_create_context")) {
        int attribs[] = {
            WGL_CONTEXT_MAJOR_VERSION_ARB, 3,
            WGL_CONTEXT_MINOR_VERSION_ARB, 3,
            WGL_CONTEXT_PROFILE_MASK_ARB, WGL_CONTEXT_CORE_PROFILE_BIT_ARB,
            0
        };
        HGLRC newCtx = wglCreateContextAttribsARB(hdc, 0, attribs);
        if (newCtx) {
            wglMakeCurrent(NULL, NULL);
            wglDeleteContext(tempContext);
            gl33Context = newCtx;
            wglMakeCurrent(hdc, gl33Context);
        }
    }

    std::cout << "[OpenGL] Vendor:   " << glGetString(GL_VENDOR) << "\n";
    std::cout << "[OpenGL] Renderer: " << glGetString(GL_RENDERER) << "\n";
    std::cout << "[OpenGL] Version:  " << glGetString(GL_VERSION) << "\n";
    std::cout << "[OpenGL] GLSL:     " << glGetString(GL_SHADING_LANGUAGE_VERSION) << "\n\n";

    // Set VSync
    if (wglSwapIntervalEXT) {
        wglSwapIntervalEXT(1); // Enable vsync by default
        std::cout << "[VSync] Enabled by default (Press 'V' to unlock FPS)\n";
    }

    // 4. Initialize projectM
    g_pm = projectm_create();
    if (!g_pm) {
        std::cerr << "[projectM] projectm_create() failed!\n";
        return 1;
    }

    projectm_set_window_size(g_pm, windowWidth, windowHeight);
    projectm_set_fps(g_pm, 120);
    projectm_set_beat_sensitivity(g_pm, 1.2f);

    // Initial preset load
    if (!g_preset_files.empty()) {
        for (size_t i = 0; i < g_preset_files.size(); ++i) {
            if (g_preset_files[i].find("300-beatdetect") != std::string::npos ||
                g_preset_files[i].find("100-square") != std::string::npos) {
                g_current_preset_idx = (int)i;
                break;
            }
        }
        CyclePreset(0);
    }

    std::cout << "\nControls:\n";
    std::cout << "  [SPACE] / [Right Arrow] : Next preset\n";
    std::cout << "  [Left Arrow]            : Previous preset\n";
    std::cout << "  [V]                     : Toggle VSync (Capped vs Uncapped 120+ Hz)\n";
    std::cout << "  [S]                     : Toggle Audio Source (Sine vs File)\n";
    std::cout << "  [ESC]                   : Exit\n\n";

    // 5. Main Render Loop
    float pcm_drain_buf[576 * 2]; // 576 stereo frames matches projectM internal ring
    auto prev_time = std::chrono::high_resolution_clock::now();
    auto fps_timer = prev_time;
    int frame_count = 0;
    double rolling_fps = 0.0;
    double min_frame_time_ms = 999.0;
    double max_frame_time_ms = 0.0;

    MSG msg;
    while (g_running) {
        while (PeekMessage(&msg, NULL, 0, 0, PM_REMOVE)) {
            if (msg.message == WM_QUIT) {
                g_running = false;
                break;
            }
            TranslateMessage(&msg);
            DispatchMessage(&msg);
        }
        if (!g_running) break;

        auto now = std::chrono::high_resolution_clock::now();
        double dt_ms = std::chrono::duration<double, std::milli>(now - prev_time).count();
        prev_time = now;

        if (dt_ms < min_frame_time_ms) min_frame_time_ms = dt_ms;
        if (dt_ms > max_frame_time_ms) max_frame_time_ms = dt_ms;

        // A. Drain newest audio from lock-free ring and push to projectM
        size_t frames_available = g_pcm_ring.PopLatest(pcm_drain_buf, 576);
        if (frames_available > 0) {
            projectm_pcm_add_float(g_pm, pcm_drain_buf, (unsigned int)frames_available, PROJECTM_STEREO);
        }

        // B. Render Frame
        projectm_opengl_render_frame(g_pm);

        // C. Present to Window
        SwapBuffers(hdc);

        // D. Telemetry & FPS calculation
        frame_count++;
        double elapsed_sec = std::chrono::duration<double>(now - fps_timer).count();
        if (elapsed_sec >= 0.5) { // Update window title twice per second
            rolling_fps = frame_count / elapsed_sec;
            frame_count = 0;
            fps_timer = now;

            std::string preset_name = g_preset_files.empty() ? "None" : fs::path(g_preset_files[g_current_preset_idx]).stem().string();
            char title[256];
            snprintf(title, sizeof(title),
                "projectM 4.1.8 | FPS: %.1f (%.2f ms) | VSync: %s | Audio: %s | Preset: %s",
                rolling_fps, dt_ms, g_vsync ? "ON" : "OFF (Uncapped)",
                g_use_synthetic_sine ? "60Hz Sine" : "File", preset_name.c_str()
            );
            SetWindowText(hwnd, title);

            // Log benchmark stats periodically if uncapped
            if (!g_vsync) {
                std::cout << "[Benchmark] FPS: " << rolling_fps
                          << " | FrameTime: " << dt_ms << " ms"
                          << " (Min: " << min_frame_time_ms << "ms, Max: " << max_frame_time_ms << "ms)" << std::endl;
            }
            min_frame_time_ms = 999.0;
            max_frame_time_ms = 0.0;
        }
    }

    // Cleanup
    std::cout << "\n[Teardown] Cleaning up resources...\n";
    ma_device_stop(&g_audio_device);
    ma_device_uninit(&g_audio_device);
    if (g_has_decoder) {
        ma_decoder_uninit(&g_audio_decoder);
    }

    if (g_pm) {
        projectm_destroy(g_pm);
    }

    wglMakeCurrent(NULL, NULL);
    wglDeleteContext(gl33Context);
    ReleaseDC(hwnd, hdc);
    DestroyWindow(hwnd);

    std::cout << "[Teardown] Complete. Exiting successfully.\n";
    return 0;
}
