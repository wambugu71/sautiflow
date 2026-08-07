import 'dart:math' as math;
import 'package:flutter/material.dart';

class RaceSoundstageVisualizer extends StatefulWidget {
  final double delayMs; // e.g. 0.05 to 0.40 ms
  final double alpha;   // e.g. 0.10 to 0.90
  final double lpfHz;   // e.g. 500 to 8000 Hz
  final bool isEnabled;
  final Color primaryColor;

  const RaceSoundstageVisualizer({
    super.key,
    required this.delayMs,
    required this.alpha,
    required this.lpfHz,
    this.isEnabled = true,
    this.primaryColor = const Color(0xFF6366F1),
  });

  @override
  State<RaceSoundstageVisualizer> createState() =>
      _RaceSoundstageVisualizerState();
}

class _RaceSoundstageVisualizerState extends State<RaceSoundstageVisualizer>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final microseconds = (widget.delayMs * 1000).round();

    return AnimatedBuilder(
      animation: _animController,
      builder: (context, child) {
        return Container(
          width: double.infinity,
          height: 180,
          margin: const EdgeInsets.symmetric(vertical: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF0F172A).withValues(alpha: 0.8),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: widget.isEnabled
                  ? widget.primaryColor.withValues(alpha: 0.4)
                  : Colors.white10,
              width: 1.5,
            ),
            boxShadow: widget.isEnabled
                ? [
                    BoxShadow(
                      color: widget.primaryColor.withValues(alpha: 0.15),
                      blurRadius: 16,
                      spreadRadius: 2,
                    ),
                  ]
                : [],
          ),
          child: Column(
            children: [
              // Top metric badges
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _buildBadge(
                    icon: Icons.timer_outlined,
                    label: 'ITD Delay',
                    value: '$microsecondsµs',
                    color: Colors.cyanAccent,
                  ),
                  _buildBadge(
                    icon: Icons.waves,
                    label: 'Alpha (α)',
                    value: '${(widget.alpha * 100).toInt()}%',
                    color: Colors.amberAccent,
                  ),
                  _buildBadge(
                    icon: Icons.shield_outlined,
                    label: 'Head LPF',
                    value: '${widget.lpfHz.toInt()}Hz',
                    color: Colors.purpleAccent,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // Main CustomPaint Visualizer
              Expanded(
                child: CustomPaint(
                  size: Size.infinite,
                  painter: _RaceSoundstagePainter(
                    delayMs: widget.delayMs,
                    alpha: widget.alpha,
                    lpfHz: widget.lpfHz,
                    isEnabled: widget.isEnabled,
                    primaryColor: widget.primaryColor,
                    animValue: _animController.value,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildBadge({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            '$label: ',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.6),
              fontSize: 10,
              fontWeight: FontWeight.w500,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

class _RaceSoundstagePainter extends CustomPainter {
  final double delayMs;
  final double alpha;
  final double lpfHz;
  final bool isEnabled;
  final Color primaryColor;
  final double animValue;

  _RaceSoundstagePainter({
    required this.delayMs,
    required this.alpha,
    required this.lpfHz,
    required this.isEnabled,
    required this.primaryColor,
    required this.animValue,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2 + 10);
    final opacityMultiplier = isEnabled ? 1.0 : 0.25;

    // 1. Calculate Virtual Speaker Spread Angle based on delayMs
    // 0.05ms -> ~20° separation; 0.40ms -> ~75° separation
    final normDelay = ((delayMs - 0.05) / 0.35).clamp(0.0, 1.0);
    final angleRad = (25.0 + normDelay * 55.0) * (math.pi / 180.0);
    final speakerDist = size.width * 0.38;

    final leftSpeaker = Offset(
      center.dx - speakerDist * math.sin(angleRad / 2),
      center.dy - speakerDist * math.cos(angleRad / 2) * 0.4 - 15,
    );
    final rightSpeaker = Offset(
      center.dx + speakerDist * math.sin(angleRad / 2),
      center.dy - speakerDist * math.cos(angleRad / 2) * 0.4 - 15,
    );

    // 2. Draw Listener Head at Center
    final headRadius = 14.0;
    final headPaint = Paint()
      ..color = isEnabled
          ? Colors.white.withValues(alpha: 0.9)
          : Colors.white30
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, headRadius, headPaint);

    // Ears
    final earPaint = Paint()
      ..color = isEnabled ? primaryColor : Colors.white24
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(center.dx - headRadius - 2, center.dy), 3.5, earPaint);
    canvas.drawCircle(Offset(center.dx + headRadius + 2, center.dy), 3.5, earPaint);

    // Head Shadow Low-Pass Filter Shield Arc
    // Cutoff 500Hz -> thick shielding; 8000Hz -> thin acoustic shield
    final normLpf = (1.0 - (lpfHz - 500) / 7500).clamp(0.1, 1.0);
    final shieldRadius = headRadius + 8 + normLpf * 6;
    final shieldPaint = Paint()
      ..color = Colors.purpleAccent.withValues(alpha: 0.4 * opacityMultiplier)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5 + normLpf * 3.0;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: shieldRadius),
      math.pi * 0.85,
      math.pi * 1.3,
      false,
      shieldPaint,
    );

    // 3. Draw Speaker Cones
    _drawSpeakerCone(canvas, leftSpeaker, true, isEnabled);
    _drawSpeakerCone(canvas, rightSpeaker, false, isEnabled);

    // 4. Draw Soundwaves from Speakers to Ears (Direct sound)
    final directWavePaint = Paint()
      ..color = isEnabled
          ? primaryColor.withValues(alpha: 0.5 * opacityMultiplier)
          : Colors.white12
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    _drawExpandingRings(canvas, leftSpeaker, animValue, directWavePaint);
    _drawExpandingRings(canvas, rightSpeaker, animValue, directWavePaint);

    // 5. Draw Crosstalk Cancellation Wave Arcs (R.A.C.E. Anti-Phase Waves)
    // Left speaker to Right ear cancellation arc (and vice versa)
    if (isEnabled) {
      final leftEar = Offset(center.dx - headRadius - 2, center.dy);
      final rightEar = Offset(center.dx + headRadius + 2, center.dy);

      final cancelWavePaint = Paint()
        ..color = Colors.amberAccent.withValues(alpha: alpha * 0.7)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5 + alpha * 2.0;

      final cancelPathL2R = Path();
      cancelPathL2R.moveTo(leftSpeaker.dx, leftSpeaker.dy);
      cancelPathL2R.quadraticBezierTo(
        center.dx,
        center.dy - 35,
        rightEar.dx,
        rightEar.dy,
      );
      canvas.drawPath(cancelPathL2R, cancelWavePaint);

      final cancelPathR2L = Path();
      cancelPathR2L.moveTo(rightSpeaker.dx, rightSpeaker.dy);
      cancelPathR2L.quadraticBezierTo(
        center.dx,
        center.dy - 35,
        leftEar.dx,
        leftEar.dy,
      );
      canvas.drawPath(cancelPathR2L, cancelWavePaint);

      // Pulse dots along cancellation paths
      final pulseT = (animValue * 2) % 1.0;
      final pL2R = _getQuadraticPoint(leftSpeaker, Offset(center.dx, center.dy - 35), rightEar, pulseT);
      final pR2L = _getQuadraticPoint(rightSpeaker, Offset(center.dx, center.dy - 35), leftEar, pulseT);

      final dotPaint = Paint()
        ..color = Colors.amberAccent
        ..style = PaintingStyle.fill;
      canvas.drawCircle(pL2R, 3.0, dotPaint);
      canvas.drawCircle(pR2L, 3.0, dotPaint);
    }

    // Soundstage Width Indicator Line
    final stageLinePaint = Paint()
      ..color = Colors.cyanAccent.withValues(alpha: 0.3 * opacityMultiplier)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    final dashPath = Path()
      ..moveTo(leftSpeaker.dx, leftSpeaker.dy + 15)
      ..lineTo(rightSpeaker.dx, rightSpeaker.dy + 15);
    canvas.drawPath(dashPath, stageLinePaint);
  }

  void _drawSpeakerCone(
      Canvas canvas, Offset pos, bool isLeft, bool active) {
    final bodyPaint = Paint()
      ..color = active ? primaryColor.withValues(alpha: 0.8) : Colors.white24
      ..style = PaintingStyle.fill;

    final glowPaint = Paint()
      ..color = active ? primaryColor.withValues(alpha: 0.4) : Colors.transparent
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);

    canvas.drawCircle(pos, 9, glowPaint);
    canvas.drawCircle(pos, 7, bodyPaint);

    final innerPaint = Paint()
      ..color = Colors.black87
      ..style = PaintingStyle.fill;
    canvas.drawCircle(pos, 3, innerPaint);
  }

  void _drawExpandingRings(
      Canvas canvas, Offset origin, double phase, Paint paint) {
    for (int i = 0; i < 3; i++) {
      final ringPhase = (phase + i / 3.0) % 1.0;
      final radius = 6.0 + ringPhase * 28.0;
      final ringOpacity = (1.0 - ringPhase) * 0.6;
      final p = Paint()
        ..color = paint.color.withValues(alpha: ringOpacity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2;
      canvas.drawCircle(origin, radius, p);
    }
  }

  Offset _getQuadraticPoint(
      Offset p0, Offset p1, Offset p2, double t) {
    final u = 1 - t;
    final tt = t * t;
    final uu = u * u;
    final x = uu * p0.dx + 2 * u * t * p1.dx + tt * p2.dx;
    final y = uu * p0.dy + 2 * u * t * p1.dy + tt * p2.dy;
    return Offset(x, y);
  }

  @override
  bool shouldRepaint(covariant _RaceSoundstagePainter oldDelegate) {
    return oldDelegate.delayMs != delayMs ||
        oldDelegate.alpha != alpha ||
        oldDelegate.lpfHz != lpfHz ||
        oldDelegate.isEnabled != isEnabled ||
        oldDelegate.animValue != animValue;
  }
}
