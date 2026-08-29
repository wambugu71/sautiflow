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
  Color get _textMuted => context.textMuted;
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
        final pid = item.playlistId;

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
          debugPrint('dart_ytmusic_api getPlaylistVideos failed for $pid: $e');
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

  void _playAll({bool shuffle = false}) {
    if (widget.onPlayTracks == null || _tracks.isEmpty) return;
    final tracks = shuffle
        ? (List<TrackInfo>.from(_tracks)..shuffle())
        : _tracks;
    Navigator.of(context).popUntil((route) => route.isFirst);
    widget.onPlayTracks!(tracks, initialIndex: 0);
  }

  void _playAt(int index) {
    if (widget.onPlayTracks == null || _tracks.isEmpty) return;
    Navigator.of(context).popUntil((route) => route.isFirst);
    widget.onPlayTracks!(_tracks, initialIndex: index);
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
                    backgroundColor: _bgDark,
                    surfaceTintColor: Colors.transparent,
                    elevation: 0,
                    scrolledUnderElevation: 0,
                    pinned: true,
                    leading: Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: Center(
                        child: M3EIconButton(
                          icon:
                              const Icon(Icons.arrow_back_rounded, size: 20),
                          variant: M3EIconButtonVariant.tonal,
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ),
                    ),
                  ),

                  // ── Hero ──
                  SliverToBoxAdapter(
                      child: _buildHero(isDesktop: isDesktop)),

                  // ── Tracklist ──
                  if (_loading)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: RepaintBoundary(
                        child: Center(
                          child: M3EProgressIndicator.circularWavy(
                            color: _primary,
                            trackColor: _primary.withValues(alpha: 0.15),
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
                  else ...[
                    SliverPadding(
                      padding: EdgeInsets.symmetric(
                          horizontal: isDesktop ? 32 : 16, vertical: 8),
                      sliver: SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, i) => _buildTrackRow(
                            i,
                            _tracks[i],
                            isDesktop: isDesktop,
                            isFirst: i == 0,
                            isLast: i == _tracks.length - 1,
                          ),
                          childCount: _tracks.length,
                        ),
                      ),
                    ),
                  ],

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

  // ── Hero ───────────────────────────────────────────────────────────────────

  Widget _buildHero({required bool isDesktop}) {
    if (isDesktop) {
      final details = _buildHeroDetails(isDesktop: true, centered: false);
      final art = _buildHeroArt(size: 280.0);
      return Padding(
        padding: const EdgeInsets.fromLTRB(32, 24, 32, 20),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            art,
            const SizedBox(width: 36),
            Expanded(child: details),
          ],
        ),
      );
    }

    // ── Mobile: large artwork with the info overlaid on a bottom scrim ──
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Stack(
        children: [
          // Artwork
          AspectRatio(
            aspectRatio: 1,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: _thumbnailUrl != null
                  ? CachedNetworkImage(
                      imageUrl: _thumbnailUrl!,
                      fit: BoxFit.cover,
                      alignment: Alignment.topCenter,
                      memCacheWidth: 700,
                      memCacheHeight: 700,
                      placeholder: (_, __) =>
                          Container(color: _surfaceDark),
                      errorWidget: (_, __, ___) =>
                          Container(color: _surfaceDark),
                    )
                  : Container(color: _surfaceDark),
            ),
          ),
          // Bottom scrim keeps the overlaid info legible
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  stops: const [0.0, 0.65],
                  colors: [
                    Colors.black.withValues(alpha: 0.85),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          // Info overlaid at the bottom of the artwork
          Positioned(
            left: 18,
            right: 18,
            bottom: 16,
            child: _buildHeroDetails(
              isDesktop: false,
              centered: false,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeroDetails({
    required bool isDesktop,
    required bool centered,
  }) {
    final CrossAxisAlignment align =
        centered ? CrossAxisAlignment.center : CrossAxisAlignment.start;

    final metaRow = Row(
      mainAxisAlignment:
          centered ? MainAxisAlignment.center : MainAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Text(
            _artist,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: _textPrimary.withValues(alpha: 0.85),
              fontSize: isDesktop ? 17 : 14.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        if (_year != null) ...[
          _metaDot(),
          Text(
            _year!,
            style: TextStyle(
              color: _textMuted,
              fontSize: isDesktop ? 15 : 13,
            ),
          ),
        ],
        if (_tracks.isNotEmpty) ...[
          _metaDot(),
          Text(
            '${_tracks.length} songs',
            style: TextStyle(
              color: _textMuted,
              fontSize: isDesktop ? 15 : 13,
            ),
          ),
        ],
      ],
    );

    return Column(
      crossAxisAlignment: align,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Kind label
        Text(
          _screenLabel,
          style: TextStyle(
            color: _primary,
            fontSize: 11.5,
            fontWeight: FontWeight.w800,
            letterSpacing: 2,
          ),
        ),
        const SizedBox(height: 6),
        // Title
        Text(
          _title,
          textAlign: centered ? TextAlign.center : TextAlign.left,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: _textPrimary,
            fontSize: isDesktop ? 38 : 28,
            fontWeight: FontWeight.w800,
            height: 1.12,
            letterSpacing: -0.8,
          ),
        ),
        const SizedBox(height: 10),
        metaRow,
        // Actions
        if (!centered) ...[
          SizedBox(height: isDesktop ? 28 : 16),
          _buildHeroActions(centered: false, isDesktop: isDesktop),
        ],
      ],
    );
  }

  Widget _buildHeroActions({
    required bool centered,
    required bool isDesktop,
  }) {
    final children = [
      M3EButton.icon(
        icon: const Icon(Icons.play_arrow_rounded, size: 18),
        label: const Text('Play'),
        onPressed: () => _playAll(),
      ),
      const SizedBox(width: 10),
      M3EButton.tonal(
        onPressed: () => _playAll(shuffle: true),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(Icons.shuffle_rounded, size: 16),
            SizedBox(width: 6),
            Text('Shuffle'),
          ],
        ),
      ),
      const SizedBox(width: 10),
      _buildLikeButton(isDesktop: isDesktop),
    ];

    if (centered) {
      return Row(mainAxisAlignment: MainAxisAlignment.center, children: children);
    }
    return Row(children: children);
  }

  Widget _metaDot() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Container(
        width: 3.5,
        height: 3.5,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: _textMuted.withValues(alpha: 0.6),
        ),
      ),
    );
  }

  Widget _buildHeroArt({required double size}) {
    Widget fallback = Container(
      color: _surfaceDark,
      child: Icon(
        Icons.album_rounded,
        color: _textMuted.withValues(alpha: 0.35),
        size: 64,
      ),
    );

    return RepaintBoundary(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            // Neutral shadow — no colored glow
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.35),
              blurRadius: 32,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: _thumbnailUrl != null
              ? CachedNetworkImage(
                  imageUrl: _thumbnailUrl!,
                  fit: BoxFit.cover,
                  memCacheWidth: 600,
                  memCacheHeight: 600,
                  placeholder: (_, __) => fallback,
                  errorWidget: (_, __, ___) => fallback,
                )
              : fallback,
        ),
      ),
    );
  }

  /// Heart toggle — same persistence logic as before, expressive chrome.
  Widget _buildLikeButton({bool isDesktop = false}) {
    return ValueListenableBuilder<List<LikedSong>>(
      valueListenable: LikedSongsService.instance.likedSongsNotifier,
      builder: (context, likedSongs, _) {
        bool isSaved = false;
        if (_tracks.isNotEmpty) {
          isSaved = _tracks.every(
              (track) => likedSongs.any((s) => s.videoId == track.videoId));
        }
        return M3EIconButton(
          icon: Icon(isSaved ? Icons.favorite_rounded : Icons.favorite_border,
              size: isDesktop ? 22 : 20),
          variant:
              isSaved ? M3EIconButtonVariant.filled : M3EIconButtonVariant.tonal,
          onPressed: () async {
            if (_tracks.isEmpty) return;
            final messenger = ScaffoldMessenger.of(context);
            if (isSaved) {
              for (final track in _tracks) {
                await LikedSongsService.instance
                    .removeLikedSong(track.videoId);
              }
              if (mounted) {
                messenger.showSnackBar(const SnackBar(
                    content: Text('Removed all from Liked Songs')));
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
                messenger.showSnackBar(const SnackBar(
                    content: Text('Saved all to Liked Songs')));
              }
            }
          },
        );
      },
    );
  }

  // ── Track rows (connected corner cards, matching Library/Search) ──────────

  Widget _buildTrackRow(
    int index,
    TrackInfo track, {
    bool isDesktop = false,
    bool isFirst = false,
    bool isLast = false,
  }) {
    final borderRadius = BorderRadius.only(
      topLeft: Radius.circular(isFirst ? 20 : 6),
      topRight: Radius.circular(isFirst ? 20 : 6),
      bottomLeft: Radius.circular(isLast ? 20 : 6),
      bottomRight: Radius.circular(isLast ? 20 : 6),
    );

    final Widget artwork = ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: isDesktop ? 52 : 44,
        height: isDesktop ? 52 : 44,
        child: track.thumbnailUrl != null
            ? CachedNetworkImage(
                imageUrl: track.thumbnailUrl!,
                fit: BoxFit.cover,
                memCacheWidth: 120,
                memCacheHeight: 120,
                placeholder: (_, __) =>
                    Container(color: _surfaceDark),
                errorWidget: (_, __, ___) => Container(
                  color: _surfaceDark,
                  child: Icon(Icons.music_note_rounded,
                      color: _textMuted.withValues(alpha: 0.4),
                      size: isDesktop ? 22 : 18),
                ),
              )
            : Container(
                color: _surfaceDark,
                child: Icon(Icons.music_note_rounded,
                    color: _textMuted.withValues(alpha: 0.4),
                    size: isDesktop ? 22 : 18),
              ),
      ),
    );

    return RepaintBoundary(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 3.0),
        child: Material(
          color: _surfaceDark,
          shape: RoundedRectangleBorder(
            borderRadius: borderRadius,
            side: BorderSide(color: _outline.withValues(alpha: 0.12)),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => _playAt(index),
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                children: [
                  // Track number
                  SizedBox(
                    width: isDesktop ? 26 : 20,
                    child: Text(
                      '${index + 1}',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: _textMuted.withValues(alpha: 0.7),
                        fontWeight: FontWeight.w600,
                        fontSize: isDesktop ? 13 : 12,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  artwork,
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          track.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: _textPrimary,
                            fontWeight: FontWeight.w600,
                            fontSize: isDesktop ? 15 : 13.5,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          track.artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: _textMuted,
                            fontSize: isDesktop ? 13 : 11.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _formatDuration(track.durationSeconds),
                    style: TextStyle(
                      color: _textMuted,
                      fontWeight: FontWeight.w500,
                      fontSize: isDesktop ? 13 : 11.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── States ────────────────────────────────────────────────────────────────

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
                child: const Center(
                  child: Icon(
                    Icons.error_outline_rounded,
                    size: 38,
                    color: Colors.redAccent,
                  ),
                ),
              ),
              SizedBox(height: isDesktop ? 20 : 16),
              Text(
                'Failed to load tracks',
                style: TextStyle(
                  color: _textPrimary,
                  fontSize: isDesktop ? 20 : 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _error ?? 'Unknown network error.',
                textAlign: TextAlign.center,
                style: TextStyle(color: _textMuted, fontSize: 13),
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
                color: _textMuted,
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
