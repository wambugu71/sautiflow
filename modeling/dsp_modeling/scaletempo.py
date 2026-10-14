"""
ScaleTempo: Waveform Similarity Overlap-Add (WSOLA) Time-Scale Modification
============================================================================

Mathematical Formulation:
-------------------------
WSOLA enables arbitrary tempo and playback speed scaling (from 0.05x to 10.0x)
without altering signal pitch, or pitch shifting when combined with a resampler.

Given an input discrete signal $x[n]$ and a scaling factor $s = v_{\\text{out}} / v_{\\text{in}}$:
1. Nominal target frame position:
   $$\\Delta_{\\text{nominal}}[m] = m \\cdot S_{\\text{step}} \\cdot s$$
   where $S_{\\text{stride}}$ is the analysis stride and $S_{\\text{step}} = S_{\\text{stride}} - S_{\\text{overlap}}$.

2. Search window optimization for maximum waveform similarity:
   The search finds an optimal time lag $k^* \\in [k_{\\text{min}}, k_{\\text{max}}]$ that maximizes
   the cross-correlation between the previous output tail $y_{\\text{tail}}[n]$ and candidates $x[k + n]$:
   $$R(k) = \\sum_{n=0}^{L_{\\text{overlap}}-1} (y_{\\text{tail}}[n] - \\mu_{\\text{tail}}) (x[k+n] - \\mu_x(k))$$

3. Raised-cosine (Hann) overlap-add synthesis:
   $$y[m \\cdot S_{\\text{step}} + n] = (1 - w[n]) \\cdot y_{\\text{tail}}[n] + w[n] \\cdot x[k^* + n]$$
   where $w[n] = \\frac{1}{2} \\left(1 - \\cos\\left(\\frac{\\pi(n + 0.5)}{L_{\\text{overlap}}}\\right)\\right)$ for $n \\in [0, L_{\\text{overlap}}-1]$.

Historical Attribution & Creators:
----------------------------------
- **Dr. Werner Verhelst and Marc Roelands** (1993):
  Pioneered the WSOLA algorithm at Vrije Universiteit Brussel (VUB), Belgium:
  "An overlap-add technique based on waveform similarity (WSOLA) for high quality time-scale modification of speech",
  Speech Communication, Vol. 13, Issues 3-4, pp. 319-328, December 1993.
- **Salomon Roucos and Alexander M. Wilgus** (1985):
  Pioneered Synchronized Overlap-Add (SOLA) at BBN Laboratories, upon which WSOLA improved
  by introducing tolerance intervals that eliminate artificial pitch periodicities.
"""

from typing import Optional, Tuple
import numpy as np


class ScaleTempoDSP:
    """
    Mathematical and functional model of the SautiFlow ScaleTempo processor.
    
    Attributes:
        sample_rate: Audio sampling frequency in Hz (e.g., 48000 Hz).
        channels: Channel count (1 for mono, 2 for stereo).
        stride_ms: Length of processing stride in milliseconds (default: 30 ms).
        overlap_ratio: Overlap window proportion (default: 0.20 = 20%).
        search_ms: Correlation search neighborhood radius (default: 14 ms).
    """

    def __init__(
        self,
        sample_rate: int = 48000,
        channels: int = 2,
        stride_ms: float = 30.0,
        overlap_ratio: float = 0.20,
        search_ms: float = 14.0,
    ) -> None:
        self.sample_rate = max(8000, sample_rate)
        self.channels = max(1, channels)
        self.scale = 1.0

        self.stride_frames = max(32, int(round(self.sample_rate * stride_ms / 1000.0)))
        self.overlap_frames = max(16, int(round(self.stride_frames * overlap_ratio)))
        if self.overlap_frames >= self.stride_frames:
            self.overlap_frames = self.stride_frames // 2
        self.step_frames = self.stride_frames - self.overlap_frames

        self.search_frames = max(16, int(round(self.sample_rate * search_ms / 1000.0)))

        # Precompute Hann blending window
        phases = np.pi * (np.arange(self.overlap_frames) + 0.5) / self.overlap_frames
        self.blend_table = (0.5 * (1.0 - np.cos(phases))).astype(np.float32)

        self.reset()

    def reset(self) -> None:
        """Reset internal buffers and state variables."""
        self.overlap_buffer = np.zeros((self.overlap_frames, self.channels), dtype=np.float32)
        self.mono_overlap = np.zeros(self.overlap_frames, dtype=np.float32)
        self.mono_overlap_mean = 0.0
        self.mono_overlap_var = 0.0
        self.nominal_position = 0.0
        self.has_overlap = False

    def set_scale(self, scale: float) -> None:
        """Set tempo scaling ratio (clamped to [0.05, 10.0])."""
        self.scale = float(np.clip(scale, 0.05, 10.0))

    def _update_mono_overlap(self) -> None:
        self.mono_overlap = np.mean(self.overlap_buffer, axis=1)
        self.mono_overlap_mean = float(np.mean(self.mono_overlap))
        self.mono_overlap_var = float(np.var(self.mono_overlap))

    def _compute_correlation(self, mono_input: np.ndarray, offset: int) -> float:
        """Compute cross-correlation between mono overlap and candidate input window."""
        cand = mono_input[offset : offset + self.overlap_frames]
        if len(cand) < self.overlap_frames:
            return -1e30

        c_mean = float(np.mean(cand))
        c_var = float(np.var(cand))

        norm = np.sqrt(self.mono_overlap_var * c_var) + 1e-12
        cov = float(np.mean((self.mono_overlap - self.mono_overlap_mean) * (cand - c_mean)))
        return cov / norm

    def process(self, x: np.ndarray) -> np.ndarray:
        """
        Process an input signal x (shape: [num_samples] or [num_samples, channels])
        and return the time-scaled output signal.
        """
        is_1d = (x.ndim == 1)
        if is_1d:
            inp = x[:, np.newaxis].astype(np.float32)
        else:
            inp = x.astype(np.float32)

        if abs(self.scale - 1.0) < 0.001:
            return x.copy()

        total_input_frames = len(inp)
        out_chunks = []
        in_pos = 0

        # Prime initial stride if starting fresh
        if not self.has_overlap and total_input_frames >= self.stride_frames:
            prime_chunk = inp[: self.stride_frames].copy()
            out_chunks.append(prime_chunk)
            overlap_offset = self.stride_frames - self.overlap_frames
            self.overlap_buffer = inp[overlap_offset : self.stride_frames].copy()
            self._update_mono_overlap()
            in_pos += self.stride_frames
            self.nominal_position = float(self.step_frames * self.scale)
            self.has_overlap = True

        mono_inp = np.mean(inp, axis=1)

        while True:
            remaining_frames = total_input_frames - in_pos
            center_offset = int(round(self.nominal_position))
            search_min = max(0, center_offset - self.search_frames)
            search_max = center_offset + self.search_frames

            if remaining_frames < (search_max + self.stride_frames):
                break

            current_mono = mono_inp[in_pos:]

            # Two-pass similarity search (coarse stride 4, then fine ±3)
            coarse_step = 4
            best_corr = -1e30
            coarse_best = search_min

            for k in range(search_min, search_max + 1, coarse_step):
                corr = self._compute_correlation(current_mono, k)
                if corr > best_corr:
                    best_corr = corr
                    coarse_best = k

            best_offset = coarse_best
            fine_start = max(search_min, coarse_best - (coarse_step - 1))
            fine_end = min(search_max, coarse_best + (coarse_step - 1))
            for k in range(fine_start, fine_end + 1):
                if k == coarse_best:
                    continue
                corr = self._compute_correlation(current_mono, k)
                if corr > best_corr:
                    best_corr = corr
                    best_offset = k

            # Synthesize overlap-add frame
            candidate_window = inp[in_pos + best_offset : in_pos + best_offset + self.stride_frames]
            step_out = np.zeros((self.step_frames, self.channels), dtype=np.float32)

            # 1. Crossfade overlap region
            w = self.blend_table[:, np.newaxis]
            step_out[: self.overlap_frames] = (
                self.overlap_buffer * (1.0 - w) + candidate_window[: self.overlap_frames] * w
            )

            # 2. Direct copy remainder
            if self.step_frames > self.overlap_frames:
                step_out[self.overlap_frames :] = candidate_window[
                    self.overlap_frames : self.step_frames
                ]

            out_chunks.append(step_out)

            # 3. Save new tail into overlap buffer
            tail_offset = self.step_frames
            self.overlap_buffer = candidate_window[tail_offset : tail_offset + self.overlap_frames].copy()
            self._update_mono_overlap()

            # 4. Advance input position and update nominal target
            in_pos += best_offset
            self.nominal_position += (self.step_frames * self.scale) - best_offset

        if len(out_chunks) == 0:
            return np.zeros((0, self.channels) if not is_1d else (0,), dtype=np.float32)

        result = np.vstack(out_chunks)
        if is_1d:
            return result.squeeze(axis=-1)
        return result
