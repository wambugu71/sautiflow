import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:sautiplay/database/preferences_store.dart';
import 'package:sautiplay/services/youtube_auth_service.dart';
import 'package:sautiplay/streaming_service.dart';

void main() {
  setUpAll(() async {
    // 1. Read actual cookie header from SQLite
    final process = await Process.run('python', [
      '-c',
      '''import sqlite3
conn = sqlite3.connect(r'C:\\Users\\wambugukinyua\\Documents\\sautiplay_db.sqlite')
c = conn.cursor()
c.execute("SELECT value FROM app_preferences WHERE key = 'sautiplay_yt_cookie_auth'")
row = c.fetchone()
print(row[0] if row else "")
'''
    ]);
    final cookie = process.stdout.toString().trim();
    expect(cookie.isNotEmpty, isTrue, reason: 'Cookie must exist in sautiplay_db.sqlite');

    // 2. Mock preferences store with real cookie
    PreferencesStore.instance.setMockValues({
      'sautiplay_yt_cookie_auth': cookie,
      'sautiplay_yt_account_name': 'Connected YouTube Session',
      'streaming_quality_preset': 'audiophile',
      'prefer_native_aac': false,
      'enable_hosted_fallback': false,
    });

    // 3. Initialize YouTube Auth Service
    await YouTubeAuthService.instance.init();
    expect(YouTubeAuthService.instance.hasAuth, isTrue);

    final authHeaders = YouTubeAuthService.instance.getAuthHeadersSync();
    expect(authHeaders.containsKey('Cookie'), isTrue);
    expect(authHeaders.containsKey('Authorization'), isTrue);
    print('Auth OK: SAPISIDHASH present');
  });

  // Run tracks sequentially to avoid shared client contention
  test('Resolve and stream: Queen - Bohemian Rhapsody (vbvyNnw8Qjg)', () async {
    await _testTrack('vbvyNnw8Qjg', 'Queen - Bohemian Rhapsody Live Aid 1985');
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('Resolve and stream: Rick Astley - Never Gonna Give You Up (dQw4w9WgXcQ)', () async {
    await _testTrack('dQw4w9WgXcQ', 'Rick Astley - Never Gonna Give You Up');
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('Resolve and stream: Justin Bieber - Baby (kffacxfA7G4)', () async {
    await _testTrack('kffacxfA7G4', 'Justin Bieber - Baby');
  }, timeout: const Timeout(Duration(minutes: 3)));
}

Future<void> _testTrack(String videoId, String name) async {
  print('\n--- Testing: $name ($videoId) ---');
  final result = await StreamingService.resolveStreamDetailed(
    videoId,
    quality: AudioQualityPreset.audiophile,
    allowFallback: false,
  );

  expect(result, isNotNull, reason: 'Stream resolution for $videoId must not be null');
  print('Resolved: ${result!.container} ${result.audioCodec} (${result.bitrateKbps} kbps)');
  expect(result.url, contains('googlevideo.com'));

  final res = await http.get(
    Uri.parse(result.url),
    headers: {
      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:130.0) Gecko/20100101 Firefox/130.0',
      'Referer': 'https://music.youtube.com/',
      'Origin': 'https://music.youtube.com',
      'Range': 'bytes=0-1024',
    },
  );

  print('HTTP status: ${res.statusCode}');
  print('Content-Type: ${res.headers['content-type']}');
  print('Content-Range: ${res.headers['content-range']}');

  expect(res.statusCode, isIn([200, 206]),
      reason: 'Audio stream for $videoId must return 200 or 206');
}
