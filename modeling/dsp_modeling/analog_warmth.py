"""
Analog Warmth & Non-Linear Tube/Tape Modeling
=============================================

Creators & Historical Foundations:
----------------------------------
- **Vacuum Triode Valve**: Lee de Forest (Audion, 1906); RCA (12AX7 / ECC83 dual triode, 1947).
- **Vacuum Tube Digital Circuit Simulation**: David T. Yeh, Jonathan S. Abel, and Julius O. Smith III
  ("Simulation of the Diode-Clipper and Guitar-Pedal Circuits", Stanford CCRMA, 2007).
- **Magnetic Tape Recording**: Valdemar Poulsen (1898); Fritz Pfleumer (1928); Ampex Corporation (1948).
- **Class-A Console Preamplifiers**: Rupert Neve (Neve 1073 console preamplifier, 1970).

Physical & Mathematical Models
------------------------------
1. **Triode 12AX7 Vacuum Tube (Class-A Asymmetric Saturation)**:
   The physical grid characteristic of a 12AX7 exhibits soft compression on positive grid excursions
   and an extended soft knee on negative swings:
       x_driven = x * (1.0 + drive * 2.5)
       y = tanh(x_driven)                                    if x_driven > 0
       y = tanh(0.85 * x_driven) / 0.85                      if x_driven <= 0
       y_warmth = y + (x_driven^2 * 0.08 * drive)            (2nd-order even harmonic generation)
       y_out = y_warmth / (1.0 + drive * 0.5)                (makeup gain compensation)
   The asymmetric DC offset is stripped using a 10 Hz 1-pole high-pass DC blocker:
       y_dc[n] = x[n] - x[n-1] + R * y_dc[n-1],  where R = 1 - 2*pi*10/fs

2. **Magnetic Tape Saturation (Symmetric S-Curve + Head Gap Losses)**:
   Models magnetic domain particle alignment and high-frequency tape head gap absorption:
       sat = tanh(x * (1.0 + drive * 2.0))
       y_damped[n] = sat * (1.0 - d) + prev * d,  where d = clamp(6000 / (fs * oversample), 0.01, 0.35)
       y_out = y_damped / (1.0 + drive * 0.4)

3. **Vintage Console Preamp (Subtle Class-A Harmonic Excitation)**:
   3-term polynomial series modeling subtle transformer/transistor saturation:
       d_scale = drive * 0.5
       y = x - 0.15 * d_scale * x^2 - 0.10 * d_scale * x^3, clamped to [-1.0, 1.0]
"""

from enum import Enum
from typing import Optional
import numpy as np

from .oversampler import PolyphaseOversampler2x, PolyphaseOversampler4x


class AnalogWarmthProfile(str, Enum):
    TRIODE_12AX7 = "triode_12ax7"
    MAGNETIC_TAPE = "magnetic_tape"
    VINTAGE_PREAMP = "vintage_preamp"

    # Convenient aliases
    TUBE_12AX7 = "triode_12ax7"
    TAPE_STUDER_A800 = "magnetic_tape"
    CONSOLE_NEVE_8048 = "vintage_preamp"


class AnalogWarmthDSP:
    """
    High-fidelity non-linear analog saturation suite with 2x/4x polyphase oversampling,
    parameter smoothing, and DC blocking.
    """

    def __init__(
        self,
        sample_rate: float = 48000.0,
        profile: AnalogWarmthProfile | str = AnalogWarmthProfile.TRIODE_12AX7,
        drive: float = 0.5,
        oversampling_factor: int = 2
    ):
        self.sample_rate = float(sample_rate)
        self.profile = AnalogWarmthProfile(profile)
        self.drive = float(np.clip(drive, 0.0, 1.0))
        self.oversampling_factor = int(oversampling_factor)

        self.oversampler_2x = PolyphaseOversampler2x(self.sample_rate)
        self.oversampler_4x = PolyphaseOversampler4x(self.sample_rate)

        self.reset()

    def reset(self):
        self.oversampler_2x.reset()
        self.oversampler_4x.reset()
        # DC block states
        self.dc_x1_l = self.dc_y1_l = 0.0
        self.dc_x1_r = self.dc_y1_r = 0.0
        # Tape damping states
        self.tape_prev_l = 0.0
        self.tape_prev_r = 0.0

    def _dc_block(self, x: float, ch: int) -> float:
        """10 Hz 1-pole DC blocking highpass filter."""
        r = 1.0 - (2.0 * np.pi * 10.0 / self.sample_rate)
        if ch == 0:
            y = x - self.dc_x1_l + r * self.dc_y1_l
            self.dc_x1_l = x
            self.dc_y1_l = y
            return y
        else:
            y = x - self.dc_x1_r + r * self.dc_y1_r
            self.dc_x1_r = x
            self.dc_y1_r = y
            return y

    def _process_triode(self, x: np.ndarray) -> np.ndarray:
        gain = 1.0 + self.drive * 2.5
        driven = x * gain

        # Asymmetric transfer
        pos_mask = driven > 0.0
        out = np.empty_like(driven)
        out[pos_mask] = np.tanh(driven[pos_mask])
        neg = driven[~pos_mask] * 0.85
        out[~pos_mask] = np.tanh(neg) / 0.85

        # Quadratic even-harmonic injection
        out += (driven * driven * 0.08 * self.drive)

        comp = 1.0 / (1.0 + self.drive * 0.5)
        return out * comp

    def _process_tape(self, signal: np.ndarray, effective_fs: float) -> np.ndarray:
        gain = 1.0 + self.drive * 2.0
        driven = signal * gain
        sat = np.tanh(driven)

        # 1-pole high frequency tape head gap absorption
        tape_damping = float(np.clip(6000.0 / effective_fs, 0.01, 0.35))
        out = np.zeros_like(sat)

        num_frames = signal.shape[0]
        comp = 1.0 / (1.0 + self.drive * 0.4)

        prev_l = self.tape_prev_l
        prev_r = self.tape_prev_r

        for n in range(num_frames):
            sl = sat[n, 0] * (1.0 - tape_damping) + prev_l * tape_damping
            sr = sat[n, 1] * (1.0 - tape_damping) + prev_r * tape_damping
            prev_l = sat[n, 0]
            prev_r = sat[n, 1]
            out[n, 0] = sl * comp
            out[n, 1] = sr * comp

        self.tape_prev_l = prev_l
        self.tape_prev_r = prev_r
        return out

    def _process_preamp(self, x: np.ndarray) -> np.ndarray:
        d_scale = self.drive * 0.5
        x2 = x * x
        x3 = x2 * x
        out = x - (x2 * 0.15 * d_scale) - (x3 * 0.10 * d_scale)
        return np.clip(out, -1.0, 1.0)

    def process(self, signal: np.ndarray) -> np.ndarray:
        """Process mono or stereo audio through the non-linear saturation model."""
        s = np.asarray(signal, dtype=np.float32)
        is_1d = (s.ndim == 1)
        if is_1d:
            s = np.column_stack([s, s])

        effective_os = self.oversampling_factor

        def non_linear_kernel(samples: np.ndarray) -> np.ndarray:
            eff_fs = self.sample_rate * (effective_os if effective_os > 0 else 1)
            if self.profile == AnalogWarmthProfile.TRIODE_12AX7:
                return self._process_triode(samples)
            elif self.profile == AnalogWarmthProfile.MAGNETIC_TAPE:
                return self._process_tape(samples, eff_fs)
            elif self.profile == AnalogWarmthProfile.VINTAGE_PREAMP:
                return self._process_preamp(samples)
            return samples

        if effective_os == 4:
            processed = self.oversampler_4x.process(s, non_linear_kernel)
        elif effective_os == 2:
            processed = self.oversampler_2x.process(s, non_linear_kernel)
        else:
            processed = non_linear_kernel(s)

        # Post-processing: DC blocker for Triode profile
        if self.profile == AnalogWarmthProfile.TRIODE_12AX7:
            for n in range(processed.shape[0]):
                processed[n, 0] = self._dc_block(float(processed[n, 0]), 0)
                processed[n, 1] = self._dc_block(float(processed[n, 1]), 1)

        return processed[:, 0] if is_1d else processed
