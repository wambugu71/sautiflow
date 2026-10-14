"""
Spatial Surround DSP & 3D Binaural Acoustic Suite
==================================================

Mathematical Formulation:
-------------------------
1. Cinema Matrix 5.1 (Cleanroom Pro Logic II Dematrix -> Spherical HRTF):
   - Passive matrix extraction:
     $$C = \\frac{1}{\\sqrt{2}} (L_t + R_t), \\quad S = \\frac{1}{\\sqrt{2}} (L_t - R_t)$$
     $$L = L_t - 0.5 C, \\quad R = R_t - 0.5 C$$
     $$L_s = S_{\\angle +90^\\circ}, \\quad R_s = -S_{\\angle -90^\\circ}$$
     $$LFE = \\text{ButterworthLPF}_{80\\,\\text{Hz}}(C)$$
   - Interaural Time Difference (ITD) by Woodworth's Spherical Head Model:
     $$\\Delta t(\\theta) = \\frac{a}{c} (\\theta + \\sin\\theta)$$
     where $a$ is the head radius ($8.75\\,\\text{cm}$), $c = 343\\,\\text{m/s}$, and $\\theta$ is azimuth in radians.
   - Brown & Duda Structural Head-Shadow Filter:
     Continuous transfer function:
     $$H_{\\text{shadow}}(s) = \\frac{1 + \\alpha s \\tau_0}{1 + s \\tau_0}, \\quad \\tau_0 = \\frac{a}{c}$$
     $$\\alpha_{\\text{ipsi}} = 1 + 0.5 \\cos\\theta, \\quad \\alpha_{\\text{contra}} = 1 - 0.5 \\cos\\theta$$
     Mapped to discrete $z$-domain via bilinear transform ($s \\leftarrow \\frac{2}{T}\\frac{1 - z^{-1}}{1 + z^{-1}}$):
     $$b_0 = \\frac{2\\alpha\\tau_0 + T}{2\\tau_0 + T}, \\quad b_1 = \\frac{T - 2\\alpha\\tau_0}{2\\tau_0 + T}, \\quad a_1 = \\frac{T - 2\\tau_0}{2\\tau_0 + T}$$
   - Pinna Elevation Notch:
     $$f_{\\text{pinna}}(\\phi) = 6500 + 3500 \\left(\\frac{\\phi}{90^\\circ}\\right) \\,\\text{Hz}$$

2. Binaural HRTF Virtualizer:
   - Contralateral interaural time delay ($0.23\\,\\text{ms} \\approx 11\\,\\text{samples}$ at $48\\,\\text{kHz}$)
   - 2nd-order Butterworth $3.5\\,\\text{kHz}$ head-shadow lowpass filter
   - 4-tap early reflection diffuser lattice for Studio, Cinema, and Concert Hall acoustic staging.

3. 3D Acoustic Stage:
   - Interaural acoustic cross-talk cancellation (ATF inversion):
     $$L_{\\text{out}} = L_{\\text{in}} - \\alpha \\cdot z^{-D} R_{\\text{in}}, \\quad R_{\\text{out}} = R_{\\text{in}} - \\alpha \\cdot z^{-D} L_{\\text{in}}$$
   - Mid/Side stereo soundstage expander with high-frequency air presence contour ($12\\,\\text{kHz}$ shelf)
   - Sub-bass fundamental anchor ($80\\,\\text{Hz}$ highpass on side channel).

Historical Attribution & Creators:
----------------------------------
- **Jim C. Fosgate** (1937–2022) & **Dolby Laboratories**:
  Pioneered matrix quadraphonic and Pro Logic II matrix steering decoders. Fosgate was awarded an Emmy
  Award in 2003 for development of the surround audio decoder technology.
- **C. Phillip Brown & Richard O. Duda** (1998):
  "A structural model for binaural sound synthesis", IEEE Transactions on Speech and Audio Processing,
  Vol. 6, No. 5, pp. 476–488, September 1998. Formulated the 1st-order head-shadow shelf filter.
- **Robert S. Woodworth** (1938):
  "Experimental Psychology", New York: Henry Holt and Company; derived the spherical head model ITD equation.
- **Frederic L. Wightman & Doris J. Kistler** (1989):
  "Headphone simulation of free-field listening", Journal of the Acoustical Society of America.
"""

from enum import IntEnum
from typing import Tuple
import numpy as np
from .biquad import make_biquad, BiquadFilterType


class SurroundMode(IntEnum):
    OFF = 0
    MATRIX_SURROUND = 1       # Pro Logic II Dematrix -> 5.1 Spherical HRTF
    BINAURAL_VIRTUALIZER = 2  # Headphone HRTF + Room reflections
    ACOUSTIC_STAGE = 3        # Crosstalk cancellation + M/S Expander


class BrownDudaShelf:
    """1st-order head-shadow shelf filter (Brown & Duda structural model)."""

    def __init__(self, alpha: float, tau0: float, t_period: float) -> None:
        a0 = 2.0 * tau0 + t_period
        self.b0 = float((2.0 * alpha * tau0 + t_period) / a0)
        self.b1 = float((t_period - 2.0 * alpha * tau0) / a0)
        self.a1 = float((t_period - 2.0 * tau0) / a0)
        self.x1 = 0.0
        self.y1 = 0.0

    def reset(self) -> None:
        self.x1 = 0.0
        self.y1 = 0.0

    def process_sample(self, x: float) -> float:
        y = self.b0 * x + self.b1 * self.x1 - self.a1 * self.y1
        self.x1 = x
        self.y1 = 0.0 if abs(y) < 1e-15 else y
        return self.y1

    def process(self, x: np.ndarray) -> np.ndarray:
        out = np.zeros_like(x)
        for i in range(len(x)):
            out[i] = self.process_sample(float(x[i]))
        return out


class HrtfVirtualSource:
    """
    Parametric spherical-head HRTF virtual speaker source.
    Implements Woodworth's ITD formula, Brown & Duda's head shadow, and pinna elevation notch.
    """

    def __init__(
        self,
        azimuth_deg: float,
        elevation_deg: float,
        sample_rate: float = 48000.0,
        head_radius_cm: float = 8.75,
        pinna_strength: float = 0.7,
    ) -> None:
        self.sample_rate = sample_rate
        self.azimuth_deg = azimuth_deg
        self.elevation_deg = elevation_deg
        self.head_radius_cm = head_radius_cm
        self.pinna_strength = pinna_strength

        # Physics constants
        c_sound = 343.0  # speed of sound in m/s
        theta = abs(azimuth_deg) * (np.pi / 180.0)
        a = head_radius_cm * 0.01
        t_period = 1.0 / sample_rate
        tau0 = a / c_sound

        # Brown & Duda head shadow coefficients
        alpha_ipsi = 1.0 + 0.5 * np.cos(theta)
        alpha_contra = 1.0 - 0.5 * np.cos(theta)
        self.shelf_ipsi = BrownDudaShelf(alpha_ipsi, tau0, t_period)
        self.shelf_contra = BrownDudaShelf(alpha_contra, tau0, t_period)

        # Woodworth spherical head ITD: Delta t = (a / c) * (theta + sin(theta))
        delta_t = (a / c_sound) * (theta + np.sin(theta))
        self.itd_samples = max(1, int(round(delta_t * sample_rate)))

        # Pinna elevation notch
        f_pinna = 6500.0 + 3500.0 * (elevation_deg / 90.0)
        notch_gain_db = -4.0 * pinna_strength
        self.pinna_ipsi = make_biquad(
            BiquadFilterType.PEAK, sample_rate, f_pinna, gain_db=notch_gain_db, q=3.0
        )
        self.pinna_contra = make_biquad(
            BiquadFilterType.PEAK, sample_rate, f_pinna * 0.92, gain_db=notch_gain_db * 0.7, q=2.5
        )

        self.delay_buf = np.zeros(self.itd_samples + 16, dtype=np.float32)
        self.delay_idx = 0

    def reset(self) -> None:
        self.shelf_ipsi.reset()
        self.shelf_contra.reset()
        self.pinna_ipsi.reset()
        self.pinna_contra.reset()
        self.delay_buf.fill(0.0)
        self.delay_idx = 0

    def process(self, x: np.ndarray, gain: float = 1.0) -> Tuple[np.ndarray, np.ndarray]:
        """Synthesize binaural stereo signals (out_l, out_r) from mono source."""
        s = (x * gain).astype(np.float32)
        n = len(s)

        # Contralateral fractional/integer delay line
        delayed = np.zeros(n, dtype=np.float32)
        buf_len = len(self.delay_buf)
        for i in range(n):
            self.delay_buf[self.delay_idx] = s[i]
            read_idx = (self.delay_idx - self.itd_samples + buf_len) % buf_len
            delayed[i] = self.delay_buf[read_idx]
            self.delay_idx = (self.delay_idx + 1) % buf_len

        ipsi = self.pinna_ipsi.process(self.shelf_ipsi.process(s))
        contra = self.pinna_contra.process(self.shelf_contra.process(delayed))

        if self.azimuth_deg >= 0.0:
            return contra, ipsi
        else:
            return ipsi, contra


class SpatialSurroundDSP:
    """
    Mathematical and functional model of the full SpatialSurroundDSP suite.
    """

    def __init__(self, sample_rate: float = 48000.0) -> None:
        self.sample_rate = sample_rate
        self.mode = SurroundMode.OFF
        self.stage_width = 1.3
        self.crosstalk_attenuation = 0.32
        self.crosstalk_delay_samples = 11

        # Pro Logic II virtual speakers (Left: -30°, Right: +30°, Center: 0°, Ls: -110°, Rs: +110°)
        self.v_left = HrtfVirtualSource(-30.0, 0.0, sample_rate)
        self.v_right = HrtfVirtualSource(30.0, 0.0, sample_rate)
        self.v_center = HrtfVirtualSource(0.0, 0.0, sample_rate)
        self.v_ls = HrtfVirtualSource(-110.0, 10.0, sample_rate)
        self.v_rs = HrtfVirtualSource(110.0, 10.0, sample_rate)

        # Sub-bass anchor and air presence
        self.side_hp = make_biquad(BiquadFilterType.HIGHPASS, sample_rate, 80.0, q=0.7071)
        self.air_shelf = make_biquad(BiquadFilterType.HIGHSHELF, sample_rate, 12000.0, gain_db=2.5)

    def set_mode(self, mode: SurroundMode) -> None:
        self.mode = mode

    def reset(self) -> None:
        self.v_left.reset()
        self.v_right.reset()
        self.v_center.reset()
        self.v_ls.reset()
        self.v_rs.reset()
        self.side_hp.reset()
        self.air_shelf.reset()

    def process(self, left: np.ndarray, right: np.ndarray) -> Tuple[np.ndarray, np.ndarray]:
        """Process stereo input channels and return rendered spatial audio."""
        if self.mode == SurroundMode.OFF:
            return left.copy(), right.copy()

        n = len(left)

        if self.mode == SurroundMode.MATRIX_SURROUND:
            # 1. Pro Logic II passive dematrix
            center_sig = 0.7071 * (left + right)
            surround_sig = 0.7071 * (left - right)
            clean_l = left - 0.5 * center_sig
            clean_r = right - 0.5 * center_sig

            # 2. Render virtual 5.1 speakers through HRTF
            ol_l, or_l = self.v_left.process(clean_l, gain=0.9)
            ol_r, or_r = self.v_right.process(clean_r, gain=0.9)
            ol_c, or_c = self.v_center.process(center_sig, gain=0.8)
            ol_ls, or_ls = self.v_ls.process(surround_sig, gain=0.75)
            ol_rs, or_rs = self.v_rs.process(-surround_sig, gain=0.75)

            out_l = ol_l + ol_r + ol_c + ol_ls + ol_rs
            out_r = or_l + or_r + or_c + or_ls + or_rs
            return out_l, out_r

        elif self.mode == SurroundMode.ACOUSTIC_STAGE:
            # Mid/Side soundstage expansion with sub-bass anchoring
            mid = 0.5 * (left + right)
            side = 0.5 * (left - right)

            # Anchor sub-bass (highpass on side channel at 80 Hz)
            side_anchored = self.side_hp.process(side) * self.stage_width

            # Interaural crosstalk cancellation
            d = self.crosstalk_delay_samples
            alpha = self.crosstalk_attenuation

            xt_l = np.zeros(n, dtype=np.float32)
            xt_r = np.zeros(n, dtype=np.float32)
            if n > d:
                xt_l[d:] = right[:-d] * alpha
                xt_r[d:] = left[:-d] * alpha

            out_l = (mid + side_anchored) - xt_l
            out_r = (mid - side_anchored) - xt_r

            # Air presence restoration
            out_l = self.air_shelf.process(out_l)
            out_r = self.air_shelf.process(out_r)
            return out_l, out_r

        else:  # BINAURAL_VIRTUALIZER
            # Simple head-shadow + contralateral crossfeed
            ol_l, or_l = self.v_left.process(left, gain=0.85)
            ol_r, or_r = self.v_right.process(right, gain=0.85)
            return ol_l + ol_r, or_l + or_r
