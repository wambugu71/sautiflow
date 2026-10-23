import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/scheduler.dart';
import 'package:material_ui/material_ui.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:sautiflow/sautiflow.dart';

import '../isolate_player.dart';
import '../database/preferences_store.dart';
import 'package:projectm_visualizer/projectm_visualizer.dart';
import 'dual_oscilloscope_visualizer.dart';
import 'fluid_area_visualizer.dart';
import 'physics_dots_visualizer.dart';
import 'projectm_audio_visualizer.dart';
import 'projectm_preset_manager_dialog.dart';
import '../services/projectm_preset_manager.dart';
import '../services/visualizer_settings_service.dart';
import 'stereo_vectorscope_graph.dart';

/// Unified host widget that renders any supported audio visualizer at a specified height/width.
class AudioVisualizerHost extends StatefulWidget {
  final IsolateAudioPlayer player;
  final String analyzerType;
  final String spectrumStyle;
  final Color primaryColor;
  final List<double> currentAnalyzerValues;
  final List<double> peakValues;
  final ValueNotifier<List<double>>? analyzerValuesNotifier;
  final ValueNotifier<List<double>>? peakValuesNotifier;
  final double height;
  final double width;
  final bool isPlaying;
  final int maxFreq;
  final bool showGrids;
  final bool logScale;
  final bool autoFit;
  final ValueChanged<String>? onThemeChanged;

  const AudioVisualizerHost({
    super.key,
    required this.player,
    required this.analyzerType,
    required this.spectrumStyle,
    required this.primaryColor,
    this.currentAnalyzerValues = const [],
    this.peakValues = const [],
    this.analyzerValuesNotifier,
    this.peakValuesNotifier,
    this.height = 160.0,
    this.width = double.infinity,
    this.isPlaying = true,
    this.maxFreq = 24000,
    this.showGrids = true,
    this.logScale = true,
    this.autoFit = false,
    this.onThemeChanged,
  });

  @override
  State<AudioVisualizerHost> createState() => _AudioVisualizerHostState();
}

class _AudioVisualizerHostState extends State<AudioVisualizerHost> {
  bool _hasEverLoadedProjectM = false;
  Timer? _autoChangeTimer;
  StreamSubscription? _settingsSub;

  @override
  void initState() {
    super.initState();
    _settingsSub =
        VisualizerSettingsService.instance.onSettingsChanged.listen((_) {
      if (mounted) _syncAutoChangeTimer();
    });
    _syncAutoChangeTimer();
  }

  void _syncAutoChangeTimer() {
    _autoChangeTimer?.cancel();
    _autoChangeTimer = null;
    if (!widget.isPlaying ||
        !VisualizerSettingsService.instance.autoChangeEnabled) {
      return;
    }

    final intervalSec =
        VisualizerSettingsService.instance.autoChangeIntervalSeconds;
    _autoChangeTimer = Timer.periodic(Duration(seconds: intervalSec), (_) {
      if (!mounted || !widget.isPlaying) return;
      final next = VisualizerSettingsService.instance.getNextPresetId(
        currentAnalyzerType: widget.analyzerType,
        currentSpectrumStyle: widget.spectrumStyle,
      );
      if (next != widget.spectrumStyle) {
        widget.onThemeChanged?.call(next);
        PreferencesStore.instance.setString('spectrum_style', next);
      }
    });
  }

  @override
  void didUpdateWidget(covariant AudioVisualizerHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isPlaying != widget.isPlaying ||
        oldWidget.analyzerType != widget.analyzerType) {
      _syncAutoChangeTimer();
    }
  }

  @override
  void dispose() {
    _autoChangeTimer?.cancel();
    _settingsSub?.cancel();
    super.dispose();
  }

  bool _isProjectM(String type) {
    if (type == 'projectm') return true;
    const standardNonPm = {
      'oscilloscope',
      'Dual Oscilloscope',
      'Waveform',
      'vectorscope',
      'Stereo Vectorscope',
      'Stereo Radar',
      'Radar',
      'area',
      'Waves',
      'bar',
      'dots',
      'Dots',
    };
    return !standardNonPm.contains(type);
  }

  @override
  Widget build(BuildContext context) {
    final isPm = _isProjectM(widget.analyzerType);
    if (isPm) {
      _hasEverLoadedProjectM = true;
    }

    Widget? standardViz;
    if (widget.analyzerType == 'oscilloscope' ||
        widget.analyzerType == 'Dual Oscilloscope' ||
        widget.analyzerType == 'Waveform') {
      standardViz = RepaintBoundary(
        child: DualOscilloscopeVisualizer(
          player: widget.player,
          stereoStream: widget.player.analyzerStereoStream,
          analyzerStream: widget.player.analyzerStream,
          isPlaying: widget.isPlaying,
          primaryColor: widget.primaryColor,
          height: widget.height,
        ),
      );
    } else if (widget.analyzerType == 'vectorscope' ||
        widget.analyzerType == 'Stereo Vectorscope' ||
        widget.analyzerType == 'Stereo Radar' ||
        widget.analyzerType == 'Radar') {
      standardViz = RepaintBoundary(
        child: StereoVectorscopeGraph(
          width: 1.5,
          isEnabled: true,
          height: widget.height,
          primaryColor: widget.primaryColor,
          analyzerStream: widget.player.analyzerStream,
          live: true,
          stereoAnalyzerStream: widget.player.analyzerStereoStream,
          statsProvider: () => widget.player.getStereoStats(),
        ),
      );
    } else if (widget.analyzerType == 'area' ||
        widget.analyzerType == 'Waves') {
      Widget buildArea(List<double> values) {
        return FluidAreaVisualizer(
          values: values,
          primaryColor: widget.primaryColor,
          height: widget.height,
          themeName: widget.spectrumStyle,
          showGrids: widget.showGrids,
          logScale: widget.logScale,
          autoFit: widget.autoFit,
          maxFreq: widget.maxFreq,
          onThemeChanged: widget.onThemeChanged,
        );
      }

      if (widget.analyzerValuesNotifier != null) {
        standardViz = RepaintBoundary(
          child: ValueListenableBuilder<List<double>>(
            valueListenable: widget.analyzerValuesNotifier!,
            builder: (context, values, _) => buildArea(values),
          ),
        );
      } else {
        standardViz = RepaintBoundary(
          child: buildArea(widget.currentAnalyzerValues),
        );
      }
    } else if (widget.analyzerType == 'bar' ||
        widget.analyzerType == 'dots' ||
        widget.analyzerType == 'Dots') {
      Widget buildDots(List<double> values) {
        return PhysicsDotsVisualizer(
          values: values,
          primaryColor: widget.primaryColor,
          height: widget.height,
          themeName: widget.spectrumStyle,
          showGrids: widget.showGrids,
          logScale: widget.logScale,
          autoFit: widget.autoFit,
          maxFreq: widget.maxFreq,
          onThemeChanged: widget.onThemeChanged,
        );
      }

      if (widget.analyzerValuesNotifier != null) {
        standardViz = RepaintBoundary(
          child: ValueListenableBuilder<List<double>>(
            valueListenable: widget.analyzerValuesNotifier!,
            builder: (context, values, _) => buildDots(values),
          ),
        );
      } else {
        standardViz = RepaintBoundary(
          child: buildDots(widget.currentAnalyzerValues),
        );
      }
    }

    if (!_hasEverLoadedProjectM) {
      return standardViz ?? const SizedBox.shrink();
    }

    final preset = ProjectMPresetLibrary.findById(
      widget.spectrumStyle.isNotEmpty && widget.spectrumStyle != 'minimal'
          ? widget.spectrumStyle
          : widget.analyzerType,
    );
    final isCompact = widget.height <= 220;

    final projectMViz = RepaintBoundary(
      child: ProjectMAudioVisualizer(
        key: const ValueKey('projectm_vis_host_instance'),
        player: widget.player,
        isPlaying: isPm && widget.isPlaying,
        presetId: preset.id,
        height: widget.height,
        width: widget.width,
        quality: isCompact ? VisualizerQuality.eco : VisualizerQuality.balanced,
        fit: BoxFit.cover,
      ),
    );

    if (standardViz == null) {
      return projectMViz;
    }

    return Stack(
      fit: StackFit.passthrough,
      children: [
        Offstage(
          offstage: !isPm,
          child: projectMViz,
        ),
        if (!isPm) standardViz,
      ],
    );
  }
}

/// Fullscreen immersive audio spectrum analyzer / visualizer overlay.
///
/// Runs smoothly at native display refresh rate (20Hz - 120Hz ProMotion)
/// with isolated composited rendering layers and seamless Hero return flight.
class FullscreenSpectrumVisualizer extends StatefulWidget {
  final IsolateAudioPlayer player;
  final ValueNotifier<List<double>> analyzerValuesNotifier;
  final ValueNotifier<List<double>> peakValuesNotifier;
  final Color primaryColor;
  final String initialAnalyzerType;
  final String initialSpectrumStyle;
  final bool isPlaying;
  final int maxFreq;
  final int sampleRate;
  final bool analyzerShowGrids;
  final bool analyzerLogScale;
  final bool analyzerAutoFit;
  final ValueChanged<String>? onAnalyzerTypeChanged;
  final ValueChanged<String>? onSpectrumStyleChanged;

  const FullscreenSpectrumVisualizer({
    super.key,
    required this.player,
    required this.analyzerValuesNotifier,
    required this.peakValuesNotifier,
    required this.primaryColor,
    required this.initialAnalyzerType,
    required this.initialSpectrumStyle,
    required this.isPlaying,
    required this.maxFreq,
    required this.sampleRate,
    required this.analyzerShowGrids,
    required this.analyzerLogScale,
    required this.analyzerAutoFit,
    this.onAnalyzerTypeChanged,
    this.onSpectrumStyleChanged,
  });

  @override
  State<FullscreenSpectrumVisualizer> createState() =>
      _FullscreenSpectrumVisualizerState();
}

class _FullscreenSpectrumVisualizerState
    extends State<FullscreenSpectrumVisualizer>
    with SingleTickerProviderStateMixin {
  late String _currentAnalyzerType;
  late String _currentSpectrumStyle;
  bool _showHud = true;
  Timer? _autoHideTimer;

  // Real-time Display VSync Telemetry (estimates 60/90/120 Hz)
  late final Ticker _fpsTicker;
  DateTime? _lastTickTime;
  double _measuredFps = 60.0;
  final ValueNotifier<double> _fpsNotifier = ValueNotifier<double>(60.0);
  int _fpsFrameCount = 0;

  // Swipe-down dismiss drag accumulator
  double _dragOffsetY = 0.0;

  @override
  void initState() {
    super.initState();
    _currentAnalyzerType = widget.initialAnalyzerType;
    _currentSpectrumStyle = widget.initialSpectrumStyle;

    _fpsTicker = createTicker(_onFpsTick);
    _fpsTicker.start();

    _scheduleHudAutoHide();
  }

  void _onFpsTick(Duration elapsed) {
    final now = DateTime.now();
    if (_lastTickTime != null) {
      final dt = now.difference(_lastTickTime!).inMicroseconds / 1000000.0;
      if (dt > 0.001 && dt < 0.2) {
        final instantFps = 1.0 / dt;
        _measuredFps = (_measuredFps * 0.92) + (instantFps * 0.08);
      }
    }
    _lastTickTime = now;
    _fpsFrameCount++;
    if (_fpsFrameCount % 30 == 0 && mounted) {
      _fpsNotifier.value = _measuredFps;
    }
  }

  void _scheduleHudAutoHide() {
    _autoHideTimer?.cancel();
    _autoHideTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && _showHud) {
        setState(() => _showHud = false);
      }
    });
  }

  void _toggleHud() {
    setState(() {
      _showHud = !_showHud;
    });
    if (_showHud) {
      _scheduleHudAutoHide();
    } else {
      _autoHideTimer?.cancel();
    }
  }

  String get _visualizerLabel {
    if (_currentAnalyzerType == 'oscilloscope' ||
        _currentAnalyzerType == 'Dual Oscilloscope' ||
        _currentAnalyzerType == 'Waveform') {
      return 'Waveform';
    }
    if (_currentAnalyzerType == 'vectorscope' ||
        _currentAnalyzerType == 'Stereo Vectorscope' ||
        _currentAnalyzerType == 'Stereo Radar' ||
        _currentAnalyzerType == 'Radar') {
      return 'Radar';
    }
    if (_currentAnalyzerType == 'area' ||
        _currentAnalyzerType == 'Waves') {
      return 'Waves (${_currentSpectrumStyle.toUpperCase()})';
    }
    if (_currentAnalyzerType == 'bar' ||
        _currentAnalyzerType == 'dots' ||
        _currentAnalyzerType == 'Dots') {
      return 'Dots (${_currentSpectrumStyle.toUpperCase()})';
    }
    final preset = ProjectMPresetLibrary.findById(
      _currentSpectrumStyle.isNotEmpty && _currentSpectrumStyle != 'minimal'
          ? _currentSpectrumStyle
          : _currentAnalyzerType,
    );
    return 'Milkdrop: ${preset.displayName}';
  }

  void _selectAnalyzerType(String newType) {
    setState(() {
      _currentAnalyzerType = newType;
    });
    PreferencesStore.instance.setString('analyzer_type', newType);
    widget.onAnalyzerTypeChanged?.call(newType);
    _scheduleHudAutoHide();
  }

  void _selectSpectrumStyle(String newStyle) {
    setState(() {
      _currentSpectrumStyle = newStyle;
    });
    PreferencesStore.instance.setString('spectrum_style', newStyle);
    widget.onSpectrumStyleChanged?.call(newStyle);
    _scheduleHudAutoHide();
  }

  @override
  void dispose() {
    _fpsTicker.dispose();
    _fpsNotifier.dispose();
    _autoHideTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = widget.primaryColor;
    final topPadding = MediaQuery.paddingOf(context).top;
    final bottomPadding = MediaQuery.paddingOf(context).bottom;

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _toggleHud,
        onVerticalDragUpdate: (details) {
          if (details.delta.dy > 0 || _dragOffsetY > 0) {
            setState(() {
              _dragOffsetY = math.max(0.0, _dragOffsetY + details.delta.dy);
            });
          }
        },
        onVerticalDragEnd: (details) {
          if (_dragOffsetY > 90.0 ||
              (details.primaryVelocity != null &&
                  details.primaryVelocity! > 350.0)) {
            Navigator.of(context).pop();
          } else {
            setState(() => _dragOffsetY = 0.0);
          }
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          transform: Matrix4.translationValues(0.0, _dragOffsetY, 0.0),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // 1. High-Performance Visualizer Canvas (Isolated RepaintBoundary)
              Positioned.fill(
                child: Material(
                  color: Colors.transparent,
                  child: Container(
                    color: const Color(0xFF06080D),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        return AudioVisualizerHost(
                          player: widget.player,
                          analyzerType: _currentAnalyzerType,
                          spectrumStyle: _currentSpectrumStyle,
                          primaryColor: primaryColor,
                          analyzerValuesNotifier:
                              widget.analyzerValuesNotifier,
                          peakValuesNotifier: widget.peakValuesNotifier,
                          height: constraints.maxHeight,
                          width: constraints.maxWidth,
                          isPlaying: widget.isPlaying,
                          maxFreq: widget.maxFreq,
                          showGrids: widget.analyzerShowGrids,
                          logScale: widget.analyzerLogScale,
                          autoFit: widget.analyzerAutoFit,
                          onThemeChanged: _selectSpectrumStyle,
                        );
                      },
                    ),
                  ),
                ),
              ),

              // 2. Animated HUD Overlay (Header Bar, Telemetry, Menus)
              AnimatedOpacity(
                duration: const Duration(milliseconds: 220),
                opacity: _showHud ? 1.0 : 0.0,
                child: IgnorePointer(
                  ignoring: !_showHud,
                  child: Column(
                    children: [
                      // Top Bar
                      Container(
                        padding: EdgeInsets.fromLTRB(
                          12.0,
                          topPadding + 6.0,
                          12.0,
                          10.0,
                        ),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.black.withValues(alpha: 0.85),
                              Colors.black.withValues(alpha: 0.0),
                            ],
                          ),
                        ),
                        child: Row(
                          children: [
                            M3EIconButton(
                              variant: M3EIconButtonVariant.tonal,
                              icon: const Icon(
                                Icons.fullscreen_exit_rounded,
                                size: 22,
                                color: Colors.white,
                              ),
                              onPressed: () => Navigator.of(context).pop(),
                            ),
                            const SizedBox(width: 8),

                            // Visualizer Type Selector Dropdown Menu
                            M3EMenu(
                              anchorBuilder: (context, open) => InkWell(
                                onTap: open,
                                borderRadius: BorderRadius.circular(10),
                                child: Container(
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(10),
                                    color: Colors.black.withValues(alpha: 0.55),
                                    border: Border.all(
                                      color: primaryColor.withValues(alpha: 0.35),
                                    ),
                                  ),
                                  height: 36,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.grid_view_rounded,
                                        color: primaryColor,
                                        size: 16,
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        _visualizerLabel,
                                        style: TextStyle(
                                          color: primaryColor,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      Icon(
                                        Icons.keyboard_arrow_down_rounded,
                                        color: primaryColor,
                                        size: 18,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              children: [
                                M3EMenuGroup.entries(
                                  label: 'Visualizer Modes',
                                  entries: [
                                    M3EMenuEntry(
                                      label: 'Waves',
                                      leading: Icon(
                                        Icons.water_rounded,
                                        color: _currentAnalyzerType == 'area'
                                            ? primaryColor
                                            : null,
                                        size: 18,
                                      ),
                                      onPressed: () =>
                                          _selectAnalyzerType('area'),
                                    ),
                                    M3EMenuEntry(
                                      label: 'Dots',
                                      leading: Icon(
                                        Icons.grain_rounded,
                                        color: _currentAnalyzerType == 'dots' ||
                                                _currentAnalyzerType == 'bar'
                                            ? primaryColor
                                            : null,
                                        size: 18,
                                      ),
                                      onPressed: () =>
                                          _selectAnalyzerType('dots'),
                                    ),
                                    M3EMenuEntry(
                                      label: 'Waveform',
                                      leading: Icon(
                                        Icons.waves_rounded,
                                        color: _currentAnalyzerType ==
                                                'oscilloscope'
                                            ? primaryColor
                                            : null,
                                        size: 18,
                                      ),
                                      onPressed: () =>
                                          _selectAnalyzerType('oscilloscope'),
                                    ),
                                    M3EMenuEntry(
                                      label: 'Radar',
                                      leading: Icon(
                                        Icons.radar_rounded,
                                        color: _currentAnalyzerType ==
                                                'vectorscope'
                                            ? primaryColor
                                            : null,
                                        size: 18,
                                      ),
                                      onPressed: () =>
                                          _selectAnalyzerType('vectorscope'),
                                    ),
                                  ],
                                ),
                                M3EMenuGroup.entries(
                                  label: 'Milkdrop Library & Downloads',
                                  entries: [
                                    M3EMenuEntry(
                                      label: 'Browse & Download Presets...',
                                      leading: Icon(
                                        Icons.cloud_download_outlined,
                                        size: 16,
                                        color: primaryColor,
                                      ),
                                      onPressed: () {
                                        _scheduleHudAutoHide();
                                        ProjectMPresetManagerDialog.show(
                                          context,
                                          activePresetId: _currentSpectrumStyle,
                                          onPresetSelected: (preset) {
                                            setState(() {
                                              _currentAnalyzerType = 'projectm';
                                              _currentSpectrumStyle = preset.id;
                                            });
                                            PreferencesStore.instance.setString(
                                                'analyzer_type', 'projectm');
                                            PreferencesStore.instance.setString(
                                                'spectrum_style', preset.id);
                                            widget.onAnalyzerTypeChanged
                                                ?.call('projectm');
                                            widget.onSpectrumStyleChanged
                                                ?.call(preset.id);
                                            _scheduleHudAutoHide();
                                          },
                                        );
                                      },
                                    ),
                                    M3EMenuEntry(
                                      label: 'Import .milk from Device...',
                                      leading: Icon(
                                        Icons.file_open_outlined,
                                        size: 16,
                                        color: primaryColor,
                                      ),
                                      onPressed: () async {
                                        _scheduleHudAutoHide();
                                        final summary =
                                            await ProjectMPresetManager.instance
                                                .pickAndImportFromDisk();
                                        if (summary
                                                .importedPresets.isNotEmpty &&
                                            mounted) {
                                          final first =
                                              summary.importedPresets.first;
                                          setState(() {
                                            _currentAnalyzerType = 'projectm';
                                            _currentSpectrumStyle = first.id;
                                          });
                                          PreferencesStore.instance.setString(
                                              'analyzer_type', 'projectm');
                                          PreferencesStore.instance.setString(
                                              'spectrum_style', first.id);
                                          widget.onAnalyzerTypeChanged
                                              ?.call('projectm');
                                          widget.onSpectrumStyleChanged
                                              ?.call(first.id);
                                          _scheduleHudAutoHide();
                                        }
                                      },
                                    ),
                                  ],
                                ),
                                M3EMenuGroup.entries(
                                  label:
                                      'Milkdrop Presets (${ProjectMPresetLibrary.allWithCustom.length})',
                                  entries: ProjectMPresetLibrary.allWithCustom
                                      .map((preset) {
                                    final isSelected = (_currentAnalyzerType ==
                                                'projectm' ||
                                            _currentAnalyzerType ==
                                                preset.id) &&
                                        (_currentSpectrumStyle == preset.id ||
                                            _currentAnalyzerType == preset.id);
                                    return M3EMenuEntry(
                                      label: preset.displayName,
                                      leading: Icon(
                                        Icons.auto_awesome_rounded,
                                        color: isSelected ? primaryColor : null,
                                        size: 16,
                                      ),
                                      onPressed: () {
                                        setState(() {
                                          _currentAnalyzerType = 'projectm';
                                          _currentSpectrumStyle = preset.id;
                                        });
                                        PreferencesStore.instance.setString(
                                            'analyzer_type', 'projectm');
                                        PreferencesStore.instance.setString(
                                            'spectrum_style', preset.id);
                                        widget.onAnalyzerTypeChanged
                                            ?.call('projectm');
                                        widget.onSpectrumStyleChanged
                                            ?.call(preset.id);
                                        _scheduleHudAutoHide();
                                      },
                                    );
                                  }).toList(),
                                ),
                              ],
                            ),

                            const Spacer(),

                            // Telemetry Badge: Live Refresh Rate & DAC Hardware Specs
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 9,
                                vertical: 5,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.55),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.12),
                                ),
                              ),
                              child: ValueListenableBuilder<double>(
                                valueListenable: _fpsNotifier,
                                builder: (context, fps, _) {
                                  return Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Container(
                                        width: 6,
                                        height: 6,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: fps >= 100
                                              ? const Color(0xFF00E676)
                                              : primaryColor,
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        '${fps.round()} Hz • ${(widget.maxFreq / 1000).toStringAsFixed(1)}k Nyquist',
                                        style: const TextStyle(
                                          color: Colors.white70,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          letterSpacing: 0.3,
                                        ),
                                      ),
                                    ],
                                  );
                                },
                              ),
                            ),
                            const SizedBox(width: 8),

                            // Milkdrop Presets Library & Downloader Button
                            Material(
                              color: Colors.transparent,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(10),
                                onTap: () {
                                  _scheduleHudAutoHide();
                                  ProjectMPresetManagerDialog.show(
                                    context,
                                    activePresetId: _currentSpectrumStyle,
                                    onPresetSelected: (preset) {
                                      setState(() {
                                        _currentAnalyzerType = 'projectm';
                                        _currentSpectrumStyle = preset.id;
                                      });
                                      PreferencesStore.instance.setString(
                                          'analyzer_type', 'projectm');
                                      PreferencesStore.instance.setString(
                                          'spectrum_style', preset.id);
                                      widget.onAnalyzerTypeChanged
                                          ?.call('projectm');
                                      widget.onSpectrumStyleChanged
                                          ?.call(preset.id);
                                    },
                                  );
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 9,
                                    vertical: 5,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.55),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: primaryColor.withValues(alpha: 0.4),
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.auto_awesome,
                                        size: 14,
                                        color: primaryColor,
                                      ),
                                      const SizedBox(width: 5),
                                      Text(
                                        'Presets',
                                        style: TextStyle(
                                          color: Colors.white
                                              .withValues(alpha: 0.9),
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          letterSpacing: 0.3,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      const Spacer(),

                      // Bottom HUD: Stereo RMS Meter + Pull-down hint
                      Container(
                        padding: EdgeInsets.fromLTRB(
                          16.0,
                          12.0,
                          16.0,
                          bottomPadding + 10.0,
                        ),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                            colors: [
                              Colors.black.withValues(alpha: 0.88),
                              Colors.black.withValues(alpha: 0.0),
                            ],
                          ),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Live stereo RMS dB meter
                            RepaintBoundary(
                              child: RmsMeterWidget(
                                analyzerStream: widget.player.analyzerStream,
                                isPlaying: widget.isPlaying,
                                primaryColor: primaryColor,
                              ),
                            ),
                            const SizedBox(height: 10),
                            // Pull-down handle pill
                            Center(
                              child: Container(
                                width: 38,
                                height: 4,
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.4),
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Swipe down or tap close to return to EQ',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.35),
                                fontSize: 11,
                                letterSpacing: 0.4,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
