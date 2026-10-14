"""
DSP Mathematical Modeling Library
=================================

A comprehensive Python library mathematically modeling all DSP algorithms in SautiFlow / MiniAudioDart:

1.  Biquad & Parametric Filters (`biquad.py`)
2.  Half-Band Polyphase Oversampling (`oversampler.py`)
3.  Analog Warmth & Non-Linear Tube/Tape Modeling (`analog_warmth.py`)
4.  Broadcast Leveller AGC (`broadcast_leveller.py`)
5.  Audio Clarity & High-Frequency Enhancer (`clarity.py`)
6.  De-Esser Split-Band & Wideband (`de_esser.py`)
7.  Dialog Enhancer & Formant Shaping (`dialog_enhancer.py`)
8.  Downward Expander & Noise Reducer (`downward_expander.py`)
9.  Dynamic Bass & Harmonic Synthesizer (`dynamic_bass.py`)
10. Dynamic Parametric Equalizer (`dynamic_eq.py`)
11. Dynamic Loudness ISO 226 Contour (`dynamic_loudness.py`)
12. Dynamic System & Transducer Matrix (`dynamic_system.py`)
13. FFT Partitioned Convolver (`fft_convolver.py`)
14. Master Brickwall Lookahead Limiter (`master_limiter.py`)
15. Audiophile Tone Crossover (`tone_crossover.py`)
16. Noise Gate with Hysteresis & Hold (`noise_gate.py`)
17. OpenStage Spherical-Head Crossfeed (`open_stage.py`)
18. Binaural Crossfeed Topologies (`crossfeed.py`)
19. Algorithmic Reverbs (Dattorro, Diffusion, Lattice) (`reverb.py`)
20. ScaleTempo WSOLA Time-Stretching (`scaletempo.py`)
21. Spatial Surround & Binaural HRTF (`spatial_surround.py`)
22. Stereo Imager & Velvet Noise Decorrelator (`stereo_imager.py`)
23. Subsonic 18 Hz Filter (`subsonic_filter.py`)
24. Tape Drift, Wow & Flutter (`tape_drift.py`)
25. AutoEQ Parametric Profile Parser (`autoeq.py`)
26. DSP Signal Utilities & Analysis (`utils.py`)
"""

from .biquad import Biquad, BiquadFilterType, make_biquad, biquad_frequency_response
from .oversampler import PolyphaseHalfBandFilter2x, PolyphaseOversampler2x, PolyphaseOversampler4x
from .analog_warmth import AnalogWarmthDSP, AnalogWarmthProfile
from .broadcast_leveller import BroadcastLevellerDSP
from .clarity import AudioClarityDSP, AudioClarityProfile
from .de_esser import DeEsserDSP, DeEsserMode, DeEsserPreset
from .dialog_enhancer import DialogEnhancerDSP, DialogEnhancerProfile
from .downward_expander import DownwardExpanderDSP, ExpanderPreset
from .dynamic_bass import HarmonicBassDSP, BassEnhanceProfile, DYNAMIC_BASS_PRESETS
from .dynamic_eq import DynamicEqDSP, DynamicEqFilterType, DynamicEqMode, DynamicEqBandConfig
from .dynamic_loudness import DynamicLoudnessDSP
from .dynamic_system import DynamicSystemDSP, TransducerProfile, DYNAMIC_SYSTEM_PRESETS
from .fft_convolver import FFTConvolverDSP
from .master_limiter import MasterLimiterDSP
from .tone_crossover import ToneCrossoverDSP
from .noise_gate import NoiseGateDSP, GateState
from .open_stage import OpenStageDSP
from .crossfeed import CrossfeedNode, CrossfeedAlgorithm
from .reverb import DattorroReverb, DiffusionReverbDSP, LatticeReverbDSP
from .scaletempo import ScaleTempoDSP
from .spatial_surround import SpatialSurroundDSP, SurroundMode
from .stereo_imager import StereoImagerDSP, StereoImagerMode
from .subsonic_filter import SubsonicFilter
from .tape_drift import TapeDriftDSP, TapeDriftPreset
from .autoeq import AutoEqParser, AutoEqProfile, AutoEqBand
from .utils import (
    generate_sine,
    generate_sweep,
    generate_impulse,
    compute_thd,
    frequency_spectrum,
    measure_rt60
)

__all__ = [
    "Biquad",
    "BiquadFilterType",
    "make_biquad",
    "biquad_frequency_response",
    "PolyphaseHalfBandFilter2x",
    "PolyphaseOversampler2x",
    "PolyphaseOversampler4x",
    "AnalogWarmthDSP",
    "AnalogWarmthProfile",
    "BroadcastLevellerDSP",
    "AudioClarityDSP",
    "AudioClarityProfile",
    "DeEsserDSP",
    "DeEsserMode",
    "DeEsserPreset",
    "DialogEnhancerDSP",
    "DialogEnhancerProfile",
    "DownwardExpanderDSP",
    "ExpanderPreset",
    "HarmonicBassDSP",
    "BassEnhanceProfile",
    "DYNAMIC_BASS_PRESETS",
    "DynamicEqDSP",
    "DynamicEqFilterType",
    "DynamicEqMode",
    "DynamicEqBandConfig",
    "DynamicLoudnessDSP",
    "DynamicSystemDSP",
    "TransducerProfile",
    "DYNAMIC_SYSTEM_PRESETS",
    "FFTConvolverDSP",
    "MasterLimiterDSP",
    "ToneCrossoverDSP",
    "NoiseGateDSP",
    "GateState",
    "OpenStageDSP",
    "CrossfeedNode",
    "CrossfeedAlgorithm",
    "DattorroReverb",
    "DiffusionReverbDSP",
    "LatticeReverbDSP",
    "ScaleTempoDSP",
    "SpatialSurroundDSP",
    "SurroundMode",
    "StereoImagerDSP",
    "StereoImagerMode",
    "SubsonicFilter",
    "TapeDriftDSP",
    "TapeDriftPreset",
    "AutoEqParser",
    "AutoEqProfile",
    "AutoEqBand",
    "generate_sine",
    "generate_sweep",
    "generate_impulse",
    "compute_thd",
    "frequency_spectrum",
    "measure_rt60"
]
