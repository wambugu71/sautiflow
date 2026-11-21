import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../database/preferences_store.dart';

/// Configuration for a Navidrome / Subsonic / Airsonic / Gonic server.
class SubsonicConfig {
  final String id;
  final String name;
  final String baseUrl;
  final String username;
  final String password;
  final bool usePlaintextAuth;

  /// `'raw'` for bit-perfect original audio, or `'mp3'` / `'opus'` / `'aac'`.
  final String transcodeFormat;

  /// Max bitrate in kbps when [transcodeFormat] is not `'raw'` (0 = unlimited).
  final int maxBitRate;

  const SubsonicConfig({
    required this.id,
    required this.name,
    required this.baseUrl,
    required this.username,
    required this.password,
    this.usePlaintextAuth = false,
    this.transcodeFormat = 'raw',
    this.maxBitRate = 0,
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
        'usePlaintextAuth': usePlaintextAuth,
        'transcodeFormat': transcodeFormat,
        'maxBitRate': maxBitRate,
      };

  factory SubsonicConfig.fromJson(Map<String, dynamic> json) => SubsonicConfig(
        id: json['id'] as String? ??
            DateTime.now().millisecondsSinceEpoch.toString(),
        name: json['name'] as String? ?? 'Navidrome',
        baseUrl: json['baseUrl'] as String? ?? '',
        username: json['username'] as String? ?? '',
        password: json['password'] as String? ?? '',
        usePlaintextAuth: json['usePlaintextAuth'] as bool? ?? false,
        transcodeFormat: json['transcodeFormat'] as String? ?? 'raw',
        maxBitRate: json['maxBitRate'] as int? ?? 0,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SubsonicConfig &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}

class SubsonicArtist {
  final String id;
  final String name;
  final int albumCount;
  final String? coverArtId;

  const SubsonicArtist({
    required this.id,
    required this.name,
    this.albumCount = 0,
    this.coverArtId,
  });

  factory SubsonicArtist.fromJson(Map<String, dynamic> json) => SubsonicArtist(
        id: json['id']?.toString() ?? '',
        name: json['name']?.toString() ?? 'Unknown Artist',
        albumCount: (json['albumCount'] as num?)?.toInt() ?? 0,
        coverArtId: json['coverArt']?.toString(),
      );
}

class SubsonicAlbum {
  final String id;
  final String name;
  final String artist;
  final String? artistId;
  final int songCount;
  final int durationSeconds;
  final int? year;
  final String? genre;
  final String? coverArtId;

  const SubsonicAlbum({
    required this.id,
    required this.name,
    required this.artist,
    this.artistId,
    this.songCount = 0,
    this.durationSeconds = 0,
    this.year,
    this.genre,
    this.coverArtId,
  });

  factory SubsonicAlbum.fromJson(Map<String, dynamic> json) => SubsonicAlbum(
        id: json['id']?.toString() ?? '',
        name: (json['name'] ?? json['title'])?.toString() ?? 'Unknown Album',
        artist: json['artist']?.toString() ?? 'Unknown Artist',
        artistId: json['artistId']?.toString(),
        songCount: (json['songCount'] as num?)?.toInt() ?? 0,
        durationSeconds: (json['duration'] as num?)?.toInt() ?? 0,
        year: (json['year'] as num?)?.toInt(),
        genre: json['genre']?.toString(),
        coverArtId: json['coverArt']?.toString(),
      );
}

class SubsonicPlaylist {
  final String id;
  final String name;
  final int songCount;
  final int durationSeconds;
  final String? coverArtId;

  const SubsonicPlaylist({
    required this.id,
    required this.name,
    this.songCount = 0,
    this.durationSeconds = 0,
    this.coverArtId,
  });

  factory SubsonicPlaylist.fromJson(Map<String, dynamic> json) =>
      SubsonicPlaylist(
        id: json['id']?.toString() ?? '',
        name: json['name']?.toString() ?? 'Playlist',
        songCount: (json['songCount'] as num?)?.toInt() ?? 0,
        durationSeconds: (json['duration'] as num?)?.toInt() ?? 0,
        coverArtId: json['coverArt']?.toString(),
      );
}

class SubsonicTrack {
  final String id;
  final String title;
  final String artist;
  final String? artistId;
  final String? album;
  final String? albumId;
  final int? trackNumber;
  final int durationSeconds;
  final String? suffix;
  final int? bitRate;
  final int? samplingRate;
  final int? bitDepth;
  final String? coverArtId;
  final double? replayGainTrackDb;
  final double? replayGainAlbumDb;

  const SubsonicTrack({
    required this.id,
    required this.title,
    required this.artist,
    this.artistId,
    this.album,
    this.albumId,
    this.trackNumber,
    this.durationSeconds = 0,
    this.suffix,
    this.bitRate,
    this.samplingRate,
    this.bitDepth,
    this.coverArtId,
    this.replayGainTrackDb,
    this.replayGainAlbumDb,
  });

  factory SubsonicTrack.fromJson(Map<String, dynamic> json) {
    final rg = json['replayGain'] as Map<String, dynamic>?;
    return SubsonicTrack(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? 'Unknown Track',
      artist: json['artist']?.toString() ?? 'Unknown Artist',
      artistId: json['artistId']?.toString(),
      album: json['album']?.toString(),
      albumId: json['albumId']?.toString(),
      trackNumber: (json['track'] as num?)?.toInt(),
      durationSeconds: (json['duration'] as num?)?.toInt() ?? 0,
      suffix: json['suffix']?.toString(),
      bitRate: (json['bitRate'] as num?)?.toInt(),
      samplingRate: (json['samplingRate'] as num?)?.toInt(),
      bitDepth: (json['bitDepth'] as num?)?.toInt(),
      coverArtId: json['coverArt']?.toString(),
      replayGainTrackDb: (rg?['trackGain'] as num?)?.toDouble(),
      replayGainAlbumDb: (rg?['albumGain'] as num?)?.toDouble(),
    );
  }

  String get qualityBadge {
    final parts = <String>[];
    if (suffix != null && suffix!.isNotEmpty) {
      parts.add(suffix!.toUpperCase());
    }
    if (bitDepth != null && samplingRate != null) {
      final khz = (samplingRate! / 1000).toStringAsFixed(
          samplingRate! % 1000 == 0 ? 0 : 1);
      parts.add('$bitDepth-bit/${khz}kHz');
    } else if (bitRate != null && bitRate! > 0) {
      parts.add('$bitRate kbps');
    }
    return parts.join(' • ');
  }
}

class SubsonicSearchResult {
  final List<SubsonicArtist> artists;
  final List<SubsonicAlbum> albums;
  final List<SubsonicTrack> songs;

  const SubsonicSearchResult({
    this.artists = const [],
    this.albums = const [],
    this.songs = const [],
  });
}

class SubsonicService {
  static const String _prefsKey = 'subsonic_servers_v1';
  static const String _apiVersion = '1.16.1';
  static const String _clientName = 'SautiPlay';
  static final Random _rng = Random.secure();

  static Future<List<SubsonicConfig>> getSavedConfigs() async {
    try {
      final jsonStr = PreferencesStore.instance.getString(_prefsKey);
      if (jsonStr == null || jsonStr.isEmpty) return [];
      final list = jsonDecode(jsonStr) as List<dynamic>;
      return list
          .map((e) => SubsonicConfig.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('[SubsonicService] Failed to load configs: $e');
      return [];
    }
  }

  static Future<void> saveConfig(SubsonicConfig config) async {
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

  static String _randomSalt() {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    return List.generate(8, (_) => chars[_rng.nextInt(chars.length)]).join();
  }

  static Map<String, String> _authParams(SubsonicConfig config) {
    final params = <String, String>{
      'u': config.username,
      'v': _apiVersion,
      'c': _clientName,
      'f': 'json',
    };
    if (config.usePlaintextAuth) {
      params['p'] = config.password;
    } else {
      final salt = _randomSalt();
      final token = md5.convert(utf8.encode('${config.password}$salt')).toString();
      params['s'] = salt;
      params['t'] = token;
    }
    return params;
  }

  static Uri _buildUri(
    SubsonicConfig config,
    String endpoint, [
    Map<String, String>? extra,
  ]) {
    final base = Uri.parse('${config.normalizedBaseUrl}/rest/$endpoint.view');
    final query = <String, String>{
      ..._authParams(config),
      if (extra != null) ...extra,
    };
    return base.replace(queryParameters: query);
  }

  static Future<Map<String, dynamic>> _getJson(
    SubsonicConfig config,
    String endpoint, [
    Map<String, String>? extra,
  ]) async {
    final uri = _buildUri(config, endpoint, extra);
    final res = await http.get(uri).timeout(const Duration(seconds: 12));
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('HTTP ${res.statusCode}');
    }
    final decoded = jsonDecode(res.body) as Map<String, dynamic>;
    final root = decoded['subsonic-response'] as Map<String, dynamic>?;
    if (root == null) {
      throw Exception('Invalid Subsonic response');
    }
    if (root['status'] != 'ok') {
      final err = root['error'] as Map<String, dynamic>?;
      throw Exception(err?['message']?.toString() ?? 'Subsonic API error');
    }
    return root;
  }

  /// Tests connectivity & credentials; returns `null` on success or an error string.
  static Future<String?> testConnection(SubsonicConfig config) async {
    try {
      await _getJson(config, 'ping');
      return null;
    } catch (e) {
      return e.toString().replaceFirst('Exception: ', '');
    }
  }

  static Future<List<SubsonicAlbum>> getAlbumList(
    SubsonicConfig config, {
    String type = 'recent',
    int size = 50,
    int offset = 0,
  }) async {
    final root = await _getJson(config, 'getAlbumList2', {
      'type': type,
      'size': '$size',
      'offset': '$offset',
    });
    final list = (root['albumList2'] as Map<String, dynamic>?)?['album']
            as List<dynamic>? ??
        const [];
    return list
        .map((e) => SubsonicAlbum.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static Future<List<SubsonicArtist>> getArtists(SubsonicConfig config) async {
    final root = await _getJson(config, 'getArtists');
    final indexes =
        (root['artists'] as Map<String, dynamic>?)?['index'] as List<dynamic>? ??
            const [];
    final artists = <SubsonicArtist>[];
    for (final idx in indexes) {
      final list = (idx as Map<String, dynamic>)['artist'] as List<dynamic>? ??
          const [];
      for (final a in list) {
        artists.add(SubsonicArtist.fromJson(a as Map<String, dynamic>));
      }
    }
    return artists;
  }

  static Future<List<SubsonicAlbum>> getArtistAlbums(
    SubsonicConfig config,
    String artistId,
  ) async {
    final root = await _getJson(config, 'getArtist', {'id': artistId});
    final list = (root['artist'] as Map<String, dynamic>?)?['album']
            as List<dynamic>? ??
        const [];
    return list
        .map((e) => SubsonicAlbum.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static Future<List<SubsonicTrack>> getAlbumTracks(
    SubsonicConfig config,
    String albumId,
  ) async {
    final root = await _getJson(config, 'getAlbum', {'id': albumId});
    final list =
        (root['album'] as Map<String, dynamic>?)?['song'] as List<dynamic>? ??
            const [];
    return list
        .map((e) => SubsonicTrack.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static Future<List<SubsonicPlaylist>> getPlaylists(
    SubsonicConfig config,
  ) async {
    final root = await _getJson(config, 'getPlaylists');
    final list = (root['playlists'] as Map<String, dynamic>?)?['playlist']
            as List<dynamic>? ??
        const [];
    return list
        .map((e) => SubsonicPlaylist.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static Future<List<SubsonicTrack>> getPlaylistTracks(
    SubsonicConfig config,
    String playlistId,
  ) async {
    final root = await _getJson(config, 'getPlaylist', {'id': playlistId});
    final list = (root['playlist'] as Map<String, dynamic>?)?['entry']
            as List<dynamic>? ??
        const [];
    return list
        .map((e) => SubsonicTrack.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static Future<SubsonicSearchResult> search(
    SubsonicConfig config,
    String query,
  ) async {
    final root = await _getJson(config, 'search3', {
      'query': query,
      'artistCount': '15',
      'albumCount': '20',
      'songCount': '40',
    });
    final res = root['searchResult3'] as Map<String, dynamic>? ?? const {};
    final artists = (res['artist'] as List<dynamic>? ?? const [])
        .map((e) => SubsonicArtist.fromJson(e as Map<String, dynamic>))
        .toList();
    final albums = (res['album'] as List<dynamic>? ?? const [])
        .map((e) => SubsonicAlbum.fromJson(e as Map<String, dynamic>))
        .toList();
    final songs = (res['song'] as List<dynamic>? ?? const [])
        .map((e) => SubsonicTrack.fromJson(e as Map<String, dynamic>))
        .toList();
    return SubsonicSearchResult(
      artists: artists,
      albums: albums,
      songs: songs,
    );
  }

  static String buildStreamUrl(SubsonicConfig config, String trackId) {
    final extra = <String, String>{'id': trackId};
    if (config.transcodeFormat != 'raw') {
      extra['format'] = config.transcodeFormat;
      if (config.maxBitRate > 0) {
        extra['maxBitRate'] = '${config.maxBitRate}';
      }
    } else {
      extra['format'] = 'raw';
    }
    return _buildUri(config, 'stream', extra).toString();
  }

  static String? buildCoverArtUrl(
    SubsonicConfig config,
    String? coverArtId, {
    int size = 300,
  }) {
    if (coverArtId == null || coverArtId.isEmpty) return null;
    return _buildUri(config, 'getCoverArt', {
      'id': coverArtId,
      'size': '$size',
    }).toString();
  }
}
