import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
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

  static Directory? _persistentDownloadsDir;

  /// Permanent directory for explicit user downloads (e.g. from Now Playing screen).
  /// Stored in [getApplicationDocumentsDirectory] so it is immune to OS "Clear Cache".
  Directory get downloadsDirectory {
    if (_persistentDownloadsDir != null) {
      return _persistentDownloadsDir!;
    }
    final tempDir = Directory.systemTemp;
    return Directory(
        '${tempDir.path}${Platform.pathSeparator}sautiplay_downloads');
  }

  /// Volatile directory for transient stream buffer caching during playback.
  /// Stored in system temp directory so the OS can safely reclaim space if needed.
  Directory get streamCacheDirectory {
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

  /// Default directory for general lookups.
  Directory get cacheDirectory => downloadsDirectory;

  /// Helper to check if a file for [videoId] exists in a specific directory.
  File? _findFileInDir(Directory dir, String videoId) {
    if (videoId.isEmpty || !dir.existsSync()) return null;
    for (final ext in ['webm', 'm4a', 'mp3', 'opus']) {
      final f = File('${dir.path}${Platform.pathSeparator}stream_$videoId.$ext');
      if (f.existsSync() && f.lengthSync() > 1024) {
        return f;
      }
    }
    return null;
  }

  /// Checks whether a given path points to an existing file in either the downloads
  /// or stream cache directory.
  bool _isCacheFile(String filePath) {
    if (filePath.isEmpty) return false;
    final lower = filePath.toLowerCase();
    if (!lower.contains('miniaudiodart_stream_cache') &&
        !lower.contains('sautiplay_downloads')) return false;
    return File(filePath).existsSync();
  }

  /// Searches first in permanent downloads, then in transient stream cache.
  File? findExistingCacheFile(String videoId) {
    if (videoId.isEmpty) return null;
    try {
      // 1. Check permanent user downloads directory first
      final downloadFile = _findFileInDir(downloadsDirectory, videoId);
      if (downloadFile != null) return downloadFile;

      // 2. Check transient stream cache directory second
      final streamFile = _findFileInDir(streamCacheDirectory, videoId);
      if (streamFile != null) return streamFile;
    } catch (_) {}
    return null;
  }

  /// Initializes the service, ensuring both downloads (documents) and stream cache
  /// directories are prepared, and refreshes the cache index.
  Future<void> init() async {
    if (_isInitialized) return;
    _isInitialized = true;
    try {
      final docsDir = await getApplicationDocumentsDirectory();
      _persistentDownloadsDir = Directory(
        p.join(docsDir.path, 'sautiplay_downloads'),
      );
      if (!_persistentDownloadsDir!.existsSync()) {
        await _persistentDownloadsDir!.create(recursive: true);
      }

      // Ensure transient stream cache dir exists
      if (!streamCacheDirectory.existsSync()) {
        await streamCacheDirectory.create(recursive: true);
      }
    } catch (e) {
      debugPrint('[CachedStreamService] Error initializing storage dirs: $e');
    }
    await refreshCache();
  }

  /// Looks up whether an audio stream is already downloaded or cached locally.
  CachedStreamItem? getCachedItem(String videoId) {
    if (videoId.isEmpty) return null;
    for (final item in cachedStreamsNotifier.value) {
      if (item.videoId == videoId) {
        if (File(item.filePath).existsSync()) return item;
        final inDocs =
            File(p.join(downloadsDirectory.path, p.basename(item.filePath)));
        if (inDocs.existsSync()) return item;
        final inTemp =
            File(p.join(streamCacheDirectory.path, p.basename(item.filePath)));
        if (inTemp.existsSync()) return item;
      }
    }
    // Also check physical disk in case metadata was not yet refreshed
    final physical = findExistingCacheFile(videoId);
    if (physical != null) {
      final isDownload =
          physical.path.toLowerCase().contains('sautiplay_downloads');
      return CachedStreamItem(
        videoId: videoId,
        title: 'Stream $videoId',
        artist: isDownload ? 'Offline Download' : 'Cached Stream',
        durationSeconds: 0,
        filePath: physical.path,
        fileSizeBytes: physical.lengthSync(),
        cachedAt: physical.lastModifiedSync(),
        isUserDownload: isDownload,
      );
    }
    return null;
  }

  /// Saves an online stream to disk.
  /// - If [isUserDownload] is `true` (e.g. user tapped Download on Now Playing),
  ///   it saves to the Documents directory ([downloadsDirectory]), making it permanent
  ///   and immune to OS cache clearing until the user deletes it.
  /// - If [isUserDownload] is `false` (passive playback streaming buffer),
  ///   it saves to the Temporary directory ([streamCacheDirectory]) so OS can clear it.
  Future<bool> cacheStreamInBackground({
    required String videoId,
    required String streamUrl,
    required String title,
    required String artist,
    String? thumbnailUrl,
    int? durationSeconds,
    bool isUserDownload = false,
  }) async {
    if (videoId.isEmpty) return false;
    if (_activeDownloads.contains(videoId)) return false;
    _activeDownloads.add(videoId);
    activeDownloadsNotifier.value = Set<String>.unmodifiable(_activeDownloads);

    try {
      final targetDir =
          isUserDownload ? downloadsDirectory : streamCacheDirectory;
      if (!targetDir.existsSync()) {
        targetDir.createSync(recursive: true);
      }

      // If valid file already exists in target directory, register and return immediately
      final existingInTarget = _findFileInDir(targetDir, videoId);
      if (existingInTarget != null) {
        await registerCachedStream(
          videoId: videoId,
          title: title,
          artist: artist,
          thumbnailUrl: thumbnailUrl,
          durationSeconds: durationSeconds,
          filePath: existingInTarget.path,
          streamUrl: streamUrl,
          fileSizeBytes: existingInTarget.lengthSync(),
          isUserDownload: isUserDownload,
        );
        return true;
      }

      // Optimization: If user requested download and song was already in stream cache,
      // promote it instantly to Documents dir without re-downloading!
      if (isUserDownload) {
        final existingInTemp = _findFileInDir(streamCacheDirectory, videoId);
        if (existingInTemp != null &&
            existingInTemp.existsSync() &&
            existingInTemp.lengthSync() > 1024) {
          final ext = p.extension(existingInTemp.path);
          final destFile = File(
            '${targetDir.path}${Platform.pathSeparator}stream_$videoId$ext',
          );
          existingInTemp.copySync(destFile.path);
          await registerCachedStream(
            videoId: videoId,
            title: title,
            artist: artist,
            thumbnailUrl: thumbnailUrl,
            durationSeconds: durationSeconds,
            filePath: destFile.path,
            streamUrl: streamUrl,
            fileSizeBytes: destFile.lengthSync(),
            isUserDownload: true,
          );
          debugPrint(
              '[CachedStreamService] Promoted stream cache to permanent download: $title');
          return true;
        }
      }

      final tempFile = File(
        '${targetDir.path}${Platform.pathSeparator}stream_${videoId}_temp_${DateTime.now().millisecondsSinceEpoch}.tmp',
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
          '${targetDir.path}${Platform.pathSeparator}stream_$videoId.$downloadedContainer',
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
          isUserDownload: isUserDownload,
        );
        debugPrint(
            '[CachedStreamService] Successfully saved ${isUserDownload ? "permanent download" : "stream cache"}: $title (${formatBytes(targetFile.lengthSync())})');
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
          // Resilient file resolution: if stored path moved or container changed,
          // check if it exists in downloadsDirectory or streamCacheDirectory by file name
          String resolvedPath = item.filePath;
          if (!File(resolvedPath).existsSync()) {
            final fileName = p.basename(item.filePath);
            final inDocs = File(p.join(downloadsDirectory.path, fileName));
            final inTemp = File(p.join(streamCacheDirectory.path, fileName));
            if (inDocs.existsSync()) {
              resolvedPath = inDocs.path;
            } else if (inTemp.existsSync()) {
              resolvedPath = inTemp.path;
            }
          }

          // Only files inside the dedicated cache/downloads folders that physically exist
          if (!_isCacheFile(resolvedPath)) continue;

          final isDownload = item.isUserDownload ||
              resolvedPath.toLowerCase().contains('sautiplay_downloads');

          final effectiveItem = (resolvedPath == item.filePath &&
                  isDownload == item.isUserDownload)
              ? item
              : CachedStreamItem(
                  videoId: item.videoId,
                  title: item.title,
                  artist: item.artist,
                  thumbnailUrl: item.thumbnailUrl,
                  durationSeconds: item.durationSeconds,
                  filePath: resolvedPath,
                  streamUrl: item.streamUrl,
                  fileSizeBytes: item.fileSizeBytes,
                  cachedAt: item.cachedAt,
                  isUserDownload: isDownload,
                );

          loadedItems.add(effectiveItem);
          seenVideoIds.add(effectiveItem.videoId);
          seenFileNames.add(p.basename(effectiveItem.filePath).toLowerCase());
        } catch (_) {}
      }

      // Also scan disk directories for any tracks
      for (final dir in [downloadsDirectory, streamCacheDirectory]) {
        if (dir.existsSync()) {
          final isDocsDir = dir.path == downloadsDirectory.path;
          final dirFiles = dir.listSync().whereType<File>();
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
                    artist: isDocsDir ? 'Offline Download' : 'Cached Stream',
                    thumbnailUrl: null,
                    durationSeconds: 0,
                    filePath: file.path,
                    streamUrl: null,
                    fileSizeBytes: size,
                    cachedAt: file.lastModifiedSync(),
                    isUserDownload: isDocsDir,
                  ));
                  seenVideoIds.add(cleanVideoId);
                  seenFileNames.add(fileNameLower);
                }
              }
            }
          }
        }
      }

      // Sort: permanent downloads first, then newest
      loadedItems.sort((a, b) {
        if (a.isUserDownload != b.isUserDownload) {
          return a.isUserDownload ? -1 : 1;
        }
        return b.cachedAt.compareTo(a.cachedAt);
      });

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
    bool? isUserDownload,
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

      final isDownload = isUserDownload ??
          filePath.toLowerCase().contains('sautiplay_downloads');

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
        isUserDownload: isDownload,
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

  /// Clears stream cache files.
  /// If [clearUserDownloads] is false (default), only the volatile stream cache is deleted,
  /// preserving all user downloaded offline songs.
  Future<void> clearAllCache({bool clearUserDownloads = false}) async {
    try {
      if (streamCacheDirectory.existsSync()) {
        final entities = streamCacheDirectory.listSync();
        for (final entity in entities) {
          try {
            entity.deleteSync(recursive: true);
          } catch (_) {}
        }
      }

      if (clearUserDownloads && downloadsDirectory.existsSync()) {
        final entities = downloadsDirectory.listSync();
        for (final entity in entities) {
          try {
            entity.deleteSync(recursive: true);
          } catch (_) {}
        }
      }

      await refreshCache();
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
