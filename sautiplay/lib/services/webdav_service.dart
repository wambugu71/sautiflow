import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:xml/xml.dart';

import '../database/preferences_store.dart';
import 'remote_file_entry.dart';
import 'remote_stream_relay.dart';

/// Configuration profile for a WebDAV server (Nextcloud, ownCloud, Synology, etc.).
class WebDavConfig {
  final String id;
  final String name;
  final String baseUrl;
  final String username;
  final String password;
  final String rootPath;
  final bool allowSelfSigned;

  const WebDavConfig({
    required this.id,
    required this.name,
    required this.baseUrl,
    this.username = '',
    this.password = '',
    this.rootPath = '/',
    this.allowSelfSigned = false,
  });

  String get normalizedBaseUrl {
    var url = baseUrl.trim();
    while (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      url = 'https://$url';
    }
    return url;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'baseUrl': baseUrl,
        'username': username,
        'password': password,
        'rootPath': rootPath,
        'allowSelfSigned': allowSelfSigned,
      };

  factory WebDavConfig.fromJson(Map<String, dynamic> json) => WebDavConfig(
        id: json['id'] as String? ??
            DateTime.now().millisecondsSinceEpoch.toString(),
        name: json['name'] as String? ?? 'WebDAV Server',
        baseUrl: json['baseUrl'] as String? ?? '',
        username: json['username'] as String? ?? '',
        password: json['password'] as String? ?? '',
        rootPath: json['rootPath'] as String? ?? '/',
        allowSelfSigned: json['allowSelfSigned'] as bool? ?? false,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WebDavConfig &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}

class _WebDavByteSource implements RemoteByteSource {
  final WebDavConfig config;
  final RemoteFileEntry entry;

  _WebDavByteSource(this.config, this.entry);

  @override
  String get id => 'webdav:${config.id}:${entry.path}';

  @override
  String get fileName => entry.name;

  @override
  int? get knownSizeBytes => entry.sizeBytes > 0 ? entry.sizeBytes : null;

  @override
  Future<int?> resolveSizeBytes() async {
    if (entry.sizeBytes > 0) return entry.sizeBytes;
    final client = WebDavService.createHttpClient(config);
    try {
      final uri = WebDavService.buildUri(config, entry.path);
      final req = await client.openUrl('HEAD', uri);
      WebDavService.applyAuth(req, config);
      final res = await req.close();
      await res.drain<void>();
      return res.contentLength > 0 ? res.contentLength : null;
    } finally {
      client.close(force: false);
    }
  }

  @override
  Future<Stream<Uint8List>> openRangeStream(int start, int? end) async {
    final client = WebDavService.createHttpClient(config);
    final uri = WebDavService.buildUri(config, entry.path);
    final req = await client.getUrl(uri);
    WebDavService.applyAuth(req, config);
    if (end != null) {
      req.headers.set(HttpHeaders.rangeHeader, 'bytes=$start-$end');
    } else if (start > 0) {
      req.headers.set(HttpHeaders.rangeHeader, 'bytes=$start-');
    }
    final res = await req.close();
    if (res.statusCode >= 400) {
      await res.drain<void>();
      client.close(force: true);
      throw HttpException('WebDAV HTTP ${res.statusCode}', uri: uri);
    }
    return res.transform(
      StreamTransformer.fromHandlers(
        handleData: (data, sink) => sink.add(Uint8List.fromList(data)),
        handleDone: (sink) {
          client.close(force: false);
          sink.close();
        },
        handleError: (e, st, sink) {
          client.close(force: true);
          sink.addError(e, st);
        },
      ),
    );
  }
}

class WebDavService {
  static const String _prefsKey = 'webdav_servers_v1';

  static Future<List<WebDavConfig>> getSavedConfigs() async {
    try {
      final jsonStr = PreferencesStore.instance.getString(_prefsKey);
      if (jsonStr == null || jsonStr.isEmpty) return [];
      final list = jsonDecode(jsonStr) as List<dynamic>;
      return list
          .map((e) => WebDavConfig.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('[WebDavService] Failed to load configs: $e');
      return [];
    }
  }

  static Future<void> saveConfig(WebDavConfig config) async {
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
    final configs = await getSavedConfigs();
    configs.removeWhere((c) => c.id == id);
    await PreferencesStore.instance
        .setString(_prefsKey, jsonEncode(configs.map((c) => c.toJson()).toList()));
  }

  static HttpClient createHttpClient(WebDavConfig config) {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 12);
    if (config.allowSelfSigned) {
      client.badCertificateCallback = (_, __, ___) => true;
    }
    return client;
  }

  static void applyAuth(HttpClientRequest req, WebDavConfig config) {
    if (config.username.isNotEmpty || config.password.isNotEmpty) {
      final token = base64Encode(
        utf8.encode('${config.username}:${config.password}'),
      );
      req.headers.set(HttpHeaders.authorizationHeader, 'Basic $token');
    }
  }

  static Uri buildUri(WebDavConfig config, String relativeOrFullPath) {
    final base = Uri.parse(config.normalizedBaseUrl);
    final basePath = base.path.endsWith('/')
        ? base.path.substring(0, base.path.length - 1)
        : base.path;
    final cleanRel = relativeOrFullPath.startsWith('/')
        ? relativeOrFullPath
        : '/$relativeOrFullPath';

    final fullPath = cleanRel == '/'
        ? (basePath.isEmpty ? '/' : '$basePath/')
        : '$basePath$cleanRel';

    return base.replace(path: fullPath);
  }

  static Future<String?> testConnection(WebDavConfig config) async {
    final client = createHttpClient(config);
    try {
      final uri = buildUri(config, config.rootPath);
      final req = await client.openUrl('PROPFIND', uri);
      applyAuth(req, config);
      req.headers.set('Depth', '0');
      req.headers.set(HttpHeaders.contentTypeHeader, 'application/xml; charset=utf-8');
      req.write(
        '<?xml version="1.0" encoding="utf-8"?>'
        '<d:propfind xmlns:d="DAV:"><d:prop><d:resourcetype/></d:prop></d:propfind>',
      );
      final res = await req.close();
      await res.drain<void>();
      if (res.statusCode == 401 || res.statusCode == 403) {
        return 'Authentication failed (HTTP ${res.statusCode})';
      }
      if (res.statusCode >= 400) {
        return 'HTTP ${res.statusCode}';
      }
      return null;
    } catch (e) {
      return e.toString();
    } finally {
      client.close(force: false);
    }
  }

  static Future<List<RemoteFileEntry>> listDirectory(
    WebDavConfig config, {
    String? dirPath,
  }) async {
    final targetPath = dirPath ?? config.rootPath;
    final client = createHttpClient(config);
    try {
      final uri = buildUri(config, targetPath);
      final req = await client.openUrl('PROPFIND', uri);
      applyAuth(req, config);
      req.headers.set('Depth', '1');
      req.headers.set(
        HttpHeaders.contentTypeHeader,
        'application/xml; charset=utf-8',
      );
      req.write(
        '<?xml version="1.0" encoding="utf-8"?>'
        '<d:propfind xmlns:d="DAV:">'
        '<d:prop>'
        '<d:displayname/>'
        '<d:getcontentlength/>'
        '<d:getlastmodified/>'
        '<d:resourcetype/>'
        '</d:prop>'
        '</d:propfind>',
      );
      final res = await req.close();
      final body = await utf8.decodeStream(res);
      if (res.statusCode >= 400) {
        throw HttpException('WebDAV PROPFIND HTTP ${res.statusCode}', uri: uri);
      }

      return _parsePropfindResponse(body, uri.path, targetPath, config);
    } finally {
      client.close(force: false);
    }
  }

  static List<RemoteFileEntry> _parsePropfindResponse(
    String xmlBody,
    String requestUriPath,
    String logicalDirPath,
    WebDavConfig config,
  ) {
    final doc = XmlDocument.parse(xmlBody);
    final responses = doc.descendants
        .whereType<XmlElement>()
        .where((e) => e.name.local == 'response');

    final basePath = Uri.parse(config.normalizedBaseUrl).path;
    final normalizedBasePath = basePath.endsWith('/')
        ? basePath.substring(0, basePath.length - 1)
        : basePath;
    final normalizedReqPath = _stripTrailingSlash(Uri.decodeFull(requestUriPath));

    final entries = <RemoteFileEntry>[];

    for (final resp in responses) {
      final hrefEl = resp.descendants
          .whereType<XmlElement>()
          .where((e) => e.name.local == 'href')
          .firstOrNull;
      if (hrefEl == null) continue;

      final rawHref = hrefEl.innerText.trim();
      final parsedHref = Uri.tryParse(rawHref);
      final decodedHrefPath =
          _stripTrailingSlash(Uri.decodeFull(parsedHref?.path ?? rawHref));

      // Skip the directory itself.
      if (decodedHrefPath == normalizedReqPath) continue;

      final isCollection = resp.descendants
          .whereType<XmlElement>()
          .any((e) => e.name.local == 'collection');

      final sizeEl = resp.descendants
          .whereType<XmlElement>()
          .where((e) => e.name.local == 'getcontentlength')
          .firstOrNull;
      final sizeBytes = int.tryParse(sizeEl?.innerText.trim() ?? '') ?? 0;

      final modEl = resp.descendants
          .whereType<XmlElement>()
          .where((e) => e.name.local == 'getlastmodified')
          .firstOrNull;
      DateTime? modTime;
      if (modEl != null && modEl.innerText.trim().isNotEmpty) {
        try {
          modTime = HttpDate.parse(modEl.innerText.trim());
        } catch (_) {}
      }

      // Derive logical path relative to config.baseUrl.
      var logicalPath = decodedHrefPath;
      if (normalizedBasePath.isNotEmpty &&
          logicalPath.startsWith(normalizedBasePath)) {
        logicalPath = logicalPath.substring(normalizedBasePath.length);
      }
      if (!logicalPath.startsWith('/')) logicalPath = '/$logicalPath';

      final segments =
          logicalPath.split('/').where((s) => s.isNotEmpty).toList();
      final name = segments.isNotEmpty ? segments.last : logicalPath;
      if (name.isEmpty || name.startsWith('.')) continue;

      final entry = RemoteFileEntry(
        name: name,
        path: logicalPath,
        isDirectory: isCollection,
        sizeBytes: sizeBytes,
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

  static String _stripTrailingSlash(String path) {
    if (path.length > 1 && path.endsWith('/')) {
      return path.substring(0, path.length - 1);
    }
    return path;
  }

  static RemoteByteSource createByteSource(
    WebDavConfig config,
    RemoteFileEntry entry,
  ) =>
      _WebDavByteSource(config, entry);
}
