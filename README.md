# sautiflow

![Sautiflow Logo](docs/assets/sautiflow.png)

**[ Download Latest Sautiplay Real-world App Release](https://github.com/wambugu71/sautiflow/releases/latest)**
*Check out the [Sautiplay Readme](sautiplay/README.md) to see a full production app built on this engine with advanced EQ, gapless playback, and native streaming.*

Sautiflow is a cross-platform audio playback and processing engine for Dart and Flutter, powered by the C++ miniaudio library. It provides a high-level API for playlist management, gapless transitions, audio effects, and real-time status updates, all accessible via Dart FFI. Sautiflow supports native targets including Windows, Linux, Android, iOS, and macOS. Audiophiles and developers can leverage Sautiflow for building rich audio applications with advanced playback and processing capabilities.

## Features

- Playlist engine (set/add/insert/remove/move)
- Gapless transitions between tracks
- Audiophile-grade resampling algorithms powered by `libsamplerate` (SRC Sinc Best/Medium/Fastest, ZOH, Linear)
- Play/pause/stop/seek/next/previous/jump
- Shuffle + loop modes (`off`, `all`, `one`)
- FX chain: gain, pan, stereo widening, audiophile crossfeed (BS2B/Joe0bloggs), EQ (3-band), multiband EQ, reverb, low-pass, high-pass, band-pass, delay, peak EQ, notch, low-shelf, high-shelf
- Pollable player status and stream updates
- Native targets: Windows, Linux, Android, iOS/macOS


### Audiophile Headphone Crossfeed
When listening to music originally mastered for stereo speakers on headphones, extreme stereo separation (classic L/R ping-pong) can cause listening fatigue since your left ear cannot hear the right speaker at all. Sautiflow features a mastering-grade Crossfeed algorithm with configurable presets:
- **1. BS2B Weak:** Smooths out extreme stereo separation with minimal tonal change.
- **2. BS2B Strong:** Stronger acoustic shadowing for extreme-panned old records (e.g. early Beatles).
- **3. Joe0bloggs Realistic:** Delay-heavy, Linkwitz-style frequency shaping for a natural room-like experience on headphones.

`dart
// Enable crossfeed
player.setCrossfeedEnabled(enabled: true);

// Set preset (1 = BS2B Weak, 2 = BS2B Strong, 3 = Joe0bloggs)
player.setCrossfeedPreset(preset: 3);
`

## Audio Formats & Quality

Sautiflow is built with audiophile-grade fidelity in mind. It handles different audio formats natively within its C++ engine to provide the best possible acoustic reproduction:

- **Lossy Formats (MP3, AAC, OGG etc.)**: These formats are inherently compressed. Upon playback, Sautiflow **upscales/upsamples** the decoded bitstream internally (in 32-bit floating point math) ensuring that DSP operations—like EQ, reverb, and spatial width—have plenty of headroom and do not clip or introduce artificial artifacts typical of low-resolution math.
- **Lossless Formats (FLAC, WAV, ALAC, etc.)**: These are mapped and processed **raw**. Sautiflow does **not** dynamically upscale them to guess lost data (since nothing is lost). It maintains their pristine bit-perfect original depth into the DSP chain. If the file's sample rate doesn't match your device's native hardware rate (e.g., trying to play an 88.2kHz FLAC file on a 48kHz output device), Sautiflow will employ high-fidelity **resampling** transparently using `libsamplerate` to perfectly match your hardware, avoiding quality loss while retaining bit-depth fidelity.

## Public Dart API

Import:

```dart
import 'package:sautiflow/sautiflow.dart';
```

### Querying the Audio Pipeline True State

You can interrogate the engine to uncover the exact properties of the actively running audio pipeline. This is incredibly useful for audiophiles wanting to see the "true" negotiated hardware output formats, track their native input resolutions, and confirm spatializer or FX states.

```dart
final state = player.pipelineState;

// Input Source File (e.g. decoded MP3 format)
print('Input Format: ${state.inputFormatString} | ${state.inputChannels} channels');
print('Input Sample Rate: ${state.inputSampleRate}Hz');

// Sub-System DSP (Miniaudio processes FX primarily in 32-bit Float)
print('DSP Format: ${state.processingFormatString}');

// True hardware OS-negotiated driver output
print('Speaker Format: ${state.outputFormatString} | ${state.outputSampleRate}Hz');

// Enabled DSP Features currently actively shifting the stream
print('Eq Enabled: ${state.eqEnabled}');
print('Reverb Enabled: ${state.reverbEnabled}');

### Native Track Metadata Inspection

Sautiflow exports a high-speed C++ native file stream inspector (`player.inspectFile(path)`). It parses raw container headers (including FLAC `STREAMINFO` blocks and WAV `fmt ` chunks) without needing to decode full PCM streams, returning exact audio properties in microseconds:

```dart
final info = player.inspectFile('/path/to/song.flac');

if (info != null) {
  print('Sample Rate: ${info.sampleRate} Hz');    // e.g. 96000 Hz, 192000 Hz
  print('Bit Depth:   ${info.bitDepth} bits');    // e.g. 24-bit, 32-bit
  print('Float PCM:   ${info.isFloat}');         // true for 32-bit Float WAV
  print('Channels:    ${info.channels}');        // 2 (Stereo), 1 (Mono)
  print('Bitrate:     ${info.bitrateKbps} kbps');// e.g. 1411 kbps, 2304 kbps
  print('Codec:       ${info.formatName}');     // "FLAC", "WAV", "MP3"
}
```
```

### Example (playlist + controls)

```dart
final player = MiniAudioPlayer();
player.init();

final playlist = <AudioSource>[
  AudioSource.uri(Uri.parse('https://example.com/track1.mp3')),
  AudioSource.uri(Uri.parse('https://example.com/track2.mp3')),
  AudioSource.uri(Uri.parse('https://example.com/track3.mp3')),
];

player.setAudioSources(
  playlist,
  initialIndex: 0,
  initialPosition: Duration.zero,
  useLazyPreparation: true,
);

player.play();
player.seekToNext();
player.seekToPrevious();
player.seekTo(const Duration(seconds: 0), index: 2);
player.setLoopMode(LoopMode.all);
player.setShuffleModeEnabled(true);

player.addAudioSource(AudioSource.uri(Uri.parse('https://example.com/new.mp3')));
player.insertAudioSource(1, AudioSource.uri(Uri.parse('https://example.com/ins.mp3')));
player.removeAudioSourceAt(3);
player.moveAudioSource(2, 1);

player.setEqEnabled(true);
player.setEq(low: 1.2, mid: 1.0, high: 1.1);
player.setReverbEnabled(true);
player.setReverb(mix: 0.2, feedback: 0.6, delayMs: 100);

// Advanced filters / parametric shaping
player.setBandpass(enabled: true, cutoffHz: 1000, q: 0.8);
player.setPeakEq(enabled: true, gainDb: 3.0, q: 1.0, frequencyHz: 2500);
player.setNotch(enabled: true, q: 10.0, frequencyHz: 60);
player.setLowshelf(enabled: true, gainDb: 4.0, slope: 1.0, frequencyHz: 100);
player.setHighshelf(enabled: true, gainDb: 2.5, slope: 1.0, frequencyHz: 10000);
```

## Native build outputs

Expected library names by platform:

- Windows: `sautiflow.dll`
- Linux/Android: `libsautiflow.so`
- macOS: `libsautiflow.dylib`
- iOS: statically linked (`DynamicLibrary.process()`)

## Flutter plugin structure

This package is configured as a Flutter FFI plugin in [pubspec.yaml](pubspec.yaml) with:

- Android (`ffiPlugin: true`)
- iOS (`ffiPlugin: true`)
- Linux (`ffiPlugin: true`)
- Windows (`ffiPlugin: true`)

Platform native build configs are included:

- [android/src/main/cpp/CMakeLists.txt](android/src/main/cpp/CMakeLists.txt)
- [ios/sautiflow.podspec](ios/sautiflow.podspec)
- [linux/CMakeLists.txt](linux/CMakeLists.txt)
- [windows/CMakeLists.txt](windows/CMakeLists.txt)

## Build scripts

- Windows: [tool/build_windows.ps1](tool/build_windows.ps1)
- Linux: [tool/build_linux.sh](tool/build_linux.sh)
- Android (NDK): [tool/build_android.sh](tool/build_android.sh)
- Android (NDK, PowerShell): [tool/build_android.ps1](tool/build_android.ps1)
- Apple (iOS + macOS): [tool/build_apple.sh](tool/build_apple.sh)

## Packaging notes

For Flutter app integration, keep native artifacts available in app/plugin output:

- Android: `android/src/main/jniLibs/<abi>/libsautiflow.so`
- iOS: link `sautiflow.xcframework` in Xcode/Podspec
- Windows: place `sautiflow.dll` next to executable
- Linux: ship `libsautiflow.so` with app bundle and ensure loader path

### Android native network streaming (libcurl)

Android now attempts to enable native URL streaming by default.

- If `libcurl` is found (explicit path or bundled per ABI), native network streaming is enabled.
- If not found, Android build continues and falls back to non-native URL handling (no build break).

Optional overrides (Gradle project properties):

- `MINIAUDIODART_ENABLE_CURL=ON|OFF`
- `MINIAUDIODART_CURL_INCLUDE_DIR=/path/to/include`
- `MINIAUDIODART_CURL_LIBRARY=/path/to/libcurl.a` (or `.so`)
- `MINIAUDIODART_CURL_LIBRARY_DIR=/path/to/abi-parent`
- `MINIAUDIODART_CURL_EXTRA_LIBS=ssl;crypto;z` (optional static dependency chain)

### Recommended Android setup (static per ABI)

Use static `libcurl.a` per ABI to keep plugin packaging simple (single `libsautiflow.so`).

Expected layout:

- `native/android/include/` (curl headers)
- `native/android/armeabi-v7a/libcurl.a`
- `native/android/arm64-v8a/libcurl.a`

The Android Gradle configs are aligned to arm ABIs by default (`armeabi-v7a`, `arm64-v8a`).
If you need emulator ABIs (`x86`, `x86_64`), add matching prebuilt curl artifacts and expand ABI filters.

For release/legal packaging, include third-party attributions from
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

## Credits and Acknowledgements

- **ViPER DSP Engine**: The ViPER DSP integration is based on reverse-engineered code. The original intellectual property belongs to Zhuhang and ViPER520 (ViPER4Android). Reverse engineering by [Martmists](https://github.com/Martmists-GH), [Iscle](https://github.com/iscle), and [likelikeslike](https://github.com/likelikeslike) ([AndroidAudioMods/ViPERFX_RE](https://github.com/AndroidAudioMods/ViPERFX_RE)). Please note this specific module carries no standard open source license (All Rights Reserved) and is intended for personal use only.

## Example

See [example/main.dart](example/main.dart) for a complete usage sample.

## Support

If you find this project useful, consider buying me a coffee! 

<a href="https://buymeacoffee.com/wambugu" target="_blank"><img src="https://cdn.buymeacoffee.com/buttons/v2/default-yellow.png" alt="Buy Me A Coffee" style="height: 60px !important;width: 217px !important;" ></a>

Leave a star if you find this project useful! ⭐

Project inspired by `just_audio` for simplicity and familiarity of API design, but built on a custom native engine with a focus on advanced audio processing features and real-time capabilities.


