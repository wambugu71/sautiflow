import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/cached_stream_item.dart';
import '../streaming_service.dart';

/// Service managing offline cached online audio streams and their metadata.
class CachedStreamService {
  static final CachedStreamService instance = CachedStreamService._internal();

  CachedStreamService._internal();

  static const String _storageKey = 'sautiplay_cached_streams_metadata_v1';

  final ValueNotifier<List<CachedStreamItem>> cachedStreamsNotifier =
      ValueNotifier<List<CachedStreamItem>>([]);

  final ValueNotifier<int> totalSizeBytesNotifier = ValueNotifier<int>(0);

  final Set<String> _activeDownloads = <String>{};

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

  /// Looks up whether an audio stream is already downloaded and cached locally.
  CachedStreamItem? getCachedItem(String videoId) {
    for (final item in cachedStreamsNotifier.value) {
      if (item.videoId == videoId && File(item.filePath).existsSync()) {
        return item;
      }
    }
    return null;
  }

  /// Downloads an online audio stream in the background, saves it to disk cache,
  /// and automatically registers it for the Library "Cached Online Streams" playlist.
  Future<void> cacheStreamInBackground({
    required String videoId,
    required String streamUrl,
    required String title,
    required String artist,
    String? thumbnailUrl,
    int? durationSeconds,
  }) async {
    if (videoId.isEmpty) return;
    if (_activeDownloads.contains(videoId)) return;
    _activeDownloads.add(videoId);

    try {
      final dir = cacheDirectory;
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }

      // Determine container extension (.m4a, .webm, or .mp3)
      String ext = 'm4a';
      final lowerUrl = streamUrl.toLowerCase();
      if (lowerUrl.contains('webm') ||
          lowerUrl.contains('opus') ||
          lowerUrl.contains('itag=251') ||
          lowerUrl.contains('itag=250') ||
          lowerUrl.contains('itag=249')) {
        ext = 'webm';
      } else if (lowerUrl.contains('download') || lowerUrl.contains('mp3')) {
        ext = 'mp3';
      }

      final targetFile =
          File('${dir.path}${Platform.pathSeparator}stream_$videoId.$ext');

      // If valid file already exists, just register metadata
      if (targetFile.existsSync() && targetFile.lengthSync() > 1024) {
        await registerCachedStream(
          videoId: videoId,
          title: title,
          artist: artist,
          thumbnailUrl: thumbnailUrl,
          durationSeconds: durationSeconds,
          filePath: targetFile.path,
          streamUrl: streamUrl,
          fileSizeBytes: targetFile.lengthSync(),
        );
        return;
      }

      final tempFile = File('${targetFile.path}.tmp');
      final client = HttpClient();
      try {
        String effectiveUrl = streamUrl;
        if (effectiveUrl.isEmpty) {
          final resolved = await StreamingService.resolveStreamUrl(videoId);
          if (resolved != null && resolved.isNotEmpty) {
            effectiveUrl = resolved;
          }
        }
        if (effectiveUrl.isEmpty) return;

        HttpClientRequest req = await client.getUrl(Uri.parse(effectiveUrl));
        HttpClientResponse res = await req.close();

        // If direct stream URL expired or failed with HTTP 403, attempt re-resolution
        if (res.statusCode != 200 && res.statusCode != 206) {
          final freshUrl = await StreamingService.resolveStreamUrl(videoId);
          if (freshUrl != null && freshUrl.isNotEmpty && freshUrl != effectiveUrl) {
            effectiveUrl = freshUrl;
            req = await client.getUrl(Uri.parse(effectiveUrl));
            res = await req.close();
          }
        }

        if (res.statusCode == 200 || res.statusCode == 206) {
          final sink = tempFile.openWrite();
          await res.pipe(sink);
          await sink.flush();
          await sink.close();

          if (tempFile.existsSync() && tempFile.lengthSync() > 1024) {
            if (targetFile.existsSync()) {
              targetFile.deleteSync();
            }
            tempFile.renameSync(targetFile.path);

            await registerCachedStream(
              videoId: videoId,
              title: title,
              artist: artist,
              thumbnailUrl: thumbnailUrl,
              durationSeconds: durationSeconds,
              filePath: targetFile.path,
              streamUrl: effectiveUrl,
              fileSizeBytes: targetFile.lengthSync(),
            );
            debugPrint(
                '[CachedStreamService] Successfully cached offline stream: $title (${formatBytes(targetFile.lengthSync())})');
          }
        }
      } finally {
        client.close(force: true);
        if (tempFile.existsSync()) {
          try {
            tempFile.deleteSync();
          } catch (_) {}
        }
      }
    } catch (e) {
      debugPrint('[CachedStreamService] Background cache error for $videoId: $e');
    } finally {
      _activeDownloads.remove(videoId);
    }
  }

  /// Scans the cache folder and persisted records, pruning non-existent files.
  Future<List<CachedStreamItem>> refreshCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final rawList = prefs.getStringList(_storageKey) ?? [];

      final loadedItems = <CachedStreamItem>[];
      final seenPaths = <String>{};
      final cacheRoot = cacheDirectory.path.toLowerCase();

      for (final raw in rawList) {
        try {
          final item = CachedStreamItem.fromJson(raw);
          // Prune wrongly-registered local music files: only files inside the
          // dedicated stream-cache folder are legitimate offline streams.
          if (!item.filePath.toLowerCase().startsWith(cacheRoot)) continue;
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
                title: fileName
                    .replaceAll('.mp3', '')
                    .replaceAll('.m4a', '')
                    .replaceAll('.webm', '')
                    .replaceAll('stream_', ''),
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
