import 'package:test/test.dart';
import 'package:audio_metadata_reader/src/utils/date_parser.dart';

void main() {
  group('date_parser tests', () {
    test('8-digit date string YYYYMMDD (20161127)', () {
      final dt = parseDateSafely('20161127');
      expect(dt, isNotNull);
      expect(dt!.year, equals(2016));
      expect(dt.month, equals(11));
      expect(dt.day, equals(27));
    });

    test('8-digit integer YYYYMMDD (20161127)', () {
      final dt = parseDateSafely(20161127);
      expect(dt, isNotNull);
      expect(dt!.year, equals(2016));
      expect(dt.month, equals(11));
      expect(dt.day, equals(27));
    });

    test('4-digit year string (2016)', () {
      final dt = parseDateSafely('2016');
      expect(dt, isNotNull);
      expect(dt!.year, equals(2016));
    });

    test('4-digit year int (2016)', () {
      final dt = parseDateSafely(2016);
      expect(dt, isNotNull);
      expect(dt!.year, equals(2016));
    });

    test('ISO string (2016-11-27)', () {
      final dt = parseDateSafely('2016-11-27');
      expect(dt, isNotNull);
      expect(dt!.year, equals(2016));
      expect(dt.month, equals(11));
      expect(dt.day, equals(27));
    });

    test('Slash delimited (2016/11/27)', () {
      final dt = parseDateSafely('2016/11/27');
      expect(dt, isNotNull);
      expect(dt!.year, equals(2016));
      expect(dt.month, equals(11));
      expect(dt.day, equals(27));
    });

    test('Invalid / out-of-range strings do not throw', () {
      expect(parseDateSafely(null), isNull);
      expect(parseDateSafely(''), isNull);
      expect(parseDateSafely('not-a-date'), isNull);
      expect(parseDateSafely('999999999'), isNull);
    });
  });
}
