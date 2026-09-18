import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:sautiflow/sautiflow.dart';
import 'eq_screen.dart';
import 'isolate_player.dart';
import 'models/audio_profile.dart';
import 'services/app_theme_service.dart';
import 'services/audio_hardware_inspector.dart';
import 'services/audio_profile_service.dart';
import 'services/fft_processor.dart';
import 'widgets/fluid_area_visualizer.dart';
import 'widgets/glsl_audio_visualizer.dart';
import 'widgets/physics_dots_visualizer.dart';
import 'widgets/autoeq_selector_widget.dart';
import 'widgets/profile_selector.dart';
import 'widgets/stereo_vectorscope_graph.dart';

class EffectsScreen extends StatefulWidget {
  final IsolateAudioPlayer player;
  final bool analyzerEnabled;
  final String analyzerType;
  final bool analyzerAutoFit;
  final bool analyzerShowGrids;
  final bool analyzerLogScale;
  final int outputSampleRate;
  final String spectrumStyle;
  final GlobalKey? effectsKnobKey;
  final bool isActive;

  const EffectsScreen({
    super.key,
    required this.player,
    required this.analyzerEnabled,
    this.analyzerType = 'bar',
    required this.analyzerAutoFit,
    required this.analyzerShowGrids,
    this.analyzerLogScale = true,
    required this.outputSampleRate,
    this.spectrumStyle = 'minimal',
    this.effectsKnobKey,
    this.isActive = true,
  });

  @override
  State<EffectsScreen> createState() => _EffectsScreenState();
}

class _EffectsScreenState extends State<EffectsScreen> {
  List<double> _analyzerValues = [];
  List<double> _peakValues = [];
  StreamSubscription? _analyzerSub;
  StreamSubscription<PlayerStatus>? _statusSub;
  StreamSubscription<AudioHardwareSpecs>? _hardwareSub;
  StreamSubscription<AudioProfile?>? _profileSub;
  AudioHardwareSpecs? _hardwareSpecs;
  List<AudioProfile> _audioProfiles = [];
  AudioProfile? _selectedAudioProfile;
  bool _isPlaying = false;
  FftProcessor? _fftProcessor;
  late String _currentAnalyzerType;
  late String _currentSpectrumStyle;

  /// Effective sample rate currently used by audio engine & DAC hardware.
  int get _currentlyUsedSampleRate {
    if (widget.outputSampleRate > 0) {
      return widget.outputSampleRate;
    }
    final hwRate = _hardwareSpecs?.sampleRate ??
        AudioHardwareInspector.currentSpecs?.sampleRate;
    if (hwRate != null && hwRate > 0) {
      return hwRate;
    }
    return 48000;
  }

  /// True Nyquist upper boundary (f_s / 2) for the currently used sample rate.
  int get _currentMaxFreq => _currentlyUsedSampleRate ~/ 2;

  String _formatRateString(int rateHz) {
    if (rateHz <= 0) return '48 kHz';
    final double kHz = rateHz / 1000.0;
    return rateHz % 1000 == 0
        ? '${rateHz ~/ 1000} kHz'
        : '${kHz.toStringAsFixed(1)} kHz';
  }

  @override
  void initState() {
    super.initState();
    _currentAnalyzerType = widget.analyzerType;
    _currentSpectrumStyle = widget.spectrumStyle;
    _isPlaying = widget.player.isPlaying;

    _hardwareSpecs = AudioHardwareInspector.currentSpecs;
    AudioHardwareInspector.inspectAsync(widget.player).then((specs) {
      if (mounted) {
        setState(() {
          _hardwareSpecs = specs;
          _updateAnalyzerConfig();
        });
      }
    });
    _hardwareSub =
        AudioHardwareInspector.hardwareStream(widget.player).listen((specs) {
      if (mounted) {
        setState(() {
          _hardwareSpecs = specs;
          _updateAnalyzerConfig();
        });
      }
    });

    _loadAudioProfiles();
    _profileSub = AudioProfileService.instance.activeProfileStream.listen((p) {
      if (mounted) setState(() => _selectedAudioProfile = p);
    });

    _setupAnalyzer(widget.isActive && widget.analyzerEnabled);
    _statusSub = widget.player.statusStream.listen((status) {
      if (mounted && _isPlaying != status.isPlaying) {
        setState(() {
          _isPlaying = status.isPlaying;
        });
      }
    });
  }

  Future<void> _loadAudioProfiles() async {
    final profiles = await AudioProfileService.instance.getProfiles();
    final active = await AudioProfileService.instance.getActiveProfile();
    if (mounted) {
      setState(() {
        _audioProfiles = profiles;
        _selectedAudioProfile = active;
      });
    }
  }

  String get _visualizerLabel {
    if (_currentAnalyzerType == 'vectorscope' ||
        _currentAnalyzerType == 'Stereo Vectorscope') {
      return 'Vectorscope';
    } else if (_currentAnalyzerType == 'area') {
      return 'Wave Area';
    } else if (_currentAnalyzerType == 'bar') {
      return 'Dot Matrix';
    }
    final glslMatch = GlslShaderStyle.values.firstWhere(
      (s) =>
          s.name == _currentAnalyzerType ||
          s.displayName == _currentAnalyzerType,
      orElse: () => GlslShaderStyle.cyberTunnel,
    );
    return glslMatch.displayName;
  }

  void _showProfileMenu(BuildContext btnContext) async {
    final renderBox = btnContext.findRenderObject() as RenderBox?;
    if (renderBox == null) return;
    final offset = renderBox.localToGlobal(Offset.zero);
    final size = renderBox.size;
    final position = RelativeRect.fromLTRB(
      offset.dx,
      offset.dy + size.height + 6,
      offset.dx + size.width,
      offset.dy + size.height + 6,
    );

    final selected = await showMenu<AudioProfile>(
      context: context,
      position: position,
      color: const Color(0xFF101924),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xFF1E2D40)),
      ),
      items: _audioProfiles.map((p) {
        final isSelected = p.id == _selectedAudioProfile?.id;
        return PopupMenuItem<AudioProfile>(
          value: p,
          height: 38,
          child: Row(
            children: [
              Icon(
                Icons.bar_chart_rounded,
                size: 16,
                color: isSelected ? const Color(0xFF38BDF8) : Colors.white54,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  p.name,
                  style: TextStyle(
                    color: isSelected ? const Color(0xFF38BDF8) : Colors.white,
                    fontWeight:
                        isSelected ? FontWeight.bold : FontWeight.normal,
                    fontSize: 13,
                  ),
                ),
              ),
              if (isSelected)
                const Icon(Icons.check_rounded,
                    size: 16, color: Color(0xFF38BDF8)),
            ],
          ),
        );
      }).toList(),
    );

    if (selected != null) {
      setState(() => _selectedAudioProfile = selected);
      await AudioProfileService.instance.applyProfile(widget.player, selected);
    }
  }

  @override
  void didUpdateWidget(covariant EffectsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.analyzerType != widget.analyzerType) {
      _currentAnalyzerType = widget.analyzerType;
    }
    if (oldWidget.spectrumStyle != widget.spectrumStyle) {
      _currentSpectrumStyle = widget.spectrumStyle;
    }
    if (oldWidget.outputSampleRate != widget.outputSampleRate ||
        oldWidget.analyzerLogScale != widget.analyzerLogScale) {
      _updateAnalyzerConfig();
    }
    if (oldWidget.analyzerEnabled != widget.analyzerEnabled ||
        oldWidget.isActive != widget.isActive) {
      _setupAnalyzer(widget.isActive && widget.analyzerEnabled);
    }
  }

  void _updateAnalyzerConfig() {
    _fftProcessor?.setSampleRate(_currentlyUsedSampleRate);
    _fftProcessor?.setLogScale(widget.analyzerLogScale);
  }

  @override
  void dispose() {
    _analyzerSub?.cancel();
    _statusSub?.cancel();
    _hardwareSub?.cancel();
    _profileSub?.cancel();
    super.dispose();
  }

  void _setupAnalyzer(bool enabled) {
    if (enabled) {
      final sr = _currentlyUsedSampleRate;
      _fftProcessor ??= FftProcessor(
        sampleRate: sr,
        logScale: widget.analyzerLogScale,
      );
      _fftProcessor!.setSampleRate(sr);
      _fftProcessor!.setLogScale(widget.analyzerLogScale);
      widget.player.setAnalyzerEnabled(true);
      _analyzerSub ??= widget.player.analyzerStream.listen((frame) {
        if (frame.isEmpty) return;
        if (!_isPlaying) {
          _isPlaying = true;
        }
        const targetBins = 60;
        final bins = _fftProcessor!.processFrame(
          frame,
          targetBins: targetBins,
          logScale: widget.analyzerLogScale,
        );
        if (mounted) {
          setState(() {
            _analyzerValues = bins;
            if (_peakValues.length != targetBins) {
              _peakValues = List<double>.filled(targetBins, 0.0);
            }
            for (int i = 0; i < targetBins; i++) {
              if (bins[i] > _peakValues[i]) {
                _peakValues[i] = bins[i];
              } else {
                _peakValues[i] = math.max(0.0, _peakValues[i] - 0.02);
              }
            }
          });
        }
      });
    } else {
      _analyzerSub?.cancel();
      _analyzerSub = null;
      _fftProcessor?.reset();
      if (mounted) {
        setState(() {
          _analyzerValues = [];
          _peakValues = [];
        });
      }
    }
  }

  Widget _buildVisualizer(Color primaryColor,
      List<double> currentAnalyzerValues, List<double> peakValues) {
    final int maxFreq = _currentMaxFreq;

    if (_currentAnalyzerType == 'vectorscope' ||
        _currentAnalyzerType == 'Stereo Vectorscope') {
      return RepaintBoundary(
        child: StereoVectorscopeGraph(
          width: 1.5,
          isEnabled: true,
          height: 160.0,
          primaryColor: primaryColor,
          analyzerStream: widget.player.analyzerStream,
        ),
      );
    }

    for (final style in GlslShaderStyle.values) {
      if (_currentAnalyzerType == style.name ||
          _currentAnalyzerType == style.displayName) {
        return GlslAudioVisualizerWidget(
          analyzerStream: widget.player.analyzerStream,
          isPlaying: _isPlaying,
          style: style,
          primaryColor: primaryColor,
          height: 160.0,
        );
      }
    }

    if (_currentAnalyzerType == 'area') {
      return FluidAreaVisualizer(
        values: currentAnalyzerValues,
        primaryColor: primaryColor,
        height: 160.0,
        themeName: _currentSpectrumStyle,
        showGrids: widget.analyzerShowGrids,
        logScale: widget.analyzerLogScale,
        autoFit: widget.analyzerAutoFit,
        maxFreq: maxFreq,
        onThemeChanged: (newTheme) {
          setState(() {
            _currentSpectrumStyle = newTheme;
          });
        },
      );
    } else {
      return PhysicsDotsVisualizer(
        values: currentAnalyzerValues,
        primaryColor: primaryColor,
        height: 160.0,
        themeName: _currentSpectrumStyle,
        showGrids: widget.analyzerShowGrids,
        logScale: widget.analyzerLogScale,
        autoFit: widget.analyzerAutoFit,
        maxFreq: maxFreq,
        onThemeChanged: (newTheme) {
          setState(() {
            _currentSpectrumStyle = newTheme;
          });
        },
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = context.primaryColor;
    final bgColor = context.bgDark;
    final headerColor = bgColor;

    // Calculate the dynamic expanded height based on what's visible
    final double analyzerChartHeight =
        (widget.analyzerEnabled && _analyzerValues.isNotEmpty)
            ? 194.0
            : 0.0; // 160 + 18 (specs) + 16 (padding)
    final double spectrumHeight = widget.analyzerEnabled
        ? 160.0
        : 0.0; // 85 (spectrum) + 8 (gap) + 45 (RMS meter) + 22 (padding)
    const double controlBarHeight = 98.0;
    const double titleBarHeight = 50.0;
    const double dragHandleHeight = 10.0;
    final topPadding = MediaQuery.of(context).padding.top;
    final double expandedHeight = topPadding +
        titleBarHeight +
        controlBarHeight +
        analyzerChartHeight +
        spectrumHeight +
        dragHandleHeight;
    final double collapsedHeight =
        topPadding + titleBarHeight + controlBarHeight + dragHandleHeight;

    return Scaffold(
      backgroundColor: bgColor,
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) {
          return [
            SliverAppBar(
              backgroundColor: headerColor,
              pinned: true,
              floating: false,
              snap: false,
              expandedHeight: expandedHeight,
              collapsedHeight: collapsedHeight,
              toolbarHeight: 0, // We handle our own title in flexibleSpace
              automaticallyImplyLeading: false,
              flexibleSpace: LayoutBuilder(
                builder: (context, constraints) {
                  // How much space is available beyond the collapsed state
                  final double currentHeight = constraints.maxHeight;
                  final double expandableRange =
                      expandedHeight - collapsedHeight;
                  final double scrollFraction = expandableRange > 0
                      ? ((currentHeight - collapsedHeight) / expandableRange)
                          .clamp(0.0, 1.0)
                      : 0.0;

                  return Column(
                    children: [
                      // Safe area top padding
                      SizedBox(height: topPadding),

                      // Title Bar (Always visible)
                      SizedBox(
                        height: titleBarHeight,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12.0),
                          child: Row(
                            children: [
                              if (Navigator.canPop(context))
                                const BackButton(color: Colors.white),
                              Icon(Icons.tune_rounded,
                                  color: primaryColor, size: 22),
                              const SizedBox(width: 8),
                              const Text(
                                'Audio Effects & DSP',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 17,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const Spacer(),
                              // Quick toggle analyzer visualizer
                              IconButton(
                                icon: Icon(
                                  widget.analyzerEnabled
                                      ? Icons.equalizer
                                      : Icons.equalizer_outlined,
                                  color: widget.analyzerEnabled
                                      ? primaryColor
                                      : Colors.white38,
                                  size: 22,
                                ),
                                tooltip: widget.analyzerEnabled
                                    ? 'Analyzer Active'
                                    : 'Analyzer Off',
                                onPressed: () {
                                  _setupAnalyzer(!widget.analyzerEnabled);
                                },
                              ),
                            ],
                          ),
                        ),
                      ),

                      // Control Bar (Matching screenshot UI)
                      SizedBox(
                        height: controlBarHeight,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12.0, vertical: 2.0),
                          child: Column(
                            children: [
                              // Row 1: Visualizer pill + Profile pill + Spacer + Save + Tune
                              Row(
                                children: [

                                  // Visualizer Selector Pill Menu
                                  M3EMenu(
                                    anchorBuilder: (context, open) => InkWell(
                                      onTap: open,
                                      borderRadius: BorderRadius.circular(10),
                                      child: Container(
                                        decoration: BoxDecoration(
                                          borderRadius:
                                              BorderRadius.circular(10),
                                          color: const Color(0xFF101924),
                                        ),
                                        height: 36,
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 10),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Icon(
                                              Icons.grid_view_rounded,
                                              color: Color(0xFF38BDF8),
                                              size: 16,
                                            ),
                                            const SizedBox(width: 6),
                                            Text(
                                              _visualizerLabel,
                                              style: const TextStyle(
                                                color: Color(0xFF38BDF8),
                                                fontSize: 13,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                            const SizedBox(width: 4),
                                            const Icon(
                                              Icons.keyboard_arrow_down_rounded,
                                              color: Color(0xFF38BDF8),
                                              size: 18,
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                    children: [
                                      M3EMenuGroup.entries(
                                        label: 'Standard Visualizers',
                                        entries: [
                                          M3EMenuEntry(
                                            label: 'Stereo Vectorscope',
                                            leading: const Icon(
                                                Icons.radar_rounded,
                                                size: 18),
                                            onPressed: () {
                                              setState(() {
                                                _currentAnalyzerType =
                                                    'vectorscope';
                                              });
                                            },
                                          ),
                                          M3EMenuEntry(
                                            label: 'Wave Area',
                                            leading: const Icon(
                                                Icons.show_chart_rounded,
                                                size: 18),
                                            onPressed: () {
                                              setState(() {
                                                _currentAnalyzerType = 'area';
                                              });
                                            },
                                          ),
                                          M3EMenuEntry(
                                            label: 'Matrix Spectrum',
                                            leading: const Icon(
                                                Icons.grain_rounded,
                                                size: 18),
                                            onPressed: () {
                                              setState(() {
                                                _currentAnalyzerType = 'bar';
                                              });
                                            },
                                          ),
                                        ],
                                      ),
                                      M3EMenuGroup.entries(
                                        label: _currentAnalyzerType == 'area'
                                            ? 'Wave Themes'
                                            : 'Matrix Themes',
                                        entries: (_currentAnalyzerType == 'area'
                                                ? FluidAreaTheme.values.map(
                                                    (theme) => M3EMenuEntry(
                                                      label: theme.displayName,
                                                      leading: Icon(
                                                        theme.icon,
                                                        size: 18,
                                                        color:
                                                            _currentSpectrumStyle ==
                                                                    theme.name
                                                                ? primaryColor
                                                                : null,
                                                      ),
                                                      onPressed: () {
                                                        setState(() {
                                                          _currentSpectrumStyle =
                                                              theme.name;
                                                        });
                                                      },
                                                    ),
                                                  )
                                                : PhysicsDotsTheme.values.map(
                                                    (theme) => M3EMenuEntry(
                                                      label: theme.displayName,
                                                      leading: Icon(
                                                        theme.icon,
                                                        size: 18,
                                                        color:
                                                            _currentSpectrumStyle ==
                                                                    theme.name
                                                                ? primaryColor
                                                                : null,
                                                      ),
                                                      onPressed: () {
                                                        setState(() {
                                                          _currentSpectrumStyle =
                                                              theme.name;
                                                        });
                                                      },
                                                    ),
                                                  ))
                                            .toList(),
                                      ),
                                      M3EMenuGroup.entries(
                                        label: 'GLSL Shaders',
                                        entries: GlslShaderStyle.values
                                            .map(
                                              (s) => M3EMenuEntry(
                                                label: s.displayName,
                                                leading: const Icon(
                                                    Icons.auto_awesome,
                                                    size: 18),
                                                onPressed: () {
                                                  setState(() {
                                                    _currentAnalyzerType =
                                                        s.name;
                                                  });
                                                },
                                              ),
                                            )
                                            .toList(),
                                      ),
                                    ],
                                  ),

                                  const SizedBox(width: 8),

                                  // Audio Profile Selector Pill
                                  Builder(
                                    builder: (btnCtx) {
                                      return InkWell(
                                        onTap: () => _showProfileMenu(btnCtx),
                                        borderRadius: BorderRadius.circular(10),
                                        child: Container(
                                          decoration: BoxDecoration(
                                            borderRadius:
                                                BorderRadius.circular(10),
                                            color: const Color(0xFF101924),
                                          ),
                                          height: 36,
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 10),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              const Icon(
                                                Icons.bar_chart_rounded,
                                                color: Color(0xFF38BDF8),
                                                size: 16,
                                              ),
                                              const SizedBox(width: 6),
                                              ConstrainedBox(
                                                constraints:
                                                    const BoxConstraints(
                                                        maxWidth: 85),
                                                child: Text(
                                                  _selectedAudioProfile?.name ??
                                                      'Flat',
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: const TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 13,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 4),
                                              const Icon(
                                                Icons.keyboard_arrow_down_rounded,
                                                color: Colors.white70,
                                                size: 18,
                                              ),
                                            ],
                                          ),
                                        ),
                                      );
                                    },
                                  ),

                                  const Spacer(),

                                  // Save Audio Profile Button
                                  InkWell(
                                    onTap: () {
                                      AudioProfileSelector.showSaveDialog(
                                        context: context,
                                        player: widget.player,
                                        onProfileSaved: _loadAudioProfiles,
                                      );
                                    },
                                    borderRadius: BorderRadius.circular(8),
                                    child: Container(
                                      width: 34,
                                      height: 34,
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF162232),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: const Icon(
                                        Icons.save_outlined,
                                        color: Colors.white70,
                                        size: 17,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 6),

                                  // Manage Audio Profiles (Tune) Button
                                  InkWell(
                                    onTap: () {
                                      showDialog(
                                        context: context,
                                        builder: (dialogCtx) =>
                                            AudioProfileManagerDialog(
                                          player: widget.player,
                                          onProfilesUpdated:
                                              _loadAudioProfiles,
                                        ),
                                      );
                                    },
                                    borderRadius: BorderRadius.circular(8),
                                    child: Container(
                                      width: 34,
                                      height: 34,
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF162232),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: const Icon(
                                        Icons.tune_rounded,
                                        color: Colors.white70,
                                        size: 17,
                                      ),
                                    ),
                                  ),
                                ],
                              ),

                              const SizedBox(height: 8),

                              // Row 2: AutoEQ Selector Widget
                              Row(
                                children: [
                                  Expanded(
                                    child: AutoEqSelectorWidget(
                                      player: widget.player,
                                      isCompact: true,
                                      onProfileApplied: () {
                                        setState(() {});
                                      },
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),

                      // Collapsible analyzer section
                      if (expandableRange > 0)
                        Expanded(
                          child: ClipRect(
                            child: Opacity(
                              opacity: scrollFraction,
                              child: SingleChildScrollView(
                                physics: const NeverScrollableScrollPhysics(),
                                child: Column(
                                  children: [
                                    // Realtime Visualizer (BarChart / LineChart / GLSL Shaders)
                                    if (widget.analyzerEnabled)
                                      Padding(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 16.0, vertical: 8.0),
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            SizedBox(
                                              height: 160,
                                              child: _buildVisualizer(
                                                  primaryColor,
                                                  _analyzerValues,
                                                  _peakValues),
                                            ),
                                          ],
                                        ),
                                      ),

                                    // RMS Loudness Meter Slider
                                    if (widget.analyzerEnabled)
                                      Padding(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 16.0, vertical: 6.0),
                                        child: RmsMeterWidget(
                                          analyzerStream:
                                              widget.player.analyzerStream,
                                          isPlaying: _isPlaying,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),

                      // Drag Handle Affordance (Pill indicator for sliver expansion/collapse)
                      Padding(
                        padding: const EdgeInsets.only(top: 4, bottom: 2),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 36,
                              height: 4,
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.35),
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ];
        },
        body: EqScreen(
          effectsKnobKey: widget.effectsKnobKey,
          player: widget.player,
          analyzerEnabled: widget.analyzerEnabled,
          analyzerType: widget.analyzerType,
        ),
      ),
    );
  }
}
