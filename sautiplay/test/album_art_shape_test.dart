import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_m3shapes_extended/flutter_m3shapes_extended.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sautiplay/services/app_theme_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Album Art Shape & M3E Container Settings Tests', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('default useM3EAlbumArtShape is false (default square restored)', () {
      final service = AppThemeService.instance;
      expect(service.useM3EAlbumArtShape, isFalse);
    });

    test('saveUseM3EAlbumArtShape updates state and notifies stream', () async {
      final service = AppThemeService.instance;
      bool? streamEmittedValue;
      final sub = service.useM3EAlbumArtShapeChanged.stream.listen((val) {
        streamEmittedValue = val;
      });

      await service.saveUseM3EAlbumArtShape(true);
      await pumpEventQueue();
      expect(service.useM3EAlbumArtShape, isTrue);
      expect(streamEmittedValue, isTrue);

      await service.saveUseM3EAlbumArtShape(false);
      await pumpEventQueue();
      expect(service.useM3EAlbumArtShape, isFalse);
      expect(streamEmittedValue, isFalse);

      await sub.cancel();
    });

    test('saveAlbumArtShape updates shape and notifies stream', () async {
      final service = AppThemeService.instance;
      Shapes? emittedShape;
      final sub = service.albumArtShapeChanged.stream.listen((shape) {
        emittedShape = shape;
      });

      await service.saveAlbumArtShape(Shapes.bun);
      await pumpEventQueue();
      expect(service.albumArtShape, Shapes.bun);
      expect(emittedShape, Shapes.bun);

      await sub.cancel();
    });

    testWidgets('AppThemeProvider correctly exposes useM3EAlbumArtShape to BuildContext', (tester) async {
      final themeData = AppThemeService.themes.first;
      late bool contextUseM3E;
      late Shapes contextShape;

      await tester.pumpWidget(
        AppThemeProvider(
          themeData: themeData,
          albumArtShape: Shapes.heart,
          useM3EAlbumArtShape: true,
          child: Builder(
            builder: (context) {
              contextUseM3E = context.useM3EAlbumArtShape;
              contextShape = context.albumArtShape;
              return const SizedBox();
            },
          ),
        ),
      );

      expect(contextUseM3E, isTrue);
      expect(contextShape, Shapes.heart);
    });
  });
}
