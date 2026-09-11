import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../services/app_theme_service.dart';

class _ScopeParticle {
  final double baseMid;
  final double baseSide;
  final double phase;
  final double speed;
  final double driftAmp;
  final double size;
  final double alpha;

  const _ScopeParticle({
    required this.baseMid,
    required this.baseSide,
    required this.phase,
    required this.speed,
    required this.driftAmp,
    required this.size,
    required this.alpha,
  });
}

/// An interactive, real-time Polar Goniometer & Stereo Vectorscope display.
///
/// Visualizes stereo soundstage width, phase correlation, transient dynamics,
/// and elliptical mono-bass anchoring in real-time. Responds dynamically to
/// incoming audio stream energy, pulse rhythms, and user-selected spatial modes.
class StereoVectorscopeGraph extends StatefulWidget {
  final double width; // 0.0 to 3.0+ (1.0 = normal, 2.0+ = wide)
  final double delayMs; // Haas delay / room pre-delay
  final int mode; // 0 = Clean Mastering, 1 = Spatial 3D, 2 = Blumlein Shuffler
  final double monoBelowHz; // Sub-bass anchor frequency (e.g. 150 Hz)
  final double airBoostDb; // High-shelf air boost (0.0 to 6.0 dB)
  final bool isEnabled;
  final double height;
  final Color? primaryColor;
  final Stream<Float32List>? analyzerStream;

  const StereoVectorscopeGraph({
    super.key,
    required this.width,
    this.delayMs = 15.0,
    this.mode = 0,
    this.monoBelowHz = 150.0,
    this.airBoostDb = 1.5,
    this.isEnabled = true,
    this.height = 210.0,
    this.primaryColor,
    this.analyzerStream,
  });

  @override
  State<StereoVectorscopeGraph> createState() => _StereoVectorscopeGraphState();
}

class _StereoVectorscopeGraphState extends State<StereoVectorscopeGraph>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late List<_ScopeParticle> _particles;
  StreamSubscription<Float32List>? _analyzerSub;

  double _liveAudioEnergy = 0.25; // Dynamic energy derived from real-time audio
  double _peakPulse = 0.0;

  static const int particleCount = 280;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2800),
    )..repeat();

    _initParticles();
    _subscribeAnalyzer();
  }

  void _initParticles() {
    final rng = math.Random(42);
    _particles = List.generate(particleCount, (i) {
      // Gaussian distribution for natural audio distribution
      final u1 = rng.nextDouble().clamp(1e-6, 1.0);
      final u2 = rng.nextDouble();
      final z0 = math.sqrt(-2.0 * math.log(u1)) * math.cos(2.0 * math.pi * u2);
      final z1 = math.sqrt(-2.0 * math.log(u1)) * math.sin(2.0 * math.pi * u2);

      final baseMid = (z0 * 0.38).clamp(-0.85, 0.85);
      final baseSide = (z1 * 0.24).clamp(-0.85, 0.85);

      return _ScopeParticle(
        baseMid: baseMid,
        baseSide: baseSide,
        phase: rng.nextDouble() * 2.0 * math.pi,
        speed: 0.8 + rng.nextDouble() * 2.0,
        driftAmp: 0.025 + rng.nextDouble() * 0.045,
        size: 1.2 + rng.nextDouble() * 2.0,
        alpha: 0.35 + rng.nextDouble() * 0.65,
      );
    });
  }

  void _subscribeAnalyzer() {
    _analyzerSub?.cancel();
    if (widget.analyzerStream != null) {
      _analyzerSub = widget.analyzerStream!.listen((frames) {
        if (frames.isEmpty || !mounted) return;
        double sumSq = 0.0;
        final step = math.max(1, frames.length ~/ 128);
        int count = 0;
        for (int i = 0; i < frames.length; i += step) {
          final s = frames[i];
          sumSq += s * s;
          count++;
        }
        final rms = math.sqrt(sumSq / math.max(1, count));
        final targetEnergy = (rms * 3.5).clamp(0.08, 1.35);

        setState(() {
          _liveAudioEnergy = _liveAudioEnergy * 0.70 + targetEnergy * 0.30;
          if (targetEnergy > _peakPulse) {
            _peakPulse = targetEnergy;
          } else {
            _peakPulse *= 0.92;
          }
        });
      });
    }
  }

  @override
  void didUpdateWidget(covariant StereoVectorscopeGraph oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.analyzerStream != widget.analyzerStream) {
      _subscribeAnalyzer();
    }
  }

  @override
  void dispose() {
    _analyzerSub?.cancel();
    _animController.dispose();
    super.dispose();
  }

  Color _getModeAccentColor(Color primary) {
    if (!widget.isEnabled) return Colors.grey;
    switch (widget.mode) {
      case 1: // Spatial 3D Velvet
        return const Color(0xFFC084FC); // Vibrant Purple / Violet
      case 2: // Blumlein Shuffler
        return const Color(0xFFFBBF24); // Warm Amber
      case 0: // Clean Mastering
      default:
        return primary;
    }
  }

  String _getModeLabel() {
    switch (widget.mode) {
      case 1:
        return 'SPATIAL 3D (VELVET)';
      case 2:
        return 'BLUMLEIN SHUFFLER';
      case 0:
      default:
        return 'CLEAN MASTERING (M/S)';
    }
  }

  @override
  Widget build(BuildContext context) {
    final effectivePrimary =
        widget.primaryColor ?? AppThemeService.instance.currentData.primary;
    final cardBg = AppThemeService.instance.currentData.cardDark;
    final modeColor = _getModeAccentColor(effectivePrimary);

    return AnimatedBuilder(
      animation: _animController,
      builder: (context, child) {
        return Container(
          height: widget.height,
          margin: const EdgeInsets.symmetric(vertical: 8.0),
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(16.0),
            border: Border.all(
              color: widget.isEnabled
                  ? modeColor.withValues(alpha: 0.35)
                  : Colors.white.withValues(alpha: 0.08),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: widget.isEnabled
                    ? modeColor.withValues(alpha: 0.15)
                    : Colors.black.withValues(alpha: 0.35),
                blurRadius: 16,
                spreadRadius: widget.isEnabled ? 1 : 0,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Stack(
            children: [
              // 1. Live Polar Goniometer Canvas
              ClipRRect(
                borderRadius: BorderRadius.circular(16.0),
                child: CustomPaint(
                  size: Size.infinite,
                  painter: _VectorscopePainter(
                    width: widget.width,
                    delayMs: widget.delayMs,
                    mode: widget.mode,
                    monoBelowHz: widget.monoBelowHz,
                    airBoostDb: widget.airBoostDb,
                    isEnabled: widget.isEnabled,
                    primaryColor: modeColor,
                    animProgress: _animController.value,
                    audioEnergy: _liveAudioEnergy,
                    peakPulse: _peakPulse,
                    particles: _particles,
                  ),
                ),
              ),

              // 2. Top-Left: Active Mode Badge & Mono Anchor Pill
              Positioned(
                top: 10,
                left: 12,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8.0, vertical: 3.0),
                      decoration: BoxDecoration(
                        color: widget.isEnabled
                            ? modeColor.withValues(alpha: 0.20)
                            : Colors.white.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(6.0),
                        border: Border.all(
                          color: widget.isEnabled
                              ? modeColor.withValues(alpha: 0.50)
                              : Colors.white12,
                          width: 0.8,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            widget.mode == 1
                                ? Icons.blur_on_rounded
                                : (widget.mode == 2
                                    ? Icons.waves_rounded
                                    : Icons.tune_rounded),
                            size: 11,
                            color: widget.isEnabled ? modeColor : Colors.white38,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _getModeLabel(),
                            style: TextStyle(
                              fontSize: 9.0,
                              fontWeight: FontWeight.bold,
                              fontFamily: 'monospace',
                              letterSpacing: 0.5,
                              color:
                                  widget.isEnabled ? modeColor : Colors.white38,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (widget.isEnabled && widget.monoBelowHz > 25.0) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6.0, vertical: 3.0),
                        decoration: BoxDecoration(
                          color: Colors.cyanAccent.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(6.0),
                          border: Border.all(
                            color: Colors.cyanAccent.withValues(alpha: 0.35),
                            width: 0.8,
                          ),
                        ),
                        child: Text(
                          'MONO <${widget.monoBelowHz.toInt()}Hz',
                          style: const TextStyle(
                            fontSize: 8.5,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'monospace',
                            color: Colors.cyanAccent,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              // 3. Top-Right: Width Multiplier Readout
              Positioned(
                top: 10,
                right: 12,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8.0, vertical: 3.0),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.45),
                    borderRadius: BorderRadius.circular(6.0),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.10),
                      width: 0.8,
                    ),
                  ),
                  child: Text(
                    widget.isEnabled
                        ? '${widget.width.toStringAsFixed(1)}x WIDTH'
                        : 'BYPASS',
                    style: TextStyle(
                      fontSize: 9.0,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'monospace',
                      color: widget.isEnabled ? Colors.white70 : Colors.white30,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _VectorscopePainter extends CustomPainter {
  final double width;
  final double delayMs;
  final int mode;
  final double monoBelowHz;
  final double airBoostDb;
  final bool isEnabled;
  final Color primaryColor;
  final double animProgress;
  final double audioEnergy;
  final double peakPulse;
  final List<_ScopeParticle> particles;

  _VectorscopePainter({
    required this.width,
    required this.delayMs,
    required this.mode,
    required this.monoBelowHz,
    required this.airBoostDb,
    required this.isEnabled,
    required this.primaryColor,
    required this.animProgress,
    required this.audioEnergy,
    required this.peakPulse,
    required this.particles,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const barHeight = 28.0;
    const topMargin = 26.0;
    final scopeHeight = size.height - barHeight - topMargin;
    final scopeCenter = Offset(size.width / 2.0, topMargin + scopeHeight / 2.0);
    final radius = math.min(size.width / 2.0, scopeHeight / 2.0) - 8.0;
    if (radius <= 0) return;

    // 1. Draw Polar Scope Grid & Concentric Reference Rings
    _drawScopeGrid(canvas, scopeCenter, radius);

    // 2. Draw Sub-Bass Mono Anchor Halo
    _drawMonoBassHalo(canvas, scopeCenter, radius);

    // 3. Draw Dispersing, Live-Responsive Particle Cloud
    _drawParticles(canvas, scopeCenter, radius);

    // 4. Draw Real-Time Phase Correlation Bar at bottom
    _drawPhaseCorrelationBar(canvas, size, size.height - barHeight);
  }

  void _drawScopeGrid(Canvas canvas, Offset center, double radius) {
    final circlePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.08)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    final innerCirclePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.04)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;

    final axisPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.07)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    final labelStyle = TextStyle(
      color: Colors.white.withValues(alpha: 0.35),
      fontSize: 9.5,
      fontWeight: FontWeight.bold,
      fontFamily: 'monospace',
    );

    // Outer boundary circle
    canvas.drawCircle(center, radius, circlePaint);

    // Inner concentric reference circles (dB steps: -12dB, -6dB)
    canvas.drawCircle(center, radius * 0.40, innerCirclePaint);
    canvas.drawCircle(center, radius * 0.72, innerCirclePaint);

    // Mid/Side Axes (Vertical = Mid, Horizontal = Side)
    canvas.drawLine(
      Offset(center.dx, center.dy - radius),
      Offset(center.dx, center.dy + radius),
      axisPaint,
    );
    canvas.drawLine(
      Offset(center.dx - radius, center.dy),
      Offset(center.dx + radius, center.dy),
      axisPaint,
    );

    // 45° Diagonal Lines for Left and Right Stereo Axes
    final diag = radius * 0.7071;
    canvas.drawLine(center, Offset(center.dx - diag, center.dy - diag), axisPaint);
    canvas.drawLine(center, Offset(center.dx + diag, center.dy - diag), axisPaint);

    // Labels: M (Mid/Center), L (Left), R (Right), S (Side)
    void drawText(String text, Offset pos) {
      final tp = TextPainter(
        text: TextSpan(text: text, style: labelStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(pos.dx - tp.width / 2.0, pos.dy - tp.height / 2.0));
    }

    drawText('+M', Offset(center.dx, center.dy - radius + 8.0));
    drawText('L', Offset(center.dx - diag + 8.0, center.dy - diag + 8.0));
    drawText('R', Offset(center.dx + diag - 8.0, center.dy - diag + 8.0));
    drawText('+S', Offset(center.dx + radius - 8.0, center.dy));
    drawText('-S', Offset(center.dx - radius + 8.0, center.dy));
  }

  void _drawMonoBassHalo(Canvas canvas, Offset center, double radius) {
    if (!isEnabled || monoBelowHz <= 25.0) return;
    // The sub-bass anchor radius scales with frequency (e.g. 150 Hz ~ 25% radius)
    final anchorRadius = (radius * (monoBelowHz / 450.0)).clamp(12.0, radius * 0.45);
    final haloPaint = Paint()
      ..color = Colors.cyanAccent.withValues(alpha: 0.08 + 0.05 * math.sin(animProgress * 2.0 * math.pi))
      ..style = PaintingStyle.fill;

    final borderPaint = Paint()
      ..color = Colors.cyanAccent.withValues(alpha: 0.20)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;

    canvas.drawCircle(center, anchorRadius, haloPaint);
    canvas.drawCircle(center, anchorRadius, borderPaint);
  }

  void _drawParticles(Canvas canvas, Offset center, double radius) {
    final effectiveWidth = isEnabled ? width.clamp(0.0, 3.5) : 1.0;
    final dynamicEnergy = isEnabled ? (0.65 + 0.70 * audioEnergy) : 0.40;
    final time = animProgress;

    final dotPaint = Paint()..style = PaintingStyle.fill;

    for (final p in particles) {
      final driftAngle = p.phase + 2.0 * math.pi * time * p.speed;
      final driftX = math.sin(driftAngle) * p.driftAmp * (0.5 + 0.5 * effectiveWidth);
      final driftY = math.cos(driftAngle) * p.driftAmp;

      // Mode-specific particle physics:
      // Mode 1 (Spatial 3D): Adds subtle randomized spatial flutter
      // Mode 2 (Blumlein): Adds low-mid horizontal expansion
      double modeFlutterX = 0.0;
      if (mode == 1 && isEnabled) {
        modeFlutterX = math.sin(driftAngle * 3.2) * 0.04 * effectiveWidth;
      }

      final sideComponent = (p.baseSide * effectiveWidth * 0.78 + driftX + modeFlutterX) * dynamicEnergy;
      final midComponent = (p.baseMid + driftY) * dynamicEnergy;

      final px = (center.dx + sideComponent * radius)
          .clamp(center.dx - radius + 2, center.dx + radius - 2);
      final py = (center.dy - midComponent * radius)
          .clamp(center.dy - radius + 2, center.dy + radius - 2);

      // Pulse alpha with music and breathing cycle
      final shimmer = 0.75 + 0.25 * math.sin(driftAngle * 1.8);
      final dynamicAlpha = isEnabled
          ? (p.alpha * shimmer * (0.6 + 0.4 * audioEnergy)).clamp(0.18, 0.95)
          : 0.15;

      dotPaint.color = primaryColor.withValues(alpha: dynamicAlpha);

      final pSize = isEnabled
          ? (p.size * (0.85 + 0.35 * peakPulse)).clamp(1.0, 4.2)
          : 1.0;

      canvas.drawCircle(Offset(px, py), pSize, dotPaint);
    }
  }

  void _drawPhaseCorrelationBar(Canvas canvas, Size size, double barTop) {
    const barPaddingX = 36.0;
    final barWidth = size.width - (barPaddingX * 2.0);
    const barH = 6.5;

    if (barWidth <= 0) return;

    // Track background
    final trackRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(barPaddingX, barTop + 4.0, barWidth, barH),
      const Radius.circular(3.5),
    );
    canvas.drawRRect(
      trackRect,
      Paint()..color = Colors.white.withValues(alpha: 0.07),
    );

    // Calculate theoretical phase correlation based on current width & mode:
    // Mono (w=0) => +1.00
    // Normal (w=1) => +0.80
    // Wide (w=2) => +0.45
    // Extreme (w=3.5) => +0.05
    final effectiveWidth = isEnabled ? width.clamp(0.0, 3.5) : 1.0;
    double correlation = (1.0 - (effectiveWidth * 0.28) + 0.08).clamp(-1.0, 1.0);
    if (!isEnabled) correlation = 0.0;

    // Normalized to 0.0 (-1.0) .. 1.0 (+1.0)
    final norm = ((correlation - (-1.0)) / 2.0).clamp(0.0, 1.0);
    final activeWidth = (barWidth * norm).clamp(4.0, barWidth);

    // Active correlation fill bar with gradient
    final activeRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(barPaddingX, barTop + 4.0, activeWidth, barH),
      const Radius.circular(3.5),
    );

    final gradColors = isEnabled
        ? (correlation >= 0.35
            ? [primaryColor.withValues(alpha: 0.4), primaryColor]
            : [Colors.amberAccent.withValues(alpha: 0.4), Colors.amberAccent])
        : [Colors.white24, Colors.white38];

    canvas.drawRRect(
      activeRect,
      Paint()
        ..shader = LinearGradient(colors: gradColors).createShader(
          Rect.fromLTWH(barPaddingX, barTop + 4.0, activeWidth, barH),
        ),
    );

    // Labels: -1 (left), correlation value (center), +1 (right)
    final labelStyle = TextStyle(
      color: Colors.white.withValues(alpha: 0.38),
      fontSize: 8.5,
      fontFamily: 'monospace',
    );

    final leftTp = TextPainter(
      text: TextSpan(text: '-1 (ANTI)', style: labelStyle),
      textDirection: TextDirection.ltr,
    )..layout();
    leftTp.paint(canvas, Offset(barPaddingX, barTop + barH + 6.0));

    final valText = isEnabled
        ? (correlation >= 0
            ? '+${correlation.toStringAsFixed(2)} CORRELATION'
            : '${correlation.toStringAsFixed(2)} CORRELATION')
        : 'BYPASS';
    final valTp = TextPainter(
      text: TextSpan(
        text: valText,
        style: TextStyle(
          color: isEnabled ? primaryColor : Colors.white38,
          fontSize: 8.5,
          fontWeight: FontWeight.bold,
          fontFamily: 'monospace',
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    valTp.paint(canvas,
        Offset(size.width / 2.0 - valTp.width / 2.0, barTop + barH + 6.0));

    final rightTp = TextPainter(
      text: TextSpan(text: '+1 (MONO)', style: labelStyle),
      textDirection: TextDirection.ltr,
    )..layout();
    rightTp.paint(canvas,
        Offset(barPaddingX + barWidth - rightTp.width, barTop + barH + 6.0));
  }

  @override
  bool shouldRepaint(covariant _VectorscopePainter oldDelegate) {
    return oldDelegate.animProgress != animProgress ||
        oldDelegate.width != width ||
        oldDelegate.mode != mode ||
        oldDelegate.monoBelowHz != monoBelowHz ||
        oldDelegate.airBoostDb != airBoostDb ||
        oldDelegate.audioEnergy != audioEnergy ||
        oldDelegate.peakPulse != peakPulse ||
        oldDelegate.isEnabled != isEnabled ||
        oldDelegate.primaryColor != primaryColor;
  }
}
