"""
DSP Modeling Utilities & Signal Analysis
========================================

Provides synthetic signal generation, audio conversions, and psychoacoustic/spectral
measurement utilities for DSP algorithm verification and visualization.
"""

from typing import Tuple, Optional
import numpy as np


def db_to_linear(db: float | np.ndarray) -> float | np.ndarray:
    """Convert decibels (dB) to linear amplitude factor: 10^(dB / 20)."""
    return np.power(10.0, db / 20.0)


def linear_to_db(linear: float | np.ndarray, floor_db: float = -120.0) -> float | np.ndarray:
    """Convert linear amplitude factor to decibels: 20 * log10(|linear|)."""
    eps = np.power(10.0, floor_db / 20.0)
    clipped = np.maximum(np.abs(linear), eps)
    return 20.0 * np.log10(clipped)


def power_to_db(power: float | np.ndarray, floor_db: float = -120.0) -> float | np.ndarray:
    """Convert linear power factor to decibels: 10 * log10(|power|)."""
    eps = np.power(10.0, floor_db / 10.0)
    clipped = np.maximum(np.abs(power), eps)
    return 10.0 * np.log10(clipped)


def generate_sine(
    freq_hz: float,
    duration_s: float,
    sample_rate: float = 48000.0,
    amplitude: float = 1.0,
    phase: float = 0.0,
    fs: Optional[float] = None
) -> np.ndarray:
    """Generate a clean sinusoidal test tone."""
    if fs is not None:
        sample_rate = fs
    t = np.arange(int(round(duration_s * sample_rate))) / sample_rate
    return amplitude * np.sin(2.0 * np.pi * freq_hz * t + phase).astype(np.float32)


def generate_sweep(
    f_start: float = 20.0,
    f_end: float = 20000.0,
    duration_s: float = 1.0,
    sample_rate: float = 48000.0,
    amplitude: float = 1.0,
    fs: Optional[float] = None
) -> np.ndarray:
    """Generate a logarithmic sine sweep (chirp) from f_start to f_end."""
    if fs is not None:
        sample_rate = fs
    num_samples = int(round(duration_s * sample_rate))
    t = np.arange(num_samples) / sample_rate
    # Logarithmic chirp instantaneous phase
    k = np.exp((t / duration_s) * np.log(f_end / f_start))
    phase = 2.0 * np.pi * f_start * (duration_s / np.log(f_end / f_start)) * (k - 1.0)
    return amplitude * np.sin(phase).astype(np.float32)


def generate_impulse(
    duration_s_or_samples: float | int = 0.1,
    sample_rate: float = 48000.0,
    offset_samples: int = 0,
    fs: Optional[float] = None
) -> np.ndarray:
    """Generate a discrete Dirac unit impulse delta[n - offset]."""
    if fs is not None:
        sample_rate = fs
    if isinstance(duration_s_or_samples, int) and duration_s_or_samples > 100:
        num_samples = duration_s_or_samples
    else:
        num_samples = int(round(float(duration_s_or_samples) * sample_rate))
    x = np.zeros(num_samples, dtype=np.float32)
    if offset_samples < num_samples:
        x[offset_samples] = 1.0
    return x


def generate_tone_burst(
    freq_hz: float = 1000.0,
    burst_duration_s: float = 0.02,
    total_duration_s: float = 0.1,
    sample_rate: float = 48000.0,
    amplitude: float = 1.0,
    fs: Optional[float] = None
) -> np.ndarray:
    """Generate a Tukey-windowed tone burst for transient response analysis."""
    if fs is not None:
        sample_rate = fs
    num_samples = int(round(total_duration_s * sample_rate))
    burst_samples = int(round(burst_duration_s * sample_rate))
    x = np.zeros(num_samples, dtype=np.float32)

    t_burst = np.arange(burst_samples) / sample_rate
    # 10% cosine fade-in and fade-out to prevent spectral splatter
    window = np.ones(burst_samples, dtype=np.float32)
    fade_len = max(4, burst_samples // 10)
    ramp = 0.5 * (1.0 - np.cos(np.pi * np.arange(fade_len) / fade_len))
    window[:fade_len] = ramp
    window[-fade_len:] = ramp[::-1]

    tone = amplitude * np.sin(2.0 * np.pi * freq_hz * t_burst) * window
    start_idx = (num_samples - burst_samples) // 4
    x[start_idx:start_idx + burst_samples] = tone
    return x


def to_stereo(mono_or_stereo: np.ndarray) -> np.ndarray:
    """Ensure signal has shape [N, 2]."""
    arr = np.asarray(mono_or_stereo, dtype=np.float32)
    if arr.ndim == 1:
        return np.column_stack([arr, arr])
    if arr.ndim == 2:
        if arr.shape[1] == 1:
            return np.column_stack([arr[:, 0], arr[:, 0]])
        if arr.shape[1] == 2:
            return arr
    raise ValueError(f"Expected 1D or 2-column array, got shape {arr.shape}")


def to_interleaved(stereo: np.ndarray) -> np.ndarray:
    """Flatten [N, 2] stereo signal into interleaved 1D array [L0, R0, L1, R1, ...]."""
    s = to_stereo(stereo)
    return s.flatten().astype(np.float32)


def from_interleaved(interleaved: np.ndarray) -> np.ndarray:
    """Reshape interleaved 1D array [L0, R0, ...] back into [N, 2]."""
    arr = np.asarray(interleaved, dtype=np.float32)
    return arr.reshape(-1, 2)


def frequency_spectrum(
    signal: np.ndarray,
    sample_rate: float = 48000.0,
    n_fft: Optional[int] = None,
    window: str = "hann",
    fs: Optional[float] = None,
    include_phase: bool = False
):
    """
    Compute single-sided FFT spectrum.
    
    Returns:
        freqs: Frequency axis in Hz
        mag_db: Magnitude in dBFS
        (phase_rad: Phase in radians, only if include_phase=True)
    """
    if fs is not None:
        sample_rate = fs
    x = np.asarray(signal, dtype=np.float32)
    if x.ndim == 2:
        x = x[:, 0]  # Take left channel if stereo
    if n_fft is None:
        n_fft = 1 << int(np.ceil(np.log2(len(x))))

    if window == "hann":
        w = np.hanning(min(len(x), n_fft))
    else:
        w = np.ones(min(len(x), n_fft))

    padded = np.zeros(n_fft, dtype=np.float32)
    padded[:len(w)] = x[:len(w)] * w

    X = np.fft.rfft(padded)
    freqs = np.fft.rfftfreq(n_fft, 1.0 / sample_rate)

    # Scaling
    scale = 2.0 / np.sum(w) if np.sum(w) > 0 else 1.0
    mag_lin = np.abs(X) * scale
    mag_db = linear_to_db(mag_lin, floor_db=-140.0)
    phase_rad = np.angle(X)
    if include_phase:
        return freqs, mag_db, phase_rad
    return freqs, mag_db


def compute_thd(
    signal: np.ndarray,
    fundamental_hz: float,
    sample_rate: float = 48000.0,
    max_harmonics: int = 10,
    fs: Optional[float] = None
) -> float:
    """
    Calculate Total Harmonic Distortion (THD) percentage:
    THD = sqrt(sum(V_h^2)) / V_1 * 100%
    """
    if fs is not None:
        sample_rate = fs
    x = np.asarray(signal, dtype=np.float64)
    if x.ndim == 2:
        x = x[:, 0]
    n = len(x)
    w = np.blackman(n)
    X = np.abs(np.fft.rfft(x * w))
    freqs = np.fft.rfftfreq(n, 1.0 / sample_rate)

    # Locate fundamental peak
    fund_idx = int(np.round(fundamental_hz * n / sample_rate))
    search_w = max(2, int(fund_idx * 0.05))
    peak_idx = fund_idx - search_w + np.argmax(X[max(0, fund_idx - search_w):min(len(X), fund_idx + search_w + 1)])
    v1 = X[peak_idx]

    if v1 < 1e-9:
        return 0.0

    harmonic_power = 0.0
    for h in range(2, max_harmonics + 1):
        target_hz = fundamental_hz * h
        if target_hz >= sample_rate * 0.49:
            break
        h_idx = int(np.round(target_hz * n / sample_rate))
        h_search = max(2, int(h_idx * 0.05))
        h_peak_idx = h_idx - h_search + np.argmax(X[max(0, h_idx - h_search):min(len(X), h_idx + h_search + 1)])
        vh = X[h_peak_idx]
        harmonic_power += vh * vh

    thd_ratio = np.sqrt(harmonic_power) / v1
    return float(thd_ratio * 100.0)


def measure_rt60(
    impulse_response: np.ndarray,
    sample_rate: float = 48000.0,
    start_db: float = -5.0,
    end_db: float = -35.0,
    fs: Optional[float] = None
) -> float:
    if fs is not None:
        sample_rate = fs
    """
    Measure RT60 from an impulse response using Schroeder backwards energy integration:
    E(t) = integral_t^inf h^2(tau) dtau
    Then fits a linear regression between start_db (-5 dB) and end_db (-35 dB, T30)
    and extrapolates to 60 dB decay time.
    """
    h = np.asarray(impulse_response, dtype=np.float64)
    if h.ndim == 2:
        h = h[:, 0]

    # Schroeder backwards integration
    energy = np.cumsum(h[::-1] ** 2)[::-1]
    energy = np.maximum(energy, 1e-20)
    energy_db = 10.0 * np.log10(energy / energy[0])

    # Find sample points for start_db and end_db
    idx_start = np.where(energy_db <= start_db)[0]
    idx_end = np.where(energy_db <= end_db)[0]

    if len(idx_start) == 0 or len(idx_end) == 0 or idx_end[0] <= idx_start[0]:
        return 0.0

    s = idx_start[0]
    e = idx_end[0]

    t_axis = (np.arange(s, e) - s) / sample_rate
    decay_db = energy_db[s:e]

    # Linear regression slope: decay_db = slope * t + intercept
    slope, _ = np.polyfit(t_axis, decay_db, 1)

    if slope >= 0.0:
        return 0.0

    # RT60 is time for 60 dB decay
    rt60 = -60.0 / slope
    return float(rt60)
