import 'dart:math' as math;
import 'package:material_ui/material_ui.dart';
import 'package:sautiflow/sautiflow.dart';
import '../services/app_theme_service.dart';

class DynamicBassPresetParams {
  final String name;
  final double xLow;
  final double yLow;
  final double yHigh;
  final double sideGainX;
  final double sideGainY;

  const DynamicBassPresetParams(
    this.name,
    this.xLow,
    this.yLow,
    this.yHigh,
    this.sideGainX,
    this.sideGainY,
  );
}

const List<DynamicBassPresetParams> kDynamicBassPresets = [
  DynamicBassPresetParams('Smooth Natural Sub', 140.0, 40.0, 65.0, 0.10, 0.80),
  DynamicBassPresetParams('Punchy In-Ear', 180.0, 55.0, 85.0, 0.10, 0.70),
  DynamicBassPresetParams('Warm Over-Ear', 300.0, 60.0, 105.0, 0.15, 0.50),
  DynamicBassPresetParams('Deep Acoustic', 260.0, 50.0, 95.0, 0.20, 0.60),
  DynamicBassPresetParams('Wide Dynamic', 280.0, 45.0, 85.0, 0.30, 0.55),
  DynamicBassPresetParams('Sub-Bass Boom', 240.0, 38.0, 78.0, 0.10, 0.95),
  DynamicBassPresetParams('Tight Sub', 240.0, 45.0, 85.0, 0.10, 0.55),
  DynamicBassPresetParams('Solid Impact', 280.0, 50.0, 90.0, 0.20, 0.40),
  DynamicBassPresetParams('Clean Kick', 250.0, 55.0, 95.0, 0.20, 0.25),
  DynamicBassPresetParams('Rich Low-End', 320.0, 50.0, 95.0, 0.25, 0.60),
  DynamicBassPresetParams('Club PA Punch', 320.0, 45.0, 90.0, 0.30, 0.65),
  DynamicBassPresetParams('Basshead Heavy', 280.0, 55.0, 105.0, 0.20, 0.85),
  DynamicBassPresetParams('Resonant Rumble', 260.0, 40.0, 85.0, 0.15, 0.90),
  DynamicBassPresetParams('Cinema Sub', 260.0, 45.0, 90.0, 0.10, 0.85),
  DynamicBassPresetParams('Car Audio Slam', 280.0, 40.0, 85.0, 0.15, 0.80),
  DynamicBassPresetParams('Audiophile Reference', 220.0, 45.0, 85.0, 0.10, 0.65),
  DynamicBassPresetParams('Studio Monitor Lows', 240.0, 50.0, 95.0, 0.10, 0.55),
  DynamicBassPresetParams('Deep Sub Extension', 220.0, 35.0, 75.0, 0.05, 1.00),
  DynamicBassPresetParams('Ultimate Subwoofer', 260.0, 45.0, 95.0, 0.10, 0.90),
];

/// Analytical frequency response graph matching HarmonicBassDSP across all 6 modes.
class DynamicBassGraph extends StatelessWidget {
  final HarmonicBassProfile profile;
  final int preset;
  final double cutoffHz; // 30Hz - 160Hz Focus Frequency
  final double gainDb; // 0dB - 18dB Bass Gain (Mode 5)
  final double boost; // 0.0 - 1.0 Bass Power (Modes 0..4)
  final bool isEnabled;
  final double height;
  final Color? primaryColor;

  const DynamicBassGraph({
    super.key,
    required this.profile,
    this.preset = 18,
    required this.cutoffHz,
    required this.gainDb,
    required this.boost,
    this.isEnabled = true,
    this.height = 125.0,
    this.primaryColor,
  });

  @override
  Widget build(BuildContext context) {
    final effectivePrimary =
        primaryColor ?? AppThemeService.instance.currentData.primary;
    final cardBg = AppThemeService.instance.currentData.cardDark;

    return Container(
      height: height,
      margin: const EdgeInsets.symmetric(vertical: 8.0),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(12.0),
        border:
            Border.all(color: Colors.white.withValues(alpha: 0.1), width: 1.0),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12.0),
        child: CustomPaint(
          size: Size.infinite,
          painter: _DynamicBassPainter(
            profile: profile,
            preset: preset,
            cutoffHz: cutoffHz,
            gainDb: gainDb,
            boost: boost,
            isEnabled: isEnabled,
            primaryColor: effectivePrimary,
          ),
        ),
      ),
    );
  }
}

typedef _Complex = ({double re, double im});

_Complex _cAdd(_Complex a, _Complex b) => (re: a.re + b.re, im: a.im + b.im);
_Complex _cSub(_Complex a, _Complex b) => (re: a.re - b.re, im: a.im - b.im);
_Complex _cMul(_Complex a, _Complex b) =>
    (re: a.re * b.re - a.im * b.im, im: a.re * b.im + a.im * b.re);
_Complex _cDiv(_Complex a, _Complex b) {
  final d = math.max(1e-30, b.re * b.re + b.im * b.im);
  return (re: (a.re * b.re + a.im * b.im) / d, im: (a.im * b.re - a.re * b.im) / d);
}
_Complex _cScale(_Complex a, double s) => (re: a.re * s, im: a.im * s);
double _cAbs(_Complex a) => math.sqrt(a.re * a.re + a.im * a.im);

({ _Complex lp4, _Complex hp4, _Complex ap2 }) _evalLr4(
    double fc, double t, double fs) {
  final clampedFc = fc.clamp(15.0, fs * 0.45);
  final g = math.tan(math.pi * clampedFc / fs);
  const k = math.sqrt2;
  final den = (re: g * g - t * t, im: k * g * t);
  final lp2 = _cDiv((re: g * g, im: 0.0), den);
  final hp2 = _cDiv((re: -t * t, im: 0.0), den);
  final ap2 = _cDiv((re: g * g - t * t, im: -k * g * t), den);
  return (lp4: _cMul(lp2, lp2), hp4: _cMul(hp2, hp2), ap2: ap2);
}

_Complex _evalSvfBell(double fc, double gainDb, double q, double t, double fs) {
  if (gainDb.abs() < 0.005) return (re: 1.0, im: 0.0);
  final a = math.pow(10.0, gainDb / 40.0).toDouble();
  final g = math.tan(math.pi * fc.clamp(10.0, fs * 0.45) / fs);
  final k = 1.0 / (q * a);
  final num = (re: g * g - t * t, im: (a / q) * g * t);
  final den = (re: g * g - t * t, im: k * g * t);
  return _cDiv(num, den);
}

_Complex _evalSvfLowShelf(double fc, double gainDb, double q, double t, double fs) {
  if (gainDb.abs() < 0.005) return (re: 1.0, im: 0.0);
  final a = math.pow(10.0, gainDb / 40.0).toDouble();
  final g = math.tan(math.pi * fc.clamp(10.0, fs * 0.45) / fs) / math.sqrt(a);
  final k = 1.0 / q;
  final num = (re: a * a * g * g - t * t, im: k * a * g * t);
  final den = (re: g * g - t * t, im: k * g * t);
  return _cDiv(num, den);
}

_Complex _evalSvfLowPass(double fc, double q, double t, double fs) {
  final g = math.tan(math.pi * fc.clamp(10.0, fs * 0.45) / fs);
  final k = 1.0 / q;
  final den = (re: g * g - t * t, im: k * g * t);
  return _cDiv((re: g * g, im: 0.0), den);
}

_Complex _evalDcBlocker(double f, double fs) {
  final c = math.exp(-2.0 * math.pi * 18.0 / fs);
  final w = 2.0 * math.pi * f / fs;
  final zInv = (re: math.cos(w), im: -math.sin(w));
  final num = _cScale(_cSub((re: 1.0, im: 0.0), zInv), c);
  final den = _cSub((re: 1.0, im: 0.0), _cScale(zInv, c));
  return _cDiv(num, den);
}

class _DynamicBassPainter extends CustomPainter {
  final HarmonicBassProfile profile;
  final int preset;
  final double cutoffHz;
  final double gainDb;
  final double boost;
  final bool isEnabled;
  final Color primaryColor;

  _DynamicBassPainter({
    required this.profile,
    required this.preset,
    required this.cutoffHz,
    required this.gainDb,
    required this.boost,
    required this.isEnabled,
    required this.primaryColor,
  });

  static const double minFreq = 20.0;
  static const double maxFreq = 500.0;
  static const double minDb = -6.0;
  static const double maxDb = 18.0;
  static const int numPoints = 120;

  @override
  void paint(Canvas canvas, Size size) {
    final paddingLeft = 32.0;
    final paddingRight = 16.0;
    final paddingTop = 14.0;
    final paddingBottom = 18.0;

    final graphWidth = size.width - paddingLeft - paddingRight;
    final graphHeight = size.height - paddingTop - paddingBottom;
    if (graphWidth <= 0 || graphHeight <= 0) return;

    double freqToX(double f) {
      final clamped = f.clamp(minFreq, maxFreq);
      final logRatio =
          math.log(clamped / minFreq) / math.log(maxFreq / minFreq);
      return paddingLeft + logRatio * graphWidth;
    }

    double dbToY(double db) {
      final clamped = db.clamp(minDb, maxDb);
      final norm = (clamped - minDb) / (maxDb - minDb);
      return paddingTop + (1.0 - norm) * graphHeight;
    }

    final baselineY = dbToY(0.0);

    // 1. Draw Grid
    _drawGrid(canvas, paddingLeft, paddingTop, graphWidth, graphHeight);

    final bool inactive = !isEnabled ||
        (profile == HarmonicBassProfile.dynamicMultiPole
            ? gainDb < 0.05
            : boost < 0.005);

    if (inactive) {
      canvas.drawLine(
        Offset(paddingLeft, baselineY),
        Offset(paddingLeft + graphWidth, baselineY),
        Paint()
          ..color = primaryColor.withValues(alpha: 0.4)
          ..strokeWidth = 1.8,
      );
      return;
    }

    // 2. Pre-calculate logarithmic frequencies [20Hz, 500Hz]
    final freqs = List<double>.generate(numPoints, (i) {
      return minFreq * math.pow(maxFreq / minFreq, i / (numPoints - 1));
    });

    const double fs = 48000.0;
    final fc = cutoffHz.clamp(30.0, 160.0);
    final b = boost.clamp(0.0, 1.0);
    final gDb = gainDb.clamp(0.0, 18.0);

    // 3. Compute exact transfer curve for the active HarmonicBassProfile
    final curveDbs = <double>[];
    double peakFreq = fc;
    double peakDb = 0.0;

    for (int i = 0; i < numPoints; i++) {
      final f = freqs[i];
      final t = math.tan(math.pi * f / fs);
      double pointDb = 0.0;

      switch (profile) {
        case HarmonicBassProfile.dynamicMultiPole:
          final p = kDynamicBassPresets[
              preset.clamp(0, kDynamicBassPresets.length - 1)];
          final yl = p.yLow.clamp(20.0, 140.0);
          final yh = math.max(p.yHigh, yl + 15.0).clamp(35.0, 300.0);
          final xl = math.max(p.xLow, yh + 20.0).clamp(60.0, 1500.0);

          final bassGain = math.pow(10.0, gDb / 20.0).toDouble();
          final drive = math.max(0.0, bassGain - 1.0);
          final gSub = 1.0 + drive * (0.30 + 0.70 * p.sideGainY);
          final gPunch = 1.0 + drive;
          final gUbass = 1.0 + drive * (0.40 * p.sideGainX);

          final cXl = _evalLr4(xl, t, fs);
          final cYh = _evalLr4(yh, t, fs);
          final cYl = _evalLr4(yl, t, fs);

          final bSub = _cMul(cXl.lp4, _cMul(cYh.lp4, cYl.lp4));
          final bPunch = _cMul(cXl.lp4, _cMul(cYh.lp4, cYl.hp4));
          final bUbass = _cMul(cXl.lp4, _cMul(cYh.hp4, cYl.ap2));
          final lo = _cAdd(
            _cAdd(_cScale(bSub, gSub), _cScale(bPunch, gPunch)),
            _cScale(bUbass, gUbass),
          );
          final up = _cMul(cYh.ap2, _cMul(cYl.ap2, cXl.hp4));
          final hTot = _cAdd(lo, up);
          pointDb = 20.0 * math.log(math.max(_cAbs(hTot), 1e-6)) / math.ln10;
          break;

        case HarmonicBassProfile.naturalBass:
        case HarmonicBassProfile.pureBass:
          final lp = _evalSvfLowPass(fc, 0.53, t, fs);
          final dc = _evalDcBlocker(f, fs);
          final bass = _cScale(_cMul(lp, dc), b * 3.5);
          final hTot = _cAdd((re: 1.0, im: 0.0), bass);
          pointDb = 20.0 * math.log(math.max(_cAbs(hTot), 1e-6)) / math.ln10;
          break;

        case HarmonicBassProfile.subwoofer:
          final subFc2 = (fc * 1.8).clamp(60.0, 180.0);
          final p1 = _evalSvfBell(fc, b * 16.0, 0.95, t, fs);
          final p2 = _evalSvfBell(subFc2, b * 8.0, 1.4, t, fs);
          final lpf = _evalSvfLowPass(380.0, 0.65, t, fs);
          final diff = _cSub(_cMul(p1, p2), (re: 1.0, im: 0.0));
          final injected = _cScale(_cMul(_cMul(diff, lpf), _evalDcBlocker(f, fs)), 0.6);
          final hTot = _cAdd((re: 1.0, im: 0.0), injected);
          pointDb = 20.0 * math.log(math.max(_cAbs(hTot), 1e-6)) / math.ln10;
          break;

        case HarmonicBassProfile.harmonicExciter:
          final lp = _evalSvfLowPass(fc, 0.7071, t, fs);
          final fundMag = _cAbs(lp);
          pointDb = 20.0 * math.log(math.max(1.0 + b * 1.5 * fundMag, 1e-6)) / math.ln10;
          break;

        case HarmonicBassProfile.pultecDeep:
          final scoopFc = (fc * 5.0).clamp(200.0, 400.0);
          final scoop = _evalSvfBell(scoopFc, -b * 4.5, 1.2, t, fs);
          final shelf = _evalSvfLowShelf(fc, b * 12.0, 0.70710678, t, fs);
          final boostInj = _cScale(
              _cMul(_cSub(shelf, (re: 1.0, im: 0.0)), _evalDcBlocker(f, fs)),
              0.8);
          final hTot = _cAdd(scoop, boostInj);
          pointDb = 20.0 * math.log(math.max(_cAbs(hTot), 1e-6)) / math.ln10;
          break;
      }

      final clampedDb = pointDb.clamp(minDb, maxDb);
      curveDbs.add(clampedDb);
      if (clampedDb > peakDb) {
        peakDb = clampedDb;
        peakFreq = f;
      }
    }

    // 4. Draw Gradient Fill Under Bass Curve
    final curvePath = Path();
    curvePath.moveTo(freqToX(freqs[0]), dbToY(curveDbs[0]));
    for (int i = 1; i < numPoints; i++) {
      curvePath.lineTo(freqToX(freqs[i]), dbToY(curveDbs[i]));
    }

    final fillPath = Path.from(curvePath);
    fillPath.lineTo(freqToX(freqs.last), baselineY);
    fillPath.lineTo(freqToX(freqs.first), baselineY);
    fillPath.close();

    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          primaryColor.withValues(alpha: 0.30),
          primaryColor.withValues(alpha: 0.02),
        ],
      ).createShader(
          Rect.fromLTWH(paddingLeft, paddingTop, graphWidth, graphHeight))
      ..style = PaintingStyle.fill;
    canvas.drawPath(fillPath, fillPaint);

    // 5. Draw Glowing Resonance Curve
    final glowPaint = Paint()
      ..color = primaryColor.withValues(alpha: 0.4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.5
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3.5);
    canvas.drawPath(curvePath, glowPaint);

    final strokePaint = Paint()
      ..color = primaryColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(curvePath, strokePaint);

    // 6. Draw Harmonic Overtones ONLY in HarmonicExciter mode
    if (profile == HarmonicBassProfile.harmonicExciter) {
      final h2Freq = fc * 2.0;
      final h3Freq = fc * 3.0;
      final refDb = (b * 12.0).clamp(1.0, maxDb);

      void drawHarmonicBar(double freq, String label, double gainRatio) {
        if (freq <= maxFreq) {
          final barX = freqToX(freq);
          final barHeight = refDb * gainRatio;
          final barTopY = dbToY(barHeight);

          canvas.drawLine(
            Offset(barX, baselineY),
            Offset(barX, barTopY),
            Paint()
              ..color = const Color(0xFF00E5FF).withValues(alpha: 0.7)
              ..strokeWidth = 2.0
              ..strokeCap = StrokeCap.round,
          );
          canvas.drawCircle(
            Offset(barX, barTopY),
            3.5,
            Paint()..color = const Color(0xFF00E5FF),
          );

          final tp = TextPainter(
            text: TextSpan(
              text: label,
              style: const TextStyle(
                color: Color(0xFF00E5FF),
                fontSize: 8.5,
                fontWeight: FontWeight.bold,
                fontFamily: 'monospace',
              ),
            ),
            textDirection: TextDirection.ltr,
          )..layout();
          tp.paint(canvas, Offset(barX - tp.width / 2, barTopY - 12));
        }
      }

      drawHarmonicBar(h2Freq, '2f', 0.70);
      drawHarmonicBar(h3Freq, '3f', 0.30);
    }

    // 7. Peak Handle
    final peakX = freqToX(peakFreq);
    final peakY = dbToY(peakDb);

    final dashPaint = Paint()
      ..color = primaryColor.withValues(alpha: 0.3)
      ..strokeWidth = 1.0;
    double dy = peakY;
    while (dy < baselineY) {
      canvas.drawLine(
        Offset(peakX, dy),
        Offset(peakX, math.min(dy + 3, baselineY)),
        dashPaint,
      );
      dy += 6;
    }

    canvas.drawCircle(
      Offset(peakX, peakY),
      6.5,
      Paint()..color = primaryColor.withValues(alpha: 0.3),
    );
    canvas.drawCircle(
      Offset(peakX, peakY),
      3.5,
      Paint()..color = Colors.white,
    );

    // 8. Info Banner
    final isDynamic = profile == HarmonicBassProfile.dynamicMultiPole;
    final pObj = kDynamicBassPresets[preset.clamp(0, kDynamicBassPresets.length - 1)];
    final infoSpan = TextSpan(
      children: [
        TextSpan(
          text: isDynamic ? '${pObj.name}  ' : 'Focus: ${fc.toInt()}Hz  ',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 9.0,
            fontWeight: FontWeight.bold,
            fontFamily: 'monospace',
          ),
        ),
        TextSpan(
          text: '+${peakDb.toStringAsFixed(1)}dB  ',
          style: TextStyle(
            color: primaryColor,
            fontSize: 9.0,
            fontWeight: FontWeight.bold,
            fontFamily: 'monospace',
          ),
        ),
        TextSpan(
          text: isDynamic
              ? 'Sub ${pObj.yLow.toInt()}-${pObj.yHigh.toInt()}Hz'
              : 'Power: ${(b * 100).toInt()}%',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.6),
            fontSize: 8.5,
            fontFamily: 'monospace',
          ),
        ),
      ],
    );
    final tp = TextPainter(text: infoSpan, textDirection: TextDirection.ltr)
      ..layout();
    tp.paint(canvas, Offset(paddingLeft + 6, paddingTop + 2));
  }

  void _drawGrid(Canvas canvas, double paddingLeft, double paddingTop,
      double graphWidth, double graphHeight) {
    final gridLinePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.06)
      ..strokeWidth = 1.0;

    final baselinePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.2)
      ..strokeWidth = 1.0;

    final textStyle = TextStyle(
      color: Colors.white.withValues(alpha: 0.4),
      fontSize: 8.5,
      fontFamily: 'monospace',
    );

    // Gain ticks: -6dB, 0dB, +6dB, +12dB, +18dB
    final dbTicks = [-6.0, 0.0, 6.0, 12.0, 18.0];
    for (final db in dbTicks) {
      final norm = (db - minDb) / (maxDb - minDb);
      final y = paddingTop + (1.0 - norm) * graphHeight;

      canvas.drawLine(
        Offset(paddingLeft, y),
        Offset(paddingLeft + graphWidth, y),
        db == 0.0 ? baselinePaint : gridLinePaint,
      );

      final label = '${db > 0 ? '+' : ''}${db.toInt()}';
      final tp = TextPainter(
        text: TextSpan(text: label, style: textStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(paddingLeft - tp.width - 4, y - tp.height / 2));
    }

    // Frequency ticks: 20Hz, 40Hz, 80Hz, 150Hz, 300Hz, 500Hz
    final freqTicks = [
      {'f': 20.0, 'l': '20'},
      {'f': 40.0, 'l': '40'},
      {'f': 80.0, 'l': '80'},
      {'f': 150.0, 'l': '150'},
      {'f': 300.0, 'l': '300'},
      {'f': 500.0, 'l': '500Hz'},
    ];

    for (final tick in freqTicks) {
      final freq = tick['f'] as double;
      final label = tick['l'] as String;

      final logRatio = math.log(freq / minFreq) / math.log(maxFreq / minFreq);
      final x = paddingLeft + logRatio * graphWidth;

      canvas.drawLine(
        Offset(x, paddingTop),
        Offset(x, paddingTop + graphHeight),
        gridLinePaint,
      );

      final tp = TextPainter(
        text: TextSpan(text: label, style: textStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(x - tp.width / 2, paddingTop + graphHeight + 3));
    }
  }

  @override
  bool shouldRepaint(covariant _DynamicBassPainter oldDelegate) {
    return oldDelegate.profile != profile ||
        oldDelegate.preset != preset ||
        oldDelegate.cutoffHz != cutoffHz ||
        oldDelegate.gainDb != gainDb ||
        oldDelegate.boost != boost ||
        oldDelegate.isEnabled != isEnabled ||
        oldDelegate.primaryColor != primaryColor;
  }
}
