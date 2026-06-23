import 'package:cached_network_image/cached_network_image.dart';
import 'package:dart_ytmusic_api/dart_ytmusic_api.dart';
import 'package:flutter/material.dart';
import 'package:loading_indicator_m3e/loading_indicator_m3e.dart';

import 'album_detail_screen.dart';

// ─ Colors (matching the existing app theme) ─
const _bgDark = Color(0xFF101922);
const _surfaceDark = Color(0xFF1C252E);
const _primary = Color(0xFF137fec);

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
    if (hour < 12) return 'Good Morning';
    if (hour < 17) return 'Good Afternoon';
    return 'Good Evening';
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
    // Pick the largest thumbnail
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
              ? Center(
                  child: LoadingIndicatorM3E(
                      color: _primary, containerColor: _primary.withAlpha(50)),
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
    return CustomScrollView(
      physics:
          const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
      slivers: [
        // ── Header ──
        if (!widget.isNested) _buildHeader(isDesktop: false),

        // ── Sections ──
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
    return CustomScrollView(
      physics:
          const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
      slivers: [
        // ── Header ──
        if (!widget.isNested) _buildHeader(isDesktop: true),

        // ── Sections ──
        for (final section in _sections) ...[
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: _buildSectionHeader(section.title, isDesktop: true),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: _buildDesktopSectionContent(section),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 48)),
        ],

        // Bottom padding so content doesn't hide behind mini player
        const SliverToBoxAdapter(child: SizedBox(height: 140)),
      ],
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.wifi_off_rounded,
                size: 56, color: Colors.white.withValues(alpha: 0.3)),
            const SizedBox(height: 16),
            Text('Could not load home',
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.7),
                    fontSize: 16,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text('An error occurred. Check your internet connection.',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.4), fontSize: 13)),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () {
                setState(() {
                  _loading = true;
                  _error = null;
                });
                _loadHome();
              },
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Retry'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24)),
              ),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () {
                if (widget.onGoToDownloads != null) {
                  widget.onGoToDownloads!();
                }
              },
              icon: const Icon(Icons.library_music_rounded, size: 18),
              label: const Text('Downloads & offline songs!'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: BorderSide(color: Colors.white.withValues(alpha: 0.3)),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader({bool isDesktop = false}) {
    return SliverAppBar(
      backgroundColor: _bgDark,
      pinned: true,
      floating: true,
      elevation: 0,
      toolbarHeight: isDesktop ? 100 : 80,
      title: Padding(
        padding: EdgeInsets.only(left: isDesktop ? 24.0 : 8.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('WELCOME BACK',
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.5),
                    fontSize: isDesktop ? 13 : 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.5)),
            const SizedBox(height: 4),
            Text(_greeting(),
                style: TextStyle(
                    color: Colors.white,
                    fontSize: isDesktop ? 34 : 28,
                    fontWeight: FontWeight.bold)),
          ],
        ),
      ),
      actions: [
        Padding(
          padding: EdgeInsets.only(right: isDesktop ? 32.0 : 24.0),
          child: Center(
            child: GestureDetector(
              onTap: () {
                setState(() {
                  _loading = true;
                  _error = null;
                });
                _loadHome();
              },
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                      color: Colors.white.withValues(alpha: 0.15), width: 2),
                  gradient: LinearGradient(
                    colors: [_primary.withValues(alpha: 0.6), _surfaceDark],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: const Icon(Icons.refresh_rounded,
                    color: Colors.white54, size: 22),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSectionHeader(String title, {bool isDesktop = false}) {
    if (title.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding:
          EdgeInsets.fromLTRB(24, isDesktop ? 32 : 24, 24, isDesktop ? 16 : 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: Colors.white,
                    fontSize: isDesktop ? 26 : 20,
                    fontWeight: FontWeight.bold)),
          ),
          /*    Text('VIEW ALL',
              style: TextStyle(
                  color: _primary,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.8)),*/
        ],
      ),
    );
  }

  Widget _buildSectionContent(HomeSection section) {
    return SizedBox(
      height: 210,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 24),
        itemCount: section.contents.length,
        separatorBuilder: (_, __) => const SizedBox(width: 16),
        itemBuilder: (context, i) {
          final item = section.contents[i];
          return _buildContentTile(item, isDesktop: false);
        },
      ),
    );
  }

  Widget _buildDesktopSectionContent(HomeSection section) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24.0),
      child: Wrap(
        spacing: 24,
        runSpacing: 32,
        children: section.contents.map((item) {
          return _buildContentTile(item, isDesktop: true);
        }).toList(),
      ),
    );
  }

  Widget _buildContentTile(dynamic item, {bool isDesktop = false}) {
    final name = _itemName(item);
    final subtitle = _itemSubtitle(item);
    final thumb = _itemThumbnail(item);

    return GestureDetector(
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
      child: SizedBox(
        width: isDesktop ? 200 : 156,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Thumbnail
            AspectRatio(
              aspectRatio: 1,
              child: Container(
                decoration: BoxDecoration(
                  color: _surfaceDark,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.3),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                clipBehavior: Clip.antiAlias,
                child: thumb != null
                    ? CachedNetworkImage(
                        imageUrl: thumb,
                        fit: BoxFit.cover,
                        placeholder: (_, __) => Container(
                          color: _surfaceDark,
                          child: const Center(
                            child: Icon(Icons.music_note,
                                color: Colors.white24, size: 32),
                          ),
                        ),
                        errorWidget: (_, __, ___) => Container(
                          color: _surfaceDark,
                          child: const Center(
                            child: Icon(Icons.music_note,
                                color: Colors.white24, size: 32),
                          ),
                        ),
                      )
                    : const Center(
                        child: Icon(Icons.music_note,
                            color: Colors.white24, size: 32),
                      ),
              ),
            ),
            const SizedBox(height: 10),
            // Title
            Text(name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: Colors.white,
                    fontSize: isDesktop ? 15 : 13,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            // Subtitle
            Text(subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.45),
                    fontSize: isDesktop ? 13 : 11)),
          ],
        ),
      ),
    );
  }
}
