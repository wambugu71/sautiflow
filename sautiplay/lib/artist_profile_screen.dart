import 'package:cached_network_image/cached_network_image.dart';
import 'package:dart_ytmusic_api/dart_ytmusic_api.dart';
import 'package:flutter/material.dart';
import 'package:loading_indicator_m3e/loading_indicator_m3e.dart';

import 'album_detail_screen.dart'; // For TrackInfo + routing
import 'artist_catalog_screen.dart';
import 'services/app_theme_service.dart';

class ArtistProfileScreen extends StatefulWidget {
  final String? artistId;
  final String artistName;
  final Future<void> Function(List<TrackInfo> tracks, {int initialIndex})?
      onPlayTracks;

  const ArtistProfileScreen({
    super.key,
    this.artistId,
    required this.artistName,
    this.onPlayTracks,
  });

  @override
  State<ArtistProfileScreen> createState() => _ArtistProfileScreenState();
}

class _ArtistProfileScreenState extends State<ArtistProfileScreen> {
  final YTMusic _ytMusic = YTMusic();

  Color get _bgDark => context.bgDark;
  Color get _surfaceDark => context.cardDark;
  Color get _primary => context.primaryColor;

  bool _isLoading = true;
  String? _error;

  ArtistFull? _artistFull;
  String? _artistId;

  // Header image fallback
  String? _headerImageUrl;

  @override
  void initState() {
    super.initState();
    _artistId = widget.artistId;
    _loadArtist();
  }

  Future<void> _loadArtist() async {
    try {
      await _ytMusic.initialize();

      String? resolvedId = widget.artistId;

      // 1. If artistId is not directly passed, search for the artist to get their ID
      if (resolvedId == null || resolvedId.isEmpty) {
        final results = await _ytMusic.search(widget.artistName);
        if (results.isEmpty) {
          throw Exception("Artist not found");
        }

        SearchResult? artistSearchItem;
        try {
          artistSearchItem = results.firstWhere((item) =>
              item is ArtistDetailed || item is ArtistDetailedSearchResult);
        } catch (e) {
          artistSearchItem = null;
        }

        if (artistSearchItem == null) {
          throw Exception("Could not resolve artist ID");
        }

        final artistInfo = artistSearchItem is ArtistDetailedSearchResult
            ? artistSearchItem.artistDetailed
            : artistSearchItem as ArtistDetailed;

        resolvedId = artistInfo.artistId;
        _headerImageUrl = _getBestThumbnail(artistInfo.thumbnails);
      }

      _artistId = resolvedId;

      // 2. Fetch full artist profile details
      final fullProfile = await _ytMusic.getArtist(resolvedId);
      if (_headerImageUrl == null && fullProfile.thumbnails.isNotEmpty) {
        _headerImageUrl = _getBestThumbnail(fullProfile.thumbnails);
      }

      if (mounted) {
        setState(() {
          _artistFull = fullProfile;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  String? _getBestThumbnail(List<ThumbnailFull> thumbs) {
    if (thumbs.isEmpty) return null;
    final sorted = List<ThumbnailFull>.from(thumbs)
      ..sort((a, b) => b.width.compareTo(a.width));
    return sorted.first.url;
  }

  String _formatDuration(int? seconds) {
    if (seconds == null || seconds <= 0) return '--:--';
    final m = (seconds ~/ 60).toString();
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  void _openCatalog(ArtistCatalogType type) {
    if (_artistId == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ArtistCatalogScreen(
          artistId: _artistId!,
          artistName: _artistFull?.name ?? widget.artistName,
          initialType: type,
          onPlayTracks: widget.onPlayTracks,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgDark,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isDesktop = constraints.maxWidth >= 800;
          final content = _isLoading
              ? _buildLoading()
              : _error != null
                  ? _buildError()
                  : _buildContent(isDesktop);

          if (isDesktop) {
            return Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1000.0),
                child: content,
              ),
            );
          }
          return content;
        },
      ),
    );
  }

  Widget _buildLoading() {
    return Center(
      child: LoadingIndicatorM3E(
        color: _primary,
        containerColor: _primary.withValues(alpha: 0.2),
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline,
              size: 64, color: Colors.white.withValues(alpha: 0.3)),
          const SizedBox(height: 16),
          const Text(
            'Could not load artist profile',
            style: TextStyle(
                color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              _error ?? 'Unknown error',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white54),
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: () {
              setState(() {
                _isLoading = true;
                _error = null;
              });
              _loadArtist();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: _primary,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20)),
            ),
            child: const Text('Retry', style: TextStyle(color: Colors.white)),
          )
        ],
      ),
    );
  }

  Widget _buildContent(bool isDesktop) {
    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        _buildSliverAppBar(isDesktop),
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: isDesktop ? 48.0 : 20.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 24),
                _buildTopTracksSection(isDesktop),
                const SizedBox(height: 32),
                _buildDiscographySection(
                  'Albums',
                  _artistFull!.topAlbums,
                  isDesktop,
                  type: ArtistCatalogType.albums,
                ),
                const SizedBox(height: 32),
                _buildDiscographySection(
                  'Singles & EPs',
                  _artistFull!.topSingles,
                  isDesktop,
                  type: ArtistCatalogType.singles,
                ),
                if (_artistFull!.featuredOn.isNotEmpty) ...[
                  const SizedBox(height: 32),
                  _buildPlaylistsSection('Featured On', _artistFull!.featuredOn, isDesktop),
                ],
                if (_artistFull!.topVideos.isNotEmpty) ...[
                  const SizedBox(height: 32),
                  _buildVideosSection('Music Videos', _artistFull!.topVideos, isDesktop),
                ],
                if (_artistFull!.similarArtists.isNotEmpty) ...[
                  const SizedBox(height: 32),
                  _buildSimilarArtistsSection('Fans Also Like', _artistFull!.similarArtists, isDesktop),
                ],
                const SizedBox(height: 120), // Padding for mini player
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSliverAppBar(bool isDesktop) {
    final heroHeight = MediaQuery.of(context).size.height * 0.42;

    return SliverAppBar(
      expandedHeight: heroHeight.clamp(280.0, 480.0),
      pinned: true,
      backgroundColor: _bgDark.withValues(alpha: 0.95),
      elevation: 0,
      leading: IconButton(
        icon: Container(
          width: 40,
          height: 40,
          decoration: const BoxDecoration(
            color: Colors.black38,
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.keyboard_arrow_down, color: Colors.white),
        ),
        onPressed: () => Navigator.pop(context),
      ),
      flexibleSpace: FlexibleSpaceBar(
        background: Stack(
          fit: StackFit.expand,
          children: [
            // Background Image
            if (_headerImageUrl != null)
              CachedNetworkImage(
                imageUrl: _headerImageUrl!,
                fit: BoxFit.cover,
                memCacheWidth: 800,
                memCacheHeight: 600,
                placeholder: (context, url) => Container(color: _surfaceDark),
                errorWidget: (context, url, error) =>
                    Container(color: _surfaceDark),
              )
            else
              Container(color: _surfaceDark),

            // Gradients
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.35),
                      Colors.transparent,
                      _bgDark,
                    ],
                    stops: const [0.0, 0.45, 1.0],
                  ),
                ),
              ),
            ),
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              height: heroHeight / 2,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      _bgDark,
                      _bgDark.withValues(alpha: 0.7),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),

            // Header Content
            Positioned(
              bottom: 20,
              left: 20,
              right: 20,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.verified, color: _primary, size: 18),
                      const SizedBox(width: 6),
                      const Text(
                        'ARTIST',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.5,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _artistFull?.name ?? widget.artistName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 40,
                      fontWeight: FontWeight.bold,
                      height: 1.1,
                      letterSpacing: -0.5,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 14),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      if (_artistId != null)
                        OutlinedButton.icon(
                          onPressed: () => _openCatalog(ArtistCatalogType.albums),
                          icon: const Icon(Icons.library_music_rounded, size: 16, color: Colors.white),
                          label: const Text('Catalog', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(color: Colors.white.withValues(alpha: 0.3)),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                            backgroundColor: Colors.black26,
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          ),
                        )
                      else
                        const SizedBox(),
                      GestureDetector(
                        onTap: () {
                          if (widget.onPlayTracks != null &&
                              _artistFull != null &&
                              _artistFull!.topSongs.isNotEmpty) {
                            final tracks = _artistFull!.topSongs
                                .map((s) => TrackInfo.fromSongDetailed(s))
                                .toList();
                            Navigator.of(context)
                                .popUntil((route) => route.isFirst);
                            widget.onPlayTracks!(tracks, initialIndex: 0);
                          }
                        },
                        child: Container(
                          width: 54,
                          height: 54,
                          decoration: BoxDecoration(
                            color: _primary,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: _primary.withValues(alpha: 0.4),
                                blurRadius: 18,
                                spreadRadius: 0,
                              )
                            ],
                          ),
                          child: const Icon(Icons.play_arrow_rounded,
                              color: Colors.white, size: 32),
                        ),
                      )
                    ],
                  )
                ],
              ),
            )
          ],
        ),
      ),
    );
  }

  Widget _buildTopTracksSection(bool isDesktop) {
    if (_artistFull!.topSongs.isEmpty) return const SizedBox.shrink();

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Top Tracks',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            if (_artistId != null)
              TextButton(
                onPressed: () => _openCatalog(ArtistCatalogType.songs),
                child: Text(
                  'SEE ALL',
                  style: TextStyle(
                    color: _primary,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.0,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        ..._artistFull!.topSongs.asMap().entries.take(5).map((entry) {
          final idx = entry.key;
          final track = entry.value;
          return _buildTrackItem(idx, track);
        }),
      ],
    );
  }

  Widget _buildTrackItem(int index, SongDetailed item) {
    final thumb = _getBestThumbnail(item.thumbnails);

    return InkWell(
      onTap: () {
        if (widget.onPlayTracks != null) {
          final tracks = _artistFull!.topSongs
              .map((s) => TrackInfo.fromSongDetailed(s))
              .toList();
          Navigator.of(context).popUntil((route) => route.isFirst);
          widget.onPlayTracks!(tracks, initialIndex: index);
        }
      },
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4),
        child: Row(
          children: [
            SizedBox(
              width: 28,
              child: Text(
                '${index + 1}',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white54,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(width: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 44,
                height: 44,
                child: thumb != null
                    ? CachedNetworkImage(
                        imageUrl: thumb,
                        fit: BoxFit.cover,
                        memCacheWidth: 100,
                        memCacheHeight: 100,
                        placeholder: (context, url) => Container(color: _surfaceDark),
                        errorWidget: (context, url, err) => Container(
                          color: _surfaceDark,
                          child: const Icon(Icons.music_note_rounded, color: Colors.white24, size: 20),
                        ),
                      )
                    : Container(
                        color: _surfaceDark,
                        child: const Icon(Icons.music_note_rounded, color: Colors.white24, size: 20),
                      ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    item.album?.name ?? _artistFull?.name ?? widget.artistName,
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Text(
              _formatDuration(item.duration),
              style: const TextStyle(color: Colors.white54, fontSize: 13),
            ),
            const SizedBox(width: 8),
          ],
        ),
      ),
    );
  }

  Widget _buildDiscographySection(
    String title,
    List<AlbumDetailed> albums,
    bool isDesktop, {
    required ArtistCatalogType type,
  }) {
    if (albums.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            if (_artistId != null)
              TextButton(
                onPressed: () => _openCatalog(type),
                child: Text(
                  'SEE ALL',
                  style: TextStyle(
                    color: _primary,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.0,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 195,
          child: ListView.separated(
            physics: const BouncingScrollPhysics(),
            scrollDirection: Axis.horizontal,
            itemCount: albums.length,
            separatorBuilder: (context, index) => const SizedBox(width: 14),
            itemBuilder: (context, index) {
              final album = albums[index];
              return _buildAlbumCard(album);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildAlbumCard(AlbumDetailed album) {
    final thumb = _getBestThumbnail(album.thumbnails);

    return InkWell(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => AlbumDetailScreen(
              item: album,
              onPlayTracks: widget.onPlayTracks,
            ),
          ),
        );
      },
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(
        width: 140,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 140,
              height: 140,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                color: _surfaceDark,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.25),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  )
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: thumb != null
                  ? CachedNetworkImage(
                      imageUrl: thumb,
                      fit: BoxFit.cover,
                      memCacheWidth: 280,
                      memCacheHeight: 280,
                      placeholder: (context, url) => Center(
                          child: Icon(Icons.album_rounded,
                              color: Colors.white24, size: 40)),
                      errorWidget: (context, url, err) => Center(
                          child: Icon(Icons.album_rounded,
                              color: Colors.white24, size: 40)),
                    )
                  : const Center(
                      child:
                          Icon(Icons.album_rounded, color: Colors.white24, size: 40)),
            ),
            const SizedBox(height: 8),
            Text(
              album.name,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            Text(
              album.year != null ? '${album.year}' : 'Release',
              style: const TextStyle(color: Colors.white54, fontSize: 12),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  // ── Featured Playlists Section ─────────────────────────────────────────────

  Widget _buildPlaylistsSection(
    String title,
    List<PlaylistDetailed> playlists,
    bool isDesktop,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 195,
          child: ListView.separated(
            physics: const BouncingScrollPhysics(),
            scrollDirection: Axis.horizontal,
            itemCount: playlists.length,
            separatorBuilder: (context, index) => const SizedBox(width: 14),
            itemBuilder: (context, index) {
              final playlist = playlists[index];
              final thumb = _getBestThumbnail(playlist.thumbnails);

              return InkWell(
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => AlbumDetailScreen(
                        item: playlist,
                        onPlayTracks: widget.onPlayTracks,
                      ),
                    ),
                  );
                },
                borderRadius: BorderRadius.circular(16),
                child: SizedBox(
                  width: 140,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 140,
                        height: 140,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          color: _surfaceDark,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.25),
                              blurRadius: 8,
                              offset: const Offset(0, 4),
                            )
                          ],
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: thumb != null
                            ? CachedNetworkImage(
                                imageUrl: thumb,
                                fit: BoxFit.cover,
                                memCacheWidth: 280,
                                memCacheHeight: 280,
                                placeholder: (_, __) => Container(color: _surfaceDark),
                                errorWidget: (_, __, ___) => Center(
                                  child: Icon(Icons.playlist_play_rounded, color: Colors.white24, size: 40),
                                ),
                              )
                            : Center(
                                child: Icon(Icons.playlist_play_rounded, color: Colors.white24, size: 40),
                              ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        playlist.name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      const Text(
                        'Playlist',
                        style: TextStyle(color: Colors.white54, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // ── Music Videos Section ───────────────────────────────────────────────────

  Widget _buildVideosSection(
    String title,
    List<VideoDetailed> videos,
    bool isDesktop,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 175,
          child: ListView.separated(
            physics: const BouncingScrollPhysics(),
            scrollDirection: Axis.horizontal,
            itemCount: videos.length,
            separatorBuilder: (context, index) => const SizedBox(width: 14),
            itemBuilder: (context, index) {
              final video = videos[index];
              final thumb = _getBestThumbnail(video.thumbnails);

              return InkWell(
                onTap: () {
                  if (widget.onPlayTracks != null) {
                    final track = TrackInfo.fromVideoDetailed(video);
                    Navigator.of(context).popUntil((r) => r.isFirst);
                    widget.onPlayTracks!([track], initialIndex: 0);
                  }
                },
                borderRadius: BorderRadius.circular(14),
                child: SizedBox(
                  width: 200,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Stack(
                        children: [
                          Container(
                            width: 200,
                            height: 115,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(14),
                              color: _surfaceDark,
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: thumb != null
                                ? CachedNetworkImage(
                                    imageUrl: thumb,
                                    fit: BoxFit.cover,
                                    memCacheWidth: 400,
                                    placeholder: (_, __) => Container(color: _surfaceDark),
                                    errorWidget: (_, __, ___) => Center(
                                      child: Icon(Icons.ondemand_video_rounded, color: Colors.white24, size: 36),
                                    ),
                                  )
                                : Center(
                                    child: Icon(Icons.ondemand_video_rounded, color: Colors.white24, size: 36),
                                  ),
                          ),
                          Positioned(
                            bottom: 6,
                            right: 6,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.75),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                _formatDuration(video.duration),
                                style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        video.name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      const Text(
                        'Video',
                        style: TextStyle(color: Colors.white54, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // ── Fans Also Like / Similar Artists ──────────────────────────────────────

  Widget _buildSimilarArtistsSection(
    String title,
    List<ArtistDetailed> artists,
    bool isDesktop,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 14),
        SizedBox(
          height: 165,
          child: ListView.separated(
            physics: const BouncingScrollPhysics(),
            scrollDirection: Axis.horizontal,
            itemCount: artists.length,
            separatorBuilder: (context, index) => const SizedBox(width: 16),
            itemBuilder: (context, index) {
              final artist = artists[index];
              final thumb = _getBestThumbnail(artist.thumbnails);

              return InkWell(
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ArtistProfileScreen(
                        artistId: artist.artistId,
                        artistName: artist.name,
                        onPlayTracks: widget.onPlayTracks,
                      ),
                    ),
                  );
                },
                borderRadius: BorderRadius.circular(60),
                child: SizedBox(
                  width: 110,
                  child: Column(
                    children: [
                      Container(
                        width: 100,
                        height: 100,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _surfaceDark,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.3),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: thumb != null
                            ? CachedNetworkImage(
                                imageUrl: thumb,
                                fit: BoxFit.cover,
                                memCacheWidth: 200,
                                memCacheHeight: 200,
                                placeholder: (_, __) => Container(color: _surfaceDark),
                                errorWidget: (_, __, ___) => const Center(
                                  child: Icon(Icons.person_rounded, color: Colors.white24, size: 40),
                                ),
                              )
                            : const Center(
                                child: Icon(Icons.person_rounded, color: Colors.white24, size: 40),
                              ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        artist.name,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      const Text(
                        'Artist',
                        style: TextStyle(color: Colors.white54, fontSize: 11),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
