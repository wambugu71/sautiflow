"""
Transducer Acoustic Profiles & Dynamic System Matrix Modeling
=============================================================

Creators & Historical Foundations:
----------------------------------
- **Electroacoustic Transducer Analogies**: Dr. Harry F. Olson
  ("Elements of Acoustical Engineering", D. Van Nostrand Co., Princeton NJ, 1947).
- **Loudspeaker Mechanical & Acoustic System Parameters**: A. Neville Thiele & Richard H. Small
  ("Loudspeakers in Vented Boxes", JAES, 1971–1972).

Mathematical Topologies
-----------------------
Electroacoustic transducers (in-ear monitors, circumaural headphones, planar magnetic drivers,
bookshelf speakers, and subwoofers) have distinct mechanical resonances, excursion limits,
and acoustic impedance transfer functions.

The Dynamic System Matrix implements a Dual-Cascade 4-Pole Multi-Band Network:
- **Stage 1 (Primary Boundary)**:
  Splits signal at crossover frequencies x_low (100–1200 Hz) and x_high (5400–6200 Hz).
  Contralateral and resonance shaping via side_gain_x.
- **Stage 2 (Sub-Transducer Acoustic Coupling)**:
  Shapes infrasonic sub-bass at y_low (40–80 Hz) and mid-bass at y_high (60–140 Hz)
  with excursion damping via side_gain_y.
- **Max Drive Headroom Control**:
  Governs transducer excursion limits to prevent mechanical bottoming out or voice-coil distortion.
"""

from enum import Enum
from typing import Dict, Any, List
import numpy as np

from .biquad import make_biquad, BiquadFilterType


class TransducerProfile(int, Enum):
    EARPHONE = 0
    HEADPHONE = 1
    HIGH_END_REFERENCE = 2
    SPEAKER_MONITOR = 3
    EXTREME_SUBWOOFER = 4
    PURE_DYNAMIC = 5
    AUDIOPHILE_REFERENCE = 6
    STUDIO_MONITOR_LOWS = 7
    CINEMA_SUB_SLAM = 8
    CAR_AUDIO_BASS = 9
    DEEP_ACOUSTIC_WARMTH = 10
    CLEAN_KICK_DRUM = 11
    RESONANT_RUMBLE = 12
    SUB_BASS_BOOM = 13
    SOLID_IMPACT = 14
    RICH_LOW_END = 15
    CLUB_PA_PUNCH = 16
    DEEP_SUB_EXTENSION = 17
    ULTIMATE_SUBWOOFER = 18

    # Friendly aliases
    PLANAR_MAGNETIC = 6
    ELECTROSTATIC = 2
    STUDIO_MONITOR_NEARFIELD = 3
    CLUB_PA_SYSTEM = 16


DYNAMIC_SYSTEM_PRESETS: List[Dict[str, Any]] = [
    {"name": "In-Ear Earbuds", "x_low": 180.0, "x_high": 5800.0, "y_low": 55.0, "y_high": 80.0, "side_x": 0.10, "side_y": 0.70, "drive": 3.4},
    {"name": "Over-Ear Headphones", "x_low": 300.0, "x_high": 5600.0, "y_low": 60.0, "y_high": 105.0, "side_x": 0.10, "side_y": 0.50, "drive": 3.0},
    {"name": "Studio Reference", "x_low": 140.0, "x_high": 6200.0, "y_low": 40.0, "y_high": 60.0, "side_x": 0.10, "side_y": 0.80, "drive": 2.2},
    {"name": "Desktop Speakers", "x_low": 400.0, "x_high": 6200.0, "y_low": 40.0, "y_high": 80.0, "side_x": 0.10, "side_y": 0.00, "drive": 3.6},
    {"name": "Club Subwoofer", "x_low": 800.0, "x_high": 6200.0, "y_low": 80.0, "y_high": 140.0, "side_x": 0.00, "side_y": 0.00, "drive": 4.6},
    {"name": "Pure Dynamic", "x_low": 1000.0, "x_high": 6200.0, "y_low": 50.0, "y_high": 90.0, "side_x": 0.30, "side_y": 0.10, "drive": 3.8},
    {"name": "Audiophile Open-Back", "x_low": 1000.0, "x_high": 6200.0, "y_low": 60.0, "y_high": 100.0, "side_x": 0.00, "side_y": 0.00, "drive": 2.5},
    {"name": "Studio Monitor Lows", "x_low": 1000.0, "x_high": 6200.0, "y_low": 60.0, "y_high": 120.0, "side_x": 0.00, "side_y": 0.00, "drive": 2.8},
    {"name": "Cinema Sub Slam", "x_low": 1200.0, "x_high": 6200.0, "y_low": 60.0, "y_high": 100.0, "side_x": 0.00, "side_y": 0.30, "drive": 4.2},
    {"name": "Car Audio Bass", "x_low": 1200.0, "x_high": 6200.0, "y_low": 40.0, "y_high": 80.0, "side_x": 0.00, "side_y": 0.30, "drive": 4.0},
    {"name": "Deep Acoustic Warmth", "x_low": 600.0, "x_high": 5400.0, "y_low": 60.0, "y_high": 105.0, "side_x": 0.10, "side_y": 0.20, "drive": 2.8},
    {"name": "Clean Kick Drum", "x_low": 400.0, "x_high": 6200.0, "y_low": 40.0, "y_high": 80.0, "side_x": 0.10, "side_y": 0.00, "drive": 3.2},
    {"name": "Resonant Rumble", "x_low": 1200.0, "x_high": 6200.0, "y_low": 50.0, "y_high": 100.0, "side_x": 0.10, "side_y": 0.50, "drive": 4.4},
    {"name": "Sub-Bass Boom", "x_low": 1200.0, "x_high": 6200.0, "y_low": 40.0, "y_high": 80.0, "side_x": 0.00, "side_y": 0.20, "drive": 4.8},
    {"name": "Solid Impact", "x_low": 800.0, "x_high": 6200.0, "y_low": 40.0, "y_high": 80.0, "side_x": 0.10, "side_y": 0.00, "drive": 3.5},
    {"name": "Rich Low-End", "x_low": 1200.0, "x_high": 6200.0, "y_low": 50.0, "y_high": 90.0, "side_x": 0.15, "side_y": 0.10, "drive": 3.6},
    {"name": "Club PA Punch", "x_low": 1000.0, "x_high": 6200.0, "y_low": 50.0, "y_high": 90.0, "side_x": 0.30, "side_y": 0.10, "drive": 4.0},
    {"name": "Deep Sub Extension", "x_low": 1000.0, "x_high": 6200.0, "y_low": 80.0, "y_high": 140.0, "side_x": 0.00, "side_y": 0.00, "drive": 4.5},
    {"name": "Ultimate Subwoofer", "x_low": 800.0, "x_high": 6200.0, "y_low": 80.0, "y_high": 140.0, "side_x": 0.00, "side_y": 0.00, "drive": 5.0}
]


class DynamicSystemDSP:
    """
    Dual-Cascade 4-Pole Multi-Band Transducer Simulation & Bass Engine.
    """

    def __init__(
        self,
        sample_rate: float = 48000.0,
        profile: TransducerProfile | int = TransducerProfile.HEADPHONE,
        bass_drive: float = 0.5
    ):
        self.sample_rate = float(sample_rate)
        self.profile = TransducerProfile(profile)
        self.bass_drive = float(np.clip(bass_drive, 0.0, 1.0))
        self.reset()

    def reset(self):
        preset = DYNAMIC_SYSTEM_PRESETS[int(self.profile)]
        self.preset_data = preset

        # Stage 1 filters
        self.lp_x = make_biquad(BiquadFilterType.LOWPASS, preset["x_low"], q=0.7071, sample_rate=self.sample_rate)
        self.hp_x = make_biquad(BiquadFilterType.HIGHPASS, preset["x_high"], q=0.7071, sample_rate=self.sample_rate)

        # Stage 2 filters
        self.lp_y = make_biquad(BiquadFilterType.LOWPASS, preset["y_high"], q=0.7071, sample_rate=self.sample_rate)
        self.hp_y = make_biquad(BiquadFilterType.HIGHPASS, preset["y_low"], q=0.7071, sample_rate=self.sample_rate)

    def process(self, signal: np.ndarray) -> np.ndarray:
        s = np.asarray(signal, dtype=np.float32)
        is_1d = (s.ndim == 1)
        if is_1d:
            s = np.column_stack([s, s])

        p = self.preset_data
        drive_mult = 1.0 + self.bass_drive * (p["drive"] - 1.0)

        # Stage 1 split
        low_x = self.lp_x.process(s)
        high_x = self.hp_x.process(s)

        # Stage 2 sub-bass extraction from low_x
        sub_y = self.hp_y.process(self.lp_y.process(low_x))

        # Recombine with acoustic weighting
        out = (s +
               low_x * (p["side_x"] * drive_mult) +
               sub_y * (p["side_y"] * drive_mult * 1.5))

        # Soft clip to prevent excursion clipping
        knee = 0.85
        drive_abs = np.abs(out)
        over = np.maximum(0.0, drive_abs - knee)
        shaped = knee + over / np.sqrt(1.0 + over * over)
        clipped = out * (shaped / np.maximum(drive_abs, 1e-9))

        return clipped[:, 0] if is_1d else clipped

    def frequency_response(self, frequencies_hz: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
        """Compute small-signal linear acoustic frequency response."""
        p = self.preset_data
        drive_mult = 1.0 + self.bass_drive * (p["drive"] - 1.0)
        
        w = 2.0 * np.pi * np.asarray(frequencies_hz, dtype=np.float64) / self.sample_rate
        z_inv = np.exp(-1j * w)
        z_inv2 = z_inv * z_inv

        def bq_h(bq):
            num = bq.b0 + bq.b1 * z_inv + bq.b2 * z_inv2
            den = 1.0 + bq.a1 * z_inv + bq.a2 * z_inv2
            return num / den

        h_lp_x = bq_h(self.lp_x)
        h_lp_y = bq_h(self.lp_y)
        h_hp_y = bq_h(self.hp_y)

        h_sub_y = h_lp_x * h_lp_y * h_hp_y
        h_total = 1.0 + h_lp_x * (p["side_x"] * drive_mult) + h_sub_y * (p["side_y"] * drive_mult * 1.5)

        mag_db = 20.0 * np.log10(np.maximum(np.abs(h_total), 1e-12))
        phase_deg = np.rad2deg(np.unwrap(np.angle(h_total)))
        return mag_db, phase_deg
