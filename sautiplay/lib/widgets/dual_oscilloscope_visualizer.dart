import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import '../isolate_player.dart';

/// Display layout mode for the dual-channel oscilloscope.
enum OscilloscopeMode {
  /// Both channels overlaid on the center baseline with distinct beam colors.
  dualOverlay('Dual Overlay', Icons.layers_rounded),

  /// Split screen: CH1 on upper half, CH2 on lower half.
  splitTrace('Split Dual', Icons.splitscreen_rounded),

  /// X-Y Lissajous vectorscope mode (CH1 = X, CH2 = Y).
  xyLissajous('X-Y Phase', Icons.all_inclusive_rounded),

  /// CH1 (Left) solo trace.
  ch1Solo('CH1 (Left)', Icons.looks_one_rounded),

  /// CH2 (Right) solo trace.
  ch2Solo('CH2 (Right)', Icons.looks_two_rounded);

  final String displayName;
  final IconData icon;
  const OscilloscopeMode(this.displayName, this.icon);
}

/// Trigger synchronization mode for steady, rock-solid waveform locking.
enum OscilloscopeTriggerMode {
  /// Automatically finds rising zero-crossing; free-runs if no signal.
  autoRising('Auto ↑', Icons.trending_up_rounded),

  /// Automatically finds falling zero-crossing; free-runs if no signal.
  autoFalling('Auto ↓', Icons.trending_down_rounded),

  /// Strict edge triggering.
  normal('Norm ↑', Icons.lock_clock_rounded),

  /// Continuous scrolling free-run (no trigger sync).
  freeRun('Free', Icons.sync_disabled_rounded);

  final String label;
  final IconData icon;
  const OscilloscopeTriggerMode(this.label, this.icon);
}

/// A high-performance, 60-120 Hz hardware-accelerated dual-channel oscilloscope
/// visualizer for real-time time-domain audio analysis.
///
/// Features:
/// - True dual-channel (Left/CH1 & Right/CH2) waveform rendering at 60-120 FPS.
/// - Edge-trigger zero-crossing stabilization to eliminate waveform jitter.
/// - Dual Overlay, Stacked Split-Trace, and X-Y Lissajous phase orbital modes.
/// - Calibrated DSO reticle graticule with center crosshairs and division marks.
/// - Analog phosphor beam bloom and decaying persistence ghost trails.
/// - Real-time telemetry: 60-120 Hz FPS counter, $V_{pp}$, RMS, frequency counter,
///   and stereo phase correlation.
class DualOscilloscopeVisualizer extends StatefulWidget {
  final IsolateAudioPlayer? player;
  final Stream<Float32List>? stereoStream;
  final Stream<Float32List>? analyzerStream;
  final bool isPlaying;
  final Color primaryColor;
  final double height;
  final OscilloscopeMode initialMode;
  final bool showControls;

  const DualOscilloscopeVisualizer({
    super.key,
    this.player,
    this.stereoStream,
    this.analyzerStream,
    this.isPlaying = true,
    required this.primaryColor,
    this.height = 180.0,
    this.initialMode = OscilloscopeMode.dualOverlay,
    this.showControls = true,
  });

  @override
  State<DualOscilloscopeVisualizer> createState() =>
      _DualOscilloscopeVisualizerState();
}

class _DualOscilloscopeVisualizerState extends State<DualOscilloscopeVisualizer>
    with SingleTickerProviderStateMixin {
  // Circular ring buffer capacity (holds ~85ms of audio at 48kHz)
  static const int _ringCapacity = 4096;

  final Float32List _ch1Ring = Float32List(_ringCapacity);
  final Float32List _ch2Ring = Float32List(_ringCapacity);
  int _ringWriteIndex = 0;
  int _samplesCount = 0;

  StreamSubscription<Float32List>? _stereoSub;
  StreamSubscription<Float32List>? _monoSub;
  late final Ticker _ticker;

  // Active configurations
  late OscilloscopeMode _mode;
  OscilloscopeTriggerMode _triggerMode = OscilloscopeTriggerMode.autoRising;
  double _timeZoom = 1.0; // 0.5x to 4.0x
  double _voltsGain = 1.0; // 0.5x to 3.0x
  bool _glowPersistence = true;
  bool _showHud = true;

  // Real-time measurements
  double _measuredFps = 60.0;
  int _frameCount = 0;
  DateTime _fpsLastTime = DateTime.now();
  double _ch1Vpp = 0.0;
  double _ch2Vpp = 0.0;
  double _ch1RmsDb = -100.0;
  double _ch2RmsDb = -100.0;
  double _detectedFreqHz = 0.0;
  double _stereoCorrelation = 1.0;

  // Phosphor history buffers (for analog persistence trails)
  final List<List<Offset>> _ch1Persistence = [];
  final List<List<Offset>> _ch2Persistence = [];
  final List<List<Offset>> _xyPersistence = [];
  static const int _maxPersistenceFrames = 3;

  @override
  void initState() {
    super.initState();
    _mode = widget.initialMode;

    // Request high-rate 120Hz polling interval from player isolate
    widget.player?.setAnalyzerPollInterval(const Duration(milliseconds: 8));

    _subscribeAudioStreams();

    // Start 60-120Hz vsync-driven animation ticker
    _ticker = createTicker(_onTick)..start();
  }

  @override
  void didUpdateWidget(covariant DualOscilloscopeVisualizer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.stereoStream != widget.stereoStream ||
        oldWidget.analyzerStream != widget.analyzerStream) {
      _subscribeAudioStreams();
    }
  }

  void _subscribeAudioStreams() {
    _stereoSub?.cancel();
    _monoSub?.cancel();
    _stereoSub = null;
    _monoSub = null;

    if (widget.stereoStream != null) {
      _stereoSub = widget.stereoStream!.listen(_onStereoFrame);
    }

    if (widget.analyzerStream != null) {
      _monoSub = widget.analyzerStream!.listen(_onMonoFallbackFrame);
    }
  }

  void _onStereoFrame(Float32List interleaved) {
    if (interleaved.isEmpty) return;
    final pairs = interleaved.length ~/ 2;
    for (int i = 0; i < pairs; i++) {
      final l = interleaved[i * 2];
      final r = interleaved[i * 2 + 1];
      _ch1Ring[_ringWriteIndex] = l;
      _ch2Ring[_ringWriteIndex] = r;
      _ringWriteIndex = (_ringWriteIndex + 1) % _ringCapacity;
    }
    _samplesCount = math.min(_ringCapacity, _samplesCount + pairs);
  }

  void _onMonoFallbackFrame(Float32List mono) {
    // Only use mono if no stereo stream data has been received recently
    if (_stereoSub != null) return;
    if (mono.isEmpty) return;
    for (int i = 0; i < mono.length; i++) {
      final s = mono[i];
      _ch1Ring[_ringWriteIndex] = s;
      // Synthesize subtle phase shift for CH2 if strictly mono
      final prevIdx = (_ringWriteIndex - 4 + _ringCapacity) % _ringCapacity;
      _ch2Ring[_ringWriteIndex] = _ch1Ring[prevIdx] * 0.95;
      _ringWriteIndex = (_ringWriteIndex + 1) % _ringCapacity;
    }
    _samplesCount = math.min(_ringCapacity, _samplesCount + mono.length);
  }

  void _onTick(Duration elapsed) {
    if (!mounted) return;

    // High-precision FPS calculation
    _frameCount++;
    final now = DateTime.now();
    final elapsedMs = now.difference(_fpsLastTime).inMilliseconds;
    if (elapsedMs >= 500) {
      _measuredFps = (_frameCount * 1000.0) / elapsedMs;
      _frameCount = 0;
      _fpsLastTime = now;
    }

    // Force frame repaint on every vsync tick
    setState(() {});
  }

  @override
  void dispose() {
    _ticker.dispose();
    _stereoSub?.cancel();
    _monoSub?.cancel();
    // Restore default ~30Hz polling interval to conserve CPU when not viewing scope
    widget.player?.setAnalyzerPollInterval(const Duration(milliseconds: 33));
    super.dispose();
  }

  /// Calculates trigger point, extracts display samples, and computes telemetry.
  _ScopeRenderData _computeScopeData(Size size) {
    if (_samplesCount < 64 || !widget.isPlaying) {
      return _ScopeRenderData.empty();
    }

    // Determine window size based on timebase zoom (standard 10ms ~ 480 samples)
    final baseWindow = 512;
    final int windowSize =
        (baseWindow / _timeZoom).round().clamp(64, _ringCapacity ~/ 2);

    // 1. Edge-Trigger Synchronization on CH1
    int triggerOffset = 0;
    if (_triggerMode != OscilloscopeTriggerMode.freeRun) {
      const searchRange = 256;
      final start =
          (_ringWriteIndex - windowSize - searchRange + _ringCapacity) %
              _ringCapacity;

      int bestZeroCross = -1;
      int secondZeroCross = -1;
      const hysteresis = 0.012;

      for (int i = 1; i < searchRange; i++) {
        final idxPrev = (start + i - 1) % _ringCapacity;
        final idxCurr = (start + i) % _ringCapacity;
        final p = _ch1Ring[idxPrev];
        final c = _ch1Ring[idxCurr];

        final isRising = _triggerMode == OscilloscopeTriggerMode.autoRising ||
            _triggerMode == OscilloscopeTriggerMode.normal;

        final isCross = isRising
            ? (p <= 0.0 && c > hysteresis)
            : (p >= 0.0 && c < -hysteresis);

        if (isCross) {
          if (bestZeroCross == -1) {
            bestZeroCross = i;
          } else if (secondZeroCross == -1 && (i - bestZeroCross) > 12) {
            secondZeroCross = i;
            break;
          }
        }
      }

      if (bestZeroCross != -1) {
        triggerOffset = (start + bestZeroCross) % _ringCapacity;
        // Frequency estimation: period = distance between consecutive crossings
        if (secondZeroCross != -1) {
          final periodSamples = secondZeroCross - bestZeroCross;
          if (periodSamples > 0) {
            final estimatedHz = 48000.0 / periodSamples;
            _detectedFreqHz = _detectedFreqHz * 0.75 + estimatedHz * 0.25;
          }
        }
      } else {
        triggerOffset =
            (_ringWriteIndex - windowSize + _ringCapacity) % _ringCapacity;
      }
    } else {
      triggerOffset =
          (_ringWriteIndex - windowSize + _ringCapacity) % _ringCapacity;
    }

    // 2. Extract Waveforms & Calculate Metrics
    final ch1Pts = <Offset>[];
    final ch2Pts = <Offset>[];
    final xyPts = <Offset>[];

    double ch1Min = 1.0, ch1Max = -1.0, ch1SumSq = 0.0;
    double ch2Min = 1.0, ch2Max = -1.0, ch2SumSq = 0.0;
    double dotProduct = 0.0;

    final width = size.width;
    final height = size.height;

    for (int i = 0; i < windowSize; i++) {
      final ringIdx = (triggerOffset + i) % _ringCapacity;
      final raw1 = _ch1Ring[ringIdx];
      final raw2 = _ch2Ring[ringIdx];

      // Telemetry tracking
      ch1Min = math.min(ch1Min, raw1);
      ch1Max = math.max(ch1Max, raw1);
      ch1SumSq += raw1 * raw1;

      ch2Min = math.min(ch2Min, raw2);
      ch2Max = math.max(ch2Max, raw2);
      ch2SumSq += raw2 * raw2;

      dotProduct += raw1 * raw2;

      final s1 = (raw1 * _voltsGain).clamp(-1.0, 1.0);
      final s2 = (raw2 * _voltsGain).clamp(-1.0, 1.0);

      final x = (i / (windowSize - 1)) * width;

      if (_mode == OscilloscopeMode.splitTrace) {
        // CH1 on top quarter-center, CH2 on bottom quarter-center
        final y1 = (height * 0.25) - (s1 * (height * 0.22));
        final y2 = (height * 0.75) - (s2 * (height * 0.22));
        ch1Pts.add(Offset(x, y1));
        ch2Pts.add(Offset(x, y2));
      } else {
        // Dual Overlay: center baseline
        final centerY = height * 0.5;
        final y1 = centerY - (s1 * (height * 0.44));
        final y2 = centerY - (s2 * (height * 0.44));
        ch1Pts.add(Offset(x, y1));
        ch2Pts.add(Offset(x, y2));
      }

      // X-Y Lissajous points
      final xyX = (width * 0.5) + (s1 * (width * 0.40));
      final xyY = (height * 0.5) - (s2 * (height * 0.40));
      xyPts.add(Offset(xyX, xyY));
    }

    // Telemetry updates
    _ch1Vpp = (ch1Max - ch1Min).clamp(0.0, 2.0);
    _ch2Vpp = (ch2Max - ch2Min).clamp(0.0, 2.0);

    final rms1 = math.sqrt(ch1SumSq / windowSize);
    final rms2 = math.sqrt(ch2SumSq / windowSize);
    _ch1RmsDb = rms1 > 1e-4 ? 20.0 * math.log(rms1) / math.ln10 : -96.0;
    _ch2RmsDb = rms2 > 1e-4 ? 20.0 * math.log(rms2) / math.ln10 : -96.0;

    // Stereo phase correlation
    final denom = math.sqrt(ch1SumSq * ch2SumSq);
    if (denom > 1e-6) {
      _stereoCorrelation =
          (_stereoCorrelation * 0.8) + ((dotProduct / denom) * 0.2);
    }

    // 3. Phosphor Persistence History Management
    if (_glowPersistence) {
      _ch1Persistence.add(List.from(ch1Pts));
      _ch2Persistence.add(List.from(ch2Pts));
      _xyPersistence.add(List.from(xyPts));

      if (_ch1Persistence.length > _maxPersistenceFrames) {
        _ch1Persistence.removeAt(0);
      }
      if (_ch2Persistence.length > _maxPersistenceFrames) {
        _ch2Persistence.removeAt(0);
      }
      if (_xyPersistence.length > _maxPersistenceFrames) {
        _xyPersistence.removeAt(0);
      }
    } else {
      _ch1Persistence.clear();
      _ch2Persistence.clear();
      _xyPersistence.clear();
    }

    return _ScopeRenderData(
      ch1Points: ch1Pts,
      ch2Points: ch2Pts,
      xyPoints: xyPts,
      ch1Persistence: List.from(_ch1Persistence),
      ch2Persistence: List.from(_ch2Persistence),
      xyPersistence: List.from(_xyPersistence),
    );
  }

  @override
  Widget build(BuildContext context) {
    final primary = widget.primaryColor;
    const ch1Color = Color(0xFF00F2FE); // Cyan Beam
    const ch2Color = Color(0xFFFF2A6D); // Neon Magenta Beam

    return Container(
      height: widget.height,
      decoration: BoxDecoration(
        color: const Color(0xFF0A0D14),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: primary.withValues(alpha: 0.28),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.5),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
          BoxShadow(
            color: primary.withValues(alpha: 0.08),
            blurRadius: 16,
            spreadRadius: -2,
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          // 1. Gesture Interactive Canvas
          Positioned.fill(
            child: GestureDetector(
              onTap: () {
                // Cycle modes on tap
                setState(() {
                  final nextIdx = (_mode.index + 1) % 3;
                  _mode = OscilloscopeMode.values[nextIdx];
                });
              },
              onDoubleTap: () {
                setState(() {
                  _timeZoom = 1.0;
                  _voltsGain = 1.0;
                });
              },
              onLongPress: () {
                setState(() => _showHud = !_showHud);
              },
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final renderData = _computeScopeData(
                    Size(constraints.maxWidth, constraints.maxHeight),
                  );
                  return CustomPaint(
                    painter: _OscilloscopePainter(
                      data: renderData,
                      mode: _mode,
                      primaryColor: primary,
                      ch1Color: ch1Color,
                      ch2Color: ch2Color,
                      glowPersistence: _glowPersistence,
                    ),
                    size: Size.infinite,
                  );
                },
              ),
            ),
          ),

          // 2. HUD Top Telemetry Bar

          // 3. HUD Bottom Telemetry Bar (Frequency, Phase, Trigger)

          // 4. Quick Interactive Floating Toolbar
        ],
      ),
    );
  }

  Widget _buildChannelBadge({
    required String channel,
    required Color color,
    required double vpp,
    required double rmsDb,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            channel,
            style: TextStyle(
              color: color,
              fontSize: 9.5,
              fontWeight: FontWeight.bold,
              fontFamily: 'monospace',
            ),
          ),
          const SizedBox(width: 4),
          Text(
            '${(vpp * 1.0).toStringAsFixed(2)}V',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 9.5,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToolbarChip({
    required IconData icon,
    required String label,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    final primary = widget.primaryColor;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        height: 24,
        padding: const EdgeInsets.symmetric(horizontal: 7),
        decoration: BoxDecoration(
          color: isActive
              ? primary.withValues(alpha: 0.18)
              : Colors.black.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isActive ? primary.withValues(alpha: 0.6) : Colors.white12,
            width: 0.8,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 12,
              color: isActive ? primary : Colors.white60,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                color: isActive ? Colors.white : Colors.white60,
                fontSize: 9.5,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Snapshot holding calculated point geometry and persistence history.
class _ScopeRenderData {
  final List<Offset> ch1Points;
  final List<Offset> ch2Points;
  final List<Offset> xyPoints;
  final List<List<Offset>> ch1Persistence;
  final List<List<Offset>> ch2Persistence;
  final List<List<Offset>> xyPersistence;

  _ScopeRenderData({
    required this.ch1Points,
    required this.ch2Points,
    required this.xyPoints,
    required this.ch1Persistence,
    required this.ch2Persistence,
    required this.xyPersistence,
  });

  factory _ScopeRenderData.empty() => _ScopeRenderData(
        ch1Points: const [],
        ch2Points: const [],
        xyPoints: const [],
        ch1Persistence: const [],
        ch2Persistence: const [],
        xyPersistence: const [],
      );
}

/// Custom painter for the precision oscilloscope graticule, beam bloom,
/// and phosphor persistence traces.
class _OscilloscopePainter extends CustomPainter {
  final _ScopeRenderData data;
  final OscilloscopeMode mode;
  final Color primaryColor;
  final Color ch1Color;
  final Color ch2Color;
  final bool glowPersistence;

  _OscilloscopePainter({
    required this.data,
    required this.mode,
    required this.primaryColor,
    required this.ch1Color,
    required this.ch2Color,
    required this.glowPersistence,
  });

  @override
  void paint(Canvas canvas, Size size) {
    _drawGraticuleGrid(canvas, size);

    if (mode == OscilloscopeMode.xyLissajous) {
      _drawXyTrace(canvas, size);
    } else {
      _drawTimeDomainTraces(canvas, size);
    }
  }

  /// Draws an authentic 8x10 division oscilloscope graticule with center ticks.
  void _drawGraticuleGrid(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = const Color(0xFF1B2A38).withValues(alpha: 0.55)
      ..strokeWidth = 0.8
      ..style = PaintingStyle.stroke;

    final centerAxisPaint = Paint()
      ..color = const Color(0xFF2E485D).withValues(alpha: 0.85)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    final tickPaint = Paint()
      ..color = const Color(0xFF385770)
      ..strokeWidth = 0.8
      ..style = PaintingStyle.stroke;

    const numHDivs = 10;
    const numVDivs = 8;

    final stepX = size.width / numHDivs;
    final stepY = size.height / numVDivs;

    // Vertical grid lines
    for (int i = 1; i < numHDivs; i++) {
      final x = i * stepX;
      canvas.drawLine(
        Offset(x, 0),
        Offset(x, size.height),
        (i == numHDivs ~/ 2) ? centerAxisPaint : gridPaint,
      );
    }

    // Horizontal grid lines
    for (int j = 1; j < numVDivs; j++) {
      final y = j * stepY;
      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        (j == numVDivs ~/ 2) ? centerAxisPaint : gridPaint,
      );
    }

    // Center Crosshairs Division Ticks (5 ticks per major division)
    final centerX = size.width * 0.5;
    final centerY = size.height * 0.5;
    const tickLen = 3.0;

    // Horizontal axis tick marks
    for (int i = 0; i <= numHDivs * 5; i++) {
      final x = (i / (numHDivs * 5)) * size.width;
      canvas.drawLine(
        Offset(x, centerY - tickLen),
        Offset(x, centerY + tickLen),
        tickPaint,
      );
    }

    // Vertical axis tick marks
    for (int j = 0; j <= numVDivs * 5; j++) {
      final y = (j / (numVDivs * 5)) * size.height;
      canvas.drawLine(
        Offset(centerX - tickLen, y),
        Offset(centerX + tickLen, y),
        tickPaint,
      );
    }

    // If split trace mode, draw secondary zero baselines
    if (mode == OscilloscopeMode.splitTrace) {
      final splitAxisPaint = Paint()
        ..color = Colors.white.withValues(alpha: 0.15)
        ..strokeWidth = 0.8
        ..style = PaintingStyle.stroke;

      canvas.drawLine(
        Offset(0, size.height * 0.25),
        Offset(size.width, size.height * 0.25),
        splitAxisPaint,
      );
      canvas.drawLine(
        Offset(0, size.height * 0.75),
        Offset(size.width, size.height * 0.75),
        splitAxisPaint,
      );
    }
  }

  /// Draws CH1 and CH2 time-domain waveforms with dual-pass glow and persistence.
  void _drawTimeDomainTraces(Canvas canvas, Size size) {
    final showCh1 = mode != OscilloscopeMode.ch2Solo;
    final showCh2 = mode != OscilloscopeMode.ch1Solo;

    // 1. Draw Phosphor Persistence Ghost Trails (oldest to newest)
    if (glowPersistence) {
      if (showCh1 && data.ch1Persistence.isNotEmpty) {
        for (int i = 0; i < data.ch1Persistence.length; i++) {
          final alpha = 0.12 + (i * 0.08);
          _drawTracePath(
            canvas,
            data.ch1Persistence[i],
            ch1Color.withValues(alpha: alpha),
            strokeWidth: 1.2,
          );
        }
      }

      if (showCh2 && data.ch2Persistence.isNotEmpty) {
        for (int i = 0; i < data.ch2Persistence.length; i++) {
          final alpha = 0.12 + (i * 0.08);
          _drawTracePath(
            canvas,
            data.ch2Persistence[i],
            ch2Color.withValues(alpha: alpha),
            strokeWidth: 1.2,
          );
        }
      }
    }

    // 2. Active Channel 2 (Magenta) Trace
    if (showCh2 && data.ch2Points.isNotEmpty) {
      // Outer Beam Bloom / Halo
      _drawTracePath(
        canvas,
        data.ch2Points,
        ch2Color.withValues(alpha: 0.35),
        strokeWidth: 4.2,
        blurSigma: 2.5,
      );
      // Sharp Intense Core Beam
      _drawTracePath(
        canvas,
        data.ch2Points,
        ch2Color.withValues(alpha: 0.95),
        strokeWidth: 1.6,
      );
    }

    // 3. Active Channel 1 (Cyan) Trace
    if (showCh1 && data.ch1Points.isNotEmpty) {
      // Outer Beam Bloom / Halo
      _drawTracePath(
        canvas,
        data.ch1Points,
        ch1Color.withValues(alpha: 0.35),
        strokeWidth: 4.2,
        blurSigma: 2.5,
      );
      // Sharp Intense Core Beam
      _drawTracePath(
        canvas,
        data.ch1Points,
        ch1Color.withValues(alpha: 0.95),
        strokeWidth: 1.6,
      );
    }
  }

  /// Draws X-Y Lissajous phase orbital with gradient bloom.
  void _drawXyTrace(Canvas canvas, Size size) {
    if (data.xyPoints.isEmpty) return;

    // Phosphor Persistence Ghost Trails
    if (glowPersistence && data.xyPersistence.isNotEmpty) {
      for (int i = 0; i < data.xyPersistence.length; i++) {
        final alpha = 0.10 + (i * 0.08);
        _drawTracePath(
          canvas,
          data.xyPersistence[i],
          ch1Color.withValues(alpha: alpha),
          strokeWidth: 1.2,
        );
      }
    }

    // Outer Bloom
    _drawTracePath(
      canvas,
      data.xyPoints,
      primaryColor.withValues(alpha: 0.35),
      strokeWidth: 4.0,
      blurSigma: 2.5,
    );

    // Inner Core Lissajous Beam
    _drawTracePath(
      canvas,
      data.xyPoints,
      const Color(0xFF00F2FE).withValues(alpha: 0.95),
      strokeWidth: 1.6,
    );
  }

  void _drawTracePath(
    Canvas canvas,
    List<Offset> points,
    Color color, {
    required double strokeWidth,
    double? blurSigma,
  }) {
    if (points.length < 2) return;

    final path = Path()..moveTo(points[0].dx, points[0].dy);
    for (int i = 1; i < points.length; i++) {
      path.lineTo(points[i].dx, points[i].dy);
    }

    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    if (blurSigma != null && blurSigma > 0) {
      paint.maskFilter = MaskFilter.blur(BlurStyle.normal, blurSigma);
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _OscilloscopePainter oldDelegate) => true;
}
