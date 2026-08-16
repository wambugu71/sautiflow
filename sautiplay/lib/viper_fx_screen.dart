import 'dart:async';
import 'package:flutter/material.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:flutter_m3shapes_extended/flutter_m3shapes_extended.dart';
import 'isolate_player.dart';
import 'eq_screen.dart';
import 'services/app_state_service.dart';
import 'package:file_picker/file_picker.dart';
import 'package:file_selector/file_selector.dart' as file_selector;
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:sautiflow/sautiflow.dart';
import 'widgets/parametric_eq_graph.dart';
import 'services/app_theme_service.dart';
import 'services/autoeq_parser.dart';

class ViperFxScreen extends StatefulWidget {
  final IsolateAudioPlayer player;

  const ViperFxScreen({super.key, required this.player});

  static Future<void> applySavedStateToEngine(IsolateAudioPlayer player) async {
    final map = await AppStateService.instance.loadViperFxState();

    bool viperEnabled = map['viperEnabled'] ?? false;
    player.setViperEnabled(viperEnabled);

    player.setViperMasterLimiter(
      threshold: map['masterLimiterThreshold'] ?? 1.0,
      outputVolume: map['masterLimiterVolume'] ?? 1.0,
      channelPan: map['masterLimiterPan'] ?? 0.0,
    );
    player.setViperPlaybackGain(
      enable: map['playbackGainEnabled'] ?? false,
      strength: map['playbackGainStrength'] ?? 0.5,
      maxGain: map['playbackGainMax'] ?? 0.5,
      outputThreshold: map['playbackGainThreshold'] ?? 0.9,
    );
    player.setViperLufs(
      enable: map['lufsEnabled'] ?? false,
      target: map['lufsTarget'] ?? -14.0,
      maxGainDb: map['lufsMaxGainDb'] ?? 6.0,
      speed: map['lufsSpeed'] ?? 1,
    );
    player.setViperAdaptiveLoudness(
      enable: map['alcEnabled'] ?? false,
      mode: map['alcMode'] ?? 0,
      strength: (map['alcStrength'] as num?)?.toDouble() ?? 1.0,
      attenuationDb: 0.0,
    );

    player.setViperStereoImager(
      enable: map['stereoImagerEnabled'] ?? false,
      lowWidth: map['stereoLowWidth'] ?? 100.0,
      midWidth: map['stereoMidWidth'] ?? 100.0,
      highWidth: map['stereoHighWidth'] ?? 100.0,
      lowCrossoverHz: (map['stereoLowCrossover'] as num?)?.toDouble() ?? 300.0,
      highCrossoverHz:
          (map['stereoHighCrossover'] as num?)?.toDouble() ?? 3000.0,
    );
    player.setViperCure(
      enable: map['cureEnabled'] ?? false,
      preset: map['curePreset'] ?? 0,
    );
    player.setViperHeadphoneSurround(
      enable: map['headphoneSurroundEnabled'] ?? false,
      quality: map['headphoneSurroundQuality'] ?? 1,
    );
    player.setViperFieldSurround(
      enable: map['fieldSurroundEnabled'] ?? false,
      widening: map['fieldWidening'] ?? 0.5,
      midImage: map['fieldMidImage'] ?? 0.5,
      depth: (map['fieldDepth'] as num?)?.toInt() ?? 2,
    );
    player.setViperDiffSurround(
      enable: map['diffSurroundEnabled'] ?? false,
      delay: map['diffDelay'] ?? 5.0,
      reverse: map['diffReverse'] ?? false,
      wetDryMix: map['diffWetDry'] ?? 0.5,
      lpCutoffHz: map['diffLpCutoff'] ?? 8000.0,
    );
    player.setViperReverb(
      enable: map['reverbEnabled'] ?? false,
      roomSize: map['reverbRoom'] ?? 0.5,
      width: map['reverbWidth'] ?? 0.5,
      damp: map['reverbDamp'] ?? 0.5,
      wet: map['reverbWet'] ?? 0.5,
      dry: map['reverbDry'] ?? 0.5,
    );

    player.setViperDynamicSystem(
      enable: map['dynamicSystemEnabled'] ?? false,
      xCoeffLow: (map['dynXLow'] as num?)?.toInt() ?? 40,
      xCoeffHigh: (map['dynXHigh'] as num?)?.toInt() ?? 60,
      yCoeffLow: (map['dynYLow'] as num?)?.toInt() ?? 100,
      yCoeffHigh: (map['dynYHigh'] as num?)?.toInt() ?? 150,
      sideGainLow: map['dynSideGainLow'] ?? 1.0,
      sideGainHigh: map['dynSideGainHigh'] ?? 1.0,
      strength: map['dynamicSystemStrength'] ?? 0.5,
    );

    final mbcCrossFreqs = (map['mbcCrossFreqs'] as List?)
            ?.map((e) => (e as num).toDouble())
            .toList() ??
        [120.0, 800.0, 4000.0, 10000.0];
    final mbcThresholds = (map['mbcThresholds'] as List?)
            ?.map((e) => (e as num).toDouble())
            .toList() ??
        [-20.0, -20.0, -20.0, -20.0, -20.0];
    final mbcRatios = (map['mbcRatios'] as List?)
            ?.map((e) => (e as num).toDouble())
            .toList() ??
        [2.0, 2.0, 2.0, 2.0, 2.0];
    final mbcAttacks = (map['mbcAttacks'] as List?)
            ?.map((e) => (e as num).toDouble())
            .toList() ??
        [10.0, 10.0, 10.0, 10.0, 10.0];
    final mbcReleases = (map['mbcReleases'] as List?)
            ?.map((e) => (e as num).toDouble())
            .toList() ??
        [100.0, 100.0, 100.0, 100.0, 100.0];
    final mbcGains = (map['mbcGains'] as List?)
            ?.map((e) => (e as num).toDouble())
            .toList() ??
        [0.0, 0.0, 0.0, 0.0, 0.0];
    player.setViperMultibandCompressor(
      enable: map['multibandCompressorEnabled'] ?? false,
      crossoverFreqs: mbcCrossFreqs,
      bands: List.generate(
          5,
          (i) => {
                'enable': true,
                'threshold': mbcThresholds[i],
                'ratio': mbcRatios[i],
                'attack': mbcAttacks[i],
                'release': mbcReleases[i],
                'gain': mbcGains[i],
              }),
    );
    player.setViperFetCompressor(
      enable: map['fetCompressorEnabled'] ?? false,
      threshold: map['fetThreshold'] ?? 0.0,
      ratio: map['fetRatio'] ?? 1.0,
      knee: map['fetKnee'] ?? 0.0,
      kneeAuto: map['fetKneeAuto'] ?? false,
      gain: map['fetGain'] ?? 0.0,
      gainAuto: map['fetGainAuto'] ?? false,
      attack: map['fetAttack'] ?? 20.0,
      attackAuto: map['fetAttackAuto'] ?? false,
      release: map['fetRelease'] ?? 100.0,
      releaseAuto: map['fetReleaseAuto'] ?? false,
      kneeMulti: map['fetKneeMulti'] ?? 0.0,
      maxAttack: map['fetMaxAttack'] ?? 20.0,
      maxRelease: map['fetMaxRelease'] ?? 100.0,
      crest: map['fetCrest'] ?? 0.0,
      adapt: map['fetAdapt'] ?? 0.0,
      noClip: map['fetNoClip'] ?? false,
    );

    player.setViperBass(
      enable: map['bassEnabled'] ?? false,
      mode: map['bassMode'] ?? 1,
      frequencyHz: (map['bassFreq'] as num?)?.round() ?? 80,
      gain: map['bassGain'] ?? 0.5,
      antiPop: map['bassAntiPop'] ?? false,
    );
    player.setViperBassMono(
      enable: map['bassMonoEnabled'] ?? false,
      mode: map['bassMonoMode'] ?? 1,
      frequencyHz: (map['bassMonoFreq'] as num?)?.round() ?? 80,
      gain: map['bassMonoGain'] ?? 0.5,
      antiPop: map['bassMonoAntiPop'] ?? false,
    );
    player.setViperPsychoacousticBass(
      enable: map['psychoBassEnabled'] ?? false,
      cutoffHz: (map['psychoCutoff'] as num?)?.round() ?? 80,
      intensity: (map['psychoIntensity'] as num?)?.round() ?? 50,
      harmonicOrder: (map['psychoHarmonicOrder'] as num?)?.toInt() ?? 2,
      originalLevel: (map['psychoOriginalLevel'] as num?)?.round() ?? 100,
    );
    player.setViperClarity(
      enable: map['clarityEnabled'] ?? false,
      mode: map['clarityMode'] ?? 0,
      gain: map['clarityGain'] ?? 0.5,
    );
    player.setViperSpectrumExtension(
      enable: map['spectrumEnabled'] ?? false,
      strength: (map['spectrumStrength'] as num?)?.round() ?? 50,
      exciter: map['spectrumExciter'] ?? 0.5,
    );

    bool convolverEnabled = map['convolverEnabled'] ?? false;
    double convolverCrossChannel =
        (map['convolverCrossChannel'] as num?)?.toDouble() ?? 0.0;
    player.setViperConvolver(
        enable: convolverEnabled, crossChannel: convolverCrossChannel);
    if (convolverEnabled &&
        map['convolverFolder'] != null &&
        map['selectedConvolverFile'] != null) {
      player.loadViperConvolver(
          p.join(map['convolverFolder'], map['selectedConvolverFile']));
    }

    final dynamicEqFreqs = (map['dynamicEqFreqs'] as List?)
            ?.map((e) => (e as num).toDouble())
            .toList() ??
        [100.0, 250.0, 1000.0, 4000.0, 8000.0];
    final dynamicEqGains = (map['dynamicEqGains'] as List?)
            ?.map((e) => (e as num).toDouble())
            .toList() ??
        [0.0, 0.0, 0.0, 0.0, 0.0];
    player.setViperDynamicEq(
      enable: map['dynamicEqEnabled'] ?? false,
      bands: List.generate(
          5,
          (i) => {
                'frequencyHz': dynamicEqFreqs[i],
                'q': (map['dynamicEqQs'] as List?)
                        ?.map((e) => (e as num).toDouble())
                        .toList()[i] ??
                    1.0,
                'gainDb': dynamicEqGains[i],
                'thresholdDb': (map['dynamicEqThresholds'] as List?)
                        ?.map((e) => (e as num).toDouble())
                        .toList()[i] ??
                    -20.0,
                'attackMs': (map['dynamicEqAttacks'] as List?)
                        ?.map((e) => (e as num).toDouble())
                        .toList()[i] ??
                    20.0,
                'releaseMs': (map['dynamicEqReleases'] as List?)
                        ?.map((e) => (e as num).toDouble())
                        .toList()[i] ??
                    100.0,
                'filterType': (map['dynamicEqFilterTypes'] as List?)
                        ?.map((e) => (e as num).toInt())
                        .toList()[i] ??
                    0,
              }),
    );

    bool ddcEnabled = map['ddcEnabled'] ?? false;
    player.setViperDdc(ddcEnabled);
    if (ddcEnabled &&
        map['ddcFolder'] != null &&
        map['selectedDdcFile'] != null) {
      player.loadViperDdc(p.join(map['ddcFolder'], map['selectedDdcFile']));
    }

    player.setViperTubeSimulator(map['tubeEnabled'] ?? false);
    player.setViperAnalogX(
      enable: map['analogXEnabled'] ?? false,
      mode: map['analogXMode'] ?? 1,
    );
    player.setViperSpeakerCorrection(map['speakerCorrectionEnabled'] ?? false);
  }

  @override
  State<ViperFxScreen> createState() => _ViperFxScreenState();
}

class _ViperFxScreenState extends State<ViperFxScreen>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  // Reactive theme colors from BuildContext
  Color get primaryColor => context.primaryColor;
  Color get bgDarkColor => context.bgDark;
  Color get surfaceDarkColor => context.cardDark;
  Color get surfaceDarkerColor => context.cardDark.withValues(alpha: 0.8);

  bool _viperEnabled = false;

  // --- Core & Limits ---
  double _masterLimiterThreshold = 1.0;
  double _masterLimiterVolume = 1.0;
  double _masterLimiterPan = 0.0;

  bool _playbackGainEnabled = false;
  double _playbackGainStrength = 0.5;
  double _playbackGainMax = 0.5;
  double _playbackGainThreshold = 0.9;

  bool _lufsEnabled = false;
  double _lufsTarget = -14.0;
  double _lufsMaxGainDb = 6.0;
  int _lufsSpeed = 1; // 0: Slow, 1: Normal, 2: Fast

  bool _alcEnabled = false;
  int _alcMode = 0; // 0: Natural, 1: Mild, 2: Punchy
  double _alcStrength = 1.0;

  // --- Spatial & Surround ---
  bool _stereoImagerEnabled = false;
  double _stereoLowWidth = 100.0;
  double _stereoMidWidth = 100.0;
  double _stereoHighWidth = 100.0;
  double _stereoLowCrossover = 300.0;
  double _stereoHighCrossover = 3000.0;

  bool _cureEnabled = false;
  int _curePreset = 0;

  bool _headphoneSurroundEnabled = false;
  int _headphoneSurroundQuality = 1;

  bool _fieldSurroundEnabled = false;
  double _fieldWidening = 0.5;
  double _fieldMidImage = 0.5;
  int _fieldDepth = 2;

  bool _diffSurroundEnabled = false;
  double _diffDelay = 5.0; // ms
  bool _diffReverse = false;
  double _diffWetDry = 0.5;
  double _diffLpCutoff = 8000.0;

  bool _reverbEnabled = false;
  double _reverbRoom = 0.5;
  double _reverbWidth = 0.5;
  double _reverbDamp = 0.5;
  double _reverbWet = 0.5;
  double _reverbDry = 0.5;

  // --- Dynamics & Compression ---
  bool _dynamicSystemEnabled = false;
  double _dynamicSystemStrength = 0.5;
  int _dynPreset = 0; // 0: Custom, 1: Common Earphone, 2: High-end Headphone
  double _dynXLow = 40.0;
  double _dynXHigh = 60.0;
  double _dynYLow = 100.0;
  double _dynYHigh = 150.0;
  double _dynSideGainLow = 1.0;
  double _dynSideGainHigh = 1.0;

  bool _multibandCompressorEnabled = false;
  List<double> _mbcCrossFreqs = [120.0, 800.0, 4000.0, 10000.0];
  List<double> _mbcThresholds = [-20.0, -20.0, -20.0, -20.0, -20.0];
  List<double> _mbcRatios = [2.0, 2.0, 2.0, 2.0, 2.0];
  List<double> _mbcAttacks = [10.0, 10.0, 10.0, 10.0, 10.0];
  List<double> _mbcReleases = [100.0, 100.0, 100.0, 100.0, 100.0];
  List<double> _mbcGains = [0.0, 0.0, 0.0, 0.0, 0.0];

  bool _fetCompressorEnabled = false;
  double _fetThreshold = 0.0;
  double _fetRatio = 1.0;
  double _fetKnee = 0.0;
  bool _fetKneeAuto = false;
  double _fetGain = 0.0;
  bool _fetGainAuto = false;
  double _fetAttack = 20.0;
  bool _fetAttackAuto = false;
  double _fetRelease = 100.0;
  bool _fetReleaseAuto = false;
  double _fetKneeMulti = 0.0;
  double _fetMaxAttack = 20.0;
  double _fetMaxRelease = 100.0;
  double _fetCrest = 0.0;
  double _fetAdapt = 0.0;
  bool _fetNoClip = false;

  // --- Bass & Clarity ---
  bool _bassEnabled = false;
  int _bassMode = 1;
  double _bassFreq = 80.0;
  double _bassGain = 0.5;
  bool _bassAntiPop = false;

  bool _bassMonoEnabled = false;
  int _bassMonoMode = 1;
  double _bassMonoFreq = 80.0;
  double _bassMonoGain = 0.5;
  bool _bassMonoAntiPop = false;

  bool _psychoBassEnabled = false;
  double _psychoCutoff = 80.0;
  double _psychoIntensity = 50.0;
  int _psychoHarmonicOrder = 2;
  double _psychoOriginalLevel = 100.0;

  bool _clarityEnabled = false;
  int _clarityMode = 0; // 0: Natural, 1: Ozone+, 2: XHiFi
  double _clarityGain = 0.5;

  bool _spectrumEnabled = false;
  double _spectrumStrength = 50.0;
  double _spectrumExciter = 0.5;

  // --- Equalization ---
  bool _firEqEnabled = false;
  final List<double> _firEqFreqs = [100.0, 250.0, 1000.0, 4000.0, 8000.0];
  final List<double> _firEqGains = [0.0, 0.0, 0.0, 0.0, 0.0];

  bool _dynamicEqEnabled = false;
  List<double> _dynamicEqFreqs = [100.0, 250.0, 1000.0, 4000.0, 8000.0];
  List<double> _dynamicEqGains = [0.0, 0.0, 0.0, 0.0, 0.0];
  List<double> _dynamicEqQs = [1.0, 1.0, 1.0, 1.0, 1.0];
  List<double> _dynamicEqThresholds = [-20.0, -20.0, -20.0, -20.0, -20.0];
  List<double> _dynamicEqAttacks = [20.0, 20.0, 20.0, 20.0, 20.0];
  List<double> _dynamicEqReleases = [100.0, 100.0, 100.0, 100.0, 100.0];
  List<int> _dynamicEqFilterTypes = [0, 0, 0, 0, 0];

  bool _iirEqEnabled = false;
  final List<double> _iirEqFreqs = [100.0, 250.0, 1000.0, 4000.0, 8000.0];
  final List<double> _iirEqGains = [0.0, 0.0, 0.0, 0.0, 0.0];

  String? _convolverFolder;
  String? _selectedConvolverFile;
  List<String> _convolverFiles = [];
  bool _convolverEnabled = false;
  double _convolverCrossChannel = 0.0;

  String? _ddcFolder;
  String? _selectedDdcFile;
  List<String> _ddcFiles = [];
  bool _ddcEnabled = false;

  // --- Analog & Emulation ---
  bool _tubeEnabled = false;

  bool _analogXEnabled = false;
  int _analogXMode = 1; // moderate

  bool _speakerCorrectionEnabled = false;

  StateSetter? _subScreenSetState;

  @override
  void setState(VoidCallback fn) {
    super.setState(fn);
    _subScreenSetState?.call(() {});
  }

  StreamSubscription<void>? _eqSettingsSub;

  @override
  void initState() {
    super.initState();
    _loadState();
    _eqSettingsSub =
        AppStateService.instance.eqSettingsChanged.stream.listen((_) {
      if (mounted) _loadState();
    });
  }

  @override
  void dispose() {
    _eqSettingsSub?.cancel();
    super.dispose();
  }

  Future<void> _loadState() async {
    final map = await AppStateService.instance.loadViperFxState();
    if (mounted) {
      setState(() {
        _fromMap(map);
      });
    }
  }

  Map<String, dynamic> _toMap() {
    return {
      'viperEnabled': _viperEnabled,
      'masterLimiterThreshold': _masterLimiterThreshold,
      'masterLimiterVolume': _masterLimiterVolume,
      'masterLimiterPan': _masterLimiterPan,
      'playbackGainEnabled': _playbackGainEnabled,
      'playbackGainStrength': _playbackGainStrength,
      'playbackGainMax': _playbackGainMax,
      'playbackGainThreshold': _playbackGainThreshold,
      'lufsEnabled': _lufsEnabled,
      'lufsTarget': _lufsTarget,
      'lufsMaxGainDb': _lufsMaxGainDb,
      'lufsSpeed': _lufsSpeed,
      'alcEnabled': _alcEnabled,
      'alcMode': _alcMode,
      'alcStrength': _alcStrength,
      'stereoImagerEnabled': _stereoImagerEnabled,
      'stereoLowWidth': _stereoLowWidth,
      'stereoMidWidth': _stereoMidWidth,
      'stereoHighWidth': _stereoHighWidth,
      'stereoLowCrossover': _stereoLowCrossover,
      'stereoHighCrossover': _stereoHighCrossover,
      'cureEnabled': _cureEnabled,
      'curePreset': _curePreset,
      'headphoneSurroundEnabled': _headphoneSurroundEnabled,
      'headphoneSurroundQuality': _headphoneSurroundQuality,
      'fieldSurroundEnabled': _fieldSurroundEnabled,
      'fieldWidening': _fieldWidening,
      'fieldMidImage': _fieldMidImage,
      'fieldDepth': _fieldDepth,
      'diffSurroundEnabled': _diffSurroundEnabled,
      'diffDelay': _diffDelay,
      'diffReverse': _diffReverse,
      'diffWetDry': _diffWetDry,
      'diffLpCutoff': _diffLpCutoff,
      'reverbEnabled': _reverbEnabled,
      'reverbRoom': _reverbRoom,
      'reverbWidth': _reverbWidth,
      'reverbDamp': _reverbDamp,
      'reverbWet': _reverbWet,
      'reverbDry': _reverbDry,
      'dynamicSystemEnabled': _dynamicSystemEnabled,
      'dynamicSystemStrength': _dynamicSystemStrength,
      'dynPreset': _dynPreset,
      'dynXLow': _dynXLow,
      'dynXHigh': _dynXHigh,
      'dynYLow': _dynYLow,
      'dynYHigh': _dynYHigh,
      'dynSideGainLow': _dynSideGainLow,
      'dynSideGainHigh': _dynSideGainHigh,
      'multibandCompressorEnabled': _multibandCompressorEnabled,
      'mbcCrossFreqs': _mbcCrossFreqs,
      'mbcThresholds': _mbcThresholds,
      'mbcRatios': _mbcRatios,
      'mbcAttacks': _mbcAttacks,
      'mbcReleases': _mbcReleases,
      'mbcGains': _mbcGains,
      'fetCompressorEnabled': _fetCompressorEnabled,
      'fetThreshold': _fetThreshold,
      'fetRatio': _fetRatio,
      'fetKnee': _fetKnee,
      'fetKneeAuto': _fetKneeAuto,
      'fetGain': _fetGain,
      'fetGainAuto': _fetGainAuto,
      'fetAttack': _fetAttack,
      'fetAttackAuto': _fetAttackAuto,
      'fetRelease': _fetRelease,
      'fetReleaseAuto': _fetReleaseAuto,
      'fetKneeMulti': _fetKneeMulti,
      'fetMaxAttack': _fetMaxAttack,
      'fetMaxRelease': _fetMaxRelease,
      'fetCrest': _fetCrest,
      'fetAdapt': _fetAdapt,
      'fetNoClip': _fetNoClip,
      'bassEnabled': _bassEnabled,
      'bassMode': _bassMode,
      'bassFreq': _bassFreq,
      'bassGain': _bassGain,
      'bassAntiPop': _bassAntiPop,
      'bassMonoEnabled': _bassMonoEnabled,
      'bassMonoMode': _bassMonoMode,
      'bassMonoFreq': _bassMonoFreq,
      'bassMonoGain': _bassMonoGain,
      'bassMonoAntiPop': _bassMonoAntiPop,
      'psychoBassEnabled': _psychoBassEnabled,
      'psychoCutoff': _psychoCutoff,
      'psychoIntensity': _psychoIntensity,
      'psychoHarmonicOrder': _psychoHarmonicOrder,
      'psychoOriginalLevel': _psychoOriginalLevel,
      'clarityEnabled': _clarityEnabled,
      'clarityMode': _clarityMode,
      'clarityGain': _clarityGain,
      'spectrumEnabled': _spectrumEnabled,
      'spectrumStrength': _spectrumStrength,
      'spectrumExciter': _spectrumExciter,
      'firEqEnabled': _firEqEnabled,
      'dynamicEqEnabled': _dynamicEqEnabled,
      'dynamicEqFreqs': _dynamicEqFreqs,
      'dynamicEqGains': _dynamicEqGains,
      'dynamicEqQs': _dynamicEqQs,
      'dynamicEqThresholds': _dynamicEqThresholds,
      'dynamicEqAttacks': _dynamicEqAttacks,
      'dynamicEqReleases': _dynamicEqReleases,
      'dynamicEqFilterTypes': _dynamicEqFilterTypes,
      'iirEqEnabled': _iirEqEnabled,
      'tubeEnabled': _tubeEnabled,
      'analogXEnabled': _analogXEnabled,
      'analogXMode': _analogXMode,
      'speakerCorrectionEnabled': _speakerCorrectionEnabled,
      'convolverEnabled': _convolverEnabled,
      'convolverCrossChannel': _convolverCrossChannel,
      'convolverFolder': _convolverFolder,
      'selectedConvolverFile': _selectedConvolverFile,
      'ddcEnabled': _ddcEnabled,
      'ddcFolder': _ddcFolder,
      'selectedDdcFile': _selectedDdcFile,
    };
  }

  void _fromMap(Map<String, dynamic> map) {
    _viperEnabled = map['viperEnabled'] ?? false;
    _masterLimiterThreshold =
        (map['masterLimiterThreshold'] as num?)?.toDouble() ?? 1.0;
    _masterLimiterVolume =
        (map['masterLimiterVolume'] as num?)?.toDouble() ?? 1.0;
    _masterLimiterPan = (map['masterLimiterPan'] as num?)?.toDouble() ?? 0.0;
    _playbackGainEnabled = map['playbackGainEnabled'] ?? false;
    _playbackGainStrength =
        (map['playbackGainStrength'] as num?)?.toDouble() ?? 0.5;
    _playbackGainMax = (map['playbackGainMax'] as num?)?.toDouble() ?? 0.5;
    _playbackGainThreshold =
        (map['playbackGainThreshold'] as num?)?.toDouble() ?? 0.9;
    _lufsEnabled = map['lufsEnabled'] ?? false;
    _lufsTarget = (map['lufsTarget'] as num?)?.toDouble() ?? -14.0;
    _lufsMaxGainDb = (map['lufsMaxGainDb'] as num?)?.toDouble() ?? 6.0;
    _lufsSpeed = (map['lufsSpeed'] as num?)?.toInt() ?? 1;
    _alcEnabled = map['alcEnabled'] ?? false;
    _alcMode = (map['alcMode'] as num?)?.toInt() ?? 0;
    _alcStrength = (map['alcStrength'] as num?)?.toDouble() ?? 1.0;
    _stereoImagerEnabled = map['stereoImagerEnabled'] ?? false;
    _stereoLowWidth = (map['stereoLowWidth'] as num?)?.toDouble() ?? 100.0;
    _stereoMidWidth = (map['stereoMidWidth'] as num?)?.toDouble() ?? 100.0;
    _stereoHighWidth = (map['stereoHighWidth'] as num?)?.toDouble() ?? 100.0;
    _stereoLowCrossover =
        (map['stereoLowCrossover'] as num?)?.toDouble() ?? 300.0;
    _stereoHighCrossover =
        (map['stereoHighCrossover'] as num?)?.toDouble() ?? 3000.0;
    _cureEnabled = map['cureEnabled'] ?? false;
    _curePreset = (map['curePreset'] as num?)?.toInt() ?? 0;
    _headphoneSurroundEnabled = map['headphoneSurroundEnabled'] ?? false;
    _headphoneSurroundQuality =
        (map['headphoneSurroundQuality'] as num?)?.toInt() ?? 1;
    _fieldSurroundEnabled = map['fieldSurroundEnabled'] ?? false;
    _fieldWidening = (map['fieldWidening'] as num?)?.toDouble() ?? 0.5;
    _fieldMidImage = (map['fieldMidImage'] as num?)?.toDouble() ?? 0.5;
    _fieldDepth = (map['fieldDepth'] as num?)?.toInt() ?? 2;
    _diffSurroundEnabled = map['diffSurroundEnabled'] ?? false;
    _diffDelay = (map['diffDelay'] as num?)?.toDouble() ?? 5.0;
    _diffReverse = map['diffReverse'] ?? false;
    _diffWetDry = (map['diffWetDry'] as num?)?.toDouble() ?? 0.5;
    _diffLpCutoff = (map['diffLpCutoff'] as num?)?.toDouble() ?? 8000.0;
    _reverbEnabled = map['reverbEnabled'] ?? false;
    _reverbRoom = (map['reverbRoom'] as num?)?.toDouble() ?? 0.5;
    _reverbWidth = (map['reverbWidth'] as num?)?.toDouble() ?? 0.5;
    _reverbDamp = (map['reverbDamp'] as num?)?.toDouble() ?? 0.5;
    _reverbWet = (map['reverbWet'] as num?)?.toDouble() ?? 0.5;
    _reverbDry = (map['reverbDry'] as num?)?.toDouble() ?? 0.5;
    _dynamicSystemEnabled = map['dynamicSystemEnabled'] ?? false;
    _dynamicSystemStrength =
        (map['dynamicSystemStrength'] as num?)?.toDouble() ?? 0.5;
    _dynPreset = (map['dynPreset'] as num?)?.toInt() ?? 0;
    _dynXLow = (map['dynXLow'] as num?)?.toDouble() ?? 40.0;
    _dynXHigh = (map['dynXHigh'] as num?)?.toDouble() ?? 60.0;
    _dynYLow = (map['dynYLow'] as num?)?.toDouble() ?? 100.0;
    _dynYHigh = (map['dynYHigh'] as num?)?.toDouble() ?? 150.0;
    _dynSideGainLow = (map['dynSideGainLow'] as num?)?.toDouble() ?? 1.0;
    _dynSideGainHigh = (map['dynSideGainHigh'] as num?)?.toDouble() ?? 1.0;
    _multibandCompressorEnabled = map['multibandCompressorEnabled'] ?? false;
    _mbcCrossFreqs = (map['mbcCrossFreqs'] as List?)
            ?.map((e) => (e as num).toDouble())
            .toList() ??
        _mbcCrossFreqs;
    _mbcThresholds = (map['mbcThresholds'] as List?)
            ?.map((e) => (e as num).toDouble())
            .toList() ??
        _mbcThresholds;
    _mbcRatios = (map['mbcRatios'] as List?)
            ?.map((e) => (e as num).toDouble())
            .toList() ??
        _mbcRatios;
    _mbcAttacks = (map['mbcAttacks'] as List?)
            ?.map((e) => (e as num).toDouble())
            .toList() ??
        _mbcAttacks;
    _mbcReleases = (map['mbcReleases'] as List?)
            ?.map((e) => (e as num).toDouble())
            .toList() ??
        _mbcReleases;
    _mbcGains = (map['mbcGains'] as List?)
            ?.map((e) => (e as num).toDouble())
            .toList() ??
        _mbcGains;
    _fetCompressorEnabled = map['fetCompressorEnabled'] ?? false;
    _fetThreshold = (map['fetThreshold'] as num?)?.toDouble() ?? 0.0;
    _fetRatio = (map['fetRatio'] as num?)?.toDouble() ?? 1.0;
    _fetKnee = (map['fetKnee'] as num?)?.toDouble() ?? 0.0;
    _fetKneeAuto = map['fetKneeAuto'] ?? false;
    _fetGain = (map['fetGain'] as num?)?.toDouble() ?? 0.0;
    _fetGainAuto = map['fetGainAuto'] ?? false;
    _fetAttack = (map['fetAttack'] as num?)?.toDouble() ?? 20.0;
    _fetAttackAuto = map['fetAttackAuto'] ?? false;
    _fetRelease = (map['fetRelease'] as num?)?.toDouble() ?? 100.0;
    _fetReleaseAuto = map['fetReleaseAuto'] ?? false;
    _fetKneeMulti = (map['fetKneeMulti'] as num?)?.toDouble() ?? 0.0;
    _fetMaxAttack = (map['fetMaxAttack'] as num?)?.toDouble() ?? 20.0;
    _fetMaxRelease = (map['fetMaxRelease'] as num?)?.toDouble() ?? 100.0;
    _fetCrest = (map['fetCrest'] as num?)?.toDouble() ?? 0.0;
    _fetAdapt = (map['fetAdapt'] as num?)?.toDouble() ?? 0.0;
    _fetNoClip = map['fetNoClip'] ?? false;
    _bassEnabled = map['bassEnabled'] ?? false;
    _bassMode = (map['bassMode'] as num?)?.toInt() ?? 1;
    _bassFreq = (map['bassFreq'] as num?)?.toDouble() ?? 80.0;
    _bassGain = (map['bassGain'] as num?)?.toDouble() ?? 0.5;
    _bassAntiPop = map['bassAntiPop'] ?? false;
    _bassMonoEnabled = map['bassMonoEnabled'] ?? false;
    _bassMonoMode = (map['bassMonoMode'] as num?)?.toInt() ?? 1;
    _bassMonoFreq = (map['bassMonoFreq'] as num?)?.toDouble() ?? 80.0;
    _bassMonoGain = (map['bassMonoGain'] as num?)?.toDouble() ?? 0.5;
    _bassMonoAntiPop = map['bassMonoAntiPop'] ?? false;
    _psychoBassEnabled = map['psychoBassEnabled'] ?? false;
    _psychoCutoff = (map['psychoCutoff'] as num?)?.toDouble() ?? 80.0;
    _psychoIntensity = (map['psychoIntensity'] as num?)?.toDouble() ?? 50.0;
    _psychoHarmonicOrder = (map['psychoHarmonicOrder'] as num?)?.toInt() ?? 2;
    _psychoOriginalLevel =
        (map['psychoOriginalLevel'] as num?)?.toDouble() ?? 100.0;
    _clarityEnabled = map['clarityEnabled'] ?? false;
    _clarityMode = (map['clarityMode'] as num?)?.toInt() ?? 0;
    _clarityGain = (map['clarityGain'] as num?)?.toDouble() ?? 0.5;
    _spectrumEnabled = map['spectrumEnabled'] ?? false;
    _spectrumStrength = (map['spectrumStrength'] as num?)?.toDouble() ?? 50.0;
    _spectrumExciter = (map['spectrumExciter'] as num?)?.toDouble() ?? 0.5;
    _firEqEnabled = map['firEqEnabled'] ?? false;
    _dynamicEqEnabled = map['dynamicEqEnabled'] ?? false;
    _dynamicEqFreqs = (map['dynamicEqFreqs'] as List?)
            ?.map((e) => (e as num).toDouble())
            .toList() ??
        _dynamicEqFreqs;
    _dynamicEqGains = (map['dynamicEqGains'] as List?)
            ?.map((e) => (e as num).toDouble())
            .toList() ??
        _dynamicEqGains;
    _dynamicEqQs = (map['dynamicEqQs'] as List?)
            ?.map((e) => (e as num).toDouble())
            .toList() ??
        _dynamicEqQs;
    _dynamicEqThresholds = (map['dynamicEqThresholds'] as List?)
            ?.map((e) => (e as num).toDouble())
            .toList() ??
        _dynamicEqThresholds;
    _dynamicEqAttacks = (map['dynamicEqAttacks'] as List?)
            ?.map((e) => (e as num).toDouble())
            .toList() ??
        _dynamicEqAttacks;
    _dynamicEqReleases = (map['dynamicEqReleases'] as List?)
            ?.map((e) => (e as num).toDouble())
            .toList() ??
        _dynamicEqReleases;
    _dynamicEqFilterTypes = (map['dynamicEqFilterTypes'] as List?)
            ?.map((e) => (e as num).toInt())
            .toList() ??
        _dynamicEqFilterTypes;
    _iirEqEnabled = map['iirEqEnabled'] ?? false;
    _tubeEnabled = map['tubeEnabled'] ?? false;
    _analogXEnabled = map['analogXEnabled'] ?? false;
    _analogXMode = (map['analogXMode'] as num?)?.toInt() ?? 1;
    _speakerCorrectionEnabled = map['speakerCorrectionEnabled'] ?? false;
    _convolverEnabled = map['convolverEnabled'] ?? false;
    _convolverCrossChannel =
        (map['convolverCrossChannel'] as num?)?.toDouble() ?? 0.0;
    _convolverFolder = map['convolverFolder'];
    _selectedConvolverFile = map['selectedConvolverFile'];
    _ddcEnabled = map['ddcEnabled'] ?? false;
    _ddcFolder = map['ddcFolder'];
    _selectedDdcFile = map['selectedDdcFile'];

    if (_convolverFolder != null) _scanConvolverFolder();
    if (_ddcFolder != null) _scanDdcFolder();
  }

  void _updateEngine() {
    AppStateService.instance.saveViperFxState(_toMap());
    widget.player.setViperEnabled(_viperEnabled);
    if (!_viperEnabled) return;

    // Core
    widget.player.setViperMasterLimiter(
      threshold: _masterLimiterThreshold,
      outputVolume: _masterLimiterVolume,
      channelPan: _masterLimiterPan,
    );
    widget.player.setViperPlaybackGain(
      enable: _playbackGainEnabled,
      strength: _playbackGainStrength,
      maxGain: _playbackGainMax,
      outputThreshold: _playbackGainThreshold,
    );
    widget.player.setViperLufs(
      enable: _lufsEnabled,
      target: _lufsTarget,
      maxGainDb: _lufsMaxGainDb,
      speed: _lufsSpeed,
    );
    widget.player.setViperAdaptiveLoudness(
      enable: _alcEnabled,
      mode: _alcMode,
      strength: _alcStrength,
      attenuationDb: 0.0,
    );

    // Spatial
    widget.player.setViperStereoImager(
      enable: _stereoImagerEnabled,
      lowWidth: _stereoLowWidth,
      midWidth: _stereoMidWidth,
      highWidth: _stereoHighWidth,
      lowCrossoverHz: _stereoLowCrossover,
      highCrossoverHz: _stereoHighCrossover,
    );
    widget.player.setViperCure(
      enable: _cureEnabled,
      preset: _curePreset,
    );
    widget.player.setViperHeadphoneSurround(
      enable: _headphoneSurroundEnabled,
      quality: _headphoneSurroundQuality,
    );
    widget.player.setViperFieldSurround(
      enable: _fieldSurroundEnabled,
      widening: _fieldWidening,
      midImage: _fieldMidImage,
      depth: _fieldDepth,
    );
    widget.player.setViperDiffSurround(
      enable: _diffSurroundEnabled,
      delay: _diffDelay,
      reverse: _diffReverse,
      wetDryMix: _diffWetDry,
      lpCutoffHz: _diffLpCutoff,
    );
    widget.player.setViperReverb(
      enable: _reverbEnabled,
      roomSize: _reverbRoom,
      width: _reverbWidth,
      damp: _reverbDamp,
      wet: _reverbWet,
      dry: _reverbDry,
    );

    // Dynamics
    widget.player.setViperDynamicSystem(
      enable: _dynamicSystemEnabled,
      xCoeffLow: _dynXLow.toInt(),
      xCoeffHigh: _dynXHigh.toInt(),
      yCoeffLow: _dynYLow.toInt(),
      yCoeffHigh: _dynYHigh.toInt(),
      sideGainLow: _dynSideGainLow,
      sideGainHigh: _dynSideGainHigh,
      strength: _dynamicSystemStrength,
    );
    widget.player.setViperMultibandCompressor(
      enable: _multibandCompressorEnabled,
      crossoverFreqs: _mbcCrossFreqs,
      bands: List.generate(
          5,
          (i) => {
                'enable': true,
                'threshold': _mbcThresholds[i],
                'ratio': _mbcRatios[i],
                'attack': _mbcAttacks[i],
                'release': _mbcReleases[i],
                'gain': _mbcGains[i],
              }),
    );
    widget.player.setViperFetCompressor(
      enable: _fetCompressorEnabled,
      threshold: _fetThreshold,
      ratio: _fetRatio,
      knee: _fetKnee,
      kneeAuto: _fetKneeAuto,
      gain: _fetGain,
      gainAuto: _fetGainAuto,
      attack: _fetAttack,
      attackAuto: _fetAttackAuto,
      release: _fetRelease,
      releaseAuto: _fetReleaseAuto,
      kneeMulti: _fetKneeMulti,
      maxAttack: _fetMaxAttack,
      maxRelease: _fetMaxRelease,
      crest: _fetCrest,
      adapt: _fetAdapt,
      noClip: _fetNoClip,
    );

    // Bass & Clarity
    widget.player.setViperBass(
      enable: _bassEnabled,
      mode: _bassMode,
      frequencyHz: _bassFreq.round(),
      gain: _bassGain,
      antiPop: _bassAntiPop,
    );
    widget.player.setViperBassMono(
      enable: _bassMonoEnabled,
      mode: _bassMonoMode,
      frequencyHz: _bassMonoFreq.round(),
      gain: _bassMonoGain,
      antiPop: _bassMonoAntiPop,
    );
    widget.player.setViperPsychoacousticBass(
      enable: _psychoBassEnabled,
      cutoffHz: _psychoCutoff.round(),
      intensity: _psychoIntensity.round(),
      harmonicOrder: _psychoHarmonicOrder,
      originalLevel: _psychoOriginalLevel.round(),
    );
    widget.player.setViperClarity(
      enable: _clarityEnabled,
      mode: _clarityMode,
      gain: _clarityGain,
    );
    widget.player.setViperSpectrumExtension(
      enable: _spectrumEnabled,
      strength: _spectrumStrength.round(),
      exciter: _spectrumExciter,
    );

    // Equalization
    widget.player.setViperConvolver(
        enable: _convolverEnabled, crossChannel: _convolverCrossChannel);
    widget.player.setViperDynamicEq(
      enable: _dynamicEqEnabled,
      bands: List.generate(
          5,
          (i) => {
                'frequencyHz': _dynamicEqFreqs[i],
                'q': _dynamicEqQs[i],
                'gainDb': _dynamicEqGains[i],
                'thresholdDb': _dynamicEqThresholds[i],
                'attackMs': _dynamicEqAttacks[i],
                'releaseMs': _dynamicEqReleases[i],
                'filterType': _dynamicEqFilterTypes[i],
              }),
    );
    widget.player.setViperDdc(_ddcEnabled);
    if (_convolverEnabled && _selectedConvolverFile != null) {
      widget.player.loadViperConvolver(
          p.join(_convolverFolder!, _selectedConvolverFile!));
    } else if (!_convolverEnabled) {
      // Assuming a way to clear convolver or it stays loaded but inactive
    }
    if (_ddcEnabled && _selectedDdcFile != null) {
      widget.player.loadViperDdc(p.join(_ddcFolder!, _selectedDdcFile!));
    }

    // Analog
    widget.player.setViperTubeSimulator(_tubeEnabled);
    widget.player.setViperAnalogX(
      enable: _analogXEnabled,
      mode: _analogXMode,
    );
    widget.player.setViperSpeakerCorrection(_speakerCorrectionEnabled);
  }

  void _toggleMaster(bool val) {
    setState(() => _viperEnabled = val);
    _updateEngine();
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
      child: Row(
        children: [
          /*M3EContainer(
            Shapes.pill,
            width: 8,
            height: 8,
            color: primaryColor,
            child: */
          const SizedBox.shrink(),
          //),
          const SizedBox(width: 8),
          Text(
            title.toUpperCase(),
            style: TextStyle(
              color: primaryColor,
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEffectTileCard({
    required Shapes shape,
    required IconData icon,
    required String title,
    required String subtitle,
    required bool isEnabled,
    ValueChanged<bool>? onToggle,
    required VoidCallback onTapDetail,
  }) {
    return M3EListItem(
      headline: title,
      supportingText: subtitle,
      leading: /*M3EContainer(
        shape,
        width: 42,
        height: 42,
        color: isEnabled
            ? primaryColor.withValues(alpha: 0.18)
            : Colors.white.withValues(alpha: 0.05),
        border: BorderSide(
          color: isEnabled
              ? primaryColor.withValues(alpha: 0.45)
              : Colors.white.withValues(alpha: 0.08),
          width: 1,
        ),
        child: */
          Center(
        child: Icon(
          icon,
          color: isEnabled ? primaryColor : Colors.white54,
          size: 20,
        ),
        // ),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (onToggle != null) ...[
            M3ESwitch(
              selectedIcon: Icon(Icons.check, color: primaryColor),
              value: isEnabled,
              onChanged: onToggle,
            ),
            const SizedBox(width: 6),
          ],
          const Icon(
            Icons.chevron_right_rounded,
            color: Colors.white38,
            size: 22,
          ),
        ],
      ),
      onTap: onTapDetail,
    );
  }

  void _openDetailScreen(
      String title, Shapes shape, IconData icon, WidgetBuilder contentBuilder) {
    Navigator.push(
      context,
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 300),
        reverseTransitionDuration: const Duration(milliseconds: 240),
        pageBuilder: (context, animation, secondaryAnimation) {
          return StatefulBuilder(
            builder: (context, setSubState) {
              _subScreenSetState = setSubState;
              return Scaffold(
                backgroundColor: bgDarkColor,
                appBar: AppBar(
                  backgroundColor: surfaceDarkerColor,
                  elevation: 0,
                  leading: M3EIconButton(
                    icon: const Icon(Icons.keyboard_arrow_down,
                        color: Colors.white),
                    variant: M3EIconButtonVariant.standard,
                    onPressed: () {
                      _subScreenSetState = null;
                      Navigator.pop(context);
                    },
                  ),
                  title: Row(
                    children: [
                      /* M3EContainer(
                        shape,
                        width: 32,
                        height: 32,
                        color: primaryColor.withValues(alpha: 0.18),
                        border: BorderSide(
                          color: primaryColor.withValues(alpha: 0.4),
                          width: 1,
                        ),
                        child: */
                      Center(
                        child: Icon(icon, color: primaryColor, size: 16),
                      ),
                      //  ),
                      const SizedBox(width: 12),
                      Text(
                        title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                body: RepaintBoundary(
                  child: contentBuilder(context),
                ),
              );
            },
          );
        },
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          final curveAnimation = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic,
          );

          final slideAnimation = Tween<Offset>(
            begin: const Offset(0.05, 0.0),
            end: Offset.zero,
          ).animate(curveAnimation);

          final fadeAnimation = Tween<double>(
            begin: 0.0,
            end: 1.0,
          ).animate(curveAnimation);

          return SlideTransition(
            position: slideAnimation,
            child: FadeTransition(
              opacity: fadeAnimation,
              child: child,
            ),
          );
        },
      ),
    ).then((_) {
      _subScreenSetState = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1000.0),
        child: CustomScrollView(
          key: const PageStorageKey<String>('viper_screen_scroll'),
          slivers: [
            // Top Master Enable Switch
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: M3ECard(
                  variant: M3ECardVariant.filled,
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            /* M3EContainer(
                              Shapes.c4SidedCookie,
                              width: 44,
                              height: 44,
                              color: primaryColor.withValues(alpha: 0.18),
                              border: BorderSide(
                                color: primaryColor.withValues(alpha: 0.4),
                                width: 1.0,
                              ),
                              child:*/
                            Center(
                              child: Icon(Icons.graphic_eq_rounded,
                                  color: primaryColor, size: 22),
                            ),
                            //),
                            const SizedBox(width: 14),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'ViPER4Android DSP',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 16.5,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: -0.2,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  _viperEnabled
                                      ? 'DSP Pipeline Active'
                                      : 'Master Bypassed',
                                  style: TextStyle(
                                    color: _viperEnabled
                                        ? primaryColor.withValues(alpha: 0.9)
                                        : Colors.white38,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        M3ESwitch(
                          selectedIcon: Icon(Icons.check, color: primaryColor),
                          value: _viperEnabled,
                          onChanged: _toggleMaster,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            // Section 1: Core Output & Gain Controls
            SliverToBoxAdapter(
              child: _buildSectionHeader('Core Output & Gain'),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: M3ECardList(
                  itemCount: 1,
                  onTap: (index) {
                    _openDetailScreen(
                      'Core & Limits',
                      Shapes.gem,
                      Icons.tune,
                      (_) => _buildDeckViews()[0],
                    );
                  },
                  itemBuilder: (context, index) {
                    return _buildEffectTileCard(
                      shape: Shapes.gem,
                      icon: Icons.tune,
                      title: 'Core & Limits',
                      subtitle: _viperEnabled
                          ? 'Master Limiter, AGC & LUFS'
                          : 'Disabled',
                      isEnabled: _viperEnabled,
                      onToggle: _toggleMaster,
                      onTapDetail: () => _openDetailScreen(
                          'Core & Limits',
                          Shapes.gem,
                          Icons.tune,
                          (_) => _buildDeckViews()[0]),
                    );
                  },
                ),
              ),
            ),

            // Section 2: VIPRR System & Dynamics
            SliverToBoxAdapter(
              child: _buildSectionHeader('VIPRR System & Dynamics'),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: M3ECardList(
                  itemCount: 2,
                  onTap: (index) {
                    switch (index) {
                      case 0:
                        _openDetailScreen('VIPRR Dynamic System', Shapes.boom,
                            Icons.bolt, (_) => _buildDeckViews()[1]);
                        break;
                      case 1:
                        _openDetailScreen(
                            'Dynamics & Compressors',
                            Shapes.diamond,
                            Icons.compress,
                            (_) => _buildDeckViews()[2]);
                        break;
                    }
                  },
                  itemBuilder: (context, index) {
                    if (index == 0) {
                      return _buildEffectTileCard(
                        shape: Shapes.boom,
                        icon: Icons.bolt,
                        title: 'VIPRR Dynamic System',
                        subtitle: _dynamicSystemEnabled
                            ? 'Strength: ${(_dynamicSystemStrength * 100).toInt()}%'
                            : 'Disabled',
                        isEnabled: _dynamicSystemEnabled,
                        onToggle: (v) {
                          setState(() => _dynamicSystemEnabled = v);
                          _updateEngine();
                        },
                        onTapDetail: () => _openDetailScreen(
                            'VIPRR Dynamic System',
                            Shapes.boom,
                            Icons.bolt,
                            (_) => _buildDeckViews()[1]),
                      );
                    }
                    return _buildEffectTileCard(
                      shape: Shapes.diamond,
                      icon: Icons.compress,
                      title: 'Dynamics & Compressors',
                      subtitle: (_multibandCompressorEnabled ||
                              _fetCompressorEnabled)
                          ? '5-Band & FET Active'
                          : 'Disabled',
                      isEnabled: _multibandCompressorEnabled ||
                          _fetCompressorEnabled,
                      onTapDetail: () => _openDetailScreen(
                          'Dynamics & Compressors',
                          Shapes.diamond,
                          Icons.compress,
                          (_) => _buildDeckViews()[2]),
                    );
                  },
                ),
              ),
            ),

            // Section 3: Bass & Clarity Enhancement
            SliverToBoxAdapter(
              child: _buildSectionHeader('Bass & Clarity Enhancement'),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: M3ECardList(
                  itemCount: 1,
                  onTap: (index) {
                    _openDetailScreen('Bass & Clarity Engine', Shapes.burst,
                        Icons.equalizer, (_) => _buildDeckViews()[3]);
                  },
                  itemBuilder: (context, index) {
                    return _buildEffectTileCard(
                      shape: Shapes.burst,
                      icon: Icons.equalizer,
                      title: 'Bass & Clarity Engine',
                      subtitle: (_bassEnabled ||
                              _bassMonoEnabled ||
                              _psychoBassEnabled ||
                              _clarityEnabled ||
                              _spectrumEnabled)
                          ? 'Active'
                          : 'Disabled',
                      isEnabled: _bassEnabled ||
                          _bassMonoEnabled ||
                          _psychoBassEnabled ||
                          _clarityEnabled ||
                          _spectrumEnabled,
                      onTapDetail: () => _openDetailScreen(
                          'Bass & Clarity Engine',
                          Shapes.burst,
                          Icons.equalizer,
                          (_) => _buildDeckViews()[3]),
                    );
                  },
                ),
              ),
            ),

            // Section 4: Spatial & Surround Sound
            SliverToBoxAdapter(
              child: _buildSectionHeader('Spatial & Surround Sound'),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: M3ECardList(
                  itemCount: 2,
                  onTap: (index) {
                    switch (index) {
                      case 0:
                        _openDetailScreen(
                            'Spatial & Surround Engine',
                            Shapes.softBoom,
                            Icons.surround_sound,
                            (_) => _buildDeckViews()[4]);
                        break;
                      case 1:
                        _openDetailScreen('ViPER Reverb', Shapes.arch,
                            Icons.meeting_room, (_) => _buildDeckViews()[5]);
                        break;
                    }
                  },
                  itemBuilder: (context, index) {
                    if (index == 0) {
                      return _buildEffectTileCard(
                        shape: Shapes.softBoom,
                        icon: Icons.surround_sound,
                        title: 'Spatial & Surround Engine',
                        subtitle: (_stereoImagerEnabled ||
                                _cureEnabled ||
                                _headphoneSurroundEnabled ||
                                _fieldSurroundEnabled ||
                                _diffSurroundEnabled)
                            ? 'Active'
                            : 'Disabled',
                        isEnabled: _stereoImagerEnabled ||
                            _cureEnabled ||
                            _headphoneSurroundEnabled ||
                            _fieldSurroundEnabled ||
                            _diffSurroundEnabled,
                        onTapDetail: () => _openDetailScreen(
                            'Spatial & Surround Engine',
                            Shapes.softBoom,
                            Icons.surround_sound,
                            (_) => _buildDeckViews()[4]),
                      );
                    }
                    return _buildEffectTileCard(
                      shape: Shapes.arch,
                      icon: Icons.meeting_room,
                      title: 'ViPER Reverb',
                      subtitle: _reverbEnabled
                          ? 'Room: ${(_reverbRoom * 100).toInt()}%'
                          : 'Disabled',
                      isEnabled: _reverbEnabled,
                      onToggle: (v) {
                        setState(() => _reverbEnabled = v);
                        _updateEngine();
                      },
                      onTapDetail: () => _openDetailScreen(
                          'ViPER Reverb',
                          Shapes.arch,
                          Icons.meeting_room,
                          (_) => _buildDeckViews()[5]),
                    );
                  },
                ),
              ),
            ),

            // Section 5: Equalization, Impulse & Emulation
            SliverToBoxAdapter(
              child: _buildSectionHeader('EQ, Impulse & Emulation'),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: M3ECardList(
                  itemCount: 3,
                  onTap: (index) {
                    switch (index) {
                      case 0:
                        _openDetailScreen(
                            'Dynamic EQ & FIR Filter',
                            Shapes.slanted,
                            Icons.show_chart,
                            (_) => _buildDeckViews()[6]);
                        break;
                      case 1:
                        _openDetailScreen(
                            'Convolver & DDC Loader',
                            Shapes.l4LeafClover,
                            Icons.graphic_eq,
                            (_) => _buildDeckViews()[7]);
                        break;
                      case 2:
                        _openDetailScreen(
                            'AnalogX & Tube Simulator',
                            Shapes.circle,
                            Icons.album,
                            (_) => _buildDeckViews()[8]);
                        break;
                    }
                  },
                  itemBuilder: (context, index) {
                    if (index == 0) {
                      return _buildEffectTileCard(
                        shape: Shapes.slanted,
                        icon: Icons.show_chart,
                        title: 'Dynamic EQ & FIR Filter',
                        subtitle: (_firEqEnabled ||
                                _dynamicEqEnabled ||
                                _iirEqEnabled)
                            ? 'Active'
                            : 'Disabled',
                        isEnabled: _firEqEnabled ||
                            _dynamicEqEnabled ||
                            _iirEqEnabled,
                        onTapDetail: () => _openDetailScreen(
                            'Dynamic EQ & FIR Filter',
                            Shapes.slanted,
                            Icons.show_chart,
                            (_) => _buildDeckViews()[6]),
                      );
                    }
                    if (index == 1) {
                      return _buildEffectTileCard(
                        shape: Shapes.l4LeafClover,
                        icon: Icons.graphic_eq,
                        title: 'Convolver & DDC Loader',
                        subtitle: (_convolverEnabled || _ddcEnabled)
                            ? 'Impulse / DDC Active'
                            : 'Disabled',
                        isEnabled: _convolverEnabled || _ddcEnabled,
                        onTapDetail: () => _openDetailScreen(
                            'Convolver & DDC Loader',
                            Shapes.l4LeafClover,
                            Icons.graphic_eq,
                            (_) => _buildDeckViews()[7]),
                      );
                    }
                    return _buildEffectTileCard(
                      shape: Shapes.circle,
                      icon: Icons.album,
                      title: 'AnalogX & Tube Simulator',
                      subtitle: (_tubeEnabled ||
                              _analogXEnabled ||
                              _speakerCorrectionEnabled)
                          ? 'Tube/AnalogX Active'
                          : 'Disabled',
                      isEnabled: _tubeEnabled ||
                          _analogXEnabled ||
                          _speakerCorrectionEnabled,
                      onTapDetail: () => _openDetailScreen(
                          'AnalogX & Tube Simulator',
                          Shapes.circle,
                          Icons.album,
                          (_) => _buildDeckViews()[8]),
                    );
                  },
                ),
              ),
            ),

            // Bottom Spacing for floating player / nav
            const SliverToBoxAdapter(
              child: SizedBox(height: 120),
            ),
          ],
        ),
      ),
    );
  }

  M3EExpandableStyle get _deckExpandableStyle => M3EExpandableStyle(
        color: surfaceDarkColor,
        gap: 8,
        headerPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        bodyPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      );

  List<Widget> _buildDeckViews() => [
        // Deck 0: Core & Limits
        SingleChildScrollView(
          primary: false,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
          child: M3EExpandableList(
            allowMultipleExpanded: true,
            style: _deckExpandableStyle,
            initiallyExpanded: {
              if (_viperEnabled) 0,
              if (_playbackGainEnabled) 1,
              if (_lufsEnabled) 2,
              if (_alcEnabled) 3,
            },
            data: [
              M3EExpandableData(
                title: 'Master Limiter',
                subtitle: 'Peak threshold, volume & pan',
                leading: Icon(Icons.tune, color: primaryColor, size: 20),
                trailing: M3ESwitch(
                  selectedIcon: Icon(Icons.check, color: primaryColor),
                  value: _viperEnabled,
                  onChanged: _toggleMaster,
                ),
                body: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Wrap(
                    spacing: 16,
                    runSpacing: 16,
                    alignment: WrapAlignment.center,
                    children: [
                      SizedBox(
                          width: 75,
                          child: ModernAudioKnob(
                              label: 'THRESH',
                              value: _masterLimiterThreshold,
                              min: 0.0,
                              max: 1.0,
                              activeColor: primaryColor,
                              valueFormatter: (v) => '${(v * 100).round()}%',
                              onChanged: _viperEnabled
                                  ? (v) {
                                      setState(
                                          () => _masterLimiterThreshold = v);
                                      _updateEngine();
                                    }
                                  : (_) {})),
                      SizedBox(
                          width: 75,
                          child: ModernAudioKnob(
                              label: 'VOLUME',
                              value: _masterLimiterVolume,
                              min: 0.0,
                              max: 2.0,
                              activeColor: primaryColor,
                              valueFormatter: (v) => '${v.toStringAsFixed(1)}x',
                              onChanged: _viperEnabled
                                  ? (v) {
                                      setState(() => _masterLimiterVolume = v);
                                      _updateEngine();
                                    }
                                  : (_) {})),
                      SizedBox(
                          width: 75,
                          child: ModernAudioKnob(
                              label: 'PAN',
                              value: _masterLimiterPan,
                              min: -1.0,
                              max: 1.0,
                              activeColor: primaryColor,
                              valueFormatter: (v) => v.toStringAsFixed(2),
                              onChanged: _viperEnabled
                                  ? (v) {
                                      setState(() => _masterLimiterPan = v);
                                      _updateEngine();
                                    }
                                  : (_) {})),
                    ],
                  ),
                ),
              ),
              M3EExpandableData(
                title: 'Playback Gain',
                subtitle: 'AGC volume normalisation',
                leading: Icon(Icons.volume_up, color: primaryColor, size: 20),
                trailing: M3ESwitch(
                  selectedIcon: Icon(Icons.check, color: primaryColor),
                  value: _playbackGainEnabled,
                  onChanged: _viperEnabled
                      ? (v) {
                          setState(() => _playbackGainEnabled = v);
                          _updateEngine();
                        }
                      : null,
                ),
                body: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Wrap(
                    spacing: 16,
                    runSpacing: 16,
                    alignment: WrapAlignment.center,
                    children: [
                      SizedBox(
                          width: 75,
                          child: ModernAudioKnob(
                              label: 'STRENGTH',
                              value: _playbackGainStrength,
                              min: 0.0,
                              max: 1.0,
                              activeColor: primaryColor,
                              valueFormatter: (v) => '${(v * 100).round()}%',
                              onChanged: _viperEnabled && _playbackGainEnabled
                                  ? (v) {
                                      setState(() => _playbackGainStrength = v);
                                      _updateEngine();
                                    }
                                  : (_) {})),
                      SizedBox(
                          width: 75,
                          child: ModernAudioKnob(
                              label: 'MAX GAIN',
                              value: _playbackGainMax,
                              min: 0.0,
                              max: 2.0,
                              activeColor: primaryColor,
                              valueFormatter: (v) => '${(v * 100).round()}%',
                              onChanged: _viperEnabled && _playbackGainEnabled
                                  ? (v) {
                                      setState(() => _playbackGainMax = v);
                                      _updateEngine();
                                    }
                                  : (_) {})),
                      SizedBox(
                          width: 75,
                          child: ModernAudioKnob(
                              label: 'THRESH',
                              value: _playbackGainThreshold,
                              min: 0.0,
                              max: 1.0,
                              activeColor: primaryColor,
                              valueFormatter: (v) => '${(v * 100).round()}%',
                              onChanged: _viperEnabled && _playbackGainEnabled
                                  ? (v) {
                                      setState(
                                          () => _playbackGainThreshold = v);
                                      _updateEngine();
                                    }
                                  : (_) {})),
                    ],
                  ),
                ),
              ),
              M3EExpandableData(
                title: 'LUFS Normalizer',
                subtitle: 'EBU R128 loudness target',
                leading: Icon(Icons.speed, color: primaryColor, size: 20),
                trailing: M3ESwitch(
                  selectedIcon: Icon(Icons.check, color: primaryColor),
                  value: _lufsEnabled,
                  onChanged: _viperEnabled
                      ? (v) {
                          setState(() => _lufsEnabled = v);
                          _updateEngine();
                        }
                      : null,
                ),
                body: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    children: [
                      Wrap(
                        spacing: 16,
                        runSpacing: 16,
                        alignment: WrapAlignment.center,
                        children: [
                          SizedBox(
                              width: 75,
                              child: ModernAudioKnob(
                                  label: 'TARGET',
                                  value: _lufsTarget,
                                  min: -24.0,
                                  max: -6.0,
                                  activeColor: primaryColor,
                                  valueFormatter: (v) =>
                                      '${v.toStringAsFixed(1)}dB',
                                  onChanged: _viperEnabled && _lufsEnabled
                                      ? (v) {
                                          setState(() => _lufsTarget = v);
                                          _updateEngine();
                                        }
                                      : (_) {})),
                          SizedBox(
                              width: 75,
                              child: ModernAudioKnob(
                                  label: 'MAX GAIN',
                                  value: _lufsMaxGainDb,
                                  min: 0.0,
                                  max: 20.0,
                                  activeColor: primaryColor,
                                  valueFormatter: (v) =>
                                      '${v.toStringAsFixed(1)}dB',
                                  onChanged: _viperEnabled && _lufsEnabled
                                      ? (v) {
                                          setState(() => _lufsMaxGainDb = v);
                                          _updateEngine();
                                        }
                                      : (_) {})),
                        ],
                      ),
                      const SizedBox(height: 16),
                      const Text('Speed',
                          style:
                              TextStyle(color: Colors.white70, fontSize: 11)),
                      const SizedBox(height: 4),
                      M3ESegmentedButton<int>(
                        segments: const [
                          M3ESegment(value: 0, label: 'Slow'),
                          M3ESegment(value: 1, label: 'Normal'),
                          M3ESegment(value: 2, label: 'Fast'),
                        ],
                        selected: {_lufsSpeed},
                        onSelectionChanged: (Set<int> newSelection) {
                          if (_viperEnabled &&
                              _lufsEnabled &&
                              newSelection.isNotEmpty) {
                            setState(() => _lufsSpeed = newSelection.first);
                            _updateEngine();
                          }
                        },
                      ),
                    ],
                  ),
                ),
              ),
              M3EExpandableData(
                title: 'ALC Dynamics',
                subtitle: 'Automatic Limiter Control',
                leading: Icon(Icons.graphic_eq, color: primaryColor, size: 20),
                trailing: M3ESwitch(
                  selectedIcon: Icon(Icons.check, color: primaryColor),
                  value: _alcEnabled,
                  onChanged: _viperEnabled
                      ? (v) {
                          setState(() => _alcEnabled = v);
                          _updateEngine();
                        }
                      : null,
                ),
                body: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    children: [
                      Wrap(
                        spacing: 16,
                        runSpacing: 16,
                        alignment: WrapAlignment.center,
                        children: [
                          SizedBox(
                              width: 75,
                              child: ModernAudioKnob(
                                  label: 'STRENGTH',
                                  value: _alcStrength,
                                  min: 0.0,
                                  max: 1.0,
                                  activeColor: primaryColor,
                                  valueFormatter: (v) =>
                                      '${(v * 100).round()}%',
                                  onChanged: _viperEnabled && _alcEnabled
                                      ? (v) {
                                          setState(() => _alcStrength = v);
                                          _updateEngine();
                                        }
                                      : (_) {})),
                        ],
                      ),
                      const SizedBox(height: 16),
                      const Text('Mode',
                          style:
                              TextStyle(color: Colors.white70, fontSize: 11)),
                      const SizedBox(height: 4),
                      M3ESegmentedButton<int>(
                        segments: const [
                          M3ESegment(value: 0, label: 'Natural'),
                          M3ESegment(value: 1, label: 'Mild'),
                          M3ESegment(value: 2, label: 'Punchy'),
                        ],
                        selected: {_alcMode},
                        onSelectionChanged: (Set<int> newSelection) {
                          if (_viperEnabled &&
                              _alcEnabled &&
                              newSelection.isNotEmpty) {
                            setState(() => _alcMode = newSelection.first);
                            _updateEngine();
                          }
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),

        // Deck 1: VIPRR Dynamic System
        SingleChildScrollView(
          primary: false,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
          child: M3EExpandableList(
            allowMultipleExpanded: true,
            style: _deckExpandableStyle,
            initiallyExpanded: {
              if (_dynamicSystemEnabled) 0,
            },
            data: [
              M3EExpandableData(
                title: 'VIPRR Dynamic System',
                subtitle: 'Psychoacoustic bass enhancer',
                leading: Icon(Icons.bolt, color: primaryColor, size: 20),
                trailing: M3ESwitch(
                  selectedIcon: Icon(Icons.check, color: primaryColor),
                  value: _dynamicSystemEnabled,
                  onChanged: _viperEnabled
                      ? (v) {
                          setState(() => _dynamicSystemEnabled = v);
                          _updateEngine();
                        }
                      : null,
                ),
                body: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    children: [
                      const Text('Preset',
                          style:
                              TextStyle(color: Colors.white70, fontSize: 11)),
                      const SizedBox(height: 6),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 4, vertical: 2),
                        child: M3EDropdownMenu<int>(
                          key: ValueKey('dyn_preset_$_dynPreset'),
                          singleSelect: true,
                          enabled: _viperEnabled && _dynamicSystemEnabled,
                          fieldStyle: M3EDropdownFieldStyle(
                            hintText: 'Select dynamic system preset',
                            backgroundColor: surfaceDarkColor,
                            foregroundColor: Colors.white,
                            selectedTextStyle: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 10),
                          ),
                          dropdownStyle: M3EDropdownPanelStyle(
                            backgroundColor: surfaceDarkColor,
                            elevation: 4,
                          ),
                          itemStyle: M3EDropdownItemStyle(
                            textColor: Colors.white,
                            selectedTextColor: primaryColor,
                            selectedBackgroundColor:
                                primaryColor.withValues(alpha: 0.15),
                          ),
                          items: [
                            M3EDropdownItem(
                                label: 'Custom',
                                value: 0,
                                selected: _dynPreset == 0),
                            M3EDropdownItem(
                                label: 'Unknown Type I',
                                value: 1,
                                selected: _dynPreset == 1),
                            M3EDropdownItem(
                                label: 'Unknown Type II',
                                value: 2,
                                selected: _dynPreset == 2),
                            M3EDropdownItem(
                                label: 'Unknown Type III',
                                value: 3,
                                selected: _dynPreset == 3),
                            M3EDropdownItem(
                                label: 'Unknown Type IV',
                                value: 4,
                                selected: _dynPreset == 4),
                            M3EDropdownItem(
                                label: 'Earbud',
                                value: 5,
                                selected: _dynPreset == 5),
                            M3EDropdownItem(
                                label: 'In-Ear',
                                value: 6,
                                selected: _dynPreset == 6),
                            M3EDropdownItem(
                                label: 'Over-Ear',
                                value: 7,
                                selected: _dynPreset == 7),
                            M3EDropdownItem(
                                label: 'Extreme Headphone',
                                value: 8,
                                selected: _dynPreset == 8),
                          ],
                          onSelectionChanged: (selectedList) {
                            if (selectedList.isNotEmpty &&
                                _viperEnabled &&
                                _dynamicSystemEnabled) {
                              final newValue = selectedList.first.value;
                              if (newValue != null && newValue != _dynPreset) {
                                WidgetsBinding.instance
                                    .addPostFrameCallback((_) {
                                  if (mounted) {
                                    setState(() {
                                      _dynPreset = newValue;
                                      switch (newValue) {
                                        case 1:
                                          _dynXLow = 30;
                                          _dynXHigh = 50;
                                          _dynYLow = 80;
                                          _dynYHigh = 120;
                                          _dynSideGainLow = 1.2;
                                          _dynSideGainHigh = 1.0;
                                          break;
                                        case 2:
                                          _dynXLow = 40;
                                          _dynXHigh = 60;
                                          _dynYLow = 100;
                                          _dynYHigh = 150;
                                          _dynSideGainLow = 1.3;
                                          _dynSideGainHigh = 1.1;
                                          break;
                                        case 3:
                                          _dynXLow = 50;
                                          _dynXHigh = 70;
                                          _dynYLow = 120;
                                          _dynYHigh = 170;
                                          _dynSideGainLow = 1.4;
                                          _dynSideGainHigh = 1.2;
                                          break;
                                        case 4:
                                          _dynXLow = 60;
                                          _dynXHigh = 80;
                                          _dynYLow = 140;
                                          _dynYHigh = 190;
                                          _dynSideGainLow = 1.5;
                                          _dynSideGainHigh = 1.3;
                                          break;
                                        case 5:
                                          _dynXLow = 60;
                                          _dynXHigh = 100;
                                          _dynYLow = 150;
                                          _dynYHigh = 200;
                                          _dynSideGainLow = 1.8;
                                          _dynSideGainHigh = 1.5;
                                          break;
                                        case 6:
                                          _dynXLow = 40;
                                          _dynXHigh = 70;
                                          _dynYLow = 100;
                                          _dynYHigh = 150;
                                          _dynSideGainLow = 1.5;
                                          _dynSideGainHigh = 1.2;
                                          break;
                                        case 7:
                                          _dynXLow = 30;
                                          _dynXHigh = 50;
                                          _dynYLow = 80;
                                          _dynYHigh = 120;
                                          _dynSideGainLow = 1.2;
                                          _dynSideGainHigh = 1.0;
                                          break;
                                        case 8:
                                          _dynXLow = 20;
                                          _dynXHigh = 40;
                                          _dynYLow = 60;
                                          _dynYHigh = 100;
                                          _dynSideGainLow = 2.0;
                                          _dynSideGainHigh = 1.5;
                                          break;
                                      }
                                    });
                                    _updateEngine();
                                  }
                                });
                              }
                            }
                          },
                        ),
                      ),
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 16,
                        runSpacing: 16,
                        alignment: WrapAlignment.center,
                        children: [
                          SizedBox(
                              width: 75,
                              child: ModernAudioKnob(
                                  label: 'STRENGTH',
                                  value: _dynamicSystemStrength,
                                  min: 0.0,
                                  max: 1.0,
                                  activeColor: primaryColor,
                                  isPercentage: true,
                                  onChanged: _viperEnabled &&
                                          _dynamicSystemEnabled
                                      ? (v) {
                                          setState(
                                              () => _dynamicSystemStrength = v);
                                          _updateEngine();
                                        }
                                      : (_) {})),
                          if (_dynPreset == 0) ...[
                            SizedBox(
                                width: 75,
                                child: ModernAudioKnob(
                                    label: 'X LOW',
                                    value: _dynXLow,
                                    min: 20.0,
                                    max: 200.0,
                                    activeColor: primaryColor,
                                    valueFormatter: (v) => '${v.round()}Hz',
                                    onChanged:
                                        _viperEnabled && _dynamicSystemEnabled
                                            ? (v) {
                                                setState(() => _dynXLow = v);
                                                _updateEngine();
                                              }
                                            : (_) {})),
                            SizedBox(
                                width: 75,
                                child: ModernAudioKnob(
                                    label: 'X HIGH',
                                    value: _dynXHigh,
                                    min: 20.0,
                                    max: 200.0,
                                    activeColor: primaryColor,
                                    valueFormatter: (v) => '${v.round()}Hz',
                                    onChanged:
                                        _viperEnabled && _dynamicSystemEnabled
                                            ? (v) {
                                                setState(() => _dynXHigh = v);
                                                _updateEngine();
                                              }
                                            : (_) {})),
                            SizedBox(
                                width: 75,
                                child: ModernAudioKnob(
                                    label: 'Y LOW',
                                    value: _dynYLow,
                                    min: 50.0,
                                    max: 500.0,
                                    activeColor: primaryColor,
                                    valueFormatter: (v) => '${v.round()}Hz',
                                    onChanged:
                                        _viperEnabled && _dynamicSystemEnabled
                                            ? (v) {
                                                setState(() => _dynYLow = v);
                                                _updateEngine();
                                              }
                                            : (_) {})),
                            SizedBox(
                                width: 75,
                                child: ModernAudioKnob(
                                    label: 'Y HIGH',
                                    value: _dynYHigh,
                                    min: 50.0,
                                    max: 500.0,
                                    activeColor: primaryColor,
                                    valueFormatter: (v) => '${v.round()}Hz',
                                    onChanged:
                                        _viperEnabled && _dynamicSystemEnabled
                                            ? (v) {
                                                setState(() => _dynYHigh = v);
                                                _updateEngine();
                                              }
                                            : (_) {})),
                            SizedBox(
                                width: 75,
                                child: ModernAudioKnob(
                                    label: 'SIDE LOW',
                                    value: _dynSideGainLow,
                                    min: 0.0,
                                    max: 5.0,
                                    activeColor: primaryColor,
                                    valueFormatter: (v) =>
                                        '${v.toStringAsFixed(1)}x',
                                    onChanged: _viperEnabled &&
                                            _dynamicSystemEnabled
                                        ? (v) {
                                            setState(() => _dynSideGainLow = v);
                                            _updateEngine();
                                          }
                                        : (_) {})),
                            SizedBox(
                                width: 75,
                                child: ModernAudioKnob(
                                    label: 'SIDE HIGH',
                                    value: _dynSideGainHigh,
                                    min: 0.0,
                                    max: 5.0,
                                    activeColor: primaryColor,
                                    valueFormatter: (v) =>
                                        '${v.toStringAsFixed(1)}x',
                                    onChanged:
                                        _viperEnabled && _dynamicSystemEnabled
                                            ? (v) {
                                                setState(
                                                    () => _dynSideGainHigh = v);
                                                _updateEngine();
                                              }
                                            : (_) {})),
                          ]
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),

        // Deck 2: Dynamics & Compression
        SingleChildScrollView(
          primary: false,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
          child: M3EExpandableList(
            allowMultipleExpanded: true,
            style: _deckExpandableStyle,
            initiallyExpanded: {
              if (_multibandCompressorEnabled) 0,
              if (_fetCompressorEnabled) 1,
            },
            data: [
              M3EExpandableData(
                title: 'Multiband Compressor',
                subtitle: '5-band dynamics',
                leading: Icon(Icons.tune, color: primaryColor, size: 20),
                trailing: M3ESwitch(
                  selectedIcon: Icon(Icons.check, color: primaryColor),
                  value: _multibandCompressorEnabled,
                  onChanged: _viperEnabled
                      ? (v) {
                          setState(() => _multibandCompressorEnabled = v);
                          _updateEngine();
                        }
                      : null,
                ),
                body: Column(
                  children: [
                    _buildMbcCrossovers(),
                    const SizedBox(height: 12),
                    _buildCompressorBands(),
                  ],
                ),
              ),
              M3EExpandableData(
                title: 'FET Compressor',
                subtitle: 'Vintage dynamics processing',
                leading: Icon(Icons.compress, color: primaryColor, size: 20),
                trailing: M3ESwitch(
                  selectedIcon: Icon(Icons.check, color: primaryColor),
                  value: _fetCompressorEnabled,
                  onChanged: _viperEnabled
                      ? (v) {
                          setState(() => _fetCompressorEnabled = v);
                          _updateEngine();
                        }
                      : null,
                ),
                body: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    children: [
                      Wrap(
                        spacing: 16,
                        runSpacing: 16,
                        alignment: WrapAlignment.center,
                        children: [
                          SizedBox(
                              width: 75,
                              child: ModernAudioKnob(
                                  label: 'THRESH',
                                  value: _fetThreshold,
                                  min: -60.0,
                                  max: 0.0,
                                  activeColor: primaryColor,
                                  valueFormatter: (v) =>
                                      '${v.toStringAsFixed(1)}dB',
                                  onChanged:
                                      _viperEnabled && _fetCompressorEnabled
                                          ? (v) {
                                              setState(() => _fetThreshold = v);
                                              _updateEngine();
                                            }
                                          : (_) {})),
                          SizedBox(
                              width: 75,
                              child: ModernAudioKnob(
                                  label: 'RATIO',
                                  value: _fetRatio,
                                  min: 1.0,
                                  max: 20.0,
                                  activeColor: primaryColor,
                                  valueFormatter: (v) =>
                                      '${v.toStringAsFixed(1)}:1',
                                  onChanged:
                                      _viperEnabled && _fetCompressorEnabled
                                          ? (v) {
                                              setState(() => _fetRatio = v);
                                              _updateEngine();
                                            }
                                          : (_) {})),
                          SizedBox(
                              width: 75,
                              child: ModernAudioKnob(
                                  label: 'KNEE',
                                  value: _fetKnee,
                                  min: 0.0,
                                  max: 60.0,
                                  activeColor: primaryColor,
                                  valueFormatter: (v) => '${v.round()}',
                                  onChanged: _viperEnabled &&
                                          _fetCompressorEnabled &&
                                          !_fetKneeAuto
                                      ? (v) {
                                          setState(() => _fetKnee = v);
                                          _updateEngine();
                                        }
                                      : (_) {})),
                          SizedBox(
                              width: 75,
                              child: ModernAudioKnob(
                                  label: 'GAIN',
                                  value: _fetGain,
                                  min: -60.0,
                                  max: 60.0,
                                  activeColor: primaryColor,
                                  valueFormatter: (v) =>
                                      '${v.toStringAsFixed(1)}dB',
                                  onChanged: _viperEnabled &&
                                          _fetCompressorEnabled &&
                                          !_fetGainAuto
                                      ? (v) {
                                          setState(() => _fetGain = v);
                                          _updateEngine();
                                        }
                                      : (_) {})),
                          SizedBox(
                              width: 75,
                              child: ModernAudioKnob(
                                  label: 'ATTACK',
                                  value: _fetAttack,
                                  min: 0.0,
                                  max: 100.0,
                                  activeColor: primaryColor,
                                  valueFormatter: (v) => '${v.round()}ms',
                                  onChanged: _viperEnabled &&
                                          _fetCompressorEnabled &&
                                          !_fetAttackAuto
                                      ? (v) {
                                          setState(() => _fetAttack = v);
                                          _updateEngine();
                                        }
                                      : (_) {})),
                          SizedBox(
                              width: 75,
                              child: ModernAudioKnob(
                                  label: 'RELEASE',
                                  value: _fetRelease,
                                  min: 10.0,
                                  max: 1000.0,
                                  activeColor: primaryColor,
                                  valueFormatter: (v) => '${v.round()}ms',
                                  onChanged: _viperEnabled &&
                                          _fetCompressorEnabled &&
                                          !_fetReleaseAuto
                                      ? (v) {
                                          setState(() => _fetRelease = v);
                                          _updateEngine();
                                        }
                                      : (_) {})),
                          SizedBox(
                              width: 75,
                              child: ModernAudioKnob(
                                  label: 'KNEE MULT',
                                  value: _fetKneeMulti,
                                  min: 0.0,
                                  max: 1.0,
                                  activeColor: primaryColor,
                                  valueFormatter: (v) =>
                                      '${(v * 100).round()}%',
                                  onChanged:
                                      _viperEnabled && _fetCompressorEnabled
                                          ? (v) {
                                              setState(() => _fetKneeMulti = v);
                                              _updateEngine();
                                            }
                                          : (_) {})),
                          SizedBox(
                              width: 75,
                              child: ModernAudioKnob(
                                  label: 'MAX ATK',
                                  value: _fetMaxAttack,
                                  min: 0.0,
                                  max: 100.0,
                                  activeColor: primaryColor,
                                  valueFormatter: (v) => '${v.round()}ms',
                                  onChanged:
                                      _viperEnabled && _fetCompressorEnabled
                                          ? (v) {
                                              setState(() => _fetMaxAttack = v);
                                              _updateEngine();
                                            }
                                          : (_) {})),
                          SizedBox(
                              width: 75,
                              child: ModernAudioKnob(
                                  label: 'MAX REL',
                                  value: _fetMaxRelease,
                                  min: 10.0,
                                  max: 1000.0,
                                  activeColor: primaryColor,
                                  valueFormatter: (v) => '${v.round()}ms',
                                  onChanged: _viperEnabled &&
                                          _fetCompressorEnabled
                                      ? (v) {
                                          setState(() => _fetMaxRelease = v);
                                          _updateEngine();
                                        }
                                      : (_) {})),
                          SizedBox(
                              width: 75,
                              child: ModernAudioKnob(
                                  label: 'CREST',
                                  value: _fetCrest,
                                  min: 0.0,
                                  max: 1.0,
                                  activeColor: primaryColor,
                                  valueFormatter: (v) =>
                                      '${(v * 100).round()}%',
                                  onChanged:
                                      _viperEnabled && _fetCompressorEnabled
                                          ? (v) {
                                              setState(() => _fetCrest = v);
                                              _updateEngine();
                                            }
                                          : (_) {})),
                          SizedBox(
                              width: 75,
                              child: ModernAudioKnob(
                                  label: 'ADAPT',
                                  value: _fetAdapt,
                                  min: 0.0,
                                  max: 1.0,
                                  activeColor: primaryColor,
                                  valueFormatter: (v) =>
                                      '${(v * 100).round()}%',
                                  onChanged:
                                      _viperEnabled && _fetCompressorEnabled
                                          ? (v) {
                                              setState(() => _fetAdapt = v);
                                              _updateEngine();
                                            }
                                          : (_) {})),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 8,
                        runSpacing: 0,
                        alignment: WrapAlignment.center,
                        children: [
                          SizedBox(
                              width: 150,
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text('Auto Knee',
                                      style: TextStyle(
                                          color: Colors.white70, fontSize: 11)),
                                  M3ESwitch(
                                    selectedIcon:
                                        Icon(Icons.check, color: primaryColor),
                                    value: _fetKneeAuto,
                                    onChanged: _viperEnabled &&
                                            _fetCompressorEnabled
                                        ? (v) {
                                            setState(() => _fetKneeAuto = v);
                                            _updateEngine();
                                          }
                                        : null,
                                  ),
                                ],
                              )),
                          SizedBox(
                              width: 150,
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text('Auto Gain',
                                      style: TextStyle(
                                          color: Colors.white70, fontSize: 11)),
                                  M3ESwitch(
                                    selectedIcon:
                                        Icon(Icons.check, color: primaryColor),
                                    value: _fetGainAuto,
                                    onChanged: _viperEnabled &&
                                            _fetCompressorEnabled
                                        ? (v) {
                                            setState(() => _fetGainAuto = v);
                                            _updateEngine();
                                          }
                                        : null,
                                  ),
                                ],
                              )),
                          SizedBox(
                              width: 150,
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text('Auto Attack',
                                      style: TextStyle(
                                          color: Colors.white70, fontSize: 11)),
                                  M3ESwitch(
                                    value: _fetAttackAuto,
                                    onChanged: _viperEnabled &&
                                            _fetCompressorEnabled
                                        ? (v) {
                                            setState(() => _fetAttackAuto = v);
                                            _updateEngine();
                                          }
                                        : null,
                                  ),
                                ],
                              )),
                          SizedBox(
                              width: 150,
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text('Auto Release',
                                      style: TextStyle(
                                          color: Colors.white70, fontSize: 11)),
                                  M3ESwitch(
                                    selectedIcon:
                                        Icon(Icons.check, color: primaryColor),
                                    value: _fetReleaseAuto,
                                    onChanged: _viperEnabled &&
                                            _fetCompressorEnabled
                                        ? (v) {
                                            setState(() => _fetReleaseAuto = v);
                                            _updateEngine();
                                          }
                                        : null,
                                  ),
                                ],
                              )),
                          SizedBox(
                              width: 150,
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text('No Clip',
                                      style: TextStyle(
                                          color: Colors.white70, fontSize: 11)),
                                  M3ESwitch(
                                    selectedIcon:
                                        Icon(Icons.check, color: primaryColor),
                                    value: _fetNoClip,
                                    onChanged:
                                        _viperEnabled && _fetCompressorEnabled
                                            ? (v) {
                                                setState(() => _fetNoClip = v);
                                                _updateEngine();
                                              }
                                            : null,
                                  ),
                                ],
                              )),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),

        // Deck 3: Bass & Clarity
        SingleChildScrollView(
          primary: false,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
          child: M3EExpandableList(
            allowMultipleExpanded: true,
            style: _deckExpandableStyle,
            initiallyExpanded: {
              if (_bassEnabled) 0,
              if (_bassMonoEnabled) 1,
              if (_psychoBassEnabled) 2,
              if (_clarityEnabled) 3,
              if (_spectrumEnabled) 4,
            },
            data: [
              M3EExpandableData(
                title: 'ViPER Bass',
                subtitle: 'Stereo bass boost',
                leading: Icon(Icons.speaker, color: primaryColor, size: 20),
                trailing: M3ESwitch(
                  selectedIcon: Icon(Icons.check, color: primaryColor),
                  value: _bassEnabled,
                  onChanged: _viperEnabled
                      ? (v) {
                          setState(() => _bassEnabled = v);
                          _updateEngine();
                        }
                      : null,
                ),
                body: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    children: [
                      const Text('Mode',
                          style:
                              TextStyle(color: Colors.white70, fontSize: 11)),
                      const SizedBox(height: 4),
                      M3ESegmentedButton<int>(
                        segments: const [
                          M3ESegment(value: 0, label: 'Natural'),
                          M3ESegment(value: 1, label: 'Pure'),
                          M3ESegment(value: 2, label: 'Subwoofer'),
                        ],
                        selected: {_bassMode},
                        onSelectionChanged: (Set<int> newSelection) {
                          if (_viperEnabled &&
                              _bassEnabled &&
                              newSelection.isNotEmpty) {
                            setState(() => _bassMode = newSelection.first);
                            _updateEngine();
                          }
                        },
                      ),
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 16,
                        runSpacing: 16,
                        alignment: WrapAlignment.center,
                        children: [
                          SizedBox(
                              width: 75,
                              child: ModernAudioKnob(
                                  label: 'FREQ',
                                  value: _bassFreq,
                                  min: 20.0,
                                  max: 120.0,
                                  activeColor: primaryColor,
                                  valueFormatter: (v) => '${v.round()}Hz',
                                  onChanged: _viperEnabled && _bassEnabled
                                      ? (v) {
                                          setState(() => _bassFreq = v);
                                          _updateEngine();
                                        }
                                      : (_) {})),
                          SizedBox(
                              width: 75,
                              child: ModernAudioKnob(
                                  label: 'GAIN',
                                  value: _bassGain,
                                  min: 0.0,
                                  max: 1.0,
                                  activeColor: primaryColor,
                                  isPercentage: true,
                                  onChanged: _viperEnabled && _bassEnabled
                                      ? (v) {
                                          setState(() => _bassGain = v);
                                          _updateEngine();
                                        }
                                      : (_) {})),
                        ],
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Anti-Pop',
                              style: TextStyle(
                                  color: Colors.white70, fontSize: 11)),
                          M3ESwitch(
                            selectedIcon:
                                Icon(Icons.check, color: primaryColor),
                            value: _bassAntiPop,
                            onChanged: _viperEnabled && _bassEnabled
                                ? (v) {
                                    setState(() => _bassAntiPop = v);
                                    _updateEngine();
                                  }
                                : null,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              M3EExpandableData(
                title: 'ViPER Bass Mono',
                subtitle: 'Sub-bass reinforcement',
                leading:
                    Icon(Icons.speaker_group, color: primaryColor, size: 20),
                trailing: M3ESwitch(
                  selectedIcon: Icon(Icons.check, color: primaryColor),
                  value: _bassMonoEnabled,
                  onChanged: _viperEnabled
                      ? (v) {
                          setState(() => _bassMonoEnabled = v);
                          _updateEngine();
                        }
                      : null,
                ),
                body: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    children: [
                      const Text('Mode',
                          style:
                              TextStyle(color: Colors.white70, fontSize: 11)),
                      const SizedBox(height: 4),
                      M3ESegmentedButton<int>(
                        segments: const [
                          M3ESegment(value: 0, label: 'Natural'),
                          M3ESegment(value: 1, label: 'Pure'),
                          M3ESegment(value: 2, label: 'Subwoofer'),
                        ],
                        selected: {_bassMonoMode},
                        onSelectionChanged: (Set<int> newSelection) {
                          if (_viperEnabled &&
                              _bassMonoEnabled &&
                              newSelection.isNotEmpty) {
                            setState(() => _bassMonoMode = newSelection.first);
                            _updateEngine();
                          }
                        },
                      ),
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 16,
                        runSpacing: 16,
                        alignment: WrapAlignment.center,
                        children: [
                          SizedBox(
                              width: 75,
                              child: ModernAudioKnob(
                                  label: 'FREQ',
                                  value: _bassMonoFreq,
                                  min: 20.0,
                                  max: 120.0,
                                  activeColor: primaryColor,
                                  valueFormatter: (v) => '${v.round()}Hz',
                                  onChanged: _viperEnabled && _bassMonoEnabled
                                      ? (v) {
                                          setState(() => _bassMonoFreq = v);
                                          _updateEngine();
                                        }
                                      : (_) {})),
                          SizedBox(
                              width: 75,
                              child: ModernAudioKnob(
                                  label: 'GAIN',
                                  value: _bassMonoGain,
                                  min: 0.0,
                                  max: 1.0,
                                  activeColor: primaryColor,
                                  isPercentage: true,
                                  onChanged: _viperEnabled && _bassMonoEnabled
                                      ? (v) {
                                          setState(() => _bassMonoGain = v);
                                          _updateEngine();
                                        }
                                      : (_) {})),
                        ],
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Anti-Pop',
                              style: TextStyle(
                                  color: Colors.white70, fontSize: 11)),
                          M3ESwitch(
                            selectedIcon:
                                Icon(Icons.check, color: primaryColor),
                            value: _bassMonoAntiPop,
                            onChanged: _viperEnabled && _bassMonoEnabled
                                ? (v) {
                                    setState(() => _bassMonoAntiPop = v);
                                    _updateEngine();
                                  }
                                : null,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              M3EExpandableData(
                title: 'Psychoacoustic Bass',
                subtitle: 'Harmonic synthesis',
                leading: Icon(Icons.waves, color: primaryColor, size: 20),
                trailing: M3ESwitch(
                  selectedIcon: Icon(Icons.check, color: primaryColor),
                  value: _psychoBassEnabled,
                  onChanged: _viperEnabled
                      ? (v) {
                          setState(() => _psychoBassEnabled = v);
                          _updateEngine();
                        }
                      : null,
                ),
                body: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    children: [
                      const Text('Harmonic Order',
                          style:
                              TextStyle(color: Colors.white70, fontSize: 11)),
                      const SizedBox(height: 4),
                      M3ESegmentedButton<int>(
                        segments: const [
                          M3ESegment(value: 2, label: '2nd'),
                          M3ESegment(value: 3, label: '3rd'),
                          M3ESegment(value: 4, label: '4th'),
                          M3ESegment(value: 5, label: '5th'),
                        ],
                        selected: {_psychoHarmonicOrder},
                        onSelectionChanged: (Set<int> newSelection) {
                          if (_viperEnabled &&
                              _psychoBassEnabled &&
                              newSelection.isNotEmpty) {
                            setState(() =>
                                _psychoHarmonicOrder = newSelection.first);
                            _updateEngine();
                          }
                        },
                      ),
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 16,
                        runSpacing: 16,
                        alignment: WrapAlignment.center,
                        children: [
                          SizedBox(
                              width: 75,
                              child: ModernAudioKnob(
                                  label: 'CUTOFF',
                                  value: _psychoCutoff,
                                  min: 30.0,
                                  max: 150.0,
                                  activeColor: primaryColor,
                                  valueFormatter: (v) => '${v.round()}Hz',
                                  onChanged: _viperEnabled && _psychoBassEnabled
                                      ? (v) {
                                          setState(() => _psychoCutoff = v);
                                          _updateEngine();
                                        }
                                      : (_) {})),
                          SizedBox(
                              width: 75,
                              child: ModernAudioKnob(
                                  label: 'INTENS',
                                  value: _psychoIntensity,
                                  min: 0.0,
                                  max: 100.0,
                                  activeColor: primaryColor,
                                  valueFormatter: (v) => '${v.round()}%',
                                  onChanged: _viperEnabled && _psychoBassEnabled
                                      ? (v) {
                                          setState(() => _psychoIntensity = v);
                                          _updateEngine();
                                        }
                                      : (_) {})),
                          SizedBox(
                              width: 75,
                              child: ModernAudioKnob(
                                  label: 'ORIG BASS',
                                  value: _psychoOriginalLevel,
                                  min: 0.0,
                                  max: 100.0,
                                  activeColor: primaryColor,
                                  valueFormatter: (v) => '${v.round()}%',
                                  onChanged: _viperEnabled && _psychoBassEnabled
                                      ? (v) {
                                          setState(
                                              () => _psychoOriginalLevel = v);
                                          _updateEngine();
                                        }
                                      : (_) {})),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              M3EExpandableData(
                title: 'ViPER Clarity',
                subtitle: 'Vocal and treble extraction',
                leading:
                    Icon(Icons.auto_awesome, color: primaryColor, size: 20),
                trailing: M3ESwitch(
                  selectedIcon: Icon(Icons.check, color: primaryColor),
                  value: _clarityEnabled,
                  onChanged: _viperEnabled
                      ? (v) {
                          setState(() => _clarityEnabled = v);
                          _updateEngine();
                        }
                      : null,
                ),
                body: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    children: [
                      const Text('Mode',
                          style:
                              TextStyle(color: Colors.white70, fontSize: 11)),
                      const SizedBox(height: 4),
                      M3ESegmentedButton<int>(
                        segments: const [
                          M3ESegment(value: 0, label: 'Natural'),
                          M3ESegment(value: 1, label: 'Ozone+'),
                          M3ESegment(value: 2, label: 'XHiFi'),
                        ],
                        selected: {_clarityMode},
                        onSelectionChanged: (Set<int> newSelection) {
                          if (_viperEnabled &&
                              _clarityEnabled &&
                              newSelection.isNotEmpty) {
                            setState(() => _clarityMode = newSelection.first);
                            _updateEngine();
                          }
                        },
                      ),
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 16,
                        runSpacing: 16,
                        alignment: WrapAlignment.center,
                        children: [
                          SizedBox(
                              width: 75,
                              child: ModernAudioKnob(
                                  label: 'GAIN',
                                  value: _clarityGain,
                                  min: 0.0,
                                  max: 1.0,
                                  activeColor: primaryColor,
                                  isPercentage: true,
                                  onChanged: _viperEnabled && _clarityEnabled
                                      ? (v) {
                                          setState(() => _clarityGain = v);
                                          _updateEngine();
                                        }
                                      : (_) {})),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              M3EExpandableData(
                title: 'Spectrum Extension',
                subtitle: 'High-frequency air',
                leading: Icon(Icons.blur_on, color: primaryColor, size: 20),
                trailing: M3ESwitch(
                  selectedIcon: Icon(Icons.check, color: primaryColor),
                  value: _spectrumEnabled,
                  onChanged: _viperEnabled
                      ? (v) {
                          setState(() => _spectrumEnabled = v);
                          _updateEngine();
                        }
                      : null,
                ),
                body: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Wrap(
                    spacing: 16,
                    runSpacing: 16,
                    alignment: WrapAlignment.center,
                    children: [
                      SizedBox(
                          width: 75,
                          child: ModernAudioKnob(
                              label: 'STRENGTH',
                              value: _spectrumStrength,
                              min: 0.0,
                              max: 100.0,
                              activeColor: primaryColor,
                              valueFormatter: (v) => '${v.round()}%',
                              onChanged: _viperEnabled && _spectrumEnabled
                                  ? (v) {
                                      setState(() => _spectrumStrength = v);
                                      _updateEngine();
                                    }
                                  : (_) {})),
                      SizedBox(
                          width: 75,
                          child: ModernAudioKnob(
                              label: 'EXCITER',
                              value: _spectrumExciter,
                              min: 0.0,
                              max: 1.0,
                              activeColor: primaryColor,
                              valueFormatter: (v) => '${(v * 100).round()}%',
                              onChanged: _viperEnabled && _spectrumEnabled
                                  ? (v) {
                                      setState(() => _spectrumExciter = v);
                                      _updateEngine();
                                    }
                                  : (_) {})),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),

        // Deck 4: Spatial & Surround
        SingleChildScrollView(
          primary: false,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
          child: M3EExpandableList(
            allowMultipleExpanded: true,
            style: _deckExpandableStyle,
            initiallyExpanded: {
              if (_stereoImagerEnabled) 0,
              if (_cureEnabled) 1,
              if (_headphoneSurroundEnabled) 2,
              if (_fieldSurroundEnabled) 3,
              if (_diffSurroundEnabled) 4,
            },
            data: [
              M3EExpandableData(
                title: 'Stereo Imager',
                subtitle: 'Multiband width & crossover control',
                leading:
                    Icon(Icons.surround_sound, color: primaryColor, size: 20),
                trailing: M3ESwitch(
                  selectedIcon: Icon(Icons.check, color: primaryColor),
                  value: _stereoImagerEnabled,
                  onChanged: _viperEnabled
                      ? (v) {
                          setState(() => _stereoImagerEnabled = v);
                          _updateEngine();
                        }
                      : null,
                ),
                body: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Wrap(
                    spacing: 16,
                    runSpacing: 16,
                    alignment: WrapAlignment.center,
                    children: [
                      SizedBox(
                          width: 75,
                          child: ModernAudioKnob(
                              label: 'LOW',
                              value: _stereoLowWidth,
                              min: 0.0,
                              max: 200.0,
                              activeColor: primaryColor,
                              valueFormatter: (v) => '${v.round()}%',
                              onChanged: _viperEnabled && _stereoImagerEnabled
                                  ? (v) {
                                      setState(() => _stereoLowWidth = v);
                                      _updateEngine();
                                    }
                                  : (_) {})),
                      SizedBox(
                          width: 75,
                          child: ModernAudioKnob(
                              label: 'MID',
                              value: _stereoMidWidth,
                              min: 0.0,
                              max: 200.0,
                              activeColor: primaryColor,
                              valueFormatter: (v) => '${v.round()}%',
                              onChanged: _viperEnabled && _stereoImagerEnabled
                                  ? (v) {
                                      setState(() => _stereoMidWidth = v);
                                      _updateEngine();
                                    }
                                  : (_) {})),
                      SizedBox(
                          width: 75,
                          child: ModernAudioKnob(
                              label: 'HIGH',
                              value: _stereoHighWidth,
                              min: 0.0,
                              max: 200.0,
                              activeColor: primaryColor,
                              valueFormatter: (v) => '${v.round()}%',
                              onChanged: _viperEnabled && _stereoImagerEnabled
                                  ? (v) {
                                      setState(() => _stereoHighWidth = v);
                                      _updateEngine();
                                    }
                                  : (_) {})),
                      SizedBox(
                          width: 75,
                          child: ModernAudioKnob(
                              label: 'LOW X-OVER',
                              value: _stereoLowCrossover,
                              min: 50.0,
                              max: 1000.0,
                              activeColor: primaryColor,
                              valueFormatter: (v) => '${v.round()}Hz',
                              onChanged: _viperEnabled && _stereoImagerEnabled
                                  ? (v) {
                                      setState(() => _stereoLowCrossover = v);
                                      _updateEngine();
                                    }
                                  : (_) {})),
                      SizedBox(
                          width: 75,
                          child: ModernAudioKnob(
                              label: 'HIGH X-OVER',
                              value: _stereoHighCrossover,
                              min: 1000.0,
                              max: 10000.0,
                              activeColor: primaryColor,
                              valueFormatter: (v) =>
                                  '${(v / 1000).toStringAsFixed(1)}kHz',
                              onChanged: _viperEnabled && _stereoImagerEnabled
                                  ? (v) {
                                      setState(() => _stereoHighCrossover = v);
                                      _updateEngine();
                                    }
                                  : (_) {})),
                    ],
                  ),
                ),
              ),
              M3EExpandableData(
                title: 'Auditory System Protection',
                subtitle: 'Cure Tech+ binaural crossfeed',
                leading: Icon(Icons.hearing, color: primaryColor, size: 20),
                trailing: M3ESwitch(
                  selectedIcon: Icon(Icons.check, color: primaryColor),
                  value: _cureEnabled,
                  onChanged: _viperEnabled
                      ? (v) {
                          setState(() => _cureEnabled = v);
                          _updateEngine();
                        }
                      : null,
                ),
                body: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    children: [
                      const Text('Binaural Level',
                          style:
                              TextStyle(color: Colors.white70, fontSize: 11)),
                      const SizedBox(height: 4),
                      M3ESegmentedButton<int>(
                        segments: const [
                          M3ESegment(value: 0, label: 'Off'),
                          M3ESegment(value: 1, label: 'Slight'),
                          M3ESegment(value: 2, label: 'Extreme'),
                        ],
                        selected: {_curePreset},
                        onSelectionChanged: (Set<int> newSelection) {
                          if (_viperEnabled &&
                              _cureEnabled &&
                              newSelection.isNotEmpty) {
                            setState(() => _curePreset = newSelection.first);
                            _updateEngine();
                          }
                        },
                      ),
                    ],
                  ),
                ),
              ),
              M3EExpandableData(
                title: 'Headphone Surround+',
                subtitle: 'Eliminates in-head fatigue',
                leading: Icon(Icons.headphones, color: primaryColor, size: 20),
                trailing: M3ESwitch(
                  selectedIcon: Icon(Icons.check, color: primaryColor),
                  value: _headphoneSurroundEnabled,
                  onChanged: _viperEnabled
                      ? (v) {
                          setState(() => _headphoneSurroundEnabled = v);
                          _updateEngine();
                        }
                      : null,
                ),
                body: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    children: [
                      const Text('Quality',
                          style:
                              TextStyle(color: Colors.white70, fontSize: 11)),
                      const SizedBox(height: 4),
                      M3ESegmentedButton<int>(
                        segments: const [
                          M3ESegment(value: 0, label: 'Low'),
                          M3ESegment(value: 1, label: 'Mid'),
                          M3ESegment(value: 2, label: 'High'),
                        ],
                        selected: {_headphoneSurroundQuality},
                        onSelectionChanged: (Set<int> newSelection) {
                          if (_viperEnabled &&
                              _headphoneSurroundEnabled &&
                              newSelection.isNotEmpty) {
                            setState(() =>
                                _headphoneSurroundQuality = newSelection.first);
                            _updateEngine();
                          }
                        },
                      ),
                    ],
                  ),
                ),
              ),
              M3EExpandableData(
                title: 'Field Surround',
                subtitle: 'ColorfulMusic field expansion',
                leading:
                    Icon(Icons.spatial_audio, color: primaryColor, size: 20),
                trailing: M3ESwitch(
                  selectedIcon: Icon(Icons.check, color: primaryColor),
                  value: _fieldSurroundEnabled,
                  onChanged: _viperEnabled
                      ? (v) {
                          setState(() => _fieldSurroundEnabled = v);
                          _updateEngine();
                        }
                      : null,
                ),
                body: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    children: [
                      const Text('Surround Depth Level',
                          style:
                              TextStyle(color: Colors.white70, fontSize: 11)),
                      const SizedBox(height: 4),
                      M3ESegmentedButton<int>(
                        segments: const [
                          M3ESegment(value: 0, label: 'Lvl 1'),
                          M3ESegment(value: 1, label: 'Lvl 2'),
                          M3ESegment(value: 2, label: 'Lvl 3'),
                          M3ESegment(value: 3, label: 'Lvl 4'),
                          M3ESegment(value: 4, label: 'Lvl 5'),
                        ],
                        selected: {_fieldDepth},
                        onSelectionChanged: (Set<int> newSelection) {
                          if (_viperEnabled &&
                              _fieldSurroundEnabled &&
                              newSelection.isNotEmpty) {
                            setState(() => _fieldDepth = newSelection.first);
                            _updateEngine();
                          }
                        },
                      ),
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 16,
                        runSpacing: 16,
                        alignment: WrapAlignment.center,
                        children: [
                          SizedBox(
                              width: 75,
                              child: ModernAudioKnob(
                                  label: 'WIDENING',
                                  value: _fieldWidening,
                                  min: 0.0,
                                  max: 1.0,
                                  activeColor: primaryColor,
                                  valueFormatter: (v) =>
                                      '${(v * 100).round()}%',
                                  onChanged: _viperEnabled &&
                                          _fieldSurroundEnabled
                                      ? (v) {
                                          setState(() => _fieldWidening = v);
                                          _updateEngine();
                                        }
                                      : (_) {})),
                          SizedBox(
                              width: 75,
                              child: ModernAudioKnob(
                                  label: 'MID IMG',
                                  value: _fieldMidImage,
                                  min: 0.0,
                                  max: 1.0,
                                  activeColor: primaryColor,
                                  valueFormatter: (v) =>
                                      '${(v * 100).round()}%',
                                  onChanged: _viperEnabled &&
                                          _fieldSurroundEnabled
                                      ? (v) {
                                          setState(() => _fieldMidImage = v);
                                          _updateEngine();
                                        }
                                      : (_) {})),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              M3EExpandableData(
                title: 'Differential Surround',
                subtitle: 'Haas effect delay panning',
                leading:
                    Icon(Icons.compare_arrows, color: primaryColor, size: 20),
                trailing: M3ESwitch(
                  selectedIcon: Icon(Icons.check, color: primaryColor),
                  value: _diffSurroundEnabled,
                  onChanged: _viperEnabled
                      ? (v) {
                          setState(() => _diffSurroundEnabled = v);
                          _updateEngine();
                        }
                      : null,
                ),
                body: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Wrap(
                        spacing: 16,
                        runSpacing: 16,
                        alignment: WrapAlignment.center,
                        children: [
                          SizedBox(
                              width: 75,
                              child: ModernAudioKnob(
                                  label: 'DELAY',
                                  value: _diffDelay,
                                  min: 0.0,
                                  max: 50.0,
                                  activeColor: primaryColor,
                                  valueFormatter: (v) =>
                                      '${v.toStringAsFixed(1)}ms',
                                  onChanged:
                                      _viperEnabled && _diffSurroundEnabled
                                          ? (v) {
                                              setState(() => _diffDelay = v);
                                              _updateEngine();
                                            }
                                          : (_) {})),
                          SizedBox(
                              width: 75,
                              child: ModernAudioKnob(
                                  label: 'WET/DRY',
                                  value: _diffWetDry,
                                  min: 0.0,
                                  max: 1.0,
                                  activeColor: primaryColor,
                                  valueFormatter: (v) =>
                                      '${(v * 100).round()}%',
                                  onChanged:
                                      _viperEnabled && _diffSurroundEnabled
                                          ? (v) {
                                              setState(() => _diffWetDry = v);
                                              _updateEngine();
                                            }
                                          : (_) {})),
                          SizedBox(
                              width: 75,
                              child: ModernAudioKnob(
                                  label: 'CUTOFF',
                                  value: _diffLpCutoff,
                                  min: 20.0,
                                  max: 20000.0,
                                  activeColor: primaryColor,
                                  valueFormatter: (v) => '${v.round()}Hz',
                                  onChanged:
                                      _viperEnabled && _diffSurroundEnabled
                                          ? (v) {
                                              setState(() => _diffLpCutoff = v);
                                              _updateEngine();
                                            }
                                          : (_) {})),
                        ],
                      ),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Reverse',
                            style:
                                TextStyle(color: Colors.white70, fontSize: 11)),
                        M3ESwitch(
                          selectedIcon: Icon(Icons.check, color: primaryColor),
                          value: _diffReverse,
                          onChanged: _viperEnabled && _diffSurroundEnabled
                              ? (v) {
                                  setState(() => _diffReverse = v);
                                  _updateEngine();
                                }
                              : null,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        // Deck 5: ViPER Reverb
        SingleChildScrollView(
          primary: false,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
          child: M3EExpandableList(
            allowMultipleExpanded: true,
            style: _deckExpandableStyle,
            initiallyExpanded: {
              if (_reverbEnabled) 0,
            },
            data: [
              M3EExpandableData(
                title: 'Reverberation',
                subtitle: 'Room simulation',
                leading:
                    Icon(Icons.meeting_room, color: primaryColor, size: 20),
                trailing: M3ESwitch(
                  selectedIcon: Icon(Icons.check, color: primaryColor),
                  value: _reverbEnabled,
                  onChanged: _viperEnabled
                      ? (v) {
                          setState(() => _reverbEnabled = v);
                          _updateEngine();
                        }
                      : null,
                ),
                body: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Wrap(
                    spacing: 16,
                    runSpacing: 16,
                    alignment: WrapAlignment.center,
                    children: [
                      SizedBox(
                          width: 75,
                          child: ModernAudioKnob(
                              label: 'ROOM',
                              value: _reverbRoom,
                              min: 0.0,
                              max: 1.0,
                              activeColor: primaryColor,
                              valueFormatter: (v) => '${(v * 100).round()}%',
                              onChanged: _viperEnabled && _reverbEnabled
                                  ? (v) {
                                      setState(() => _reverbRoom = v);
                                      _updateEngine();
                                    }
                                  : (_) {})),
                      SizedBox(
                          width: 75,
                          child: ModernAudioKnob(
                              label: 'WIDTH',
                              value: _reverbWidth,
                              min: 0.0,
                              max: 1.0,
                              activeColor: primaryColor,
                              valueFormatter: (v) => '${(v * 100).round()}%',
                              onChanged: _viperEnabled && _reverbEnabled
                                  ? (v) {
                                      setState(() => _reverbWidth = v);
                                      _updateEngine();
                                    }
                                  : (_) {})),
                      SizedBox(
                          width: 75,
                          child: ModernAudioKnob(
                              label: 'DAMP',
                              value: _reverbDamp,
                              min: 0.0,
                              max: 1.0,
                              activeColor: primaryColor,
                              valueFormatter: (v) => '${(v * 100).round()}%',
                              onChanged: _viperEnabled && _reverbEnabled
                                  ? (v) {
                                      setState(() => _reverbDamp = v);
                                      _updateEngine();
                                    }
                                  : (_) {})),
                      SizedBox(
                          width: 75,
                          child: ModernAudioKnob(
                              label: 'WET',
                              value: _reverbWet,
                              min: 0.0,
                              max: 1.0,
                              activeColor: primaryColor,
                              valueFormatter: (v) => '${(v * 100).round()}%',
                              onChanged: _viperEnabled && _reverbEnabled
                                  ? (v) {
                                      setState(() => _reverbWet = v);
                                      _updateEngine();
                                    }
                                  : (_) {})),
                      SizedBox(
                          width: 75,
                          child: ModernAudioKnob(
                              label: 'DRY',
                              value: _reverbDry,
                              min: 0.0,
                              max: 1.0,
                              activeColor: primaryColor,
                              valueFormatter: (v) => '${(v * 100).round()}%',
                              onChanged: _viperEnabled && _reverbEnabled
                                  ? (v) {
                                      setState(() => _reverbDry = v);
                                      _updateEngine();
                                    }
                                  : (_) {})),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),

        // Deck 6: Dynamic EQ & FIR
        SingleChildScrollView(
          primary: false,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
          child: M3EExpandableList(
            allowMultipleExpanded: true,
            style: _deckExpandableStyle,
            initiallyExpanded: {
              if (_firEqEnabled) 0,
              if (_dynamicEqEnabled) 1,
              if (_iirEqEnabled) 2,
            },
            data: [
              M3EExpandableData(
                title: 'FIR Equalizer',
                subtitle: 'FIR bands processing',
                leading: Icon(Icons.graphic_eq, color: primaryColor, size: 20),
                trailing: M3ESwitch(
                  selectedIcon: Icon(Icons.check, color: primaryColor),
                  value: _firEqEnabled,
                  onChanged: _viperEnabled
                      ? (v) {
                          setState(() => _firEqEnabled = v);
                          _updateEngine();
                        }
                      : null,
                ),
                body: _buildEqBands(_firEqFreqs, _firEqGains, _firEqEnabled),
              ),
              M3EExpandableData(
                title: 'Dynamic EQ',
                subtitle: 'Adaptive frequency scaling',
                leading: Icon(Icons.equalizer, color: primaryColor, size: 20),
                trailing: M3ESwitch(
                  selectedIcon: Icon(Icons.check, color: primaryColor),
                  value: _dynamicEqEnabled,
                  onChanged: _viperEnabled
                      ? (v) {
                          setState(() => _dynamicEqEnabled = v);
                          _updateEngine();
                        }
                      : null,
                ),
                body: _buildDynamicEqBands(),
              ),
              M3EExpandableData(
                title: 'IIR Order EQ',
                subtitle: 'IIR bands processing',
                leading: Icon(Icons.tune, color: primaryColor, size: 20),
                trailing: M3ESwitch(
                  selectedIcon: Icon(Icons.check, color: primaryColor),
                  value: _iirEqEnabled,
                  onChanged: _viperEnabled
                      ? (v) {
                          setState(() => _iirEqEnabled = v);
                          _updateEngine();
                        }
                      : null,
                ),
                body: _buildEqBands(_iirEqFreqs, _iirEqGains, _iirEqEnabled),
              ),
            ],
          ),
        ),

        // Deck 7: Convolver & DDC
        SingleChildScrollView(
          primary: false,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildAutoEqImporter(),
              const SizedBox(height: 12),
              M3EExpandableList(
                allowMultipleExpanded: true,
                style: _deckExpandableStyle,
                initiallyExpanded: {
                  if (_convolverEnabled) 0,
                  if (_ddcEnabled) 1,
                },
                data: [
                  M3EExpandableData(
                    title: 'Convolver',
                    subtitle: 'IRS Convolver processing',
                    leading:
                        Icon(Icons.audiotrack, color: primaryColor, size: 20),
                    trailing: M3ESwitch(
                      selectedIcon: Icon(Icons.check, color: primaryColor),
                      value: _convolverEnabled,
                      onChanged: _viperEnabled
                          ? (v) {
                              setState(() => _convolverEnabled = v);
                              _updateEngine();
                            }
                          : null,
                    ),
                    body: _buildConvolverSelector(),
                  ),
                  M3EExpandableData(
                    title: 'Viper DDC',
                    subtitle: 'Device-Dependent Correction',
                    leading: Icon(Icons.headset, color: primaryColor, size: 20),
                    trailing: M3ESwitch(
                      selectedIcon: Icon(Icons.check, color: primaryColor),
                      value: _ddcEnabled,
                      onChanged: _viperEnabled
                          ? (v) {
                              setState(() => _ddcEnabled = v);
                              _updateEngine();
                            }
                          : null,
                    ),
                    body: _buildDdcSelector(),
                  ),
                ],
              ),
            ],
          ),
        ),

        // Deck 8: Analog & Tube
        SingleChildScrollView(
          primary: false,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
          child: M3EExpandableList(
            allowMultipleExpanded: true,
            style: _deckExpandableStyle,
            initiallyExpanded: {
              if (_tubeEnabled) 0,
              if (_analogXEnabled) 1,
              if (_speakerCorrectionEnabled) 2,
            },
            data: [
              M3EExpandableData(
                title: 'Tube Simulator',
                subtitle: '6N1J analog warmth',
                leading: Icon(Icons.radio, color: primaryColor, size: 20),
                trailing: M3ESwitch(
                  selectedIcon: Icon(Icons.check, color: primaryColor),
                  value: _tubeEnabled,
                  onChanged: _viperEnabled
                      ? (v) {
                          setState(() => _tubeEnabled = v);
                          _updateEngine();
                        }
                      : null,
                ),
                body: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    'Emulates a 6N1J dual-triode vacuum tube for harmonic richness and warmth.',
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ),
              ),
              M3EExpandableData(
                title: 'AnalogX',
                subtitle: 'Analog sound signature',
                leading: Icon(Icons.album, color: primaryColor, size: 20),
                trailing: M3ESwitch(
                  selectedIcon: Icon(Icons.check, color: primaryColor),
                  value: _analogXEnabled,
                  onChanged: _viperEnabled
                      ? (v) {
                          setState(() => _analogXEnabled = v);
                          _updateEngine();
                        }
                      : null,
                ),
                body: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    children: [
                      const Text('Mode',
                          style:
                              TextStyle(color: Colors.white70, fontSize: 11)),
                      const SizedBox(height: 4),
                      M3ESegmentedButton<int>(
                        segments: const [
                          M3ESegment(value: 0, label: 'Mild'),
                          M3ESegment(value: 1, label: 'Moderate'),
                          M3ESegment(value: 2, label: 'Aggressive'),
                        ],
                        selected: {_analogXMode},
                        onSelectionChanged: (Set<int> newSelection) {
                          if (_viperEnabled &&
                              _analogXEnabled &&
                              newSelection.isNotEmpty) {
                            setState(() => _analogXMode = newSelection.first);
                            _updateEngine();
                          }
                        },
                      ),
                    ],
                  ),
                ),
              ),
              M3EExpandableData(
                title: 'Speaker Correction',
                subtitle: 'Impulse response correction',
                leading: Icon(Icons.speaker, color: primaryColor, size: 20),
                trailing: M3ESwitch(
                  selectedIcon: Icon(Icons.check, color: primaryColor),
                  value: _speakerCorrectionEnabled,
                  onChanged: _viperEnabled
                      ? (v) {
                          setState(() => _speakerCorrectionEnabled = v);
                          _updateEngine();
                        }
                      : null,
                ),
                body: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    'Calibrates speaker non-linear frequency response curve.',
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ),
              ),
            ],
          ),
        ),
      ];

  Widget _buildMbcCrossovers() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(left: 16, top: 8, bottom: 4),
          child: Text('Crossover Frequencies',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold)),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Wrap(
            spacing: 16,
            runSpacing: 16,
            children: [
              SizedBox(
                width: 75,
                child: ModernAudioKnob(
                    label: 'SUB-LOW',
                    value: _mbcCrossFreqs[0],
                    min: 20.0,
                    max: 300.0,
                    activeColor: primaryColor,
                    valueFormatter: (v) => '${v.round()}Hz',
                    onChanged: _viperEnabled
                        ? (v) {
                            setState(() => _mbcCrossFreqs[0] = v);
                            _updateEngine();
                          }
                        : (_) {}),
              ),
              SizedBox(
                width: 75,
                child: ModernAudioKnob(
                    label: 'LOW-MID',
                    value: _mbcCrossFreqs[1],
                    min: 300.0,
                    max: 2000.0,
                    activeColor: primaryColor,
                    valueFormatter: (v) => '${v.round()}Hz',
                    onChanged: _viperEnabled
                        ? (v) {
                            setState(() => _mbcCrossFreqs[1] = v);
                            _updateEngine();
                          }
                        : (_) {}),
              ),
              SizedBox(
                width: 75,
                child: ModernAudioKnob(
                    label: 'MID-HI',
                    value: _mbcCrossFreqs[2],
                    min: 2000.0,
                    max: 8000.0,
                    activeColor: primaryColor,
                    valueFormatter: (v) => '${v.round()}Hz',
                    onChanged: _viperEnabled
                        ? (v) {
                            setState(() => _mbcCrossFreqs[2] = v);
                            _updateEngine();
                          }
                        : (_) {}),
              ),
              SizedBox(
                width: 75,
                child: ModernAudioKnob(
                    label: 'HI-AIR',
                    value: _mbcCrossFreqs[3],
                    min: 8000.0,
                    max: 20000.0,
                    activeColor: primaryColor,
                    valueFormatter: (v) => '${v.round()}Hz',
                    onChanged: _viperEnabled
                        ? (v) {
                            setState(() => _mbcCrossFreqs[3] = v);
                            _updateEngine();
                          }
                        : (_) {}),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCompressorBands() {
    final labels = ['Sub', 'Low', 'Mid', 'High', 'Air'];
    return SizedBox(
      height: 380,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: 5,
        itemBuilder: (context, i) {
          return Container(
            width: 180,
            margin: const EdgeInsets.symmetric(horizontal: 4.0),
            padding: const EdgeInsets.symmetric(vertical: 8.0),
            decoration: BoxDecoration(
              color: Colors.black12,
              borderRadius: BorderRadius.circular(12),
            ),
            child: SingleChildScrollView(
              child: Column(
                children: [
                  Text(labels[i],
                      style: TextStyle(
                          color: primaryColor,
                          fontSize: 13,
                          fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 16,
                    alignment: WrapAlignment.center,
                    children: [
                      SizedBox(
                          width: 75,
                          child: ModernAudioKnob(
                              label: 'THRESH',
                              value: _mbcThresholds[i],
                              min: -60.0,
                              max: 0.0,
                              activeColor: primaryColor,
                              valueFormatter: (v) => '${v.round()}dB',
                              onChanged:
                                  _viperEnabled && _multibandCompressorEnabled
                                      ? (v) {
                                          setState(() => _mbcThresholds[i] = v);
                                          _updateEngine();
                                        }
                                      : (_) {})),
                      SizedBox(
                          width: 75,
                          child: ModernAudioKnob(
                              label: 'RATIO',
                              value: _mbcRatios[i],
                              min: 1.0,
                              max: 20.0,
                              activeColor: primaryColor,
                              valueFormatter: (v) =>
                                  '${v.toStringAsFixed(1)}:1',
                              onChanged:
                                  _viperEnabled && _multibandCompressorEnabled
                                      ? (v) {
                                          setState(() => _mbcRatios[i] = v);
                                          _updateEngine();
                                        }
                                      : (_) {})),
                      SizedBox(
                          width: 75,
                          child: ModernAudioKnob(
                              label: 'ATTACK',
                              value: _mbcAttacks[i],
                              min: 0.0,
                              max: 100.0,
                              activeColor: primaryColor,
                              valueFormatter: (v) => '${v.round()}ms',
                              onChanged:
                                  _viperEnabled && _multibandCompressorEnabled
                                      ? (v) {
                                          setState(() => _mbcAttacks[i] = v);
                                          _updateEngine();
                                        }
                                      : (_) {})),
                      SizedBox(
                          width: 75,
                          child: ModernAudioKnob(
                              label: 'RELEASE',
                              value: _mbcReleases[i],
                              min: 10.0,
                              max: 1000.0,
                              activeColor: primaryColor,
                              valueFormatter: (v) => '${v.round()}ms',
                              onChanged:
                                  _viperEnabled && _multibandCompressorEnabled
                                      ? (v) {
                                          setState(() => _mbcReleases[i] = v);
                                          _updateEngine();
                                        }
                                      : (_) {})),
                      SizedBox(
                          width: 75,
                          child: ModernAudioKnob(
                              label: 'GAIN',
                              value: _mbcGains[i],
                              min: -12.0,
                              max: 12.0,
                              activeColor: primaryColor,
                              valueFormatter: (v) =>
                                  '${v > 0 ? '+' : ''}${v.toStringAsFixed(1)}dB',
                              onChanged:
                                  _viperEnabled && _multibandCompressorEnabled
                                      ? (v) {
                                          setState(() => _mbcGains[i] = v);
                                          _updateEngine();
                                        }
                                      : (_) {})),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  List<EqBandConfig> _getViperDynamicEqBands() {
    return List.generate(5, (i) {
      EqBandType type;
      switch (_dynamicEqFilterTypes[i]) {
        case 1:
          type = EqBandType.lowshelf;
          break;
        case 2:
          type = EqBandType.highshelf;
          break;
        case 0:
        default:
          type = EqBandType.peak;
          break;
      }
      return EqBandConfig(
        type: type,
        frequencyHz: _dynamicEqFreqs[i],
        gainDb: _dynamicEqGains[i],
        q: _dynamicEqQs[i],
        enabled: true,
      );
    });
  }

  Widget _buildDynamicEqBands() {
    final labels = ['Band 1', 'Band 2', 'Band 3', 'Band 4', 'Band 5'];
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        RepaintBoundary(
          child: ParametricEqGraph(
            bands: _getViperDynamicEqBands(),
            isEnabled: _viperEnabled && _dynamicEqEnabled,
            height: 100.0,
            primaryColor: primaryColor,
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 480,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: 5,
            itemBuilder: (context, i) {
              return Container(
                width: 250,
                margin: const EdgeInsets.symmetric(horizontal: 4.0),
                padding: const EdgeInsets.symmetric(vertical: 8.0),
                decoration: BoxDecoration(
                  color: Colors.black12,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      Text(labels[i],
                          style: TextStyle(
                              color: primaryColor,
                              fontSize: 13,
                              fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 16,
                        alignment: WrapAlignment.center,
                        children: [
                          SizedBox(
                              width: 75,
                              child: ModernAudioKnob(
                                  label: 'FREQ',
                                  value: _dynamicEqFreqs[i],
                                  min: 20.0,
                                  max: 20000.0,
                                  activeColor: primaryColor,
                                  valueFormatter: (v) => '${v.round()}Hz',
                                  onChanged: _viperEnabled && _dynamicEqEnabled
                                      ? (v) {
                                          setState(
                                              () => _dynamicEqFreqs[i] = v);
                                          _updateEngine();
                                        }
                                      : (_) {})),
                          SizedBox(
                              width: 75,
                              child: ModernAudioKnob(
                                  label: 'Q',
                                  value: _dynamicEqQs[i],
                                  min: 0.1,
                                  max: 10.0,
                                  activeColor: primaryColor,
                                  valueFormatter: (v) => v.toStringAsFixed(1),
                                  onChanged: _viperEnabled && _dynamicEqEnabled
                                      ? (v) {
                                          setState(() => _dynamicEqQs[i] = v);
                                          _updateEngine();
                                        }
                                      : (_) {})),
                          SizedBox(
                              width: 75,
                              child: ModernAudioKnob(
                                  label: 'GAIN',
                                  value: _dynamicEqGains[i],
                                  min: -12.0,
                                  max: 12.0,
                                  activeColor: primaryColor,
                                  valueFormatter: (v) =>
                                      '${v > 0 ? '+' : ''}${v.toStringAsFixed(1)}dB',
                                  onChanged: _viperEnabled && _dynamicEqEnabled
                                      ? (v) {
                                          setState(
                                              () => _dynamicEqGains[i] = v);
                                          _updateEngine();
                                        }
                                      : (_) {})),
                          SizedBox(
                              width: 75,
                              child: ModernAudioKnob(
                                  label: 'THRESH',
                                  value: _dynamicEqThresholds[i],
                                  min: -60.0,
                                  max: 0.0,
                                  activeColor: primaryColor,
                                  valueFormatter: (v) => '${v.round()}dB',
                                  onChanged: _viperEnabled && _dynamicEqEnabled
                                      ? (v) {
                                          setState(() =>
                                              _dynamicEqThresholds[i] = v);
                                          _updateEngine();
                                        }
                                      : (_) {})),
                          SizedBox(
                              width: 75,
                              child: ModernAudioKnob(
                                  label: 'ATTACK',
                                  value: _dynamicEqAttacks[i],
                                  min: 0.0,
                                  max: 100.0,
                                  activeColor: primaryColor,
                                  valueFormatter: (v) => '${v.round()}ms',
                                  onChanged: _viperEnabled && _dynamicEqEnabled
                                      ? (v) {
                                          setState(
                                              () => _dynamicEqAttacks[i] = v);
                                          _updateEngine();
                                        }
                                      : (_) {})),
                          SizedBox(
                              width: 75,
                              child: ModernAudioKnob(
                                  label: 'RELEASE',
                                  value: _dynamicEqReleases[i],
                                  min: 10.0,
                                  max: 1000.0,
                                  activeColor: primaryColor,
                                  valueFormatter: (v) => '${v.round()}ms',
                                  onChanged: _viperEnabled && _dynamicEqEnabled
                                      ? (v) {
                                          setState(
                                              () => _dynamicEqReleases[i] = v);
                                          _updateEngine();
                                        }
                                      : (_) {})),
                        ],
                      ),
                      const SizedBox(height: 16),
                      const Text('Type',
                          style:
                              TextStyle(color: Colors.white70, fontSize: 11)),
                      const SizedBox(height: 4),
                      M3ESegmentedButton<int>(
                        segments: const [
                          M3ESegment(value: 0, label: 'Peak'),
                          M3ESegment(value: 1, label: 'LoShelf'),
                          M3ESegment(value: 2, label: 'HiShelf'),
                        ],
                        selected: {_dynamicEqFilterTypes[i]},
                        onSelectionChanged: (Set<int> newSelection) {
                          if (_viperEnabled &&
                              _dynamicEqEnabled &&
                              newSelection.isNotEmpty) {
                            setState(() =>
                                _dynamicEqFilterTypes[i] = newSelection.first);
                            _updateEngine();
                          }
                        },
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildEqBands(List<double> freqs, List<double> gains, bool enabled) {
    return RepaintBoundary(
      child: SizedBox(
        height: 250,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          itemCount: freqs.length,
          itemBuilder: (context, index) {
            final freq = freqs[index];
            String label = freq >= 1000
                ? '${(freq / 1000).toStringAsFixed(freq % 1000 == 0 ? 0 : 1)}k'
                : '${freq.round()}';

            return Container(
              width: 80,
              margin: const EdgeInsets.symmetric(horizontal: 4.0),
              padding: const EdgeInsets.symmetric(vertical: 8.0),
              decoration: BoxDecoration(
                color: Colors.black12,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '$label Hz',
                    style: TextStyle(
                      color: primaryColor,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${gains[index] > 0 ? '+' : ''}${gains[index].toStringAsFixed(1)} dB',
                    style: const TextStyle(color: Colors.white70, fontSize: 11),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: SizedBox(
                      width: 44,
                      child: M3ESlider.vertical(
                        value: gains[index],
                        min: -12.0,
                        max: 12.0,
                        onChanged: _viperEnabled && enabled
                            ? (v) {
                                setState(() => gains[index] = v);
                                _updateEngine();
                              }
                            : null,
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  void _scanConvolverFolder() {
    if (_convolverFolder == null) return;
    final dir = Directory(_convolverFolder!);
    if (dir.existsSync()) {
      final files = dir
          .listSync()
          .whereType<File>()
          .where((f) =>
              f.path.toLowerCase().endsWith('.irs') ||
              f.path.toLowerCase().endsWith('.wav'))
          .map((f) => p.basename(f.path))
          .toList();
      setState(() {
        _convolverFiles = files;
        if (_selectedConvolverFile != null &&
            !_convolverFiles.contains(_selectedConvolverFile)) {
          _selectedConvolverFile = null;
        }
      });
    }
  }

  void _scanDdcFolder() {
    if (_ddcFolder == null) return;
    final dir = Directory(_ddcFolder!);
    if (dir.existsSync()) {
      final files = dir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.toLowerCase().endsWith('.vdc'))
          .map((f) => p.basename(f.path))
          .toList();
      setState(() {
        _ddcFiles = files;
        if (_selectedDdcFile != null && !_ddcFiles.contains(_selectedDdcFile)) {
          _selectedDdcFile = null;
        }
      });
    }
  }

  Future<String?> _pickDirectory(bool isConvolver) async {
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      return await file_selector.getDirectoryPath();
    } else {
      final result = await FilePicker.pickFiles(
        allowMultiple: true,
        type: FileType.any,
      );
      if (result != null && result.paths.isNotEmpty) {
        final targetDir = Directory(
            '${Directory.systemTemp.path}${Platform.pathSeparator}sautiplay_${isConvolver ? "irs" : "vdc"}');
        if (!targetDir.existsSync()) {
          targetDir.createSync(recursive: true);
        }
        for (var path in result.paths) {
          if (path != null) {
            final file = File(path);
            if (file.existsSync()) {
              final newPath = p.join(targetDir.path, p.basename(path));
              file.copySync(newPath);
            }
          }
        }
        return targetDir.path;
      }
      return null;
    }
  }

  Widget _buildConvolverSelector() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          M3EButton.icon(
            onPressed: () async {
              String? selectedDirectory = await _pickDirectory(true);
              if (selectedDirectory != null) {
                setState(() {
                  _convolverFolder = selectedDirectory;
                  _selectedConvolverFile = null;
                });
                _scanConvolverFolder();
                _updateEngine();
              }
            },
            icon: const Icon(Icons.folder_open_rounded),
            label: Text(_convolverFolder == null
                ? 'Import IRS Folder / Files'
                : 'Change Directory / Files'),
          ),
          if (_convolverFolder != null) ...[
            const SizedBox(height: 12),
            Text('Folder: ${p.basename(_convolverFolder!)}',
                style: const TextStyle(color: Colors.white70, fontSize: 12)),
            const SizedBox(height: 8),
            /*M3EContainer(
              Shapes.pill,
              color: surfaceDarkColor,
              border: BorderSide(
                color: primaryColor.withValues(alpha: 0.35),
              ),
              child: */
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: M3EDropdownMenu<String>(
                key: ValueKey(
                    'convolver_${_selectedConvolverFile}_${_convolverFiles.length}'),
                singleSelect: true,
                searchEnabled: _convolverFiles.length > 5,
                enabled: _viperEnabled && _convolverEnabled,
                fieldStyle: M3EDropdownFieldStyle(
                  hintText: 'Select Impulse Response',
                  backgroundColor: surfaceDarkColor,
                  foregroundColor: Colors.white,
                  selectedTextStyle: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                ),
                dropdownStyle: M3EDropdownPanelStyle(
                  backgroundColor: surfaceDarkColor,
                  elevation: 4,
                ),
                itemStyle: M3EDropdownItemStyle(
                  textColor: Colors.white,
                  selectedTextColor: primaryColor,
                  selectedBackgroundColor: primaryColor.withValues(alpha: 0.15),
                ),
                items: _convolverFiles
                    .map((file) => M3EDropdownItem<String>(
                          label: file,
                          value: file,
                          selected: file == _selectedConvolverFile,
                        ))
                    .toList(),
                onSelectionChanged: (selectedList) {
                  if (selectedList.isNotEmpty &&
                      _viperEnabled &&
                      _convolverEnabled) {
                    final newValue = selectedList.first.value;
                    if (newValue != _selectedConvolverFile) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted) {
                          setState(() => _selectedConvolverFile = newValue);
                          _updateEngine();
                        }
                      });
                    }
                  }
                },
              ),
            ),
            const SizedBox(height: 12),
            Center(
              child: SizedBox(
                width: 100,
                child: ModernAudioKnob(
                  label: 'CROSS CH',
                  value: _convolverCrossChannel,
                  min: 0.0,
                  max: 1.0,
                  activeColor: primaryColor,
                  valueFormatter: (v) => '${(v * 100).round()}%',
                  onChanged: _viperEnabled && _convolverEnabled
                      ? (v) {
                          setState(() => _convolverCrossChannel = v);
                          _updateEngine();
                        }
                      : (_) {},
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDdcSelector() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          M3EButton.icon(
            onPressed: () async {
              String? selectedDirectory = await _pickDirectory(false);
              if (selectedDirectory != null) {
                setState(() {
                  _ddcFolder = selectedDirectory;
                  _selectedDdcFile = null;
                });
                _scanDdcFolder();
                _updateEngine();
              }
            },
            icon: const Icon(Icons.folder_open_rounded),
            label: Text(_ddcFolder == null
                ? 'Import DDC Folder / Files'
                : 'Change Directory / Files'),
          ),
          if (_ddcFolder != null) ...[
            const SizedBox(height: 12),
            Text('Folder: ${p.basename(_ddcFolder!)}',
                style: const TextStyle(color: Colors.white70, fontSize: 12)),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: M3EDropdownMenu<String>(
                key: ValueKey('ddc_${_selectedDdcFile}_${_ddcFiles.length}'),
                singleSelect: true,
                searchEnabled: _ddcFiles.length > 5,
                enabled: _viperEnabled && _ddcEnabled,
                fieldStyle: M3EDropdownFieldStyle(
                  hintText: 'Select DDC Profile',
                  backgroundColor: surfaceDarkColor,
                  foregroundColor: Colors.white,
                  selectedTextStyle: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                ),
                dropdownStyle: M3EDropdownPanelStyle(
                  backgroundColor: surfaceDarkColor,
                  elevation: 4,
                ),
                itemStyle: M3EDropdownItemStyle(
                  textColor: Colors.white,
                  selectedTextColor: primaryColor,
                  selectedBackgroundColor: primaryColor.withValues(alpha: 0.15),
                ),
                items: _ddcFiles
                    .map((file) => M3EDropdownItem<String>(
                          label: file,
                          value: file,
                          selected: file == _selectedDdcFile,
                        ))
                    .toList(),
                onSelectionChanged: (selectedList) {
                  if (selectedList.isNotEmpty && _viperEnabled && _ddcEnabled) {
                    final newValue = selectedList.first.value;
                    if (newValue != _selectedDdcFile) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted) {
                          setState(() => _selectedDdcFile = newValue);
                          _updateEngine();
                        }
                      });
                    }
                  }
                },
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAutoEqImporter() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: M3ECard(
        variant: M3ECardVariant.filled,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  /*  M3EContainer(
                    Shapes.burst,
                    width: 32,
                    height: 32,
                    color: primaryColor.withValues(alpha: 0.18),
                    border: BorderSide(
                      color: primaryColor.withValues(alpha: 0.4),
                      width: 1,
                    ),
                    child: */
                  Center(
                    child:
                        Icon(Icons.auto_awesome, color: primaryColor, size: 16),
                  ),
                  //  ),
                  const SizedBox(width: 10),
                  const Text('AutoEQ & Presets Importer',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                  'Import AutoEQ text files (.txt, GraphicEQ, ParametricEQ), Convolver impulse files (.irs, .wav), or DDC profiles (.vdc).',
                  style: TextStyle(color: Colors.white60, fontSize: 12)),
              const SizedBox(height: 14),
              M3EButton.icon(
                onPressed: _viperEnabled
                    ? () async {
                        final result = await FilePicker.pickFiles(
                          type: FileType.any,
                          allowMultiple: false,
                        );
                        if (result != null &&
                            result.files.single.path != null) {
                          final path = result.files.single.path!;
                          final ext = p.extension(path).toLowerCase();
                          if (ext == '.txt' || ext == '.eq' || ext == '.txt') {
                            try {
                              final autoEqResult = AutoEqParser.parseFile(path);
                              widget.player.loadViperAutoEqText(path);
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                        'AutoEQ Loaded: ${autoEqResult.profileName} (Preamp: ${autoEqResult.preampGainDb.toStringAsFixed(1)} dB)'),
                                    backgroundColor: primaryColor,
                                  ),
                                );
                              }
                            } catch (e) {
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                      content: Text('AutoEQ Error: $e'),
                                      backgroundColor: Colors.red),
                                );
                              }
                            }
                          } else if (ext == '.irs' || ext == '.wav') {
                            final targetDir = Directory(
                                '${Directory.systemTemp.path}${Platform.pathSeparator}sautiplay_irs');
                            if (!targetDir.existsSync()) {
                              targetDir.createSync(recursive: true);
                            }
                            final newPath =
                                p.join(targetDir.path, p.basename(path));
                            File(path).copySync(newPath);
                            setState(() {
                              _convolverFolder = targetDir.path;
                              _selectedConvolverFile = p.basename(path);
                              _convolverEnabled = true;
                            });
                            _scanConvolverFolder();
                            _updateEngine();
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                    content: Text(
                                        'Convolver Loaded: ${p.basename(path)}'),
                                    backgroundColor: primaryColor),
                              );
                            }
                          } else if (ext == '.vdc') {
                            final targetDir = Directory(
                                '${Directory.systemTemp.path}${Platform.pathSeparator}sautiplay_vdc');
                            if (!targetDir.existsSync()) {
                              targetDir.createSync(recursive: true);
                            }
                            final newPath =
                                p.join(targetDir.path, p.basename(path));
                            File(path).copySync(newPath);
                            setState(() {
                              _ddcFolder = targetDir.path;
                              _selectedDdcFile = p.basename(path);
                              _ddcEnabled = true;
                            });
                            _scanDdcFolder();
                            _updateEngine();
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                    content: Text(
                                        'DDC Profile Loaded: ${p.basename(path)}'),
                                    backgroundColor: primaryColor),
                              );
                            }
                          }
                        }
                      }
                    : null,
                icon: const Icon(Icons.file_upload_outlined),
                label: const Text('Import AutoEQ / Preset File'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
