import 'dart:async';
import 'dart:convert';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/foundation.dart';

import '../database/preferences_store.dart';
import 'remote_file_entry.dart';
import 'remote_stream_relay.dart';

/// Configuration profile for an SFTP (SSH) server connection.
class SftpConfig {
  final String id;
  final String name;
  final String host;
  final int port;
  final String username;
  final String password;
  final String privateKeyPem;
  final String passphrase;
  final String rootPath;

  const SftpConfig({
    required this.id,
    required this.name,
    required this.host,
    this.port = 22,
    required this.username,
    this.password = '',
    this.privateKeyPem = '',
    this.passphrase = '',
    this.rootPath = '/',
  });

  bool get usesKeyAuth => privateKeyPem.trim().isNotEmpty;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'host': host,
        'port': port,
        'username': username,
        'password': password,
        'privateKeyPem': privateKeyPem,
        'passphrase': passphrase,
        'rootPath': rootPath,
      };

  factory SftpConfig.fromJson(Map<String, dynamic> json) => SftpConfig(
        id: json['id'] as String? ??
            DateTime.now().millisecondsSinceEpoch.toString(),
        name: json['name'] as String? ?? 'SFTP Server',
        host: json['host'] as String? ?? '',
        port: json['port'] as int? ?? 22,
        username: json['username'] as String? ?? '',
        password: json['password'] as String? ?? '',
        privateKeyPem: json['privateKeyPem'] as String? ?? '',
        passphrase: json['passphrase'] as String? ?? '',
        rootPath: json['rootPath'] as String? ?? '/',
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SftpConfig && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
}

class _SftpPoolEntry {
  final SSHClient client;
  final SftpClient sftp;
  DateTime lastUsed;

  _SftpPoolEntry(this.client, this.sftp) : lastUsed = DateTime.now();

  bool get isClosed => client.isClosed;

  void close() {
    try {
      sftp.close();
    } catch (_) {}
    try {
      client.close();
    } catch (_) {}
  }
}

class _SftpByteSource implements RemoteByteSource {
  final SftpConfig config;
  final RemoteFileEntry entry;

  _SftpByteSource(this.config, this.entry);

  @override
  String get id => 'sftp:${config.id}:${entry.path}';

  @override
  String get fileName => entry.name;

  @override
  int? get knownSizeBytes => entry.sizeBytes > 0 ? entry.sizeBytes : null;

  @override
  Future<int?> resolveSizeBytes() async {
    if (entry.sizeBytes > 0) return entry.sizeBytes;
    final sftp = await SftpService._acquireSftp(config);
    final stat = await sftp.stat(entry.path);
    return stat.size;
  }

  @override
  Future<Stream<Uint8List>> openRangeStream(int start, int? end) async {
    final sftp = await SftpService._acquireSftp(config);
    final file = await sftp.open(entry.path);
    final int? length = end != null ? (end - start + 1) : null;
    final rawStream = file.read(offset: start, length: length);

    return rawStream.transform(
      StreamTransformer.fromHandlers(
        handleData: (data, sink) => sink.add(data),
        handleDone: (sink) async {
          try {
            await file.close();
          } catch (_) {}
          sink.close();
        },
        handleError: (e, st, sink) async {
          try {
            await file.close();
          } catch (_) {}
          sink.addError(e, st);
        },
      ),
    );
  }
}

class SftpService {
  static const String _prefsKey = 'sftp_servers_v1';
  static final Map<String, _SftpPoolEntry> _pool = {};

  static Future<List<SftpConfig>> getSavedConfigs() async {
    try {
      final jsonStr = PreferencesStore.instance.getString(_prefsKey);
      if (jsonStr == null || jsonStr.isEmpty) return [];
      final list = jsonDecode(jsonStr) as List<dynamic>;
      return list
          .map((e) => SftpConfig.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('[SftpService] Failed to load configs: $e');
      return [];
    }
  }

  static Future<void> saveConfig(SftpConfig config) async {
    _evictPool(config.id);
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
    _evictPool(id);
    final configs = await getSavedConfigs();
    configs.removeWhere((c) => c.id == id);
    await PreferencesStore.instance
        .setString(_prefsKey, jsonEncode(configs.map((c) => c.toJson()).toList()));
  }

  static void _evictPool(String configId) {
    final existing = _pool.remove(configId);
    existing?.close();
  }

  static Future<SSHClient> _connectClient(SftpConfig config) async {
    final socket = await SSHSocket.connect(
      config.host.trim(),
      config.port,
      timeout: const Duration(seconds: 12),
    );
    List<SSHKeyPair>? identities;
    if (config.usesKeyAuth) {
      identities = SSHKeyPair.fromPem(
        config.privateKeyPem.trim(),
        config.passphrase.isEmpty ? null : config.passphrase,
      );
    }

    final client = SSHClient(
      socket,
      username: config.username.trim(),
      identities: identities,
      onPasswordRequest:
          config.password.isNotEmpty ? () => config.password : null,
      keepAliveInterval: const Duration(seconds: 20),
    );
    await client.authenticated;
    return client;
  }

  static Future<SftpClient> _acquireSftp(SftpConfig config) async {
    final existing = _pool[config.id];
    if (existing != null && !existing.isClosed) {
      existing.lastUsed = DateTime.now();
      return existing.sftp;
    }
    existing?.close();
    final client = await _connectClient(config);
    final sftp = await client.sftp();
    _pool[config.id] = _SftpPoolEntry(client, sftp);
    return sftp;
  }

  static Future<String?> testConnection(SftpConfig config) async {
    SSHClient? client;
    try {
      client = await _connectClient(config);
      final sftp = await client.sftp();
      await sftp.listdir(config.rootPath.isEmpty ? '/' : config.rootPath);
      sftp.close();
      return null;
    } catch (e) {
      return e.toString();
    } finally {
      client?.close();
    }
  }

  static Future<List<RemoteFileEntry>> listDirectory(
    SftpConfig config, {
    String? dirPath,
  }) async {
    final targetPath = (dirPath == null || dirPath.isEmpty)
        ? (config.rootPath.isEmpty ? '/' : config.rootPath)
        : dirPath;

    SftpClient sftp;
    try {
      sftp = await _acquireSftp(config);
    } catch (_) {
      _evictPool(config.id);
      sftp = await _acquireSftp(config);
    }

    List<SftpName> items;
    try {
      items = await sftp.listdir(targetPath);
    } catch (_) {
      // Retry once on stale pooled SSH session.
      _evictPool(config.id);
      sftp = await _acquireSftp(config);
      items = await sftp.listdir(targetPath);
    }

    final entries = <RemoteFileEntry>[];
    for (final item in items) {
      final name = item.filename;
      if (name == '.' || name == '..' || name.startsWith('.')) continue;
      final isDir = item.attr.isDirectory;
      final fullPath = targetPath == '/' ? '/$name' : '$targetPath/$name';
      final modTime = item.attr.modifyTime != null
          ? DateTime.fromMillisecondsSinceEpoch(item.attr.modifyTime! * 1000)
          : null;

      final entry = RemoteFileEntry(
        name: name,
        path: fullPath,
        isDirectory: isDir,
        sizeBytes: item.attr.size ?? 0,
        modifiedTime: modTime,
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
    SftpConfig config,
    RemoteFileEntry entry,
  ) =>
      _SftpByteSource(config, entry);
}
