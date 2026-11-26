import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import 'services/app_state_service.dart';

/// Supported audio streaming quality presets.
enum AudioQualityPreset {
  /// ~48-51 kbps (Opus Tag 249 / AAC Tag 139) - Maximum bandwidth conservation
  low,

  /// ~68-70 kbps (Opus Tag 250) - Balanced mobile streaming
  medium,

  /// ~128 kbps (AAC-LC Tag 140 / Opus) - High fidelity AAC
  high,

  /// ~135-160 kbps (Opus Tag 251) - Maximum YouTube audio bitrate
  audiophile,
}

/// Pure descriptor for stream selection so selection math can be unit-tested
/// without instantiating YouTube's manifest internals.
class StreamCandidate {
  final int index;
  final double bitrateKbps;
  final bool isMp4OrAac;

  const StreamCandidate({
    required this.index,
    required this.bitrateKbps,
    required this.isMp4OrAac,
  });
}

/// Selector utility for filtering and sorting audio streams by quality preset and container.
class AudioStreamSelector {
  /// Selects the best candidate index (into the caller's unsorted list) for
  /// [quality] and [preferAac].
  static int selectCandidateIndex(
    List<StreamCandidate> candidates, {
    AudioQualityPreset quality = AudioQualityPreset.audiophile,
    bool preferAac = false,
  }) {
    if (candidates.isEmpty) {
      throw Exception('No audio-only streams found in manifest.');
    }

    final sorted = List<StreamCandidate>.from(candidates)
      ..sort((a, b) => a.bitrateKbps.compareTo(b.bitrateKbps));

    List<StreamCandidate> pool = sorted;
    if (preferAac) {
      final aac = sorted.where((c) => c.isMp4OrAac).toList();
      if (aac.isNotEmpty) {
        pool = aac;
      }
    }

    switch (quality) {
      case AudioQualityPreset.low:
        return pool.first.index;

      case AudioQualityPreset.medium:
        final mid = pool
            .where((s) => s.bitrateKbps >= 55 && s.bitrateKbps <= 110)
            .toList();
        return (mid.isNotEmpty ? mid.first : pool[pool.length ~/ 2]).index;

      case AudioQualityPreset.high:
        final highAac = pool
            .where((s) => s.isMp4OrAac && s.bitrateKbps >= 100)
            .toList();
        if (highAac.isNotEmpty) return highAac.last.index;
        final highStreams =
            pool.where((s) => s.bitrateKbps >= 110).toList();
        return (highStreams.isNotEmpty ? highStreams.first : pool.last).index;

      case AudioQualityPreset.audiophile:
        return pool.last.index;
    }
  }

  static AudioOnlyStreamInfo selectStream(
    StreamManifest manifest, {
    AudioQualityPreset quality = AudioQualityPreset.audiophile,
    bool preferAac = false,
  }) {
    final audioStreams = manifest.audioOnly.toList();
    if (audioStreams.isEmpty) {
      throw Exception('No audio-only streams found in manifest.');
    }

    final candidates = [
      for (int i = 0; i < audioStreams.length; i++)
        StreamCandidate(
          index: i,
          bitrateKbps: audioStreams[i].bitrate.kiloBitsPerSecond,
          isMp4OrAac: audioStreams[i].container == StreamContainer.mp4 ||
              audioStreams[i].audioCodec.toLowerCase().contains('mp4a'),
        ),
    ];
    final chosenIdx = selectCandidateIndex(
      candidates,
      quality: quality,
      preferAac: preferAac,
    );
    return audioStreams[chosenIdx];
  }
}

/// Metadata model describing a resolved audio stream.
class StreamResolutionResult {
  final String videoId;
  final String url;
  final double bitrateKbps;
  final String container;
  final String audioCodec;
  final int? itag;
  final bool fromCache;
  final bool isFallback;
  final DateTime resolvedAt;
  final DateTime expiresAt;

  const StreamResolutionResult({
    required this.videoId,
    required this.url,
    required this.bitrateKbps,
    required this.container,
    required this.audioCodec,
    this.itag,
    this.fromCache = false,
    this.isFallback = false,
    required this.resolvedAt,
    required this.expiresAt,
  });

  bool get isExpired => DateTime.now().isAfter(expiresAt);
}

/// High-efficiency stream resolver for YouTube audio.
///
/// Features:
/// 1. Direct on-device extraction via [YoutubeExplode] (no third-party proxy required).
/// 2. Audio quality presets (Low, Medium, High, Audiophile).
/// 3. Resilient fallback to hosted scraper API if YouTube blocks or errors.
/// 4. In-memory cache with ~5.5-hour TTL to prevent expired URL playback errors.
/// 5. Concurrency-limited batch lookahead resolution for smooth queueing.
class StreamingService {
  static final YoutubeExplode _ytExplode = YoutubeExplode();

  static const _hostedUrl1 = String.fromEnvironment(
    'STREAM_URL_1',
    defaultValue: 'https://wambugu-music.vercel.app/download',
  );
  static const _hostedUrl2 = String.fromEnvironment('STREAM_URL_2');

  static List<String> get _hostedBaseUrls => [
        if (_hostedUrl1.isNotEmpty) _hostedUrl1,
        if (_hostedUrl2.isNotEmpty) _hostedUrl2,
      ];

  // In-memory stream cache keyed by "videoId_quality_preferAac"
  static final Map<String, StreamResolutionResult> _cache = {};

  static String _cacheKey(
      String videoId, AudioQualityPreset quality, bool preferAac) {
    return '${videoId}_${quality.name}_$preferAac';
  }

  /// Resolves a single videoId to a direct streaming URL string.
  ///
  /// Backwards-compatible signature used by `main.dart` and player controllers.
  static Future<String?> resolveStreamUrl(
    String videoId, {
    AudioQualityPreset? quality,
    bool? preferAac,
    bool allowFallback = true,
  }) async {
    final result = await resolveStreamDetailed(
      videoId,
      quality: quality,
      preferAac: preferAac,
      allowFallback: allowFallback,
    );
    return result?.url;
  }

  /// Resolves a single videoId with detailed metadata, quality options, and error resilience.
  static Future<StreamResolutionResult?> resolveStreamDetailed(
    String videoId, {
    AudioQualityPreset? quality,
    bool? preferAac,
    bool allowFallback = true,
  }) async {
    if (videoId.isEmpty) return null;

    // Load active settings if not explicitly specified
    final activeQuality =
        quality ?? await AppStateService.instance.loadStreamingQualityPreset();
    final activePreferAac =
        preferAac ?? await AppStateService.instance.loadPreferNativeAac();
    final isFallbackEnabled = allowFallback &&
        await AppStateService.instance.loadEnableHostedFallback();

    final key = _cacheKey(videoId, activeQuality, activePreferAac);

    // 1. Check in-memory cache with expiration check (~5.5 hours)
    final cached = _cache[key];
    if (cached != null && !cached.isExpired) {
      debugPrint(
          '[StreamingService] ✓ Cache hit for $videoId (${cached.bitrateKbps.toStringAsFixed(1)} kbps)');
      return cached;
    }

    // 2. Primary: Direct on-device extraction via youtube_explode_dart (with transient retry)
    YoutubeExplode client = _ytExplode;
    bool ownsClient = false;
    try {
      for (int attempt = 1; attempt <= 2; attempt++) {
        try {
          final targetVideoId = VideoId(videoId);
          final manifest = await client.videos.streams
              .getManifest(targetVideoId)
              .timeout(const Duration(seconds: 25));
          final streamInfo = AudioStreamSelector.selectStream(
            manifest,
            quality: activeQuality,
            preferAac: activePreferAac,
          );

          final now = DateTime.now();
          // Direct YouTube URLs typically expire after 6 hours; set safety TTL to 5.5 hours
          final expiresAt = now.add(const Duration(hours: 5, minutes: 30));

          final result = StreamResolutionResult(
            videoId: videoId,
            url: streamInfo.url.toString(),
            bitrateKbps: streamInfo.bitrate.kiloBitsPerSecond,
            container: streamInfo.container.name,
            audioCodec: streamInfo.audioCodec,
            itag: streamInfo.tag,
            fromCache: false,
            isFallback: false,
            resolvedAt: now,
            expiresAt: expiresAt,
          );

          _cache[key] = result;
          debugPrint(
              '[StreamingService] ✓ Resolved $videoId (${streamInfo.bitrate.kiloBitsPerSecond.toStringAsFixed(1)} kbps)');
          return result;
        } catch (e) {
          debugPrint(
              '[StreamingService] Direct extraction attempt $attempt failed for $videoId: $e');

          // Retry with an isolated fresh client instead of closing the shared
          // static _ytExplode underneath concurrent batch lookahead futures.
          if (attempt == 1 &&
              (e is SocketException ||
                  e is HandshakeException ||
                  e is TimeoutException)) {
            if (ownsClient) {
              try {
                client.close();
              } catch (_) {}
            }
            client = YoutubeExplode();
            ownsClient = true;
            await Future.delayed(const Duration(milliseconds: 1200));
          } else {
            break;
          }
        }
      }
    } finally {
      if (ownsClient) {
        try {
          client.close();
        } catch (_) {}
      }
    }

    // 3. Fallback: Hosted scraping backend if enabled
    if (isFallbackEnabled) {
      debugPrint(
          '[StreamingService] ⚠️ Attempting hosted fallback for $videoId...');
      for (int i = 0; i < _hostedBaseUrls.length; i++) {
        final fallbackUrl =
            await _fetchFromHostedServer(_hostedBaseUrls[i], videoId);
        if (fallbackUrl != null) {
          final now = DateTime.now();
          final result = StreamResolutionResult(
            videoId: videoId,
            url: fallbackUrl,
            bitrateKbps: 128.0,
            container: 'mp3',
            audioCodec: 'mp3',
            fromCache: false,
            isFallback: true,
            resolvedAt: now,
            expiresAt: now.add(const Duration(hours: 3)),
          );
          _cache[key] = result;
          debugPrint(
              '[StreamingService] ✓ Fallback resolved $videoId from server ${i + 1}');
          return result;
        }
      }
    }

    debugPrint(
        '[StreamingService] ❌ All resolution methods failed for $videoId');
    return null;
  }

  /// Downloads audio for [videoId] directly to [targetFile] via chunked parallel streams.
  ///
  /// Uses [YoutubeExplode.videos.streamsClient] to bypass YouTube's single-connection throttling.
  /// Returns the stream container format (e.g. 'webm' or 'm4a') if successful, or null on failure.
  static Future<String?> downloadAudioStreamToFile({
    required String videoId,
    required File targetFile,
    AudioQualityPreset? quality,
    bool? preferAac,
  }) async {
    final activeQuality =
        quality ?? await AppStateService.instance.loadStreamingQualityPreset();
    final activePreferAac =
        preferAac ?? await AppStateService.instance.loadPreferNativeAac();

    YoutubeExplode client = _ytExplode;
    bool ownsClient = false;
    try {
      for (int attempt = 1; attempt <= 2; attempt++) {
        try {
          final targetVideoId = VideoId(videoId);
          final manifest = await client.videos.streams
              .getManifest(targetVideoId)
              .timeout(const Duration(seconds: 25));
          final streamInfo = AudioStreamSelector.selectStream(
            manifest,
            quality: activeQuality,
            preferAac: activePreferAac,
          );

          final sink = targetFile.openWrite();
          await client.videos.streamsClient.get(streamInfo).pipe(sink);
          await sink.flush();
          await sink.close();

          if (targetFile.existsSync() && targetFile.lengthSync() > 1024) {
            final container = streamInfo.container.name;
            return container == 'mp4' ? 'm4a' : container;
          }
        } catch (e) {
          debugPrint(
              '[StreamingService] Direct download attempt $attempt failed for $videoId: $e');
          if (attempt == 1 &&
              (e is SocketException ||
                  e is HandshakeException ||
                  e is TimeoutException)) {
            if (ownsClient) {
              try {
                client.close();
              } catch (_) {}
            }
            client = YoutubeExplode();
            ownsClient = true;
            await Future.delayed(const Duration(milliseconds: 1200));
          } else {
            break;
          }
        }
      }
    } finally {
      if (ownsClient) {
        try {
          client.close();
        } catch (_) {}
      }
    }
    return null;
  }

  /// Concurrently resolves a list of videoIds with concurrency-controlled pooling.
  ///
  /// Preserves list order and returns `null` for failed tracks.
  static Future<List<String?>> resolveBatchStreamUrls(
    List<String> videoIds, {
    AudioQualityPreset? quality,
    bool? preferAac,
    bool allowFallback = true,
    int maxConcurrent = 4,
  }) async {
    if (videoIds.isEmpty) return [];

    final results = List<String?>.filled(videoIds.length, null);
    final activeQuality =
        quality ?? await AppStateService.instance.loadStreamingQualityPreset();
    final activePreferAac =
        preferAac ?? await AppStateService.instance.loadPreferNativeAac();

    // Check cache for all tracks first
    final unresolvedIndices = <int>[];
    for (int i = 0; i < videoIds.length; i++) {
      final key = _cacheKey(videoIds[i], activeQuality, activePreferAac);
      final cached = _cache[key];
      if (cached != null && !cached.isExpired) {
        results[i] = cached.url;
      } else {
        unresolvedIndices.add(i);
      }
    }

    if (unresolvedIndices.isEmpty) {
      return results;
    }

    // Resolve remaining items in pooled batches
    for (int chunkStart = 0;
        chunkStart < unresolvedIndices.length;
        chunkStart += maxConcurrent) {
      final chunkEnd = (chunkStart + maxConcurrent < unresolvedIndices.length)
          ? chunkStart + maxConcurrent
          : unresolvedIndices.length;

      final chunkIndices = unresolvedIndices.sublist(chunkStart, chunkEnd);
      final futures = chunkIndices.map((idx) async {
        final res = await resolveStreamDetailed(
          videoIds[idx],
          quality: activeQuality,
          preferAac: activePreferAac,
          allowFallback: allowFallback,
        );
        results[idx] = res?.url;
      });

      await Future.wait(futures);
    }

    return results;
  }

  /// Clears in-memory URL cache.
  static void clearCache() {
    _cache.clear();
  }

  /// Evicts cached stream entries for a specific [videoId].
  static void evictFromCache(String videoId) {
    if (videoId.isEmpty) return;
    _cache.removeWhere(
        (key, value) => value.videoId == videoId || key.startsWith('${videoId}_'));
  }

  /// Closes underlying HTTP and Explode clients.
  static void dispose() {
    _cache.clear();
    try {
      _ytExplode.close();
    } catch (_) {}
  }

  // ---------------------------------------------------------------------------
  // Internal Hosted Server Fallback Helper
  // ---------------------------------------------------------------------------

  static Future<String?> _fetchFromHostedServer(
    String baseUrl,
    String videoId,
  ) async {
    final ytUrl = 'https://www.youtube.com/watch?v=$videoId';
    final apiUrl = '$baseUrl?url=${Uri.encodeComponent(ytUrl)}';
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 15);

    try {
      final req = await client
          .getUrl(Uri.parse(apiUrl))
          .timeout(const Duration(seconds: 15));
      req.headers.set('User-Agent', 'SautiPlay/1.0');
      req.headers.set('Accept', 'application/json');

      final res = await req.close().timeout(const Duration(seconds: 15));
      if (res.statusCode < 200 || res.statusCode >= 300) {
        return null;
      }

      final body = await res
          .transform(utf8.decoder)
          .join()
          .timeout(const Duration(seconds: 15));
      final json = jsonDecode(body) as Map<String, dynamic>;

      if (json['status'] != true) {
        return null;
      }

      final result = json['result'] as Map<String, dynamic>?;
      final downloadUrl = result?['download_url'] as String?;

      if (downloadUrl == null || downloadUrl.isEmpty) {
        return null;
      }

      return downloadUrl;
    } catch (e) {
      debugPrint('[StreamingService] Error from fallback $baseUrl: $e');
      return null;
    } finally {
      client.close(force: true);
    }
  }
}
