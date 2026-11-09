import 'dart:async';
import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

/// Displays [text] on a single line, switching automatically to an optimized,
/// hardware-accelerated horizontal marquee when [text] overflows the available
/// bounded width.
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

  /// Delay before the marquee starts scrolling on mount or text update.
  ///
  /// Defaults to 650ms so bottom sheet entrance transitions and route changes
  /// open fluidly at 60/120fps with zero competing text animations.
  final Duration startAfter;

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
    this.startAfter = const Duration(milliseconds: 650),
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

        // Constrain marquee width to the available bounded slot.
        // The Marquee internally isolates its animation using RepaintBoundary
        // so scrolling text never triggers repaints of parent sheets or containers.
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
            startAfter: startAfter,
            startPadding: 0.0,
            accelerationDuration: const Duration(milliseconds: 500),
            accelerationCurve: Curves.easeIn,
            decelerationDuration: const Duration(milliseconds: 500),
            decelerationCurve: Curves.easeOut,
            fadingEdgeStartFraction: fadingEdgeStartFraction,
            fadingEdgeEndFraction: fadingEdgeEndFraction,
            textWidth: tp.width,
          ),
        );
      },
    );
  }
}

/// A lightweight, hardware-accelerated marquee widget designed for butter-smooth
/// 60/120fps scrolling without [ShaderMask] saveLayer or [ListView] viewport overhead.
///
/// Features:
/// - Isolated GPU layer: Wraps scrolling text in [RepaintBoundary] so animation ticks
///   never invalidate or re-render parent bottom sheets, dialogs, or lists.
/// - Static render tree: Animated using [Transform.translate] on an [OverflowBox] child
///   passed to [AnimatedBuilder], eliminating [Widget] / [RenderObject] rebuilds.
/// - Sheet-friendly start delay: Default [startAfter] (650ms) lets bottom sheets
///   and dialogs complete entrance animations before marquee motion begins.
class Marquee extends StatefulWidget {
  /// The text string to scroll.
  final String text;

  /// The text style.
  final TextStyle style;

  /// Text direction.
  final TextDirection textDirection;

  /// Scroll axis (horizontal or vertical).
  final Axis scrollAxis;

  /// Cross-axis alignment.
  final CrossAxisAlignment crossAxisAlignment;

  /// Spacing between looped text instances in logical pixels.
  final double blankSpace;

  /// Scroll speed in logical pixels per second.
  final double velocity;

  /// Pause duration after each completed scroll loop.
  final Duration pauseAfterRound;

  /// Delay before scrolling starts after mount or text change.
  final Duration startAfter;

  /// Starting offset padding.
  final double startPadding;

  /// Acceleration duration.
  final Duration accelerationDuration;

  /// Acceleration curve.
  final Curve accelerationCurve;

  /// Deceleration duration.
  final Duration decelerationDuration;

  /// Deceleration curve.
  final Curve decelerationCurve;

  /// Start fading edge fraction (0.0 to 0.5).
  final double fadingEdgeStartFraction;

  /// End fading edge fraction (0.0 to 0.5).
  final double fadingEdgeEndFraction;

  /// Optional pre-measured text width to skip duplicate [TextPainter] layout.
  final double? textWidth;

  const Marquee({
    super.key,
    required this.text,
    required this.style,
    this.textDirection = TextDirection.ltr,
    this.scrollAxis = Axis.horizontal,
    this.crossAxisAlignment = CrossAxisAlignment.start,
    this.blankSpace = 40.0,
    this.velocity = 30.0,
    this.pauseAfterRound = const Duration(seconds: 2),
    this.startAfter = const Duration(milliseconds: 650),
    this.startPadding = 0.0,
    this.accelerationDuration = const Duration(milliseconds: 500),
    this.accelerationCurve = Curves.easeIn,
    this.decelerationDuration = const Duration(milliseconds: 500),
    this.decelerationCurve = Curves.easeOut,
    this.fadingEdgeStartFraction = 0.0,
    this.fadingEdgeEndFraction = 0.0,
    this.textWidth,
  });

  @override
  State<Marquee> createState() => _MarqueeState();
}

class _MarqueeState extends State<Marquee> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  Timer? _timer;
  double _measuredTextWidth = 0.0;
  bool _running = false;

  @override
  void initState() {
    super.initState();
    _measuredTextWidth = widget.textWidth ?? 0.0;
    _controller = AnimationController(vsync: this);
    _controller.addStatusListener(_handleAnimationStatus);
    _scheduleStart();
  }

  void _scheduleStart() {
    _timer?.cancel();
    _controller.stop();
    _controller.value = 0.0;
    _running = false;

    if (widget.startAfter > Duration.zero) {
      _timer = Timer(widget.startAfter, () {
        if (mounted) _startScroll();
      });
    } else {
      _startScroll();
    }
  }

  void _startScroll() {
    if (!mounted || _measuredTextWidth <= 0.0) return;
    _running = true;
    _animateRound();
  }

  void _animateRound() {
    if (!mounted || !_running) return;
    final totalDistance = _measuredTextWidth + widget.blankSpace;
    final durationMs =
        (totalDistance / math.max(1.0, widget.velocity) * 1000).round();
    _controller.duration = Duration(milliseconds: math.max(100, durationMs));
    _controller.forward(from: 0.0);
  }

  void _handleAnimationStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed && mounted && _running) {
      if (widget.pauseAfterRound > Duration.zero) {
        _timer = Timer(widget.pauseAfterRound, () {
          if (mounted && _running) {
            _animateRound();
          }
        });
      } else {
        _animateRound();
      }
    }
  }

  @override
  void didUpdateWidget(Marquee oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text ||
        oldWidget.style != widget.style ||
        oldWidget.velocity != widget.velocity ||
        oldWidget.blankSpace != widget.blankSpace ||
        oldWidget.startAfter != widget.startAfter) {
      _measuredTextWidth = widget.textWidth ?? 0.0;
      _scheduleStart();
    }
  }

  @override
  void dispose() {
    _running = false;
    _timer?.cancel();
    _controller.removeStatusListener(_handleAnimationStatus);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_measuredTextWidth <= 0.0) {
      final textScaler = MediaQuery.textScalerOf(context);
      final tp = TextPainter(
        text: TextSpan(text: widget.text, style: widget.style),
        maxLines: 1,
        textDirection: widget.textDirection,
        textScaler: textScaler,
      )..layout(maxWidth: double.infinity);
      _measuredTextWidth = tp.width;
      if (!_running && (_timer == null || !_timer!.isActive)) {
        _scheduleStart();
      }
    }

    final isRtl = widget.textDirection == TextDirection.rtl;
    final totalDistance = _measuredTextWidth + widget.blankSpace;

    Widget content = AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final progress = _controller.value;
        final offset =
            isRtl ? progress * totalDistance : -progress * totalDistance;
        return Transform.translate(
          offset: Offset(offset, 0.0),
          child: child,
        );
      },
      child: OverflowBox(
        alignment: isRtl ? Alignment.centerRight : Alignment.centerLeft,
        minWidth: 0.0,
        maxWidth: double.infinity,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.text,
              style: widget.style,
              textDirection: widget.textDirection,
              maxLines: 1,
              softWrap: false,
            ),
            SizedBox(width: widget.blankSpace),
            Text(
              widget.text,
              style: widget.style,
              textDirection: widget.textDirection,
              maxLines: 1,
              softWrap: false,
            ),
          ],
        ),
      ),
    );

    if (widget.fadingEdgeStartFraction > 0.0 ||
        widget.fadingEdgeEndFraction > 0.0) {
      final startFrac = widget.fadingEdgeStartFraction.clamp(0.0, 0.5);
      final endFrac = widget.fadingEdgeEndFraction.clamp(0.0, 0.5);
      content = ShaderMask(
        shaderCallback: (bounds) {
          return LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            stops: [0.0, startFrac, 1.0 - endFrac, 1.0],
            colors: [
              startFrac > 0 ? Colors.transparent : Colors.white,
              Colors.white,
              Colors.white,
              endFrac > 0 ? Colors.transparent : Colors.white,
            ],
          ).createShader(bounds);
        },
        blendMode: BlendMode.dstIn,
        child: content,
      );
    }

    return RepaintBoundary(
      child: ClipRect(
        child: content,
      ),
    );
  }
}
