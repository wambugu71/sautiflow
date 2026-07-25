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
  final ValueNotifier<PlayerStatus>? statusNotifier;

  const QueueScreen({
    super.key,
    required this.queue,
    this.videoId,
    this.albumArt,
    required this.onPlayQueueIndex,
    required this.onReorderQueue,
    this.statusNotifier,
  });

  @override
  State<QueueScreen> createState() => _QueueScreenState();
}

class _QueueScreenState extends State<QueueScreen> {
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
    if (oldWidget.videoId != widget.videoId) {
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
    final indexChanged = _lastPlayingIndex != null && _lastPlayingIndex != newIndex;
    _lastPlayingIndex = newIndex;

    setState(() {});

    if (indexChanged) {
      _scrollToPlayingItem(animate: true);
    }
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

  @override
  Widget build(BuildContext context) {
    const Color primaryColor = Color(0xFF137FEC);
    const Color bgColor = Color(0xFF101922);

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Up Next',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              '${widget.queue.length} tracks',
              style: const TextStyle(
                color: Colors.white38,
                fontSize: 13,
              ),
            ),
          ],
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          if (widget.queue.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.my_location, color: primaryColor),
              tooltip: 'Center playing track',
              onPressed: () => _scrollToPlayingItem(animate: true),
            ),
        ],
      ),
      body: widget.queue.isEmpty
          ? const Center(
              child: Text(
                'Queue is empty',
                style: TextStyle(color: Colors.white54, fontSize: 16),
              ),
            )
          : Theme(
              data: Theme.of(context).copyWith(
                canvasColor: Colors.transparent,
              ),
              child: ReorderableListView.builder(
                scrollController: _scrollController,
                itemCount: widget.queue.length,
                onReorder: widget.onReorderQueue,
                itemBuilder: (context, index) {
                  final track = widget.queue[index];
                  final status = widget.statusNotifier?.value;
                  final playingIndex = _getPlayingIndex(status);
                  final isPlaying = (playingIndex == index) ||
                      (widget.videoId != null && track.videoId == widget.videoId);

                  return Container(
                    key: ValueKey(track.videoId + index.toString()),
                    margin: const EdgeInsets.symmetric(
                        vertical: 4, horizontal: 16),
                    decoration: BoxDecoration(
                      color: isPlaying
                          ? primaryColor.withValues(alpha: 0.18)
                          : Colors.white.withValues(alpha: 0.04),
                      borderRadius: BorderRadius.circular(12),
                      border: isPlaying
                          ? Border.all(
                              color: primaryColor.withValues(alpha: 0.6),
                              width: 1.5,
                            )
                          : Border.all(color: Colors.transparent),
                      boxShadow: isPlaying
                          ? [
                              BoxShadow(
                                color: primaryColor.withValues(alpha: 0.25),
                                blurRadius: 10,
                                spreadRadius: 1,
                              ),
                            ]
                          : null,
                    ),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      leading: _buildTrackLeading(track, isPlaying, primaryColor),
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
                                color: Colors.white.withValues(alpha: 0.9),
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
                              animate: true
                            ),
                            const SizedBox(width: 6),
                          ],
                          Expanded(
                            child: Text(
                              track.artist,
                              style: TextStyle(
                                color: isPlaying
                                    ? primaryColor.withValues(alpha: 0.85)
                                    : Colors.white.withValues(alpha: 0.5),
                                fontWeight: isPlaying
                                    ? FontWeight.w600
                                    : FontWeight.normal,
                                fontSize: 13,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      trailing: ReorderableDragStartListener(
                        index: index,
                        child: const Icon(Icons.drag_handle,
                            color: Colors.white54),
                      ),
                      onTap: () {
                        widget.onPlayQueueIndex(index);
                      },
                    ),
                  );
                },
              ),
            ),
    );
  }

  Widget _buildTrackLeading(TrackInfo track, bool isPlaying, Color primaryColor) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: 48,
        height: 48,
        child: Stack(
          children: [
            Positioned.fill(
              child: _buildArtworkImage(track, isPlaying),
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

  Widget _buildArtworkImage(TrackInfo track, bool isPlaying) {
    if (isPlaying && widget.albumArt != null && widget.albumArt!.isNotEmpty) {
      return Image.memory(
        widget.albumArt!,
        fit: BoxFit.cover,
      );
    }

    if (track.thumbnailUrl != null &&
        (track.thumbnailUrl!.startsWith('http://') ||
            track.thumbnailUrl!.startsWith('https://'))) {
      return CachedNetworkImage(
        imageUrl: track.thumbnailUrl!,
        fit: BoxFit.cover,
        placeholder: (_, __) => Container(
          color: Colors.white.withValues(alpha: 0.05),
          child: const Icon(Icons.music_note, color: Colors.white24, size: 20),
        ),
        errorWidget: (_, __, ___) => _buildFallbackArt(),
      );
    }

    if (track.thumbnailUrl != null && File(track.thumbnailUrl!).existsSync()) {
      return Image.file(
        File(track.thumbnailUrl!),
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _buildFallbackArt(),
      );
    }

    if (File(track.videoId).existsSync()) {
      return LocalAlbumArt(
        path: track.videoId,
        size: 48,
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
