# User-Configurable Fixed Output Buffers (`audio_engine.cpp`)

Feasibility write-up only — **no code has been edited yet**.

---

## 1. What "fixed buffers" means here

The user sets the audio device's buffering granularity before/after engine creation:

| Setting | Meaning | miniaudio field |
|---|---|---|
| Period size | Frames per hardware callback block (or ms) | `cfg.periodSizeInFrames` / `cfg.periodSizeInMilliseconds` |
| Period count | Number of such blocks queued (total latency = size × count) | `cfg.periods` |
| Mode | `0` = engine auto-selects (current behavior), `1` = user fixed values | new engine flag |

Total output latency ≈ `periodSize × periods / sampleRate`. Lower = snappier UI/seek but higher underrun risk; higher = stable on weak hardware/network streams.

## 2. Current state of the engine

Buffer sizing today is hardcoded and scattered across **three** `ma_device_init` call sites:

1. **`ae_create_engine`** — `audio_engine.cpp:4851`
   No period settings at all → miniaudio defaults (`periodSizeInMilliseconds = 0`, `periods = 0` → backend default ~10ms×2..3).

2. **`restart_and_apply_config`** — `audio_engine.cpp:6610–6701`
   - Sinc-resampler case: `periodSizeInMilliseconds = 50; cfg.periods = 3` (line 6639)
   - Exclusive mode: `periodSizeInMilliseconds = 25; cfg.periods = 4`, low-latency profile (line 6653)
   - Shared fallback + **failsafe baseline config** (`safeCfg`, line 6688): nothing set.

So there are already *implicit* buffer policies, but no user control, and they're inconsistent between create and restart paths.

## 3. Why this is highly feasible

The hard part of changing live device parameters is already solved in this codebase:

- ✅ **Device hot-restart plumbing exists.** `restart_and_apply_config()` (line 6538) already tears down/re-inits the device while preserving decoder position, crossfade state, rate plan, EQ/FX filters, pitch resampler, and absolute-time scaling. Buffer changes can ride exactly this path — same as `ae_set_exclusive_mode`, `ae_set_output_format`, etc. (lines 7009–7139 all just call it).
- ✅ **Pattern to copy exists.** The `exclusiveModeEnabled` atomic + setter + getter + restart-trigger trio is a template we replicate verbatim.
- ✅ **Hardware info reporting exists** (`ae_get_hardware_info` returns actual `period_size_frames` / `period_count`, line ~8817), so users get feedback on what was actually negotiated.

Estimated effort: **~150–250 lines total** across C++ header/source, plus optional Dart FFI bindings. Risk: **low-medium** (device reinit path is well-trodden).

## 4. Proposed implementation

### 4.1 Engine struct additions (near line 2570)

```cpp
std::atomic<int> userPeriodFrames{0};    // 0 = auto
std::atomic<int> userPeriodCount{0};     // 0 = auto
```

### 4.2 Public C API (audio_engine.h)

```c
/* Set fixed device buffering. frames=0 or count=0 => engine auto-selects.
 * Valid ranges: frames [16, 16384], count [2, 16].
 * Takes effect immediately via device restart (brief gap, position preserved). */
AE_API void ae_set_output_buffer(AudioEngineHandle *engine,
                                 int period_frames, int period_count);
AE_API void ae_get_output_buffer(AudioEngineHandle *engine,
                                 int *out_period_frames, int *out_period_count);
```

(Optionally an ms-based variant `ae_set_output_buffer_ms(int ms)` that converts using current sample rate.)

### 4.3 A single helper to apply policy at every init site

```cpp
static void apply_buffer_policy(AudioEngineHandle *e, ma_device_config &cfg)
{
    const int f = e->userPeriodFrames.load(std::memory_order_relaxed);
    const int c = e->userPeriodCount.load(std::memory_order_relaxed);
    if (f > 0) { cfg.periodSizeInFrames = (ma_uint32)f; }
    if (c > 0) { cfg.periods = (ma_uint32)c; }
}
```

Call it in:
- `ae_create_engine` (after line 4856)
- `restart_and_apply_config` main cfg build (after line 6633)
- **Not** in the failsafe `safeCfg` — keep that one pristine so it always succeeds.

### 4.4 Setter implementation (copy of `ae_set_exclusive_mode` pattern, ~line 7009)

```cpp
AE_API void ae_set_output_buffer(AudioEngineHandle *e, int frames, int count)
{
    if (!e) return;
    e->userPeriodFrames.store(clamp(frames, 0, 16384), std::memory_order_relaxed);
    e->userPeriodCount.store(clamp(count, 0, 16), std::memory_order_relaxed);
    restart_and_apply_config(e);   // same trigger used by format/rate/exclusive setters
}
```

### 4.5 Interaction with existing policies

Current implicit policies should become **defaults when user hasn't set anything** (frames==0):

- Exclusive mode keeps its 25 ms × 4 low-latency profile unless overridden.
- Sinc-resampler 50 ms × 3 stays as-is unless overridden.
- Document precedence: `user explicit > exclusive-mode profile > resampler heuristic > miniaudio default`.

### 4.6 Dart side (optional but recommended)

Add to `lib/audio_engine_ffi.dart`: two `NativeFunction` lookups + wrapper methods mirroring `setExclusiveMode`, then surface on `MiniAudioPlayer`.

## 5. Platform caveats (these are hints, not guarantees)

| Backend | Behavior |
|---|---|
| **WASAPI shared** (Windows) | miniaudio converts internally; requested periods honored approximately. IAudioClient3 fixed-period possible but not via simple config. |
| **WASAPI exclusive** | Honored closely; too-small values will fail init → falls back to shared (already handled by existing fallback chain). Good. |
| **AAudio/OpenSL** (Android) | Respects frames reasonably; OpenSL rounds to supported sizes. |
| **CoreAudio** (iOS/macOS) | iOS typically forces its own IO buffer (256/512/… frames); treat request as upper bound hint. |
| **ALSA/Pulse** (Linux) | Honored as min/max hints; Pulse may ignore entirely. |

Because `ma_device_init` failure paths already exist at all three sites, "hardware declined my buffer" degrades gracefully with zero extra code.

## 6. Edge cases to handle during implementation

1. **Validation**: reject `count < 2` (miniaudio requires ≥ 2 periods); clamp rather than error for out-of-range frames.
2. **Setting while stopped/paused**: works fine — setter just stores values; next init picks them up. Consider skipping restart when `!isPlaying`.
3. **Race with `rateTransitionInProgress`**: guard setter with the same check other setters use (see Issues_bugs.md §4.5 note about unlocked stops).
4. **Telemetry**: after restart, log actual negotiated `device.playback.internalPeriodSizeInFrames` so users see what they really got.
5. **Underrun counter** (`underrun_count` in `AEQualityTelemetry`) already exists — recommend exposing it alongside so users can tune their value empirically.

## 7. Verdict

**Very feasible (~90% confidence, low risk).** All machinery — device restart, fallback chains, telemetry, FFI pattern — already exists. Work is essentially: 2 atomics + 1 helper + 4 API functions + calling the helper in 2 places, then wiring Dart bindings. The only genuinely uncertain part is how much each OS backend respects the requested values, which is inherent to the feature, not to this codebase.
