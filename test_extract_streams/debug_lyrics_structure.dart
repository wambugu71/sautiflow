import 'package:dart_ytmusic_api/dart_ytmusic_api.dart';
import 'package:dart_ytmusic_api/utils/traverse.dart';

void main() async {
  final yt = YTMusic();
  await yt.initialize();

  final queries = ['Imagine John Lennon', 'Queen Bohemian Rhapsody', 'Adele Hello', 'Ed Sheeran Perfect'];

  for (final q in queries) {
    print('\n=============================================');
    print('Testing query: "$q"');
    final results = await yt.searchSongs(q);
    if (results.isEmpty) {
      print('No search results');
      continue;
    }
    final song = results.first;
    print('Found song: "${song.name}" by ${song.artist.name} (ID: ${song.videoId})');

    final nextData = await yt.constructRequest('next', body: {'videoId': song.videoId});
    
    final tabs = traverse(nextData, ['contents', 'singleColumnMusicWatchNextResultsRenderer', 'tabbedRenderer', 'watchNextTabbedResultsRenderer', 'tabs']);
    if (tabs is List) {
      for (var i = 0; i < tabs.length; i++) {
        final tab = tabs[i]['tabRenderer'];
        if (tab != null) {
          final title = tab['title'];
          final unselectable = tab['unselectable'] ?? false;
          final endpoint = tab['endpoint'];
          final browseId = endpoint != null ? (endpoint['browseEndpoint'] != null ? endpoint['browseEndpoint']['browseId'] : null) : null;
          print('  Tab $i: title="$title", unselectable=$unselectable, browseId=$browseId');
        }
      }
    }

    try {
      final timed = await yt.getTimedLyrics(song.videoId);
      if (timed != null && timed.timedLyricsData.isNotEmpty) {
        print('  -> Timed lyrics found (${timed.timedLyricsData.length} lines). Source: ${timed.sourceMessage}');
        print('     First 2 lines:');
        for (var i = 0; i < timed.timedLyricsData.length && i < 2; i++) {
          final item = timed.timedLyricsData[i];
          print('     [${item.cueRange?.startTimeMilliseconds}ms]: ${item.lyricLine}');
        }
      } else {
        print('  -> No timed lyrics.');
        final plain = await yt.getLyrics(song.videoId);
        if (plain != null) {
          print('  -> Plain lyrics found (${plain.split('\n').length} lines)');
        } else {
          print('  -> No plain lyrics either.');
        }
      }
    } catch (e) {
      print('  -> Error fetching lyrics: $e');
    }
  }
}
