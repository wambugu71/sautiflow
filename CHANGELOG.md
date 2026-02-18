# Changelog

## 0.3.0-dev

- Started unified mixed multiband FX implementation.
- Added new public Dart model types for user-defined band chains:
  - `EqBandType` (`peak`, `bandpass`, `notch`, `lowshelf`, `highshelf`)
  - `EqBandConfig` (per-band `frequencyHz`, `q`, `gainDb`, `slope`, `enabled`)
- Added `MiniAudioPlayer` APIs:
  - `initMultibandFx(bands, enabled: true)`
  - `setMultibandFxBands(bands)`
  - `setMultibandFxEnabled(enabled)`
  - `clearMultibandFx()`
- Wired new mixed multiband FX path through Dart FFI and native C/C++ ABI (`ae_set_multiband_fx_*`).
- Added initial realtime analyzer frame API for visualization pipelines:
  - Native C ABI: `ae_set_analyzer_enabled`, `ae_configure_analyzer`, `ae_poll_analyzer_frame`
  - Dart FFI + `MiniAudioPlayer` surface:
    - `configureAnalyzer(frameSize: ...)`
    - `setAnalyzerEnabled(enabled)`
    - `getLatestAnalyzerFrame()`
    - `analyzerStream`
- Added transition crossfade controls end-to-end:
  - `setCrossfadeEnabled(bool)`
  - `setCrossfadeDurationMs(int)` (native clamp `0..10000`)
- Updated output sample-rate handling so `setOutputSampleRate(0)` now applies native device rate mode.

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
