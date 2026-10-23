# projectm_visualizer

Milkdrop visuals for Flutter, powered by [libprojectM 4.1.8](https://github.com/projectM-visualizer/projectm) and miniaudio.

`projectm_visualizer` embeds the libprojectM C++ rendering engine behind a Dart FFI facade. It renders `.milk` presets on a dedicated native render thread, reacts to decoded audio (or PCM you supply yourself), and displays the result through a Flutter widget.

```dart
final visualizer = await ProjectMVisualizer.create();
visualizer.setFps(60);
await visualizer.loadPresetFromAsset('assets/presets/neon_hyperspace.milk');
visualizer.playSine(frequencyHz: 60);

ProjectMWidget(controller: visualizer);
```

---

## Contents

- [Features](#features)
- [Platform support](#platform-support)
- [Requirements](#requirements)
- [Installation](#installation)
- [Quick start](#quick-start)
- [How it works](#how-it-works)
- [Presets](#presets)
- [Audio](#audio)
- [Quality and performance](#quality-and-performance)
- [Telemetry](#telemetry)
- [The ProjectMWidget](#the-projectmwidget)
- [Reading frames directly](#reading-frames-directly)
- [Lifecycle and disposal](#lifecycle-and-disposal)
- [API reference](#api-reference)
- [Troubleshooting](#troubleshooting)
- [Running the example](#running-the-example)
- [Building the native library](#building-the-native-library)
- [Known limitations](#known-limitations)
- [License and attribution](#license-and-attribution)

---

## Features

- **Preset rendering** — load Milkdrop `.milk` presets from a file, a string, or a Flutter asset, with optional smooth crossfades.
- **Audio-driven** — built-in miniaudio decoder for WAV, MP3, FLAC and Ogg Vorbis, a synthetic sine generator for testing, or push your own interleaved stereo PCM.
- **Zero-copy on Android** — when a hardware surface is available the native renderer draws straight into a Flutter `Texture`. Desktop and emulators use an asynchronous PBO readback path instead.
- **Fast by default** — triple-buffered pixel output, command queue and PCM ring, audio analysis, and frame pacing all live off the UI thread.
- **Quality profiles** — 360p, 540p, 720p, native-resolution and custom render targets, plus adjustable mesh resolution and frame rate.
- **Battery aware** — optional throttling to 15 FPS after a few seconds of silence.
- **Telemetry** — FPS, frame time, bass/mid/treble energy, frame count, playback state.
- **Asset-friendly** — presets can ship inside your app bundle; no file picker required.

---

## Platform support

| Platform | Status | Rendering path |
| --- | --- | --- |
| Android | Supported (minSdk 24) | EGL/GLES 3 window surface → Flutter hardware texture; RGBA readback fallback |
| Windows | Supported | WGL OpenGL 3.3 core context + PBO readback |
| Linux | Supported | EGL Desktop OpenGL 3.3 core context (pbuffer) + PBO readback |
| macOS | Supported | CGL OpenGL 3.2+ core context + PBO readback |
| iOS | Supported (iOS 13+) | EAGL OpenGL ES 3.0 context (FBO/RBO) + PBO readback |

Web is not supported.

> **Important:** this package is not published on pub.dev. It is designed to live inside a checkout of the libprojectM 4.1.8 source tree, because the native build locates the engine by walking up the directory tree to `src/libprojectM/ProjectM.cpp`.

---

## Requirements

### Runtime

- Dart SDK `^3.13.5` (Flutter 3.47.x is the tested baseline).
- **Android:** app `minSdk` of at least **24**, NDK **28.2.13676358**, CMake **3.22.1**, compile SDK **36**.
- **Windows:** a GPU and driver exposing **OpenGL 3.3 core** or newer.

### Build machine

- Flutter with desktop support enabled.
- A C++17 toolchain (Visual Studio with the Desktop C++ workload on Windows).
- CMake 3.20+ (the Android build pins 3.22.1).
- On Windows, a prebuilt libprojectM and GLEW. The plugin's CMake expects them at:

  ```text
  build/projectm/src/libprojectM/Release/projectM-4.dll
  build/projectm/src/libprojectM/Release/projectM-4.lib
  vendor/glew/glew-2.2.0/
  ```

  See [Building the native library](#building-the-native-library).

---

## Installation

Add the package as a path dependency:

```yaml
dependencies:
  flutter:
    sdk: flutter
  projectm_visualizer:
    path: ../libprojectM-4.1.8/flutter/projectm_visualizer
```

or, if you keep the tree in Git:

```yaml
dependencies:
  projectm_visualizer:
    git:
      url: https://github.com/<you>/libprojectM.git
      path: flutter/projectm_visualizer
```

Then run:

```console
flutter pub get
```

If your application lives outside the libprojectM checkout, vendor the whole libprojectM 4.1.8 tree into your repository and keep the package under `flutter/projectm_visualizer`. The CMake script searches upward for `src/libprojectM/ProjectM.cpp`; a package copied out of the tree will fail to configure.

---

## Quick start

### 1. Add a preset as an asset

Put a `.milk` file in your app, for example `assets/presets/neon_hyperspace.milk`, and declare it:

```yaml
flutter:
  assets:
    - assets/presets/neon_hyperspace.milk
```

The repository ships test presets under `presets/tests/` that you can copy.

### 2. Render it

```dart
import 'package:flutter/material.dart';
import 'package:projectm_visualizer/projectm_visualizer.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const VisualizerApp());
}

class VisualizerApp extends StatefulWidget {
  const VisualizerApp({super.key});

  @override
  State<VisualizerApp> createState() => _VisualizerAppState();
}

class _VisualizerAppState extends State<VisualizerApp> {
  ProjectMVisualizer? _visualizer;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    final visualizer = await ProjectMVisualizer.create(
      width: 960,
      height: 540,
    );

    visualizer.setFps(60);
    visualizer.setMeshSize(32, 24);
    visualizer.setSoftCutDuration(1.5);

    await visualizer.loadPresetFromAsset(
      'assets/presets/neon_hyperspace.milk',
    );

    // The engine starts with a 60 Hz test tone. Play a real file instead,
    // or call pauseAudio() for silent visuals.
    visualizer.playSine(frequencyHz: 60);

    if (!mounted) {
      visualizer.dispose();
      return;
    }
    setState(() => _visualizer = visualizer);
  }

  @override
  void dispose() {
    _visualizer?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final visualizer = _visualizer;
    if (visualizer == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      body: ProjectMWidget(
        controller: visualizer,
        quality: VisualizerQuality.balanced,
      ),
    );
  }
}
```

That is the complete integration: create the controller, load a preset, and hand the controller to `ProjectMWidget`.

---

## How it works

- `ProjectMVisualizer.create()` loads the platform library, creates the native instance, and starts a render thread plus a miniaudio playback thread. The controller is usable immediately; the first visible frames arrive once the render thread has created its GL context and a preset has been loaded.
- Every configuration call (`setFps`, `loadPresetFile`, `pushPcm`, ...) enqueues work for the render thread. These methods are safe to call from the Flutter UI isolate and return immediately. Preset loading is still asynchronous from the renderer's point of view: the new preset appears on a following frame.
- `ProjectMWidget` owns presentation. On Android, when a hardware texture was created, it renders a `Texture`. Everywhere else it uses a `Ticker`, pulls new RGBA frames, decodes them with `decodeImageFromPixels`, and paints a `RawImage`.
- The widget automatically calls `setSize` when its layout or quality profile changes, so you normally do not need to resize manually.
- `dispose()` is idempotent. It stops the render and audio threads and frees the native buffers. The widget does **not** dispose the controller for you.

---

## Presets

Any `.milk` preset from the Milkdrop ecosystem should load, including presets that use custom textures or shaders.

```dart
// From disk (desktop, or a path extracted from an asset on mobile).
await visualizer.loadPresetFile('/path/to/preset.milk');

// From raw preset text.
await visualizer.loadPresetData(milkText);

// Straight from the Flutter asset bundle.
await visualizer.loadPresetFromAsset('assets/presets/neon.milk');
```

`loadPresetFile`, `loadPresetData` and `loadPresetFromAsset` all accept `smoothTransition` (default `true`). Pass `false` to cut immediately.

### No preset, no picture

libprojectM renders nothing until a preset is loaded. If you see a black or empty surface, the first thing to check is that one of the `loadPreset*` methods succeeded.

### Preset textures

Some presets reference texture images (`.jpg`, `.png`, `.tga`). Point libprojectM at the directory containing them:

```dart
visualizer.setTextureSearchPath('/path/to/preset/textures');
```

Flutter assets do **not** live at a normal filesystem path. If a preset uses helper textures, extract those textures (and optionally the preset) to a temporary or documents directory and set the search path to that directory.

---

## Audio

The engine has three audio modes.

### 1. Built-in file playback

```dart
final ok = await visualizer.playAudioFile('/music/track.mp3');
if (!ok) {
  // The decoder could not open the file.
}
```

The bundled miniaudio build decodes **WAV, MP3, FLAC and Ogg Vorbis**. AAC/M4A is not guaranteed; `playAudioFile` returns `false` for a format the decoder cannot open.

`playAudioFile` takes a filesystem path. Bundled Flutter assets must first be written to a temporary file:

```dart
final data = await rootBundle.load('assets/audio/track.mp3');
final file = File('${Directory.systemTemp.path}/track.mp3');
await file.writeAsBytes(
  data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
  flush: true,
);

await visualizer.playAudioFile(file.path);
```

### 2. Synthetic tone

```dart
visualizer.playSine(frequencyHz: 60);
```

Useful for demos, tests and screensavers. Note that this is also the default state: a freshly created visualizer produces a 60 Hz sine. Call `pauseAudio()` if you want silent visuals.

### 3. Your own PCM

If audio is already playing elsewhere (a music player, a streaming engine, a microphone tap), feed it directly:

```dart
// Stop the built-in generator first, or it will keep writing to the
// analysis buffer alongside your samples.
visualizer.pauseAudio();

// Interleaved stereo: [L, R, L, R, ...], nominally in the range -1.0..1.0.
visualizer.pushPcm(Float32List.fromList(samples));
```

Guidelines:

- Push small chunks frequently. projectM analyses the most recent **576 frames per channel**, so chunks of around 512 frames (about 11.6 ms at 44.1 kHz) work well.
- The native ring is large (16k frames) but the renderer consumes only the newest portion each frame; pushing huge buffers does not improve analysis.
- `pushPcm` is non-blocking and safe from the UI isolate.
- Keep the sample rate consistent with what you send; projectM does not resample.

### Transport controls

```dart
visualizer.pauseAudio();
visualizer.resumeAudio();
visualizer.stopAudio();     // stops and rewinds a decoded file
visualizer.setVolume(0.8);  // clamped to 0.0..2.0
```

---

## Quality and performance

Render resolution is chosen per widget through `VisualizerQuality`:

| Value | Render size | Typical use |
| --- | --- | --- |
| `VisualizerQuality.eco` | 640×360 | Low-end Android, battery saver, background visualizer |
| `VisualizerQuality.balanced` | 960×540 | Default; good quality with moderate GPU/memory load |
| `VisualizerQuality.high` | 1280×720 | Desktop and modern phones |
| `VisualizerQuality.native` | Layout size × device pixel ratio | High-DPI screens; most expensive |
| `VisualizerQuality.custom` | `customWidth` × `customHeight` | Fixed targets, thumbnails, recordings |

`eco`, `balanced` and `high` fix the height and derive the width from the widget's aspect ratio when `maintainAspectRatio` is `true`; otherwise they use 640, 960 and 1280 wide respectively. Sizes are rounded down to even numbers for GL stride alignment.

### Tuning the engine

```dart
visualizer.setFps(60);          // 30, 60, 120, ...
visualizer.setMeshSize(32, 24); // per-vertex equation mesh; higher = sharper, slower
visualizer.setSoftCutDuration(1.5); // crossfade seconds between presets
visualizer.setBatterySaver(true);   // 15 FPS after ~3s of silence
```

Lower `setMeshSize` values, such as `24, 18`, substantially reduce per-frame CPU/GPU work for preset equations. Values below `8` are ignored.

### Rules of thumb

- Start at `balanced` and 60 FPS, then move up or down.
- `eco` + mesh `24×18` + 30 FPS is a good low-end mobile baseline.
- `native` on a 4K display is expensive; prefer `high` unless you need the detail.
- The desktop path performs a GPU→CPU readback. At very large sizes this is the bottleneck, not the preset.
- The Android hardware texture path avoids the readback entirely.

---

## Telemetry

```dart
final stats = visualizer.getStats();

stats.fps;                // measured over roughly the last half second
stats.frameTimeMs;        // duration of the last rendered frame
stats.bass;               // 0.0..1.0 approximation
stats.mid;                // 0.0..1.0 approximation
stats.treb;               // 0.0..1.0 approximation
stats.framesRendered;     // total frames produced
stats.pcmFramesDropped;   // reserved PCM drop counter (currently 0)
stats.isPlaying;          // audio transport state
```

Poll on a timer rather than every frame:

```dart
final timer = Timer.periodic(
  const Duration(milliseconds: 250),
  (_) => setState(() => _stats = visualizer.getStats()),
);
// ...
timer.cancel();
```

`bass`, `mid` and `treb` are computed from the current PCM window and are intended for meters and reactive UI, not for audio analysis.

---

## The ProjectMWidget

```dart
ProjectMWidget(
  controller: visualizer,
  aspectRatio: 16 / 9,
  maintainAspectRatio: true,
  fit: BoxFit.contain,
  alignment: Alignment.center,
  backgroundColor: Colors.black,
  quality: VisualizerQuality.balanced,
  customWidth: null,
  customHeight: null,
  filterQuality: FilterQuality.low,
  placeholder: null,
)
```

| Property | Default | Purpose |
| --- | --- | --- |
| `controller` | required | The `ProjectMVisualizer` to display |
| `aspectRatio` | `16 / 9` | Target aspect ratio; `null` follows the parent |
| `maintainAspectRatio` | `true` | Letterbox/pillarbox instead of stretching |
| `fit` | `BoxFit.contain` | How the visualizer is inscribed in the layout box |
| `alignment` | `Alignment.center` | Placement inside the box |
| `backgroundColor` | `Colors.black` | Fill visible behind letterboxed content |
| `quality` | `balanced` | Render resolution profile |
| `customWidth` / `customHeight` | `null` | Used only by `VisualizerQuality.custom` |
| `filterQuality` | `FilterQuality.low` | Scaling filter; `low` is cheapest |
| `placeholder` | spinner | Widget shown until the first frame arrives |

The widget handles unbounded constraints (for example inside a `Column` or `ListView`) with a sensible 960-wide fallback.

---

## Reading frames directly

For recordings, thumbnails, custom compositing or exporting, bypass the widget:

```dart
final copied = visualizer.copyFrameRgba(
  (pixels, width, height, frameId) {
    // `pixels` is a Uint8List view over native memory.
    // Copy it if you need to retain it beyond this callback.
    final frame = Uint8List.fromList(pixels);
  },
);
```

- Returns `false` when no new frame has been produced since the last call.
- `pixels` is RGBA8888, `width * height * 4` bytes.
- The callback receives a temporary view. Do not store the `Uint8List` itself.
- Call it from a single isolate; the controller reuses internal native buffers.
- On Android, when the hardware texture path is active, frames are presented straight to the texture and are **not** published to the readback buffer. If you need pixel access, create the controller with `enableHardwareTexture: false`.

---

## Lifecycle and disposal

The native render and audio threads keep running when the Flutter app is backgrounded. Handle lifecycle explicitly:

```dart
class _MyState extends State<MyWidget> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final visualizer = _visualizer;
    if (visualizer == null) return;

    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
        visualizer.pauseAudio();
      case AppLifecycleState.resumed:
        visualizer.resumeAudio();
      case AppLifecycleState.detached:
        break;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _visualizer?.dispose();
    super.dispose();
  }
}
```

To save more power while hidden, also lower the frame rate:

```dart
visualizer.setFps(15); // on pause
visualizer.setFps(60); // on resume
```

Dispose the controller once, when the owning screen is gone. Do not call methods on a disposed controller; they return silently or produce zeroed stats.

---

## API reference

### `ProjectMVisualizer`

| Method | Description |
| --- | --- |
| `static Future<ProjectMVisualizer> create({int width = 1280, int height = 720, bool enableHardwareTexture = true})` | Create the native instance and threads. Throws `StateError` if the native instance cannot be created. |
| `int? get hardwareTextureId` | Non-null when the Android zero-copy texture path is active. |
| `void setSize(int width, int height)` | Change the render viewport. The widget calls this automatically. |
| `void setFps(int fps)` | Target render frame rate. |
| `void setMeshSize(int width, int height)` | Milkdrop equation mesh resolution; minimum `8×8`. |
| `void setSoftCutDuration(double seconds)` | Crossfade time between presets. |
| `void setBatterySaver(bool enabled)` | Throttle to 15 FPS after sustained silence. |
| `Future<void> loadPresetFile(String filePath, {bool smoothTransition = true})` | Load a `.milk` file from disk. |
| `Future<void> loadPresetData(String data, {bool smoothTransition = true})` | Load preset text directly. |
| `Future<void> loadPresetFromAsset(String assetPath, {bool smoothTransition = true})` | Load a `.milk` bundled as a Flutter asset. |
| `void setTextureSearchPath(String directoryPath)` | Directory containing preset texture images. |
| `Future<bool> playAudioFile(String filePath)` | Decode and play a file; `false` if it cannot be opened. |
| `void playSine({double frequencyHz = 60.0})` | Use the synthetic tone generator. |
| `void pauseAudio()` | Pause output and stop feeding the analyser. |
| `void resumeAudio()` | Resume output. |
| `void stopAudio()` | Stop playback and rewind a decoded file. |
| `void setVolume(double volume)` | Playback volume, clamped to `0.0..2.0`. |
| `void pushPcm(Float32List interleavedStereo)` | Feed your own interleaved stereo `-1.0..1.0` samples. |
| `bool copyFrameRgba(void Function(Uint8List pixels, int width, int height, int frameId) onFrame)` | Pull the newest RGBA frame; `false` if unchanged. |
| `VisualizerStats getStats()` | Read telemetry. |
| `void dispose()` | Stop threads and free native resources. Idempotent. |

### `VisualizerStats`

| Field | Type | Meaning |
| --- | --- | --- |
| `fps` | `double` | Measured render rate |
| `frameTimeMs` | `double` | Last frame time in milliseconds |
| `bass` / `mid` / `treb` | `double` | PCM energy approximations, `0.0..1.0` |
| `framesRendered` | `int` | Total frames rendered |
| `pcmFramesDropped` | `int` | Reserved PCM drop counter; currently always `0` |
| `isPlaying` | `bool` | Audio transport state |

`VisualizerStats` also has a readable `toString()` for logging.

### `VisualizerQuality`

`eco`, `balanced`, `high`, `native`, `custom`. See [Quality and performance](#quality-and-performance).

---

## Troubleshooting

| Symptom | Likely cause and fix |
| --- | --- |
| Black or empty surface | No preset loaded. Call `loadPresetFile`, `loadPresetData` or `loadPresetFromAsset`. |
| `UnsupportedError: Unsupported platform` | The package is running somewhere other than Android or Windows. |
| `StateError: Failed to create native projectM visualizer instance` | The render thread could not create a GL context or the projectM instance. Verify GL 3.3 core on Windows, GLES 3 on Android, and that a GPU driver is present. |
| `DynamicLibrary.open` failure | Native libraries are not bundled. On Windows ensure `projectm_visualizer.dll`, `projectM-4.dll` and `glew32.dll` are next to the executable. |
| No reaction to audio | If you feed PCM, call `pauseAudio()` first; otherwise confirm the file decoded (`playAudioFile` returned `true`) or that `pushPcm` is called regularly with interleaved stereo data. |
| Audio file will not play | The built-in decoder supports WAV, MP3, FLAC and Ogg Vorbis. Convert AAC/M4A or decode it yourself and use `pushPcm`. |
| Low FPS | Lower `quality`, reduce `setMeshSize`, cap `setFps`, or enable `setBatterySaver`. On desktop, prefer `high` over `native`. |
| Android falls back to the slow path | The hardware texture could not be created. Check logcat for `ProjectMVisualizer: Hardware texture not available`. Rendering still works via the pixel path. |
| High memory on resize | Each distinct render size reallocates native buffers. Avoid resizing every frame; the widget only resizes when the computed target changes. |
| Preset textures missing | Call `setTextureSearchPath` with a real directory, and extract textures from Flutter assets first. |

---

## Running the example

The `example/` app is a full demo: preset browser, audio file picker, sine generator, quality/FPS/aspect-ratio controls and live telemetry.

```console
cd flutter/projectm_visualizer/example
flutter pub get
flutter run -d windows
```

On Android:

```console
flutter run -d <device-id>
```

The example looks for presets under `presets/tests/` in the libprojectM tree and falls back to embedded presets when none are found.

---

## Building the native library

### Windows

The plugin links against a **prebuilt** libprojectM plus the vendored GLEW. From the libprojectM repository root:

```console
cmake -S . -B build/projectm -G "Visual Studio 17 2022" -A x64 ^
  -DENABLE_INSTALL=OFF ^
  -DENABLE_PLAYLIST=OFF ^
  -DENABLE_SDL_UI=OFF ^
  -DBUILD_TESTING=OFF

cmake --build build/projectm --config Release --target projectM
```

libprojectM requires GLEW on Windows. Either install it with vcpkg and pass the toolchain file, or make it discoverable through `CMAKE_PREFIX_PATH` / `GLEW_INCLUDE_DIR` and `GLEW_LIBRARY`.

Confirm the expected artifacts exist:

```text
build/projectm/src/libprojectM/Release/projectM-4.dll
build/projectm/src/libprojectM/Release/projectM-4.lib
vendor/glew/glew-2.2.0/
```

Then build/run the app:

```console
cd flutter/projectm_visualizer/example
flutter run -d windows
```

The plugin's CMake copies `projectM-4.dll` and `glew32.dll` next to the plugin binary automatically.

### Android

No prebuilt engine is needed. The plugin's `src/CMakeLists.txt` adds the libprojectM tree and builds it with GLES 3 for Android. The build pins:

- NDK `28.2.13676358`
- CMake `3.22.1`
- `minSdk 24`
- 16 KB page alignment (`-Wl,-z,max-page-size=16384`)

Adjust `android/build.gradle` if your environment uses different NDK/CMake versions, then run the example on a device or emulator.

### Regenerating FFI bindings

The Dart bindings are generated from `src/pmvis.h`:

```console
dart run ffigen --config ffigen.yaml
```

Commit the regenerated `lib/projectm_visualizer_bindings_generated.dart` with any native ABI change.

---

## Known limitations

- Only Android and Windows are wired in `pubspec.yaml`; Linux, macOS and iOS need native build work and CI coverage before they can be advertised.
- No web support.
- No built-in preset playlist or automatic advancement. Auto-cycling presets is application logic (the example uses a `Timer`).
- No microphone or line-in capture; audio input is file playback, synthetic tone, or your own PCM.
- The desktop/emulator path has one frame of readback latency; the Android hardware texture path does not.
- `pcmFramesDropped` is a reserved field and is not incremented yet. The PCM ring keeps the newest audio rather than queueing every sample, so pushing excessively large buffers can silently skip old audio.

---

## License and attribution

This package embeds and links against **libprojectM**, which is distributed under the **GNU Lesser General Public License 2.1**. See `LICENSE.txt` / `COPYING` in the libprojectM repository root for the full text and comply with the LGPL when distributing a binary (dynamic linking, notices, and a source offer for the libprojectM components).

Audio decoding is provided by **miniaudio**, which is released into the public domain or under the MIT No Attribution license, at your option.

The package's own `LICENSE` file is currently a placeholder and must be completed before publishing.
