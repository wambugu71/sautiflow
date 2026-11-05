import 'package:flutter_test/flutter_test.dart';
import 'package:dart_ytmusic_api/dart_ytmusic_api.dart';
import 'package:sautiplay/database/preferences_store.dart';
import 'package:sautiplay/services/youtube_auth_service.dart';
import 'package:sautiplay/streaming_service.dart';

void main() {
  test('Search songs on YTMusic and test resolveStreamDetailed', () async {
    PreferencesStore.instance.setMockValues({
      'streaming_quality_preset': 'audiophile',
      'prefer_native_aac': false,
      'enable_hosted_fallback': false,
    });
    await YouTubeAuthService.instance.init();

    final yt = YTMusic();
    await yt.initialize();
    final songs = await yt.searchSongs('The Weeknd Blinding Lights');
    print('Found ${songs.length} songs');

    final testIds = songs.take(3).map((s) => s.videoId).toList();
    print('Testing tracks: $testIds');

    for (final vid in testIds) {
      print('\n--- Resolving $vid ---');
      final result = await StreamingService.resolveStreamDetailed(
        vid,
        quality: AudioQualityPreset.audiophile,
        allowFallback: false,
      );
      print('Resolved $vid -> ${result?.url != null ? "SUCCESS (${result!.bitrateKbps} kbps)" : "FAILED (null)"}');
      if (result != null) {
        print('URL: ${result.url}');
      }
    }
  }, timeout: const Timeout(Duration(minutes: 3)));
}
