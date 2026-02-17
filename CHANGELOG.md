# Changelog

## 0.2.0

- Added new miniaudio-powered FX APIs:
  - `setBandpass(enabled, cutoffHz, q)`
  - `setPeakEq(enabled, gainDb, q, frequencyHz)`
  - `setNotch(enabled, q, frequencyHz)`
  - `setLowshelf(enabled, gainDb, slope, frequencyHz)`
  - `setHighshelf(enabled, gainDb, slope, frequencyHz)`
- Wired new FX end-to-end across native engine, Dart FFI, and public `MiniAudioPlayer` API.
- Expanded example EQ screen with interactive controls for the new FX for easier testing.
- Updated documentation and feature lists to include the new filter/EQ set.

## 0.1.0

- Initial release of `sautiflow`.
- Cross-platform audio playback engine via miniaudio and Dart FFI.
- Playlist controls: play, pause, stop, seek, next, previous, jump, shuffle, loop.
- Audio effects support: gain, pan, EQ, reverb, low/high-pass, delay.
- Platform support: Android, iOS, macOS, Linux, and Windows.
