import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:projectm_visualizer/projectm_visualizer.dart';

import '../isolate_player.dart';
import '../services/projectm_preset_manager.dart';
import '../services/visualizer_settings_service.dart';

/// Centralized manager that caches and coordinates a single active [ProjectMVisualizer] instance
/// across small and fullscreen visualizers, completely eliminating freeze and crash cycles.
class ProjectMVisualizerManager {
  static final ProjectMVisualizerManager instance =
      ProjectMVisualizerManager._();
  ProjectMVisualizerManager._();

  ProjectMVisualizer? _sharedController;
  Future<ProjectMVisualizer>? _initFuture;
  int _activeClients = 0;
  Timer? _disposalTimer;

  Future<ProjectMVisualizer> acquireController({
    required int width,
    required int height,
  }) async {
    _disposalTimer?.cancel();
    _activeClients++;

    if (_sharedController != null && !_sharedController!.isDisposed) {
      return _sharedController!;
    }

    if (_initFuture != null) {
      return _initFuture!;
    }

    _initFuture = () async {
      try {
        final ctrl = await ProjectMVisualizer.create(
          width: width,
          height: height,
          enableHardwareTexture: true,
        );
        _sharedController = ctrl;
        return ctrl;
      } finally {
        _initFuture = null;
      }
    }();

    return _initFuture!;
  }

  void releaseController() {
    _activeClients = math.max(0, _activeClients - 1);
    if (_activeClients == 0) {
      _disposalTimer?.cancel();
      // Keep engine alive for 8 seconds during route/modal transitions
      _disposalTimer = Timer(const Duration(seconds: 8), () {
        if (_activeClients == 0 && _sharedController != null) {
          _sharedController?.dispose();
          _sharedController = null;
        }
      });
    }
  }
}

/// Embedded Milkdrop visualizer widget powered by libprojectM 4.1.8.
///
/// Seamlessly taps Sauti's native [IsolateAudioPlayer.analyzerStereoStream]
/// to feed 60 FPS audio reactive equations into the projectM render engine.
class ProjectMAudioVisualizer extends StatefulWidget {
  final IsolateAudioPlayer player;
  final bool isPlaying;
  final String presetId;
  final VisualizerQuality quality;
  final double? aspectRatio;
  final bool maintainAspectRatio;
  final BoxFit fit;
  final Alignment alignment;
  final Color backgroundColor;
  final double height;
  final double width;
  final bool showTelemetryOverlay;
  final ValueChanged<VisualizerStats>? onStatsChanged;

  const ProjectMAudioVisualizer({
    super.key,
    required this.player,
    this.isPlaying = true,
    this.presetId = 'neon_hyperspace',
    this.quality = VisualizerQuality.balanced,
    this.aspectRatio,
    this.maintainAspectRatio = false,
    this.fit = BoxFit.cover,
    this.alignment = Alignment.center,
    this.backgroundColor = Colors.black,
    this.height = 160.0,
    this.width = double.infinity,
    this.showTelemetryOverlay = false,
    this.onStatsChanged,
  });

  @override
  State<ProjectMAudioVisualizer> createState() => _ProjectMAudioVisualizerState();
}

class _ProjectMAudioVisualizerState extends State<ProjectMAudioVisualizer> {
  ProjectMVisualizer? _controller;
  StreamSubscription? _stereoSub;
  StreamSubscription? _settingsSub;
  Timer? _telemetryTimer;
  final ValueNotifier<VisualizerStats?> _statsNotifier =
      ValueNotifier<VisualizerStats?>(null);
  bool _isInitializing = true;
  String _activePresetId = '';

  int _resolveTargetFps() {
    return VisualizerSettingsService.instance.targetFps;
  }

  @override
  void initState() {
    super.initState();
    _activePresetId = widget.presetId;
    _settingsSub =
        VisualizerSettingsService.instance.onSettingsChanged.listen((_) {
      if (mounted && _controller != null) {
        final targetFps = _resolveTargetFps();
        _controller!.setFps(targetFps);
        _controller!.setSoftCutDuration(
            VisualizerSettingsService.instance.softCutDuration);
        _controller!.setBatterySaver(
            VisualizerSettingsService.instance.batterySaverEnabled);
      }
    });
    _initVisualizer();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_controller != null) {
      final targetFps = _resolveTargetFps();
      _controller!.setFps(targetFps);
    }
  }

  Future<void> _initVisualizer() async {
    try {
      final isCompact = widget.height <= 220;
      final controller =
          await ProjectMVisualizerManager.instance.acquireController(
        width: 960,
        height: 540,
      );

      final targetFps = _resolveTargetFps();
      controller.setFps(targetFps);
      controller.setMeshSize(isCompact ? 24 : 32, isCompact ? 18 : 24);
      controller.setSoftCutDuration(
          VisualizerSettingsService.instance.softCutDuration);
      controller.setBatterySaver(
          VisualizerSettingsService.instance.batterySaverEnabled);
      controller.setIsPlaying(widget.isPlaying);

      final texturesPath = ProjectMPresetManager.instance.getTexturesPath();
      if (texturesPath != null) {
        controller.setTextureSearchPath(texturesPath);
      }

      final preset = ProjectMPresetLibrary.findById(_activePresetId);
      await controller.loadPreset(preset, smoothTransition: false);

      _stereoSub = widget.player.analyzerStereoStream.listen((samples) {
        if (!mounted || _controller == null || samples.isEmpty) return;
        if (widget.isPlaying) {
          _controller!.pushPcm(samples);
        }
      });

      if (widget.showTelemetryOverlay || widget.onStatsChanged != null) {
        _telemetryTimer = Timer.periodic(const Duration(milliseconds: 200), (_) {
          if (!mounted || _controller == null) return;
          final stats = _controller!.getStats();
          if (mounted) {
            _statsNotifier.value = stats;
            widget.onStatsChanged?.call(stats);
          }
        });
      }

      if (mounted) {
        setState(() {
          _controller = controller;
          _isInitializing = false;
        });
      } else {
        ProjectMVisualizerManager.instance.releaseController();
      }
    } catch (e) {
      debugPrint('ProjectMAudioVisualizer initialization error: $e');
      if (mounted) {
        setState(() => _isInitializing = false);
      }
    }
  }

  @override
  void didUpdateWidget(covariant ProjectMAudioVisualizer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isPlaying != widget.isPlaying) {
      _controller?.setIsPlaying(widget.isPlaying);
    }

    if (oldWidget.presetId != widget.presetId && widget.presetId.isNotEmpty) {
      _activePresetId = widget.presetId;
      final preset = ProjectMPresetLibrary.findById(_activePresetId);
      _controller?.loadPreset(preset, smoothTransition: true);
    }

    if (oldWidget.height != widget.height && _controller != null) {
      final isCompact = widget.height <= 220;
      _controller!.setMeshSize(isCompact ? 24 : 32, isCompact ? 18 : 24);
    }

    if (oldWidget.player != widget.player) {
      _stereoSub?.cancel();
      _stereoSub = widget.player.analyzerStereoStream.listen((samples) {
        if (!mounted || _controller == null || samples.isEmpty) return;
        if (widget.isPlaying) {
          _controller!.pushPcm(samples);
        }
      });
    }
  }

  @override
  void dispose() {
    _settingsSub?.cancel();
    _stereoSub?.cancel();
    _telemetryTimer?.cancel();
    _statsNotifier.dispose();
    ProjectMVisualizerManager.instance.releaseController();
    _controller = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isInitializing || _controller == null) {
      return Container(
        height: widget.height,
        width: widget.width,
        color: widget.backgroundColor,
      );
    }

    final isCompact = widget.height <= 220;
    final effectiveQuality =
        isCompact && widget.quality == VisualizerQuality.balanced
            ? VisualizerQuality.eco
            : widget.quality;

    Widget content = ProjectMWidget(
      controller: _controller!,
      aspectRatio: widget.aspectRatio,
      maintainAspectRatio: widget.maintainAspectRatio,
      fit: widget.fit,
      alignment: widget.alignment,
      backgroundColor: widget.backgroundColor,
      quality: effectiveQuality,
      filterQuality: FilterQuality.medium,
    );

    if (widget.showTelemetryOverlay) {
      content = Stack(
        fit: StackFit.expand,
        children: [
          content,
          Positioned(
            bottom: 8,
            left: 12,
            child: ValueListenableBuilder<VisualizerStats?>(
              valueListenable: _statsNotifier,
              builder: (context, stats, _) {
                if (stats == null) return const SizedBox.shrink();
                return _buildTelemetryBadge(stats);
              },
            ),
          ),
        ],
      );
    }

    return SizedBox(
      height: widget.height,
      width: widget.width,
      child: content,
    );
  }

  Widget _buildTelemetryBadge(VisualizerStats stats) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${stats.fps.toStringAsFixed(0)} FPS',
            style: const TextStyle(
              color: Color(0xFF00E5FF),
              fontSize: 10,
              fontWeight: FontWeight.bold,
              fontFamily: 'monospace',
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${stats.frameTimeMs.toStringAsFixed(1)}ms',
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 10,
              fontFamily: 'monospace',
            ),
          ),
          const SizedBox(width: 8),
          _buildMeterBar('B', stats.bass, const Color(0xFF00E5FF)),
          const SizedBox(width: 4),
          _buildMeterBar('M', stats.mid, const Color(0xFF9D4EDD)),
          const SizedBox(width: 4),
          _buildMeterBar('T', stats.treb, const Color(0xFFFF007A)),
        ],
      ),
    );
  }

  Widget _buildMeterBar(String label, double value, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: TextStyle(
            color: color.withValues(alpha: 0.8),
            fontSize: 9,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(width: 2),
        SizedBox(
          width: 20,
          height: 4,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: value.clamp(0.0, 1.0),
              backgroundColor: Colors.white12,
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
        ),
      ],
    );
  }
}
