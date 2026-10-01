# Sautiplay

![Sautiplay](../docs/assets/sautiflow.png)

A cross-platform music player for audiophiles, built with Flutter and powered by the [Sautiflow](../README.md) C++ audio engine.

[Website](https://sautiflow.nett.to) | [Download Releases](https://github.com/wambugu71/sautiflow/releases/latest) | [Telegram Community](https://t.me/+MilnrgkNkbFiYmY0) | [Issues](https://github.com/wambugu71/sautiflow/issues)

## Overview

Sautiplay is an offline-first player designed for bit-perfect output and direct hardware access. It bypasses shared system mixers and OEM audio effects to deliver clean sound straight to your DAC or headphones.

- **Direct hardware output**: requests AAudio MMAP on Android, WASAPI Exclusive on Windows, CoreAudio on Apple platforms, and ALSA on Linux.
- **Sample rate matching**: adjusts the output DAC clock to match source audio (44.1 kHz up to 192 kHz).
- **Sinc resampling**: embeds `r8brain` and `libsamplerate` for local tracks, and FFmpeg for network streams.
- **DSP chain**: parametric and graphic equalizers, AutoEQ profile import, impulse response (WAV) convolution, BS2B crossfeed, and optional 64-bit float precision.
- **Privacy**: no ads, no telemetry, no tracking, and no accounts.
- **Streaming & casting**: web stream playback, UPnP/DLNA casting, and a local DLNA MediaRenderer receiver.

## Downloads

Pre-built binaries are available on [GitHub Releases](https://github.com/wambugu71/sautiflow/releases/latest):

- **Android**: ARM64 and ARMv7 APKs
- **Windows**: portable ZIP
- **Linux**: tar.gz
- **macOS**: ZIP
- **iOS**: IPA (install with AltStore or Sideloadly)

## Building from source

Prerequisites: Flutter SDK and platform build tools (Visual Studio on Windows, Xcode on macOS, Android Studio and NDK on Android, clang/make on Linux).

1. Clone the repository:
   ```bash
   git clone https://github.com/wambugu71/sautiflow.git
   cd sautiflow/sautiplay
   ```

2. Fetch dependencies:
   ```bash
   flutter pub get
   ```

3. Run the app:
   ```bash
   flutter run
   ```

For detailed platform prerequisites, configuration flags, and release build recipes, see the [documentation](https://sautiflow.nett.to).

## Community and support

- Telegram: [Sautiplay / Sautiflow group](https://t.me/+MilnrgkNkbFiYmY0)
- Support development: [Buy Me a Coffee](https://buymeacoffee.com/wambugu)

## License

Sautiplay is open-source software licensed under the GNU General Public License v3.0. See [LICENSE](LICENSE) for details.

Third-party notices and licenses for miniaudio, FFmpeg, libsamplerate, and r8brain are in [THIRD_PARTY_NOTICES.md](../THIRD_PARTY_NOTICES.md).
