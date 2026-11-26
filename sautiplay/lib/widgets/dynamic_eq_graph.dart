import 'dart:math' as math;
import 'package:material_ui/material_ui.dart';
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
/// specifically engineered for the Dynamic Equalizer (up to 6 bands).
///
/// Features:
/// - Exact Cytomic Trapezoidal SVF transfer functions matching `dsp/dynamic_eq_dsp.h`
///   and `dsp/cytomic_svf_dsp.h` (Orfanidis Peaking, Low-Shelf, and Nyquist-matched High-Shelf).
/// - Shows baseline curve and dynamic excursion envelope (compression/expansion zones).
/// - Displays composite master acoustic output curve with glowing neon gradient.
/// - Interactive band badge markers (1-6) with tap selection support.
class DynamicEqGraph extends StatelessWidget {
  final List<DynamicEqBandModel> bands;
  final bool isEnabled;
  final double height;
  final Color? primaryColor;
  final double sampleRate;
  final int selectedBandIndex;
  final List<double>? liveGainOffsetsDb;
  final ValueChanged<int>? onBandSelected;

  const DynamicEqGraph({
    super.key,
    required this.bands,
    this.isEnabled = true,
    this.height = 160.0,
    this.primaryColor,
    this.sampleRate = 48000.0,
    this.selectedBandIndex = 0,
    this.liveGainOffsetsDb,
    this.onBandSelected,
  });

  static const List<Color> bandColors = [
    Color(0xFF78909C), // Band 1 (Sub): Slate Blue
    Color(0xFFD4A373), // Band 2 (Bass): Muted Ochre
    Color(0xFF81B29A), // Band 3 (Low-Mid): Sage Green
    Color(0xFFE07A5F), // Band 4 (Mid-High): Muted Terracotta
    Color(0xFF9D8DF1), // Band 5 (Presence): Muted Lavender
    Color(0xFF48BFE3), // Band 6 (Air): Steel Teal
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
        borderRadius: BorderRadius.circular(12.0),
        border:
            Border.all(color: Colors.white.withValues(alpha: 0.08), width: 1.0),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12.0),
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
                  final bandLog =
                      math.log(bands[i].freqHz.clamp(minFreq, maxFreq));
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
                      bands: List<DynamicEqBandModel>.of(bands),
                      isEnabled: isEnabled,
                      primaryColor: effectivePrimary,
                      sampleRate: sampleRate > 0 ? sampleRate : 48000.0,
                      selectedBandIndex: selectedBandIndex,
                      liveGainOffsetsDb: liveGainOffsetsDb != null
                          ? List<double>.of(liveGainOffsetsDb!)
                          : null,
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
            isEnabled ? '$activeCount/${bands.length} Active' : 'Bypassed',
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

class _DynamicSvfCoeffs {
  final double g;
  final double k;
  final double m0;
  final double m1;
  final double m2;
  final bool isFlat;

  const _DynamicSvfCoeffs({
    this.g = 0.0,
    this.k = 1.0,
    this.m0 = 1.0,
    this.m1 = 0.0,
    this.m2 = 0.0,
    this.isFlat = true,
  });
}

class _DynamicEqPainter extends CustomPainter {
  final List<DynamicEqBandModel> bands;
  final bool isEnabled;
  final Color primaryColor;
  final double sampleRate;
  final int selectedBandIndex;
  final List<double>? liveGainOffsetsDb;

  _DynamicEqPainter({
    required this.bands,
    required this.isEnabled,
    required this.primaryColor,
    required this.sampleRate,
    required this.selectedBandIndex,
    this.liveGainOffsetsDb,
  });

  static const double minFreq = 20.0;
  static const double maxFreq = 20000.0;
  static const double minDb = -18.0;
  static const double maxDb = 18.0;
  static const int numPoints = 150;

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
    final liveTotalDbCurve = List<double>.filled(numPoints, 0.0);
    bool hasLiveActivity = false;

    for (int b = 0; b < bands.length; b++) {
      final band = bands[b];
      if (!band.enabled) continue;

      final liveOffset = (liveGainOffsetsDb != null && b < liveGainOffsetsDb!.length)
          ? liveGainOffsetsDb![b]
          : 0.0;
      if (liveOffset.abs() > 0.02) {
        hasLiveActivity = true;
      }

      final baseCoeffs = _computeSvfCoeffs(
        band.filterType,
        band.freqHz,
        band.q,
        band.baseGainDb,
        sampleRate,
      );

      final liveCoeffs = liveOffset.abs() > 0.02
          ? _computeSvfCoeffs(
              band.filterType,
              band.freqHz,
              band.q,
              (band.baseGainDb + liveOffset).clamp(-36.0, 36.0),
              sampleRate,
            )
          : baseCoeffs;

      // Excursion curve computation (Compress: baseGain - rangeDb; Expand: baseGain + rangeDb)
      final hasDynamics =
          band.mode != DynamicEqMode.staticMode && band.rangeDb > 0.01;
      final excursionGainDb = band.mode == DynamicEqMode.compress
          ? band.baseGainDb - band.rangeDb
          : (band.mode == DynamicEqMode.expand
              ? band.baseGainDb + band.rangeDb
              : band.baseGainDb);

      final excursionCoeffs = hasDynamics
          ? _computeSvfCoeffs(
              band.filterType,
              band.freqHz,
              band.q,
              excursionGainDb,
              sampleRate,
            )
          : baseCoeffs;

      for (int i = 0; i < numPoints; i++) {
        final baseDb = _evalSvfGainDb(baseCoeffs, freqs[i], sampleRate);
        bandBaselineCurves[b][i] = baseDb;
        totalDbCurve[i] += baseDb;
        liveTotalDbCurve[i] += liveOffset.abs() > 0.02
            ? _evalSvfGainDb(liveCoeffs, freqs[i], sampleRate)
            : baseDb;

        if (hasDynamics) {
          bandExcursionCurves[b][i] =
              _evalSvfGainDb(excursionCoeffs, freqs[i], sampleRate);
        } else {
          bandExcursionCurves[b][i] = baseDb;
        }
      }
    }

    // 4. Draw Individual Bands: Dynamic Excursion Envelope & Baseline Curve
    for (int b = 0; b < bands.length; b++) {
      final band = bands[b];
      if (!band.enabled) continue;

      final color =
          DynamicEqGraph.bandColors[b % DynamicEqGraph.bandColors.length];
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

    // 5. Draw Master Combined Composite Curve (Clean Hairline, No Glow)
    final masterPath = Path();
    masterPath.moveTo(xCoords[0], dbToY(totalDbCurve[0]));
    for (int i = 1; i < numPoints; i++) {
      masterPath.lineTo(xCoords[i], dbToY(totalDbCurve[i]));
    }

    // Clean, crisp master line
    final masterStrokePaint = Paint()
      ..color = primaryColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(masterPath, masterStrokePaint);

    // Subtle master gradient fill down to 0 dB line
    final masterFillPath = Path.from(masterPath);
    masterFillPath.lineTo(xCoords.last, zeroY);
    masterFillPath.lineTo(xCoords.first, zeroY);
    masterFillPath.close();

    final masterFillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          primaryColor.withValues(alpha: 0.08),
          primaryColor.withValues(alpha: 0.0),
        ],
      ).createShader(
          Rect.fromLTWH(paddingLeft, paddingTop, graphWidth, graphHeight))
      ..style = PaintingStyle.fill;
    canvas.drawPath(masterFillPath, masterFillPaint);

    // 5b. Draw Real-Time Live Gain Excursion Composite Curve
    if (hasLiveActivity) {
      final livePath = Path();
      livePath.moveTo(xCoords[0], dbToY(liveTotalDbCurve[0]));
      for (int i = 1; i < numPoints; i++) {
        livePath.lineTo(xCoords[i], dbToY(liveTotalDbCurve[i]));
      }

      final liveFillPath = Path.from(livePath)
        ..lineTo(xCoords.last, zeroY)
        ..lineTo(xCoords.first, zeroY)
        ..close();

      canvas.drawPath(
        liveFillPath,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              const Color(0xFF00E676).withValues(alpha: 0.16),
              const Color(0xFF00E676).withValues(alpha: 0.0),
            ],
          ).createShader(
              Rect.fromLTWH(paddingLeft, paddingTop, graphWidth, graphHeight))
          ..style = PaintingStyle.fill,
      );

      canvas.drawPath(
        livePath,
        Paint()
          ..color = const Color(0xFF00E676).withValues(alpha: 0.92)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0
          ..strokeCap = StrokeCap.round,
      );
    }

    // 6. Draw Band Center Handles & Badges (Clean Studio Aesthetic)
    for (int b = 0; b < bands.length; b++) {
      final band = bands[b];
      if (!band.enabled) continue;

      final color =
          DynamicEqGraph.bandColors[b % DynamicEqGraph.bandColors.length];
      final isSelected = b == selectedBandIndex;
      final freq = band.freqHz.clamp(minFreq, maxFreq);

      final logRatio = math.log(freq / minFreq) / math.log(maxFreq / minFreq);
      final handleX = paddingLeft + logRatio * graphWidth;

      // Net gain at center frequency
      final coeffs = _computeSvfCoeffs(
        band.filterType,
        band.freqHz,
        band.q,
        band.baseGainDb,
        sampleRate,
      );
      final bandNetDb = _evalSvfGainDb(coeffs, freq, sampleRate);
      final handleY = dbToY(bandNetDb);

      final liveOffset =
          (liveGainOffsetsDb != null && b < liveGainOffsetsDb!.length)
              ? liveGainOffsetsDb![b]
              : 0.0;
      if (liveOffset.abs() > 0.02) {
        final liveCoeffs = _computeSvfCoeffs(
          band.filterType,
          band.freqHz,
          band.q,
          (band.baseGainDb + liveOffset).clamp(-36.0, 36.0),
          sampleRate,
        );
        final liveY = dbToY(_evalSvfGainDb(liveCoeffs, freq, sampleRate));
        canvas.drawLine(
          Offset(handleX, handleY),
          Offset(handleX, liveY),
          Paint()
            ..color = color.withValues(alpha: 0.85)
            ..strokeWidth = 1.6,
        );
        canvas.drawCircle(
          Offset(handleX, liveY),
          3.2,
          Paint()..color = color,
        );
      }

      // Selected clean outer boundary ring (1px stroke, no blur)
      if (isSelected) {
        canvas.drawCircle(
          Offset(handleX, handleY),
          11.0,
          Paint()
            ..color = color.withValues(alpha: 0.75)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.0,
        );
      }

      // Background matte disk
      canvas.drawCircle(
        Offset(handleX, handleY),
        8.0,
        Paint()..color = const Color(0xFF1B1D22),
      );

      // Inner color circle
      canvas.drawCircle(
        Offset(handleX, handleY),
        7.0,
        Paint()..color = isSelected ? color : color.withValues(alpha: 0.85),
      );

      // Clean hairline inner border
      canvas.drawCircle(
        Offset(handleX, handleY),
        7.0,
        Paint()
          ..color = Colors.white.withValues(alpha: 0.35)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.8,
      );

      // Band Number Label (1-6)
      final textSpan = TextSpan(
        text: '${b + 1}',
        style: TextStyle(
          color: Colors.white,
          fontSize: isSelected ? 9.0 : 8.0,
          fontWeight: FontWeight.w700,
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
        final step =
            math.min(remainingInState, segmentLength - currentSegmentPos);

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

  // --- Exact Cytomic SVF & Orfanidis Math matching dsp/dynamic_eq_dsp.h ---

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

  _DynamicSvfCoeffs _computeSvfCoeffs(
    DynamicEqFilterType type,
    double freqHz,
    double q,
    double gainDb,
    double fs,
  ) {
    final clampedGain = gainDb.clamp(-36.0, 36.0);
    if (clampedGain.abs() < 0.005) {
      return const _DynamicSvfCoeffs(isFlat: true);
    }

    final fc = freqHz.clamp(10.0, fs * 0.499);
    final clampedQ = (q > 0.05 ? q : 1.0).clamp(0.05, 30.0);
    final w0 = 2.0 * math.pi * fc / fs;
    final a = math.pow(10.0, clampedGain / 40.0).toDouble();
    final k0 = 1.0 / clampedQ;
    final t0 = math.tan(w0 * 0.5);

    switch (type) {
      case DynamicEqFilterType.peak:
        final absGainDb = clampedGain.abs();
        final aPos = math.pow(10.0, absGainDb / 40.0).toDouble();
        final gPos = aPos * aPos;
        final gb = aPos;

        final r = math.sqrt(1.0 + 1.0 / (4.0 * clampedQ * clampedQ)) -
            1.0 / (2.0 * clampedQ);
        final w1 = w0 * r;
        final t1 = math.tan(0.5 * w1);

        final uNyq = math.pi / w0;
        final oneMinusU2 = 1.0 - uNyq * uNyq;
        final bwTermNum = (aPos * uNyq) / clampedQ;
        final bwTermDen = uNyq / (clampedQ * aPos);
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

        if (clampedGain >= 0.0) {
          final gOut = math.sqrt(w2);
          final kOut = bd / gOut;
          return _DynamicSvfCoeffs(
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
          return _DynamicSvfCoeffs(
            g: gOut,
            k: kOut,
            m0: invG1,
            m1: ((bd * invG1) / gOut) - invG1 * kOut,
            m2: 1.0 - invG1,
            isFlat: false,
          );
        }

      case DynamicEqFilterType.lowShelf:
        return _DynamicSvfCoeffs(
          g: t0 / math.sqrt(a),
          k: k0,
          m0: 1.0,
          m1: k0 * (a - 1.0),
          m2: a * a - 1.0,
          isFlat: false,
        );

      case DynamicEqFilterType.highShelf:
        final absGainDb = clampedGain.abs();
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
          kEff = cand.clamp(0.25 * k0, 4.0 * k0).toDouble();
        }

        if (clampedGain >= 0.0) {
          return _DynamicSvfCoeffs(
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
          return _DynamicSvfCoeffs(
            g: gBoost / sqrtG1,
            k: kCut,
            m0: invG1,
            m1: (kEff / sqrtG1) - invG1 * kCut,
            m2: 1.0 - invG1,
            isFlat: false,
          );
        }
    }
  }

  double _evalSvfGainDb(_DynamicSvfCoeffs c, double f, double fs) {
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

  @override
  bool shouldRepaint(covariant _DynamicEqPainter oldDelegate) {
    if (oldDelegate.isEnabled != isEnabled ||
        oldDelegate.primaryColor != primaryColor ||
        oldDelegate.sampleRate != sampleRate ||
        oldDelegate.selectedBandIndex != selectedBandIndex ||
        oldDelegate.bands.length != bands.length) {
      return true;
    }
    for (int i = 0; i < bands.length; i++) {
      final a = oldDelegate.bands[i];
      final b = bands[i];
      if (a.filterType != b.filterType ||
          a.mode != b.mode ||
          a.freqHz != b.freqHz ||
          a.q != b.q ||
          a.baseGainDb != b.baseGainDb ||
          a.thresholdDb != b.thresholdDb ||
          a.rangeDb != b.rangeDb ||
          a.ratio != b.ratio ||
          a.enabled != b.enabled) {
        return true;
      }
    }
    final oldLive = oldDelegate.liveGainOffsetsDb;
    final curLive = liveGainOffsetsDb;
    if ((oldLive == null) != (curLive == null)) return true;
    if (oldLive != null && curLive != null) {
      if (oldLive.length != curLive.length) return true;
      for (int i = 0; i < curLive.length; i++) {
        if ((oldLive[i] - curLive[i]).abs() > 1e-4) return true;
      }
    }
    return false;
  }
}
