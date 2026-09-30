import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:dart_ytmusic_api/dart_ytmusic_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_m3shapes_extended/flutter_m3shapes_extended.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:shimmer/shimmer.dart';

import 'album_detail_screen.dart';
import 'artist_profile_screen.dart';
import 'search_screen.dart';
import 'services/app_theme_service.dart';

// ══════════════════════════════════════════════════════════════════════════════
// REACTIVE HOME STATE MODEL
// ══════════════════════════════════════════════════════════════════════════════

sealed class HomeScreenState {
  const HomeScreenState();
}

class HomeStateLoading extends HomeScreenState {
  const HomeStateLoading();
}

class HomeStateSuccess extends HomeScreenState {
  final List<HomeSection> sections;
  final dynamic spotlightItem;
  final DateTime lastUpdated;

  HomeStateSuccess({
    required this.sections,
    this.spotlightItem,
    DateTime? lastUpdated,
  }) : lastUpdated = lastUpdated ?? DateTime.now();
}

class HomeStateError extends HomeScreenState {
  final String message;
  const HomeStateError({required this.message});
}

// ══════════════════════════════════════════════════════════════════════════════
// REACTIVE HOME CONTROLLER
// ══════════════════════════════════════════════════════════════════════════════

class HomeReactiveController extends ValueNotifier<HomeScreenState> {
  final YTMusic _ytMusic = YTMusic();
  int _activeRequestId = 0;

  HomeReactiveController() : super(const HomeStateLoading());

  Future<void> init() async {
    await refresh(keepCurrentData: false);
  }

  Future<void> refresh({bool keepCurrentData = false}) async {
    final token = ++_activeRequestId;
    if (!keepCurrentData) {
      value = const HomeStateLoading();
    }

    try {
      await _ytMusic.initialize();
      final sections = await _ytMusic.getHomeSections();
      if (token != _activeRequestId) return;

      final validSections =
          sections.where((s) => s.contents.isNotEmpty).toList();
      dynamic spotlight;
      if (validSections.isNotEmpty && validSections.first.contents.isNotEmpty) {
        spotlight = validSections.first.contents.first;
      }

      value = HomeStateSuccess(
        sections: validSections,
        spotlightItem: spotlight,
      );
    } catch (e) {
      if (token != _activeRequestId) return;
      String msg = 'Could not load online feed. Please try again.';
      final errStr = e.toString().toLowerCase();
      if (errStr.contains('socketexception') ||
          errStr.contains('timeout') ||
          errStr.contains('failed host lookup') ||
          errStr.contains('handshakeexception')) {
        msg = 'No internet connection. Please check your network.';
      }
      value = HomeStateError(message: msg);
    }
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// HOME SCREEN WIDGET
// ══════════════════════════════════════════════════════════════════════════════

class HomeScreen extends StatefulWidget {
  final Future<void> Function(List<TrackInfo> tracks, {int initialIndex})?
      onPlayTracks;
  final VoidCallback? onGoToDownloads;
  final bool isNested;

  const HomeScreen({
    super.key,
    this.onPlayTracks,
    this.onGoToDownloads,
    this.isNested = false,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  final HomeReactiveController _controller = HomeReactiveController();

  // Dynamic theme colors
  Color get _bgDark => context.bgDark;
  Color get _surfaceDark => context.cardDark;
  Color get _surfaceBorder => context.cardDark.withValues(alpha: 0.5);
  Color get _primary => context.primaryColor;
  Color get _textPrimary => context.textPrimary;
  Color get _textSecondary => context.textMuted;

  @override
  void initState() {
    super.initState();
    _controller.init();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  // ── Common metadata extractors ─────────────────────────────────────────────

  String _itemName(dynamic item) {
    if (item is SongDetailed) return item.name;
    if (item is VideoDetailed) return item.name;
    if (item is AlbumDetailed) return item.name;
    if (item is PlaylistDetailed) return item.name;
    if (item is ArtistDetailed) return item.name;
    return '';
  }

  String _itemSubtitle(dynamic item) {
    if (item is SongDetailed) return item.artist.name;
    if (item is VideoDetailed) return item.artist.name;
    if (item is AlbumDetailed) return item.artist.name;
    if (item is PlaylistDetailed) return item.artist.name;
    if (item is ArtistDetailed) return 'Artist';
    return '';
  }

  String? _itemThumbnail(dynamic item) {
    List<ThumbnailFull>? thumbs;
    if (item is SongDetailed) thumbs = item.thumbnails;
    if (item is VideoDetailed) thumbs = item.thumbnails;
    if (item is AlbumDetailed) thumbs = item.thumbnails;
    if (item is PlaylistDetailed) thumbs = item.thumbnails;
    if (item is ArtistDetailed) thumbs = item.thumbnails;
    if (thumbs == null || thumbs.isEmpty) return null;
    final sorted = List<ThumbnailFull>.from(thumbs)
      ..sort((a, b) => b.width.compareTo(a.width));
    return sorted.first.url;
  }

  String _formatDuration(int? durationSeconds) {
    if (durationSeconds == null || durationSeconds <= 0) return '';
    final d = Duration(seconds: durationSeconds);
    final m = d.inMinutes;
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  int _parseDuration(String? durationStr) {
    if (durationStr == null || durationStr.isEmpty) return 0;
    final parts = durationStr.split(':');
    if (parts.length == 2) {
      return (int.tryParse(parts[0]) ?? 0) * 60 +
          (int.tryParse(parts[1]) ?? 0);
    } else if (parts.length == 3) {
      return (int.tryParse(parts[0]) ?? 0) * 3600 +
          (int.tryParse(parts[1]) ?? 0) * 60 +
          (int.tryParse(parts[2]) ?? 0);
    }
    return 0;
  }

  TrackInfo _createTrackInfo(dynamic item) {
    if (item is SongDetailed) {
      return TrackInfo(
        videoId: item.videoId,
        title: item.name,
        artist: item.artist.name,
        artistId: item.artist.artistId,
        album: item.album?.name,
        albumId: item.album?.albumId,
        albumArtist: item.artist.name,
        durationSeconds: item.duration is int
            ? item.duration
            : _parseDuration(item.duration?.toString()),
        thumbnailUrl: _itemThumbnail(item),
      );
    } else if (item is VideoDetailed) {
      return TrackInfo(
        videoId: item.videoId,
        title: item.name,
        artist: item.artist.name,
        artistId: item.artist.artistId,
        albumArtist: item.artist.name,
        durationSeconds: item.duration,
        thumbnailUrl: _itemThumbnail(item),
      );
    }
    return TrackInfo(
      videoId: '',
      title: _itemName(item),
      artist: _itemSubtitle(item),
      thumbnailUrl: _itemThumbnail(item),
    );
  }

  // ── Navigation & Direct Play Actions ───────────────────────────────────────

  void _openItem(dynamic item) {
    if (item is ArtistDetailed) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ArtistProfileScreen(
            artistId: item.artistId,
            artistName: item.name,
            onPlayTracks: widget.onPlayTracks,
          ),
        ),
      );
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AlbumDetailScreen(
          item: item,
          onPlayTracks: widget.onPlayTracks,
        ),
      ),
    );
  }

  void _playTrackDirectly(dynamic item) {
    final track = _createTrackInfo(item);
    if (track.videoId.isNotEmpty && widget.onPlayTracks != null) {
      widget.onPlayTracks!([track], initialIndex: 0);
    } else {
      _openItem(item);
    }
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

  void _openSongArtist(SongDetailed song) {
    final artistId = song.artist.artistId;
    if (artistId == null || artistId.isEmpty) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ArtistProfileScreen(
          artistId: artistId,
          artistName: song.artist.name,
          onPlayTracks: widget.onPlayTracks,
        ),
      ),
    );
  }

  // ── Carousel layout rotation ───────────────────────────────────────────────

  static const List<M3ECarouselType> _carouselTypes = [
    M3ECarouselType.hero,
    M3ECarouselType.contained,
    M3ECarouselType.uncontained,
  ];

  static M3ECarouselType _carouselTypeFor(int sectionIndex) =>
      _carouselTypes[sectionIndex % _carouselTypes.length];

  // ── Build Method ───────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth >= 800;

        return Scaffold(
          backgroundColor: _bgDark,
          body: SafeArea(
            bottom: false,
            child: ValueListenableBuilder<HomeScreenState>(
              valueListenable: _controller,
              builder: (context, state, _) {
                return AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  child: KeyedSubtree(
                    key: ValueKey(_stateKey(state)),
                    child: switch (state) {
                      HomeStateLoading() => _HomeShimmerView(
                          isDesktop: isDesktop,
                          isNested: widget.isNested,
                        ),
                      HomeStateError(:final message) => _buildError(message),
                      HomeStateSuccess(
                        :final sections,
                        :final spotlightItem,
                      ) =>
                        RefreshIndicator(
                          color: _primary,
                          backgroundColor: _surfaceDark,
                          onRefresh: () =>
                              _controller.refresh(keepCurrentData: true),
                          child: isDesktop
                              ? _buildDesktopLayout(sections, spotlightItem)
                              : _buildMobileLayout(sections, spotlightItem),
                        ),
                    },
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }

  String _stateKey(HomeScreenState state) {
    return switch (state) {
      HomeStateLoading() => 'loading',
      HomeStateError() => 'error',
      HomeStateSuccess() => 'success',
    };
  }

  // ── Mobile & Desktop Layouts ───────────────────────────────────────────────

  Widget _buildMobileLayout(
    List<HomeSection> sections,
    dynamic spotlightItem,
  ) {
    return CustomScrollView(
      physics:
          const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
      slivers: [
        const SliverToBoxAdapter(child: SizedBox(height: 12)),
        if (!widget.isNested) _buildHeader(isDesktop: false),
        if (spotlightItem != null)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: _buildSpotlightCard(spotlightItem, isDesktop: false),
            ),
          ),
        for (var i = 0; i < sections.length; i++) ...[
          SliverToBoxAdapter(
            child: _buildSectionHeader(sections[i].title, isDesktop: false),
          ),
          SliverToBoxAdapter(
            child: _buildSectionContent(
              sections[i],
              sectionIndex: i,
              isDesktop: false,
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 8)),
        ],
        const SliverToBoxAdapter(child: SizedBox(height: 140)),
      ],
    );
  }

  Widget _buildDesktopLayout(
    List<HomeSection> sections,
    dynamic spotlightItem,
  ) {
    return CustomScrollView(
      physics:
          const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
      slivers: [
        const SliverToBoxAdapter(child: SizedBox(height: 12)),
        if (!widget.isNested) _buildHeader(isDesktop: true),
        if (spotlightItem != null)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(28, 16, 28, 16),
              child: _buildSpotlightCard(spotlightItem, isDesktop: true),
            ),
          ),
        for (var i = 0; i < sections.length; i++) ...[
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12.0),
              child: _buildSectionHeader(sections[i].title, isDesktop: true),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: _buildSectionContent(
                sections[i],
                sectionIndex: i,
                isDesktop: true,
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 36)),
        ],
        const SliverToBoxAdapter(child: SizedBox(height: 140)),
      ],
    );
  }

  // ── Header Widget ──────────────────────────────────────────────────────────

  Widget _buildHeader({bool isDesktop = false}) {
    return SliverAppBar(
      backgroundColor: _bgDark,
      pinned: true,
      floating: true,
      elevation: 0,
      toolbarHeight: isDesktop ? 90 : 72,
      title: Padding(
        padding: EdgeInsets.only(left: isDesktop ? 16.0 : 4.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              _greeting(),
              style: TextStyle(
                color: _textPrimary,
                fontSize: isDesktop ? 28 : 22,
                fontWeight: FontWeight.bold,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'Music curated for you',
              style: TextStyle(
                color: _textSecondary,
                fontSize: isDesktop ? 14 : 12,
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
      actions: [
        Padding(
          padding: EdgeInsets.only(right: isDesktop ? 24.0 : 16.0),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              M3ETooltip(
                message: 'Search',
                child: M3EIconButton(
                  icon: const Icon(Icons.search_rounded, size: 20),
                  variant: M3EIconButtonVariant.tonal,
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => SearchScreen(
                          onPlayTracks: widget.onPlayTracks,
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(width: 8),
              M3ETooltip(
                message: 'Refresh feed',
                child: M3EIconButton(
                  icon: const Icon(Icons.refresh_rounded, size: 20),
                  variant: M3EIconButtonVariant.tonal,
                  onPressed: () => _controller.refresh(keepCurrentData: false),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── Spotlight Banner with Rich Song & Album Info ───────────────────────────

  Widget _buildSpotlightCard(dynamic item, {bool isDesktop = false}) {
    final name = _itemName(item);
    final thumb = _itemThumbnail(item);
    final isSong = item is SongDetailed;
    final isVideo = item is VideoDetailed;
    final isAlbum = item is AlbumDetailed;
    final isPlaylist = item is PlaylistDetailed;

    String typeLabel = 'FEATURED';
    IconData typeIcon = Icons.star_rounded;
    if (isSong) {
      typeLabel = 'FEATURED SONG';
      typeIcon = Icons.music_note_rounded;
    } else if (isVideo) {
      typeLabel = 'FEATURED VIDEO';
      typeIcon = Icons.ondemand_video_rounded;
    } else if (isAlbum) {
      typeLabel = 'FEATURED ALBUM';
      typeIcon = Icons.album_rounded;
    } else if (isPlaylist) {
      typeLabel = 'FEATURED PLAYLIST';
      typeIcon = Icons.playlist_play_rounded;
    }

    String subtitle = _itemSubtitle(item);
    String? extraContext;
    if (isSong && item.album != null && item.album!.name.isNotEmpty) {
      extraContext = 'Album: ${item.album!.name}';
    } else if (isAlbum && item.year != null) {
      extraContext = '${item.year}';
    }

    return RepaintBoundary(
      child: M3ECard(
        variant: M3ECardVariant.elevated,
        onPressed: () => _openItem(item),
        color: _surfaceDark,
        borderRadius: BorderRadius.circular(24),
        padding: EdgeInsets.all(isDesktop ? 20 : 15),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 3.5),
                  decoration: BoxDecoration(
                    color: _primary.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(typeIcon, color: _primary, size: 12),
                      const SizedBox(width: 4),
                      Text(
                        typeLabel,
                        style: TextStyle(
                          color: _primary,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.0,
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                if (isSong && item.duration != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 2.5),
                    decoration: BoxDecoration(
                      color: _surfaceBorder.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _formatDuration(item.duration),
                      style: TextStyle(
                        color: _textSecondary,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                // Spotlight Artwork
                SizedBox(
                  width: isDesktop ? 104 : 80,
                  height: isDesktop ? 104 : 80,
                  child: M3EContainer(
                    Shapes.slanted,
                    color: _surfaceDark,
                    border: BorderSide(
                      color: _primary.withValues(alpha: 0.3),
                      width: 1.5,
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: thumb != null
                        ? CachedNetworkImage(
                            imageUrl: thumb,
                            fit: BoxFit.cover,
                            memCacheWidth: 240,
                            memCacheHeight: 240,
                            placeholder: (_, __) => Container(
                              color: _surfaceBorder,
                              child: const Icon(
                                Icons.music_note_rounded,
                                color: Colors.white24,
                                size: 28,
                              ),
                            ),
                            errorWidget: (_, __, ___) => Container(
                              color: _surfaceBorder,
                              child: const Icon(
                                Icons.music_note_rounded,
                                color: Colors.white24,
                                size: 28,
                              ),
                            ),
                          )
                        : Container(
                            color: _surfaceBorder,
                            child: const Icon(
                              Icons.music_note_rounded,
                              color: Colors.white24,
                              size: 28,
                            ),
                          ),
                  ),
                ),
                const SizedBox(width: 16),
                // Text details
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: _textPrimary,
                          fontSize: isDesktop ? 19 : 16,
                          fontWeight: FontWeight.bold,
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: _textSecondary,
                          fontSize: isDesktop ? 14 : 12.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      if (extraContext != null) ...[
                        const SizedBox(height: 3),
                        Text(
                          extraContext,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: _textSecondary.withValues(alpha: 0.8),
                            fontSize: isDesktop ? 12.5 : 11,
                          ),
                        ),
                      ],
                      const SizedBox(height: 10),
                      // Action buttons row
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          FilledButton.tonalIcon(
                            icon: const Icon(Icons.play_arrow_rounded, size: 18),
                            label: const Text('Play'),
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 4,
                              ),
                              visualDensity: VisualDensity.compact,
                            ),
                            onPressed: () => _playTrackDirectly(item),
                          ),
                          if (isSong &&
                              item.album != null &&
                              item.album!.albumId.isNotEmpty)
                            OutlinedButton.icon(
                              icon: const Icon(Icons.album_outlined, size: 14),
                              label: const Text('Album'),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                                visualDensity: VisualDensity.compact,
                              ),
                              onPressed: () => _openSongAlbum(item),
                            ),
                          if (isSong &&
                              item.artist.artistId != null &&
                              item.artist.artistId!.isNotEmpty)
                            OutlinedButton.icon(
                              icon: const Icon(Icons.person_outline_rounded,
                                  size: 14),
                              label: const Text('Artist'),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                                visualDensity: VisualDensity.compact,
                              ),
                              onPressed: () => _openSongArtist(item),
                            ),
                        ],
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

  // ── Section Header ─────────────────────────────────────────────────────────

  Widget _buildSectionHeader(String title, {bool isDesktop = false}) {
    if (title.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: EdgeInsets.fromLTRB(
        isDesktop ? 28 : 16,
        isDesktop ? 24 : 20,
        isDesktop ? 28 : 16,
        isDesktop ? 14 : 10,
      ),
      child: Row(
        children: [
          Container(
            width: 4,
            height: isDesktop ? 22 : 18,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  _primary,
                  _primary.withValues(alpha: 0.6),
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: _textPrimary,
                fontSize: isDesktop ? 22 : 18,
                fontWeight: FontWeight.bold,
                letterSpacing: -0.4,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Container(
              height: 1.5,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    _textSecondary.withValues(alpha: 0.25),
                    _textSecondary.withValues(alpha: 0.0),
                  ],
                ),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Section Content with Carousel ──────────────────────────────────────────

  Widget _buildSectionContent(
    HomeSection section, {
    int sectionIndex = 0,
    bool isDesktop = false,
  }) {
    final M3ECarouselType type = _carouselTypeFor(sectionIndex);

    final double height = switch (type) {
      M3ECarouselType.hero => isDesktop ? 344 : 304,
      M3ECarouselType.contained => isDesktop ? 288 : 252,
      M3ECarouselType.uncontained => isDesktop ? 284 : 256,
    };

    return SizedBox(
      height: height,
      child: M3ECarousel(
        type: type,
        heroAlignment: M3ECarouselHeroAlignment.left,
        isExtended: isDesktop,
        uncontainedItemExtent: isDesktop ? 200 : 172,
        uncontainedShrinkExtent: 150,
        childElementBorderRadius: 22,
        onTap: (i) {
          if (i >= 0 && i < section.contents.length) {
            _openItem(section.contents[i]);
          }
        },
        children: [
          for (final item in section.contents)
            _buildOverlayTile(item, compact: type != M3ECarouselType.hero),
        ],
      ),
    );
  }

  // ── Overlay Tile with Rich Media Badges & Quick Play ───────────────────────

  Widget _buildOverlayTile(dynamic item, {bool compact = false}) {
    final name = _itemName(item);
    final subtitle = _itemSubtitle(item);
    final thumb = _itemThumbnail(item);
    final isSong = item is SongDetailed;
    final isVideo = item is VideoDetailed;
    final isAlbum = item is AlbumDetailed;
    final isPlaylist = item is PlaylistDetailed;

    final double inset = compact ? 12 : 18;
    final double titleSize = compact ? 14 : 19;
    final double subtitleSize = compact ? 11.5 : 12.5;

    // Type badge information
    String typeTag = '';
    IconData? typeIcon;
    if (isSong) {
      typeTag = item.duration != null
          ? 'SONG • ${_formatDuration(item.duration)}'
          : 'SONG';
      typeIcon = Icons.music_note_rounded;
    } else if (isVideo) {
      typeTag = item.duration != null
          ? 'VIDEO • ${_formatDuration(item.duration)}'
          : 'VIDEO';
      typeIcon = Icons.ondemand_video_rounded;
    } else if (isAlbum) {
      typeTag = item.year != null ? 'ALBUM • ${item.year}' : 'ALBUM';
      typeIcon = Icons.album_rounded;
    } else if (isPlaylist) {
      typeTag = 'PLAYLIST';
      typeIcon = Icons.playlist_play_rounded;
    }

    String displaySubtitle = subtitle;
    if (isSong &&
        item.album != null &&
        item.album!.name.isNotEmpty &&
        item.album!.name != item.name) {
      displaySubtitle = '$subtitle • ${item.album!.name}';
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        // Full-bleed artwork
        thumb != null
            ? CachedNetworkImage(
                imageUrl: thumb,
                fit: BoxFit.cover,
                alignment: Alignment.topCenter,
                memCacheWidth: 600,
                memCacheHeight: 600,
                placeholder: (_, __) => Container(color: _surfaceDark),
                errorWidget: (_, __, ___) => Container(color: _surfaceDark),
              )
            : Container(color: _surfaceDark),
        // Dark gradient scrim for legibility
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
              stops: compact ? const [0.0, 0.65] : const [0.0, 0.58],
              colors: [
                Colors.black.withValues(alpha: compact ? 0.88 : 0.90),
                Colors.transparent,
              ],
            ),
          ),
        ),
        // Top-left type tag badge
        if (typeTag.isNotEmpty)
          Positioned(
            top: inset * 0.8,
            left: inset * 0.8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.58),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.15),
                  width: 0.8,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (typeIcon != null) ...[
                    Icon(typeIcon, size: 10.5, color: _primary),
                    const SizedBox(width: 3.5),
                  ],
                  Text(
                    typeTag,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.92),
                      fontSize: 9.5,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.6,
                    ),
                  ),
                ],
              ),
            ),
          ),
        // Title & artist/album overlaid at bottom
        Positioned(
          left: inset,
          right: inset + (compact ? 42 : 58),
          bottom: inset,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: titleSize,
                  height: 1.15,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.3,
                  shadows: const [
                    Shadow(
                      color: Colors.black54,
                      blurRadius: 12,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 3),
              Text(
                displaySubtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.82),
                  fontSize: subtitleSize,
                  height: 1.15,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        // Floating quick play button
        Positioned(
          right: compact ? 10 : 14,
          bottom: compact ? 10 : 14,
          child: Material(
            color: Colors.transparent,
            shape: const CircleBorder(),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => _playTrackDirectly(item),
              child: M3EContainer.circle(
                width: compact ? 34 : 44,
                height: compact ? 34 : 44,
                gradient: LinearGradient(
                  colors: [
                    _primary,
                    _primary.withValues(alpha: 0.85),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.35),
                    blurRadius: compact ? 8 : 12,
                    offset: const Offset(0, 3),
                  ),
                ],
                child: Center(
                  child: Icon(
                    Icons.play_arrow_rounded,
                    color: Colors.white,
                    size: compact ? 20 : 26,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ── Error state ────────────────────────────────────────────────────────────

  Widget _buildError(String message) {
    return RepaintBoundary(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              M3EContainer(
                Shapes.c4SidedCookie,
                width: 96,
                height: 96,
                gradient: LinearGradient(
                  colors: [
                    _primary,
                    _primary.withValues(alpha: 0.7),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: [
                  BoxShadow(
                    color: _primary.withValues(alpha: 0.35),
                    blurRadius: 20,
                    offset: const Offset(0, 6),
                  ),
                ],
                child: const Center(
                  child: Icon(
                    Icons.wifi_off_rounded,
                    size: 46,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'Could not load feed',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: _textPrimary,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: _textSecondary,
                  fontSize: 14,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 28),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  M3EButton.icon(
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: const Text('Retry'),
                    onPressed: () =>
                        _controller.refresh(keepCurrentData: false),
                  ),
                  if (widget.onGoToDownloads != null) ...[
                    const SizedBox(width: 12),
                    M3EButton.icon(
                      icon: const Icon(Icons.library_music_rounded, size: 18),
                      label: const Text('Go to Library Tracks'),
                      onPressed: widget.onGoToDownloads,
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// HOME SHIMMER SKELETON
// ══════════════════════════════════════════════════════════════════════════════

class _HomeShimmerView extends StatelessWidget {
  final bool isDesktop;
  final bool isNested;

  const _HomeShimmerView({
    required this.isDesktop,
    required this.isNested,
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
          borderRadius:
              shape == BoxShape.circle ? null : BorderRadius.circular(borderRadius),
          shape: shape,
        ),
      );
    }

    return RepaintBoundary(
      child: Shimmer.fromColors(
        baseColor: baseColor,
        highlightColor: highlightColor,
        child: CustomScrollView(
          physics: const NeverScrollableScrollPhysics(),
          slivers: [
            const SliverToBoxAdapter(child: SizedBox(height: 12)),
            // Header skeleton
            if (!isNested)
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    isDesktop ? 32 : 16,
                    16,
                    isDesktop ? 32 : 16,
                    12,
                  ),
                  child: Row(
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          shimmerBox(
                            width: isDesktop ? 200 : 150,
                            height: isDesktop ? 26 : 22,
                            borderRadius: 6,
                          ),
                          const SizedBox(height: 6),
                          shimmerBox(
                            width: isDesktop ? 130 : 100,
                            height: 13,
                            borderRadius: 4,
                          ),
                        ],
                      ),
                      const Spacer(),
                      shimmerBox(
                        width: 38,
                        height: 38,
                        shape: BoxShape.circle,
                      ),
                      const SizedBox(width: 8),
                      shimmerBox(
                        width: 38,
                        height: 38,
                        shape: BoxShape.circle,
                      ),
                    ],
                  ),
                ),
              ),

            // Spotlight Banner skeleton
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: isDesktop ? 28 : 16,
                  vertical: 12,
                ),
                child: Container(
                  decoration: BoxDecoration(
                    color: cardColor,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: context.outlineColor.withValues(alpha: 0.12),
                    ),
                  ),
                  padding: EdgeInsets.all(isDesktop ? 20 : 15),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          shimmerBox(width: 75, height: 16, borderRadius: 8),
                          const Spacer(),
                          shimmerBox(width: 36, height: 14, borderRadius: 6),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          shimmerBox(
                            width: isDesktop ? 104 : 80,
                            height: isDesktop ? 104 : 80,
                            borderRadius: 16,
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                shimmerBox(
                                  width: isDesktop ? 220 : 160,
                                  height: 18,
                                  borderRadius: 4,
                                ),
                                const SizedBox(height: 8),
                                shimmerBox(
                                  width: isDesktop ? 140 : 100,
                                  height: 13,
                                  borderRadius: 4,
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    shimmerBox(
                                      width: 60,
                                      height: 22,
                                      borderRadius: 8,
                                    ),
                                    const SizedBox(width: 8),
                                    shimmerBox(
                                      width: 65,
                                      height: 22,
                                      borderRadius: 8,
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // 2 Section Carousel skeletons
            for (var s = 0; s < 2; s++) ...[
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    isDesktop ? 28 : 16,
                    20,
                    isDesktop ? 28 : 16,
                    12,
                  ),
                  child: Row(
                    children: [
                      shimmerBox(width: 4, height: 18, borderRadius: 2),
                      const SizedBox(width: 10),
                      shimmerBox(
                        width: isDesktop ? 160 : 130,
                        height: 18,
                        borderRadius: 4,
                      ),
                    ],
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: SizedBox(
                  height: isDesktop ? 288 : 252,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    physics: const NeverScrollableScrollPhysics(),
                    padding: EdgeInsets.symmetric(
                      horizontal: isDesktop ? 28 : 16,
                    ),
                    itemCount: 4,
                    itemBuilder: (context, i) {
                      return Padding(
                        padding: const EdgeInsets.only(right: 14),
                        child: Container(
                          width: isDesktop ? 210 : 172,
                          decoration: BoxDecoration(
                            color: cardColor,
                            borderRadius: BorderRadius.circular(22),
                            border: Border.all(
                              color:
                                  context.outlineColor.withValues(alpha: 0.12),
                            ),
                          ),
                          child: Stack(
                            children: [
                              Positioned(
                                top: 12,
                                left: 12,
                                child: shimmerBox(
                                  width: 50,
                                  height: 15,
                                  borderRadius: 6,
                                ),
                              ),
                              Positioned(
                                left: 14,
                                bottom: 14,
                                right: 54,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    shimmerBox(
                                      width: 100,
                                      height: 14,
                                      borderRadius: 4,
                                    ),
                                    const SizedBox(height: 6),
                                    shimmerBox(
                                      width: 70,
                                      height: 11,
                                      borderRadius: 4,
                                    ),
                                  ],
                                ),
                              ),
                              Positioned(
                                right: 12,
                                bottom: 12,
                                child: shimmerBox(
                                  width: 34,
                                  height: 34,
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 16)),
            ],
            const SliverToBoxAdapter(child: SizedBox(height: 120)),
          ],
        ),
      ),
    );
  }
}
