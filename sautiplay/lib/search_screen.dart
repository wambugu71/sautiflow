import 'package:cached_network_image/cached_network_image.dart';
import 'package:dart_ytmusic_api/dart_ytmusic_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_m3shapes_extended/flutter_m3shapes_extended.dart';
import 'package:material_3_expressive/material_3_expressive.dart';

import 'album_detail_screen.dart';
import 'services/app_theme_service.dart';

class SearchScreen extends StatefulWidget {
  final Future<void> Function(List<TrackInfo> tracks, {int initialIndex})?
      onPlayTracks;

  const SearchScreen({super.key, this.onPlayTracks});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final YTMusic _ytMusic = YTMusic();
  final TextEditingController _searchController = TextEditingController();

  Color get _bgDark => context.bgDark;
  Color get _surfaceDark => context.cardDark;
  Color get _primary => context.primaryColor;
  Color get _textPrimary => context.textPrimary;
  Color get _textDark => context.textMuted;
  Color get _outline => context.outlineColor;

  bool _isSearching = false;
  String? _error;
  List<dynamic> _allResults = [];

  // Filter types: 'All', 'Songs', 'Playlists', 'Albums', 'Artists'
  String _selectedFilter = 'All';
  final List<String> _filters = [
    'All',
    'Songs',
    'Playlists',
    'Albums',
    'Artists'
  ];

  @override
  void initState() {
    super.initState();
    _ytMusic.initialize();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _performSearch(String query) async {
    if (query.trim().isEmpty) return;

    setState(() {
      _isSearching = true;
      _error = null;
    });

    try {
      final results = await _ytMusic.search(query);
      if (mounted) {
        setState(() {
          _allResults = results;
          _isSearching = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isSearching = false;
        });
      }
    }
  }

  List<dynamic> _getFilteredResults() {
    if (_selectedFilter == 'All') return _allResults;

    return _allResults.where((item) {
      if (_selectedFilter == 'Songs' && item is SongDetailed) return true;
      if (_selectedFilter == 'Albums' && item is AlbumDetailed) return true;
      if (_selectedFilter == 'Playlists' && item is PlaylistDetailed) return true;
      if (_selectedFilter == 'Artists' && item is ArtistDetailed) return true;
      return false;
    }).toList();
  }

  // ── Extract common fields from the dynamic content items ──
  String _itemName(dynamic item) {
    if (item is SongDetailed) return item.name;
    if (item is AlbumDetailed) return item.name;
    if (item is PlaylistDetailed) return item.name;
    if (item is ArtistDetailed) return item.name;
    return 'Unknown';
  }

  String _itemSubtitle(dynamic item) {
    if (item is SongDetailed) return item.artist.name;
    if (item is AlbumDetailed) return 'Album • ${item.artist.name}';
    if (item is PlaylistDetailed) return 'Playlist • ${item.artist.name}';
    if (item is ArtistDetailed) return 'Artist';
    return '';
  }

  String? _getTrailingText(dynamic item) {
    if (item is SongDetailed && item.duration != null) {
      final d = Duration(seconds: item.duration!);
      final m = d.inMinutes;
      final s = (d.inSeconds % 60).toString().padLeft(2, '0');
      return '$m:$s';
    }
    if (item is AlbumDetailed && item.year != null) {
      return '${item.year}';
    }
    return null;
  }

  String? _itemThumbnail(dynamic item) {
    List<ThumbnailFull>? thumbs;
    if (item is SongDetailed) thumbs = item.thumbnails;
    if (item is AlbumDetailed) thumbs = item.thumbnails;
    if (item is PlaylistDetailed) thumbs = item.thumbnails;
    if (item is ArtistDetailed) thumbs = item.thumbnails;
    if (thumbs == null || thumbs.isEmpty) return null;
    thumbs.sort((a, b) => b.width.compareTo(a.width));
    return thumbs.first.url;
  }

  @override
  Widget build(BuildContext context) {
    final filteredResults = _getFilteredResults();

    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth >= 800;
        final contentMaxWidth = isDesktop ? 1000.0 : double.infinity;

        return Scaffold(
          backgroundColor: _bgDark,
          body: SafeArea(
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: contentMaxWidth),
                child: Column(
                  children: [
                    _buildSearchHeader(isDesktop: isDesktop),
                    _buildFilterChips(isDesktop: isDesktop),
                    Expanded(
                      child: _isSearching
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
                              : _allResults.isEmpty
                                  ? _buildEmptyState(isDesktop: isDesktop)
                                  : _buildResultsList(filteredResults,
                                      isDesktop: isDesktop),
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

  Widget _buildSearchHeader({bool isDesktop = false}) {
    final canPop = Navigator.of(context).canPop();

    return Padding(
      padding: EdgeInsets.fromLTRB(
          isDesktop ? 32 : 16, isDesktop ? 20 : 12, isDesktop ? 32 : 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (canPop)
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: M3EIconButton(
                    icon: const Icon(Icons.arrow_back_rounded, size: 20),
                    variant: M3EIconButtonVariant.tonal,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
              Text(
                'Search',
                style: TextStyle(
                  color: _textPrimary,
                  fontSize: isDesktop ? 34 : 26,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.5,
                ),
              ),
            ],
          ),
          SizedBox(height: isDesktop ? 20 : 14),
          Container(
            height: isDesktop ? 56 : 48,
            decoration: BoxDecoration(
              color: _surfaceDark,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: _outline,
                width: 1,
              ),
            ),
            child: Row(
              children: [
                Padding(
                  padding: EdgeInsets.only(left: 16, right: isDesktop ? 16 : 8),
                  child: Icon(Icons.search_rounded,
                      color: _textDark, size: isDesktop ? 26 : 22),
                ),
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    style: TextStyle(
                        color: _textPrimary, fontSize: isDesktop ? 18 : 16),
                    decoration: InputDecoration(
                      hintText: 'Songs, artists, albums...',
                      hintStyle: TextStyle(
                          color: _textDark.withValues(alpha: 0.6),
                          fontSize: isDesktop ? 18 : 16),
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                    textInputAction: TextInputAction.search,
                    onSubmitted: _performSearch,
                  ),
                ),
                if (_searchController.text.isNotEmpty)
                  IconButton(
                    icon: Icon(Icons.close_rounded,
                        color: _textDark, size: isDesktop ? 24 : 20),
                    onPressed: () {
                      _searchController.clear();
                      setState(() {
                        _allResults.clear();
                      });
                    },
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChips({bool isDesktop = false}) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      padding: EdgeInsets.symmetric(
          horizontal: isDesktop ? 32 : 16, vertical: isDesktop ? 16 : 10),
      child: Row(
        children: _filters.map((filter) {
          final isSelected = _selectedFilter == filter;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: M3EChip(
              label: filter,
              type: M3EChipType.filter,
              selected: isSelected,
              onPressed: () => setState(() => _selectedFilter = filter),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildEmptyState({bool isDesktop = false}) {
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
                  Icons.search_rounded,
                  size: isDesktop ? 44 : 36,
                  color: _primary.withValues(alpha: 0.8),
                ),
              ),
            ),
            SizedBox(height: isDesktop ? 20 : 16),
            Text(
              'Find your favorite music',
              style: TextStyle(
                color: _textDark,
                fontSize: isDesktop ? 18 : 15,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildError() {
    return RepaintBoundary(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              M3EContainer(
                Shapes.c4SidedCookie,
                width: 76,
                height: 76,
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
              const SizedBox(height: 18),
              Text(
                'Search failed',
                style: TextStyle(
                  color: _textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _error ?? 'Unknown error occurred.',
                textAlign: TextAlign.center,
                style: TextStyle(color: _textDark, fontSize: 13),
              ),
              const SizedBox(height: 20),
              M3EButton.icon(
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Retry Search'),
                onPressed: () => _performSearch(_searchController.text),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildResultsList(List<dynamic> results, {bool isDesktop = false}) {
    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 120),
      physics: const BouncingScrollPhysics(),
      itemCount: results.length,
      separatorBuilder: (_, __) =>
          Divider(color: _outline.withValues(alpha: 0.3), height: 1),
      itemBuilder: (context, index) {
        final item = results[index];
        final isTopResult = index == 0 && _selectedFilter == 'All';

        if (isTopResult) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(isDesktop ? 32 : 16,
                    isDesktop ? 24 : 16, isDesktop ? 32 : 16, 8),
                child: Text(
                  'TOP RESULT',
                  style: TextStyle(
                    color: _textDark,
                    fontSize: isDesktop ? 14 : 12,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
              _buildTopResultItem(item, isDesktop: isDesktop),
              if (results.length > 1)
                Padding(
                  padding: EdgeInsets.fromLTRB(isDesktop ? 32 : 16,
                      isDesktop ? 32 : 24, isDesktop ? 32 : 16, 8),
                  child: Text(
                    'SONGS & MORE',
                    style: TextStyle(
                      color: _textDark,
                      fontSize: isDesktop ? 14 : 12,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
            ],
          );
        }

        return _buildStandardResultItem(item, isDesktop: isDesktop);
      },
    );
  }

  Widget _buildTopResultItem(dynamic item, {bool isDesktop = false}) {
    final name = _itemName(item);
    final subtitle = _itemSubtitle(item);
    final thumb = _itemThumbnail(item);
    final isExplicit =
        item is SongDetailed && item.name.toLowerCase().contains('explicit');
    const Shapes itemShape = Shapes.slanted;

    return RepaintBoundary(
      child: InkWell(
        onTap: () => _handleItemTap(item),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: EdgeInsets.symmetric(
              horizontal: isDesktop ? 32 : 16, vertical: isDesktop ? 16 : 12),
          child: Row(
            children: [
              SizedBox(
                width: isDesktop ? 110 : 80,
                height: isDesktop ? 110 : 80,
                child: M3EContainer(
                  item is ArtistDetailed ? Shapes.circle : itemShape,
                  color: _surfaceDark,
                  border: BorderSide(
                    color: _primary.withValues(alpha: 0.25),
                    width: 1.2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.15),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                  clipBehavior: Clip.antiAlias,
                  child: thumb != null
                      ? CachedNetworkImage(
                          imageUrl: thumb,
                          fit: BoxFit.cover,
                          placeholder: (_, __) => Container(
                            color: _surfaceDark,
                            child: Icon(Icons.music_note_rounded,
                                color: _textDark.withValues(alpha: 0.4), size: 30),
                          ),
                          errorWidget: (_, __, ___) => Container(
                            color: _surfaceDark,
                            child: Icon(Icons.music_note_rounded,
                                color: _textDark.withValues(alpha: 0.4), size: 30),
                          ),
                        )
                      : Center(
                          child: Icon(Icons.music_note_rounded,
                              color: _textDark.withValues(alpha: 0.4), size: 30),
                        ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: TextStyle(
                        color: _textPrimary,
                        fontSize: isDesktop ? 20 : 17,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    SizedBox(height: isDesktop ? 8 : 4),
                    Row(
                      children: [
                        if (isExplicit) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 5, vertical: 2),
                            decoration: BoxDecoration(
                              color: _textDark.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              'E',
                              style: TextStyle(
                                  color: _textPrimary,
                                  fontSize: isDesktop ? 12 : 10,
                                  fontWeight: FontWeight.bold),
                            ),
                          ),
                          const SizedBox(width: 8),
                        ],
                        Expanded(
                          child: Text(
                            subtitle,
                            style: TextStyle(
                              color: _textDark,
                              fontSize: isDesktop ? 15 : 13,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (_getTrailingText(item) != null)
                Padding(
                  padding: const EdgeInsets.only(right: 8.0),
                  child: Text(
                    _getTrailingText(item)!,
                    style: TextStyle(
                      color: _textDark,
                      fontSize: isDesktop ? 14 : 12,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStandardResultItem(dynamic item, {bool isDesktop = false}) {
    final name = _itemName(item);
    final subtitle = _itemSubtitle(item);
    final thumb = _itemThumbnail(item);
    final isArtist = item is ArtistDetailed;

    return RepaintBoundary(
      child: InkWell(
        onTap: () => _handleItemTap(item),
        child: Padding(
          padding: EdgeInsets.symmetric(
              horizontal: isDesktop ? 32 : 16, vertical: isDesktop ? 14 : 10),
          child: Row(
            children: [
              SizedBox(
                width: isDesktop ? 60 : 52,
                height: isDesktop ? 60 : 52,
                child: M3EContainer(
                  isArtist ? Shapes.circle : Shapes.slanted,
                  color: _surfaceDark,
                  border: BorderSide(
                    color: _outline.withValues(alpha: 0.3),
                    width: 1,
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: thumb != null
                      ? CachedNetworkImage(
                          imageUrl: thumb,
                          fit: BoxFit.cover,
                          placeholder: (_, __) => Container(
                            color: _surfaceDark,
                            child: Icon(
                              isArtist ? Icons.person_rounded : Icons.music_note_rounded,
                              color: _textDark.withValues(alpha: 0.4),
                              size: 22,
                            ),
                          ),
                          errorWidget: (_, __, ___) => Container(
                            color: _surfaceDark,
                            child: Icon(
                              isArtist ? Icons.person_rounded : Icons.music_note_rounded,
                              color: _textDark.withValues(alpha: 0.4),
                              size: 22,
                            ),
                          ),
                        )
                      : Center(
                          child: Icon(
                            isArtist ? Icons.person_rounded : Icons.music_note_rounded,
                            color: _textDark.withValues(alpha: 0.4),
                            size: 22,
                          ),
                        ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: TextStyle(
                        color: _textPrimary,
                        fontSize: isDesktop ? 17 : 15,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: _textDark,
                        fontSize: isDesktop ? 14 : 12,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (_getTrailingText(item) != null)
                Padding(
                  padding: const EdgeInsets.only(right: 8.0),
                  child: Text(
                    _getTrailingText(item)!,
                    style: TextStyle(
                      color: _textDark,
                      fontSize: isDesktop ? 14 : 12,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _handleItemTap(dynamic item) {
    if (item is SongDetailed) {
      final track = TrackInfo(
        videoId: item.videoId,
        title: item.name,
        artist: item.artist.name,
        durationSeconds: item.duration is int
            ? item.duration
            : _parseDuration(item.duration?.toString()),
        thumbnailUrl: _itemThumbnail(item),
      );
      if (widget.onPlayTracks != null) {
        widget.onPlayTracks!([track], initialIndex: 0);
      }
    } else {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => AlbumDetailScreen(
            item: item,
            onPlayTracks: widget.onPlayTracks,
          ),
        ),
      );
    }
  }

  int _parseDuration(String? durationStr) {
    if (durationStr == null || durationStr.isEmpty) return 0;
    final parts = durationStr.split(':');
    if (parts.length == 2) {
      return (int.tryParse(parts[0]) ?? 0) * 60 + (int.tryParse(parts[1]) ?? 0);
    } else if (parts.length == 3) {
      return (int.tryParse(parts[0]) ?? 0) * 3600 +
          (int.tryParse(parts[1]) ?? 0) * 60 +
          (int.tryParse(parts[2]) ?? 0);
    }
    return 0;
  }
}
