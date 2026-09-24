import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
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

  final ValueNotifier<Set<String>> activeDownloadsNotifier =
      ValueNotifier<Set<String>>(<String>{});

  bool isDownloading(String videoId) => _activeDownloads.contains(videoId);

  bool _isInitialized = false;

  Directory get cacheDirectory {
    final tempDir = Directory.systemTemp;
    String basePath;
    try {
      basePath = tempDir.resolveSymbolicLinksSync();
    } catch (_) {
      basePath = tempDir.path;
    }
    return Directory(
      '$basePath${Platform.pathSeparator}miniaudiodart_stream_cache',
    );
  }

  /// Checks whether a given path points to an existing file in the stream cache directory.
  ///
  /// Resilient against Windows 8.3 short paths (e.g. WAMBUG~1 vs wambugukinyua)
  /// and path separator differences, while strictly rejecting any local user tracks.
  bool _isCacheFile(String filePath) {
    if (filePath.isEmpty) return false;
    final lower = filePath.toLowerCase();
    if (!lower.contains('miniaudiodart_stream_cache')) return false;
    return File(filePath).existsSync();
  }

  /// Searches the cache directory for any existing cached audio file for [videoId].
  File? findExistingCacheFile(String videoId) {
    if (videoId.isEmpty) return null;
    try {
      final dir = cacheDirectory;
      if (!dir.existsSync()) return null;
      for (final ext in ['webm', 'm4a', 'mp3', 'opus']) {
        final f =
            File('${dir.path}${Platform.pathSeparator}stream_$videoId.$ext');
        if (f.existsSync() && f.lengthSync() > 1024) {
          return f;
        }
      }
    } catch (_) {}
    return null;
  }

  /// Initializes the service, loading persisted metadata and verifying files on disk.
  Future<void> init() async {
    if (_isInitialized) return;
    _isInitialized = true;
    await refreshCache();
  }

  /// Looks up whether an audio stream is already downloaded and cached locally.
  CachedStreamItem? getCachedItem(String videoId) {
    if (videoId.isEmpty) return null;
    for (final item in cachedStreamsNotifier.value) {
      if (item.videoId == videoId && File(item.filePath).existsSync()) {
        return item;
      }
    }
    // Also check physical disk in case metadata was not yet refreshed
    final physical = findExistingCacheFile(videoId);
    if (physical != null) {
      return CachedStreamItem(
        videoId: videoId,
        title: 'Stream $videoId',
        artist: 'Online Stream',
        durationSeconds: 0,
        filePath: physical.path,
        fileSizeBytes: physical.lengthSync(),
        cachedAt: physical.lastModifiedSync(),
      );
    }
    return null;
  }

  /// Downloads an online audio stream in the background, saves it to disk cache,
  /// and automatically registers it for the Library "Cached Online Streams" playlist.
  ///
  /// Returns `true` if the stream was successfully cached, `false` otherwise.
  Future<bool> cacheStreamInBackground({
    required String videoId,
    required String streamUrl,
    required String title,
    required String artist,
    String? thumbnailUrl,
    int? durationSeconds,
  }) async {
    if (videoId.isEmpty) return false;
    if (_activeDownloads.contains(videoId)) return false;
    _activeDownloads.add(videoId);
    activeDownloadsNotifier.value = Set<String>.unmodifiable(_activeDownloads);

    try {
      final dir = cacheDirectory;
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }

      // If valid file already exists on disk, register and return immediately
      final existingFile = findExistingCacheFile(videoId);
      if (existingFile != null) {
        await registerCachedStream(
          videoId: videoId,
          title: title,
          artist: artist,
          thumbnailUrl: thumbnailUrl,
          durationSeconds: durationSeconds,
          filePath: existingFile.path,
          streamUrl: streamUrl,
          fileSizeBytes: existingFile.lengthSync(),
        );
        return true;
      }

      final tempFile = File(
        '${dir.path}${Platform.pathSeparator}stream_${videoId}_temp_${DateTime.now().millisecondsSinceEpoch}.tmp',
      );
      String? downloadedContainer;

      // 1. Primary: Fast direct chunked download via YoutubeExplode
      final isYoutubeId = !videoId.contains('/') &&
          !videoId.contains(r'\') &&
          !videoId.startsWith('http');
      if (isYoutubeId) {
        downloadedContainer = await StreamingService.downloadAudioStreamToFile(
          videoId: videoId,
          targetFile: tempFile,
        );
      }

      // 2. Fallback: Download via HttpClient if direct chunked download failed or not a YouTube ID
      if (downloadedContainer == null) {
        String effectiveUrl = streamUrl;
        if (effectiveUrl.isEmpty && isYoutubeId) {
          effectiveUrl = await StreamingService.resolveStreamUrl(videoId) ?? '';
        }
        if (effectiveUrl.isNotEmpty) {
          final clientSuccess =
              await _downloadViaHttpClient(effectiveUrl, tempFile);
          if (clientSuccess) {
            final lower = effectiveUrl.toLowerCase();
            if (lower.contains('m4a') || lower.contains('mp4')) {
              downloadedContainer = 'm4a';
            } else if (lower.contains('mp3')) {
              downloadedContainer = 'mp3';
            } else {
              downloadedContainer = 'webm';
            }
          }
        }
      }

      if (downloadedContainer != null &&
          tempFile.existsSync() &&
          tempFile.lengthSync() > 1024) {
        final targetFile = File(
          '${dir.path}${Platform.pathSeparator}stream_$videoId.$downloadedContainer',
        );
        if (targetFile.existsSync()) {
          try {
            targetFile.deleteSync();
          } catch (_) {}
        }
        tempFile.renameSync(targetFile.path);

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
        debugPrint(
            '[CachedStreamService] Successfully cached offline stream: $title (${formatBytes(targetFile.lengthSync())})');
        return true;
      }

      return false;
    } catch (e) {
      debugPrint('[CachedStreamService] Background cache error for $videoId: $e');
      return false;
    } finally {
      _activeDownloads.remove(videoId);
      activeDownloadsNotifier.value = Set<String>.unmodifiable(_activeDownloads);
    }
  }

  Future<bool> _downloadViaHttpClient(String url, File tempFile) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
    try {
      final req = await client.getUrl(Uri.parse(url));
      final res = await req.close();
      if (res.statusCode == 200 || res.statusCode == 206) {
        final sink = tempFile.openWrite();
        await res.pipe(sink);
        await sink.flush();
        await sink.close();
        return tempFile.existsSync() && tempFile.lengthSync() > 1024;
      }
      return false;
    } catch (e) {
      debugPrint('[CachedStreamService] HttpClient download error: $e');
      return false;
    } finally {
      client.close(force: true);
      if (!tempFile.existsSync() || tempFile.lengthSync() <= 1024) {
        try {
          if (tempFile.existsSync()) tempFile.deleteSync();
        } catch (_) {}
      }
    }
  }

  /// Scans the cache folder and persisted records, pruning non-existent files.
  Future<List<CachedStreamItem>> refreshCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final rawList = prefs.getStringList(_storageKey) ?? [];

      final loadedItems = <CachedStreamItem>[];
      final seenVideoIds = <String>{};
      final seenFileNames = <String>{};

      for (final raw in rawList) {
        try {
          final item = CachedStreamItem.fromJson(raw);
          // Only files inside the dedicated stream-cache folder that physically exist
          if (!_isCacheFile(item.filePath)) continue;
          loadedItems.add(item);
          seenVideoIds.add(item.videoId);
          seenFileNames.add(p.basename(item.filePath).toLowerCase());
        } catch (_) {}
      }

      // Also scan directory in case new stream files were written directly
      if (cacheDirectory.existsSync()) {
        final dirFiles = cacheDirectory.listSync().whereType<File>();
        for (final file in dirFiles) {
          if (!file.path.endsWith('.tmp')) {
            final size = file.existsSync() ? file.lengthSync() : 0;
            if (size > 1024) {
              final fileName = p.basename(file.path);
              final fileNameLower = fileName.toLowerCase();
              final baseWithoutExt = p.basenameWithoutExtension(file.path);
              final cleanVideoId = baseWithoutExt.startsWith('stream_')
                  ? baseWithoutExt.substring(7)
                  : baseWithoutExt;

              if (!seenFileNames.contains(fileNameLower) &&
                  !seenVideoIds.contains(cleanVideoId)) {
                loadedItems.add(CachedStreamItem(
                  videoId: cleanVideoId,
                  title: 'Stream $cleanVideoId',
                  artist: 'Online Stream',
                  thumbnailUrl: null,
                  durationSeconds: 0,
                  filePath: file.path,
                  streamUrl: null,
                  fileSizeBytes: size,
                  cachedAt: file.lastModifiedSync(),
                ));
                seenVideoIds.add(cleanVideoId);
                seenFileNames.add(fileNameLower);
              }
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

      final fileName = p.basename(filePath).toLowerCase();
      final current = List<CachedStreamItem>.from(cachedStreamsNotifier.value);
      current.removeWhere((item) =>
          item.videoId == videoId ||
          item.filePath == filePath ||
          p.basename(item.filePath).toLowerCase() == fileName);

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

      final fileName = p.basename(filePath).toLowerCase();
      final current = List<CachedStreamItem>.from(cachedStreamsNotifier.value)
        ..removeWhere((item) =>
            item.filePath == filePath ||
            p.basename(item.filePath).toLowerCase() == fileName);

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
