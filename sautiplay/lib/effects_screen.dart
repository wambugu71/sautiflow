import 'dart:async';
import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'isolate_player.dart';
import 'viper_fx_screen.dart';
import 'eq_screen.dart';

class EffectsScreen extends StatefulWidget {
  final IsolateAudioPlayer player;
  final bool analyzerEnabled;
  final String analyzerType;
  final bool analyzerAutoFit;
  final bool analyzerShowGrids;
  final int outputSampleRate;

  const EffectsScreen({
    super.key,
    required this.player,
    required this.analyzerEnabled,
    required this.analyzerType,
    required this.analyzerAutoFit,
    required this.analyzerShowGrids,
    required this.outputSampleRate,
  });

  @override
  State<EffectsScreen> createState() => _EffectsScreenState();
}

class _EffectsScreenState extends State<EffectsScreen> {
  List<double> _analyzerValues = [];
  List<double> _peakValues = [];
  bool _isLogScale = true;
  StreamSubscription? _analyzerSub;

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
      widget.player.setAnalyzerEnabled(true);
      _analyzerSub ??= widget.player.analyzerStream.listen((frame) {
        if (frame.isEmpty) return;
        const targetBins = 96;
        final bins = List<double>.filled(targetBins, 0.0);
        final srcLen = frame.length;
        for (var i = 0; i < targetBins; i++) {
          final from = (i * srcLen / targetBins).floor();
          final to = ((i + 1) * srcLen / targetBins).ceil();
          var sum = 0.0;
          var count = 0;
          for (var j = from; j < to && j < srcLen; j++) {
            sum += frame[j].abs();
            count++;
          }
          bins[i] = count > 0 ? sum / count : 0.0;
        }
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
                _peakValues[i] = math.max(0.0, _peakValues[i] - 0.015);
              }
            }
          });
        }
      });
    } else {
      _analyzerSub?.cancel();
      _analyzerSub = null;
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
        if (_isLogScale) {
          val = math.log(val * 100 + 1) / math.log(101);
          peak = math.log(peak * 100 + 1) / math.log(101);
        } else {
          val = val * 8.0;
          peak = peak * 8.0;
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
      if (dynamicMaxY > 1.0 && !_isLogScale) dynamicMaxY = 1.0;
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
              _isLogScale ? '${(value * 100).toInt()} ds' : '${(value * 100).toInt()}%',
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
            if (value % 10 != 0 || value == 0) return const SizedBox.shrink();
            double freq = 20.0 + (value / (numBars - 1)) * (maxFreq - 20.0);
            String label;
            if (freq >= 1000) {
              label = '${(freq / 1000).toStringAsFixed(1)}k';
            } else {
              label = '${freq.toInt()}';
            }
            return Padding(
              padding: const EdgeInsets.only(top: 6.0),
              child: Text(
                label,
                style: const TextStyle(color: Colors.white54, fontSize: 9),
              ),
            );
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
    
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: const Color(0xFF101922),
        body: Column(
          children: [
            Container(
              color: const Color(0xFF111a22).withOpacity(0.95),
              child: SafeArea(
                bottom: false,
                child: Column(
                  children: [
                    SizedBox(
                      height: 56,
                      child: Row(
                        children: [
                          const BackButton(color: Colors.white),
                          const Expanded(
                            child: Text('Audio Effects', 
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                          ),
                          const SizedBox(width: 48),
                        ],
                      ),
                    ),
                    if (widget.analyzerEnabled && _analyzerValues.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                        child: Column(
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                const Text('Log Scale', style: TextStyle(color: Colors.white70, fontSize: 12)),
                                Switch(
                                  value: _isLogScale,
                                  onChanged: (v) => setState(() => _isLogScale = v),
                                  activeColor: primaryColor,
                                ),
                              ],
                            ),
                            SizedBox(
                              height: 160,
                              child: _buildVisualizer(primaryColor, _analyzerValues, _peakValues),
                            ),
                          ],
                        ),
                      ),
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
                ),
              ),
            ),
            Expanded(
              child: TabBarView(
                children: [
                  EqScreen(player: widget.player, analyzerEnabled: widget.analyzerEnabled, analyzerType: widget.analyzerType),
                  ViperFxScreen(player: widget.player),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
