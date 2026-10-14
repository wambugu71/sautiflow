"""
Audiophile 3-Band Tone Tuning Crossover Mathematical Modeling
============================================================

Theoretical Foundation & Audiophile Ethics:
-------------------------------------------
- **Linkwitz-Riley 4th Order (LR4)**: Siegfried Linkwitz & Russ Riley (1976),
  "Active Crossover Networks for Noncoincident Drivers", JAES.
- **Phase-Compensated 3-Way Summation**: By adding a 2nd-order All-Pass filter (AP2)
  tuned to f_high into the Low branch:
      H_low(s)  = LP1(s, f_low) * AP2(s, f_high)
      H_mid(s)  = HP1(s, f_low) * LP2(s, f_high)
      H_high(s) = HP1(s, f_low) * HP2(s, f_high)
- **Unity Gain Transparency**:
      H_sum(s) = H_low + H_mid + H_high = AP1(s, f_low) * AP2(s, f_high)
      |H_sum(j*w)| == 1.000000000 (0.000 dB ripple across 20 Hz - 20 kHz).
- **Zero Dynamic Pumping**: Pure LTI filter network, preserving micro-dynamics,
  crest factor, and transient impact without compression or intermodulation distortion.
"""

from typing import Optional, Tuple
import numpy as np
from scipy import signal


class ToneCrossoverDSP:
    """
    Audiophile 3-Band Phase-Compensated Linkwitz-Riley 4th-Order (LR4) Tone Crossover.
    """

    def __init__(
        self,
        sample_rate: float = 48000.0,
        bass_gain_db: float = 0.0,
        mid_gain_db: float = 0.0,
        treble_gain_db: float = 0.0,
        low_crossover_hz: float = 250.0,
        high_crossover_hz: float = 3200.0,
    ):
        self.sample_rate = float(sample_rate)
        self.bass_gain_db = float(bass_gain_db)
        self.mid_gain_db = float(mid_gain_db)
        self.treble_gain_db = float(treble_gain_db)
        self.low_crossover_hz = float(low_crossover_hz)
        self.high_crossover_hz = float(high_crossover_hz)
        self.enabled = True
        self.reset()

    def reset(self):
        self._update_filters()

    def set_gains_db(self, bass_db: float, mid_db: float, treble_db: float):
        self.bass_gain_db = float(np.clip(bass_db, -15.0, 15.0))
        self.mid_gain_db = float(np.clip(mid_db, -15.0, 15.0))
        self.treble_gain_db = float(np.clip(treble_db, -15.0, 15.0))

    def set_crossover_frequencies(self, low_hz: float, high_hz: float):
        self.low_crossover_hz = float(np.clip(low_hz, 60.0, 1000.0))
        self.high_crossover_hz = float(np.clip(high_hz, 1200.0, 10000.0))
        self._update_filters()

    def _update_filters(self):
        fs = self.sample_rate
        f1 = self.low_crossover_hz
        f2 = self.high_crossover_hz

        # Butterworth 2nd order (Q = 1/sqrt(2))
        self.b_lp1, self.a_lp1 = signal.butter(2, f1, btype='low', fs=fs)
        self.b_hp1, self.a_hp1 = signal.butter(2, f1, btype='high', fs=fs)
        self.b_lp2, self.a_lp2 = signal.butter(2, f2, btype='low', fs=fs)
        self.b_hp2, self.a_hp2 = signal.butter(2, f2, btype='high', fs=fs)

        # 2nd-order All-Pass at f2 for phase matching on low branch
        w0 = 2.0 * np.pi * f2 / fs
        alpha = np.sin(w0) / np.sqrt(2.0)
        self.b_ap2 = np.array([1.0 - alpha, -2.0 * np.cos(w0), 1.0 + alpha]) / (1.0 + alpha)
        self.a_ap2 = np.array([1.0 + alpha, -2.0 * np.cos(w0), 1.0 - alpha]) / (1.0 + alpha)

    def process(self, signal_in: np.ndarray, right: Optional[np.ndarray] = None) -> np.ndarray:
        if not self.enabled:
            if right is not None:
                return np.column_stack([signal_in, right]).astype(np.float32)
            return signal_in.astype(np.float32)

        if right is not None:
            s = np.column_stack([signal_in, right]).astype(np.float64)
            is_two_args = True
        else:
            s = np.asarray(signal_in, dtype=np.float64)
            is_two_args = False

        is_1d = (s.ndim == 1)
        if is_1d:
            s = s[:, np.newaxis]

        channels = s.shape[1]
        out = np.zeros_like(s)

        g_low = 10.0 ** (self.bass_gain_db * 0.05)
        g_mid = 10.0 ** (self.mid_gain_db * 0.05)
        g_high = 10.0 ** (self.treble_gain_db * 0.05)

        for c in range(channels):
            x = s[:, c]

            # LR4 stage 1 (cascaded pair of Butterworth 2nd order)
            x_lp1 = signal.lfilter(self.b_lp1, self.a_lp1, signal.lfilter(self.b_lp1, self.a_lp1, x))
            x_hp1 = signal.lfilter(self.b_hp1, self.a_hp1, signal.lfilter(self.b_hp1, self.a_hp1, x))

            # Phase compensation for Low band
            x_low = signal.lfilter(self.b_ap2, self.a_ap2, x_lp1)

            # LR4 stage 2 on x_hp1
            x_mid = signal.lfilter(self.b_lp2, self.a_lp2, signal.lfilter(self.b_lp2, self.a_lp2, x_hp1))
            x_high = signal.lfilter(self.b_hp2, self.a_hp2, signal.lfilter(self.b_hp2, self.a_hp2, x_hp1))

            y = (x_low * g_low) + (x_mid * g_mid) + (x_high * g_high)
            out[:, c] = y

        if is_1d:
            out = out[:, 0]
        if is_two_args:
            return out[:, 0].astype(np.float32), out[:, 1].astype(np.float32)
        return out.astype(np.float32)
