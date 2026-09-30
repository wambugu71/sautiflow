# Changelog

## v0.6.30 — 2026-09-24

- **[7-Zone Mastering Signal Chain]** Reorganized the core audio processing callback (`audio_engine.cpp`) into a 7-zone mastering topology to resolve routing and placement issues:
  1. *Intermodulation distortion reduction:* repositioned Dattorro figure-8 tank reverb (`ReverbNode`) and spatial wideners downstream of non-linear saturation stages (`AnalogWarmthDSP`, `TapeDriftDSP`). Driving recirculating delay taps through polynomial saturation curves previously generated intermodulation distortion ($|mf_1 \pm nf_2|$); spatialization now runs post-saturation so tape and tube character are applied to the dry signal before spatial diffusion.
  2. *Reverb tail protection:* moved `NoiseGateDSP` and `DownwardExpanderDSP` to Zone 1 (Restoration), upstream of spatialization and reverb. Low-level reverb tails previously crossed the noise gate threshold prematurely, causing chatter and premature cutoff.
  3. *Dynamics ordering:* reordered dynamics processing so compression runs in Zone 4 before master tone shaping, and peak limiting (`MasterLimiterDSP` / `LookAheadLimiterState`) runs in Zone 7 (Mastering and Output). This prevents the limiter from clamping transients before compression makeup gain, eliminating overshoot and pumping while providing true-peak protection across volume, ISO 226 loudness, and AutoEQ convolution gain.
  4. *De-esser placement:* moved split-band `DeEsserDSP` (4–9 kHz) to Zone 2 ahead of spatialization, preventing vocal sibilants from feeding into the reverb tank or spatial diffusors.
  5. *Metering alignment:* moved ITU-R BS.1770 LUFS and true-peak metering to Zone 6 after the Broadcast Leveller AGC so visualizer and loudness telemetry reflect output volume.
  6. *Multichannel and float precision:* retained stereo extraction for Front L/R channels across stereo-only DSP modules while passing Center, LFE, and Surround channels through in 64-bit float precision. Added node latency tracking to the Audio Engine Diagnostic panel.
- **[Dattorro Reverb Calibration]** Corrected DSP scaling in `ReverbNode`: eliminated half-wave LFO clipping in modulated allpasses by storing quiescent center delays with symmetric excursion headroom; corrected loop decay using true Dattorro round-trip delay ($T_{\text{loop}} \approx 0.725\text{s}$) to map room size ($0.0 \dots 1.0$) to physical RT60 times ($0.35\text{s} \dots 14\text{s}$); removed the $1.5\text{ rad}$ cutoff limit on the damping filter to preserve treble above $15\text{ kHz}$ at zero damping; widened pre-filtering ($80\text{ Hz}$ HPF / $15\text{ kHz}$ LPF); normalized M/S stereo width ($1.0 = \text{neutral}$), removing $17.5\%$ anti-phase cross-talk; updated Sautiplay reverb presets.
- **[Real-Time Audio Callback Safety]** Removed dynamic memory allocations and blocking synchronization from the real-time audio thread (`data_callback`). Preallocated `sidechain_buf_` in `AudioClarityDSP` (16,384 samples) and partitioned processing to avoid runtime `.resize()` calls. Clamped buffer allocations to static capacities. Removed console I/O and mutex acquisitions from render callback paths, and removed mutex lock around `decodeProducerCv.notify_one()` to prevent priority inversion.
- **[Custom Sinc Resampling in Pitch Shifter]** Replaced the linear interpolator in `pitchResampler` (`ma_resample_algorithm_linear`) with `ma_resample_algorithm_custom` bound to the engine's custom sinc resampler vtable (`g_customResamplerVTable`), with a 4th-order low-pass filter fallback. Added 4th-order anti-aliasing filtering (`lpfOrder = 4`) to crossfade linear resamplers to reduce high-frequency roll-off during pitch and speed adjustments.
- **[Multi-Rate Psychoacoustic Noise Shaping]** Re-calibrated 5th-order noise shaping filter coefficients across standard (44.1k/48k), high-resolution (88.2k/96k), and ultra-high-resolution (176.4k/192k+) rate tiers for Shibata, Low-Shibata, High-Shibata, Lipshitz, F-weighted, and Modified E-weighted curves. Passed active rate to the dither stage across both 64-bit and 32-bit output paths and resampler conversion.
- **[Spatial Surround Stereo Balance]** Fixed soundstage balance shifts during spatial surround engagement in `SpatialSurroundDSP`. Updated the envelope fade-in to iterate per stereo frame rather than per interleaved sample, applying matching gain to Left and Right channels during the 50 ms ramp. Added `getAntiPop()` accessor.
- **[Analog Warmth Tape Damping Scaling]** Corrected tape damping rate scaling in `AnalogWarmthDSP`. Updated `updateTapeFilter()` to dynamically compute `effective_sr = sample_rate_ * os_mul` across 1x, 2x, and 4x oversampling factors, scaling one-pole tape damping ($0.1250$ at 1x, $0.0625$ at 2x, $0.03125$ at 4x). Added `getTapeDamping()` getter.
- **[Multichannel Support in DSP Suite]** Resolved channel cross-contamination when playing 5.1 (6-channel) or 7.1 (8-channel) streams through the native DSP suite (`audio_engine.cpp`). Native DSP modules expect interleaved stereo pairs $[L, R]$; passing multichannel buffers previously caused Center/LFE and Surround channels to be processed as stereo pairs. Implemented stereo extraction and re-interleaving for both 32-bit float and 64-bit double processing pipelines (`e->dspStereoBuffer` / `e->dspStereoBuffer64`), de-interleaving channels 0 & 1 into an aligned stereo frame, applying DSP across all buffer frames, and writing stereo results back into the multichannel stream while preserving Center, LFE, and Surround channels.
- **[F32 Output Path Memcpy Fix]** Resolved undefined behavior in the F32 hardware path of `data_callback` (`audio_engine.cpp`) where `memcpy` was called with identical source and destination pointers. Guarded the final copy with an identity check `if (finalDstBuffer != pOutput)`.
- **[Base-Rate Nonlinear Saturation Aliasing]** Confined rational soft-clipping in `DynamicBassDSP` strictly to the isolated sub-120 Hz DC-blocked fundamental bass channel where harmonics remain below Nyquist, removing full-band soft-clipping from `shapeMix` and `processDynamicMultiPole`. Replaced saturation in `DynamicSystemDSP` with direct linear assignment from the phase-aligned ladder matrix reconstruction.
- **[De-Esser Soft Knee & Coefficient Modulation]** Replaced the piecewise hard threshold in `DeEsserDSP` with a quadratic soft knee across a 4.0 dB transition width. Throttled `updateShelfCoeffs` recalculation to trigger only when gain changes by $\ge 0.1\text{ dB}$, and implemented continuous 1 ms active biquad coefficient interpolation for click-free parameter adjustments.
- **[Dialog Enhancer Headroom Compensation]** Added automatic headroom trim compensation capping static 3-band boost to a +12 dB ceiling (`headroom_comp_ = 10^((12 - total_boost)/20)`), dynamic headroom attenuation clamping mid-channel peaks to $\le 0.95$ on voice tracks, and sub-block coefficient calculation throttling to 32-sample boundaries.
- **[Bit-Perfect Exclusive Mode & Direct PCM Streaming]** Implemented raw integer PCM delivery directly to the hardware output ring (`pOutput`) when operating in exclusive mode at unity gain without resampling, pitch scaling, or crossfading. Replaced hardcoded float32 decoder output configuration with native format negotiation (`ma_format_unknown` / `e->outputFormat`), allowing 16-bit and 24-bit tracks to bypass float roundtripping. Added a dedicated `SPSCBuffer<uint8_t> pcmDirectRingBuffer` and runtime eligibility evaluation (`evaluate_direct_pcm_eligibility`), bypassing Stage 1 ReplayGain, normalization, effect filters, master gain multiplication, and dither when direct streaming is eligible. Implemented fallback to the 64-bit float pipeline with TPDF dithering when volume is attenuated, and automatic re-engagement of direct PCM upon returning to unity gain. Disarmed track transition fade-in envelopes during exclusive mode, corrected `bypassAppDsp` evaluation during auto sample-rate matching, and exposed `ae_is_direct_pcm_active` in the C API.
- **[ReplayGain Anti-Clipping]** Added anti-clipping headroom ceiling limiting (`maxSafeLinear = 1.0f / peak`) in `apply_initial_track_loudness`, next track preload in `worker_loop`, and manual ReplayGain setters (`ae_set_replay_gain_with_peak`, `ae_set_next_replay_gain_with_peak`), capping linear gain so amplified audio does not exceed 0 dBFS. Extended autonomous BS.1770-4 preview normalization in `compute_preview_lufs` to track true max sample peaks.
- **[Multichannel Delay Sync in TapeDriftDSP]** Expanded `TapeDriftDSP` to 8-channel surround (up to 7.1) and migrated delay buffering to heap-allocated linear memory. Routed all active channels through the fractional Hermite delay line with identical 15 ms nominal delay, synchronizing Center vocals and Surround channels with the Front stereo stage ($\Delta = 0$) while applying decorrelated phase offsets.
- **[Filter State Retention on EQ Adjustments]** Replaced filter reinitialization with in-place coefficient updates (`ma_*_reinit`), preserving internal biquad delay registers (`pR1`, `pR2`), updating filter bands in place rather than clearing vectors, and implementing `FxBand::uninit` lifecycle management across AutoEQ and dynamic parametric modules.
- **[Device Resampler Input Calculation]** Replaced ceiling math for device resampling with required input frame queries via `ma_resampler_get_required_input_frame_count`. Implemented an output drain loop to prevent silence padding when fractional filter latency is withheld, corrected underrun detection to measure consumed frames against required input frames, and guarded latency queries with `std::try_to_lock`.
- **[Sample Rate Change Audio Offset Fix]** Fixed ~350 ms forward audio skipping during sample rate switching, channel reconfigurations, and device restarts. Replaced the producer thread's forward-looking decoder cursor with the consumed audible frame count (`seekBasePcmFrame + playedPcmFrames`) cross-validated with ring buffer read availability.
- **[FFmpeg Decoder Preroll Discard for Accurate Seeking]** Added `pkt_timebase` configuration to stream decoder contexts, implemented automated preroll calculation from codec parameters and transform filterbank warmup requirements, decoded and discarded priming frames prior to the seek point, and stored overlapping frame suffixes into residual buffers for sample-accurate playback alignment (`maxDiff = 0.000000e+00`).
- **[64-Bit Float Precision Pipeline]** Removed intermediate double/float conversions in the 64-bit audio rendering pipeline. Implemented native 64-bit double precision processing with SIMD acceleration in MasterLimiterDSP, templated DynamicRangeCompressor and LookAheadLimiterState for direct double precision delay buffering and gain modulation, made DSP Suite and Pre-FX float conversions conditional on active modules, and routed dithering and integer quantization directly from double precision to S16, S24, S32, and U8 output formats.
- **[Polyphase Oversampler Kernel Redesign]** Redesigned the 2x/4x polyphase half-band oversampler with a 55-tap Remez equiripple linear-phase FIR kernel, increasing stopband aliasing rejection from 33 dB to $\ge 96.1\text{ dB}$ (+58.6 dB suppression) and reducing passband ripple to $< 0.0003\text{ dB}$ across 20 Hz – 19 kHz with exact 1.000000 DC unity gain and SIMD acceleration.
- **[r8brain Minimum Phase Standardization & SoXR Removal]** Removed `third_party/libsoxr` and all build dependencies, standardizing on r8brain 24-bit Minimum Phase (Mode 12) as the default engine resampler. Remapped legacy SoX enum indices to r8brain in the C++ backend, implemented startup preference migration in Sautiplay `AppStateService`, and routed FFmpeg stream resampling through `swresample` sinc filtering.
- **[Artist Navigation & Catalog Screen]** Made artist subtitles in `NowPlayingScreen` and `MiniPlayer` navigate directly to the artist profile. Added Top Tracks, Albums, Singles, Featured On playlists, Music Videos, and Similar Artists to `ArtistProfileScreen`. Added `ArtistCatalogScreen` for browsing complete song catalogs and discographies.
- **[Loudness Initialization & Crossfade Normalization]** Added instant loudness initialization (`apply_initial_track_loudness`) before frame 0 render to eliminate volume jumps on track start and playlist jumps. Made crossfades loudness-aware with real-time normalizer gains, preserved normalizer processing during crossfades, accelerated initial convergence on the first 10 blocks in the BS.1770 meter, and corrected closed-loop metering placement with inverted normalizer gains.
- **[AutoEQ Reset Behavior]** Fixed profile clear and bypass behavior so clearing an AutoEQ profile resets master preamp gain to 1.0 (0 dB), clears and disables Parametric EQ, zeroes all 32 bands and disables Graphic EQ, resets persisted EQ states to Flat, restores the inline clear button on the pinned AutoEQ bar, and updates the fallback label to 'None (Flat)'.
- **[Offline Stream Cache]** Added a "Save to Offline Cache" action on the Now Playing screen for online streams. Accelerated stream audio downloads via the YoutubeExplode pipeline and resolved Windows file path sanitization and directory resolution issues for cached streams.
- **[AAudio Buffer Capacity Configuration]** Enabled explicit AAudio buffer capacity configuration (`cfg.aaudio.allowSetBufferCapacity = MA_TRUE`) when period sizes are specified. Guarded hardware querying so default period sizes only serve as fallbacks, updated buffer parameters in device latency reporting, and exposed total buffer depth in the Audio Engine Diagnostic panel.
- **[Settings Screen Layout Updates]** Added `AppSettingsTile` and `AppSettingsValueTile` with multi-line title and subtitle wrapping to eliminate text truncation on smaller screens. Replaced raw DSP parameter names with user-facing labels, reorganized settings into logical categories (Playback & Sound, Sources & Data, System & About), and updated subscreen back buttons to dropdown chevrons.
- **[Log Redaction]** Redacted streaming endpoints, authentication tokens, and sensitive query strings from decoder and network engine diagnostic logs.

## v0.6.29 — 2026-09-20

- **[Cross-Platform SIMD DSP Acceleration]** Added a SIMD abstraction (`dsp/simd_math.h`, `SimdFloat4` / `SimdDouble2`) covering ARM NEON, ARM32 VFPv3/VFPv4, x86 SSE/AVX/FMA, and a scalar fallback. Vectorized 14 compute-intensive modules: SubsonicFilter, Oversampler, AnalogWarmth, FFTConvolver, DynamicBass, ScaleTempo, Clarity, DownwardExpander, DeEsser, DialogEnhancer, SpatialSurround, DynamicSystem, MasterLimiter, and StereoImager, preserving 64-bit double precision across recursive low-frequency biquads. Added a 58-test SIMD test suite.
- **[Six DSP Engines]** Added Tier 1 Dynamic Loudness (ISO 226 equal-loudness contours) and AutoEQ parametric profile importer; Tier 2 Broadcast Leveller (EBU R128 AGC with silence freeze) and Studio Noise Gate (dual-threshold hysteresis, sidechain HPF); Tier 3 Dynamic Parametric EQ (compress/expand modes, 6 bands) and Vintage Tape Drift (Catmull-Rom delay, wow/flutter LFOs). Ordered signal chain: gate → tone/tape/dynEQ → leveller → loudness, with FFI bindings, isolate commands, and five collapsible EQ sections.
- **[OpenStage Acoustic Crossfeed]** Added `sauti::dsp::OpenStageDSP` with spherical-head ITD, RBJ shelving biquads, bilinear all-pass delay, de-zippering, anti-pop ramp, and denormal protection, connected through `CrossfeedNode`, the C API, Dart FFI, and isolate dispatch. Added `OpenStageSoundstageVisualizer` to the EQ screen with animated wavefronts, telemetry, and Speaker Angle, Gain Comp, and Mix controls.
- **[FFmpeg Decoder Unification]** Integrated the custom FFmpeg stream decoder and retired the legacy MP4/AAC path. Local files retry through FFmpeg when native miniaudio decoding fails (`forceFallback` in `FFmpegDecoderInitConfig`, retry in `load_decoder_for_path`, channel-layout normalization in `FFmpegLocalFileSource::open`). Removed minimp4, old test runners, and obsolete license notices.
- **[Partitioned FFT Convolver Hardening]** Added a 20 ms anti-pop crossfade and buffer flushing, computed partition FFTs outside `ir_mutex_` to prevent real-time thread starvation, fixed HeSuVi 14-channel routing (Ch 0 left direct, Ch 7 right direct) in `WavParser`, maintained wet signal continuity across IR hot-swaps, and replaced spectral attenuation with peak-only normalization plus tanh soft-saturation on the wet output.
- **[M3E AutoEQ Profile System]** Added an AutoEQ selector built on Material 3 Expressive components with a headphone profile library, parametric profile importer, and isolate-side application. Pinned the control bar on the effects screen and updated the sliver header with visualizer and profile controls.
- **[Stereo Analyzer & Goniometer]** Extended the analyzer tap with `AEStereoStats` and `ae_poll_analyzer_frame_stereo` / `ae_get_stereo_stats` C ABI entry points to capture interleaved L/R audio and calculate phase correlation, balance, M/S RMS, and width per window under `try_lock`. Connected `MiniAudioPlayer.analyzerStereoStream` to a goniometer scatter plot (45° rotation, phosphor trail) and correlation bar with live and simulation modes.
- **[Waveform Seek Bar Optimization]** Moved waveform extraction to `Isolate.run` with 2 KB windowed I/O and integer math, added a synchronous peak fallback, queue pre-fetching, and a Frame-0 mount notifier. Switched rendering to batched `drawRawPoints` with cached geometry and a direct-canvas playhead thumb inside a `RepaintBoundary` for 60–120 Hz response.
- **[Album Art Shapes & Queue Safety]** Added `AlbumArtShape` configuration in `AppThemeService` and Settings, applied across the mini player, shimmer player, and now-playing screen. Disabled swipe-to-dismiss on queue rows and hid the per-row remove button to prevent accidental queue edits.
- **[EQ Screen Refinements]** Redesigned Dynamic EQ with a response graph and horizontal band cards, expanded it to 6 bands with normalization, enabled the noise gate and AGC leveller meters, and cleaned up labels across Broadcast Leveller, ReplayGain, OpenStage, and the default preset. Restored the Dolby Digital Plus HRIR preset and fixed `WavParser` Float32List typing.
- **[GPL-3.0 Licensing]** Relicensed the engine and app under GPL-3.0 and expanded `THIRD_PARTY_NOTICES.md` to cover bundled C/C++ engine and Dart dependencies.
- **[Documentation Links]** Added a Docs entry to the masthead navigation and footer on the Sautiplay site, linking header release badges and ENGINE cards directly to documentation.

## v0.6.28 — 2026-09-16

- **[Parametric EQ Filter Expansion]** Added 5 filter types: `allpass`, `asuperpass`, `bandreject`, `asuperstop`, and `asupercut`. Implemented Transposed Direct Form II engine processing with analytical coefficient derivation, cascaded Butterworth SOS stages for steep roll-offs and notch suppression, multi-stage transfer function evaluation in `ParametricEqGraph`, and depth controls in Sautiplay.
- **[Native FFmpeg Audio Metadata & Album Art Reader]** Replaced third-party metadata readers with direct libavformat, libavcodec, and libavutil extraction (`read_file_metadata_ffmpeg`). Extracts audio tags, embedded album pictures (`AV_DISPOSITION_ATTACHED_PIC`), and ReplayGain metadata (tags and `AV_PKT_DATA_REPLAYGAIN` packet side-data) with thread isolation for network streams.
- **[DSP Pipeline & Real-Time Safety]** Replaced blocking mutexes with lock-free `try_to_lock` patterns on real-time audio threads. Added oversampling (1x/2x/4x) to AnalogWarmth and AudioClarity DSPs with pre-allocated buffers. Confined soft clipping in dynamic bass processors to prevent foldback aliasing, added initialization safety guards across all DSP filters, and repositioned DSP bypass ahead of ReplayGain/Normalizer for direct bit-perfect playback.
- **[Engine Resampler & Streaming Correctness]** Handled input caps and tail flushing in r8brain and libsamplerate backends, converted integer formats strictly in the float domain, routed post-dither conversions through exact rounding (`f32ToIntExact`), and made algorithm switching atomic and thread-safe. Fixed ICY metadata deadlock and seek/ring-buffer race conditions in network streaming with proper EOF flush handling.
- **[In-App FAQ]** Integrated a dedicated FAQ section in Misc & System settings derived from the user manual, styled with Material 3 Expressive expandable cards, category filtering, search, and bit-perfect playback guidance.
- **[Real-Time ReplayGain Telemetry]** Added track and album ReplayGain gain/peak telemetry to the Audio Engine Diagnostic panel for real-time loudness inspection.
- **[Waveform Seek Bar]** Updated the waveform seek bar with higher-resolution bars and interpolated audio sampling.

## v0.6.27 — 2026-09-08

- **[64-Bit Float DSP Pipeline]** Implemented IEEE 754 double precision (64-bit float) processing across the active DSP chain (SubsonicFilter, Biquad64 EQ, 3-band tone EQ, user gain, soft limiter, and monitor routing) when `use64BitProcessing` is active. Zero runtime allocations achieved via a preallocated 262,144 double-precision buffer in `ae_init()`.
- **[Remez Equiripple Polyphase Oversampler]** Corrected tap chronology inversion in polyphase oversampling to eliminate 20 kHz treble roll-off. Calibrated Remez half-band equiripple filter coefficients for flat passband (<0.75 dB ripple) and exact 1.0000 DC unity gain. Added templated float and double oversamplers (`PolyphaseOversampler2x64` / `4x64`) with C ABI, Dart FFI, and UI integration.
- **[Dattorro Diffuse Tank Reverb]** Upgraded ReverbNode to a Dattorro figure-8 diffuse tank with cascaded dual-channel input diffusers, dual-phase quadrature LFO modulation to eliminate metallic flutter echoes, 160 Hz HPF / 7.5 kHz LPF pre-filtering, physically scaled one-pole damping, and 14 decorrelated stereo taps.
- **[Bell & Tilt Parametric EQ Filters]** Added `AE_EQ_BAND_BELL` and `AE_EQ_BAND_TILT` filter modes to Parametric EQ. Implemented complementary shelving pairs for Tilt filtering with pivot frequency and variable slope. Updated `ParametricEqGraph` with real-time composite frequency response curve evaluation.
- **[FFT Window Functions]** Implemented Hann, Hamming, Blackman-Harris, and Flat-Top FFT windows in C++, Dart FFI, and DSP analysis pipelines with coherent gain compensation, plus an interactive window selector and comparison guide in Settings.
- **[Spectrum Analyzers]** Added `PhysicsDotsVisualizer` (segmented LED matrix with gravity falloff, fast attack, and peak-hold free-fall) and `FluidAreaVisualizer` (cross-band surface tension ripples with floating peak drape), running at 60/120 FPS on custom canvas.
- **[Sample-Rate Aware Scaling & Dynamic Nyquist]** Computed Nyquist limits ($F_s / 2$) dynamically in `FftProcessor` and connected hardware sample-rate inspection to visualizers. Added Logarithmic (octave binning, dB) vs Linear (kHz binning, magnitude) toggle.
- **[EQ Interface Layout]** Decimated Graphic EQ frequency labels for 16- and 32-band layouts on mobile screens. Reordered the DSP chain (ingress polarity/pre-gain, egress balance/safety limiter) and placed Limiters and Loudness cards into dedicated sections.
- **[FFmpeg Stream Resampler Decoupling]** Decoupled online network streams to use FFmpeg's native internal `SwrContext` resampler without routing through external sinc backends. Added defensive flush null-checks and dynamic handle recreation on rate switches in `libsoxr`.
- **[Memory & Queue Optimization]** Offloaded album art decoding to background worker isolates and downscaled raw art to 120x120 cached thumbnails. Lazily mounted `QueueScreen` in PageView and added an interactive draggable fast scrollbar with an animated shortcut dock.

## v0.6.26 — 2026-09-08

- **[In-App Update Detection]** Added automated release detection against the GitHub Releases API with strict OS and CPU ABI matching (`dart:ffi` `Abi.current()`), distinguishing Android ARM64 (`sautiflow_android_arm64.apk`), Android ARMv7 (`sautiflow_android_armv7.apk`), macOS, Windows, and Linux.
- **[Background Isolate Streaming & Resumable Downloads]** Offloaded binary download, chunk streaming, and file writing to a background worker Isolate with throttled progress updates to keep the UI at 120 FPS. Integrated HTTP Range headers (`206 Partial Content`) to automatically resume interrupted downloads.
- **[Material 3 Expressive Dialog]** Implemented `M3EDialog` update prompt with animated `M3EProgressIndicator.linearWavy`, tabular byte sizing (`FontFeature.tabularFigures()`), and in-flight cancel, restart, and resume controls.
- **[Network Drop Watchdog]** Added an 18-second inactivity watchdog to handle silent network drops, with guaranteed file handle closure to prevent file locks.
- **[Android In-App Package Installation]** Connected native `FileProvider` and `REQUEST_INSTALL_PACKAGES` permission in `MainActivity.kt` for APK installation prompts.
- **[Settings Screen Update Status]** Added an interactive "Check for Updates" tile and an "UPDATE AVAILABLE" category badge in Settings.

## v0.6.25 — 2026-09-05

- Bug fixes and performance improvements.
- Added audio backend selection for Android.
- Decoupled home screen UI components.

## v0.6.24 — 2026-09-02

- **[Android Online Stream Architecture Fix]** Resolved online stream playback stalls on Android by implementing a two-stage resampler initialization in `ffmpeg_stream_decoder.cpp`. Falls back from SoXR to FFmpeg's native `SWR_ENGINE_SWR` engine with 32-tap sinc filtering, eliminating `AVERROR(EINVAL)` (-22) failures when `libsoxr` is not present in Android prebuilts.
- **[Track Switch & Decoder Mutex Contention]** Resolved decoder mutex lock starvation in `audio_engine.cpp` during track changes and playlist jumps by releasing `decoderMutex` before waiting on `decodeProducerCv`. Reduced track loading latency from 20+ seconds to ~1 ms.
- **[Stream Probing Zero-Rate Guards]** Guarded `soxr_onInit` and `src_onInit` against unprobed or non-positive sample rates during dynamic stream format discovery, preventing `MA_ERROR` aborts.
- **[Android MediaSession Timeline Telemetry]** Corrected `bufferedPosition` in `mobile_system_audio.dart` to report absolute media timeline position (`currentPositionMs + bufferAheadMs`), preventing Android MediaSession underflow stalls and lockscreen notification dismissals.
- **[Push Stream Start Threshold]** Maintained a 32 KB initial buffer threshold in `pushStream` for immediate audio start on chunked and live radio streams.
- **[Isolate Stream Telemetry]** Connected real-time stream telemetry from `IsolateAudioPlayer` into `MiniAudioSystemAudioController`.

## v0.6.23 — 2026-08-28

- **[Universal Native Streaming Build Support]** Enabled `-DSAUTIFLOW_ENABLE_FFMPEG=1` across all platform build systems (Windows, Linux, Android, iOS, and macOS). Fixed network streaming support detection (`isNetworkStreamingSupported`), eliminated isolate `ArgumentError` exceptions on network source enqueueing, and rebuilt Windows native DLLs.
- **[Dynamic System Bass DSP]** Implemented dual-cascade 4-pole multi-band ladder matrix dynamic bass DSP with 19 acoustic transducer hardware presets and sample-by-sample parameter de-zippering.
- **[Acoustic Hardware Transducer Presets]** Exposed dynamic profile selection and dynamic drive control across the native C++ engine, Dart FFI bindings, and Sautiplay EQ screen.
- **[Audio Engine Quality & Playback Fixes]** Enabled Lookahead Safety Limiter by default to prevent inter-sample clipping, added perceptual cubic volume curve mapping and dB volume controls, integrated ISO 226 equal-loudness contour compensation in the real-time spectrum analyzer, smoothed audio ducking ramps, and added dynamic status polling for lower idle CPU consumption.

## v0.6.22 — 2026-08-20

- **[Synced Lyrics]** Integrated online YouTube Music timed lyrics fetching and offline companion `.lrc` / `.txt` local file import with auto-scroll active line viewport centering, interactive click-to-seek, and frosted album art overlay.
- **[Dynamic Range Processing]** Added Studio Dynamic Range Compressor (threshold, ratio, attack, release, knee, auto-makeup gain), Downward Expander & Adaptive Noise Floor Reducer, and Split-Band / Wide-Band De-Esser.
- **[Subsonic Protection & Resampling Defaults]** Implemented 18 Hz high-pass subsonic filter, 2x polyphase half-band oversampling for saturation stages, multi-arch DAZ/FTZ denormals flushing (x86_64 and ARM64/NEON), and libsoxr sinc resampler defaults.
- **[Material 3 Expressive UI]** Redesigned dark metallic `ModernAudioKnob` with radial glow, optimized mobile album art layering, and added Telegram community links to settings.

## v0.6.21 — 2026-08-14

- **[Native Streaming Engine]** Integrated embedded FFmpeg (`libavformat` + `libavcodec` + `libswresample`) decoding backend into miniaudio with a 10-second lock-free jitter ring buffer, live ICY metadata parsing, and effects pipeline integration.
- **[Spatial Surround Suite]** Added real-time 3D spatial surround suite (Field Expander, Haas Spatializer, ViPER Headphone Surround+, Matrix 5.1 HRTF) with per-sample anti-pop smoothing.
- **[DSP Dynamics & Dither]** Parametric Reverb wet/dry gain staging, BS.1770 loudness normalizer telemetry, and psychoacoustic noise-shaping dither.
- **[Sample-Accurate Crossfade]** Implemented non-blocking crossfade pipeline with graceful abort and stall watchdog.
- **[DLNA & Cast]** Added cross-platform DLNA cast-out and integrated DLNA MediaRenderer receiver.
- **[Sautiplay M3E Redesign]** Updated UI with Material 3 Expressive carousels, reactive search with suggestions, and unified Dark Blue theme.
- **[CI/CD Release Automation]** Automated multi-platform release build generation and Telegram channel release notifications.

## v0.6.20 — 2026-08-04

- **[DSP Engine & Audio Architecture]** Updated Sautiflow engine and Sautiplay app with 64-bit float DSP pipeline, bit-perfect hardware rate matching, Ambiophonics crossfeed, and psychoacoustic noise-shaping dither modes.
- **[Dynamic Cover Art & Theme Engine]** Added Material 3 Isolate-driven cover art color extraction (`ArtworkThemeService`) that generates harmonious palettes from album art without UI stutter.
- **[Waveform Seek Bar]** Added interactive waveform seek bar widget (`WaveformSeekBarWidget`) with background waveform extraction (`WaveformExtractorService`) and pending seek state reset handling across track changes.
- **[GPU GLSL Visualizers]** Added 15 custom GPU GLSL audio-reactive visualizer presets with a pinned mobile control bar and animation pause/resume on playback state changes.
- **[Network Sources & Media Streaming]** Added FTP and DLNA/UPnP network source browser, local folder caching, built-in HTTP local media server (`LocalMediaServer`), and network stream player navigation.
- **[App Onboarding]** Integrated `showcaseview` package with themed `AppShowcase` for step-by-step feature onboarding for new installs.
- **[Library & Storage]** Added Album and Genre hierarchical groupings for local library, and fixed mobile profile and playlist export file saving on Android and iOS.
- **[UI Organization & Polish]** Reorganized Settings screen into clean category sub-screens with unified Material 3 styling and fixed lint rule compliance.

## v0.6.19 — 2026-07-28

- **[AutoEQ & Presets]** Added native AutoEQ profile parser service supporting `GraphicEQ.txt` lines and `ParametricEQ.txt` text blocks (`autoeq_parser.dart`).
- **[AutoEQ UI]** Added unified AutoEQ & Presets Importer UI in Sautiplay to import and apply `.txt`, `.irs`, `.wav`, and `.vdc` profiles.
- **[AutoEQ Headroom Scaling]** Integrated automatic preamp gain scaling to prevent digital clipping when applying AutoEQ boosts.
- **[UI Fixes]** Fixed `NestedScrollView` and `Scrollbar` `ScrollController` position conflicts in Sautiplay tab views.

## v0.6.18 — 2026-07-20

- Bug fixes and improvements in the audio engine.
- Updated version numbers across the package and Sautiplay app.

## v0.6.17 — 2026-07-12

- **[Android]** Added MethodChannel hardware audio inspection for Android `AudioServiceActivity` in Sautiplay.
- **[Android]** Fixed JNI reflection hidden API restrictions on Android 9+ and resolved `IsolateAudioPlayer` inspection compatibility.

## v0.6.16 — 2026-07-04

- Fixed minor bugs and improved performance and stability.
- Updated Sautiplay app to use the latest version of Sautiflow.

## v0.6.15 — 2026-06-25

- **[Core/FFI]** Added real-time native hardware output inspection API (`AEHardwareInfo` & `ae_get_hardware_info`). Exposes active audio backend (`WASAPI`, `AAudio`, `Core Audio`, `PulseAudio`, `ALSA`), negotiated hardware sample rate, bit depth, buffer frame size, latency in ms, active soundcard device name, and exclusive mode status.
- **[Apps/UI]** Added Hardware Audio Output & Device Inspector modal sheet to Sautiplay Now Playing Screen.
- **[Core]** Fixed crossfade handling and resolved stability bugs in the Sautiflow library.
- **[Apps/UI]** Added Sauti DSP Suite effects, UI refinements, and performance improvements to Sautiplay.

## v0.6.11 — 2026-06-18

- Fixed Linux build error: added missing `cstdint` include for `uint32_t` in `TubeSimulator`.

## v0.6.10 — 2026-06-15

- GitHub Actions CI workflow fix: removed branch triggers from publish workflow to resolve pub.dev tag `refType` error.

## v0.6.9 — 2026-06-10

- CI deployment fix: bumped version following successful publish.

## v0.6.8 — 2026-06-05

- Fixed Linux build error (`cmath` / `std::abs`).
- Fixed Windows build error (coroutine deprecation warning).

## v0.6.4 — 2026-05-20

- Version bump for release.

## v0.6.3 — 2026-05-12

- **[Build]** Added unsigned iOS `.ipa` generation to GitHub Actions workflow for sideloading.
- **[Docs]** Updated Sautiplay README with instructions on how to install the `.ipa` using unsigned methods like Sideloadly or AltStore.

## v0.6.2 — 2026-05-02

- Fixed missing C++ headers in published package.

## v0.6.1 — 2026-04-20

- **[Core]** Added `getPipelineState()` API to query the native C++ audio engine pipeline state, tracking the flow from input source -> internal DSP processing -> hardware output format.
- **[Apps/UI]** Implemented the pipeline state viewer inside the Sautiplay EQ Screen.

## v0.6.0 — 2026-04-10

- **[DSP Effects]** Added Stereo Widening feature using a hybrid Haas Effect + Mid/Side (M/S) Matrix algorithm. Exposes `setStereoWiden({required bool enabled, required double width, required double delayMs})` in `MiniAudioPlayer` and `IsolateAudioPlayer`.
- **[UI/Apps]** Integrated Stereo Stage configuration knobs into the Example app and Sautiplay EQ screens.
- **[Apps]** Added persistent state saving for Stereo Widening options in Sautiplay's SharedPreferences.

## v0.5.0 — 2026-03-25

- **[Pitch & Spatialization]** Added native miniaudio audio features:
  - Pitch Control with `setPitch(double)`.
  - 3D Spatial Audio: enable via `setSpatializationEnabled(bool)` and position sound sources via `setPosition(x,y,z)`, `setDirection()`, and `setVelocity()`.
  - 3D Audio parameters: Doppler effect, attenuation models, rolloff factor, min/max gain, and distance thresholds.
  - Fading: `setFade(startVol, endVol, durationMs)`.
  - Playback scheduling: `scheduleStartTimeInPcmFrames(time)` and `scheduleStopTimeInPcmFrames(time)`.
- **[Example App]** Updated demonstration app with sliders to configure pitch shifting and 3D spatial audio in real time.
- **[Resampling]** Integrated `libsamplerate` (Secret Rabbit Code) for sinc sample rate conversion with algorithms:
  - `srcSincBestQuality`
  - `srcSincMediumQuality`
  - `srcSincFastest`
  - `srcZeroOrderHold`
  - `srcLinear`
- Exposed algorithms in `MiniAudioPlayer.setEngineResampleAlgorithm(ResampleAlgorithm)`.
- Updated Windows and Android CMake build systems to compile `libsamplerate` alongside `miniaudio`.
- Enhanced example application with UI dropdown to dynamically change resampling algorithms.

## v0.4.0-dev — 2026-02-15

- Added standalone object-oriented filter API wrapping miniaudio natively (`MiniaudioLpf1`, `MiniaudioLpf2`, `MiniaudioLpf`, `MiniaudioHpf1`).
- Added standalone `MiniaudioBiquad` filter wrapper.
- Added standalone `MiniaudioResampler` with support for linear and sinc algorithms and dithering modes.
- Added support for `s24` and `s32` AudioFormats in native engine mappings.
- Re-architected C++ FFI to expose standalone filters independently of the main `AudioEngineHandle` player.
- **[Real-Time DSP]** Injected `ma_lpf1`, `ma_hpf1`, and `ma_biquad` as native nodes in the main AudioEngineHandle data callback.
- **[Real-Time DSP]** Exposed `setEngineResampleAlgorithm` and `setEngineDitherMode` to dynamically re-configure the global audio device.
- Updated documentation and the example app with controls for testing native backend integrations.

## v0.3.0-dev — 2026-01-20

- Added mixed multiband FX implementation.
- Added public Dart model types for user-defined band chains:
  - `EqBandType` (`peak`, `bandpass`, `notch`, `lowshelf`, `highshelf`)
  - `EqBandConfig` (per-band `frequencyHz`, `q`, `gainDb`, `slope`, `enabled`)
- Added `MiniAudioPlayer` APIs:
  - `initMultibandFx(bands, enabled: true)`
  - `setMultibandFxBands(bands)`
  - `setMultibandFxEnabled(enabled)`
  - `clearMultibandFx()`
- Wired mixed multiband FX path through Dart FFI and native C/C++ ABI (`ae_set_multiband_fx_*`).
- Added real-time analyzer frame API for visualization pipelines:
  - Native C ABI: `ae_set_analyzer_enabled`, `ae_configure_analyzer`, `ae_poll_analyzer_frame`
  - Dart FFI & `MiniAudioPlayer`: `configureAnalyzer`, `setAnalyzerEnabled`, `getLatestAnalyzerFrame`, `analyzerStream`
- Added transition crossfade controls:
  - `setCrossfadeEnabled(bool)`
  - `setCrossfadeDurationMs(int)`
- Updated output sample-rate handling so `setOutputSampleRate(0)` applies native device rate mode.

## v0.2.0 — 2025-12-10

- Added miniaudio-powered FX APIs:
  - `setBandpass(enabled, cutoffHz, q)`
  - `setPeakEq(enabled, gainDb, q, frequencyHz)`
  - `setNotch(enabled, q, frequencyHz)`
  - `setLowshelf(enabled, gainDb, slope, frequencyHz)`
  - `setHighshelf(enabled, gainDb, slope, frequencyHz)`
- Wired FX across native engine, Dart FFI, and public `MiniAudioPlayer` API.
- Expanded example EQ screen with controls for new filter and EQ types.
- Updated documentation and feature lists with the new filter/EQ set.

## v0.1.0 — 2025-11-01

- Initial release of `sautiflow`.
- Cross-platform audio playback engine via miniaudio and Dart FFI.
- Playlist controls: play, pause, stop, seek, next, previous, jump, shuffle, loop.
- Audio effects support: gain, pan, EQ, reverb, low/high-pass, delay.
- Platform support: Android, iOS, macOS, Linux, and Windows.
