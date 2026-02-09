# miniaudiodart

Cross-platform Dart audio package backed by a C++ miniaudio engine.

## Features

- Playlist engine (set/add/insert/remove/move)
- Gapless transitions between tracks
- Play/pause/stop/seek/next/previous/jump
- Shuffle + loop modes (`off`, `all`, `one`)
- FX chain: gain, pan, EQ (3-band), reverb, low-pass, high-pass, delay
- Pollable player status and stream updates
- Native targets: Windows, Linux, Android, iOS/macOS

## Public Dart API

Import:

```dart
import 'package:miniaudiodart/miniaudiodart.dart';
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
```

## Native build outputs

Expected library names by platform:

- Windows: `audio_engine.dll`
- Linux/Android: `libaudio_engine.so`
- macOS: `libaudio_engine.dylib`
- iOS: statically linked (`DynamicLibrary.process()`)

## Flutter plugin structure

This package is configured as a Flutter FFI plugin in [pubspec.yaml](pubspec.yaml) with:

- Android (`ffiPlugin: true`)
- iOS (`ffiPlugin: true`)
- Linux (`ffiPlugin: true`)
- Windows (`ffiPlugin: true`)

Platform native build configs are included:

- [android/src/main/cpp/CMakeLists.txt](android/src/main/cpp/CMakeLists.txt)
- [ios/miniaudiodart.podspec](ios/miniaudiodart.podspec)
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

- Android: `android/src/main/jniLibs/<abi>/libaudio_engine.so`
- iOS: link `audio_engine.xcframework` in Xcode/Podspec
- Windows: place `audio_engine.dll` next to executable
- Linux: ship `libaudio_engine.so` with app bundle and ensure loader path

## Example

See [example/main.dart](example/main.dart) for a complete usage sample.
