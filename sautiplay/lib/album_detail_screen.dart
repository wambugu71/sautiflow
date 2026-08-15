import 'package:cached_network_image/cached_network_image.dart';
import 'package:dart_ytmusic_api/dart_ytmusic_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_m3shapes_extended/flutter_m3shapes_extended.dart';
import 'package:material_3_expressive/material_3_expressive.dart';

import 'models/liked_song.dart';
import 'services/app_theme_service.dart';
import 'services/liked_songs_service.dart';

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

  /// From dart_ytmusic_api VideoDetailed
  factory TrackInfo.fromVideoDetailed(VideoDetailed video) {
    String? thumb;
    if (video.thumbnails.isNotEmpty) {
      final sorted = List<ThumbnailFull>.from(video.thumbnails)
        ..sort((a, b) => b.width.compareTo(a.width));
      thumb = sorted.first.url;
    }
    return TrackInfo(
      videoId: video.videoId,
      title: video.name,
      artist: video.artist.name,
      thumbnailUrl: thumb,
      durationSeconds: video.duration,
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

  Color get _bgDark => context.bgDark;
  Color get _surfaceDark => context.cardDark;
  Color get _primary => context.primaryColor;
  Color get _textPrimary => context.textPrimary;
  Color get _textDark => context.textMuted;
  Color get _outline => context.outlineColor;

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
        String pid = item.playlistId;
        if (pid.startsWith('VL')) pid = pid.substring(2);

        try {
          await _ytMusic.initialize();
          final playlistVideos = await _ytMusic.getPlaylistVideos(pid);
          if (mounted) {
            setState(() {
              _tracks = playlistVideos
                  .map((v) => TrackInfo.fromVideoDetailed(v))
                  .toList();
              _loading = false;
              _error = null;
            });
          }
        } catch (e) {
          debugPrint('dart_ytmusic_api getPlaylistVideos failed: $e');
          if (mounted) {
            setState(() {
              _error = 'Could not load playlist tracks.';
              _loading = false;
            });
          }
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
    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth >= 800;
        final contentMaxWidth = isDesktop ? 1000.0 : double.infinity;

        return Scaffold(
          backgroundColor: _bgDark,
          body: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: contentMaxWidth),
              child: CustomScrollView(
                physics: const BouncingScrollPhysics(),
                slivers: [
                  // ── App Bar ──
                  SliverAppBar(
                    backgroundColor: _bgDark.withValues(alpha: 0.9),
                    elevation: 0,
                    pinned: true,
                    leading: M3EIconButton(
                      icon: const Icon(Icons.arrow_back_rounded, size: 20),
                      variant: M3EIconButtonVariant.tonal,
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    centerTitle: true,
                    title: Text(_screenLabel,
                        style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.5),
                            fontSize: isDesktop ? 16 : 13,
                            fontWeight: FontWeight.w500,
                            letterSpacing: 1.5)),
                  ),

                  // ── Hero Section ──
                  SliverToBoxAdapter(child: _buildHero(isDesktop: isDesktop)),

                  // ── Track List Header ──
                  SliverToBoxAdapter(
                      child: _buildTrackListHeader(isDesktop: isDesktop)),

                  // ── Tracks ──
                  if (_loading)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: RepaintBoundary(
                        child: Center(
                          child: M3ELoadingIndicator(
                            color: _primary,
                            containerColor: _primary.withValues(alpha: 0.15),
                          ),
                        ),
                      ),
                    )
                  else if (_error != null)
                    SliverFillRemaining(
                        hasScrollBody: false,
                        child: _buildError(isDesktop: isDesktop))
                  else if (_tracks.isEmpty)
                    SliverFillRemaining(
                        hasScrollBody: false,
                        child: _buildEmpty(isDesktop: isDesktop))
                  else
                    SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, i) =>
                            _buildTrackRow(i, _tracks[i], isDesktop: isDesktop),
                        childCount: _tracks.length,
                      ),
                    ),

                  // Bottom padding
                  const SliverToBoxAdapter(child: SizedBox(height: 120)),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildHero({bool isDesktop = false}) {
    return Padding(
      padding: EdgeInsets.fromLTRB(isDesktop ? 64 : 24, isDesktop ? 32 : 8,
          isDesktop ? 64 : 24, isDesktop ? 32 : 16),
      child: isDesktop
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _buildHeroArt(isDesktop: isDesktop),
                const SizedBox(width: 48),
                Expanded(child: _buildHeroDetails(isDesktop: isDesktop)),
              ],
            )
          : Column(
              children: [
                _buildHeroArt(isDesktop: isDesktop),
                const SizedBox(height: 24),
                _buildHeroDetails(isDesktop: isDesktop),
              ],
            ),
    );
  }

  Widget _buildHeroArt({bool isDesktop = false}) {
    return Center(
      child: SizedBox(
        width: isDesktop ? 300 : 220,
        height: isDesktop ? 300 : 220,
        child: M3EContainer(
          Shapes.slanted,
          color: _surfaceDark,
          border: BorderSide(
            color: _primary.withValues(alpha: 0.3),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: _primary.withValues(alpha: 0.25),
              blurRadius: isDesktop ? 40 : 24,
              offset: const Offset(0, 8),
            ),
          ],
          clipBehavior: Clip.antiAlias,
          child: _thumbnailUrl != null
              ? CachedNetworkImage(
                  imageUrl: _thumbnailUrl!,
                  fit: BoxFit.cover,
                  memCacheWidth: 600,
                  memCacheHeight: 600,
                  placeholder: (_, __) => Container(
                    color: _surfaceDark,
                    child: Center(
                        child: Icon(Icons.album_rounded,
                            color: Colors.white24, size: isDesktop ? 64 : 48)),
                  ),
                  errorWidget: (_, __, ___) => Container(
                    color: _surfaceDark,
                    child: Center(
                        child: Icon(Icons.album_rounded,
                            color: Colors.white24, size: isDesktop ? 64 : 48)),
                  ),
                )
              : Container(
                  color: _surfaceDark,
                  child: Center(
                      child: Icon(Icons.album_rounded,
                          color: Colors.white24, size: isDesktop ? 64 : 48)),
                ),
        ),
      ),
    );
  }

  Widget _buildHeroDetails({bool isDesktop = false}) {
    return Column(
      crossAxisAlignment:
          isDesktop ? CrossAxisAlignment.start : CrossAxisAlignment.center,
      children: [
        // Title
        Text(_title,
            textAlign: isDesktop ? TextAlign.left : TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                color: Colors.white,
                fontSize: isDesktop ? 42 : 26,
                fontWeight: FontWeight.bold,
                height: 1.2)),

        SizedBox(height: isDesktop ? 16 : 8),

        // Artist + Year
        Row(
          mainAxisAlignment:
              isDesktop ? MainAxisAlignment.start : MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(_artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.7),
                      fontSize: isDesktop ? 20 : 16,
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
                      fontSize: isDesktop ? 18 : 14)),
            ],
          ],
        ),

        SizedBox(height: isDesktop ? 48 : 28),

        // Action buttons
        Row(
          mainAxisAlignment:
              isDesktop ? MainAxisAlignment.start : MainAxisAlignment.center,
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
                  isDesktop: isDesktop,
                  onTap: () async {
                    if (_tracks.isEmpty) return;
                    final messenger = ScaffoldMessenger.of(context);
                    if (isSaved) {
                      for (final track in _tracks) {
                        await LikedSongsService.instance
                            .removeLikedSong(track.videoId);
                      }
                      if (mounted) {
                        messenger.showSnackBar(
                          const SnackBar(
                              content: Text('Removed all from Liked Songs')),
                        );
                      }
                    } else {
                      for (final track in _tracks) {
                        await LikedSongsService.instance.addLikedSong(LikedSong(
                          videoId: track.videoId,
                          title: track.title,
                          artist: track.artist,
                          thumbnailUrl: track.thumbnailUrl ?? _thumbnailUrl,
                          durationSeconds: track.durationSeconds ?? 0,
                          likedAt: DateTime.now(),
                        ));
                      }
                      if (mounted) {
                        messenger.showSnackBar(
                          const SnackBar(
                              content: Text('Saved all to Liked Songs')),
                        );
                      }
                    }
                  },
                );
              },
            ),
            SizedBox(width: isDesktop ? 40 : 28),
            // Play
            GestureDetector(
              onTap: () {
                if (widget.onPlayTracks != null && _tracks.isNotEmpty) {
                  Navigator.of(context).pop();
                  widget.onPlayTracks!(_tracks, initialIndex: 0);
                }
              },
              child: Container(
                width: isDesktop ? 84 : 72,
                height: isDesktop ? 84 : 72,
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
                child: Icon(Icons.play_arrow,
                    color: Colors.white, size: isDesktop ? 48 : 38),
              ),
            ),
            SizedBox(width: isDesktop ? 40 : 28),
            // Shuffle
            _buildActionButton(
              icon: Icons.shuffle,
              label: 'SHUFFLE',
              isDesktop: isDesktop,
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
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Color? iconColor,
    bool isDesktop = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: isDesktop ? 64 : 52,
            height: isDesktop ? 64 : 52,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: 0.05),
              border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
            ),
            child: Icon(icon,
                color: iconColor ?? Colors.white54, size: isDesktop ? 32 : 26),
          ),
          SizedBox(height: isDesktop ? 8 : 6),
          Text(label,
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.35),
                  fontSize: isDesktop ? 11 : 9,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1)),
        ],
      ),
    );
  }

  Widget _buildTrackListHeader({bool isDesktop = false}) {
    return Padding(
      padding:
          EdgeInsets.fromLTRB(isDesktop ? 64 : 20, 16, isDesktop ? 64 : 20, 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text('#   TITLE',
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.3),
                  fontSize: isDesktop ? 13 : 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1)),
          Icon(Icons.schedule,
              size: isDesktop ? 20 : 16,
              color: Colors.white.withValues(alpha: 0.3)),
        ],
      ),
    );
  }

  Widget _buildTrackRow(int index, TrackInfo track, {bool isDesktop = false}) {
    const Shapes itemShape = Shapes.slanted;

    return RepaintBoundary(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            if (widget.onPlayTracks != null && _tracks.isNotEmpty) {
              Navigator.of(context).pop();
              widget.onPlayTracks!(_tracks, initialIndex: index);
            }
          },
          child: Container(
            padding: EdgeInsets.symmetric(
                horizontal: isDesktop ? 64 : 16, vertical: isDesktop ? 14 : 10),
            child: Row(
              children: [
                // Track number
                SizedBox(
                  width: isDesktop ? 36 : 26,
                  child: Text(
                    '${index + 1}',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.4),
                        fontWeight: FontWeight.w600,
                        fontSize: isDesktop ? 15 : 13),
                  ),
                ),
                SizedBox(width: isDesktop ? 16 : 10),

                // Artwork thumbnail with Expressive Shape
                if (track.thumbnailUrl != null) ...[
                  SizedBox(
                    width: isDesktop ? 48 : 40,
                    height: isDesktop ? 48 : 40,
                    child: M3EContainer(
                      itemShape,
                      color: _surfaceDark,
                      border: BorderSide(
                        color: Colors.white.withValues(alpha: 0.08),
                        width: 1,
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: CachedNetworkImage(
                        imageUrl: track.thumbnailUrl!,
                        fit: BoxFit.cover,
                        memCacheWidth: 120,
                        memCacheHeight: 120,
                        placeholder: (_, __) => Container(
                          color: _surfaceDark,
                        ),
                        errorWidget: (_, __, ___) => Container(
                          color: _surfaceDark,
                          child: Icon(Icons.music_note_rounded,
                              color: Colors.white24, size: isDesktop ? 22 : 18),
                        ),
                      ),
                    ),
                  ),
                  SizedBox(width: isDesktop ? 16 : 10),
                ],

                // Song info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        track.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: isDesktop ? 16 : 14),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        track.artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.45),
                            fontSize: isDesktop ? 13 : 12),
                      ),
                    ],
                  ),
                ),

                // Duration
                Padding(
                  padding: EdgeInsets.only(left: isDesktop ? 20 : 10),
                  child: Text(
                    _formatDuration(track.durationSeconds),
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.4),
                        fontWeight: FontWeight.w500,
                        fontSize: isDesktop ? 14 : 12),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildError({bool isDesktop = false}) {
    return RepaintBoundary(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              M3EContainer(
                Shapes.c4SidedCookie,
                width: isDesktop ? 88 : 72,
                height: isDesktop ? 88 : 72,
                color: Colors.red.withValues(alpha: 0.15),
                border: BorderSide(
                  color: Colors.red.withValues(alpha: 0.3),
                  width: 1.2,
                ),
                child: Center(
                  child: Icon(
                    Icons.error_outline_rounded,
                    size: isDesktop ? 44 : 36,
                    color: Colors.redAccent,
                  ),
                ),
              ),
              SizedBox(height: isDesktop ? 20 : 16),
              Text(
                'Failed to load tracks',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: isDesktop ? 20 : 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _error ?? 'Unknown network error.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.5),
                  fontSize: isDesktop ? 14 : 12,
                ),
              ),
              SizedBox(height: isDesktop ? 24 : 18),
              M3EButton.icon(
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Retry'),
                onPressed: () {
                  setState(() {
                    _loading = true;
                    _error = null;
                  });
                  _loadSongs();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmpty({bool isDesktop = false}) {
    return RepaintBoundary(
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            M3EContainer(
              Shapes.c4SidedCookie,
              width: isDesktop ? 88 : 72,
              height: isDesktop ? 88 : 72,
              color: _primary.withValues(alpha: 0.12),
              border: BorderSide(
                color: _primary.withValues(alpha: 0.25),
                width: 1.2,
              ),
              child: Center(
                child: Icon(
                  Icons.queue_music_rounded,
                  size: isDesktop ? 44 : 36,
                  color: _primary.withValues(alpha: 0.8),
                ),
              ),
            ),
            SizedBox(height: isDesktop ? 20 : 16),
            Text(
              'No tracks available',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.6),
                fontSize: isDesktop ? 18 : 15,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
