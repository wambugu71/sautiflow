import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/cached_stream_item.dart';

/// Service managing offline cached online audio streams and their metadata.
class CachedStreamService {
  static final CachedStreamService instance = CachedStreamService._internal();

  CachedStreamService._internal();

  static const String _storageKey = 'sautiplay_cached_streams_metadata_v1';

  final ValueNotifier<List<CachedStreamItem>> cachedStreamsNotifier =
      ValueNotifier<List<CachedStreamItem>>([]);

  final ValueNotifier<int> totalSizeBytesNotifier = ValueNotifier<int>(0);

  bool _isInitialized = false;

  Directory get cacheDirectory => Directory(
        '${Directory.systemTemp.path}${Platform.pathSeparator}miniaudiodart_stream_cache',
      );

  /// Initializes the service, loading persisted metadata and verifying files on disk.
  Future<void> init() async {
    if (_isInitialized) return;
    _isInitialized = true;
    await refreshCache();
  }

  /// Scans the cache folder and persisted records, pruning non-existent files.
  Future<List<CachedStreamItem>> refreshCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final rawList = prefs.getStringList(_storageKey) ?? [];

      final loadedItems = <CachedStreamItem>[];
      final seenPaths = <String>{};

      for (final raw in rawList) {
        try {
          final item = CachedStreamItem.fromJson(raw);
          if (File(item.filePath).existsSync()) {
            loadedItems.add(item);
            seenPaths.add(item.filePath);
          }
        } catch (_) {}
      }

      // Also scan directory in case new stream files were written directly
      if (cacheDirectory.existsSync()) {
        final dirFiles = cacheDirectory.listSync().whereType<File>();
        for (final file in dirFiles) {
          if (!file.path.endsWith('.tmp') && !seenPaths.contains(file.path)) {
            final size = file.existsSync() ? file.lengthSync() : 0;
            if (size > 1024) {
              final fileName = file.uri.pathSegments.last;
              loadedItems.add(CachedStreamItem(
                videoId: fileName,
                title: fileName.replaceAll('.mp3', '').replaceAll('stream_', ''),
                artist: 'Online Stream',
                thumbnailUrl: null,
                durationSeconds: 0,
                filePath: file.path,
                streamUrl: null,
                fileSizeBytes: size,
                cachedAt: file.lastModifiedSync(),
              ));
              seenPaths.add(file.path);
            }
          }
        }
      }

      // Sort newest first
      loadedItems.sort((a, b) => b.cachedAt.compareTo(a.cachedAt));

      cachedStreamsNotifier.value = List.unmodifiable(loadedItems);
      _updateTotalSize(loadedItems);
      await _persist(loadedItems);

      return loadedItems;
    } catch (e) {
      debugPrint('[CachedStreamService] Error refreshing cache: $e');
      return cachedStreamsNotifier.value;
    }
  }

  /// Registers or updates metadata for a cached audio stream file.
  Future<void> registerCachedStream({
    required String videoId,
    required String title,
    required String artist,
    String? thumbnailUrl,
    required String filePath,
    int? durationSeconds,
    String? streamUrl,
    int? fileSizeBytes,
  }) async {
    try {
      final file = File(filePath);
      if (!file.existsSync()) return;

      final actualSize = fileSizeBytes ?? file.lengthSync();
      if (actualSize <= 1024) return; // Skip zero or invalid files

      final current = List<CachedStreamItem>.from(cachedStreamsNotifier.value);
      current.removeWhere(
          (item) => item.filePath == filePath || item.videoId == videoId);

      final newItem = CachedStreamItem(
        videoId: videoId,
        title: title.isNotEmpty ? title : 'Stream $videoId',
        artist: artist.isNotEmpty ? artist : 'Online Stream',
        thumbnailUrl: thumbnailUrl,
        durationSeconds: durationSeconds ?? 0,
        filePath: filePath,
        streamUrl: streamUrl,
        fileSizeBytes: actualSize,
        cachedAt: DateTime.now(),
      );

      current.insert(0, newItem);

      cachedStreamsNotifier.value = List.unmodifiable(current);
      _updateTotalSize(current);
      await _persist(current);
    } catch (e) {
      debugPrint('[CachedStreamService] Error registering cached stream: $e');
    }
  }

  /// Deletes a cached stream file from disk and removes its metadata.
  Future<void> removeCachedStream(String filePath) async {
    try {
      final file = File(filePath);
      if (file.existsSync()) {
        try {
          file.deleteSync();
        } catch (e) {
          debugPrint('[CachedStreamService] Error deleting file $filePath: $e');
        }
      }

      final current = List<CachedStreamItem>.from(cachedStreamsNotifier.value)
        ..removeWhere((item) => item.filePath == filePath);

      cachedStreamsNotifier.value = List.unmodifiable(current);
      _updateTotalSize(current);
      await _persist(current);
    } catch (e) {
      debugPrint('[CachedStreamService] Error removing cached stream: $e');
    }
  }

  /// Clears the entire stream cache folder and clears stored records.
  Future<void> clearAllCache() async {
    try {
      if (cacheDirectory.existsSync()) {
        final entities = cacheDirectory.listSync();
        for (final entity in entities) {
          try {
            entity.deleteSync(recursive: true);
          } catch (_) {}
        }
      }

      cachedStreamsNotifier.value = const [];
      totalSizeBytesNotifier.value = 0;

      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_storageKey);
    } catch (e) {
      debugPrint('[CachedStreamService] Error clearing all cache: $e');
    }
  }

  void _updateTotalSize(List<CachedStreamItem> items) {
    int total = 0;
    for (final item in items) {
      total += item.fileSizeBytes;
    }
    totalSizeBytesNotifier.value = total;
  }

  Future<void> _persist(List<CachedStreamItem> items) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stringList = items.map((e) => e.toJson()).toList();
      await prefs.setStringList(_storageKey, stringList);
    } catch (e) {
      debugPrint('[CachedStreamService] Error saving metadata: $e');
    }
  }

  /// Helper to format a byte count nicely into MB/KB string.
  static String formatBytes(int bytes) {
    if (bytes <= 0) return '0 MB';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
