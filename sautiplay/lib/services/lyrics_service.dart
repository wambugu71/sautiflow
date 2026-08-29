import 'dart:async';
import 'dart:io';
import 'package:dart_ytmusic_api/dart_ytmusic_api.dart';
import 'package:flutter/foundation.dart';

class LyricsService {
  LyricsService._internal();
  static final LyricsService instance = LyricsService._internal();

  final YTMusic _ytMusic = YTMusic();
  bool _isInitialized = false;

  // In-memory cache to ensure fast retrieval when looping or re-playing tracks
  final Map<String, String> _lyricsCache = {};

  /// Ensures YTMusic client is initialized
  Future<void> init() async {
    if (_isInitialized) return;
    try {
      await _ytMusic.initialize();
      _isInitialized = true;
    } catch (e) {
      debugPrint('[LyricsService] Error initializing YTMusic: $e');
    }
  }

  /// Fast non-blocking internet connectivity check
  Future<bool> isInternetAvailable() async {
    try {
      final result = await InternetAddress.lookup('google.com')
          .timeout(const Duration(seconds: 2));
      return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Cleans raw track title by stripping file extensions, track numbers, and noise tags
  String cleanTrackTitle(String rawTitle) {
    var title = rawTitle.trim();
    if (title.isEmpty) return title;

    // Strip folder paths if path separators are present
    if (title.contains('/') || title.contains(r'\')) {
      final lastSlash = title.lastIndexOf(RegExp(r'[/\\]'));
      if (lastSlash >= 0 && lastSlash < title.length - 1) {
        title = title.substring(lastSlash + 1);
      }
    }

    // Remove file extension (.mp3, .flac, .m4a, .wav, .ogg, .opus, .aac, .wma, .alac, etc.)
    title = title.replaceAll(RegExp(r'\.[a-zA-Z0-9]{2,5}$'), '');

    // Remove leading track numbers e.g. "01 - ", "01. ", "1 - ", "1. ", "01 "
    title = title.replaceAll(RegExp(r'^\d+[\s\.\-_]+'), '');

    // Remove audio/video noise tags like [Official Video], (2013 Remaster), (Audio), [Remastered], etc.
    title = title.replaceAll(
      RegExp(
        r'\s*[\(\[][^\)\]]*\b(?:Official|Remaster(?:ed)?|Audio|Video|Lyrics?|HD|HQ|1080p|4K|Explicit|Clean|Live|Deluxe|Bonus(?:\s+Track)?|Version|Stereo|Mono)\b[^\)\]]*[\)\]]',
        caseSensitive: false,
      ),
      '',
    );

    // Replace underscores with spaces if no spaces exist (e.g. Bohemian_Rhapsody)
    if (!title.contains(' ') && title.contains('_')) {
      title = title.replaceAll('_', ' ');
    }

    return title.trim();
  }

  /// Cleans artist name
  String? cleanArtistName(String? rawArtist) {
    if (rawArtist == null) return null;
    final a = rawArtist.trim();
    if (a.isEmpty ||
        a.toLowerCase() == 'unknown artist' ||
        a.toLowerCase() == '<unknown>' ||
        a.toLowerCase() == 'unknown' ||
        a.toLowerCase() == 'various artists' ||
        a.toLowerCase() == 'various') {
      return null;
    }
    return a;
  }

  /// Parses and decouples artist and title from raw metadata or file names
  (String cleanTitle, String? cleanArtist) parseArtistAndTitle({
    String? rawTitle,
    String? rawArtist,
    String? filePath,
  }) {
    var title = rawTitle?.trim() ?? '';
    var artist = cleanArtistName(rawArtist);

    // If title is empty but filePath is present, extract base filename
    if (title.isEmpty && filePath != null && filePath.isNotEmpty) {
      title = filePath;
    }

    // Strip folder paths if path separators are present
    if (title.contains('/') || title.contains(r'\')) {
      final lastSlash = title.lastIndexOf(RegExp(r'[/\\]'));
      if (lastSlash >= 0 && lastSlash < title.length - 1) {
        title = title.substring(lastSlash + 1);
      }
    }

    // Strip file extension
    title = title.replaceAll(RegExp(r'\.[a-zA-Z0-9]{2,5}$'), '');

    // If artist is unknown and title contains "Artist - Title", extract artist and title
    if (artist == null && title.contains(' - ')) {
      final parts = title.split(' - ');
      if (parts.length >= 2) {
        final possibleArtist = cleanArtistName(parts[0]);
        final possibleTitle = cleanTrackTitle(parts.sublist(1).join(' - '));
        if (possibleArtist != null && possibleTitle.isNotEmpty) {
          return (possibleTitle, possibleArtist);
        }
      }
    }

    return (cleanTrackTitle(title), artist);
  }

  /// Converts TimedLyricsRes into a standard synchronized LRC timestamped string format
  String formatTimedLyricsToLrc(TimedLyricsRes timedLyrics) {
    final sb = StringBuffer();
    for (final data in timedLyrics.timedLyricsData) {
      final line = data.lyricLine?.trim() ?? '';
      final cue = data.cueRange;
      if (cue == null) {
        if (line.isNotEmpty) sb.writeln(line);
        continue;
      }
      final startMs = cue.startTimeMilliseconds;
      final dur = Duration(milliseconds: startMs);
      final mm = dur.inMinutes.remainder(60).toString().padLeft(2, '0');
      final ss = (dur.inSeconds % 60).toString().padLeft(2, '0');
      final xx = ((dur.inMilliseconds % 1000) ~/ 10).toString().padLeft(2, '0');
      sb.writeln('[$mm:$ss.$xx] $line');
    }
    return sb.toString().trim();
  }

  /// Generates timestamped LRC lines for plain text lyrics distributed across duration
  String generateEstimatedLrc(String text, int totalDurationMs) {
    final lines = text
        .split('\n')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    if (lines.isEmpty || totalDurationMs <= 0) return text.trim();

    final msPerLine = (totalDurationMs / lines.length).floor();
    final sb = StringBuffer();
    for (int i = 0; i < lines.length; i++) {
      final currentMs = i * msPerLine;
      final dur = Duration(milliseconds: currentMs);
      final mm = dur.inMinutes.remainder(60).toString().padLeft(2, '0');
      final ss = (dur.inSeconds % 60).toString().padLeft(2, '0');
      final xx = ((dur.inMilliseconds % 1000) ~/ 10).toString().padLeft(2, '0');
      sb.writeln('[$mm:$ss.$xx] ${lines[i]}');
    }
    return sb.toString().trim();
  }

  /// Retrieves lyrics for a track with full fallback logic:
  /// 1. Local companion .lrc / .txt file (if filePath provided)
  /// 2. Memory cache check
  /// 3. Online video ID timed lyrics -> plain lyrics
  /// 4. Local track online lookup via cleaned title + artist (if internet connected)
  Future<String?> fetchLyricsForTrack({
    String? videoId,
    String? title,
    String? artist,
    String? filePath,
    int? durationSeconds,
  }) async {
    // 1. Check for local companion .lrc or .txt file next to local audio file
    if (filePath != null && filePath.isNotEmpty) {
      try {
        final cleanPath = filePath.startsWith('file://')
            ? Uri.tryParse(filePath)?.toFilePath() ?? filePath
            : filePath;
        final lastDot = cleanPath.lastIndexOf('.');
        if (lastDot > 0) {
          final basePath = cleanPath.substring(0, lastDot);
          // Check companion .lrc
          final lrcFile = File('$basePath.lrc');
          if (await lrcFile.exists()) {
            final content = await lrcFile.readAsString();
            if (content.trim().isNotEmpty) {
              debugPrint('[LyricsService] Found companion .lrc file: $basePath.lrc');
              return content.trim();
            }
          }

          // Check companion .txt
          final txtFile = File('$basePath.txt');
          if (await txtFile.exists()) {
            final content = await txtFile.readAsString();
            if (content.trim().isNotEmpty) {
              debugPrint('[LyricsService] Found companion .txt file: $basePath.txt');
              final hasTimestamp = RegExp(r'\[\d+:\d+').hasMatch(content);
              if (!hasTimestamp && durationSeconds != null && durationSeconds > 0) {
                return generateEstimatedLrc(content, durationSeconds * 1000);
              }
              return content.trim();
            }
          }
        }
      } catch (e) {
        debugPrint('[LyricsService] Error checking local .lrc/.txt file: $e');
      }
    }

    await init();

    final isOnlineVideoId = videoId != null &&
        videoId.isNotEmpty &&
        !videoId.contains('/') &&
        !videoId.contains(r'\') &&
        !videoId.contains('.') &&
        RegExp(r'^[a-zA-Z0-9-_]{11}$').hasMatch(videoId);

    // 2. Fetch lyrics using online videoId
    if (isOnlineVideoId) {
      final cacheKey = 'videoId:$videoId';
      if (_lyricsCache.containsKey(cacheKey)) {
        return _lyricsCache[cacheKey];
      }

      try {
        // Try real timed lyrics first
        final timed = await _ytMusic
            .getTimedLyrics(videoId)
            .timeout(const Duration(seconds: 7));
        if (timed != null && timed.timedLyricsData.isNotEmpty) {
          final lrc = formatTimedLyricsToLrc(timed);
          if (lrc.isNotEmpty) {
            _lyricsCache[cacheKey] = lrc;
            return lrc;
          }
        }

        // Fallback to plain lyrics
        final plain = await _ytMusic
            .getLyrics(videoId)
            .timeout(const Duration(seconds: 7));
        if (plain != null && plain.trim().isNotEmpty) {
          final effectiveDurationMs = (durationSeconds != null && durationSeconds > 0)
              ? durationSeconds * 1000
              : 0;
          final result = effectiveDurationMs > 0
              ? generateEstimatedLrc(plain, effectiveDurationMs)
              : plain.trim();
          _lyricsCache[cacheKey] = result;
          return result;
        }
      } catch (e) {
        debugPrint('[LyricsService] Failed online lyrics fetch for $videoId: $e');
      }
    }

    // 3. Local offline song online lookup (or online song without valid videoId)
    final (cleanTitle, cleanArtist) = parseArtistAndTitle(
      rawTitle: title,
      rawArtist: artist,
      filePath: filePath,
    );

    if (cleanTitle.isEmpty) return null;

    final localCacheKey =
        'local:${cleanTitle.toLowerCase()}|${(cleanArtist ?? '').toLowerCase()}';
    if (_lyricsCache.containsKey(localCacheKey)) {
      return _lyricsCache[localCacheKey];
    }

    // Check internet availability before attempting search
    final hasInternet = await isInternetAvailable();
    if (!hasInternet) {
      debugPrint('[LyricsService] No internet connection for local track lookup');
      return null;
    }

    try {
      final query = cleanArtist != null ? '$cleanTitle $cleanArtist' : cleanTitle;
      debugPrint('[LyricsService] Searching YTMusic for track: "$query"');
      var searchResults = await _ytMusic
          .searchSongs(query)
          .timeout(const Duration(seconds: 6));

      // Fallback search with title only if artist-qualified search returned nothing
      if (searchResults.isEmpty && cleanArtist != null) {
        debugPrint('[LyricsService] Retrying search with title only: "$cleanTitle"');
        searchResults = await _ytMusic
            .searchSongs(cleanTitle)
            .timeout(const Duration(seconds: 6));
      }

      if (searchResults.isNotEmpty) {
        final match = searchResults.first;
        final matchId = match.videoId;
        debugPrint(
            '[LyricsService] Match found for track: "${match.name}" by ${match.artist.name} (ID: $matchId)');

        // Fetch timed lyrics for match
        final timed = await _ytMusic
            .getTimedLyrics(matchId)
            .timeout(const Duration(seconds: 6));
        if (timed != null && timed.timedLyricsData.isNotEmpty) {
          final lrc = formatTimedLyricsToLrc(timed);
          if (lrc.isNotEmpty) {
            _lyricsCache[localCacheKey] = lrc;
            _lyricsCache['videoId:$matchId'] = lrc;
            return lrc;
          }
        }

        // Fallback to plain lyrics for match
        final plain = await _ytMusic
            .getLyrics(matchId)
            .timeout(const Duration(seconds: 6));
        if (plain != null && plain.trim().isNotEmpty) {
          final matchDur = match.duration;
          final int effectiveDurationMs =
              (durationSeconds != null && durationSeconds > 0)
                  ? durationSeconds * 1000
                  : ((matchDur != null && matchDur > 0) ? matchDur * 1000 : 0);
          final result = effectiveDurationMs > 0
              ? generateEstimatedLrc(plain, effectiveDurationMs)
              : plain.trim();
          _lyricsCache[localCacheKey] = result;
          _lyricsCache['videoId:$matchId'] = result;
          return result;
        }
      } else {
        debugPrint('[LyricsService] No matching song found on YTMusic for "$query"');
      }
    } catch (e) {
      debugPrint('[LyricsService] Track online lookup error: $e');
    }

    return null;
  }

  /// Clears in-memory lyrics cache
  void clearCache() {
    _lyricsCache.clear();
  }
}
