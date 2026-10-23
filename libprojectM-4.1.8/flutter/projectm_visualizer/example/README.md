# projectm_visualizer example

A complete demo of the `projectm_visualizer` package: libprojectM Milkdrop visuals driven by audio, with a preset browser, quality controls and live telemetry.

## What it demonstrates

- Creating a `ProjectMVisualizer` and loading `.milk` presets, including embedded fallback presets.
- Playing a bundled WAV track, picking an audio file from disk, or generating a 60/120 Hz sine.
- Displaying the render through `ProjectMWidget` with selectable quality, FPS and aspect-ratio modes.
- Reading telemetry (`fps`, frame time, bass/mid/treble) on a timer.
- Pausing, resuming, changing volume and disposing the controller correctly.
- Keyboard shortcuts: arrows cycle presets, `Space` toggles playback, `R` random preset, `O` open audio, `P` preset browser, `M` open a `.milk` file, `A` cycle aspect ratio, `F` cycle fit, `H` hide the HUD.

## Run it

From this directory:

```console
flutter pub get
flutter run -d windows
```

On Android:

```console
flutter run -d <device-id>
```

### Windows prerequisite

The plugin links against a prebuilt libprojectM and the vendored GLEW. From the libprojectM repository root, build the engine once:

```console
cmake -S . -B build/projectm -G "Visual Studio 17 2022" -A x64 ^
  -DENABLE_INSTALL=OFF ^
  -DENABLE_PLAYLIST=OFF ^
  -DENABLE_SDL_UI=OFF ^
  -DBUILD_TESTING=OFF

cmake --build build/projectm --config Release --target projectM
```

Then verify these exist:

```text
build/projectm/src/libprojectM/Release/projectM-4.dll
build/projectm/src/libprojectM/Release/projectM-4.lib
vendor/glew/glew-2.2.0/
```

### Android prerequisite

Use NDK `28.2.13676358`, CMake `3.22.1` and `minSdk 24`. The plugin builds libprojectM from source as part of the Gradle/CMake build, so no separate engine build is required.

## Presets

The app first scans for `.milk` files under `presets/tests/` relative to the working directory and its parents. If none are found, it uses three embedded presets. You can also open any `.milk` file at runtime with the `M` shortcut or the preset browser.

## Audio

- **Bundled sample** — `assets/sample_groove.wav` is copied to a temporary file and passed to `playAudioFile`.
- **File picker** — MP3, WAV, FLAC, OGG, M4A and AAC can be selected, but the built-in miniaudio decoder only guarantees WAV, MP3, FLAC and Ogg Vorbis.
- **Sine generator** — useful when no audio file is available.

For the full usage guide, see the [package README](../README.md).
