import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sautiplay/services/file_deletion_helper.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('FileDeletionHelper Tests', () {
    test('normalizeFilePath handles various path and URI formats correctly', () {
      // 1. Quoted path
      expect(
        FileDeletionHelper.normalizeFilePath('"/storage/emulated/0/Music/Song.mp3"'),
        contains('Song.mp3'),
      );

      // 2. file:// URI
      final fromUri = FileDeletionHelper.normalizeFilePath('file:///storage/emulated/0/Music/Song.mp3');
      expect(fromUri.startsWith('file://'), isFalse);
      expect(fromUri, contains('Song.mp3'));

      // 3. Percent-encoded URL characters (%20 -> space)
      final decoded = FileDeletionHelper.normalizeFilePath('/storage/emulated/0/Music/My%20Favorite%20Song.mp3');
      expect(decoded, contains('My Favorite Song.mp3'));
      expect(decoded, isNot(contains('%20')));

      // 4. Combined file:// URI with percent-encoding
      final combined = FileDeletionHelper.normalizeFilePath('file:///storage/emulated/0/Music/Artist%20Name/Track%2001.flac');
      expect(combined.startsWith('file://'), isFalse);
      expect(combined, contains('Artist Name'));
      expect(combined, contains('Track 01.flac'));
    });

    test('DeletionResult models success, cancellation, and error correctly', () {
      final ok = DeletionResult.ok();
      expect(ok.success, isTrue);
      expect(ok.cancelled, isFalse);
      expect(ok.errorMessage, isNull);

      final cancelled = DeletionResult.cancelled('User tapped cancel');
      expect(cancelled.success, isFalse);
      expect(cancelled.cancelled, isTrue);
      expect(cancelled.errorMessage, 'User tapped cancel');

      final failed = DeletionResult.failed('Access denied');
      expect(failed.success, isFalse);
      expect(failed.cancelled, isFalse);
      expect(failed.errorMessage, 'Access denied');
    });

    test('safeDeleteTrackFile succeeds when file is already absent', () async {
      final result = await FileDeletionHelper.safeDeleteTrackFile(
        '/non_existent_folder_path/non_existent_song_12345.mp3',
      );
      expect(result.success, isTrue);
    });

    test('safeDeleteTrackFile physically removes existing file and runs hook', () async {
      final tempDir = Directory.systemTemp.createTempSync('sautiplay_del_test_');
      final testFile = File('${tempDir.path}${Platform.pathSeparator}test_song.mp3');
      testFile.writeAsStringSync('dummy audio data');

      expect(testFile.existsSync(), isTrue);

      String? hookedPath;
      final result = await FileDeletionHelper.safeDeleteTrackFile(
        testFile.path,
        onBeforeDelete: (path) async {
          hookedPath = path;
        },
      );

      expect(result.success, isTrue);
      expect(testFile.existsSync(), isFalse);
      expect(hookedPath, isNotNull);

      tempDir.deleteSync(recursive: true);
    });
  });
}
