# SautiFlow Mathematical DSP Modeling Library (`dsp_modeling`)

A professional-grade, rigorous Python library and reference implementation mathematically modeling every Digital Signal Processing (DSP) algorithm within the **SautiFlow / MiniAudioDart** audio engine.

This library bridges continuous-time acoustic physics, differential circuit equations, and discrete Z-plane realizations directly to their production C++ counterparts in `dsp/*.h`, `crossfeed_node.h`, and `reverb_node.h`.

---

## 🏛️ Comprehensive Table of Algorithms & Historical Creators

In accordance with scientific and engineering honesty, below is the complete attribution catalog acknowledging the original inventors, researchers, mathematicians, and acousticians who derived these foundational DSP algorithms.

| # | Algorithm Module | C++ Implementation | Primary Inventors & Historical Creators | Landmark Citations & Years |
|---|---|---|---|---|
| **1** | **Biquad Filters** (`biquad.py`) | `audio_engine.h` (AEEqBand) | **Robert Bristow-Johnson**, Adolf Hurwitz, Hendrik Bode | RBJ Audio EQ Cookbook (1994–2005); Hurwitz stability criterion (1895); Bode sensitivity integral (1945). |
| **2** | **Polyphase Oversampler** (`oversampler.py`) | `dsp/oversampler.h` | **Ronald E. Crochiere**, **Lawrence R. Rabiner**, **James H. McClellan**, **Thomas W. Parks**, **Evgeny Remez** | McClellan-Parks FIR algorithm (1973); Remez exchange algorithm (1934); Crochiere & Rabiner *Multirate Digital Signal Processing* (1983). |
| **3** | **Analog Warmth** (`analog_warmth.py`) | `dsp/analog_warmth_dsp.h` | **Lee de Forest**, **D. T. Yeh**, **J. S. Abel**, **J. O. Smith III**, **Valdemar Poulsen**, **Fritz Pfleumer**, **Rupert Neve** | Triode vacuum tube patent (1906); Yeh/Abel/Smith DAFx tube modeling (2007–2008); Poulsen telegraphone (1898); Pfleumer magnetic tape (1928); Neve transformer saturation (1960s). |
| **4** | **Broadcast Leveller** (`broadcast_leveller.py`) | `dsp/broadcast_leveller_dsp.h` | **Gilbert Soulodre**, **Florian Camerer**, **EBU PLOUD / ITU-R** | ITU-R BS.1770-4 loudness algorithms (Soulodre, 2004); EBU R128 broadcast loudness normalisation (Camerer, 2011). |
| **5** | **Clarity & Air Exciter** (`clarity.py`) | `dsp/clarity_dsp.h` | **Curt Knoppel**, **Marvin Caesar**, **Ruben Tilgner**, **Clif Maag**, **Siegfried Linkwitz**, **Russ Riley** | Aphex Aural Exciter patent (Knoppel, 1975); elysia nvelope dual-band differentiator (Tilgner, 2011); Maag Audio Air Band (1993); Linkwitz-Riley crossover networks (1976). |
| **6** | **De-Esser** (`de_esser.py`) | `dsp/de_esser_dsp.h` | **Douglas Shearer**, **David E. Blackmer**, **Robert (Bob) Orban** | Shearer sound sibilance limiter patent (1936); Blackmer dbx RMS detector & VCA (1971); Orban 8100/8300 Optimod speech de-essers (1980s). |
| **7** | **Dialog Enhancer** (`dialog_enhancer.py`) | `dsp/dialog_enhancer_dsp.h` | **Gordon E. Peterson**, **Harold L. Barney**, **Harvey Fletcher**, **Alan D. Blumlein** | Peterson & Barney vowel formant acoustics (1952); Fletcher speech intelligibility articulation index (1921); Blumlein Mid/Side decomposition (1931). |
| **8** | **Downward Expander** (`downward_expander.py`) | `dsp/downward_expander_dsp.h` | **David E. Blackmer**, **Ray Dolby** | dbx modular logarithmic RMS dynamics (Blackmer, 1971); Dolby A/SR downward expansion dynamics (1965–1986). |
| **9** | **Dynamic Bass & Subharmonic** (`dynamic_bass.py`) | `dsp/dynamic_bass_dsp.h` | **Jan Frederik Schouten**, **Meir Shashoua**, **Eugene Shenk**, **Ollie Summerlin**, **Robert Moog** | Schouten "The Residue and the Missing Fundamental" (1938); Shashoua MaxxBass patent (1998); Shenk & Summerlin Pultec EQP-1A (1951); Moog 4-pole transistor ladder (1965). |
| **10** | **Dynamic EQ** (`dynamic_eq.py`) | `dsp/dynamic_eq_dsp.h` | **BSS Audio (Chas Brooke)**, **Daniel Weiss** | BSS DPR-901 dynamic equalizer (1989); Weiss Engineering digital dynamic EQ (1990s). |
| **11** | **Dynamic Loudness ISO 226** (`dynamic_loudness.py`) | `dsp/dynamic_loudness_dsp.h` | **Harvey Fletcher**, **Wilden A. Munson**, **D. W. Robinson**, **R. S. Dadson**, **H. Takeshima**, **Y. Suzuki** | Fletcher & Munson equal-loudness contours (1933); Robinson & Dadson phon contours (1956); ISO 226:2003 revised standard (Suzuki & Takeshima, 2003). |
| **12** | **Dynamic System & Transducers** (`dynamic_system.py`) | `dsp/dynamic_system_dsp.h` | **Harry F. Olson**, **A. Neville Thiele**, **Richard H. Small** | Olson *Elements of Acoustical Engineering* (1940); Thiele & Small loudspeaker parameter synthesis (1961–1973). |
| **13** | **FFT Partitioned Convolver** (`fft_convolver.py`) | `dsp/fft_convolver_dsp.h` | **James W. Cooley**, **John W. Tukey**, **William G. Gardner**, **Anders Torger**, **Angelo Farina** | Cooley-Tukey FFT algorithm (1965); Gardner zero-latency partitioned convolution (1995); Torger & Farina BruteFIR uniform partition overlap-add (2001). |
| **14** | **Master Brickwall Limiter** (`master_limiter.py`) | `dsp/master_limiter_dsp.h` | **Michael A. Gerzon**, **ITU-R BS.1770 / EBU PLOUD** | Gerzon non-linear lookahead peak limiting (1990s); ITU-R BS.1770 4x oversampled true-peak detection. |
| **15** | **Multiband Mastering Processor** (`multiband_mastering.py`) | `dsp/multiband_mastering_dsp.h` | **Bob Katz**, **TC Electronic (Thomas Lund)** | Katz K-System mastering architecture & dynamics (1999); TC Electronic Finalizer 96K mastering topology (1996). |
| **16** | **Noise Gate** (`noise_gate.py`) | `dsp/noise_gate_dsp.h` | **Ivor Drawmer**, **David E. Blackmer** | Drawmer DS201 dual-threshold frequency-conscious noise gate (1982); Blackmer VCA envelope detectors (1971). |
| **17** | **OpenStage Spherical Crossfeed** (`open_stage.py`) | `dsp/open_stage_dsp.h` | **John William Strutt (Lord Rayleigh)**, **Benjamin B. Bauer**, **Siegfried Linkwitz** | Rayleigh Duplex Theory of sound localization (1907); Bauer stereophonic headphone crossfeed circuit (1961); Linkwitz binaural headphone modeling (1971). |
| **18** | **Binaural Crossfeed Topologies** (`crossfeed.py`) | `crossfeed_node.h` | **Benjamin B. Bauer**, **Boris Mikhaylov**, **Jan Meier**, **Ralph Glasgal**, **Yoichi Ando** | Bauer CBS crossfeed (1961); Mikhaylov BS2B algorithm (2007); Jan Meier natural crossfeed (2001); Glasgal & Ando Ambiophonics RACE crosstalk cancellation (1995). |
| **19** | **Algorithmic Reverb** (`reverb.py`) | `reverb_node.h`, `diffusion_reverb_dsp.h`, `lattice_reverb_dsp.h` | **Jon Dattorro**, **Manfred R. Schroeder**, **James A. Moorer**, **David Griesinger** | Schroeder allpass and comb reverberator (1962); Moorer early reflections & lowpass combs (1979); Griesinger Lexicon 224/480L design; Dattorro figure-8 plate/tank architecture (1997). |
| **20** | **ScaleTempo WSOLA** (`scaletempo.py`) | `dsp/scaletempo_dsp.h` | **Werner Verhelst**, **Marc Roelands**, **Salomon Roucos**, **Alexander M. Wilgus** | Roucos & Wilgus Synchronized Overlap-Add (SOLA, 1985); Verhelst & Roelands Waveform Similarity Overlap-Add (WSOLA, 1993). |
| **21** | **Spatial Surround & 3D HRTF** (`spatial_surround.py`) | `dsp/spatial_surround_dsp.h` | **Jim C. Fosgate**, **C. Phillip Brown**, **Richard O. Duda**, **Robert S. Woodworth** | Fosgate Pro Logic II matrix surround (2000, Emmy 2003); Woodworth spherical head ITD formula (1938); Brown & Duda structural HRTF filter (1998). |
| **22** | **Stereo Imager & Velvet Decorrelation** (`stereo_imager.py`) | `dsp/stereo_imager_dsp.h` | **Alan Dower Blumlein**, **Michael A. Gerzon**, **Matti Karjalainen**, **Vesa Välimäki** | Blumlein stereophony patent & shuffler (1931); Gerzon stereo shuffler matrixing (1992); Karjalainen & Välimäki Velvet Noise decorrelation (2007). |
| **23** | **Subsonic 18 Hz Filter** (`subsonic_filter.py`) | `dsp/subsonic_filter.h` | **Stephen Butterworth** | Butterworth maximally-flat filter synthesis (1930). |
| **24** | **Tape Drift, Wow & Flutter** (`tape_drift.py`) | `dsp/tape_drift_dsp.h` | **Charles Hermite**, **Edwin Catmull**, **Raphael Rom**, **Valdemar Poulsen**, **Fritz Pfleumer** | Hermite polynomial interpolation; Catmull & Rom local cubic spline (1974); Poulsen magnetic recording (1898); Pfleumer magnetic tape (1928). |
| **25** | **AutoEQ Parametric Profiles** (`autoeq.py`) | `dsp/autoeq_parser.h` | **Jaakko Pasanen**, **Dr. Sean E. Olive**, **Todd Welti**, **Peter Verbeek** | Pasanen AutoEq project (2018); Olive & Welti Harman Target Curves research (2012–2018); Verbeek Equalizer APO syntax. |

---

## 🚀 Installation & Quickstart

### Prerequisites
- Python 3.9+
- `numpy >= 1.24.0`
- `scipy >= 1.10.0`
- `matplotlib >= 3.7.0`
- `jupyter >= 1.0.0` (for interactive notebooks)

### Installation
From the `modeling/` directory:
```bash
pip install -e .
```
Or install requirements directly:
```bash
pip install -r requirements.txt
```

### Basic Example: Frequency Response & Saturation Analysis
```python
import numpy as np
from dsp_modeling import make_biquad, BiquadFilterType, AnalogWarmthDSP, AnalogWarmthProfile

# 1. Synthesize a 1 kHz peaking EQ filter (+6 dB, Q=2.0)
fs = 48000.0
eq = make_biquad(BiquadFilterType.PEAK, fs, 1000.0, gain_db=6.0, q=2.0)

# Calculate discrete frequency response
freqs = np.logspace(1, 4.3, 1000)
mag_db, phase_rad = eq.frequency_response(freqs)

# 2. Simulate analog tube saturation
tube = AnalogWarmthDSP(sample_rate=fs, profile=AnalogWarmthProfile.TUBE_12AX7)
t = np.linspace(0, 0.01, int(fs * 0.01))
test_tone = 0.9 * np.sin(2.0 * np.pi * 1000.0 * t)
saturated = tube.process(test_tone)
```

---

## 📓 Interactive Jupyter Notebook

To launch the comprehensive demonstration notebook covering mathematical derivations, transfer function pole-zero diagrams, harmonic distortion spectra, and dynamic curves:
```bash
jupyter notebook dsp_mathematical_modeling.ipynb
```

---

## 📁 Repository Structure
```
modeling/
├── dsp_modeling/                  # Python DSP package
│   ├── __init__.py                # Package exports
│   ├── analog_warmth.py           # Triode, Tape, and Console saturation models
│   ├── autoeq.py                  # AutoEq / EqualizerAPO profile parser
│   ├── biquad.py                  # RBJ Audio EQ Cookbook biquad filters
│   ├── broadcast_leveller.py      # EBU R128 / ITU-R BS.1770 AGC leveller
│   ├── clarity.py                 # Transient crisp differentiator & air exciter
│   ├── crossfeed.py               # Bauer BS2B, Meier, Natural SVF, RACE
│   ├── de_esser.py                # Split-band and wideband sibilance limiter
│   ├── dialog_enhancer.py         # Mid-Side vocal formant peaking
│   ├── downward_expander.py       # Soft-knee expander & rumble filter
│   ├── dynamic_bass.py            # Natural, Pure Bass+, Missing Fundamental, Pultec
│   ├── dynamic_eq.py              # 6-band dynamic parametric equalizer
│   ├── dynamic_loudness.py        # ISO 226:2003 equal-loudness contour engine
│   ├── dynamic_system.py          # Transducer acoustic models (19 presets)
│   ├── fft_convolver.py           # Uniform partitioned overlap-add convolution
│   ├── master_limiter.py          # Lookahead true-peak brickwall limiter
│   ├── multiband_mastering.py     # 5-stage mastering processor
│   ├── noise_gate.py              # Dual-threshold hysteresis gate
│   ├── open_stage.py              # Spherical head acoustic ITD & crossfeed
│   ├── oversampler.py             # 55-tap Remez equiripple half-band FIR
│   ├── reverb.py                  # Dattorro plate, Diffusion, Lattice reverbs
│   ├── scaletempo.py              # WSOLA tempo scaling algorithm
│   ├── spatial_surround.py        # Pro Logic II dematrix, Binaural HRTF, 3D stage
│   ├── stereo_imager.py           # M/S width, Velvet Noise decorrelation, Blumlein
│   ├── subsonic_filter.py         # 18 Hz Butterworth rumble filter
│   ├── tape_drift.py              # Wow, flutter, drift, Hermite interpolation
│   └── utils.py                   # Signal generation, THD, FFT spectra, RT60
├── docs/
│   └── mathematical_derivations.md # Full theoretical mathematical proofs & derivations
├── dsp_mathematical_modeling.ipynb # Interactive demonstration Jupyter notebook
├── pyproject.toml                 # Modern Python packaging specification
├── setup.py                       # Setuptools installation script
├── requirements.txt               # Pinned library dependencies
└── README.md                      # This documentation file
```
