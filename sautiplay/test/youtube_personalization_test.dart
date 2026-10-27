import 'package:flutter_test/flutter_test.dart';
import 'package:dart_ytmusic_api/dart_ytmusic_api.dart';
import 'package:dart_ytmusic_api/utils/sha1.dart';
import 'package:sautiplay/services/youtube_auth_service.dart';
import 'package:sautiplay/database/preferences_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    PreferencesStore.instance.setMockValues({});
  });

  group('SHA-1 InnerTube Test Vectors', () {
    test('computes correct hash for standard vectors', () {
      expect(computeSha1(''), 'da39a3ee5e6b4b0d3255bfef95601890afd80709');
      expect(
        computeSha1('The quick brown fox jumps over the lazy dog'),
        '2fd4e1c67a2d28fced849ee1bb76e7391b93eb12',
      );
    });
  });

  group('YTMusic Cookie Scoping and Re-init', () {
    test('properly scopes cookies to music.youtube.com and loads them for requests', () async {
      final yt = YTMusic();
      const testCookie = 'LOGIN_INFO=AFmmF2cwRQIhAJ0; SAPISID=abcdef123456789; __Secure-3PAPISID=xyz987654';

      await yt.initialize(cookies: testCookie, force: true);

      final uri = Uri.parse('https://music.youtube.com/youtubei/v1/browse?alt=json');
      final loadedCookies = await yt.cookieJar.loadForRequest(uri);

      expect(loadedCookies.isNotEmpty, isTrue);
      final names = loadedCookies.map((c) => c.name).toSet();
      expect(names.contains('LOGIN_INFO'), isTrue);
      expect(names.contains('SAPISID'), isTrue);
      expect(names.contains('__Secure-3PAPISID'), isTrue);
    });

    test('clears cookies on logout (cookies: null with force: true)', () async {
      final yt = YTMusic();
      const testCookie = 'LOGIN_INFO=AFmmF2cwRQIhAJ0';

      await yt.initialize(cookies: testCookie, force: true);
      final uri = Uri.parse('https://music.youtube.com/');
      var loaded = await yt.cookieJar.loadForRequest(uri);
      expect(loaded.isNotEmpty, isTrue);

      // Sign out / clear
      await yt.initialize(cookies: null, force: true);
      loaded = await yt.cookieJar.loadForRequest(uri);
      expect(loaded.isEmpty, isTrue);
    });
  });

  group('YouTubeAuthService listener notifications', () {
    test('notifies listeners when session cookies are saved and removed', () async {
      final auth = YouTubeAuthService.instance;
      int changeCount = 0;
      void listener() {
        changeCount++;
      }

      auth.addAuthListener(listener);

      await auth.saveCookieAuth('LOGIN_INFO=test_login; SAPISID=test_sapisid');
      expect(changeCount, 1);
      expect(auth.hasAuth, isTrue);
      expect(auth.currentCookie, contains('LOGIN_INFO=test_login'));

      await auth.signOut();
      expect(changeCount, 2);
      expect(auth.hasAuth, isFalse);
      expect(auth.currentCookie, isNull);

      auth.removeAuthListener(listener);
    });
  });
}
