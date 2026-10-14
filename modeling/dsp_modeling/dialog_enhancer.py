"""
Dialog Enhancer & Speech Formant Shaping Mathematical Modeling
==============================================================

Creators & Historical Foundations:
----------------------------------
- **Mid-Side (Sum-and-Difference) Stereophony**: Alan Dower Blumlein
  (EMI Central Research Laboratories, British Patent 394,325, 1931).
- **Acoustic Formant Theory of Speech**: Gordon E. Peterson and Harold L. Barney
  ("Control Methods Used in a Study of the Vowels", J. Acoust. Soc. Am., 1952);
  Harvey Fletcher ("Speech and Hearing in Communication", Van Nostrand, 1953).

Mathematical Topologies
-----------------------
Maximizes vocal intelligibility in movies, podcasts, and TV broadcasts while suppressing background noise:

1. **Mid-Side Matrix Decomposition**:
       Mid  = 0.5 * (Left + Right)   (contains center dialogue)
       Side = 0.5 * (Left - Right)   (contains stereo ambiance, effects, music, reverb)

2. **3-Stage Vocal Formant Resonator Cascade (Mid Channel)**:
   - Stage A (Primary Vocal Formant): 2400 Hz (Q = 1.25) -> speech vowel intelligibility
   - Stage B (Speech Body Resonator): 1200 Hz (Q = 1.00) -> throat & vocal chest fullness
   - Stage C (Consonant Articulation): 3800 Hz (Q = 1.30) -> dental & plosive clarity

3. **Dynamic Side Ducking**:
   Tracks speech energy envelope on the enhanced Mid signal (15 ms attack, 120 ms release):
       speech_activity = clamp((env - 0.012) * 6.0, 0.0, 1.0)
       side_attenuation = 1.0 - speech_activity * (ducking_amount * 0.65)
       Side_out = Side * side_attenuation * (1.0 - center_focus * 0.20)

4. **Headroom Trim Compensation**:
   When cumulative cascaded boost exceeds +12 dB, attenuates Mid by 10^((12 - total_boost)/20)
   to guarantee zero inter-stage digital clipping.

5. **Stereo Reconstruction**:
       Left_out  = Mid_out + Side_out
       Right_out = Mid_out - Side_out
"""

from enum import Enum
from typing import Optional, Tuple
import numpy as np

from .biquad import make_biquad, BiquadFilterType


class DialogEnhancerProfile(str, Enum):
    CINEMA = "cinema"
    MUSIC = "music"
    VOICE = "voice"
    NIGHT = "night"
    CUSTOM = "custom"

    # Convenient alias
    PODCAST_CLEAN = "voice"


class DialogEnhancerDSP:
    """
    Cleanroom dialogue booster and dynamic background ducking processor.
    """

    def __init__(
        self,
        sample_rate: float = 48000.0,
        profile: DialogEnhancerProfile | str = DialogEnhancerProfile.CINEMA,
        amount: float = 0.65,
        ducking: float = 0.55,
        clarity: float = 0.60,
        center_focus: float = 0.70
    ):
        self.sample_rate = float(sample_rate)
        self.profile = DialogEnhancerProfile(profile)
        self.amount = float(np.clip(amount, 0.0, 1.0))
        self.ducking = float(np.clip(ducking, 0.0, 1.0))
        self.clarity = float(np.clip(clarity, 0.0, 1.0))
        self.center_focus = float(np.clip(center_focus, 0.0, 1.0))

        if self.profile != DialogEnhancerProfile.CUSTOM:
            self._apply_profile_defaults()

        self.reset()

    def _apply_profile_defaults(self):
        if self.profile == DialogEnhancerProfile.CINEMA:
            self.amount = 0.65
            self.ducking = 0.55
            self.clarity = 0.60
            self.center_focus = 0.70
        elif self.profile == DialogEnhancerProfile.MUSIC:
            self.amount = 0.35
            self.ducking = 0.20
            self.clarity = 0.40
            self.center_focus = 0.35
        elif self.profile == DialogEnhancerProfile.VOICE:
            self.amount = 0.85
            self.ducking = 0.65
            self.clarity = 0.75
            self.center_focus = 0.85
        elif self.profile == DialogEnhancerProfile.NIGHT:
            self.amount = 0.50
            self.ducking = 0.40
            self.clarity = 0.50
            self.center_focus = 0.50

    def reset(self):
        # 3 Formant biquad stages
        boost_db = self.amount * 12.0
        clarity_db = self.clarity * 6.0

        self.bq_formant = make_biquad(
            BiquadFilterType.PEAK, 2400.0, gain_db=boost_db, q=1.25, sample_rate=self.sample_rate
        )
        self.bq_body = make_biquad(
            BiquadFilterType.PEAK, 1200.0, gain_db=boost_db * 0.35, q=1.0, sample_rate=self.sample_rate
        )
        self.bq_clarity = make_biquad(
            BiquadFilterType.PEAK, 3800.0, gain_db=clarity_db, q=1.3, sample_rate=self.sample_rate
        )

        # Headroom compensation calculation
        total_boost = boost_db + boost_db * 0.35 + clarity_db
        if total_boost > 12.0:
            self.headroom_comp = float(np.power(10.0, (12.0 - total_boost) / 20.0))
        else:
            self.headroom_comp = 1.0

        self.env = 0.0
        self.peak_atten = 1.0

        # Ballistics (15ms attack, 120ms release)
        self.alpha_att = 1.0 - np.exp(-1.0 / (self.sample_rate * 0.015))
        self.alpha_rel = 1.0 - np.exp(-1.0 / (self.sample_rate * 0.120))
        self.atten_release = 1.0 - np.exp(-1.0 / (self.sample_rate * 0.050))

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

        env = self.env
        peak_atten = self.peak_atten

        mid_gain = 1.0 + self.center_focus * 0.25
        max_ducking_lin = 1.0 - (self.ducking * 0.65)

        for i in range(num_frames):
            in_l = float(s[i, 0])
            in_r = float(s[i, 1])

            # 1. Mid-Side decomposition
            mid = 0.5 * (in_l + in_r)
            side = 0.5 * (in_l - in_r)

            # 2. 3-stage formant enhancement on Mid
            m_f, _ = self.bq_formant.process_sample_df1(mid, mid)
            m_b, _ = self.bq_body.process_sample_df1(m_f, m_f)
            m_enh, _ = self.bq_clarity.process_sample_df1(m_b, m_b)

            # 3. Speech envelope follower
            abs_m = abs(m_enh)
            env += (self.alpha_att if abs_m > env else self.alpha_rel) * (abs_m - env)

            # Dynamic side ducking
            speech_act = float(np.clip((env - 0.012) * 6.0, 0.0, 1.0))
            side_gain = (1.0 - speech_act * (1.0 - max_ducking_lin)) * (1.0 - self.center_focus * 0.20)

            # Peak limiter headroom check
            mid_peak = max(env, abs_m) * (mid_gain * self.headroom_comp)
            target_atten = 0.95 / mid_peak if mid_peak > 0.95 else 1.0
            if target_atten < peak_atten:
                peak_atten = target_atten
            else:
                peak_atten += self.atten_release * (target_atten - peak_atten)

            out_mid = m_enh * (mid_gain * self.headroom_comp * peak_atten)
            out_side = side * side_gain

            # 4. Reconstruction
            out[i, 0] = out_mid + out_side
            out[i, 1] = out_mid - out_side

        self.env = env
        self.peak_atten = peak_atten
        if is_two_args:
            return out[:, 0], out[:, 1]
        return out[:, 0] if is_1d else out
