"""
Audio Clarity & High-Frequency Enhancer Mathematical Modeling
=============================================================

Creators & Historical Foundations:
----------------------------------
- **Transient Pre-Emphasis & Differential Dynamics**: Ruben Tilgner
  (SPL Transient Designer, Sound Performance Lab, 1998).
- **Ultra-High Frequency Air Band**: Clif Maag
  (Maag Audio EQ4 Air Band, 1993); Peter J. Baxandall (Negative feedback tone control, 1952).
- **Subtractive Phase-Aligned Crossover**: Siegfried Linkwitz & Russ Riley
  ("Active Crossover Networks for Noncoincident Drivers", JAES, 1976).
- **Psychoacoustic Aural Exciter**: Curt Knoppel & Marvin Caesar
  (Aphex Systems Aural Exciter Type A, US Patent 4,150,253, 1975).

Mathematical Topologies
-----------------------
1. **Transient Crisp (Sample-Rate Scaled Differentiator + 18 kHz Reconstruction LPF)**:
   Extracts instantaneous rate-of-change (dx/dt) normalized to 48 kHz calibration:
       diff[n] = (x[n] - x[n-1]) * (intensity * 1.5) * (fs / 48000)
       sharp[n] = x[n] + diff[n]
   Followed by a 1st-order anti-aliasing reconstruction LPF at min(18 kHz, 0.45*fs):
       gamma = cos(w0) / (1 + sin(w0))
       y[n] = sharp[n] * 0.5*(1 - gamma) + state[n-1]
       state[n] = sharp[n] * 0.5*(1 - gamma) - y[n] * (-gamma)

2. **Air Shelf (12 kHz High-Shelf Biquad)**:
   RBJ high-shelf biquad at 12 kHz providing up to +8 dB ultra-high harmonic sparkle.

3. **Presence Exciter (3-Way Subtractive Flat-Sum Crossover)**:
   Splits audio into Low (<120 Hz, Butterworth LPF) and High (>1200 Hz, Butterworth HPF).
   Derives Mid channel by exact algebraic subtraction:
       mid[n] = x[n] - low[n] - high[n]   (guarantees 100% phase-aligned flat summation!)
       y[n] = low[n] + mid[n] * (1.0 + intensity * 0.4) + high[n] * (1.0 + intensity * 0.8)

4. **Harmonic Brilliance (Aphex-Style Non-Linear Aural Exciter)**:
   High-pass sidechain at 3.5 kHz -> 2x/4x oversampled non-linear cubic/quadratic generator:
       c = 2.2 * hp
       sat = tanh(c) + 0.25 * hp^2
   Re-injected into dry signal: y[n] = x[n] + sat[n] * (intensity * 0.45).
"""

from enum import Enum
import numpy as np

from .biquad import make_biquad, BiquadFilterType
from .oversampler import PolyphaseOversampler2x, PolyphaseOversampler4x


class AudioClarityProfile(str, Enum):
    TRANSIENT_CRISP = "transient_crisp"
    AIR_SHELF = "air_shelf"
    PRESENCE_EXCITER = "presence_exciter"
    HARMONIC_BRILLIANCE = "harmonic_brilliance"

    # Convenient alias
    VOCAL_PRESENCE = "presence_exciter"


class AudioClarityDSP:
    """
    High-frequency audio clarity and psychoacoustic exciter suite.
    """

    def __init__(
        self,
        sample_rate: float = 48000.0,
        profile: AudioClarityProfile | str = AudioClarityProfile.TRANSIENT_CRISP,
        intensity: float = 0.5,
        oversampling_factor: int = 2
    ):
        self.sample_rate = float(sample_rate)
        self.profile = AudioClarityProfile(profile)
        self.intensity = float(np.clip(intensity, 0.0, 1.0))
        self.oversampling_factor = int(oversampling_factor)

        self.oversampler_2x = PolyphaseOversampler2x(self.sample_rate)
        self.oversampler_4x = PolyphaseOversampler4x(self.sample_rate)

        self.reset()

    def reset(self):
        self.oversampler_2x.reset()
        self.oversampler_4x.reset()

        # Transient Crisp states
        self.prev_x_l = self.prev_x_r = 0.0
        self.smooth_state_l = self.smooth_state_r = 0.0

        # Air Shelf filter
        shelf_gain = self.intensity * 8.0
        self.air_shelf = make_biquad(
            BiquadFilterType.HIGHSHELF, 12000.0, gain_db=shelf_gain, q=0.7071, sample_rate=self.sample_rate
        )

        # 3-Way Crossover filters
        self.lp_120 = make_biquad(BiquadFilterType.LOWPASS, 120.0, q=0.7071, sample_rate=self.sample_rate)
        self.hp_1200 = make_biquad(BiquadFilterType.HIGHPASS, 1200.0, q=0.7071, sample_rate=self.sample_rate)

        # Harmonic Brilliance 3.5 kHz HPF sidechain
        self.hp_brill = make_biquad(BiquadFilterType.HIGHPASS, 3500.0, q=0.7071, sample_rate=self.sample_rate)

    def _process_transient_crisp(self, signal: np.ndarray) -> np.ndarray:
        num_frames = signal.shape[0]
        out = np.zeros_like(signal)
        diff_scale = self.intensity * 1.5 * (self.sample_rate / 48000.0)

        # 1st-order smoothing LPF at 18 kHz
        fc = min(18000.0, self.sample_rate * 0.45)
        w0 = 2.0 * np.pi * fc / self.sample_rate
        gamma = float(np.cos(w0) / (1.0 + np.sin(w0)))
        b0 = (1.0 - gamma) * 0.5
        b1 = b0
        a1 = -gamma

        prev_l = self.prev_x_l
        prev_r = self.prev_x_r
        state_l = self.smooth_state_l
        state_r = self.smooth_state_r

        for n in range(num_frames):
            in_l = float(signal[n, 0])
            in_r = float(signal[n, 1])

            sharp_l = in_l + (in_l - prev_l) * diff_scale
            sharp_r = in_r + (in_r - prev_r) * diff_scale
            prev_l = in_l
            prev_r = in_r

            out_l = sharp_l * b0 + state_l
            state_l = sharp_l * b1 - out_l * a1

            out_r = sharp_r * b0 + state_r
            state_r = sharp_r * b1 - out_r * a1

            out[n, 0] = out_l
            out[n, 1] = out_r

        self.prev_x_l = prev_l
        self.prev_x_r = prev_r
        self.smooth_state_l = state_l
        self.smooth_state_r = state_r
        return out

    def _process_presence_exciter(self, signal: np.ndarray) -> np.ndarray:
        low = self.lp_120.process(signal)
        high = self.hp_1200.process(signal)
        # Subtractive phase-aligned mid channel
        mid = signal - low - high

        mid_gain = 1.0 + self.intensity * 0.4
        high_gain = 1.0 + self.intensity * 0.8
        return low + (mid * mid_gain) + (high * high_gain)

    def _process_harmonic_brilliance(self, signal: np.ndarray) -> np.ndarray:
        # 1. 3.5 kHz Highpass sidechain filter
        sidechain = self.hp_brill.process(signal)

        # 2. Non-linear saturation kernel
        def saturate(samples: np.ndarray) -> np.ndarray:
            c = samples * 2.2
            return np.tanh(c) + 0.25 * (samples * samples)

        eff_os = self.oversampling_factor
        if eff_os == 4:
            sat_sc = self.oversampler_4x.process(sidechain, saturate)
        elif eff_os == 2:
            sat_sc = self.oversampler_2x.process(sidechain, saturate)
        else:
            sat_sc = saturate(sidechain)

        # 3. Mix back into dry signal
        mix = self.intensity * 0.45
        return signal + sat_sc * mix

    def process(self, signal: np.ndarray) -> np.ndarray:
        s = np.asarray(signal, dtype=np.float32)
        is_1d = (s.ndim == 1)
        if is_1d:
            s = np.column_stack([s, s])

        if self.profile == AudioClarityProfile.TRANSIENT_CRISP:
            res = self._process_transient_crisp(s)
        elif self.profile == AudioClarityProfile.AIR_SHELF:
            res = self.air_shelf.process(s)
        elif self.profile == AudioClarityProfile.PRESENCE_EXCITER:
            res = self._process_presence_exciter(s)
        elif self.profile == AudioClarityProfile.HARMONIC_BRILLIANCE:
            res = self._process_harmonic_brilliance(s)
        else:
            res = s

        return res[:, 0] if is_1d else res
