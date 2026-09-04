import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:dart_ytmusic_api/dart_ytmusic_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_m3shapes_extended/flutter_m3shapes_extended.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_3_expressive/components/floating_action_buttons/enums/m3e_fab.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  final ScrollController _scrollController = ScrollController();

  Color get _bgDark => context.bgDark;
  Color get _surfaceDark => context.cardDark;
  Color get _primary => context.primaryColor;
  Color get _textPrimary => context.textPrimary;
  Color get _textDark => context.textMuted;
  Color get _outline => context.outlineColor;

  bool _isSearching = false;
  String? _error;
  List<dynamic> _allResults = [];
  String _lastSearchQuery = '';

  // Reactive typing state
  List<String> _suggestions = [];
  Timer? _suggestDebounce;
  Timer? _searchDebounce;
  int _suggestionToken = 0;
  int _searchToken = 0;

  // Recent searches
  static const String _recentKey = 'sautiplay_recent_searches';
  List<String> _recentSearches = [];

  // Scroll-to-top FAB
  bool _showScrollTop = false;

  // Filter types: 'All', 'Songs', 'Playlists', 'Albums', 'Artists'
  String _selectedFilter = 'All';
  final List<String> _filters = [
    'All',
    'Songs',
    'Playlists',
    'Albums',
    'Artists'
  ];

  /// Mixtapes / long mixes to hide: any song/video at or above 10 minutes.
  static const int _maxDurationSeconds = 600;

  @override
  void initState() {
    super.initState();
    _ytMusic.initialize();
    _loadRecentSearches();
    _scrollController.addListener(_onScroll);
    _searchController.addListener(_onQueryChanged);
  }

  @override
  void dispose() {
    _suggestDebounce?.cancel();
    _searchDebounce?.cancel();
    _searchController.removeListener(_onQueryChanged);
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    final shouldShow =
        _scrollController.hasClients && _scrollController.offset > 600;
    if (shouldShow != _showScrollTop) {
      setState(() => _showScrollTop = shouldShow);
    }
  }

  // ── Reactive search-as-you-type ────────────────────────────────────────────

  void _onQueryChanged() {
    if (!mounted) return;
    setState(() {}); // refresh clear-button / body state
    final query = _searchController.text.trim();

    _suggestDebounce?.cancel();
    _searchDebounce?.cancel();

    if (query.isEmpty) {
      setState(() => _suggestions = []);
      return;
    }

    // Fast lane: live YT Music autocomplete
    _suggestDebounce = Timer(
      const Duration(milliseconds: 250),
      () => _loadSuggestions(query),
    );

    // Slow lane: full auto-search once typing settles
    _searchDebounce = Timer(
      const Duration(milliseconds: 650),
      () => _performSearch(query),
    );
  }

  Future<void> _loadSuggestions(String query) async {
    final token = ++_suggestionToken;
    try {
      final suggestions = await _ytMusic.getSearchSuggestions(query);
      if (!mounted ||
          token != _suggestionToken ||
          query != _searchController.text.trim()) {
        return;
      }
      setState(() => _suggestions = suggestions);
    } catch (_) {
      // Suggestions are best-effort; never surface errors here.
    }
  }

  Future<void> _performSearch(String query) async {
    query = query.trim();
    if (query.isEmpty) return;

    final token = ++_searchToken;
    setState(() {
      _isSearching = true;
      _error = null;
    });

    try {
      final results = await _ytMusic.search(query);
      if (!mounted ||
          token != _searchToken ||
          query != _searchController.text.trim()) {
        return; // stale response – a newer keystroke superseded it
      }
      final filtered = _filterOutLongMixes(results);
      setState(() {
        _allResults = filtered;
        _lastSearchQuery = query;
        _isSearching = false;
      });
      await _saveRecentSearch(query);
    } catch (e) {
      if (!mounted || token != _searchToken) return;
      String msg = 'Search failed. Please try again.';
      final errStr = e.toString().toLowerCase();
      if (errStr.contains('socketexception') ||
          errStr.contains('timeout') ||
          errStr.contains('failed host lookup') ||
          errStr.contains('handshakeexception')) {
        msg = 'Offline or connection error. Please check your internet.';
      }
      setState(() {
        _error = msg;
        _isSearching = false;
      });
    }
  }

  /// Hide long mixes / mixtapes (>= 10 min) from songs & videos.
  List<dynamic> _filterOutLongMixes(List<dynamic> results) {
    bool isLongMix(dynamic item) {
      int? seconds;
      if (item is SongDetailed) seconds = item.duration;
      if (item is VideoDetailed) seconds = item.duration;
      return seconds != null && seconds >= _maxDurationSeconds;
    }

    return results.where((r) => !isLongMix(r)).toList();
  }

  // ── Recent searches ────────────────────────────────────────────────────────

  Future<void> _loadRecentSearches() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (mounted) {
        setState(() => _recentSearches = prefs.getStringList(_recentKey) ?? []);
      }
    } catch (_) {}
  }

  Future<void> _saveRecentSearch(String query) async {
    setState(() {
      _recentSearches
        ..removeWhere((e) => e.toLowerCase() == query.toLowerCase())
        ..insert(0, query);
      if (_recentSearches.length > 8) {
        _recentSearches = _recentSearches.sublist(0, 8);
      }
    });
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_recentKey, _recentSearches);
    } catch (_) {}
  }

  Future<void> _clearRecentSearches() async {
    setState(() => _recentSearches = []);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_recentKey, []);
    } catch (_) {}
  }

  void _runSearchFromChip(String query) {
    _searchController.text = query;
    _searchController.selection = TextSelection.fromPosition(
      TextPosition(offset: query.length),
    );
    _suggestDebounce?.cancel();
    _searchDebounce?.cancel();
    _performSearch(query);
  }

  // ── Filtering & extraction ─────────────────────────────────────────────────

  List<dynamic> _getFilteredResults() {
    if (_selectedFilter == 'All') return _allResults;

    return _allResults.where((item) {
      if (_selectedFilter == 'Songs' && item is SongDetailed) return true;
      if (_selectedFilter == 'Albums' && item is AlbumDetailed) return true;
      if (_selectedFilter == 'Playlists' && item is PlaylistDetailed) {
        return true;
      }
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
    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth >= 800;
        final contentMaxWidth = isDesktop ? 1000.0 : double.infinity;

        return Scaffold(
          backgroundColor: _bgDark,
          floatingActionButton: _showScrollTop
              ? Padding(
                  padding: const EdgeInsets.only(bottom: 96),
                  child: M3EFab(
                    icon: const Icon(Icons.keyboard_arrow_down),
                    size: M3EFabSize.small,
                    color: M3EFabColor.primary,
                    onPressed: () => _scrollController.animateTo(
                      0,
                      duration: const Duration(milliseconds: 450),
                      curve: Curves.easeOutCubic,
                    ),
                  ),
                )
              : null,
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
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 220),
                        switchInCurve: Curves.easeOut,
                        switchOutCurve: Curves.easeIn,
                        child: KeyedSubtree(
                          key: ValueKey(_bodyStateKey),
                          child: _buildBody(isDesktop: isDesktop),
                        ),
                      ),
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

  String get _bodyStateKey {
    if (_isSearching) return 'loading';
    if (_error != null) return 'error';
    final query = _searchController.text.trim();
    if (query.isEmpty) return 'empty';
    if (_lastSearchQuery == query) return 'results$_selectedFilter';
    if (_suggestions.isNotEmpty) return 'suggestions';
    return 'typing';
  }

  Widget _buildBody({bool isDesktop = false}) {
    if (_isSearching) {
      return RepaintBoundary(
        child: Center(
          child: M3EProgressIndicator.circularWavy(
            color: _primary,
            trackColor: _primary.withValues(alpha: 0.15),
          ),
        ),
      );
    }

    if (_error != null) return _buildError();

    final query = _searchController.text.trim();
    if (query.isEmpty) {
      return _buildIdleState(isDesktop: isDesktop);
    }

    // Fresh results for exactly what was typed → show them
    if (_lastSearchQuery == query && _allResults.isNotEmpty) {
      final filteredResults = _getFilteredResults();
      return _buildResultsList(filteredResults, isDesktop: isDesktop);
    }

    // Still typing → live suggestions
    if (_suggestions.isNotEmpty) {
      return _buildSuggestionsPanel(isDesktop: isDesktop);
    }

    return RepaintBoundary(
      child: Center(
        child: Text(
          'Keep typing to see suggestions…',
          style: TextStyle(color: _textDark, fontSize: isDesktop ? 15 : 13),
        ),
      ),
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
                    icon: const Icon(Icons.keyboard_arrow_down, size: 20),
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
                    autofocus: true,
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
                    onSubmitted: (q) {
                      _suggestDebounce?.cancel();
                      _searchDebounce?.cancel();
                      _performSearch(q);
                    },
                  ),
                ),
                if (_searchController.text.isNotEmpty)
                  IconButton(
                    icon: Icon(Icons.close_rounded,
                        color: _textDark, size: isDesktop ? 24 : 20),
                    onPressed: () {
                      _suggestDebounce?.cancel();
                      _searchDebounce?.cancel();
                      _searchController.clear();
                      setState(() {
                        _allResults = [];
                        _lastSearchQuery = '';
                        _error = null;
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

  // ── Idle / empty state with recent searches ────────────────────────────────

  Widget _buildIdleState({bool isDesktop = false}) {
    final hasRecents = _recentSearches.isNotEmpty;
    return ListView(
      controller: _scrollController,
      physics: const BouncingScrollPhysics(),
      padding: EdgeInsets.symmetric(horizontal: isDesktop ? 32 : 16),
      children: [
        SizedBox(height: isDesktop ? 40 : 24),
        Center(
          child: Column(
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
        if (hasRecents) ...[
          SizedBox(height: isDesktop ? 40 : 28),
          Row(
            children: [
              Icon(Icons.history_rounded, color: _textDark, size: 18),
              const SizedBox(width: 8),
              Text(
                'RECENT SEARCHES',
                style: TextStyle(
                  color: _textDark,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: _clearRecentSearches,
                child: Text(
                  'Clear',
                  style: TextStyle(
                    color: _primary,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _recentSearches
                .map((q) => M3EChip(
                      label: q,
                      leading: Icon(Icons.history_rounded,
                          size: 16, color: _textDark),
                      onPressed: () => _runSearchFromChip(q),
                    ))
                .toList(),
          ),
        ],
        const SizedBox(height: 140),
      ],
    );
  }

  // ── Live suggestions while typing ──────────────────────────────────────────

  Widget _buildSuggestionsPanel({bool isDesktop = false}) {
    return ListView.builder(
      controller: _scrollController,
      physics: const BouncingScrollPhysics(),
      padding:
          EdgeInsets.fromLTRB(isDesktop ? 32 : 12, 4, isDesktop ? 32 : 12, 120),
      itemCount: _suggestions.length,
      itemBuilder: (context, index) {
        final suggestion = _suggestions[index];
        final isRecent = _recentSearches
            .any((r) => r.toLowerCase() == suggestion.toLowerCase());
        return RepaintBoundary(
          child: InkWell(
            onTap: () => _runSearchFromChip(suggestion),
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 11),
              child: Row(
                children: [
                  Icon(
                    isRecent ? Icons.history_rounded : Icons.north_west_rounded,
                    color: _textDark.withValues(alpha: 0.7),
                    size: isDesktop ? 22 : 19,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      suggestion,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: _textPrimary,
                        fontSize: isDesktop ? 17 : 15,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  Icon(Icons.search_rounded,
                      color: _textDark.withValues(alpha: 0.4),
                      size: isDesktop ? 20 : 17),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // ── Error state ─────────────────────────────────────────────────────────────

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

  // ── Results ─────────────────────────────────────────────────────────────────

  Widget _buildSectionHeader(String title, {bool isDesktop = false}) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          isDesktop ? 32 : 16, isDesktop ? 26 : 20, isDesktop ? 32 : 16, 6),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 18,
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
          Text(
            title,
            style: TextStyle(
              color: _textPrimary,
              fontSize: isDesktop ? 20 : 16,
              fontWeight: FontWeight.bold,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Container(
              height: 1.5,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    _textDark.withValues(alpha: 0.25),
                    _textDark.withValues(alpha: 0.0),
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

  Widget _buildResultsList(List<dynamic> results, {bool isDesktop = false}) {
    if (results.isEmpty) {
      return RepaintBoundary(
        child: Center(
          child: Text(
            _selectedFilter == 'All'
                ? 'No results found.'
                : 'No ${_selectedFilter.toLowerCase()} in these results.',
            style: TextStyle(color: _textDark, fontSize: isDesktop ? 15 : 13),
          ),
        ),
      );
    }

    // Specific filter tab → plain card list
    if (_selectedFilter != 'All') {
      return ListView.builder(
        controller: _scrollController,
        physics: const BouncingScrollPhysics(),
        padding: EdgeInsets.symmetric(
          horizontal: isDesktop ? 32 : 16,
          vertical: 8,
        ).copyWith(bottom: 120),
        itemCount: results.length,
        itemBuilder: (context, index) => _buildStandardResultItem(
          results[index],
          isDesktop: isDesktop,
          isFirst: index == 0,
          isLast: index == results.length - 1,
        ),
      );
    }

    // 'All' → grouped expressive sections
    final top = results.first;
    final rest = results.skip(1).toList();
    final songs = rest.whereType<SongDetailed>().toList();
    final artists = rest.whereType<ArtistDetailed>().toList();
    final albums = rest.whereType<AlbumDetailed>().toList();
    final playlists = rest.whereType<PlaylistDetailed>().toList();

    Widget sectionItem(List<dynamic> items, int index) {
      final shown = items.length > 6 ? 6 : items.length;
      return Padding(
        padding: EdgeInsets.symmetric(horizontal: isDesktop ? 32 : 16),
        child: _buildStandardResultItem(
          items[index],
          isDesktop: isDesktop,
          isFirst: index == 0,
          isLast: index == shown - 1,
        ),
      );
    }

    return ListView(
      controller: _scrollController,
      physics: const BouncingScrollPhysics(),
      padding: EdgeInsets.only(top: 8, bottom: 120),
      children: [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: isDesktop ? 32 : 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSectionHeader('TOP RESULT', isDesktop: isDesktop),
              _buildTopResultItem(top, isDesktop: isDesktop),
            ],
          ),
        ),
        if (songs.isNotEmpty) ...[
          _buildSectionHeader('SONGS', isDesktop: isDesktop),
          for (var i = 0; i < songs.length && i < 6; i++) sectionItem(songs, i),
        ],
        if (artists.isNotEmpty) ...[
          _buildSectionHeader('ARTISTS', isDesktop: isDesktop),
          for (var i = 0; i < artists.length && i < 6; i++)
            sectionItem(artists, i),
        ],
        if (albums.isNotEmpty) ...[
          _buildSectionHeader('ALBUMS', isDesktop: isDesktop),
          for (var i = 0; i < albums.length && i < 6; i++)
            sectionItem(albums, i),
        ],
        if (playlists.isNotEmpty) ...[
          _buildSectionHeader('PLAYLISTS', isDesktop: isDesktop),
          for (var i = 0; i < playlists.length && i < 6; i++)
            sectionItem(playlists, i),
        ],
      ],
    );
  }

  Widget _buildTopResultItem(dynamic item, {bool isDesktop = false}) {
    final name = _itemName(item);
    final subtitle = _itemSubtitle(item);
    final thumb = _itemThumbnail(item);

    return RepaintBoundary(
      child: M3ECard(
        variant: M3ECardVariant.elevated,
        onPressed: () => _handleItemTap(item),
        color: _surfaceDark,
        borderRadius: BorderRadius.circular(20),
        padding: EdgeInsets.all(isDesktop ? 18 : 14),
        child: Row(
          children: [
            SizedBox(
              width: isDesktop ? 110 : 80,
              height: isDesktop ? 110 : 80,
              child: M3EContainer(
                item is ArtistDetailed ? Shapes.circle : Shapes.slanted,
                color: _surfaceDark,
                border: BorderSide(
                  color: _primary.withValues(alpha: 0.25),
                  width: 1.2,
                ),
                clipBehavior: Clip.antiAlias,
                child: thumb != null
                    ? CachedNetworkImage(
                        imageUrl: thumb,
                        fit: BoxFit.cover,
                        memCacheWidth: 200,
                        memCacheHeight: 200,
                        placeholder: (_, __) => Container(
                          color: _surfaceDark,
                          child: Icon(Icons.music_note_rounded,
                              color: _textDark.withValues(alpha: 0.4),
                              size: 30),
                        ),
                        errorWidget: (_, __, ___) => Container(
                          color: _surfaceDark,
                          child: Icon(Icons.music_note_rounded,
                              color: _textDark.withValues(alpha: 0.4),
                              size: 30),
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
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  SizedBox(height: isDesktop ? 8 : 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: _textDark,
                      fontSize: isDesktop ? 15 : 13,
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
    );
  }

  /// Result row styled exactly like the Library tracks list: connected
  /// corner-rounded cards (20dp at group ends, 6dp between) on surface
  /// fill with a hairline border.
  Widget _buildStandardResultItem(
    dynamic item, {
    bool isDesktop = false,
    bool isFirst = false,
    bool isLast = false,
  }) {
    final name = _itemName(item);
    final subtitle = _itemSubtitle(item);
    final thumb = _itemThumbnail(item);
    final isArtist = item is ArtistDetailed;
    final thumbSize = isDesktop ? 60.0 : 48.0;

    final borderRadius = BorderRadius.only(
      topLeft: Radius.circular(isFirst ? 20 : 6),
      topRight: Radius.circular(isFirst ? 20 : 6),
      bottomLeft: Radius.circular(isLast ? 20 : 6),
      bottomRight: Radius.circular(isLast ? 20 : 6),
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
            onTap: () => _handleItemTap(item),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                children: [
                  SizedBox(
                    width: thumbSize,
                    height: thumbSize,
                    child: M3EContainer(
                      isArtist ? Shapes.circle : Shapes.pill,
                      color: _surfaceDark,
                      clipBehavior: Clip.antiAlias,
                      child: thumb != null
                          ? CachedNetworkImage(
                              imageUrl: thumb,
                              fit: BoxFit.cover,
                              memCacheWidth: 160,
                              memCacheHeight: 160,
                              placeholder: (_, __) => Container(
                                color: _surfaceDark,
                                child: Icon(
                                  isArtist
                                      ? Icons.person_rounded
                                      : Icons.music_note_rounded,
                                  color: _textDark.withValues(alpha: 0.4),
                                  size: 22,
                                ),
                              ),
                              errorWidget: (_, __, ___) => Container(
                                color: _surfaceDark,
                                child: Icon(
                                  isArtist
                                      ? Icons.person_rounded
                                      : Icons.music_note_rounded,
                                  color: _textDark.withValues(alpha: 0.4),
                                  size: 22,
                                ),
                              ),
                            )
                          : Center(
                              child: Icon(
                                isArtist
                                    ? Icons.person_rounded
                                    : Icons.music_note_rounded,
                                color: _textDark.withValues(alpha: 0.4),
                                size: 22,
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          name,
                          style: TextStyle(
                            fontSize: isDesktop ? 15 : 13.5,
                            fontWeight: FontWeight.w600,
                            color: _textPrimary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          style: TextStyle(
                            fontSize: isDesktop ? 13 : 11.5,
                            color: _textDark,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (_getTrailingText(item) != null)
                    Text(
                      _getTrailingText(item)!,
                      style: TextStyle(
                        color: _textDark,
                        fontSize: isDesktop ? 13 : 11.5,
                      ),
                    )
                  else
                    Icon(
                      Icons.chevron_right_rounded,
                      color: const Color(0xFF64748B),
                      size: isDesktop ? 20 : 18,
                    ),
                ],
              ),
            ),
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
        Navigator.of(context).popUntil((route) => route.isFirst);
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
