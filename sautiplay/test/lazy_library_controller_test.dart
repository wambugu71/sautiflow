import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sautiplay/database/app_database.dart';
import 'package:sautiplay/models/local_song_item.dart';
import 'package:sautiplay/services/lazy_library_controller.dart';

List<LocalSongItem> _generateTracks(int count) {
  final baseTime = DateTime(2026, 1, 1);
  return List.generate(count, (i) {
    final padded = i.toString().padLeft(4, '0');
    return LocalSongItem(
      path: '/music/artist_${i % 10}/album_${i % 20}/track_$padded.flac',
      title: 'Track $padded',
      artist: 'Artist ${i % 10}',
      album: 'Album ${i % 20}',
      genre: 'Audiophile',
      sizeBytes: (1000 + i) * 1024,
      lastModified: baseTime.add(Duration(minutes: i)),
      trackNumber: (i % 12) + 1,
    );
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  group('AppDatabase LocalTrackEntries', () {
    test('batch insert, count, windowed fetch, and sort orders', () async {
      final tracks = _generateTracks(250);
      await db.replaceAllLocalTracks(tracks);

      expect(await db.countLocalTracks(), equals(250));
      expect(await db.countLocalTracks(query: 'Track 004'), equals(10));

      final pageAsc = await db.fetchLocalTracksWindow(
        offset: 10,
        limit: 5,
        sort: 'Name (A-Z)',
      );
      expect(pageAsc.length, equals(5));
      expect(pageAsc.first.title, equals('Track 0010'));

      final pageDesc = await db.fetchLocalTracksWindow(
        offset: 0,
        limit: 3,
        sort: 'Name (Z-A)',
      );
      expect(pageDesc.first.title, equals('Track 0249'));

      final pageSize = await db.fetchLocalTracksWindow(
        offset: 0,
        limit: 2,
        sort: 'Size (Largest)',
      );
      expect(pageSize.first.title, equals('Track 0249'));
    });

    test('artist and album SQL summaries and drill-down queries', () async {
      final tracks = _generateTracks(100);
      await db.replaceAllLocalTracks(tracks);

      final artists = await db.fetchArtistSummaries();
      expect(artists.length, equals(10));
      expect(artists.first.trackCount, equals(10));

      final albums = await db.fetchAlbumSummaries(query: 'Album 1');
      // Matches Album 1, Album 10..19 => 11 albums
      expect(albums.length, equals(11));

      final artistTracks = await db.fetchTracksForArtist('Artist 3');
      expect(artistTracks.length, equals(10));
      expect(artistTracks.every((t) => t.artist == 'Artist 3'), isTrue);

      final albumTracks = await db.fetchTracksForAlbum('Album 5');
      expect(albumTracks.length, equals(5));
      expect(albumTracks.every((t) => t.album == 'Album 5'), isTrue);
    });

    test('upsert and delete by path or realFilePath', () async {
      final tracks = _generateTracks(5);
      await db.replaceAllLocalTracks(tracks);

      final updated = LocalSongItem(
        path: tracks[0].path,
        title: 'Updated Title',
        artist: 'Updated Artist',
        album: tracks[0].album,
        sizeBytes: tracks[0].sizeBytes,
        lastModified: tracks[0].lastModified,
      );
      await db.upsertLocalTrack(updated);

      final fetched = await db.fetchLocalTracksWindow(
        offset: 0,
        limit: 5,
        query: 'Updated Title',
      );
      expect(fetched.length, equals(1));
      expect(fetched.first.artist, equals('Updated Artist'));

      await db.deleteLocalTracksByPaths([tracks[1].path]);
      expect(await db.countLocalTracks(), equals(4));

      await db.deleteLocalTracksByRealPath(tracks[2].realFilePath);
      expect(await db.countLocalTracks(), equals(3));
    });
  });

  group('LazyLibraryController', () {
    test('loads chunk 0 on refresh and lazily fetches distant chunks', () async {
      await db.replaceAllLocalTracks(_generateTracks(150));
      final controller = LazyLibraryController(
        db: db,
        chunkSize: 20,
        maxCachedChunks: 3,
      );

      await controller.refresh();
      expect(controller.totalCount, equals(150));
      expect(controller.totalLibraryCount, equals(150));
      expect(controller.cachedChunkCount, equals(1));

      // Chunk 0 is immediately available
      expect(controller.getItem(0)?.title, equals('Track 0000'));

      // Distant index 135 is not cached yet -> returns null and schedules fetch
      expect(controller.getItem(135), isNull);
      await pumpEventQueue();
      expect(controller.getItem(135)?.title, equals('Track 0135'));

      controller.dispose();
    });

    test('enforces bounded LRU cache eviction', () async {
      await db.replaceAllLocalTracks(_generateTracks(200));
      final controller = LazyLibraryController(
        db: db,
        chunkSize: 16,
        maxCachedChunks: 3,
      );

      await controller.refresh();
      // Access 6 distinct chunks
      for (int c = 1; c <= 6; c++) {
        controller.getItem(c * 16);
        await pumpEventQueue();
      }

      expect(controller.cachedChunkCount, lessThanOrEqualTo(3));
      expect(controller.cachedItemCount, lessThanOrEqualTo(48));
      controller.dispose();
    });

    test('activeTrackPath updates without invalidating list cache or notifying list',
        () async {
      await db.replaceAllLocalTracks(_generateTracks(40));
      final controller = LazyLibraryController(db: db, chunkSize: 20);
      await controller.refresh();

      int listNotifications = 0;
      controller.addListener(() => listNotifications++);

      final activeEvents = <String?>[];
      controller.activeTrackPath.addListener(() {
        activeEvents.add(controller.activeTrackPath.value);
      });

      controller.setActiveTrackPath('/music/artist_5/album_5/track_0025.flac');
      expect(activeEvents.length, equals(1));
      expect(listNotifications, equals(0));
      expect(controller.cachedChunkCount, equals(1));

      final idx = await controller
          .findIndexOfPath('/music/artist_5/album_5/track_0025.flac');
      expect(idx, equals(25));

      final allPaths = await controller.fetchAllMatchingPaths();
      expect(allPaths.length, equals(40));

      controller.dispose();
    });
  });
}
