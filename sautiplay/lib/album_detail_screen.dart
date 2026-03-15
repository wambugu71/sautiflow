import 'package:flutter/material.dart';
import 'package:dart_ytmusic_api/dart_ytmusic_api.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:loading_indicator_m3e/loading_indicator_m3e.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart' as yte;

import 'models/liked_song.dart';
import 'services/liked_songs_service.dart';

// ─ Colors (matching the existing app theme) ─
const _bgDark = Color(0xFF101922);
const _surfaceDark = Color(0xFF1C252E);
const _primary = Color(0xFF137fec);

/// Unified track model that works with both dart_ytmusic_api and youtube_explode_dart
class TrackInfo {
  final String videoId;
  final String title;
  final String artist;
  final String? thumbnailUrl;
  final int? durationSeconds;

  TrackInfo({
    required this.videoId,
    required this.title,
    required this.artist,
    this.thumbnailUrl,
    this.durationSeconds,
  });

  /// From JSON for persistence
  factory TrackInfo.fromJson(Map<String, dynamic> json) {
    return TrackInfo(
      videoId: json['videoId'] as String,
      title: json['title'] as String,
      artist: json['artist'] as String,
      thumbnailUrl: json['thumbnailUrl'] as String?,
      durationSeconds: json['durationSeconds'] as int?,
    );
  }

  /// To JSON for persistence
  Map<String, dynamic> toJson() {
    return {
      'videoId': videoId,
      'title': title,
      'artist': artist,
      if (thumbnailUrl != null) 'thumbnailUrl': thumbnailUrl,
      if (durationSeconds != null) 'durationSeconds': durationSeconds,
    };
  }

  /// From dart_ytmusic_api SongDetailed
  factory TrackInfo.fromSongDetailed(SongDetailed song) {
    String? thumb;
    if (song.thumbnails.isNotEmpty) {
      final sorted = List<ThumbnailFull>.from(song.thumbnails)
        ..sort((a, b) => b.width.compareTo(a.width));
      thumb = sorted.first.url;
    }
    return TrackInfo(
      videoId: song.videoId,
      title: song.name,
      artist: song.artist.name,
      thumbnailUrl: thumb,
      durationSeconds: song.duration,
    );
  }

  /// From youtube_explode_dart Video
  factory TrackInfo.fromYTExplodeVideo(yte.Video video) {
    return TrackInfo(
      videoId: video.id.value,
      title: video.title,
      artist: video.author,
      thumbnailUrl: video.thumbnails.highResUrl,
      durationSeconds: video.duration?.inSeconds,
    );
  }
}

class AlbumDetailScreen extends StatefulWidget {
  /// The tapped item from the home screen (AlbumDetailed, PlaylistDetailed, or SongDetailed)
  final dynamic item;

  /// Callback to start streaming playback from the parent
  final Future<void> Function(List<TrackInfo> tracks, {int initialIndex})?
      onPlayTracks;

  const AlbumDetailScreen({super.key, required this.item, this.onPlayTracks});

  @override
  State<AlbumDetailScreen> createState() => _AlbumDetailScreenState();
}

class _AlbumDetailScreenState extends State<AlbumDetailScreen> {
  final YTMusic _ytMusic = YTMusic();
  List<TrackInfo> _tracks = [];
  bool _loading = true;
  String? _error;

  // Extracted info
  String _title = '';
  String _artist = '';
  String? _year;
  String? _thumbnailUrl;
  String _screenLabel = 'ALBUM';

  @override
  void initState() {
    super.initState();
    _extractInfo();
    _loadSongs();
  }

  void _extractInfo() {
    final item = widget.item;
    if (item is AlbumDetailed) {
      _title = item.name;
      _artist = item.artist.name;
      _year = item.year?.toString();
      _thumbnailUrl = _bestThumb(item.thumbnails);
      _screenLabel = 'ALBUM';
    } else if (item is PlaylistDetailed) {
      _title = item.name;
      _artist = item.artist.name;
      _thumbnailUrl = _bestThumb(item.thumbnails);
      _screenLabel = 'PLAYLIST';
    } else if (item is SongDetailed) {
      _title = item.name;
      _artist = item.artist.name;
      _thumbnailUrl = _bestThumb(item.thumbnails);
      _screenLabel = 'SONG';
    }
  }

  String? _bestThumb(List<ThumbnailFull> thumbs) {
    if (thumbs.isEmpty) return null;
    thumbs.sort((a, b) => b.width.compareTo(a.width));
    return thumbs.first.url;
  }

  Future<void> _loadSongs() async {
    try {
      final item = widget.item;

      if (item is AlbumDetailed) {
        // Use dart_ytmusic_api for albums
        await _ytMusic.initialize();
        if (item.albumId.isNotEmpty) {
          try {
            final album = await _ytMusic.getAlbum(item.albumId);
            if (mounted) {
              setState(() {
                _tracks = album.songs
                    .map((s) => TrackInfo.fromSongDetailed(s))
                    .toList();
                _loading = false;
                if (album.year != null) _year = album.year.toString();
              });
            }
            return;
          } catch (e) {
            debugPrint('getAlbum failed for ${item.albumId}: $e');
          }
        }
        if (mounted) setState(() => _loading = false);
      } else if (item is PlaylistDetailed) {
        // Use youtube_explode_dart for playlists (dart_ytmusic_api is broken for RDCLAK IDs)
        final ytExplode = yte.YoutubeExplode();
        try {
          final List<TrackInfo> tracks = [];
          await for (final video in ytExplode.playlists
              .getVideos(yte.PlaylistId(item.playlistId))) {
            tracks.add(TrackInfo.fromYTExplodeVideo(video));
          }
          if (mounted) {
            setState(() {
              _tracks = tracks;
              _loading = false;
            });
          }
        } catch (e) {
          debugPrint('YTExplode getPlaylist failed: $e');
          if (mounted) {
            setState(() {
              _error = e.toString();
              _loading = false;
            });
          }
        } finally {
          ytExplode.close();
        }
      } else if (item is SongDetailed) {
        // Show the song + load related tracks via getUpNexts
        await _ytMusic.initialize();
        final List<TrackInfo> trackList = [TrackInfo.fromSongDetailed(item)];
        try {
          final upNexts = await _ytMusic.getUpNexts(item.videoId);
          for (final next in upNexts) {
            trackList.add(TrackInfo(
              videoId: next.videoId,
              title: next.title,
              artist: next.artists.name,
              thumbnailUrl:
                  next.thumbnails.isNotEmpty ? next.thumbnails.first.url : null,
              durationSeconds: next.duration,
            ));
          }
        } catch (e) {
          debugPrint('getUpNexts failed: $e');
        }
        if (mounted) {
          setState(() {
            _tracks = trackList;
            _loading = false;
          });
        }
      } else {
        if (mounted) setState(() => _loading = false);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  String _formatDuration(int? seconds) {
    if (seconds == null || seconds <= 0) return '--:--';
    final m = (seconds ~/ 60).toString();
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgDark,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          // ── App Bar ──
          SliverAppBar(
            backgroundColor: _bgDark.withValues(alpha: 0.9),
            elevation: 0,
            pinned: true,
            leading: IconButton(
              icon:
                  const Icon(Icons.arrow_back_outlined, color: Colors.white70),
              onPressed: () => Navigator.of(context).pop(),
            ),
            centerTitle: true,
            title: Text(_screenLabel,
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.5),
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 1.5)),
            /*  actions: [
              IconButton(
                icon: const Icon(Icons.more_vert, color: Colors.white70),
                onPressed: () {},
              ),
            ],*/
          ),

          // ── Hero Section ──
          SliverToBoxAdapter(child: _buildHero()),

          // ── Track List Header ──
          SliverToBoxAdapter(child: _buildTrackListHeader()),

          // ── Tracks ──
          if (_loading)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                  child: LoadingIndicatorM3E(
                      color: _primary, containerColor: _primary.withAlpha(50))),
            )
          else if (_error != null)
            SliverFillRemaining(hasScrollBody: false, child: _buildError())
          else if (_tracks.isEmpty)
            SliverFillRemaining(hasScrollBody: false, child: _buildEmpty())
          else
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, i) => _buildTrackRow(i, _tracks[i]),
                childCount: _tracks.length,
              ),
            ),

          // Bottom padding
          const SliverToBoxAdapter(child: SizedBox(height: 120)),
        ],
      ),
    );
  }

  Widget _buildHero() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
      child: Column(
        children: [
          // Album art with glow
          Center(
            child: SizedBox(
              width: 240,
              height: 240,
              child: Stack(
                children: [
                  // Glow behind
                  Positioned.fill(
                    child: Container(
                      margin: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: _primary.withValues(alpha: 0.35),
                            blurRadius: 50,
                            spreadRadius: 5,
                          ),
                        ],
                      ),
                    ),
                  ),
                  // Art
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                            color: Colors.white.withValues(alpha: 0.1)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.4),
                            blurRadius: 20,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: _thumbnailUrl != null
                          ? CachedNetworkImage(
                              imageUrl: _thumbnailUrl!,
                              fit: BoxFit.cover,
                              placeholder: (_, __) => Container(
                                color: _surfaceDark,
                                child: const Center(
                                    child: Icon(Icons.album,
                                        color: Colors.white24, size: 48)),
                              ),
                              errorWidget: (_, __, ___) => Container(
                                color: _surfaceDark,
                                child: const Center(
                                    child: Icon(Icons.album,
                                        color: Colors.white24, size: 48)),
                              ),
                            )
                          : Container(
                              color: _surfaceDark,
                              child: const Center(
                                  child: Icon(Icons.album,
                                      color: Colors.white24, size: 48)),
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 24),

          // Title
          Text(_title,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  height: 1.2)),

          const SizedBox(height: 8),

          // Artist + Year
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(_artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.7),
                        fontSize: 16,
                        fontWeight: FontWeight.w500)),
              ),
              if (_year != null) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Container(
                    width: 4,
                    height: 4,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withValues(alpha: 0.3),
                    ),
                  ),
                ),
                Text(_year!,
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.4),
                        fontSize: 14)),
              ],
            ],
          ),

          //  const SizedBox(height: 6),

          // Label
          /* Text('HI-RES LOSSLESS',
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.2),
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 2)),
*/
          const SizedBox(height: 28),

          // Action buttons
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Save
              ValueListenableBuilder<List<LikedSong>>(
                valueListenable: LikedSongsService.instance.likedSongsNotifier,
                builder: (context, likedSongs, _) {
                  bool isSaved = false;
                  if (_tracks.isNotEmpty) {
                    isSaved = _tracks.every((track) =>
                        likedSongs.any((s) => s.videoId == track.videoId));
                  }
                  return _buildActionButton(
                    icon: isSaved ? Icons.favorite : Icons.favorite_border,
                    label: isSaved ? 'SAVED' : 'SAVE',
                    iconColor: isSaved ? _primary : null,
                    onTap: () async {
                      if (_tracks.isEmpty) return;
                      if (isSaved) {
                        for (final track in _tracks) {
                          await LikedSongsService.instance
                              .removeLikedSong(track.videoId);
                        }
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text('Removed all from Liked Songs')),
                          );
                        }
                      } else {
                        for (final track in _tracks) {
                          await LikedSongsService.instance
                              .addLikedSong(LikedSong(
                            videoId: track.videoId,
                            title: track.title,
                            artist: track.artist,
                            thumbnailUrl: track.thumbnailUrl ?? _thumbnailUrl,
                            durationSeconds: track.durationSeconds ?? 0,
                            likedAt: DateTime.now(),
                          ));
                        }
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text('Saved all to Liked Songs')),
                          );
                        }
                      }
                    },
                  );
                },
              ),
              const SizedBox(width: 28),
              // Play
              GestureDetector(
                onTap: () {
                  if (widget.onPlayTracks != null && _tracks.isNotEmpty) {
                    Navigator.of(context).pop();
                    widget.onPlayTracks!(_tracks, initialIndex: 0);
                  }
                },
                child: Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _primary,
                    boxShadow: [
                      BoxShadow(
                        color: _primary.withValues(alpha: 0.4),
                        blurRadius: 24,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: const Icon(Icons.play_arrow,
                      color: Colors.white, size: 38),
                ),
              ),
              const SizedBox(width: 28),
              // Shuffle
              _buildActionButton(
                icon: Icons.shuffle,
                label: 'SHUFFLE',
                onTap: () {
                  if (widget.onPlayTracks != null && _tracks.isNotEmpty) {
                    final shuffledTracks = List<TrackInfo>.from(_tracks)
                      ..shuffle();
                    Navigator.of(context).pop();
                    widget.onPlayTracks!(shuffledTracks, initialIndex: 0);
                  }
                },
                iconColor: _primary,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Color? iconColor,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: 0.05),
              border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
            ),
            child: Icon(icon, color: iconColor ?? Colors.white54, size: 26),
          ),
          const SizedBox(height: 6),
          Text(label,
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.35),
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1)),
        ],
      ),
    );
  }

  Widget _buildTrackListHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text('#   TITLE',
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.3),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1)),
          Icon(Icons.schedule,
              size: 16, color: Colors.white.withValues(alpha: 0.3)),
        ],
      ),
    );
  }

  Widget _buildTrackRow(int index, TrackInfo track) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          if (widget.onPlayTracks != null && _tracks.isNotEmpty) {
            Navigator.of(context).pop(); // Go back to main shell
            widget.onPlayTracks!(_tracks, initialIndex: index);
          }
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: const BoxDecoration(
            border: Border(
              left: BorderSide(
                color: Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: Row(
            children: [
              // Track number
              SizedBox(
                width: 28,
                child: Text(
                  '${index + 1}',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.4),
                      fontWeight: FontWeight.w500,
                      fontSize: 14),
                ),
              ),
              const SizedBox(width: 12),

              // Thumbnail (small)
              if (track.thumbnailUrl != null) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: CachedNetworkImage(
                    imageUrl: track.thumbnailUrl!,
                    width: 40,
                    height: 40,
                    fit: BoxFit.cover,
                    placeholder: (_, __) => Container(
                      width: 40,
                      height: 40,
                      color: _surfaceDark,
                    ),
                    errorWidget: (_, __, ___) => Container(
                      width: 40,
                      height: 40,
                      color: _surfaceDark,
                      child: const Icon(Icons.music_note,
                          color: Colors.white24, size: 18),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
              ],

              // Song info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(track.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w500,
                            fontSize: 14)),
                    const SizedBox(height: 2),
                    Text(track.artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.4),
                            fontSize: 12)),
                  ],
                ),
              ),

              // Duration
              Padding(
                padding: const EdgeInsets.only(left: 12),
                child: Text(
                  _formatDuration(track.durationSeconds),
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.4),
                      fontWeight: FontWeight.w500,
                      fontSize: 13),
                ),
              ),

              // More button
              const SizedBox(width: 4),
              Icon(Icons.more_vert,
                  size: 20, color: Colors.white.withValues(alpha: 0.3)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline,
                size: 48, color: Colors.white.withValues(alpha: 0.3)),
            const SizedBox(height: 16),
            Text('Failed to load tracks',
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.6),
                    fontSize: 16,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text(_error ?? '',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.35), fontSize: 12)),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  _loading = true;
                  _error = null;
                });
                _loadSongs();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: _primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20)),
              ),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.queue_music,
              size: 48, color: Colors.white.withValues(alpha: 0.2)),
          const SizedBox(height: 16),
          Text('No tracks available',
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.5),
                  fontSize: 15,
                  fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}
