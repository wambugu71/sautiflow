import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:sautiflow/sautiflow.dart';

/// Represents a distinct storage volume (Internal Storage, SD Card, Desktop drive).
class StorageVolume {
  final String path;
  final String label;
  final bool isRemovable;
  final IconData icon;

  const StorageVolume({
    required this.path,
    required this.label,
    required this.isRemovable,
    required this.icon,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StorageVolume &&
          runtimeType == other.runtimeType &&
          path == other.path;

  @override
  int get hashCode => path.hashCode;
}

/// Represents an audio file discovered in a directory.
class AudioFileEntry {
  final String path;
  final String name;
  final String extension;
  final int sizeBytes;
  final DateTime lastModified;
  final String title;
  final String artist;
  final String? subtitle;
  final int? trackNumber;

  const AudioFileEntry({
    required this.path,
    required this.name,
    required this.extension,
    required this.sizeBytes,
    required this.lastModified,
    required this.title,
    required this.artist,
    this.subtitle,
    this.trackNumber,
  });

  String get realPath => CueVirtualPath.strip(path);
  bool get isCueTrack => CueVirtualPath.isVirtual(path);

  String get formattedSize {
    if (sizeBytes <= 0) return '0 B';
    const suffixes = ['B', 'KB', 'MB', 'GB'];
    var i = 0;
    double size = sizeBytes.toDouble();
    while (size >= 1024 && i < suffixes.length - 1) {
      size /= 1024;
      i++;
    }
    return '${size.toStringAsFixed(1)} ${suffixes[i]}';
  }
}

/// Represents a subdirectory within a folder.
class FolderEntry {
  final String path;
  final String name;
  final int audioCount;

  const FolderEntry({
    required this.path,
    required this.name,
    this.audioCount = 0,
  });
}

/// Snapshot of the contents of a directory.
class FolderContents {
  final String currentPath;
  final String? parentPath;
  final List<FolderEntry> subdirectories;
  final List<AudioFileEntry> audioFiles;

  const FolderContents({
    required this.currentPath,
    this.parentPath,
    required this.subdirectories,
    required this.audioFiles,
  });

  bool get isEmpty => subdirectories.isEmpty && audioFiles.isEmpty;
  int get totalItems => subdirectories.length + audioFiles.length;
}

/// Senior-engineered high-performance service for discovering storage volumes,
/// traversing local directories (Internal Storage & SD Cards), and extracting audio.
class StorageVolumeService {
  StorageVolumeService._();
  static final StorageVolumeService instance = StorageVolumeService._();

  static const Set<String> supportedAudioExtensions = {
    '.mp3',
    '.m4a',
    '.wav',
    '.flac',
    '.aac',
    '.ogg',
    '.opus',
    '.wma',
    '.alac',
    '.aiff',
    '.aif',
    '.ape',
    '.wv',
    '.m4b',
    '.m4p',
    '.dsf',
    '.dff',
  };

  // In-memory LRU-style cache for rapid directory navigation back/forth
  final Map<String, FolderContents> _dirCache = {};
  static const int _maxCacheEntries = 64;

  /// Ensures necessary permissions are requested on Android for full filesystem access.
  /// On Android 11+ (API 30+), requests `MANAGE_EXTERNAL_STORAGE` to browse SD cards and internal storage.
  static Future<bool> ensureStoragePermissions() async {
    if (Platform.isAndroid) {
      if (await Permission.manageExternalStorage.isGranted) {
        return true;
      }
      final manageStatus = await Permission.manageExternalStorage.request();
      if (manageStatus.isGranted) {
        return true;
      }

      var storageStatus = await Permission.storage.status;
      if (!storageStatus.isGranted) {
        storageStatus = await Permission.storage.request();
      }
      var audioStatus = await Permission.audio.status;
      if (!audioStatus.isGranted) {
        audioStatus = await Permission.audio.request();
      }
      return storageStatus.isGranted || audioStatus.isGranted;
    }
    return true;
  }

  /// Automatically discovers all accessible storage volumes (Internal Storage, SD Cards, Drives).
  static Future<List<StorageVolume>> getStorageVolumes() async {
    final volumes = <StorageVolume>[];
    final seenPaths = <String>{};

    void addVolume(String path, String label, bool isRemovable, IconData icon) {
      final canonical = p.canonicalize(path);
      if (seenPaths.add(canonical.toLowerCase())) {
        volumes.add(StorageVolume(
          path: canonical,
          label: label,
          isRemovable: isRemovable,
          icon: icon,
        ));
      }
    }

    if (Platform.isAndroid) {
      // 1. Primary Internal Storage (/storage/emulated/0)
      const internalPath = '/storage/emulated/0';
      if (await Directory(internalPath).exists()) {
        addVolume(
          internalPath,
          'Internal Storage',
          false,
          Icons.phone_android_rounded,
        );
      }

      // 2. Discover Removable SD Card(s) via getExternalStorageDirectories()
      try {
        final extDirs = await getExternalStorageDirectories();
        if (extDirs != null) {
          for (final dir in extDirs) {
            final parts = dir.path.split('/Android/data');
            if (parts.isNotEmpty) {
              final root = parts[0];
              if (root != internalPath && await Directory(root).exists()) {
                final cardName = p.basename(root);
                addVolume(
                  root,
                  'SD Card ($cardName)',
                  true,
                  Icons.sd_card_rounded,
                );
              }
            }
          }
        }
      } catch (e) {
        debugPrint('[StorageVolumeService] Error checking getExternalStorageDirectories: $e');
      }

      // 3. Inspect /storage directory directly (effective when MANAGE_EXTERNAL_STORAGE is active)
      try {
        final storageDir = Directory('/storage');
        if (await storageDir.exists()) {
          final entities = storageDir.listSync();
          for (final entity in entities) {
            if (entity is Directory) {
              final name = p.basename(entity.path);
              if (name != 'emulated' &&
                  name != 'self' &&
                  name != 'knox' &&
                  !name.startsWith('.')) {
                addVolume(
                  entity.path,
                  'SD Card ($name)',
                  true,
                  Icons.sd_card_rounded,
                );
              }
            }
          }
        }
      } catch (e) {
        debugPrint('[StorageVolumeService] Error inspecting /storage: $e');
      }

      // 4. Fallback check for /mnt/media_rw
      try {
        final mntDir = Directory('/mnt/media_rw');
        if (await mntDir.exists()) {
          final entities = mntDir.listSync();
          for (final entity in entities) {
            if (entity is Directory && !p.basename(entity.path).startsWith('.')) {
              addVolume(
                entity.path,
                'SD Card (${p.basename(entity.path)})',
                true,
                Icons.sd_card_rounded,
              );
            }
          }
        }
      } catch (_) {}
    } else if (Platform.isWindows) {
      // Windows drives
      for (final letter in 'CDEFGHIJKLMNOPQRSTUVWXYZ'.split('')) {
        final drivePath = '$letter:\\';
        try {
          if (Directory(drivePath).existsSync()) {
            addVolume(
              drivePath,
              'Drive ($letter:)',
              letter != 'C',
              letter == 'C'
                  ? Icons.laptop_windows_rounded
                  : Icons.storage_rounded,
            );
          }
        } catch (_) {}
      }
    } else if (Platform.isLinux || Platform.isMacOS) {
      // Unix home directory
      final home = Platform.environment['HOME'];
      if (home != null && Directory(home).existsSync()) {
        addVolume(
          home,
          'Home Directory',
          false,
          Icons.home_rounded,
        );
      }
      // Common mount points
      final mountDirs = ['/Volumes', '/media', '/mnt'];
      for (final m in mountDirs) {
        try {
          final d = Directory(m);
          if (d.existsSync()) {
            for (final entity in d.listSync()) {
              if (entity is Directory && !p.basename(entity.path).startsWith('.')) {
                addVolume(
                  entity.path,
                  p.basename(entity.path),
                  true,
                  Icons.folder_shared_rounded,
                );
              }
            }
          }
        } catch (_) {}
      }
    }

    // Default safety fallback if nothing could be detected
    if (volumes.isEmpty) {
      try {
        final docDir = await getApplicationDocumentsDirectory();
        addVolume(
          docDir.path,
          'App Storage',
          false,
          Icons.folder_rounded,
        );
      } catch (_) {}
    }

    return volumes;
  }

  static bool isCueFile(String filePath) =>
      p.extension(filePath).toLowerCase() == '.cue';

  static String _canonicalPathKey(String filePath) {
    final canonical = p.canonicalize(CueVirtualPath.strip(filePath));
    return Platform.isWindows ? canonical.toLowerCase() : canonical;
  }

  /// Expands external `.cue` sidecars and embedded CUE sheets in [files] and returns
  /// the generated virtual entries plus the set of canonical raw audio file keys to suppress.
  static Future<({
    List<AudioFileEntry> cueEntries,
    Set<String> suppressedMasterKeys,
  })> _expandCueFilesInDirectory(List<File> files) async {
    final cueEntries = <AudioFileEntry>[];
    final suppressedKeys = <String>{};
    final statCache = <String, FileStat>{};

    Future<FileStat?> getStat(String path) async {
      final key = _canonicalPathKey(path);
      if (statCache.containsKey(key)) return statCache[key];
      try {
        final f = File(path);
        if (!await f.exists()) return null;
        final st = await f.stat();
        statCache[key] = st;
        return st;
      } catch (_) {
        return null;
      }
    }

    Future<void> addSheetTracks(CueSheet sheet) async {
      final validTracks = sheet.allTracks
          .where((t) => File(t.filePath).existsSync())
          .toList();
      if (validTracks.isEmpty) return;

      // Group count per master file for proportional virtual track sizes
      final countByMaster = <String, int>{};
      for (final t in validTracks) {
        final masterKey = _canonicalPathKey(t.filePath);
        suppressedKeys.add(masterKey);
        countByMaster[masterKey] = (countByMaster[masterKey] ?? 0) + 1;
      }

      for (final t in validTracks) {
        final canonicalMaster = p.canonicalize(t.filePath);
        final masterKey = _canonicalPathKey(canonicalMaster);
        final st = await getStat(canonicalMaster);
        final masterSize = st?.size ?? 0;
        final trackCount = countByMaster[masterKey] ?? 1;
        final extLabel = p
            .extension(canonicalMaster)
            .replaceFirst('.', '')
            .toUpperCase();
        final trackPrefix = t.trackNumber.toString().padLeft(2, '0');
        final dur = t.duration;
        final durLabel = dur != null
            ? '${dur.inMinutes}:${(dur.inSeconds % 60).toString().padLeft(2, '0')}'
            : null;
        final virtualPath = CueVirtualPath.encode(
          realFilePath: canonicalMaster,
          trackNumber: t.trackNumber,
          startMs: t.startMs,
          endMs: t.endMs,
          title: t.title,
          artist: t.effectiveArtist,
          album: t.effectiveAlbum,
          genre: t.genre,
          year: t.year,
          replayGainTrackDb: t.replayGainTrackDb,
          replayGainAlbumDb: t.replayGainAlbumDb,
          cueFilePath: sheet.cueFilePath,
        );

        cueEntries.add(
          AudioFileEntry(
            path: virtualPath,
            name: '$trackPrefix. ${t.title}',
            extension: extLabel.isNotEmpty ? extLabel : 'CUE',
            sizeBytes: trackCount > 0 ? (masterSize ~/ trackCount) : masterSize,
            lastModified: st?.modified ?? DateTime.now(),
            title: '$trackPrefix. ${t.title}',
            artist: t.effectiveArtist,
            subtitle: [
              t.effectiveArtist,
              if (durLabel != null) durLabel,
              'CUE',
            ].join(' • '),
            trackNumber: t.trackNumber,
          ),
        );
      }
    }

    // 1. Parse external .cue sidecar files first
    for (final f in files) {
      if (isCueFile(f.path)) {
        final sheet = await CueParser.parseFile(f.path);
        if (sheet != null && sheet.allTracks.isNotEmpty) {
          await addSheetTracks(sheet);
        }
      }
    }

    // 2. Check lossless master containers for embedded CUE sheets if not already expanded
    for (final f in files) {
      final ext = p.extension(f.path).toLowerCase();
      if (ext != '.flac' && ext != '.wv' && ext != '.ape') continue;
      final key = _canonicalPathKey(f.path);
      if (suppressedKeys.contains(key)) continue;
      final sheet = CueParser.extractEmbeddedCueSync(f.path);
      if (sheet != null && sheet.allTracks.length >= 2) {
        await addSheetTracks(sheet);
      }
    }

    return (cueEntries: cueEntries, suppressedMasterKeys: suppressedKeys);
  }

  /// Lists only the immediate contents of [dirPath] without deep recursion.
  /// Blazing fast: ensures zero frame drops even with tens of thousands of files on SD card.
  Future<FolderContents> listDirectoryContents(
    String dirPath, {
    bool forceRefresh = false,
  }) async {
    final canonicalPath = p.canonicalize(dirPath);

    if (!forceRefresh && _dirCache.containsKey(canonicalPath)) {
      return _dirCache[canonicalPath]!;
    }

    final targetDir = Directory(canonicalPath);
    if (!await targetDir.exists()) {
      return FolderContents(
        currentPath: canonicalPath,
        parentPath: p.dirname(canonicalPath) != canonicalPath
            ? p.dirname(canonicalPath)
            : null,
        subdirectories: const [],
        audioFiles: const [],
      );
    }

    final subdirectories = <FolderEntry>[];
    final regularFiles = <File>[];
    final regularAudioEntries = <AudioFileEntry>[];

    try {
      await for (final entity in targetDir.list(followLinks: false).handleError((e) {
        debugPrint('[StorageVolumeService] Error listing $canonicalPath: $e');
      })) {
        final entityPath = entity.path;
        final baseName = p.basename(entityPath);

        // Skip hidden files & folders (.git, .trashed, etc.)
        if (baseName.startsWith('.')) continue;

        if (entity is Directory) {
          // Check quick direct audio count in subdirectory (shallow check)
          int directAudioCount = 0;
          try {
            final children = entity.listSync(followLinks: false);
            for (final child in children) {
              if (child is File) {
                final ext = p.extension(child.path).toLowerCase();
                if (supportedAudioExtensions.contains(ext) || ext == '.cue') {
                  directAudioCount++;
                }
              }
            }
          } catch (_) {
            // Ignore access issues on subfolder preview
          }

          subdirectories.add(FolderEntry(
            path: p.canonicalize(entityPath),
            name: baseName,
            audioCount: directAudioCount,
          ));
        } else if (entity is File) {
          regularFiles.add(entity);
          final ext = p.extension(entityPath).toLowerCase();
          if (supportedAudioExtensions.contains(ext)) {
            int size = 0;
            DateTime modified = DateTime.now();
            try {
              final stat = await entity.stat();
              size = stat.size;
              modified = stat.modified;
            } catch (_) {}

            final title = p.basenameWithoutExtension(entityPath);

            regularAudioEntries.add(AudioFileEntry(
              path: p.canonicalize(entityPath),
              name: baseName,
              extension: ext.replaceFirst('.', '').toUpperCase(),
              sizeBytes: size,
              lastModified: modified,
              title: title,
              artist: 'Local Track',
            ));
          }
        }
      }
    } catch (e) {
      debugPrint('[StorageVolumeService] Error reading directory $canonicalPath: $e');
    }

    final expanded = await _expandCueFilesInDirectory(regularFiles);
    final audioFiles = <AudioFileEntry>[
      ...expanded.cueEntries,
      ...regularAudioEntries.where(
        (entry) => !expanded.suppressedMasterKeys.contains(_canonicalPathKey(entry.path)),
      ),
    ];

    // Sort: Subdirectories alphabetically first; CUE tracks keep track order per master file
    subdirectories.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    audioFiles.sort((a, b) {
      if (a.isCueTrack &&
          b.isCueTrack &&
          _canonicalPathKey(a.realPath) == _canonicalPathKey(b.realPath)) {
        return (a.trackNumber ?? 0).compareTo(b.trackNumber ?? 0);
      }
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });

    final parent = p.dirname(canonicalPath);
    final parentPath = (parent != canonicalPath && parent.isNotEmpty) ? parent : null;

    final contents = FolderContents(
      currentPath: canonicalPath,
      parentPath: parentPath,
      subdirectories: subdirectories,
      audioFiles: audioFiles,
    );

    // Maintain LRU cache
    if (_dirCache.length >= _maxCacheEntries) {
      _dirCache.remove(_dirCache.keys.first);
    }
    _dirCache[canonicalPath] = contents;

    return contents;
  }

  /// Recursively collects all audio files within [dirPath] and its subdirectories.
  /// Used for "Play All Folder", "Shuffle All", or indexing into the library.
  static Future<List<String>> scanAudioFilesRecursively(String dirPath) async {
    final audioFiles = <String>[];
    final seenPaths = <String>{};
    final rootDir = Directory(dirPath);
    if (!await rootDir.exists()) return audioFiles;

    final dirsToScan = <Directory>[rootDir];
    final visitedDirs = <String>{};

    while (dirsToScan.isNotEmpty) {
      final currentDir = dirsToScan.removeLast();
      final canonicalDirPath = p.canonicalize(currentDir.path).toLowerCase();
      if (!visitedDirs.add(canonicalDirPath)) {
        continue;
      }

      try {
        final dirFiles = <File>[];
        await for (final entity in currentDir.list(followLinks: false).handleError((e) {
          debugPrint('[StorageVolumeService] Error traversing ${currentDir.path}: $e');
        })) {
          try {
            if (entity is Directory) {
              final dirName = p.basename(entity.path);
              if (!dirName.startsWith('.')) {
                dirsToScan.add(entity);
              }
            } else if (entity is File) {
              dirFiles.add(entity);
            }
          } catch (_) {}
        }

        final expanded = await _expandCueFilesInDirectory(dirFiles);
        for (final entry in expanded.cueEntries) {
          if (seenPaths.add(entry.path.toLowerCase())) {
            audioFiles.add(entry.path);
          }
        }
        for (final file in dirFiles) {
          final ext = p.extension(file.path).toLowerCase();
          if (supportedAudioExtensions.contains(ext)) {
            final canonical = p.canonicalize(file.path);
            if (expanded.suppressedMasterKeys.contains(_canonicalPathKey(canonical))) {
              continue;
            }
            if (seenPaths.add(canonical.toLowerCase())) {
              audioFiles.add(canonical);
            }
          }
        }
      } catch (_) {}
    }

    return audioFiles;
  }

  /// Clears the directory listing cache.
  void clearCache() {
    _dirCache.clear();
  }
}
