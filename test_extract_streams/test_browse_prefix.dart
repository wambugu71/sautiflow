import 'package:dart_ytmusic_api/yt_music.dart';

void main() async {
  final ytmusic = YTMusic();
  await ytmusic.initialize();

  final rawId = "RDCLAK5uy_lnm4v4arFrmL63NUzIdoXJe-E7G4_sriU";

  print('--- Test 1: getPlaylist without VL prefix ---');
  try {
    final p1 = await ytmusic.getPlaylist(rawId);
    print('p1 success: title = ${p1.name}, videoCount = ${p1.videoCount}');
  } catch (e) {
    print('p1 error: $e');
  }

  print('\n--- Test 2: getPlaylist with VL prefix (VL$rawId) ---');
  try {
    final p2 = await ytmusic.getPlaylist("VL$rawId");
    print('p2 success: title = ${p2.name}, videoCount = ${p2.videoCount}');
  } catch (e) {
    print('p2 error: $e');
  }

  print('\n--- Test 3: Raw constructRequest with browseId: rawId ---');
  try {
    final data1 = await ytmusic.constructRequest("browse", body: {"browseId": rawId});
    print('data1 keys: ${data1.keys}');
  } catch (e) {
    print('data1 error: $e');
  }

  print('\n--- Test 4: Raw constructRequest with browseId: VL$rawId ---');
  try {
    final data2 = await ytmusic.constructRequest("browse", body: {"browseId": "VL$rawId"});
    print('data2 keys: ${data2.keys}');
  } catch (e) {
    print('data2 error: $e');
  }
}
