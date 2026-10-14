"""
Dynamic Parametric Equalizer Mathematical Modeling
==================================================

Creators & Historical Foundations:
----------------------------------
- **Analog Dynamic Equalizer (DPR-901)**: BSS Audio
  (BSS DPR-901 4-Band Dynamic Equalizer, Hertfordshire, UK, 1989).
- **Digital Mastering Dynamic EQ**: Daniel Weiss
  (Weiss Engineering EQ1-DYN Digital Dynamic Equalizer, Uster, Switzerland, 1998).

Mathematical Topologies
-----------------------
Unlike static equalizers (which apply fixed gain regardless of signal level) or wideband compressors
(which duck the entire audio spectrum), a Dynamic Equalizer modulates the boost/cut of specific
parametric biquad bands according to real-time energy in that band:

1. **Sidechain Bandpass Energy Extraction**:
   For band b centered at fc with bandwidth Q:
       sc[n] = H_bandpass(x[n], fc, Q)

2. **Per-Band Envelope Ballistics**:
       peak = |sc[n]|
       env[n] = env[n-1] + alpha_att * (peak - env[n-1])  if peak > env[n-1]
       env[n] = env[n-1] + alpha_rel * (peak - env[n-1])  otherwise

3. **Dynamic Gain Modulation Curve**:
   Let env_db = 20*log10(env), threshold T, ratio R, and range limit Range:
       excess = max(0.0, env_db - T)
       modulation = min(Range, excess * (1.0 - 1.0 / R))
       
       In COMPRESS mode (cuts loud resonances):
           G_active = base_gain_db - modulation
       In EXPAND mode (boosts weak signals):
           G_active = base_gain_db + modulation

4. **Sub-Block Filter Updating (Click-Free Direct Form I)**:
   Recomputes RBJ peaking/shelf coefficients every 32 samples to guarantee zero zipper noise.
"""

from enum import Enum
from dataclasses import dataclass
from typing import List
import numpy as np

from .biquad import make_biquad, BiquadFilterType, Biquad


class DynamicEqFilterType(str, Enum):
    PEAK = "peak"
    LOWSHELF = "lowshelf"
    HIGHSHELF = "highshelf"


class DynamicEqMode(str, Enum):
    STATIC = "static"
    COMPRESS = "compress"
    EXPAND = "expand"


class DynamicEqBandConfig:
    def __init__(
        self,
        enabled: bool = True,
        type: DynamicEqFilterType | BiquadFilterType | str = DynamicEqFilterType.PEAK,
        filter_type: DynamicEqFilterType | BiquadFilterType | str | None = None,
        mode: DynamicEqMode | str = DynamicEqMode.COMPRESS,
        freq_hz: float = 1000.0,
        frequency_hz: float | None = None,
        q: float = 1.0,
        base_gain_db: float = 0.0,
        gain_db: float | None = None,
        threshold_db: float = -24.0,
        range_db: float = 6.0,
        ratio: float = 3.0,
        attack_ms: float = 2.0,
        release_ms: float = 60.0,
        **kwargs
    ):
        self.enabled = enabled
        ft = filter_type if filter_type is not None else type
        if hasattr(ft, "value"):
            ft = ft.value
        self.type = DynamicEqFilterType(str(ft).lower())
        self.mode = DynamicEqMode(mode) if isinstance(mode, str) else mode
        self.freq_hz = float(frequency_hz if frequency_hz is not None else freq_hz)
        self.q = float(q)
        self.base_gain_db = float(gain_db if gain_db is not None else base_gain_db)
        self.threshold_db = float(threshold_db)
        self.range_db = float(range_db)
        self.ratio = float(ratio)
        self.attack_ms = float(attack_ms)
        self.release_ms = float(release_ms)


class DynamicEqDSP:
    """
    6-Band Studio-Grade Dynamic Parametric Equalizer.
    """

    def __init__(self, sample_rate: float = 48000.0, bands: List[DynamicEqBandConfig] = None):
        self.sample_rate = float(sample_rate)
        if bands is None:
            # Default 6-band configuration
            self.bands = [
                DynamicEqBandConfig(type=DynamicEqFilterType.LOWSHELF, freq_hz=60.0, q=0.707, threshold_db=-20.0),
                DynamicEqBandConfig(type=DynamicEqFilterType.PEAK, freq_hz=180.0, q=1.2, threshold_db=-20.0),
                DynamicEqBandConfig(type=DynamicEqFilterType.PEAK, freq_hz=600.0, q=1.4, threshold_db=-22.0),
                DynamicEqBandConfig(type=DynamicEqFilterType.PEAK, freq_hz=2000.0, q=1.6, threshold_db=-24.0),
                DynamicEqBandConfig(type=DynamicEqFilterType.PEAK, freq_hz=6000.0, q=2.0, threshold_db=-24.0),
                DynamicEqBandConfig(type=DynamicEqFilterType.HIGHSHELF, freq_hz=12000.0, q=0.707, threshold_db=-22.0),
            ]
        else:
            self.bands = list(bands)

        self.reset()

    def configure_band(self, index: int, config: DynamicEqBandConfig):
        """Configure settings for a specific band."""
        if 0 <= index < len(self.bands):
            self.bands[index] = config
            self.sidechain_filters[index] = make_biquad(
                BiquadFilterType.BANDPASS, config.freq_hz, q=config.q, sample_rate=self.sample_rate
            )
            bq_type = BiquadFilterType(config.type.value if hasattr(config.type, "value") else str(config.type))
            self.audio_filters[index] = make_biquad(
                bq_type, config.freq_hz, gain_db=config.base_gain_db, q=config.q, sample_rate=self.sample_rate
            )

    def reset(self):
        self.env = [0.0] * len(self.bands)
        self.audio_filters: List[Biquad] = []
        self.sidechain_filters: List[Biquad] = []

        for b in self.bands:
            # Sidechain bandpass filter
            sc_b = make_biquad(BiquadFilterType.BANDPASS, b.freq_hz, q=b.q, sample_rate=self.sample_rate)
            self.sidechain_filters.append(sc_b)

            # Audio processing filter
            bq_type = BiquadFilterType(b.type.value)
            aud_b = make_biquad(bq_type, b.freq_hz, gain_db=b.base_gain_db, q=b.q, sample_rate=self.sample_rate)
            self.audio_filters.append(aud_b)

    def process(self, signal: np.ndarray, sub_block_size: int = 32) -> np.ndarray:
        s = np.asarray(signal, dtype=np.float32)
        is_1d = (s.ndim == 1)
        if is_1d:
            s = np.column_stack([s, s])

        num_frames = s.shape[0]
        out = np.copy(s)

        for b_idx, b in enumerate(self.bands):
            if not b.enabled:
                continue

            alpha_att = 1.0 - np.exp(-1.0 / (self.sample_rate * (max(b.attack_ms, 0.1) * 0.001)))
            alpha_rel = 1.0 - np.exp(-1.0 / (self.sample_rate * (max(b.release_ms, 1.0) * 0.001)))

            sc_filt = self.sidechain_filters[b_idx]
            aud_filt = self.audio_filters[b_idx]
            env_val = self.env[b_idx]

            # Filter sidechain across entire block
            sc_sig = sc_filt.process(out)

            for i in range(num_frames):
                sc_peak = max(abs(float(sc_sig[i, 0])), abs(float(sc_sig[i, 1])))
                env_val += (alpha_att if sc_peak > env_val else alpha_rel) * (sc_peak - env_val)

                if (i & (sub_block_size - 1)) == 0:
                    env_db = 20.0 * np.log10(max(env_val, 1e-6))
                    excess = max(0.0, env_db - b.threshold_db)
                    mod = min(b.range_db, excess * (1.0 - 1.0 / max(b.ratio, 1.0)))

                    if b.mode == DynamicEqMode.COMPRESS:
                        target_gain = b.base_gain_db - mod
                    elif b.mode == DynamicEqMode.EXPAND:
                        target_gain = b.base_gain_db + mod
                    else:
                        target_gain = b.base_gain_db

                    aud_filt = make_biquad(
                        BiquadFilterType(b.type.value),
                        b.freq_hz,
                        gain_db=target_gain,
                        q=b.q,
                        sample_rate=self.sample_rate
                    )
                    self.audio_filters[b_idx] = aud_filt

                out[i, 0], out[i, 1] = aud_filt.process_sample_df1(float(out[i, 0]), float(out[i, 1]))

            self.env[b_idx] = env_val

        return out[:, 0] if is_1d else out
