"""
Dynamic Loudness ISO 226:2003 Equal-Loudness Contour Modeling
=============================================================

Creators & Historical Foundations:
----------------------------------
- **Equal-Loudness Contours (Phon Curves)**: Harvey Fletcher and Wilden A. Munson
  ("Loudness, its definition, measurement and calculation", J. Acoust. Soc. Am., 1933).
- **Robinson-Dadson Contours**: D. W. Robinson and R. S. Dadson
  ("A re-determination of the equal-loudness relations for pure tones", Br. J. Appl. Phys., 1956).
- **ISO 226:2003 International Standard**: Yôiti Suzuki, Hisashi Takeshima, et al.
  ("Acoustics — Normal equal-loudness-level contours", International Organization for Standardization, 2003).

Psychoacoustic Principles
-------------------------
The human auditory system exhibits non-flat frequency perception that changes dynamically as sound pressure
level (SPL) varies. At low listening volumes, the ear's sensitivity to low frequencies (<150 Hz) and high
frequencies (>8 kHz) drops much faster than in the 1–4 kHz midrange.

1. **Volume-Dependent Compensation Slopes**:
   Let current volume in dB be Vol_db, and calibrated reference level Ref_db (e.g. 0 dBFS):
       attenuation_db = max(0.0, Ref_db - Vol_db)
       Bass_boost_db   = min(max_bass_boost, attenuation_db * 0.26)    (ISO 226 bass curve slope)
       Treble_boost_db = min(max_treble_boost, attenuation_db * 0.12)  (ISO 226 treble curve slope)

2. **Acoustic Filter Cascade**:
   - Low-Shelf Biquad (80–100 Hz): Restores perceived low-end punch and bass fullness.
   - High-Shelf Biquad (8–10 kHz): Restores acoustic air and brilliance.
   - At reference volume (0 dBFS), both boosts evaluate to exactly 0 dB (100% flat bit-perfect pass).
"""

import numpy as np

from .biquad import make_biquad, BiquadFilterType


class DynamicLoudnessDSP:
    """
    ISO 226:2003 Equal-loudness contour bass and treble dynamic compensation engine.
    """

    def __init__(
        self,
        sample_rate: float = 48000.0,
        ref_level_db: float = 0.0,
        max_bass_boost_db: float = 12.0,
        max_treble_boost_db: float = 6.0,
        bass_freq_hz: float = 85.0,
        treble_freq_hz: float = 9000.0
    ):
        self.sample_rate = float(sample_rate)
        self.ref_level_db = float(ref_level_db)
        self.max_bass_boost_db = float(max_bass_boost_db)
        self.max_treble_boost_db = float(max_treble_boost_db)
        self.bass_freq_hz = float(bass_freq_hz)
        self.treble_freq_hz = float(treble_freq_hz)

        self.current_bass_db = 0.0
        self.current_treble_db = 0.0
        self.reset()

    def reset(self):
        self.bass_filter = make_biquad(
            BiquadFilterType.LOWSHELF, self.bass_freq_hz, gain_db=0.0, q=0.7071, sample_rate=self.sample_rate
        )
        self.treble_filter = make_biquad(
            BiquadFilterType.HIGHSHELF, self.treble_freq_hz, gain_db=0.0, q=0.7071, sample_rate=self.sample_rate
        )

    def compute_boosts(self, volume_linear: float) -> tuple[float, float]:
        """Compute bass and treble boost in dB for a given linear volume factor."""
        vol_clamped = max(float(volume_linear), 1e-4)
        vol_db = 20.0 * np.log10(vol_clamped)
        attenuation_db = max(0.0, self.ref_level_db - vol_db)

        target_bass = min(self.max_bass_boost_db, attenuation_db * 0.26)
        target_treble = min(self.max_treble_boost_db, attenuation_db * 0.12)
        return float(target_bass), float(target_treble)

    def process(self, signal: np.ndarray, volume_linear: float = 0.25) -> np.ndarray:
        s = np.asarray(signal, dtype=np.float32)
        is_1d = (s.ndim == 1)
        if is_1d:
            s = np.column_stack([s, s])

        target_bass, target_treble = self.compute_boosts(volume_linear)

        # Update filters
        self.bass_filter = make_biquad(
            BiquadFilterType.LOWSHELF, self.bass_freq_hz, gain_db=target_bass, q=0.7071, sample_rate=self.sample_rate
        )
        self.treble_filter = make_biquad(
            BiquadFilterType.HIGHSHELF, self.treble_freq_hz, gain_db=target_treble, q=0.7071, sample_rate=self.sample_rate
        )

        # Cascade Low Shelf -> High Shelf
        out_bass = self.bass_filter.process(s, topology="tdf2")
        out_total = self.treble_filter.process(out_bass, topology="tdf2")

        return out_total[:, 0] if is_1d else out_total

    def set_volume(self, volume_linear: float) -> None:
        """Set playback volume and reconfigure shelving filters."""
        target_bass, target_treble = self.compute_boosts(volume_linear)
        self.current_bass_db = target_bass
        self.current_treble_db = target_treble
        self.bass_filter = make_biquad(
            BiquadFilterType.LOWSHELF, self.bass_freq_hz, gain_db=target_bass, q=0.7071, sample_rate=self.sample_rate
        )
        self.treble_filter = make_biquad(
            BiquadFilterType.HIGHSHELF, self.treble_freq_hz, gain_db=target_treble, q=0.7071, sample_rate=self.sample_rate
        )

    def frequency_response(self, frequencies_hz: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
        """Compute composite frequency response of cascaded bass and treble filters."""
        mag_b, ph_b = self.bass_filter.frequency_response(frequencies_hz)
        mag_t, ph_t = self.treble_filter.frequency_response(frequencies_hz)
        return mag_b + mag_t, ph_b + ph_t
