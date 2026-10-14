"""
Tape Drift DSP: Vintage Tape Wow, Flutter & Mechanical Pitch Drift
===================================================================

Mathematical Formulation:
-------------------------
Analog magnetic tape recorders and vinyl turntables suffer from continuous, physical
mechanical transport speed variations that produce pitch modulation and phase dispersion:

1. Modulating Components:
   - **Wow** ($0.2$–$3.0\\,\\text{Hz}$): Slow cyclic motor speed variation, capstan out-of-roundness,
     or warped vinyl platter eccentricities.
   - **Flutter** ($5.0$–$30.0\\,\\text{Hz}$): High-frequency mechanical scrape flutter across playback heads
     and drive belt tooth vibrations.
   - **Drift** ($0.05$–$0.5\\,\\text{Hz}$): Organic thermal motor drift modeled as a slow random walk.

2. Composite Modulated Delay Function:
   $$D(t) = D_{\\text{nominal}} + A_{\\text{wow}} \\sin(\\omega_{\\text{wow}} t + \\phi) + A_{\\text{flutter}} \\sin(\\omega_{\\text{flutter}} t + 1.5\\phi) + A_{\\text{drift}} W(t)$$
   where nominal center delay is $15\\,\\text{ms}$, and $\\phi$ is the channel quadrature phase offset.

3. 4-Point 3rd-Order Catmull-Rom / Hermite Cubic Fractional Delay Interpolation:
   Given 4 equidistant delay buffer samples $y_{-1}, y_0, y_1, y_2$ and fractional offset $\\mu = D - \\lfloor D \\rfloor \\in [0, 1)$:
   $$c_0 = y_0$$
   $$c_1 = \\frac{1}{2} (y_1 - y_{-1})$$
   $$c_2 = y_{-1} - 2.5 y_0 + 2.0 y_1 - 0.5 y_2$$
   $$c_3 = \\frac{1}{2} (y_2 - y_{-1}) + 1.5 (y_0 - y_1)$$
   $$y(\\mu) = ((c_3 \\mu + c_2) \\mu + c_1) \\mu + c_0$$
   This guarantees continuous 1st derivatives ($C^1$ continuity), completely preventing discontinuity clicks
   and high-frequency aliasing during continuous delay pitch modulation.

4. Magnetic Tape Head Damping Filter:
   A 1-pole lowpass filter modeling magnetic gap high-frequency absorption:
   $$y[n] = y[n-1] + \\alpha (x[n] - y[n-1]), \\quad \\alpha = \\frac{\\omega_c}{\\omega_c + 1}$$

Historical Attribution & Creators:
----------------------------------
- **Charles Hermite** (1822–1901) & **Edwin Catmull & Raphael Rom** (1974):
  Developed Hermite interpolation and the Catmull-Rom local cubic spline:
  "A Class of Local Interpolating Splines", *Computer Aided Geometric Design*, Academic Press, 1974.
- **Valdemar Poulsen** (1869–1942):
  Danish engineer who invented magnetic sound recording with the Telegraphone in 1898.
- **Fritz Pfleumer** (1881–1945):
  German-Austrian engineer who invented magnetic audio tape in 1928 by applying iron oxide coating.
"""

from enum import IntEnum
from typing import Tuple, Optional
import numpy as np


class TapeDriftPreset(IntEnum):
    SUBTLE_HIFI = 0
    VINTAGE_REEL_TO_REEL = 1
    WARPED_VINYL = 2
    CASSETTE_LOFI = 3
    CUSTOM = 4


class TapeDriftDSP:
    """
    Mathematical and functional model of the TapeDriftDSP processor.
    """

    def __init__(self, sample_rate: float = 48000.0) -> None:
        self.sample_rate = sample_rate
        self.preset = TapeDriftPreset.SUBTLE_HIFI
        self.buffer_size = 16384
        self.buffer_mask = self.buffer_size - 1

        self.wow_rate_hz = 0.8
        self.wow_depth_ms = 0.35
        self.flutter_rate_hz = 12.0
        self.flutter_depth_ms = 0.08
        self.drift_depth_ms = 0.10
        self.stereo_phase_deg = 45.0
        self.hf_damping_hz = 18000.0

        self.set_preset(TapeDriftPreset.SUBTLE_HIFI)
        self.reset()

    def set_preset(self, preset: TapeDriftPreset) -> None:
        self.preset = preset
        if preset == TapeDriftPreset.SUBTLE_HIFI:
            self.wow_rate_hz = 0.8
            self.wow_depth_ms = 0.35
            self.flutter_rate_hz = 12.0
            self.flutter_depth_ms = 0.08
            self.drift_depth_ms = 0.10
            self.stereo_phase_deg = 45.0
            self.hf_damping_hz = 18000.0
        elif preset == TapeDriftPreset.VINTAGE_REEL_TO_REEL:
            self.wow_rate_hz = 1.0
            self.wow_depth_ms = 0.90
            self.flutter_rate_hz = 16.0
            self.flutter_depth_ms = 0.22
            self.drift_depth_ms = 0.30
            self.stereo_phase_deg = 60.0
            self.hf_damping_hz = 15000.0
        elif preset == TapeDriftPreset.WARPED_VINYL:
            self.wow_rate_hz = 0.555  # 33.33 RPM / 60
            self.wow_depth_ms = 2.2
            self.flutter_rate_hz = 7.5
            self.flutter_depth_ms = 0.12
            self.drift_depth_ms = 0.20
            self.stereo_phase_deg = 90.0
            self.hf_damping_hz = 16000.0
        elif preset == TapeDriftPreset.CASSETTE_LOFI:
            self.wow_rate_hz = 1.6
            self.wow_depth_ms = 2.0
            self.flutter_rate_hz = 22.0
            self.flutter_depth_ms = 0.55
            self.drift_depth_ms = 0.70
            self.stereo_phase_deg = 90.0
            self.hf_damping_hz = 10000.0

    def reset(self) -> None:
        self.buffer = np.zeros((2, self.buffer_size), dtype=np.float64)
        self.write_pos = 0
        self.wow_phase = 0.0
        self.flutter_phase = 0.0
        self.drift_val = 0.0
        self.drift_target = 0.0
        self.drift_counter = 0
        self.hf_state = np.zeros(2, dtype=np.float64)

    @staticmethod
    def hermite4(ym1: float, y0: float, y1: float, y2: float, frac: float) -> float:
        """4-point 3rd-order Catmull-Rom / Hermite cubic interpolation."""
        c0 = y0
        c1 = 0.5 * (y1 - ym1)
        c2 = ym1 - 2.5 * y0 + 2.0 * y1 - 0.5 * y2
        c3 = 0.5 * (y2 - ym1) + 1.5 * (y0 - y1)
        return ((c3 * frac + c2) * frac + c1) * frac + c0

    def process(self, left: np.ndarray, right: np.ndarray) -> Tuple[np.ndarray, np.ndarray]:
        """Process stereo channels with wow, flutter, drift, and head damping."""
        n = len(left)
        out_l = np.zeros(n, dtype=np.float32)
        out_r = np.zeros(n, dtype=np.float32)

        nominal_delay = 0.015 * self.sample_rate  # 15ms center delay
        wow_amp = (self.wow_depth_ms * 0.001) * self.sample_rate
        flutter_amp = (self.flutter_depth_ms * 0.001) * self.sample_rate
        drift_amp = (self.drift_depth_ms * 0.001) * self.sample_rate

        phase_offset = float(np.radians(self.stereo_phase_deg))
        wow_inc = 2.0 * np.pi * self.wow_rate_hz / self.sample_rate
        flt_inc = 2.0 * np.pi * self.flutter_rate_hz / self.sample_rate

        # 1-pole damping coefficient
        fc = min(self.hf_damping_hz, self.sample_rate * 0.45)
        w0 = 2.0 * np.pi * fc / self.sample_rate
        hf_alpha = w0 / (w0 + 1.0)
        drift_interval = max(1, int(self.sample_rate * 0.1))

        rng = np.random.RandomState(42)

        for i in range(n):
            self.wow_phase += wow_inc
            if self.wow_phase >= 2.0 * np.pi:
                self.wow_phase -= 2.0 * np.pi

            self.flutter_phase += flt_inc
            if self.flutter_phase >= 2.0 * np.pi:
                self.flutter_phase -= 2.0 * np.pi

            self.drift_counter += 1
            if self.drift_counter >= drift_interval:
                self.drift_counter = 0
                self.drift_target = rng.uniform(-1.0, 1.0)

            self.drift_val += 0.0005 * (self.drift_target - self.drift_val)

            # Store input samples
            self.buffer[0, self.write_pos] = float(left[i])
            self.buffer[1, self.write_pos] = float(right[i])

            # Process Left and Right channels
            for ch in range(2):
                ch_phase = phase_offset if ch == 1 else 0.0
                wow_mod = np.sin(self.wow_phase + ch_phase) * wow_amp
                flt_mod = np.sin(self.flutter_phase + ch_phase * 1.5) * flutter_amp
                drift_mod = self.drift_val * drift_amp

                tot_delay = float(np.clip(
                    nominal_delay + wow_mod + flt_mod + drift_mod, 2.0, self.buffer_size - 8
                ))
                read_pos = float(self.write_pos) - tot_delay
                i_read = int(np.floor(read_pos))
                frac = read_pos - float(i_read)

                idx_m1 = (i_read - 1) & self.buffer_mask
                idx_0 = i_read & self.buffer_mask
                idx_p1 = (i_read + 1) & self.buffer_mask
                idx_p2 = (i_read + 2) & self.buffer_mask

                ym1 = self.buffer[ch, idx_m1]
                y0 = self.buffer[ch, idx_0]
                y1 = self.buffer[ch, idx_p1]
                y2 = self.buffer[ch, idx_p2]

                delayed = self.hermite4(ym1, y0, y1, y2, frac)

                # Head damping
                if self.hf_damping_hz < 20000.0:
                    self.hf_state[ch] += hf_alpha * (delayed - self.hf_state[ch])
                    delayed = self.hf_state[ch]

                if ch == 0:
                    out_l[i] = delayed
                else:
                    out_r[i] = delayed

            self.write_pos = (self.write_pos + 1) & self.buffer_mask

        return out_l, out_r
