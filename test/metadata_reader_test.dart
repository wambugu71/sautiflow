import 'dart:io';
import 'dart:isolate';
import 'package:flutter_test/flutter_test.dart';
import 'package:sautiflow/sautiflow.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('NativeAudioMetadata class and readMetadata API are available and isolate-safe', () {
    expect(NativeAudioMetadata, isNotNull);
    
    // STRICT ISOLATION: Network URLs must immediately return empty metadata with 0 network calls
    final networkMeta = NativeAudioMetadata.read('http://stream.example.com/live.mp3');
    expect(networkMeta.artist, isNull);
    expect(networkMeta.title, isNull);
    expect(networkMeta.pictures.isEmpty, isTrue);

    final httpsMeta = NativeAudioMetadata.read('https://stream.example.com/playlist.m3u8');
    expect(httpsMeta.artist, isNull);
    expect(httpsMeta.pictures.isEmpty, isTrue);

    // Non-existent file safely returns empty metadata
    final emptyMeta = readMetadata(File('non_existent_audio_file.flac'), getImage: true);
    expect(emptyMeta.artist, isNull);
    expect(emptyMeta.title, isNull);
    expect(emptyMeta.pictures.isEmpty, isTrue);
    expect(emptyMeta.trackGainDb, 0.0);
    expect(emptyMeta.albumGainDb, 0.0);
  });

  test('NativeAudioMetadata reads real audio file inside background isolate via Isolate.run', () async {
    const testFilePath = 'sautiplay/assets/hrirs/atmos.wav';
    final file = File(testFilePath);
    if (!file.existsSync()) {
      return;
    }

    final meta = await Isolate.run(() {
      return NativeAudioMetadata.read(testFilePath, getImage: true);
    });

    expect(meta.sampleRate, greaterThan(0));
    expect(meta.channels, greaterThan(0));
    expect(meta.duration, greaterThan(Duration.zero));
    expect(meta.codec.isNotEmpty, isTrue);
  });
}
