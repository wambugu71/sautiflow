import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:dart_ytmusic_api/dart_ytmusic_api.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_m3shapes_extended/flutter_m3shapes_extended.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_3_expressive/components/floating_action_buttons/enums/m3e_fab.dart';
import 'package:shimmer/shimmer.dart';

import 'album_detail_screen.dart';
import 'artist_profile_screen.dart';
import 'database/preferences_store.dart';
import 'l10n/app_strings.dart';
import 'services/app_theme_service.dart';

// ══════════════════════════════════════════════════════════════════════════════
// REACTIVE SEARCH STATE MODEL
// ══════════════════════════════════════════════════════════════════════════════

sealed class SearchScreenState {
  const SearchScreenState();
}

class SearchStateIdle extends SearchScreenState {
  final List<String> recentSearches;
  const SearchStateIdle({this.recentSearches = const []});
}

class SearchStateSuggestions extends SearchScreenState {
  final String query;
  final List<String> suggestions;
  final List<String> recentSearches;
  const SearchStateSuggestions({
    required this.query,
    required this.suggestions,
    this.recentSearches = const [],
  });
}

class SearchStateLoading extends SearchScreenState {
  final String query;
  final String selectedFilter;
  const SearchStateLoading({
    required this.query,
    this.selectedFilter = 'All',
  });
}

class SearchStateSuccess extends SearchScreenState {
  final String query;
  final List<dynamic> rawResults;
  final String selectedFilter;

  const SearchStateSuccess({
    required this.query,
    required this.rawResults,
    this.selectedFilter = 'All',
  });

  List<dynamic> get filteredResults {
    if (selectedFilter == 'All') return rawResults;
    return rawResults.where((item) {
      if (selectedFilter == 'Songs') {
        return item is SongDetailed || item is VideoDetailed;
      }
      if (selectedFilter == 'Albums') {
        return item is AlbumDetailed;
      }
      if (selectedFilter == 'Playlists') {
        return item is PlaylistDetailed;
      }
      if (selectedFilter == 'Artists') {
        return item is ArtistDetailed || item is ArtistDetailedSearchResult;
      }
      return false;
    }).toList();
  }

  SearchStateSuccess copyWithFilter(String newFilter) {
    return SearchStateSuccess(
      query: query,
      rawResults: rawResults,
      selectedFilter: newFilter,
    );
  }
}

class SearchStateError extends SearchScreenState {
  final String query;
  final String message;
  const SearchStateError({required this.query, required this.message});
}

// ══════════════════════════════════════════════════════════════════════════════
// REACTIVE SEARCH CONTROLLER
// ══════════════════════════════════════════════════════════════════════════════

class SearchReactiveController extends ValueNotifier<SearchScreenState> {
  final YTMusic _ytMusic = YTMusic();
  Timer? _suggestDebounce;
  Timer? _searchDebounce;
  int _activeRequestId = 0;

  static const String _recentKey = 'sautiplay_recent_searches';
  static const int _maxDurationSeconds = 600;

  String _selectedFilter = 'All';
  String get selectedFilter => _selectedFilter;

  List<String> _recentSearches = [];
  List<String> get recentSearches => List.unmodifiable(_recentSearches);

  SearchReactiveController() : super(const SearchStateIdle());

  Future<void> init() async {
    final savedFilter =
        PreferencesStore.instance.getString('search_selected_filter');
    if (savedFilter != null &&
        ['All', 'Songs', 'Playlists', 'Albums', 'Artists']
            .contains(savedFilter)) {
      _selectedFilter = savedFilter;
    }
    await _ytMusic.initialize();
    await _loadRecentSearches();
    value = SearchStateIdle(recentSearches: _recentSearches);
  }

  void onQueryChanged(String query) {
    final trimmed = query.trim();
    _suggestDebounce?.cancel();
    _searchDebounce?.cancel();

    if (trimmed.isEmpty) {
      value = SearchStateIdle(recentSearches: _recentSearches);
      return;
    }

    // Fast lane: YT Music autocomplete suggestions
    _suggestDebounce = Timer(
      const Duration(milliseconds: 220),
      () => _loadSuggestions(trimmed),
    );

    // Settle lane: auto-search after typing pauses
    _searchDebounce = Timer(
      const Duration(milliseconds: 650),
      () => performSearch(trimmed),
    );
  }

  Future<void> _loadSuggestions(String query) async {
    final token = ++_activeRequestId;
    try {
      final suggestions = await _ytMusic.getSearchSuggestions(query);
      if (token != _activeRequestId) return;
      value = SearchStateSuggestions(
        query: query,
        suggestions: suggestions,
        recentSearches: _recentSearches,
      );
    } catch (_) {
      // Suggestions are best-effort
    }
  }

  Future<void> performSearch(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return;

    _suggestDebounce?.cancel();
    _searchDebounce?.cancel();

    final token = ++_activeRequestId;
    value = SearchStateLoading(
      query: trimmed,
      selectedFilter: _selectedFilter,
    );

    try {
      final results = await _ytMusic.search(trimmed);
      if (token != _activeRequestId) return;

      final filtered = _filterOutLongMixes(results);
      value = SearchStateSuccess(
        query: trimmed,
        rawResults: filtered,
        selectedFilter: _selectedFilter,
      );
      await _saveRecentSearch(trimmed);
    } catch (e) {
      if (token != _activeRequestId) return;
      String msg = 'Search failed. Please try again.';
      final errStr = e.toString().toLowerCase();
      if (errStr.contains('socketexception') ||
          errStr.contains('timeout') ||
          errStr.contains('failed host lookup') ||
          errStr.contains('handshakeexception')) {
        msg = 'Offline or connection error. Please check your internet.';
      }
      value = SearchStateError(query: trimmed, message: msg);
    }
  }

  void setFilter(String filter) {
    if (_selectedFilter == filter) return;
    _selectedFilter = filter;
    PreferencesStore.instance.setString('search_selected_filter', filter);

    final current = value;
    if (current is SearchStateSuccess) {
      value = current.copyWithFilter(filter);
    } else if (current is SearchStateLoading) {
      value = SearchStateLoading(query: current.query, selectedFilter: filter);
    } else {
      notifyListeners();
    }
  }

  void clear() {
    _suggestDebounce?.cancel();
    _searchDebounce?.cancel();
    ++_activeRequestId;
    value = SearchStateIdle(recentSearches: _recentSearches);
  }

  List<dynamic> _filterOutLongMixes(List<dynamic> results) {
    bool isLongMix(dynamic item) {
      int? seconds;
      if (item is SongDetailed) seconds = item.duration;
      if (item is VideoDetailed) seconds = item.duration;
      return seconds != null && seconds >= _maxDurationSeconds;
    }

    return results.where((r) => !isLongMix(r)).toList();
  }

  Future<void> _loadRecentSearches() async {
    try {
      final prefs = PreferencesStore.instance;
      _recentSearches = prefs.getStringList(_recentKey) ?? [];
    } catch (_) {}
  }

  Future<void> _saveRecentSearch(String query) async {
    _recentSearches
      ..removeWhere((e) => e.toLowerCase() == query.toLowerCase())
      ..insert(0, query);
    if (_recentSearches.length > 8) {
      _recentSearches = _recentSearches.sublist(0, 8);
    }
    try {
      final prefs = PreferencesStore.instance;
      await prefs.setStringList(_recentKey, _recentSearches);
    } catch (_) {}
  }

  Future<void> removeRecentSearch(String query) async {
    _recentSearches.removeWhere((e) => e.toLowerCase() == query.toLowerCase());
    try {
      final prefs = PreferencesStore.instance;
      await prefs.setStringList(_recentKey, _recentSearches);
    } catch (_) {}
    final current = value;
    if (current is SearchStateIdle) {
      value = SearchStateIdle(recentSearches: _recentSearches);
    } else if (current is SearchStateSuggestions) {
      value = SearchStateSuggestions(
        query: current.query,
        suggestions: current.suggestions,
        recentSearches: _recentSearches,
      );
    }
  }

  Future<void> clearRecentSearches() async {
    _recentSearches = [];
    try {
      final prefs = PreferencesStore.instance;
      await prefs.setStringList(_recentKey, []);
    } catch (_) {}
    final current = value;
    if (current is SearchStateIdle) {
      value = const SearchStateIdle(recentSearches: []);
    } else if (current is SearchStateSuggestions) {
      value = SearchStateSuggestions(
        query: current.query,
        suggestions: current.suggestions,
        recentSearches: const [],
      );
    }
  }

  @override
  void dispose() {
    _suggestDebounce?.cancel();
    _searchDebounce?.cancel();
    super.dispose();
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// SEARCH SCREEN WIDGET
// ══════════════════════════════════════════════════════════════════════════════

class SearchScreen extends StatefulWidget {
  final Future<void> Function(List<TrackInfo> tracks, {int initialIndex})?
      onPlayTracks;

  const SearchScreen({super.key, this.onPlayTracks});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final SearchReactiveController _controller = SearchReactiveController();
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  Color get _bgDark => context.bgDark;
  Color get _surfaceDark => context.cardDark;
  Color get _primary => context.primaryColor;
  Color get _textPrimary => context.textPrimary;
  Color get _textDark => context.textMuted;
  Color get _outline => context.outlineColor;

  bool _showScrollTop = false;

  final List<String> _filters = [
    'All',
    'Songs',
    'Playlists',
    'Albums',
    'Artists',
  ];

  @override
  void initState() {
    super.initState();
    _controller.init();
    _scrollController.addListener(_onScroll);
    _searchController.addListener(_onInputChanged);
  }

  @override
  void dispose() {
    _searchController.removeListener(_onInputChanged);
    _searchController.dispose();
    _scrollController.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _onScroll() {
    final shouldShow =
        _scrollController.hasClients && _scrollController.offset > 600;
    if (shouldShow != _showScrollTop) {
      setState(() => _showScrollTop = shouldShow);
    }
  }

  void _onInputChanged() {
    _controller.onQueryChanged(_searchController.text);
  }

  void _runSearchFromSuggestion(String query) {
    _searchController.text = query;
    _searchController.selection = TextSelection.fromPosition(
      TextPosition(offset: query.length),
    );
    _controller.performSearch(query);
  }

  // ── Common field extractors ────────────────────────────────────────────────
  String _itemName(dynamic item) {
    if (item is SongDetailed) return item.name;
    if (item is VideoDetailed) return item.name;
    if (item is AlbumDetailed) return item.name;
    if (item is PlaylistDetailed) return item.name;
    if (item is ArtistDetailed) return item.name;
    if (item is ArtistDetailedSearchResult) return item.artistDetailed.name;
    return 'Unknown';
  }

  String _itemSubtitle(dynamic item) {
    if (item is SongDetailed) return item.artist.name;
    if (item is VideoDetailed) return item.artist.name;
    if (item is AlbumDetailed) return 'Album • ${item.artist.name}';
    if (item is PlaylistDetailed) return 'Playlist • ${item.artist.name}';
    if (item is ArtistDetailed || item is ArtistDetailedSearchResult) {
      return 'Artist';
    }
    return '';
  }

  String? _getTrailingText(dynamic item) {
    if (item is SongDetailed && item.duration != null) {
      final d = Duration(seconds: item.duration!);
      final m = d.inMinutes;
      final s = (d.inSeconds % 60).toString().padLeft(2, '0');
      return '$m:$s';
    }
    if (item is VideoDetailed && item.duration != null) {
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
    if (item is VideoDetailed) thumbs = item.thumbnails;
    if (item is AlbumDetailed) thumbs = item.thumbnails;
    if (item is PlaylistDetailed) thumbs = item.thumbnails;
    if (item is ArtistDetailed) thumbs = item.thumbnails;
    if (item is ArtistDetailedSearchResult) {
      thumbs = item.artistDetailed.thumbnails;
    }
    if (thumbs == null || thumbs.isEmpty) return null;
    final sorted = List<ThumbnailFull>.from(thumbs)
      ..sort((a, b) => b.width.compareTo(a.width));
    return sorted.first.url;
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
                    icon: const Icon(Icons.keyboard_arrow_up_rounded),
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
                      child: ValueListenableBuilder<SearchScreenState>(
                        valueListenable: _controller,
                        builder: (context, state, _) {
                          return AnimatedSwitcher(
                            duration: const Duration(milliseconds: 220),
                            switchInCurve: Curves.easeOutCubic,
                            switchOutCurve: Curves.easeInCubic,
                            child: KeyedSubtree(
                              key: ValueKey(_stateKey(state)),
                              child: _buildBodyForState(
                                state,
                                isDesktop: isDesktop,
                              ),
                            ),
                          );
                        },
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

  String _stateKey(SearchScreenState state) {
    return switch (state) {
      SearchStateIdle() => 'idle',
      SearchStateSuggestions() => 'suggestions',
      SearchStateLoading() => 'loading_${state.selectedFilter}',
      SearchStateSuccess() => 'success_${state.selectedFilter}',
      SearchStateError() => 'error',
    };
  }

  Widget _buildBodyForState(
    SearchScreenState state, {
    bool isDesktop = false,
  }) {
    return switch (state) {
      SearchStateIdle(:final recentSearches) => _buildIdleState(
          recentSearches: recentSearches,
          isDesktop: isDesktop,
        ),
      SearchStateSuggestions(:final suggestions, :final recentSearches) =>
        _buildSuggestionsPanel(
          suggestions: suggestions,
          recentSearches: recentSearches,
          isDesktop: isDesktop,
        ),
      SearchStateLoading(:final selectedFilter) => _SearchShimmerView(
          isDesktop: isDesktop,
          selectedFilter: selectedFilter,
        ),
      SearchStateSuccess(:final query, :final filteredResults) =>
        _buildResultsList(
          filteredResults,
          query: query,
          isDesktop: isDesktop,
        ),
      SearchStateError(:final message, :final query) => _buildError(
          message: message,
          query: query,
        ),
    };
  }

  // ── Header & Search Input ──────────────────────────────────────────────────

  Widget _buildSearchHeader({bool isDesktop = false}) {
    final canPop = Navigator.of(context).canPop();

    return Padding(
      padding: EdgeInsets.fromLTRB(
        isDesktop ? 32 : 16,
        isDesktop ? 20 : 12,
        isDesktop ? 32 : 16,
        8,
      ),
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
                context.strings.search,
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
                color: _outline.withValues(alpha: 0.18),
                width: 1,
              ),
            ),
            child: Row(
              children: [
                Padding(
                  padding: EdgeInsets.only(left: 16, right: isDesktop ? 16 : 8),
                  child: Icon(
                    Icons.search_rounded,
                    color: _textDark,
                    size: isDesktop ? 26 : 22,
                  ),
                ),
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    autofocus: true,
                    style: TextStyle(
                      color: _textPrimary,
                      fontSize: isDesktop ? 18 : 16,
                    ),
                    decoration: InputDecoration(
                      hintText: context.strings.searchPlaceholder,
                      hintStyle: TextStyle(
                        color: _textDark.withValues(alpha: 0.6),
                        fontSize: isDesktop ? 18 : 16,
                      ),
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                    textInputAction: TextInputAction.search,
                    onSubmitted: (q) => _controller.performSearch(q),
                  ),
                ),
                ValueListenableBuilder<TextEditingValue>(
                  valueListenable: _searchController,
                  builder: (context, value, _) {
                    if (value.text.isEmpty) return const SizedBox.shrink();
                    return IconButton(
                      icon: Icon(
                        Icons.close_rounded,
                        color: _textDark,
                        size: isDesktop ? 24 : 20,
                      ),
                      onPressed: () {
                        _searchController.clear();
                        _controller.clear();
                      },
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _getLocalizedFilter(String filter) {
    switch (filter) {
      case 'All':
        return context.strings.all;
      case 'Songs':
        return context.strings.tracks;
      case 'Playlists':
        return context.strings.playlists;
      case 'Albums':
        return context.strings.albums;
      case 'Artists':
        return context.strings.artists;
      default:
        return filter;
    }
  }

  Widget _buildFilterChips({bool isDesktop = false}) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final activeFilter = _controller.selectedFilter;
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          padding: EdgeInsets.symmetric(
            horizontal: isDesktop ? 32 : 16,
            vertical: isDesktop ? 16 : 10,
          ),
          child: Row(
            children: _filters.map((filter) {
              final isSelected = activeFilter == filter;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: M3EChip(
                  label: _getLocalizedFilter(filter),
                  type: M3EChipType.filter,
                  selected: isSelected,
                  onPressed: () => _controller.setFilter(filter),
                ),
              );
            }).toList(),
          ),
        );
      },
    );
  }

  // ── Idle State (Recent searches & placeholder) ─────────────────────────────

  Widget _buildIdleState({
    required List<String> recentSearches,
    bool isDesktop = false,
  }) {
    final hasRecents = recentSearches.isNotEmpty;
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
                onTap: _controller.clearRecentSearches,
                child: Text(
                  'Clear all',
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
            children: recentSearches
                .map((q) => M3EChip(
                      label: q,
                      leading: Icon(
                        Icons.history_rounded,
                        size: 16,
                        color: _textDark,
                      ),
                      onPressed: () => _runSearchFromSuggestion(q),
                    ))
                .toList(),
          ),
        ],
        const SizedBox(height: 140),
      ],
    );
  }

  // ── Suggestions panel ──────────────────────────────────────────────────────

  Widget _buildSuggestionsPanel({
    required List<String> suggestions,
    required List<String> recentSearches,
    bool isDesktop = false,
  }) {
    if (suggestions.isEmpty) {
      return RepaintBoundary(
        child: Center(
          child: Text(
            'Keep typing to see suggestions…',
            style: TextStyle(
              color: _textDark,
              fontSize: isDesktop ? 15 : 13,
            ),
          ),
        ),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      physics: const BouncingScrollPhysics(),
      padding: EdgeInsets.fromLTRB(
        isDesktop ? 32 : 12,
        4,
        isDesktop ? 32 : 12,
        120,
      ),
      itemCount: suggestions.length,
      itemBuilder: (context, index) {
        final suggestion = suggestions[index];
        final isRecent = recentSearches
            .any((r) => r.toLowerCase() == suggestion.toLowerCase());
        return RepaintBoundary(
          child: InkWell(
            onTap: () => _runSearchFromSuggestion(suggestion),
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
                    child: _buildHighlightedText(
                      suggestion,
                      _searchController.text,
                      baseStyle: TextStyle(
                        color: _textPrimary,
                        fontSize: isDesktop ? 17 : 15,
                        fontWeight: FontWeight.w500,
                      ),
                      highlightStyle: TextStyle(
                        color: _primary,
                        fontSize: isDesktop ? 17 : 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  Icon(
                    Icons.search_rounded,
                    color: _textDark.withValues(alpha: 0.4),
                    size: isDesktop ? 20 : 17,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // ── Error state ────────────────────────────────────────────────────────────

  Widget _buildError({required String message, required String query}) {
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
                message,
                textAlign: TextAlign.center,
                style: TextStyle(color: _textDark, fontSize: 13),
              ),
              const SizedBox(height: 20),
              M3EButton.icon(
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Retry Search'),
                onPressed: () => _controller.performSearch(query),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Results Presentation ───────────────────────────────────────────────────

  Widget _buildSectionHeader(String title, {bool isDesktop = false}) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        isDesktop ? 32 : 16,
        isDesktop ? 26 : 20,
        isDesktop ? 32 : 16,
        8,
      ),
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

  Widget _buildResultsList(
    List<dynamic> results, {
    required String query,
    bool isDesktop = false,
  }) {
    final selectedFilter = _controller.selectedFilter;

    if (results.isEmpty) {
      return RepaintBoundary(
        child: Center(
          child: Text(
            selectedFilter == 'All'
                ? 'No results found.'
                : 'No ${selectedFilter.toLowerCase()} in these results.',
            style: TextStyle(color: _textDark, fontSize: isDesktop ? 15 : 13),
          ),
        ),
      );
    }

    // Specific filter tab → standard full list
    if (selectedFilter != 'All') {
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
          query: query,
          isDesktop: isDesktop,
          isFirst: index == 0,
          isLast: index == results.length - 1,
        ),
      );
    }

    // 'All' tab → categorized sections with rich Top Result card
    final top = results.first;
    final rest = results.skip(1).toList();
    final songs = rest.where((r) => r is SongDetailed || r is VideoDetailed).toList();
    final artists = rest
        .where((r) => r is ArtistDetailed || r is ArtistDetailedSearchResult)
        .toList();
    final albums = rest.whereType<AlbumDetailed>().toList();
    final playlists = rest.whereType<PlaylistDetailed>().toList();

    Widget sectionItem(List<dynamic> items, int index) {
      final shown = items.length > 6 ? 6 : items.length;
      return Padding(
        padding: EdgeInsets.symmetric(horizontal: isDesktop ? 32 : 16),
        child: _buildStandardResultItem(
          items[index],
          query: query,
          isDesktop: isDesktop,
          isFirst: index == 0,
          isLast: index == shown - 1,
        ),
      );
    }

    return ListView(
      controller: _scrollController,
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.only(top: 8, bottom: 120),
      children: [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: isDesktop ? 32 : 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSectionHeader('TOP RESULT', isDesktop: isDesktop),
              _buildTopResultItem(top, query: query, isDesktop: isDesktop),
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

  // ── Rich Top Result Card ───────────────────────────────────────────────────

  Widget _buildTopResultItem(
    dynamic item, {
    required String query,
    bool isDesktop = false,
  }) {
    final name = _itemName(item);
    final thumb = _itemThumbnail(item);
    final isSong = item is SongDetailed;
    final isVideo = item is VideoDetailed;
    final isArtist = item is ArtistDetailed || item is ArtistDetailedSearchResult;
    final isAlbum = item is AlbumDetailed;
    final isPlaylist = item is PlaylistDetailed;

    String typeLabel = 'RESULT';
    if (isSong) typeLabel = 'SONG';
    if (isVideo) typeLabel = 'MUSIC VIDEO';
    if (isArtist) typeLabel = 'ARTIST';
    if (isAlbum) typeLabel = 'ALBUM';
    if (isPlaylist) typeLabel = 'PLAYLIST';

    return RepaintBoundary(
      child: M3ECard(
        variant: M3ECardVariant.elevated,
        onPressed: () => _handleItemTap(item),
        color: _surfaceDark,
        borderRadius: BorderRadius.circular(20),
        padding: EdgeInsets.all(isDesktop ? 18 : 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: _primary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isSong
                            ? Icons.music_note_rounded
                            : isVideo
                                ? Icons.ondemand_video_rounded
                                : isArtist
                                    ? Icons.person_rounded
                                    : Icons.album_rounded,
                        size: 13,
                        color: _primary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'TOP $typeLabel',
                        style: TextStyle(
                          color: _primary,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                if (_getTrailingText(item) != null)
                  Text(
                    _getTrailingText(item)!,
                    style: TextStyle(
                      color: _textDark,
                      fontSize: isDesktop ? 13 : 11.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(
                  width: isDesktop ? 110 : 80,
                  height: isDesktop ? 110 : 80,
                  child: M3EContainer(
                    isArtist ? Shapes.circle : Shapes.slanted,
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
                            memCacheWidth: 220,
                            memCacheHeight: 220,
                            placeholder: (_, __) => Container(
                              color: _surfaceDark,
                              child: Icon(
                                isArtist
                                    ? Icons.person_rounded
                                    : Icons.music_note_rounded,
                                color: _textDark.withValues(alpha: 0.4),
                                size: 30,
                              ),
                            ),
                            errorWidget: (_, __, ___) => Container(
                              color: _surfaceDark,
                              child: Icon(
                                isArtist
                                    ? Icons.person_rounded
                                    : Icons.music_note_rounded,
                                color: _textDark.withValues(alpha: 0.4),
                                size: 30,
                              ),
                            ),
                          )
                        : Center(
                            child: Icon(
                              isArtist
                                  ? Icons.person_rounded
                                  : Icons.music_note_rounded,
                              color: _textDark.withValues(alpha: 0.4),
                              size: 30,
                            ),
                          ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildHighlightedText(
                        name,
                        query,
                        maxLines: 2,
                        baseStyle: TextStyle(
                          color: _textPrimary,
                          fontSize: isDesktop ? 20 : 17,
                          fontWeight: FontWeight.bold,
                          letterSpacing: -0.2,
                        ),
                        highlightStyle: TextStyle(
                          color: _primary,
                          fontSize: isDesktop ? 20 : 17,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 5),
                      _buildSongOrItemSubtitle(
                        item,
                        query,
                        isDesktop: isDesktop,
                        isTopResult: true,
                      ),
                      const SizedBox(height: 10),
                      // Actions and badges
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          if (isSong || isVideo)
                            FilledButton.tonalIcon(
                              icon: const Icon(
                                Icons.play_arrow_rounded,
                                size: 18,
                              ),
                              label: const Text('Play'),
                              style: FilledButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 6,
                                ),
                                visualDensity: VisualDensity.compact,
                              ),
                              onPressed: () => _handleItemTap(item),
                            ),
                          if (isSong &&
                              item.album != null &&
                              item.album!.albumId.isNotEmpty)
                            OutlinedButton.icon(
                              icon: const Icon(
                                Icons.album_outlined,
                                size: 15,
                              ),
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
                              icon: const Icon(
                                Icons.person_outline_rounded,
                                size: 15,
                              ),
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
                          if (isArtist)
                            FilledButton.tonalIcon(
                              icon: const Icon(
                                Icons.person_search_rounded,
                                size: 18,
                              ),
                              label: const Text('View Profile'),
                              style: FilledButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 6,
                                ),
                                visualDensity: VisualDensity.compact,
                              ),
                              onPressed: () => _handleItemTap(item),
                            ),
                          if (isAlbum)
                            FilledButton.tonalIcon(
                              icon: const Icon(
                                Icons.album_rounded,
                                size: 18,
                              ),
                              label: const Text('View Album'),
                              style: FilledButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 6,
                                ),
                                visualDensity: VisualDensity.compact,
                              ),
                              onPressed: () => _handleItemTap(item),
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

  // ── Standard Item with Rich Song Metadata ──────────────────────────────────

  Widget _buildStandardResultItem(
    dynamic item, {
    required String query,
    bool isDesktop = false,
    bool isFirst = false,
    bool isLast = false,
  }) {
    final name = _itemName(item);
    final thumb = _itemThumbnail(item);
    final isArtist = item is ArtistDetailed || item is ArtistDetailedSearchResult;
    final isSong = item is SongDetailed;
    final isVideo = item is VideoDetailed;
    final thumbSize = isDesktop ? 60.0 : 48.0;

    final borderRadius = BorderRadius.only(
      topLeft: Radius.circular(isFirst ? 20 : 6),
      topRight: Radius.circular(isFirst ? 20 : 6),
      bottomLeft: Radius.circular(isLast ? 20 : 6),
      bottomRight: Radius.circular(isLast ? 20 : 6),
    );

    // Relevance cues
    String? matchBadge;
    final cleanQuery = query.trim().toLowerCase();
    if (cleanQuery.isNotEmpty) {
      final nameMatches = name.toLowerCase().contains(cleanQuery);
      if (!nameMatches) {
        if (isSong && item.artist.name.toLowerCase().contains(cleanQuery)) {
          matchBadge = 'Artist match';
        } else if (isSong &&
            item.album != null &&
            item.album!.name.toLowerCase().contains(cleanQuery)) {
          matchBadge = 'Album match';
        }
      }
    }

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
                        Row(
                          children: [
                            Flexible(
                              child: _buildHighlightedText(
                                name,
                                query,
                                baseStyle: TextStyle(
                                  fontSize: isDesktop ? 15 : 13.5,
                                  fontWeight: FontWeight.w600,
                                  color: _textPrimary,
                                ),
                                highlightStyle: TextStyle(
                                  fontSize: isDesktop ? 15 : 13.5,
                                  fontWeight: FontWeight.bold,
                                  color: _primary,
                                ),
                              ),
                            ),
                            if (isVideo) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 5,
                                  vertical: 1,
                                ),
                                decoration: BoxDecoration(
                                  color:
                                      Colors.redAccent.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Text(
                                  'VIDEO',
                                  style: TextStyle(
                                    color: Colors.redAccent,
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ),
                            ],
                            if (matchBadge != null) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 5,
                                  vertical: 1,
                                ),
                                decoration: BoxDecoration(
                                  color: _primary.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  matchBadge,
                                  style: TextStyle(
                                    color: _primary,
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 3),
                        _buildSongOrItemSubtitle(
                          item,
                          query,
                          isDesktop: isDesktop,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (isSong || isVideo) ...[
                    if (_getTrailingText(item) != null)
                      Text(
                        _getTrailingText(item)!,
                        style: TextStyle(
                          color: _textDark,
                          fontSize: isDesktop ? 13 : 11.5,
                        ),
                      ),
                    const SizedBox(width: 4),
                    IconButton(
                      icon: Icon(
                        Icons.play_circle_fill_rounded,
                        color: _primary.withValues(alpha: 0.85),
                        size: isDesktop ? 26 : 22,
                      ),
                      tooltip: 'Play track',
                      visualDensity: VisualDensity.compact,
                      onPressed: () => _handleItemTap(item),
                    ),
                    if (item is SongDetailed &&
                        (item.album != null || item.artist.artistId != null))
                      _buildSongOptionsMenu(item),
                  ] else if (_getTrailingText(item) != null) ...[
                    Text(
                      _getTrailingText(item)!,
                      style: TextStyle(
                        color: _textDark,
                        fontSize: isDesktop ? 13 : 11.5,
                      ),
                    ),
                  ] else ...[
                    Icon(
                      Icons.chevron_right_rounded,
                      color: const Color(0xFF64748B),
                      size: isDesktop ? 20 : 18,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSongOrItemSubtitle(
    dynamic item,
    String query, {
    bool isDesktop = false,
    bool isTopResult = false,
  }) {
    final style = TextStyle(
      fontSize: isDesktop
          ? (isTopResult ? 15 : 13)
          : (isTopResult ? 13.5 : 11.5),
      color: _textDark,
    );
    final highlightStyle = style.copyWith(
      color: _primary,
      fontWeight: FontWeight.bold,
    );

    if (item is SongDetailed) {
      final artistName = item.artist.name;
      final albumName = item.album?.name;

      if (albumName != null && albumName.isNotEmpty && albumName != artistName) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: _buildHighlightedText(
                artistName,
                query,
                baseStyle: style,
                highlightStyle: highlightStyle,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4.0),
              child: Text('•', style: style),
            ),
            Icon(
              Icons.album_outlined,
              size: isDesktop ? 13 : 11,
              color: _textDark.withValues(alpha: 0.7),
            ),
            const SizedBox(width: 3),
            Flexible(
              child: _buildHighlightedText(
                albumName,
                query,
                baseStyle: style,
                highlightStyle: highlightStyle,
              ),
            ),
          ],
        );
      } else {
        return _buildHighlightedText(
          artistName,
          query,
          baseStyle: style,
          highlightStyle: highlightStyle,
        );
      }
    }

    if (item is VideoDetailed) {
      return _buildHighlightedText(
        item.artist.name,
        query,
        baseStyle: style,
        highlightStyle: highlightStyle,
      );
    }

    if (item is AlbumDetailed) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Album • ', style: style),
          Flexible(
            child: _buildHighlightedText(
              item.artist.name,
              query,
              baseStyle: style,
              highlightStyle: highlightStyle,
            ),
          ),
        ],
      );
    }

    if (item is PlaylistDetailed) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Playlist • ', style: style),
          Flexible(
            child: _buildHighlightedText(
              item.artist.name,
              query,
              baseStyle: style,
              highlightStyle: highlightStyle,
            ),
          ),
        ],
      );
    }

    if (item is ArtistDetailed || item is ArtistDetailedSearchResult) {
      return Text('Artist Profile', style: style);
    }

    return Text(_itemSubtitle(item), style: style);
  }

  Widget _buildSongOptionsMenu(SongDetailed song) {
    return PopupMenuButton<String>(
      icon: Icon(
        Icons.more_vert_rounded,
        size: 18,
        color: _textDark.withValues(alpha: 0.8),
      ),
      padding: EdgeInsets.zero,
      color: _surfaceDark,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: _outline.withValues(alpha: 0.15)),
      ),
      onSelected: (val) {
        if (val == 'play') {
          _handleItemTap(song);
        } else if (val == 'album') {
          _openSongAlbum(song);
        } else if (val == 'artist') {
          _openSongArtist(song);
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          value: 'play',
          child: Row(
            children: [
              Icon(Icons.play_arrow_rounded, color: _primary, size: 20),
              const SizedBox(width: 10),
              const Text('Play Song'),
            ],
          ),
        ),
        if (song.album != null && song.album!.albumId.isNotEmpty)
          PopupMenuItem(
            value: 'album',
            child: Row(
              children: [
                Icon(Icons.album_outlined, color: _textDark, size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Go to Album (${song.album!.name})',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        if (song.artist.artistId != null && song.artist.artistId!.isNotEmpty)
          PopupMenuItem(
            value: 'artist',
            child: Row(
              children: [
                Icon(Icons.person_outline_rounded, color: _textDark, size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Go to Artist (${song.artist.name})',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  // ── Navigation & Actions ───────────────────────────────────────────────────

  void _handleItemTap(dynamic item) {
    if (item is SongDetailed) {
      final track = TrackInfo(
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
      if (widget.onPlayTracks != null) {
        widget.onPlayTracks!([track], initialIndex: 0);
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } else if (item is VideoDetailed) {
      final track = TrackInfo(
        videoId: item.videoId,
        title: item.name,
        artist: item.artist.name,
        artistId: item.artist.artistId,
        albumArtist: item.artist.name,
        durationSeconds: item.duration,
        thumbnailUrl: _itemThumbnail(item),
      );
      if (widget.onPlayTracks != null) {
        widget.onPlayTracks!([track], initialIndex: 0);
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } else if (item is ArtistDetailed) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ArtistProfileScreen(
            artistId: item.artistId,
            artistName: item.name,
            onPlayTracks: widget.onPlayTracks,
          ),
        ),
      );
    } else if (item is ArtistDetailedSearchResult) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ArtistProfileScreen(
            artistId: item.artistDetailed.artistId,
            artistName: item.artistDetailed.name,
            onPlayTracks: widget.onPlayTracks,
          ),
        ),
      );
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
}

// ══════════════════════════════════════════════════════════════════════════════
// SHIMMER LOADING SKELETON
// ══════════════════════════════════════════════════════════════════════════════

class _SearchShimmerView extends StatelessWidget {
  final bool isDesktop;
  final String selectedFilter;

  const _SearchShimmerView({
    required this.isDesktop,
    required this.selectedFilter,
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

    Widget buildSongSkeleton({
      required bool isFirst,
      required bool isLast,
    }) {
      final borderRadius = BorderRadius.only(
        topLeft: Radius.circular(isFirst ? 20 : 6),
        topRight: Radius.circular(isFirst ? 20 : 6),
        bottomLeft: Radius.circular(isLast ? 20 : 6),
        bottomRight: Radius.circular(isLast ? 20 : 6),
      );
      final thumbSize = isDesktop ? 60.0 : 48.0;

      return Padding(
        padding: const EdgeInsets.only(bottom: 3.0),
        child: Container(
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: borderRadius,
            border: Border.all(
              color: context.outlineColor.withValues(alpha: 0.12),
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              shimmerBox(
                width: thumbSize,
                height: thumbSize,
                borderRadius: 10,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    shimmerBox(
                      width: isDesktop ? 220 : 150,
                      height: 14,
                      borderRadius: 4,
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        shimmerBox(
                          width: isDesktop ? 100 : 70,
                          height: 11,
                          borderRadius: 4,
                        ),
                        const SizedBox(width: 8),
                        shimmerBox(
                          width: isDesktop ? 120 : 80,
                          height: 11,
                          borderRadius: 4,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              shimmerBox(
                width: 34,
                height: 12,
                borderRadius: 4,
              ),
              const SizedBox(width: 8),
              shimmerBox(
                width: 26,
                height: 26,
                shape: BoxShape.circle,
              ),
            ],
          ),
        ),
      );
    }

    return RepaintBoundary(
      child: Shimmer.fromColors(
        baseColor: baseColor,
        highlightColor: highlightColor,
        child: ListView(
          physics: const BouncingScrollPhysics(),
          padding: EdgeInsets.symmetric(
            horizontal: isDesktop ? 32 : 16,
            vertical: 8,
          ).copyWith(bottom: 120),
          children: [
            if (selectedFilter == 'All') ...[
              // Top result skeleton
              Container(
                decoration: BoxDecoration(
                  color: cardColor,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: context.outlineColor.withValues(alpha: 0.12),
                  ),
                ),
                padding: EdgeInsets.all(isDesktop ? 18 : 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        shimmerBox(
                          width: 80,
                          height: 12,
                          borderRadius: 4,
                        ),
                        const Spacer(),
                        shimmerBox(
                          width: 44,
                          height: 12,
                          borderRadius: 4,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        shimmerBox(
                          width: isDesktop ? 100 : 76,
                          height: isDesktop ? 100 : 76,
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
                                width: isDesktop ? 150 : 110,
                                height: 13,
                                borderRadius: 4,
                              ),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  shimmerBox(
                                    width: 50,
                                    height: 18,
                                    borderRadius: 6,
                                  ),
                                  const SizedBox(width: 8),
                                  shimmerBox(
                                    width: 65,
                                    height: 18,
                                    borderRadius: 6,
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
              const SizedBox(height: 16),
              // Section header skeleton
              Row(
                children: [
                  shimmerBox(width: 4, height: 18, borderRadius: 2),
                  const SizedBox(width: 10),
                  shimmerBox(width: 70, height: 16, borderRadius: 4),
                ],
              ),
              const SizedBox(height: 8),
              for (var i = 0; i < 5; i++)
                buildSongSkeleton(isFirst: i == 0, isLast: i == 4),
            ] else ...[
              for (var i = 0; i < 7; i++)
                buildSongSkeleton(isFirst: i == 0, isLast: i == 6),
            ],
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// HIGHLIGHTED TEXT UTILITY
// ══════════════════════════════════════════════════════════════════════════════

Widget _buildHighlightedText(
  String text,
  String query, {
  required TextStyle baseStyle,
  required TextStyle highlightStyle,
  int maxLines = 1,
  TextOverflow overflow = TextOverflow.ellipsis,
}) {
  final cleanQuery = query.trim();
  if (cleanQuery.isEmpty || text.isEmpty) {
    return Text(
      text,
      style: baseStyle,
      maxLines: maxLines,
      overflow: overflow,
    );
  }

  final lowerText = text.toLowerCase();
  final lowerQuery = cleanQuery.toLowerCase();

  final matches = <_TextRange>[];
  var start = 0;
  while (start < lowerText.length) {
    final idx = lowerText.indexOf(lowerQuery, start);
    if (idx == -1) break;
    matches.add(_TextRange(idx, idx + lowerQuery.length));
    start = idx + lowerQuery.length;
  }

  // Multi-word fallback
  if (matches.isEmpty && lowerQuery.contains(' ')) {
    final words = lowerQuery
        .split(RegExp(r'\s+'))
        .where((w) => w.length >= 2)
        .toList();
    for (final word in words) {
      var wStart = 0;
      while (wStart < lowerText.length) {
        final idx = lowerText.indexOf(word, wStart);
        if (idx == -1) break;
        matches.add(_TextRange(idx, idx + word.length));
        wStart = idx + word.length;
      }
    }
  }

  if (matches.isEmpty) {
    return Text(
      text,
      style: baseStyle,
      maxLines: maxLines,
      overflow: overflow,
    );
  }

  // Merge overlapping or adjoining ranges
  matches.sort((a, b) => a.start.compareTo(b.start));
  final merged = <_TextRange>[];
  for (final m in matches) {
    if (merged.isEmpty) {
      merged.add(m);
    } else {
      final last = merged.last;
      if (m.start <= last.end) {
        merged[merged.length - 1] = _TextRange(
          last.start,
          m.end > last.end ? m.end : last.end,
        );
      } else {
        merged.add(m);
      }
    }
  }

  final spans = <TextSpan>[];
  var currentIndex = 0;
  for (final m in merged) {
    if (m.start > currentIndex) {
      spans.add(TextSpan(
        text: text.substring(currentIndex, m.start),
        style: baseStyle,
      ));
    }
    spans.add(TextSpan(
      text: text.substring(m.start, m.end),
      style: highlightStyle,
    ));
    currentIndex = m.end;
  }
  if (currentIndex < text.length) {
    spans.add(TextSpan(
      text: text.substring(currentIndex),
      style: baseStyle,
    ));
  }

  return Text.rich(
    TextSpan(children: spans),
    maxLines: maxLines,
    overflow: overflow,
  );
}

class _TextRange {
  final int start;
  final int end;
  const _TextRange(this.start, this.end);
}
