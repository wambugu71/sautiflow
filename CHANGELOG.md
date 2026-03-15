# Changelog

## 0.6.0

- **[DSP Effects]** Added new Stereo Widening feature using a hybrid Haas Effect + Mid/Side (M/S) Matrix algorithm.
  - Exposes `setStereoWiden({required bool enabled, required double width, required double delayMs})` directly in `MiniAudioPlayer` and `IsolateAudioPlayer`.
  - Enables professional, mono-compatible "wide soundstage" manipulation without destructive phase cancellation.
- **[UI/Apps]** Integrated fully functional "Stereo Stage" configuration knobs into the Example app and Sautiplay EQ screens.
- **[Apps]** Added persistent state saving for the Stereo Widening options in Sautiplay's SharedPreferences.

## 0.5.0

- **[Pitch & Spatialization]** Added new advanced audio features natively using miniaudio:
  - Added robust Pitch Control with `setPitch(double)`.
  - Added 3D Spatial Audio: Enable via `setSpatializationEnabled(bool)` and position sound sources in a 3D environment via `setPosition(x,y,z)`, `setDirection()`, and `setVelocity()`.
  - Configurable 3D Audio parameters: Doppler effect, attenuation models, rolloff factor, min/max gain, and distance thresholds.
  - Added customizable Fading: `setFade(startVol, endVol, durationMs)`.
  - Added granular Playback Scheduling: `scheduleStartTimeInPcmFrames(time)` and `scheduleStopTimeInPcmFrames(time)`.
- **[Example App]** Updated the demonstration app with UI sliders to configure Pitch shifting and 3D Spatial Audio in real-time.

- Integrated `libsamplerate` (Secret Rabbit Code) for audiophile-grade audio resampling.
- Added extensive new resampling algorithms via Flutter FFI to the native C++ audio engine:
  - `srcSincBestQuality`
  - `srcSincMediumQuality`
  - `srcSincFastest`
  - `srcZeroOrderHold`
  - `srcLinear`
- Exposed the new algorithms in `MiniAudioPlayer.setEngineResampleAlgorithm(ResampleAlgorithm)`.
- Updated Windows and Android CMake build systems to natively compile `libsamplerate` alongside `faad2` and `miniaudio`.
- Added m4a AAC decoding support via `faad2`.
- Enhanced example application with UI dropdown to dynamically change resampling algorithms on the fly.

## 0.4.0-dev

- Added standalone object-oriented filter API wrapping miniaudio natively (`MiniaudioLpf1`, `MiniaudioLpf2`, `MiniaudioLpf`, `MiniaudioHpf1`, etc).
- Added standalone `MiniaudioBiquad` filter wrapping.
- Added standalone `MiniaudioResampler` with support for algorithms (`linear`, `sinc`) and dithering modes.
- Added support for `s24` and `s32` AudioFormats in the native engine mappings.
- Re-architected C++ FFI to expose these standalone filters independently of the main `AudioEngineHandle` player.
- **[Real-Time DSP]** Injected custom `ma_lpf1`, `ma_hpf1`, and `ma_biquad` as native nodes in the main AudioEngineHandle data callback.
- **[Real-Time DSP]** Exposed `setEngineResampleAlgorithm` and `setEngineDitherMode` to dynamically re-configure the global audio device.
- Updated documentation and the example app to include interactive, real-time SLIDER and DROPDOWN controls for testing the native backend integrations.

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
