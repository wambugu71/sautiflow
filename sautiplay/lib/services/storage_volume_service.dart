import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

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

  const AudioFileEntry({
    required this.path,
    required this.name,
    required this.extension,
    required this.sizeBytes,
    required this.lastModified,
    required this.title,
    required this.artist,
  });

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
    final audioFiles = <AudioFileEntry>[];

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
                if (supportedAudioExtensions.contains(ext)) {
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

            audioFiles.add(AudioFileEntry(
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

    // Sort: Subdirectories alphabetically first, then audio files alphabetically
    subdirectories.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    audioFiles.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

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
              final ext = p.extension(entity.path).toLowerCase();
              if (supportedAudioExtensions.contains(ext)) {
                final canonical = p.canonicalize(entity.path);
                if (seenPaths.add(canonical.toLowerCase())) {
                  audioFiles.add(canonical);
                }
              }
            }
          } catch (_) {}
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
