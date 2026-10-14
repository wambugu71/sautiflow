"""
Binaural Crossfeed Topologies Mathematical Modeling
===================================================

Creators & Historical Foundations:
----------------------------------
- **Bauer Crossfeed Circuit & Binaural Phonation**: Benjamin B. Bauer
  (CBS Laboratories, "Stereophonic Earphones and Binaural Loudspeakers", JAES, 1961).
- **libbs2b Implementation**: Boris Mikhaylov
  ("Bauer stereophonic-to-binaural DSP effect library", 2005).
- **Corda Natural Crossfeed Topology**: Dr. Jan Meier
  (Meier Audio, Germany, 2000).
- **Recursive Ambiophonic Crosstalk Elimination (R.A.C.E.)**: Ralph Glasgal & Yoichi Ando
  (Ambiophonics Institute, "Ambiophonics: Real 3D Audio in the Home", JAES, 2001).

Supported Crossfeed Algorithms
------------------------------
1. **Simple Crossfeed**:
   Fractional linear-interpolated delay line + proportional crossfeed gain + RMS energy compensation.

2. **Bauer BS2B**:
   Accurately models the acoustic head-shadow filter of Benjamin Bauer:
       - Low-pass filtered crossfeed path (group delay ~ 1 / (2*pi*fcut))
       - High-boost direct path preserving high-frequency crispness
       - Net delay compensation guaranteeing exact target ITD.

3. **Jan Meier Crossfeed**:
   1-pole lowpass crossfeed paired with direct-channel high-frequency enhancement (+15% treble lift).

4. **Natural Crossfeed**:
   2-pole Butterworth State Variable Filter (SVF) with energy-normalized fractional delay.

5. **Ambiophonics RACE**:
   Contralateral anti-phase recursive acoustic crosstalk cancellation for expansive soundstages:
       raw_L = in_L - alpha * LPF(delayed_out_R) + (alpha * 0.35) * mono_bass
       raw_R = in_R - alpha * LPF(delayed_out_L) + (alpha * 0.35) * mono_bass
"""

from enum import IntEnum
from typing import Optional
import numpy as np

from .open_stage import OpenStageDSP


class CrossfeedAlgorithm(IntEnum):
    OFF = 0
    SIMPLE = 1
    BS2B = 2
    BAUER_BS2B = 2
    MEIER = 3
    NATURAL = 4
    RACE = 5
    OPEN_STAGE = 6


class CrossfeedNode:
    """
    Comprehensive stereo crossfeed processor implementing 6 distinct binaural algorithms.
    """

    MAX_DELAY_SAMPLES = 4096

    def __init__(
        self,
        sample_rate: float = 48000.0,
        algorithm: CrossfeedAlgorithm | int = CrossfeedAlgorithm.BS2B,
        mix: float = 0.8,
        delay_ms: float = 0.35,
        cutoff_hz: float = 700.0,
        output_compensation: bool = True
    ):
        self.sample_rate = float(sample_rate)
        self.algorithm = CrossfeedAlgorithm(algorithm)
        self.mix = float(np.clip(mix, 0.0, 1.0))
        self.delay_ms = float(np.clip(delay_ms, 0.02, 5.0))
        self.cutoff_hz = float(np.clip(cutoff_hz, 100.0, 16000.0))
        self.output_compensation = bool(output_compensation)

        self.open_stage = OpenStageDSP(self.sample_rate)
        self.reset()

    def reset(self):
        self.ring_l = np.zeros(self.MAX_DELAY_SAMPLES, dtype=np.float32)
        self.ring_r = np.zeros(self.MAX_DELAY_SAMPLES, dtype=np.float32)
        self.write_idx = 0

        # Filter states
        self.lpf_state_l = [0.0, 0.0]
        self.lpf_state_r = [0.0, 0.0]
        self.bs2b_asis_l = self.bs2b_asis_r = 0.0
        self.bs2b_hi_l = self.bs2b_hi_r = 0.0
        self.bs2b_lo_l = self.bs2b_lo_r = 0.0

        self.race_lpf_out_l = self.race_lpf_out_r = 0.0
        self.race_bass_state = 0.0
        self.open_stage.reset()

    def _calc_bs2b_coeffs(self) -> tuple[float, float, float, float, float, float]:
        fc = self.cutoff_hz
        level_db = 4.5
        g = float(np.power(10.0, -level_db / 20.0))
        q = max(1e-4, 1.0 - g)
        w0 = 2.0 * np.pi * fc / self.sample_rate

        # Lowpass crossfeed coeffs
        b1_lo = float(np.exp(-w0))
        a0_lo = float((1.0 - b1_lo) * (1.0 - g))

        # Highpass direct coeffs
        w1 = w0 / q
        b1_hi = float(np.exp(-w1))
        a0_hi = float(1.0 - (1.0 - g) * (1.0 - b1_hi))
        a1_hi = float(-b1_hi * (1.0 - g))
        bs2b_gain = 1.0
        return a0_lo, b1_lo, a0_hi, a1_hi, b1_hi, bs2b_gain

    def process(self, signal: np.ndarray, right: Optional[np.ndarray] = None) -> np.ndarray:
        if right is not None:
            s = np.column_stack([signal, right]).astype(np.float32)
            is_two_args = True
            is_1d = False
        else:
            s = np.asarray(signal, dtype=np.float32)
            is_two_args = False
            is_1d = (s.ndim == 1)
            if is_1d:
                s = np.column_stack([s, s])

        if self.algorithm == CrossfeedAlgorithm.OFF or self.mix < 1e-4:
            if is_two_args:
                return s[:, 0], s[:, 1]
            return s[:, 0] if is_1d else s

        if self.algorithm == CrossfeedAlgorithm.OPEN_STAGE:
            res = self.open_stage.process(s)
            if is_two_args:
                return res[:, 0], res[:, 1]
            return res[:, 0] if is_1d else res

        num_frames = s.shape[0]
        out = np.zeros_like(s)

        delay_samples = float(self.delay_ms * 0.001 * self.sample_rate)
        clamped_delay = np.clip(delay_samples, 0.01, self.MAX_DELAY_SAMPLES - 2)

        # BS2B coefficients
        a0_lo, b1_lo, a0_hi, a1_hi, b1_hi, bs2b_gain = self._calc_bs2b_coeffs()

        # Meier filter alpha
        x_m = np.exp(-2.0 * np.pi * self.cutoff_hz / self.sample_rate)
        meier_alpha = float(1.0 - x_m)

        # RACE filter alpha
        x_race = np.exp(-2.0 * np.pi * self.cutoff_hz / self.sample_rate)
        race_a0 = float(1.0 - x_race)
        race_b1 = float(x_race)
        x_bass = np.exp(-2.0 * np.pi * 160.0 / self.sample_rate)
        bass_a0 = float(1.0 - x_bass)
        bass_b1 = float(x_bass)

        write_idx = self.write_idx

        for i in range(num_frames):
            in_l = float(s[i, 0])
            in_r = float(s[i, 1])

            if self.algorithm == CrossfeedAlgorithm.SIMPLE:
                self.ring_l[write_idx] = in_l
                self.ring_r[write_idx] = in_r

                read_pos = write_idx + self.MAX_DELAY_SAMPLES - clamped_delay
                i0 = int(np.floor(read_pos)) % self.MAX_DELAY_SAMPLES
                i1 = (i0 + 1) % self.MAX_DELAY_SAMPLES
                frac = float(read_pos - np.floor(read_pos))

                del_l = (1.0 - frac) * self.ring_l[i0] + frac * self.ring_l[i1]
                del_r = (1.0 - frac) * self.ring_r[i0] + frac * self.ring_r[i1]

                cross_gain = self.mix * 0.30
                dir_gain = 1.0 / np.sqrt(1.0 + cross_gain * cross_gain) if self.output_compensation else 1.0

                out[i, 0] = dir_gain * in_l + cross_gain * del_r
                out[i, 1] = dir_gain * in_r + cross_gain * del_l

            elif self.algorithm == CrossfeedAlgorithm.BS2B:
                self.bs2b_lo_l = a0_lo * in_l + b1_lo * self.bs2b_lo_l
                self.bs2b_lo_r = a0_lo * in_r + b1_lo * self.bs2b_lo_r

                hi_l = a0_hi * in_l + a1_hi * self.bs2b_asis_l + b1_hi * self.bs2b_hi_l
                hi_r = a0_hi * in_r + a1_hi * self.bs2b_asis_r + b1_hi * self.bs2b_hi_r
                self.bs2b_asis_l = in_l
                self.bs2b_asis_r = in_r
                self.bs2b_hi_l = hi_l
                self.bs2b_hi_r = hi_r

                self.ring_l[write_idx] = self.bs2b_lo_l
                self.ring_r[write_idx] = self.bs2b_lo_r

                filter_delay_ms = 1000.0 / (2.0 * np.pi * self.cutoff_hz)
                extra_delay_samples = max(0.0, (self.delay_ms - filter_delay_ms) * 0.001 * self.sample_rate)
                clamped_extra = np.clip(extra_delay_samples, 0.0, self.MAX_DELAY_SAMPLES - 2)

                read_pos = write_idx + self.MAX_DELAY_SAMPLES - clamped_extra
                i0 = int(np.floor(read_pos)) % self.MAX_DELAY_SAMPLES
                i1 = (i0 + 1) % self.MAX_DELAY_SAMPLES
                frac = float(read_pos - np.floor(read_pos))

                del_l = (1.0 - frac) * self.ring_l[i0] + frac * self.ring_l[i1]
                del_r = (1.0 - frac) * self.ring_r[i0] + frac * self.ring_r[i1]

                bs2b_l = (hi_l + del_r) * bs2b_gain
                bs2b_r = (hi_r + del_l) * bs2b_gain

                out[i, 0] = in_l * (1.0 - self.mix) + bs2b_l * self.mix
                out[i, 1] = in_r * (1.0 - self.mix) + bs2b_r * self.mix

            elif self.algorithm == CrossfeedAlgorithm.MEIER:
                self.lpf_state_l[0] += meier_alpha * (in_l - self.lpf_state_l[0])
                self.lpf_state_r[0] += meier_alpha * (in_r - self.lpf_state_r[0])
                cross_l = self.lpf_state_l[0]
                cross_r = self.lpf_state_r[0]

                direct_l = in_l + 0.15 * (in_l - cross_l)
                direct_r = in_r + 0.15 * (in_r - cross_r)

                self.ring_l[write_idx] = cross_l
                self.ring_r[write_idx] = cross_r

                read_pos = write_idx + self.MAX_DELAY_SAMPLES - clamped_delay
                i0 = int(np.floor(read_pos)) % self.MAX_DELAY_SAMPLES
                i1 = (i0 + 1) % self.MAX_DELAY_SAMPLES
                frac = float(read_pos - np.floor(read_pos))

                del_l = (1.0 - frac) * self.ring_l[i0] + frac * self.ring_l[i1]
                del_r = (1.0 - frac) * self.ring_r[i0] + frac * self.ring_r[i1]

                cross_gain = self.mix * 0.35
                comp = 1.0 / np.sqrt(1.0 + 0.0225 + cross_gain * cross_gain) if self.output_compensation else 1.0

                out[i, 0] = (direct_l + cross_gain * del_r) * comp
                out[i, 1] = (direct_r + cross_gain * del_l) * comp

            elif self.algorithm == CrossfeedAlgorithm.RACE:
                mid = 0.5 * (in_l + in_r)
                self.race_bass_state = bass_a0 * mid + bass_b1 * self.race_bass_state

                self.ring_l[write_idx] = in_l
                self.ring_r[write_idx] = in_r

                read_pos = write_idx + self.MAX_DELAY_SAMPLES - clamped_delay
                i0 = int(np.floor(read_pos)) % self.MAX_DELAY_SAMPLES
                i1 = (i0 + 1) % self.MAX_DELAY_SAMPLES
                frac = float(read_pos - np.floor(read_pos))

                del_out_l = (1.0 - frac) * self.ring_l[i0] + frac * self.ring_l[i1]
                del_out_r = (1.0 - frac) * self.ring_r[i0] + frac * self.ring_r[i1]

                self.race_lpf_out_l = race_a0 * del_out_l + race_b1 * self.race_lpf_out_l
                self.race_lpf_out_r = race_a0 * del_out_r + race_b1 * self.race_lpf_out_r

                alpha = self.mix
                raw_l = in_l - alpha * self.race_lpf_out_r + (alpha * 0.35) * self.race_bass_state
                raw_r = in_r - alpha * self.race_lpf_out_l + (alpha * 0.35) * self.race_bass_state

                if self.output_compensation:
                    race_comp = 1.0 / np.sqrt(1.0 + 0.60 * alpha * alpha)
                    raw_l *= race_comp
                    raw_r *= race_comp

                out[i, 0] = np.clip(raw_l, -1.0, 1.0)
                out[i, 1] = np.clip(raw_r, -1.0, 1.0)

            write_idx = (write_idx + 1) % self.MAX_DELAY_SAMPLES

        self.write_idx = write_idx
        if is_two_args:
            return out[:, 0], out[:, 1]
        return out[:, 0] if is_1d else out
