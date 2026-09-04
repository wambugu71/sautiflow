import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../models/liked_song.dart';
import '../services/app_theme_service.dart';
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
  Color get bgDark => AppThemeService.instance.currentData.bgDark;
  Color get primaryColor => AppThemeService.instance.currentData.primary;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth >= 800;
        final contentMaxWidth = isDesktop ? 1000.0 : double.infinity;

        return Scaffold(
          backgroundColor: bgDark,
          body: SafeArea(
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: contentMaxWidth),
                child: Column(
                  children: [
                    // Header
                    Container(
                      padding: EdgeInsets.fromLTRB(
                          isDesktop ? 32 : 24,
                          isDesktop ? 32 : 24,
                          isDesktop ? 32 : 24,
                          isDesktop ? 24 : 16),
                      decoration: BoxDecoration(
                        color: bgDark.withOpacity(0.95),
                        border: Border(
                          bottom:
                              BorderSide(color: Colors.white.withOpacity(0.05)),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              IconButton(
                                icon: Icon(Icons.keyboard_arrow_down,
                                    color: Colors.white,
                                    size: isDesktop ? 28 : 24),
                                onPressed: () => Navigator.of(context).pop(),
                              ),
                              SizedBox(width: isDesktop ? 16 : 0),
                              Text(
                                'Liked Songs',
                                style: TextStyle(
                                  fontSize: isDesktop ? 36 : 28,
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
                        valueListenable:
                            LikedSongsService.instance.likedSongsNotifier,
                        builder: (context, likedSongs, _) {
                          if (likedSongs.isEmpty) {
                            return Center(
                              child: Text(
                                'No liked songs yet.',
                                style: TextStyle(
                                    color: const Color(0xFFA0A0A0),
                                    fontSize: isDesktop ? 18 : 14),
                              ),
                            );
                          }

                          return ListView.builder(
                            padding:
                                const EdgeInsets.only(top: 16, bottom: 120),
                            itemCount: likedSongs.length,
                            itemBuilder: (context, index) {
                              final track = likedSongs[index];
                              return _buildTrackItem(track, likedSongs, index,
                                  isDesktop: isDesktop);
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildTrackItem(LikedSong track, List<LikedSong> allTracks, int index,
      {bool isDesktop = false}) {
    return InkWell(
      onTap: () {
        widget.onPlayTracks(allTracks, initialIndex: index);
        Navigator.of(context).popUntil((route) => route.isFirst);
      },
      child: Padding(
        padding: EdgeInsets.symmetric(
            horizontal: isDesktop ? 32.0 : 16.0,
            vertical: isDesktop ? 12.0 : 8.0),
        child: Row(
          children: [
            // Thumbnail
            Container(
              width: isDesktop ? 72 : 56,
              height: isDesktop ? 72 : 56,
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
                        memCacheWidth: 160,
                        memCacheHeight: 160,
                        errorWidget: (context, url, error) => Icon(
                            Icons.music_note,
                            color: Colors.white54,
                            size: isDesktop ? 32 : 24),
                      )
                    : Icon(Icons.music_note,
                        color: Colors.white54, size: isDesktop ? 32 : 24),
              ),
            ),
            SizedBox(width: isDesktop ? 24 : 16),

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
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: isDesktop ? 18 : 16,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (!track.isLocal) ...[
                        SizedBox(width: isDesktop ? 12 : 8),
                        Container(
                          padding: EdgeInsets.symmetric(
                              horizontal: isDesktop ? 8 : 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                                color: Colors.white.withOpacity(0.05)),
                          ),
                          child: Text(
                            'ONLINE',
                            style: TextStyle(
                              fontSize: isDesktop ? 12 : 10,
                              fontWeight: FontWeight.bold,
                              color: const Color(0xFFA0A0A0),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  SizedBox(height: isDesktop ? 6 : 4),
                  Text(
                    '${track.artist} • ${_formatDuration(track.durationSeconds)}',
                    style: TextStyle(
                      color: const Color(0xFFA0A0A0),
                      fontSize: isDesktop ? 15 : 14,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),

            // Like toggle / Context Menu Button
            IconButton(
              icon: Icon(Icons.favorite,
                  color: primaryColor, size: isDesktop ? 28 : 24),
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
