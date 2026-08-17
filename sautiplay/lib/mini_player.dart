import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_m3shapes_extended/flutter_m3shapes_extended.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import 'services/app_state_service.dart';
import 'services/app_theme_service.dart';
import 'widgets/adaptive_marquee_text.dart';

class MiniPlayer extends StatefulWidget {
  final String title;
  final String artist;
  final Uint8List? albumArt;
  final double progress; // 0.0 to 1.0
  final bool isPlaying;
  final VoidCallback onPlayPause;
  final VoidCallback onNext;
  final VoidCallback? onPrevious;
  final VoidCallback onTap;

  const MiniPlayer({
    super.key,
    required this.title,
    required this.artist,
    this.albumArt,
    this.progress = 0.0,
    required this.isPlaying,
    required this.onPlayPause,
    required this.onNext,
    this.onPrevious,
    required this.onTap,
  });

  @override
  State<MiniPlayer> createState() => _MiniPlayerState();
}

class _MiniPlayerState extends State<MiniPlayer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _rotationController;
  bool _isDragging = false;
  double _dragOffsetX = 0.0;

  @override
  void initState() {
    super.initState();
    _rotationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 20),
    );
    if (widget.isPlaying) {
      _rotationController.repeat();
    }
    AppStateService.instance.loadUseWavySlider();
  }

  @override
  void reassemble() {
    super.reassemble();
    AppStateService.instance.loadUseWavySlider();
  }

  @override
  void didUpdateWidget(MiniPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isPlaying != oldWidget.isPlaying) {
      if (widget.isPlaying) {
        _rotationController.repeat();
      } else {
        _rotationController.stop();
      }
    }
  }

  @override
  void dispose() {
    _rotationController.dispose();
    super.dispose();
  }

  void _handleDragUpdate(DragUpdateDetails details) {
    setState(() {
      _isDragging = true;
      _dragOffsetX += details.delta.dx;
    });
  }

  void _handleDragEnd(DragEndDetails details) {
    const double swipeThreshold = 40.0;
    final velocity = details.primaryVelocity ?? 0.0;

    if (_dragOffsetX < -swipeThreshold || velocity < -200) {
      // Swiped left -> next track
      widget.onNext();
    } else if (_dragOffsetX > swipeThreshold || velocity > 200) {
      // Swiped right -> previous track
      widget.onPrevious?.call();
    }

    setState(() {
      _isDragging = false;
      _dragOffsetX = 0.0;
    });
  }

  void _handleDragCancel() {
    setState(() {
      _isDragging = false;
      _dragOffsetX = 0.0;
    });
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final slideFraction =
        screenWidth > 0 ? (_dragOffsetX / screenWidth).clamp(-0.25, 0.25) : 0.0;
    final cardColor = context.cardDark;
    final primaryColor = context.primaryColor;
    final textPrimary = context.textPrimary;
    final textMuted = context.textMuted;
    final outlineColor = context.outlineColor;
    final isDark = context.isDark;
    final artShape = context.albumArtShape;

    return GestureDetector(
      onTap: widget.onTap,
      onHorizontalDragUpdate: _handleDragUpdate,
      onHorizontalDragEnd: _handleDragEnd,
      onHorizontalDragCancel: _handleDragCancel,
      child: AnimatedSlide(
        duration:
            _isDragging ? Duration.zero : const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
        offset: Offset(slideFraction, 0),
        child: Container(
          height: 64,
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.08),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
            border: Border.all(
              color: outlineColor,
              width: 1,
            ),
          ),
          child: Column(
            children: [
              ValueListenableBuilder<bool>(
                valueListenable: AppStateService.instance.useWavySliderNotifier,
                builder: (context, useWavy, _) {
                  if (useWavy) {
                    return M3EProgressIndicator.linearWavy(
                      //wavelength: 60,
                      //waveSpeed: 25,
                      strokeWidth: 4,
                      value: widget.progress.clamp(0.0, 1.0),
                      linearSize: M3EProgressIndicatorSize.s,
                      trackColor: Colors.transparent,
                      color: primaryColor,
                    );
                  }
                  return M3EProgressIndicator.linear(
                    value: widget.progress.clamp(0.0, 1.0),
                    linearSize: M3EProgressIndicatorSize.s,
                    trackColor: Colors.transparent,
                    color: primaryColor,
                  );
                },
              ),
              // Main content
              Expanded(
                child: Row(
                  children: [
                    // Album Art
                    Padding(
                      padding: const EdgeInsets.only(
                          left: 8, right: 0, top: 0, bottom: 4),
                      child: M3EContainer(
                        artShape,
                        width: 48,
                        height: 48,
                        clipBehavior: Clip.antiAlias,
                        color: cardColor,
                        child: (widget.albumArt != null &&
                                widget.albumArt!.isNotEmpty)
                            ? Image.memory(
                                widget.albumArt!,
                                fit: BoxFit.cover,
                                cacheWidth: 120,
                                cacheHeight: 120,
                              )
                            : RotationTransition(
                                turns: _rotationController,
                                child: Image.asset(
                                  'assets/icon/splash.png',
                                  fit: BoxFit.contain,
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    // Track Info
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          AdaptiveMarqueeText(
                            text: widget.title,
                            style: TextStyle(
                              color: textPrimary,
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                            height: 20,
                            velocity: 25.0,
                            blankSpace: 30.0,
                            pauseAfterRound: const Duration(seconds: 2),
                          ),
                          Text(
                            widget.artist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: textMuted,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Controls
                    M3EIconButton(
                      onPressed: widget.onPlayPause,
                      icon: Icon(
                        widget.isPlaying
                            ? Icons.pause_circle_filled
                            : Icons.play_circle_filled,
                        size: 32,
                        color: textPrimary,
                      ),
                    ),
                    M3EIconButton(
                      onPressed: widget.onNext,
                      icon: Icon(
                        Icons.skip_next,
                        size: 28,
                        color: textPrimary,
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
