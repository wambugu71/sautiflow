"""
Algorithmic Reverberation Mathematical Modeling (Dattorro, Lattice, Diffusion, Hadamard FDN, Barr Ring & Griesinger)
==============================================================================

Creators & Historical Foundations:
----------------------------------
- **Figure-8 Diffuse Tank Stereo Reverb**: Jon Dattorro
  (Stanford CCRMA / Ensoniq Corp., "Effect Design, Part 1: Reverberator and Other Filters",
   J. Audio Eng. Soc., Vol. 45, No. 9, September 1997).
- **Computer-Simulated Natural Reverberation**: Dr. Manfred R. Schroeder
  (Bell Telephone Laboratories, "Natural Sound Reverberation for Computers", JAES, 1962;
   "Colorless Artificial Reverberation", IRE Trans. Audio, 1961).
- **Early Reflections & Comb Lowpass Damping**: James A. Moorer
  (Stanford CCRMA, "About This Reverberation Business", Computer Music Journal, 1979).

Architecture of the Dattorro Figure-8 Reverberator
--------------------------------------------------
Dattorro's 1997 plate/tank design replaced metallic 1960s parallel comb resonators with a cross-coupled
diffuse recirculating figure-8 tank:

1. **Pre-Delay**: Initial acoustic gap (0–250 ms) before the room reacts.
2. **Abbey Road Bandpass Pre-Filtering**: 80 Hz HPF + 15 kHz LPF to cut rumble and harsh digital glare.
3. **Input Diffusers (4 Cascaded Allpasses per channel)**:
   Smears sharp transients into a dense, silky initial reflection cloud before entering the tank.
4. **Coupled Figure-8 Tank (Tank 1 <-> Tank 2)**:
   - Modulated Allpass with dual-phase quadrature LFOs (eliminates static standing modes & flutter).
   - Primary Tank Delay Line.
   - Frequency-Dependent Damping Absorption Filter (1-pole lowpass simulating air/wall absorption).
   - Decay Attenuation Factor (decay = 10^(-1.0881 / RT60)).
   - Secondary Allpass Diffuser.
   - Secondary Tank Delay Line.
   - Full Cross-Coupling: Tank 1 outputs into Tank 2, and Tank 2 outputs into Tank 1!
5. **14 Mutually Prime Multi-Tap Output Matrix**:
   Reads 7 mutually prime fractional taps from each tank loop with alternating polarities.
6. **Mid-Side Stereo Width Stage**:
   Mid = 0.5 * (L + R), Side = 0.5 * (L - R) * Width.
"""

from typing import Tuple, List, Optional
import numpy as np


class AllpassDelay:
    """Schroeder/Dattorro 1st-order allpass diffuser."""

    def __init__(self, delay_samples: int, coefficient: float = 0.5):
        self.delay = max(2, int(delay_samples))
        self.coeff = float(coefficient)
        self.buf = np.zeros(self.delay, dtype=np.float32)
        self.idx = 0

    def reset(self):
        self.buf.fill(0.0)
        self.idx = 0

    def process(self, x: float) -> float:
        buf_out = self.buf[self.idx]
        y = -self.coeff * x + buf_out
        self.buf[self.idx] = x + self.coeff * y
        self.idx = (self.idx + 1) % self.delay
        return y


class DattorroReverb:
    """
    Jon Dattorro (1997) Figure-8 Plate/Tank Stereo Reverberator.
    """

    def __init__(
        self,
        sample_rate: float = 48000.0,
        decay_time_s: float = 2.5,
        decay: Optional[float] = None,
        damping: float = 0.3,
        pre_delay_ms: float = 20.0,
        width: float = 1.0,
        wet: float = 0.35,
        dry: float = 1.0,
        **kwargs
    ):
        self.sample_rate = float(sample_rate)
        if decay is not None:
            self.decay_time_s = float(decay * 3.0)
        else:
            self.decay_time_s = float(decay_time_s)
        self.damping = float(damping)
        self.pre_delay_ms = float(pre_delay_ms)
        self.width = float(width)
        self.wet = float(wet)
        self.dry = float(dry)

        self.reset()

    def reset(self):
        fs = self.sample_rate
        scale = fs / 29761.0  # Dattorro's original paper was tuned for 29.761 kHz

        # 4 Input diffusers per channel
        diff_delays = [int(round(d * scale)) for d in [142, 107, 379, 277]]
        self.diff_l = [AllpassDelay(d, 0.75 if i < 2 else 0.625) for i, d in enumerate(diff_delays)]
        self.diff_r = [AllpassDelay(d + 13, 0.75 if i < 2 else 0.625) for i, d in enumerate(diff_delays)]

        # Pre-delay buffer
        pre_samples = max(2, int(round(self.pre_delay_ms * 0.001 * fs)))
        self.pre_buf_l = np.zeros(pre_samples, dtype=np.float32)
        self.pre_buf_r = np.zeros(pre_samples, dtype=np.float32)
        self.pre_idx = 0

        # Tank 1 components
        self.t1_mod_del = max(4, int(round(672 * scale)))
        self.t1_mod_buf = np.zeros(self.t1_mod_del + 32, dtype=np.float32)
        self.t1_mod_idx = 0

        self.t1_del1_len = max(4, int(round(4453 * scale)))
        self.t1_del1_buf = np.zeros(self.t1_del1_len, dtype=np.float32)
        self.t1_del1_idx = 0

        self.t1_ap2 = AllpassDelay(int(round(1800 * scale)), 0.5)

        self.t1_del2_len = max(4, int(round(3720 * scale)))
        self.t1_del2_buf = np.zeros(self.t1_del2_len, dtype=np.float32)
        self.t1_del2_idx = 0

        self.t1_damp_state = 0.0
        self.t1_last_out = 0.0

        # Tank 2 components
        self.t2_mod_del = max(4, int(round(908 * scale)))
        self.t2_mod_buf = np.zeros(self.t2_mod_del + 32, dtype=np.float32)
        self.t2_mod_idx = 0

        self.t2_del1_len = max(4, int(round(4217 * scale)))
        self.t2_del1_buf = np.zeros(self.t2_del1_len, dtype=np.float32)
        self.t2_del1_idx = 0

        self.t2_ap2 = AllpassDelay(int(round(2656 * scale)), 0.5)

        self.t2_del2_len = max(4, int(round(3163 * scale)))
        self.t2_del2_buf = np.zeros(self.t2_del2_len, dtype=np.float32)
        self.t2_del2_idx = 0

        self.t2_damp_state = 0.0
        self.t2_last_out = 0.0

        # LFOs
        self.lfo_phase1 = 0.0
        self.lfo_phase2 = np.pi * 0.5

    def process(self, signal: np.ndarray, right: Optional[np.ndarray] = None) -> np.ndarray:
        if right is not None:
            s = np.column_stack([signal, right]).astype(np.float32)
            is_two_args = True
            is_1d = False
        else:
            s = np.asarray(signal, dtype=np.float32)
            is_two_args = False
            is_1d = (s.ndim == 1)
            if is_1d:
                s = np.column_stack([s, s])

        num_frames = s.shape[0]
        out = np.zeros_like(s)

        # Decay factor from RT60
        decay = min(0.985, float(np.power(10.0, -1.0881 / max(0.1, self.decay_time_s))))
        # Frequency damping cutoff
        damp_hz = 18000.0 * np.power(0.0667, self.damping)
        w_damp = min(np.pi * 0.95, 2.0 * np.pi * damp_hz / self.sample_rate)
        damp_coeff = float(1.0 - np.exp(-w_damp))

        scale = self.sample_rate / 29761.0
        mod_depth = 8.0 * scale
        lfo_inc1 = 2.0 * np.pi * 0.73 / self.sample_rate
        lfo_inc2 = 2.0 * np.pi * 0.91 / self.sample_rate

        for i in range(num_frames):
            in_l = float(s[i, 0])
            in_r = float(s[i, 1])

            # 1. Pre-delay
            pd_l = self.pre_buf_l[self.pre_idx]
            pd_r = self.pre_buf_r[self.pre_idx]
            self.pre_buf_l[self.pre_idx] = in_l
            self.pre_buf_r[self.pre_idx] = in_r
            self.pre_idx = (self.pre_idx + 1) % len(self.pre_buf_l)

            # 2. Input diffusers
            d_in_l = pd_l + 0.20 * pd_r
            d_in_r = pd_r + 0.20 * pd_l
            for ap_l, ap_r in zip(self.diff_l, self.diff_r):
                d_in_l = ap_l.process(d_in_l)
                d_in_r = ap_r.process(d_in_r)

            # 3. Coupled Figure-8 Tank Loops
            t1_in = d_in_l + self.t2_last_out * decay
            t2_in = d_in_r + self.t1_last_out * decay

            # LFO modulation
            mod1 = mod_depth * np.sin(self.lfo_phase1)
            mod2 = mod_depth * np.sin(self.lfo_phase2)
            self.lfo_phase1 = (self.lfo_phase1 + lfo_inc1) % (2.0 * np.pi)
            self.lfo_phase2 = (self.lfo_phase2 + lfo_inc2) % (2.0 * np.pi)

            # --- TANK 1 LOOP ---
            # Modulated allpass
            m_pos1 = (self.t1_mod_idx - self.t1_mod_del - mod1) % len(self.t1_mod_buf)
            m_idx1 = int(np.floor(m_pos1))
            m_frac1 = m_pos1 - m_idx1
            buf1_out = (1.0 - m_frac1) * self.t1_mod_buf[m_idx1] + m_frac1 * self.t1_mod_buf[(m_idx1 + 1) % len(self.t1_mod_buf)]
            t1_ap1_out = -0.7 * t1_in + buf1_out
            self.t1_mod_buf[self.t1_mod_idx] = t1_in + 0.7 * t1_ap1_out
            self.t1_mod_idx = (self.t1_mod_idx + 1) % len(self.t1_mod_buf)

            # Delay 1
            t1_del1_out = self.t1_del1_buf[self.t1_del1_idx]
            self.t1_del1_buf[self.t1_del1_idx] = t1_ap1_out
            self.t1_del1_idx = (self.t1_del1_idx + 1) % self.t1_del1_len

            # Damping LPF
            self.t1_damp_state += damp_coeff * (t1_del1_out - self.t1_damp_state)
            # Allpass 2
            t1_ap2_out = self.t1_ap2.process(self.t1_damp_state)

            # Delay 2
            self.t1_last_out = self.t1_del2_buf[self.t1_del2_idx]
            self.t1_del2_buf[self.t1_del2_idx] = t1_ap2_out
            self.t1_del2_idx = (self.t1_del2_idx + 1) % self.t1_del2_len

            # --- TANK 2 LOOP ---
            m_pos2 = (self.t2_mod_idx - self.t2_mod_del - mod2) % len(self.t2_mod_buf)
            m_idx2 = int(np.floor(m_pos2))
            m_frac2 = m_pos2 - m_idx2
            buf2_out = (1.0 - m_frac2) * self.t2_mod_buf[m_idx2] + m_frac2 * self.t2_mod_buf[(m_idx2 + 1) % len(self.t2_mod_buf)]
            t2_ap1_out = -0.7 * t2_in + buf2_out
            self.t2_mod_buf[self.t2_mod_idx] = t2_in + 0.7 * t2_ap1_out
            self.t2_mod_idx = (self.t2_mod_idx + 1) % len(self.t2_mod_buf)

            t2_del1_out = self.t2_del1_buf[self.t2_del1_idx]
            self.t2_del1_buf[self.t2_del1_idx] = t2_ap1_out
            self.t2_del1_idx = (self.t2_del1_idx + 1) % self.t2_del1_len

            self.t2_damp_state += damp_coeff * (t2_del1_out - self.t2_damp_state)
            t2_ap2_out = self.t2_ap2.process(self.t2_damp_state)

            self.t2_last_out = self.t2_del2_buf[self.t2_del2_idx]
            self.t2_del2_buf[self.t2_del2_idx] = t2_ap2_out
            self.t2_del2_idx = (self.t2_del2_idx + 1) % self.t2_del2_len

            # 4. Multi-Tap Output Extraction
            wet_l = (t2_del1_out + self.t2_last_out - t1_del1_out - self.t1_last_out) * 0.36
            wet_r = (t1_del1_out + self.t1_last_out - t2_del1_out - self.t2_last_out) * 0.36

            # 5. Stereo Width M/S Balance
            mid = 0.5 * (wet_l + wet_r)
            side = 0.5 * (wet_l - wet_r) * self.width
            wet_out_l = mid + side
            wet_out_r = mid - side

            out[i, 0] = in_l * self.dry + wet_out_l * self.wet
            out[i, 1] = in_r * self.dry + wet_out_r * self.wet

        if is_two_args:
            return out[:, 0], out[:, 1]
        return out[:, 0] if is_1d else out


def _prepare_stereo(
    signal: np.ndarray, right: Optional[np.ndarray] = None
) -> tuple[np.ndarray, bool, bool]:
    """Normalize mono, interleaved stereo, or split L/R inputs to (N, 2) float64."""
    if right is not None:
        left_arr = np.asarray(signal, dtype=np.float64).reshape(-1)
        right_arr = np.asarray(right, dtype=np.float64).reshape(-1)
        n = min(len(left_arr), len(right_arr))
        return np.column_stack((left_arr[:n], right_arr[:n])), False, True

    arr = np.asarray(signal, dtype=np.float64)
    if arr.ndim == 1:
        return np.column_stack((arr, arr)), True, False
    if arr.ndim == 2 and arr.shape[1] == 1:
        col = arr[:, 0]
        return np.column_stack((col, col)), False, False
    if arr.ndim == 2 and arr.shape[1] >= 2:
        return arr[:, :2], False, False
    raise ValueError(f"Expected 1D or 2D audio signal, got shape {arr.shape}")


def _format_stereo(
    out: np.ndarray, is_1d: bool, is_two_args: bool
):
    """Return mono 1D, (N, 2) stereo, or (L, R) tuple matching DattorroReverb."""
    out_f32 = out.astype(np.float32, copy=False)
    if is_two_args:
        return out_f32[:, 0], out_f32[:, 1]
    return out_f32[:, 0] if is_1d else out_f32


def _mix_ms_wet_dry(
    in_l: float,
    in_r: float,
    wet_l: float,
    wet_r: float,
    width: float,
    dry: float,
    wet: float,
    clamp_limit: float = 4.0,
) -> tuple[float, float]:
    """Apply M/S stereo width, wet/dry gain, and output safety clamping."""
    mid = 0.5 * (wet_l + wet_r)
    side = 0.5 * (wet_l - wet_r) * width
    out_l = in_l * dry + (mid + side) * wet
    out_r = in_r * dry + (mid - side) * wet
    if out_l > clamp_limit:
        out_l = clamp_limit
    elif out_l < -clamp_limit:
        out_l = -clamp_limit
    if out_r > clamp_limit:
        out_r = clamp_limit
    elif out_r < -clamp_limit:
        out_r = -clamp_limit
    return out_l, out_r


class _DampedCombFilter:
    """Single-pole low-pass damped feedback comb filter."""

    def __init__(self, size: int, feedback: float, damp: float):
        self.size = max(1, int(size))
        self.buf = [0.0] * self.size
        self.idx = 0
        self.filt = 0.0
        self.feedback = float(feedback)
        self.damp = float(damp)

    def step(self, inp: float) -> float:
        buf = self.buf
        idx = self.idx
        out = buf[idx]
        filt = out * (1.0 - self.damp) + self.filt * self.damp
        self.filt = filt
        buf[idx] = inp + filt * self.feedback
        idx += 1
        if idx >= self.size:
            idx = 0
        self.idx = idx
        return out


class _CanonicalAllpass:
    """Fixed-length Schroeder canonical allpass filter."""

    def __init__(self, size: int, coeff: float):
        self.size = max(1, int(size))
        self.buf = [0.0] * self.size
        self.idx = 0
        self.coeff = float(coeff)

    def step(self, inp: float) -> float:
        buf = self.buf
        idx = self.idx
        buf_out = buf[idx]
        g = self.coeff
        v = inp + g * buf_out
        out = buf_out - g * v
        buf[idx] = v
        idx += 1
        if idx >= self.size:
            idx = 0
        self.idx = idx
        return out


class _ModulatedDelayLine:
    """Circular delay line with fractional Catmull-Rom or linear tap reads."""

    def __init__(self, nominal_delay: int, headroom: int = 48):
        self.nominal_delay = max(1, int(nominal_delay))
        self.size = self.nominal_delay + max(8, int(headroom))
        self.buf = [0.0] * self.size
        self.idx = 0

    def write(self, val: float) -> None:
        self.buf[self.idx] = val
        idx = self.idx + 1
        if idx >= self.size:
            idx = 0
        self.idx = idx

    def read_tap(self, tap_samples: int) -> float:
        return self.buf[(self.idx - tap_samples) % self.size]

    def read_linear(self, delay_samples: float) -> float:
        buf = self.buf
        sz = self.size
        read_pos = self.idx - delay_samples
        i0 = int(read_pos // 1)
        frac = read_pos - i0
        idx0 = i0 % sz
        idx1 = (idx0 + 1) % sz
        return buf[idx0] * (1.0 - frac) + buf[idx1] * frac

    def read_catmull_rom(self, delay_samples: float) -> float:
        buf = self.buf
        sz = self.size
        read_pos = self.idx - delay_samples
        i1 = int(read_pos // 1)
        t = read_pos - i1
        t2 = t * t
        t3 = t2 * t
        y0 = buf[(i1 - 1) % sz]
        y1 = buf[i1 % sz]
        y2 = buf[(i1 + 1) % sz]
        y3 = buf[(i1 + 2) % sz]
        c0 = -0.5 * t + t2 - 0.5 * t3
        c1 = 1.0 - 2.5 * t2 + 1.5 * t3
        c2 = 0.5 * t + 2.0 * t2 - 1.5 * t3
        c3 = -0.5 * t2 + 0.5 * t3
        return c0 * y0 + c1 * y1 + c2 * y2 + c3 * y3


class _ModulatedAllpass:
    """Catmull-Rom modulated Schroeder allpass filter."""

    def __init__(self, nominal_delay: int, coeff: float, headroom: int = 48):
        self.delay = _ModulatedDelayLine(nominal_delay, headroom=headroom)
        self.coeff = float(coeff)

    def step(self, inp: float, mod_offset: float = 0.0) -> float:
        max_mod = float(self.delay.size - self.delay.nominal_delay - 3)
        if mod_offset > max_mod:
            mod_offset = max_mod
        elif mod_offset < -(self.delay.nominal_delay - 2):
            mod_offset = -float(self.delay.nominal_delay - 2)
        del_val = self.delay.read_catmull_rom(self.delay.nominal_delay + mod_offset)
        g = self.coeff
        v = inp + g * del_val
        self.delay.write(v)
        return del_val - g * v


class _ParallelCombAllpassBase:
    """Shared stereo 4-comb + N-allpass tank base for Lattice and Diffusion."""

    def __init__(
        self,
        sample_rate: float,
        base_comb_l: tuple[int, ...],
        comb_offset: int,
        base_allpass_l: tuple[int, ...],
        allpass_offset: int,
        t60_sec: float,
        damp: float,
        ap_coeff: float,
        wet: float,
        dry: float,
        width: float,
    ):
        self.sample_rate = float(sample_rate)
        self.wet = float(wet)
        self.dry = float(dry)
        self.width = float(width)

        scale = max(0.25, self.sample_rate / 48000.0)
        self._combs: list[list[_DampedCombFilter]] = [[], []]
        self._allpasses: list[list[_CanonicalAllpass]] = [[], []]

        for ch, offset in enumerate((0, comb_offset)):
            for base_len in base_comb_l:
                sz = max(16, int(round((base_len + offset) * scale)))
                fb = min(0.985, 10.0 ** (-3.0 * sz / (self.sample_rate * t60_sec)))
                self._combs[ch].append(_DampedCombFilter(sz, fb, damp))

        for ch, offset in enumerate((0, allpass_offset)):
            for base_len in base_allpass_l:
                sz = max(8, int(round((base_len + offset) * scale)))
                self._allpasses[ch].append(_CanonicalAllpass(sz, ap_coeff))

    def process(self, signal: np.ndarray, right: Optional[np.ndarray] = None):
        stereo, is_1d, is_two_args = _prepare_stereo(signal, right)
        n = stereo.shape[0]
        out = np.empty((n, 2), dtype=np.float64)

        combs_l, combs_r = self._combs
        aps_l, aps_r = self._allpasses
        width = self.width
        dry = self.dry
        wet = self.wet

        for i in range(n):
            in_l = float(stereo[i, 0])
            in_r = float(stereo[i, 1])

            sum_l = 0.0
            for c in combs_l:
                sum_l += c.step(in_l)
            wet_l = sum_l * 0.25
            for ap in aps_l:
                wet_l = ap.step(wet_l)

            sum_r = 0.0
            for c in combs_r:
                sum_r += c.step(in_r)
            wet_r = sum_r * 0.25
            for ap in aps_r:
                wet_r = ap.step(wet_r)

            out[i, 0], out[i, 1] = _mix_ms_wet_dry(
                in_l, in_r, wet_l, wet_r, width, dry, wet
            )

        return _format_stereo(out, is_1d, is_two_args)


class DiffusionReverbDSP(_ParallelCombAllpassBase):
    """Multi-stage 4-Comb + 4-Allpass diffusion reverb matching C++ DiffusionReverb."""

    BASE_COMB_L = (1051, 1153, 1283, 1399)
    COMB_STEREO_OFFSET = 23
    BASE_ALLPASS_L = (223, 337, 443, 557)
    ALLPASS_STEREO_OFFSET = 16

    def __init__(
        self,
        sample_rate: float = 48000.0,
        wet: float = 0.35,
        dry: float = 0.70,
        room_size: float = 0.70,
        decay_time_ms: Optional[float] = 1500.0,
        diffusion: float = 0.65,
        damping: float = 0.25,
        width: float = 1.0,
    ):
        if decay_time_ms is None:
            decay_ms = 350.0 * (40.0 ** float(room_size))
        else:
            decay_ms = max(100.0, min(15000.0, float(decay_time_ms)))
        t60_sec = max(0.1, decay_ms * 0.001)
        damp = float(damping) * 0.7
        ap_fb = 0.35 + 0.35 * float(diffusion)
        super().__init__(
            sample_rate=sample_rate,
            base_comb_l=self.BASE_COMB_L,
            comb_offset=self.COMB_STEREO_OFFSET,
            base_allpass_l=self.BASE_ALLPASS_L,
            allpass_offset=self.ALLPASS_STEREO_OFFSET,
            t60_sec=t60_sec,
            damp=damp,
            ap_coeff=ap_fb,
            wet=wet,
            dry=dry,
            width=width,
        )


class LatticeReverbDSP(_ParallelCombAllpassBase):
    """Low-coloration 4-Comb + 2-Allpass recursive lattice reverb matching C++ LatticeReverb."""

    BASE_COMB_L = (1116, 1188, 1277, 1356)
    COMB_STEREO_OFFSET = 23
    BASE_ALLPASS_L = (225, 341)
    ALLPASS_STEREO_OFFSET = 13

    def __init__(
        self,
        sample_rate: float = 48000.0,
        wet: float = 0.35,
        dry: float = 0.70,
        room_size: float = 0.75,
        damping: float = 0.25,
        width: float = 1.0,
    ):
        target_rt60 = 0.35 * (40.0 ** float(room_size))
        damp = float(damping) * 0.7
        super().__init__(
            sample_rate=sample_rate,
            base_comb_l=self.BASE_COMB_L,
            comb_offset=self.COMB_STEREO_OFFSET,
            base_allpass_l=self.BASE_ALLPASS_L,
            allpass_offset=self.ALLPASS_STEREO_OFFSET,
            t60_sec=target_rt60,
            damp=damp,
            ap_coeff=0.5,
            wet=wet,
            dry=dry,
            width=width,
        )


class HadamardFdnDSP:
    """8-channel modulated Fast Walsh-Hadamard Feedback Delay Network matching C++ HadamardFDN."""

    NUM_CHANNELS = 8
    BASE_DELAYS = (1321, 1579, 1873, 2179, 2503, 2851, 3167, 3571)
    MOD_RATES = (0.41, 0.53, 0.67, 0.79, 0.97, 1.13, 1.31, 1.49)

    def __init__(
        self,
        sample_rate: float = 48000.0,
        wet: float = 0.35,
        dry: float = 1.0,
        room_size: float = 0.70,
        damping: float = 0.30,
        width: float = 1.0,
    ):
        import math

        self.sample_rate = float(sample_rate)
        self.wet = float(wet)
        self.dry = float(dry)
        self.width = float(width)
        self._sqrt8_inv = 1.0 / math.sqrt(8.0)

        scale = max(0.25, self.sample_rate / 48000.0)
        rt60 = 0.35 * (40.0 ** float(room_size))
        self._damp_factor = 1.0 - float(damping) * 0.85
        self._mod_depth = 2.5 * (self.sample_rate / 48000.0)
        headroom = max(32, int(math.ceil(abs(self._mod_depth))) + 8)

        self._lengths = [max(32, int(round(b * scale))) for b in self.BASE_DELAYS]
        self._delays = [
            _ModulatedDelayLine(length, headroom=headroom) for length in self._lengths
        ]
        self._decay_gains = [
            min(0.995, 10.0 ** (-3.0 * (length / self.sample_rate) / rt60))
            for length in self._lengths
        ]
        self._damp_state = [0.0] * self.NUM_CHANNELS
        self._lfo_phase = [i * 0.785398163 for i in range(self.NUM_CHANNELS)]
        self._lfo_incs = [
            2.0 * math.pi * rate / self.sample_rate for rate in self.MOD_RATES
        ]

    @staticmethod
    def _fwht8(x: list[float], scale_norm: float) -> list[float]:
        y = list(x)
        # Stage 1: stride 1
        for k in range(0, 8, 2):
            a, b = y[k], y[k + 1]
            y[k], y[k + 1] = a + b, a - b
        # Stage 2: stride 2
        for k in (0, 4):
            for j in range(2):
                a, b = y[k + j], y[k + j + 2]
                y[k + j], y[k + j + 2] = a + b, a - b
        # Stage 3: stride 4
        for j in range(4):
            a, b = y[j], y[j + 4]
            y[j], y[j + 4] = (a + b) * scale_norm, (a - b) * scale_norm
        return y

    def process(self, signal: np.ndarray, right: Optional[np.ndarray] = None):
        import math

        stereo, is_1d, is_two_args = _prepare_stereo(signal, right)
        n = stereo.shape[0]
        out = np.empty((n, 2), dtype=np.float64)

        sin = math.sin
        two_pi = 2.0 * math.pi
        delays = self._delays
        lengths = self._lengths
        decay_gains = self._decay_gains
        damp_state = self._damp_state
        damp_factor = self._damp_factor
        phases = self._lfo_phase
        incs = self._lfo_incs
        mod_depth = self._mod_depth
        sqrt8_inv = self._sqrt8_inv
        width = self.width
        dry = self.dry
        wet = self.wet

        ch_out = [0.0] * 8
        for i in range(n):
            in_l = float(stereo[i, 0])
            in_r = float(stereo[i, 1])

            for c in range(8):
                ph = phases[c]
                del_val = delays[c].read_linear(lengths[c] + sin(ph) * mod_depth)
                ph += incs[c]
                if ph >= two_pi:
                    ph -= two_pi
                phases[c] = ph
                damp_state[c] += damp_factor * (del_val - damp_state[c])
                ch_out[c] = damp_state[c] * decay_gains[c]

            matrix_out = self._fwht8(ch_out, sqrt8_inv)
            half_l = 0.5 * in_l
            half_r = 0.5 * in_r
            delays[0].write(half_l + matrix_out[0])
            delays[1].write(-half_l + matrix_out[1])
            delays[2].write(half_l + matrix_out[2])
            delays[3].write(-half_l + matrix_out[3])
            delays[4].write(half_r + matrix_out[4])
            delays[5].write(-half_r + matrix_out[5])
            delays[6].write(half_r + matrix_out[6])
            delays[7].write(-half_r + matrix_out[7])

            wet_l = (ch_out[0] + ch_out[2] + ch_out[4] + ch_out[6]) * 0.5
            wet_r = (ch_out[1] - ch_out[3] + ch_out[5] - ch_out[7]) * 0.5
            out[i, 0], out[i, 1] = _mix_ms_wet_dry(
                in_l, in_r, wet_l, wet_r, width, dry, wet
            )

        return _format_stereo(out, is_1d, is_two_args)


class BarrRingReverbDSP:
    """Keith Barr 4-stage cascaded allpass ring reverb matching C++ BarrRingReverb."""

    BASE_IN_DIFF_L = (156, 223, 332, 548)
    BASE_IN_DIFF_R = (186, 253, 302, 498)
    BASE_AP_A = (1251, 943, 1282, 1174)
    BASE_AP_B = (1551, 1343, 1381, 1382)
    BASE_DELAYS = (2859, 3145, 2476, 3568)
    BASE_TAP_L = (2630, 1943, 1200, 2016)
    BASE_TAP_R = (2420, 1631, 1163, 2330)
    TAP_GAINS = (0.8, 0.7, 0.6, 0.5)

    def __init__(
        self,
        sample_rate: float = 48000.0,
        wet: float = 0.35,
        dry: float = 1.0,
        room_size: float = 0.70,
        damping: float = 0.30,
        width: float = 1.0,
    ):
        import math

        self.sample_rate = float(sample_rate)
        self.wet = float(wet)
        self.dry = float(dry)
        self.width = float(width)

        scale = max(0.25, self.sample_rate / 32768.0)
        self._krt = min(0.985, 10.0 ** (-3.0 * 0.1702 / (0.35 * (40.0 ** float(room_size)))))
        self._lpf_coeff = 1.0 - float(damping) * 0.75
        self._mod_depth = 8.0 * (self.sample_rate / 32768.0)
        headroom = max(32, int(math.ceil(abs(self._mod_depth))) + 8)
        self._lfo_phase = 0.0
        self._lfo_inc = 2.0 * math.pi * 0.5 / self.sample_rate

        self._in_diff_l = [
            _CanonicalAllpass(max(16, int(round(b * scale))), 0.6)
            for b in self.BASE_IN_DIFF_L
        ]
        self._in_diff_r = [
            _CanonicalAllpass(max(16, int(round(b * scale))), 0.6)
            for b in self.BASE_IN_DIFF_R
        ]
        self._ap_a = [
            _ModulatedAllpass(max(32, int(round(b * scale))), 0.6, headroom=headroom)
            for b in self.BASE_AP_A
        ]
        self._ap_b = [
            _CanonicalAllpass(max(32, int(round(b * scale))), 0.5)
            for b in self.BASE_AP_B
        ]
        self._stage_delays = [
            _ModulatedDelayLine(max(64, int(round(b * scale))), headroom=8)
            for b in self.BASE_DELAYS
        ]
        self._taps_l = [
            min(self._stage_delays[s].nominal_delay - 1, max(1, int(round(self.BASE_TAP_L[s] * scale))))
            for s in range(4)
        ]
        self._taps_r = [
            min(self._stage_delays[s].nominal_delay - 1, max(1, int(round(self.BASE_TAP_R[s] * scale))))
            for s in range(4)
        ]
        self._lpf_state = [0.0, 0.0, 0.0, 0.0]
        self._del_out = [0.0, 0.0, 0.0, 0.0]

    def process(self, signal: np.ndarray, right: Optional[np.ndarray] = None):
        import math

        stereo, is_1d, is_two_args = _prepare_stereo(signal, right)
        n = stereo.shape[0]
        out = np.empty((n, 2), dtype=np.float64)

        sin = math.sin
        cos = math.cos
        two_pi = 2.0 * math.pi
        in_diff_l = self._in_diff_l
        in_diff_r = self._in_diff_r
        ap_a = self._ap_a
        ap_b = self._ap_b
        delays = self._stage_delays
        taps_l = self._taps_l
        taps_r = self._taps_r
        tap_gains = self.TAP_GAINS
        lpf_state = self._lpf_state
        del_out = self._del_out
        krt = self._krt
        lpf_coeff = self._lpf_coeff
        mod_depth = self._mod_depth
        lfo_phase = self._lfo_phase
        lfo_inc = self._lfo_inc
        width = self.width
        dry = self.dry
        wet = self.wet

        for i in range(n):
            in_l = float(stereo[i, 0])
            in_r = float(stereo[i, 1])

            d_in_l = in_l * 0.6
            for ap in in_diff_l:
                d_in_l = ap.step(d_in_l)

            d_in_r = in_r * 0.6
            for ap in in_diff_r:
                d_in_r = ap.step(d_in_r)

            stage_ins = (
                del_out[3] * krt + d_in_l,
                del_out[0] * krt + d_in_r,
                del_out[1] * krt + d_in_l,
                del_out[2] * krt + d_in_r,
            )
            mod_offsets = (
                sin(lfo_phase) * mod_depth,
                0.0,
                cos(lfo_phase) * mod_depth,
                0.0,
            )
            lfo_phase += lfo_inc
            if lfo_phase >= two_pi:
                lfo_phase -= two_pi

            tap_sum_l = 0.0
            tap_sum_r = 0.0
            for s in range(4):
                x = ap_a[s].step(stage_ins[s], mod_offsets[s])
                x = ap_b[s].step(x)
                lpf_state[s] += lpf_coeff * (x - lpf_state[s])
                delays[s].write(lpf_state[s])
                del_out[s] = delays[s].read_tap(delays[s].nominal_delay)
                tap_sum_l += delays[s].read_tap(taps_l[s]) * tap_gains[s]
                tap_sum_r += delays[s].read_tap(taps_r[s]) * tap_gains[s]

            out[i, 0], out[i, 1] = _mix_ms_wet_dry(
                in_l, in_r, tap_sum_l * 0.32, tap_sum_r * 0.32, width, dry, wet
            )

        self._lfo_phase = lfo_phase
        return _format_stereo(out, is_1d, is_two_args)


class _GriesingerTankHalf:
    """One half of the cross-coupled Griesinger Spin & Wander tank."""

    def __init__(
        self,
        ap1_len: int,
        del1_len: int,
        ap2_len: int,
        del2_len: int,
        taps: tuple[int, ...],
        scale: float,
        headroom: int,
    ):
        self.ap1 = _ModulatedAllpass(max(16, int(round(ap1_len * scale))), 0.7, headroom=headroom)
        self.del1 = _ModulatedDelayLine(max(32, int(round(del1_len * scale))), headroom=headroom)
        self.ap2 = _CanonicalAllpass(max(16, int(round(ap2_len * scale))), 0.5)
        self.del2 = _ModulatedDelayLine(max(32, int(round(del2_len * scale))), headroom=8)
        self.taps = [max(1, int(round(t * scale))) for t in taps]
        self.damp_state = 0.0
        self.last_out = 0.0

    def step(
        self,
        inp: float,
        spin_offset: float,
        wander_offset: float,
        damp_coeff: float,
        decay_gain: float,
    ) -> float:
        x = self.ap1.step(inp, spin_offset)
        self.del1.write(x)
        d1 = self.del1.read_linear(self.del1.nominal_delay + wander_offset)
        self.damp_state += damp_coeff * (d1 - self.damp_state)
        x = self.ap2.step(self.damp_state * decay_gain)
        self.del2.write(x)
        self.last_out = self.del2.read_tap(self.del2.nominal_delay)
        return self.last_out


class GriesingerTankDSP:
    """David Griesinger Spin & Wander modulated stereo reverb tank matching C++ GriesingerTank."""

    BASE_DIFF = (142, 107, 379, 277)
    DIFF_COEFFS = (0.75, 0.75, 0.625, 0.625)
    BASE_TAPS_T1 = (266, 2974, 1913, 1996, 198, 3689)
    BASE_TAPS_T2 = (353, 3627, 1228, 2673, 1066, 2980)

    def __init__(
        self,
        sample_rate: float = 48000.0,
        wet: float = 0.35,
        dry: float = 1.0,
        room_size: float = 0.70,
        damping: float = 0.30,
        width: float = 1.0,
    ):
        import math

        self.sample_rate = float(sample_rate)
        self.wet = float(wet)
        self.dry = float(dry)
        self.width = float(width)

        scale = max(0.25, self.sample_rate / 29761.0)
        self._decay_gain = min(
            0.985, 10.0 ** (-3.0 * 0.3627 / (0.35 * (40.0 ** float(room_size))))
        )
        self._damp_coeff = 1.0 - float(damping) * 0.80

        self._spin_depth = 8.0 * scale
        self._wander_depth = 12.0 * scale
        headroom = max(48, int(math.ceil(self._spin_depth + self._wander_depth)) + 16)

        self._spin_phase1 = 0.0
        self._spin_phase2 = 0.5 * math.pi
        self._spin_inc1 = 2.0 * math.pi * 0.75 / self.sample_rate
        self._spin_inc2 = 2.0 * math.pi * 1.10 / self.sample_rate

        self._lcg_seed1 = 0x12345678
        self._lcg_seed2 = 0x9ABCDEF0
        self._wander_period = max(16, int(round(128.0 * scale)))
        self._wander_counter = 0
        self._wander_smooth = 1.0 - math.exp(-1.0 / (0.0067 * self.sample_rate))
        self._wander_target1 = 0.0
        self._wander_target2 = 0.0
        self._wander_state1 = 0.0
        self._wander_state2 = 0.0

        self._in_diff_l = [
            _CanonicalAllpass(max(16, int(round(b * scale))), c)
            for b, c in zip(self.BASE_DIFF, self.DIFF_COEFFS)
        ]
        self._in_diff_r = [
            _CanonicalAllpass(max(16, int(round(b * scale))), c)
            for b, c in zip(self.BASE_DIFF, self.DIFF_COEFFS)
        ]
        self._t1 = _GriesingerTankHalf(
            672, 4453, 1800, 3720, self.BASE_TAPS_T1, scale, headroom
        )
        self._t2 = _GriesingerTankHalf(
            908, 4217, 2656, 3163, self.BASE_TAPS_T2, scale, headroom
        )

    def process(self, signal: np.ndarray, right: Optional[np.ndarray] = None):
        import math

        stereo, is_1d, is_two_args = _prepare_stereo(signal, right)
        n = stereo.shape[0]
        out = np.empty((n, 2), dtype=np.float64)

        sin = math.sin
        two_pi = 2.0 * math.pi
        in_diff_l = self._in_diff_l
        in_diff_r = self._in_diff_r
        t1 = self._t1
        t2 = self._t2
        decay_gain = self._decay_gain
        damp_coeff = self._damp_coeff
        spin_depth = self._spin_depth
        wander_depth = self._wander_depth
        sp1 = self._spin_phase1
        sp2 = self._spin_phase2
        inc1 = self._spin_inc1
        inc2 = self._spin_inc2
        wander_period = self._wander_period
        wander_counter = self._wander_counter
        wander_smooth = self._wander_smooth
        wt1 = self._wander_target1
        wt2 = self._wander_target2
        ws1 = self._wander_state1
        ws2 = self._wander_state2
        seed1 = self._lcg_seed1
        seed2 = self._lcg_seed2
        width = self.width
        dry = self.dry
        wet = self.wet

        t1_taps = t1.taps
        t2_taps = t2.taps

        for i in range(n):
            in_l = float(stereo[i, 0])
            in_r = float(stereo[i, 1])

            d_in_l = in_l
            for ap in in_diff_l:
                d_in_l = ap.step(d_in_l)

            d_in_r = in_r
            for ap in in_diff_r:
                d_in_r = ap.step(d_in_r)

            if wander_counter == 0:
                seed1 = (seed1 * 1664525 + 1013904223) & 0xFFFFFFFF
                seed2 = (seed2 * 1664525 + 1013904223) & 0xFFFFFFFF
                wt1 = (seed1 / 2147483647.5) - 1.0
                wt2 = (seed2 / 2147483647.5) - 1.0
            wander_counter += 1
            if wander_counter >= wander_period:
                wander_counter = 0

            ws1 += wander_smooth * (wt1 - ws1)
            ws2 += wander_smooth * (wt2 - ws2)

            spin_off1 = sin(sp1) * spin_depth
            spin_off2 = sin(sp2) * spin_depth
            sp1 += inc1
            if sp1 >= two_pi:
                sp1 -= two_pi
            sp2 += inc2
            if sp2 >= two_pi:
                sp2 -= two_pi

            t1_in = d_in_l + t2.last_out * decay_gain
            t2_in = d_in_r + t1.last_out * decay_gain

            t1.step(t1_in, spin_off1, ws1 * wander_depth, damp_coeff, decay_gain)
            t2.step(t2_in, spin_off2, ws2 * wander_depth, damp_coeff, decay_gain)

            wet_l = (
                t1.del1.read_tap(t1_taps[0])
                + t1.del1.read_tap(t1_taps[1])
                - t1.del2.read_tap(t1_taps[2])
                + t2.del1.read_tap(t2_taps[0])
                - t2.del2.read_tap(t2_taps[1])
                - t2.del2.read_tap(t2_taps[2])
            ) * 0.28
            wet_r = (
                t2.del1.read_tap(t2_taps[3])
                + t2.del1.read_tap(t2_taps[4])
                - t2.del2.read_tap(t2_taps[5])
                + t1.del1.read_tap(t1_taps[3])
                - t1.del2.read_tap(t1_taps[4])
                - t1.del2.read_tap(t1_taps[5])
            ) * 0.28

            out[i, 0], out[i, 1] = _mix_ms_wet_dry(
                in_l, in_r, wet_l, wet_r, width, dry, wet
            )

        self._spin_phase1 = sp1
        self._spin_phase2 = sp2
        self._wander_counter = wander_counter
        self._wander_target1 = wt1
        self._wander_target2 = wt2
        self._wander_state1 = ws1
        self._wander_state2 = ws2
        self._lcg_seed1 = seed1
        self._lcg_seed2 = seed2

        return _format_stereo(out, is_1d, is_two_args)

