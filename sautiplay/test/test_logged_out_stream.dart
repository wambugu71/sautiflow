import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:sautiplay/database/preferences_store.dart';
import 'package:sautiplay/services/youtube_auth_service.dart';
import 'package:sautiplay/streaming_service.dart';

void main() {
  setUpAll(() async {
    // Completely unauthenticated (clean install / logged out)
    PreferencesStore.instance.setMockValues({
      'streaming_quality_preset': 'audiophile',
      'prefer_native_aac': false,
      'enable_hosted_fallback': false,
    });
    await YouTubeAuthService.instance.init();
    expect(YouTubeAuthService.instance.hasAuth, isFalse);
    print('Logged-out test ready: hasAuth = false');
  });

  test('Resolve Queen - Bohemian Rhapsody (vbvyNnw8Qjg) logged out', () async {
    final result = await StreamingService.resolveStreamDetailed(
      'vbvyNnw8Qjg',
      quality: AudioQualityPreset.audiophile,
      allowFallback: false,
    );

    print('Result: $result');
    if (result != null) {
      print('URL: ${result.url}');
      final res = await http.get(
        Uri.parse(result.url),
        headers: {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:130.0) Gecko/20100101 Firefox/130.0',
          'Referer': 'https://music.youtube.com/',
          'Origin': 'https://music.youtube.com',
          'Range': 'bytes=0-1024',
        },
      );
      print('HTTP GET status: ${res.statusCode}');
      expect(res.statusCode, isIn([200, 206]));
    }
  }, timeout: const Timeout(Duration(minutes: 2)));
}
