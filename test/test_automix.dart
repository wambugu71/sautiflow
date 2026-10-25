import 'dart:io';
import 'package:sautiflow/audio_engine_ffi.dart';
// ignore: avoid_relative_lib_imports
import '../sautiplay/lib/services/automix_analysis_service.dart';

void main() {
  print('Running Automix tests (pure Dart FFI)...');

  assert(AutomixStyle.bassSwap.value == 0);
  assert(AutomixStyle.beatBlend.value == 1);
  assert(AutomixStyle.filterSweep.value == 2);
  assert(AutomixStyle.spaceEcho.value == 3);
  assert(AutomixStyle.dropCut.value == 4);
  assert(AutomixStyle.smartHybrid.value == 5);

  assert(AutomixStyle.fromString('bass_swap') == AutomixStyle.bassSwap);
  assert(AutomixStyle.fromString('blend') == AutomixStyle.beatBlend);
  assert(AutomixStyle.fromString('filter') == AutomixStyle.filterSweep);
  assert(AutomixStyle.fromString('echo') == AutomixStyle.spaceEcho);
  assert(AutomixStyle.fromString('cut') == AutomixStyle.dropCut);
  assert(AutomixStyle.fromString('smart_hybrid') == AutomixStyle.smartHybrid);
  assert(AutomixStyle.fromString('auto') == AutomixStyle.smartHybrid);

  const config = AutomixConfig(
    enabled: true,
    style: AutomixStyle.bassSwap,
    transitionBars: 16,
    tempoSyncEnabled: true,
    keyLockEnabled: true,
  );
  assert(config.enabled == true);
  assert(config.style == AutomixStyle.bassSwap);
  assert(config.transitionBars == 16);

  print('Enum & model tests passed.');

  // Test Camelot Analysis Engine
  final service = AutomixAnalysisService.instance;
  assert(service.parseCamelotKey('Am') == '8A');
  assert(service.parseCamelotKey('A min') == '8A');
  assert(service.parseCamelotKey('C maj') == '8B');
  assert(service.parseCamelotKey('8B') == '8B');
  assert(service.parseCamelotKey('F#m') == '11A');
  assert(service.parseCamelotKey('G#m') == '1A');

  // Test Harmonic Mixing Relations
  assert(service.getHarmonicRelation('8A', '8A') == CamelotHarmonicRelation.exactMatch);
  assert(service.getHarmonicRelation('8A', '8B') == CamelotHarmonicRelation.relativePair);
  assert(service.getHarmonicRelation('8A', '7A') == CamelotHarmonicRelation.subdominant);
  assert(service.getHarmonicRelation('8A', '9A') == CamelotHarmonicRelation.dominant);
  assert(service.getHarmonicRelation('8A', '3A') == CamelotHarmonicRelation.energyBoost);

  // Test Playlist Optimization
  final tracks = [
    const TrackAutomixInfo(uri: '1', bpm: 120, musicalKey: 'Am', camelotKey: '8A', introEndSeconds: 10, outroStartSeconds: 200),
    const TrackAutomixInfo(uri: '2', bpm: 130, musicalKey: 'F#m', camelotKey: '11A', introEndSeconds: 10, outroStartSeconds: 200),
    const TrackAutomixInfo(uri: '3', bpm: 122, musicalKey: 'C', camelotKey: '8B', introEndSeconds: 10, outroStartSeconds: 200),
    const TrackAutomixInfo(uri: '4', bpm: 124, musicalKey: 'Em', camelotKey: '9A', introEndSeconds: 10, outroStartSeconds: 200),
  ];
  final ordered = service.optimizePlaylistOrder(tracks);
  assert(ordered.length == 4);
  assert(ordered[0].uri == '1'); // starts with Am (8A)
  assert(ordered[1].camelotKey == '8B' || ordered[1].camelotKey == '9A'); // smoothly connects to 8B or 9A

  // Test Dynamic Style Recommendation
  final styleMatch = service.recommendTransitionStyle(tracks[0], tracks[2]); // 8A -> 8B, 120 -> 122 BPM
  assert(styleMatch == AutomixStyle.smartHybrid);

  const clashTrack = TrackAutomixInfo(uri: 'x', bpm: 155, musicalKey: 'B', camelotKey: '1B', introEndSeconds: 10, outroStartSeconds: 200);
  final styleClash = service.recommendTransitionStyle(tracks[0], clashTrack); // 8A -> 1B, 120 -> 155 BPM
  assert(styleClash == AutomixStyle.dropCut);

  print('AutomixAnalysisService tests passed.');

  final dllPath = File('windows/build/Release/sautiflow.dll').existsSync()
      ? 'windows/build/Release/sautiflow.dll'
      : 'sautiflow.dll';
  print('Loading native DLL from $dllPath');

  final engine = AudioEngineFFI(libraryPath: dllPath);
  final ok = engine.create(sampleRate: 48000, channels: 2);
  assert(ok == true, 'engine create failed');

  // Initial default config should be disabled
  final initial = engine.getAutomixConfig();
  assert(initial.enabled == false, 'initial enabled should be false');

  // Set enabled with Bass-Swap style
  const target = AutomixConfig(
    enabled: true,
    style: AutomixStyle.bassSwap,
    transitionBars: 32,
    tempoSyncEnabled: true,
    keyLockEnabled: true,
  );
  engine.setAutomixConfig(target);

  final retrieved = engine.getAutomixConfig();
  assert(retrieved.enabled == true, 'retrieved.enabled failed');
  assert(retrieved.style == AutomixStyle.bassSwap, 'retrieved.style failed');
  assert(retrieved.transitionBars == 32, 'retrieved.transitionBars failed');
  assert(retrieved.tempoSyncEnabled == true, 'retrieved.tempoSyncEnabled failed');
  assert(retrieved.keyLockEnabled == true, 'retrieved.keyLockEnabled failed');

  // Status query
  final status = engine.getAutomixStatus();
  assert(status.style == AutomixStyle.bassSwap, 'status.style failed');
  assert(status.deckAVolume == 1.0, 'status.deckAVolume failed');
  assert(status.deckBVolume == 0.0, 'status.deckBVolume failed');

  // Test BPM APIs
  engine.setTrackBpm(128.0);
  assert((engine.getTrackBpm() - 128.0).abs() < 0.01, 'getTrackBpm failed');
  engine.setNextTrackBpm(132.0);

  // Test Space Echo and Beat Blend configurations
  const spaceEchoCfg = AutomixConfig(
    enabled: true,
    style: AutomixStyle.spaceEcho,
    transitionBars: 8,
    tempoSyncEnabled: true,
    keyLockEnabled: true,
  );
  engine.setAutomixConfig(spaceEchoCfg);
  assert(engine.getAutomixConfig().style == AutomixStyle.spaceEcho);

  const beatBlendCfg = AutomixConfig(
    enabled: true,
    style: AutomixStyle.beatBlend,
    transitionBars: 16,
    tempoSyncEnabled: true,
    keyLockEnabled: true,
  );
  engine.setAutomixConfig(beatBlendCfg);
  assert(engine.getAutomixConfig().style == AutomixStyle.beatBlend);

  engine.destroy();
  print('ALL AUTOMIX NATIVE & DART TESTS PASSED SUCCESSFULLY!');
}
