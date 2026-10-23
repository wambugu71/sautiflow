import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:projectm_visualizer/projectm_visualizer.dart';

/// State of the curated preset pack download & installation.
enum PackDownloadState {
  idle,
  downloading,
  extracting,
  completed,
  error,
}

/// Status payload for curated preset pack background tasks.
class ProjectMPackStatus {
  const ProjectMPackStatus({
    this.state = PackDownloadState.idle,
    this.progress = 0.0,
    this.message = '',
    this.presetCount = 0,
    this.error,
  });

  final PackDownloadState state;
  final double progress;
  final String message;
  final int presetCount;
  final String? error;

  ProjectMPackStatus copyWith({
    PackDownloadState? state,
    double? progress,
    String? message,
    int? presetCount,
    String? error,
  }) {
    return ProjectMPackStatus(
      state: state ?? this.state,
      progress: progress ?? this.progress,
      message: message ?? this.message,
      presetCount: presetCount ?? this.presetCount,
      error: error,
    );
  }
}

/// Result summary of an import operation from local storage.
class PresetImportSummary {
  const PresetImportSummary({
    required this.importedPresets,
    required this.importedTextures,
    this.error,
  });

  final List<ProjectMPreset> importedPresets;
  final int importedTextures;
  final String? error;

  bool get isSuccess => error == null;
}

/// Internal arguments transferred into the background worker isolate.
class _UnpackArgs {
  const _UnpackArgs({
    required this.archivePath,
    required this.targetPresetsDirPath,
    required this.texturesDirPath,
    required this.category,
  });

  final String archivePath;
  final String targetPresetsDirPath;
  final String texturesDirPath;
  final String category;
}

/// Internal result emitted by the background worker isolate.
class _UnpackResult {
  const _UnpackResult({
    required this.presetCount,
    required this.textureCount,
    required this.presetFiles,
    this.error,
  });

  final int presetCount;
  final int textureCount;
  final List<String> presetFiles;
  final String? error;
}

/// Senior-engineered Milkdrop preset manager.
///
/// Features:
/// - Background threaded streaming download of curated preset packs (Poweramp viz sets).
/// - Thread-isolated unzipping and parsing via [Isolate.run] to guarantee zero UI jank.
/// - Safe persistent storage under application support directory.
/// - Dynamic local file importing (.milk files, .zip archives, .apk packs).
/// - Automatic texture search path indexing for libprojectM texture samplers.
class ProjectMPresetManager {
  ProjectMPresetManager._();

  static final ProjectMPresetManager instance = ProjectMPresetManager._();

  /// Official release URL of the curated Poweramp Milkdrop presets APK pack.
  static const String curatedPackUrl =
      'https://github.com/SpasilliumNexus/poweramp-visualizer-presets/releases/download/1.2/com.poweramp.v3.vispresets.curatedvizsets-3.apk';
  static const String curatedPackFileName =
      'com.poweramp.v3.vispresets.curatedvizsets-3.apk';

  bool _isInitialized = false;
  Directory? _baseDir;
  Directory? _curatedDir;
  Directory? _importedDir;
  Directory? _texturesDir;
  Directory? _downloadsDir;

  http.Client? _activeClient;
  bool _cancelRequested = false;

  final ValueNotifier<ProjectMPackStatus> statusNotifier =
      ValueNotifier<ProjectMPackStatus>(const ProjectMPackStatus());

  final ValueNotifier<List<ProjectMPreset>> presetsNotifier =
      ValueNotifier<List<ProjectMPreset>>(ProjectMPresetLibrary.all);

  /// Ensure directories exist and scan previously downloaded/imported presets.
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      final appSupport = await getApplicationSupportDirectory();
      _baseDir = Directory(p.join(appSupport.path, 'projectm_presets'));
      _curatedDir = Directory(p.join(_baseDir!.path, 'curated'));
      _importedDir = Directory(p.join(_baseDir!.path, 'imported'));
      _texturesDir = Directory(p.join(_baseDir!.path, 'textures'));
      _downloadsDir = Directory(p.join(_baseDir!.path, 'downloads'));

      await _curatedDir!.create(recursive: true);
      await _importedDir!.create(recursive: true);
      await _texturesDir!.create(recursive: true);
      await _downloadsDir!.create(recursive: true);

      await refreshPresets();
      _isInitialized = true;
    } catch (e) {
      debugPrint('ProjectMPresetManager initialization error: $e');
    }
  }

  /// Get the active path to texture bitmaps (used by projectM presets).
  String? getTexturesPath() {
    if (_texturesDir != null && _texturesDir!.existsSync()) {
      return _texturesDir!.path;
    }
    return null;
  }

  /// True if the curated Poweramp pack has already been downloaded and unpacked.
  bool get isCuratedPackDownloaded {
    if (_curatedDir == null || !_curatedDir!.existsSync()) return false;
    final milks = _curatedDir!
        .listSync()
        .where((f) => f.path.toLowerCase().endsWith('.milk'));
    return milks.isNotEmpty;
  }

  /// Total count of curated presets currently available locally on disk.
  int get curatedPresetCount {
    if (_curatedDir == null || !_curatedDir!.existsSync()) return 0;
    return _curatedDir!
        .listSync()
        .where((f) => f.path.toLowerCase().endsWith('.milk'))
        .length;
  }

  /// Total count of user-imported presets currently available locally on disk.
  int get importedPresetCount {
    if (_importedDir == null || !_importedDir!.existsSync()) return 0;
    return _importedDir!
        .listSync(recursive: true)
        .where((f) => f.path.toLowerCase().endsWith('.milk'))
        .length;
  }

  /// Scan storage directories and synchronize [ProjectMPresetLibrary].
  Future<void> refreshPresets() async {
    if (_baseDir == null) return;

    final List<ProjectMPreset> discovered = [];

    // 1. Scan curated presets
    if (_curatedDir != null && _curatedDir!.existsSync()) {
      final files = _curatedDir!
          .listSync()
          .where((f) => f is File && f.path.toLowerCase().endsWith('.milk'))
          .cast<File>()
          .toList();
      files.sort((a, b) => p.basename(a.path).compareTo(p.basename(b.path)));

      for (final file in files) {
        discovered.add(
          _createPresetFromFile(file, category: 'Poweramp Curated'),
        );
      }
    }

    // 2. Scan user imported presets
    if (_importedDir != null && _importedDir!.existsSync()) {
      final files = _importedDir!
          .listSync(recursive: true)
          .where((f) => f is File && f.path.toLowerCase().endsWith('.milk'))
          .cast<File>()
          .toList();
      files.sort((a, b) => p.basename(a.path).compareTo(p.basename(b.path)));

      for (final file in files) {
        discovered.add(
          _createPresetFromFile(file, category: 'Imported'),
        );
      }
    }

    // 3. Update global library & observable notifier
    ProjectMPresetLibrary.clearCustomPresets();
    ProjectMPresetLibrary.registerCustomPresets(discovered);

    presetsNotifier.value = ProjectMPresetLibrary.allWithCustom;
    statusNotifier.value = statusNotifier.value.copyWith(
      presetCount: discovered.length,
      state: isCuratedPackDownloaded
          ? PackDownloadState.completed
          : PackDownloadState.idle,
      message: isCuratedPackDownloaded
          ? 'Curated pack installed (${curatedPresetCount} presets)'
          : 'Ready to download',
    );
  }

  /// Download the community curated Poweramp visualizer preset APK in a background stream,
  /// then unpacks all .milk presets and textures in a separate worker isolate.
  Future<bool> downloadAndInstallCuratedPack({
    void Function(double progress, String status)? onProgress,
  }) async {
    await initialize();
    if (statusNotifier.value.state == PackDownloadState.downloading ||
        statusNotifier.value.state == PackDownloadState.extracting) {
      return false;
    }

    _cancelRequested = false;
    _activeClient = http.Client();

    final tempApkFile = File(p.join(_downloadsDir!.path, curatedPackFileName));

    try {
      statusNotifier.value = statusNotifier.value.copyWith(
        state: PackDownloadState.downloading,
        progress: 0.0,
        message: 'Connecting to GitHub releases...',
        error: null,
      );
      onProgress?.call(0.0, 'Connecting to GitHub releases...');

      final request = http.Request('GET', Uri.parse(curatedPackUrl));
      request.headers['User-Agent'] = 'Sautiplay-ProjectM/1.0';

      final streamedResponse = await _activeClient!.send(request);

      if (streamedResponse.statusCode != 200) {
        throw HttpException(
          'Download failed with HTTP ${streamedResponse.statusCode}',
        );
      }

      final totalBytes = streamedResponse.contentLength ?? -1;
      int bytesReceived = 0;

      final sink = tempApkFile.openWrite();

      await for (final chunk in streamedResponse.stream) {
        if (_cancelRequested) {
          await sink.close();
          if (tempApkFile.existsSync()) tempApkFile.deleteSync();
          statusNotifier.value = statusNotifier.value.copyWith(
            state: PackDownloadState.idle,
            message: 'Download cancelled',
          );
          onProgress?.call(0.0, 'Download cancelled');
          return false;
        }

        sink.add(chunk);
        bytesReceived += chunk.length;

        if (totalBytes > 0) {
          final progress = (bytesReceived / totalBytes).clamp(0.0, 1.0);
          final mbReceived = (bytesReceived / (1024 * 1024)).toStringAsFixed(1);
          final mbTotal = (totalBytes / (1024 * 1024)).toStringAsFixed(1);
          final msg = 'Downloading: ${(progress * 100).toStringAsFixed(0)}% ($mbReceived / $mbTotal MB)';

          statusNotifier.value = statusNotifier.value.copyWith(
            state: PackDownloadState.downloading,
            progress: progress,
            message: msg,
          );
          onProgress?.call(progress, msg);
        } else {
          final mbReceived = (bytesReceived / (1024 * 1024)).toStringAsFixed(1);
          final msg = 'Downloading: $mbReceived MB';
          statusNotifier.value = statusNotifier.value.copyWith(
            state: PackDownloadState.downloading,
            progress: 0.5,
            message: msg,
          );
          onProgress?.call(0.5, msg);
        }
      }

      await sink.flush();
      await sink.close();

      // Background Isolate Unpacking
      statusNotifier.value = statusNotifier.value.copyWith(
        state: PackDownloadState.extracting,
        progress: 1.0,
        message: 'Unpacking Milkdrop equations & textures in background isolate...',
      );
      onProgress?.call(1.0, 'Unpacking Milkdrop equations & textures in background isolate...');

      final unpackArgs = _UnpackArgs(
        archivePath: tempApkFile.path,
        targetPresetsDirPath: _curatedDir!.path,
        texturesDirPath: _texturesDir!.path,
        category: 'Poweramp Curated',
      );

      final result = await Isolate.run(() => _unpackArchiveWorker(unpackArgs));

      if (result.error != null) {
        throw StateError(result.error!);
      }

      // Cleanup downloaded APK cache to save flash memory
      if (tempApkFile.existsSync()) {
        try {
          tempApkFile.deleteSync();
        } catch (_) {}
      }

      // Refresh preset registry
      await refreshPresets();

      statusNotifier.value = statusNotifier.value.copyWith(
        state: PackDownloadState.completed,
        progress: 1.0,
        presetCount: result.presetCount,
        message: 'Successfully installed ${result.presetCount} presets & ${result.textureCount} textures!',
      );
      onProgress?.call(
        1.0,
        'Successfully installed ${result.presetCount} presets & ${result.textureCount} textures!',
      );

      return true;
    } catch (e) {
      debugPrint('Curated pack download/install error: $e');
      if (tempApkFile.existsSync()) {
        try {
          tempApkFile.deleteSync();
        } catch (_) {}
      }
      statusNotifier.value = statusNotifier.value.copyWith(
        state: PackDownloadState.error,
        message: 'Download error: $e',
        error: e.toString(),
      );
      onProgress?.call(0.0, 'Error: $e');
      return false;
    } finally {
      _activeClient?.close();
      _activeClient = null;
    }
  }

  /// Cancel any active in-flight curated pack download.
  void cancelDownload() {
    _cancelRequested = true;
    _activeClient?.close();
    _activeClient = null;
  }

  /// Download and install preset files or archives from a custom GitHub repository or web URL.
  Future<bool> downloadCustomPackFromUrl(
    String url, {
    String packName = 'GitHub Preset Pack',
    void Function(double progress, String status)? onProgress,
  }) async {
    await initialize();
    if (statusNotifier.value.state == PackDownloadState.downloading ||
        statusNotifier.value.state == PackDownloadState.extracting) {
      return false;
    }

    _cancelRequested = false;
    _activeClient = http.Client();
    final uri = Uri.tryParse(url.trim());
    if (uri == null || !uri.hasScheme) {
      statusNotifier.value = statusNotifier.value.copyWith(
        state: PackDownloadState.error,
        message: 'Invalid URL provided',
        error: 'Invalid URL',
      );
      return false;
    }

    final rawFileName = p.basename(uri.path);
    final fileName = rawFileName.isNotEmpty ? rawFileName : 'github_presets.zip';
    final tempFile = File(p.join(_downloadsDir!.path, fileName));

    try {
      statusNotifier.value = statusNotifier.value.copyWith(
        state: PackDownloadState.downloading,
        progress: 0.0,
        message: 'Connecting to $packName...',
        error: null,
      );
      onProgress?.call(0.0, 'Connecting to $packName...');

      final request = http.Request('GET', uri);
      request.headers['User-Agent'] = 'Sautiplay-ProjectM/1.0';

      final streamedResponse = await _activeClient!.send(request);
      if (streamedResponse.statusCode != 200) {
        throw HttpException('Download failed with HTTP ${streamedResponse.statusCode}');
      }

      final totalBytes = streamedResponse.contentLength ?? -1;
      int bytesReceived = 0;
      final sink = tempFile.openWrite();

      await for (final chunk in streamedResponse.stream) {
        if (_cancelRequested) {
          await sink.close();
          if (tempFile.existsSync()) tempFile.deleteSync();
          statusNotifier.value = statusNotifier.value.copyWith(
            state: PackDownloadState.idle,
            message: 'Download cancelled',
          );
          return false;
        }

        sink.add(chunk);
        bytesReceived += chunk.length;

        if (totalBytes > 0) {
          final progress = (bytesReceived / totalBytes).clamp(0.0, 1.0);
          final mbReceived = (bytesReceived / (1024 * 1024)).toStringAsFixed(1);
          final mbTotal = (totalBytes / (1024 * 1024)).toStringAsFixed(1);
          final msg = 'Downloading: ${(progress * 100).toStringAsFixed(0)}% ($mbReceived / $mbTotal MB)';
          statusNotifier.value = statusNotifier.value.copyWith(
            state: PackDownloadState.downloading,
            progress: progress,
            message: msg,
          );
          onProgress?.call(progress, msg);
        } else {
          final mbReceived = (bytesReceived / (1024 * 1024)).toStringAsFixed(1);
          final msg = 'Downloading: $mbReceived MB';
          statusNotifier.value = statusNotifier.value.copyWith(
            state: PackDownloadState.downloading,
            progress: 0.5,
            message: msg,
          );
          onProgress?.call(0.5, msg);
        }
      }

      await sink.flush();
      await sink.close();

      // If it's a standalone .milk file, copy directly to imported
      if (fileName.toLowerCase().endsWith('.milk')) {
        final dest = File(p.join(_importedDir!.path, fileName));
        await tempFile.copy(dest.path);
        if (tempFile.existsSync()) tempFile.deleteSync();
        await refreshPresets();
        statusNotifier.value = statusNotifier.value.copyWith(
          state: PackDownloadState.completed,
          progress: 1.0,
          presetCount: 1,
          message: 'Installed $fileName successfully!',
        );
        return true;
      }

      // Unpack archive in worker isolate
      statusNotifier.value = statusNotifier.value.copyWith(
        state: PackDownloadState.extracting,
        progress: 1.0,
        message: 'Extracting preset equations in worker isolate...',
      );
      onProgress?.call(1.0, 'Extracting preset equations...');

      final unpackArgs = _UnpackArgs(
        archivePath: tempFile.path,
        targetPresetsDirPath: _importedDir!.path,
        texturesDirPath: _texturesDir!.path,
        category: packName,
      );

      final result = await Isolate.run(() => _unpackArchiveWorker(unpackArgs));
      if (result.error != null) throw StateError(result.error!);

      if (tempFile.existsSync()) {
        try {
          tempFile.deleteSync();
        } catch (_) {}
      }

      await refreshPresets();
      statusNotifier.value = statusNotifier.value.copyWith(
        state: PackDownloadState.completed,
        progress: 1.0,
        presetCount: result.presetCount,
        message: 'Successfully installed ${result.presetCount} presets from GitHub!',
      );
      onProgress?.call(1.0, 'Installed ${result.presetCount} presets');
      return true;
    } catch (e) {
      debugPrint('Custom pack download error: $e');
      if (tempFile.existsSync()) {
        try {
          tempFile.deleteSync();
        } catch (_) {}
      }
      statusNotifier.value = statusNotifier.value.copyWith(
        state: PackDownloadState.error,
        message: 'Download failed: $e',
        error: e.toString(),
      );
      onProgress?.call(0.0, 'Error: $e');
      return false;
    } finally {
      _activeClient?.close();
      _activeClient = null;
    }
  }

  /// Open file picker to import custom `.milk` presets, `.zip` archives, or `.apk` packs from disk.
  Future<PresetImportSummary> pickAndImportFromDisk({
    void Function(String message)? onStatus,
  }) async {
    await initialize();

    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['milk', 'zip', 'apk'],
        allowMultiple: true,
      );

      if (result == null || result.files.isEmpty) {
        return const PresetImportSummary(
          importedPresets: [],
          importedTextures: 0,
        );
      }

      onStatus?.call('Importing ${result.files.length} selected files...');

      final List<ProjectMPreset> newlyImported = [];
      int totalTextures = 0;

      for (final picked in result.files) {
        final path = picked.path;
        if (path == null || !File(path).existsSync()) continue;

        final fileName = picked.name;
        final lower = fileName.toLowerCase();

        if (lower.endsWith('.zip') || lower.endsWith('.apk')) {
          onStatus?.call('Unpacking $fileName in background isolate...');
          final packSubDirName = p
              .basenameWithoutExtension(fileName)
              .replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
          final targetSubDir = Directory(
            p.join(_importedDir!.path, packSubDirName),
          );
          await targetSubDir.create(recursive: true);

          final unpackArgs = _UnpackArgs(
            archivePath: path,
            targetPresetsDirPath: targetSubDir.path,
            texturesDirPath: _texturesDir!.path,
            category: 'Imported: $packSubDirName',
          );

          final unpackResult =
              await Isolate.run(() => _unpackArchiveWorker(unpackArgs));

          totalTextures += unpackResult.textureCount;
          for (final filePath in unpackResult.presetFiles) {
            newlyImported.add(
              _createPresetFromFile(
                File(filePath),
                category: 'Imported: $packSubDirName',
              ),
            );
          }
        } else if (lower.endsWith('.milk')) {
          final destFile = File(p.join(_importedDir!.path, fileName));
          await File(path).copy(destFile.path);
          newlyImported.add(
            _createPresetFromFile(destFile, category: 'Imported'),
          );
        }
      }

      await refreshPresets();

      onStatus?.call(
        'Imported ${newlyImported.length} presets (${totalTextures} textures).',
      );

      return PresetImportSummary(
        importedPresets: newlyImported,
        importedTextures: totalTextures,
      );
    } catch (e) {
      debugPrint('Error importing presets from disk: $e');
      return PresetImportSummary(
        importedPresets: [],
        importedTextures: 0,
        error: e.toString(),
      );
    }
  }

  /// Remove all presets in the curated pack and reset status.
  Future<void> deleteCuratedPack() async {
    if (_curatedDir != null && _curatedDir!.existsSync()) {
      try {
        _curatedDir!.deleteSync(recursive: true);
        await _curatedDir!.create(recursive: true);
        await refreshPresets();
      } catch (e) {
        debugPrint('Error deleting curated pack: $e');
      }
    }
  }

  /// Remove a specific custom preset from storage and registry.
  Future<bool> deletePreset(ProjectMPreset preset) async {
    if (preset.filePath == null) return false;
    try {
      final file = File(preset.filePath!);
      if (file.existsSync()) {
        file.deleteSync();
      }
      ProjectMPresetLibrary.removeCustomPreset(preset.id);
      await refreshPresets();
      return true;
    } catch (e) {
      debugPrint('Error deleting preset: $e');
      return false;
    }
  }

  static ProjectMPreset _createPresetFromFile(File file, {required String category}) {
    final fileName = p.basename(file.path);
    final baseName = p.basenameWithoutExtension(fileName);
    final cleanTitle = baseName
        .replaceAll(RegExp(r'^\d+-'), '')
        .replaceAll('-', ' ')
        .replaceAll('_', ' ')
        .split(' ')
        .where((w) => w.isNotEmpty)
        .map((w) => '${w[0].toUpperCase()}${w.substring(1)}')
        .join(' ');

    return ProjectMPreset(
      id: file.path,
      displayName: cleanTitle.isEmpty ? fileName : cleanTitle,
      category: category,
      description: 'Milkdrop preset from $fileName',
      filePath: file.path,
    );
  }

  /// Pure worker function running in an isolated background thread via [Isolate.run].
  ///
  /// Unzips `.milk` preset equations and image textures directly to disk
  /// without locking the Flutter UI thread.
  static _UnpackResult _unpackArchiveWorker(_UnpackArgs args) {
    try {
      final archiveFile = File(args.archivePath);
      if (!archiveFile.existsSync()) {
        return const _UnpackResult(
          presetCount: 0,
          textureCount: 0,
          presetFiles: [],
          error: 'Archive file not found',
        );
      }

      final bytes = archiveFile.readAsBytesSync();
      final archive = ZipDecoder().decodeBytes(bytes);

      final targetDir = Directory(args.targetPresetsDirPath);
      if (!targetDir.existsSync()) {
        targetDir.createSync(recursive: true);
      }

      final texturesDir = Directory(args.texturesDirPath);
      if (!texturesDir.existsSync()) {
        texturesDir.createSync(recursive: true);
      }

      final List<String> presetFiles = [];
      int textureCount = 0;

      for (final file in archive) {
        if (!file.isFile) continue;
        final rawName = file.name;
        final lower = rawName.toLowerCase();

        // 1. Milkdrop preset equations (.milk)
        if (lower.endsWith('.milk')) {
          final simpleName = rawName.split('/').last.split('\\').last;
          if (simpleName.isEmpty) continue;

          final outFile = File(p.join(targetDir.path, simpleName));
          final data = file.content as List<int>;
          outFile.writeAsBytesSync(data, flush: true);
          presetFiles.add(outFile.path);
        }
        // 2. Texture bitmaps referenced by Milkdrop equations
        else if (lower.contains('texture') ||
            lower.endsWith('.jpg') ||
            lower.endsWith('.jpeg') ||
            lower.endsWith('.png') ||
            lower.endsWith('.tga') ||
            lower.endsWith('.bmp')) {
          final simpleName = rawName.split('/').last.split('\\').last;
          if (simpleName.isEmpty) continue;

          final outFile = File(p.join(texturesDir.path, simpleName));
          final data = file.content as List<int>;
          outFile.writeAsBytesSync(data, flush: true);
          textureCount++;
        }
      }

      return _UnpackResult(
        presetCount: presetFiles.length,
        textureCount: textureCount,
        presetFiles: presetFiles,
      );
    } catch (e) {
      return _UnpackResult(
        presetCount: 0,
        textureCount: 0,
        presetFiles: [],
        error: e.toString(),
      );
    }
  }
}
