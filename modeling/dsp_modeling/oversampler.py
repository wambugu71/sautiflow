"""
Polyphase Half-Band FIR Oversampler Mathematical Modeling
=========================================================

Creators & Historical Foundations:
----------------------------------
- **Multirate DSP & Polyphase Decomposition**: Ronald E. Crochiere & Lawrence R. Rabiner
  ("Multirate Digital Signal Processing", Prentice-Hall, 1983).
- **Optimal Equiripple FIR Filter Design**: James H. McClellan, Thomas W. Parks, and Eugene Y. Remez
  (The Parks-McClellan / Remez Exchange Algorithm, IEEE Trans. Audio Electroacoust., 1973).

Mathematical Principles
-----------------------
A half-band low-pass FIR filter satisfies the symmetry condition in the time and frequency domains:
    h[2m] = 0.5 * delta[m]  (all even-indexed taps are zero except the center tap)
    H(e^j(pi - w)) = 1 - H(e^jw)

Because even taps are zero, polyphase decomposition splits the filter into two polyphase branches:
    Branch 0 (Even taps): Pure delay line of (TAPS - 1) / 4 samples. Requires 0 multiplications!
    Branch 1 (Odd taps): Symmetrically folded FIR filter over (TAPS - 1) / 4 non-zero coefficients.

Filter Specifications (55-tap Remez Equiripple):
    - Taps: 55 (Linear phase, symmetric about tap 27)
    - Passband: 0 Hz to 0.45 * fs (passband ripple < 0.0003 dB)
    - Stopband: 0.55 * fs to fs (stopband attenuation >= 96 dB)
    - Group Delay: Exactly 13.5 samples at 2x oversampled rate (13 native samples delay).
"""

from typing import Tuple, Callable
import numpy as np


class PolyphaseHalfBandFilter2x:
    """
    55-Tap Remez equiripple polyphase half-band FIR filter for 2x upsampling and downsampling.
    Matches the exact coefficients and phase delay of `oversampler.h`.
    """

    # Odd-indexed half-band filter taps (symmetric pairs offset by +/- (2k + 1) from center tap)
    ODD_COEFFS = np.array([
        0.63325347322776659,  # +/- 1
        -0.20229304029740469,  # +/- 3
        0.11141361671711554,  # +/- 5
        -0.06987882027518606,  # +/- 7
        0.04556866943326758,  # +/- 9
        -0.02975924061736543,  # +/- 11
        0.01906329776408587,  # +/- 13
        -0.01179311919626298,  # +/- 15
        0.00695287304654732,  # +/- 17
        -0.00384251557970565,  # +/- 19
        0.00195419140138790,  # +/- 21
        -0.00088244408750492,  # +/- 23
        0.00033695575785263,  # +/- 25
        -0.00009389729459378  # +/- 27
    ], dtype=np.float64)

    TAPS = 55
    DELAY_NATIVE = 13
    DELAY_OVERSAMPLED = 27

    @property
    def taps(self) -> np.ndarray:
        """Full 55-tap symmetric impulse response."""
        h = np.zeros(self.TAPS, dtype=np.float64)
        center = self.DELAY_OVERSAMPLED  # 27
        h[center] = 0.5
        for k, c in enumerate(self.ODD_COEFFS):
            offset = 2 * k + 1
            h[center - offset] = 0.5 * c
            h[center + offset] = 0.5 * c
        return h

    def __init__(self):
        self.reset()

    def reset(self):
        # Ring buffers for stereo upsampling (32 native samples)
        self.hist_up = np.zeros((2, 32), dtype=np.float64)
        self.idx_up = 0

        # Ring buffers for stereo downsampling (64 oversampled samples)
        self.hist_down = np.zeros((2, 64), dtype=np.float64)
        self.idx_down = 0

    def upsample_frame(self, in_l: float, in_r: float) -> Tuple[float, float, float, float]:
        """
        Upsample 1 native stereo frame into 2 oversampled stereo frames.
        Returns (out_l0, out_r0, out_l1, out_r1).
        """
        self.hist_up[0, self.idx_up] = in_l
        self.hist_up[1, self.idx_up] = in_r

        # Center tap delayed by 13 native samples
        idx13 = (self.idx_up - 13) & 31
        out_l0 = self.hist_up[0, idx13]
        out_r0 = self.hist_up[1, idx13]

        # Odd polyphase branch interpolation
        sum_l = 0.0
        sum_r = 0.0
        for k, c in enumerate(self.ODD_COEFFS):
            p = (self.idx_up - (13 - (2 * k + 1))) & 31
            m = (self.idx_up - (14 + (2 * k + 1))) & 31
            sum_l += c * (self.hist_up[0, p] + self.hist_up[0, m])
            sum_r += c * (self.hist_up[1, p] + self.hist_up[1, m])

        out_l1 = sum_l
        out_r1 = sum_r

        self.idx_up = (self.idx_up + 1) & 31
        return out_l0, out_r0, out_l1, out_r1

    def downsample_frame(
        self,
        in_l0: float, in_r0: float,
        in_l1: float, in_r1: float
    ) -> Tuple[float, float]:
        """
        Downsample 2 oversampled stereo frames back to 1 native stereo frame.
        """
        # Push first oversampled frame
        self.hist_down[0, self.idx_down] = in_l0
        self.hist_down[1, self.idx_down] = in_r0
        self.idx_down = (self.idx_down + 1) & 63

        # Push second oversampled frame
        self.hist_down[0, self.idx_down] = in_l1
        self.hist_down[1, self.idx_down] = in_r1
        self.idx_down = (self.idx_down + 1) & 63

        center = (self.idx_down - 28) & 63
        center_l = self.hist_down[0, center] * 0.5
        center_r = self.hist_down[1, center] * 0.5

        sum_l = 0.0
        sum_r = 0.0
        for k, c in enumerate(self.ODD_COEFFS):
            p = (center + (2 * k + 1)) & 63
            m = (center - (2 * k + 1)) & 63
            c_half = c * 0.5
            sum_l += c_half * (self.hist_down[0, p] + self.hist_down[0, m])
            sum_r += c_half * (self.hist_down[1, p] + self.hist_down[1, m])

        return center_l + sum_l, center_r + sum_r


class PolyphaseOversampler2x:
    """Complete 2x oversampling engine wrapping PolyphaseHalfBandFilter2x."""

    def __init__(self, sample_rate: float = 48000.0):
        self.sample_rate = float(sample_rate)
        self.filter = PolyphaseHalfBandFilter2x()

    def reset(self):
        self.filter.reset()

    def upsample(self, signal: np.ndarray) -> np.ndarray:
        """Upsample native stereo signal [N, 2] to 2x oversampled rate [2N, 2]."""
        s = np.asarray(signal, dtype=np.float32)
        if s.ndim == 1:
            s = np.column_stack([s, s])
        num_frames = s.shape[0]
        out = np.zeros((num_frames * 2, 2), dtype=np.float32)

        for n in range(num_frames):
            l0, r0, l1, r1 = self.filter.upsample_frame(float(s[n, 0]), float(s[n, 1]))
            out[2 * n, 0] = l0
            out[2 * n, 1] = r0
            out[2 * n + 1, 0] = l1
            out[2 * n + 1, 1] = r1

        return out

    def downsample(self, signal: np.ndarray) -> np.ndarray:
        """Downsample 2x oversampled signal [2N, 2] to native rate [N, 2]."""
        s = np.asarray(signal, dtype=np.float32)
        num_frames = s.shape[0] // 2
        out = np.zeros((num_frames, 2), dtype=np.float32)

        for n in range(num_frames):
            l0, r0 = float(s[2 * n, 0]), float(s[2 * n, 1])
            l1, r1 = float(s[2 * n + 1, 0]), float(s[2 * n + 1, 1])
            out_l, out_r = self.filter.downsample_frame(l0, r0, l1, r1)
            out[n, 0] = out_l
            out[n, 1] = out_r

        return out

    def process(self, signal: np.ndarray, proc_func: Callable[[np.ndarray], np.ndarray]) -> np.ndarray:
        """Convenience method: upsample -> apply non-linear function -> downsample."""
        up = self.upsample(signal)
        proc = proc_func(up)
        return self.downsample(proc)


class PolyphaseOversampler4x:
    """Cascaded 4x oversampling engine utilizing two stages of 2x half-band filters."""

    def __init__(self, sample_rate: float = 48000.0):
        self.sample_rate = float(sample_rate)
        self.stage1 = PolyphaseOversampler2x(sample_rate)
        self.stage2 = PolyphaseOversampler2x(sample_rate * 2.0)

    def reset(self):
        self.stage1.reset()
        self.stage2.reset()

    def upsample(self, signal: np.ndarray) -> np.ndarray:
        s2x = self.stage1.upsample(signal)
        return self.stage2.upsample(s2x)

    def downsample(self, signal: np.ndarray) -> np.ndarray:
        s2x = self.stage2.downsample(signal)
        return self.stage1.downsample(s2x)

    def process(self, signal: np.ndarray, proc_func: Callable[[np.ndarray], np.ndarray]) -> np.ndarray:
        up = self.upsample(signal)
        proc = proc_func(up)
        return self.downsample(proc)
