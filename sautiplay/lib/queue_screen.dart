import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'album_detail_screen.dart'; // For TrackInfo

class QueueScreen extends StatefulWidget {
  final List<TrackInfo> queue;
  final String? videoId;
  final Uint8List? albumArt;
  final void Function(int) onPlayQueueIndex;
  final void Function(int, int) onReorderQueue;

  const QueueScreen({
    super.key,
    required this.queue,
    this.videoId,
    this.albumArt,
    required this.onPlayQueueIndex,
    required this.onReorderQueue,
  });

  @override
  State<QueueScreen> createState() => _QueueScreenState();
}

class _QueueScreenState extends State<QueueScreen> {
  late ScrollController _scrollController;
  bool _hasScrolled = false;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_hasScrolled && widget.queue.isNotEmpty) {
        final playingIndex =
            widget.queue.indexWhere((t) => t.videoId == widget.videoId);
        if (playingIndex > 0 && _scrollController.hasClients) {
          _scrollController.jumpTo(playingIndex * 68.0);
        }
        _hasScrolled = true;
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
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
                  final currentVideoId = widget.videoId;
                  final isPlaying = currentVideoId != null &&
                      track.videoId == currentVideoId;

                  return Card(
                    key: ValueKey(track.videoId + index.toString()),
                    color: isPlaying
                        ? primaryColor.withValues(alpha: 0.15)
                        : Colors.white.withValues(alpha: 0.04),
                    elevation: 0,
                    margin: const EdgeInsets.symmetric(
                        vertical: 4, horizontal: 16),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      leading: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: SizedBox(
                          width: 48,
                          height: 48,
                          child: isPlaying && widget.albumArt != null
                              ? Image.memory(
                                  widget.albumArt!,
                                  fit: BoxFit.cover,
                                )
                              : track.thumbnailUrl != null
                                  ? Image.network(
                                      track.thumbnailUrl!,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) => const Icon(
                                          Icons.music_note,
                                          color: Colors.white54),
                                    )
                                  : const Icon(Icons.music_note,
                                      color: Colors.white54),
                        ),
                      ),
                      title: Text(
                        track.title,
                        style: TextStyle(
                          color: isPlaying
                              ? primaryColor
                              : Colors.white.withValues(alpha: 0.9),
                          fontWeight: isPlaying
                              ? FontWeight.bold
                              : FontWeight.w500,
                          fontSize: 15,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        track.artist,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.5),
                          fontSize: 13,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: ReorderableDragStartListener(
                        index: index,
                        child: const Icon(Icons.drag_handle,
                            color: Colors.white54),
                      ),
                      onTap: () {
                        widget.onPlayQueueIndex(index);
                        Navigator.of(context).pop();
                      },
                    ),
                  );
                },
              ),
            ),
    );
  }
}
