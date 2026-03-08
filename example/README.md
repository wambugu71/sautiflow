# miniaudiodart_example

A full-featured Flutter project demonstrating the capabilities of the `miniaudiodart` native audio engine.

## Features Demonstrated

The application provides a comprehensive UI with multiple tabs to test the following native features:

- **Playback Controls**: Local file and URL streaming, playlist management, shuffle, loop, and crossfade.
- **Advanced Audio**: 
  - Dynamic **Pitch Shifting** controls.
  - **3D Spatialization** with X/Y/Z positioning.
  - Native Multiband FX, 10-Band EQ, and customizable Mixed FX Chains (Peak, Notch, Shelf, Bandpass).
  - Standalone Filters (LPF, HPF, Biquad).
- **Environment & Routing**: Audio format (s16, f32), sample rate matching, mono/stereo toggles, resampling algorithm selection, and dither modes.
- **Analytics**: Real-time native byte-level Fast Fourier Transform (FFT) / Envelope analyzer visualizer.
