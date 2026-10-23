# libprojectM × Flutter — Delivery Plan

**Status:** Draft for review · **Owner:** wambugukinyua · **Date:** 2026-10-20
**Scope:** Build a first-class Flutter package that renders Milkdrop `.milk` presets with libprojectM 4.1.8, driven by audio, and surfaces the result to a Flutter app via `dart:ffi`.

---

## 1. Goal & success criteria

Ship a Flutter plugin package (`projectm_visualizer`) plus a working example app that proves the whole chain end to end.

**Definition of success (all must hold):**

| # | Criterion | How it is proven |
|---|---|---|
| S1 | A `.milk` preset loads and renders | Example app shows motion reacting to audio; screenshot in `docs/` |
| S2 | Audio drives the visuals | 60 Hz sine → visible bass response; asserted programmatically (§8) |
| S3 | Rendering is GPU-side, zero-copy to the compositor | Android: EGL window surface on Flutter `SurfaceProducer`; desktop: FBO + readback fallback, documented |
| S4 | Frame rate ≥ 30 fps at 720p on the dev machine | On-screen FPS counter + benchmark test |
| S5 | No leaks / no crashes over a 30-minute soak | Soak test in `integration_test/`, memory flat ±5 % |
| S6 | The package is publishable | `flutter pub publish --dry-run` passes; `flutter analyze --fatal-infos` clean |
| S7 | CI is green on Windows + Linux + Android emulator | GitHub Actions badge in the README |

**Explicit non-goals for v1:** iOS/macOS GPU path (stub only), preset playlists/transition choreography, Web (libprojectM is not GLES-on-web ready in this tree), audio *input* (mic/line-in) — v1 is file/stream driven only.

### Delivery sequence at a glance

```
M0  native spike ──────────────►  proves GL 3.3 core + .milk loading on this machine
                                 (no Flutter involved; 1 day of risk removed)
M1  vendor + libpmvis (C ABI) ─►  native library with a tested, documented ABI
M2  flutter package + FFI ─────►  `flutter/projectm_visualizer/` publishable skeleton
                                 + generated bindings + facade
M3  example app on desktop ────►  THE EXAMPLE APP: renders a .milk, reacts to audio,
                                 shows telemetry → "does it work?" answered on Windows
M4  example app on Android ───►  same app on the real target (SurfaceProducer path)
M5  audio sources ─────────────►  miniaudio decoder (self-contained) + sautiflow tap
M6  hardening + CI ────────────►  publishable, soak-tested, CI-green
```

**The example app is the acceptance harness**, not a toy: it is where "everything works" is demonstrated — preset loading, audio-driven motion, telemetry, lifecycle (background/foreground), and the failure modes (missing preset, no GL, dropped audio) rendered as typed errors in the UI.

---

## 2. Verified technical facts (the constraints that shape the design)

Every item below was verified against this working tree, this machine, or the cited upstream documentation — not from memory.

| # | Fact | Evidence | Design consequence |
|---|---|---|---|
| F1 | libprojectM's public API is already a flat `extern "C"` ABI | `src/api/include/projectM-4/core.h:43,71,87`, `audio.h:59`, `render_opengl.h:42`, `parameters.h:266` | `dart:ffi` binds `projectm_*` directly. No C++ shim required for the API surface. |
| F2 | `RenderFrame()` hard-binds draw-FBO **0** (`glBindFramebuffer(GL_DRAW_FRAMEBUFFER, 0)`) | `src/libprojectM/ProjectM.cpp:170` (+ ToDo at :169) | projectM can **only** draw into the default framebuffer. The Flutter target surface must therefore *be* the GL default framebuffer → window surface, not an FBO. |
| F3 | Desktop build compiles GLSL `#version 330` (needs **GL 3.3 core**) | `src/libprojectM/MilkdropPreset/MilkdropStaticShaders.cpp.in:35`, `src/libprojectM/Renderer/CopyTexture.cpp:12` | Desktop needs a real desktop-GL context. Flutter Windows' engine context is ANGLE/GLES2 → **not shareable**. |
| F4 | GLES build compiles GLSL `#version 300 es` (needs **GLES 3.0**) | `MilkdropStaticShaders.cpp.in:30`, `CopyTexture.cpp:10` | Android path is GLES3 via EGL. `ENABLE_GLES` is force-enabled for Android by the root `CMakeLists.txt`. |
| F5 | Windows requires GLEW (headers + lib) | `src/libprojectM/projectM-opengl.h:28-29`; root `CMakeLists.txt` (`find_package(GLEW REQUIRED)`); `vcpkg.json` declares `glew` for windows | Windows desktop build needs vcpkg (or prebuilt GLEW). Not installed on this machine — see M0. |
| F6 | PCM input is **interleaved** LRLRLR, float in ±1 | `src/libprojectM/Audio/PCM.cpp:10-34` | Feed interleaved stereo floats; chunk to ≤ 576 frames (F7). |
| F7 | Internal PCM ring is 576 samples/channel; `Add()` wraps, it does not queue | `src/libprojectM/Audio/AudioConstants.hpp:8`, `PCM.cpp:10` | Push ≤ 576 frames per call; the ring holds the *most recent* audio, which is what the analyser wants. |
| F8 | `PCM::Add` and `PCM::UpdateFrameAudioData` are not mutually synchronised | `PCM.cpp` (plain writes vs plain reads) | Feed PCM **from the render thread**, never concurrently from Dart. |
| F9 | `projectm_create()` requires a **current** GL context; `projectm_set_window_size` must be set or nothing is drawn | `src/api/include/projectM-4/core.h:35-43`; `ProjectM.cpp` early-return on 0×0 | Context creation and instance creation happen on the same native thread, in that order. |
| F10 | `.milk` is plain text; `projectm_load_preset_data` takes a NUL-terminated string | `core.h:87`; `ProjectMCWrapper.cpp:87` (builds `std::stringstream`) | Presets can be loaded straight from Flutter assets. Binary-unsafe but `.milk` is text. |
| F11 | `sautiflow` already exposes a **raw, non-windowed** interleaved L/R tap | `miniaudiodart/audio_engine.h:586` (`ae_poll_analyzer_frame_stereo`), impl `audio_engine.cpp:4163` | Audio source for the visualiser can be the existing engine — no second audio stack. |
| F12 | This tree carries a local GLES fix (explicit `glDrawBuffers(GL_BACK)` after preset render) | `src/libprojectM/ProjectM.cpp:165-175` | Vendoring must preserve the working tree, not a pristine upstream checkout. |
| F13 | Flutter's Android embedder ships `TextureRegistry.SurfaceProducer`; it is the **recommended** producer API under Impeller (ImageReader/HardwareBuffer backend on API 29+) | `javap` on `engine/android-arm64/flutter.jar`; `docs.flutter.dev/release/breaking-changes/android-surface-plugins` | Our GLES3 producer writes into `producer.getSurface()`; Impeller's Vulkan backend samples that Surface natively. |
| F14 | Impeller is the default renderer on Android API 29+ **and on Windows since 3.47** | `docs.flutter.dev/perf/impeller` | Confirms F3: no engine context to borrow on any platform. `--no-enable-impeller` exists as a debug escape hatch only. |
| F15 | `SurfaceProducer.scheduleFrame()` is "not officially part of the public API surface and will be deprecated" | Flutter API docs, `TextureRegistry.SurfaceProducer` | We never call it: an EGL `eglSwapBuffers` into the Surface is the frame signal. |

### Environment baseline (measured, not assumed)

| Tool | Version / path | Status |
|---|---|---|
| Flutter | **3.47.7** — installed at `C:\flutter\3.27.3` ⚠️ *the folder name is stale; pin by `flutter --version`, never by path* | ✅ |
| Dart | **3.13.5** (bundled, DevTools 2.60.0) | ✅ |
| CMake (host) | 3.22.1 | ✅ (libprojectM needs ≥ 3.21) |
| Ninja | 1.10.2 | ✅ |
| Android SDK | `C:\androidsdk` | ✅ |
| Android NDK | 28.2.13676358 | ✅ |
| Android SDK CMake | 3.22.1 | ✅ (satisfies libprojectM's ≥ 3.21) |
| JDK | OpenJDK 21.0.6 | ✅ |
| Git | 2.47.1 | ✅ |
| vcpkg | **not installed** | ❌ blocker for Windows desktop → M0 step 0 |
| ffigen | 11.0.0 and 20.1.1 in pub cache | ⚠️ 20.1.1 matches Dart 3.13 → D-4 |

---

## 3. Target architecture

```
┌──────────────────────── Flutter (Dart) ────────────────────────┐
│  ProjectMVisualizer (public facade)                           │
│    ├─ loadPreset(File|Data)      → queued to native            │
│    ├─ pushPcm(Float32List)       → queued to native            │
│    ├─ resize(w,h) / setFps(n)    → queued to native            │
│    └─ dispose()                  → signals + joins native      │
│  ExampleApp: Texture (Android) / Image (desktop) + telemetry   │
└───────────────────────────────┬────────────────────────────────┘
                                │ dart:ffi (C ABI, no callbacks crossing FFI)
┌───────────────────────────────▼────────────────────────────────┐
│  libpmvis  (native, C++17, one .so/.dll)                      │
│  ┌──────────────┐   ┌────────────────┐   ┌───────────────────┐  │
│  │ CommandQueue │   │  PCM SPSC ring │   │  Render thread    │  │
│  │ (Dart→Native)│   │ (Native←Dart)  │   │  ─ owns GL ctx    │  │
│  └──────────────┘   └────────────────┘   │  ─ owns instance  │  │
│                                          │  ─ drains both    │  │
│                                          │  ─ renders+swap  │  │
│                                          └────────┬──────────┘  │
└───────────────────────────────────────────────────┼─────────────┘
                     libprojectM (C API)           │ GL/EGL/WGL
            projectm_create / load_preset / pcm_add_float /
            set_window_size / opengl_render_frame
                                                   ▼
        Android: EGL window surface on Flutter SurfaceProducer  → Texture
        Desktop: WGL pbuffer (= FBO 0) → glReadPixels → RGBA → ui.decodeImageFromPixels → RawImage
```

**Threading contract (non-negotiable, enforced by design):**

- Exactly **one** thread owns the GL context, the projectM instance, and all projectM calls.
- Dart calls only ever enqueue commands / PCM into lock-free structures. Never touch projectM directly.
- PCM is consumed by the render thread and pushed with `projectm_pcm_add_float` immediately before `projectm_opengl_render_frame` → satisfies F8.
- No FFI callbacks from native → Dart (avoids isolate re-entrancy hazards); telemetry is pulled by Dart on a timer.

**Lifecycle contract:**

- `ProjectMVisualizer.create()` → native spawns render thread, creates context + instance, returns handle.
- `attachSurface(...)` (Android) → binds the Flutter `Surface` to an EGL window surface.
- `dispose()` → enqueue `stop`, join thread, destroy GL resources in context order (surface → context → instance), free handle. Idempotent.

---

## 4. Repository layout (target)

```
libprojectM-4.1.8/                    ← existing C++ tree (untouched except vendoring step)
├── src/ vendor/ presets/ …           ← libprojectM 4.1.8 as-is
└── flutter/                          ← NEW: all Flutter-side work
    ├── PLAN.md                       ← this document
    ├── projectm_visualizer/          ← the plugin package
    │   ├── lib/
    │   │   ├── projectm_visualizer.dart        ← public facade (barrel)
    │   │   └── src/
    │   │       ├── bindings/pmvis_bindings.dart        ← ffigen-generated (committed)
    │   │       ├── engine/project_m_visualizer.dart     ← facade impl
    │   │       ├── engine/visualizer_commands.dart     ← typed command enum
    │   │       ├── engine/preset_source.dart           ← sealed preset source
    │   │       ├── engine/failures.dart                ← sealed ProjectMFailure
    │   │       ├── platform/native_library.dart         ← per-platform DynamicLibrary.open
    │   │       └── platform/texture_surface.dart        ← Android Texture / desktop Image
    │   ├── src/                       ← native sources, shared by all platforms
    │   │   ├── CMakeLists.txt
    │   │   ├── pmvis.h                ← the C ABI (single source of truth)
    │   │   ├── pmvis.cpp              ← facade: queue, ring, lifecycle
    │   │   ├── pmvis_render.cpp       ← render thread + frame loop
    │   │   ├── pmvis_gl.h/.cpp        ← GL context abstraction (EGL / WGL / GLX)
    │   │   ├── pmvis_pcm_ring.h/.cpp  ← lock-free SPSC ring
    │   │   └── pmvis_queue.h/.cpp     ← lock-free command queue
    │   ├── android/                   ← Kotlin plugin (SurfaceProducer) + Gradle NDK build
    │   │   ├── build.gradle
    │   │   └── src/main/kotlin/com/wambugu/projectm_visualizer/ProjectMVisualizerPlugin.kt
    │   ├── ios/ macos/ linux/ windows/  ← ffiPlugin: true (Linux/Windows CMake, Darwin podspec)
    │   ├── third_party/projectm/      ← vendored libprojectM snapshot (see M1)
    │   ├── example/                   ← the example app (acceptance harness)
    │   ├── test/                      ← Dart unit + integration tests
    │   ├── ffigen.yaml
    │   ├── pubspec.yaml
    │   └── analysis_options.yaml
    ├── docs/                          ← screenshots, architecture diagram, ADRs
    ├── tools/spike/                   ← M0 native spike (console app, no Flutter)
    └── ci/                            ← GitHub Actions workflows
```

Naming follows the house conventions: `Screen`/`Notifier`/`Repository`-style role suffixes are **not** applicable (this is a package, not an app); we use `*_engine`, `*_bindings`, `*_commands`, `*_failures`.

---

## 5. Interfaces

### 5.1 Native C ABI (`src/pmvis.h`) — the only ABI the Dart side depends on

```c
typedef struct PmVis PmVis;

/* Lifecycle */
PmVis*   pmvis_create(void);                 /* spawns render thread; NULL on failure      */
void     pmvis_destroy(PmVis*);              /* idempotent; joins thread; frees resources   */
int      pmvis_attach_surface(PmVis*, void* native_window, int w, int h); /* EGL/WGL target   */
void     pmvis_detach_surface(PmVis*);

/* Configuration (queued; safe from any thread) */
int      pmvis_set_size(PmVis*, int w, int h);
int      pmvis_set_fps(PmVis*, int fps);
int      pmvis_load_preset_data(PmVis*, const char* data, size_t len, int smooth);
int      pmvis_load_preset_file(PmVis*, const char* path, int smooth);
void     pmvis_set_texture_search_path(PmVis*, const char* dir);

/* Audio (queued; consumed on the render thread) */
int      pmvis_push_pcm(PmVis*, const float* interleaved_lr, unsigned frames);

/* Telemetry (pulled) */
typedef struct PmVisStats {
    double  fps;            /* measured over the last second            */
    double  bass, mid, treb;/* most recent projectM frame audio values   */
    uint32_t frames_rendered;
    uint32_t pcm_frames_dropped;
    int      last_error;     /* 0 = none                                 */
} PmVisStats;
int      pmvis_get_stats(PmVis*, PmVisStats* out);
const char* pmvis_last_error_message(PmVis*);
```

Rules: POD-only structs; `cdecl`; `__declspec(dllexport)` on Windows, `__attribute__((visibility("default")))` elsewhere; no exceptions crossing the boundary; every function returns `int` status or a nullable pointer.

### 5.2 Dart public surface

```dart
final class ProjectMVisualizer {
  static Future<ProjectMVisualizer> create({PresetSource? preset});
  Future<void> loadPreset(PresetSource source, {bool smoothTransition = true});
  Future<void> setSize(int width, int height);
  Future<void> setFps(int fps);
  Future<void> pushPcm(Float32List interleavedStereo);
  Future<VisualizerStats> stats();
  Future<void> dispose();
}
```

- `PresetSource` is a **sealed** type: `PresetFile(path)` | `PresetData(bytes)`.
- `VisualizerStats` is an immutable value type with value equality.
- Failures are **returned**, not thrown: `ProjectMFailure` sealed (`glContextUnavailable`, `presetParseFailed`, `surfaceUnavailable`, `nativeLibraryMissing`, `outOfMemory`) with a stable `code` — never a localized string.

---

## 6. Milestones

Each milestone has a **gate**: the listed verification commands must pass before the next starts. No milestone starts with a failing gate.

### M0 — Toolchain baseline & native spike *(no Dart yet)*

**Why first:** the two highest-risk facts (F3/F5 — GL 3.3 core + GLEW on Windows) are cheapest to disprove here, before any Flutter scaffolding exists.

**Steps**
1. Bootstrap vcpkg (`C:\vcpkg\vcpkg.exe bootstrap`; `vcpkg install glew:x64-windows`) — satisfies F5, and the repo's `vcpkg.json` already declares it.
2. Build libprojectM standalone, Release:
   ```powershell
   cmake -S . -B build/projectm -G Ninja `
     -DCMAKE_BUILD_TYPE=Release `
     -DCMAKE_TOOLCHAIN_FILE=C:/vcpkg/scripts/buildsystems/vcpkg.cmake `
     -DENABLE_INSTALL=OFF -DENABLE_PLAYLIST=OFF -DENABLE_SDL_UI=OFF -DBUILD_TESTING=OFF
   cmake --build build/projectm --target projectM -j
   ```
3. Build the **spike**: `flutter/tools/spike/spike.cpp` — a ~200-line console app that:
   - creates a hidden WGL window + GL 3.3 core context, prints `glGetString(GL_VERSION)` / `GL_SHADING_LANGUAGE_VERSION`, and **fails loudly if either is below 3.3 / 3.30** (this is the F3 gate),
   - asserts `projectm_create()` returns non-NULL *with the context current* (this is the F9 gate),
   - `projectm_set_window_size(640,360)` → `projectm_load_preset_file("presets/tests/100-square.milk")`,
   - feeds 512 frames of a 60 Hz sine before each rendered frame — projectM keeps only the newest 576 samples (F7), so this is a *synthetic driver*, not a real-time clock; the spike's job is to prove the render path, not the timing,
   - calls `projectm_opengl_render_frame()` and reads the **default framebuffer** (`glReadBuffer(GL_BACK)` + `glReadPixels`) — this is exactly the F2 constraint under test: projectM draws to FBO 0, so the spike must read the window's back buffer, not an FBO,
   - writes `flutter/docs/spike/frame.png` using the vendored `vendor/SOIL2` (`stb_image_write`, already in-tree) and asserts the image is not uniformly black.
4. Same spike built for Android NDK (no window): EGL **pbuffer** surface → proves the GLES3 path compiles and renders off-device.

**Gate**
```powershell
cmake --build build/projectm -j            # exit 0
.\build\spike.exe                          # prints "GL_VERSION=…", writes frame.png, exit 0
```
**Exit criteria:** `frame.png` exists, is non-black, and the console reports GL ≥ 3.3 / GLSL ≥ 3.30.
**Rollback:** delete `build/`, `flutter/tools/spike/` — nothing else depends on it.

---

### M1 — Vendor libprojectM + native `libpmvis` (C ABI, no Flutter)

**Steps**
1. Vendor the working tree into `flutter/projectm_visualizer/third_party/projectm` — **copy the current tree, do not re-clone upstream** (F12: the local GLES `glDrawBuffers` fix must survive). Record the provenance (upstream 4.1.8 + local patch list) in `third_party/projectm/VENDOR.md`.
2. `src/CMakeLists.txt`:
   ```cmake
   cmake_minimum_required(VERSION 3.22)          # libprojectM needs ≥3.21
   project(projectm_visualizer_native LANGUAGES C CXX)
   set(CMAKE_CXX_STANDARD 17)
   set(PROJECTM_SOURCE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../third_party/projectm" CACHE PATH "")
   add_subdirectory(${PROJECTM_SOURCE_DIR} ${CMAKE_CURRENT_BINARY_DIR}/projectm EXCLUDE_FROM_ALL)
   add_library(pmvis SHARED pmvis.cpp pmvis_render.cpp pmvis_gl.cpp pmvis_pcm_ring.cpp pmvis_queue.cpp)
   target_link_libraries(pmvis PRIVATE projectM Threads::Threads)
   ```
   Note: `add_subdirectory` of libprojectM must not re-enter its own `project()` options — pass `-DENABLE_INSTALL=OFF -DENABLE_PLAYLIST=OFF -DENABLE_SDL_UI=OFF` as cache defaults in `pmvis`'s `CMakeLists.txt`.
3. Implement `pmvis.h`/`.cpp`:
   - `pmvis_create()` → spawn render thread; thread creates GL context (EGL on Android, WGL on Windows, GLX on Linux), `eglMakeCurrent`, then `projectm_create()`, `projectm_set_window_size`, `projectm_set_fps(30)`, `projectm_set_preset_locked(true)`. Startup handshake via `std::promise`/condition variable; `pmvis_create` returns only after the instance is live, or `nullptr` with an error message.
   - Command queue: MPSC ring of tagged commands (resize / fps / load preset data / load preset file / set texture path / stop).
   - PCM ring: SPSC, float, capacity 8192 frames, drop-oldest on overflow, counters exposed in stats.
   - Frame loop: drain commands → pull PCM → `projectm_pcm_add_float(handle, buf, n, PROJECTM_STEREO)` → `projectm_opengl_render_frame(handle)` → present (EGL `eglSwapBuffers` / WGL `SwapBuffers`).
   - Desktop presentation path (**F2-compliant**): projectM always draws to draw-FBO 0, so the desktop target must be a **pbuffer** (WGL/GLX) or a hidden window whose *default framebuffer* is the render target. We then read it back with `glReadBuffer(GL_FRONT|GL_BACK)` + `glReadPixels` into a reusable RGBA buffer and publish it to the Dart-side pixel sink. We never bind our own FBO — projectM would override it.
   - Android presentation path: the EGL **window surface** on the Flutter `Surface` is the default framebuffer, so projectM's `eglSwapBuffers` publishes it directly (no readback).
4. Native unit tests (CTest, no GL): PCM ring (wrap, overflow, torn-read detection), command queue (ordering, capacity), preset-text validation.

**Gate**
```powershell
cmake -S flutter/projectm_visualizer/src -B build/pmvis -G Ninja -DCMAKE_BUILD_TYPE=Release
cmake --build build/pmvis -j
ctest --test-dir build/pmvis --output-on-failure      # all green
```
**Exit criteria:** `libpmvis.dll`/`libpmvis.so` exports exactly the §5.1 symbols; `nm`/`dumpbin` shows no projectM symbol leakage beyond the intended linkage; CTest green.
**Rollback:** delete `flutter/projectm_visualizer/src` + `build/pmvis`.

---

### M2 — Flutter package skeleton + FFI bindings (pure Dart, no rendering)

**Steps**
1. Scaffold (the template already provides the FFI/CMake/ffigen wiring — `templates/plugin_ffi`):
   ```powershell
   cd flutter
   flutter create --template=plugin_ffi --org com.wambugu `
     --project-name projectm_visualizer `
     --platforms=android,ios,macos,linux,windows projectm_visualizer
   ```
   Generated: `src/CMakeLists.txt` (shared by Android `externalNativeBuild` + Linux/Windows), `ffigen.yaml`, `lib/*_bindings_generated.dart`, `example/`.
2. Wire `ffigen.yaml` to `src/pmvis.h` (not the template's placeholder header); pin ffigen (D-4); commit generated bindings.
3. Replace the template's stub with the §5.2 facade:
   - `native_library.dart` → per-platform `DynamicLibrary.open` (`libpmvis.dll` / `libpmvis.so` / `libpmvis.dylib`).
   - `ProjectMVisualizer` — owns the handle; `dispose()` is idempotent; every method returns `Result`-style values (sealed `ProjectMFailure`).
   - Dart-side PCM staging: `Float32List` → `calloc<Float>(n)` → `copy` → `pmvis_push_pcm` → `free`. **Never** `calloc` per frame in a hot loop — keep one reusable buffer.
4. `analysis_options.yaml`: `include: package:very_good_analysis/analysis_options.yaml` (pinned) + `strict-casts`/`strict-raw-types`/`public_member_api_docs`. **Note:** `very_good_analysis` is *not* in the local pub cache (only `lints` 6.1.0 is) → one network fetch, or fall back to `lints: ^6.1.0` plus explicit strict flags if the build must stay offline. Decide at M2 and record the choice.
5. Static analysis gates wired: `dart format --set-exit-if-changed`.

**Gate**
```powershell
cd flutter/projectm_visualizer
dart pub get
dart run ffigen --config ffigen.yaml
dart analyze --fatal-infos            # 0 issues
dart format --set-exit-if-changed .
flutter test                            # unit tests green
```
**Exit criteria:** `ProjectMVisualizer.create()` succeeds on the host and `stats()` returns a sane struct (proves the .so loads and the thread starts) — even though nothing renders yet on desktop.
**Rollback:** delete `flutter/projectm_visualizer`, keep `flutter/PLAN.md`.

---

### M3 — Desktop rendering path (Windows first — this is the dev machine)

**Steps**
1. WGL context on a background thread (`CreateWindowEx` hidden + `wglCreateContext` + GLEW for the 3.3 entry points — GLEW is already a dependency via vcpkg, F5).
   Impeller is the default engine on Windows since 3.47 (F14) and still exposes no GL 3.3 context to plugins, so this own-context design stands. `--no-enable-impeller` is available as a debugging escape hatch but changes nothing about the constraint.
2. Desktop target = a WGL **pbuffer** (no visible window, no compositor involvement) whose default framebuffer is FBO 0 — the only place projectM can draw (F2). `glReadBuffer(GL_FRONT)` + `glReadPixels` → RGBA byte buffer → publish to the Dart-side pixel sink. pbuffer size tracks the requested size; `projectm_set_window_size` must be kept in sync with it.
3. Dart side: `VisualizerFrameSource` polls the native pixel buffer (double-buffered, seqlock-style) → `ui.decodeImageFromPixels` → `ui.Image` → `RawImage` widget (no implicit repaint storms: rebuild only on new frame id).
4. Example app v1: load `presets/tests/100-square.milk` (or a bundled user preset), feed a 60 Hz sine, show the visualization + FPS + bass/mid/treb telemetry + a preset picker.

**Gate**
```powershell
cd flutter/projectm_visualizer/example
flutter run -d windows     # manual: visuals move, bass meter reacts
flutter test integration_test --reporter expanded   # headless smoke on Windows
```
**Exit criteria:** ≥ 30 fps at 1280×720 on the dev machine (measured, printed in the app); a 60 Hz sine raises the reported `bass` value by ≥ 3× the silence baseline; 10-minute soak shows flat memory.
**Rollback:** feature-flag the desktop path off (`--dart-define=PMV_DESKTOP=off`) — Android path unaffected.

---

### M4 — Android rendering path (the real target)

**Steps**
1. `android/build.gradle` — the template already wires `externalNativeBuild { cmake { path = "../src/CMakeLists.txt" } }`. **Pin `version "3.22.1"`** (SDK-installed; libprojectM needs ≥ 3.21 — the template's default 3.10.2 is *not* enough). Confirm `ndkVersion` matches the app's (28.2.13676358 here).
2. Kotlin plugin `ProjectMVisualizerPlugin` — exact API surface (verified against the 3.47.7 engine jar):
   ```kotlin
   // SurfaceLifecycle.resetInBackground → the surface is reset when the app is
   // backgrounded and re-delivered via onSurfaceAvailable().
   val producer = flutterEngine.textureRegistry
       .createSurfaceProducer(TextureRegistry.SurfaceLifecycle.resetInBackground)
   producer.setSize(widthPx, heightPx)              // physical pixels
   producer.setCallback(object : TextureRegistry.SurfaceProducer.Callback {
       override fun onSurfaceAvailable() { /* (re)create EGL window surface */ }
       override fun onSurfaceCleanup()    { /* destroy EGL window surface, stop rendering */ }
   })
   nativeAttachSurface(producer.surface)              // JNI: ANativeWindow_fromSurface
   // → Dart: Texture(textureId: producer.id())
   ```
   Rules: **never** `surface.release()` (the engine owns it); **never** call `scheduleFrame()` (deprecated, F15); `producer.handlesCropAndRotation()` returns `false` on the ImageReader backend — harmless for us because we render a full-frame image with no rotation metadata (document it in the plugin README).
3. Native EGL: `eglGetDisplay(EGL_DEFAULT_DISPLAY)`, config with `EGL_RENDERABLE_TYPE=EGL_OPENGL_ES3_BIT`, **`EGL_RECORDABLE_ANDROID=1`** (mandatory for Flutter's Surface), `EGL_CONTEXT_CLIENT_VERSION=3`, `eglCreateWindowSurface` on the `ANativeWindow`, `eglSwapBuffers` per frame. projectM is built GLES3 on Android automatically (F4).
   Under Impeller/Vulkan the engine samples our Surface as a HardwareBuffer — this is the officially supported producer path (F13), so no `VK_ANDROID_external_memory_android_hardware_buffer` work is needed on our side.
4. Dart: `VisualizerSurface` widget → `Texture(textureId: producer.id())`.

**Gate**
```powershell
cd flutter/projectm_visualizer/example
flutter build apk --debug
adb install -r build/app/outputs/flutter-apk/app-debug.apk
# manual + scripted:
flutter test integration_test -d <emulator-id>
```
**Exit criteria:** visualization renders on a device/emulator at ≥ 30 fps; survives background→foreground 20× without "BufferQueue abandoned" or context loss; `adb logcat` free of `EGL_BAD_*` / `GL_INVALID_*`.
**Rollback:** the package still supports desktop; Android plugin can be disabled via pubspec platform map.

---

### M5 — Audio source integration

**Two providers behind one Dart interface `PcmSource`:**

- **M5a (v1, self-contained):** native miniaudio decoder. `ma_decoder_init_file` → read ≤ 576 frames per call → `pmvis_push_pcm`. Also drives an optional `ma_device` for audible playback (playback and visualisation read the same decoder, so they cannot drift).
- **M5b (v1.1, integration with `sautiflow`):** use the existing raw stereo tap (F11): `ae_poll_analyzer_frame_stereo` → `pmvis_push_pcm`. Slight drawback: it is a *snapshot* of the most recent window (frames can be skipped at 35 fps polling), so add a small native ring in the sautiflow side if drop-free delivery matters.

**Gate:** the example app plays a bundled audio file; bass/mid/treb telemetry tracks the file's energy; visual motion correlates with the beat.
**Exit criteria:** no drift between audio position and visualisation state over a 3-minute track; `pcm_frames_dropped == 0` in stats.

---

### M6 — Hardening, packaging, CI

- `flutter pub publish --dry-run` clean; CHANGELOG; LICENSE (LGPL-2.1 for the vendored libprojectM — **must** be surfaced in the package's licence file).
- GitHub Actions matrix:
  | Job | Runner | What it proves |
  |---|---|---|
  | `analyze` | ubuntu | `dart format --set-exit-if-changed`, `dart analyze --fatal-infos`, `flutter test` |
  | `native` | ubuntu + windows | libprojectM + libpmvis build; CTest green |
  | `desktop-e2e` | ubuntu (xvfb + Mesa llvmpipe) | example app renders a non-black frame headlessly (software GL is fine) |
  | `android-e2e` | ubuntu + KVM emulator | SurfaceProducer path renders; APK installs |
- Soak test (30 min) in `integration_test/`, memory-flat assertion.

---

## 7. Build & release engineering

- **Version pinning:** record the output of `flutter --version` (**Flutter 3.47.7 / Dart 3.13.5** — the install folder is named `3.27.3` and lies), NDK 28.2.13676358, SDK CMake 3.22.1, host CMake 3.22.1, Ninja 1.10.2, JDK 21.0.6 in `docs/ENVIRONMENT.md`; CI pins the same versions. Never reference the SDK by folder path in scripts.
- **One native CMake entry point:** `src/CMakeLists.txt` is consumed by Android (`externalNativeBuild`), Linux, Windows (`ffiPlugin`), and by our own dev scripts → no duplicated build definitions.
- **Linux/Windows `ffiPlugin` wiring:** the generated `linux/CMakeLists.txt` / `windows/CMakeLists.txt` already `add_subdirectory(../src)`; we only need to add `pmvis` to the bundled-libraries list.
- **Darwin:** podspec must include `src/**` and the vendored tree; `ffiPlugin: true` for ios/macos is *deferred* (v1 = Android + Windows).
- **CI caches:** vcpkg binary cache, NDK, pub cache, CMake presets per OS.

---

## 8. Test strategy

**Principle: projectM is wall-clock driven — it is not pixel-deterministic.** (It advances on `TimeKeeper`/`DateTime`, so two runs at different times differ.) Therefore:

| Layer | Technique | Asserts |
|---|---|---|
| Native unit | CTest on ring buffer / queue / preset parsing | wrap-around, overflow policy, ordering, no torn reads |
| Dart unit | `package:test` with a fake native port | facade behaviour, error mapping, dispose idempotency |
| Rendering invariant | Render N frames of a known preset with a **60 Hz sine**; assert the reported `bass` value ≫ silence baseline, and that the framebuffer is not uniform black | the audio→visual chain is alive |
| Visual regression | **No golden images.** Instead assert structural invariants: non-black pixel ratio ∈ [0.05, 0.95], mean luminance drift < 20 % over 5 s | catches "renders garbage" without brittle goldens |
| Platform e2e | `integration_test` on Windows + Android emulator | frame id advances, fps ≥ 30, no crash over 5 min |
| Soak | 30 min run | RSS growth < 5 %, handle count stable |

Any golden-based test we are tempted to write is a smell — the renderer is time-dependent.

---

## 9. Risk register

| ID | Risk | Likelihood | Impact | Mitigation | Trigger → action |
|---|---|---|---|---|---|
| R1 | Flutter Windows' ANGLE/GLES2 context cannot host projectM (F3) | certain | high | Own WGL context + readback (M3). Never assume engine-context sharing. | Desktop frame rate < 24 fps → drop to 720p or move readback to a background isolate |
| R2 | GLEW missing on Windows (F5) | high | medium | Bootstrap vcpkg in M0 step 1; vendor GLEW headers fallback | Build fails on `GL/glew.h` → install vcpkg port |
| R3 | Android `externalNativeBuild` CMake version < 3.21 breaks libprojectM | medium | high | Pin `version "3.22.1"` in the plugin's `android/build.gradle` | CMake error → set the version and re-sync SDK |
| R4 | EGL surface leaks → "BufferQueue abandoned" | medium | high | `SurfaceProducer.Callback` → `pmvis_detach_surface`; explicit teardown order (surface→context→instance) | logcat errors → audit detach path |
| R5 | PCM ring overrun under load → dropped frames → visual stutter | medium | medium | 8192-frame ring + drop-oldest + `pcm_frames_dropped` counter surfaced in the app | counter > 0 → enlarge ring / reduce poll rate |
| R6 | projectM renders only to FBO 0 (F2) forecloses future FBO-based paths | certain | medium | Accept; document. If needed later, patch `ProjectM.cpp:170` behind a compile flag | Feature request for "render into texture" → evaluate the patch |
| R7 | Vendored tree drifts from upstream / loses the local GLES fix (F12) | medium | medium | `third_party/projectm/VENDOR.md` records provenance + patch list; CI diffs it | upstream bump → re-apply and re-run M0 |
| R8 | ffigen/Dart version mismatch | medium | low | Pin ffigen (D-4) and commit generated bindings | `dart pub get` fails → adjust pin |
| R9 | Desktop readback cost at 1080p+ | medium | medium | Cap default size at 1280×720; expose quality preset | fps < 30 → lower default size |
| R10 | LGPL-2.1 obligations when shipping the package | low | high | NOTICE file, dynamic linking, source offer for the vendored tree | release time → legal review |
| R11 | `SurfaceProducer.setSize()` is a no-op on some OEM builds (flutter#162060, Huawei p30) | low | medium | Read back `producer.getWidth()/getHeight()` and drive the EGL surface size from the *actual* surface dimensions, not from our requested size | device shows wrong aspect → query surface size each frame |
| R12 | Impeller/Vulkan consumes our produced frames differently than Skia/GLES did | medium | medium | Validate on a physical Android 10+ device **early** (M4 gate includes a device run, not only the emulator) | black/garbled texture on device → check `handlesCropAndRotation()` and buffer format |

---

## 10. Open decisions (recommended defaults in **bold**)

| ID | Decision | Options | Recommendation |
|---|---|---|---|
| D-1 | Package name / org | `projectm_visualizer` / `com.wambugu` | **as stated** — matches `sautiflow` conventions |
| D-2 | Where the native lib lives | inside the plugin package / separate repo | **inside the plugin** — one `flutter create` produces a publishable unit |
| D-3 | Vendoring libprojectM | copy tree / git submodule / vcpkg port | **copy tree + `VENDOR.md`** — preserves F12's local patch; submodule would drop it |
| D-4 | ffigen version | 11.0.0 (cached) / 20.1.1 (cached) / newest compatible | **ffigen 20.1.1** — requires Dart ≥ 3.8, satisfied by Dart 3.13.5, and already in the local pub cache (offline-friendly). Commit `pubspec.lock`. |
| D-5 | v1 platform support | Android + Windows / + all | **Android + Windows**; Linux/macOS/iOS wired but untested (declare support only when CI covers it) |
| D-6 | Desktop presentation | pbuffer readback → `RawImage` / offscreen window / ship a separate native window | **pbuffer readback → `RawImage`** — stays inside the Flutter scene, portable, no extra window (F2 forbids binding our own FBO) |
| D-7 | Audio source in v1 | native miniaudio decoder / sautiflow tap / both | **both**, behind `PcmSource`; M5a ships first (self-contained), M5b proves the integration story |

---

## 11. Definition of Done (v1)

- [ ] `flutter pub publish --dry-run` passes from `flutter/projectm_visualizer`.
- [ ] `dart analyze --fatal-infos` → 0 issues; `dart format --set-exit-if-changed .` → clean.
- [ ] `flutter test` (unit) and `integration_test` (Windows + Android emulator) green.
- [ ] Example app: loads a `.milk` from assets, renders it, reacts to audio, shows telemetry, survives a 30-min soak.
- [ ] Android APK builds and runs on a physical device (not only the emulator).
- [ ] `docs/` contains: architecture diagram, environment pins, screenshots, the ADRs for D-1…D-7.
- [ ] CI green on the §7 matrix.
- [ ] Licence/NOTICE files state LGPL-2.1 obligations for the vendored libprojectM.

---

## 12. Appendix — verified command reference

```powershell
# Scaffold the package
cd "C:\Users\wambugukinyua\OneDrive\Desktop\libprojectM-4.1.8\flutter"
flutter create --template=plugin_ffi --org com.wambugu `
  --project-name projectm_visualizer `
  --platforms=android,ios,macos,linux,windows projectm_visualizer

# libprojectM standalone (dev baseline)
cmake -S . -B build/projectm -G Ninja -DCMAKE_BUILD_TYPE=Release `
  -DCMAKE_TOOLCHAIN_FILE=C:/vcpkg/scripts/buildsystems/vcpkg.cmake `
  -DENABLE_INSTALL=OFF -DENABLE_PLAYLIST=OFF -DENABLE_SDL_UI=OFF
cmake --build build/projectm --target projectM -j

# Native plugin library
cmake -S flutter/projectm_visualizer/src -B build/pmvis -G Ninja -DCMAKE_BUILD_TYPE=Release
cmake --build build/pmvis -j
ctest --test-dir build/pmvis --output-on-failure

# Dart
cd flutter/projectm_visualizer
dart pub get
dart run ffigen --config ffigen.yaml
dart analyze --fatal-infos
dart format --set-exit-if-changed .

# Example app
cd example
flutter build apk --debug
flutter test integration_test -d <device-id>
```

**Source references used in this plan** (all inside this working tree):

- `src/api/include/projectM-4/{core.h,audio.h,render_opengl.h,parameters.h,types.h}`
- `src/libprojectM/ProjectM.cpp:170` (FBO-0 binding), `src/libprojectM/ProjectM.cpp:165-175` (local GLES fix)
- `src/libprojectM/Audio/PCM.cpp:10-34` (interleave), `src/libprojectM/Audio/AudioConstants.hpp:8` (576)
- `src/libprojectM/projectM-opengl.h:28-29` (GLEW), `src/libprojectM/MilkdropPreset/MilkdropStaticShaders.cpp.in:30,35` (GLSL versions)
- `CMakeLists.txt` (GLES forced on Android; CMake ≥ 3.21; GLEW on Windows), `vcpkg.json` (glew/windows)
- `C:\flutter\3.27.3\packages\flutter_tools\templates\plugin_ffi\*` (template wiring), `.../engine/android-arm64/flutter.jar` → `io/flutter/view/TextureRegistry$SurfaceProducer` (Flutter **3.47.7** — the folder name is stale)
- `C:\Users\wambugukinyua\miniaudiodart\audio_engine.h:586` + `audio_engine.cpp:4163` (raw stereo PCM tap)

**External sources consulted (2026-10-20)**

- Flutter, *New APIs for Android plugins that render to a Surface* — `docs.flutter.dev/release/breaking-changes/android-surface-plugins` (SurfaceProducer migration guide; `onSurfaceAvailable` / `onSurfaceCleanup`; `scheduleFrame` deprecation)
- Flutter, *Impeller rendering engine* — `docs.flutter.dev/perf/impeller` (Impeller default on Android API 29+, and on Windows/macOS/Linux since 3.47)
- Flutter API docs — `api.flutter.dev/javadoc/io/flutter/view/TextureRegistry.SurfaceProducer.html` (`handlesCropAndRotation`, ImageReader backend on API 29+)
- Flutter engine source — `github.com/flutter/flutter/engine/src/flutter/shell/platform/android/io/flutter/view/TextureRegistry.java` (`SurfaceLifecycle.manual` / `resetInBackground`)
- flutter/flutter#162060 — `SurfaceProducer.setSize()` no-op on some OEM devices

