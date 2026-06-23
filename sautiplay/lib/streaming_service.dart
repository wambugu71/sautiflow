import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// Resolves YouTube videoIds to streaming MP3 URLs via the Wambugu Music API.
class StreamingService {
  static const _streamUrl1 = String.fromEnvironment(
    'STREAM_URL_1',
    defaultValue: 'https://wambugu-music.vercel.app/download',
  );
  static const _streamUrl2 = String.fromEnvironment('STREAM_URL_2');

  static List<String> get _baseUrls => [
        if (_streamUrl1.isNotEmpty) _streamUrl1,
        if (_streamUrl2.isNotEmpty) _streamUrl2,
      ];

  // ---------------------------------------------------------------------------
  // Single-track resolver (kept for backward compatibility)
  // ---------------------------------------------------------------------------

  /// Resolves a single videoId to a direct MP3 download URL.
  /// Automatically falls back to the other server if the primary fails.
  /// Returns null only if ALL servers fail.
  static Future<String?> resolveStreamUrl(String videoId) async {
    for (int i = 0; i < _baseUrls.length; i++) {
      final url = await _fetchFromServer(_baseUrls[i], videoId);
      if (url != null) return url;
      debugPrint(
          '[streaming] Server ${i + 1} failed for $videoId – trying next…');
    }
    debugPrint('[streaming] All servers failed for $videoId');
    return null;
  }

  // ---------------------------------------------------------------------------
  // Batch resolver – resolves many videoIds concurrently across both servers
  // ---------------------------------------------------------------------------

  /// Resolves a list of videoIds concurrently, splitting work across servers.
  ///
  /// * Odd-indexed tracks go to server 0, even-indexed to server 1.
  /// * If a server is down or returns an error for a track, it automatically
  ///   retries that track on the remaining server(s).
  ///
  /// Returns a list of the same length as [videoIds].
  /// Entries are null where resolution failed on all servers.
  static Future<List<String?>> resolveBatchStreamUrls(
    List<String> videoIds,
  ) async {
    final results = List<String?>.filled(videoIds.length, null);

    // Build futures that resolve each videoId with its assigned server first,
    // then fall back to the other server if needed.
    final futures = List.generate(videoIds.length, (i) async {
      final videoId = videoIds[i];
      // Distribute across servers by index
      final primaryIndex = i % _baseUrls.length;

      // Try primary server
      String? url = await _fetchFromServer(_baseUrls[primaryIndex], videoId);

      // If primary failed, try remaining servers as failover
      if (url == null) {
        for (int j = 1; j < _baseUrls.length; j++) {
          final fallbackIndex = (primaryIndex + j) % _baseUrls.length;
          debugPrint(
            '[streaming] Batch: fallback to server ${fallbackIndex + 1} for $videoId',
          );
          url = await _fetchFromServer(_baseUrls[fallbackIndex], videoId);
          if (url != null) break;
        }
      }

      results[i] = url;
    });

    // Wait for all concurrent requests to complete
    await Future.wait(futures);
    return results;
  }

  // ---------------------------------------------------------------------------
  // Internal helpers
  // ---------------------------------------------------------------------------

  /// Makes a single HTTP request to [baseUrl] for the given [videoId].
  /// Returns the resolved download URL, or null on any failure.
  static Future<String?> _fetchFromServer(
    String baseUrl,
    String videoId,
  ) async {
    final ytUrl = 'https://www.youtube.com/watch?v=$videoId';
    final apiUrl = '$baseUrl?url=${Uri.encodeComponent(ytUrl)}';
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 15);

    try {
      final req = await client.getUrl(Uri.parse(apiUrl));
      req.headers.set('User-Agent', 'SautiPlay/1.0');
      req.headers.set('Accept', 'application/json');

      final res = await req.close();
      if (res.statusCode < 200 || res.statusCode >= 300) {
        debugPrint(
            '[streaming] HTTP ${res.statusCode} from $baseUrl for $videoId');
        return null;
      }

      final body = await res.transform(utf8.decoder).join();
      final json = jsonDecode(body) as Map<String, dynamic>;

      if (json['status'] != true) {
        debugPrint('[streaming] status=false from $baseUrl for $videoId');
        return null;
      }

      final result = json['result'] as Map<String, dynamic>?;
      final downloadUrl = result?['download_url'] as String?;

      if (downloadUrl == null || downloadUrl.isEmpty) {
        debugPrint('[streaming] No download_url from $baseUrl for $videoId');
        return null;
      }

      debugPrint('[streaming] ✓ $videoId → $downloadUrl (via $baseUrl)');
      return downloadUrl;
    } catch (e) {
      debugPrint('[streaming] Error from $baseUrl for $videoId: $e');
      return null;
    } finally {
      client.close(force: true);
    }
  }
}
