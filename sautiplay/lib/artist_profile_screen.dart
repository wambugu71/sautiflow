import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:dart_ytmusic_api/dart_ytmusic_api.dart';
import 'package:flutter/material.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:shimmer/shimmer.dart';

import 'album_detail_screen.dart'; // For TrackInfo + routing
import 'artist_catalog_screen.dart';
import 'l10n/app_strings.dart';
import 'services/app_theme_service.dart';

// ══════════════════════════════════════════════════════════════════════════════
// REACTIVE ARTIST PROFILE STATE MODEL
// ══════════════════════════════════════════════════════════════════════════════

sealed class ArtistProfileState {
  const ArtistProfileState();
}

class ArtistProfileStateLoading extends ArtistProfileState {
  final String? initialHeaderImage;
  const ArtistProfileStateLoading({this.initialHeaderImage});
}

class ArtistProfileStateSuccess extends ArtistProfileState {
  final ArtistFull artistFull;
  final String? artistId;
  final String? headerImageUrl;

  const ArtistProfileStateSuccess({
    required this.artistFull,
    this.artistId,
    this.headerImageUrl,
  });
}

class ArtistProfileStateError extends ArtistProfileState {
  final String message;
  const ArtistProfileStateError({required this.message});
}

// ══════════════════════════════════════════════════════════════════════════════
// REACTIVE ARTIST PROFILE CONTROLLER
// ══════════════════════════════════════════════════════════════════════════════

class ArtistProfileReactiveController
    extends ValueNotifier<ArtistProfileState> {
  final YTMusic _ytMusic = YTMusic();
  final String? initialArtistId;
  final String artistName;
  int _activeRequestId = 0;

  ArtistProfileReactiveController({
    this.initialArtistId,
    required this.artistName,
  }) : super(const ArtistProfileStateLoading());

  Future<void> init() async {
    await loadArtist();
  }

  String? _getBestThumbnail(List<ThumbnailFull> thumbs) {
    if (thumbs.isEmpty) return null;
    final sorted = List<ThumbnailFull>.from(thumbs)
      ..sort((a, b) => b.width.compareTo(a.width));
    return sorted.first.url;
  }

  Future<void> loadArtist() async {
    final token = ++_activeRequestId;
    value = const ArtistProfileStateLoading();

    try {
      await _ytMusic.initialize();

      String? resolvedId = initialArtistId;
      String? headerImageUrl;

      // 1. If artistId is not directly passed, search for the artist to get their ID
      if (resolvedId == null || resolvedId.isEmpty) {
        String cleanQuery = artistName.trim();
        cleanQuery = cleanQuery
            .replaceAll(RegExp(r'\s*-\s*Topic$', caseSensitive: false), '')
            .trim();
        cleanQuery = cleanQuery
            .replaceAll(RegExp(r'\s+VEVO$', caseSensitive: false), '')
            .trim();
        final featMatch = RegExp(
          r'^(.*?)\s+(?:feat\.|ft\.|featuring)\s+.*$',
          caseSensitive: false,
        ).firstMatch(cleanQuery);
        if (featMatch != null) {
          cleanQuery = featMatch.group(1)!.trim();
        }

        try {
          final artists = await _ytMusic.searchArtists(cleanQuery);
          if (artists.isNotEmpty) {
            final match = artists.firstWhere(
              (a) => a.name.toLowerCase() == cleanQuery.toLowerCase(),
              orElse: () => artists.first,
            );
            if (match.artistId.isNotEmpty) {
              resolvedId = match.artistId;
              headerImageUrl = _getBestThumbnail(match.thumbnails);
            }
          }
        } catch (_) {}

        if ((resolvedId == null || resolvedId.isEmpty) &&
            cleanQuery.contains(',')) {
          final first = cleanQuery.split(',').first.trim();
          if (first.isNotEmpty && first != cleanQuery) {
            try {
              final artists = await _ytMusic.searchArtists(first);
              if (artists.isNotEmpty) {
                final match = artists.firstWhere(
                  (a) => a.name.toLowerCase() == first.toLowerCase(),
                  orElse: () => artists.first,
                );
                if (match.artistId.isNotEmpty) {
                  resolvedId = match.artistId;
                  headerImageUrl = _getBestThumbnail(match.thumbnails);
                }
              }
            } catch (_) {}
          }
        }

        if (resolvedId == null || resolvedId.isEmpty) {
          final results = await _ytMusic.search(cleanQuery);
          for (final item in results) {
            if (item is ArtistDetailed && item.artistId.isNotEmpty) {
              resolvedId = item.artistId;
              headerImageUrl = _getBestThumbnail(item.thumbnails);
              break;
            }
            if (item is ArtistDetailedSearchResult &&
                item.artistDetailed.artistId.isNotEmpty) {
              resolvedId = item.artistDetailed.artistId;
              headerImageUrl =
                  _getBestThumbnail(item.artistDetailed.thumbnails);
              break;
            }
          }

          if (resolvedId == null || resolvedId.isEmpty) {
            for (final item in results) {
              if (item is SongDetailed &&
                  item.artist.artistId != null &&
                  item.artist.artistId!.isNotEmpty) {
                resolvedId = item.artist.artistId;
                break;
              }
            }
          }
        }

        if (resolvedId == null || resolvedId.isEmpty) {
          throw Exception('Could not resolve artist ID for "$artistName"');
        }
      }

      if (token != _activeRequestId) return;

      // 2. Fetch full artist profile details
      final fullProfile = await _ytMusic.getArtist(resolvedId);
      if (token != _activeRequestId) return;

      if (headerImageUrl == null && fullProfile.thumbnails.isNotEmpty) {
        headerImageUrl = _getBestThumbnail(fullProfile.thumbnails);
      }

      value = ArtistProfileStateSuccess(
        artistFull: fullProfile,
        artistId: resolvedId,
        headerImageUrl: headerImageUrl,
      );
    } catch (e) {
      if (token != _activeRequestId) return;
      value = ArtistProfileStateError(
        message: e.toString().replaceFirst(RegExp(r'^Exception:\s*'), ''),
      );
    }
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// ARTIST PROFILE SCREEN WIDGET
// ══════════════════════════════════════════════════════════════════════════════

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
  late final ArtistProfileReactiveController _controller;

  Color get _bgDark => context.bgDark;
  Color get _surfaceDark => context.cardDark;
  Color get _primary => context.primaryColor;

  @override
  void initState() {
    super.initState();
    _controller = ArtistProfileReactiveController(
      initialArtistId: widget.artistId,
      artistName: widget.artistName,
    )..init();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
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

  void _openCatalog(String? artistId, String artistName, ArtistCatalogType type) {
    if (artistId == null || artistId.isEmpty) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ArtistCatalogScreen(
          artistId: artistId,
          artistName: artistName,
          initialType: type,
          onPlayTracks: widget.onPlayTracks,
        ),
      ),
    );
  }

  void _openSongAlbum(SongDetailed song) {
    if (song.album == null || song.album!.albumId.isEmpty) return;
    final albumItem = AlbumDetailed(
      type: 'album',
      albumId: song.album!.albumId,
      playlistId: '',
      name: song.album!.name,
      artist: song.artist,
      thumbnails: song.thumbnails,
    );
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AlbumDetailScreen(
          item: albumItem,
          onPlayTracks: widget.onPlayTracks,
        ),
      ),
    );
  }

  void _playSongDirectly(SongDetailed song) {
    if (widget.onPlayTracks != null) {
      final track = TrackInfo.fromSongDetailed(
        song,
        album: song.album?.name,
        albumId: song.album?.albumId,
        albumArtist: song.artist.name,
      );
      Navigator.of(context).popUntil((route) => route.isFirst);
      widget.onPlayTracks!([track], initialIndex: 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgDark,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isDesktop = constraints.maxWidth >= 800;

          Widget content = ValueListenableBuilder<ArtistProfileState>(
            valueListenable: _controller,
            builder: (context, state, _) {
              return AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                child: KeyedSubtree(
                  key: ValueKey(_stateKey(state)),
                  child: switch (state) {
                    ArtistProfileStateLoading() => _ArtistProfileShimmerView(
                        artistName: widget.artistName,
                        isDesktop: isDesktop,
                      ),
                    ArtistProfileStateError(:final message) =>
                      _buildError(message),
                    ArtistProfileStateSuccess(
                      :final artistFull,
                      :final artistId,
                      :final headerImageUrl,
                    ) =>
                      _buildContent(
                        artistFull,
                        artistId,
                        headerImageUrl,
                        isDesktop,
                      ),
                  },
                ),
              );
            },
          );

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

  String _stateKey(ArtistProfileState state) {
    return switch (state) {
      ArtistProfileStateLoading() => 'loading',
      ArtistProfileStateError() => 'error',
      ArtistProfileStateSuccess() => 'success',
    };
  }

  // ── Error State ────────────────────────────────────────────────────────────

  Widget _buildError(String message) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline_rounded,
              size: 64,
              color: Colors.redAccent.withValues(alpha: 0.6),
            ),
            const SizedBox(height: 16),
            const Text(
              'Could not load artist profile',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white54, fontSize: 13),
            ),
            const SizedBox(height: 24),
            M3EButton.icon(
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: Text(context.strings.retry),
              onPressed: () => _controller.loadArtist(),
            ),
          ],
        ),
      ),
    );
  }

  // ── Main Content ───────────────────────────────────────────────────────────

  Widget _buildContent(
    ArtistFull artistFull,
    String? artistId,
    String? headerImageUrl,
    bool isDesktop,
  ) {
    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        _buildSliverAppBar(artistFull, artistId, headerImageUrl, isDesktop),
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: isDesktop ? 48.0 : 20.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 24),
                _buildTopTracksSection(artistFull, artistId, isDesktop),
                if (artistFull.topAlbums.isNotEmpty) ...[
                  const SizedBox(height: 32),
                  _buildDiscographySection(
                    context.strings.albums,
                    artistFull.topAlbums,
                    artistId,
                    artistFull.name,
                    isDesktop,
                    type: ArtistCatalogType.albums,
                  ),
                ],
                if (artistFull.topSingles.isNotEmpty) ...[
                  const SizedBox(height: 32),
                  _buildDiscographySection(
                    context.strings.singlesAndEPs,
                    artistFull.topSingles,
                    artistId,
                    artistFull.name,
                    isDesktop,
                    type: ArtistCatalogType.singles,
                  ),
                ],
                if (artistFull.featuredOn.isNotEmpty) ...[
                  const SizedBox(height: 32),
                  _buildPlaylistsSection(
                    context.strings.featuredOn,
                    artistFull.featuredOn,
                    isDesktop,
                  ),
                ],
                if (artistFull.topVideos.isNotEmpty) ...[
                  const SizedBox(height: 32),
                  _buildVideosSection(
                    context.strings.musicVideos,
                    artistFull.topVideos,
                    isDesktop,
                  ),
                ],
                if (artistFull.similarArtists.isNotEmpty) ...[
                  const SizedBox(height: 32),
                  _buildSimilarArtistsSection(
                    context.strings.similarArtists,
                    artistFull.similarArtists,
                    isDesktop,
                  ),
                ],
                const SizedBox(height: 120),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ── Sliver App Bar with Dynamic Hero Image ─────────────────────────────────

  Widget _buildSliverAppBar(
    ArtistFull artistFull,
    String? artistId,
    String? headerImageUrl,
    bool isDesktop,
  ) {
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
            if (headerImageUrl != null)
              CachedNetworkImage(
                imageUrl: headerImageUrl,
                fit: BoxFit.cover,
                memCacheWidth: 800,
                memCacheHeight: 600,
                placeholder: (context, url) => Container(color: _surfaceDark),
                errorWidget: (context, url, error) =>
                    Container(color: _surfaceDark),
              )
            else
              Container(color: _surfaceDark),
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
                    artistFull.name,
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
                      if (artistId != null)
                        OutlinedButton.icon(
                          onPressed: () => _openCatalog(
                            artistId,
                            artistFull.name,
                            ArtistCatalogType.albums,
                          ),
                          icon: const Icon(Icons.library_music_rounded,
                              size: 16, color: Colors.white),
                          label: Text(
                            context.strings.catalog,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(
                              color: Colors.white.withValues(alpha: 0.3),
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20),
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Top Tracks with Album Context & Quick Play ──────────────────────────────

  Widget _buildTopTracksSection(
    ArtistFull artistFull,
    String? artistId,
    bool isDesktop,
  ) {
    if (artistFull.topSongs.isEmpty) return const SizedBox.shrink();

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              context.strings.topTracks,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.onPlayTracks != null) ...[
                  IconButton(
                    icon: Icon(Icons.shuffle_rounded,
                        color: _primary, size: 20),
                    tooltip: 'Shuffle top tracks',
                    visualDensity: VisualDensity.compact,
                    onPressed: () {
                      final tracks = artistFull.topSongs
                          .map((s) => TrackInfo.fromSongDetailed(
                                s,
                                album: s.album?.name,
                                albumId: s.album?.albumId,
                                albumArtist: artistFull.name,
                              ))
                          .toList()
                        ..shuffle();
                      Navigator.of(context).popUntil((r) => r.isFirst);
                      widget.onPlayTracks!(tracks, initialIndex: 0);
                    },
                  ),
                  const SizedBox(width: 4),
                ],
                if (artistId != null)
                  TextButton(
                    onPressed: () => _openCatalog(
                      artistId,
                      artistFull.name,
                      ArtistCatalogType.songs,
                    ),
                    child: Text(
                      context.strings.seeAll,
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
          ],
        ),
        const SizedBox(height: 12),
        ...artistFull.topSongs.asMap().entries.take(5).map((entry) {
          final idx = entry.key;
          final track = entry.value;
          return _buildTrackItem(idx, track, artistFull);
        }),
      ],
    );
  }

  Widget _buildTrackItem(
    int index,
    SongDetailed item,
    ArtistFull artistFull,
  ) {
    final thumb = _getBestThumbnail(item.thumbnails);
    final albumName = item.album?.name;

    return InkWell(
      onTap: () {
        if (widget.onPlayTracks != null) {
          final tracks = artistFull.topSongs
              .map((s) => TrackInfo.fromSongDetailed(
                    s,
                    album: s.album?.name,
                    albumId: s.album?.albumId,
                    albumArtist: artistFull.name,
                  ))
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
                        placeholder: (context, url) =>
                            Container(color: _surfaceDark),
                        errorWidget: (context, url, err) => Container(
                          color: _surfaceDark,
                          child: const Icon(Icons.music_note_rounded,
                              color: Colors.white24, size: 20),
                        ),
                      )
                    : Container(
                        color: _surfaceDark,
                        child: const Icon(Icons.music_note_rounded,
                            color: Colors.white24, size: 20),
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
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      if (albumName != null && albumName.isNotEmpty) ...[
                        Icon(
                          Icons.album_outlined,
                          size: 12,
                          color: Colors.white38,
                        ),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            albumName,
                            style: const TextStyle(
                              color: Colors.white54,
                              fontSize: 12,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ] else ...[
                        Flexible(
                          child: Text(
                            artistFull.name,
                            style: const TextStyle(
                              color: Colors.white54,
                              fontSize: 12,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              _formatDuration(item.duration),
              style: const TextStyle(color: Colors.white54, fontSize: 13),
            ),
            const SizedBox(width: 6),
            IconButton(
              icon: Icon(
                Icons.play_circle_fill_rounded,
                color: _primary.withValues(alpha: 0.85),
                size: 24,
              ),
              tooltip: 'Play track',
              visualDensity: VisualDensity.compact,
              onPressed: () => _playSongDirectly(item),
            ),
            if (item.album != null && item.album!.albumId.isNotEmpty)
              PopupMenuButton<String>(
                icon: const Icon(
                  Icons.more_vert_rounded,
                  size: 18,
                  color: Colors.white54,
                ),
                padding: EdgeInsets.zero,
                color: _surfaceDark,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: BorderSide(
                    color: Colors.white.withValues(alpha: 0.12),
                  ),
                ),
                onSelected: (val) {
                  if (val == 'play') {
                    _playSongDirectly(item);
                  } else if (val == 'album') {
                    _openSongAlbum(item);
                  }
                },
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: 'play',
                    child: Row(
                      children: [
                        Icon(Icons.play_arrow_rounded,
                            color: _primary, size: 20),
                        const SizedBox(width: 10),
                        const Text('Play Song'),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'album',
                    child: Row(
                      children: [
                        const Icon(Icons.album_outlined,
                            color: Colors.white70, size: 18),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Go to Album (${item.album!.name})',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  // ── Discography Sections ───────────────────────────────────────────────────

  Widget _buildDiscographySection(
    String title,
    List<AlbumDetailed> albums,
    String? artistId,
    String artistName,
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
            if (artistId != null)
              TextButton(
                onPressed: () => _openCatalog(artistId, artistName, type),
                child: Text(
                  context.strings.seeAll,
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
                  ),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: thumb != null
                  ? CachedNetworkImage(
                      imageUrl: thumb,
                      fit: BoxFit.cover,
                      memCacheWidth: 280,
                      memCacheHeight: 280,
                      placeholder: (context, url) => const Center(
                        child: Icon(Icons.album_rounded,
                            color: Colors.white24, size: 40),
                      ),
                      errorWidget: (context, url, err) => const Center(
                        child: Icon(Icons.album_rounded,
                            color: Colors.white24, size: 40),
                      ),
                    )
                  : const Center(
                      child: Icon(Icons.album_rounded,
                          color: Colors.white24, size: 40),
                    ),
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
                            ),
                          ],
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: thumb != null
                            ? CachedNetworkImage(
                                imageUrl: thumb,
                                fit: BoxFit.cover,
                                memCacheWidth: 280,
                                memCacheHeight: 280,
                                placeholder: (_, __) =>
                                    Container(color: _surfaceDark),
                                errorWidget: (_, __, ___) => const Center(
                                  child: Icon(Icons.playlist_play_rounded,
                                      color: Colors.white24, size: 40),
                                ),
                              )
                            : const Center(
                                child: Icon(Icons.playlist_play_rounded,
                                    color: Colors.white24, size: 40),
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
                                    placeholder: (_, __) =>
                                        Container(color: _surfaceDark),
                                    errorWidget: (_, __, ___) => const Center(
                                      child: Icon(Icons.ondemand_video_rounded,
                                          color: Colors.white24, size: 36),
                                    ),
                                  )
                                : const Center(
                                    child: Icon(Icons.ondemand_video_rounded,
                                        color: Colors.white24, size: 36),
                                  ),
                          ),
                          Positioned(
                            bottom: 6,
                            right: 6,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.75),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                _formatDuration(video.duration),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
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
                                placeholder: (_, __) =>
                                    Container(color: _surfaceDark),
                                errorWidget: (_, __, ___) => const Center(
                                  child: Icon(Icons.person_rounded,
                                      color: Colors.white24, size: 40),
                                ),
                              )
                            : const Center(
                                child: Icon(Icons.person_rounded,
                                    color: Colors.white24, size: 40),
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

// ══════════════════════════════════════════════════════════════════════════════
// ARTIST PROFILE SHIMMER SKELETON
// ══════════════════════════════════════════════════════════════════════════════

class _ArtistProfileShimmerView extends StatelessWidget {
  final String artistName;
  final bool isDesktop;

  const _ArtistProfileShimmerView({
    required this.artistName,
    required this.isDesktop,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = context.cardDark;
    final baseColor = isDark
        ? cardColor.withValues(alpha: 0.6)
        : Colors.black.withValues(alpha: 0.05);
    final highlightColor = isDark
        ? cardColor.withValues(alpha: 0.18)
        : Colors.black.withValues(alpha: 0.12);
    final placeholderColor = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.black.withValues(alpha: 0.07);

    Widget shimmerBox({
      required double width,
      required double height,
      double borderRadius = 6,
      BoxShape shape = BoxShape.rectangle,
    }) {
      return Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: placeholderColor,
          borderRadius: shape == BoxShape.circle
              ? null
              : BorderRadius.circular(borderRadius),
          shape: shape,
        ),
      );
    }

    final heroHeight = (MediaQuery.of(context).size.height * 0.42)
        .clamp(280.0, 480.0);

    return RepaintBoundary(
      child: Shimmer.fromColors(
        baseColor: baseColor,
        highlightColor: highlightColor,
        child: CustomScrollView(
          physics: const NeverScrollableScrollPhysics(),
          slivers: [
            // Hero app bar shimmer
            SliverAppBar(
              expandedHeight: heroHeight,
              pinned: true,
              backgroundColor: cardColor,
              elevation: 0,
              leading: IconButton(
                icon: Container(
                  width: 40,
                  height: 40,
                  decoration: const BoxDecoration(
                    color: Colors.black38,
                    shape: BoxShape.circle,
                  ),
                  child:
                      const Icon(Icons.keyboard_arrow_down, color: Colors.white),
                ),
                onPressed: () => Navigator.pop(context),
              ),
              flexibleSpace: FlexibleSpaceBar(
                background: Stack(
                  fit: StackFit.expand,
                  children: [
                    Container(color: cardColor),
                    Positioned(
                      bottom: 24,
                      left: 20,
                      right: 20,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          shimmerBox(width: 60, height: 14, borderRadius: 4),
                          const SizedBox(height: 8),
                          shimmerBox(
                            width: isDesktop ? 280 : 200,
                            height: 36,
                            borderRadius: 6,
                          ),
                          const SizedBox(height: 14),
                          shimmerBox(width: 100, height: 32, borderRadius: 16),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Body sliver
            SliverToBoxAdapter(
              child: Padding(
                padding:
                    EdgeInsets.symmetric(horizontal: isDesktop ? 48.0 : 20.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 24),
                    // Top tracks shimmer
                    shimmerBox(width: 120, height: 20, borderRadius: 4),
                    const SizedBox(height: 12),
                    for (var i = 0; i < 5; i++)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8.0),
                        child: Row(
                          children: [
                            shimmerBox(width: 24, height: 14, borderRadius: 4),
                            const SizedBox(width: 12),
                            shimmerBox(width: 44, height: 44, borderRadius: 8),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  shimmerBox(
                                    width: isDesktop ? 220 : 150,
                                    height: 14,
                                    borderRadius: 4,
                                  ),
                                  const SizedBox(height: 6),
                                  shimmerBox(
                                    width: isDesktop ? 140 : 90,
                                    height: 11,
                                    borderRadius: 4,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            shimmerBox(width: 34, height: 12, borderRadius: 4),
                            const SizedBox(width: 8),
                            shimmerBox(
                              width: 26,
                              height: 26,
                              shape: BoxShape.circle,
                            ),
                          ],
                        ),
                      ),

                    const SizedBox(height: 32),
                    // Albums carousel shimmer
                    shimmerBox(width: 100, height: 20, borderRadius: 4),
                    const SizedBox(height: 14),
                    SizedBox(
                      height: 195,
                      child: ListView.separated(
                        physics: const NeverScrollableScrollPhysics(),
                        scrollDirection: Axis.horizontal,
                        itemCount: 4,
                        separatorBuilder: (_, __) => const SizedBox(width: 14),
                        itemBuilder: (_, __) => Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            shimmerBox(width: 140, height: 140, borderRadius: 16),
                            const SizedBox(height: 8),
                            shimmerBox(width: 110, height: 13, borderRadius: 4),
                            const SizedBox(height: 4),
                            shimmerBox(width: 60, height: 11, borderRadius: 4),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 32),
                    // Singles carousel shimmer
                    shimmerBox(width: 130, height: 20, borderRadius: 4),
                    const SizedBox(height: 14),
                    SizedBox(
                      height: 195,
                      child: ListView.separated(
                        physics: const NeverScrollableScrollPhysics(),
                        scrollDirection: Axis.horizontal,
                        itemCount: 4,
                        separatorBuilder: (_, __) => const SizedBox(width: 14),
                        itemBuilder: (_, __) => Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            shimmerBox(width: 140, height: 140, borderRadius: 16),
                            const SizedBox(height: 8),
                            shimmerBox(width: 110, height: 13, borderRadius: 4),
                            const SizedBox(height: 4),
                            shimmerBox(width: 60, height: 11, borderRadius: 4),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 120),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
