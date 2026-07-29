import 'package:path/path.dart' as p;

/// Represents a single audio entry parsed from an M3U/M3U8 playlist.
class M3uEntry {
  final String title;
  final String artist;
  final String pathOrUrl;
  final int durationSeconds;

  const M3uEntry({
    required this.title,
    required this.artist,
    required this.pathOrUrl,
    this.durationSeconds = -1,
  });

  bool get isNetwork =>
      pathOrUrl.startsWith('http://') || pathOrUrl.startsWith('https://');

  Map<String, dynamic> toJson() => {
        'title': title,
        'artist': artist,
        'pathOrUrl': pathOrUrl,
        'durationSeconds': durationSeconds,
      };

  factory M3uEntry.fromJson(Map<String, dynamic> json) => M3uEntry(
        title: json['title'] as String? ?? '',
        artist: json['artist'] as String? ?? 'Unknown Artist',
        pathOrUrl: json['pathOrUrl'] as String? ?? '',
        durationSeconds: json['durationSeconds'] as int? ?? -1,
      );
}

/// Parser and encoder for M3U and M3U8 audio playlist files.
class M3uParser {
  /// Parses the raw string content of an M3U or M3U8 playlist into a list of [M3uEntry].
  ///
  /// If [baseDirectory] is provided, relative file paths will automatically be resolved
  /// relative to that directory.
  static List<M3uEntry> parse(String content, {String? baseDirectory}) {
    final lines = content.split(RegExp(r'\r?\n'));
    final entries = <M3uEntry>[];

    String currentTitle = '';
    String currentArtist = 'Unknown Artist';
    int currentDuration = -1;

    for (var line in lines) {
      line = line.trim();
      if (line.isEmpty) continue;

      if (line.startsWith('#EXTINF:')) {
        final infoStr = line.substring(8);
        final commaIdx = infoStr.indexOf(',');

        if (commaIdx != -1) {
          final durStr = infoStr.substring(0, commaIdx).trim();
          currentDuration = int.tryParse(durStr) ?? -1;

          final metaStr = infoStr.substring(commaIdx + 1).trim();
          if (metaStr.contains(' - ')) {
            final parts = metaStr.split(' - ');
            currentArtist = parts[0].trim();
            currentTitle = parts.sublist(1).join(' - ').trim();
          } else {
            currentTitle = metaStr;
            currentArtist = 'Unknown Artist';
          }
        }
      } else if (!line.startsWith('#')) {
        String targetPath = line;
        final isUrl =
            targetPath.startsWith('http://') || targetPath.startsWith('https://');

        if (!isUrl && baseDirectory != null && p.isRelative(targetPath)) {
          targetPath = p.normalize(p.join(baseDirectory, targetPath));
        }

        final title = currentTitle.isNotEmpty
            ? currentTitle
            : p.basenameWithoutExtension(targetPath);

        entries.add(
          M3uEntry(
            title: title,
            artist: currentArtist,
            pathOrUrl: targetPath,
            durationSeconds: currentDuration,
          ),
        );

        // Reset per-track parsing buffers
        currentTitle = '';
        currentArtist = 'Unknown Artist';
        currentDuration = -1;
      }
    }

    return entries;
  }

  /// Encodes a list of [M3uEntry] items into a standard `#EXTM3U` formatted string.
  static String encode(List<M3uEntry> entries) {
    final buffer = StringBuffer();
    buffer.writeln('#EXTM3U');

    for (final entry in entries) {
      final dur = entry.durationSeconds >= 0 ? entry.durationSeconds : -1;
      final artistTitle = entry.artist.isNotEmpty && entry.artist != 'Unknown Artist'
          ? '${entry.artist} - ${entry.title}'
          : entry.title;
      buffer.writeln('#EXTINF:$dur,$artistTitle');
      buffer.writeln(entry.pathOrUrl);
    }

    return buffer.toString();
  }
}
