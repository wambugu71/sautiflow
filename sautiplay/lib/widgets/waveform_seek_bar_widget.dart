import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

/// An interactive, high-performance waveform seek bar widget.
/// Optimized for 60-120Hz smooth rendering with geometry caching,
/// GPU-accelerated batch point drawing, and direct canvas playhead rendering.
class WaveformSeekBarWidget extends StatefulWidget {
  final List<double> peaks;
  final double displayPosMs;
  final double maxMs;
  final ValueChanged<double> onSeekEnd;
  final ValueChanged<double>? onDragUpdate;
  final ValueChanged<bool>? onDragStateChanged;

  // A-B Repeat Markers Support
  final int abRepeatState; // 0=off, 1=setting A, 2=active A-B
  final double? abPointAMs;
  final double? abPointBMs;

  final Color? activeColor;
  final Color? inactiveColor;
  final Color? abHighlightColor;
  final double height;

  const WaveformSeekBarWidget({
    super.key,
    required this.peaks,
    required this.displayPosMs,
    required this.maxMs,
    required this.onSeekEnd,
    this.onDragUpdate,
    this.onDragStateChanged,
    this.abRepeatState = 0,
    this.abPointAMs,
    this.abPointBMs,
    this.activeColor,
    this.inactiveColor,
    this.abHighlightColor,
    this.height = 36.0,
  });

  @override
  State<WaveformSeekBarWidget> createState() => _WaveformSeekBarWidgetState();
}

class _WaveformSeekBarWidgetState extends State<WaveformSeekBarWidget> {
  bool _isDragging = false;
  double? _dragPositionMs;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final activeColor = widget.activeColor ?? theme.primaryColor;
    final inactiveColor =
        widget.inactiveColor ?? Colors.white.withValues(alpha: 0.18);
    final abHighlightColor =
        widget.abHighlightColor ?? Colors.amber.withValues(alpha: 0.35);

    final currentPos = _isDragging
        ? (_dragPositionMs ?? widget.displayPosMs)
        : widget.displayPosMs;
    final maxDuration = widget.maxMs > 0 ? widget.maxMs : 1.0;
    final progress = (currentPos / maxDuration).clamp(0.0, 1.0);

    return LayoutBuilder(
      builder: (context, constraints) {
        final totalWidth = constraints.maxWidth;

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragStart: (details) {
            final ms = _calculateMsFromX(
                details.localPosition.dx, totalWidth, maxDuration);
            setState(() {
              _isDragging = true;
              _dragPositionMs = ms;
            });
            widget.onDragStateChanged?.call(true);
            widget.onDragUpdate?.call(ms);
          },
          onHorizontalDragUpdate: (details) {
            final ms = _calculateMsFromX(
                details.localPosition.dx, totalWidth, maxDuration);
            setState(() => _dragPositionMs = ms);
            widget.onDragUpdate?.call(ms);
          },
          onHorizontalDragEnd: (details) {
            if (_dragPositionMs != null) {
              widget.onSeekEnd(_dragPositionMs!);
            }
            setState(() {
              _isDragging = false;
              _dragPositionMs = null;
            });
            widget.onDragStateChanged?.call(false);
          },
          onHorizontalDragCancel: () {
            setState(() {
              _isDragging = false;
              _dragPositionMs = null;
            });
            widget.onDragStateChanged?.call(false);
          },
          onTapDown: (details) {
            final ms = _calculateMsFromX(
                details.localPosition.dx, totalWidth, maxDuration);
            setState(() {
              _isDragging = true;
              _dragPositionMs = ms;
            });
            widget.onDragStateChanged?.call(true);
            widget.onDragUpdate?.call(ms);
          },
          onTapUp: (details) {
            if (_dragPositionMs != null) {
              widget.onSeekEnd(_dragPositionMs!);
            }
            setState(() {
              _isDragging = false;
              _dragPositionMs = null;
            });
            widget.onDragStateChanged?.call(false);
          },
          onTapCancel: () {
            if (!_isDragging) {
              setState(() {
                _isDragging = false;
                _dragPositionMs = null;
              });
              widget.onDragStateChanged?.call(false);
            }
          },
          child: RepaintBoundary(
            child: SizedBox(
              height: widget.height,
              width: totalWidth,
              child: CustomPaint(
                painter: _WaveformSeekBarPainter(
                  peaks: widget.peaks,
                  progress: progress,
                  activeColor: activeColor,
                  inactiveColor: inactiveColor,
                  isDragging: _isDragging,
                  abRepeatState: widget.abRepeatState,
                  abPointAMs: widget.abPointAMs,
                  abPointBMs: widget.abPointBMs,
                  maxMs: maxDuration,
                  abHighlightColor: abHighlightColor,
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  double _calculateMsFromX(double dx, double totalWidth, double maxMs) {
    if (totalWidth <= 0) return 0.0;
    final ratio = (dx / totalWidth).clamp(0.0, 1.0);
    return ratio * maxMs;
  }
}

class _WaveformGeometry {
  final List<double> peaks;
  final double width;
  final double height;
  final Float32List points;

  const _WaveformGeometry({
    required this.peaks,
    required this.width,
    required this.height,
    required this.points,
  });
}

class _WaveformSeekBarPainter extends CustomPainter {
  final List<double> peaks;
  final double progress;
  final Color activeColor;
  final Color inactiveColor;
  final bool isDragging;

  final int abRepeatState;
  final double? abPointAMs;
  final double? abPointBMs;
  final double maxMs;
  final Color abHighlightColor;

  _WaveformSeekBarPainter({
    required this.peaks,
    required this.progress,
    required this.activeColor,
    required this.inactiveColor,
    required this.isDragging,
    required this.abRepeatState,
    required this.abPointAMs,
    required this.abPointBMs,
    required this.maxMs,
    required this.abHighlightColor,
  });

  // Reusable static Paint instances to eliminate GC churn at 60-120Hz
  static final Paint _paintInactive = Paint()
    ..strokeWidth = 1.5
    ..strokeCap = StrokeCap.round;
  static final Paint _paintActive = Paint()
    ..strokeWidth = 1.5
    ..strokeCap = StrokeCap.round;
  static final Paint _paintThumbShadow = Paint()
    ..color = const Color(0x80000000)
    ..strokeCap = StrokeCap.round;
  static final Paint _paintThumb = Paint()..strokeCap = StrokeCap.round;
  static final Paint _paintThumbCap = Paint()..style = PaintingStyle.fill;
  static final Paint _paintAbHighlight = Paint()..style = PaintingStyle.fill;
  static final Paint _paintPinA = Paint()
    ..color = const Color(0xFFFFA726)
    ..strokeWidth = 2.0;
  static final Paint _paintPinB = Paint()..strokeWidth = 2.0;

  // Cached geometry (line segments) to avoid recalculating bar dimensions per frame
  static _WaveformGeometry? _cachedGeom;

  static Float32List _getPoints(
      List<double> peaks, double width, double height) {
    if (_cachedGeom != null &&
        identical(_cachedGeom!.peaks, peaks) &&
        _cachedGeom!.width == width &&
        _cachedGeom!.height == height) {
      return _cachedGeom!.points;
    }

    const barWidth = 1.5;
    const gap = 0.75;
    const totalBarStep = barWidth + gap;
    final maxBars = (width / totalBarStep).floor();
    final count = math.max(0, math.min(maxBars, peaks.length));

    if (count == 0) {
      _cachedGeom = _WaveformGeometry(
        peaks: peaks,
        width: width,
        height: height,
        points: Float32List(0),
      );
      return _cachedGeom!.points;
    }

    final points = Float32List(count * 4);
    final centerPy = height / 2;

    for (int i = 0; i < count; i++) {
      final barRatio = i / count;
      final x = barRatio * width + barWidth / 2;

      final samplePos = barRatio * peaks.length;
      final idx = samplePos.floor().clamp(0, peaks.length - 1);
      final idxNext = (idx + 1).clamp(0, peaks.length - 1);
      final t = samplePos - samplePos.floor();
      final peakVal =
          (peaks[idx] * (1.0 - t) + peaks[idxNext] * t).clamp(0.05, 1.0);

      final barHeight = (peakVal * (height - 4)).clamp(2.0, height - 2);
      final topY = centerPy - (barHeight / 2);
      final bottomY = centerPy + (barHeight / 2);

      final offset = i * 4;
      points[offset] = x;
      points[offset + 1] = topY;
      points[offset + 2] = x;
      points[offset + 3] = bottomY;
    }

    _cachedGeom = _WaveformGeometry(
      peaks: peaks,
      width: width,
      height: height,
      points: points,
    );
    return points;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (peaks.isEmpty) return;

    final width = size.width;
    final height = size.height;

    // 1. Draw A-B Highlighted region & markers
    if (abRepeatState >= 1 && abPointAMs != null && maxMs > 0) {
      final xA = (abPointAMs! / maxMs * width).clamp(0.0, width);

      if (abRepeatState == 2 && abPointBMs != null) {
        final xB = (abPointBMs! / maxMs * width).clamp(0.0, width);
        final left = math.min(xA, xB);
        final right = math.max(xA, xB);

        final abRect = Rect.fromLTRB(left, 2, right, height - 2);
        _paintAbHighlight.color = abHighlightColor;
        canvas.drawRRect(
          RRect.fromRectAndRadius(abRect, const Radius.circular(6)),
          _paintAbHighlight,
        );

        // Pin B line
        _paintPinB.color = activeColor;
        canvas.drawLine(Offset(xB, 0), Offset(xB, height), _paintPinB);
      }

      // Pin A line
      canvas.drawLine(Offset(xA, 0), Offset(xA, height), _paintPinA);
    }

    final points = _getPoints(peaks, width, height);
    if (points.isEmpty) return;

    // 2. Draw inactive waveform in a single batch GPU call
    _paintInactive.color = inactiveColor;
    canvas.drawRawPoints(ui.PointMode.lines, points, _paintInactive);

    // 3. Draw active waveform clipped to playback progress in a single batch call
    if (progress > 0.0) {
      final activeClipWidth = (progress * width).clamp(0.0, width);
      canvas.save();
      canvas.clipRect(Rect.fromLTWH(0, 0, activeClipWidth, height));
      _paintActive.color = activeColor;
      canvas.drawRawPoints(ui.PointMode.lines, points, _paintActive);
      canvas.restore();
    }

    // 4. Draw Playhead Thumb indicator directly on canvas
    final thumbX = (progress * width).clamp(0.0, width);
    final thumbWidth = isDragging ? 3.5 : 2.0;

    // Shadow line
    _paintThumbShadow.strokeWidth = thumbWidth + 2.0;
    canvas.drawLine(
      Offset(thumbX, 2),
      Offset(thumbX, height - 2),
      _paintThumbShadow,
    );

    // Primary thumb needle
    _paintThumb
      ..strokeWidth = thumbWidth
      ..color =
          isDragging ? Colors.white : activeColor.withValues(alpha: 0.95);
    canvas.drawLine(
      Offset(thumbX, 2),
      Offset(thumbX, height - 2),
      _paintThumb,
    );

    // Tactile pill ends when dragging
    if (isDragging) {
      _paintThumbCap.color = Colors.white;
      canvas.drawCircle(Offset(thumbX, 3.5), 3.0, _paintThumbCap);
      canvas.drawCircle(Offset(thumbX, height - 3.5), 3.0, _paintThumbCap);
    }
  }

  @override
  bool shouldRepaint(covariant _WaveformSeekBarPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        !identical(oldDelegate.peaks, peaks) ||
        oldDelegate.isDragging != isDragging ||
        oldDelegate.activeColor != activeColor ||
        oldDelegate.inactiveColor != inactiveColor ||
        oldDelegate.abRepeatState != abRepeatState ||
        oldDelegate.abPointAMs != abPointAMs ||
        oldDelegate.abPointBMs != abPointBMs ||
        oldDelegate.abHighlightColor != abHighlightColor;
  }
}
