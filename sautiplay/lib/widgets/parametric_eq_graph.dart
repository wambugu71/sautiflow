import 'dart:math' as math;
import 'package:material_ui/material_ui.dart';
import 'package:sautiflow/sautiflow.dart';
import '../services/app_theme_service.dart';

/// A sleek, real-time frequency response visualization graph for Parametric EQ.
///
/// Samples 150 logarithmic frequency points across [20Hz, 20kHz] and computes
/// exact Cytomic SVF (and multi-stage TDF-II for Super-Filters) transfer functions
/// matching `audio_engine.cpp` and `dsp/cytomic_svf_dsp.h`.
class ParametricEqGraph extends StatelessWidget {
  final List<EqBandConfig> bands;
  final bool isEnabled;
  final double height;
  final Color? primaryColor;
  final double sampleRate;

  const ParametricEqGraph({
    super.key,
    required this.bands,
    this.isEnabled = true,
    this.height = 160.0,
    this.primaryColor,
    this.sampleRate = 48000.0,
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
          painter: _ParametricEqPainter(
            bands: bands,
            isEnabled: isEnabled,
            primaryColor: effectivePrimary,
            sampleRate: sampleRate > 0 ? sampleRate : 48000.0,
          ),
        ),
      ),
    );
  }
}

class _SvfCoeffs {
  final double g;
  final double k;
  final double m0;
  final double m1;
  final double m2;
  final bool isFlat;

  const _SvfCoeffs({
    this.g = 0.0,
    this.k = 1.0,
    this.m0 = 1.0,
    this.m1 = 0.0,
    this.m2 = 0.0,
    this.isFlat = true,
  });
}

class _ParametricEqPainter extends CustomPainter {
  final List<EqBandConfig> bands;
  final bool isEnabled;
  final Color primaryColor;
  final double sampleRate;

  _ParametricEqPainter({
    required this.bands,
    required this.isEnabled,
    required this.primaryColor,
    required this.sampleRate,
  });

  static const double minFreq = 20.0;
  static const double maxFreq = 20000.0;
  static const double minDb = -18.0;
  static const double maxDb = 18.0;
  static const int numPoints = 150;

  static const List<Color> _bandColors = [
    Color(0xFF00E5FF), // Cyan
    Color(0xFFFF9100), // Amber / Orange
    Color(0xFFE040FB), // Purple / Pink
    Color(0xFF00E676), // Neon Green
    Color(0xFFFF5252), // Coral Red
    Color(0xFFFFEA00), // Yellow
    Color(0xFF7C4DFF), // Deep Purple
    Color(0xFF1DE9B6), // Teal
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final paddingLeft = 32.0;
    final paddingRight = 16.0;
    final paddingTop = 12.0;
    final paddingBottom = 18.0;

    final graphWidth = size.width - paddingLeft - paddingRight;
    final graphHeight = size.height - paddingTop - paddingBottom;
    if (graphWidth <= 0 || graphHeight <= 0) return;

    // 1. Draw Grid & Axes Labels
    _drawGridAndLabels(
      canvas,
      size,
      paddingLeft,
      paddingTop,
      graphWidth,
      graphHeight,
    );

    // If disabled or no bands, return early after drawing grid
    if (!isEnabled || bands.isEmpty) return;

    // 2. Pre-calculate logarithmic frequency array & X coordinates
    final freqs = List<double>.generate(numPoints, (i) {
      return minFreq * math.pow(maxFreq / minFreq, i / (numPoints - 1));
    });

    final xCoords = List<double>.generate(numPoints, (i) {
      final logRatio =
          math.log(freqs[i] / minFreq) / math.log(maxFreq / minFreq);
      return paddingLeft + logRatio * graphWidth;
    });

    // 3. Compute per-band dB curves & total master dB curve
    final bandDbCurves =
        List.generate(bands.length, (_) => List<double>.filled(numPoints, 0.0));
    final totalDbCurve = List<double>.filled(numPoints, 0.0);

    for (int b = 0; b < bands.length; b++) {
      final band = bands[b];
      if (!band.enabled) continue;

      if (band.type == EqBandType.asupercut ||
          band.type == EqBandType.asuperpass ||
          band.type == EqBandType.asuperstop) {
        final stages = _computeMultiStageCoeffs(band, sampleRate);
        for (int i = 0; i < numPoints; i++) {
          double db = 0.0;
          for (final stageCoeffs in stages) {
            db += _evalBiquadGainDb(stageCoeffs, freqs[i], sampleRate);
          }
          bandDbCurves[b][i] = db;
          totalDbCurve[i] += db;
        }
      } else {
        final svfCoeffs = _computeSvfCoeffs(band, sampleRate);
        for (int i = 0; i < numPoints; i++) {
          final db = _evalSvfGainDb(svfCoeffs, freqs[i], sampleRate);
          bandDbCurves[b][i] = db;
          totalDbCurve[i] += db;
        }
      }
    }

    // Helper to map dB value to Y canvas coordinate
    double dbToY(double db) {
      final clampedDb = db.clamp(minDb, maxDb);
      final norm = (clampedDb - minDb) / (maxDb - minDb);
      return paddingTop + (1.0 - norm) * graphHeight;
    }

    final zeroY = dbToY(0.0);

    // 4. Draw Individual Band Filled Curves & Lines
    for (int b = 0; b < bands.length; b++) {
      final band = bands[b];
      if (!band.enabled) continue;

      final color = _bandColors[b % _bandColors.length];
      final bandPath = Path();
      bandPath.moveTo(xCoords[0], dbToY(bandDbCurves[b][0]));

      for (int i = 1; i < numPoints; i++) {
        bandPath.lineTo(xCoords[i], dbToY(bandDbCurves[b][i]));
      }

      // Draw subtle stroke for individual band
      final strokePaint = Paint()
        ..color = color.withValues(alpha: 0.45)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..strokeCap = StrokeCap.round;
      canvas.drawPath(bandPath, strokePaint);

      // Draw semi-transparent gradient fill to zero-line for band
      final fillPath = Path.from(bandPath);
      fillPath.lineTo(xCoords.last, zeroY);
      fillPath.lineTo(xCoords.first, zeroY);
      fillPath.close();

      final fillPaint = Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            color.withValues(alpha: 0.18),
            color.withValues(alpha: 0.02),
          ],
        ).createShader(
            Rect.fromLTWH(paddingLeft, paddingTop, graphWidth, graphHeight))
        ..style = PaintingStyle.fill;
      canvas.drawPath(fillPath, fillPaint);
    }

    // 5. Draw Master Combined Composite Curve
    final masterPath = Path();
    masterPath.moveTo(xCoords[0], dbToY(totalDbCurve[0]));
    for (int i = 1; i < numPoints; i++) {
      masterPath.lineTo(xCoords[i], dbToY(totalDbCurve[i]));
    }

    // Glowing stroke shadow
    final glowPaint = Paint()
      ..color = primaryColor.withValues(alpha: 0.35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5.0
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4.0);
    canvas.drawPath(masterPath, glowPaint);

    // Master bright line
    final masterStrokePaint = Paint()
      ..color = primaryColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(masterPath, masterStrokePaint);

    // Master subtle fill under composite curve
    final masterFillPath = Path.from(masterPath);
    masterFillPath.lineTo(xCoords.last, zeroY);
    masterFillPath.lineTo(xCoords.first, zeroY);
    masterFillPath.close();

    final masterFillPaint = Paint()
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
    canvas.drawPath(masterFillPath, masterFillPaint);

    // 6. Draw Band Center Handles / Badges
    for (int b = 0; b < bands.length; b++) {
      final band = bands[b];
      if (!band.enabled) continue;

      final color = _bandColors[b % _bandColors.length];
      final freq = band.frequencyHz.clamp(minFreq, maxFreq);

      // Compute position on canvas
      final logRatio = math.log(freq / minFreq) / math.log(maxFreq / minFreq);
      final handleX = paddingLeft + logRatio * graphWidth;

      // Evaluate the actual net gain at center frequency for placing the handle
      final double bandNetDb;
      if (band.type == EqBandType.tilt || band.type == EqBandType.allpass) {
        bandNetDb = 0.0;
      } else if (band.type == EqBandType.asupercut ||
          band.type == EqBandType.asuperpass ||
          band.type == EqBandType.asuperstop) {
        final stages = _computeMultiStageCoeffs(band, sampleRate);
        double dbSum = 0.0;
        for (final stageCoeffs in stages) {
          dbSum += _evalBiquadGainDb(stageCoeffs, freq, sampleRate);
        }
        bandNetDb = dbSum;
      } else {
        final svfCoeffs = _computeSvfCoeffs(band, sampleRate);
        bandNetDb = _evalSvfGainDb(svfCoeffs, freq, sampleRate);
      }
      final handleY = dbToY(bandNetDb);

      // Outer glowing ring
      canvas.drawCircle(
        Offset(handleX, handleY),
        10.0,
        Paint()..color = color.withValues(alpha: 0.25),
      );

      // Inner solid circle
      canvas.drawCircle(
        Offset(handleX, handleY),
        7.0,
        Paint()..color = color,
      );

      // Border circle
      canvas.drawCircle(
        Offset(handleX, handleY),
        7.0,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2,
      );

      // Band Number Label inside dot
      final textSpan = TextSpan(
        text: '${b + 1}',
        style: const TextStyle(
          color: Colors.black,
          fontSize: 9,
          fontWeight: FontWeight.bold,
        ),
      );
      final textPainter = TextPainter(
        text: textSpan,
        textDirection: TextDirection.ltr,
      )..layout();
      textPainter.paint(
        canvas,
        Offset(
            handleX - textPainter.width / 2, handleY - textPainter.height / 2),
      );
    }
  }

  void _drawGridAndLabels(
    Canvas canvas,
    Size size,
    double paddingLeft,
    double paddingTop,
    double graphWidth,
    double graphHeight,
  ) {
    final gridLinePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.06)
      ..strokeWidth = 1.0;

    final zeroLinePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.2)
      ..strokeWidth = 1.0;

    final textStyle = TextStyle(
      color: Colors.white.withValues(alpha: 0.45),
      fontSize: 9,
      fontFamily: 'monospace',
    );

    // Horizontal dB lines (-18dB, -12dB, -6dB, 0dB, +6dB, +12dB, +18dB)
    final dbSteps = [-18.0, -12.0, -6.0, 0.0, 6.0, 12.0, 18.0];
    for (final db in dbSteps) {
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

    // Vertical Logarithmic Frequency lines & labels (20Hz, 100Hz, 1kHz, 10kHz, 20kHz)
    final freqTicks = [
      {'f': 20.0, 'l': '20'},
      {'f': 100.0, 'l': '100'},
      {'f': 1000.0, 'l': '1k'},
      {'f': 10000.0, 'l': '10k'},
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
      tp.paint(
        canvas,
        Offset(x - tp.width / 2, paddingTop + graphHeight + 4),
      );
    }
  }

  // --- Exact Cytomic TPT SVF & Orfanidis Math matching dsp/cytomic_svf_dsp.h ---

  double _analogHighShelfMag(double freqHz, double fcHz, double a, double k0) {
    final u = freqHz / fcHz;
    final u2 = u * u;
    final sqrtA = math.sqrt(a);
    final imag = k0 * sqrtA * u;
    final numRe = 1.0 - a * u2;
    final denRe = a - u2;
    final numMagSq = numRe * numRe + imag * imag;
    final denMagSq = math.max(denRe * denRe + imag * imag, 1.0e-30);
    return a * math.sqrt(numMagSq / denMagSq);
  }

  _SvfCoeffs _computeSvfCoeffs(EqBandConfig band, double fs) {
    final fc = band.frequencyHz.clamp(10.0, fs * 0.499);
    final gainDb = band.gainDb.clamp(-36.0, 36.0);
    final isShelfOrTilt = band.type == EqBandType.lowshelf ||
        band.type == EqBandType.highshelf ||
        band.type == EqBandType.tilt;
    final rawQ = (isShelfOrTilt &&
            (band.slope - 1.0).abs() > 1.0e-5 &&
            band.slope > 0.0)
        ? band.slope
        : band.q;
    final q = rawQ.clamp(0.05, 30.0);

    final isGainType = band.type == EqBandType.peak ||
        band.type == EqBandType.bell ||
        band.type == EqBandType.lowshelf ||
        band.type == EqBandType.highshelf ||
        band.type == EqBandType.tilt ||
        band.type == EqBandType.bandreject;
    if (isGainType && gainDb.abs() < 0.005) {
      return const _SvfCoeffs(isFlat: true);
    }

    final w0 = 2.0 * math.pi * fc / fs;
    final a = math.pow(10.0, gainDb / 40.0).toDouble();
    final gLin = a * a;
    final k0 = 1.0 / q;
    final t0 = math.tan(w0 * 0.5);

    switch (band.type) {
      case EqBandType.peak:
      case EqBandType.bell:
        final absGainDb = gainDb.abs();
        final aPos = math.pow(10.0, absGainDb / 40.0).toDouble();
        final gPos = aPos * aPos;
        final gb = aPos;

        final r = math.sqrt(1.0 + 1.0 / (4.0 * q * q)) - 1.0 / (2.0 * q);
        final w1 = w0 * r;
        final t1 = math.tan(0.5 * w1);

        final uNyq = math.pi / w0;
        final oneMinusU2 = 1.0 - uNyq * uNyq;
        final bwTermNum = (aPos * uNyq) / q;
        final bwTermDen = uNyq / (q * aPos);
        final g1Sq = (oneMinusU2 * oneMinusU2 + bwTermNum * bwTermNum) /
            math.max(oneMinusU2 * oneMinusU2 + bwTermDen * bwTermDen, 1.0e-30);
        final g1 = math.sqrt(math.min(g1Sq, gPos * gPos - 1.0e-15));

        final x0 = math.max(t0 * t0, 1.0e-24);
        final x1 = math.max(t1 * t1, 1.0e-24);
        final g2M1 = math.max(gPos * gPos - 1.0, 1.0e-24);
        final w2 = x0 *
            math.sqrt(math.max((gPos * gPos - g1Sq) / g2M1, 1.0e-18));

        final rhs1 = (gPos * gPos * (w2 - x0) * (w2 - x0) -
                (w2 - g1 * x0) * (w2 - g1 * x0)) /
            x0;
        final rhs2 = (gb * gb * (w2 - x1) * (w2 - x1) -
                (w2 - g1 * x1) * (w2 - g1 * x1)) /
            x1;
        final bd2 = math.max(
            (rhs2 - rhs1) / math.max(gPos * gPos - gb * gb, 1.0e-24), 1.0e-24);
        final bn2 = math.max(rhs1 + gPos * gPos * bd2, 1.0e-24);
        final bn = math.sqrt(bn2);
        final bd = math.sqrt(bd2);

        if (gainDb >= 0.0) {
          final gOut = math.sqrt(w2);
          final kOut = bd / gOut;
          return _SvfCoeffs(
            g: gOut,
            k: kOut,
            m0: g1,
            m1: (bn / gOut) - g1 * kOut,
            m2: 1.0 - g1,
            isFlat: false,
          );
        } else {
          final invG1 = 1.0 / g1;
          final gOut = math.sqrt(w2 * invG1);
          final kOut = bd > 0.0 ? (bn * invG1) / gOut : k0;
          return _SvfCoeffs(
            g: gOut,
            k: kOut,
            m0: invG1,
            m1: ((bd * invG1) / gOut) - invG1 * kOut,
            m2: 1.0 - invG1,
            isFlat: false,
          );
        }

      case EqBandType.lowshelf:
        return _SvfCoeffs(
          g: t0 / math.sqrt(a),
          k: k0,
          m0: 1.0,
          m1: k0 * (a - 1.0),
          m2: a * a - 1.0,
          isFlat: false,
        );

      case EqBandType.highshelf:
        final absGainDb = gainDb.abs();
        final aPos = math.pow(10.0, absGainDb / 40.0).toDouble();
        final g1 = _analogHighShelfMag(0.5 * fs, fc, aPos, k0);
        final r = (g1 + aPos) / (1.0 + aPos);
        final w2 = t0 * t0 * r;
        final gBoost = math.sqrt(w2);

        final ratioNyq = (fc / (0.5 * fs)).clamp(0.0, 1.0);
        final blend = ratioNyq * ratioNyq;
        final fRef = (1.0 - blend) * (0.7 * fc) +
            blend * math.sqrt(fc * 0.48 * fs);
        final m = _analogHighShelfMag(fRef, fc, aPos, k0);
        final m2Sq = m * m;
        final t1 = math.tan(math.pi * fRef / fs);
        final x1 = t1 * t1;
        final denomK = w2 * x1 * (m2Sq - aPos * aPos);
        final numK =
            (w2 - g1 * x1) * (w2 - g1 * x1) - m2Sq * (w2 - x1) * (w2 - x1);
        double kEff = k0;
        if (denomK.abs() > 1.0e-12 && (numK / denomK) > 0.0) {
          final cand = math.sqrt(numK / denomK);
          if (cand >= 0.25 * k0 && cand <= 4.0 * k0) {
            kEff = cand;
          }
        }

        if (gainDb >= 0.0) {
          return _SvfCoeffs(
            g: gBoost,
            k: kEff,
            m0: g1,
            m1: (aPos - g1) * kEff,
            m2: 1.0 - g1,
            isFlat: false,
          );
        } else {
          final sqrtG1 = math.sqrt(g1);
          final invG1 = 1.0 / g1;
          final kCut = (aPos * kEff) / sqrtG1;
          return _SvfCoeffs(
            g: gBoost / sqrtG1,
            k: kCut,
            m0: invG1,
            m1: (kEff / sqrtG1) - invG1 * kCut,
            m2: 1.0 - invG1,
            isFlat: false,
          );
        }

      case EqBandType.bandpass:
        return _SvfCoeffs(g: t0, k: k0, m0: 0.0, m1: 1.0, m2: 0.0, isFlat: false);

      case EqBandType.notch:
        return _SvfCoeffs(g: t0, k: k0, m0: 1.0, m1: -k0, m2: 0.0, isFlat: false);

      case EqBandType.lowpass:
        return _SvfCoeffs(g: t0, k: k0, m0: 0.0, m1: 0.0, m2: 1.0, isFlat: false);

      case EqBandType.highpass:
        return _SvfCoeffs(g: t0, k: k0, m0: 1.0, m1: -k0, m2: -1.0, isFlat: false);

      case EqBandType.allpass:
        return _SvfCoeffs(
            g: t0, k: k0, m0: 1.0, m1: -2.0 * k0, m2: 0.0, isFlat: false);

      case EqBandType.tilt:
        return _SvfCoeffs(
          g: t0 * math.sqrt(a),
          k: k0,
          m0: a,
          m1: (1.0 - a) * k0,
          m2: (1.0 / a) - a,
          isFlat: false,
        );

      case EqBandType.bandreject:
        return _SvfCoeffs(
          g: t0,
          k: k0,
          m0: 1.0,
          m1: (gLin - 1.0) * k0,
          m2: 0.0,
          isFlat: false,
        );

      case EqBandType.asupercut:
      case EqBandType.asuperpass:
      case EqBandType.asuperstop:
        return const _SvfCoeffs(isFlat: true);
    }
  }

  double _evalSvfGainDb(_SvfCoeffs c, double f, double fs) {
    if (c.isFlat) return 0.0;
    if (f >= 0.5 * fs * (1.0 - 1.0e-7)) {
      return 20.0 * (math.log(math.max(c.m0.abs(), 1.0e-12)) / math.ln10);
    }
    final t = math.tan(math.pi * f / fs);
    final t2 = t * t;
    final g2 = c.g * c.g;
    final kg = c.k * c.g;

    final denRe = g2 - t2;
    final denIm = kg * t;
    final numRe = c.m0 * denRe + c.m2 * g2;
    final numIm = (c.m0 * kg + c.m1 * c.g) * t;

    final numMagSq = numRe * numRe + numIm * numIm;
    final denMagSq = math.max(denRe * denRe + denIm * denIm, 1.0e-30);
    final magSq = numMagSq / denMagSq;
    if (magSq <= 1.0e-12) return -60.0;
    return 10.0 * (math.log(magSq) / math.ln10);
  }

  List<List<double>> _computeMultiStageCoeffs(EqBandConfig band, double fs) {
    final f0 = band.frequencyHz.clamp(20.0, fs / 2.1);
    final q = band.q > 0 ? band.q : 1.0;

    switch (band.type) {

      case EqBandType.asupercut:
        // 8th-order Butterworth low-pass (4 cascaded SOS)
        final w0 = f0 / fs;
        final k = math.tan(math.pi * w0.clamp(0.0001, 0.49));
        final k2 = k * k;
        final list = <List<double>>[];
        for (int s = 0; s < 4; s++) {
          final qButter =
              1.0 / (2.0 * math.sin((2.0 * s + 1.0) * math.pi / 16.0));
          final norm = 1.0 / (1.0 + k / qButter + k2);
          final b0 = k2 * norm;
          final b1 = 2.0 * b0;
          final b2 = b0;
          const a0 = 1.0;
          final a1 = 2.0 * (k2 - 1.0) * norm;
          final a2 = (1.0 - k / qButter + k2) * norm;
          list.add([b0, b1, b2, a0, a1, a2]);
        }
        return list;

      case EqBandType.asuperpass:
        // 8th-order band-pass: 4th-order HP at fLow + 4th-order LP at fHigh
        final term = math.sqrt(1.0 + 1.0 / (4.0 * q * q));
        final fLow = (f0 * (term - 0.5 / q)).clamp(20.0, fs * 0.45);
        final fHigh = (f0 * (term + 0.5 / q)).clamp(fLow + 10.0, fs * 0.48);

        final khp = math.tan(math.pi * fLow / fs);
        final khp2 = khp * khp;
        final klp = math.tan(math.pi * fHigh / fs);
        final klp2 = klp * klp;

        final q4 = [
          1.0 / (2.0 * math.cos(math.pi / 8.0)),
          1.0 / (2.0 * math.cos(3.0 * math.pi / 8.0)),
        ];

        final list = <List<double>>[];
        for (int s = 0; s < 2; s++) {
          final normHp = 1.0 / (1.0 + khp / q4[s] + khp2);
          final b0hp = normHp;
          final b1hp = -2.0 * b0hp;
          final b2hp = b0hp;
          const a0 = 1.0;
          final a1hp = 2.0 * (khp2 - 1.0) * normHp;
          final a2hp = (1.0 - khp / q4[s] + khp2) * normHp;
          list.add([b0hp, b1hp, b2hp, a0, a1hp, a2hp]);
        }
        for (int s = 0; s < 2; s++) {
          final normLp = 1.0 / (1.0 + klp / q4[s] + klp2);
          final b0lp = klp2 * normLp;
          final b1lp = 2.0 * b0lp;
          final b2lp = b0lp;
          const a0 = 1.0;
          final a1lp = 2.0 * (klp2 - 1.0) * normLp;
          final a2lp = (1.0 - klp / q4[s] + klp2) * normLp;
          list.add([b0lp, b1lp, b2lp, a0, a1lp, a2lp]);
        }
        return list;

      case EqBandType.asuperstop:
        // Cascaded 3-stage steep notch filter around f0
        final w0 = 2.0 * math.pi * f0 / fs;
        final cosW0 = math.cos(w0);
        final sinW0 = math.sin(w0);
        final qFactors = [q * 0.70, q * 1.0, q * 1.45];
        final list = <List<double>>[];
        for (final qf in qFactors) {
          final alpha = sinW0 / (2.0 * qf);
          const b0 = 1.0;
          final b1 = -2.0 * cosW0;
          const b2 = 1.0;
          final a0 = 1.0 + alpha;
          final a1 = -2.0 * cosW0;
          final a2 = 1.0 - alpha;
          list.add([b0, b1, b2, a0, a1, a2]);
        }
        return list;

      default:
        return [
          [1.0, 0.0, 0.0, 1.0, 0.0, 0.0]
        ];
    }
  }

  double _evalBiquadGainDb(List<double> coeffs, double f, double fs) {
    final a0 = coeffs[3];
    if (a0 == 0.0) return 0.0;

    final b0n = coeffs[0] / a0;
    final b1n = coeffs[1] / a0;
    final b2n = coeffs[2] / a0;
    final a1n = coeffs[4] / a0;
    final a2n = coeffs[5] / a0;

    final w = 2.0 * math.pi * f / fs;
    final cos1 = math.cos(w);
    final cos2 = math.cos(2.0 * w);
    final sin1 = math.sin(w);
    final sin2 = math.sin(2.0 * w);

    final numR = b0n + b1n * cos1 + b2n * cos2;
    final numI = -b1n * sin1 - b2n * sin2;
    final denR = 1.0 + a1n * cos1 + a2n * cos2;
    final denI = -a1n * sin1 - a2n * sin2;

    final numSq = numR * numR + numI * numI;
    final denSq = denR * denR + denI * denI;

    if (denSq < 1e-12) return 0.0;
    final magSq = numSq / denSq;
    if (magSq <= 1e-12) return -60.0; // Floor at -60dB

    return 10.0 * (math.log(magSq) / math.ln10);
  }

  @override
  bool shouldRepaint(covariant _ParametricEqPainter oldDelegate) {
    return true;
  }
}
