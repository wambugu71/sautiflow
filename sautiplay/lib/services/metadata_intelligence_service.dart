import 'package:path/path.dart' as p;

import '../database/app_database.dart';
import '../models/local_song_item.dart';
import 'automix_analysis_service.dart';

class InferredMetadata {
  final String? title;
  final String? artist;
  final String? album;
  final int? trackNumber;
  final int? discNumber;
  final int? year;
  final double confidence;
  final String matchedPattern;

  const InferredMetadata({
    this.title,
    this.artist,
    this.album,
    this.trackNumber,
    this.discNumber,
    this.year,
    required this.confidence,
    required this.matchedPattern,
  });

  bool get hasAny =>
      title != null ||
      artist != null ||
      album != null ||
      trackNumber != null ||
      discNumber != null ||
      year != null;
}

class MetadataIntelligenceService {
  MetadataIntelligenceService._();
  static final MetadataIntelligenceService instance =
      MetadataIntelligenceService._();

  static final RegExp _noiseBracketRe = RegExp(
    r'\s*[\[\(](?:320\s*kbps|256\s*kbps|192\s*kbps|128\s*kbps|flac|mp3|wav|alac|aac|m4a|hi-?res|24bit|16bit|official\s*(?:audio|video|lyric\s*video|music\s*video)|lyrics?|hd|hq|remastered(?:\s*\d{4})?)[\]\)]',
    caseSensitive: false,
  );
  static final RegExp _yearRe = RegExp(r'\b(19\d{2}|20\d{2})\b');
  static final RegExp _discFolderRe =
      RegExp(r'^(?:cd|disc|disk)\s*(\d+)$', caseSensitive: false);
  static final RegExp _trackPrefixRe =
      RegExp(r'^(\d{1,3})\s*[-._)\]]+\s*(.+)$');
  static final RegExp _discTrackPrefixRe =
      RegExp(r'^(\d)[.-](\d{2})\s*[-._)\]]*\s*(.+)$');
  static final RegExp _artistTitleRe = RegExp(r'^(.+?)\s+-\s+(.+)$');
  static final RegExp _albumYearPrefixRe =
      RegExp(r'^(\d{4})\s*[-._]\s*(.+)$');
  static final RegExp _albumYearSuffixRe =
      RegExp(r'^(.+?)\s*[\(\[](\d{4})[\)\]]$');

  static const Set<String> _preserveUpper = {
    'DJ', 'MC', 'EP', 'LP', 'VIP', 'UK', 'USA', 'NYC', 'LA', 'II', 'III', 'IV',
    'RMX', 'OST', 'BBC', 'R&B', 'EDM', 'IDM',
  };
  static const Set<String> _lowerParticles = {
    'a', 'an', 'and', 'as', 'at', 'but', 'by', 'for', 'in', 'nor', 'of',
    'on', 'or', 'the', 'to', 'vs', 'vs.', 'feat.', 'ft.',
  };

  /// Cleans common rip/download noise from a filename or tag string.
  String cleanNoise(String raw) {
    var s = raw.replaceAll('_', ' ').trim();
    s = s.replaceAll(_noiseBracketRe, '');
    s = s.replaceAll(RegExp(r'\s{2,}'), ' ').trim();
    return s;
  }

  /// Smart title-casing that preserves DJ/EP/ROMAN numerals and minor words.
  String normalizeTitleCase(String raw) {
    final cleaned = cleanNoise(raw);
    if (cleaned.isEmpty) return cleaned;
    final words = cleaned.split(RegExp(r'\s+'));
    final out = <String>[];
    for (int i = 0; i < words.length; i++) {
      final w = words[i];
      final upper = w.toUpperCase();
      if (_preserveUpper.contains(upper)) {
        out.add(upper);
        continue;
      }
      final lower = w.toLowerCase();
      if (i > 0 && i < words.length - 1 && _lowerParticles.contains(lower)) {
        out.add(lower);
        continue;
      }
      if (w.length == 1) {
        out.add(w.toUpperCase());
      } else {
        out.add(w[0].toUpperCase() + w.substring(1).toLowerCase());
      }
    }
    return out.join(' ');
  }

  /// Infers metadata from the file's path and parent folder hierarchy.
  InferredMetadata inferFromPath(String filePath) {
    final realPath = filePath.split('#').first;
    final baseName = cleanNoise(p.basenameWithoutExtension(realPath));
    final segments = p.split(p.dirname(realPath));

    int? discNumber;
    String? albumFolder;
    String? artistFolder;

    if (segments.isNotEmpty) {
      var idx = segments.length - 1;
      final lastFolder = segments[idx];
      final discMatch = _discFolderRe.firstMatch(lastFolder.trim());
      if (discMatch != null) {
        discNumber = int.tryParse(discMatch.group(1)!);
        idx--;
      }
      if (idx >= 0) {
        final candidateAlbum = segments[idx];
        if (!_isGenericRootFolder(candidateAlbum)) {
          albumFolder = candidateAlbum;
          idx--;
        }
      }
      if (idx >= 0) {
        final candidateArtist = segments[idx];
        if (!_isGenericRootFolder(candidateArtist)) {
          artistFolder = candidateArtist;
        }
      }
    }

    int? year;
    String? album;
    if (albumFolder != null) {
      final ym1 = _albumYearPrefixRe.firstMatch(albumFolder.trim());
      final ym2 = _albumYearSuffixRe.firstMatch(albumFolder.trim());
      if (ym1 != null) {
        year = int.tryParse(ym1.group(1)!);
        album = cleanNoise(ym1.group(2)!);
      } else if (ym2 != null) {
        album = cleanNoise(ym2.group(1)!);
        year = int.tryParse(ym2.group(2)!);
      } else {
        album = cleanNoise(albumFolder);
        final anyYear = _yearRe.firstMatch(albumFolder);
        if (anyYear != null) year = int.tryParse(anyYear.group(1)!);
      }
    }

    int? trackNumber;
    var remainder = baseName;
    String pattern = 'Filename only';
    double confidence = 0.45;

    final discTrackMatch = _discTrackPrefixRe.firstMatch(remainder);
    if (discTrackMatch != null) {
      discNumber ??= int.tryParse(discTrackMatch.group(1)!);
      trackNumber = int.tryParse(discTrackMatch.group(2)!);
      remainder = discTrackMatch.group(3)!.trim();
      pattern = 'Disc-Track - Title';
      confidence = 0.78;
    } else {
      final trackMatch = _trackPrefixRe.firstMatch(remainder);
      if (trackMatch != null) {
        trackNumber = int.tryParse(trackMatch.group(1)!);
        remainder = trackMatch.group(2)!.trim();
        pattern = 'Track - Title';
        confidence = 0.72;
      }
    }

    String? artist;
    String? title = remainder;
    final artistTitleMatch = _artistTitleRe.firstMatch(remainder);
    if (artistTitleMatch != null) {
      artist = cleanNoise(artistTitleMatch.group(1)!);
      title = cleanNoise(artistTitleMatch.group(2)!);
      pattern = trackNumber != null
          ? 'Track - Artist - Title'
          : 'Artist - Title';
      confidence = 0.85;
    } else if (artistFolder != null && artistFolder.isNotEmpty) {
      artist = cleanNoise(artistFolder);
      if (album != null) {
        pattern = 'Artist/Album/Track - Title';
        confidence = 0.82;
      }
    }

    return InferredMetadata(
      title: (title.isNotEmpty) ? title : null,
      artist: (artist != null && artist.isNotEmpty) ? artist : null,
      album: (album != null && album.isNotEmpty) ? album : null,
      trackNumber: trackNumber,
      discNumber: discNumber,
      year: year,
      confidence: confidence,
      matchedPattern: pattern,
    );
  }

  bool _isGenericRootFolder(String name) {
    final lower = name.trim().toLowerCase();
    return lower.isEmpty ||
        lower == 'music' ||
        lower == 'downloads' ||
        lower == 'audio' ||
        lower == 'songs' ||
        lower == 'tracks' ||
        lower == 'media' ||
        lower == 'storage' ||
        lower == 'emulated' ||
        lower == '0' ||
        lower.endsWith(':\\') ||
        lower == '/';
  }

  /// Detects metadata quality issues for a track ("Tag Health").
  List<String> detectTagIssues(LocalSongItem item) {
    final issues = <String>[];
    final a = item.artist.trim().toLowerCase();
    final al = item.album.trim().toLowerCase();
    final g = item.genre.trim().toLowerCase();
    if (a.isEmpty || a == 'unknown artist' || a == '<unknown>') {
      issues.add('Missing Artist');
    }
    if (al.isEmpty || al == 'unknown album' || al == '<unknown>') {
      issues.add('Missing Album');
    }
    if (g.isEmpty || g == 'unknown genre' || g == '<unknown>') {
      issues.add('Missing Genre');
    }
    if (item.year == null || item.year! <= 0) {
      issues.add('Missing Year');
    }
    if (_noiseBracketRe.hasMatch(item.title) || item.title.contains('_')) {
      issues.add('Unformatted Title');
    }
    return issues;
  }

  /// Resolves a Camelot key automatically if [musicalKey] is provided.
  String? resolveCamelot(String? musicalKey) {
    if (musicalKey == null || musicalKey.trim().isEmpty) return null;
    return AutomixAnalysisService.instance.parseCamelotKey(musicalKey);
  }

  /// Applies inferred metadata only to missing/generic fields (or all if [overwriteAll]).
  LocalSongItem applyInferred(
    LocalSongItem item, {
    bool overwriteAll = false,
  }) {
    final inferred = inferFromPath(item.path);
    bool isMissing(String val, String fallback) {
      final l = val.trim().toLowerCase();
      return l.isEmpty || l == fallback || l == '<unknown>';
    }

    return item.copyWith(
      title: (overwriteAll || item.title.trim().isEmpty)
          ? (inferred.title ?? item.title)
          : item.title,
      artist: (overwriteAll || isMissing(item.artist, 'unknown artist'))
          ? (inferred.artist ?? item.artist)
          : item.artist,
      album: (overwriteAll || isMissing(item.album, 'unknown album'))
          ? (inferred.album ?? item.album)
          : item.album,
      trackNumber: (overwriteAll || item.trackNumber == null)
          ? (inferred.trackNumber ?? item.trackNumber)
          : item.trackNumber,
      discNumber: (overwriteAll || item.discNumber == null)
          ? (inferred.discNumber ?? item.discNumber)
          : item.discNumber,
      year: (overwriteAll || item.year == null)
          ? (inferred.year ?? item.year)
          : item.year,
    );
  }

  /// Formats a clean filename from a track's tags.
  String formatFilenameFromTags(
    LocalSongItem item, {
    String template = '{track} - {title}',
  }) {
    final ext = p.extension(item.realFilePath);
    final trackStr = item.trackNumber != null
        ? item.trackNumber!.toString().padLeft(2, '0')
        : '00';
    var out = template
        .replaceAll('{track}', trackStr)
        .replaceAll('{title}', item.title)
        .replaceAll('{artist}', item.artist)
        .replaceAll('{album}', item.album)
        .replaceAll('{year}', item.year?.toString() ?? '');
    out = out.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_').trim();
    if (out.isEmpty) out = p.basenameWithoutExtension(item.realFilePath);
    return '$out$ext';
  }

  /// Saves single-track tag edits with snapshot history for Undo.
  Future<void> saveTagsWithHistory(LocalSongItem updated) async {
    final normalized = updated.copyWith(
      camelotKey: updated.camelotKey ?? resolveCamelot(updated.musicalKey),
    );
    await AppDatabase.instance.recordAndApplyTagEdit(normalized);
  }

  /// Batch-updates multiple tracks in Drift (with Undo history per track).
  Future<int> batchUpdateTags(
    List<LocalSongItem> items, {
    String? artist,
    String? album,
    String? albumArtist,
    String? genre,
    int? year,
    int? discNumber,
    bool autoNumber = false,
    bool autoInferMissing = false,
    bool normalizeCasing = false,
  }) async {
    int count = 0;
    for (int i = 0; i < items.length; i++) {
      var current = items[i];
      if (autoInferMissing) {
        current = applyInferred(current);
      }
      if (artist != null && artist.trim().isNotEmpty) {
        current = current.copyWith(artist: artist.trim());
      }
      if (album != null && album.trim().isNotEmpty) {
        current = current.copyWith(album: album.trim());
      }
      if (albumArtist != null && albumArtist.trim().isNotEmpty) {
        current = current.copyWith(albumArtist: albumArtist.trim());
      }
      if (genre != null && genre.trim().isNotEmpty) {
        current = current.copyWith(genre: genre.trim());
      }
      if (year != null && year > 0) {
        current = current.copyWith(year: year);
      }
      if (discNumber != null && discNumber > 0) {
        current = current.copyWith(discNumber: discNumber);
      }
      if (autoNumber) {
        current = current.copyWith(trackNumber: i + 1);
      }
      if (normalizeCasing) {
        current = current.copyWith(
          title: normalizeTitleCase(current.title),
          artist: normalizeTitleCase(current.artist),
          album: normalizeTitleCase(current.album),
        );
      }
      await AppDatabase.instance.recordAndApplyTagEdit(current);
      count++;
    }
    return count;
  }

  Future<LocalSongItem?> undoLastEdit(String trackPath) {
    return AppDatabase.instance.undoLastTagEdit(trackPath);
  }
}
