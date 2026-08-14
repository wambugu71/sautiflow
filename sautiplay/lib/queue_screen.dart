import 'dart:io';
import 'dart:ui';
import 'dart:typed_data';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:flutter_m3shapes_extended/flutter_m3shapes_extended.dart';
import 'package:mini_music_visualizer/mini_music_visualizer.dart';
import 'package:sautiflow/sautiflow.dart';
import 'album_detail_screen.dart'; // For TrackInfo
import 'services/app_theme_service.dart';
import 'widgets/adaptive_marquee_text.dart';
import 'widgets/local_album_art.dart';

class QueueScreen extends StatefulWidget {
  final List<TrackInfo> queue;
  final String? videoId;
  final Uint8List? albumArt;
  final void Function(int) onPlayQueueIndex;
  final void Function(int, int) onReorderQueue;
  final void Function(int)? onRemoveFromQueue;
  final ValueNotifier<PlayerStatus>? statusNotifier;
  final VoidCallback? onClose;

  const QueueScreen({
    super.key,
    required this.queue,
    this.videoId,
    this.albumArt,
    required this.onPlayQueueIndex,
    required this.onReorderQueue,
    this.onRemoveFromQueue,
    this.statusNotifier,
    this.onClose,
  });

  @override
  State<QueueScreen> createState() => _QueueScreenState();
}

class _QueueScreenState extends State<QueueScreen>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;
  late ScrollController _scrollController;
  int? _lastPlayingIndex;
  bool _hasInitialScrolled = false;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _lastPlayingIndex = _getPlayingIndex(widget.statusNotifier?.value);
    widget.statusNotifier?.addListener(_onStatusChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_hasInitialScrolled) {
        _scrollToPlayingItem(animate: false);
        _hasInitialScrolled = true;
      }
    });
  }

  @override
  void didUpdateWidget(QueueScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.statusNotifier != widget.statusNotifier) {
      oldWidget.statusNotifier?.removeListener(_onStatusChanged);
      widget.statusNotifier?.addListener(_onStatusChanged);
    }
    if (oldWidget.videoId != widget.videoId ||
        oldWidget.queue != widget.queue) {
      final newIndex = _getPlayingIndex(widget.statusNotifier?.value);
      if (_lastPlayingIndex != newIndex) {
        _lastPlayingIndex = newIndex;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _scrollToPlayingItem(animate: true);
        });
      }
    }
  }

  @override
  void dispose() {
    widget.statusNotifier?.removeListener(_onStatusChanged);
    _scrollController.dispose();
    super.dispose();
  }

  void _onStatusChanged() {
    if (!mounted) return;
    final newIndex = _getPlayingIndex(widget.statusNotifier?.value);

    // Performance optimization: Avoid rebuilding the queue screen on playback position ticks.
    // Only update state if the current playing index actually changed.
    if (_lastPlayingIndex == newIndex) {
      return;
    }

    _lastPlayingIndex = newIndex;
    setState(() {});

    _scrollToPlayingItem(animate: true);
  }

  int _getPlayingIndex(PlayerStatus? status) {
    if (widget.queue.isEmpty) return -1;

    final currentVideoId = widget.videoId;
    if (currentVideoId != null && currentVideoId.isNotEmpty) {
      final idx = widget.queue.indexWhere((t) => t.videoId == currentVideoId);
      if (idx != -1) return idx;
    }

    if (status != null &&
        status.currentIndex >= 0 &&
        status.currentIndex < widget.queue.length) {
      return status.currentIndex;
    }

    return -1;
  }

  void _scrollToPlayingItem({bool animate = true}) {
    if (!_scrollController.hasClients || widget.queue.isEmpty) return;

    final status = widget.statusNotifier?.value;
    final index = _getPlayingIndex(status);
    if (index < 0) return;

    const double itemHeight = 76.0;
    final double screenHeight = _scrollController.position.viewportDimension;
    double targetOffset =
        (index * itemHeight) - (screenHeight / 2.0) + (itemHeight / 2.0);

    final double maxScroll = _scrollController.position.maxScrollExtent;
    targetOffset = targetOffset.clamp(0.0, maxScroll);

    if (animate) {
      _scrollController.animateTo(
        targetOffset,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
      );
    } else {
      _scrollController.jumpTo(targetOffset);
    }
  }

  String _calculateTotalDuration() {
    int totalSec = 0;
    int count = 0;
    for (final track in widget.queue) {
      if (track.durationSeconds != null && track.durationSeconds! > 0) {
        totalSec += track.durationSeconds!;
        count++;
      }
    }
    if (count == 0 || totalSec == 0) {
      return '${widget.queue.length} tracks';
    }

    final hours = totalSec ~/ 3600;
    final mins = (totalSec % 3600) ~/ 60;

    final durationStr = hours > 0 ? '${hours}h ${mins}m' : '$mins min';

    return '${widget.queue.length} tracks • $durationStr';
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final Color primaryColor = context.primaryColor;
    final Color bgColor = context.bgDark;
    final Color textPrimary = context.textPrimary;
    final Color textDark = context.textMuted;
    final Color surfaceDark = context.cardDark;
    final Color outlineColor = context.outlineColor;

    final playingIndex = _getPlayingIndex(widget.statusNotifier?.value);

    return Scaffold(
      backgroundColor: bgColor,
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600.0),
            child: Column(
              children: [
                const SizedBox(height: 12),
                // ── Top Header matching M3E Design ──
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12.0, vertical: 4.0),
                  child: Row(
                    children: [
                      M3EIconButton(
                        icon: const Icon(Icons.keyboard_arrow_down, size: 28),
                        variant: M3EIconButtonVariant.standard,
                        onPressed:
                            widget.onClose ?? () => Navigator.of(context).pop(),
                      ),
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Center drag handle pill for sheet representation
                            Container(
                              width: 38,
                              height: 4,
                              margin: const EdgeInsets.only(bottom: 6),
                              decoration: BoxDecoration(
                                color: outlineColor,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  'Up Next',
                                  style: TextStyle(
                                    color: textPrimary,
                                    fontSize: 17,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: -0.3,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: primaryColor.withValues(alpha: 0.18),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color:
                                          primaryColor.withValues(alpha: 0.35),
                                      width: 1,
                                    ),
                                  ),
                                  child: Text(
                                    'QUEUE',
                                    style: TextStyle(
                                      color: primaryColor,
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 1.0,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 3),
                            Text(
                              _calculateTotalDuration(),
                              style: TextStyle(
                                color: textDark,
                                fontSize: 12,
                                fontWeight: FontWeight.w400,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      if (widget.queue.isNotEmpty)
                        M3EIconButton(
                          icon: const Icon(Icons.my_location_rounded, size: 20),
                          variant: M3EIconButtonVariant.tonal,
                          tooltip: 'Center playing track',
                          onPressed: () => _scrollToPlayingItem(animate: true),
                        )
                      else
                        const SizedBox(width: 44),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                // ── Main Queue Content ──
                Expanded(
                  child: widget.queue.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              M3EContainer(
                                Shapes.c4SidedCookie,
                                width: 88,
                                height: 88,
                                color: primaryColor.withValues(alpha: 0.12),
                                border: BorderSide(
                                  color: primaryColor.withValues(alpha: 0.3),
                                  width: 1.5,
                                ),
                                child: Center(
                                  child: Icon(Icons.queue_music_rounded,
                                      color: primaryColor, size: 40),
                                ),
                              ),
                              const SizedBox(height: 20),
                              Text(
                                'Queue is empty',
                                style: TextStyle(
                                  color: textPrimary,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Play a track or album to populate the playback queue',
                                style: TextStyle(
                                  color: textDark,
                                  fontSize: 13.5,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        )
                      : Theme(
                          data: Theme.of(context).copyWith(
                            canvasColor: Colors.transparent,
                          ),
                          child: ReorderableListView.builder(
                            scrollController: _scrollController,
                            physics: const BouncingScrollPhysics(
                                parent: AlwaysScrollableScrollPhysics()),
                            itemCount: widget.queue.length,
                            onReorder: widget.onReorderQueue,
                            proxyDecorator:
                                (Widget child, int index, Animation<double> animation) {
                              return AnimatedBuilder(
                                animation: animation,
                                builder: (BuildContext context, Widget? child) {
                                  final double animValue =
                                      Curves.easeInOut.transform(animation.value);
                                  final double scale =
                                      lerpDouble(1.0, 1.025, animValue)!;
                                  return Transform.scale(
                                    scale: scale,
                                    child: Material(
                                      elevation: 10,
                                      shadowColor:
                                          primaryColor.withValues(alpha: 0.4),
                                      color: Colors.transparent,
                                      borderRadius: BorderRadius.circular(16),
                                      child: child,
                                    ),
                                  );
                                },
                                child: child,
                              );
                            },
                            itemBuilder: (context, index) {
                              final track = widget.queue[index];
                              final isPlaying = (playingIndex == index) ||
                                  (widget.videoId != null &&
                                      track.videoId == widget.videoId);

                              return RepaintBoundary(
                                key: ValueKey('${track.videoId}_$index'),
                                child: Container(
                                  margin: const EdgeInsets.symmetric(
                                      vertical: 3.5, horizontal: 12),
                                  decoration: BoxDecoration(
                                    color: isPlaying
                                        ? primaryColor.withValues(alpha: 0.16)
                                        : surfaceDark,
                                    borderRadius: BorderRadius.circular(16),
                                    border: isPlaying
                                        ? Border.all(
                                            color: primaryColor.withValues(
                                                alpha: 0.6),
                                            width: 1.5,
                                          )
                                        : Border.all(
                                            color: outlineColor.withValues(alpha: 0.3)),
                                    boxShadow: isPlaying
                                        ? [
                                            BoxShadow(
                                              color: primaryColor.withValues(
                                                  alpha: 0.22),
                                              blurRadius: 14,
                                              spreadRadius: 0,
                                              offset: const Offset(0, 3),
                                            ),
                                          ]
                                        : null,
                                  ),
                                  child: ListTile(
                                    contentPadding: const EdgeInsets.only(
                                        left: 10, right: 12, top: 3, bottom: 3),
                                    leading: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        // Track index number or playing icon indicator
                                        SizedBox(
                                          width: 24,
                                          child: isPlaying
                                              ? Icon(
                                                  Icons.volume_up_rounded,
                                                  color: primaryColor,
                                                  size: 17)
                                              : Text(
                                                  '${index + 1}',
                                                  textAlign: TextAlign.center,
                                                  style: TextStyle(
                                                    color: textDark,
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                        ),
                                        const SizedBox(width: 8),
                                        _QueueTrackArtwork(
                                          track: track,
                                          isPlaying: isPlaying,
                                          albumArt: widget.albumArt,
                                          primaryColor: primaryColor,
                                        ),
                                      ],
                                    ),
                                    title: isPlaying
                                        ? AdaptiveMarqueeText(
                                            text: track.title,
                                            style: TextStyle(
                                              color: primaryColor,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 15,
                                            ),
                                            blankSpace: 30.0,
                                            velocity: 30.0,
                                          )
                                        : Text(
                                            track.title,
                                            style: TextStyle(
                                              color: textPrimary,
                                              fontWeight: FontWeight.w500,
                                              fontSize: 15,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                    subtitle: Row(
                                      children: [
                                        if (isPlaying) ...[
                                          RepaintBoundary(
                                            child: MiniMusicVisualizer(
                                              color: primaryColor,
                                              width: 3,
                                              height: 12,
                                              animate: true,
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                        ],
                                        Expanded(
                                          child: Text(
                                            track.artist,
                                            style: TextStyle(
                                              color: isPlaying
                                                  ? primaryColor.withValues(
                                                      alpha: 0.88)
                                                  : Colors.white
                                                      .withValues(alpha: 0.5),
                                              fontWeight: isPlaying
                                                  ? FontWeight.w600
                                                  : FontWeight.normal,
                                              fontSize: 13,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        if (track.durationSeconds != null &&
                                            track.durationSeconds! > 0)
                                          Text(
                                            _formatDuration(
                                                track.durationSeconds),
                                            style: TextStyle(
                                              color: Colors.white
                                                  .withValues(alpha: 0.35),
                                              fontSize: 11,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                      ],
                                    ),
                                    trailing: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        if (widget.onRemoveFromQueue != null)
                                          M3EIconButton(
                                            icon: const Icon(
                                                Icons.close_rounded,
                                                size: 18),
                                            variant: M3EIconButtonVariant.standard,
                                            visualSize: const Size(32, 32),
                                            tooltip: 'Remove from queue',
                                            onPressed: () =>
                                                widget.onRemoveFromQueue!(
                                                    index),
                                          ),
                                        const SizedBox(width: 4),
                                        ReorderableDragStartListener(
                                          index: index,
                                          child: const Padding(
                                            padding: EdgeInsets.all(6.0),
                                            child: Icon(
                                              Icons.drag_handle_rounded,
                                              color: Colors.white38,
                                              size: 22,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    onTap: () {
                                      widget.onPlayQueueIndex(index);
                                    },
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String _formatDuration(int? seconds) {
    if (seconds == null || seconds <= 0) return '';
    final m = seconds ~/ 60;
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}

/// Memoized track artwork component wrapped in RepaintBoundary to eliminate synchronous disk/render repaints.
class _QueueTrackArtwork extends StatelessWidget {
  final TrackInfo track;
  final bool isPlaying;
  final Uint8List? albumArt;
  final Color primaryColor;

  const _QueueTrackArtwork({
    required this.track,
    required this.isPlaying,
    this.albumArt,
    required this.primaryColor,
  });

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: SizedBox(
          width: 48,
          height: 48,
          child: Stack(
            children: [
              Positioned.fill(
                child: _buildArtworkContent(),
              ),
              if (isPlaying)
                Positioned.fill(
                  child: RepaintBoundary(
                    child: Container(
                      color: Colors.black.withValues(alpha: 0.45),
                      child: Center(
                        child: MiniMusicVisualizer(
                          color: primaryColor,
                          width: 4,
                          height: 16,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildArtworkContent() {
    if (isPlaying && albumArt != null && albumArt!.isNotEmpty) {
      return Image.memory(
        albumArt!,
        fit: BoxFit.cover,
      );
    }

    final thumb = track.thumbnailUrl;
    if (thumb != null &&
        (thumb.startsWith('http://') || thumb.startsWith('https://'))) {
      return CachedNetworkImage(
        imageUrl: thumb,
        fit: BoxFit.cover,
        placeholder: (_, __) => Container(
          color: Colors.white.withValues(alpha: 0.05),
          child: const Icon(Icons.music_note, color: Colors.white24, size: 20),
        ),
        errorWidget: (_, __, ___) => _buildFallbackArt(),
      );
    }

    // Local file artwork check without synchronous File.existsSync() blocking
    if (thumb != null && thumb.isNotEmpty && !thumb.startsWith('http')) {
      return Image.file(
        File(thumb),
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _buildFallbackArt(),
      );
    }

    // Fallback to local audio extractor if track.videoId looks like a file path
    if (track.videoId.contains('/') ||
        track.videoId.contains('\\') ||
        track.videoId.endsWith('.mp3') ||
        track.videoId.endsWith('.flac') ||
        track.videoId.endsWith('.m4a')) {
      return LocalAlbumArt(
        path: track.videoId,
        size: 48,
        borderRadius: 10,
        fallbackIcon: Icons.music_note,
      );
    }

    return _buildFallbackArt();
  }

  Widget _buildFallbackArt() {
    return Container(
      decoration: const BoxDecoration(
        image: DecorationImage(
          image: AssetImage('assets/icon/splash.png'),
          fit: BoxFit.cover,
        ),
      ),
    );
  }
}

