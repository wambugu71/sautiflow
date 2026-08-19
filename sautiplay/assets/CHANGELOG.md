## v0.6.20 — 2026-08-18
- Reesigned the app with material 3 expressive components for a fresh look. 
- Add developer info (name, copyright year) to Misc & System About section
- Add inline changelog viewer to Misc & System screen
- File extension sorting (A-Z / Z-A) in tracks sort dialog
- Fix NULL-deref crash when enabling LPF, HPF, biquad, or shelf filters
- Add cached online streams view with playlist playback
- Convolver, DDC, and crossfeed expanders now auto-expand and persist state
- Cache network streams to disk for reliable online playback; cap Up Next to 20 tracks
- Remove genre tab and grouping from Library screen
- Set Shapes.slanted as default album art shape, applied to mini player
- Optimize queue scroll performance and tune dismissible gestures
- Fix intermittent crash and assertion abort on track skip / jump
- Fix RenderFlex overflow in EQ and ViPER FX tabs using sliver layout
- Switch bottom navigation to M3ENavigationBar components

## v0.6.10 — 2026-08

- Add active hardware output device and route info to audio engine diagnostic panel
- Sync wavy/linear slider style with mini-player progress bar
- Adapt Material 3 Expressive card lists to Look & Feel themes
- Upgrade SautiPlay UI to Material 3 Expressive (M3E) component system
- Add M3E slider style selector; refine seekbar touch sensitivity; remove bubble
- Optimize queue and library list rendering; throttle album art extraction workers
- Redesign Visualizer subscreen with M3E components and live spectrum preview
- Fix missing Material ancestor for dialogs and profile controls

## v0.6.0 — 2026-08

- Implement reactive Material 3 Expressive theme adaptation across SautiPlay
- Refactor Settings and ViPER FX sub-screens to M3E components
- Redesign Equalizer and DSP screen with M3E vertical sliders
- Redesign Home, Search, and Online Playlist screens with M3E
- Integrate M3E components across Library, Song Info dialogs, and card lists

## v0.5.5 — 2026-07

- Fix native crash during rapid track skipping
- Add True-Peak limiter and BS.1770-4 LUFS loudness normalizer (Release 1 Quality Foundation)
- Add Polarity Inversion, L/R Swap, and Per-Channel Gain in DSP engine and settings
- Add Loudness-Aware Crossfade
- Fix live audio settings update without playback interruption
- Add Plugin Delay Compensation and per-node latency telemetry
- Add developer audio engine diagnostic panel

## v0.5.0 — 2026-07

- Fix push-stream startup, drain garbage queue, and align S24 buffer layout
- Fix libsamplerate and libsoxr pitch, tempo, and artifact issues
- Fix crash when disabling Auto Sample-Rate Match during active playback
- Final cleanup of 3-rate architecture and allocation-free audio callback
- Implement modular sample-rate-aware Crossfeed DSP node
- Fix A-B repeat loop timing, buffer flushing, and position tracking
- Implement separated sample-rate architecture and Auto Sample-Rate Match
- Integrate libsoxr resampler engine with selectable quality options
- Reset frame position counters on crossfade track transition
- Resolve resampler VTable latency frame dropouts; add quality tier UI

## v0.4.0 — 2026-06

- Add 7 GLSL 3D fragment shader visualizers and 2 canvas visualizers
- Fix Auto Bit-Perfect DAC rate switching crash and audio freeze
- Deduplicate music tracks by fast file-content hash and folder subsumption
- Add swipe left/right gesture controls to mini player
- Hybrid engine architecture: fast seeking, sample-rate pitch fix, WASAPI exclusive stability
- Worker-driven SPSC ring buffer, garbage collector queue, and lock-free parameters
- Enhance Auto Bit-Perfect with exclusive MMAP and low-latency profile
- Add toast notifications for Bit-Perfect mode accept / reject

## v0.3.0 — 2026-05

- Add Auto Bit-Perfect hardware rate matching and 64-bit float DSP math
- Fix resampler bugs, real-time audio allocation, and LibSampleRate vtable gaps
- Expose miniaudio filters via FFI and integrate real-time filter graphs
- Expand output channel UI to 1-8 channels (surround support)
- Add 3D audio spatialization: sound cones, attenuation, and listener controls
- Add MulticastLock, Wi-Fi permissions, and iOS local network entitlements for DLNA discovery
- Fix dithering processor: correct F32 bypass bug and full-scale TPDF dither
- Expose Ambiophonics R.A.C.E. parameters with soundstage visualizer UI
