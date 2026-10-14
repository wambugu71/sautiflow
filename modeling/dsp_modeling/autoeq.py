"""
AutoEQ Parametric Profile Parser & Curve Synthesizer
====================================================

Mathematical Formulation:
-------------------------
AutoEQ and Equalizer APO profiles define target acoustic equalization profiles
designed to normalize headphone and in-ear monitor frequency responses to psychoacoustic
reference targets (e.g., the Harman Target Curves):

1. Cascaded Transfer Function:
   The composite system transfer function $H(z)$ is the product of the pre-attenuation gain
   and $N$ cascaded 2nd-order biquadratic filter sections:
   $$H(z) = 10^{G_{\\text{preamp}} / 20} \\prod_{k=1}^{N} H_k(z)$$
   where each $H_k(z)$ is an RBJ Audio EQ Cookbook biquad:
   $$H_k(z) = \\frac{b_{0,k} + b_{1,k} z^{-1} + b_{2,k} z^{-2}}{1 + a_{1,k} z^{-1} + a_{2,k} z^{-2}}$$

2. Composite Magnitude Response (in decibels):
   $$|H(e^{j\\omega})|_{\\text{dB}} = G_{\\text{preamp}} + \\sum_{k=1}^{N} 20 \\log_{10} \\left| H_k(e^{j\\omega}) \\right|$$

3. Phase Response:
   $$\\theta(\\omega) = \\sum_{k=1}^{N} \\text{atan2}\\left(\\text{Im}[H_k(e^{j\\omega})], \\text{Re}[H_k(e^{j\\omega})]\\right)$$

Historical Attribution & Creators:
----------------------------------
- **Jaakko Pasanen** (2018–present):
  Finnish audio engineer and creator of the open-source **AutoEq** project
  (https://github.com/jaakkopasanen/AutoEq), which standardizes automated headphone compensation
  to target frequency responses using parametric bi-quad optimization.
- **Dr. Sean E. Olive & Todd Welti** (2012–2018):
  Harman International acoustic researchers who conducted landmark double-blind subjective preference
  investigations establishing the **Harman Target Curves** for over-ear (AE/OE) and in-ear (IE) headphones
  ("The Relationship Between Perception and Measurement of Headphone Sound Quality", AES Convention 134, 2013).
- **Peter Verbeek**:
  Author of Equalizer APO for Windows, which established the de-facto standard configuration file syntax.
"""

from dataclasses import dataclass, field
from enum import IntEnum
from typing import List, Optional, Tuple
import re
import numpy as np
from .biquad import make_biquad, BiquadFilterType, Biquad


class AutoEqBandType(IntEnum):
    PEAK = 0
    BANDPASS = 1
    NOTCH = 2
    LOWSHELF = 3
    HIGHSHELF = 4
    LOWPASS = 5
    HIGHPASS = 6
    BELL = 7
    TILT = 8
    ALLPASS = 9


@dataclass
class AutoEqBand:
    """Parametric equalizer band specification."""
    filter_type: AutoEqBandType = AutoEqBandType.PEAK
    enabled: bool = True
    frequency_hz: float = 1000.0
    gain_db: float = 0.0
    q: float = 1.0
    slope: float = 1.0

    def to_biquad(self, sample_rate: float) -> Optional[Biquad]:
        """Convert parametric band into an RBJ biquad filter instance."""
        if not self.enabled:
            return None

        type_map = {
            AutoEqBandType.PEAK: BiquadFilterType.PEAK,
            AutoEqBandType.BELL: BiquadFilterType.PEAK,
            AutoEqBandType.LOWSHELF: BiquadFilterType.LOWSHELF,
            AutoEqBandType.HIGHSHELF: BiquadFilterType.HIGHSHELF,
            AutoEqBandType.LOWPASS: BiquadFilterType.LOWPASS,
            AutoEqBandType.HIGHPASS: BiquadFilterType.HIGHPASS,
            AutoEqBandType.BANDPASS: BiquadFilterType.BANDPASS,
            AutoEqBandType.NOTCH: BiquadFilterType.NOTCH,
            AutoEqBandType.ALLPASS: BiquadFilterType.ALLPASS,
            AutoEqBandType.TILT: BiquadFilterType.TILT,
        }

        btype = type_map.get(self.filter_type, BiquadFilterType.PEAK)
        return make_biquad(
            btype,
            sample_rate,
            self.frequency_hz,
            gain_db=self.gain_db,
            q=self.q
        )


@dataclass
class AutoEqProfile:
    """Complete headphone/room EQ profile parsed from EqualizerAPO / AutoEq configuration."""
    preamp_db: float = 0.0
    bands: List[AutoEqBand] = field(default_factory=list)
    is_valid: bool = False

    def compute_response(
        self, frequencies: np.ndarray, sample_rate: float = 48000.0
    ) -> Tuple[np.ndarray, np.ndarray]:
        """
        Compute total cascaded frequency response (magnitude in dB and unwrapped phase in radians).
        """
        total_mag_db = np.full_like(frequencies, self.preamp_db, dtype=np.float64)
        total_phase = np.zeros_like(frequencies, dtype=np.float64)

        for band in self.bands:
            if not band.enabled:
                continue
            bq = band.to_biquad(sample_rate)
            if bq is None:
                continue
            mag_db, phase = bq.frequency_response(frequencies)
            total_mag_db += mag_db
            total_phase += phase

        return total_mag_db, np.unwrap(total_phase)

    def process(self, x: np.ndarray, sample_rate: float = 48000.0) -> np.ndarray:
        """Process an audio signal through the entire cascaded profile."""
        preamp_linear = 10.0 ** (self.preamp_db / 20.0)
        out = x * preamp_linear
        for band in self.bands:
            if not band.enabled:
                continue
            bq = band.to_biquad(sample_rate)
            if bq is not None:
                out = bq.process(out)
        return out


class AutoEqParser:
    """Parser for EqualizerAPO / AutoEq text configuration files."""

    @staticmethod
    def parse_string(content: str) -> AutoEqProfile:
        """Parse configuration text into an AutoEqProfile."""
        profile = AutoEqProfile()

        for raw_line in content.splitlines():
            line = raw_line.strip()
            # Strip comments
            for sep in ["#", ";", "//"]:
                if sep in line:
                    line = line.split(sep)[0].strip()

            if not line:
                continue

            upper = line.upper()

            # Preamp line
            if upper.startswith("PREAMP"):
                colon_idx = line.find(":")
                val_str = line[colon_idx + 1:] if colon_idx != -1 else line[6:]
                # Match float e.g. -6.5 dB
                match = re.search(r"[-+]?\d*\.?\d+", val_str)
                if match:
                    profile.preamp_db = float(match.group(0))
                continue

            # Filter line
            if upper.startswith("FILTER"):
                colon_idx = line.find(":")
                body = line[colon_idx + 1:] if colon_idx != -1 else line[6:]
                tokens = body.strip().split()
                if len(tokens) < 2:
                    continue

                band = AutoEqBand()
                idx = 0

                # Check ON/OFF
                if tokens[0].upper() == "ON":
                    band.enabled = True
                    idx = 1
                elif tokens[0].upper() == "OFF":
                    band.enabled = False
                    idx = 1

                if idx >= len(tokens):
                    continue

                # Type
                t_token = tokens[idx].upper()
                idx += 1
                if t_token in ("PK", "PEAK", "BELL"):
                    band.filter_type = AutoEqBandType.PEAK
                elif t_token in ("LSC", "LS", "LOWSHELF", "LOW_SHELF"):
                    band.filter_type = AutoEqBandType.LOWSHELF
                elif t_token in ("HSC", "HS", "HIGHSHELF", "HIGH_SHELF"):
                    band.filter_type = AutoEqBandType.HIGHSHELF
                elif t_token in ("LP", "LPF", "LOWPASS", "LOW_PASS"):
                    band.filter_type = AutoEqBandType.LOWPASS
                elif t_token in ("HP", "HPF", "HIGHPASS", "HIGH_PASS"):
                    band.filter_type = AutoEqBandType.HIGHPASS
                elif t_token in ("BP", "BPF", "BANDPASS"):
                    band.filter_type = AutoEqBandType.BANDPASS
                elif t_token in ("NO", "NOTCH"):
                    band.filter_type = AutoEqBandType.NOTCH
                elif t_token == "TILT":
                    band.filter_type = AutoEqBandType.TILT
                elif t_token in ("AP", "ALLPASS"):
                    band.filter_type = AutoEqBandType.ALLPASS

                # Parse key-values
                while idx < len(tokens):
                    key = tokens[idx].upper()
                    idx += 1
                    if idx >= len(tokens):
                        break

                    val_token = tokens[idx]
                    idx += 1
                    # Extract number
                    num_match = re.search(r"[-+]?\d*\.?\d+", val_token)
                    if not num_match:
                        continue
                    num_val = float(num_match.group(0))

                    if key == "FC":
                        band.frequency_hz = num_val
                    elif key == "GAIN":
                        band.gain_db = num_val
                    elif key in ("Q", "BW"):
                        band.q = num_val

                profile.bands.append(band)

        profile.is_valid = len(profile.bands) > 0
        return profile
