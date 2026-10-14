"""
Broadcast Leveller AGC Mathematical Modeling
============================================

Creators & Historical Foundations:
----------------------------------
- **ITU-R BS.1770 Algorithm**: Gilbert Soulodre
  ("Evaluation of Objective Loudness Meters", 116th AES Convention, 2004; ITU-R Recommendation BS.1770, 2006).
- **EBU R128 Loudness Standard**: Florian Camerer and the EBU PLOUD Group
  ("EBU Recommendation R128: Loudness normalisation and permitted maximum level of audio signals", Geneva, 2010).

Mathematical Principles
-----------------------
Slow-window automatic gain control (AGC) eliminates long-term volume disparity across tracks, podcasts,
and broadcasts by riding gain at psychoacoustically transparent slew rates (0.5–1.5 dB/s) without compressor pumping.

1. **Short-Term Loudness Measurement (3-Second Sliding Leaky Integrator)**:
   Energy in a block of N frames:
       E_block = (1/N) * sum_{n=0}^{N-1} [ (1/C) * sum_{c=0}^{C-1} x[n, c]^2 ]
   Leaky continuous integrator with time constant tau = (3.0 * fs) / 2:
       decay = exp(-N / tau)
       sum_sq = sum_sq * decay + E_block
       count = count * decay + N
       LUFS = -0.691 + 10 * log10(sum_sq / count)

2. **Silence / Noise Floor Freeze**:
   If LUFS <= silence_gate_lufs (e.g. -45 LUFS during speech pauses), target gain freezes to prevent
   elevating room tone, background hiss, or breath noise.

3. **Slew-Rate Gain Limiter**:
   Desired correction: delta_G = target_lufs - measured_lufs, clamped to [-max_att, +max_boost].
   Over block duration dt = N / fs:
       If delta_G > G_current:  G_current = min(delta_G, G_current + max_rise * dt)
       If delta_G < G_current:  G_current = max(delta_G, G_current - max_fall * dt)
"""

from typing import Tuple, Optional
import numpy as np


class BroadcastLevellerDSP:
    """
    EBU R128 / ITU-R BS.1770 slow-window automatic gain control engine with silence freezing
    and slew rate limiting.
    """

    def __init__(
        self,
        sample_rate: float = 48000.0,
        target_lufs: float = -16.0,
        max_rise_db_sec: float = 0.75,
        max_fall_db_sec: float = 1.50,
        max_boost_db: float = 9.0,
        max_attenuation_db: float = 12.0,
        silence_gate_lufs: float = -45.0
    ):
        self.sample_rate = float(sample_rate)
        self.target_lufs = float(target_lufs)
        self.max_rise_db_sec = float(max_rise_db_sec)
        self.max_fall_db_sec = float(max_fall_db_sec)
        self.max_boost_db = float(max_boost_db)
        self.max_attenuation_db = float(max_attenuation_db)
        self.silence_gate_lufs = float(silence_gate_lufs)

        self.reset()

    def reset(self):
        self.current_gain_db = 0.0
        self.target_gain_db = 0.0
        self.current_gain_linear = 1.0
        self.is_frozen = False
        self.internal_sum_sq = 0.0
        self.internal_sample_count = 0.0
        self.internal_short_term_lufs = -100.0

    def compute_internal_lufs(self, block: np.ndarray) -> float:
        """Measure unweighted short-term LUFS via exponential leaky integrator."""
        frame_count = block.shape[0]
        channels = block.shape[1] if block.ndim > 1 else 1
        block_energy = float(np.sum(block ** 2)) / float(channels)

        # 3.0 second short-term window target
        window_samples = self.sample_rate * 3.0
        tau = window_samples * 0.5
        decay = np.exp(-frame_count / tau)

        self.internal_sum_sq = self.internal_sum_sq * decay + block_energy
        self.internal_sample_count = self.internal_sample_count * decay + float(frame_count)

        min_fill = window_samples / 32.0
        if self.internal_sample_count >= min_fill:
            mean_pwr = self.internal_sum_sq / self.internal_sample_count
            if mean_pwr > 1.0e-10:
                self.internal_short_term_lufs = float(-0.691 + 10.0 * np.log10(mean_pwr))
            else:
                self.internal_short_term_lufs = -100.0
        return self.internal_short_term_lufs

    def compute_block_gain(self, effective_lufs: float, frame_count: int) -> float:
        """Slew-rate limited target gain update in dB."""
        if effective_lufs <= self.silence_gate_lufs:
            self.is_frozen = True
            return self.current_gain_db

        self.is_frozen = False
        desired_gain = np.clip(
            self.target_lufs - effective_lufs,
            -self.max_attenuation_db,
            self.max_boost_db
        )
        self.target_gain_db = desired_gain

        dt = frame_count / self.sample_rate
        cur = self.current_gain_db

        if self.target_gain_db > cur:
            max_rise = self.max_rise_db_sec * dt
            cur = min(self.target_gain_db, cur + max_rise)
        elif self.target_gain_db < cur:
            max_fall = self.max_fall_db_sec * dt
            cur = max(self.target_gain_db, cur - max_fall)

        self.current_gain_db = cur
        return cur

    def process(
        self,
        signal: np.ndarray,
        block_size: int = 512,
        external_lufs: Optional[float] = None
    ) -> np.ndarray:
        """
        Process mono or stereo audio in sub-blocks with smooth linear gain ramping.
        """
        s = np.asarray(signal, dtype=np.float32)
        is_1d = (s.ndim == 1)
        if is_1d:
            s = np.column_stack([s, s])

        num_frames = s.shape[0]
        out = np.zeros_like(s)

        for offset in range(0, num_frames, block_size):
            chunk = s[offset:min(num_frames, offset + block_size)]
            n = chunk.shape[0]

            eff_lufs = external_lufs if external_lufs is not None else self.compute_internal_lufs(chunk)
            self.compute_block_gain(eff_lufs, n)

            start_gain = self.current_gain_linear
            end_gain = np.power(10.0, self.current_gain_db / 20.0)
            gain_ramp = np.linspace(start_gain, end_gain, n, endpoint=True, dtype=np.float32)

            out[offset:offset + n, 0] = chunk[:, 0] * gain_ramp
            out[offset:offset + n, 1] = chunk[:, 1] * gain_ramp
            self.current_gain_linear = float(end_gain)

        return out[:, 0] if is_1d else out
