import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sautiplay/database/preferences_store.dart';
import 'package:sautiplay/models/cached_stream_item.dart';
import 'package:sautiplay/services/cached_stream_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    PreferencesStore.instance.setMockValues({});
  });

  group('CachedStreamService Tests', () {
    test('refreshCache discovers physical files on disk and cleans videoId',
        () async {
      final service = CachedStreamService.instance;
      final dir = service.cacheDirectory;
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }

      // Create a mock stream file
      const testVideoId = 'unit_test_vid_123';
      final dummyFile =
          File('${dir.path}${Platform.pathSeparator}stream_$testVideoId.webm');
      dummyFile.writeAsBytesSync(List<int>.filled(2048, 42));

      try {
        final items = await service.refreshCache();

        expect(items.any((item) => item.videoId == testVideoId), isTrue);

        final cachedItem = service.getCachedItem(testVideoId);
        expect(cachedItem, isNotNull);
        expect(cachedItem!.videoId, equals(testVideoId));
        expect(cachedItem.fileSizeBytes, equals(2048));
        expect(service.totalSizeBytesNotifier.value, greaterThanOrEqualTo(2048));
      } finally {
        if (dummyFile.existsSync()) {
          dummyFile.deleteSync();
        }
      }
    });

    test('findExistingCacheFile finds file across supported extensions', () {
      final service = CachedStreamService.instance;
      final dir = service.cacheDirectory;
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }

      const testVideoId = 'unit_test_vid_ext';
      final dummyM4a =
          File('${dir.path}${Platform.pathSeparator}stream_$testVideoId.m4a');
      dummyM4a.writeAsBytesSync(List<int>.filled(1500, 1));

      try {
        final found = service.findExistingCacheFile(testVideoId);
        expect(found, isNotNull);
        expect(p.basename(found!.path), equals('stream_$testVideoId.m4a'));
      } finally {
        if (dummyM4a.existsSync()) {
          dummyM4a.deleteSync();
        }
      }
    });

    test('registerCachedStream and removeCachedStream work accurately',
        () async {
      final service = CachedStreamService.instance;
      final dir = service.cacheDirectory;
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }

      const testVideoId = 'unit_test_vid_reg';
      final dummyFile =
          File('${dir.path}${Platform.pathSeparator}stream_$testVideoId.webm');
      dummyFile.writeAsBytesSync(List<int>.filled(3000, 5));

      try {
        await service.registerCachedStream(
          videoId: testVideoId,
          title: 'Unit Test Song',
          artist: 'Unit Test Artist',
          filePath: dummyFile.path,
          fileSizeBytes: 3000,
        );

        expect(service.getCachedItem(testVideoId), isNotNull);
        final item = service.getCachedItem(testVideoId)!;
        expect(item.title, equals('Unit Test Song'));
        expect(item.artist, equals('Unit Test Artist'));

        await service.removeCachedStream(dummyFile.path);
        expect(service.getCachedItem(testVideoId), isNull);
        expect(dummyFile.existsSync(), isFalse);
      } finally {
        if (dummyFile.existsSync()) {
          dummyFile.deleteSync();
        }
      }
    });

    test('cacheStreamInBackground completes and registers file', () async {
      final service = CachedStreamService.instance;
      const testVideoId = 'test_bg_cache_vid';
      final dir = service.cacheDirectory;
      final dummyFile =
          File('${dir.path}${Platform.pathSeparator}stream_$testVideoId.webm');
      dummyFile.writeAsBytesSync(List<int>.filled(5000, 9));

      try {
        final success = await service.cacheStreamInBackground(
          videoId: testVideoId,
          streamUrl: '',
          title: 'Background Caching Song',
          artist: 'Background Artist',
        );

        expect(success, isTrue);
        expect(service.isDownloading(testVideoId), isFalse);
        final item = service.getCachedItem(testVideoId);
        expect(item, isNotNull);
        expect(item!.title, equals('Background Caching Song'));
      } finally {
        if (dummyFile.existsSync()) {
          dummyFile.deleteSync();
        }
        await service.removeCachedStream(dummyFile.path);
      }
    });

    test('CachedStreamItem preserves album metadata in serialization and copyWith',
        () {
      final now = DateTime.now();
      final item = CachedStreamItem(
        videoId: 'vid_alb_1',
        title: 'Song One',
        artist: 'Artist One',
        durationSeconds: 210,
        filePath: '/tmp/song1.mp3',
        fileSizeBytes: 4096,
        cachedAt: now,
        isUserDownload: true,
        album: 'Moonlight Symphony',
        albumId: 'ALB_MOON_99',
        albumArtist: 'Symphony Orchestra',
        trackNumber: 1,
      );

      expect(item.album, equals('Moonlight Symphony'));
      expect(item.albumId, equals('ALB_MOON_99'));
      expect(item.albumArtist, equals('Symphony Orchestra'));
      expect(item.trackNumber, equals(1));

      // Test map serialization & deserialization
      final map = item.toMap();
      final deserialized = CachedStreamItem.fromMap(map);
      expect(deserialized.album, equals('Moonlight Symphony'));
      expect(deserialized.albumId, equals('ALB_MOON_99'));
      expect(deserialized.albumArtist, equals('Symphony Orchestra'));
      expect(deserialized.trackNumber, equals(1));

      // Test copyWith
      final modified = item.copyWith(
        trackNumber: 2,
        title: 'Song Two',
      );
      expect(modified.trackNumber, equals(2));
      expect(modified.title, equals('Song Two'));
      expect(modified.album, equals('Moonlight Symphony'));
    });

    test('AlbumDownloadProgress computes correct progress and finishes correctly',
        () {
      final prog = AlbumDownloadProgress(
        albumKey: 'ALB_1',
        albumTitle: 'Super Album',
        totalTracks: 10,
        completedTracks: 5,
        failedTracks: 1,
        state: AlbumBatchState.downloading,
      );

      expect(prog.progress, equals(0.5));
      expect(prog.isCompleted, isFalse);

      final completed = prog.copyWith(
        completedTracks: 10,
        state: AlbumBatchState.completed,
      );
      expect(completed.progress, equals(1.0));
      expect(completed.isCompleted, isTrue);

      final zero = AlbumDownloadProgress(
        albumKey: 'ALB_EMPTY',
        albumTitle: 'Empty',
        totalTracks: 0,
      );
      expect(zero.progress, equals(0.0));
    });

    test(
        'CachedStreamService album queries and removeAlbumFromCache operate accurately',
        () async {
      final service = CachedStreamService.instance;
      final dir = service.cacheDirectory;
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }

      final file1 =
          File('${dir.path}${Platform.pathSeparator}stream_alb_t1.webm');
      final file2 =
          File('${dir.path}${Platform.pathSeparator}stream_alb_t2.webm');
      file1.writeAsBytesSync(List<int>.filled(1200, 1));
      file2.writeAsBytesSync(List<int>.filled(1200, 2));

      const albumTitle = 'Echoes of Eternity';
      const albumId = 'ALB_ECHOES_2026';

      try {
        await service.registerCachedStream(
          videoId: 'alb_t1',
          title: 'Track 1',
          artist: 'Ambient Artist',
          filePath: file1.path,
          fileSizeBytes: 1200,
          album: albumTitle,
          albumId: albumId,
          albumArtist: 'Ambient Artist',
          trackNumber: 1,
        );

        await service.registerCachedStream(
          videoId: 'alb_t2',
          title: 'Track 2',
          artist: 'Ambient Artist',
          filePath: file2.path,
          fileSizeBytes: 1200,
          album: albumTitle,
          albumId: albumId,
          albumArtist: 'Ambient Artist',
          trackNumber: 2,
        );

        // Verify retrieval ordered by trackNumber
        final tracks = service.getTracksForAlbum(albumTitle, albumId: albumId);
        expect(tracks.length, equals(2));
        expect(tracks[0].trackNumber, equals(1));
        expect(tracks[1].trackNumber, equals(2));

        // Verify cached count and fully cached detection
        expect(service.getAlbumCachedCount(albumTitle, albumId: albumId),
            equals(2));
        expect(
            service.isAlbumFullyCached(albumTitle,
                albumId: albumId, totalTracks: 2),
            isTrue);
        expect(
            service.isAlbumFullyCached(albumTitle,
                albumId: albumId, totalTracks: 3),
            isFalse);

        // Verify album removal
        await service.removeAlbumFromCache(albumTitle, albumId: albumId);
        expect(service.getTracksForAlbum(albumTitle, albumId: albumId), isEmpty);
        expect(file1.existsSync(), isFalse);
        expect(file2.existsSync(), isFalse);
      } finally {
        if (file1.existsSync()) file1.deleteSync();
        if (file2.existsSync()) file2.deleteSync();
      }
    });

    test('CachedStreamService cancelAlbumDownload cleans up batch state', () {
      final service = CachedStreamService.instance;
      service.cancelAlbumDownload('ALB_NON_EXISTENT');
      expect(service.isAlbumDownloading('ALB_NON_EXISTENT'), isFalse);
      expect(service.getAlbumDownloadProgress('ALB_NON_EXISTENT'), isNull);
    });
  });
}
