"""
Subsonic Filter: 18 Hz Butterworth DC & Turntable Rumble Protection Filter
==========================================================================

Mathematical Formulation:
-------------------------
The subsonic filter removes sub-audible low-frequency rumble ($< 20\\,\\text{Hz}$),
DC offsets, tonearm mechanical resonance ($4$–$12\\,\\text{Hz}$), and microphone wind pops.
By stripping inaudible high-amplitude infrasonic energy before downstream non-linear processors
(such as harmonic exciters and analog tube models), it preserves DAC headroom and protects
transducer voice coils from over-excursion distortion.

1. Continuous Analog Butterworth Prototype:
   A 2nd-order high-pass transfer function with Butterworth alignment ($Q = \\frac{1}{\\sqrt{2}} \\approx 0.7071068$):
   $$H(s) = \\frac{s^2}{s^2 + \\frac{\\omega_0}{Q} s + \\omega_0^2}$$
   where $\\omega_0 = 2\\pi f_0$ ($f_0 = 18.0\\,\\text{Hz}$).

2. Bilinear Transform with Pre-Warping:
   Substituting $s = \\frac{2}{T} \\frac{1 - z^{-1}}{1 + z^{-1}}$ where $T = 1 / f_s$:
   $$\\omega_d = 2\\pi \\frac{f_0}{f_s}, \\quad \\alpha = \\frac{\\sin(\\omega_d)}{2 Q}, \\quad a_0 = 1 + \\alpha$$
   Digital Biquad Coefficients:
   $$b_0 = \\frac{1 + \\cos(\\omega_d)}{2 a_0}, \\quad b_1 = -\\frac{1 + \\cos(\\omega_d)}{a_0} = -2 b_0, \\quad b_2 = \\frac{1 + \\cos(\\omega_d)}{2 a_0} = b_0$$
   $$a_1 = -\\frac{2 \\cos(\\omega_d)}{a_0}, \\quad a_2 = \\frac{1 - \\alpha}{a_0}$$

3. Transposed Direct Form II (TDF2) Realization:
   For optimal numerical robustness and resistance to coefficient quantization at very low frequencies ($18\\,\\text{Hz} \\ll f_s$):
   $$y[n] = b_0 x[n] + s_1[n-1]$$
   $$s_1[n] = b_1 x[n] - a_1 y[n] + s_2[n-1]$$
   $$s_2[n] = b_2 x[n] - a_2 y[n]$$

Historical Attribution & Creators:
----------------------------------
- **Stephen Butterworth** (1885–1958):
  British physicist and mathematician at the Admiralty Research Laboratory.
  Pioneered the mathematically "maximally flat" passband filter synthesis:
  "On the Theory of Filter Amplifiers", *Experimental Wireless and the Wireless Engineer*,
  Vol. 7, No. 85, pp. 536–541, October 1930.
"""

from typing import Tuple
import numpy as np


class SubsonicFilter:
    """
    Mathematical and functional model of the 18 Hz Subsonic Rumble Filter.
    
    Attributes:
        sample_rate: Sampling frequency in Hz (e.g. 48000 Hz).
        cutoff_hz: Highpass cutoff frequency (nominally 18.0 Hz).
        enabled: Filter bypass toggle.
    """

    def __init__(self, sample_rate: float = 48000.0, cutoff_hz: float = 18.0) -> None:
        self.sample_rate = sample_rate
        self.cutoff_hz = cutoff_hz
        self.enabled = True
        self._update_coefficients()
        self.reset()

    def reset(self) -> None:
        """Reset internal TDF2 state variables."""
        self.s1 = 0.0
        self.s2 = 0.0

    def _update_coefficients(self) -> None:
        q = 0.7071067811865475  # 1/sqrt(2) Butterworth
        w0 = 2.0 * np.pi * self.cutoff_hz / self.sample_rate
        w0 = np.clip(w0, 1e-4, np.pi * 0.95)

        cos_w0 = np.cos(w0)
        sin_w0 = np.sin(w0)
        alpha = sin_w0 / (2.0 * q)

        a0 = 1.0 + alpha
        self.b0 = float(((1.0 + cos_w0) / 2.0) / a0)
        self.b1 = float((-(1.0 + cos_w0)) / a0)
        self.b2 = float(((1.0 + cos_w0) / 2.0) / a0)
        self.a1 = float((-2.0 * cos_w0) / a0)
        self.a2 = float((1.0 - alpha) / a0)

    def set_sample_rate(self, sample_rate: float) -> None:
        self.sample_rate = sample_rate
        self._update_coefficients()

    def process_sample(self, x: float) -> float:
        """Process a single audio sample through Transposed Direct Form II."""
        if not self.enabled:
            return x
        y = self.b0 * x + self.s1
        self.s1 = self.b1 * x - self.a1 * y + self.s2
        self.s2 = self.b2 * x - self.a2 * y
        return y

    def process(self, x: np.ndarray) -> np.ndarray:
        """Process an array of audio samples."""
        if not self.enabled:
            return x.copy()
        out = np.zeros_like(x, dtype=np.float64)
        for i in range(len(x)):
            out[i] = self.process_sample(float(x[i]))
        return out.astype(x.dtype)

    def frequency_response(self, frequencies: np.ndarray) -> Tuple[np.ndarray, np.ndarray]:
        """Compute complex frequency response across specified frequencies."""
        w = 2.0 * np.pi * frequencies / self.sample_rate
        ejw = np.exp(-1j * w)
        ejw2 = np.exp(-2j * w)

        num = self.b0 + self.b1 * ejw + self.b2 * ejw2
        den = 1.0 + self.a1 * ejw + self.a2 * ejw2
        h = num / den

        magnitude_db = 20.0 * np.log10(np.maximum(np.abs(h), 1e-12))
        phase_rad = np.angle(h)
        return magnitude_db, phase_rad
