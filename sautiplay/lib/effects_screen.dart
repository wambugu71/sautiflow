import 'dart:async';
import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:sautiflow/sautiflow.dart';
import 'eq_screen.dart';
import 'isolate_player.dart';
import 'services/fft_processor.dart';
import 'viper_fx_screen.dart';

class EffectsScreen extends StatefulWidget {
  final IsolateAudioPlayer player;
  final bool analyzerEnabled;
  final String analyzerType;
  final bool analyzerAutoFit;
  final bool analyzerShowGrids;
  final bool analyzerLogScale;
  final int outputSampleRate;
  final String spectrumStyle;

  const EffectsScreen({
    super.key,
    required this.player,
    required this.analyzerEnabled,
    required this.analyzerType,
    required this.analyzerAutoFit,
    required this.analyzerShowGrids,
    this.analyzerLogScale = true,
    required this.outputSampleRate,
    this.spectrumStyle = 'neon',
  });

  @override
  State<EffectsScreen> createState() => _EffectsScreenState();
}

class _EffectsScreenState extends State<EffectsScreen> {
  List<double> _analyzerValues = [];
  List<double> _peakValues = [];
  StreamSubscription? _analyzerSub;
  FftProcessor? _fftProcessor;

  @override
  void initState() {
    super.initState();
    _setupAnalyzer(widget.analyzerEnabled);
  }

  @override
  void didUpdateWidget(covariant EffectsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.analyzerEnabled != widget.analyzerEnabled) {
      _setupAnalyzer(widget.analyzerEnabled);
    }
  }

  @override
  void dispose() {
    _analyzerSub?.cancel();
    super.dispose();
  }

  void _setupAnalyzer(bool enabled) {
    if (enabled) {
      final sr = widget.outputSampleRate > 0 ? widget.outputSampleRate : 48000;
      _fftProcessor ??= FftProcessor(sampleRate: sr);
      widget.player.setAnalyzerEnabled(true);
      _analyzerSub ??= widget.player.analyzerStream.listen((frame) {
        if (frame.isEmpty) return;
        const targetBins = 60;
        final bins = _fftProcessor!.processFrame(frame, targetBins: targetBins);
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

  Widget _buildVisualizer(Color primaryColor, List<double> currentAnalyzerValues, List<double> peakValues) {
    const int numBars = 60;
    final visualData = <double>[];
    final visualPeaks = <double>[];
    if (currentAnalyzerValues.isEmpty) {
      for (int i = 0; i < numBars; i++) {
        visualData.add(0.0);
        visualPeaks.add(0.0);
      }
    } else {
      final step = math.max(1, currentAnalyzerValues.length / numBars);
      for (int i = 0; i < numBars; i++) {
        final index = (i * step).floor().clamp(0, currentAnalyzerValues.length - 1);
        double val = currentAnalyzerValues[index];
        double peak = peakValues[index];
        if (!widget.analyzerLogScale) {
          val = val * val;
          peak = peak * peak;
        }
        visualData.add(val.clamp(0.0, 1.0));
        visualPeaks.add(peak.clamp(0.0, 1.0));
      }
    }

    final flGridData = FlGridData(
      show: widget.analyzerShowGrids,
      drawVerticalLine: true,
      horizontalInterval: 0.25,
      getDrawingHorizontalLine: (value) => FlLine(color: Colors.white10, strokeWidth: 1),
      getDrawingVerticalLine: (value) => FlLine(color: Colors.white10, strokeWidth: 1),
    );

    int maxFreq = widget.outputSampleRate == 0 ? 24000 : widget.outputSampleRate ~/ 2;
    if (maxFreq > 24000) maxFreq = 24000;

    double dynamicMaxY = 1.0;
    if (widget.analyzerAutoFit) {
      double maxPeak = 0.0;
      for (var p in visualPeaks) {
        if (p > maxPeak) maxPeak = p;
      }
      dynamicMaxY = math.max(0.1, maxPeak * 1.2); // Add headroom
      if (dynamicMaxY > 1.0 && !widget.analyzerLogScale) dynamicMaxY = 1.0;
    }

    final flTitlesData = FlTitlesData(
      show: true,
      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      leftTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 28,
          getTitlesWidget: (value, meta) {
            if (value == 0 || value >= dynamicMaxY) return const SizedBox.shrink();
            return Text(
              widget.analyzerLogScale ? '${(value * 100).toInt()} dB' : '${(value * 100).toInt()}%',
              style: const TextStyle(color: Colors.white54, fontSize: 9),
              textAlign: TextAlign.right,
            );
          },
        ),
      ),
      bottomTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 20,
          getTitlesWidget: (value, meta) {
            final int idx = value.toInt();
            // Display 6 evenly spaced logarithmic frequency ticks across 20Hz - 20kHz
            if (idx == 0 || idx == 10 || idx == 22 || idx == 34 || idx == 46 || idx == (numBars - 1)) {
              double freq = 20.0 * math.pow(maxFreq / 20.0, idx / (numBars - 1));
              String label;
              if (freq >= 1000) {
                final k = freq / 1000;
                label = k >= 10 ? '${k.round()}k' : '${k.toStringAsFixed(1)}k';
              } else {
                label = '${freq.round()}';
              }
              return Padding(
                padding: const EdgeInsets.only(top: 6.0),
                child: Text(
                  label,
                  style: const TextStyle(color: Colors.white54, fontSize: 9),
                ),
              );
            }
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    final flBorderData = FlBorderData(
      show: true,
      border: const Border(
        bottom: BorderSide(color: Colors.white24, width: 1),
        left: BorderSide(color: Colors.white24, width: 1),
        right: BorderSide.none,
        top: BorderSide.none,
      ),
    );

    if (widget.analyzerType == 'area') {
      final spots = <FlSpot>[];
      for (int i = 0; i < numBars; i++) {
        spots.add(FlSpot(i.toDouble(), visualData[i]));
      }
      return LineChart(
        LineChartData(
          lineTouchData: const LineTouchData(enabled: false),
          gridData: flGridData,
          titlesData: flTitlesData,
          borderData: flBorderData,
          minX: 0,
          maxX: numBars.toDouble() - 1,
          minY: 0,
          maxY: dynamicMaxY,
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              curveSmoothness: 0.35,
              color: primaryColor,
              barWidth: 2,
              isStrokeCapRound: true,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(
                show: true,
                gradient: LinearGradient(
                  colors: [
                    primaryColor.withOpacity(0.5),
                    primaryColor.withOpacity(0.0),
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
            ),
          ],
        ),
      );
    } else {
      final barGroups = List.generate(numBars, (i) {
        return BarChartGroupData(
          x: i,
          barRods: [
            BarChartRodData(
              toY: math.max(0.02, visualPeaks[i]),
              color: Colors.transparent,
              width: 4,
              rodStackItems: [
                BarChartRodStackItem(0, math.max(0.02, visualData[i]), primaryColor.withOpacity(0.8)),
                BarChartRodStackItem(math.max(0.0, visualPeaks[i] - 0.02), visualPeaks[i], Colors.white),
              ],
              borderRadius: BorderRadius.circular(2),
            ),
          ],
        );
      });
      return BarChart(
        BarChartData(
          barTouchData: BarTouchData(enabled: false),
          alignment: BarChartAlignment.spaceBetween,
          maxY: dynamicMaxY,
          minY: 0,
          barGroups: barGroups,
          titlesData: flTitlesData,
          borderData: flBorderData,
          gridData: flGridData,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    const primaryColor = Color(0xFF137fec);
    const bgColor = Color(0xFF101922);
    const headerColor = Color(0xFF111a22);

    // Calculate the dynamic expanded height based on what's visible
    final double analyzerChartHeight =
        (widget.analyzerEnabled && _analyzerValues.isNotEmpty) ? 176.0 : 0.0; // 160 + padding
    final double spectrumHeight = widget.analyzerEnabled ? 160.0 : 0.0; // 85 (spectrum) + 8 (gap) + 45 (RMS meter) + 22 (padding)
    const double titleBarHeight = 56.0;
    const double tabBarHeight = 48.0;
    final topPadding = MediaQuery.of(context).padding.top;
    final double expandedHeight =
        topPadding + titleBarHeight + analyzerChartHeight + spectrumHeight + tabBarHeight;
    final double collapsedHeight = topPadding + titleBarHeight + tabBarHeight;

    return DefaultTabController(
      length: 2,
      child: Scaffold(
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
                    final double expandableRange = expandedHeight - collapsedHeight;
                    final double scrollFraction = expandableRange > 0
                        ? ((currentHeight - collapsedHeight) / expandableRange).clamp(0.0, 1.0)
                        : 0.0;

                    return Column(
                      children: [
                        // Safe area top padding
                        SizedBox(height: topPadding),

                        // Title bar (always visible)
                        SizedBox(
                          height: titleBarHeight,
                          child: Row(
                            children: [
                              const BackButton(color: Colors.white),
                              const Expanded(
                                child: Text(
                                  'Audio Effects',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 48),
                            ],
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
                                      // FL Chart Realtime Analyzer
                                      if (widget.analyzerEnabled && _analyzerValues.isNotEmpty)
                                        Padding(
                                          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                                          child: SizedBox(
                                            height: 160,
                                            child: _buildVisualizer(primaryColor, _analyzerValues, _peakValues),
                                          ),
                                        ),

                                      // Spectrum Visualizer + RMS Meter
                                      if (widget.analyzerEnabled)
                                        Padding(
                                          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 6.0),
                                          child: Column(
                                            children: [
                                              SpectrumVisualizerWidget(
                                                analyzerStream: widget.player.analyzerStream,
                                                isPlaying: true,
                                                bandCount: 32,
                                                height: 85,
                                                style: SpectrumVisualStyle.values.firstWhere(
                                                  (s) => s.name == widget.spectrumStyle,
                                                  orElse: () => SpectrumVisualStyle.neon,
                                                ),
                                              ),
                                              const SizedBox(height: 8),
                                              RmsMeterWidget(
                                                analyzerStream: widget.player.analyzerStream,
                                                isPlaying: true,
                                              ),
                                            ],
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),

                        // TabBar (always pinned at bottom of header)
                        const TabBar(
                          indicatorColor: primaryColor,
                          labelColor: Colors.white,
                          unselectedLabelColor: Colors.white54,
                          tabs: [
                            Tab(text: 'Equalizer'),
                            Tab(text: 'ViPER FX'),
                          ],
                        ),
                      ],
                    );
                  },
                ),
              ),
            ];
          },
          body: TabBarView(
            children: [
              EqScreen(
                player: widget.player,
                analyzerEnabled: widget.analyzerEnabled,
                analyzerType: widget.analyzerType,
              ),
              ViperFxScreen(player: widget.player),
            ],
          ),
        ),
      ),
    );
  }
}
