import 'package:flutter_test/flutter_test.dart';
import 'package:sautiflow/sautiflow.dart';

void main() {
  test('Phase Inversion Test', () {
    final player = MiniAudioPlayer(libraryPath: 'sautiflow.dll');
    final ok = player.init();
    expect(ok, isTrue);

    player.setPhaseInversion(invertLeft: true, invertRight: false);
    final status1 = player.getPhaseInversion();
    expect(status1.left, isTrue);
    expect(status1.right, isFalse);

    player.setPhaseInversion(invertLeft: false, invertRight: true);
    final status2 = player.getPhaseInversion();
    expect(status2.left, isFalse);
    expect(status2.right, isTrue);

    player.dispose();
  });
}
