# Sautiflow Audio Engine — Audiophile-Grade Audit

**Scope:** `audio_engine.cpp` (12,304 lines), `audio_engine.h`, `dsp/*.h`, `crossfeed_node.h`, `reverb_node.h`
**Method:** static source audit (render-thread path, DSP math, SRC, output backend, RT-safety, test coverage)
**Verdict:** **B− / "audiophile-adjacent", not confidently audiophile-grade.** The architecture is ambitious and several subsystems are genuinely high quality, but there are multiple correctness and real-time defects — including one headline feature that is dead code — that prevent calling this transparent/reference grade today.

---

## 1. Signal path (as implemented)

```
source file/URL
  -> ma_decoder (FFmpeg/AAC custom) -> f32 @ engineRate  [decoder SRC: SoXR/r8brain/SRC]
  -> lock-free SPSC pcmRingBuffer  (192000 samples)
  -> producer thread (decode_producer_loop): rate/pitch (ScaleTempo + ma_resampler)
  === data_callback (realtime) ===
     pre-gain (ReplayGain + loudness normalizer)
     [bypassAppDsp? exclusive && !auto-match]
       fade -> subsonic HPF -> crossfeed/widen/enhance/crystalizer/reverb
       -> multiband EQ/FX -> 3-band EQ -> native DSP suite -> compressor
     loudness meter / true-peak meter / analyzer
     master user gain -> lookahead limiter or brickwall limiter
     pan / L-R trim / polarity / L-R swap
     engine->device SRC -> dither -> format convert -> DAC
```

Internal processing is float32 by default; a float64 path exists for a *subset* of stages (`use64`). The engine rate equals the device rate in shared mode, so the device SRC is usually bypassed — good.

---

## 2. What is genuinely good (credit where due)

| Area | Assessment | Evidence |
|---|---|---|
| Dattorro figure-8 reverb | Legit modern design: pre-delay, dual diffusers, modulated allpasses, damping, quadrature LFO, 14 prime taps. Better than Freeverb. | `reverb_node.h:162-347` |
| Crossfeed | Real BS2B/Meier/Natural-SVF/RACE implementations with ITD + head-shadow, group-delay compensation, output compensation. | `crossfeed_node.h:176-411` |
| BS.1770-4 loudness | Correct K-weighting coefficients, gated momentary/short-term/integrated + LRA, channel weights. | `audio_engine.cpp:1851-2040` |
| True-peak meter | 4-phase × 12-tap polyphase interpolation, honest sample-peak reporting instead of fabricated values. | `audio_engine.cpp:1686-1759` |
| Dither | RPDF/TPDF + 6 noise-shaping curves, **per-channel PRNG** (avoids mono-correlated dither), anti-windup on clamp. | `audio_engine.cpp:2894-3057` |
| SRC backends | SoXR VHQ linear/min-phase, r8brain 24-bit, libsamplerate sinc; default is SoXR VHQ min-phase. | `audio_engine.cpp:617-1345`, `3562` |
| Decode off RT thread | Codec decode + crossfade old-track decode are on producer threads; SPSC ring, no allocation in steady-state callback. | `audio_engine.cpp:3389-3431`, `5590-5707` |
| Denormals | RAII FTZ/DAZ on x86 and ARM (AArch64/ARMv7) wraps the whole callback. | `dsp/denormals.h:27-107` |
| Exclusive/auto-rate | WASAPI exclusive with `noAutoConvertSRC`, ALSA no-MMap off, Android AAudio/direct AudioTrack fallback. | `audio_engine.cpp:8982-9039` |
| Diagnostics | Hardware info, resampling policy, latency/underrun/clip telemetry. | `audio_engine.cpp:12249-12302` |

---

## 3. Critical findings

### C1 — DSP oversampling API is dead code (feature does not work)
`dspOversamplingFactor` is stored (`audio_engine.cpp:3331`, `9611-9623`) and read back by getters, but it is **never read anywhere in the render path**. A grep shows only the setter/getter touch it. Users selecting "2x/4x Remez oversampling" in Settings get **no change in output**. This directly contradicts the v0.6.27 changelog and site claims. This is the single most damaging finding for an "audiophile" product.

### C2 — The oversampler's own kernel is ~33 dB, not the advertised >85 dB
`oversampler.h:13` claims ">85 dB stopband attenuation", but the actual Remez coefficients are documented at line 138 as "**>33 dB stopband attenuation**". This same half-band kernel is used to oversample every non-linear stage (analog warmth, clarity harmonic brilliance, dynamic bass/system). 33 dB image rejection is insufficient to suppress aliasing from `tanh`/soft-clip distortion, so the "anti-aliased saturation" is largely cosmetic. Fix the coefficients (or increase taps) or the aliasing persists.

### C3 — Base-rate soft-clipping of full-band audio (aliasing)
`dynamic_bass_dsp.h` (clips at `:540-541, 559-560, 834-835, 859-860`) and `dynamic_system_dsp.h` (`:232-233`) apply full-band `softClip` at the native rate with no oversampling. Any clipped HF content folds back into the audible band. `crossfeed_node.h:385-396` likewise hard-saturates RACE at base rate (less severe, only at >0.98).

### C4 — Constructor initialization bug across native DSP classes
Each class has:
```cpp
BaseClass() { setSampleRate(48000.0f); reset(); }
void setSampleRate(float sr) { if (fabs(sample_rate_ - sr) < 0.1f) return; ... updateFilters(); }
```
Since `sample_rate_` already defaults to 48000, the call **early-returns and never runs `updateFilters()` / coefficient init**. Consequences:
- `clarity_dsp.h:30-39` — Harmonic Brilliance HPF is passthrough, `sidechain_buf_` empty.
- `de_esser_dsp.h:43-52` — **sidechain is identity (no 4–9 kHz sibilance HPF) and ballistics are wrong** until the first real rate change.
- `dynamic_system_dsp.h:87`, `analog_warmth_dsp.h:30` — preset/tape-damping coefficients never computed.

For any engine instance that runs at 48 kHz (the common case), these DSP blocks are **silently mis-initialized for their entire lifetime**.

### C5 — Real-time unsafe blocking locks in the audio callback
The callback takes **blocking** `std::lock_guard` on `fxMutex` (`:5747`) and `eqMutex` (`:5887`). On the control side, `applyRatePlan()` holds `fxMutex` while doing `reverbNode.setSampleRate()` (which calls `buildBuffers()` → many `std::vector` allocations), `eq.updateCoefficients`, and filter rebuilds (`:4083-4094`). If a rate/device transition coincides with a callback, the realtime thread can block for milliseconds → dropout. Priority inversion. Only `dspMutex` correctly uses `try_lock` (`:5925`). This is the classic "audio glitch on settings change" bug.

### C6 — Exclusive "bit-perfect" mode is not bit-perfect
`bypassAppDsp` (`:5806`) skips most DSP, but:
- Stage 1 (`:5757-5804`) applies **ReplayGain and the loudness normalizer before the bypass check**, so they always run.
- Stage 3 user gain (`:5996-6018`) always runs.
- The decoder always converts to **float32** at `engineRate` (`load_decoder_for_path`, `:4283`), so integer PCM is float-converted and back — not a bit-exact path.
So "bit-perfect" means "bypasses app effects if gain/RG are unity", not literally bit-perfect. The marketing site's "Bit-perfect / WASAPI exclusive" claim overstates it.

---

## 4. High-severity findings

### H1 — `subsonic_filter.h` silently ignores channels ≥ 3
Both the `channels >= 2` float and double branches filter only `idx+0`/`idx+1` (`:85-105, 123-143`). Center/surround/LFE pass unfiltered. Mono uses only one shared state.

### H2 — Loudness meter allocates in the callback
`BS1770LoudnessMeter::process` does `accumulatedBlocks.push_back` (`:2023`) on the RT thread. `std::deque` growth allocates. It is opt-in, but when enabled it violates RT-safety.

### H3 — `clarity_dsp.h` allocates in `process()`
`sidechain_buf_.resize(frame_count*2)` at `:273-275` and the oversampler's `upsample` can resize (`oversampler.h:192`) for blocks > 4096 frames. Audio-thread heap allocation.

### H4 — Per-sample coefficient re-solves and hard-knee/instant-attack envelopes
- `de_esser_dsp.h:275, 391-419`: `updateShelfCoeffs()` runs `pow/sin/cos/sqrt` whenever GR moves, while `current_gr_db_` is instantaneous and the gain computer is **hard-knee** despite the "soft-knee" doc. Time-varying IIR modulated in place → clicks/instability.
- `dialog_enhancer_dsp.h:164-167`: `recalcBiquads()` called inside the sample loop (trig per sample).
- `dialog_enhancer_dsp.h:304-316`: three peaking filters sum to ~+19.5 dB with no trim/limiter.

### H5 — ScaleTempo quality issues (off-RT thread, so not a glitch risk)
Verified it runs in `decode_producer_loop` (`:5038-5356`), not the callback — so its heap churn is not a real-time hazard. However the correlation metric (`scaletempo_dsp.h:359-371`) is not mean-removed or window-energy-normalized, biasing the search toward loud candidates → lower-quality time-stretch.

### H6 — Dynamic-bass harmonic envelope ballistics are sample-rate dependent
`dynamic_bass_dsp.h:706-708` hard-codes `0.01/0.0001`, so attack/release are wrong at any rate other than ~48 kHz.

---

## 5. Medium / low findings

- **`AEResamplingPolicyInfo` reporting bugs:** `filter_passband_ratio = 0.45 * device_sample_rate` (`:12272`) is in Hz, not a ratio; `mode` only distinguishes bypass/auto and hard-codes "3" for everything non-auto, never reporting SoXR/r8brain specifically.
- **S24 output path mismatch:** in `restart_and_apply_config` S24 maps to `ma_format_s32` (`:8904`), so the callback's `pDevice->playback.format == ma_format_s24` branch is dead and dither is computed at 24-bit LSB while conversion scales to s32. Not harmful, but the bit-depth story is muddled.
- **Network streams use FFmpeg `SwrContext`** (`:4285-4296`) while local files use SoXR/r8brain — inconsistent fidelity for the same app.
- **Initial `ae_create_engine` forces `ma_format_f32`** (`:6980`); requested `outputFormat`/bit-depth only takes effect after a restart. The "hardware bit-depth match" is not applied at first launch.
- **`AETrackInfo.is_float` / `bit_depth`** are decoder-reported; not validated against actual PCM.
- **`getLatencySamples` in reverb/crossfeed** uses target not smoothed value; latency compensation is approximate.
- **`info.mode`** never reports `2=IntegerPolyphase`/`4=SoxrVHQ` as its comment promises (`audio_engine.h:386`).
- **`resampleAlgorithm` is a non-atomic `int`** written by `ae_set_engine_resample_algorithm` (`:9574`) while potentially read in `applyRatePlan` on a restart path — minor data race.

---

## 6. Real-time safety scorecard

| Concern | Status |
|---|---|
| Heap alloc in callback steady-state | Mostly avoided via prealloc (262144 floats), **but** `clarity_dsp` sidechain resize and loudness-meter deque remain |
| Blocking locks in callback | **Fail** — `fxMutex`, `eqMutex` blocking (`:5747, 5887`) |
| Denormals | Pass (RAII FTZ/DAZ) |
| Decode on audio thread | Pass (producer thread + SPSC ring) |
| Atomics / torn state | Mostly pass; `resampleAlgorithm` non-atomic |
| Exception handling | Wrapped in `try/catch` that zeroes device buffer (`:6278`) — masks bugs but prevents catastrophe |
| Priority inversion | Present via blocking mutexes held by control thread doing allocations |

---

## 7. Test coverage assessment

There is substantial test surface (`tests/*.cpp`, `test/*.dart`: rate matrix, dither, 64-bit, DSP smoothness, crossfeed, reverb, phase, normalizer). Weaknesses:

- **The oversampling test only checks the getter** (`tests/test_engine_api.cpp:117-129`) — it never verifies that audio is actually oversampled. This is exactly why C1 went unnoticed.
- No objective **THD+N / IMD / aliasing** measurement tests for the saturation stages.
- No null-test (bit-exactness) test for the bit-perfect/exclusive path.
- No RT-sanitizer / allocation-tracking test for the callback.
- No frequency-response validation of the half-band kernel against its documented spec.

---

## 8. Prioritized remediation

**P0 — correctness of advertised features**
1. Wire `dspOversamplingFactor` into the render path (or remove the API and all UI/marketing references). (C1)
2. Fix or retune the half-band coefficients to a true >90 dB stopband, or drop the "anti-aliased" claim. (C2)
3. Fix the `setSampleRate` early-return in every DSP class (add an explicit `init(sr)` or a `initialized_` flag). (C4)
4. Move ReplayGain/normalizer/user-gain under an explicit "processing" gate so exclusive mode is actually transparent when configured. (C6)

**P1 — real-time integrity**
5. Replace blocking `fxMutex`/`eqMutex` acquires in the callback with `try_lock` + block-bypass (as `dspMutex` already does), and make control-thread reconfigs lock-free/double-buffered. (C5)
6. Preallocate `sidechain_buf_`; replace loudness-meter `deque` with a fixed ring. (H2/H3)
7. Oversample all base-rate non-linear stages or gate them off. (C3)

**P2 — DSP quality**
8. De-esser: dB-domain soft knee, smoothed attack, coefficient update once per block not per sample. (H4)
9. Dialog enhancer: cap cascade gain, move recalc out of the sample loop.
10. Fixed low-order ringing/aliasing fixes and sample-rate-correct ballistics in dynamic bass (H6).
11. Fix `subsonic_filter` multi-channel handling (H1) and correct `AEResamplingPolicyInfo` reporting.

**P3 — verification**
12. Add null/bit-exact, THD+N/aliasing, and callback-allocation tests; make oversampling test assert on audio, not just the setter.

---

## 9. Grade

| Dimension | Grade | Notes |
|---|---|---|
| Architecture / signal flow | B+ | Clean separation, good SRC choices, decode off RT thread |
| DSP algorithm quality | B− | Excellent reverb/crossfeed/loudness; weak saturation & dynamics |
| Real-time safety | C+ | Denormals/SPSC good; blocking locks + allocations fail |
| Bit-perfect / hi-res claims | C | Overstated; not bit-exact, float round-trip |
| Feature completeness | D | Oversampling API is non-functional; several mislabeled modes |
| Verification | C+ | Broad but misses the exact defects that matter |
| **Overall** | **B−** | **Audiophile-adjacent, not reference-grade as shipped** |

**Bottom line:** This is a well-engineered *consumer/hi-fi* engine with real audiophile DNA in its reverb, crossfeed, loudness metering, dither, and resampler selection. It is **not yet audiophile-grade** because a headline feature (oversampling) is dead, the anti-aliasing story on all non-linear stages is false due to a ~33 dB kernel, several DSP blocks are mis-initialized at 48 kHz, and the render thread takes blocking locks during reconfigurations. Fixing P0+P1 alone would move this to a credible **A−**; the DSP quality work (P2) would make the "audiophile-grade" claim defensible.
