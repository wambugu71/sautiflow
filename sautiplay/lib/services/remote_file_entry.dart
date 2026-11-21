import 'package:path/path.dart' as p;

/// Supported audio file extensions for remote file browsers.
const Set<String> kRemoteAudioExtensions = {
  '.mp3',
  '.flac',
  '.wav',
  '.aac',
  '.m4a',
  '.ogg',
  '.opus',
  '.dsf',
  '.dff',
  '.wma',
  '.aiff',
  '.aif',
  '.alac',
  '.wv',
  '.ape',
  '.mka',
};

/// Returns `true` if [fileName] has a supported audio file extension.
bool isSupportedAudioFile(String fileName) {
  final ext = p.extension(fileName).toLowerCase();
  return kRemoteAudioExtensions.contains(ext);
}

/// Returns the upper-case format badge label (e.g. `FLAC`, `DSF`, `MP3`).
String audioFormatLabel(String fileName) {
  final ext = p.extension(fileName).toLowerCase();
  if (ext.isEmpty) return 'AUDIO';
  return ext.substring(1).toUpperCase();
}

/// Returns an appropriate MIME type for [fileName].
String mimeTypeForAudioFile(String fileName) {
  switch (p.extension(fileName).toLowerCase()) {
    case '.mp3':
      return 'audio/mpeg';
    case '.flac':
      return 'audio/flac';
    case '.wav':
      return 'audio/wav';
    case '.aac':
      return 'audio/aac';
    case '.m4a':
    case '.alac':
      return 'audio/mp4';
    case '.ogg':
      return 'audio/ogg';
    case '.opus':
      return 'audio/opus';
    case '.dsf':
      return 'audio/x-dsf';
    case '.dff':
      return 'audio/x-dff';
    case '.aiff':
    case '.aif':
      return 'audio/aiff';
    case '.wv':
      return 'audio/x-wavpack';
    case '.ape':
      return 'audio/x-ape';
    default:
      return 'application/octet-stream';
  }
}

/// Formats a byte count into a human-readable string (e.g. `24.6 MB`).
String formatFileSize(int bytes) {
  if (bytes <= 0) return '';
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
}

/// Unified directory/file entry for remote file browsers (WebDAV, SFTP, SMB).
class RemoteFileEntry {
  final String name;
  final String path;
  final bool isDirectory;
  final int sizeBytes;
  final DateTime? modifiedTime;
  final String? shareName;

  const RemoteFileEntry({
    required this.name,
    required this.path,
    required this.isDirectory,
    this.sizeBytes = 0,
    this.modifiedTime,
    this.shareName,
  });

  bool get isAudioFile => !isDirectory && isSupportedAudioFile(name);

  String get formatBadge => audioFormatLabel(name);

  String get formattedSize => formatFileSize(sizeBytes);
}
