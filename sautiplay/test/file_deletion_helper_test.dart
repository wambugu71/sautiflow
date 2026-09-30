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

    test('BatchDeletionResult models success, cancellation, and error correctly', () {
      final ok = BatchDeletionResult.ok(count: 3, paths: ['/p1', '/p2', '/p3']);
      expect(ok.success, isTrue);
      expect(ok.cancelled, isFalse);
      expect(ok.deletedCount, 3);
      expect(ok.deletedPaths.length, 3);
      expect(ok.errorMessage, isNull);

      final cancelled = BatchDeletionResult.cancelled('User dismissed system dialog');
      expect(cancelled.success, isFalse);
      expect(cancelled.cancelled, isTrue);
      expect(cancelled.deletedCount, 0);
      expect(cancelled.errorMessage, 'User dismissed system dialog');

      final failed = BatchDeletionResult.failed('Permission denied');
      expect(failed.success, isFalse);
      expect(failed.cancelled, isFalse);
      expect(failed.deletedCount, 0);
      expect(failed.errorMessage, 'Permission denied');
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

    test('safeDeleteTrackFiles deletes multiple files in batch and triggers hook', () async {
      final tempDir = Directory.systemTemp.createTempSync('sautiplay_batch_del_test_');
      final file1 = File('${tempDir.path}${Platform.pathSeparator}track_01.mp3');
      final file2 = File('${tempDir.path}${Platform.pathSeparator}track_02.mp3');
      final file3 = File('${tempDir.path}${Platform.pathSeparator}track_03.mp3');

      file1.writeAsStringSync('sample 1');
      file2.writeAsStringSync('sample 2');
      file3.writeAsStringSync('sample 3');

      expect(file1.existsSync(), isTrue);
      expect(file2.existsSync(), isTrue);
      expect(file3.existsSync(), isTrue);

      List<String>? hookedPaths;
      final result = await FileDeletionHelper.safeDeleteTrackFiles(
        [file1.path, file2.path, file3.path],
        onBeforeDelete: (paths) async {
          hookedPaths = paths;
        },
      );

      expect(result.success, isTrue);
      expect(result.deletedCount, 3);
      expect(file1.existsSync(), isFalse);
      expect(file2.existsSync(), isFalse);
      expect(file3.existsSync(), isFalse);
      expect(hookedPaths?.length, 3);

      tempDir.deleteSync(recursive: true);
    });
  });
}
