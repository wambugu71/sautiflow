import 'dart:math' as math;
import 'package:flutter/material.dart';

/// An interactive, high-performance waveform seek bar widget.
/// Replaces the standard Flutter Slider when enabled in settings.
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
    this.height = 48.0,
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
    final inactiveColor = widget.inactiveColor ?? Colors.white.withValues(alpha: 0.18);
    final abHighlightColor = widget.abHighlightColor ?? Colors.amber.withValues(alpha: 0.35);

    final currentPos = _isDragging ? (_dragPositionMs ?? widget.displayPosMs) : widget.displayPosMs;
    final maxDuration = widget.maxMs > 0 ? widget.maxMs : 1.0;
    final progress = (currentPos / maxDuration).clamp(0.0, 1.0);

    return LayoutBuilder(
      builder: (context, constraints) {
        final totalWidth = constraints.maxWidth;

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragStart: (details) {
            setState(() {
              _isDragging = true;
              _dragPositionMs = _calculateMsFromX(details.localPosition.dx, totalWidth, maxDuration);
            });
            widget.onDragStateChanged?.call(true);
            if (_dragPositionMs != null) widget.onDragUpdate?.call(_dragPositionMs!);
          },
          onHorizontalDragUpdate: (details) {
            final ms = _calculateMsFromX(details.localPosition.dx, totalWidth, maxDuration);
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
          onTapDown: (details) {
            final ms = _calculateMsFromX(details.localPosition.dx, totalWidth, maxDuration);
            widget.onSeekEnd(ms);
          },
          child: SizedBox(
            height: widget.height,
            width: totalWidth,
            child: Stack(
              children: [
                // Waveform Custom Painter
                Positioned.fill(
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

                // Thumb handle marker line when dragging or playing
                Positioned(
                  left: (progress * totalWidth - 1.5).clamp(0.0, totalWidth - 3.0),
                  top: 4,
                  bottom: 4,
                  child: Container(
                    width: _isDragging ? 4.0 : 3.0,
                    decoration: BoxDecoration(
                      color: _isDragging ? Colors.white : activeColor.withValues(alpha: 0.9),
                      borderRadius: BorderRadius.circular(2.0),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.5),
                          blurRadius: 4,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
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

  @override
  void paint(Canvas canvas, Size size) {
    if (peaks.isEmpty) return;

    final width = size.width;
    final height = size.height;
    final centerPy = height / 2;

    // Draw A-B Highlighted region & markers
    if (abRepeatState >= 1 && abPointAMs != null && maxMs > 0) {
      final xA = (abPointAMs! / maxMs * width).clamp(0.0, width);

      if (abRepeatState == 2 && abPointBMs != null) {
        final xB = (abPointBMs! / maxMs * width).clamp(0.0, width);
        final left = math.min(xA, xB);
        final right = math.max(xA, xB);

        final abRect = Rect.fromLTRB(left, 2, right, height - 2);
        final abPaint = Paint()
          ..color = abHighlightColor
          ..style = PaintingStyle.fill;
        canvas.drawRRect(RRect.fromRectAndRadius(abRect, const Radius.circular(6)), abPaint);

        // Pin B line
        final pinBPaint = Paint()
          ..color = activeColor
          ..strokeWidth = 2.0;
        canvas.drawLine(Offset(xB, 0), Offset(xB, height), pinBPaint);
      }

      // Pin A line
      final pinAPaint = Paint()
        ..color = const Color(0xFFFFA726)
        ..strokeWidth = 2.0;
      canvas.drawLine(Offset(xA, 0), Offset(xA, height), pinAPaint);
    }

    // Bar dimensions
    const barWidth = 3.0;
    const gap = 2.0;
    const totalBarStep = barWidth + gap;
    final maxBars = (width / totalBarStep).floor();

    final paintActive = Paint()
      ..color = activeColor
      ..strokeWidth = barWidth
      ..strokeCap = StrokeCap.round;

    final paintInactive = Paint()
      ..color = inactiveColor
      ..strokeWidth = barWidth
      ..strokeCap = StrokeCap.round;

    final count = math.min(maxBars, peaks.length);

    for (int i = 0; i < count; i++) {
      final barRatio = (i / count);
      final x = barRatio * width + barWidth / 2;
      final peakVal = peaks[i].clamp(0.05, 1.0);

      final barHeight = (peakVal * (height - 8)).clamp(4.0, height - 4);
      final topY = centerPy - (barHeight / 2);
      final bottomY = centerPy + (barHeight / 2);

      final paint = barRatio <= progress ? paintActive : paintInactive;
      canvas.drawLine(Offset(x, topY), Offset(x, bottomY), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _WaveformSeekBarPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.peaks != peaks ||
        oldDelegate.isDragging != isDragging ||
        oldDelegate.abRepeatState != abRepeatState ||
        oldDelegate.abPointAMs != abPointAMs ||
        oldDelegate.abPointBMs != abPointBMs;
  }
}
