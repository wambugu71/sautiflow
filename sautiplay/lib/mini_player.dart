import 'dart:typed_data';
import 'package:flutter/material.dart';
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
    final slideFraction = screenWidth > 0
        ? (_dragOffsetX / screenWidth).clamp(-0.25, 0.25)
        : 0.0;

    return GestureDetector(
      onTap: widget.onTap,
      onHorizontalDragUpdate: _handleDragUpdate,
      onHorizontalDragEnd: _handleDragEnd,
      onHorizontalDragCancel: _handleDragCancel,
      child: AnimatedSlide(
        duration: _isDragging ? Duration.zero : const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
        offset: Offset(slideFraction, 0),
        child: Container(
        height: 64,
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: AppThemeService.instance.currentData.cardDark, // surfaceDarkColor
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.1),
            width: 1,
          ),
        ),
        child: Column(
          children: [
            // Top Progress Bar
            LinearProgressIndicator(
              value: widget.progress.clamp(0.0, 1.0),
              minHeight: 2,
              backgroundColor: Colors.transparent,
              valueColor:
                  AlwaysStoppedAnimation<Color>(AppThemeService.instance.currentData.primary),
            ),
            // Main content
            Expanded(
              child: Row(
                children: [
                  // Album Art
                  Container(
                    width: 48,
                    height: 48,
                    margin: const EdgeInsets.only(left: 8),
                    decoration: BoxDecoration(
                      color: AppThemeService.instance.currentData.primary
                          .withValues(alpha: 0.2), // primaryColor
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: (widget.albumArt != null && widget.albumArt!.isNotEmpty)
                          ? Container(
                              decoration: BoxDecoration(
                                image: DecorationImage(
                                  image: MemoryImage(widget.albumArt!),
                                  fit: BoxFit.cover,
                                ),
                              ),
                            )
                          : RotationTransition(
                              turns: _rotationController,
                              child: Container(
                                color: AppThemeService.instance.currentData.primary.withValues(alpha: 0.2),
                                padding: const EdgeInsets.all(6.0),
                                child: Image.asset(
                                  'assets/icon/splash.png',
                                  fit: BoxFit.contain,
                                ),
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
                          style: const TextStyle(
                            color: Colors.white,
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
                            color: Colors.white.withValues(alpha: 0.5),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Controls
                  IconButton(
                    onPressed: widget.onPlayPause,
                    icon: Icon(
                      widget.isPlaying
                          ? Icons.pause_circle_filled
                          : Icons.play_circle_filled,
                      size: 32,
                      color: Colors.white,
                    ),
                  ),
                  IconButton(
                    onPressed: widget.onNext,
                    icon: const Icon(
                      Icons.skip_next,
                      size: 28,
                      color: Colors.white,
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
