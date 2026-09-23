import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sautiflow/sautiflow.dart';
import 'package:sautiplay/isolate_player.dart';
import 'package:sautiplay/models/autoeq_profile.dart';
import 'package:sautiplay/services/app_state_service.dart';
import 'package:sautiplay/services/autoeq_parser.dart';
import 'package:sautiplay/services/autoeq_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakePlayerForAutoEq extends Fake implements IsolateAudioPlayer {
  double gain = 0.0;
  bool multibandFxEnabled = true;
  bool multibandFxCleared = false;
  bool multibandEqEnabled = true;
  final Map<int, double> eqBandGains = {};

  @override
  void setGain(double g) {
    gain = g;
  }

  @override
  void setMultibandFxEnabled(bool enabled) {
    multibandFxEnabled = enabled;
  }

  @override
  void clearMultibandFx() {
    multibandFxCleared = true;
  }

  @override
  void setMultibandEqBandGain(int index, double gainDb) {
    eqBandGains[index] = gainDb;
  }

  @override
  void setMultibandEqEnabled(bool enabled) {
    multibandEqEnabled = enabled;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AutoEqParser Differentiation & Parsing', () {
    test('Correctly differentiates between Parametric EQ and Graphic EQ formats', () {
      const peqSample = '''
Preamp: -6.5 dB
Filter 1: ON PK Fc 31 Hz Gain -4.2 dB Q 1.41
Filter 2: ON LSC Fc 105 Hz Gain 5.5 dB Q 0.71
''';

      const geqSample = '''
Preamp: -6.5 dB
GraphicEQ: 20 5.4; 25 5.5; 31.5 5.2; 40 4.5; 1000 0.1; 20000 -2.5
''';

      const csvGeqSample = '''
20.0, 5.4
25.0, 5.5
31.5, 5.2
40.0, 4.5
1000.0, 0.1
''';

      expect(AutoEqParser.isParametricEq(peqSample), isTrue);
      expect(AutoEqParser.isGraphicEq(peqSample), isFalse);

      expect(AutoEqParser.isGraphicEq(geqSample), isTrue);
      expect(AutoEqParser.isParametricEq(geqSample), isFalse);

      expect(AutoEqParser.isGraphicEq(csvGeqSample), isTrue);
      expect(AutoEqParser.isParametricEq(csvGeqSample), isFalse);
    });

    test('Parses EqualizerAPO Parametric EQ profile correctly', () {
      const peqSample = '''
# Sennheiser HD 600 Oratory1990
Preamp: -6.5 dB
Filter 1: ON PK Fc 31 Hz Gain -4.2 dB Q 1.41
Filter 2: ON LSC Fc 105 Hz Gain 5.5 dB Q 0.71
Filter 3: OFF PK Fc 2400 Hz Gain -3.1 dB Q 2.00
Filter 4: ON HSC Fc 10000 Hz Gain -2.0 dB Q 0.71
Filter 5: ON NOTCH Fc 6000 Hz Gain 0.0 dB Q 5.00
''';

      final result = AutoEqParser.parseContent(peqSample, profileName: 'HD 600');
      expect(result.isGraphicEq, isFalse);
      expect(result.isParametric, isTrue);
      expect(result.preampGainDb, closeTo(-6.5, 0.01));
      expect(result.parametricBands.length, 5);

      // Band 1
      final b1 = result.parametricBands[0];
      expect(b1.type, EqBandType.peak);
      expect(b1.frequencyHz, closeTo(31.0, 0.01));
      expect(b1.gainDb, closeTo(-4.2, 0.01));
      expect(b1.q, closeTo(1.41, 0.01));
      expect(b1.enabled, isTrue);

      // Band 2
      final b2 = result.parametricBands[1];
      expect(b2.type, EqBandType.lowshelf);
      expect(b2.frequencyHz, closeTo(105.0, 0.01));
      expect(b2.gainDb, closeTo(5.5, 0.01));
      expect(b2.q, closeTo(0.71, 0.01));

      // Band 3 (disabled)
      final b3 = result.parametricBands[2];
      expect(b3.enabled, isFalse);

      // Band 4 (high shelf)
      final b4 = result.parametricBands[3];
      expect(b4.type, EqBandType.highshelf);
      expect(b4.frequencyHz, closeTo(10000.0, 0.01));

      // Band 5 (notch)
      final b5 = result.parametricBands[4];
      expect(b5.type, EqBandType.notch);
      expect(b5.frequencyHz, closeTo(6000.0, 0.01));

      // Test frequency gain interpolation from parametric curve
      final gains10 = result.getGainsForFrequencies([32.0, 60.0, 125.0, 1000.0, 10000.0]);
      expect(gains10.length, 5);
      expect(gains10[0], isNotNull);
    });

    test('Parses EqualizerAPO GraphicEQ profile and interpolates properly', () {
      const geqSample = '''
Preamp: -6.1 dB
GraphicEQ: 20 0.2; 25 -0.5; 31.5 -1.2; 40 -1.8; 50 -2.5; 63 -3.2; 80 -4.0; 100 -4.5; 125 -4.8; 160 -4.5; 200 -3.8; 250 -2.5; 500 1.8; 1000 0.5; 2000 2.1; 4000 1.2; 8000 -1.5; 16000 0.5; 20000 0.0
''';

      final result = AutoEqParser.parseContent(geqSample, profileName: 'WH-1000XM4');
      expect(result.isGraphicEq, isTrue);
      expect(result.isParametric, isFalse);
      expect(result.preampGainDb, closeTo(-6.1, 0.01));
      expect(result.bandGainDbs31.length, 31);
      expect(result.rawGraphicPairs.isNotEmpty, isTrue);

      // Test interpolation to 10 bands
      const bands10 = [32.0, 60.0, 125.0, 250.0, 500.0, 1000.0, 2000.0, 4000.0, 8000.0, 16000.0];
      final gains10 = result.getGainsForFrequencies(bands10);
      expect(gains10.length, 10);
      expect(gains10[2], closeTo(-4.8, 0.1)); // 125 Hz
      expect(gains10[4], closeTo(1.8, 0.1)); // 500 Hz
      expect(gains10[5], closeTo(0.5, 0.1)); // 1000 Hz
    });

    test('AutoEqProfileModel serializes and deserializes cleanly', () {
      final model = AutoEqProfileModel(
        id: 'test_model_1',
        name: 'Test Headphone PEQ',
        modelName: 'Test Headphone',
        brand: 'TestBrand',
        target: 'Harman 2019',
        type: AutoEqType.parametric,
        preampDb: -5.0,
        parametricBands: [
          EqBandConfig(
            type: EqBandType.peak,
            frequencyHz: 1000.0,
            gainDb: 3.5,
            q: 1.4,
          ),
        ],
      );

      final json = model.toJson();
      final roundTrip = AutoEqProfileModel.fromJson(json);

      expect(roundTrip.id, model.id);
      expect(roundTrip.name, model.name);
      expect(roundTrip.type, AutoEqType.parametric);
      expect(roundTrip.preampDb, -5.0);
      expect(roundTrip.parametricBands.length, 1);
      expect(roundTrip.parametricBands.first.frequencyHz, 1000.0);
      expect(roundTrip.parametricBands.first.gainDb, 3.5);
    });

    test('Verifies all 24 built-in asset files parse without error', () {
      final manifestFile = File('assets/autoeq/manifest.json');
      expect(manifestFile.existsSync(), isTrue);

      final manifestContent = manifestFile.readAsStringSync();
      final List rawList = jsonDecode(manifestContent) as List;
      expect(rawList.length, 24);

      for (final item in rawList) {
        final assetPath = item['assetPath'] as String;
        final expectedType = item['type'] as String;
        final file = File(assetPath);
        expect(file.existsSync(), isTrue, reason: 'File $assetPath should exist');

        final content = file.readAsStringSync();
        final parsed = AutoEqParser.parseContent(content, profileName: item['name']);

        if (expectedType == 'parametric') {
          expect(parsed.isParametric, isTrue, reason: '$assetPath should be parametric');
          expect(parsed.parametricBands.isNotEmpty, isTrue);
        } else {
          expect(parsed.isGraphicEq, isTrue, reason: '$assetPath should be graphic');
          expect(parsed.bandGainDbs31.isNotEmpty, isTrue);
        }
      }
    });
  });

  group('AutoEqService Profile Reset & Bypass', () {
    test('clearActiveProfile resets preamp gain, PEQ, GEQ, and AppStateService to flat/off', () async {
      SharedPreferences.setMockInitialValues({
        'sp_active_autoeq_profile_id_v2': 'test_active_profile',
        'sp_parametric_eq_enabled': true,
        'sp_active_parametric_preset': 'HD 600',
        'sp_eq_enabled': true,
        'sp_eq_preset': 'WH-1000XM4',
        'sp_preamp_db': -6.5,
      });

      final fakePlayer = FakePlayerForAutoEq();
      fakePlayer.gain = 0.473; // non-1.0 gain
      fakePlayer.multibandFxEnabled = true;
      fakePlayer.multibandEqEnabled = true;

      await AutoEqService.instance.clearActiveProfile(fakePlayer);

      expect(AutoEqService.instance.activeProfile, isNull);
      expect(fakePlayer.gain, 1.0);
      expect(fakePlayer.multibandFxEnabled, isFalse);
      expect(fakePlayer.multibandFxCleared, isTrue);
      expect(fakePlayer.multibandEqEnabled, isFalse);
      expect(fakePlayer.eqBandGains.length, 32);
      expect(fakePlayer.eqBandGains.values.every((g) => g == 0.0), isTrue);

      final pEq = await AppStateService.instance.loadParametricEq();
      expect(pEq.enabled, isFalse);
      expect(pEq.bands, isEmpty);

      final geq = await AppStateService.instance.loadEqBands();
      expect(geq.enabled, isFalse);
      expect(geq.preset, 'Flat');
      expect(geq.gains.every((g) => g == 0.0), isTrue);
      expect(geq.preampDb, 0.0);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey('sp_active_autoeq_profile_id_v2'), isFalse);
      expect(prefs.containsKey('sp_active_parametric_preset'), isFalse);
    });
  });
}
