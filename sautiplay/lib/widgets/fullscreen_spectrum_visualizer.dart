import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/scheduler.dart';
import 'package:material_ui/material_ui.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:sautiflow/sautiflow.dart';

import '../isolate_player.dart';
import '../database/preferences_store.dart';
import 'dual_oscilloscope_visualizer.dart';
import 'fluid_area_visualizer.dart';
import 'glsl_audio_visualizer.dart';
import 'physics_dots_visualizer.dart';
import 'stereo_vectorscope_graph.dart';

/// Unified host widget that renders any supported audio visualizer at a specified height/width.
class AudioVisualizerHost extends StatelessWidget {
  final IsolateAudioPlayer player;
  final String analyzerType;
  final String spectrumStyle;
  final Color primaryColor;
  final List<double> currentAnalyzerValues;
  final List<double> peakValues;
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
    required this.currentAnalyzerValues,
    required this.peakValues,
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
  Widget build(BuildContext context) {
    if (analyzerType == 'oscilloscope' ||
        analyzerType == 'Dual Oscilloscope' ||
        analyzerType == 'Waveform') {
      return RepaintBoundary(
        child: DualOscilloscopeVisualizer(
          player: player,
          stereoStream: player.analyzerStereoStream,
          analyzerStream: player.analyzerStream,
          isPlaying: isPlaying,
          primaryColor: primaryColor,
          height: height,
        ),
      );
    }

    if (analyzerType == 'vectorscope' ||
        analyzerType == 'Stereo Vectorscope' ||
        analyzerType == 'Stereo Radar' ||
        analyzerType == 'Radar') {
      return RepaintBoundary(
        child: StereoVectorscopeGraph(
          width: 1.5,
          isEnabled: true,
          height: height,
          primaryColor: primaryColor,
          analyzerStream: player.analyzerStream,
          live: true,
          stereoAnalyzerStream: player.analyzerStereoStream,
          statsProvider: () => player.getStereoStats(),
        ),
      );
    }

    for (final style in GlslShaderStyle.values) {
      if (analyzerType == style.name ||
          analyzerType == style.displayName ||
          analyzerType.toLowerCase() == style.name.toLowerCase() ||
          analyzerType.toLowerCase() == style.displayName.toLowerCase()) {
        return GlslAudioVisualizerWidget(
          analyzerStream: player.analyzerStream,
          isPlaying: isPlaying,
          style: style,
          primaryColor: primaryColor,
          height: height,
          width: width,
        );
      }
    }

    if (analyzerType == 'area') {
      return FluidAreaVisualizer(
        values: currentAnalyzerValues,
        primaryColor: primaryColor,
        height: height,
        themeName: spectrumStyle,
        showGrids: showGrids,
        logScale: logScale,
        autoFit: autoFit,
        maxFreq: maxFreq,
        onThemeChanged: onThemeChanged,
      );
    }

    // Default: physics dots spectrum analyzer
    return PhysicsDotsVisualizer(
      values: currentAnalyzerValues,
      primaryColor: primaryColor,
      height: height,
      themeName: spectrumStyle,
      showGrids: showGrids,
      logScale: logScale,
      autoFit: autoFit,
      maxFreq: maxFreq,
      onThemeChanged: onThemeChanged,
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
      setState(() {});
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
    final glslMatch = GlslShaderStyle.values.firstWhere(
      (s) =>
          s.name == _currentAnalyzerType ||
          s.displayName == _currentAnalyzerType ||
          s.displayName.toLowerCase() == _currentAnalyzerType.toLowerCase() ||
          s.name.toLowerCase() == _currentAnalyzerType.toLowerCase(),
      orElse: () => GlslShaderStyle.fromString(_currentAnalyzerType),
    );
    return glslMatch.displayName;
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
                child: Hero(
                  tag: 'spectrum_analyzer_hero',
                  child: Material(
                    color: Colors.transparent,
                    child: Container(
                      color: const Color(0xFF06080D),
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          return ValueListenableBuilder<List<double>>(
                            valueListenable: widget.analyzerValuesNotifier,
                            builder: (context, analyzerVals, _) {
                              return AudioVisualizerHost(
                                player: widget.player,
                                analyzerType: _currentAnalyzerType,
                                spectrumStyle: _currentSpectrumStyle,
                                primaryColor: primaryColor,
                                currentAnalyzerValues: analyzerVals,
                                peakValues: widget.peakValuesNotifier.value,
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
                          );
                        },
                      ),
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
                                  label: 'GLSL Hardware Shaders',
                                  entries: GlslShaderStyle.values.map((style) {
                                    final isSelected =
                                        _currentAnalyzerType == style.name ||
                                            _currentAnalyzerType ==
                                                style.displayName;
                                    return M3EMenuEntry(
                                      label: style.displayName,
                                      leading: Icon(
                                        Icons.auto_awesome_rounded,
                                        color: isSelected ? primaryColor : null,
                                        size: 16,
                                      ),
                                      onPressed: () =>
                                          _selectAnalyzerType(style.name),
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
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: 6,
                                    height: 6,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: _measuredFps >= 100
                                          ? const Color(0xFF00E676)
                                          : primaryColor,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    '${_measuredFps.round()} Hz • ${(widget.maxFreq / 1000).toStringAsFixed(1)}k Nyquist',
                                    style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: 0.3,
                                    ),
                                  ),
                                ],
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
