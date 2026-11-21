import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:smb_connect/smb_connect.dart';

import '../database/preferences_store.dart';
import 'remote_file_entry.dart';
import 'remote_stream_relay.dart';

/// Configuration profile for an SMB/CIFS (Samba / Windows / NAS) share.
class SmbConfig {
  final String id;
  final String name;
  final String host;
  final String domain;
  final String username;
  final String password;
  final String rootPath;
  final bool forceSmb1;

  const SmbConfig({
    required this.id,
    required this.name,
    required this.host,
    this.domain = '',
    this.username = '',
    this.password = '',
    this.rootPath = '/',
    this.forceSmb1 = false,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'host': host,
        'domain': domain,
        'username': username,
        'password': password,
        'rootPath': rootPath,
        'forceSmb1': forceSmb1,
      };

  factory SmbConfig.fromJson(Map<String, dynamic> json) => SmbConfig(
        id: json['id'] as String? ??
            DateTime.now().millisecondsSinceEpoch.toString(),
        name: json['name'] as String? ?? 'SMB Share',
        host: json['host'] as String? ?? '',
        domain: json['domain'] as String? ?? '',
        username: json['username'] as String? ?? '',
        password: json['password'] as String? ?? '',
        rootPath: json['rootPath'] as String? ?? '/',
        forceSmb1: json['forceSmb1'] as bool? ?? false,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SmbConfig && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
}

class _SmbByteSource implements RemoteByteSource {
  final SmbConfig config;
  final RemoteFileEntry entry;

  _SmbByteSource(this.config, this.entry);

  @override
  String get id => 'smb:${config.id}:${entry.path}';

  @override
  String get fileName => entry.name;

  @override
  int? get knownSizeBytes => entry.sizeBytes > 0 ? entry.sizeBytes : null;

  @override
  Future<int?> resolveSizeBytes() async {
    if (entry.sizeBytes > 0) return entry.sizeBytes;
    SmbConnect conn = await SmbService._acquireConnection(config);
    try {
      final file = await conn.file(entry.path);
      return file.size > 0 ? file.size : null;
    } catch (_) {
      await SmbService._evictIfSame(config.id, conn);
      conn = await SmbService._acquireConnection(config);
      final file = await conn.file(entry.path);
      return file.size > 0 ? file.size : null;
    }
  }

  @override
  Future<Stream<Uint8List>> openRangeStream(int start, int? end) async {
    return _openRangeStreamWithRetry(start, end);
  }

  Stream<Uint8List> _openRangeStreamWithRetry(int start, int? end) async* {
    int currentStart = start;
    for (int attempt = 0; attempt < 2; attempt++) {
      if (end != null && currentStart > end) return;
      final conn = await SmbService._acquireConnection(config);
      try {
        final file = await conn.file(entry.path);
        // smb_connect openRead uses exclusive end offset if specified.
        final int? exclusiveEnd = end != null ? end + 1 : null;
        final stream = await conn.openRead(file, currentStart, exclusiveEnd);
        await for (final chunk in stream) {
          currentStart += chunk.length;
          yield chunk;
        }
        return;
      } catch (e) {
        await SmbService._evictIfSame(config.id, conn);
        if (attempt == 1) rethrow;
      }
    }
  }
}

class SmbService {
  static const String _prefsKey = 'smb_servers_v1';
  static final Map<String, SmbConnect> _pool = {};
  static final Map<String, Future<SmbConnect>> _pendingConnections = {};

  static Future<List<SmbConfig>> getSavedConfigs() async {
    try {
      final jsonStr = PreferencesStore.instance.getString(_prefsKey);
      if (jsonStr == null || jsonStr.isEmpty) return [];
      final list = jsonDecode(jsonStr) as List<dynamic>;
      return list
          .map((e) => SmbConfig.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('[SmbService] Failed to load configs: $e');
      return [];
    }
  }

  static Future<void> saveConfig(SmbConfig config) async {
    await _evictPool(config.id);
    final configs = await getSavedConfigs();
    final idx = configs.indexWhere((c) => c.id == config.id);
    if (idx >= 0) {
      configs[idx] = config;
    } else {
      configs.add(config);
    }
    await PreferencesStore.instance
        .setString(_prefsKey, jsonEncode(configs.map((c) => c.toJson()).toList()));
  }

  static Future<void> deleteConfig(String id) async {
    await _evictPool(id);
    final configs = await getSavedConfigs();
    configs.removeWhere((c) => c.id == id);
    await PreferencesStore.instance
        .setString(_prefsKey, jsonEncode(configs.map((c) => c.toJson()).toList()));
  }

  static Future<void> _evictPool(String id) async {
    final existing = _pool.remove(id);
    if (existing != null) {
      try {
        await existing.close();
      } catch (_) {}
    }
  }

  static Future<void> _evictIfSame(String id, SmbConnect conn) async {
    if (identical(_pool[id], conn)) {
      _pool.remove(id);
    }
    try {
      await conn.close();
    } catch (_) {}
  }

  static Future<SmbConnect> _acquireConnection(SmbConfig config) async {
    final existing = _pool[config.id];
    if (existing != null) return existing;

    final inFlight = _pendingConnections[config.id];
    if (inFlight != null) return inFlight;

    final future = () async {
      final conn = await SmbConnect.connectAuth(
        host: config.host.trim(),
        domain: config.domain.trim(),
        username: config.username.trim(),
        password: config.password,
        forceSmb1: config.forceSmb1,
        onDisconnect: (_) {
          _pool.remove(config.id);
        },
      );
      _pool[config.id] = conn;
      return conn;
    }();

    _pendingConnections[config.id] = future;
    try {
      return await future;
    } finally {
      if (identical(_pendingConnections[config.id], future)) {
        _pendingConnections.remove(config.id);
      }
    }
  }

  static Future<String?> testConnection(SmbConfig config) async {
    SmbConnect? conn;
    try {
      conn = await SmbConnect.connectAuth(
        host: config.host.trim(),
        domain: config.domain.trim(),
        username: config.username.trim(),
        password: config.password,
        forceSmb1: config.forceSmb1,
      );
      final shares = await conn.listShares();
      if (shares.isEmpty) {
        return 'Connected, but no accessible shares found.';
      }
      return null;
    } catch (e) {
      return e.toString();
    } finally {
      try {
        await conn?.close();
      } catch (_) {}
    }
  }

  static Future<List<RemoteFileEntry>> listDirectory(
    SmbConfig config, {
    String? dirPath,
  }) async {
    final targetPath = (dirPath == null || dirPath.isEmpty)
        ? (config.rootPath.isEmpty ? '/' : config.rootPath)
        : dirPath;

    SmbConnect conn;
    try {
      conn = await _acquireConnection(config);
    } catch (_) {
      await _evictPool(config.id);
      conn = await _acquireConnection(config);
    }

    List<SmbFile> smbFiles;
    try {
      if (targetPath == '/') {
        smbFiles = await conn.listShares();
      } else {
        final folder = await conn.file(targetPath);
        smbFiles = await conn.listFiles(folder);
      }
    } catch (_) {
      await _evictPool(config.id);
      conn = await _acquireConnection(config);
      if (targetPath == '/') {
        smbFiles = await conn.listShares();
      } else {
        final folder = await conn.file(targetPath);
        smbFiles = await conn.listFiles(folder);
      }
    }

    final entries = <RemoteFileEntry>[];
    for (final f in smbFiles) {
      final name = f.name;
      if (name.isEmpty ||
          name == '.' ||
          name == '..' ||
          name.startsWith('.') ||
          name.endsWith('\$')) {
        continue;
      }
      final isDir = targetPath == '/' ? true : f.isDirectory();
      final normalizedPath =
          f.path.startsWith('/') ? f.path : '/${f.path}';

      final entry = RemoteFileEntry(
        name: name,
        path: normalizedPath,
        isDirectory: isDir,
        sizeBytes: f.size,
        modifiedTime: f.lastModified > 0
            ? DateTime.fromMillisecondsSinceEpoch(f.lastModified)
            : null,
        shareName: f.share,
      );

      if (entry.isDirectory || entry.isAudioFile) {
        entries.add(entry);
      }
    }

    entries.sort((a, b) {
      if (a.isDirectory != b.isDirectory) return a.isDirectory ? -1 : 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return entries;
  }

  static RemoteByteSource createByteSource(
    SmbConfig config,
    RemoteFileEntry entry,
  ) =>
      _SmbByteSource(config, entry);
}
