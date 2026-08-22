import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

/// Service for Last.fm authentication, real-time "Now Playing" updates,
/// and song scrobbling.
class LastFmService extends ChangeNotifier {
  LastFmService._();
  static final LastFmService instance = LastFmService._();

  static const String _apiKey = '5a1dd8613a7aa67cdb6dd751208f8531';
  static const String _sharedSecret = '9f5e65a1af72e6d4b9dff9f6b11d8c29';
  static const String _apiEndpoint = 'https://ws.audioscrobbler.com/2.0/';

  static const String _kSessionKey = 'lastfm_session_key';
  static const String _kUsername = 'lastfm_username';
  static const String _kScrobbleEnabled = 'lastfm_scrobble_enabled';
  static const String _kNowPlayingEnabled = 'lastfm_nowplaying_enabled';

  final StreamController<String> _logController = StreamController<String>.broadcast();
  Stream<String> get logStream => _logController.stream;

  String? _sessionKey;
  String? _username;
  bool _scrobbleEnabled = true;
  bool _nowPlayingEnabled = true;
  bool _isInitialized = false;

  String? get sessionKey => _sessionKey;
  String? get username => _username;
  bool get isLoggedIn => _sessionKey != null && _sessionKey!.isNotEmpty;
  bool get isScrobbleEnabled => _scrobbleEnabled;
  bool get isNowPlayingEnabled => _nowPlayingEnabled;

  // Active track scrobbling state tracking
  String? _currentTitle;
  String? _currentArtist;
  int? _trackStartTimeSeconds;
  int? _trackDurationSeconds;
  double _maxPositionSeconds = 0.0;
  bool _currentTrackScrobbled = false;

  void _log(String message) {
    _logController.add(message);
  }

  /// Initializes preferences and loads saved credentials.
  Future<void> init() async {
    if (_isInitialized) return;
    final prefs = await SharedPreferences.getInstance();
    _sessionKey = prefs.getString(_kSessionKey);
    _username = prefs.getString(_kUsername);
    _scrobbleEnabled = prefs.getBool(_kScrobbleEnabled) ?? true;
    _nowPlayingEnabled = prefs.getBool(_kNowPlayingEnabled) ?? true;
    _isInitialized = true;
    if (isLoggedIn) {
      _log('[LastFm] Initialized with user: $_username');
    } else {
      _log('[LastFm] Initialized (Not connected)');
    }
    notifyListeners();
  }

  /// Sets scrobbling toggle
  Future<void> setScrobbleEnabled(bool enabled) async {
    _scrobbleEnabled = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kScrobbleEnabled, enabled);
    _log('[LastFm] Scrobbling enabled: $enabled');
    notifyListeners();
  }

  /// Sets Now Playing toggle
  Future<void> setNowPlayingEnabled(bool enabled) async {
    _nowPlayingEnabled = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kNowPlayingEnabled, enabled);
    _log('[LastFm] Now Playing updates enabled: $enabled');
    notifyListeners();
  }

  /// Generates the MD5 signature required for authenticated Last.fm requests.
  String _generateApiSignature(Map<String, String> params) {
    final keys = params.keys.where((k) => k != 'format' && k != 'callback').toList()..sort();
    final buffer = StringBuffer();
    for (final key in keys) {
      buffer.write(key);
      buffer.write(params[key]);
    }
    buffer.write(_sharedSecret);
    return md5.convert(utf8.encode(buffer.toString())).toString();
  }

  /// Step 1: Requests a temporary unauthorized token from Last.fm.
  Future<String?> fetchRequestToken() async {
    try {
      final uri = Uri.parse(_apiEndpoint).replace(queryParameters: {
        'method': 'auth.getToken',
        'api_key': _apiKey,
        'format': 'json',
      });
      final res = await http.get(uri);
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final token = data['token'] as String?;
        _log('[LastFm] Received auth token');
        return token;
      } else {
        _log('[LastFm] Failed to get auth token (${res.statusCode}): ${res.body}');
      }
    } catch (e) {
      _log('[LastFm] Error fetching request token: $e');
    }
    return null;
  }

  /// Step 2: Launches the web browser for the user to authorize this application.
  Future<bool> launchAuthorizationUrl(String token) async {
    final authUrl = Uri.parse('https://www.last.fm/api/auth/?api_key=$_apiKey&token=$token');
    _log('[LastFm] Opening authorization webpage: $authUrl');
    try {
      if (await canLaunchUrl(authUrl)) {
        return await launchUrl(authUrl, mode: LaunchMode.externalApplication);
      } else {
        // Direct attempt fallback if canLaunchUrl check fails
        return await launchUrl(authUrl, mode: LaunchMode.platformDefault);
      }
    } catch (e) {
      _log('[LastFm] Error launching authorization URL: $e');
      try {
        return await launchUrl(authUrl, mode: LaunchMode.platformDefault);
      } catch (_) {
        return false;
      }
    }
  }

  /// Step 3: Exchanges the authorized token for a permanent session key.
  Future<bool> fetchSession(String token) async {
    try {
      final params = <String, String>{
        'method': 'auth.getSession',
        'api_key': _apiKey,
        'token': token,
      };
      params['api_sig'] = _generateApiSignature(params);
      params['format'] = 'json';

      final uri = Uri.parse(_apiEndpoint).replace(queryParameters: params);
      final res = await http.get(uri);
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        if (data.containsKey('session')) {
          final session = data['session'] as Map<String, dynamic>;
          _sessionKey = session['key'] as String?;
          _username = session['name'] as String?;

          final prefs = await SharedPreferences.getInstance();
          if (_sessionKey != null) await prefs.setString(_kSessionKey, _sessionKey!);
          if (_username != null) await prefs.setString(_kUsername, _username!);

          notifyListeners();
          _log('[LastFm] Successfully authenticated as $_username');
          return true;
        }
      } else {
        _log('[LastFm] Session fetch error (${res.statusCode}): ${res.body}');
      }
    } catch (e) {
      _log('[LastFm] Error fetching session: $e');
    }
    return false;
  }

  /// Logs out of Last.fm and clears saved credentials.
  Future<void> logout() async {
    _log('[LastFm] Logged out from $_username');
    _sessionKey = null;
    _username = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kSessionKey);
    await prefs.remove(_kUsername);
    notifyListeners();
  }

  // ─── Playback & Scrobble Operations ─────────────────────────────────────────

  /// Called when a new track begins playing.
  Future<void> onTrackStarted({
    required String title,
    required String artist,
    String? album,
    int? durationSeconds,
  }) async {
    _currentTitle = title.trim();
    _currentArtist = (artist.trim().isNotEmpty && artist != 'Unknown Artist' && artist != 'Local File')
        ? artist.trim()
        : '';
    _trackStartTimeSeconds = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
    _trackDurationSeconds = durationSeconds;
    _maxPositionSeconds = 0.0;
    _currentTrackScrobbled = false;

    if (!isLoggedIn) {
      _log('[LastFm] Track started but account is not connected');
      return;
    }

    if (!_nowPlayingEnabled) return;
    if (_currentTitle == null || _currentTitle!.isEmpty) return;

    final effectiveArtist = _currentArtist!.isNotEmpty ? _currentArtist! : 'Unknown Artist';

    try {
      final params = <String, String>{
        'method': 'track.updateNowPlaying',
        'api_key': _apiKey,
        'sk': _sessionKey!,
        'artist': effectiveArtist,
        'track': _currentTitle!,
      };
      if (album != null && album.trim().isNotEmpty) {
        params['album'] = album.trim();
      }
      if (durationSeconds != null && durationSeconds > 0) {
        params['duration'] = durationSeconds.toString();
      }
      params['api_sig'] = _generateApiSignature(params);
      params['format'] = 'json';

      final res = await http.post(
        Uri.parse(_apiEndpoint),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: params,
      );
      if (res.statusCode == 200) {
        _log('[LastFm] Updated Now Playing: $effectiveArtist - $_currentTitle');
      } else {
        _log('[LastFm] updateNowPlaying error (${res.statusCode}): ${res.body}');
      }
    } catch (e) {
      _log('[LastFm] Failed to update now playing: $e');
    }
  }

  /// Called periodically with player playback progress.
  /// Last.fm Scrobble guidelines:
  /// - Track must be >= 30 seconds long
  /// - User must have listened to >= 50% of track OR 240 seconds (4 minutes)
  Future<void> onPlaybackProgress({
    required String title,
    required String artist,
    String? album,
    required double currentPositionSeconds,
    required double totalDurationSeconds,
    required bool isPlaying,
  }) async {
    if (_currentTrackScrobbled) return;
    if (!isLoggedIn || !_scrobbleEnabled) return;

    final cleanTitle = title.trim();
    if (cleanTitle.isEmpty) return;

    // Keep track metadata updated
    if (artist.trim().isNotEmpty && artist != 'Unknown Artist' && artist != 'Local File') {
      _currentArtist = artist.trim();
    }
    _currentTitle = cleanTitle;

    if (currentPositionSeconds > _maxPositionSeconds) {
      _maxPositionSeconds = currentPositionSeconds;
    }

    final duration = totalDurationSeconds > 0 ? totalDurationSeconds : (_trackDurationSeconds?.toDouble() ?? 0.0);
    // Ignore tracks shorter than 30s as per Last.fm spec
    if (duration > 0 && duration < 30) return;

    // Check scrobble qualifying threshold (50% or 240s)
    final halfDuration = duration > 0 ? duration / 2.0 : 120.0;
    final threshold = halfDuration < 240.0 ? halfDuration : 240.0;

    if (_maxPositionSeconds >= threshold) {
      _currentTrackScrobbled = true;
      final effectiveArtist = (_currentArtist != null && _currentArtist!.isNotEmpty) ? _currentArtist! : 'Unknown Artist';
      final timestamp = _trackStartTimeSeconds ?? (DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000);
      await _sendScrobble(
        title: cleanTitle,
        artist: effectiveArtist,
        album: album,
        timestamp: timestamp,
        durationSeconds: duration.toInt(),
      );
    }
  }

  /// Called when a track finishes playing or is skipped after playing.
  Future<void> onTrackCompleted({
    required String title,
    required String artist,
    String? album,
    required double maxPositionSeconds,
    required double durationSeconds,
  }) async {
    if (_currentTrackScrobbled) return;
    if (!isLoggedIn || !_scrobbleEnabled) return;

    final cleanTitle = title.trim();
    if (cleanTitle.isEmpty) return;

    final effectiveArtist = (artist.trim().isNotEmpty && artist != 'Unknown Artist' && artist != 'Local File')
        ? artist.trim()
        : ((_currentArtist != null && _currentArtist!.isNotEmpty) ? _currentArtist! : 'Unknown Artist');

    final duration = durationSeconds > 0 ? durationSeconds : (_trackDurationSeconds?.toDouble() ?? 0.0);
    if (duration > 0 && duration < 30) return;

    final halfDuration = duration > 0 ? duration / 2.0 : 120.0;
    final threshold = halfDuration < 240.0 ? halfDuration : 240.0;

    if (maxPositionSeconds >= threshold) {
      _currentTrackScrobbled = true;
      final timestamp = _trackStartTimeSeconds ?? (DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000);
      await _sendScrobble(
        title: cleanTitle,
        artist: effectiveArtist,
        album: album,
        timestamp: timestamp,
        durationSeconds: duration.toInt(),
      );
    }
  }

  Future<void> _sendScrobble({
    required String title,
    required String artist,
    String? album,
    required int timestamp,
    int? durationSeconds,
  }) async {
    try {
      final params = <String, String>{
        'method': 'track.scrobble',
        'api_key': _apiKey,
        'sk': _sessionKey!,
        'artist': artist.trim(),
        'track': title.trim(),
        'timestamp': timestamp.toString(),
      };
      if (album != null && album.trim().isNotEmpty) {
        params['album'] = album.trim();
      }
      if (durationSeconds != null && durationSeconds > 0) {
        params['duration'] = durationSeconds.toString();
      }
      params['api_sig'] = _generateApiSignature(params);
      params['format'] = 'json';

      final res = await http.post(
        Uri.parse(_apiEndpoint),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: params,
      );
      if (res.statusCode == 200) {
        _log('[LastFm] Scrobbled track: $artist - $title');
      } else {
        _log('[LastFm] Scrobble error (${res.statusCode}): ${res.body}');
      }
    } catch (e) {
      _log('[LastFm] Failed to scrobble: $e');
    }
  }
}
