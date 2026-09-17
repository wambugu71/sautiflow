import 'dart:math' as math;
import 'package:flutter/material.dart';

/// A rich, real-time soundstage visualizer for the OpenStage crossfeed algorithm.
///
/// Visualizes:
/// 1. Virtual studio monitor positioning at the exact stereo spread angle (0° to 90°).
/// 2. Listener head model with ipsilateral (direct) and contralateral (head-shadow) paths.
/// 3. Spherical-head ITD transit delay and low-shelf acoustic occlusion telemetry.
/// 4. Animated acoustic wavefront propagation.
class OpenStageSoundstageVisualizer extends StatefulWidget {
  final double angleDegrees; // 0.0 to 90.0 degrees
  final double gainDb; // -12.0 to +12.0 dB
  final double mix; // 0.0 to 1.0
  final bool isEnabled;
  final Color primaryColor;

  const OpenStageSoundstageVisualizer({
    super.key,
    required this.angleDegrees,
    required this.gainDb,
    this.mix = 1.0,
    this.isEnabled = true,
    this.primaryColor = const Color(0xFF6366F1),
  });

  @override
  State<OpenStageSoundstageVisualizer> createState() =>
      _OpenStageSoundstageVisualizerState();
}

class _OpenStageSoundstageVisualizerState
    extends State<OpenStageSoundstageVisualizer>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  // Spherical head physics: ITD & Cutoff calculation
  ({int itdMicroseconds, int cutoffHz}) _computePhysics() {
    const double w = 0.15; // 15 cm head diameter
    const double d = 1.00; // 1.0 m speaker distance
    const double c = 340.0; // speed of sound m/s

    final double halfThetaRad = (widget.angleDegrees * 0.5) * (math.pi / 180.0);
    final double sinHalfTheta = math.sin(halfThetaRad);

    final double dFar = math.sqrt(
        math.max(0.0, d * d + (w * w * 0.25) + (w * d * sinHalfTheta)));
    final double dNear = math.sqrt(
        math.max(0.0, d * d + (w * w * 0.25) - (w * d * sinHalfTheta)));

    final double itdSeconds = (dFar - dNear) / c;
    final int itdMicros = (itdSeconds * 1000000.0).round();

    final double fLow = math.min(
        0.5 / math.max(itdSeconds, 1e-5), 2000.0);

    return (itdMicroseconds: itdMicros, cutoffHz: fLow.round());
  }

  @override
  Widget build(BuildContext context) {
    final physics = _computePhysics();

    return AnimatedBuilder(
      animation: _animController,
      builder: (context, child) {
        return Container(
          width: double.infinity,
          height: 190,
          margin: const EdgeInsets.symmetric(vertical: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF0F172A).withValues(alpha: 0.85),
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
                      color: widget.primaryColor.withValues(alpha: 0.12),
                      blurRadius: 16,
                      spreadRadius: 2,
                    ),
                  ]
                : [],
          ),
          child: Column(
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 4,
                alignment: WrapAlignment.center,
                children: [
                  _buildBadge(
                    icon: Icons.explore_outlined,
                    label: 'Spread',
                    value: '${widget.angleDegrees.round()}°',
                    color: Colors.cyanAccent,
                  ),
                  _buildBadge(
                    icon: Icons.timer_outlined,
                    label: 'ITD Delay',
                    value: '${physics.itdMicroseconds}µs',
                    color: Colors.amberAccent,
                  ),
                  _buildBadge(
                    icon: Icons.equalizer_rounded,
                    label: 'Gain Comp',
                    value:
                        '${widget.gainDb >= 0 ? '+' : ''}${widget.gainDb.toStringAsFixed(1)}dB',
                    color: Colors.greenAccent,
                  ),
                  _buildBadge(
                    icon: Icons.shield_outlined,
                    label: 'Head Shadow',
                    value: '${physics.cutoffHz}Hz',
                    color: Colors.purpleAccent,
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Expanded(
                child: CustomPaint(
                  size: Size.infinite,
                  painter: _OpenStagePainter(
                    angleDegrees: widget.angleDegrees,
                    gainDb: widget.gainDb,
                    mix: widget.mix,
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
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color),
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
              fontSize: 10.5,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

class _OpenStagePainter extends CustomPainter {
  final double angleDegrees;
  final double gainDb;
  final double mix;
  final bool isEnabled;
  final Color primaryColor;
  final double animValue;

  _OpenStagePainter({
    required this.angleDegrees,
    required this.gainDb,
    required this.mix,
    required this.isEnabled,
    required this.primaryColor,
    required this.animValue,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final double cx = size.width / 2.0;
    final double headY = size.height - 24.0;
    final double speakerRadius = math.min(size.width * 0.38, size.height * 0.72);

    final double halfAngleRad = (angleDegrees * 0.5) * (math.pi / 180.0);

    // Positions of left and right virtual speakers relative to head center
    final double spkLX = cx - speakerRadius * math.sin(halfAngleRad);
    final double spkLY = headY - speakerRadius * math.cos(halfAngleRad);

    final double spkRX = cx + speakerRadius * math.sin(halfAngleRad);
    final double spkRY = headY - speakerRadius * math.cos(halfAngleRad);

    final earOffset = 14.0;
    final earL = Offset(cx - earOffset, headY);
    final earR = Offset(cx + earOffset, headY);

    // 1. Draw Angle Arc between Left & Right speakers
    final arcPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.12)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;

    final arcRect = Rect.fromCircle(
        center: Offset(cx, headY), radius: speakerRadius * 0.45);
    final startAngle = -math.pi / 2 - halfAngleRad;
    final sweepAngle = halfAngleRad * 2.0;
    canvas.drawArc(arcRect, startAngle, sweepAngle, false, arcPaint);

    // 2. Acoustic wave propagation from speakers to ears
    if (isEnabled) {
      _drawAcousticWaves(
          canvas, Offset(spkLX, spkLY), earL, earR, isLeft: true);
      _drawAcousticWaves(
          canvas, Offset(spkRX, spkRY), earR, earL, isLeft: false);
    }

    // 3. Draw Speaker boxes
    _drawSpeaker(canvas, Offset(spkLX, spkLY), halfAngleRad, 'L');
    _drawSpeaker(canvas, Offset(spkRX, spkRY), -halfAngleRad, 'R');

    // 4. Draw Listener Head
    _drawListener(canvas, Offset(cx, headY), earL, earR);
  }

  void _drawAcousticWaves(Canvas canvas, Offset spk, Offset ipsiEar,
      Offset contraEar, {required bool isLeft}) {
    final directPaint = Paint()
      ..color = primaryColor.withValues(alpha: 0.45 * mix)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8;

    final crossPaint = Paint()
      ..color = const Color(0xFFFF9800).withValues(alpha: 0.35 * mix)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.3;

    // Direct path line with pulse
    canvas.drawLine(spk, ipsiEar, directPaint);

    // Animated wavefront dot along direct path
    final double directPulseProgress = animValue;
    final directPulsePos = Offset.lerp(spk, ipsiEar, directPulseProgress)!;
    final pulsePaint = Paint()
      ..color = primaryColor.withValues(alpha: 0.8)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(directPulsePos, 2.5, pulsePaint);

    // Contralateral head-shadow curve (diffraction ray bending around skull)
    final path = Path();
    path.moveTo(spk.dx, spk.dy);
    // Control point bends slightly outward to simulate head diffraction
    final midX = (spk.dx + contraEar.dx) * 0.5 + (isLeft ? -10 : 10);
    final midY = (spk.dy + contraEar.dy) * 0.5 - 6;
    path.quadraticBezierTo(midX, midY, contraEar.dx, contraEar.dy);

    canvas.drawPath(path, crossPaint);

    // Animated pulse along crossfeed path
    final double crossPulseProgress =
        (animValue - 0.22 + 1.0) % 1.0; // delayed phase
    final crossPos = Offset.lerp(
        Offset(midX, midY), contraEar, crossPulseProgress)!;
    final crossPulsePaint = Paint()
      ..color = const Color(0xFFFFB74D).withValues(alpha: 0.7)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(crossPos, 2.0, crossPulsePaint);
  }

  void _drawSpeaker(
      Canvas canvas, Offset pos, double rotationRad, String label) {
    canvas.save();
    canvas.translate(pos.dx, pos.dy);
    canvas.rotate(rotationRad);

    final boxPaint = Paint()
      ..color = isEnabled
          ? primaryColor.withValues(alpha: 0.25)
          : const Color(0xFF1E293B)
      ..style = PaintingStyle.fill;

    final borderPaint = Paint()
      ..color = isEnabled ? primaryColor : Colors.white24
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    const w = 22.0;
    const h = 26.0;
    final rrect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset.zero, width: w, height: h),
      const Radius.circular(5),
    );

    canvas.drawRRect(rrect, boxPaint);
    canvas.drawRRect(rrect, borderPaint);

    // Speaker cone circle
    final conePaint = Paint()
      ..color = isEnabled
          ? primaryColor.withValues(alpha: 0.7)
          : Colors.white30
      ..style = PaintingStyle.fill;
    canvas.drawCircle(const Offset(0, 3), 5.5, conePaint);

    // Tweeter
    canvas.drawCircle(const Offset(0, -6), 2.5, conePaint);

    canvas.restore();

    // Speaker label (L / R)
    final tp = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          color: isEnabled ? Colors.white : Colors.white54,
          fontSize: 9.5,
          fontWeight: FontWeight.bold,
          fontFamily: 'monospace',
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(pos.dx - tp.width / 2, pos.dy - 22));
  }

  void _drawListener(
      Canvas canvas, Offset headCenter, Offset earL, Offset earR) {
    // Head circle
    final headPaint = Paint()
      ..color = const Color(0xFF1E293B)
      ..style = PaintingStyle.fill;

    final headBorder = Paint()
      ..color = isEnabled ? primaryColor.withValues(alpha: 0.6) : Colors.white24
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    canvas.drawCircle(headCenter, 14.0, headPaint);
    canvas.drawCircle(headCenter, 14.0, headBorder);

    // Ears / Headphone pads
    final earPaint = Paint()
      ..color = isEnabled ? primaryColor : Colors.white38
      ..style = PaintingStyle.fill;

    canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromCenter(center: earL, width: 4.5, height: 10),
            const Radius.circular(2)),
        earPaint);

    canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromCenter(center: earR, width: 4.5, height: 10),
            const Radius.circular(2)),
        earPaint);

    // Nose pointer facing forward/up
    final nosePaint = Paint()
      ..color = isEnabled ? primaryColor.withValues(alpha: 0.7) : Colors.white24
      ..style = PaintingStyle.fill;
    final nosePath = Path()
      ..moveTo(headCenter.dx - 3, headCenter.dy - 12)
      ..lineTo(headCenter.dx, headCenter.dy - 17)
      ..lineTo(headCenter.dx + 3, headCenter.dy - 12)
      ..close();
    canvas.drawPath(nosePath, nosePaint);
  }

  @override
  bool shouldRepaint(covariant _OpenStagePainter old) {
    return old.angleDegrees != angleDegrees ||
        old.gainDb != gainDb ||
        old.mix != mix ||
        old.isEnabled != isEnabled ||
        old.primaryColor != primaryColor ||
        old.animValue != animValue;
  }
}
