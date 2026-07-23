import 'package:flutter/material.dart';
import 'package:marquee/marquee.dart';

class AdaptiveMarqueeText extends StatelessWidget {
  final String text;
  final TextStyle style;
  final double? height;
  final double velocity;
  final double blankSpace;
  final Duration pauseAfterRound;

  const AdaptiveMarqueeText({
    super.key,
    required this.text,
    required this.style,
    this.height,
    this.velocity = 30.0,
    this.blankSpace = 40.0,
    this.pauseAfterRound = const Duration(seconds: 2),
  });

  @override
  Widget build(BuildContext context) {
    if (text.isEmpty) {
      return Text('', style: style);
    }

    final double effectiveHeight = height ?? ((style.fontSize ?? 14.0) * 1.35);

    return LayoutBuilder(
      builder: (context, constraints) {
        final textScaler = MediaQuery.textScalerOf(context);
        final textSpan = TextSpan(text: text, style: style);
        final tp = TextPainter(
          text: textSpan,
          maxLines: 1,
          textDirection: TextDirection.ltr,
          textScaler: textScaler,
        )..layout(maxWidth: double.infinity);

        // If constraints are bounded and text fits within available width, render static text.
        if (constraints.hasBoundedWidth && tp.width <= constraints.maxWidth) {
          return Text(
            text,
            style: style,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          );
        }

        // Otherwise (text overflows or width is unconstrained), render Marquee.
        return SizedBox(
          height: effectiveHeight,
          child: Marquee(
            text: text,
            style: style,
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
          ),
        );
      },
    );
  }
}
