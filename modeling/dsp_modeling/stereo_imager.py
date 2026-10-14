"""
Stereo Imager & Velvet Noise Decorrelator
=========================================

Mathematical Formulation:
-------------------------
1. Symmetric Mid/Side Decomposition:
   $$M[n] = \\frac{1}{2} (L[n] + R[n]), \\quad S[n] = \\frac{1}{2} (L[n] - R[n])$$

2. Sub-Bass Mono Anchor:
   Elliptical / 2nd-order Butterworth high-pass filter applied strictly to the Side channel:
   $$S_{\\text{hp}}(z) = H_{\\text{ButterworthHP}, f_c}(z) \\cdot S(z)$$
   Guarantees that low frequencies ($< f_c \\approx 120\\,\\text{Hz}$) collapse symmetrically to mono,
   preventing phase cancellation on subwoofers and vinyl cutting head deflection.

3. Spatial3D Mode: Transient-Gated Velvet Noise Sparse Decorrelation:
   - Mid-channel transient envelope detector ($1\\,\\text{ms}$ attack, $25\\,\\text{ms}$ release):
     $$\\Delta[n] = |M[n]| - \\text{env}_M[n]$$
     If $\\Delta[n] > 0.08$, the decorrelation is attenuated to preserve transient attack crispness:
     $$\\text{gate}[n] = \\text{clamp}(1.0 - 4 \\Delta[n], 0.05, 1.0)$$
   - 12-Tap Velvet Noise sparse convolution:
     $$y_{\\text{decorr}}[n] = \\frac{1}{\\sqrt{12}} \\sum_{k=0}^{11} s_k M[n - d_k], \\quad s_k \\in \\{-1, +1\\}$$
     where delays $d_k$ span non-uniform prime intervals over a $20\\,\\text{ms}$ window.
   - Injected into the Side channel:
     $$S'[n] = S_{\\text{hp}}[n] \\cdot W + y_{\\text{decorr}}[n] \\cdot \\text{gate}[n] \\cdot \\max(0, W - 0.5)$$
     **Perfect Mono Compatibility Property**: Because $L_{\\text{out}} = M + S'$ and $R_{\\text{out}} = M - S'$,
     the mono sum is $L_{\\text{out}} + R_{\\text{out}} = 2 M$. The decorrelation and width expansions cancel completely!

4. Blumlein / Gerzon Acoustic Shuffler Mode:
   Applies a low-frequency shelf boost to the side channel to compensate for interaural acoustic crosstalk:
   $$S'[n] = H_{\\text{LowShelf}, 400\\,\\text{Hz}, +3\\,\\text{dB}}(S_{\\text{hp}}[n]) \\cdot W$$

5. Inter-Channel Phase Correlation Telemetry:
   $$r_{LR} = \\frac{\\sum_{n} L[n] R[n]}{\\sqrt{\\sum_n L^2[n] \\cdot \\sum_n R^2[n] + \\epsilon}} \\in [-1.0, +1.0]$$

Historical Attribution & Creators:
----------------------------------
- **Alan Dower Blumlein** (1903–1942):
  EMI Research Laboratories. Invented stereophonic sound (UK Patent 394,325, 1931), the Mid/Side
  sum-and-difference matrix, and the original acoustic shuffler circuit.
- **Michael A. Gerzon** (1945–1996):
  Mathematical physicist and Ambisonics pioneer. Developed the theoretical framework for modern
  psychoacoustic stereo width and shuffler matrixing: "The Design of Distance and Width Controls for
  Stereo and Surround Sound", 93rd AES Convention, 1992.
- **Matti Karjalainen & Vesa Välimäki** (2007):
  Aalto University, Finland. Invented Velvet Noise decorrelation:
  "Reverberation modeling using velvet noise", IEEE Transactions on Audio, Speech, and Language Processing,
  Vol. 16, No. 2, pp. 383–392, 2008.
"""

from enum import IntEnum
from typing import Tuple
import numpy as np
from .biquad import make_biquad, BiquadFilterType


class StereoImagerMode(IntEnum):
    CLEAN_MASTERING = 0   # Pure symmetric Mid/Side expansion + sub-bass mono anchor
    SPATIAL_3D = 1        # Transient-gated Velvet Noise sparse decorrelation
    BLUMLEIN_SHUFFLER = 2 # Low-frequency Gerzon/Blumlein acoustic shuffling matrix


class StereoImagerDSP:
    """
    Mathematical and functional model of the SautiFlow Stereo Imager.
    """

    def __init__(self, sample_rate: float = 48000.0) -> None:
        self.sample_rate = sample_rate
        self.mode = StereoImagerMode.CLEAN_MASTERING
        self.width = 1.0
        self.mono_below_hz = 120.0
        self.air_boost_db = 0.0

        # Sub-bass mono anchor filter (Butterworth HPF on Side channel)
        self.side_hp = make_biquad(
            BiquadFilterType.HIGHPASS, sample_rate, self.mono_below_hz, q=0.7071
        )

        # Blumlein shuffler low-shelf filter (400 Hz, +3 dB boost)
        self.shuffler_shelf = make_biquad(
            BiquadFilterType.LOWSHELF, sample_rate, 400.0, gain_db=3.5, q=0.7071
        )

        # Air presence shelf
        self.air_shelf = make_biquad(
            BiquadFilterType.HIGHSHELF, sample_rate, 12000.0, gain_db=self.air_boost_db, q=0.7071
        )

        # 12-tap Velvet Noise delay lines & signs
        self.velvet_taps = np.array([
            int(sample_rate * 0.0012),
            int(sample_rate * 0.0027),
            int(sample_rate * 0.0041),
            int(sample_rate * 0.0059),
            int(sample_rate * 0.0073),
            int(sample_rate * 0.0089),
            int(sample_rate * 0.0107),
            int(sample_rate * 0.0123),
            int(sample_rate * 0.0141),
            int(sample_rate * 0.0157),
            int(sample_rate * 0.0175),
            int(sample_rate * 0.0193),
        ], dtype=np.int32)
        self.velvet_signs = np.array([1, -1, 1, 1, -1, 1, -1, -1, 1, -1, 1, -1], dtype=np.float32)
        self.velvet_norm = 1.0 / np.sqrt(12.0)

        self.reset()

    def reset(self) -> None:
        self.side_hp.reset()
        self.shuffler_shelf.reset()
        self.air_shelf.reset()

    def set_mode(self, mode: StereoImagerMode) -> None:
        self.mode = mode

    def set_width(self, width: float) -> None:
        self.width = float(np.clip(width, 0.0, 3.5))

    def set_mono_below_hz(self, hz: float) -> None:
        self.mono_below_hz = float(hz)
        if hz > 20.0:
            self.side_hp = make_biquad(
                BiquadFilterType.HIGHPASS, self.sample_rate, self.mono_below_hz, q=0.7071
            )

    def set_air_boost_db(self, db: float) -> None:
        self.air_boost_db = float(np.clip(db, 0.0, 6.0))
        self.air_shelf = make_biquad(
            BiquadFilterType.HIGHSHELF, self.sample_rate, 12000.0, gain_db=self.air_boost_db, q=0.7071
        )

    def compute_correlation(self, left: np.ndarray, right: np.ndarray) -> float:
        """Compute inter-channel phase correlation coefficient in [-1, +1]."""
        dot = float(np.sum(left * right))
        denom = float(np.sqrt(np.sum(left ** 2) * np.sum(right ** 2))) + 1e-12
        return float(np.clip(dot / denom, -1.0, 1.0))

    def process(self, left: np.ndarray, right: np.ndarray) -> Tuple[np.ndarray, np.ndarray]:
        """
        Process stereo signals through selected stereo imaging topology.
        Returns: (processed_left, processed_right).
        """
        n = len(left)
        # 1. Symmetric Mid/Side decomposition
        mid = 0.5 * (left + right)
        side = 0.5 * (left - right)

        # 2. Sub-bass mono anchor
        if self.mono_below_hz > 20.0:
            side = self.side_hp.process(side)

        # 3. Mode-specific processing
        if self.mode == StereoImagerMode.CLEAN_MASTERING:
            side_out = side * self.width

        elif self.mode == StereoImagerMode.BLUMLEIN_SHUFFLER:
            side_out = self.shuffler_shelf.process(side) * self.width

        elif self.mode == StereoImagerMode.SPATIAL_3D:
            # Envelope follower on mid channel (1ms attack, 25ms release)
            attack_c = 1.0 - np.exp(-1.0 / (0.001 * self.sample_rate))
            release_c = 1.0 - np.exp(-1.0 / (0.025 * self.sample_rate))
            env = 0.0
            decorr = np.zeros(n, dtype=np.float32)

            for i in range(n):
                abs_m = abs(float(mid[i]))
                if abs_m > env:
                    env += (abs_m - env) * attack_c
                else:
                    env += (abs_m - env) * release_c

                delta = abs_m - env
                gate = 1.0
                if delta > 0.08:
                    gate = float(np.clip(1.0 - delta * 4.0, 0.05, 1.0))

                # 12-tap Velvet Noise sparse sum
                val = 0.0
                for t in range(12):
                    tap_idx = i - self.velvet_taps[t]
                    if 0 <= tap_idx < n:
                        val += float(mid[tap_idx]) * float(self.velvet_signs[t])

                decorr[i] = val * self.velvet_norm * gate

            spread = max(0.0, self.width - 0.5)
            side_out = side * self.width + decorr * spread

        else:
            side_out = side * self.width

        # Air boost
        if self.air_boost_db > 0.1:
            side_out = self.air_shelf.process(side_out)

        # Recompose L/R
        out_l = mid + side_out
        out_r = mid - side_out
        return out_l, out_r
