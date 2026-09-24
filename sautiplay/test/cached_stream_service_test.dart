import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sautiplay/services/cached_stream_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
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
  });
}
