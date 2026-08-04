import 'package:flutter_test/flutter_test.dart';
import 'package:sautiplay/widgets/synced_lyrics_widget.dart';

void main() {
  test('LrcParser test with user lyrics', () {
    final lrc = '''
[00:01.30] (Abbah)
[00:02.93] (This is Hendrick Sam)
[00:04.09] Rebete, rebete, rebete, rebete, rebete, yeah
[00:07.85] (Yeah) ooh-ooh
[00:12.22] Ah, yeah, yeah, yeah
[00:14.51] A legendary time catch a wine hapa sa ndio inabamba
[00:18.92] Na siwezi, sema sana
[00:22.19] Tena siezi bonga sana
[00:24.98] I never had a type in my life me ni vibe ndio hunibamba
''';

    final lines = LrcParser.parse(lrc);
    print('Parsed ${lines.length} lines:');
    for (var line in lines) {
      print('[${line.time.inMilliseconds}ms] ${line.text}');
    }
    expect(lines.length, equals(9));
    expect(lines[0].time.inMilliseconds, equals(1300));
    expect(lines[0].text, equals('(Abbah)'));
    expect(lines[1].time.inMilliseconds, equals(2930));
    expect(lines[1].text, equals('(This is Hendrick Sam)'));
  });
}
