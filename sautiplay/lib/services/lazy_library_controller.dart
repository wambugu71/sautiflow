import 'dart:async';
import 'dart:collection';
import 'package:flutter/foundation.dart';

import '../database/app_database.dart';
import '../models/local_song_item.dart';

/// Windowed lazy-loading controller backed by indexed Drift/SQLite queries.
///
/// Keeps only a bounded LRU window of track chunks in memory while exposing
/// the full [totalCount] for continuous scrollbars and instant index jumping.
/// Playback reactivity is decoupled into [activeTrackPath] so tapping any
/// index only rebuilds the affected rows without invalidating the list cache.
class LazyLibraryController extends ChangeNotifier {
  final AppDatabase _db;
  final int chunkSize;
  final int maxCachedChunks;

  LazyLibraryController({
    AppDatabase? db,
    this.chunkSize = 64,
    this.maxCachedChunks = 16,
  }) : _db = db ?? AppDatabase.instance;

  /// Decoupled reactive notifier for the currently playing track path.
  /// Row widgets listen to this directly so playing any index never requires
  /// rebuilding or re-querying the track list.
  final ValueNotifier<String?> activeTrackPath = ValueNotifier<String?>(null);

  final LinkedHashMap<int, List<LocalSongItem>> _chunkCache =
      LinkedHashMap<int, List<LocalSongItem>>();
  final Set<int> _inFlightChunks = <int>{};
  final Set<int> _pendingChunks = <int>{};
  bool _flushScheduled = false;

  int _totalCount = 0;
  int _totalLibraryCount = 0;
  String _query = '';
  String _sort = 'Name (A-Z)';
  int _generation = 0;
  bool _disposed = false;

  int get totalCount => _totalCount;
  int get totalLibraryCount => _totalLibraryCount;
  String get query => _query;
  String get sort => _sort;
  int get cachedChunkCount => _chunkCache.length;

  @visibleForTesting
  int get cachedItemCount =>
      _chunkCache.values.fold<int>(0, (sum, chunk) => sum + chunk.length);

  void setActiveTrackPath(String? path) {
    if (activeTrackPath.value != path) {
      activeTrackPath.value = path;
    }
  }

  /// Refreshes counts and pre-loads the first chunk for the given [query] and [sort].
  Future<void> refresh({
    String? query,
    String? sort,
    bool clearCache = true,
  }) async {
    if (_disposed) return;
    if (query != null) _query = query;
    if (sort != null) _sort = sort;

    final gen = ++_generation;
    if (clearCache) {
      _chunkCache.clear();
      _inFlightChunks.clear();
      _pendingChunks.clear();
    }

    final counts = await Future.wait([
      _db.countLocalTracks(query: _query),
      _query.trim().isEmpty
          ? Future<int>.value(-1)
          : _db.countLocalTracks(query: ''),
    ]);

    if (_disposed || gen != _generation) return;

    _totalCount = counts[0];
    _totalLibraryCount = counts[1] == -1 ? counts[0] : counts[1];

    if (_totalCount > 0 && !_chunkCache.containsKey(0)) {
      final firstChunk = await _db.fetchLocalTracksWindow(
        offset: 0,
        limit: chunkSize,
        query: _query,
        sort: _sort,
      );
      if (_disposed || gen != _generation) return;
      _putChunk(0, firstChunk);
    }

    if (!_disposed) {
      notifyListeners();
    }
  }

  /// Invalidates the LRU cache and reloads counts + visible chunks.
  Future<void> invalidate() => refresh(clearCache: true);

  /// Returns the [LocalSongItem] at [index] if its chunk is cached, or `null`
  /// while scheduling an asynchronous chunk fetch (plus lookahead prefetch).
  LocalSongItem? getItem(int index) {
    if (index < 0 || index >= _totalCount) return null;

    final chunkIdx = index ~/ chunkSize;
    final offsetInChunk = index % chunkSize;

    final cached = _chunkCache.remove(chunkIdx);
    if (cached != null) {
      // Touch LRU order
      _chunkCache[chunkIdx] = cached;

      // Prefetch next chunk when scrolling past the midpoint of the current chunk
      final nextChunkIdx = chunkIdx + 1;
      if (offsetInChunk >= chunkSize ~/ 2 &&
          nextChunkIdx * chunkSize < _totalCount &&
          !_chunkCache.containsKey(nextChunkIdx)) {
        _scheduleChunkFetch(nextChunkIdx);
      }

      if (offsetInChunk < cached.length) {
        return cached[offsetInChunk];
      }
      return null;
    }

    _scheduleChunkFetch(chunkIdx);
    return null;
  }

  void _scheduleChunkFetch(int chunkIdx) {
    if (_disposed ||
        _chunkCache.containsKey(chunkIdx) ||
        _inFlightChunks.contains(chunkIdx)) {
      return;
    }
    _pendingChunks.add(chunkIdx);
    if (!_flushScheduled) {
      _flushScheduled = true;
      Future.microtask(_flushPendingChunks);
    }
  }

  Future<void> _flushPendingChunks() async {
    _flushScheduled = false;
    if (_disposed || _pendingChunks.isEmpty) return;

    final toFetch = _pendingChunks.toList()..sort();
    _pendingChunks.clear();

    final gen = _generation;
    bool anyLoaded = false;

    await Future.wait(toFetch.map((chunkIdx) async {
      if (_disposed ||
          gen != _generation ||
          _chunkCache.containsKey(chunkIdx) ||
          _inFlightChunks.contains(chunkIdx)) {
        return;
      }
      _inFlightChunks.add(chunkIdx);
      try {
        final rows = await _db.fetchLocalTracksWindow(
          offset: chunkIdx * chunkSize,
          limit: chunkSize,
          query: _query,
          sort: _sort,
        );
        if (_disposed || gen != _generation) return;
        _putChunk(chunkIdx, rows);
        anyLoaded = true;
      } finally {
        _inFlightChunks.remove(chunkIdx);
      }
    }));

    if (anyLoaded && !_disposed && gen == _generation) {
      notifyListeners();
    }
  }

  void _putChunk(int chunkIdx, List<LocalSongItem> items) {
    _chunkCache.remove(chunkIdx);
    _chunkCache[chunkIdx] = items;
    while (_chunkCache.length > maxCachedChunks) {
      _chunkCache.remove(_chunkCache.keys.first);
    }
  }

  /// Fetches all matching track paths in current sort order for queue playback.
  Future<List<String>> fetchAllMatchingPaths() {
    return _db.fetchLocalTrackPaths(query: _query, sort: _sort);
  }

  /// Finds the index of [path] in the current sort/filter order.
  Future<int> findIndexOfPath(String path) async {
    for (final entry in _chunkCache.entries) {
      final localIdx = entry.value.indexWhere((s) => s.path == path);
      if (localIdx != -1) {
        return entry.key * chunkSize + localIdx;
      }
    }
    return _db.findLocalTrackIndex(path, query: _query, sort: _sort);
  }

  @override
  void dispose() {
    _disposed = true;
    activeTrackPath.dispose();
    _chunkCache.clear();
    _inFlightChunks.clear();
    _pendingChunks.clear();
    super.dispose();
  }
}
