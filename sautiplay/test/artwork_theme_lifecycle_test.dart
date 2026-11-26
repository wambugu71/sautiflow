import 'dart:typed_data';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:sautiplay/database/app_database.dart';
import 'package:sautiplay/database/preferences_store.dart';
import 'package:sautiplay/services/app_theme_service.dart';
import 'package:sautiplay/services/artwork_theme/adaptive_theme_generator.dart';
import 'package:sautiplay/services/artwork_theme/artwork_palette_models.dart';
import 'package:sautiplay/services/artwork_theme_service.dart';

Uint8List _solidBlockPng(int bgArgb, int accentArgb, {int size = 160}) {
  final image = img.Image(width: size, height: size, numChannels: 4);
  final minBox = (size * 0.35).round();
  final maxBox = (size * 0.65).round();
  for (int y = 0; y < size; y++) {
    for (int x = 0; x < size; x++) {
      final c = (x >= minBox && x < maxBox && y >= minBox && y < maxBox)
          ? accentArgb
          : bgArgb;
      image.setPixelRgba(
        x,
        y,
        (c >> 16) & 0xFF,
        (c >> 8) & 0xFF,
        c & 0xFF,
        (c >> 24) & 0xFF,
      );
    }
  }
  return Uint8List.fromList(img.encodePng(image));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    PreferencesStore.instance.setMockValues({});
    await ArtworkThemeService.instance.resetForTesting();
    ArtworkThemeService.instance.configureForTesting(
      database: db,
      useNativeCodec: false,
    );
    await AppThemeService.instance.saveTheme(AppThemeId.dynamicAlbumArt);
  });

  tearDown(() async {
    await ArtworkThemeService.instance.resetForTesting();
    await db.close();
  });

  group('ArtworkThemeService Lifecycle, Caching & Concurrency', () {
    test('L1 hit, repeated artwork across tracks, and L2 Drift cache hit',
        () async {
      final service = ArtworkThemeService.instance;
      final redCover = _solidBlockPng(0xFF0A0A0C, 0xFFE11D48);

      // 1. Initial extraction -> cache miss (runs worker isolate).
      final first = await service.extractAdaptiveTheme(
        trackKey: 'file:///album/track_01.flac',
        artBytes: redCover,
      );
      expect(first.isFallback, isFalse);
      expect(service.lastMetrics?.cacheTier, 'miss');
      expect(service.cacheMisses, 1);

      // Allow fire-and-forget L2 Drift upsert microtasks to complete.
      await pumpEventQueue();

      // 2. Different track sharing identical artwork bytes -> immediate L1 hit.
      final second = await service.extractAdaptiveTheme(
        trackKey: 'file:///album/track_02.flac',
        artBytes: redCover,
      );
      expect(second, equals(first));
      expect(service.lastMetrics?.cacheTier, 'l1');
      expect(service.l1Hits, 1);

      // 3. Clear L1 memory cache -> next call recovers from L2 Drift DB.
      service.clearCache();
      expect(service.peek('file:///album/track_02.flac'), isNull);

      final third = await service.extractAdaptiveTheme(
        trackKey: 'file:///album/track_02.flac',
        artBytes: redCover,
      );
      expect(third, equals(first));
      expect(service.lastMetrics?.cacheTier, 'l2');
      expect(service.l2Hits, 1);
    });

    test('algorithm version mismatch invalidates stale L2 entry cleanly',
        () async {
      final service = ArtworkThemeService.instance;
      final blueCover = _solidBlockPng(0xFF0A0E18, 0xFF2563EB);
      final hash = ArtworkThemeService.computeArtworkHash(blueCover);

      await db.upsertArtworkPalette(
        artworkHash: hash,
        algorithmVersion: 0, // Outdated schema/algorithm version.
        payloadJson: '{"stale":true}',
      );

      final palette = await service.extractAdaptiveTheme(
        trackKey: 'track_version_test',
        artBytes: blueCover,
      );
      expect(palette.isFallback, isFalse);
      expect(service.lastMetrics?.cacheTier, 'miss');

      await pumpEventQueue();
      final refreshed = await db.getArtworkPalette(
        hash,
        expectedVersion: AdaptiveThemeGenerator.kAlgorithmVersion,
      );
      expect(refreshed, isNotNull);
      expect(
        refreshed!.algorithmVersion,
        AdaptiveThemeGenerator.kAlgorithmVersion,
      );
    });

    test('corrupted L2 JSON row is purged and re-extracted without error',
        () async {
      final service = ArtworkThemeService.instance;
      final greenCover = _solidBlockPng(0xFF0A140F, 0xFF10B981);
      final hash = ArtworkThemeService.computeArtworkHash(greenCover);

      await db.into(db.artworkPaletteEntries).insert(
            ArtworkPaletteEntriesCompanion.insert(
              artworkHash: hash,
              algorithmVersion: AdaptiveThemeGenerator.kAlgorithmVersion,
              payloadJson: '{broken-corrupt-json',
              createdAtMs: 1,
              lastAccessedAtMs: 1,
            ),
          );

      final palette = await service.extractAdaptiveTheme(
        trackKey: 'track_corrupt_l2',
        artBytes: greenCover,
      );
      expect(palette.isFallback, isFalse);
      expect(service.lastMetrics?.cacheTier, 'miss');
    });

    test('rapid track skips enforce stale-result protection (latest wins)',
        () async {
      final service = ArtworkThemeService.instance;
      final coverA = _solidBlockPng(0xFF09090B, 0xFFEF4444, size: 220);
      final coverB = _solidBlockPng(0xFF09090B, 0xFFF59E0B, size: 220);
      final coverC = _solidBlockPng(0xFF09090B, 0xFF06B6D4, size: 220);

      final emitted = <AdaptiveSemanticPalette>[];
      final sub = service.onSemanticPaletteChanged.listen(emitted.add);

      // Fire A, B, C back-to-back without awaiting intermediate results.
      final futA = service.extractAdaptiveTheme(trackKey: 'a', artBytes: coverA);
      final futB = service.extractAdaptiveTheme(trackKey: 'b', artBytes: coverB);
      final futC = service.extractAdaptiveTheme(trackKey: 'c', artBytes: coverC);

      final results = await Future.wait([futA, futB, futC]);
      await pumpEventQueue();
      await sub.cancel();

      final expectedC = results[2];
      expect(expectedC.isFallback, isFalse);
      expect(service.currentSemanticPalette, equals(expectedC));
      expect(emitted, isNotEmpty);
      expect(emitted.last, equals(expectedC));
    });

    test(
        'visual continuity holds previous valid theme during pending/corrupt art',
        () async {
      final service = ArtworkThemeService.instance;
      final purpleCover = _solidBlockPng(0xFF0E0A18, 0xFFA855F7);

      final valid = await service.extractAdaptiveTheme(
        trackKey: 'valid_track',
        artBytes: purpleCover,
      );
      expect(valid.isFallback, isFalse);

      // Corrupt image bytes preserve current valid theme instead of flashing.
      final onCorrupt = await service.extractAdaptiveTheme(
        trackKey: 'corrupt_track',
        artBytes: Uint8List.fromList([0, 1, 2, 3, 4, 5]),
      );
      expect(onCorrupt, equals(valid));
      expect(service.currentSemanticPalette, equals(valid));

      // Pending artwork download preserves current valid theme.
      final onPending = await service.extractAdaptiveTheme(
        trackKey: 'pending_track',
        artBytes: null,
        isArtworkPending: true,
      );
      expect(onPending, equals(valid));

      // Genuinely missing artwork transitions cleanly to fallback.
      final onMissing = await service.extractAdaptiveTheme(
        trackKey: 'missing_track',
        artBytes: null,
        isArtworkPending: false,
      );
      expect(onMissing.isFallback, isTrue);
    });

    test(
        'static theme modes remain unchanged and mode gate stops/resumes updates',
        () async {
      final themeService = AppThemeService.instance;
      final artService = ArtworkThemeService.instance;

      final staticBefore = <AppThemeId, AppThemeData>{
        for (final id in AppThemeId.values)
          if (id != AppThemeId.dynamicAlbumArt) id: AppThemeService.dataFor(id),
      };

      final amberCover = _solidBlockPng(0xFF140D06, 0xFFF59E0B);
      await artService.extractAdaptiveTheme(
        trackKey: 'adaptive_track',
        artBytes: amberCover,
        respectModeGate: true,
      );

      // Switch away to static darkBlue mode.
      await themeService.saveTheme(AppThemeId.darkBlue);
      expect(artService.isAdaptiveModeActive, isFalse);

      final emittedWhileStatic = <AppThemeId>[];
      final sub = themeService.themeChanged.stream.listen(emittedWhileStatic.add);

      final cyanCover = _solidBlockPng(0xFF061318, 0xFF06B6D4);
      await artService.extractAdaptiveTheme(
        trackKey: 'ignored_while_static',
        artBytes: cyanCover,
        respectModeGate: true,
      );
      await pumpEventQueue();
      expect(emittedWhileStatic, isEmpty);
      expect(themeService.currentData.primary,
          staticBefore[AppThemeId.darkBlue]!.primary);

      // Verify all 6 static themes remain completely untouched.
      for (final entry in staticBefore.entries) {
        await themeService.saveTheme(entry.key);
        expect(themeService.currentData.hasSameColors(entry.value), isTrue);
      }

      // Switch back to adaptive mode -> activates and exposes semantic palette.
      await themeService.saveTheme(AppThemeId.dynamicAlbumArt);
      expect(artService.isAdaptiveModeActive, isTrue);
      await artService.extractAdaptiveTheme(
        trackKey: 'resumed_track',
        artBytes: cyanCover,
        respectModeGate: true,
      );
      final adaptiveData = themeService.currentData;
      expect(adaptiveData.id, AppThemeId.dynamicAlbumArt);
      expect(adaptiveData.elevatedSurface, isNot(adaptiveData.bgDark));
      expect(adaptiveData.secondaryAccent, isNotNull);

      await sub.cancel();
    });

    test('worker extraction latency benchmark for 320x320 artwork is fast',
        () async {
      final service = ArtworkThemeService.instance;
      final largeCover = _solidBlockPng(0xFF0B0E14, 0xFFEC4899, size: 320);

      final sw = Stopwatch()..start();
      final palette = await service.extractAdaptiveTheme(
        trackKey: 'benchmark_320',
        artBytes: largeCover,
      );
      sw.stop();

      expect(palette.isFallback, isFalse);
      expect(service.lastMetrics, isNotNull);
      expect(service.lastMetrics!.sampledPixelCount, greaterThan(0));
      expect(service.lastMetrics!.workingBufferBytes, greaterThan(0));
      expect(sw.elapsedMilliseconds, lessThan(2500));
    });
  });
}
