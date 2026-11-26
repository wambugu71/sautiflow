import 'dart:math' as math;
import 'package:material_ui/material_ui.dart';
import 'package:sautiflow/sautiflow.dart';
import '../services/app_theme_service.dart';

class DynamicSystemPresetParams {
  final String name;
  final double xLow;
  final double xHigh;
  final double yLow;
  final double yHigh;
  final double sideGainX;
  final double sideGainY;
  final double maxDrive;

  const DynamicSystemPresetParams(
    this.name,
    this.xLow,
    this.xHigh,
    this.yLow,
    this.yHigh,
    this.sideGainX,
    this.sideGainY,
    this.maxDrive,
  );
}

const List<DynamicSystemPresetParams> kDynamicSystemPresets = [
  DynamicSystemPresetParams('In-Ear Earbuds', 180.0, 5800.0, 55.0, 80.0, 0.10, 0.70, 2.8),
  DynamicSystemPresetParams('Over-Ear Headphones', 300.0, 5600.0, 60.0, 105.0, 0.10, 0.50, 2.6),
  DynamicSystemPresetParams('Studio Reference', 140.0, 6200.0, 40.0, 60.0, 0.10, 0.80, 2.0),
  DynamicSystemPresetParams('Desktop Speakers', 280.0, 6200.0, 45.0, 85.0, 0.15, 0.25, 3.0),
  DynamicSystemPresetParams('Club Subwoofer', 260.0, 6200.0, 55.0, 110.0, 0.10, 0.75, 3.8),
  DynamicSystemPresetParams('Pure Dynamic', 320.0, 6200.0, 50.0, 90.0, 0.30, 0.45, 3.2),
  DynamicSystemPresetParams('Audiophile Open-Back', 220.0, 6200.0, 45.0, 85.0, 0.10, 0.65, 2.1),
  DynamicSystemPresetParams('Studio Monitor Lows', 240.0, 6200.0, 50.0, 95.0, 0.10, 0.55, 2.3),
  DynamicSystemPresetParams('Cinema Sub Slam', 260.0, 6200.0, 45.0, 90.0, 0.10, 0.85, 3.6),
  DynamicSystemPresetParams('Car Audio Bass', 280.0, 6200.0, 40.0, 85.0, 0.15, 0.80, 3.5),
  DynamicSystemPresetParams('Deep Acoustic Warmth', 300.0, 5400.0, 55.0, 105.0, 0.25, 0.50, 2.5),
  DynamicSystemPresetParams('Clean Kick Drum', 250.0, 6200.0, 55.0, 95.0, 0.20, 0.25, 2.9),
  DynamicSystemPresetParams('Resonant Rumble', 260.0, 6200.0, 40.0, 85.0, 0.15, 0.90, 3.7),
  DynamicSystemPresetParams('Sub-Bass Boom', 240.0, 6200.0, 38.0, 78.0, 0.10, 0.95, 4.0),
  DynamicSystemPresetParams('Solid Impact', 280.0, 6200.0, 50.0, 90.0, 0.20, 0.40, 3.1),
  DynamicSystemPresetParams('Rich Low-End', 320.0, 6200.0, 50.0, 95.0, 0.25, 0.60, 3.2),
  DynamicSystemPresetParams('Club PA Punch', 320.0, 6200.0, 45.0, 90.0, 0.30, 0.65, 3.5),
  DynamicSystemPresetParams('Deep Sub Extension', 220.0, 6200.0, 35.0, 75.0, 0.05, 1.00, 3.8),
  DynamicSystemPresetParams('Ultimate Subwoofer', 260.0, 6200.0, 45.0, 95.0, 0.10, 0.90, 4.2),
];

/// Exact analytical 5-band LR4 transfer simulation graph for Dynamic System.
class DynamicSystemGraph extends StatelessWidget {
  final TransducerProfile profile;
  final double strength; // 0.0 to 1.0 (Dynamic Drive)
  final bool isEnabled;
  final double height;
  final Color? primaryColor;
  final double? customXLow;
  final double? customXHigh;
  final double? customYLow;
  final double? customYHigh;
  final double? customSideGainX;
  final double? customSideGainY;
  final double? customBassGain;

  const DynamicSystemGraph({
    super.key,
    required this.profile,
    required this.strength,
    this.isEnabled = true,
    this.height = 120.0,
    this.primaryColor,
    this.customXLow,
    this.customXHigh,
    this.customYLow,
    this.customYHigh,
    this.customSideGainX,
    this.customSideGainY,
    this.customBassGain,
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
          painter: _DynamicSystemPainter(
            profile: profile,
            strength: strength,
            isEnabled: isEnabled,
            primaryColor: effectivePrimary,
            customXLow: customXLow,
            customXHigh: customXHigh,
            customYLow: customYLow,
            customYHigh: customYHigh,
            customSideGainX: customSideGainX,
            customSideGainY: customSideGainY,
            customBassGain: customBassGain,
          ),
        ),
      ),
    );
  }
}

typedef _Complex = ({double re, double im});

_Complex _cAdd(_Complex a, _Complex b) => (re: a.re + b.re, im: a.im + b.im);
_Complex _cMul(_Complex a, _Complex b) =>
    (re: a.re * b.re - a.im * b.im, im: a.re * b.im + a.im * b.re);
_Complex _cScale(_Complex a, double s) => (re: a.re * s, im: a.im * s);
double _cAbs(_Complex a) => math.sqrt(a.re * a.re + a.im * a.im);

({ _Complex lp4, _Complex hp4, _Complex ap2 }) _evalLr4Pair(
    double fc, double t, double fs) {
  final clampedFc = fc.clamp(15.0, fs * 0.45);
  final g = math.tan(math.pi * clampedFc / fs);
  const k = math.sqrt2;
  final denRe = g * g - t * t;
  final denIm = k * g * t;
  final denSq = math.max(1e-30, denRe * denRe + denIm * denIm);

  final _Complex lp2 = (re: (g * g * denRe) / denSq, im: (-g * g * denIm) / denSq);
  final _Complex hp2 = (re: (-t * t * denRe) / denSq, im: (t * t * denIm) / denSq);
  final _Complex ap2 = (
    re: (denRe * denRe - denIm * denIm) / denSq,
    im: (-2.0 * denRe * denIm) / denSq
  );
  return (lp4: _cMul(lp2, lp2), hp4: _cMul(hp2, hp2), ap2: ap2);
}

class _DynamicSystemPainter extends CustomPainter {
  final TransducerProfile profile;
  final double strength;
  final bool isEnabled;
  final Color primaryColor;
  final double? customXLow;
  final double? customXHigh;
  final double? customYLow;
  final double? customYHigh;
  final double? customSideGainX;
  final double? customSideGainY;
  final double? customBassGain;

  _DynamicSystemPainter({
    required this.profile,
    required this.strength,
    required this.isEnabled,
    required this.primaryColor,
    this.customXLow,
    this.customXHigh,
    this.customYLow,
    this.customYHigh,
    this.customSideGainX,
    this.customSideGainY,
    this.customBassGain,
  });

  static const double minFreq = 20.0;
  static const double maxFreq = 20000.0;
  static const double minDb = -6.0;
  static const double maxDb = 15.0;
  static const int numPoints = 140;

  @override
  void paint(Canvas canvas, Size size) {
    final paddingLeft = 32.0;
    final paddingRight = 16.0;
    final paddingTop = 12.0;
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

    final zeroY = dbToY(0.0);

    // 1. Draw Grid
    _drawGrid(canvas, paddingLeft, paddingTop, graphWidth, graphHeight);

    if (!isEnabled || strength < 0.005) {
      canvas.drawLine(
        Offset(paddingLeft, zeroY),
        Offset(paddingLeft + graphWidth, zeroY),
        Paint()
          ..color = primaryColor.withValues(alpha: 0.4)
          ..strokeWidth = 1.8,
      );
      return;
    }

    // 2. Lookup Preset or Custom Parameters (only custom when profile == Custom)
    final bool isCustom = profile == TransducerProfile.custom;
    final index = profile.value.clamp(0, kDynamicSystemPresets.length - 1);
    final basePreset = kDynamicSystemPresets[index];
    final p = isCustom
        ? DynamicSystemPresetParams(
            'Custom Tuning',
            customXLow ?? basePreset.xLow,
            customXHigh ?? basePreset.xHigh,
            customYLow ?? basePreset.yLow,
            customYHigh ?? basePreset.yHigh,
            customSideGainX ?? basePreset.sideGainX,
            customSideGainY ?? basePreset.sideGainY,
            customBassGain ?? basePreset.maxDrive,
          )
        : basePreset;

    // Enforce the same monotonic crossover guard as C++ DynamicSystemDSP
    const double fs = 48000.0;
    final double yl = p.yLow.clamp(20.0, 140.0);
    final double yh = math.max(p.yHigh, yl + 15.0).clamp(35.0, 300.0);
    final double xl = math.max(p.xLow, yh + 20.0).clamp(60.0, 1500.0);
    final double xh = math.max(p.xHigh, xl + 200.0).clamp(1500.0, 16000.0);

    final double s = strength.clamp(0.0, 1.0);
    final double bassGain = 1.0 + s * (p.maxDrive - 1.0);
    final double drive = math.max(0.0, bassGain - 1.0);
    final double gSub = 1.0 + drive * (0.30 + 0.70 * p.sideGainY.clamp(0.0, 1.5));
    final double gPunch = 1.0 + drive;
    final double gUbass = 1.0 + drive * (0.40 * p.sideGainX.clamp(0.0, 1.5));
    final double gAir = 1.0 + s * 0.15;

    // 3. Evaluate exact analytical 5-band LR4 transfer response across [20Hz, 20kHz]
    final freqs = List<double>.generate(numPoints, (i) {
      return minFreq * math.pow(maxFreq / minFreq, i / (numPoints - 1));
    });

    final curveDbs = <double>[];
    for (int i = 0; i < numPoints; i++) {
      final f = freqs[i];
      final t = math.tan(math.pi * f / fs);
      final cXl = _evalLr4Pair(xl, t, fs);
      final cXh = _evalLr4Pair(xh, t, fs);
      final cYl = _evalLr4Pair(yl, t, fs);
      final cYh = _evalLr4Pair(yh, t, fs);

      final bSub = _cMul(cXl.lp4, _cMul(cYh.lp4, cYl.lp4));
      final bPunch = _cMul(cXl.lp4, _cMul(cYh.lp4, cYl.hp4));
      final bUbass = _cMul(cXl.lp4, _cMul(cYh.hp4, cYl.ap2));
      final loSum = _cAdd(
        _cAdd(_cScale(bSub, gSub), _cScale(bPunch, gPunch)),
        _cScale(bUbass, gUbass),
      );
      final lo = _cMul(cXh.ap2, loSum);

      final bMid = _cMul(cXl.hp4, cXh.lp4);
      final bAir = _cMul(cXl.hp4, cXh.hp4);
      final up = _cMul(_cMul(cYh.ap2, cYl.ap2), _cAdd(bMid, _cScale(bAir, gAir)));

      final hTot = _cAdd(lo, up);
      final db = 20.0 * math.log(math.max(_cAbs(hTot), 1e-6)) / math.ln10;
      curveDbs.add(db.clamp(minDb, maxDb));
    }

    // 4. Draw Gradient Fill Under Curve
    final curvePath = Path();
    curvePath.moveTo(freqToX(freqs[0]), dbToY(curveDbs[0]));
    for (int i = 1; i < numPoints; i++) {
      curvePath.lineTo(freqToX(freqs[i]), dbToY(curveDbs[i]));
    }

    final fillPath = Path.from(curvePath);
    fillPath.lineTo(freqToX(freqs.last), zeroY);
    fillPath.lineTo(freqToX(freqs.first), zeroY);
    fillPath.close();

    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          primaryColor.withValues(alpha: 0.25),
          primaryColor.withValues(alpha: 0.0),
        ],
      ).createShader(
          Rect.fromLTWH(paddingLeft, paddingTop, graphWidth, graphHeight))
      ..style = PaintingStyle.fill;
    canvas.drawPath(fillPath, fillPaint);

    // 5. Draw Glowing Acoustic Curve
    final glowPaint = Paint()
      ..color = primaryColor.withValues(alpha: 0.35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.5
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3.0);
    canvas.drawPath(curvePath, glowPaint);

    final strokePaint = Paint()
      ..color = primaryColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(curvePath, strokePaint);

    // 6. Draw Crossover Boundary Region Markers (xLow and xHigh)
    void drawCrossoverMarker(double f, String label) {
      final cx = freqToX(f);
      final markerPaint = Paint()
        ..color = Colors.white.withValues(alpha: 0.25)
        ..strokeWidth = 1.0;

      double my = paddingTop;
      while (my < paddingTop + graphHeight) {
        canvas.drawLine(
          Offset(cx, my),
          Offset(cx, math.min(my + 3, paddingTop + graphHeight)),
          markerPaint,
        );
        my += 6;
      }

      final tp = TextPainter(
        text: TextSpan(
          text: label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.5),
            fontSize: 8.0,
            fontFamily: 'monospace',
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(cx - tp.width / 2, paddingTop + 2));
    }

    drawCrossoverMarker(xl, 'xLow');
    drawCrossoverMarker(xh, 'xHigh');

    // 7. Info Readout
    final infoSpan = TextSpan(
      children: [
        TextSpan(
          text: '${p.name}  ',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 9.0,
            fontWeight: FontWeight.bold,
            fontFamily: 'monospace',
          ),
        ),
        TextSpan(
          text: 'Drive: ${(s * 100).toInt()}%  ',
          style: TextStyle(
            color: primaryColor,
            fontSize: 9.0,
            fontWeight: FontWeight.bold,
            fontFamily: 'monospace',
          ),
        ),
        TextSpan(
          text: 'Sub: ${yl.toInt()}Hz Mid: ${yh.toInt()}Hz',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.55),
            fontSize: 8.5,
            fontFamily: 'monospace',
          ),
        ),
      ],
    );
    final tp = TextPainter(text: infoSpan, textDirection: TextDirection.ltr)
      ..layout();
    tp.paint(canvas, Offset(paddingLeft + 6, paddingTop + graphHeight - 12));
  }

  void _drawGrid(Canvas canvas, double paddingLeft, double paddingTop,
      double graphWidth, double graphHeight) {
    final gridLinePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.06)
      ..strokeWidth = 1.0;

    final zeroLinePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.22)
      ..strokeWidth = 1.0;

    final textStyle = TextStyle(
      color: Colors.white.withValues(alpha: 0.4),
      fontSize: 8.5,
      fontFamily: 'monospace',
    );

    // dB lines: -6, 0, +6, +12
    final dbTicks = [-6.0, 0.0, 6.0, 12.0];
    for (final db in dbTicks) {
      final norm = (db - minDb) / (maxDb - minDb);
      final y = paddingTop + (1.0 - norm) * graphHeight;

      canvas.drawLine(
        Offset(paddingLeft, y),
        Offset(paddingLeft + graphWidth, y),
        db == 0.0 ? zeroLinePaint : gridLinePaint,
      );

      final label = '${db > 0 ? '+' : ''}${db.toInt()}';
      final tp = TextPainter(
        text: TextSpan(text: label, style: textStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(paddingLeft - tp.width - 4, y - tp.height / 2));
    }

    // Frequency lines
    final freqTicks = [
      {'f': 50.0, 'l': '50'},
      {'f': 200.0, 'l': '200'},
      {'f': 1000.0, 'l': '1k'},
      {'f': 6000.0, 'l': '6k'},
      {'f': 20000.0, 'l': '20k'},
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
  bool shouldRepaint(covariant _DynamicSystemPainter oldDelegate) {
    return oldDelegate.profile != profile ||
        oldDelegate.strength != strength ||
        oldDelegate.isEnabled != isEnabled ||
        oldDelegate.primaryColor != primaryColor ||
        oldDelegate.customXLow != customXLow ||
        oldDelegate.customXHigh != customXHigh ||
        oldDelegate.customYLow != customYLow ||
        oldDelegate.customYHigh != customYHigh ||
        oldDelegate.customSideGainX != customSideGainX ||
        oldDelegate.customSideGainY != customSideGainY ||
        oldDelegate.customBassGain != customBassGain;
  }
}
