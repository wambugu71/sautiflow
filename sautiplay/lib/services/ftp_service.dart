import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:ftpconnect/ftpconnect.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

/// Configuration profile for an FTP server connection.
class FtpConfig {
  final String id;
  final String name;
  final String host;
  final int port;
  final String user;
  final String password;
  final bool isSecure;
  final String rootPath;

  const FtpConfig({
    required this.id,
    required this.name,
    required this.host,
    this.port = 21,
    this.user = 'anonymous',
    this.password = '',
    this.isSecure = false,
    this.rootPath = '/',
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'host': host,
      'port': port,
      'user': user,
      'password': password,
      'isSecure': isSecure,
      'rootPath': rootPath,
    };
  }

  factory FtpConfig.fromJson(Map<String, dynamic> json) {
    return FtpConfig(
      id: json['id'] as String? ?? DateTime.now().millisecondsSinceEpoch.toString(),
      name: json['name'] as String? ?? 'FTP Server',
      host: json['host'] as String? ?? '',
      port: json['port'] as int? ?? 21,
      user: json['user'] as String? ?? 'anonymous',
      password: json['password'] as String? ?? '',
      isSecure: json['isSecure'] as bool? ?? false,
      rootPath: json['rootPath'] as String? ?? '/',
    );
  }

  FtpConfig copyWith({
    String? id,
    String? name,
    String? host,
    int? port,
    String? user,
    String? password,
    bool? isSecure,
    String? rootPath,
  }) {
    return FtpConfig(
      id: id ?? this.id,
      name: name ?? this.name,
      host: host ?? this.host,
      port: port ?? this.port,
      user: user ?? this.user,
      password: password ?? this.password,
      isSecure: isSecure ?? this.isSecure,
      rootPath: rootPath ?? this.rootPath,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FtpConfig && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
}

/// Represents an item (directory or audio file) in an FTP directory listing.
class FtpFileEntry {
  final String name;
  final String path;
  final bool isDirectory;
  final int sizeBytes;
  final DateTime? modifiedTime;

  const FtpFileEntry({
    required this.name,
    required this.path,
    required this.isDirectory,
    this.sizeBytes = 0,
    this.modifiedTime,
  });

  bool get isAudioFile {
    if (isDirectory) return false;
    final ext = p.extension(name).toLowerCase();
    return const [
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
      '.aiff'
    ].contains(ext);
  }
}

/// Service handling FTP server communication, directory browsing, and track downloading.
class FtpService {
  static const String _prefsKey = 'sautiplay_ftp_configs';

  static final Set<String> _audioExtensions = const {
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
  };

  /// Helper to instantiate FTPConnect instance with custom parameters.
  static FTPConnect _buildClient(FtpConfig config) {
    return FTPConnect(
      config.host,
      port: config.port,
      user: config.user,
      pass: config.password,
      timeout: 15,
      securityType:
          config.isSecure ? SecurityType.ftps : SecurityType.ftp,
      showLog: kDebugMode,
    );
  }

  /// Tests connection to the given FTP server.
  static Future<bool> testConnection(FtpConfig config) async {
    final client = _buildClient(config);
    try {
      final isConnected = await client.connect();
      if (isConnected) {
        await client.disconnect();
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('[FtpService] Connection test failed for ${config.host}: $e');
      return false;
    }
  }

  /// Lists files and subdirectories in [dirPath] on the FTP server.
  static Future<List<FtpFileEntry>> listDirectory(
    FtpConfig config, {
    String dirPath = '/',
  }) async {
    final client = _buildClient(config);
    final entries = <FtpFileEntry>[];

    try {
      final isConnected = await client.connect();
      if (!isConnected) {
        debugPrint('[FtpService] Failed to connect to ${config.host}');
        return [];
      }

      final normalizedPath = dirPath.isEmpty ? '/' : dirPath;
      await client.changeDirectory(normalizedPath);

      final rawList = await client.listDirectoryContent();
      for (final item in rawList) {
        final isDir = item.type == FTPEntryType.dir;
        final name = item.name;
        if (name == '.' || name == '..') continue;

        final ext = p.extension(name).toLowerCase();
        // Include directory OR supported audio file
        if (isDir || _audioExtensions.contains(ext)) {
          final fullPath = normalizedPath.endsWith('/')
              ? '$normalizedPath$name'
              : '$normalizedPath/$name';

          entries.add(FtpFileEntry(
            name: name,
            path: fullPath,
            isDirectory: isDir,
            sizeBytes: item.size ?? 0,
            modifiedTime: item.modifyTime,
          ));
        }
      }

      await client.disconnect();
    } catch (e) {
      debugPrint('[FtpService] Error listing directory $dirPath: $e');
    }

    // Sort directories first, then alphabetical by name
    entries.sort((a, b) {
      if (a.isDirectory && !b.isDirectory) return -1;
      if (!a.isDirectory && b.isDirectory) return 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });

    return entries;
  }

  /// Downloads a remote audio file to [targetLocalFile].
  static Future<bool> downloadFile(
    FtpConfig config,
    String remotePath,
    File targetLocalFile, {
    void Function(double progress)? onProgress,
  }) async {
    final client = _buildClient(config);
    try {
      final isConnected = await client.connect();
      if (!isConnected) return false;

      // Ensure directory exists
      if (!targetLocalFile.parent.existsSync()) {
        targetLocalFile.parent.createSync(recursive: true);
      }

      final success = await client.downloadFile(
        remotePath,
        targetLocalFile,
      );

      await client.disconnect();
      return success;
    } catch (e) {
      debugPrint('[FtpService] Error downloading file $remotePath: $e');
      return false;
    }
  }

  // ---------------------------------------------------------------------------
  // Persistence (SharedPreferences)
  // ---------------------------------------------------------------------------

  /// Retrieves saved FTP configurations from local storage.
  static Future<List<FtpConfig>> getSavedConfigs() async {
    final prefs = await SharedPreferences.getInstance();
    final rawJson = prefs.getString(_prefsKey);
    if (rawJson == null || rawJson.isEmpty) return [];

    try {
      final List decoded = jsonDecode(rawJson);
      return decoded.map((item) => FtpConfig.fromJson(item)).toList();
    } catch (e) {
      debugPrint('[FtpService] Error parsing saved configs: $e');
      return [];
    }
  }

  /// Saves or updates an FTP configuration profile.
  static Future<void> saveConfig(FtpConfig config) async {
    final configs = await getSavedConfigs();
    final index = configs.indexWhere((c) => c.id == config.id);

    if (index >= 0) {
      configs[index] = config;
    } else {
      configs.add(config);
    }

    final prefs = await SharedPreferences.getInstance();
    final jsonStr = jsonEncode(configs.map((c) => c.toJson()).toList());
    await prefs.setString(_prefsKey, jsonStr);
  }

  /// Deletes an FTP configuration profile by ID.
  static Future<void> deleteConfig(String id) async {
    final configs = await getSavedConfigs();
    configs.removeWhere((c) => c.id == id);

    final prefs = await SharedPreferences.getInstance();
    final jsonStr = jsonEncode(configs.map((c) => c.toJson()).toList());
    await prefs.setString(_prefsKey, jsonStr);
  }
}
