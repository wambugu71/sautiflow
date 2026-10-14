"""
OpenStage Spherical-Head Acoustic Crossfeed Mathematical Modeling
=================================================================

Creators & Historical Foundations:
----------------------------------
- **Duplex Theory of Sound Localization**: Lord Rayleigh (John William Strutt, 3rd Baron Rayleigh)
  ("On our perception of sound direction", Philosophical Magazine, Vol. 13, No. 74, 1907).
- **Binaural Acoustic Crossfeed Circuits**: Benjamin B. Bauer
  ("Stereophonic Earphones and Binaural Loudspeakers", J. Audio Eng. Soc., Vol. 9, No. 2, 1961).
- **Physical Head-Diffraction Acoustics**: Siegfried Linkwitz
  ("Acoustic Crossfeed for Headphone Listening", Audio Magazine, 1980).

Acoustic Physics & Diffraction Principles
-----------------------------------------
When listening to loudspeakers in a room, the acoustic sound from the left speaker arrives at the left ear
(ipsilateral) first, and then diffracts around the spherical head to reach the right ear (contralateral)
attenuated at high frequencies and delayed in time. Headphones isolate each ear completely, producing
an unnatural "in-the-center-of-the-head" sensation and rapid listening fatigue.

OpenStage models real-world physical diffraction:

1. **Interaural Time Difference (ITD) via Law of Cosines**:
   Head diameter w = 0.15 m, speaker distance d = 1.0 m, speed of sound c = 340 m/s:
       halfTheta = (angle_deg / 2) * (pi / 180)
       d_far_sq  = d^2 + (w/2)^2 + w * d * sin(halfTheta)
       d_near_sq = d^2 + (w/2)^2 - w * d * sin(halfTheta)
       ITD = (sqrt(d_far_sq) - sqrt(d_near_sq)) / c

2. **Frequency-Dependent Head-Shadow Shelving Filters**:
   Acoustic cutoff frequency: f_low = min(0.5 / ITD, 2000 Hz), f_high = f_low / 3:
   - **Contralateral (Cross Ear)**: Low-shelf filter (+9 dB boost, slope S=0.4, -12 dB post-gain)
     replicating high-frequency head occlusion.
   - **Ipsilateral (Direct Ear)**: High-shelf filter (+3 dB boost, slope S=0.4, -3 dB post-gain)
     preserving direct high-frequency pinna brilliance.

3. **Bilinear 2nd-Order All-Pass Phase Delay**:
   Calculates the low-shelf filter's intrinsic DC group delay tau_dc:
       tau_dc = (1/fs) * [ (b1 + 2*b2)/(b0 + b1 + b2) - (a1 + 2*a2)/(1 + a1 + a2) ]
   Compensates the remaining delay tau_rem = max(0, ITD - tau_dc) with a bilinear all-pass section:
       k = tau_rem * 0.5 * fs,   v = (1 - k) / (1 + k)
       H_ap(z) = [ (v + z^-1) / (1 + v*z^-1) ]^2
"""

from typing import Optional
import numpy as np

from .biquad import Biquad


class OpenStageDSP:
    """
    Spherical-Head Acoustic Crossfeed and Soundstage Virtualizer.
    """

    HEAD_WIDTH_M = 0.15       # 15 cm adult head diameter
    SPEAKER_DIST_M = 1.00     # 1 meter nearfield distance
    SPEED_OF_SOUND_MPS = 340.0

    def __init__(
        self,
        sample_rate: float = 48000.0,
        angle_deg: float = 60.0,
        gain_db: float = -1.0,
        mix: float = 1.0
    ):
        self.sample_rate = float(sample_rate)
        self.angle_deg = float(np.clip(angle_deg, 0.0, 90.0))
        self.gain_db = float(gain_db)
        self.mix = float(np.clip(mix, 0.0, 1.0))

        self.reset()

    @classmethod
    def compute_itd(cls, angle_degrees: float) -> float:
        """Compute interaural time difference in seconds using Law of Cosines."""
        half_theta = np.deg2rad(angle_degrees * 0.5)
        sin_half = np.sin(half_theta)

        w = cls.HEAD_WIDTH_M
        d = cls.SPEAKER_DIST_M
        c = cls.SPEED_OF_SOUND_MPS

        d_far_sq = d * d + (w * w * 0.25) + (w * d * sin_half)
        d_near_sq = d * d + (w * w * 0.25) - (w * d * sin_half)

        d_far = np.sqrt(max(0.0, d_far_sq))
        d_near = np.sqrt(max(0.0, d_near_sq))

        return float((d_far - d_near) / c)

    @staticmethod
    def _make_shelf(fs: float, fc: float, shelf_gain_db: float, slope: float, post_gain_db: float, is_low: bool) -> Biquad:
        A = np.power(10.0, shelf_gain_db / 40.0)
        w0 = np.clip(2.0 * np.pi * fc / fs, 0.0001, np.pi * 0.95)
        cos_w0 = np.cos(w0)
        sin_w0 = np.sin(w0)

        inv_q = np.sqrt(max(0.0, (A + 1.0 / A) * (1.0 / slope - 1.0) + 2.0))
        alpha = sin_w0 * 0.5 * inv_q
        two_sqrt_a_alpha = 2.0 * np.sqrt(A) * alpha
        post_lin = np.power(10.0, post_gain_db / 20.0)

        plus = A + 1.0
        minus = A - 1.0
        plus_cos = plus * cos_w0
        minus_cos = minus * cos_w0

        if is_low:
            b0 = A * (plus - minus_cos + two_sqrt_a_alpha) * post_lin
            b1 = 2.0 * A * (minus - plus_cos) * post_lin
            b2 = A * (plus - minus_cos - two_sqrt_a_alpha) * post_lin
            a0 = plus + minus_cos + two_sqrt_a_alpha
            a1 = -2.0 * (minus + plus_cos)
            a2 = plus + minus_cos - two_sqrt_a_alpha
        else:
            b0 = A * (plus + minus_cos + two_sqrt_a_alpha) * post_lin
            b1 = -2.0 * A * (minus + plus_cos) * post_lin
            b2 = A * (plus + minus_cos - two_sqrt_a_alpha) * post_lin
            a0 = plus - minus_cos + two_sqrt_a_alpha
            a1 = 2.0 * (minus - plus_cos)
            a2 = plus - minus_cos - two_sqrt_a_alpha

        return Biquad(b0, b1, b2, a0, a1, a2, sample_rate=fs)

    @staticmethod
    def _make_allpass(fs: float, delay_s: float) -> Biquad:
        if delay_s <= 0.0:
            return Biquad(1.0, 0.0, 0.0, 1.0, 0.0, 0.0, sample_rate=fs)
        k = delay_s * 0.5 * fs
        v = (1.0 - k) / (1.0 + k)
        return Biquad(v * v, 2.0 * v, 1.0, 1.0, 2.0 * v, v * v, sample_rate=fs)

    def reset(self):
        fs = self.sample_rate
        itd = self.compute_itd(self.angle_deg)

        low_cutoff = min(0.5 / max(itd, 1e-5), 2000.0)
        high_cutoff = low_cutoff / 3.0

        # Ipsilateral direct treble enhancement
        self.ipsi_shelf_l = self._make_shelf(fs, high_cutoff, 3.0, 0.4, -3.0, is_low=False)
        self.ipsi_shelf_r = self._make_shelf(fs, high_cutoff, 3.0, 0.4, -3.0, is_low=False)

        # Contralateral head-shadow low-shelf
        self.contra_shelf_l = self._make_shelf(fs, low_cutoff, 9.0, 0.4, -12.0, is_low=True)
        self.contra_shelf_r = self._make_shelf(fs, low_cutoff, 9.0, 0.4, -12.0, is_low=True)

        # Compute DC group delay of the contra filter
        c = self.contra_shelf_l
        b_sum = c.b0 + c.b1 + c.b2
        a_sum = 1.0 + c.a1 + c.a2
        tau_dc = ((c.b1 + 2.0 * c.b2) / b_sum - (c.a1 + 2.0 * c.a2) / a_sum) / fs if (abs(b_sum) > 1e-6 and abs(a_sum) > 1e-6) else 0.0

        rem_delay = max(0.0, itd - tau_dc)
        self.allpass_l = self._make_allpass(fs, rem_delay)
        self.allpass_r = self._make_allpass(fs, rem_delay)

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
        gain_lin = float(np.power(10.0, self.gain_db / 20.0))

        for i in range(num_frames):
            in_l = float(s[i, 0])
            in_r = float(s[i, 1])

            # Direct ipsilateral path
            dir_l, _ = self.ipsi_shelf_l.process_sample_tdf2(in_l, in_l)
            dir_r, _ = self.ipsi_shelf_r.process_sample_tdf2(in_r, in_r)

            # Contralateral head-shadow path
            cs_l, _ = self.contra_shelf_l.process_sample_tdf2(in_r, in_r)
            cross_l, _ = self.allpass_l.process_sample_tdf2(cs_l, cs_l)

            cs_r, _ = self.contra_shelf_r.process_sample_tdf2(in_l, in_l)
            cross_r, _ = self.allpass_r.process_sample_tdf2(cs_r, cs_r)

            wet_l = (dir_l + cross_l) * gain_lin
            wet_r = (dir_r + cross_r) * gain_lin

            out[i, 0] = in_l * (1.0 - self.mix) + wet_l * self.mix
            out[i, 1] = in_r * (1.0 - self.mix) + wet_r * self.mix

        if is_two_args:
            return out[:, 0], out[:, 1]
        return out[:, 0] if is_1d else out
