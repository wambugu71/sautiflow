import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:meta/meta.dart';

import '../../youtube_explode_dart.dart';
import '../reverse_engineering/pages/watch_page.dart';
import '../reverse_engineering/player/player_response.dart';

@internal
class VideoController {
  @protected
  final YoutubeHttpClient httpClient;

  VideoController(this.httpClient);

  Future<PlayerResponse> getPlayerResponse(
      VideoId videoId, YoutubeApiClient client,
      {WatchPage? watchPage}) async {
    final payload = client.payload;
    assert(payload['context'] != null, 'client must contain a context');
    assert(payload['context']!['client'] != null,
        'client must contain a context.client');

    final userAgent = payload['context']!['client']!['userAgent'] as String?;
    final ytCfg = watchPage?.ytCfg;

    final liveMeta = (ytCfg?.containsKey('STS') ?? false)
        ? null
        : await resolvePlayerMetadata(httpClient);
    final effectiveSts =
        ytCfg?['STS']?.toString() ?? liveMeta?.sts ?? '20759';

    final contextMap = Map<String, dynamic>.from(payload['context'] as Map);
    final clientMap = Map<String, dynamic>.from(contextMap['client'] as Map);
    contextMap['client'] = clientMap;

    final body = {
      ...payload,
      'context': contextMap,
      'videoId': videoId.value,
      'playbackContext': {
        'contentPlaybackContext': {
          'html5Preference': 'HTML5_PREF_WANTS',
          'signatureTimestamp': int.tryParse(effectiveSts) ?? effectiveSts,
        }
      },
    };
    if (clientMap['clientName'] == 'IOS') {
      clientMap['visitorData'] =
          await _extractVisitorData(httpClient, client);
    }

    // Mobile/VR clients reject web session cookies and SAPISIDHASH (HTTP 400),
    // so only web-family clients (tv, mweb, web, web_remix) get credentials.
    const noAuthClients = {
      'IOS',
      'ANDROID',
      'ANDROID_VR',
      'ANDROID_MUSIC',
      'VISIONOS',
    };
    final sendAuth =
        !noAuthClients.contains(payload['context']!['client']!['clientName']);
    final httpCookie = !sendAuth
        ? null
        : httpClient.headers['cookie'] ?? httpClient.headers['Cookie'];
    final watchCookie = (client == YoutubeApiClient.webRemix) ? null : watchPage?.cookieString;
    // Merge by cookie name (first occurrence wins, so the user's session
    // cookies take precedence over defaults) to avoid duplicate names.
    final cookieMap = <String, String>{};
    for (final source in [httpCookie, watchCookie]) {
      if (source == null || source.isEmpty) continue;
      for (final part in source.split(';')) {
        final eq = part.indexOf('=');
        if (eq <= 0) continue;
        cookieMap.putIfAbsent(
            part.substring(0, eq).trim(), () => part.substring(eq + 1).trim());
      }
    }
    final mergedCookie =
        cookieMap.entries.map((e) => '${e.key}=${e.value}').join('; ');

    final apiUri = Uri.parse(client.apiUrl);
    final targetOrigin = client.headers['Origin'] ??
        client.headers['origin'] ??
        '${apiUri.scheme}://${apiUri.host}';

    // Extract SAPISID or __Secure-3PAPISID to calculate SAPISIDHASH for targetOrigin
    String? sapisid;
    for (final part in mergedCookie.split('; ')) {
      if (part.startsWith('SAPISID=') || part.startsWith('__Secure-3PAPISID=')) {
        final eq = part.indexOf('=');
        if (eq != -1) {
          sapisid = part.substring(eq + 1).trim();
          break;
        }
      }
    }

    String? authHeader;
    if (sapisid != null && sapisid.isNotEmpty && sendAuth) {
      final ts = (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString();
      final hash = sha1.convert(utf8.encode('$ts $sapisid $targetOrigin')).toString();
      authHeader = 'SAPISIDHASH ${ts}_$hash';
    } else {
      authHeader = !sendAuth
          ? null
          : httpClient.headers['Authorization'] ??
              httpClient.headers['authorization'];
    }

    final content = await httpClient.postString(
      client.apiUrl,
      body: body,
      headers: {
        if (userAgent != null) 'User-Agent': userAgent,
        'X-Youtube-Client-Name': payload['context']!['client']!['clientName'],
        'X-Youtube-Client-Version':
            payload['context']!['client']!['clientVersion'],
        if (client != YoutubeApiClient.webRemix &&
            ytCfg != null &&
            ytCfg['INNERTUBE_CONTEXT']?['client']?['visitorData'] != null)
          'X-Goog-Visitor-Id': ytCfg['INNERTUBE_CONTEXT']['client']
              ['visitorData'],
        'Origin': targetOrigin,
        'Referer': '$targetOrigin/',
        'X-Origin': targetOrigin,
        if (authHeader != null) 'Authorization': authHeader,
        'Sec-Fetch-Mode': 'navigate',
        'Content-Type': 'application/json',
        if (mergedCookie.isNotEmpty) 'Cookie': mergedCookie,
        ...client.headers,
      },
    );
    return PlayerResponse.parse(content);
  }

  static String? _cachedPlayerUrl;
  static String? _cachedPlayerScript;
  static String? _cachedSts;
  static DateTime? _playerCacheTime;

  static String? getCachedPlayerScript(String playerUrl) =>
      _cachedPlayerUrl == playerUrl ? _cachedPlayerScript : null;

  static Future<({String playerUrl, String sts})> resolvePlayerMetadata(
      YoutubeHttpClient http) async {
    final now = DateTime.now();
    if (_cachedPlayerUrl != null &&
        _cachedSts != null &&
        _playerCacheTime != null &&
        now.difference(_playerCacheTime!) < const Duration(hours: 6)) {
      return (playerUrl: _cachedPlayerUrl!, sts: _cachedSts!);
    }
    try {
      final iframeJs = await http.getString(
        'https://www.youtube.com/iframe_api',
        validate: false,
      );
      final idMatch =
          RegExp(r'\/s\/player\/([a-zA-Z0-9_-]+)\/').firstMatch(iframeJs);
      if (idMatch != null) {
        final playerId = idMatch.group(1)!;
        final playerUrl =
            'https://www.youtube.com/s/player/$playerId/player_ias.vflset/en_US/base.js';
        final baseJs = await http.getString(playerUrl, validate: false);
        final stsMatch =
            RegExp(r'signatureTimestamp:(\d+)').firstMatch(baseJs);
        if (stsMatch != null) {
          _cachedPlayerUrl = playerUrl;
          _cachedPlayerScript = baseJs;
          _cachedSts = stsMatch.group(1)!;
          _playerCacheTime = now;
          return (playerUrl: _cachedPlayerUrl!, sts: _cachedSts!);
        }
      }
    } catch (_) {}
    return (
      playerUrl: _cachedPlayerUrl ??
          'https://www.youtube.com/s/player/ef321720/player_ias.vflset/en_US/base.js',
      sts: _cachedSts ?? '20759',
    );
  }

  String? _visitorData;

  Future<String> _extractVisitorData(
      YoutubeHttpClient http, YoutubeApiClient client) async {
    if (_visitorData != null) {
      return _visitorData!;
    }

    var response =
        await http.getString('https://www.youtube.com/sw.js_data', headers: {
      'User-Agent': client.payload['context']['client']['userAgent']!,
      'Content-Type': 'application/json',
    });

    if (response.startsWith(")]}'")) {
      response = response.substring(4);
    }

    final data = json.decode(response) as List<dynamic>;
    final value = data[0][2][0][0][13];

    return _visitorData = value;
  }
}
