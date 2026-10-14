"""
Downward Expander & Adaptive Noise Reducer Mathematical Modeling
================================================================

Creators & Historical Foundations:
----------------------------------
- **Compander & Dynamic Range Expansion**: David E. Blackmer
  (dbx Inc., US Patent 3,688,220, 1972).
- **Spectral Noise Reduction & Threshold Dynamics**: Ray M. Dolby
  (Dolby Laboratories, "An Audio Noise Reduction System", JAES, 1967).

Mathematical Principles
-----------------------
Attenuates low-level background noise (tape hiss, vinyl surface groove friction, room ambiance)
whenever the audio signal envelope drops below a defined threshold:

1. **Sidechain Sub-Rumble High-Pass Filter**:
   2nd-order Butterworth HPF (typically 30–60 Hz) preventing turntable rumble, mechanical thumps,
   or HVAC infrasound from falsely keeping the expander open.

2. **Stereo-Linked Envelope Detector**:
   Peak detection across left and right channels with configured attack and release ballistics:
       peak = max(|sc_L|, |sc_R|)
       env[n] = env[n-1] + alpha_att * (peak - env[n-1])  if peak > env[n-1]
       env[n] = env[n-1] + alpha_rel * (peak - env[n-1])  otherwise

3. **Quadratic Soft-Knee Downward Expansion Curve**:
   Let env_db = 20*log10(env), threshold T, ratio R, and knee width K:
       delta = env_db - T
       If delta >= K / 2:
           GR_db = 0.0  (100% transparent unity gain)
       If -K / 2 < delta < K / 2:
           dist_from_upper = T + K/2 - env_db
           GR_db = -((R - 1.0) / (2.0 * K)) * (dist_from_upper^2)
       If delta <= -K / 2:
           GR_db = (R - 1.0) * delta

4. **Range / Floor Limit**:
   Clamps maximum attenuation: GR_db = clamp(GR_db, max_reduction_db, 0.0),
   avoiding unnatural "breathing" or dropouts into absolute digital black.
"""

from enum import Enum
from typing import Optional
import numpy as np

from .biquad import make_biquad, BiquadFilterType


class ExpanderPreset(str, Enum):
    VINYL_CLEAN = "vinyl_clean"
    TAPE_HISS = "tape_hiss"
    GENTLE_EXPANSION = "gentle_expansion"
    DYNAMIC_GATE = "dynamic_gate"
    CUSTOM = "custom"


class DownwardExpanderDSP:
    """
    Downward expander and adaptive background noise reducer with soft-knee dynamics.
    """

    def __init__(
        self,
        sample_rate: float = 48000.0,
        preset: ExpanderPreset | str = ExpanderPreset.VINYL_CLEAN,
        threshold_db: float = -52.0,
        ratio: float = 1.8,
        max_reduction_db: float = -16.0,
        attack_ms: float = 12.0,
        release_ms: float = 280.0,
        knee_db: float = 6.0,
        sidechain_hpf_hz: float = 50.0,
        range_limit_db: Optional[float] = None
    ):
        self.sample_rate = float(sample_rate)
        self.threshold_db = float(threshold_db)
        self.ratio = float(ratio)
        if range_limit_db is not None:
            max_reduction_db = range_limit_db
        self.max_reduction_db = float(max_reduction_db)
        self.attack_ms = float(attack_ms)
        self.release_ms = float(release_ms)
        self.knee_db = float(knee_db)
        self.sidechain_hpf_hz = float(sidechain_hpf_hz)

        self.preset = ExpanderPreset(preset)
        if self.preset != ExpanderPreset.CUSTOM:
            self.set_preset(self.preset)
        else:
            self.reset()

    def set_preset(self, preset: ExpanderPreset | str):
        p = ExpanderPreset(preset)
        self.preset = p
        if p == ExpanderPreset.VINYL_CLEAN:
            self.threshold_db = -52.0
            self.ratio = 1.8
            self.max_reduction_db = -16.0
            self.attack_ms = 12.0
            self.release_ms = 280.0
            self.knee_db = 6.0
            self.sidechain_hpf_hz = 50.0
        elif p == ExpanderPreset.TAPE_HISS:
            self.threshold_db = -50.0
            self.ratio = 2.0
            self.max_reduction_db = -18.0
            self.attack_ms = 10.0
            self.release_ms = 220.0
            self.knee_db = 6.0
            self.sidechain_hpf_hz = 40.0
        elif p == ExpanderPreset.GENTLE_EXPANSION:
            self.threshold_db = -46.0
            self.ratio = 1.4
            self.max_reduction_db = -12.0
            self.attack_ms = 20.0
            self.release_ms = 400.0
            self.knee_db = 8.0
            self.sidechain_hpf_hz = 30.0
        elif p == ExpanderPreset.DYNAMIC_GATE:
            self.threshold_db = -38.0
            self.ratio = 6.0
            self.max_reduction_db = -36.0
            self.attack_ms = 2.0
            self.release_ms = 100.0
            self.knee_db = 3.0
            self.sidechain_hpf_hz = 60.0

        self.reset()

    def reset(self):
        self.envelope = 0.0
        self.gain_linear = 1.0
        self.current_gr_db = 0.0

        self.alpha_att = 1.0 - np.exp(-1.0 / (self.sample_rate * (max(self.attack_ms, 0.1) * 0.001)))
        self.alpha_rel = 1.0 - np.exp(-1.0 / (self.sample_rate * (max(self.release_ms, 1.0) * 0.001)))

        if self.sidechain_hpf_hz >= 15.0:
            self.sc_hpf = make_biquad(
                BiquadFilterType.HIGHPASS, self.sidechain_hpf_hz, q=0.7071, sample_rate=self.sample_rate
            )
        else:
            self.sc_hpf = None

    def compute_gain_reduction(self, env_val: float) -> float:
        """Compute target downward expander gain reduction in dB."""
        half_knee = self.knee_db * 0.5
        no_reduction_lin = np.power(10.0, (self.threshold_db + half_knee) / 20.0)

        if env_val >= no_reduction_lin:
            return 0.0

        env_db = 20.0 * np.log10(max(env_val, 1e-6))
        delta = env_db - self.threshold_db

        if self.knee_db > 0.0 and -half_knee < delta < half_knee:
            dist_from_upper = self.threshold_db + half_knee - env_db
            target_gr = -((self.ratio - 1.0) / (2.0 * self.knee_db)) * (dist_from_upper ** 2)
        elif delta <= (-half_knee if self.knee_db > 0.0 else 0.0):
            target_gr = (self.ratio - 1.0) * delta
        else:
            target_gr = 0.0

        return float(np.clip(target_gr, self.max_reduction_db, 0.0))

    def gain_computer_db(self, in_db: float) -> float:
        """Compute downward expander gain reduction in dB for a decibel input level."""
        env_val = float(np.power(10.0, in_db / 20.0))
        return self.compute_gain_reduction(env_val)

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

        num_frames = s.shape[0]
        out = np.zeros_like(s)

        # Sidechain filter
        sc = self.sc_hpf.process(s) if self.sc_hpf is not None else s

        env = self.envelope
        gain_lin = self.gain_linear
        smooth_coeff = 1.0 - np.exp(-1.0 / (0.020 * self.sample_rate))

        for i in range(num_frames):
            sc_l = abs(float(sc[i, 0]))
            sc_r = abs(float(sc[i, 1]))
            peak = max(sc_l, sc_r)

            env += (self.alpha_att if peak > env else self.alpha_rel) * (peak - env)

            gr_db = self.compute_gain_reduction(env)
            target_gain_lin = float(np.power(10.0, gr_db / 20.0))

            # Smooth linear gain
            gain_lin += smooth_coeff * (target_gain_lin - gain_lin)

            out[i, 0] = s[i, 0] * gain_lin
            out[i, 1] = s[i, 1] * gain_lin

        self.envelope = env
        self.gain_linear = gain_lin
        self.current_gr_db = 20.0 * np.log10(max(gain_lin, 1e-4))

        if is_two_args:
            return out[:, 0], out[:, 1]
        return out[:, 0] if is_1d else out
