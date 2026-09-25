import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sautiplay/database/app_database.dart';
import 'package:sautiplay/database/preferences_store.dart';
import 'package:sautiplay/models/liked_song.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    PreferencesStore.instance.setMockValues({});
  });

  tearDown(() async {
    await db.close();
  });

  group('PreferencesStore Tests', () {
    test('instant synchronous read with defaults', () {
      final store = PreferencesStore.instance;
      expect(store.getBool('non_existent', defaultValue: true), isTrue);
      expect(store.getInt('non_existent', defaultValue: 42), equals(42));
      expect(store.getDouble('non_existent', defaultValue: 3.14), equals(3.14));
      expect(
        store.getString('non_existent', defaultValue: 'default'),
        equals('default'),
      );
    });

    test('watchBool emits initial value and updates reactively', () async {
      final store = PreferencesStore.instance;
      final emitted = <bool>[];
      final sub = store
          .watchBool('test_toggle', defaultValue: false)
          .listen(emitted.add);

      await pumpEventQueue();
      await store.setBool('test_toggle', true);
      await pumpEventQueue();
      await store.setBool('test_toggle', false);
      await pumpEventQueue();

      expect(emitted, equals([false, true, false]));
      await sub.cancel();
    });

    test('watchString emits value changes reactively', () async {
      final store = PreferencesStore.instance;
      final emitted = <String?>[];
      final sub = store
          .watchString('theme_mode', defaultValue: 'dark')
          .listen(emitted.add);

      await pumpEventQueue();
      await store.setString('theme_mode', 'light');
      await pumpEventQueue();
      await store.setString('theme_mode', 'amoled');
      await pumpEventQueue();

      expect(emitted, equals(['dark', 'light', 'amoled']));
      await sub.cancel();
    });
  });

  group('Drift Liked Songs & Recently Played Tests', () {
    test('upsert, isLiked, and deleteLikedSong work reliably in memory DB',
        () async {
      expect(await db.isSongLiked('song_1'), isFalse);

      final track = LikedSong(
        videoId: 'song_1',
        title: 'Song One',
        artist: 'Artist One',
        durationSeconds: 240,
        likedAt: DateTime.now(),
      );

      await db.upsertLikedSong(
        LikedSongEntriesCompanion.insert(
          videoId: track.videoId,
          title: track.title,
          artist: track.artist,
          durationSeconds: Value(track.durationSeconds),
          likedAt: track.likedAt,
        ),
      );

      expect(await db.isSongLiked('song_1'), isTrue);
      final songs = await db.getLikedSongs();
      expect(songs.length, equals(1));
      expect(songs.first.title, equals('Song One'));

      await db.deleteLikedSong('song_1');
      expect(await db.isSongLiked('song_1'), isFalse);
    });

    test('RecentlyPlayed auto-prunes history to max limit', () async {
      for (int i = 0; i < 15; i++) {
        await db.addRecentlyPlayed(
          RecentlyPlayedEntriesCompanion.insert(
            videoId: 'track_$i',
            title: 'Track $i',
            artist: 'Artist $i',
            durationSeconds: const Value(180),
            playedAt: DateTime.now().add(Duration(seconds: i)),
          ),
          maxHistory: 5,
        );
      }

      final history = await db.getRecentlyPlayed(limit: 100);
      expect(history.length, equals(5));
      expect(history.first.videoId, equals('track_14')); // Most recent first
    });
  });
}
