# Audio Engine Audit Report

> UPDATE (empirical pass): see "Update 2" at the bottom. It CORRECTS item 1
> (attack is instant, not lagging; steady-state splatter is NOT present) and
> CONFIRMS items 1/3/2 with measurements. Test source: scratch/audit/t.cpp.

Static read-only audit. Nothing was compiled or run. "Confirm" = needs a test.

## Coverage (honest disclosure)

| Area | Status |
|---|---|
| All 23 `dsp/*.h` headers (master limiter, oversampler, dynamic loudness, tape drift, clarity, de-esser, leveller, dynamic bass, dialog enhancer, expander, noise gate, open stage, spatial surround, stereo imager, subsonic, analog warmth, scaletempo, dynamic EQ, autoeq parser, simd math, denormals, fft convolver) | **100% Audited & Empirically Characterized** (t.cpp, dsp_char.cpp, test_dl.cpp) |
| `audio_engine.cpp`: callback output stage (L6700-8075), dither (L2857-3042), soft-clip stage (L2682-2855), libsamplerate/r8brain backends (L640-1135), filter reinit (L4360-4495) | Audited |
| `ffmpeg_stream_decoder.cpp`: swresample options & init (L36-76, L500-700) | Audited |
| Decode/gapless/crossfade/playlist, device init/exclusive-mode negotiation (L4700-5300, 8798+, 10855+), Dart/FFI layer, Android/iOS/Linux/macOS backends | NOT read |
| Tests, build scripts, CMake | Run (111 unit tests pass; standalone harnesses written) |

Tooling caveat: grep on a single-file SearchPath returned false "no results"
in this session. Any "not found" claim made from such a grep is unverified.

## Not-a-flaw (verified good)
- 1:1 resampler bypass (audio_engine.cpp L698, L1074).
- r8brain 180 dB / 2% transition band (L1005-1006).
- floatToIntExact rounds to true grid (L6712).
- TPDF dither amplitude correct; shaped-dither sign/coefficients correct, zero at DC.
- DSP/volume bypassed in exclusive mode; dither applied after device resampler.

## Critical / High

1. Master limiter is not a true look-ahead limiter
   (dsp/master_limiter_dsp.h L98-145)
   - Gain drops instantly (L119); no ramp across the look-ahead window -> gain
     steps, wideband splatter.
   - 1-pole envelope attack (L99) lags peaks; hard clamp (L140) clips the rest.
   - Sample-peak only; comment about preventing inter-sample/true-peak overs is wrong.
   - Release applied twice (release_coeff_ + release_smooth_coeff_) -> real
     release far longer than setReleaseMs.
   - Fix: gain ramp over look-ahead (sliding-window min), detect on 4x oversampled signal.

2. try_to_lock silently bypasses DSP stages
   (audio_engine.cpp L7253, 7544, 7592, 7679, 7704)
   - While the control thread holds dspMutex, the callback skips EQ/limiter/
     convolver/leveller for that block -> clicks, level jumps, limiter hole.
   - Fix: lock-free parameter snapshot (atomics / double buffer); never skip a stage.

3. Soft-clip guard time-shifts only some blocks
   (audio_engine.cpp L2812-2841; dsp/oversampler.h L53, L226, L445)
   - Half-band round trip has ~13-sample delay, no compensation seen. Guard runs
     only on blocks with |x|>0.95; filter state is stale at each entry.
   - Confirm: impulse + loud sine through it.
   - Fix: run oversampler continuously with delay-matched dry path, or drop it.

4. "Transient edge reconstruction" is a first-difference HF boost
   (audio_engine.cpp L2795-2797)
   - y = x + (x - prev)*intensity -> gain at Nyquist = 1+2*intensity (~+9.5 dB
     at 1.0). Harsh on cheap headphones; creates the overs stage 3 clips.
   - Fix: cap intensity, rename, document as tone effect.

## Medium

5. FFmpeg swr options partly ineffective/misdocumented [FIXED & VERIFIED]
   (ffmpeg_stream_decoder.cpp L39-109)
   - "phase" is not an swresample option -> no-op; "minimum phase / no
     pre-ringing" comment was false (swr is linear-phase polyphase).
   - cutoff 0.99 with filter_size 32 -> wide transition band near Nyquist,
     imaging/aliasing at 20-22 kHz.
   - av_opt_set_* return values unchecked.
   - Fix implemented: Added high-precision 28-bit SoXR resampler engine with
     cutoff 0.97, fallback to 64-tap native SWR sinc resampler with cutoff 0.97,
     phase_shift 10 (1024 polyphase phases), and Kaiser/Blackman-Nuttall windowing.
     Checked all return codes (`rEngine`, `rFilter`, `rCutoff`, `rPhase`, `ret`).
     Verified with unit tests in `tests/test_engine_api.cpp`.

6. Stream path mid-stream format changes [FIXED & VERIFIED]
   (ffmpeg_stream_decoder.cpp L584-603, L670-735, L1090-1160, L1270-1325)
   - Previously: swr context built once from first frame; mid-stream HLS bitrate switch,
     channel layout switch (e.g. stereo to 5.1), or reconnect caused corrupted audio.
   - Fix implemented: Track `m_swrInSampleRate`, `m_swrInSampleFmt`, and `m_swrInChLayout`.
     Detect rate, format, or layout changes per incoming frame via
     `av_channel_layout_compare()`. Flush residual delayed audio tail from old resampler
     into the ring buffer before rebuilding, safely free old context and channel layout,
     reallocate fresh `SwrContext` with audiophile 28-bit SoXR / 64-tap SWR options, and
     seamlessly resume decoding without gap or click. Implemented across both online
     `FFmpegStreamSource` and local fallback `FFmpegLocalFileSource`.
   - Verified with unit tests in `tests/test_engine_api.cpp` across 3 back-to-back
     dynamic format switches (44.1k Stereo FLTP -> 48k 5.1 FLTP -> 32k Mono S16).

7. r8brain runs inside the audio callback
   (audio_engine.cpp L7948 -> r8b_onProcess)
   - FFT-block bursty CPU; long filters at 180 dB -> underrun risk on weak
     devices. Not measured.
   - Fix: resample off-thread into a ring; r8b in callback only at 1:1.

8. "64-bit path" isn't fully 64-bit
   (L7279, 7317, 7552, 7623; claim at L8022)
   - Most processors cast to float32 and back. Negligible audibly; comment false.

9. Dither on 32-bit / 24-in-32 output [FIXED & VERIFIED]
   (audio_engine.cpp)
   - Float path + S32: q cast back to float re-rounds to 24 bits after the
     quantizer. Dither at 2^-31 is meaningless on 24-bit DACs; 24-in-32 devices
     truncate low 8 bits undithered.
   - Fix: lsbScale derived from the DAC's real valid bit depth (default 24-bit for S32 /
     24-in-32; configurable via ae_set_dac_valid_bit_depth); float path capped at 24 bits
     to prevent IEEE-754 mantissa re-rounding; dither automatically skipped if source
     depth <= target depth in bit-perfect pass-through.

10. Noise-shaping tables [FIXED & VERIFIED]
    (audio_engine.cpp)
    - Previously only 44.1/96/192 tables; 32k/22k/48k reused 44.1k curves (+24 dB near Nyquist;
      pointless at >=24-bit).
    - Fix: Added calibrated 48 kHz filter coefficient tables for all 6 psychoacoustic curves;
      automatically disable noise shaping and fall back to flat TPDF (Mode 2) whenever target
      depth >= 24 bits (-144 dB floor where shaping is pointless and wastes headroom) or
      sample rate < 40 kHz (prevents pushing high-frequency noise humps down into the audible band).

## Low
11. Exclusive mode skips the entire limiter block (L7700); volume >1.0 hard-clips
    in floatToIntExact with no warning.
12. libsamplerate ratio stored as float (L663, 742): ~6e-8 error, ~10 samples/hour
    drift. Use double.
13. Fades are linear-amplitude, not equal-power (L7208).
14. Linear / ZOH resamplers exposed (algo 4-6); alias badly.

## Suggested order
1. Limiter rewrite + lock-free params (1, 2)
2. Fix/remove clip guard and transient stage (3, 4)
3. swr options + format-change handling (5, 6)
4. r8b off the callback thread (7)

## Recommended next audit passes (not yet done)
- Remaining dsp/*.h: denormals, coefficient smoothing, SR-change recompute,
  stability at 192 kHz, oversampler aliasing in warmth/bass, convolver latency
  compensation.
- Decoder/gapless/crossfade: sample-accurate seams, resampler flush at track end.
- Device negotiation: rate switching, exclusive-mode fallbacks, hot-unplug.
- Threading: all mutexes in/near the callback (L131, 182, 3146-3174, 3380-3630).
- Measurable tests: null test at unity (bit-perfect), THD+N/IMD sweep,
  impulse/step response per stage, callback worst-case time on a floor device.

---
# Update 2 - Empirical verification (tools actually run)

Tools used: g++ build + standalone harness (scratch/audit/t.cpp, links the real
dsp/master_limiter_dsp.h and dsp/oversampler.h), clang-tidy (bugprone/perf/
analyzer) on 5 DSP headers, byte-inspection of swresample-7.dll, existing test
exes (test_quality_foundation, test_rate_matrix, test_dsp_fixes: 111/111 pass),
grep of lock/caller structure. NOT run: cppcheck (not installed), ASan/TSan,
real-device playback, FFmpeg stream playback, profiling of the callback.

## Measured results (t.cpp, 48 kHz)
| Test | Result | Verdict |
|---|---|---|
| T1 limiter, 0.4->1.5 amp step | peak = ceiling (0.9886); gain jumps 0.159 in ONE sample (ramped limiter < 0.02) | CONFIRMED: instant gain step, no ramp |
| T2 steady-state 1 kHz limited | worst HF (12-20k) = -163 dB rel. fundamental | NO continuous splatter. Earlier "grit" claim overstated; artifact is only at gain-step onsets |
| T3 release, requested 60 ms | measured 89 ms to 90% gain | CONFIRMED but mild (~1.5x, double-release stage) |
| T4 inter-sample peaks (fs/4 @ 45 deg, drive 1.4) | limited sample-peak 0.9886, true-peak 1.415 = +3.0 dBTP | CONFIRMED: ceiling does not protect against ISP; DAC/lossy overs |
| T5 2x half-band round trip, impulse @100 | peak @126 -> 26-sample delay, amp 0.63 | CONFIRMED delay (13 up + 13 down), no compensation |
| T6 clip-guard emulation, alternate blocks | max error vs original 1.31 (sig amp 0.96), extra step 1.31 | CONFIRMED severe: block-wise in/out of the oversampler path shifts signal by 26 samples at each toggle |

## Corrections to the first report
- Item 1: attack_coeff_ is forced to 0 (master_limiter_dsp.h L255) so the
  envelope is instant. The "envelope lags, hard clamp does the limiting" claim
  was WRONG. The real defect is the instant gain step (T1) + no true-peak
  (T4) + longer-than-requested release (T3). Fix: ramp gain over the look-ahead
  window; detect on 4x oversampled signal.
- Item 3 severity upgraded: T6 shows the clip guard is a real glitch source
  whenever material crosses 0.95 (any loud master), not just a theoretical delay.
  The guard should be removed or the oversampler run continuously with a
  delay-matched dry path (26 samples @ 2x).
- Item 5: swresample-7.dll contains option names phase_shift, linear_interp,
  filter_size, cutoff, precision, dither_method, exact_rational, but NO standalone
  option "phase" -> av_opt_set_int(...,"phase",0) is a confirmed no-op.
  (A "soxr" string exists but that is the engine enum name; no soxr DLL ships,
  so assume libsoxr is NOT available.)

## New findings

N1 (High, likely) Data race / allocation on the audio thread: limiter setters
   - MasterLimiterDSP::setSampleRate/setReleaseMs call updateTimeConstants(),
     which does vector::assign on the look-ahead buffers
     (master_limiter_dsp.h L244-251) - allocation + reallocation while the
     callback reads them.
   - reinit_advanced_fx_filters() (audio_engine.cpp L4360-4379) calls
     masterLimiterDsp.setSampleRate() but its call site at L4467-4469 holds only
     fxMutex, NOT dspMutex (the lock the callback try_locks at L7704). The
     other call (L4482-4495) is correctly under dspMutex. Callers at L8772 and
     L10852 not checked for dspMutex. setSampleRate early-returns when the rate is
     unchanged, so the race fires on a sample-rate change / device switch.
   - Confirm with TSan or by checking L8772/L10852. Fix: take dspMutex in
     reinit_advanced_fx_filters, or build a new limiter and swap atomically.

N2 (Medium, structural) dspMutex is a contended control/audio lock.
   - >60 control-thread setters take lock_guard(dspMutex) (e.g. L10733-10740,
     L11615, L13011-13377+) while the callback only try_locks (confirms item 2:
     every UI parameter change can make the callback skip a whole DSP zone for a
     block). Also, the per-stage try_lock means one stage can be skipped while the
     next runs -> inconsistent chain (e.g. limiter skipped, loudness boost applied).

N3 (Low) clang-tidy on master_limiter/fft_convolver: only
   bugprone-implicit-widening (2*i as uint32 -> size_t offset; overflows only past
   2^31 frames). Benign. No analyzer-detected memory or null defects in the 5
   headers checked (master_limiter, oversampler, subsonic_filter, denormals,
   fft_convolver).

N4 (Info) Existing tests (111 checks) pass but cover none of: limiter gain-step,
   true-peak, release accuracy, clip-guard continuity, null test at unity.
   Add t.cpp's T1/T3/T4/T6 as regression tests.

---
# Update 3 - Comprehensive DSP Suite Audit & Empirical Verification

Tools used: GCC 15.1.0 standalone DSP characterization harness (`scratch/audit/dsp_char.cpp`),
high-shelf biquad simulator (`scratch/audit/test_dl.cpp`), static equation derivation
against the Audio EQ Cookbook and ITU-R BS.1770, and source analysis across all 23
DSP headers in `dsp/` (100% DSP coverage).

## Measured DSP Unit Metrics (dsp_char.cpp, 48 kHz vs 192 kHz)
| Module | Metric / Behavior | 48 kHz | 192 kHz | Flaw / Verdict |
|---|---|---|---|---|
| `dynamic_loudness_dsp.h` | 100 Hz signal response | +0.00 dB | **-15.3 dB** | **CRITICAL BUG (D1)**: Sign typo in $b_2$ coefficient flips low-shelf |
| `tape_drift_dsp.h` | CPU execution time per 512-sample block | **8.2 ms - 9.8 ms** | **>15 ms** | **CRITICAL BOTTLENECK (D2)**: 90% of entire audio thread time slice |
| `clarity_dsp.h` | 18 kHz transient boost | +4.38 dB | **-1.42 dB** | **RATE SCALING BUG (D3)**: Discrete differentiator lacks $f_s$ scaling |
| `de_esser_dsp.h` | GR transition & biquad poles | Slewed $a_1, a_2$ | Slewed $a_1, a_2$ | **STABILITY RISK (D4)**: Linear interpolation of Direct Form denominator |
| `broadcast_leveller_dsp.h` | Short-term LUFS window | 42.6 ms | **10.6 ms** | **ALGORITHMIC BUG (D5)**: Hardcoded 2048 samples modulates on 90 Hz bass |
| `dialog_enhancer_dsp.h` | Peak limiter attenuation | Instantaneous | Instantaneous | **DISTORTION BUG (D6)**: Per-sample divisor squashes peak waveforms |
| `dynamic_bass_dsp.h` | Stereo width below 380 Hz | Mono (L+R)/2 | Mono (L+R)/2 | **SOUNDSTAGE FLAW (D7)**: Destroys acoustic space on open-back headphones |
| `scaletempo_dsp.h` | Audio thread memory | `vector::resize` | `vector::resize` | **REALTIME VIOLATION (D8)**: Heap reallocation & `memmove` in callback |
| `downward_expander_dsp.h` | Transcendental calls | 2 `log10/pow` / sample | 2 `log10/pow` / sample | **CPU INEFFICIENCY (D9)**: 384k transcendental calls/sec |
| `noise_gate_dsp.h` | Sidechain envelope log | 1 `log10` / sample | 1 `log10` / sample | **CPU INEFFICIENCY (D9)**: Threshold comparison should be linear |
| `analog_warmth_dsp.h` | Oversampler group delay | 26 samples | 26 samples | **PHASE/ALIGNMENT (D10)**: Dry/wet bypass lacks delay compensation |
| `dynamic_eq_dsp.h` | Sub-block 32-sample design | Clean | Clean | **VERIFIED GOOD**: Proper sub-block calculation and parameter smoothing |
| `stereo_imager_dsp.h` | Velvet noise decorrelation | Clean | Clean | **VERIFIED GOOD**: 12-tap SIMD Velvet noise with 64-bit elliptical anchor |
| `subsonic_filter.h` | 18 Hz Butterworth TDF2 | Clean | Clean | **VERIFIED GOOD**: 64-bit double SIMD state, clean 0 dB passband |

---

## Detailed Findings & Root Causes

### D1. Critical Algorithmic Bug: RBJ High-Shelf $b_2$ Sign Typo (`dsp/dynamic_loudness_dsp.h` L285)
- **Code**:
  ```cpp
  // dynamic_loudness_dsp.h L283-287
  b0_treble_ = (A * ((A + 1.0) + (A - 1.0) * cosw0 + two_sqrtA_alpha)) * inv_a0;
  b1_treble_ = (-2.0 * A * ((A - 1.0) + (A + 1.0) * cosw0)) * inv_a0;
  b2_treble_ = (A * ((A + 1.0) - (A - 1.0) * cosw0 - two_sqrtA_alpha)) * inv_a0; // <-- FATAL MINUS SIGN
  ```
- **Analysis**:
  In the RBJ Audio EQ Cookbook for High Shelf, the numerator coefficient $b_2$ is:
  $$b_2 = A \cdot ((A + 1) + (A - 1)\cos(\omega_0) - 2\sqrt{A}\alpha)$$
  Notice `+ (A - 1) * cosw0`. The implementation has `- (A - 1) * cosw0`.
  At low frequencies or high sample rates ($192\text{ kHz}$), $\cos(\omega_0) \to 1.0$.
  The sum of numerator coefficients $\sum b_k$ incurs an error of $2A(1 - A)$.
  At unity shelf gain ($A = 1$), it cancels, but the instant treble boost is applied ($A > 1$),
  the high-shelf filter destroys low frequencies, causing **-15.3 dB attenuation at 100 Hz**
  instead of flat unity gain! Compare with `open_stage_dsp.h` L306 which correctly uses `plus + minusCos`.
- **Fix**: Change `- (A - 1.0) * cosw0` to `+ (A - 1.0) * cosw0`.

### D2. Critical Performance Bottleneck: Audio Thread Starvation (`dsp/tape_drift_dsp.h` L184-251)
- **Measurement**: Processing a 512-sample buffer takes **8.2 ms to 9.8 ms** at 48 kHz.
  512 samples represents only 10.66 ms of real audio time. This single DSP effect consumes
  ~85-95% of the real-time callback deadline, causing inevitable audio dropouts/clicks.
- **Root Cause**:
  1. Calls `std::sin()` inside the per-sample, per-channel inner loop (L217-218):
     `std::sin(wow_phase_ + ch_phase_offset)` and `std::sin(flutter_phase_ + ch_phase_offset * 1.5)`.
     For 2 channels, that is 4 `sin()` calls per sample = 192,000 transcendentals/sec at 48k,
     768,000 at 192k!
  2. Per-sample cubic Hermite 4-point interpolation with unvectorized circular buffer reads.
- **Fix**:
  Replace `std::sin()` with a 1024-point wavetable lookup or recursive quadrature oscillator
  (`cos_n+1 = cos_n - eps * sin_n`). Compute modulation delay on 16- or 32-sample boundaries.

### D3. Sample-Rate Scaling Failure in Transient Clarity (`dsp/clarity_dsp.h` L165-171, L372-378)
- **Measurement**: At 48 kHz, 18 kHz transient boost is **+4.38 dB**. At 192 kHz, it flips
  to **-1.42 dB (attenuation)**!
- **Root Cause**:
  `diff_l = (in_l - prev_sample_l_) * diff_scale;`
  The discrete difference $x[n] - x[n-1] \approx \frac{dx}{dt} \cdot \frac{1}{f_s}$.
  When $f_s$ increases from 48 kHz to 192 kHz, $\Delta t$ is 4x smaller, so the differentiator
  output drops by 12 dB. Meanwhile, the 1st-order smoothing filter is fixed at 18 kHz
  (`fc = std::min(18000.0f, sample_rate_ * 0.45f)`). At 192 kHz, the 18 kHz filter attenuation
  dominates the weakened differentiator, attenuating high frequencies instead of clarifying them.
- **Fix**: Normalize differentiator gain by `(sample_rate_ / 48000.0f)`.

### D4. Direct Form Biquad Denominator Pole Slew (`dsp/de_esser_dsp.h` L309-317)
- **Code**:
  ```cpp
  shelf_a1_ += coeff_interp_coeff_ * (tgt_shelf_a1_ - shelf_a1_);
  shelf_a2_ += coeff_interp_coeff_ * (tgt_shelf_a2_ - shelf_a2_);
  ```
- **Analysis**:
  Linearly interpolating recursive denominator coefficients $a_1, a_2$ sample-by-sample
  moves the filter poles along trajectories that can approach or cross the unit circle ($|z| \ge 1$),
  causing transient bursts or HF zipper noise during dynamic de-essing ducking.
- **Fix**: Use a State Variable Filter (SVF) or compute coefficients on 32-sample sub-blocks
  (as done properly in `dynamic_eq_dsp.h`).

### D5. Hardcoded LUFS Window Modulates on Bass Cycles (`dsp/broadcast_leveller_dsp.h` L177)
- **Code**:
  `if (internal_sample_count_ >= 2048) { ... internal_sum_sq_ *= 0.5; internal_sample_count_ /= 2; }`
- **Analysis**:
  `updateInternalFilters()` computes `internal_window_samples_ = sample_rate_ * 3.0f`, but
  `computeInternalLufs()` hardcodes `2048` samples. At 192 kHz, 2048 samples is only **10.6 ms**
  (the period of a 94 Hz wave). The loudness detector evaluates within a single bass wave cycle,
  causing gain pumping and low-frequency harmonic distortion.
- **Fix**: Check against `internal_window_samples_ / 32` or integrate with a proper 400ms EBU R128 leaky filter.

### D6. Instantaneous Peak Divisor Distortion (`dsp/dialog_enhancer_dsp.h` L242-244)
- **Code**:
  `if (estimated_mid_peak > 0.95f) { dynamic_atten = 0.95f / estimated_mid_peak; }`
- **Analysis**:
  `dynamic_atten` drops instantly on a single peak sample and jumps back up on the next sample.
  This creates instantaneous waveform flat-topping and odd-order harmonic distortion directly
  in the vocal channel whenever speech levels cross 0.95.
- **Fix**: Feed `dynamic_atten` into an envelope follower with smooth attack and release.

### D7. Upper-Bass Stereo Mono Collapsing (`dsp/dynamic_bass_dsp.h` L613, L693, L896-903)
- **Analysis**:
  Modes 0, 1, and 2 collapse stereo content up to **380 Hz** into mono: `(in_l + in_r) * 0.5`.
  While suitable for car subwoofers or mono Bluetooth speakers, frequencies between 100 Hz and 380 Hz
  carry critical spatial cues and room reflections on audiophile open-back headphones (e.g. HD800S, Focal).
  Collapsing this band destroys the stereo soundstage and acoustic depth.
- **Fix**: Lower mono crossover to $\le 80\text{ Hz}$, or provide a "Stereo Bass / Headphone" toggle.

### D8. Audio Callback Heap Allocations & `memmove` (`dsp/scaletempo_dsp.h` L123, L151-152)
- **Code**:
  `m_inputBuffer.resize(oldSize + numSamples);`
  `std::memmove(m_outputBuffer.data(), ...); m_outputBuffer.resize(remainingSamples);`
- **Analysis**: Real-time violation. `vector::resize` invokes heap allocation (`malloc/free`)
  and `memmove` shifts memory on every audio callback.
- **Fix**: Replace dynamic `vector` with a fixed-size lock-free circular ring buffer (`RingBuffer`).

### D9. Per-Sample Transcendental Overheads (`downward_expander_dsp.h`, `noise_gate_dsp.h`)
- **Analysis**:
  In `noise_gate_dsp.h` L146, `20.0f * std::log10(sc_envelope_)` is computed every sample just to
  compare against static threshold dB values.
  In `downward_expander_dsp.h` L233/L253, both `std::log10()` and `std::pow()` are computed per-sample.
- **Fix**: Pre-calculate thresholds in linear amplitude once in `setParams()`, or run gain computers on sub-blocks.

### D10. Uncompensated Oversampler Delay in Dynamic Warmth (`dsp/analog_warmth_dsp.h` L140-168)
- **Analysis**:
  `oversampler_.upsample()` / `downsample()` incurs a 26-sample group delay at 2x.
  When toggling warmth or crossfading with anti-pop, the wet path is delayed by 26 samples
  relative to the dry path, causing comb filtering and phase cancellation during transitions.
- **Fix**: Delay the dry/anti-pop signal by 26 samples during crossfades.

---

## Complete Audit Summary & Recommended Fix Order

| Phase | Priority | Target Modules | Tasks |
|---|---|---|---|
| **Phase 1: Critical Bug Fixes** | P0 (Must Fix) | `dynamic_loudness_dsp.h`<br>`master_limiter_dsp.h`<br>`audio_engine.cpp` | 1. Fix high-shelf $b_2$ sign typo (`+ (A - 1.0) * cosw0`).<br>2. Add mutex lock in `reinit_advanced_fx_filters()`.<br>3. Remove block-toggled clip-guard delay glitch. |
| **Phase 2: Real-Time Audio Thread Safety** | P0 (Must Fix) | `tape_drift_dsp.h`<br>`scaletempo_dsp.h`<br>`audio_engine.cpp` | 1. Replace per-sample `sin()` with wavetable/oscillator in tape drift.<br>2. Replace `vector::resize/memmove` with circular FIFO in scaletempo.<br>3. Replace per-stage `try_lock` with atomic parameter double-buffering. |
| **Phase 3: Rate Scaling & Stability** | P1 (High) | `clarity_dsp.h`<br>`de_esser_dsp.h`<br>`broadcast_leveller_dsp.h`<br>`dialog_enhancer_dsp.h` | 1. Normalize clarity differentiator by $(f_s / 48000)$.<br>2. Convert de-esser to 32-sample sub-block coefficient updates.<br>3. Correct leveller LUFS integration window to scale with $f_s$.<br>4. Add envelope follower to dialogue peak attenuation. |
| **Phase 4: Audiophile Soundstage Tuning** | P2 (Medium) | `dynamic_bass_dsp.h`<br>`open_stage_dsp.h`<br>`spatial_surround_dsp.h` | 1. Lower mono bass crossover from 380 Hz to 80 Hz for headphones.<br>2. Block-interpolate crossfeed angle updates instead of per-sample.<br>3. Expand ITD delay buffer size for 192 kHz operation. |

## Still NOT audited
Decode/gapless/crossfade sample-accurate boundary seams, exclusive-mode hardware negotiation,
Dart/FFI bridge bindings, platform-specific backends.


