# Issues & Bugs — audio_engine / DSP Audit

Audit scope: `audio_engine.cpp`, `audio_engine.h`, `crossfeed_node.h`, `dsp/*.h`
Date: 2026-08-23
Severity legend: **[C]** Critical · **[H]** High · **[M]** Medium · **[L]** Low / hygiene

---

## 1. Critical Bugs

### [C] 1.1 Guaranteed deadlock on Auto-Sample-Rate-Match track switch
- **Where:** `audio_engine.cpp:3475` → `:3517` → `:6329` (also `:6488`, `:6510`)
- **What:** `worker_loop()` acquires `decoderMutex` at line 3475 and, while still holding it, calls
  `restart_and_apply_config(e)` (line 3517). That function locks `decoderMutex` again at lines
  6329/6488/6510. `std::mutex` is non-recursive → **instant self-deadlock**.
- **Trigger:** Worker jump (`ae_next` / `ae_jump_to` for network URLs, or any worker-driven jump) where
  Auto SR Match is enabled and the new track's native rate ≠ current DAC rate.
- **Note:** `execute_jump_direct()` calls `restart_and_apply_config()` *before* its locked section
  (line 5259) and is safe — only the `worker_loop` path is broken.

### [C] 1.2 Buffer overrun in `data_callback` exception handler
- **Where:** `audio_engine.cpp:4589`
```cpp
catch (...) { std::memset(pOutput, 0, frameCount * e->channels * sizeof(float)); }
```
- **What:** When the negotiated device format is S16/U8/S24, `pOutput` only holds
  `frameCount × channels × bytes_per_sample`. This memset always writes 4 bytes/frame → writes up to
  **2–4× past the end** of the device buffer.
- **Trigger:** Any exception inside `data_callback` while the device runs a non-F32 format.
  Heap corruption. All other memset sites correctly use `ma_get_bytes_per_frame`.

### [C] 1.3 Data race: `dspMutex` never acquired by the realtime thread
- **Where:** Setters `audio_engine.cpp:7947–8075`; RT processing `audio_engine.cpp:4459–4464`
- **What:** All `ae_dsp_set_*` setters mutate the clean-room DSP objects under `dspMutex`, but
  `data_callback` processes those same objects under `fxMutex` only — it never takes `dspMutex`.
  `setProfile/setIntensity/setDrive/setBoost/updateFilters()` therefore rewrite filter coefficients
  and state concurrently with the audio thread reading them → torn floats/doubles, zipper noise,
  potential crashes.
- **Reference implementation:** `FFTConvolverDSP` handles this correctly (RT side uses
  `try_to_lock`, `dsp/fft_convolver_dsp.h:158`). The other five nodes do not.

### [C] 1.4 BS.1770 loudness meter stalls the audio thread — enabled by default
- **Where:** `audio_engine.cpp:2616` (`loudnessMeterEnabled{true}`), gating loop `:1363–1425`
- **What:** Every 100 ms block, `BS1770LoudnessMeter::process` (running **inside** the RT callback):
  - rescans ALL accumulated blocks (up to 108,000) twice for gating,
  - builds a vector and runs `std::sort` over up to ~108k doubles for LRA,
  - periodically `erase()`s 1,000 elements from the **front** of a 108k vector (O(N) memmove).
- **Result:** Multi-millisecond spike every 100 ms → dropouts; worse the longer the session.

### [C] 1.5 Master limiter is always ON and unaccounted
- **Where:** `dsp/master_limiter_dsp.h:128` (`bool enabled_ = true;`), RT call `audio_engine.cpp:4464`
- **What:** The engine never disables it at startup, so every stereo frame passes through a limiter
  with a −0.1 dBFS ceiling + hard clamp:
  - hot masters get gain-reduced without opt-in (colors all playback out of the box),
  - its 1.5 ms lookahead delay (`master_limiter_dsp.h:149`) is **not** included in
    `calculate_total_pipeline_latency_samples` (`audio_engine.cpp:5772`) — nor is the convolver's —
    so position reporting / PDC drifts.

### [C] 1.6 "Pure Bass+" polyphase FIR destroys the signal
- **Where:** `dsp/dynamic_bass_dsp.h:28–38` (coefficients), `:477–478` (replace-not-mix)
- **What:** `processPureBassPlus` **replaces** the output with the FIR result, but the 63-tap table:
  - sums to **0.2027 (≈ −14 dB DC/passband gain)** — verified numerically,
  - is **not symmetric** → nonlinear phase, contradicting the "phase-coherent / phase-aligned" comments.
- **Result:** Mode 1 massively attenuates and phase-shifts the whole track. Either the coefficient
  table is corrupt or the FIR must be mixed with dry, not substituted for it.
- **Also:** inner convolution does `(head + 63 - j) % 63` per tap → 126 modulo ops per frame per channel.

### [C] 1.7 `CrossfeedNode::setAlgorithm` silently fails to switch algorithms
- **Where:** `crossfeed_node.h:28–36` (setter), `:126` (switch condition)
- **What:** The setter only updates `currentAlgorithm` when transitioning from `Off`. At runtime,
  `process()` switches algorithms only if `currentMix < 0.001f`. With any normal mix (e.g. 0.5),
  switching Simple→Meier→BS2B via `ae_set_crossfeed_algorithm` **silently keeps the old algorithm forever**.
- **Aggravated by:** `ae_set_crossfeed_algorithm` also calls `setSampleRate(sameRate)` which early-returns.

### [C] 1.8 Push-stream mode is a one-way trap
- **Where:** `audio_engine.cpp:7279` (set true), never reset except destroy; `:5087–5097` (play branch);
  `:7296–7311` (blocking chunk push)
- **What:**
  - `isPushStreamMode` stays true after the first push-stream session. `ae_play` then short-circuits
    into the push branch and never loads playlist tracks again until the engine is destroyed.
  - `ae_push_stream_chunk` spins in a `sleep_for(2ms)` loop with **no abort flag** — if the consumer
    pauses/stalls, the calling Dart isolate blocks indefinitely.

### [C] 1.9 End-callback fired while holding `decoderMutex`
- **Where:** `audio_engine.cpp:3840–3843` (early-crossfade trigger) and `:4017–4020` (EOF path)
- **What:** `endCallback` is invoked from `decode_producer_loop` while `decoderMutex` is held.
  If the Dart handler re-enters almost any `ae_*` API that locks `decoderMutex`
  (`ae_stop`, `ae_next`, `ae_seek`, …) the same thread deadlocks on itself.
- **Also:** `ae_set_end_callback` (`:6745`) swaps the raw callback/user-data pointers non-atomically
  while the producer thread may be invoking them.

---

## 2. Realtime-Safety / Performance Bottlenecks

### [H] 2.1 Audio thread takes `decoderMutex` during crossfade (priority inversion)
- **Where:** `audio_engine.cpp:4222` (callback) vs `:3729` (producer holding mutex across decode)
- **What:** During crossfade the RT callback locks `decoderMutex` to read the fading-out decoder.
  The decode producer holds that same mutex across `ma_decoder_read_pcm_frames`, whose read
  callbacks block: `stream_on_read` waits on a CV up to **40 ms** (`:204–206`);
  `push_stream_on_read` sleeps 2 ms (`:146`).
- **Result:** Glitches exactly when crossfading network streams.

### [H] 2.2 Decoding runs on the RT thread during crossfade
- **Where:** `audio_engine.cpp:4233`
- **What:** `ma_decoder_read_pcm_frames(fadingOutDecoder, ...)` executes inside `data_callback`,
  including full codec decode and possible blocking network reads.

### [H] 2.3 Coarse locks held across the entire DSP chain
- **Where:** `fxMutex` `:4295`; nested `eqMutex` `:4442`; `deviceResamplerMutex` `:4541`
- **What:** One contended setter (UI slider) blocks the audio thread for the duration of the whole
  chain. Lock order is inconsistent across threads (control paths take `eqMutex` alone or
  `fxMutex` alone; RT nests fx→eq).

### [H] 2.4 Logging from the realtime path
- **Where:** `audio_engine.cpp:660–668` (`src_onProcess`), `:863–871` (`soxr_onProcess`)
- **What:** Every 500th resampler invocation calls `engine_log` → `fprintf` + `fflush` + global
  log mutex on the RT thread → periodic latency spikes.

### [M] 2.5 Default-on meters burn CPU even when no UI polls
- **Where:** `audio_engine.cpp:2610` (`truePeakMeterEnabled{true}`), `:2616` (`loudnessMeterEnabled{true}`)
- **What:** TruePeak does 4 phases × 12 taps × channels MACs per sample (`:1084–1106`);
  BS1770 K-weighting runs double-precision biquads per sample (`:1304–1317`). Constant load
  regardless of whether anyone reads the metrics.

### [M] 2.6 FFTConvolver is 3–4× heavier than needed
- **Where:** `dsp/fft_convolver_dsp.h:348–393`
- **What:** Naive complex radix-2 FFT (no real-FFT packing), strided twiddle indexing (`j*step`),
  and a 16 KB `std::complex<float> temp[1024]` stack array per inverse FFT call.
  ≈262k complex MACs per 512-frame block at max IR length (128 segments).
  Correct, but slow vs. real-signal optimization.

### [M] 2.7 Non-atomic SPSC ring reset while consumer active
- **Where:** `SPSCBuffer::reset` `audio_engine.cpp:2351`; callers `:3982` (A-B loop), `:5195` (seek)
- **What:** Two relaxed stores to write/read indices; the consumer samples `ringBufferFlushing`
  only once per callback → small window reading torn indices → garbage/stale burst.

---

## 3. DSP Correctness Issues

### [H] 3.1 Crystalizer tanh-compresses the entire mix
- **Where:** `audio_engine.cpp:2129` (`x = std::tanh(x)`)
- **What:** Whenever enabled — even at tiny intensity — the full signal goes through `tanh`,
  compressing clean material and adding harmonic distortion. Same pattern in
  `StereoWidenState::process` (`:1780`).

### [M] 3.2 AnalogWarmth Triode creates DC offset
- **Where:** `dsp/analog_warmth_dsp.h:150` (`out += driven*driven*0.08f*current_drive_`)
- **What:** `driven²` is always positive → asymmetric waveshaping injects DC bias with no DC blocker
  downstream → thumps/bass shift at high drive.

### [M] 3.3 Clarity PresenceExciter crossover doesn't sum flat
- **Where:** `dsp/clarity_dsp.h:245–246`
- **What:** LP + BP + HP bands summed directly (bandpass leaves spectral holes), with extra gains up to
  1.8× → magnitude ripple and clip risk. Coefficients are also rewritten from the UI thread while RT
  reads them (ties into bug 1.3).

### [M] 3.4 DynamicSystemDSP ladder filter tuning & alignment
- **Where:** `dsp/dynamic_system_dsp.h:301` (coefficient), `:213`/`:231` (band split)
- **What:** One-pole coefficient `f·π/fs` overestimates the true cutoff (~57% high) vs. the biquads used
  elsewhere in the same product; HP residual uses `in[2]` (3-sample-old input) minus `y[3]` →
  band time misalignment of 3 samples.

### [M] 3.5 Look-ahead limiters detect backwards
- **Where:** `LookAheadLimiterState::process` `audio_engine.cpp:1175–1194`;
  `MasterLimiterDSP::process` `dsp/master_limiter_dsp.h:90–123`
- **What:** Both compute the envelope from the **undelayed** input but apply gain to the **delayed**
  output — gain reduction arrives ~1.5 ms *after* the transient (opposite of look-ahead intent);
  the final hard clamp ends up doing the real work (pumping/distortion).

### [M] 3.6 BS.1770 / telemetry deviations
- **Where:** `audio_engine.cpp:1374–1421` (LRA), `:8836` (sample peak), `:8846` (underruns)
- **What:**
  - LRA gated against integrated −10 LU instead of the short-term loudness distribution (spec deviation).
  - `sample_peak_db` faked as `truepeak − 0.5 dB`.
  - `underrun_count` hardcoded to `0` — telemetry lies.

### [L] 3.7 TruePeakMeter mislabels multichannel peaks
- **Where:** `audio_engine.cpp:1102` — channels >1 fold into the "left" peak metric.

### [L] 3.8 Correlated dither across channels
- **Where:** `DitherProcessorState` `audio_engine.cpp:2146–2167`
- **What:** A single PRNG feeds all channels each sample → mono-correlated dither image (up-mixes show it).

### [L] 3.9 WarpedPFB left/right warping mismatch at high sample rates
- **Where:** `audio_engine.cpp:1817–1833` (init), `:1928–1929` (refresh)
- **What:** `assignPtrWarpedPFB(subband1,…)` skips `warpingFactor` init, so at ≥88.2 kHz the left bank
  analyzes with λ=0.82 while the right stays λ=0.65.

### [L] 3.10 `AutomatedParamFloat::next()` never reaches target
- **Where:** `audio_engine.cpp:1471–1475`
- **What:** Linear stepping overshoots/undershoots with no clamp → permanent micro-oscillation around setpoints.

### [L] 3.11 Fictional PDC latency reported for the simple limiter
- **Where:** `LimiterState::getLatencySamples` `audio_engine.cpp:974`
- **What:** Reports `attackMs` worth of latency although this limiter has no delay line →
  position display shifted by the fake compensation. Conversely, real latencies from
  `MasterLimiterDSP` and `FFTConvolverDSP` are missing entirely from
  `calculate_total_pipeline_latency_samples` (`:5772`).

---

## 4. Design / API Hygiene

| # | Issue | Where |
|---|-------|-------|
| 4.1 | **Silent no-op APIs** — reverb, lowpass/highpass, delay, bandpass/peak/notch/shelf EQ, spatialization (entire 3D section incl. listener/doppler/cones), custom LPF1/HPF1/biquad, legacy dynamic-bass are all `(void)e;` stubs while `audio_engine.h` advertises them. | `audio_engine.cpp:5928–6081`, `6018+`, `6620–6705`, `6267–6275` |
| 4.2 | Dead code — `ReverbState`, `DelayState`, `OnePoleState` (~250 lines) unused after stubbing. | `audio_engine.cpp:407–568` |
| 4.3 | `bypassAppDsp` silently disables ALL app DSP — including user volume and EQ — in exclusive mode. Surprising UX. | `audio_engine.cpp:4297` |
| 4.4 | `AE_FORMAT_S24` maps to an S32 device ("WASAPI container" hack); dither quantizes on a 24-bit grid before S32 conversion — works, but dither depth and telemetry disagree. | `audio_engine.cpp:6377`, `2180–2183` |
| 4.5 | `ae_set_output_format` / `ae_set_output_channels` stop the device WITHOUT `deviceMutex` → double-uninit race if two control calls overlap (`restart_and_apply_config` also stops/uninits under the lock). | `audio_engine.cpp:6777`, `6826` |
| 4.6 | Device started before `pcmRingBuffer.init(192000)` — safe today only because `read()` checks empty. | `audio_engine.cpp:4688` vs `4697` |
| 4.7 | Multiband-EQ gain change re-inits `ma_peak2` → filter-state reset click (acknowledged in comment). | `audio_engine.cpp:7093` |
| 4.8 | `applyRatePlan` reads `e->currentDecoder` without `decoderMutex` (log only, benign-ish but inconsistent locking). | `audio_engine.cpp:3090` |
| 4.9 | `engineAbsoluteTime` incremented by both decode producer AND pre-start silence path in the callback — double-counting semantics for scheduled start. | `audio_engine.cpp:3958`, `4169` |
| 4.10 | Repo hygiene — committed build artifacts and crash dumps: `*.o`, `*.dll`, `test_*.exe`, `hs_err_pid14764.log`, `replay_pid14764.log`, build dirs. | repo root |

---

## Top 5 fixes by impact

1. **Move loudness/true-peak metering off the RT thread** (or make integrated gating incremental and
   drop the per-block sort) — removes guaranteed periodic dropouts. *(1.4, 2.5)*
2. **Fix the recursive `decoderMutex`** in the `worker_loop` auto-SR-match jump path — hard hang today. *(1.1)*
3. **Use `ma_get_bytes_per_frame` in `data_callback`'s catch-handler memset** — heap corruption. *(1.2)*
4. **Lock-free parameter handoff for the clean-room DSP suite** (sequence counter / atomic doubles /
   snapshot swap) instead of the decorative `dspMutex`, and default-disable `MasterLimiterDSP`. *(1.3, 1.5)*
5. **Fix Pure Bass+ FIR table (or mix instead of replace)** and `CrossfeedNode` algorithm switching. *(1.6, 1.7)*
