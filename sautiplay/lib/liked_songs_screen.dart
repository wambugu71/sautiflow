import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/liked_song.dart';
import '../services/liked_songs_service.dart';

class LikedSongsScreen extends StatefulWidget {
  final Future<void> Function(List<LikedSong> tracks, {int initialIndex})
      onPlayTracks;

  const LikedSongsScreen({
    super.key,
    required this.onPlayTracks,
  });

  @override
  State<LikedSongsScreen> createState() => _LikedSongsScreenState();
}

class _LikedSongsScreenState extends State<LikedSongsScreen> {
  @override
  Widget build(BuildContext context) {
    const Color bgDark = Color(0xFF121212); // background-dark from mockup
    const Color primaryColor = Color(0xFF256AF4); // primary from mockup

    return Scaffold(
      backgroundColor: bgDark,
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
              decoration: BoxDecoration(
                color: bgDark.withOpacity(0.95),
                border: Border(
                  bottom: BorderSide(color: Colors.white.withOpacity(0.05)),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back, color: Colors.white),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                      const Text(
                        'Liked Songs',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          letterSpacing: -0.5,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Content
            Expanded(
              child: ValueListenableBuilder<List<LikedSong>>(
                valueListenable: LikedSongsService.instance.likedSongsNotifier,
                builder: (context, likedSongs, _) {
                  if (likedSongs.isEmpty) {
                    return const Center(
                      child: Text(
                        'No liked songs yet.',
                        style: TextStyle(color: Color(0xFFA0A0A0)),
                      ),
                    );
                  }

                  return ListView.builder(
                    padding: const EdgeInsets.only(top: 16, bottom: 120),
                    itemCount: likedSongs.length,
                    itemBuilder: (context, index) {
                      final track = likedSongs[index];
                      return _buildTrackItem(track, likedSongs, index);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTrackItem(
      LikedSong track, List<LikedSong> allTracks, int index) {
    return InkWell(
      onTap: () {
        widget.onPlayTracks(allTracks, initialIndex: index);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
        child: Row(
          children: [
            // Thumbnail
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                color: const Color(0xFF1E1E1E),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.4),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: track.thumbnailUrl != null
                    ? CachedNetworkImage(
                        imageUrl: track.thumbnailUrl!,
                        fit: BoxFit.cover,
                        errorWidget: (context, url, error) =>
                            const Icon(Icons.music_note, color: Colors.white54),
                      )
                    : const Icon(Icons.music_note, color: Colors.white54),
              ),
            ),
            const SizedBox(width: 16),

            // Text Details
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          track.title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (!track.isLocal) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                                color: Colors.white.withOpacity(0.05)),
                          ),
                          child: const Text(
                            'ONLINE',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFFA0A0A0),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${track.artist} • ${_formatDuration(track.durationSeconds)}',
                    style: const TextStyle(
                      color: Color(0xFFA0A0A0),
                      fontSize: 14,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),

            // Like toggle / Context Menu Button
            IconButton(
              icon: const Icon(Icons.favorite, color: Color(0xFF256AF4)),
              onPressed: () async {
                await LikedSongsService.instance.removeLikedSong(track.videoId);
              },
            ),
          ],
        ),
      ),
    );
  }

  String _formatDuration(int seconds) {
    if (seconds <= 0) return 'Unknown';
    final d = Duration(seconds: seconds);
    final min = d.inMinutes;
    final sec = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$min:$sec';
  }
}
