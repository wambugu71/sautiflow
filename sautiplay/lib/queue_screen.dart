import 'dart:io';
import 'dart:typed_data';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:mini_music_visualizer/mini_music_visualizer.dart';
import 'package:sautiflow/sautiflow.dart';
import 'album_detail_screen.dart'; // For TrackInfo
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

    const double itemHeight = 72.0;
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
    const Color primaryColor = Color(0xFF137FEC);
    const Color bgColor = Color(0xFF101922);

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
                const SizedBox(height: 16),
                // ── Top Header matching NowPlayingScreen top level exactly ──
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8.0, vertical: 4.0),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.keyboard_arrow_down,
                            color: Colors.white, size: 32),
                        onPressed:
                            widget.onClose ?? () => Navigator.of(context).pop(),
                      ),
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Center drag handle pill for sheet representation
                            Container(
                              width: 36,
                              height: 4,
                              margin: const EdgeInsets.only(bottom: 4),
                              decoration: BoxDecoration(
                                color: Colors.white24,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Text(
                                  'Up Next',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: -0.3,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 1.5),
                                  decoration: BoxDecoration(
                                    color: primaryColor.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Text(
                                    'QUEUE',
                                    style: TextStyle(
                                      color: primaryColor,
                                      fontSize: 9,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 0.8,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _calculateTotalDuration(),
                              style: const TextStyle(
                                color: Colors.white38,
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
                        IconButton(
                          icon: const Icon(Icons.my_location_rounded,
                              color: primaryColor, size: 22),
                          tooltip: 'Center playing track',
                          onPressed: () => _scrollToPlayingItem(animate: true),
                        )
                      else
                        const SizedBox(width: 48),
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
                              Container(
                                width: 72,
                                height: 72,
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.04),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.queue_music_rounded,
                                    color: Colors.white30, size: 36),
                              ),
                              const SizedBox(height: 16),
                              const Text(
                                'Queue is empty',
                                style: TextStyle(
                                    color: Colors.white70,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600),
                              ),
                              const SizedBox(height: 4),
                              const Text(
                                'Play a track or album to populate the queue',
                                style: TextStyle(
                                    color: Colors.white38, fontSize: 13),
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
                            itemBuilder: (context, index) {
                              final track = widget.queue[index];
                              final isPlaying = (playingIndex == index) ||
                                  (widget.videoId != null &&
                                      track.videoId == widget.videoId);

                              return Container(
                                key: ValueKey('${track.videoId}_$index'),
                                margin: const EdgeInsets.symmetric(
                                    vertical: 3, horizontal: 12),
                                decoration: BoxDecoration(
                                  color: isPlaying
                                      ? primaryColor.withValues(alpha: 0.16)
                                      : Colors.white.withValues(alpha: 0.035),
                                  borderRadius: BorderRadius.circular(14),
                                  border: isPlaying
                                      ? Border.all(
                                          color: primaryColor.withValues(
                                              alpha: 0.55),
                                          width: 1.5,
                                        )
                                      : Border.all(
                                          color: Colors.white
                                              .withValues(alpha: 0.03)),
                                  boxShadow: isPlaying
                                      ? [
                                          BoxShadow(
                                            color: primaryColor.withValues(
                                                alpha: 0.22),
                                            blurRadius: 12,
                                            spreadRadius: 0,
                                            offset: const Offset(0, 2),
                                          ),
                                        ]
                                      : null,
                                ),
                                child: ListTile(
                                  contentPadding: const EdgeInsets.only(
                                      left: 8, right: 12, top: 2, bottom: 2),
                                  leading: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      // Track index number or playing icon indicator
                                      SizedBox(
                                        width: 24,
                                        child: isPlaying
                                            ? const Icon(
                                                Icons.volume_up_rounded,
                                                color: primaryColor,
                                                size: 16)
                                            : Text(
                                                '${index + 1}',
                                                textAlign: TextAlign.center,
                                                style: const TextStyle(
                                                  color: Colors.white30,
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                      ),
                                      const SizedBox(width: 6),
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
                                          style: const TextStyle(
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
                                            color: Colors.white
                                                .withValues(alpha: 0.92),
                                            fontWeight: FontWeight.w500,
                                            fontSize: 15,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                  subtitle: Row(
                                    children: [
                                      if (isPlaying) ...[
                                        MiniMusicVisualizer(
                                          color: primaryColor,
                                          width: 3,
                                          height: 12,
                                          animate: true,
                                        ),
                                        const SizedBox(width: 6),
                                      ],
                                      Expanded(
                                        child: Text(
                                          track.artist,
                                          style: TextStyle(
                                            color: isPlaying
                                                ? primaryColor.withValues(
                                                    alpha: 0.85)
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
                                        IconButton(
                                          icon: const Icon(Icons.close_rounded,
                                              size: 18, color: Colors.white30),
                                          padding: EdgeInsets.zero,
                                          constraints: const BoxConstraints(),
                                          splashRadius: 18,
                                          tooltip: 'Remove from queue',
                                          onPressed: () =>
                                              widget.onRemoveFromQueue!(index),
                                        ),
                                      const SizedBox(width: 6),
                                      ReorderableDragStartListener(
                                        index: index,
                                        child: const Padding(
                                          padding: EdgeInsets.all(4.0),
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

/// Memoized track artwork component to eliminate synchronous disk checking during scrolling.
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
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: 46,
        height: 46,
        child: Stack(
          children: [
            Positioned.fill(
              child: _buildArtworkContent(),
            ),
            if (isPlaying)
              Positioned.fill(
                child: Container(
                  color: Colors.black.withValues(alpha: 0.45),
                  child: Center(
                    child: MiniMusicVisualizer(
                      color: primaryColor,
                      width: 4,
                      height: 15,
                    ),
                  ),
                ),
              ),
          ],
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
        size: 46,
        borderRadius: 8,
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
