import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:marquee/marquee.dart';

/// Displays [text] on a single line, switching automatically to a horizontal
/// marquee when [text] overflows the available bounded width.
class AdaptiveMarqueeText extends StatelessWidget {
  /// The text string to render.
  final String text;

  /// The text style applied in both static and marquee modes.
  final TextStyle style;

  /// Optional explicit height override for marquee mode.
  final double? height;

  /// Scroll speed in logical pixels per second when marqueeing.
  final double velocity;

  /// Blank gap between repeated marquee passes in logical pixels.
  final double blankSpace;

  /// Pause duration after each completed marquee pass.
  final Duration pauseAfterRound;

  /// Optional alignment applied when the text fits statically.
  final TextAlign? textAlign;

  /// Optional explicit text direction override.
  final TextDirection? textDirection;

  /// Optional start fading edge fraction (0.0 to 0.5) when marqueeing.
  final double fadingEdgeStartFraction;

  /// Optional end fading edge fraction (0.0 to 0.5) when marqueeing.
  final double fadingEdgeEndFraction;

  /// Creates an adaptive single-line text widget that scrolls when overflowing.
  const AdaptiveMarqueeText({
    super.key,
    required this.text,
    required this.style,
    this.height,
    this.velocity = 30.0,
    this.blankSpace = 40.0,
    this.pauseAfterRound = const Duration(seconds: 2),
    this.textAlign,
    this.textDirection,
    this.fadingEdgeStartFraction = 0.0,
    this.fadingEdgeEndFraction = 0.0,
  });

  @override
  Widget build(BuildContext context) {
    if (text.isEmpty) {
      return Text(
        '',
        style: style,
        textAlign: textAlign,
        textDirection: textDirection,
        maxLines: 1,
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final textScaler = MediaQuery.textScalerOf(context);
        final effectiveDirection = textDirection ??
            Directionality.maybeOf(context) ??
            TextDirection.ltr;
        final textSpan = TextSpan(text: text, style: style);
        final tp = TextPainter(
          text: textSpan,
          maxLines: 1,
          textDirection: effectiveDirection,
          textScaler: textScaler,
        )..layout(maxWidth: double.infinity);

        final double scaledFontHeight =
            textScaler.scale(style.fontSize ?? 14.0) * 1.35;
        final double effectiveHeight =
            height ?? math.max(tp.height + 1.0, scaledFontHeight);

        // Render static text when width is unbounded (avoids unbounded viewport errors)
        // or when the measured single-line width already fits inside available bounds.
        if (!constraints.hasBoundedWidth ||
            tp.width <= constraints.maxWidth + 0.1) {
          return Text(
            text,
            style: style,
            textAlign: textAlign,
            textDirection: textDirection,
            maxLines: 1,
            softWrap: false,
          );
        }

        if (MediaQuery.disableAnimationsOf(context)) {
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Text(
              text,
              style: style,
              textAlign: textAlign,
              textDirection: textDirection,
              maxLines: 1,
              softWrap: false,
            ),
          );
        }

        // Constrain marquee width to the available bounded slot so horizontal ListView
        // receives bounded cross/main extents inside flexible rows and columns.
        return SizedBox(
          width: constraints.maxWidth,
          height: effectiveHeight,
          child: Marquee(
            text: text,
            style: style,
            textDirection: effectiveDirection,
            scrollAxis: Axis.horizontal,
            crossAxisAlignment: CrossAxisAlignment.start,
            blankSpace: blankSpace,
            velocity: velocity,
            pauseAfterRound: pauseAfterRound,
            startPadding: 0.0,
            accelerationDuration: const Duration(milliseconds: 500),
            accelerationCurve: Curves.easeIn,
            decelerationDuration: const Duration(milliseconds: 500),
            decelerationCurve: Curves.easeOut,
            fadingEdgeStartFraction: fadingEdgeStartFraction,
            fadingEdgeEndFraction: fadingEdgeEndFraction,
          ),
        );
      },
    );
  }
}
