import 'dart:convert';
import 'package:dart_ytmusic_api/yt_music.dart';

void main() async {
  final ytmusic = YTMusic();
  print('Initializing YTMusic...');
  await ytmusic.initialize();

  print('Fetching Home Sections...');
  final homeSections = await ytmusic.getHomeSections();
  print('Found ${homeSections.length} home sections.\n');

  for (var i = 0; i < homeSections.length; i++) {
    final section = homeSections[i];
    print('Section [$i]: "${section.title}" (Items: ${section.contents.length})');

    for (var j = 0; j < section.contents.length && j < 3; j++) {
      final item = section.contents[j];
      print('  Item [$j]: Type = ${item.runtimeType}');
      if (item is Map) {
        print('    Keys: ${item.keys.toList()}');
        print('    Data: ${jsonEncode(item)}');
      } else {
        print('    Object: $item');
      }
    }
  }
}
