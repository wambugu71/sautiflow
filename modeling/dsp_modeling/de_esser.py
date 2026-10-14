"""
De-Esser Split-Band & Wideband Mathematical Modeling
====================================================

Creators & Historical Foundations:
----------------------------------
- **Early Film Optical Sibilance Attenuation**: Douglas Shearer
  (Metro-Goldwyn-Mayer Sound Department, 1930s).
- **VCA Dynamic Sibilance Limiting**: David E. Blackmer
  (dbx 902 De-Esser, dbx Inc., 1970s).
- **Split-Band Broadcast Sibilance Control**: Robert Orban
  (Orban Associates / Optimod-FM 8000A, 1975).

Mathematical Principles
-----------------------
Eliminates harsh, fatiguing vocal sibilance ("s", "sh", "ch", "z") without dulling natural speech:

1. **Sibilance Sidechain Extraction**:
   2nd-order Butterworth High-Pass Filter (Direct Form I in 64-bit precision) isolating 4–9 kHz:
       sc_y[n] = (b0*x[n] + b1*x[n-1] + b2*x[n-2] - a1*sc_y[n-1] - a2*sc_y[n-2])

2. **Asymmetric Envelope Ballistics**:
   Ultra-fast attack (~1 ms) captures sharp consonant onset; smooth release (~35 ms) prevents modulation distortion:
       alpha_att = 1 - exp(-1 / (fs * tau_att))
       alpha_rel = 1 - exp(-1 / (fs * tau_rel))
       env[n] = env[n-1] + alpha_att * (|sc[n]| - env[n-1])  if |sc[n]| > env[n-1]
       env[n] = env[n-1] + alpha_rel * (|sc[n]| - env[n-1])  otherwise

3. **C1 Continuous 4 dB Soft Knee Gain Reduction**:
   Let env_db = 20*log10(env), threshold T, ratio R, and knee width W = 4 dB:
       delta = env_db - T
       If delta <= -W/2:
           GR_db = 0.0
       If -W/2 < delta < W/2:
           GR_db = ((R - 1) / (2 * W * R)) * (delta + W/2)^2
       If delta >= W/2:
           GR_db = ((R - 1) / R) * delta
       GR_db = clamp(GR_db, 0.0, max_reduction_db)

4. **Output Stage Modes**:
   - **SplitBand Mode**: Applies a dynamic RBJ high-shelf filter at the sibilance frequency
     with gain = -GR_db. Flat identity pass when inactive!
   - **WideBand Mode**: Attenuates full program audio: y[n] = x[n] * 10^(-GR_db / 20).
"""

from enum import Enum
from typing import Tuple
import numpy as np

from .biquad import make_biquad, BiquadFilterType


class DeEsserMode(str, Enum):
    SPLIT_BAND = "split_band"
    WIDE_BAND = "wide_band"


class DeEsserPreset(str, Enum):
    GENTLE_VOCAL = "gentle_vocal"
    AGGRESSIVE_SIBILANCE = "aggressive_sibilance"
    VINTAGE_WIDEBAND = "vintage_wideband"
    PODCAST_SPEECH = "podcast_speech"
    CUSTOM = "custom"


class DeEsserDSP:
    """
    Studio-grade split-band & wideband de-esser with sidechain filtering, soft-knee dynamics,
    and sub-block parameter updates.
    """

    def __init__(
        self,
        sample_rate: float = 48000.0,
        mode: DeEsserMode | str = DeEsserMode.SPLIT_BAND,
        frequency_hz: float = 5500.0,
        threshold_db: float = -22.0,
        ratio: float = 4.0,
        max_reduction_db: float = 12.0,
        attack_ms: float = 1.0,
        release_ms: float = 35.0,
        knee_db: float = 4.0
    ):
        self.sample_rate = float(sample_rate)
        self.mode = DeEsserMode(mode)
        self.frequency_hz = float(frequency_hz)
        self.threshold_db = float(threshold_db)
        self.ratio = float(ratio)
        self.max_reduction_db = float(max_reduction_db)
        self.attack_ms = float(attack_ms)
        self.release_ms = float(release_ms)
        self.knee_db = float(knee_db)

        self.reset()

    def reset(self):
        # Sidechain HPF filter
        self.sc_filter = make_biquad(
            BiquadFilterType.HIGHPASS, self.frequency_hz, q=0.7071, sample_rate=self.sample_rate
        )
        self.env_l = 0.0
        self.env_r = 0.0
        self.current_gr_db = 0.0

        # Ballistics
        self.alpha_att = 1.0 - np.exp(-1.0 / (self.sample_rate * (self.attack_ms * 0.001)))
        self.alpha_rel = 1.0 - np.exp(-1.0 / (self.sample_rate * (self.release_ms * 0.001)))

    def set_preset(self, preset: DeEsserPreset | str):
        p = DeEsserPreset(preset)
        if p == DeEsserPreset.GENTLE_VOCAL:
            self.mode = DeEsserMode.SPLIT_BAND
            self.frequency_hz = 5500.0
            self.threshold_db = -24.0
            self.ratio = 3.5
            self.max_reduction_db = 8.0
            self.attack_ms = 1.5
            self.release_ms = 40.0
        elif p == DeEsserPreset.AGGRESSIVE_SIBILANCE:
            self.mode = DeEsserMode.SPLIT_BAND
            self.frequency_hz = 6000.0
            self.threshold_db = -30.0
            self.ratio = 6.0
            self.max_reduction_db = 16.0
            self.attack_ms = 0.8
            self.release_ms = 30.0
        elif p == DeEsserPreset.VINTAGE_WIDEBAND:
            self.mode = DeEsserMode.WIDE_BAND
            self.frequency_hz = 5000.0
            self.threshold_db = -22.0
            self.ratio = 4.0
            self.max_reduction_db = 10.0
            self.attack_ms = 2.0
            self.release_ms = 50.0
        elif p == DeEsserPreset.PODCAST_SPEECH:
            self.mode = DeEsserMode.SPLIT_BAND
            self.frequency_hz = 4500.0
            self.threshold_db = -26.0
            self.ratio = 5.0
            self.max_reduction_db = 14.0
            self.attack_ms = 1.0
            self.release_ms = 35.0
        self.reset()

    def compute_knee_gain_reduction(self, env_peak: float) -> float:
        """Calculate target gain reduction in dB using a C1 continuous soft knee."""
        if env_peak < 1e-6:
            return 0.0

        env_db = 20.0 * np.log10(env_peak)
        delta = env_db - self.threshold_db
        half_knee = self.knee_db * 0.5

        if delta <= -half_knee:
            target_gr = 0.0
        elif delta < half_knee:
            # Quadratic knee curve
            factor = (self.ratio - 1.0) / (2.0 * self.knee_db * self.ratio)
            target_gr = factor * ((delta + half_knee) ** 2)
        else:
            # Linear compression
            target_gr = ((self.ratio - 1.0) / self.ratio) * delta

        return float(np.clip(target_gr, 0.0, self.max_reduction_db))

    def process(self, signal: np.ndarray, sub_block_size: int = 32) -> np.ndarray:
        s = np.asarray(signal, dtype=np.float32)
        is_1d = (s.ndim == 1)
        if is_1d:
            s = np.column_stack([s, s])

        num_frames = s.shape[0]
        out = np.zeros_like(s)

        # 1. Filter sidechain
        sc = self.sc_filter.process(s)

        env_l = self.env_l
        env_r = self.env_r
        current_gr_db = self.current_gr_db

        active_shelf = make_biquad(
            BiquadFilterType.HIGHSHELF, self.frequency_hz, gain_db=0.0, q=0.7071, sample_rate=self.sample_rate
        )

        for i in range(num_frames):
            sc_abs_l = abs(float(sc[i, 0]))
            sc_abs_r = abs(float(sc[i, 1]))

            # Envelope follower
            env_l += (self.alpha_att if sc_abs_l > env_l else self.alpha_rel) * (sc_abs_l - env_l)
            env_r += (self.alpha_att if sc_abs_r > env_r else self.alpha_rel) * (sc_abs_r - env_r)
            env_peak = max(env_l, env_r)

            target_gr = self.compute_knee_gain_reduction(env_peak)
            # Smooth gain reduction
            current_gr_db += 0.05 * (target_gr - current_gr_db)

            in_l = float(s[i, 0])
            in_r = float(s[i, 1])

            if self.mode == DeEsserMode.SPLIT_BAND:
                if (i & (sub_block_size - 1)) == 0:
                    active_shelf = make_biquad(
                        BiquadFilterType.HIGHSHELF,
                        self.frequency_hz,
                        gain_db=-current_gr_db,
                        q=0.7071,
                        sample_rate=self.sample_rate
                    )
                out_l, out_r = active_shelf.process_sample_df1(in_l, in_r)
            else:
                lin_gain = float(np.power(10.0, -current_gr_db / 20.0))
                out_l = in_l * lin_gain
                out_r = in_r * lin_gain

            out[i, 0] = out_l
            out[i, 1] = out_r

        self.env_l = env_l
        self.env_r = env_r
        self.current_gr_db = current_gr_db

        return out[:, 0] if is_1d else out
