import 'package:flutter_test/flutter_test.dart';
import 'package:sautiflow/sautiflow.dart';

void main() {
  test('Phase Inversion Test', () {
    final player = MiniAudioPlayer(libraryPath: 'sautiflow.dll');
    final ok = player.init();
    expect(ok, isTrue);

    player.setPhaseInversion(invertLeft: true, invertRight: false);
    final status1 = player.getPhaseInversion();
    print('Phase Inversion Status 1: left=${status1.left}, right=${status1.right}');
    expect(status1.left, isTrue);
    expect(status1.right, isFalse);

    player.setPhaseInversion(invertLeft: false, invertRight: true);
    final status2 = player.getPhaseInversion();
    print('Phase Inversion Status 2: left=${status2.left}, right=${status2.right}');
    expect(status2.left, isFalse);
    expect(status2.right, isTrue);

    player.dispose();
  });
}
