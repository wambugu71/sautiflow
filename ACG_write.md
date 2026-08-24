# AGC / AEC Feasibility & Implementation Plan for `audio_engine.cpp`

> Note: "ACG" interpreted as **AGC** (Automatic Gain Control). AEC = Acoustic Echo Cancellation.

---

## 1. Verdict at a Glance

| Feature | Feasibility | Effort | Risk |
|---|---|---|---|
| **AGC (playback path)** | ✅ Highly feasible | Low–Medium (~250–400 LOC C++) | Low — fits existing DSP chain patterns |
| **AGC (capture/mic path)** | ⚠️ Possible but new subsystem | Medium–High | Medium — engine has no capture device today |
| **AEC** | ❌ Not feasible as pure playback feature | High | High — requires mic capture + duplex routing or OS/platform APIs |

---

## 2. Relevant Facts About the Current Engine

- The engine is **playback-only**. Both device configs use `ma_device_type_playback`
  (audio_engine.cpp:4851, 6610, 6688) with `cfg.dataCallback = data_callback`.
  There is **no microphone/capture path anywhere** in `AudioEngineHandle`
  (audio_engine.cpp:2566–2811).
- `data_callback` (audio_engine.cpp:4317) runs a linear DSP chain under `fxMutex`:
  volume → per-channel gains → fades → pan → crossfeed → stereo widen/enhancement
  → crystalizer → multiband EQ/FX → 3-band EQ → Clean-Room DSP suite →
  limiter → meters (audio_engine.cpp:4497–4715).
- The engine **already has ~80% of an AGC**: `BS1770LoudnessMeter::getNormalizerGainLinear()`
  (audio_engine.cpp:1486–1495) computes a target-LUFS gain, exposed via
  `ae_set_loudness_normalizer_enabled/target`. However it is *coarse* — it uses the
  slow **integrated** LUFS (whole-program), so it reacts over many seconds and is not
  a true real-time AGC (no attack/release envelope riding).
- Existing conventions to follow for any new stage:
  - `std::atomic<bool>` enable flag on the handle (e.g. `lookaheadLimiterEnabled`, audio_engine.cpp:2722)
  - State struct guarded by a mutex, setters mutate config on control thread,
    realtime callback reads under lock or try-lock (pattern of `dspMutex`,
    audio_engine.cpp:4665)
  - Bypass when `bypassAppDsp` is set (exclusive mode without auto-rate-match,
    audio_engine.cpp:4499)
  - Clamped setter + getter pairs in the public C API (audio_engine.h)

---

## 3. AGC (Playback Path) — Recommended Implementation

### What it does
Continuously rides the output gain so short-term loudness converges to a
user-set target LUFS, with bounded max gain boost/attenuation and smooth
attack/release so it never pumps or clicks.

### 3.1 New state struct (place near `LookAheadLimiterState`)

```cpp
struct AgcState
{
    // Config (mutated by setters under agcMutex)
    float targetLufs      = -16.0f;
    float maxGainDb       = 12.0f;   // max boost
    float maxAttenuationDb= -24.0f;  // max cut
    float attackMs        = 250.0f;  // gain-up speed (slow = transparent)
    float releaseMs       = 1000.0f; // gain-down speed
    bool  enabled         = false;

    // Runtime (realtime thread only)
    float currentGainLin  = 1.0f;
    float smoothedLufs    = -70.0f;

    void process(float* samples, ma_uint32 frames, int channels, int sampleRate);
    void reset();
};
```

### 3.2 Algorithm (clean-room, no new dependencies)

1. Per block, compute short-term RMS/LUFS-style loudness of the input block
   (reuse the K-weighting biquads already present in `BS1770LoudnessMeter`, or
   simple RMS for a lighter variant).
2. Smooth measured loudness one-pole: `smoothed += k * (measured - smoothed)`
   where `k` derives from release time.
3. Desired gain dB = `clamp(target - smoothed, maxAttenuationDb, maxGainDb)`.
4. Convert to linear, slew-limit toward desired gain using attack/release
   coefficients per-sample (or per-block with per-sample interpolation to avoid
   zipper noise — mirror the `AutomatedParamFloat` smoothing pattern,
   audio_engine.cpp:1498).
5. Multiply block by current gain. Gate: if loudness < −70 LUFS (silence),
   freeze gain instead of boosting noise.

### 3.3 Insertion point in `data_callback`

Immediately **before** the limiter stages and after the Clean-Room DSP suite
(audio_engine.cpp:4677), inside the `!bypassAppDsp` block:

```cpp
// AGC (loudness-following automatic gain)
if (e->agcEnabled.load(std::memory_order_relaxed))
{
    std::lock_guard<std::mutex> agcLock(e->agcMutex);
    e->agc.process(processBuffer, produced, e->channels, e->engineSampleRate);
}
```

Ordering rationale: AGC must see post-EQ/DSP loudness, but the lookahead
limiter must run *after* AGC so any AGC overshoot gets caught. Meters stay last.

### 3.4 Public API additions (`audio_engine.h`, matching existing style)

```c
AE_API void ae_set_agc_enabled(AudioEngineHandle *engine, int enabled);
AE_API int  ae_get_agc_enabled(AudioEngineHandle *engine);
AE_API void ae_set_agc_params(AudioEngineHandle *engine,
                              float target_lufs,        // [-30, -6]
                              float max_gain_db,        // [0, 24]
                              float attack_ms,          // [10, 5000]
                              float release_ms);        // [50, 10000]
AE_API float ae_get_agc_current_gain_db(AudioEngineHandle *engine); // telemetry
```

Also add `int agc_enabled;` to `AEPipelineState` (audio_engine.h:86) alongside
the other effect flags.

### 3.5 Dart/FFI side (`lib/audio_engine_ffi.dart`)

Add `lookupFunction` bindings for the four functions plus a wrapper class
(`AgcParams`) following the existing pattern used by the lookahead-limiter
bindings.

### 3.6 Interaction notes

- **Mutual exclusion with loudness normalizer:** if both run they fight
  (double compensation). Either document AGC as superseding the normalizer, or
  make `ae_set_agc_enabled(1)` implicitly disable the normalizer.
- **Crossfade replay-gain:** AGC sits downstream of crossfade mixing, so it will
  also level-match the two tracks during a fade — actually desirable.
- **Exclusive mode:** AGC is skipped in bit-perfect exclusive mode via existing
  `bypassAppDsp` gate — correct behavior, keep it.

### 3.7 Testing

Add `test/test_agc.cpp` mirroring `test/test_crossfeed.cpp`: feed pink-noise
blocks at −30 and −10 LUFS, assert output short-term loudness converges within
±2 LU of target and that gain slew stays below click threshold.

---

## 4. AGC (Capture/Mic Path) — Only If Voice Features Are Planned

Not possible today: there is no capture device. Would require:

1. Switching miniaudio config to `ma_device_type_duplex` (or adding a second
   capture device) — touches `restart_and_apply_config` and every device-open
   site (audio_engine.cpp:4855, 6631, 6692).
2. A capture ring buffer + new callback mirroring `data_callback`.
3. Then AGC itself is easy (SpeexDSP preprocessor or same clean-room code).

**Recommendation:** defer until a recording/VoIP feature actually exists.

---

## 5. AEC — Feasibility Analysis

AEC removes *your own playback* from the *microphone signal*. It fundamentally
requires both a far-end reference (what we play) and a near-end capture (mic).
This engine has neither a capture path nor any concept of a communication
session, so AEC cannot be "a toggle on the playback chain."

### Option comparison

| Option | Description | Effort | Notes |
|---|---|---|---|
| **A. OS-level AEC** (recommended) | Windows: open mic via voice-communication endpoint/APO; Android: `AcousticEchoCanceler`; iOS: `.voiceChat` AVAudioSession mode | Low | Zero DSP work, best quality, done at platform layer (Dart/Kotlin/Swift), not in audio_engine.cpp |
| **B. SpeexDSP vendoring** | Vendor speexdsp (like libsamplerate/libsoxr in third_party/), add duplex device, route far-end ref into `speex_echo_state`, run preprocessor AGC+NS+VAD | High (~1500+ LOC + build changes ×4 platforms) | Real software AEC; small C dep, permissive BSD |
| **C. WebRTC AudioProcessing Module** | Full APM (AEC3, NS, AGC1/2) | Very High | Heavy dependency, complex build on all targets |
| **D. Clean-room AEC** | Own NLMS/adaptive filter + delay estimator | Not realistic | Echo cancellation research-grade; do not attempt |

### If Option B were chosen, the shape would be

1. Add `AE_ENABLE_SPEEXDSP` compile flag + vendored sources.
2. New `ae_init_communication_mode(engine)` that reopens the device as duplex.
3. Playback callback pushes far-end frames into `speex_echo_play()`;
   capture callback runs `speex_echo_cancellation()` + AGC, exposing a new
   `ae_read_processed_capture(...)` API.
4. Latency alignment between playback and capture becomes the hard part
   (needs the hardware latency data already collected in `AEHardwareInfo`).

---

## 6. Recommended Path Forward

1. **Ship playback AGC now** (Section 3) — small, safe, user-facing value,
   reuses existing loudness infrastructure and code conventions.
2. **For echo-free voice calls, use Option A** (OS-level AEC) at the app layer —
   it's what every major app does and requires no changes here.
3. Revisit software AEC (Option B/C) only if you later need custom capture
   processing inside this native engine.

### Suggested commit sequence for AGC

1. `audio_engine.h`: API decls + `agc_enabled` in `AEPipelineState`.
2. `audio_engine.cpp`: `AgcState` struct + `process()`; member fields on handle
   (`agcEnabled`, `agcMutex`, `agc`); insertion in `data_callback`; setters/getters.
3. `lib/audio_engine_ffi.dart`: bindings + high-level wrapper.
4. `test/test_agc.cpp`: convergence + click-safety tests.
5. Rebuild DLLs (`tool/build_windows.ps1`, android/apple/linux scripts).
