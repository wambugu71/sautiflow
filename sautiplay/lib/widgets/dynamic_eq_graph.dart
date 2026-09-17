import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:sautiflow/sautiflow.dart';
import '../services/app_theme_service.dart';

/// Data model representing a Dynamic EQ band for visualization.
class DynamicEqBandModel {
  final DynamicEqFilterType filterType;
  final DynamicEqMode mode;
  final double freqHz;
  final double q;
  final double baseGainDb;
  final double thresholdDb;
  final double rangeDb;
  final double ratio;
  final bool enabled;

  const DynamicEqBandModel({
    required this.filterType,
    required this.mode,
    required this.freqHz,
    required this.q,
    required this.baseGainDb,
    this.thresholdDb = -24.0,
    this.rangeDb = 6.0,
    this.ratio = 3.0,
    this.enabled = true,
  });
}

/// A sleek, studio-grade real-time frequency response visualization graph
/// specifically engineered for the 4-Band Dynamic Equalizer.
///
/// Features:
/// - Exact biquad transfer functions H(z) matching `dsp/dynamic_eq_dsp.h`
///   (RBJ Peaking, Low-Shelf, and High-Shelf filters).
/// - Shows baseline curve and dynamic excursion envelope (compression/expansion zones).
/// - Displays composite master acoustic output curve with glowing neon gradient.
/// - Interactive band badge markers (1-4) with tap selection support.
class DynamicEqGraph extends StatelessWidget {
  final List<DynamicEqBandModel> bands;
  final bool isEnabled;
  final double height;
  final Color? primaryColor;
  final int selectedBandIndex;
  final ValueChanged<int>? onBandSelected;

  const DynamicEqGraph({
    super.key,
    required this.bands,
    this.isEnabled = true,
    this.height = 135.0,
    this.primaryColor,
    this.selectedBandIndex = 0,
    this.onBandSelected,
  });

  static const List<Color> bandColors = [
    Color(0xFF00E5FF), // Band 1: Cyan
    Color(0xFFFFB300), // Band 2: Warm Amber
    Color(0xFFE040FB), // Band 3: Electric Magenta
    Color(0xFF00E676), // Band 4: Neon Green
  ];

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
        borderRadius: BorderRadius.circular(14.0),
        border:
            Border.all(color: Colors.white.withValues(alpha: 0.1), width: 1.0),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14.0),
        child: LayoutBuilder(
          builder: (context, constraints) {
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: (details) {
                if (onBandSelected == null || bands.isEmpty) return;
                const paddingLeft = 32.0;
                const paddingRight = 16.0;
                final graphWidth =
                    constraints.maxWidth - paddingLeft - paddingRight;
                if (graphWidth <= 0) return;

                final tapX = details.localPosition.dx - paddingLeft;
                if (tapX < 0 || tapX > graphWidth) return;

                const minFreq = 20.0;
                const maxFreq = 20000.0;
                final tapRatio = (tapX / graphWidth).clamp(0.0, 1.0);
                final tapLog = math.log(minFreq) +
                    tapRatio * (math.log(maxFreq) - math.log(minFreq));

                // Find closest band in log-frequency space
                int closestBand = 0;
                double minDiff = double.infinity;
                for (int i = 0; i < bands.length; i++) {
                  final bandLog = math.log(bands[i].freqHz.clamp(minFreq, maxFreq));
                  final diff = (tapLog - bandLog).abs();
                  if (diff < minDiff) {
                    minDiff = diff;
                    closestBand = i;
                  }
                }
                onBandSelected!(closestBand);
              },
              child: Stack(
                children: [
                  CustomPaint(
                    size: Size(constraints.maxWidth, height),
                    painter: _DynamicEqPainter(
                      bands: bands,
                      isEnabled: isEnabled,
                      primaryColor: effectivePrimary,
                      selectedBandIndex: selectedBandIndex,
                    ),
                  ),
                  // Top overlay badge
                  Positioned(
                    top: 8,
                    right: 12,
                    child: _buildHeaderBadge(effectivePrimary),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildHeaderBadge(Color primary) {
    final activeCount = bands.where((b) => b.enabled).length;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: isEnabled
              ? primary.withValues(alpha: 0.35)
              : Colors.white.withValues(alpha: 0.1),
          width: 0.8,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isEnabled && activeCount > 0
                  ? const Color(0xFF00E676)
                  : Colors.white30,
            ),
          ),
          const SizedBox(width: 5),
          Text(
            isEnabled
                ? '$activeCount/4 Active'
                : 'Bypassed',
            style: TextStyle(
              color: isEnabled ? Colors.white70 : Colors.white38,
              fontSize: 10,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }
}

class _DynamicEqPainter extends CustomPainter {
  final List<DynamicEqBandModel> bands;
  final bool isEnabled;
  final Color primaryColor;
  final int selectedBandIndex;

  _DynamicEqPainter({
    required this.bands,
    required this.isEnabled,
    required this.primaryColor,
    required this.selectedBandIndex,
  });

  static const double minFreq = 20.0;
  static const double maxFreq = 20000.0;
  static const double minDb = -18.0;
  static const double maxDb = 18.0;
  static const int numPoints = 150;
  static const double sampleRate = 48000.0;

  @override
  void paint(Canvas canvas, Size size) {
    const paddingLeft = 32.0;
    const paddingRight = 16.0;
    const paddingTop = 14.0;
    const paddingBottom = 20.0;

    final graphWidth = size.width - paddingLeft - paddingRight;
    final graphHeight = size.height - paddingTop - paddingBottom;
    if (graphWidth <= 0 || graphHeight <= 0) return;

    // 1. Draw Grid Lines and Axes Labels
    _drawGridAndLabels(
      canvas,
      size,
      paddingLeft,
      paddingTop,
      graphWidth,
      graphHeight,
    );

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

    // Helper to map dB value to Y canvas coordinate
    double dbToY(double db) {
      final clampedDb = db.clamp(minDb, maxDb);
      final norm = (clampedDb - minDb) / (maxDb - minDb);
      return paddingTop + (1.0 - norm) * graphHeight;
    }

    final zeroY = dbToY(0.0);

    // 3. Compute per-band dB curves & total master dB curve
    final bandBaselineCurves =
        List.generate(bands.length, (_) => List<double>.filled(numPoints, 0.0));
    final bandExcursionCurves =
        List.generate(bands.length, (_) => List<double>.filled(numPoints, 0.0));
    final totalDbCurve = List<double>.filled(numPoints, 0.0);

    for (int b = 0; b < bands.length; b++) {
      final band = bands[b];
      if (!band.enabled) continue;

      final baseCoeffs = _computeBiquadCoeffs(
        band.filterType,
        band.freqHz,
        band.q,
        band.baseGainDb,
        sampleRate,
      );

      // Excursion curve computation (Compress: baseGain - rangeDb; Expand: baseGain + rangeDb)
      final hasDynamics =
          band.mode != DynamicEqMode.staticMode && band.rangeDb > 0.01;
      final excursionGainDb = band.mode == DynamicEqMode.compress
          ? band.baseGainDb - band.rangeDb
          : (band.mode == DynamicEqMode.expand
              ? band.baseGainDb + band.rangeDb
              : band.baseGainDb);

      final excursionCoeffs = hasDynamics
          ? _computeBiquadCoeffs(
              band.filterType,
              band.freqHz,
              band.q,
              excursionGainDb,
              sampleRate,
            )
          : baseCoeffs;

      for (int i = 0; i < numPoints; i++) {
        final baseDb = _evalBiquadGainDb(baseCoeffs, freqs[i], sampleRate);
        bandBaselineCurves[b][i] = baseDb;
        totalDbCurve[i] += baseDb;

        if (hasDynamics) {
          bandExcursionCurves[b][i] =
              _evalBiquadGainDb(excursionCoeffs, freqs[i], sampleRate);
        } else {
          bandExcursionCurves[b][i] = baseDb;
        }
      }
    }

    // 4. Draw Individual Bands: Dynamic Excursion Envelope & Baseline Curve
    for (int b = 0; b < bands.length; b++) {
      final band = bands[b];
      if (!band.enabled) continue;

      final color = DynamicEqGraph.bandColors[b % DynamicEqGraph.bandColors.length];
      final isSelected = b == selectedBandIndex;
      final hasDynamics =
          band.mode != DynamicEqMode.staticMode && band.rangeDb > 0.01;

      // Draw dynamic excursion shaded area (between baseline and dynamic excursion)
      if (hasDynamics) {
        final excursionPath = Path();
        excursionPath.moveTo(xCoords[0], dbToY(bandBaselineCurves[b][0]));
        for (int i = 1; i < numPoints; i++) {
          excursionPath.lineTo(xCoords[i], dbToY(bandBaselineCurves[b][i]));
        }
        for (int i = numPoints - 1; i >= 0; i--) {
          excursionPath.lineTo(xCoords[i], dbToY(bandExcursionCurves[b][i]));
        }
        excursionPath.close();

        final excursionPaint = Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              color.withValues(alpha: isSelected ? 0.22 : 0.14),
              color.withValues(alpha: 0.03),
            ],
          ).createShader(
              Rect.fromLTWH(paddingLeft, paddingTop, graphWidth, graphHeight))
          ..style = PaintingStyle.fill;
        canvas.drawPath(excursionPath, excursionPaint);

        // Dashed stroke for dynamic boundary
        _drawDashedCurve(
          canvas,
          xCoords,
          bandExcursionCurves[b],
          dbToY,
          color.withValues(alpha: isSelected ? 0.65 : 0.40),
          dashLength: 4.0,
          dashSpace: 3.0,
          strokeWidth: 1.0,
        );
      }

      // Draw baseline curve
      final baselinePath = Path();
      baselinePath.moveTo(xCoords[0], dbToY(bandBaselineCurves[b][0]));
      for (int i = 1; i < numPoints; i++) {
        baselinePath.lineTo(xCoords[i], dbToY(bandBaselineCurves[b][i]));
      }

      final baselinePaint = Paint()
        ..color = color.withValues(alpha: isSelected ? 0.70 : 0.45)
        ..style = PaintingStyle.stroke
        ..strokeWidth = isSelected ? 1.8 : 1.2
        ..strokeCap = StrokeCap.round;
      canvas.drawPath(baselinePath, baselinePaint);

      // Subtle fill down to zero dB for baseline
      final baselineFill = Path.from(baselinePath);
      baselineFill.lineTo(xCoords.last, zeroY);
      baselineFill.lineTo(xCoords.first, zeroY);
      baselineFill.close();

      final fillPaint = Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            color.withValues(alpha: isSelected ? 0.12 : 0.06),
            color.withValues(alpha: 0.0),
          ],
        ).createShader(
            Rect.fromLTWH(paddingLeft, paddingTop, graphWidth, graphHeight))
        ..style = PaintingStyle.fill;
      canvas.drawPath(baselineFill, fillPaint);
    }

    // 5. Draw Master Combined Composite Curve
    final masterPath = Path();
    masterPath.moveTo(xCoords[0], dbToY(totalDbCurve[0]));
    for (int i = 1; i < numPoints; i++) {
      masterPath.lineTo(xCoords[i], dbToY(totalDbCurve[i]));
    }

    // Glow stroke
    final glowPaint = Paint()
      ..color = primaryColor.withValues(alpha: 0.35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5.0
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4.0);
    canvas.drawPath(masterPath, glowPaint);

    // Bright crisp master line
    final masterStrokePaint = Paint()
      ..color = primaryColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(masterPath, masterStrokePaint);

    // Master gradient fill down to 0 dB line
    final masterFillPath = Path.from(masterPath);
    masterFillPath.lineTo(xCoords.last, zeroY);
    masterFillPath.lineTo(xCoords.first, zeroY);
    masterFillPath.close();

    final masterFillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          primaryColor.withValues(alpha: 0.20),
          primaryColor.withValues(alpha: 0.0),
        ],
      ).createShader(
          Rect.fromLTWH(paddingLeft, paddingTop, graphWidth, graphHeight))
      ..style = PaintingStyle.fill;
    canvas.drawPath(masterFillPath, masterFillPaint);

    // 6. Draw Band Center Handles & Badges (1, 2, 3, 4)
    for (int b = 0; b < bands.length; b++) {
      final band = bands[b];
      if (!band.enabled) continue;

      final color = DynamicEqGraph.bandColors[b % DynamicEqGraph.bandColors.length];
      final isSelected = b == selectedBandIndex;
      final freq = band.freqHz.clamp(minFreq, maxFreq);

      final logRatio =
          math.log(freq / minFreq) / math.log(maxFreq / minFreq);
      final handleX = paddingLeft + logRatio * graphWidth;

      // Net gain at center frequency
      final coeffs = _computeBiquadCoeffs(
        band.filterType,
        band.freqHz,
        band.q,
        band.baseGainDb,
        sampleRate,
      );
      final bandNetDb = _evalBiquadGainDb(coeffs, freq, sampleRate);
      final handleY = dbToY(bandNetDb);

      // Selected outer pulsing halo
      if (isSelected) {
        canvas.drawCircle(
          Offset(handleX, handleY),
          14.0,
          Paint()..color = color.withValues(alpha: 0.22),
        );
      }

      // Outer ring
      canvas.drawCircle(
        Offset(handleX, handleY),
        isSelected ? 10.5 : 8.5,
        Paint()..color = color.withValues(alpha: 0.40),
      );

      // Inner solid circle
      canvas.drawCircle(
        Offset(handleX, handleY),
        isSelected ? 8.0 : 6.5,
        Paint()..color = color,
      );

      // White boundary ring
      canvas.drawCircle(
        Offset(handleX, handleY),
        isSelected ? 8.0 : 6.5,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2,
      );

      // Band Number Label (1-4)
      final textSpan = TextSpan(
        text: '${b + 1}',
        style: TextStyle(
          color: Colors.black,
          fontSize: isSelected ? 9.5 : 8.5,
          fontWeight: FontWeight.w900,
        ),
      );
      final textPainter = TextPainter(
        text: textSpan,
        textDirection: TextDirection.ltr,
      )..layout();
      textPainter.paint(
        canvas,
        Offset(
          handleX - textPainter.width / 2,
          handleY - textPainter.height / 2,
        ),
      );

      // Mode indicator icon badge (arrow down for compress, arrow up for expand)
      if (band.mode != DynamicEqMode.staticMode && band.rangeDb > 0.01) {
        final isCompress = band.mode == DynamicEqMode.compress;
        final modeSymbol = isCompress ? '▼' : '▲';
        final symbolOffset = isCompress ? 12.0 : -14.0;
        final symbolSpan = TextSpan(
          text: modeSymbol,
          style: TextStyle(
            color: color,
            fontSize: 7.0,
            fontWeight: FontWeight.bold,
          ),
        );
        final symbolPainter = TextPainter(
          text: symbolSpan,
          textDirection: TextDirection.ltr,
        )..layout();
        symbolPainter.paint(
          canvas,
          Offset(
            handleX - symbolPainter.width / 2,
            handleY + symbolOffset - symbolPainter.height / 2,
          ),
        );
      }
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
      ..color = Colors.white.withValues(alpha: 0.07)
      ..strokeWidth = 0.8;

    final zeroLinePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.22)
      ..strokeWidth = 1.0;

    const textStyle = TextStyle(
      color: Colors.white38,
      fontSize: 8.5,
      fontFamily: 'monospace',
    );

    // Horizontal dB lines (-18, -12, -6, 0, +6, +12, +18)
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

    // Vertical Logarithmic Frequency lines & labels (20, 100, 1k, 10k, 20k)
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

      final logRatio =
          math.log(freq / minFreq) / math.log(maxFreq / minFreq);
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

  void _drawDashedCurve(
    Canvas canvas,
    List<double> xCoords,
    List<double> yValues,
    double Function(double) dbToY,
    Color color, {
    double dashLength = 4.0,
    double dashSpace = 3.0,
    double strokeWidth = 1.0,
  }) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    double accumulatedDistance = 0.0;
    bool drawing = true;

    for (int i = 0; i < xCoords.length - 1; i++) {
      final p1 = Offset(xCoords[i], dbToY(yValues[i]));
      final p2 = Offset(xCoords[i + 1], dbToY(yValues[i + 1]));
      final segmentDx = p2.dx - p1.dx;
      final segmentDy = p2.dy - p1.dy;
      final segmentLength =
          math.sqrt(segmentDx * segmentDx + segmentDy * segmentDy);
      if (segmentLength <= 0.001) continue;

      double currentSegmentPos = 0.0;
      while (currentSegmentPos < segmentLength) {
        final remainingInState =
            (drawing ? dashLength : dashSpace) - accumulatedDistance;
        final step = math.min(remainingInState, segmentLength - currentSegmentPos);

        final startFraction = currentSegmentPos / segmentLength;
        final endFraction = (currentSegmentPos + step) / segmentLength;

        if (drawing) {
          final startPt = Offset(
            p1.dx + segmentDx * startFraction,
            p1.dy + segmentDy * startFraction,
          );
          final endPt = Offset(
            p1.dx + segmentDx * endFraction,
            p1.dy + segmentDy * endFraction,
          );
          canvas.drawLine(startPt, endPt, paint);
        }

        accumulatedDistance += step;
        currentSegmentPos += step;

        if (accumulatedDistance >= (drawing ? dashLength : dashSpace)) {
          drawing = !drawing;
          accumulatedDistance = 0.0;
        }
      }
    }
  }

  // --- Exact RBJ Biquad Math matching dsp/dynamic_eq_dsp.h ---

  List<double> _computeBiquadCoeffs(
    DynamicEqFilterType type,
    double freqHz,
    double q,
    double gainDb,
    double fs,
  ) {
    final f0 = freqHz.clamp(20.0, fs / 2.1);
    final w0 = 2.0 * math.pi * f0 / fs;
    final sinW0 = math.sin(w0);
    final cosW0 = math.cos(w0);
    final clampedQ = q > 0.05 ? q : 1.0;
    final A = math.pow(10.0, gainDb / 40.0).toDouble();
    final alpha = sinW0 / (2.0 * clampedQ);

    double b0 = 1.0, b1 = 0.0, b2 = 0.0;
    double a0 = 1.0, a1 = 0.0, a2 = 0.0;

    switch (type) {
      case DynamicEqFilterType.peak:
        b0 = 1.0 + alpha * A;
        b1 = -2.0 * cosW0;
        b2 = 1.0 - alpha * A;
        a0 = 1.0 + alpha / A;
        a1 = -2.0 * cosW0;
        a2 = 1.0 - alpha / A;
        break;

      case DynamicEqFilterType.lowShelf:
        final twoSqrtAAlpha = 2.0 * math.sqrt(A) * alpha;
        final ap1 = A + 1.0;
        final am1 = A - 1.0;
        b0 = A * (ap1 - am1 * cosW0 + twoSqrtAAlpha);
        b1 = 2.0 * A * (am1 - ap1 * cosW0);
        b2 = A * (ap1 - am1 * cosW0 - twoSqrtAAlpha);
        a0 = ap1 + am1 * cosW0 + twoSqrtAAlpha;
        a1 = -2.0 * (am1 + ap1 * cosW0);
        a2 = ap1 + am1 * cosW0 - twoSqrtAAlpha;
        break;

      case DynamicEqFilterType.highShelf:
        final twoSqrtAAlpha = 2.0 * math.sqrt(A) * alpha;
        final ap1 = A + 1.0;
        final am1 = A - 1.0;
        b0 = A * (ap1 + am1 * cosW0 + twoSqrtAAlpha);
        b1 = -2.0 * A * (am1 + ap1 * cosW0);
        b2 = A * (ap1 + am1 * cosW0 - twoSqrtAAlpha);
        a0 = ap1 - am1 * cosW0 + twoSqrtAAlpha;
        a1 = 2.0 * (am1 - ap1 * cosW0);
        a2 = ap1 - am1 * cosW0 - twoSqrtAAlpha;
        break;
    }

    return [b0, b1, b2, a0, a1, a2];
  }

  double _evalBiquadGainDb(List<double> coeffs, double f, double fs) {
    final a0 = coeffs[3];
    if (a0.abs() < 1e-9) return 0.0;

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
  bool shouldRepaint(covariant _DynamicEqPainter oldDelegate) {
    return true;
  }
}
