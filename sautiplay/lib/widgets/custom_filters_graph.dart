import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../services/app_theme_service.dart';

/// Config class representing the state of all standalone / custom audio filters.
class CustomFilterGraphConfig {
  final bool lpfEnabled;
  final double lpfCutoff;

  final bool hpfEnabled;
  final double hpfCutoff;

  final bool bpfEnabled;
  final double bpfCutoff;
  final double bpfQ;

  final bool notchEnabled;
  final double notchCutoff;
  final double notchQ;

  final bool peakEnabled;
  final double peakCutoff;
  final double peakGainDb;
  final double peakQ;

  final bool loshelfEnabled;
  final double loshelfCutoff;
  final double loshelfGainDb;
  final double loshelfSlope;

  final bool hishelfEnabled;
  final double hishelfCutoff;
  final double hishelfGainDb;
  final double hishelfSlope;

  final bool biquadEnabled;
  final double biquadB0;
  final double biquadB1;
  final double biquadB2;
  final double biquadA0;
  final double biquadA1;
  final double biquadA2;

  const CustomFilterGraphConfig({
    this.lpfEnabled = false,
    this.lpfCutoff = 500.0,
    this.hpfEnabled = false,
    this.hpfCutoff = 120.0,
    this.bpfEnabled = false,
    this.bpfCutoff = 1000.0,
    this.bpfQ = 0.707,
    this.notchEnabled = false,
    this.notchCutoff = 60.0,
    this.notchQ = 10.0,
    this.peakEnabled = false,
    this.peakCutoff = 1000.0,
    this.peakGainDb = 0.0,
    this.peakQ = 1.0,
    this.loshelfEnabled = false,
    this.loshelfCutoff = 250.0,
    this.loshelfGainDb = 0.0,
    this.loshelfSlope = 1.0,
    this.hishelfEnabled = false,
    this.hishelfCutoff = 8000.0,
    this.hishelfGainDb = 0.0,
    this.hishelfSlope = 1.0,
    this.biquadEnabled = false,
    this.biquadB0 = 1.0,
    this.biquadB1 = 0.0,
    this.biquadB2 = 0.0,
    this.biquadA0 = 1.0,
    this.biquadA1 = 0.0,
    this.biquadA2 = 0.0,
  });
}

/// A real-time frequency response visualization graph for Advanced Custom Filters.
///
/// Computes the combined magnitude transfer function H(z) in real-time
/// as the user turns parameter knobs (Cutoff, Q, Gain, Slope, Biquad coeffs).
class CustomFiltersGraph extends StatelessWidget {
  final CustomFilterGraphConfig config;
  final double height;
  final Color? primaryColor;

  const CustomFiltersGraph({
    super.key,
    required this.config,
    this.height = 130.0,
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
          painter: _CustomFiltersGraphPainter(
            config: config,
            primaryColor: effectivePrimary,
          ),
        ),
      ),
    );
  }
}

class _CustomFiltersGraphPainter extends CustomPainter {
  final CustomFilterGraphConfig config;
  final Color primaryColor;

  _CustomFiltersGraphPainter({
    required this.config,
    required this.primaryColor,
  });

  static const double minFreq = 20.0;
  static const double maxFreq = 20000.0;
  static const double minDb = -24.0;
  static const double maxDb = 24.0;
  static const int numPoints = 150;
  static const double sampleRate = 48000.0;

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

    // 2. Pre-calculate logarithmic frequency array & X coordinates
    final freqs = List<double>.generate(numPoints, (i) {
      return minFreq * math.pow(maxFreq / minFreq, i / (numPoints - 1));
    });

    final xCoords = List<double>.generate(numPoints, (i) {
      final logRatio =
          math.log(freqs[i] / minFreq) / math.log(maxFreq / minFreq);
      return paddingLeft + logRatio * graphWidth;
    });

    // 3. Evaluate combined dB response curve
    final totalDbCurve = List<double>.filled(numPoints, 0.0);

    final activeBiquads = <List<double>>[];

    if (config.lpfEnabled) {
      activeBiquads.add(_computeLpf2Coeffs(config.lpfCutoff, 0.707, sampleRate));
    }
    if (config.hpfEnabled) {
      activeBiquads.add(_computeHpf2Coeffs(config.hpfCutoff, 0.707, sampleRate));
    }
    if (config.bpfEnabled) {
      activeBiquads.add(_computeBpf2Coeffs(config.bpfCutoff, config.bpfQ, sampleRate));
    }
    if (config.notchEnabled) {
      activeBiquads.add(_computeNotch2Coeffs(config.notchCutoff, config.notchQ, sampleRate));
    }
    if (config.peakEnabled) {
      activeBiquads.add(_computePeak2Coeffs(config.peakCutoff, config.peakGainDb, config.peakQ, sampleRate));
    }
    if (config.loshelfEnabled) {
      activeBiquads.add(_computeLoshelf2Coeffs(config.loshelfCutoff, config.loshelfGainDb, config.loshelfSlope, sampleRate));
    }
    if (config.hishelfEnabled) {
      activeBiquads.add(_computeHishelf2Coeffs(config.hishelfCutoff, config.hishelfGainDb, config.hishelfSlope, sampleRate));
    }
    if (config.biquadEnabled) {
      activeBiquads.add([
        config.biquadB0,
        config.biquadB1,
        config.biquadB2,
        config.biquadA0,
        config.biquadA1,
        config.biquadA2,
      ]);
    }

    for (final coeffs in activeBiquads) {
      for (int i = 0; i < numPoints; i++) {
        totalDbCurve[i] += _evalBiquadGainDb(coeffs, freqs[i], sampleRate);
      }
    }

    double dbToY(double db) {
      final clampedDb = db.clamp(minDb, maxDb);
      final norm = (clampedDb - minDb) / (maxDb - minDb);
      return paddingTop + (1.0 - norm) * graphHeight;
    }

    final zeroY = dbToY(0.0);

    // 4. Draw Combined Master Response Curve
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

    // Master line
    final masterStrokePaint = Paint()
      ..color = activeBiquads.isNotEmpty ? primaryColor : Colors.white38
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(masterPath, masterStrokePaint);

    // Master fill under curve
    if (activeBiquads.isNotEmpty) {
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

    // Horizontal dB lines (-24dB, -12dB, 0dB, +12dB, +24dB)
    final dbSteps = [-24.0, -12.0, 0.0, 12.0, 24.0];
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

  // --- Biquad Math Calculations for Each Miniaudio Filter ---

  List<double> _computeLpf2Coeffs(double cutoffHz, double q, double fs) {
    final f0 = cutoffHz.clamp(20.0, fs / 2.1);
    final w0 = 2.0 * math.pi * f0 / fs;
    final alpha = math.sin(w0) / (2.0 * q);
    final cosW0 = math.cos(w0);

    final b0 = (1.0 - cosW0) / 2.0;
    final b1 = 1.0 - cosW0;
    final b2 = (1.0 - cosW0) / 2.0;
    final a0 = 1.0 + alpha;
    final a1 = -2.0 * cosW0;
    final a2 = 1.0 - alpha;
    return [b0, b1, b2, a0, a1, a2];
  }

  List<double> _computeHpf2Coeffs(double cutoffHz, double q, double fs) {
    final f0 = cutoffHz.clamp(20.0, fs / 2.1);
    final w0 = 2.0 * math.pi * f0 / fs;
    final alpha = math.sin(w0) / (2.0 * q);
    final cosW0 = math.cos(w0);

    final b0 = (1.0 + cosW0) / 2.0;
    final b1 = -(1.0 + cosW0);
    final b2 = (1.0 + cosW0) / 2.0;
    final a0 = 1.0 + alpha;
    final a1 = -2.0 * cosW0;
    final a2 = 1.0 - alpha;
    return [b0, b1, b2, a0, a1, a2];
  }

  List<double> _computeBpf2Coeffs(double cutoffHz, double q, double fs) {
    final f0 = cutoffHz.clamp(20.0, fs / 2.1);
    final w0 = 2.0 * math.pi * f0 / fs;
    final alpha = math.sin(w0) / (2.0 * (q > 0 ? q : 1.0));
    final cosW0 = math.cos(w0);

    final b0 = alpha;
    final b1 = 0.0;
    final b2 = -alpha;
    final a0 = 1.0 + alpha;
    final a1 = -2.0 * cosW0;
    final a2 = 1.0 - alpha;
    return [b0, b1, b2, a0, a1, a2];
  }

  List<double> _computeNotch2Coeffs(double cutoffHz, double q, double fs) {
    final f0 = cutoffHz.clamp(20.0, fs / 2.1);
    final w0 = 2.0 * math.pi * f0 / fs;
    final alpha = math.sin(w0) / (2.0 * (q > 0 ? q : 1.0));
    final cosW0 = math.cos(w0);

    final b0 = 1.0;
    final b1 = -2.0 * cosW0;
    final b2 = 1.0;
    final a0 = 1.0 + alpha;
    final a1 = -2.0 * cosW0;
    final a2 = 1.0 - alpha;
    return [b0, b1, b2, a0, a1, a2];
  }

  List<double> _computePeak2Coeffs(
      double cutoffHz, double gainDb, double q, double fs) {
    final f0 = cutoffHz.clamp(20.0, fs / 2.1);
    final w0 = 2.0 * math.pi * f0 / fs;
    final sinW0 = math.sin(w0);
    final cosW0 = math.cos(w0);
    final A = math.pow(10.0, gainDb / 40.0).toDouble();
    final alpha = sinW0 / (2.0 * (q > 0 ? q : 1.0));

    final b0 = 1.0 + alpha * A;
    final b1 = -2.0 * cosW0;
    final b2 = 1.0 - alpha * A;
    final a0 = 1.0 + alpha / A;
    final a1 = -2.0 * cosW0;
    final a2 = 1.0 - alpha / A;
    return [b0, b1, b2, a0, a1, a2];
  }

  List<double> _computeLoshelf2Coeffs(
      double cutoffHz, double gainDb, double slope, double fs) {
    final f0 = cutoffHz.clamp(20.0, fs / 2.1);
    final w0 = 2.0 * math.pi * f0 / fs;
    final sinW0 = math.sin(w0);
    final cosW0 = math.cos(w0);
    final A = math.pow(10.0, gainDb / 40.0).toDouble();
    final beta = math.sqrt(A) / (slope > 0 ? slope : 1.0);
    final alpha = (sinW0 / 2.0) * beta;

    final b0 = A * ((A + 1.0) - (A - 1.0) * cosW0 + 2.0 * math.sqrt(A) * alpha);
    final b1 = 2.0 * A * ((A - 1.0) - (A + 1.0) * cosW0);
    final b2 = A * ((A + 1.0) - (A - 1.0) * cosW0 - 2.0 * math.sqrt(A) * alpha);
    final a0 = (A + 1.0) + (A - 1.0) * cosW0 + 2.0 * math.sqrt(A) * alpha;
    final a1 = -2.0 * ((A - 1.0) + (A + 1.0) * cosW0);
    final a2 = (A + 1.0) + (A - 1.0) * cosW0 - 2.0 * math.sqrt(A) * alpha;
    return [b0, b1, b2, a0, a1, a2];
  }

  List<double> _computeHishelf2Coeffs(
      double cutoffHz, double gainDb, double slope, double fs) {
    final f0 = cutoffHz.clamp(20.0, fs / 2.1);
    final w0 = 2.0 * math.pi * f0 / fs;
    final sinW0 = math.sin(w0);
    final cosW0 = math.cos(w0);
    final A = math.pow(10.0, gainDb / 40.0).toDouble();
    final beta = math.sqrt(A) / (slope > 0 ? slope : 1.0);
    final alpha = (sinW0 / 2.0) * beta;

    final b0 = A * ((A + 1.0) + (A - 1.0) * cosW0 + 2.0 * math.sqrt(A) * alpha);
    final b1 = -2.0 * A * ((A - 1.0) + (A + 1.0) * cosW0);
    final b2 = A * ((A + 1.0) + (A - 1.0) * cosW0 - 2.0 * math.sqrt(A) * alpha);
    final a0 = (A + 1.0) - (A - 1.0) * cosW0 + 2.0 * math.sqrt(A) * alpha;
    final a1 = 2.0 * ((A - 1.0) - (A + 1.0) * cosW0);
    final a2 = (A + 1.0) - (A - 1.0) * cosW0 - 2.0 * math.sqrt(A) * alpha;
    return [b0, b1, b2, a0, a1, a2];
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
    if (magSq <= 1e-12) return -60.0;

    return 10.0 * (math.log(magSq) / math.ln10);
  }

  @override
  bool shouldRepaint(covariant _CustomFiltersGraphPainter oldDelegate) {
    return true;
  }
}
