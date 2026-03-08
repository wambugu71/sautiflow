import 'dart:ffi' as ffi;
import '../audio_engine_ffi.dart' show AudioFormat;
import 'miniaudio_filters.dart';

class MiniaudioLpf1 {
  MiniaudioLpf1(this._ffi, AudioFormat format, int channels, int sampleRate,
      double cutoffHz)
      : _pointer = _ffi.createLpf1(format, channels, sampleRate, cutoffHz);

  final MiniaudioFiltersFFI _ffi;
  ffi.Pointer<ffi.Void> _pointer;

  bool get isInitialized => _pointer != ffi.nullptr;

  void reinit(
      AudioFormat format, int channels, int sampleRate, double cutoffHz) {
    if (isInitialized) {
      _ffi.reinitLpf1(_pointer, format, channels, sampleRate, cutoffHz);
    }
  }

  bool process(ffi.Pointer<ffi.Void> outFrames, ffi.Pointer<ffi.Void> inFrames,
      int frameCount) {
    if (!isInitialized) return false;
    return _ffi.processLpf1(_pointer, outFrames, inFrames, frameCount);
  }

  void dispose() {
    if (isInitialized) {
      _ffi.destroyLpf1(_pointer);
      _pointer = ffi.nullptr;
    }
  }
}

class MiniaudioLpf2 {
  MiniaudioLpf2(this._ffi, AudioFormat format, int channels, int sampleRate,
      double cutoffHz, double q)
      : _pointer = _ffi.createLpf2(format, channels, sampleRate, cutoffHz, q);

  final MiniaudioFiltersFFI _ffi;
  ffi.Pointer<ffi.Void> _pointer;

  bool get isInitialized => _pointer != ffi.nullptr;

  void reinit(AudioFormat format, int channels, int sampleRate, double cutoffHz,
      double q) {
    if (isInitialized) {
      _ffi.reinitLpf2(_pointer, format, channels, sampleRate, cutoffHz, q);
    }
  }

  bool process(ffi.Pointer<ffi.Void> outFrames, ffi.Pointer<ffi.Void> inFrames,
      int frameCount) {
    if (!isInitialized) return false;
    return _ffi.processLpf2(_pointer, outFrames, inFrames, frameCount);
  }

  void dispose() {
    if (isInitialized) {
      _ffi.destroyLpf2(_pointer);
      _pointer = ffi.nullptr;
    }
  }
}

class MiniaudioLpf {
  MiniaudioLpf(this._ffi, AudioFormat format, int channels, int sampleRate,
      double cutoffHz, int order)
      : _pointer =
            _ffi.createLpf(format, channels, sampleRate, cutoffHz, order);

  final MiniaudioFiltersFFI _ffi;
  ffi.Pointer<ffi.Void> _pointer;

  bool get isInitialized => _pointer != ffi.nullptr;

  void reinit(AudioFormat format, int channels, int sampleRate, double cutoffHz,
      int order) {
    if (isInitialized) {
      _ffi.reinitLpf(_pointer, format, channels, sampleRate, cutoffHz, order);
    }
  }

  bool process(ffi.Pointer<ffi.Void> outFrames, ffi.Pointer<ffi.Void> inFrames,
      int frameCount) {
    if (!isInitialized) return false;
    return _ffi.processLpf(_pointer, outFrames, inFrames, frameCount);
  }

  void dispose() {
    if (isInitialized) {
      _ffi.destroyLpf(_pointer);
      _pointer = ffi.nullptr;
    }
  }
}

class MiniaudioHpf1 {
  MiniaudioHpf1(this._ffi, AudioFormat format, int channels, int sampleRate,
      double cutoffHz)
      : _pointer = _ffi.createHpf1(format, channels, sampleRate, cutoffHz);

  final MiniaudioFiltersFFI _ffi;
  ffi.Pointer<ffi.Void> _pointer;

  bool get isInitialized => _pointer != ffi.nullptr;

  void reinit(
      AudioFormat format, int channels, int sampleRate, double cutoffHz) {
    if (isInitialized) {
      _ffi.reinitHpf1(_pointer, format, channels, sampleRate, cutoffHz);
    }
  }

  bool process(ffi.Pointer<ffi.Void> outFrames, ffi.Pointer<ffi.Void> inFrames,
      int frameCount) {
    if (!isInitialized) return false;
    return _ffi.processHpf1(_pointer, outFrames, inFrames, frameCount);
  }

  void dispose() {
    if (isInitialized) {
      _ffi.destroyHpf1(_pointer);
      _pointer = ffi.nullptr;
    }
  }
}

class MiniaudioHpf2 {
  MiniaudioHpf2(this._ffi, AudioFormat format, int channels, int sampleRate,
      double cutoffHz, double q)
      : _pointer = _ffi.createHpf2(format, channels, sampleRate, cutoffHz, q);

  final MiniaudioFiltersFFI _ffi;
  ffi.Pointer<ffi.Void> _pointer;

  bool get isInitialized => _pointer != ffi.nullptr;

  void reinit(AudioFormat format, int channels, int sampleRate, double cutoffHz,
      double q) {
    if (isInitialized) {
      _ffi.reinitHpf2(_pointer, format, channels, sampleRate, cutoffHz, q);
    }
  }

  bool process(ffi.Pointer<ffi.Void> outFrames, ffi.Pointer<ffi.Void> inFrames,
      int frameCount) {
    if (!isInitialized) return false;
    return _ffi.processHpf2(_pointer, outFrames, inFrames, frameCount);
  }

  void dispose() {
    if (isInitialized) {
      _ffi.destroyHpf2(_pointer);
      _pointer = ffi.nullptr;
    }
  }
}

class MiniaudioHpf {
  MiniaudioHpf(this._ffi, AudioFormat format, int channels, int sampleRate,
      double cutoffHz, int order)
      : _pointer =
            _ffi.createHpf(format, channels, sampleRate, cutoffHz, order);

  final MiniaudioFiltersFFI _ffi;
  ffi.Pointer<ffi.Void> _pointer;

  bool get isInitialized => _pointer != ffi.nullptr;

  void reinit(AudioFormat format, int channels, int sampleRate, double cutoffHz,
      int order) {
    if (isInitialized) {
      _ffi.reinitHpf(_pointer, format, channels, sampleRate, cutoffHz, order);
    }
  }

  bool process(ffi.Pointer<ffi.Void> outFrames, ffi.Pointer<ffi.Void> inFrames,
      int frameCount) {
    if (!isInitialized) return false;
    return _ffi.processHpf(_pointer, outFrames, inFrames, frameCount);
  }

  void dispose() {
    if (isInitialized) {
      _ffi.destroyHpf(_pointer);
      _pointer = ffi.nullptr;
    }
  }
}

class MiniaudioBiquad {
  MiniaudioBiquad(this._ffi, AudioFormat format, int channels, double b0,
      double b1, double b2, double a0, double a1, double a2)
      : _pointer = _ffi.createBiquad(format, channels, b0, b1, b2, a0, a1, a2);

  final MiniaudioFiltersFFI _ffi;
  ffi.Pointer<ffi.Void> _pointer;

  bool get isInitialized => _pointer != ffi.nullptr;

  void reinit(AudioFormat format, int channels, double b0, double b1, double b2,
      double a0, double a1, double a2) {
    if (isInitialized) {
      _ffi.reinitBiquad(_pointer, format, channels, b0, b1, b2, a0, a1, a2);
    }
  }

  bool process(ffi.Pointer<ffi.Void> outFrames, ffi.Pointer<ffi.Void> inFrames,
      int frameCount) {
    if (!isInitialized) return false;
    return _ffi.processBiquad(_pointer, outFrames, inFrames, frameCount);
  }

  void dispose() {
    if (isInitialized) {
      _ffi.destroyBiquad(_pointer);
      _pointer = ffi.nullptr;
    }
  }
}

class MiniaudioResampler {
  MiniaudioResampler(this._ffi, AudioFormat format, int channels,
      int sampleRateIn, int sampleRateOut,
      {ResampleAlgorithm algorithm = ResampleAlgorithm.miniaudioLinear,
      DitherMode ditherMode = DitherMode.none})
      : _pointer = _ffi.createResampler(format, channels, sampleRateIn,
            sampleRateOut, algorithm, ditherMode);

  final MiniaudioFiltersFFI _ffi;
  ffi.Pointer<ffi.Void> _pointer;

  bool get isInitialized => _pointer != ffi.nullptr;

  bool process(
      ffi.Pointer<ffi.Void> inFrames,
      ffi.Pointer<ffi.Uint64> inFrameCount,
      ffi.Pointer<ffi.Void> outFrames,
      ffi.Pointer<ffi.Uint64> outFrameCount) {
    if (!isInitialized) return false;
    return _ffi.processResampler(
        _pointer, inFrames, inFrameCount, outFrames, outFrameCount);
  }

  void setRate(int sampleRateIn, int sampleRateOut) {
    if (isInitialized) {
      _ffi.setResamplerRate(_pointer, sampleRateIn, sampleRateOut);
    }
  }

  void setRateRatio(double ratioInOut) {
    if (isInitialized) {
      _ffi.setResamplerRateRatio(_pointer, ratioInOut);
    }
  }

  int getRequiredInputFrameCount(int outFrameCount) {
    if (!isInitialized) return 0;
    return _ffi.getResamplerRequiredInput(_pointer, outFrameCount);
  }

  int getExpectedOutputFrameCount(int inFrameCount) {
    if (!isInitialized) return 0;
    return _ffi.getResamplerExpectedOutput(_pointer, inFrameCount);
  }

  int getInputLatency() {
    if (!isInitialized) return 0;
    return _ffi.getResamplerInputLatency(_pointer);
  }

  int getOutputLatency() {
    if (!isInitialized) return 0;
    return _ffi.getResamplerOutputLatency(_pointer);
  }

  void dispose() {
    if (isInitialized) {
      _ffi.destroyResampler(_pointer);
      _pointer = ffi.nullptr;
    }
  }
}
