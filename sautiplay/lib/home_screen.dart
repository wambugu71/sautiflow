import 'package:cached_network_image/cached_network_image.dart';
import 'package:dart_ytmusic_api/dart_ytmusic_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_m3shapes_extended/flutter_m3shapes_extended.dart';
import 'package:material_3_expressive/material_3_expressive.dart';

import 'album_detail_screen.dart';
import 'search_screen.dart';
import 'services/app_theme_service.dart';
import 'stream_extraction_test_screen.dart';

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

  // ─ Dynamic theme colors from BuildContext ─
  Color get _bgDark => context.bgDark;
  Color get _surfaceDark => context.cardDark;
  Color get _surfaceBorder => context.cardDark.withValues(alpha: 0.5);
  Color get _primary => context.primaryColor;
  Color get _textPrimary => context.textPrimary;
  Color get _textSecondary => context.textMuted;
  final YTMusic _ytMusic = YTMusic();
  List<HomeSection> _sections = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadHome();
  }

  Future<void> _loadHome() async {
    try {
      await _ytMusic.initialize();
      final sections = await _ytMusic.getHomeSections();
      if (mounted) {
        setState(() {
          _sections = sections.where((s) => s.contents.isNotEmpty).toList();
          _loading = false;
        });
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

  String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  // ── Extract common fields from the dynamic content items ──
  String _itemName(dynamic item) {
    if (item is SongDetailed) return item.name;
    if (item is AlbumDetailed) return item.name;
    if (item is PlaylistDetailed) return item.name;
    return '';
  }

  String _itemSubtitle(dynamic item) {
    if (item is SongDetailed) return item.artist.name;
    if (item is AlbumDetailed) return item.artist.name;
    if (item is PlaylistDetailed) return item.artist.name;
    return '';
  }

  String? _itemThumbnail(dynamic item) {
    List<ThumbnailFull>? thumbs;
    if (item is SongDetailed) thumbs = item.thumbnails;
    if (item is AlbumDetailed) thumbs = item.thumbnails;
    if (item is PlaylistDetailed) thumbs = item.thumbnails;
    if (thumbs == null || thumbs.isEmpty) return null;
    thumbs.sort((a, b) => b.width.compareTo(a.width));
    return thumbs.first.url;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth >= 800;

        return Scaffold(
          backgroundColor: _bgDark,
          body: _loading
              ? RepaintBoundary(
                  child: Center(
                    child: M3ELoadingIndicator(
                      color: _primary,
                      containerColor: _primary.withValues(alpha: 0.15),
                    ),
                  ),
                )
              : _error != null
                  ? _buildError()
                  : RefreshIndicator(
                      color: _primary,
                      backgroundColor: _surfaceDark,
                      onRefresh: () async {
                        setState(() => _loading = true);
                        await _loadHome();
                      },
                      child: isDesktop
                          ? _buildDesktopLayout()
                          : _buildMobileLayout(),
                    ),
        );
      },
    );
  }

  Widget _buildMobileLayout() {
    dynamic spotlightItem;
    if (_sections.isNotEmpty && _sections.first.contents.isNotEmpty) {
      spotlightItem = _sections.first.contents.first;
    }

    return CustomScrollView(
      physics:
          const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
      slivers: [
        // ── Header ──
        if (!widget.isNested) _buildHeader(isDesktop: false),

        // ── Featured Spotlight Banner ──
        if (spotlightItem != null)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: _buildSpotlightCard(spotlightItem, isDesktop: false),
            ),
          ),

        // ── Home Sections ──
        for (final section in _sections) ...[
          SliverToBoxAdapter(
            child: _buildSectionHeader(section.title, isDesktop: false),
          ),
          SliverToBoxAdapter(
            child: _buildSectionContent(section),
          ),
        ],

        // Bottom padding so content doesn't hide behind mini player
        const SliverToBoxAdapter(child: SizedBox(height: 140)),
      ],
    );
  }

  Widget _buildDesktopLayout() {
    dynamic spotlightItem;
    if (_sections.isNotEmpty && _sections.first.contents.isNotEmpty) {
      spotlightItem = _sections.first.contents.first;
    }

    return CustomScrollView(
      physics:
          const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
      slivers: [
        // ── Header ──
        if (!widget.isNested) _buildHeader(isDesktop: true),

        // ── Featured Spotlight Banner ──
        if (spotlightItem != null)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(28, 16, 28, 16),
              child: _buildSpotlightCard(spotlightItem, isDesktop: true),
            ),
          ),

        // ── Home Sections ──
        for (final section in _sections) ...[
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12.0),
              child: _buildSectionHeader(section.title, isDesktop: true),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28.0),
              child: _buildDesktopSectionContent(section),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 36)),
        ],

        // Bottom padding so content doesn't hide behind mini player
        const SliverToBoxAdapter(child: SizedBox(height: 140)),
      ],
    );
  }

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
              M3EIconButton(
                icon: const Icon(Icons.stream_rounded, size: 20),
                variant: M3EIconButtonVariant.tonal,
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => StreamExtractionTestScreen(
                        onPlayTracks: widget.onPlayTracks,
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(width: 8),
              M3EIconButton(
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
              const SizedBox(width: 8),
              M3EIconButton(
                icon: const Icon(Icons.refresh_rounded, size: 20),
                variant: M3EIconButtonVariant.tonal,
                onPressed: () {
                  setState(() {
                    _loading = true;
                    _error = null;
                  });
                  _loadHome();
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSpotlightCard(dynamic item, {bool isDesktop = false}) {
    final name = _itemName(item);
    final subtitle = _itemSubtitle(item);
    final thumb = _itemThumbnail(item);

    return RepaintBoundary(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => AlbumDetailScreen(
                  item: item,
                  onPlayTracks: widget.onPlayTracks,
                ),
              ),
            );
          },
          borderRadius: BorderRadius.circular(20),
          child: Container(
            padding: EdgeInsets.all(isDesktop ? 20 : 14),
            decoration: BoxDecoration(
              color: _surfaceDark,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _surfaceBorder),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.35),
                  blurRadius: 18,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Row(
              children: [
                // Spotlight Artwork with Expressive Shape
                RepaintBoundary(
                  child: SizedBox(
                    width: isDesktop ? 96 : 76,
                    height: isDesktop ? 96 : 76,
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
                              memCacheWidth: 200,
                              memCacheHeight: 200,
                              placeholder: (_, __) => Container(
                                color: _surfaceBorder,
                                child: const Icon(Icons.music_note_rounded,
                                    color: Colors.white24, size: 28),
                              ),
                              errorWidget: (_, __, ___) => Container(
                                color: _surfaceBorder,
                                child: const Icon(Icons.music_note_rounded,
                                    color: Colors.white24, size: 28),
                              ),
                            )
                          : Container(
                              color: _surfaceBorder,
                              child: const Icon(Icons.music_note_rounded,
                                  color: Colors.white24, size: 28),
                            ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                // Text Details
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: _primary.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          'FEATURED',
                          style: TextStyle(
                            color: _primary,
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: _textPrimary,
                          fontSize: isDesktop ? 18 : 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: _textSecondary,
                          fontSize: isDesktop ? 14 : 12,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                // Action Button with M3E Shape & Gradient
                M3EContainer.circle(
                  width: 44,
                  height: 44,
                  gradient: LinearGradient(
                    colors: [
                      _primary,
                      _primary.withValues(alpha: 0.8),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: _primary.withValues(alpha: 0.4),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                  child: const Center(
                    child: Icon(
                      Icons.play_arrow_rounded,
                      color: Colors.white,
                      size: 26,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

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
          Expanded(
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
        ],
      ),
    );
  }

  Widget _buildSectionContent(HomeSection section) {
    return SizedBox(
      height: 220,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: section.contents.length,
        separatorBuilder: (_, __) => const SizedBox(width: 14),
        itemBuilder: (context, i) {
          final item = section.contents[i];
          return _buildContentTile(item, isDesktop: false);
        },
      ),
    );
  }

  Widget _buildDesktopSectionContent(HomeSection section) {
    return Wrap(
      spacing: 20,
      runSpacing: 24,
      children: section.contents.map((item) {
        return _buildContentTile(item, isDesktop: true);
      }).toList(),
    );
  }

  Widget _buildContentTile(dynamic item, {bool isDesktop = false}) {
    final name = _itemName(item);
    final subtitle = _itemSubtitle(item);
    final thumb = _itemThumbnail(item);
    final cardWidth = isDesktop ? 180.0 : 144.0;
    const Shapes itemShape = Shapes.slanted;

    return RepaintBoundary(
      child: InkWell(
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => AlbumDetailScreen(
                item: item,
                onPlayTracks: widget.onPlayTracks,
              ),
            ),
          );
        },
        borderRadius: BorderRadius.circular(16),
        child: SizedBox(
          width: cardWidth,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Expressive Artwork Card
              Stack(
                children: [
                  AspectRatio(
                    aspectRatio: 1,
                    child: M3EContainer(
                      itemShape,
                      color: _surfaceDark,
                      border: BorderSide(
                        color: _primary.withValues(alpha: 0.2),
                        width: 1.2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.3),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                      clipBehavior: Clip.antiAlias,
                      child: thumb != null
                          ? CachedNetworkImage(
                              imageUrl: thumb,
                              fit: BoxFit.cover,
                              memCacheWidth: 200,
                              memCacheHeight: 200,
                              placeholder: (_, __) => Container(
                                color: _surfaceDark,
                                child: const Center(
                                  child: Icon(Icons.music_note_rounded,
                                      color: Colors.white24, size: 30),
                                ),
                              ),
                              errorWidget: (_, __, ___) => Container(
                                color: _surfaceDark,
                                child: const Center(
                                  child: Icon(Icons.music_note_rounded,
                                      color: Colors.white24, size: 30),
                                ),
                              ),
                            )
                          : const Center(
                              child: Icon(Icons.music_note_rounded,
                                  color: Colors.white24, size: 30),
                            ),
                    ),
                  ),
                  // Floating Play Badge
                  Positioned(
                    right: 8,
                    bottom: 8,
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            _primary,
                            _primary.withValues(alpha: 0.85),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.4),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: const Center(
                        child: Icon(
                          Icons.play_arrow_rounded,
                          color: Colors.white,
                          size: 18,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // Title
              Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: _textPrimary,
                  fontSize: isDesktop ? 14 : 13,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.2,
                ),
              ),
              const SizedBox(height: 2),
              // Subtitle
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: _textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildError() {
    return RepaintBoundary(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Expressive Icon Shape Badge
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
                'No Internet Connection',
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
                'Could not load online home feed. Check your connection or enjoy your offline library tracks.',
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
                    onPressed: () {
                      setState(() {
                        _loading = true;
                        _error = null;
                      });
                      _loadHome();
                    },
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
