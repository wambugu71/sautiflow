import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sautiplay/database/app_database.dart';
import 'package:sautiplay/models/local_song_item.dart';
import 'package:sautiplay/models/smart_playlist_rule.dart';
import 'package:sautiplay/services/metadata_intelligence_service.dart';

void main() {
  group('MetadataIntelligenceService', () {
    final svc = MetadataIntelligenceService.instance;

    test('infers artist, album, year, disc, track, title from nested path', () {
      final res = svc.inferFromPath(
        r'C:\Music\Daft Punk\2013 - Random Access Memories\CD2\03 - Instant Crush [FLAC].flac',
      );
      expect(res.artist, 'Daft Punk');
      expect(res.album, 'Random Access Memories');
      expect(res.year, 2013);
      expect(res.discNumber, 2);
      expect(res.trackNumber, 3);
      expect(res.title, 'Instant Crush');
      expect(res.confidence, greaterThanOrEqualTo(0.7));
    });

    test('infers artist - title and cleans rip noise', () {
      final res = svc.inferFromPath(
        '/storage/emulated/0/Music/04 - Fred_again - Delilah (Official Audio) [320kbps].mp3',
      );
      expect(res.trackNumber, 4);
      expect(res.artist, 'Fred again');
      expect(res.title, 'Delilah');
    });

    test('normalizeTitleCase preserves acronyms and minor words', () {
      expect(
        svc.normalizeTitleCase('dj shadow - in the flux (remastered 2020)'),
        'DJ Shadow - in the Flux',
      );
    });
  });

  group('AppDatabase v3 & SmartPlaylistSpec', () {
    late AppDatabase db;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
    });

    tearDown(() async {
      await db.close();
    });

    test('replaceAllLocalTracks preserves playCount and enriched metadata', () async {
      final now = DateTime(2026, 1, 1);
      final initial = LocalSongItem(
        path: '/music/a.flac',
        title: 'Track A',
        artist: 'Artist A',
        album: 'Album A',
        genre: 'Electronic',
        sizeBytes: 1000,
        lastModified: now,
        bpm: 124.0,
        camelotKey: '8A',
        playCount: 7,
        rating: 5,
      );
      await db.replaceAllLocalTracks([initial]);

      // Simulate library rescan with only basic file-scanner fields
      final rescanned = LocalSongItem(
        path: '/music/a.flac',
        title: 'Track A',
        artist: 'Artist A',
        album: 'Album A',
        genre: 'Electronic',
        sizeBytes: 1000,
        lastModified: now,
      );
      await db.replaceAllLocalTracks([rescanned]);

      final all = await db.getAllLocalTracks();
      expect(all.length, 1);
      expect(all.first.bpm, 124.0);
      expect(all.first.camelotKey, '8A');
      expect(all.first.playCount, 7);
      expect(all.first.rating, 5);
    });

    test('recordAndApplyTagEdit and undoLastTagEdit restore previous tags', () async {
      final now = DateTime(2026, 1, 1);
      final original = LocalSongItem(
        path: '/music/b.mp3',
        title: 'Old Title',
        artist: 'Old Artist',
        sizeBytes: 500,
        lastModified: now,
      );
      await db.upsertLocalTrack(original);

      final edited = original.copyWith(title: 'New Title', artist: 'New Artist');
      await db.recordAndApplyTagEdit(edited);
      expect(await db.hasTagEditHistory('/music/b.mp3'), isTrue);

      final current = await db.getLocalTracksByPaths(['/music/b.mp3']);
      expect(current['/music/b.mp3']?.title, 'New Title');

      final restored = await db.undoLastTagEdit('/music/b.mp3');
      expect(restored?.title, 'Old Title');
      expect(restored?.artist, 'Old Artist');
    });

    test('findLocalTrackIndex matches SQL sort order accurately', () async {
      final now = DateTime(2026, 1, 1);
      await db.replaceAllLocalTracks([
        LocalSongItem(path: '/m/c.mp3', title: 'Charlie', artist: 'A', sizeBytes: 1, lastModified: now),
        LocalSongItem(path: '/m/a.mp3', title: 'Alpha', artist: 'A', sizeBytes: 1, lastModified: now),
        LocalSongItem(path: '/m/b.mp3', title: 'Bravo', artist: 'A', sizeBytes: 1, lastModified: now),
      ]);

      expect(await db.findLocalTrackIndex('/m/a.mp3', sort: 'Name (A-Z)'), 0);
      expect(await db.findLocalTrackIndex('/m/b.mp3', sort: 'Name (A-Z)'), 1);
      expect(await db.findLocalTrackIndex('/m/c.mp3', sort: 'Name (A-Z)'), 2);
    });

    test('SmartPlaylistSpec compiles and filters tracks via SQLite', () async {
      final now = DateTime(2026, 1, 1);
      await db.replaceAllLocalTracks([
        LocalSongItem(
          path: '/m/1.flac',
          title: 'Hi-Res Track',
          artist: 'Artist 1',
          sizeBytes: 5000,
          lastModified: now,
          sampleRate: 96000,
          bitDepth: 24,
          bpm: 125.0,
        ),
        LocalSongItem(
          path: '/m/2.mp3',
          title: 'Standard Track',
          artist: 'Artist 2',
          sizeBytes: 500,
          lastModified: now,
          sampleRate: 44100,
          bitDepth: 16,
          bpm: 90.0,
        ),
      ]);

      const spec = SmartPlaylistSpec(
        rules: [
          SmartPlaylistRule(
            field: SmartPlaylistField.sampleRate,
            op: SmartPlaylistOperator.greaterThan,
            value: '48000',
          ),
          SmartPlaylistRule(
            field: SmartPlaylistField.bpm,
            op: SmartPlaylistOperator.between,
            value: '120',
            value2: '130',
          ),
        ],
        matchAll: true,
      );
      final q = spec.compileToSql();
      final results = await db.queryCustomLocalTracks(
        whereSql: q.whereSql,
        variables: q.variables,
        orderBySql: q.orderBySql,
        limit: q.limit,
      );
      expect(results.length, 1);
      expect(results.first.path, '/m/1.flac');
    });
  });
}
