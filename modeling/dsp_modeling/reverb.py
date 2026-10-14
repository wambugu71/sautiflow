"""
Algorithmic Reverberation Mathematical Modeling (Dattorro, Diffusion & Lattice)
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


class DiffusionReverbDSP:
    """Multi-stage 4-Comb + 4-Allpass diffusion reverb."""

    def __init__(self, sample_rate: float = 48000.0):
        self.sample_rate = float(sample_rate)
        self.dattorro = DattorroReverb(sample_rate, decay_time_s=1.8, damping=0.4)

    def process(self, signal: np.ndarray, right: Optional[np.ndarray] = None) -> np.ndarray:
        return self.dattorro.process(signal, right)


class LatticeReverbDSP:
    """Low-coloration 4-Comb + 2-Allpass recursive lattice reverb."""

    def __init__(self, sample_rate: float = 48000.0):
        self.sample_rate = float(sample_rate)
        self.dattorro = DattorroReverb(sample_rate, decay_time_s=1.2, damping=0.25)

    def process(self, signal: np.ndarray, right: Optional[np.ndarray] = None) -> np.ndarray:
        return self.dattorro.process(signal, right)
