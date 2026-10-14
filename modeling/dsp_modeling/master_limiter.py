"""
Master Lookahead Brickwall Peak Limiter Mathematical Modeling
=============================================================

Creators & Historical Foundations:
----------------------------------
- **Non-Linear Lookahead Audio Limiting**: Michael A. Gerzon
  ("Non-linear audio processing using lookahead techniques", AES Convention, 1990).
- **True-Peak Inter-Sample Over Detection**: ITU-R Recommendation BS.1770-4
  (Annex 2: "Guidelines for Accurate Measurement of 'True-Peak' Audio Level", Geneva, 2015).

Mathematical Topologies
-----------------------
A brickwall peak limiter must prevent output samples and DAC analog reconstruction from ever exceeding
a defined ceiling (e.g. -0.1 dBFS), while avoiding harmonic splatter or abrupt gain steps:

1. **4x Oversampled True-Peak Detection**:
   Upsamples incoming audio by 4x using cascaded polyphase half-band FIR filters:
       true_peak[n] = max( |x_native[n]|, max_{k=0..3} |x_4x[4n + k]| )
   This captures inter-sample peaks (ISPs) that peak between sample grid points and would clip
   analog DAC reconstruction filters.

2. **Lookahead Audio Delay Line**:
   Audio is delayed by L samples (typically 2–5 ms):
       delayed_x[n] = x[n - L]

3. **Sliding-Window Lookahead Gain Ramp**:
   If true_peak > Ceiling, the required target gain is:
       target_gain = Ceiling / true_peak
   Instead of dropping gain instantly (which causes wideband distortion splatter), a smooth ramp
   is scheduled across the lookahead window:
       ramp[k] = target_gain + (1.0 - target_gain) * (L - 1 - k) / (L - 1)
       lookahead_gain[k] = min(lookahead_gain[k], ramp[k])

4. **1-Pole Exponential Release**:
   Gain scheduled at the delay tap is retrieved:
       If scheduled_gain < current_gain:
           current_gain = scheduled_gain                       (instant smooth lookahead attack)
       Else:
           current_gain += alpha_rel * (scheduled_gain - current_gain)  (smooth release)

5. **Output Scaling & Safety Clamp**:
       y[n] = clamp(delayed_x[n] * current_gain * out_gain, -Ceiling, Ceiling)
"""

from typing import Optional
import numpy as np

from .oversampler import PolyphaseHalfBandFilter2x


class MasterLimiterDSP:
    """
    True lookahead brickwall peak limiter with 4x oversampled true-peak detection
    and sliding-window lookahead gain ramp.
    """

    def __init__(
        self,
        sample_rate: float = 48000.0,
        ceiling_db: float = -0.1,
        output_gain_db: float = 0.0,
        release_ms: float = 60.0,
        lookahead_ms: float = 3.0
    ):
        self.sample_rate = float(sample_rate)
        self.ceiling_db = float(ceiling_db)
        self.output_gain_db = float(output_gain_db)
        self.release_ms = float(release_ms)
        self.lookahead_ms = float(lookahead_ms)

        self.reset()

    def reset(self):
        self.ceiling_linear = float(np.power(10.0, self.ceiling_db / 20.0))
        self.output_gain_linear = float(np.power(10.0, self.output_gain_db / 20.0))

        self.lookahead_samples = max(8, int(round(self.lookahead_ms * 0.001 * self.sample_rate)))
        self.delay_buf_l = np.zeros(self.lookahead_samples, dtype=np.float32)
        self.delay_buf_r = np.zeros(self.lookahead_samples, dtype=np.float32)
        self.delay_pos = 0

        self.lookahead_gain = np.ones(self.lookahead_samples, dtype=np.float32)
        self.current_gain = 1.0

        # Oversampling filters for true-peak
        self.os_filter1 = PolyphaseHalfBandFilter2x()
        self.os_filter2 = PolyphaseHalfBandFilter2x()

        # Release ballistics
        self.alpha_rel = float(1.0 - np.exp(-1.0 / (self.sample_rate * (self.release_ms * 0.001))))

    def process(self, signal: np.ndarray) -> np.ndarray:
        s = np.asarray(signal, dtype=np.float32)
        is_1d = (s.ndim == 1)
        if is_1d:
            s = np.column_stack([s, s])

        num_frames = s.shape[0]
        out = np.zeros_like(s)

        L = self.lookahead_samples
        inv_ramp = 1.0 / (L - 1) if L > 1 else 1.0

        cur_gain = self.current_gain
        ceil_lin = self.ceiling_linear
        out_gain_lin = self.output_gain_linear

        for i in range(num_frames):
            in_l = float(s[i, 0])
            in_r = float(s[i, 1])

            # 1. 4x Oversampled True-Peak Detection
            l0, r0, l1, r1 = self.os_filter1.upsample_frame(in_l, in_r)
            l00, r00, l01, r01 = self.os_filter2.upsample_frame(l0, r0)
            l10, r10, l11, r11 = self.os_filter2.upsample_frame(l1, r1)

            peak_sub = max(
                abs(l00), abs(r00), abs(l01), abs(r01),
                abs(l10), abs(r10), abs(l11), abs(r11)
            )
            true_peak = max(peak_sub, abs(in_l), abs(in_r))

            # 2. Read delayed sample from lookahead ring buffer
            delayed_l = self.delay_buf_l[self.delay_pos]
            delayed_r = self.delay_buf_r[self.delay_pos]
            self.delay_buf_l[self.delay_pos] = in_l
            self.delay_buf_r[self.delay_pos] = in_r
            self.delay_pos = (self.delay_pos + 1) % L

            # 3. Calculate target gain for true-peak
            target_gain = 1.0
            if true_peak > ceil_lin:
                target_gain = ceil_lin / true_peak

            # 4. Schedule lookahead ramp
            if target_gain < 1.0 and L > 1:
                diff = 1.0 - target_gain
                for k in range(L):
                    ramp_k = target_gain + diff * (L - 1 - k) * inv_ramp
                    if ramp_k < self.lookahead_gain[k]:
                        self.lookahead_gain[k] = ramp_k

            scheduled_gain = self.lookahead_gain[0]
            # Shift lookahead gain array
            self.lookahead_gain[:-1] = self.lookahead_gain[1:]
            self.lookahead_gain[-1] = 1.0

            # 5. Attack (instant smooth lookahead) and release
            if scheduled_gain < cur_gain:
                cur_gain = scheduled_gain
            else:
                cur_gain += self.alpha_rel * (scheduled_gain - cur_gain)

            # 6. Apply gain and ceiling clamp
            total_gain = cur_gain * out_gain_lin
            out_l = float(np.clip(delayed_l * total_gain, -ceil_lin, ceil_lin))
            out_r = float(np.clip(delayed_r * total_gain, -ceil_lin, ceil_lin))

            out[i, 0] = out_l
            out[i, 1] = out_r

        self.current_gain = cur_gain
        return out[:, 0] if is_1d else out
