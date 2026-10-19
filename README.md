# Sautiflow

![Sautiflow Logo](docs/assets/sautiflow.png)

A cross-platform audio playback and DSP engine for Dart and Flutter, built in C++ on miniaudio.

[Documentation](https://sautiflow.nett.to) | [Download Sautiplay](https://github.com/wambugu71/sautiflow/releases/latest) | [Telegram Community](https://t.me/+MilnrgkNkbFiYmY0) | [Issues](https://github.com/wambugu71/sautiflow/issues)

For the player application built on this engine, see [Sautiplay](sautiplay/README.md).

## Overview

Sautiflow provides low-latency playback, gapless transitions, and direct DSP control through Dart FFI. Audio passes bit-exact to hardware when sample rates match, or resamples with high-precision sinc filters when conversion is required.

- **Playback**: gapless transitions, playlist management, shuffle, loop modes, and native network streaming.
- **DSP chain**: 3-band and multiband EQ, parametric biquad filters, reverb, delay, stereo widening, and headphone crossfeed (BS2B, Joe0bloggs).
- **Format support**: MP3, AAC, OGG, FLAC, WAV, and ALAC decoded to 32-bit float PCM.
- **Resampling**: sinc resampling with `r8brain` and `libsamplerate`.
- **Telemetry**: pipeline state inspection, track metadata inspection, and real-time event streams.

## Platforms

- Android (AAudio, OpenSL ES)
- iOS (CoreAudio, AudioQueue)
- macOS (CoreAudio)
- Windows (WASAPI)
- Linux (ALSA, PulseAudio)

## Quick start

Add the dependency to `pubspec.yaml`:

```yaml
dependencies:
  sautiflow: ^0.6.32
```

Initialize the player and start playback:

```dart
import 'package:sautiflow/sautiflow.dart';

final player = MiniAudioPlayer();
player.init();

player.setAudioSources([
  AudioSource.uri(Uri.parse('https://example.com/track.mp3')),
]);

player.play();
```

For the complete API reference, DSP configurations, and platform build steps, visit the [documentation](https://sautiflow.nett.to). A runnable Flutter example is in [example/main.dart](example/main.dart).

## Community and support

- Telegram: [Sautiplay / Sautiflow group](https://t.me/+MilnrgkNkbFiYmY0)
- Support development: [Buy Me a Coffee](https://buymeacoffee.com/wambugu)

## License

This project is licensed under the GNU General Public License v3.0. See [LICENSE](LICENSE) for details.

Third-party notices and licenses for miniaudio, FFmpeg, libsamplerate, and r8brain are in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
