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

    final body = {
      ...payload,
      'videoId': videoId.value,
      if (ytCfg?.containsKey('STS') ?? false)
        'playbackContext': {
          'contentPlaybackContext': {
            'html5Preference': 'HTML5_PREF_WANTS',
            'signatureTimestamp': ytCfg!['STS'].toString()
          }
        }
      else if (payload['playbackContext']?['contentPlaybackContext']?['signatureTimestamp'] != null)
        'playbackContext': payload['playbackContext']!
      else
        'playbackContext': {
          'contentPlaybackContext': {
            'html5Preference': 'HTML5_PREF_WANTS',
            'signatureTimestamp': '20751',
          }
        }
    };
    if (body['context']!['client']['clientName'] == 'IOS') {
      body['context']!['client']!['visitorData'] =
          await _extractVisitorData(httpClient, client);
    }

    final httpCookie =
        httpClient.headers['cookie'] ?? httpClient.headers['Cookie'];
    final watchCookie = (client == YoutubeApiClient.webRemix) ? null : watchPage?.cookieString;
    final mergedCookie = [
      if (httpCookie != null && httpCookie.isNotEmpty) httpCookie,
      if (watchCookie != null && watchCookie.isNotEmpty) watchCookie,
    ].join('; ');

    final targetOrigin = client.headers['Origin'] ??
        httpClient.headers['Origin'] ??
        httpClient.headers['origin'] ??
        'https://www.youtube.com';

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
    if (sapisid != null && sapisid.isNotEmpty) {
      final ts = (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString();
      final hash = sha1.convert(utf8.encode('$ts $sapisid $targetOrigin')).toString();
      authHeader = 'SAPISIDHASH ${ts}_$hash';
    } else {
      authHeader = httpClient.headers['Authorization'] ?? httpClient.headers['authorization'];
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
