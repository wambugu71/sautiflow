import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:path/path.dart' as p;

/// Decoded virtual sub-track metadata stored inside a virtual CUE path string.
class CueVirtualTrackInfo {
  final String realFilePath;
  final int trackNumber;
  final int startMs;
  final int? endMs;
  final String title;
  final String artist;
  final String album;
  final String? genre;
  final int? year;
  final double? replayGainTrackDb;
  final double? replayGainAlbumDb;
  final String? cueFilePath;

  const CueVirtualTrackInfo({
    required this.realFilePath,
    required this.trackNumber,
    required this.startMs,
    this.endMs,
    required this.title,
    required this.artist,
    required this.album,
    this.genre,
    this.year,
    this.replayGainTrackDb,
    this.replayGainAlbumDb,
    this.cueFilePath,
  });

  Duration get clipStart => Duration(milliseconds: startMs);

  Duration? get clipEnd => endMs != null ? Duration(milliseconds: endMs!) : null;

  Duration? get duration => (endMs != null && endMs! > startMs)
      ? Duration(milliseconds: endMs! - startMs)
      : null;
}

/// Utility for encoding and decoding CUE virtual sub-track descriptors inside
/// standard file path strings (`<realPath>#cue?...`) so existing `String path`
/// contracts work across library, folder browser, album view, and queue.
class CueVirtualPath {
  static const String marker = '#cue?';

  static bool isVirtual(String path) => path.contains(marker);

  /// Strips the virtual `#cue?...` fragment and returns the physical file path.
  static String strip(String path) {
    final idx = path.indexOf(marker);
    if (idx < 0) return path;
    return path.substring(0, idx);
  }

  /// Strips virtual fragment from `file://` URI or raw path.
  static String stripUriString(String pathOrUri) {
    final stripped = strip(pathOrUri);
    return stripped;
  }

  /// Canonicalizes the physical path portion while preserving the `#cue?...` fragment.
  static String canonicalize(String path) {
    final idx = path.indexOf(marker);
    if (idx < 0) return p.canonicalize(path);
    final real = p.canonicalize(path.substring(0, idx));
    return '$real${path.substring(idx)}';
  }

  /// Returns a stable comparison key for virtual or physical audio paths.
  static String normalizedKey(String path) {
    final idx = path.indexOf(marker);
    if (idx < 0) {
      final canonical = p.canonicalize(path);
      return Platform.isWindows ? canonical.toLowerCase() : canonical;
    }
    final canonicalReal = p.canonicalize(path.substring(0, idx));
    final realKey =
        Platform.isWindows ? canonicalReal.toLowerCase() : canonicalReal;
    return '$realKey${path.substring(idx)}';
  }

  static String encode({
    required String realFilePath,
    required int trackNumber,
    required int startMs,
    int? endMs,
    required String title,
    String? artist,
    String? album,
    String? genre,
    int? year,
    double? replayGainTrackDb,
    double? replayGainAlbumDb,
    String? cueFilePath,
  }) {
    final basePath = strip(realFilePath);
    final params = <String, String>{
      't': trackNumber.toString(),
      's': startMs.toString(),
      if (endMs != null) 'e': endMs.toString(),
      'ti': title,
      if (artist != null && artist.isNotEmpty) 'ar': artist,
      if (album != null && album.isNotEmpty) 'al': album,
      if (genre != null && genre.isNotEmpty) 'g': genre,
      if (year != null) 'y': year.toString(),
      if (replayGainTrackDb != null) 'rg': replayGainTrackDb.toStringAsFixed(2),
      if (replayGainAlbumDb != null) 'rga': replayGainAlbumDb.toStringAsFixed(2),
      if (cueFilePath != null && cueFilePath.isNotEmpty) 'c': cueFilePath,
    };
    final query = params.entries
        .map(
          (e) =>
              '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}',
        )
        .join('&');
    return '$basePath$marker$query';
  }

  static CueVirtualTrackInfo? parse(String path) {
    final idx = path.indexOf(marker);
    if (idx < 0) return null;

    final realPath = path.substring(0, idx);
    final query = path.substring(idx + marker.length);
    if (query.isEmpty) return null;

    Map<String, String> params;
    try {
      params = Uri.splitQueryString(query);
    } catch (_) {
      return null;
    }

    final trackNumber = int.tryParse(params['t'] ?? '') ?? 1;
    final startMs = int.tryParse(params['s'] ?? '') ?? 0;
    final endMs = int.tryParse(params['e'] ?? '');
    final title = params['ti']?.trim().isNotEmpty == true
        ? params['ti']!.trim()
        : 'Track ${trackNumber.toString().padLeft(2, '0')}';
    final artist = params['ar']?.trim().isNotEmpty == true
        ? params['ar']!.trim()
        : 'Unknown Artist';
    final album = params['al']?.trim().isNotEmpty == true
        ? params['al']!.trim()
        : 'Unknown Album';
    final genre = params['g']?.trim();
    final year = int.tryParse(params['y'] ?? '');
    final rgTrack = double.tryParse(params['rg'] ?? '');
    final rgAlbum = double.tryParse(params['rga'] ?? '');
    final cuePath = params['c']?.trim();

    return CueVirtualTrackInfo(
      realFilePath: realPath,
      trackNumber: trackNumber,
      startMs: startMs,
      endMs: endMs,
      title: title,
      artist: artist,
      album: album,
      genre: (genre != null && genre.isNotEmpty) ? genre : null,
      year: year,
      replayGainTrackDb: rgTrack,
      replayGainAlbumDb: rgAlbum,
      cueFilePath: (cuePath != null && cuePath.isNotEmpty) ? cuePath : null,
    );
  }
}

/// Represents a single audio track defined within a CUE sheet.
class CueTrackEntry {
  final int trackNumber;
  final String title;
  final String? performer;
  final String? albumPerformer;
  final String? albumTitle;
  final String? songwriter;
  final String? genre;
  final int? year;
  final String? isrc;
  final String filePath;
  final String? cueFilePath;
  final int startMs;
  final int? pregapMs;
  final int? endMs;
  final double? replayGainTrackDb;
  final double? replayGainTrackPeak;
  final double? replayGainAlbumDb;
  final double? replayGainAlbumPeak;

  const CueTrackEntry({
    required this.trackNumber,
    required this.title,
    this.performer,
    this.albumPerformer,
    this.albumTitle,
    this.songwriter,
    this.genre,
    this.year,
    this.isrc,
    required this.filePath,
    this.cueFilePath,
    required this.startMs,
    this.pregapMs,
    this.endMs,
    this.replayGainTrackDb,
    this.replayGainTrackPeak,
    this.replayGainAlbumDb,
    this.replayGainAlbumPeak,
  });

  String get effectiveArtist => (performer != null && performer!.isNotEmpty)
      ? performer!
      : ((albumPerformer != null && albumPerformer!.isNotEmpty)
            ? albumPerformer!
            : 'Unknown Artist');

  String get effectiveAlbum => (albumTitle != null && albumTitle!.isNotEmpty)
      ? albumTitle!
      : 'Unknown Album';

  Duration get clipStart => Duration(milliseconds: startMs);

  Duration? get clipEnd => endMs != null ? Duration(milliseconds: endMs!) : null;

  Duration? get duration => (endMs != null && endMs! > startMs)
      ? Duration(milliseconds: endMs! - startMs)
      : null;

  String get virtualPath => CueVirtualPath.encode(
    realFilePath: filePath,
    trackNumber: trackNumber,
    startMs: startMs,
    endMs: endMs,
    title: title,
    artist: effectiveArtist,
    album: effectiveAlbum,
    genre: genre,
    year: year,
    replayGainTrackDb: replayGainTrackDb,
    replayGainAlbumDb: replayGainAlbumDb,
    cueFilePath: cueFilePath,
  );

  CueTrackEntry copyWith({
    int? startMs,
    int? pregapMs,
    int? endMs,
    String? filePath,
  }) {
    return CueTrackEntry(
      trackNumber: trackNumber,
      title: title,
      performer: performer,
      albumPerformer: albumPerformer,
      albumTitle: albumTitle,
      songwriter: songwriter,
      genre: genre,
      year: year,
      isrc: isrc,
      filePath: filePath ?? this.filePath,
      cueFilePath: cueFilePath,
      startMs: startMs ?? this.startMs,
      pregapMs: pregapMs ?? this.pregapMs,
      endMs: endMs ?? this.endMs,
      replayGainTrackDb: replayGainTrackDb,
      replayGainTrackPeak: replayGainTrackPeak,
      replayGainAlbumDb: replayGainAlbumDb,
      replayGainAlbumPeak: replayGainAlbumPeak,
    );
  }
}

/// Represents a `FILE "..." <TYPE>` block in a CUE sheet.
class CueFileBlock {
  final String rawFileName;
  final String resolvedFilePath;
  final String fileType;
  final List<CueTrackEntry> tracks;

  const CueFileBlock({
    required this.rawFileName,
    required this.resolvedFilePath,
    required this.fileType,
    required this.tracks,
  });
}

/// Parsed CUE sheet metadata, file blocks, and resolved virtual tracks.
class CueSheet {
  final String? title;
  final String? performer;
  final String? songwriter;
  final String? genre;
  final int? year;
  final String? comment;
  final double? replayGainAlbumDb;
  final double? replayGainAlbumPeak;
  final String? cueFilePath;
  final List<CueFileBlock> files;

  const CueSheet({
    this.title,
    this.performer,
    this.songwriter,
    this.genre,
    this.year,
    this.comment,
    this.replayGainAlbumDb,
    this.replayGainAlbumPeak,
    this.cueFilePath,
    required this.files,
  });

  List<CueTrackEntry> get allTracks =>
      files.expand((f) => f.tracks).toList(growable: false);

  /// Normalized paths of all referenced physical audio files.
  Set<String> get referencedAudioFiles =>
      files.map((f) => normalizeAudioPathKey(f.resolvedFilePath)).toSet();

  static String normalizeAudioPathKey(String path) {
    final normalized = p.normalize(path);
    return Platform.isWindows ? normalized.toLowerCase() : normalized;
  }
}

class _MutableTrackBuilder {
  final int trackNumber;
  final bool isAudio;
  String? title;
  String? performer;
  String? songwriter;
  String? isrc;
  double? replayGainTrackDb;
  double? replayGainTrackPeak;
  int? index00Ms;
  int? index01Ms;

  _MutableTrackBuilder({required this.trackNumber, required this.isAudio});
}

class _MutableFileBuilder {
  final String rawFileName;
  final String resolvedFilePath;
  final String fileType;
  final List<_MutableTrackBuilder> tracks = [];

  _MutableFileBuilder({
    required this.rawFileName,
    required this.resolvedFilePath,
    required this.fileType,
  });
}

/// Parser for external `.cue` sidecar files and embedded FLAC/APEv2 CUESHEET tags.
class CueParser {
  static const List<String> _fallbackAudioExtensions = <String>[
    '.flac',
    '.wv',
    '.ape',
    '.wav',
    '.m4a',
    '.alac',
    '.aiff',
    '.aif',
    '.mp3',
    '.ogg',
    '.opus',
    '.aac',
    '.wma',
  ];

  /// Converts a `MM:SS:FF` CUE timestamp (75 frames/sec) to milliseconds.
  static int? parseTimestampToMs(String timestamp) {
    final match = RegExp(
      r'^(\d+):(\d{1,2}):(\d{1,2})$',
    ).firstMatch(timestamp.trim());
    if (match == null) return null;

    final minutes = int.tryParse(match.group(1)!) ?? 0;
    final seconds = int.tryParse(match.group(2)!) ?? 0;
    final frames = int.tryParse(match.group(3)!) ?? 0;

    final totalSeconds = minutes * 60 + seconds;
    final frameMs = ((frames * 1000) / 75.0).round();
    return totalSeconds * 1000 + frameMs;
  }

  /// Parses raw `.cue` text into a structured [CueSheet].
  static CueSheet parse(
    String content, {
    String? cueFilePath,
    String? baseDirectory,
    String? overrideAudioFilePath,
    int? overrideFileDurationMs,
  }) {
    var cleanContent = content;
    if (cleanContent.startsWith('\uFEFF')) {
      cleanContent = cleanContent.substring(1);
    }

    final resolvedBaseDir = baseDirectory ??
        (cueFilePath != null && cueFilePath.isNotEmpty
            ? p.dirname(cueFilePath)
            : null);

    String? albumTitle;
    String? albumPerformer;
    String? albumSongwriter;
    String? genre;
    int? year;
    String? comment;
    double? albumRgDb;
    double? albumRgPeak;

    final fileBuilders = <_MutableFileBuilder>[];
    _MutableFileBuilder? currentFile;
    _MutableTrackBuilder? currentTrack;

    final lines = cleanContent.split(RegExp(r'\r?\n'));
    for (final rawLine in lines) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;

      final upper = line.toUpperCase();

      if (upper.startsWith('REM ')) {
        final rest = line.substring(4).trim();
        final restUpper = rest.toUpperCase();
        if (restUpper.startsWith('GENRE ')) {
          genre ??= _unquote(rest.substring(6).trim());
        } else if (restUpper.startsWith('DATE ')) {
          final val = _unquote(rest.substring(5).trim());
          final m = RegExp(r'(\d{4})').firstMatch(val);
          if (m != null) {
            year ??= int.tryParse(m.group(1)!);
          }
        } else if (restUpper.startsWith('YEAR ')) {
          final val = _unquote(rest.substring(5).trim());
          final m = RegExp(r'(\d{4})').firstMatch(val);
          if (m != null) {
            year ??= int.tryParse(m.group(1)!);
          }
        } else if (restUpper.startsWith('COMMENT ')) {
          comment ??= _unquote(rest.substring(8).trim());
        } else if (restUpper.startsWith('REPLAYGAIN_ALBUM_GAIN ')) {
          albumRgDb ??= _parseGainDb(rest.substring(22).trim());
        } else if (restUpper.startsWith('REPLAYGAIN_ALBUM_PEAK ')) {
          albumRgPeak ??= double.tryParse(_unquote(rest.substring(22).trim()));
        } else if (restUpper.startsWith('REPLAYGAIN_TRACK_GAIN ') &&
            currentTrack != null) {
          currentTrack.replayGainTrackDb ??= _parseGainDb(
            rest.substring(22).trim(),
          );
        } else if (restUpper.startsWith('REPLAYGAIN_TRACK_PEAK ') &&
            currentTrack != null) {
          currentTrack.replayGainTrackPeak ??= double.tryParse(
            _unquote(rest.substring(22).trim()),
          );
        }
        continue;
      }

      if (upper.startsWith('FILE ')) {
        final parsedFile = _parseFileDirective(line.substring(5).trim());
        if (parsedFile != null) {
          final resolvedPath = overrideAudioFilePath ??
              resolveAudioFilePath(
                parsedFile.$1,
                baseDirectory: resolvedBaseDir,
                cueFilePath: cueFilePath,
              );
          currentFile = _MutableFileBuilder(
            rawFileName: parsedFile.$1,
            resolvedFilePath: resolvedPath,
            fileType: parsedFile.$2,
          );
          fileBuilders.add(currentFile);
          currentTrack = null;
        }
        continue;
      }

      if (upper.startsWith('TRACK ')) {
        if (currentFile == null && overrideAudioFilePath != null) {
          currentFile = _MutableFileBuilder(
            rawFileName: p.basename(overrideAudioFilePath),
            resolvedFilePath: overrideAudioFilePath,
            fileType: 'WAVE',
          );
          fileBuilders.add(currentFile);
        }

        final parts = line.substring(6).trim().split(RegExp(r'\s+'));
        final trackNum = int.tryParse(parts.isNotEmpty ? parts[0] : '') ?? 0;
        final mode = parts.length > 1 ? parts[1].toUpperCase() : 'AUDIO';
        final isAudio = mode == 'AUDIO';

        currentTrack = _MutableTrackBuilder(
          trackNumber: trackNum > 0
              ? trackNum
              : (currentFile?.tracks.length ?? 0) + 1,
          isAudio: isAudio,
        );
        if (currentFile != null && isAudio) {
          currentFile.tracks.add(currentTrack);
        }
        continue;
      }

      if (upper.startsWith('INDEX ')) {
        if (currentTrack != null && currentTrack.isAudio) {
          final parts = line.substring(6).trim().split(RegExp(r'\s+'));
          if (parts.length >= 2) {
            final idxNum = int.tryParse(parts[0]);
            final ms = parseTimestampToMs(parts[1]);
            if (idxNum == 0 && ms != null) {
              currentTrack.index00Ms ??= ms;
            } else if (idxNum == 1 && ms != null) {
              currentTrack.index01Ms ??= ms;
            }
          }
        }
        continue;
      }

      if (upper.startsWith('TITLE ')) {
        final val = _unquote(line.substring(6).trim());
        if (currentTrack != null) {
          currentTrack.title ??= val;
        } else {
          albumTitle ??= val;
        }
        continue;
      }

      if (upper.startsWith('PERFORMER ')) {
        final val = _unquote(line.substring(10).trim());
        if (currentTrack != null) {
          currentTrack.performer ??= val;
        } else {
          albumPerformer ??= val;
        }
        continue;
      }

      if (upper.startsWith('SONGWRITER ')) {
        final val = _unquote(line.substring(11).trim());
        if (currentTrack != null) {
          currentTrack.songwriter ??= val;
        } else {
          albumSongwriter ??= val;
        }
        continue;
      }

      if (upper.startsWith('ISRC ') && currentTrack != null) {
        currentTrack.isrc ??= _unquote(line.substring(5).trim());
        continue;
      }
    }

    final defaultAlbum = (albumTitle != null && albumTitle.isNotEmpty)
        ? albumTitle
        : (cueFilePath != null
              ? p.basenameWithoutExtension(cueFilePath)
              : null);

    final builtFiles = <CueFileBlock>[];
    for (var fi = 0; fi < fileBuilders.length; fi++) {
      final fb = fileBuilders[fi];
      final audioTracks = fb.tracks
          .where((t) => t.isAudio && (t.index01Ms != null || t.index00Ms != null))
          .toList();

      if (audioTracks.isEmpty) continue;

      final builtTracks = <CueTrackEntry>[];
      for (var ti = 0; ti < audioTracks.length; ti++) {
        final tb = audioTracks[ti];
        final startMs = tb.index01Ms ?? tb.index00Ms ?? 0;

        int? endMs;
        if (ti + 1 < audioTracks.length) {
          final next = audioTracks[ti + 1];
          final nextBoundary = (next.index00Ms != null &&
                  next.index00Ms! > startMs)
              ? next.index00Ms!
              : (next.index01Ms ?? next.index00Ms);
          if (nextBoundary != null && nextBoundary > startMs) {
            endMs = nextBoundary;
          }
        } else if (overrideFileDurationMs != null &&
            overrideFileDurationMs > startMs) {
          endMs = overrideFileDurationMs;
        }

        final fallbackTitle =
            'Track ${tb.trackNumber.toString().padLeft(2, '0')}';

        builtTracks.add(
          CueTrackEntry(
            trackNumber: tb.trackNumber,
            title: (tb.title != null && tb.title!.isNotEmpty)
                ? tb.title!
                : fallbackTitle,
            performer: tb.performer,
            albumPerformer: albumPerformer,
            albumTitle: defaultAlbum,
            songwriter: tb.songwriter ?? albumSongwriter,
            genre: genre,
            year: year,
            isrc: tb.isrc,
            filePath: fb.resolvedFilePath,
            cueFilePath: cueFilePath,
            startMs: startMs,
            pregapMs: tb.index00Ms,
            endMs: endMs,
            replayGainTrackDb: tb.replayGainTrackDb,
            replayGainTrackPeak: tb.replayGainTrackPeak,
            replayGainAlbumDb: albumRgDb,
            replayGainAlbumPeak: albumRgPeak,
          ),
        );
      }

      builtFiles.add(
        CueFileBlock(
          rawFileName: fb.rawFileName,
          resolvedFilePath: fb.resolvedFilePath,
          fileType: fb.fileType,
          tracks: builtTracks,
        ),
      );
    }

    return CueSheet(
      title: defaultAlbum,
      performer: albumPerformer,
      songwriter: albumSongwriter,
      genre: genre,
      year: year,
      comment: comment,
      replayGainAlbumDb: albumRgDb,
      replayGainAlbumPeak: albumRgPeak,
      cueFilePath: cueFilePath,
      files: builtFiles,
    );
  }

  /// Synchronously reads and parses a `.cue` file (UTF-8 with Latin-1 fallback).
  static CueSheet? parseFileSync(String cueFilePath) {
    try {
      final file = File(cueFilePath);
      if (!file.existsSync()) return null;
      final bytes = file.readAsBytesSync();
      final content = _decodeBytes(bytes);
      return parse(
        content,
        cueFilePath: cueFilePath,
        baseDirectory: file.parent.path,
      );
    } catch (_) {
      return null;
    }
  }

  /// Asynchronously reads and parses a `.cue` file (UTF-8 with Latin-1 fallback).
  static Future<CueSheet?> parseFile(String cueFilePath) async {
    try {
      final file = File(cueFilePath);
      if (!await file.exists()) return null;
      final bytes = await file.readAsBytes();
      final content = _decodeBytes(bytes);
      return parse(
        content,
        cueFilePath: cueFilePath,
        baseDirectory: file.parent.path,
      );
    } catch (_) {
      return null;
    }
  }

  /// Extracts an embedded CUE sheet from a FLAC (`VORBIS_COMMENT` `CUESHEET` or
  /// binary `CUESHEET` metadata block) or WavPack / Monkey's Audio (`APETAGEX`
  /// `CUESHEET`) file. Returns `null` if no embedded CUE sheet exists.
  static CueSheet? extractEmbeddedCueSync(String audioFilePath) {
    final ext = p.extension(audioFilePath).toLowerCase();
    if (ext == '.flac') {
      return _extractFlacEmbeddedCueSync(audioFilePath);
    }
    if (ext == '.wv' || ext == '.ape') {
      return _extractApev2EmbeddedCueSync(audioFilePath);
    }
    return null;
  }

  /// Resolves the `FILE "..."` target path on disk, falling back cleanly when
  /// a `.cue` references `.wav` while the actual file is `.flac`/`.wv`/`.ape`/etc.
  static String resolveAudioFilePath(
    String rawFileName, {
    String? baseDirectory,
    String? cueFilePath,
  }) {
    final dir = baseDirectory ??
        (cueFilePath != null && cueFilePath.isNotEmpty
            ? p.dirname(cueFilePath)
            : null);

    // Normalize mixed Windows/POSIX slashes inside rawFileName from cross-OS cues
    final cleanName = rawFileName.replaceAll('\\', '/');
    final baseNameFromRaw = p.posix.basename(cleanName);

    if (dir == null || dir.isEmpty) {
      return rawFileName;
    }

    // 1. Direct candidate path
    final direct = p.normalize(p.join(dir, cleanName));
    if (_safeFileExistsSync(direct)) {
      return direct;
    }

    // 2. Basename inside dir
    final sameDirDirect = p.normalize(p.join(dir, baseNameFromRaw));
    if (_safeFileExistsSync(sameDirDirect)) {
      return sameDirDirect;
    }

    // Scan directory entries once for case-insensitive and extension fallbacks
    final dirEntity = Directory(dir);
    if (!dirEntity.existsSync()) {
      return direct;
    }

    List<File> filesInDir;
    try {
      filesInDir = dirEntity
          .listSync(followLinks: false)
          .whereType<File>()
          .toList(growable: false);
    } catch (_) {
      return direct;
    }

    final rawBaseLower = baseNameFromRaw.toLowerCase();
    for (final f in filesInDir) {
      if (p.basename(f.path).toLowerCase() == rawBaseLower) {
        return f.path;
      }
    }

    // 3. Matching stem with alternative compressed/lossless audio extensions
    final rawStemLower = p.basenameWithoutExtension(baseNameFromRaw).toLowerCase();
    final cueStemLower = cueFilePath != null && cueFilePath.isNotEmpty
        ? p.basenameWithoutExtension(cueFilePath).toLowerCase()
        : null;

    final audioCandidatesByExt = <String, String>{};
    for (final f in filesInDir) {
      final extLower = p.extension(f.path).toLowerCase();
      if (!_fallbackAudioExtensions.contains(extLower)) continue;
      final stemLower = p.basenameWithoutExtension(f.path).toLowerCase();
      if (stemLower == rawStemLower ||
          (cueStemLower != null && stemLower == cueStemLower)) {
        audioCandidatesByExt.putIfAbsent(extLower, () => f.path);
      }
    }

    for (final ext in _fallbackAudioExtensions) {
      final hit = audioCandidatesByExt[ext];
      if (hit != null) return hit;
    }

    return direct;
  }

  static bool _safeFileExistsSync(String path) {
    try {
      return File(path).existsSync();
    } catch (_) {
      return false;
    }
  }

  static String _decodeBytes(Uint8List bytes) {
    try {
      return utf8.decode(bytes, allowMalformed: false);
    } catch (_) {
      return latin1.decode(bytes);
    }
  }

  static String _unquote(String value) {
    var s = value.trim();
    if (s.length >= 2 && s.startsWith('"') && s.endsWith('"')) {
      s = s.substring(1, s.length - 1);
    }
    return s.replaceAll('\\"', '"');
  }

  static double? _parseGainDb(String raw) {
    final s = _unquote(raw).replaceAll(RegExp(r'\s*dB$', caseSensitive: false), '');
    return double.tryParse(s.trim());
  }

  static (String, String)? _parseFileDirective(String rest) {
    if (rest.isEmpty) return null;
    if (rest.startsWith('"')) {
      final closing = rest.indexOf('"', 1);
      if (closing > 0) {
        final filename = rest.substring(1, closing);
        final after = rest.substring(closing + 1).trim();
        final fileType = after.isNotEmpty ? after.split(RegExp(r'\s+')).first : 'WAVE';
        return (filename, fileType.toUpperCase());
      }
    }
    final parts = rest.split(RegExp(r'\s+'));
    if (parts.isEmpty) return null;
    if (parts.length == 1) return (parts[0], 'WAVE');
    final fileType = parts.last.toUpperCase();
    final filename = parts.sublist(0, parts.length - 1).join(' ');
    return (filename, fileType);
  }

  static CueSheet? _extractFlacEmbeddedCueSync(String audioFilePath) {
    RandomAccessFile? raf;
    try {
      final file = File(audioFilePath);
      if (!file.existsSync()) return null;
      final fileLen = file.lengthSync();
      if (fileLen < 12) return null;

      raf = file.openSync();
      final magic = raf.readSync(4);
      if (magic.length < 4 ||
          magic[0] != 0x66 || // f
          magic[1] != 0x4C || // L
          magic[2] != 0x61 || // a
          magic[3] != 0x43) {
        // C
        return null;
      }

      int sampleRate = 44100;
      int? totalDurationMs;
      String? embeddedCueText;
      Uint8List? binaryCueBlock;
      String? tagAlbum;
      String? tagArtist;
      String? tagAlbumArtist;
      String? tagGenre;
      int? tagYear;

      var isLast = false;
      const maxMetadataBytes = 2 * 1024 * 1024;

      while (!isLast && raf.positionSync() + 4 <= fileLen) {
        final header = raf.readSync(4);
        if (header.length < 4) break;
        isLast = (header[0] & 0x80) != 0;
        final blockType = header[0] & 0x7F;
        final blockLen =
            (header[1] << 16) | (header[2] << 8) | header[3];

        if (blockLen <= 0 || raf.positionSync() + blockLen > fileLen) {
          break;
        }

        if (blockType == 0 && blockLen >= 18) {
          // STREAMINFO
          final info = raf.readSync(blockLen);
          if (info.length >= 18) {
            sampleRate =
                (info[10] << 12) | (info[11] << 4) | ((info[12] >> 4) & 0x0F);
            final totalSamples = ((info[13] & 0x0F) << 32) |
                (info[14] << 24) |
                (info[15] << 16) |
                (info[16] << 8) |
                info[17];
            if (sampleRate > 0 && totalSamples > 0) {
              totalDurationMs = ((totalSamples * 1000) / sampleRate).round();
            }
          }
        } else if (blockType == 4 && blockLen <= maxMetadataBytes) {
          // VORBIS_COMMENT
          final data = raf.readSync(blockLen);
          final parsed = _parseVorbisCommentsForCue(data);
          embeddedCueText ??= parsed.cueText;
          tagAlbum ??= parsed.album;
          tagArtist ??= parsed.artist;
          tagAlbumArtist ??= parsed.albumArtist;
          tagGenre ??= parsed.genre;
          tagYear ??= parsed.year;
        } else if (blockType == 5 && blockLen <= maxMetadataBytes) {
          // CUESHEET binary metadata block
          binaryCueBlock ??= raf.readSync(blockLen);
        } else {
          raf.setPositionSync(raf.positionSync() + blockLen);
        }
      }

      if (embeddedCueText != null && embeddedCueText.trim().isNotEmpty) {
        final sheet = parse(
          embeddedCueText,
          cueFilePath: audioFilePath,
          baseDirectory: file.parent.path,
          overrideAudioFilePath: audioFilePath,
          overrideFileDurationMs: totalDurationMs,
        );
        if (sheet.allTracks.isNotEmpty) {
          return sheet;
        }
      }

      if (binaryCueBlock != null && sampleRate > 0) {
        final sheet = _parseBinaryFlacCueBlock(
          binaryCueBlock,
          audioFilePath: audioFilePath,
          sampleRate: sampleRate,
          totalDurationMs: totalDurationMs,
          album: tagAlbum,
          performer: tagAlbumArtist ?? tagArtist,
          genre: tagGenre,
          year: tagYear,
        );
        if (sheet != null && sheet.allTracks.isNotEmpty) {
          return sheet;
        }
      }
    } catch (_) {
      return null;
    } finally {
      try {
        raf?.closeSync();
      } catch (_) {}
    }
    return null;
  }

  static ({
    String? cueText,
    String? album,
    String? artist,
    String? albumArtist,
    String? genre,
    int? year,
  }) _parseVorbisCommentsForCue(Uint8List data) {
    String? cueText;
    String? album;
    String? artist;
    String? albumArtist;
    String? genre;
    int? year;

    if (data.length < 8) {
      return (
        cueText: null,
        album: null,
        artist: null,
        albumArtist: null,
        genre: null,
        year: null,
      );
    }

    final view = ByteData.sublistView(data);
    var offset = 0;
    final vendorLen = view.getUint32(offset, Endian.little);
    offset += 4;
    if (vendorLen > data.length - offset - 4) {
      return (
        cueText: null,
        album: null,
        artist: null,
        albumArtist: null,
        genre: null,
        year: null,
      );
    }
    offset += vendorLen;

    final commentCount = math.min(
      view.getUint32(offset, Endian.little),
      4096,
    );
    offset += 4;

    for (var i = 0; i < commentCount; i++) {
      if (offset + 4 > data.length) break;
      final len = view.getUint32(offset, Endian.little);
      offset += 4;
      if (len > data.length - offset) break;
      final commentStr = utf8.decode(
        data.sublist(offset, offset + len),
        allowMalformed: true,
      );
      offset += len;

      final eq = commentStr.indexOf('=');
      if (eq <= 0) continue;
      final key = commentStr.substring(0, eq).toUpperCase();
      final val = commentStr.substring(eq + 1);
      if (key == 'CUESHEET') {
        cueText = val;
      } else if (key == 'ALBUM') {
        album ??= val.trim();
      } else if (key == 'ARTIST') {
        artist ??= val.trim();
      } else if (key == 'ALBUMARTIST' || key == 'ALBUM ARTIST') {
        albumArtist ??= val.trim();
      } else if (key == 'GENRE') {
        genre ??= val.trim();
      } else if (key == 'DATE' || key == 'YEAR') {
        final m = RegExp(r'(\d{4})').firstMatch(val);
        if (m != null) year ??= int.tryParse(m.group(1)!);
      }
    }

    return (
      cueText: cueText,
      album: album,
      artist: artist,
      albumArtist: albumArtist,
      genre: genre,
      year: year,
    );
  }

  static CueSheet? _parseBinaryFlacCueBlock(
    Uint8List block, {
    required String audioFilePath,
    required int sampleRate,
    int? totalDurationMs,
    String? album,
    String? performer,
    String? genre,
    int? year,
  }) {
    // FLAC CUESHEET block header is 396 bytes:
    // 128 MCN + 8 lead-in + 1 flags + 258 reserved + 1 numTracks
    if (block.length < 396 || sampleRate <= 0) return null;
    final view = ByteData.sublistView(block);
    var offset = 395;
    final numTracks = block[offset++];
    if (numTracks == 0) return null;

    final rawTracks = <({int trackNum, int? index00Ms, int startMs})>[];
    int? leadOutMs;

    for (var i = 0; i < numTracks; i++) {
      if (offset + 36 > block.length) break;
      final trackOffsetSamples = view.getUint64(offset, Endian.big);
      offset += 8;
      final trackNum = block[offset++];
      offset += 12; // ISRC
      final flags = block[offset++];
      final isAudio = (flags & 0x80) == 0;
      offset += 13; // reserved
      final numIndexPoints = block[offset++];

      int? index00Ms;
      int? index01Ms;

      for (var j = 0; j < numIndexPoints; j++) {
        if (offset + 12 > block.length) break;
        final idxOffsetSamples = view.getUint64(offset, Endian.big);
        offset += 8;
        final idxNum = block[offset++];
        offset += 3; // reserved

        final absSamples = trackOffsetSamples + idxOffsetSamples;
        final ms = ((absSamples * 1000) / sampleRate).round();
        if (idxNum == 0) {
          index00Ms ??= ms;
        } else if (idxNum == 1) {
          index01Ms ??= ms;
        }
      }

      if (trackNum == 170 || trackNum == 0xAA) {
        leadOutMs = ((trackOffsetSamples * 1000) / sampleRate).round();
        continue;
      }

      if (!isAudio) continue;
      final startMs = index01Ms ??
          index00Ms ??
          ((trackOffsetSamples * 1000) / sampleRate).round();
      rawTracks.add((
        trackNum: trackNum,
        index00Ms: index00Ms,
        startMs: startMs,
      ));
    }

    if (rawTracks.length < 2) {
      // Single-track binary cuesheets aren't useful to split unless >=2 tracks
      return null;
    }

    final albumName = (album != null && album.isNotEmpty)
        ? album
        : p.basenameWithoutExtension(audioFilePath);
    final entries = <CueTrackEntry>[];

    for (var i = 0; i < rawTracks.length; i++) {
      final t = rawTracks[i];
      int? endMs;
      if (i + 1 < rawTracks.length) {
        final next = rawTracks[i + 1];
        final candidate = (next.index00Ms != null && next.index00Ms! > t.startMs)
            ? next.index00Ms!
            : next.startMs;
        if (candidate > t.startMs) endMs = candidate;
      } else {
        final finalEnd = leadOutMs ?? totalDurationMs;
        if (finalEnd != null && finalEnd > t.startMs) {
          endMs = finalEnd;
        }
      }

      entries.add(
        CueTrackEntry(
          trackNumber: t.trackNum,
          title: 'Track ${t.trackNum.toString().padLeft(2, '0')}',
          performer: performer,
          albumPerformer: performer,
          albumTitle: albumName,
          genre: genre,
          year: year,
          filePath: audioFilePath,
          cueFilePath: audioFilePath,
          startMs: t.startMs,
          pregapMs: t.index00Ms,
          endMs: endMs,
        ),
      );
    }

    return CueSheet(
      title: albumName,
      performer: performer,
      genre: genre,
      year: year,
      cueFilePath: audioFilePath,
      files: [
        CueFileBlock(
          rawFileName: p.basename(audioFilePath),
          resolvedFilePath: audioFilePath,
          fileType: 'FLAC',
          tracks: entries,
        ),
      ],
    );
  }

  static CueSheet? _extractApev2EmbeddedCueSync(String audioFilePath) {
    RandomAccessFile? raf;
    try {
      final file = File(audioFilePath);
      if (!file.existsSync()) return null;
      final fileLen = file.lengthSync();
      if (fileLen < 32) return null;

      raf = file.openSync();

      // Check EOF for APEv2 footer, or right before a 128-byte ID3v1 tag
      final candidateFooterOffsets = <int>[fileLen - 32];
      if (fileLen >= 160) {
        raf.setPositionSync(fileLen - 128);
        final id3Magic = raf.readSync(3);
        if (id3Magic.length == 3 &&
            id3Magic[0] == 0x54 && // T
            id3Magic[1] == 0x41 && // A
            id3Magic[2] == 0x47) {
          // G
          candidateFooterOffsets.add(fileLen - 128 - 32);
        }
      }

      for (final footerOffset in candidateFooterOffsets) {
        if (footerOffset < 0) continue;
        raf.setPositionSync(footerOffset);
        final footer = raf.readSync(32);
        if (footer.length < 32) continue;

        final magic = String.fromCharCodes(footer.sublist(0, 8));
        if (magic != 'APETAGEX') continue;

        final view = ByteData.sublistView(footer);
        final version = view.getUint32(8, Endian.little);
        final tagSize = view.getUint32(12, Endian.little);
        final itemCount = view.getUint32(16, Endian.little);
        if (version != 2000 ||
            tagSize <= 32 ||
            tagSize > 2 * 1024 * 1024 ||
            itemCount > 1024) {
          continue;
        }

        final itemsStart = (footerOffset + 32) - tagSize;
        if (itemsStart < 0) continue;

        final itemsLen = tagSize - 32;
        raf.setPositionSync(itemsStart);
        final data = raf.readSync(itemsLen);
        if (data.length < itemsLen) continue;

        final dataView = ByteData.sublistView(data);
        var offset = 0;
        for (var i = 0; i < itemCount; i++) {
          if (offset + 8 > data.length) break;
          final valSize = dataView.getUint32(offset, Endian.little);
          final flags = dataView.getUint32(offset + 4, Endian.little);
          offset += 8;

          final keyEnd = data.indexOf(0, offset);
          if (keyEnd < 0) break;
          final key = ascii.decode(
            data.sublist(offset, keyEnd),
            allowInvalid: true,
          );
          offset = keyEnd + 1;

          if (offset + valSize > data.length) break;
          final isUtf8Text = ((flags >> 1) & 0x3) == 0;
          if (isUtf8Text && key.toUpperCase() == 'CUESHEET') {
            final val = utf8.decode(
              data.sublist(offset, offset + valSize),
              allowMalformed: true,
            );
            final sheet = parse(
              val,
              cueFilePath: audioFilePath,
              baseDirectory: file.parent.path,
              overrideAudioFilePath: audioFilePath,
            );
            if (sheet.allTracks.isNotEmpty) {
              return sheet;
            }
          }
          offset += valSize;
        }
      }
    } catch (_) {
      return null;
    } finally {
      try {
        raf?.closeSync();
      } catch (_) {}
    }
    return null;
  }
}
