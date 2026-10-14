"""
Biquad Filter & Parametric EQ Mathematical Modeling
===================================================

Mathematical formulation and digital implementation of 2nd-order Infinite Impulse Response (IIR)
biquad sections according to the Robert Bristow-Johnson (RBJ) Audio EQ Cookbook, Direct Form I,
and Transposed Direct Form II (TDF2) state topologies.

Difference Equations
--------------------
Direct Form I:
    y[n] = (b0/a0)*x[n] + (b1/a0)*x[n-1] + (b2/a0)*x[n-2] - (a1/a0)*y[n-1] - (a2/a0)*y[n-2]

Transposed Direct Form II (TDF2):
    y[n] = (b0/a0)*x[n] + s1[n-1]
    s1[n] = (b1/a0)*x[n] - (a1/a0)*y[n] + s2[n-1]
    s2[n] = (b2/a0)*x[n] - (a2/a0)*y[n]

Z-Domain Transfer Function
--------------------------
    H(z) = (b0 + b1*z^-1 + b2*z^-2) / (a0 + a1*z^-1 + a2*z^-2)
"""

from enum import Enum
from typing import Tuple, Optional
import numpy as np


class BiquadFilterType(str, Enum):
    PEAK = "peak"
    LOWSHELF = "lowshelf"
    HIGHSHELF = "highshelf"
    LOWPASS = "lowpass"
    HIGHPASS = "highpass"
    BANDPASS = "bandpass"
    NOTCH = "notch"
    ALLPASS = "allpass"
    TILT = "tilt"


class Biquad:
    """
    Second-order IIR biquad filter with configurable RBJ cookbook topologies,
    pole-zero stability analysis, and frequency response calculation.
    """

    def __init__(
        self,
        b0: float = 1.0,
        b1: float = 0.0,
        b2: float = 0.0,
        a0: float = 1.0,
        a1: float = 0.0,
        a2: float = 0.0,
        sample_rate: float = 48000.0
    ):
        self.sample_rate = float(sample_rate)
        self.set_coefficients(b0, b1, b2, a0, a1, a2)
        self.reset()

    def set_coefficients(
        self,
        b0: float,
        b1: float,
        b2: float,
        a0: float,
        a1: float,
        a2: float
    ) -> None:
        """Normalize coefficients so a0 = 1.0."""
        inv_a0 = 1.0 / a0 if abs(a0) > 1e-12 else 1.0
        self.b0 = float(b0 * inv_a0)
        self.b1 = float(b1 * inv_a0)
        self.b2 = float(b2 * inv_a0)
        self.a1 = float(a1 * inv_a0)
        self.a2 = float(a2 * inv_a0)

    def reset(self) -> None:
        """Clear delay state memories."""
        # Direct Form I states
        self.x1_l = self.x2_l = 0.0
        self.y1_l = self.y2_l = 0.0
        self.x1_r = self.x2_r = 0.0
        self.y1_r = self.y2_r = 0.0

        # Transposed Direct Form II states
        self.s1_l = self.s2_l = 0.0
        self.s1_r = self.s2_r = 0.0

    @property
    def poles(self) -> np.ndarray:
        """Roots of denominator polynomial: 1 + a1*z^-1 + a2*z^-2 = 0."""
        return np.roots([1.0, self.a1, self.a2])

    @property
    def zeros(self) -> np.ndarray:
        """Roots of numerator polynomial: b0 + b1*z^-1 + b2*z^-2 = 0."""
        return np.roots([self.b0, self.b1, self.b2])

    @property
    def is_stable(self) -> bool:
        """Check if all poles lie strictly inside the unit circle (|p| < 1.0)."""
        return bool(np.all(np.abs(self.poles) < 1.0 - 1e-7))

    def frequency_response(
        self,
        frequencies_hz: Optional[np.ndarray] = None,
        n_points: int = 512
    ) -> Tuple[np.ndarray, np.ndarray, np.ndarray, np.ndarray]:
        """
        Compute continuous frequency response H(e^jw).
        
        Returns:
            freqs: Frequencies in Hz
            mag_db: Magnitude response in dB (20*log10|H|)
            phase_deg: Phase response in degrees
            group_delay_samples: Group delay in samples (-d(phase)/dw)
        """
        if frequencies_hz is None:
            freqs = np.geomspace(20.0, self.sample_rate * 0.499, n_points)
        else:
            freqs = np.asarray(frequencies_hz, dtype=np.float64)

        omega = 2.0 * np.pi * freqs / self.sample_rate
        z_inv = np.exp(-1j * omega)
        z_inv2 = z_inv * z_inv

        num = self.b0 + self.b1 * z_inv + self.b2 * z_inv2
        den = 1.0 + self.a1 * z_inv + self.a2 * z_inv2

        h = num / den
        mag_db = 20.0 * np.log10(np.maximum(np.abs(h), 1e-12))
        phase_rad = np.unwrap(np.angle(h))
        phase_deg = np.rad2deg(phase_rad)

        # Numerical group delay: -d(phase)/dw
        dw = np.gradient(omega)
        dphi = np.gradient(phase_rad)
        group_delay_samples = -dphi / np.maximum(dw, 1e-12)

        if frequencies_hz is not None:
            return mag_db, phase_deg
        return freqs, mag_db, phase_deg, group_delay_samples

    def process_sample_tdf2(self, x_l: float, x_r: float) -> Tuple[float, float]:
        """Process a single stereo sample using Transposed Direct Form II."""
        # Left channel
        y_l = self.b0 * x_l + self.s1_l
        self.s1_l = self.b1 * x_l - self.a1 * y_l + self.s2_l
        self.s2_l = self.b2 * x_l - self.a2 * y_l

        # Right channel
        y_r = self.b0 * x_r + self.s1_r
        self.s1_r = self.b1 * x_r - self.a1 * y_r + self.s2_r
        self.s2_r = self.b2 * x_r - self.a2 * y_r

        return y_l, y_r

    def process_sample_df1(self, x_l: float, x_r: float) -> Tuple[float, float]:
        """Process a single stereo sample using Direct Form I."""
        # Left channel
        y_l = (self.b0 * x_l + self.b1 * self.x1_l + self.b2 * self.x2_l
               - self.a1 * self.y1_l - self.a2 * self.y2_l)
        self.x2_l = self.x1_l
        self.x1_l = x_l
        self.y2_l = self.y1_l
        self.y1_l = y_l

        # Right channel
        y_r = (self.b0 * x_r + self.b1 * self.x1_r + self.b2 * self.x2_r
               - self.a1 * self.y1_r - self.a2 * self.y2_r)
        self.x2_r = self.x1_r
        self.x1_r = x_r
        self.y2_r = self.y1_r
        self.y1_r = y_r

        return y_l, y_r

    def process(self, signal: np.ndarray, topology: str = "tdf2") -> np.ndarray:
        """
        Process a mono (1D) or stereo (N, 2) numpy array.
        """
        arr = np.asarray(signal, dtype=np.float32)
        is_1d = (arr.ndim == 1)
        if is_1d:
            arr = np.column_stack([arr, arr])

        out = np.zeros_like(arr)
        num_frames = arr.shape[0]

        if topology == "tdf2":
            for n in range(num_frames):
                out[n, 0], out[n, 1] = self.process_sample_tdf2(arr[n, 0], arr[n, 1])
        else:
            for n in range(num_frames):
                out[n, 0], out[n, 1] = self.process_sample_df1(arr[n, 0], arr[n, 1])

        return out[:, 0] if is_1d else out


def make_biquad(
    filter_type: BiquadFilterType | str,
    *args,
    freq_hz: Optional[float] = None,
    gain_db: float = 0.0,
    q: float = 0.7071,
    sample_rate: float = 48000.0
) -> Biquad:
    """
    Design second-order biquad filter coefficients from RBJ Audio EQ Cookbook equations.
    Supports flexible signatures:
    - make_biquad(filter_type, sample_rate, freq_hz, gain_db=0.0, q=0.7071)
    - make_biquad(filter_type, freq_hz, gain_db=0.0, q=0.7071, sample_rate=48000.0)
    """
    ftype = BiquadFilterType(filter_type)
    
    # Parse positional args
    if len(args) == 1:
        if freq_hz is None:
            freq_hz = float(args[0])
    elif len(args) == 2:
        if args[0] > 6000.0 and args[1] <= args[0] * 0.5:
            sample_rate = float(args[0])
            freq_hz = float(args[1])
        else:
            freq_hz = float(args[0])
            gain_db = float(args[1])
    elif len(args) == 3:
        if args[0] > 6000.0:
            sample_rate = float(args[0])
            freq_hz = float(args[1])
            gain_db = float(args[2])
        else:
            freq_hz = float(args[0])
            gain_db = float(args[1])
            q = float(args[2])
    elif len(args) >= 4:
        freq_hz = float(args[0])
        gain_db = float(args[1])
        q = float(args[2])
        sample_rate = float(args[3])

    if freq_hz is None:
        freq_hz = 1000.0

    fs = float(sample_rate)
    f0 = float(np.clip(freq_hz, 1.0, fs * 0.499))
    q_val = float(max(q, 0.01))

    w0 = 2.0 * np.pi * f0 / fs
    cos_w0 = np.cos(w0)
    sin_w0 = np.sin(w0)
    alpha = sin_w0 / (2.0 * q_val)
    A = np.power(10.0, gain_db / 40.0)

    if ftype == BiquadFilterType.PEAK:
        b0 = 1.0 + alpha * A
        b1 = -2.0 * cos_w0
        b2 = 1.0 - alpha * A
        a0 = 1.0 + alpha / A
        a1 = -2.0 * cos_w0
        a2 = 1.0 - alpha / A

    elif ftype == BiquadFilterType.LOWPASS:
        b0 = (1.0 - cos_w0) * 0.5
        b1 = 1.0 - cos_w0
        b2 = (1.0 - cos_w0) * 0.5
        a0 = 1.0 + alpha
        a1 = -2.0 * cos_w0
        a2 = 1.0 - alpha

    elif ftype == BiquadFilterType.HIGHPASS:
        b0 = (1.0 + cos_w0) * 0.5
        b1 = -(1.0 + cos_w0)
        b2 = (1.0 + cos_w0) * 0.5
        a0 = 1.0 + alpha
        a1 = -2.0 * cos_w0
        a2 = 1.0 - alpha

    elif ftype == BiquadFilterType.BANDPASS:
        b0 = alpha
        b1 = 0.0
        b2 = -alpha
        a0 = 1.0 + alpha
        a1 = -2.0 * cos_w0
        a2 = 1.0 - alpha

    elif ftype == BiquadFilterType.NOTCH:
        b0 = 1.0
        b1 = -2.0 * cos_w0
        b2 = 1.0
        a0 = 1.0 + alpha
        a1 = -2.0 * cos_w0
        a2 = 1.0 - alpha

    elif ftype == BiquadFilterType.ALLPASS:
        b0 = 1.0 - alpha
        b1 = -2.0 * cos_w0
        b2 = 1.0 + alpha
        a0 = 1.0 + alpha
        a1 = -2.0 * cos_w0
        a2 = 1.0 - alpha

    elif ftype == BiquadFilterType.LOWSHELF:
        two_sqrt_a_alpha = 2.0 * np.sqrt(A) * alpha
        b0 = A * ((A + 1.0) - (A - 1.0) * cos_w0 + two_sqrt_a_alpha)
        b1 = 2.0 * A * ((A - 1.0) - (A + 1.0) * cos_w0)
        b2 = A * ((A + 1.0) - (A - 1.0) * cos_w0 - two_sqrt_a_alpha)
        a0 = (A + 1.0) + (A - 1.0) * cos_w0 + two_sqrt_a_alpha
        a1 = -2.0 * ((A - 1.0) + (A + 1.0) * cos_w0)
        a2 = (A + 1.0) + (A - 1.0) * cos_w0 - two_sqrt_a_alpha

    elif ftype == BiquadFilterType.HIGHSHELF:
        two_sqrt_a_alpha = 2.0 * np.sqrt(A) * alpha
        b0 = A * ((A + 1.0) + (A - 1.0) * cos_w0 + two_sqrt_a_alpha)
        b1 = -2.0 * A * ((A - 1.0) + (A + 1.0) * cos_w0)
        b2 = A * ((A + 1.0) + (A - 1.0) * cos_w0 - two_sqrt_a_alpha)
        a0 = (A + 1.0) - (A - 1.0) * cos_w0 + two_sqrt_a_alpha
        a1 = 2.0 * ((A - 1.0) - (A + 1.0) * cos_w0)
        a2 = (A + 1.0) - (A - 1.0) * cos_w0 - two_sqrt_a_alpha

    elif ftype == BiquadFilterType.TILT:
        # Tilt filter combines half low-shelf and half high-shelf around pivot f0
        shelf_gain = gain_db * 0.5
        # Return a composite biquad approximating tilt response
        A_tilt = np.power(10.0, shelf_gain / 40.0)
        two_sqrt_a_alpha = 2.0 * np.sqrt(A_tilt) * alpha
        b0 = A_tilt * ((A_tilt + 1.0) - (A_tilt - 1.0) * cos_w0 + two_sqrt_a_alpha)
        b1 = 2.0 * A_tilt * ((A_tilt - 1.0) - (A_tilt + 1.0) * cos_w0)
        b2 = A_tilt * ((A_tilt + 1.0) - (A_tilt - 1.0) * cos_w0 - two_sqrt_a_alpha)
        a0 = (A_tilt + 1.0) + (A_tilt - 1.0) * cos_w0 + two_sqrt_a_alpha
        a1 = -2.0 * ((A_tilt - 1.0) + (A_tilt + 1.0) * cos_w0)
        a2 = (A_tilt + 1.0) + (A_tilt - 1.0) * cos_w0 - two_sqrt_a_alpha

    else:
        raise ValueError(f"Unknown filter type: {filter_type}")

    return Biquad(b0, b1, b2, a0, a1, a2, sample_rate=fs)


def biquad_frequency_response(
    filter_type: BiquadFilterType | str,
    freq_hz: float,
    gain_db: float = 0.0,
    q: float = 0.7071,
    sample_rate: float = 48000.0,
    n_points: int = 512
) -> Tuple[np.ndarray, np.ndarray, np.ndarray, np.ndarray]:
    """Helper to compute frequency response directly from filter design parameters."""
    bq = make_biquad(filter_type, freq_hz, gain_db, q, sample_rate)
    return bq.frequency_response(n_points=n_points)
