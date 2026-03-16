import 'package:cached_network_image/cached_network_image.dart';
import 'package:dart_ytmusic_api/dart_ytmusic_api.dart';
import 'package:flutter/material.dart';
import 'package:loading_indicator_m3e/loading_indicator_m3e.dart';

import 'album_detail_screen.dart';

// ─ Colors (matching the existing app theme) ─
const _bgDark = Color(0xFF101922);
const _surfaceDark = Color(0xFF1C252E);
const _primary = Color(0xFF137fec);

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
      if (_selectedFilter == 'Songs') return item is SongDetailed;
      if (_selectedFilter == 'Playlists') return item is PlaylistDetailed;
      if (_selectedFilter == 'Albums') return item is AlbumDetailed;
      if (_selectedFilter == 'Artists') return item is ArtistDetailed;
      return true;
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
    // Pick the largest thumbnail
    thumbs.sort((a, b) => b.width.compareTo(a.width));
    return thumbs.first.url;
  }

  bool _isHiRes(dynamic item) {
    // Just a UI mock toggle for songs
    return false; //item is SongDetailed && item.videoId.hashCode % 2 == 0;
  }

  bool _isLossless(dynamic item) {
    // Just a UI mock toggle for songs
    return false; //item is SongDetailed && item.videoId.hashCode % 3 == 0;
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
                          ? Center(
                              child: LoadingIndicatorM3E(
                                  color: _primary,
                                  containerColor: _primary.withAlpha(50)),
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
    return Padding(
      padding: EdgeInsets.fromLTRB(
          isDesktop ? 32 : 16, isDesktop ? 32 : 16, isDesktop ? 32 : 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Search',
            style: TextStyle(
              color: Colors.white,
              fontSize: isDesktop ? 36 : 28,
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: isDesktop ? 24 : 16),
          Container(
            height: isDesktop ? 56 : 48,
            decoration: BoxDecoration(
              color: _surfaceDark,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Colors.white.withOpacity(0.1),
                width: 1,
              ),
            ),
            child: Row(
              children: [
                Padding(
                  padding: EdgeInsets.only(left: 16, right: isDesktop ? 16 : 8),
                  child: Icon(Icons.search,
                      color: Colors.white54, size: isDesktop ? 28 : 24),
                ),
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    style: TextStyle(
                        color: Colors.white, fontSize: isDesktop ? 18 : 16),
                    decoration: InputDecoration(
                      hintText: 'Songs, artists, albums...',
                      hintStyle: TextStyle(
                          color: Colors.white.withOpacity(0.4),
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
                    icon: Icon(Icons.close,
                        color: Colors.white54, size: isDesktop ? 24 : 20),
                    onPressed: () {
                      _searchController.clear();
                      setState(() {
                        _allResults.clear();
                      });
                    },
                  )
                else
                  SizedBox.shrink()
                /*IconButton(
                    icon:
                        const Icon(Icons.mic, color: Colors.white54, size: 20),
                    onPressed: () {},
                  ),*/
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
          horizontal: isDesktop ? 32 : 16, vertical: isDesktop ? 20 : 12),
      child: Row(
        children: _filters.map((filter) {
          final isSelected = _selectedFilter == filter;
          return Padding(
            padding: const EdgeInsets.only(right: 12),
            child: InkWell(
              onTap: () => setState(() => _selectedFilter = filter),
              borderRadius: BorderRadius.circular(24),
              child: Container(
                padding: EdgeInsets.symmetric(
                    horizontal: isDesktop ? 20 : 16,
                    vertical: isDesktop ? 12 : 8),
                decoration: BoxDecoration(
                  color: isSelected ? _primary : _surfaceDark,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color:
                        isSelected ? _primary : Colors.white.withOpacity(0.1),
                  ),
                ),
                child: Text(
                  filter,
                  style: TextStyle(
                    color: isSelected ? Colors.white : Colors.white70,
                    fontWeight: FontWeight.w500,
                    fontSize: isDesktop ? 15 : 14,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildEmptyState({bool isDesktop = false}) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.search,
              size: isDesktop ? 96 : 64, color: Colors.white.withOpacity(0.2)),
          SizedBox(height: isDesktop ? 24 : 16),
          Text(
            'Find your favorite music',
            style: TextStyle(
              color: Colors.white.withOpacity(0.5),
              fontSize: isDesktop ? 20 : 16,
            ),
          ),
        ],
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
                size: 48, color: Colors.red.withOpacity(0.8)),
            const SizedBox(height: 16),
            Text(
              'Search failed',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              _error ?? 'Unknown error',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white.withOpacity(0.6)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResultsList(List<dynamic> results, {bool isDesktop = false}) {
    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 120), // Space for mini player
      physics: const BouncingScrollPhysics(),
      itemCount: results.length,
      separatorBuilder: (_, __) =>
          Divider(color: Colors.white.withOpacity(0.05), height: 1),
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
                    color: Colors.white.withOpacity(0.5),
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
                      color: Colors.white.withOpacity(0.5),
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

    return InkWell(
      onTap: () => _handleItemTap(item),
      child: Padding(
        padding: EdgeInsets.symmetric(
            horizontal: isDesktop ? 32 : 16, vertical: isDesktop ? 16 : 12),
        child: Row(
          children: [
            // Top result has a larger thumbnail
            Container(
              width: isDesktop ? 120 : 80,
              height: isDesktop ? 120 : 80,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: _surfaceDark,
                image: thumb != null
                    ? DecorationImage(
                        image: CachedNetworkImageProvider(thumb),
                        fit: BoxFit.cover,
                      )
                    : null,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.3),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: thumb == null
                  ? const Center(
                      child: Icon(Icons.music_note,
                          color: Colors.white24, size: 32))
                  : null,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: isDesktop ? 22 : 18,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  SizedBox(height: isDesktop ? 10 : 6),
                  Row(
                    children: [
                      if (isExplicit) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 4, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'E',
                            style: TextStyle(
                                color: Colors.white,
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
                            color: Colors.white.withOpacity(0.6),
                            fontSize: isDesktop ? 16 : 14,
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
                    color: Colors.white.withOpacity(0.5),
                    fontSize: isDesktop ? 14 : 12,
                  ),
                ),
              ),
            /*  IconButton(
              icon: const Icon(Icons.more_vert, color: Colors.white54),
              onPressed: () {},
            ),*/
          ],
        ),
      ),
    );
  }

  Widget _buildStandardResultItem(dynamic item, {bool isDesktop = false}) {
    final name = _itemName(item);
    final subtitle = _itemSubtitle(item);
    final thumb = _itemThumbnail(item);
    final isLossless = false; //_isLossless(item);
    final isHiRes = false; //_isHiRes(item);

    return InkWell(
      onTap: () => _handleItemTap(item),
      child: Padding(
        padding: EdgeInsets.symmetric(
            horizontal: isDesktop ? 32 : 16, vertical: isDesktop ? 16 : 12),
        child: Row(
          children: [
            Container(
              width: isDesktop ? 64 : 56,
              height: isDesktop ? 64 : 56,
              decoration: BoxDecoration(
                borderRadius: item is ArtistDetailed
                    ? BorderRadius.circular(isDesktop ? 32 : 28)
                    : BorderRadius.circular(8),
                color: _surfaceDark,
                image: thumb != null
                    ? DecorationImage(
                        image: CachedNetworkImageProvider(thumb),
                        fit: BoxFit.cover,
                      )
                    : null,
              ),
              child: thumb == null
                  ? Center(
                      child: Icon(
                        item is ArtistDetailed
                            ? Icons.person
                            : Icons.music_note,
                        color: Colors.white24,
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: isDesktop ? 18 : 16,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.6),
                      fontSize: isDesktop ? 15 : 14,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (isHiRes && !isLossless)
              Container(
                margin: const EdgeInsets.only(right: 8),
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                decoration: BoxDecoration(
                  border: Border.all(color: _primary),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'Hi-Res',
                  style: TextStyle(
                      color: _primary,
                      fontSize: isDesktop ? 12 : 10,
                      fontWeight: FontWeight.bold),
                ),
              ),
            if (isLossless)
              Container(
                margin: const EdgeInsets.only(right: 8),
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.white54),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'Lossless',
                  style: TextStyle(
                      color: Colors.white54,
                      fontSize: isDesktop ? 12 : 10,
                      fontWeight: FontWeight.bold),
                ),
              ),
            if (_getTrailingText(item) != null)
              Padding(
                padding: const EdgeInsets.only(right: 8.0),
                child: Text(
                  _getTrailingText(item)!,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.5),
                    fontSize: isDesktop ? 14 : 12,
                  ),
                ),
              ),
            /* IconButton(
              icon: const Icon(Icons.more_vert, color: Colors.white54),
              onPressed: () {},
            ),*/
          ],
        ),
      ),
    );
  }

  void _handleItemTap(dynamic item) {
    if (item is SongDetailed) {
      // Just play the selected song immediately
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
      // It's an enum or Playlist/Album, jump to detail screen
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
