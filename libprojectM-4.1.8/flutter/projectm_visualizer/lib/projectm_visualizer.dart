import 'dart:async';
import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:ffi/ffi.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import 'projectm_visualizer_bindings_generated.dart';
import 'projectm_presets.dart';

export 'projectm_presets.dart';

/// Telemetry and frame statistics reported by projectM and miniaudio.
class VisualizerStats {
  const VisualizerStats({
    required this.fps,
    required this.frameTimeMs,
    required this.bass,
    required this.mid,
    required this.treb,
    required this.framesRendered,
    required this.pcmFramesDropped,
    required this.isPlaying,
  });

  final double fps;
  final double frameTimeMs;
  final double bass;
  final double mid;
  final double treb;
  final int framesRendered;
  final int pcmFramesDropped;
  final bool isPlaying;

  @override
  String toString() =>
      'VisualizerStats(fps: ${fps.toStringAsFixed(1)}, frameTime: ${frameTimeMs.toStringAsFixed(2)}ms, frames: $framesRendered, playing: $isPlaying)';
}

/// Performance and rendering quality profile.
enum VisualizerQuality {
  /// 640x360 - Best battery life, ideal for low-end mobile devices and battery saver mode.
  eco,
  /// 960x540 - Optimal sweet spot: 75% lower memory/GPU load than 1080p with crisp scaled visuals.
  balanced,
  /// 1280x720 - HD crisp resolution for modern PCs and AC power.
  high,
  /// Unclamped screen native resolution (high-DPI demanding).
  native,
  /// Custom width and height.
  custom,
}

/// Dynamic library loader for projectm_visualizer native code.
ffi.DynamicLibrary _loadNativeLibrary() {
  if (Platform.isWindows) {
    return ffi.DynamicLibrary.open('projectm_visualizer.dll');
  } else if (Platform.isAndroid || Platform.isLinux) {
    return ffi.DynamicLibrary.open('libprojectm_visualizer.so');
  } else if (Platform.isMacOS) {
    try {
      return ffi.DynamicLibrary.open('projectm_visualizer.framework/projectm_visualizer');
    } catch (_) {
      try {
        return ffi.DynamicLibrary.open('libprojectm_visualizer.dylib');
      } catch (_) {
        return ffi.DynamicLibrary.process();
      }
    }
  } else if (Platform.isIOS) {
    try {
      return ffi.DynamicLibrary.process();
    } catch (_) {
      return ffi.DynamicLibrary.open('projectm_visualizer.framework/projectm_visualizer');
    }
  }
  throw UnsupportedError('Unsupported platform: ${Platform.operatingSystem}');
}

/// Controller managing a native projectM + miniaudio visualizer instance.
class ProjectMVisualizer {
  ProjectMVisualizer._(this._bindings, this._handle, this._initialWidth, this._initialHeight) {
    _initBuffers(_initialWidth, _initialHeight);
  }

  final ProjectmVisualizerBindings _bindings;
  ffi.Pointer<PmVis> _handle;
  final int _initialWidth;
  final int _initialHeight;

  bool _isDisposed = false;

  /// Whether the native visualizer instance has been destroyed.
  bool get isDisposed => _isDisposed;

  int _curWidth = 0;
  int _curHeight = 0;

  static const MethodChannel _androidChannel =
      MethodChannel('com.wambugu.projectm_visualizer/texture');
  int? _hardwareTextureId;

  int? get hardwareTextureId => _hardwareTextureId;

  bool _isPlaying = true;

  /// Whether audio playback is currently active and driving visual frames.
  bool get isPlaying => _isPlaying;

  // Reusable native pointers to avoid allocations in hot loops
  ffi.Pointer<ffi.Uint8> _nativePixelBuffer = ffi.nullptr;
  ffi.Pointer<ffi.Int> _outWidthPtr = ffi.nullptr;
  ffi.Pointer<ffi.Int> _outHeightPtr = ffi.nullptr;
  ffi.Pointer<ffi.Uint64> _outFrameIdPtr = ffi.nullptr;
  ffi.Pointer<PmVisStats> _statsPtr = ffi.nullptr;
  ffi.Pointer<ffi.Float> _nativePcmBuffer = ffi.nullptr;
  int _pixelBufferSize = 0;
  int _pcmBufferSize = 0;

  void _initBuffers(int w, int h) {
    _curWidth = w > 0 ? w : 1280;
    _curHeight = h > 0 ? h : 720;
    // Preallocate for up to 1080p desktop/mobile so setSize never reallocates during playback
    _pixelBufferSize = math.max(_curWidth * _curHeight * 4, 1920 * 1080 * 4);
    _nativePixelBuffer = calloc<ffi.Uint8>(_pixelBufferSize);
    _outWidthPtr = calloc<ffi.Int>();
    _outHeightPtr = calloc<ffi.Int>();
    _outFrameIdPtr = calloc<ffi.Uint64>();
    _statsPtr = calloc<PmVisStats>();
    _pcmBufferSize = 4096;
    _nativePcmBuffer = calloc<ffi.Float>(_pcmBufferSize);
  }

  /// Create and initialize a new visualizer instance.
  static Future<ProjectMVisualizer> create({
    int width = 1280,
    int height = 720,
    bool enableHardwareTexture = true,
  }) async {
    final dylib = _loadNativeLibrary();
    final bindings = ProjectmVisualizerBindings(dylib);
    final handle = bindings.pmvis_create(width, height);
    if (handle == ffi.nullptr) {
      throw StateError('Failed to create native projectM visualizer instance');
    }
    final visualizer = ProjectMVisualizer._(bindings, handle, width, height);

    if (enableHardwareTexture && Platform.isAndroid) {
      try {
        final texId = await _androidChannel.invokeMethod<int>('createTexture', {
          'handle': handle.address,
          'width': width,
          'height': height,
        });
        visualizer._hardwareTextureId = texId;
      } catch (e) {
        debugPrint('ProjectMVisualizer: Hardware texture not available, using pixel buffer: $e');
      }
    }

    return visualizer;
  }

  /// Update the render viewport dimensions.
  void setSize(int width, int height) {
    if (_isDisposed || width <= 0 || height <= 0) return;
    if (width == _curWidth && height == _curHeight) return;

    _curWidth = width;
    _curHeight = height;
    final newSize = width * height * 4;
    if (newSize > _pixelBufferSize) {
      calloc.free(_nativePixelBuffer);
      _nativePixelBuffer = calloc<ffi.Uint8>(newSize);
      _pixelBufferSize = newSize;
    }
    _bindings.pmvis_set_size(_handle, width, height);

    if (_hardwareTextureId != null && Platform.isAndroid) {
      _androidChannel.invokeMethod('updateTextureSize', {
        'textureId': _hardwareTextureId,
        'width': width,
        'height': height,
      }).catchError((_) {});
    }
  }

  /// Set the visualizer target frame rate (e.g. 60 or 120).
  void setFps(int fps) {
    if (_isDisposed || fps <= 0) return;
    _bindings.pmvis_set_fps(_handle, fps);
  }

  /// Set the Milkdrop per-vertex equation mesh resolution (e.g. 24x18 or 32x24).
  /// Lower values significantly reduce vertex CPU/GPU calculations on mobile/low-end devices.
  void setMeshSize(int width, int height) {
    if (_isDisposed || width < 8 || height < 8) return;
    _bindings.pmvis_set_mesh_size(_handle, width, height);
  }

  /// Set the duration in seconds for smooth crossfades between presets (default 1.5s).
  void setSoftCutDuration(double seconds) {
    if (_isDisposed || seconds < 0) return;
    _bindings.pmvis_set_soft_cut_duration(_handle, seconds);
  }

  /// Enable or disable battery saver mode.
  /// When enabled, projectM automatically throttles rendering down to 15 FPS when audio is silent or paused.
  void setBatterySaver(bool enabled) {
    if (_isDisposed) return;
    _bindings.pmvis_set_battery_saver(_handle, enabled ? 1 : 0);
  }

  /// Load a `.milk` preset from a file on disk.
  Future<void> loadPresetFile(String filePath, {bool smoothTransition = true}) async {
    if (_isDisposed) return;
    final cPath = filePath.toNativeUtf8();
    try {
      _bindings.pmvis_load_preset_file(_handle, cPath.cast(), smoothTransition ? 1 : 0);
    } finally {
      calloc.free(cPath);
    }
  }

  /// Load a `.milk` preset from raw string data.
  Future<void> loadPresetData(String data, {bool smoothTransition = true}) async {
    if (_isDisposed) return;
    final cData = data.toNativeUtf8();
    try {
      _bindings.pmvis_load_preset_data(_handle, cData.cast(), data.length, smoothTransition ? 1 : 0);
    } finally {
      calloc.free(cData);
    }
  }

  /// Load a `.milk` preset bundled as a Flutter asset.
  Future<void> loadPresetFromAsset(String assetPath, {bool smoothTransition = true}) async {
    final data = await rootBundle.loadString(assetPath);
    await loadPresetData(data, smoothTransition: smoothTransition);
  }

  /// Load a [ProjectMPreset] definition (inline equation string or disk file).
  Future<void> loadPreset(ProjectMPreset preset, {bool smoothTransition = true}) async {
    if (preset.filePath != null && File(preset.filePath!).existsSync()) {
      await loadPresetFile(preset.filePath!, smoothTransition: smoothTransition);
    } else if (preset.inlineMilkData != null) {
      await loadPresetData(preset.inlineMilkData!, smoothTransition: smoothTransition);
    } else {
      await loadPresetData(ProjectMPresetLibrary.defaultPreset.inlineMilkData!, smoothTransition: smoothTransition);
    }
  }

  /// Synchronize external audio playback state with projectM's internal battery saver & frame throttling.
  void setIsPlaying(bool playing) {
    if (_isDisposed) return;
    _isPlaying = playing;
    if (playing) {
      resumeAudio();
    } else {
      pauseAudio();
    }
  }

  /// Set directory path to locate helper textures referenced in presets.
  void setTextureSearchPath(String directoryPath) {
    if (_isDisposed) return;
    final cDir = directoryPath.toNativeUtf8();
    try {
      _bindings.pmvis_set_texture_search_path(_handle, cDir.cast());
    } finally {
      calloc.free(cDir);
    }
  }

  /// Play an audio track (MP3, WAV, FLAC, Vorbis) using miniaudio.
  Future<bool> playAudioFile(String filePath) async {
    if (_isDisposed) return false;
    final cPath = filePath.toNativeUtf8();
    try {
      final res = _bindings.pmvis_audio_play_file(_handle, cPath.cast());
      return res != 0;
    } finally {
      calloc.free(cPath);
    }
  }

  /// Start playback of a synthetic sine wave (e.g. 60Hz sub-bass).
  void playSine({double frequencyHz = 60.0}) {
    if (_isDisposed) return;
    _bindings.pmvis_audio_play_sine(_handle, frequencyHz);
  }

  /// Pause miniaudio playback.
  void pauseAudio() {
    if (_isDisposed) return;
    _bindings.pmvis_audio_pause(_handle);
  }

  /// Resume miniaudio playback.
  void resumeAudio() {
    if (_isDisposed) return;
    _bindings.pmvis_audio_resume(_handle);
  }

  /// Stop miniaudio playback.
  void stopAudio() {
    if (_isDisposed) return;
    _bindings.pmvis_audio_stop(_handle);
  }

  /// Set playback volume (0.0 to 1.0+).
  void setVolume(double volume) {
    if (_isDisposed) return;
    _bindings.pmvis_audio_set_volume(_handle, volume);
  }

  /// Manually supply interleaved stereo float PCM samples into projectM.
  void pushPcm(Float32List interleavedStereo) {
    if (_isDisposed || interleavedStereo.isEmpty) return;
    final length = interleavedStereo.length;
    if (length > _pcmBufferSize) {
      if (_nativePcmBuffer != ffi.nullptr) {
        calloc.free(_nativePcmBuffer);
      }
      _pcmBufferSize = length * 2;
      _nativePcmBuffer = calloc<ffi.Float>(_pcmBufferSize);
    }
    _nativePcmBuffer.asTypedList(length).setAll(0, interleavedStereo);
    final frames = length ~/ 2;
    _bindings.pmvis_push_pcm(_handle, _nativePcmBuffer, frames);
  }

  /// Copy the most recently rendered RGBA frame. Returns false if no new frame is available.
  bool copyFrameRgba(void Function(Uint8List pixels, int width, int height, int frameId) onFrame) {
    if (_isDisposed) return false;

    final hasNewFrame = _bindings.pmvis_copy_frame_rgba(
      _handle,
      _nativePixelBuffer,
      _pixelBufferSize,
      _outWidthPtr,
      _outHeightPtr,
      _outFrameIdPtr,
    );

    if (hasNewFrame != 0) {
      final w = _outWidthPtr.value;
      final h = _outHeightPtr.value;
      final frameId = _outFrameIdPtr.value;
      final byteCount = w * h * 4;
      if (byteCount <= _pixelBufferSize) {
        final typedList = _nativePixelBuffer.asTypedList(byteCount);
        onFrame(typedList, w, h, frameId);
        return true;
      }
    }
    return false;
  }

  /// Retrieve real-time performance statistics and audio analysis metrics.
  VisualizerStats getStats() {
    if (_isDisposed) {
      return const VisualizerStats(
        fps: 0,
        frameTimeMs: 0,
        bass: 0,
        mid: 0,
        treb: 0,
        framesRendered: 0,
        pcmFramesDropped: 0,
        isPlaying: false,
      );
    }
    _bindings.pmvis_get_stats(_handle, _statsPtr);
    final s = _statsPtr.ref;
    return VisualizerStats(
      fps: s.fps,
      frameTimeMs: s.frame_time_ms,
      bass: s.bass,
      mid: s.mid,
      treb: s.treb,
      framesRendered: s.frames_rendered,
      pcmFramesDropped: s.pcm_frames_dropped,
      isPlaying: s.is_playing != 0,
    );
  }

  /// Release native resources and destroy the render and audio threads.
  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;

    if (_hardwareTextureId != null && Platform.isAndroid) {
      _androidChannel.invokeMethod('destroyTexture', {
        'handle': _handle.address,
        'textureId': _hardwareTextureId,
      }).catchError((_) {});
      _hardwareTextureId = null;
    }

    _bindings.pmvis_destroy(_handle);
    _handle = ffi.nullptr;

    calloc.free(_nativePixelBuffer);
    calloc.free(_outWidthPtr);
    calloc.free(_outHeightPtr);
    calloc.free(_outFrameIdPtr);
    calloc.free(_statsPtr);
    if (_nativePcmBuffer != ffi.nullptr) {
      calloc.free(_nativePcmBuffer);
      _nativePcmBuffer = ffi.nullptr;
    }
  }
}

/// High-performance Flutter Widget that displays the projectM Milkdrop visualization.
class ProjectMWidget extends StatefulWidget {
  const ProjectMWidget({
    super.key,
    required this.controller,
    this.aspectRatio = 16 / 9,
    this.maintainAspectRatio = true,
    this.fit = BoxFit.contain,
    this.alignment = Alignment.center,
    this.backgroundColor = Colors.black,
    this.quality = VisualizerQuality.balanced,
    this.customWidth,
    this.customHeight,
    this.filterQuality = FilterQuality.low,
    this.placeholder,
  });

  /// Controller managing the native projectM + miniaudio instance.
  final ProjectMVisualizer controller;

  /// Target aspect ratio (width / height) to maintain for the visualizer.
  /// Standard Milkdrop presets default to 16 / 9 (~1.778).
  ///
  /// Set to `null` or set [maintainAspectRatio] to `false` to match the parent
  /// container's dimensions dynamically.
  final double? aspectRatio;

  /// Whether to maintain [aspectRatio] when laying out and rendering the visualizer.
  ///
  /// - When `true`: The visualizer renders at the designated aspect ratio, and scales
  ///   within the available constraints according to [fit] and [alignment],
  ///   letterboxing or pillarboxing if necessary with [backgroundColor].
  /// - When `false`: The visualizer fills whatever dimensions the parent constraints provide.
  final bool maintainAspectRatio;

  /// How the visualizer content is inscribed into the layout box.
  ///
  /// - [BoxFit.contain] (default): Entire visual is visible, letterboxed if ratios differ.
  /// - [BoxFit.cover]: Visual fills the entire space without black bars, cropping overflow
  ///   while preserving geometric circles and shapes undistorted.
  /// - [BoxFit.fill]: Stretches the visualizer to fill the entire box (when [maintainAspectRatio] is false).
  final BoxFit fit;

  /// Alignment of the visualizer inside its allocated layout box.
  /// Defaults to [Alignment.center].
  final Alignment alignment;

  /// Background color fill behind the visualization (visible during letterboxing/pillarboxing).
  /// Defaults to [Colors.black].
  final Color backgroundColor;

  /// Visualizer rendering quality profile.
  final VisualizerQuality quality;

  /// Custom render width in pixels when [quality] is [VisualizerQuality.custom].
  final int? customWidth;

  /// Custom render height in pixels when [quality] is [VisualizerQuality.custom].
  final int? customHeight;

  /// Image filtering quality applied when scaling the native texture/frame to the screen.
  final FilterQuality filterQuality;

  /// Optional widget displayed while the first frame is being rendered.
  final Widget? placeholder;

  @override
  State<ProjectMWidget> createState() => _ProjectMWidgetState();
}

class _ProjectMWidgetState extends State<ProjectMWidget> with SingleTickerProviderStateMixin {
  Ticker? _ticker;
  final ValueNotifier<ui.Image?> _imageNotifier = ValueNotifier<ui.Image?>(null);
  bool _isDecoding = false;
  int _lastWidth = 0;
  int _lastHeight = 0;
  Uint8List? _reusableFrameBytes;

  @override
  void initState() {
    super.initState();
    if (widget.controller.hardwareTextureId == null) {
      _ticker = createTicker(_onTick)..start();
    }
  }

  @override
  void didUpdateWidget(covariant ProjectMWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      if (widget.controller.hardwareTextureId == null) {
        _ticker ??= createTicker(_onTick)..start();
      } else {
        _ticker?.stop();
        _ticker?.dispose();
        _ticker = null;
      }
    }
  }

  void _onTick(Duration elapsed) {
    if (!mounted || _isDecoding || !widget.controller.isPlaying) return;

    widget.controller.copyFrameRgba((pixels, width, height, frameId) {
      _isDecoding = true;
      final byteCount = width * height * 4;
      if (_reusableFrameBytes == null || _reusableFrameBytes!.length != byteCount) {
        _reusableFrameBytes = Uint8List(byteCount);
      }
      _reusableFrameBytes!.setRange(0, byteCount, pixels);

      ui.decodeImageFromPixels(
        _reusableFrameBytes!,
        width,
        height,
        ui.PixelFormat.rgba8888,
        (image) {
          if (!mounted) {
            image.dispose();
            _isDecoding = false;
            return;
          }
          final oldImage = _imageNotifier.value;
          _imageNotifier.value = image;
          _isDecoding = false;
          oldImage?.dispose();
        },
      );
    });
  }

  @override
  void dispose() {
    _ticker?.dispose();
    _imageNotifier.value?.dispose();
    _imageNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Handle unbounded constraints safely (e.g. inside Column, ListView)
        final bool hasBoundedW = constraints.hasBoundedWidth && constraints.maxWidth > 0 && !constraints.maxWidth.isInfinite;
        final bool hasBoundedH = constraints.hasBoundedHeight && constraints.maxHeight > 0 && !constraints.maxHeight.isInfinite;

        final double effectiveAspect = (widget.maintainAspectRatio && widget.aspectRatio != null && widget.aspectRatio! > 0)
            ? widget.aspectRatio!
            : (hasBoundedW && hasBoundedH
                ? constraints.maxWidth / constraints.maxHeight
                : (16 / 9));

        double layoutWidth;
        double layoutHeight;

        if (hasBoundedW && hasBoundedH) {
          layoutWidth = constraints.maxWidth;
          layoutHeight = constraints.maxHeight;
        } else if (hasBoundedW) {
          layoutWidth = constraints.maxWidth;
          layoutHeight = layoutWidth / effectiveAspect;
        } else if (hasBoundedH) {
          layoutHeight = constraints.maxHeight;
          layoutWidth = layoutHeight * effectiveAspect;
        } else {
          // Unconstrained fallback
          layoutWidth = 960;
          layoutHeight = 960 / effectiveAspect;
        }

        // Determine target internal render resolution in native pixels
        int targetW;
        int targetH;

        switch (widget.quality) {
          case VisualizerQuality.eco:
            if (effectiveAspect >= 1.0) {
              targetH = 360;
              targetW = (targetH * effectiveAspect).round();
            } else {
              targetW = 360;
              targetH = (targetW / effectiveAspect).round();
            }
            break;
          case VisualizerQuality.balanced:
            if (effectiveAspect >= 1.0) {
              targetH = 540;
              targetW = (targetH * effectiveAspect).round();
            } else {
              targetW = 540;
              targetH = (targetW / effectiveAspect).round();
            }
            break;
          case VisualizerQuality.high:
            if (effectiveAspect >= 1.0) {
              targetH = 720;
              targetW = (targetH * effectiveAspect).round();
            } else {
              targetW = 720;
              targetH = (targetW / effectiveAspect).round();
            }
            break;
          case VisualizerQuality.native:
            final dpr = MediaQuery.devicePixelRatioOf(context);
            if (widget.maintainAspectRatio) {
              final fitted = applyBoxFit(
                widget.fit,
                Size(effectiveAspect, 1.0),
                Size(layoutWidth, layoutHeight),
              );
              targetW = (fitted.destination.width * dpr).round();
              targetH = (fitted.destination.height * dpr).round();
            } else {
              targetW = (layoutWidth * dpr).round();
              targetH = (layoutHeight * dpr).round();
            }
            break;
          case VisualizerQuality.custom:
            if (widget.customWidth != null && widget.customHeight != null) {
              targetW = widget.customWidth!;
              targetH = widget.customHeight!;
            } else if (widget.customWidth != null) {
              targetW = widget.customWidth!;
              targetH = (targetW / effectiveAspect).round();
            } else if (widget.customHeight != null) {
              targetH = widget.customHeight!;
              targetW = (targetH * effectiveAspect).round();
            } else {
              targetW = 960;
              targetH = 540;
            }
            break;
        }

        // Clamp to positive even integers for OpenGL stride alignment
        targetW = ((targetW > 1 ? targetW : 2) ~/ 2) * 2;
        targetH = ((targetH > 1 ? targetH : 2) ~/ 2) * 2;

        if (widget.controller.hardwareTextureId == null) {
          // On desktop (software readback via ui.decodeImageFromPixels), cap resolution to 960x540.
          // This keeps pixel memory overhead under 1.8MB per frame and guarantees 60-120Hz
          // without saturating Skia IO texture decode queues.
          if (targetW > 960) {
            targetH = (((targetH * (960.0 / targetW)).round()) ~/ 2) * 2;
            targetW = 960;
          }
          if (targetH > 540) {
            targetW = (((targetW * (540.0 / targetH)).round()) ~/ 2) * 2;
            targetH = 540;
          }
        }

        if (targetW != _lastWidth || targetH != _lastHeight) {
          _lastWidth = targetW;
          _lastHeight = targetH;
          widget.controller.setSize(targetW, targetH);
        }

        Widget visualizerContent;

        // 1. Android Zero-Copy Direct GPU Surface Texture
        if (widget.controller.hardwareTextureId != null) {
          visualizerContent = Texture(
            textureId: widget.controller.hardwareTextureId!,
            filterQuality: widget.filterQuality,
          );
        } else {
          // 2. High-performance lock-free Triple-buffered Pixel Fallback (Desktop / Web / Emulators)
          visualizerContent = ValueListenableBuilder<ui.Image?>(
            valueListenable: _imageNotifier,
            builder: (context, currentImage, _) {
              if (currentImage != null) {
                return RawImage(
                  image: currentImage,
                  filterQuality: widget.filterQuality,
                  fit: BoxFit.fill,
                );
              }

              return widget.placeholder ??
                  Container(
                    color: widget.backgroundColor,
                  );
            },
          );
        }

        return Container(
          width: layoutWidth,
          height: layoutHeight,
          color: widget.backgroundColor,
          child: FittedBox(
            fit: widget.fit,
            alignment: widget.alignment,
            child: SizedBox(
              width: targetW.toDouble(),
              height: targetH.toDouble(),
              child: visualizerContent,
            ),
          ),
        );
      },
    );
  }
}
