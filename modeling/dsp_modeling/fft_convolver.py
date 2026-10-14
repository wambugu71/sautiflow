"""
FFT Partitioned Overlap-Add Convolver Mathematical Modeling
===========================================================

Creators & Historical Foundations:
----------------------------------
- **Fast Fourier Transform (FFT)**: James W. Cooley and John W. Tukey
  ("An algorithm for the machine calculation of complex Fourier series", Math. Comput., 1965).
- **Uniform Partitioned Block Convolution**: Dr. William G. Gardner
  ("Efficient Convolution without Input-Output Delay", J. Audio Eng. Soc., Vol. 43, No. 3, 1995).
- **High-Performance Partitioned Engine**: Anders Torger & Angelo Farina
  ("BruteFIR: A versatile FIR filter engine", 111th AES Convention, New York, 2001).

Mathematical Topologies (UPOLS / Overlap-Add)
---------------------------------------------
Direct linear convolution of an audio stream x[n] with an impulse response h[n] of length L requires
O(N * L) time-domain multiplications, which is computationally prohibitive for long reverberation tails
(e.g., L = 144,000 samples for a 3-second reverb @ 48 kHz).

Partitioned Frequency-Domain Convolution solves this with minimal latency:
1. **Partitioning the Impulse Response**:
   Split h[n] into P uniform segments of block size B = 512:
       h_p[m] = h[p*B + m]  for m in [0, B-1]
   Zero-pad each segment to FFT size 2*B = 1024 and precompute the FFT:
       H_p[k] = FFT_{1024}( [h_p, 0_B] )

2. **Frequency-Domain Delay Line (FDDL)**:
   For incoming input block x_m of size B:
       X_m[k] = FFT_{1024}( [x_m, 0_B] )
   Multiply across stored frequency partitions:
       Y_m[k] = sum_{p=0}^{P-1} X_{m-p}[k] * H_p[k]

3. **Inverse FFT & Overlap-Add**:
       y_time = IFFT_{1024}( Y_m[k] )
       out[n] = y_time[0:B] + overlap_tail[n]
       overlap_tail = y_time[B:2B]
"""

from typing import Optional
import numpy as np


class FFTConvolverDSP:
    """
    Uniform Partitioned Overlap-Add (UPOLS) FFT Convolution Engine.
    """

    BLOCK_SIZE = 512
    FFT_SIZE = 1024

    def __init__(self, sample_rate: float = 48000.0, block_size: int = 512):
        self.sample_rate = float(sample_rate)
        self.BLOCK_SIZE = int(block_size)
        self.FFT_SIZE = int(block_size * 2)
        self.ir_loaded = False
        self.partitions_l: list[np.ndarray] = []
        self.partitions_r: list[np.ndarray] = []
        self.num_segments = 0
        self.reset()

    def reset(self):
        spec_size = self.FFT_SIZE // 2 + 1
        self.fddl_l: list[np.ndarray] = [np.zeros(spec_size, dtype=np.complex64) for _ in range(max(1, self.num_segments))]
        self.fddl_r: list[np.ndarray] = [np.zeros(spec_size, dtype=np.complex64) for _ in range(max(1, self.num_segments))]
        self.tail_l = np.zeros(self.BLOCK_SIZE, dtype=np.float32)
        self.tail_r = np.zeros(self.BLOCK_SIZE, dtype=np.float32)

    def load_impulse_response(self, ir_samples: np.ndarray) -> bool:
        """
        Partition and precompute FFT spectra for impulse response.
        """
        ir = np.asarray(ir_samples, dtype=np.float32)
        if ir.ndim == 1:
            ir = np.column_stack([ir, ir])

        # Normalize peak amplitude
        max_peak = float(np.max(np.abs(ir)))
        if max_peak > 1.0:
            ir /= max_peak

        ir_len = ir.shape[0]
        self.num_segments = int(np.ceil(ir_len / self.BLOCK_SIZE))

        self.partitions_l = []
        self.partitions_r = []

        for p in range(self.num_segments):
            start = p * self.BLOCK_SIZE
            end = min(ir_len, start + self.BLOCK_SIZE)

            block_l = np.zeros(self.FFT_SIZE, dtype=np.float32)
            block_r = np.zeros(self.FFT_SIZE, dtype=np.float32)

            block_l[:end - start] = ir[start:end, 0]
            block_r[:end - start] = ir[start:end, 1]

            self.partitions_l.append(np.fft.rfft(block_l))
            self.partitions_r.append(np.fft.rfft(block_r))

        self.ir_loaded = True
        self.reset()
        return True

    def process(self, signal: np.ndarray, wet: float = 1.0, dry: float = 0.0) -> np.ndarray:
        """
        Process audio through the partitioned convolution engine.
        """
        s = np.asarray(signal, dtype=np.float32)
        is_1d = (s.ndim == 1)
        if is_1d:
            s = np.column_stack([s, s])

        if not self.ir_loaded or self.num_segments == 0:
            return s[:, 0] if is_1d else s

        num_frames = s.shape[0]
        out = np.zeros_like(s)

        # Pad to multiple of BLOCK_SIZE
        padded_len = int(np.ceil(num_frames / self.BLOCK_SIZE)) * self.BLOCK_SIZE
        in_padded = np.zeros((padded_len, 2), dtype=np.float32)
        in_padded[:num_frames] = s

        out_padded = np.zeros((padded_len, 2), dtype=np.float32)

        time_block_l = np.zeros(self.FFT_SIZE, dtype=np.float32)
        time_block_r = np.zeros(self.FFT_SIZE, dtype=np.float32)

        for b in range(0, padded_len, self.BLOCK_SIZE):
            chunk_l = in_padded[b:b + self.BLOCK_SIZE, 0]
            chunk_r = in_padded[b:b + self.BLOCK_SIZE, 1]

            time_block_l[:self.BLOCK_SIZE] = chunk_l
            time_block_r[:self.BLOCK_SIZE] = chunk_r

            X_l = np.fft.rfft(time_block_l)
            X_r = np.fft.rfft(time_block_r)

            # Shift FDDL
            self.fddl_l.insert(0, X_l)
            self.fddl_l.pop()
            self.fddl_r.insert(0, X_r)
            self.fddl_r.pop()

            # Frequency-domain accumulate
            Y_l = np.zeros_like(X_l)
            Y_r = np.zeros_like(X_r)

            for p in range(self.num_segments):
                Y_l += self.fddl_l[p] * self.partitions_l[p]
                Y_r += self.fddl_r[p] * self.partitions_r[p]

            y_time_l = np.fft.irfft(Y_l, n=self.FFT_SIZE)
            y_time_r = np.fft.irfft(Y_r, n=self.FFT_SIZE)

            # Overlap-add
            wet_l = y_time_l[:self.BLOCK_SIZE] + self.tail_l
            wet_r = y_time_r[:self.BLOCK_SIZE] + self.tail_r

            self.tail_l = y_time_l[self.BLOCK_SIZE:self.BLOCK_SIZE * 2].astype(np.float32)
            self.tail_r = y_time_r[self.BLOCK_SIZE:self.BLOCK_SIZE * 2].astype(np.float32)

            out_padded[b:b + self.BLOCK_SIZE, 0] = chunk_l * dry + wet_l * wet
            out_padded[b:b + self.BLOCK_SIZE, 1] = chunk_r * dry + wet_r * wet

        res = out_padded[:num_frames]
        return res[:, 0] if is_1d else res
