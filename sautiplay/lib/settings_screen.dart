import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sautiflow/sautiflow.dart';

import 'eq_screen.dart';
import 'isolate_player.dart';
import 'services/app_state_service.dart';

class SettingsScreen extends StatefulWidget {
  final IsolateAudioPlayer player;
  // Shared state from main.dart
  final bool analyzerEnabled;
  final ValueChanged<bool> onAnalyzerEnabledChanged;
  final String analyzerType;
  final ValueChanged<String> onAnalyzerTypeChanged;
  final bool analyzerAutoFit;
  final ValueChanged<bool> onAnalyzerAutoFitChanged;
  final bool analyzerShowGrids;
  final ValueChanged<bool> onAnalyzerShowGridsChanged;
  final bool analyzerLogScale;
  final ValueChanged<bool> onAnalyzerLogScaleChanged;
  final int analyzerSampleSize;
  final ValueChanged<int> onAnalyzerSampleSizeChanged;
  final AudioFormat outputFormat;
  final ValueChanged<AudioFormat> onOutputFormatChanged;
  final int outputSampleRate;
  final ValueChanged<int> onOutputSampleRateChanged;
  final int outputChannels;
  final ValueChanged<int> onOutputChannelsChanged;
  final bool crossfadeEnabled;
  final ValueChanged<bool> onCrossfadeEnabledChanged;
  final int crossfadeDurationMs;
  final ValueChanged<int> onCrossfadeDurationMsChanged;
  final bool exclusiveMode;
  final ValueChanged<bool> onExclusiveModeChanged;
  final String spectrumStyle;
  final ValueChanged<String> onSpectrumStyleChanged;

  const SettingsScreen({
    super.key,
    required this.player,
    required this.analyzerEnabled,
    required this.onAnalyzerEnabledChanged,
    required this.analyzerType,
    required this.onAnalyzerTypeChanged,
    required this.analyzerAutoFit,
    required this.onAnalyzerAutoFitChanged,
    required this.analyzerShowGrids,
    required this.onAnalyzerShowGridsChanged,
    required this.analyzerLogScale,
    required this.onAnalyzerLogScaleChanged,
    required this.analyzerSampleSize,
    required this.onAnalyzerSampleSizeChanged,
    required this.outputFormat,
    required this.onOutputFormatChanged,
    required this.outputSampleRate,
    required this.onOutputSampleRateChanged,
    required this.outputChannels,
    required this.onOutputChannelsChanged,
    required this.crossfadeEnabled,
    required this.onCrossfadeEnabledChanged,
    required this.crossfadeDurationMs,
    required this.onCrossfadeDurationMsChanged,
    required this.exclusiveMode,
    required this.onExclusiveModeChanged,
    required this.spectrumStyle,
    required this.onSpectrumStyleChanged,
    required this.logs,
    required this.logUpdateNotifier,
    required this.allowInvalidTls,
    required this.onAllowInvalidTlsChanged,
    required this.onPollError,
    required this.onClearNativeError,
    required this.onClearLogs,
  });

  final List<String> logs;
  final ValueNotifier<int> logUpdateNotifier;
  final bool allowInvalidTls;
  final ValueChanged<bool> onAllowInvalidTlsChanged;
  final VoidCallback onPollError;
  final VoidCallback onClearNativeError;
  final VoidCallback onClearLogs;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  // Theme colors based on reference
  static const _bgDark = Color(0xFF101922);
  static const _cardDark = Color(0xFF1C252E);
  static const _primary = Color(0xFF137fec);
  static const _textDark = Color(0xFF94A3B8);

  // Local fake state for UI-only settings (to match mockup)
  String _streamingQuality = 'High Fidelity';
  bool _gaplessPlayback = true;
  bool _normalizeVolume = false;
  bool _streamOverWifi = true;

  // Engine Resampling and Dithering
  int _resampleAlgorithm = 0;
  int _ditherMode = 0;
  int _eqBandCount = 10;
  
  // ReplayGain
  ReplayGainMode _replayGainMode = ReplayGainMode.none;
  double _replayGainPreamp = 0.0;

  // DSP Oversampling
  int _dspOversampling = 1;

  // Speaker & Hardware Protection
  bool _speakerProtectionEnabled = true;
  double _subsonicCutoffHz = 25.0;
  double _ultrasonicCutoffHz = 20000.0;
  double _limiterThreshold = 0.95;
  double _safetyAttenuationDb = -1.0;

  // Phase Inversion
  bool _phaseInvertLeft = false;
  bool _phaseInvertRight = false;

  @override
  void initState() {
    super.initState();
    _loadUiSettings();
  }

  Future<void> _loadUiSettings() async {
    final saved = await AppStateService.instance.loadUiSettings();
    final eqSaved = await AppStateService.instance.loadEqBands();
    final rgSaved = await AppStateService.instance.loadReplayGainSettings();
    final oversamplingSaved = await AppStateService.instance.loadDspOversampling();
    final spSaved = await AppStateService.instance.loadSpeakerProtection();
    final phaseSaved = await AppStateService.instance.loadPhaseInversion();
    setState(() {
      _streamingQuality = saved.streamingQuality;
      _gaplessPlayback = saved.gaplessPlayback;
      _normalizeVolume = saved.normalizeVolume;
      _streamOverWifi = saved.streamOverWifi;
      _resampleAlgorithm = saved.resampleAlgorithm;
      _ditherMode = saved.ditherMode;
      _eqBandCount = eqSaved.bandCount;
      _replayGainMode = rgSaved.mode;
      _replayGainPreamp = rgSaved.preamp;
      _dspOversampling = oversamplingSaved;
      _speakerProtectionEnabled = spSaved.enabled;
      _subsonicCutoffHz = spSaved.subsonicCutoffHz;
      _ultrasonicCutoffHz = spSaved.ultrasonicCutoffHz;
      _limiterThreshold = spSaved.limiterThreshold;
      _safetyAttenuationDb = spSaved.safetyAttenuationDb;
      _phaseInvertLeft = phaseSaved.invertLeft;
      _phaseInvertRight = phaseSaved.invertRight;
    });
    widget.player.setViperOversampling(oversamplingSaved);
    widget.player.setPhaseInversion(
      invertLeft: _phaseInvertLeft,
      invertRight: _phaseInvertRight,
    );
    _applySpeakerProtectionSettings();
  }

  void _persistPhaseInversionSettings() {
    AppStateService.instance.savePhaseInversion(
      invertLeft: _phaseInvertLeft,
      invertRight: _phaseInvertRight,
    );
    widget.player.setPhaseInversion(
      invertLeft: _phaseInvertLeft,
      invertRight: _phaseInvertRight,
    );
  }

  void _persistSpeakerProtectionSettings() {
    AppStateService.instance.saveSpeakerProtection(
      enabled: _speakerProtectionEnabled,
      subsonicCutoffHz: _subsonicCutoffHz,
      ultrasonicCutoffHz: _ultrasonicCutoffHz,
      limiterThreshold: _limiterThreshold,
      safetyAttenuationDb: _safetyAttenuationDb,
    );
    _applySpeakerProtectionSettings();
  }

  void _applySpeakerProtectionSettings() {
    widget.player.setSpeakerProtectionParams(
      enabled: _speakerProtectionEnabled,
      subsonicCutoffHz: _subsonicCutoffHz,
      ultrasonicCutoffHz: _ultrasonicCutoffHz,
      limiterThreshold: _limiterThreshold,
      safetyAttenuationDb: _safetyAttenuationDb,
    );
  }

  void _persistReplayGainSettings() {
    AppStateService.instance.saveReplayGainSettings(
      mode: _replayGainMode,
      preamp: _replayGainPreamp,
    );
  }

  void _persistUiSettings() {
    AppStateService.instance.saveUiSettings(
      streamingQuality: _streamingQuality,
      gaplessPlayback: _gaplessPlayback,
      normalizeVolume: _normalizeVolume,
      streamOverWifi: _streamOverWifi,
      resampleAlgorithm: _resampleAlgorithm,
      ditherMode: _ditherMode,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgDark,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isDesktop = constraints.maxWidth >= 800;
          final isMobile = constraints.maxWidth < 600;
          return Align(
            alignment: isDesktop ? Alignment.topCenter : Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1000.0),
              child: CustomScrollView(
                slivers: [
                  SliverAppBar(
                    backgroundColor: _bgDark.withAlpha(230),
                    floating: true,
                    pinned: true,
                    title: const Text(
                      'Settings',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    centerTitle: true,
                  ),
                  SliverPadding(
                    padding: EdgeInsets.symmetric(
                        horizontal: isDesktop ? 48.0 : 0.0),
                    sliver: SliverList(
                      delegate: SliverChildListDelegate([
                        const SizedBox(height: 16),
                        _buildSectionTitle(isMobile ? 'AUDIO' : 'AUDIO QUALITY', isMobile: isMobile),
                        _buildAudioQualityCard(isMobile: isMobile),
                        const SizedBox(height: 24),
                        _buildSectionTitle(isMobile ? 'PROTECTION' : 'SPEAKER & HARDWARE PROTECTION', isMobile: isMobile),
                        _buildSpeakerProtectionCard(isMobile: isMobile),
                        const SizedBox(height: 24),
                        _buildSectionTitle('PLAYBACK', isMobile: isMobile),
                        _buildPlaybackCard(isMobile: isMobile),
                        const SizedBox(height: 24),
                        _buildSectionTitle(isMobile ? 'EQ' : 'EQUALIZER', isMobile: isMobile),
                        _buildEqualizerCard(isMobile: isMobile),
                        const SizedBox(height: 24),
                        _buildSectionTitle(isMobile ? 'VISUALS' : 'VISUALIZATION', isMobile: isMobile),
                        _buildVisualizationCard(isMobile: isMobile),
                        const SizedBox(height: 24),
                        _buildSectionTitle(isMobile ? 'STORAGE' : 'STORAGE & DATA', isMobile: isMobile),
                        _buildStorageCard(isMobile: isMobile),
                        const SizedBox(height: 24),
                        _buildSectionTitle(isMobile ? 'ABOUT' : 'ABOUT & LICENSES', isMobile: isMobile),
                        _buildAboutCard(context, isMobile: isMobile),
                        const SizedBox(height: 24),
                        _buildSectionTitle(isMobile ? 'DEBUG' : 'DEBUG & LOGS', isMobile: isMobile),
                        _buildDebugAndLogsCard(isMobile: isMobile),
                        const SizedBox(height: 120),
                      ]),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSectionTitle(String title, {bool isMobile = false}) {
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 16.0 : 24.0,
        vertical: isMobile ? 4.0 : 8.0,
      ),
      child: Text(
        title,
        style: TextStyle(
          color: _textDark,
          fontSize: isMobile ? 11 : 12,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  String _formatAudioDepth(AudioFormat format) {
    switch (format) {
      case AudioFormat.f32:
        return '32 bit float';
      case AudioFormat.s32:
        return '32 bit';
      case AudioFormat.s24:
        return '24 bit';
      case AudioFormat.s16:
        return '16 bit';
      case AudioFormat.u8:
        return '8 bit';
    }
  }

  Widget _buildCard({required List<Widget> children, bool isMobile = false}) {
    return Container(
      margin: EdgeInsets.symmetric(horizontal: isMobile ? 10.0 : 16.0),
      decoration: BoxDecoration(
        color: _cardDark,
        borderRadius: BorderRadius.circular(isMobile ? 16 : 20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }

  Widget _buildAudioQualityCard({bool isMobile = false}) {
    return _buildCard(
      isMobile: isMobile,
      children: [
        // Streaming Quality Segmented
        Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _primary.withAlpha(25),
                      shape: BoxShape.circle,
                    ),
                    child:
                        const Icon(Icons.graphic_eq, color: _primary, size: 24),
                  ),
                  const SizedBox(width: 16),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Streaming Quality',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w500)),
                        SizedBox(height: 4),
                        Text('Higher quality uses more data',
                            style: TextStyle(color: _textDark, fontSize: 13)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Container(
                height: 44,
                decoration: BoxDecoration(
                  color: Colors.black26,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () {
                          setState(() => _streamingQuality = 'High Fidelity');
                          _persistUiSettings();
                        },
                        child: Container(
                          decoration: BoxDecoration(
                            color: _streamingQuality == 'High Fidelity'
                                ? _primary
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            'High Fidelity',
                            style: TextStyle(
                              color: _streamingQuality == 'High Fidelity'
                                  ? Colors.white
                                  : _textDark,
                              fontWeight: _streamingQuality == 'High Fidelity'
                                  ? FontWeight.w600
                                  : FontWeight.normal,
                            ),
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: GestureDetector(
                        onTap: () {
                          setState(() => _streamingQuality = 'Data Saver');
                          _persistUiSettings();
                        },
                        child: Container(
                          decoration: BoxDecoration(
                            color: _streamingQuality == 'Data Saver'
                                ? _primary
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            'Data Saver',
                            style: TextStyle(
                              color: _streamingQuality == 'Data Saver'
                                  ? Colors.white
                                  : _textDark,
                              fontWeight: _streamingQuality == 'Data Saver'
                                  ? FontWeight.w600
                                  : FontWeight.normal,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const Divider(color: Colors.white10, height: 1),
        // Resampling Algorithm
        ListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          leading: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(10),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.memory, color: Colors.white70, size: 20),
          ),
          title: const Text('Resampling Algorithm',
              style:
                  TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
          trailing: SizedBox(
            width: 160,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Expanded(
                  child: Text(
                    _getResampleAlgorithmName(_resampleAlgorithm),
                    style: const TextStyle(color: _textDark, fontSize: 14),
                    textAlign: TextAlign.right,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.chevron_right, color: _textDark, size: 20),
              ],
            ),
          ),
          onTap: () => _showResampleAlgorithmDialog(),
        ),
        const Divider(color: Colors.white10, height: 1),
        // DSP Oversampling
        ListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          leading: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(10),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.blur_on, color: Colors.white70, size: 20),
          ),
          title: const Text('DSP Oversampling',
              style:
                  TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
          subtitle: const Text('Anti-aliasing for ViPER FX & limiters',
              style: TextStyle(color: _textDark, fontSize: 12)),
          trailing: SizedBox(
            width: 150,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Expanded(
                  child: Text(
                    _getOversamplingName(_dspOversampling),
                    style: const TextStyle(color: _textDark, fontSize: 14),
                    textAlign: TextAlign.right,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.chevron_right, color: _textDark, size: 20),
              ],
            ),
          ),
          onTap: () => _showOversamplingDialog(),
        ),
        const Divider(color: Colors.white10, height: 1),
        // Dither Mode
        ListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          leading: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(10),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.waves, color: Colors.white70, size: 20),
          ),
          title: const Text('Dither Mode',
              style:
                  TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
          trailing: SizedBox(
            width: 150,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Expanded(
                  child: Text(
                    _getDitherModeName(_ditherMode),
                    style: const TextStyle(color: _textDark, fontSize: 14),
                    textAlign: TextAlign.right,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.chevron_right, color: _textDark, size: 20),
              ],
            ),
          ),
          onTap: () => _showDitherModeDialog(),
        ),
        const Divider(color: Colors.white10, height: 1),
        // Output Format
        ListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          leading: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(10),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.code, color: Colors.white70, size: 20),
          ),
          title: const Text('Output Format',
              style:
                  TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
          subtitle: const Text('Requires engine restart',
              style: TextStyle(color: _textDark, fontSize: 12)),
          trailing: SizedBox(
            width: 150,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Expanded(
                  child: Text(
                    _formatAudioDepth(widget.outputFormat),
                    style: const TextStyle(color: _textDark, fontSize: 14),
                    textAlign: TextAlign.right,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.chevron_right, color: _textDark, size: 20),
              ],
            ),
          ),
          onTap: () => _showOutputFormatDialog(),
        ),
        const Divider(color: Colors.white10, height: 1),
        // ReplayGain Mode
        ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          leading: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(10),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.equalizer, color: Colors.white70, size: 20),
          ),
          title: const Text('ReplayGain Mode',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
          trailing: SizedBox(
            width: 150,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Expanded(
                  child: Text(
                    _replayGainMode == ReplayGainMode.none
                        ? 'None'
                        : _replayGainMode == ReplayGainMode.track
                            ? 'Track'
                            : 'Album',
                    style: const TextStyle(color: _textDark, fontSize: 14),
                    textAlign: TextAlign.right,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.chevron_right, color: _textDark, size: 20),
              ],
            ),
          ),
          onTap: () => _showReplayGainModeDialog(),
        ),
        const Divider(color: Colors.white10, height: 1),
        // ReplayGain Preamp Knob
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'ReplayGain Preamp',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
              ),
              SizedBox(
                width: 90,
                child: ModernAudioKnob(
                  label: 'GAIN',
                  value: _replayGainPreamp,
                  min: -15.0,
                  max: 15.0,
                  activeColor: _primary,
                  valueFormatter: (v) => '${v > 0 ? '+' : ''}${v.toStringAsFixed(1)} dB',
                  onChanged: (val) {
                    setState(() => _replayGainPreamp = val);
                    _persistReplayGainSettings();
                  },
                ),
              ),
            ],
          ),
        ),
        const Divider(color: Colors.white10, height: 1),
        // Sample Rate
        ListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          leading: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(10),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.speed, color: Colors.white70, size: 20),
          ),
          title: const Text('Sample Rate',
              style:
                  TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
          trailing: SizedBox(
            width: 150,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Expanded(
                  child: Text(
                    widget.outputSampleRate == 0
                        ? 'Native'
                        : '${widget.outputSampleRate} Hz',
                    style: const TextStyle(color: _textDark, fontSize: 14),
                    textAlign: TextAlign.right,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.chevron_right, color: _textDark, size: 20),
              ],
            ),
          ),
          onTap: () => _showSampleRateDialog(),
        ),
        const Divider(color: Colors.white10, height: 1),
        // Output Channels
        ListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          leading: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(10),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.speaker_group,
                color: Colors.white70, size: 20),
          ),
          title: const Text('Output Channels',
              style:
                  TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
          trailing: SizedBox(
            width: 150,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Expanded(
                  child: Text(
                    widget.outputChannels == 1 ? 'Mono' : 'Stereo',
                    style: const TextStyle(color: _textDark, fontSize: 14),
                    textAlign: TextAlign.right,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.chevron_right, color: _textDark, size: 20),
              ],
            ),
          ),
          onTap: () => _showChannelsDialog(),
        ),
        const Divider(color: Colors.white10, height: 1),
        // Phase Inversion (Polarity Flip)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white.withAlpha(10),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.swap_calls, color: Colors.white70, size: 20),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isMobile ? 'Phase Inversion' : 'Phase Inversion (Ø 180°)',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
                        ),
                        const SizedBox(height: 2),
                        const Text(
                          'Invert PCM polarity for reversed hardware or phase alignment',
                          style: TextStyle(color: _textDark, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: ChoiceChip(
                      label: const Text('Normal (0°)'),
                      selected: !_phaseInvertLeft && !_phaseInvertRight,
                      selectedColor: _primary,
                      onSelected: (val) {
                        if (val) {
                          setState(() {
                            _phaseInvertLeft = false;
                            _phaseInvertRight = false;
                          });
                          _persistPhaseInversionSettings();
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ChoiceChip(
                      label: const Text('Invert L'),
                      selected: _phaseInvertLeft,
                      selectedColor: _primary,
                      onSelected: (val) {
                        setState(() => _phaseInvertLeft = val);
                        _persistPhaseInversionSettings();
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ChoiceChip(
                      label: const Text('Invert R'),
                      selected: _phaseInvertRight,
                      selectedColor: _primary,
                      onSelected: (val) {
                        setState(() => _phaseInvertRight = val);
                        _persistPhaseInversionSettings();
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const Divider(color: Colors.white10, height: 1),
        SwitchListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          secondary: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(10),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.shield, color: Colors.white70, size: 20),
          ),
          title: Text(isMobile ? 'Bit-Perfect Output' : 'True Bit-Perfect Output',
              style:
                  const TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
          subtitle: const Text('Bypass OS Mixer & DSP. Forces exclusive mode.',
              style: TextStyle(color: _textDark, fontSize: 12)),
          value: widget.exclusiveMode,
          activeThumbColor: _primary,
          onChanged: (val) async {
            widget.player.setExclusiveMode(val);
            await Future.delayed(const Duration(milliseconds: 150));
            final actual = await widget.player.getExclusiveMode();
            widget.onExclusiveModeChanged(actual);
            if (!context.mounted) return;
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
            if (val && !actual) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  backgroundColor: _cardDark,
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: Colors.amberAccent.withAlpha(80)),
                  ),
                  content: Row(
                    children: const [
                      Icon(Icons.warning_amber_rounded, color: Colors.amberAccent, size: 20),
                      SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Hardware rejected Exclusive Mode. Falling back! Try changing Sample Rate/Format.',
                          style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            } else if (val && actual) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  backgroundColor: _cardDark,
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: _primary.withAlpha(100)),
                  ),
                  content: Row(
                    children: const [
                      Icon(Icons.check_circle_outline, color: _primary, size: 20),
                      SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Exclusive Bit-Perfect Mode Enabled! DSP bypassed.',
                          style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            } else if (!val) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  backgroundColor: _cardDark,
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: Colors.white.withAlpha(25)),
                  ),
                  content: Row(
                    children: const [
                      Icon(Icons.info_outline, color: Colors.white70, size: 20),
                      SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Bit-Perfect Mode Disabled.',
                          style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }
          },
        ),
      ],
    );
  }

  Widget _buildSpeakerProtectionCard({bool isMobile = false}) {
    return _buildCard(
      isMobile: isMobile,
      children: [
        // Master Protection Toggle
        SwitchListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          activeThumbColor: Colors.white,
          activeTrackColor: _primary,
          inactiveThumbColor: Colors.white70,
          inactiveTrackColor: Colors.white10,
          title: Text(isMobile ? 'Safeguards' : 'Protection Safeguards',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
          subtitle: Text(
            _speakerProtectionEnabled
                ? 'Subsonic filter, ultrasonic guard & peak ceiling active'
                : 'Safeguards disabled (risk of speaker over-excursion & clipping)',
            style: TextStyle(
              color: _speakerProtectionEnabled ? Colors.greenAccent.shade200 : Colors.amberAccent,
              fontSize: 12,
            ),
          ),
          secondary: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: (_speakerProtectionEnabled ? _primary : Colors.amberAccent).withAlpha(25),
              shape: BoxShape.circle,
            ),
            child: Icon(
              _speakerProtectionEnabled ? Icons.health_and_safety : Icons.warning_amber_rounded,
              color: _speakerProtectionEnabled ? _primary : Colors.amberAccent,
              size: 20,
            ),
          ),
          value: _speakerProtectionEnabled,
          onChanged: (val) {
            setState(() => _speakerProtectionEnabled = val);
            _persistSpeakerProtectionSettings();
          },
        ),
        if (_speakerProtectionEnabled) ...[
          const Divider(color: Colors.white10, height: 1),
          // Subsonic Cutoff (High Pass Filter)
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            leading: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white.withAlpha(10),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.arrow_upward, color: Colors.white70, size: 20),
            ),
            title: Text(isMobile ? 'Subsonic Filter' : 'Subsonic Filter (High-Pass)',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
            subtitle: const Text('Cuts invisible low frequencies below woofer tuning',
                style: TextStyle(color: _textDark, fontSize: 12)),
            trailing: SizedBox(
              width: 130,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Expanded(
                    child: Text(
                      _subsonicCutoffHz <= 0 ? 'Off' : '${_subsonicCutoffHz.toInt()} Hz',
                      style: const TextStyle(color: _textDark, fontSize: 14),
                      textAlign: TextAlign.right,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(Icons.chevron_right, color: _textDark, size: 20),
                ],
              ),
            ),
            onTap: () => _showSubsonicDialog(),
          ),
          const Divider(color: Colors.white10, height: 1),
          // Ultrasonic Cutoff (Low Pass Filter)
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            leading: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white.withAlpha(10),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.arrow_downward, color: Colors.white70, size: 20),
            ),
            title: Text(isMobile ? 'Ultrasonic Guard' : 'Ultrasonic Guard (Low-Pass)',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
            subtitle: const Text('Filters out dangerous high frequencies above 18-22kHz',
                style: TextStyle(color: _textDark, fontSize: 12)),
            trailing: SizedBox(
              width: 130,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Expanded(
                    child: Text(
                      _ultrasonicCutoffHz >= 24000 ? 'Off' : '${(_ultrasonicCutoffHz / 1000).toStringAsFixed(1)} kHz',
                      style: const TextStyle(color: _textDark, fontSize: 14),
                      textAlign: TextAlign.right,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(Icons.chevron_right, color: _textDark, size: 20),
                ],
              ),
            ),
            onTap: () => _showUltrasonicDialog(),
          ),
          const Divider(color: Colors.white10, height: 1),
          // Peak Limiter Threshold & Safety Headroom Knobs
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Peak Ceiling',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
                      const SizedBox(height: 2),
                      Text(
                        'Max: ${(_limiterThreshold * 100).toInt()}% (${(20 * math.log(_limiterThreshold) / math.ln10).toStringAsFixed(2)} dBFS)',
                        style: const TextStyle(color: _textDark, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                SizedBox(
                  width: 90,
                  child: ModernAudioKnob(
                    label: 'CEILING',
                    value: _limiterThreshold,
                    min: 0.70,
                    max: 1.00,
                    activeColor: _primary,
                    valueFormatter: (v) => '${(v * 100).toInt()}%',
                    onChanged: (val) {
                      setState(() => _limiterThreshold = val);
                      _persistSpeakerProtectionSettings();
                    },
                  ),
                ),
              ],
            ),
          ),
          const Divider(color: Colors.white10, height: 1),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Safety Headroom',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
                      const SizedBox(height: 2),
                      const Text('Output level attenuation buffer',
                          style: TextStyle(color: _textDark, fontSize: 12)),
                    ],
                  ),
                ),
                SizedBox(
                  width: 90,
                  child: ModernAudioKnob(
                    label: 'SAFETY',
                    value: _safetyAttenuationDb,
                    min: -6.0,
                    max: 0.0,
                    activeColor: _primary,
                    valueFormatter: (v) => '${v.toStringAsFixed(1)} dB',
                    onChanged: (val) {
                      setState(() => _safetyAttenuationDb = val);
                      _persistSpeakerProtectionSettings();
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildEqualizerCard({bool isMobile = false}) {
    return _buildCard(
      isMobile: isMobile,
      children: [
        Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _primary.withAlpha(25),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.settings_input_composite,
                        color: _primary, size: 24),
                  ),
                  const SizedBox(width: 16),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Graphic Equalizer',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w500)),
                        SizedBox(height: 4),
                        Text('Choose number of frequency bands',
                            style: TextStyle(color: _textDark, fontSize: 13)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Container(
                height: 44,
                decoration: BoxDecoration(
                  color: Colors.black26,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () async {
                          setState(() => _eqBandCount = 10);
                          final state =
                              await AppStateService.instance.loadEqBands();
                          await AppStateService.instance.saveEqBands(
                            enabled: state.enabled,
                            preset: state.preset,
                            gains: List.filled(10, 0.0),
                            preampDb: state.preampDb,
                            bandCount: 10,
                          );
                        },
                        child: Container(
                          decoration: BoxDecoration(
                            color: _eqBandCount == 10
                                ? _primary
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            '10-Band',
                            style: TextStyle(
                              color:
                                  _eqBandCount == 10 ? Colors.white : _textDark,
                              fontWeight: _eqBandCount == 10
                                  ? FontWeight.w600
                                  : FontWeight.normal,
                            ),
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: GestureDetector(
                        onTap: () async {
                          setState(() => _eqBandCount = 16);
                          final state =
                              await AppStateService.instance.loadEqBands();
                          await AppStateService.instance.saveEqBands(
                            enabled: state.enabled,
                            preset: state.preset,
                            gains: List.filled(16, 0.0),
                            preampDb: state.preampDb,
                            bandCount: 16,
                          );
                        },
                        child: Container(
                          decoration: BoxDecoration(
                            color: _eqBandCount == 16
                                ? _primary
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            '16-Band',
                            style: TextStyle(
                              color:
                                  _eqBandCount == 16 ? Colors.white : _textDark,
                              fontWeight: _eqBandCount == 16
                                  ? FontWeight.w600
                                  : FontWeight.normal,
                            ),
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: GestureDetector(
                        onTap: () async {
                          setState(() => _eqBandCount = 32);
                          final state =
                              await AppStateService.instance.loadEqBands();
                          await AppStateService.instance.saveEqBands(
                            enabled: state.enabled,
                            preset: state.preset,
                            gains: List.filled(32, 0.0),
                            preampDb: state.preampDb,
                            bandCount: 32,
                          );
                        },
                        child: Container(
                          decoration: BoxDecoration(
                            color: _eqBandCount == 32
                                ? _primary
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            '32-Band',
                            style: TextStyle(
                              color:
                                  _eqBandCount == 32 ? Colors.white : _textDark,
                              fontWeight: _eqBandCount == 32
                                  ? FontWeight.w600
                                  : FontWeight.normal,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildVisualizationCard({bool isMobile = false}) {
    return _buildCard(
      isMobile: isMobile,
      children: [
        SwitchListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          secondary: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(10),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.bar_chart, color: Colors.white70, size: 20),
          ),
          title: const Text('Realtime Analyzer',
              style:
                  TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
          subtitle: const Text('Show audio spectrum in EQ screen',
              style: TextStyle(color: _textDark, fontSize: 12)),
          value: widget.analyzerEnabled,
          activeThumbColor: _primary,
          onChanged: widget.onAnalyzerEnabledChanged,
        ),
        if (widget.analyzerEnabled) ...[
          const Divider(color: Colors.white10, height: 1),
          Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Visualization Type',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w500)),
                const SizedBox(height: 16),
                Container(
                  height: 44,
                  decoration: BoxDecoration(
                    color: Colors.black26,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: () => widget.onAnalyzerTypeChanged('bar'),
                          child: Container(
                            decoration: BoxDecoration(
                              color: widget.analyzerType == 'bar'
                                  ? _primary
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              'Bar',
                              style: TextStyle(
                                color: widget.analyzerType == 'bar'
                                    ? Colors.white
                                    : _textDark,
                                fontWeight: widget.analyzerType == 'bar'
                                    ? FontWeight.w600
                                    : FontWeight.normal,
                              ),
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        child: GestureDetector(
                          onTap: () => widget.onAnalyzerTypeChanged('area'),
                          child: Container(
                            decoration: BoxDecoration(
                              color: widget.analyzerType == 'area'
                                  ? _primary
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              'Area',
                              style: TextStyle(
                                color: widget.analyzerType == 'area'
                                    ? Colors.white
                                    : _textDark,
                                fontWeight: widget.analyzerType == 'area'
                                    ? FontWeight.w600
                                    : FontWeight.normal,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(color: Colors.white10, height: 1),
          Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Spectrum Visualizer Style',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w500)),
                const SizedBox(height: 4),
                const Text('Style for the RTA spectrum analyzer bars',
                    style: TextStyle(color: _textDark, fontSize: 12)),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final entry in {
                      'neon': ('Neon', Icons.auto_awesome),
                      'fire': ('Fire', Icons.local_fire_department),
                      'minimal': ('Minimal', Icons.remove),
                      'pill': ('Pill', Icons.lens),
                    }.entries)
                      GestureDetector(
                        onTap: () => widget.onSpectrumStyleChanged(entry.key),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          decoration: BoxDecoration(
                            color: widget.spectrumStyle == entry.key
                                ? _primary
                                : Colors.black26,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: widget.spectrumStyle == entry.key
                                  ? _primary
                                  : Colors.white10,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(entry.value.$2, size: 16,
                                  color: widget.spectrumStyle == entry.key
                                      ? Colors.white
                                      : _textDark),
                              const SizedBox(width: 6),
                              Text(
                                entry.value.$1,
                                style: TextStyle(
                                  color: widget.spectrumStyle == entry.key
                                      ? Colors.white
                                      : _textDark,
                                  fontWeight: widget.spectrumStyle == entry.key
                                      ? FontWeight.w600
                                      : FontWeight.normal,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const Divider(color: Colors.white10, height: 1),
          SwitchListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            activeThumbColor: Colors.white,
            activeTrackColor: Color(0xFF137fec),
            inactiveThumbColor: Colors.white70,
            inactiveTrackColor: Colors.white10,
            title: const Text('Auto Fit', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
            subtitle: const Text('Dynamically adjust Y-axis scale', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12)),
            value: widget.analyzerAutoFit,
            onChanged: widget.onAnalyzerAutoFitChanged,
          ),
          const Divider(color: Colors.white10, height: 1),
          SwitchListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            activeThumbColor: Colors.white,
            activeTrackColor: Color(0xFF137fec),
            inactiveThumbColor: Colors.white70,
            inactiveTrackColor: Colors.white10,
            title: const Text('Show Grids', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
            value: widget.analyzerShowGrids,
            onChanged: widget.onAnalyzerShowGridsChanged,
          ),
          const Divider(color: Colors.white10, height: 1),
          SwitchListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            activeThumbColor: Colors.white,
            activeTrackColor: Color(0xFF137fec),
            inactiveThumbColor: Colors.white70,
            inactiveTrackColor: Colors.white10,
            title: const Text('Log Scale', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
            subtitle: const Text('Logarithmic decibel response curve', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12)),
            value: widget.analyzerLogScale,
            onChanged: widget.onAnalyzerLogScaleChanged,
          ),
          const Divider(color: Colors.white10, height: 1),
          // Sample Size
          ListTile(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            leading: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white.withAlpha(10),
                shape: BoxShape.circle,
              ),
              child:
                  const Icon(Icons.data_array, color: Colors.white70, size: 20),
            ),
            title: const Text('Sample Size',
                style: TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w500)),
            trailing: SizedBox(
              width: 150,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Expanded(
                    child: Text(
                      widget.analyzerSampleSize.toString(),
                      style: const TextStyle(color: _textDark, fontSize: 14),
                      textAlign: TextAlign.right,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(Icons.chevron_right, color: _textDark, size: 20),
                ],
              ),
            ),
            onTap: () => _showAnalyzerSampleSizeDialog(),
          ),
        ],
      ],
    );
  }

  Widget _buildPlaybackCard({bool isMobile = false}) {
    return _buildCard(
      isMobile: isMobile,
      children: [
        // Gapless
        SwitchListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          activeThumbColor: Colors.white,
          activeTrackColor: _primary,
          inactiveThumbColor: Colors.white70,
          inactiveTrackColor: Colors.white10,
          title: const Text('Gapless Playback',
              style:
                  TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
          secondary: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(10),
              shape: BoxShape.circle,
            ),
            child:
                const Icon(Icons.queue_music, color: Colors.white70, size: 20),
          ),
          value: _gaplessPlayback,
          onChanged: (v) {
            setState(() => _gaplessPlayback = v);
            _persistUiSettings();
          },
        ),
        const Divider(color: Colors.white10, height: 1),
        // Crossfade
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.white.withAlpha(10),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.tune,
                            color: Colors.white70, size: 20),
                      ),
                      const SizedBox(width: 16),
                      const Text('Crossfade',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w500)),
                    ],
                  ),
                  Switch(
                      activeThumbColor: Colors.white,
                      activeTrackColor: _primary,
                      inactiveThumbColor: Colors.white70,
                      inactiveTrackColor: Colors.white10,
                      value: widget.crossfadeEnabled,
                      onChanged: (v) {
                        widget.onCrossfadeEnabledChanged(v);
                        widget.player.setCrossfadeEnabled(v);
                      }),
                ],
              ),
              const SizedBox(height: 16),
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 4,
                  activeTrackColor: _primary,
                  inactiveTrackColor: Colors.white10,
                  thumbColor: Colors.white,
                  disabledActiveTrackColor: _primary.withAlpha(100),
                  disabledInactiveTrackColor: Colors.white10.withAlpha(50),
                  disabledThumbColor: Colors.white54,
                ),
                child: Slider(
                  value: widget.crossfadeDurationMs / 1000.0,
                  min: 0,
                  max: 12,
                  divisions: 24, // 0.5s increments
                  onChanged: widget.crossfadeEnabled
                      ? (v) {
                          widget
                              .onCrossfadeDurationMsChanged((v * 1000).toInt());
                        }
                      : null,
                  onChangeEnd: widget.crossfadeEnabled
                      ? (v) {
                          widget.player
                              .setCrossfadeDurationMs((v * 1000).toInt());
                        }
                      : null,
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Off',
                      style: TextStyle(color: _textDark, fontSize: 12)),
                  Text(
                      '${(widget.crossfadeDurationMs / 1000).toStringAsFixed(1)}s',
                      style: TextStyle(
                          color: widget.crossfadeEnabled ? _primary : _textDark,
                          fontSize: 12,
                          fontWeight: FontWeight.bold)),
                  const Text('12s',
                      style: TextStyle(color: _textDark, fontSize: 12)),
                ],
              )
            ],
          ),
        ),
        const Divider(color: Colors.white10, height: 1),
        // Normalize Volume
        SwitchListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          activeThumbColor: Colors.white,
          activeTrackColor: _primary,
          inactiveThumbColor: Colors.white70,
          inactiveTrackColor: Colors.white10,
          title: const Text('Normalize Volume',
              style:
                  TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
          secondary: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(10),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.bar_chart, color: Colors.white70, size: 20),
          ),
          value: _normalizeVolume,
          onChanged: (v) {
            setState(() => _normalizeVolume = v);
            _persistUiSettings();
          },
        ),
      ],
    );
  }

  Widget _buildStorageCard({bool isMobile = false}) {
    return _buildCard(
      isMobile: isMobile,
      children: [
        SwitchListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          activeThumbColor: Colors.white,
          activeTrackColor: _primary,
          inactiveThumbColor: Colors.white70,
          inactiveTrackColor: Colors.white10,
          title: const Text('Stream over Wi-Fi Only',
              style:
                  TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
          secondary: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(10),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.wifi, color: Colors.white70, size: 20),
          ),
          value: _streamOverWifi,
          onChanged: (v) {
            setState(() => _streamOverWifi = v);
            _persistUiSettings();
          },
        ),
        const Divider(color: Colors.white10, height: 1),
        ListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          leading: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(10),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.dns, color: Colors.white70, size: 20),
          ),
          title: const Text('Audio Cache',
              style:
                  TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
          trailing: const Text('145 MB',
              style: TextStyle(color: _textDark, fontSize: 14)),
        ),
        InkWell(
          onTap: () {
            // clear cache
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text('Audio cache cleared'),
                backgroundColor: _cardDark));
          },
          child: const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Center(
              child: Text('Clear Audio Cache',
                  style: TextStyle(
                      color: Colors.redAccent,
                      fontSize: 15,
                      fontWeight: FontWeight.bold)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAboutCard(BuildContext context, {bool isMobile = false}) {
    return _buildCard(
      isMobile: isMobile,
      children: [
        ListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          leading: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(10),
              shape: BoxShape.circle,
            ),
            child:
                const Icon(Icons.info_outline, color: Colors.white70, size: 20),
          ),
          title: const Text('Version',
              style:
                  TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
          trailing: const Text('1.0.0',
              style: TextStyle(color: _textDark, fontSize: 14)),
        ),
        const Divider(color: Colors.white10, height: 1),
        ListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          leading: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(10),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.policy_outlined,
                color: Colors.white70, size: 20),
          ),
          title: const Text('Open Source Licenses',
              style:
                  TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
          trailing: const Icon(Icons.chevron_right, color: _textDark, size: 20),
          onTap: () {
            showLicensePage(
              context: context,
              applicationName: 'SautiPlay',
              applicationVersion: '1.0.0',
            );
          },
        ),
      ],
    );
  }

  Widget _buildDebugAndLogsCard({bool isMobile = false}) {
    return _buildCard(
      isMobile: isMobile,
      children: [
        SwitchListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          activeThumbColor: Colors.white,
          activeTrackColor: _primary,
          inactiveThumbColor: Colors.white70,
          inactiveTrackColor: Colors.white10,
          title: Text(
              isMobile
                  ? 'Allow invalid TLS certs'
                  : 'Allow invalid TLS certs (test only)',
              style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w500,
                  fontSize: 14)),
          secondary: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(10),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.security, color: Colors.white70, size: 20),
          ),
          value: widget.allowInvalidTls,
          onChanged: widget.onAllowInvalidTlsChanged,
        ),
        const Divider(color: Colors.white10, height: 1),
        ListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          leading: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(10),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.refresh, color: Colors.white70, size: 20),
          ),
          title: const Text('Poll Native Error',
              style:
                  TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
          trailing: const Icon(Icons.chevron_right, color: _textDark, size: 20),
          onTap: widget.onPollError,
        ),
        const Divider(color: Colors.white10, height: 1),
        ListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          leading: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(10),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.cleaning_services_outlined,
                color: Colors.white70, size: 20),
          ),
          title: const Text('Clear Native Error',
              style:
                  TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
          trailing: const Icon(Icons.chevron_right, color: _textDark, size: 20),
          onTap: widget.onClearNativeError,
        ),
        const Divider(color: Colors.white10, height: 1),
        Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ValueListenableBuilder<int>(
              valueListenable: widget.logUpdateNotifier,
              builder: (context, _, __) {
                return ExpansionTile(
                  tilePadding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  leading: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white.withAlpha(10),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.article_outlined,
                        color: Colors.white70, size: 20),
                  ),
                  title: const Text('App Logs',
                      style: TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w500)),
                  trailing: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: _primary.withAlpha(50),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text('${widget.logs.length}',
                        style: const TextStyle(
                            color: _primary,
                            fontSize: 12,
                            fontWeight: FontWeight.bold)),
                  ),
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16.0, vertical: 8.0),
                      child: Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () async {
                                if (widget.logs.isEmpty) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                          content: Text('No logs to copy')));
                                  return;
                                }
                                // import 'package:flutter/services.dart'; is needed in this file or we can just use the framework's Clipboard
                                final text = widget.logs.reversed.join('\n');
                                await Clipboard.setData(
                                    ClipboardData(text: text));
                                if (!context.mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                        content: Text(
                                            'Copied ${widget.logs.length} lines'),
                                        backgroundColor: _cardDark));
                              },
                              icon: const Icon(Icons.copy, size: 18),
                              label: const Text('Copy'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: widget.onClearLogs,
                              icon: const Icon(Icons.delete_sweep, size: 18),
                              label: const Text('Clear'),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      height: 300,
                      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      decoration: BoxDecoration(
                        color: Colors.black26,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: widget.logs.isEmpty
                          ? const Center(
                              child: Text('No logs yet',
                                  style: TextStyle(color: _textDark)))
                          : ListView.builder(
                              padding: const EdgeInsets.all(12),
                              itemCount: widget.logs.length,
                              itemBuilder: (context, index) {
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 6.0),
                                  child: SelectableText(
                                    widget.logs[index],
                                    style: const TextStyle(
                                        color: _textDark,
                                        fontSize: 12,
                                        fontFamily: 'monospace'),
                                  ),
                                );
                              },
                            ),
                    )
                  ],
                );
              }),
        ),
      ],
    );
  }

  // --- Dialogs ---

  String _getResampleAlgorithmName(int index) {
    switch (index) {
      case 0:
        return 'Miniaudio Linear (Fastest)';
      case 1:
        return 'SRC Sinc Best Quality';
      case 2:
        return 'SRC Sinc Medium Quality';
      case 3:
        return 'SRC Sinc Fastest';
      case 4:
        return 'SRC Zero Order Hold';
      case 5:
        return 'SRC Linear';
      default:
        return 'Miniaudio Linear (Fastest)';
    }
  }

  String _getOversamplingName(int factor) {
    switch (factor) {
      case 2:
        return '2x (High Quality)';
      case 4:
        return '4x (Ultra HD)';
      default:
        return 'Off (1x)';
    }
  }

  void _showOversamplingDialog() {
    final options = [
      {'factor': 1, 'name': 'Off (1x)', 'subtitle': 'Low CPU usage, native sample rate'},
      {'factor': 2, 'name': '2x Oversampling', 'subtitle': 'High Quality (Reduces aliasing in saturator/limiter)'},
      {'factor': 4, 'name': '4x Oversampling', 'subtitle': 'Ultra HD (Maximum anti-aliasing purity)'},
    ];

    showModalBottomSheet(
      context: context,
      backgroundColor: _cardDark,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Padding(
            padding: EdgeInsets.all(20.0),
            child: Text('DSP Anti-Aliasing Oversampling',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold)),
          ),
          for (final item in options)
            RadioListTile<int>(
              title: Text(item['name'] as String,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
              subtitle: Text(item['subtitle'] as String,
                  style: const TextStyle(color: _textDark, fontSize: 12)),
              value: item['factor'] as int,
              groupValue: _dspOversampling,
              activeColor: _primary,
              onChanged: (val) {
                if (val != null) {
                  setState(() => _dspOversampling = val);
                  widget.player.setViperOversampling(val);
                  AppStateService.instance.saveDspOversampling(val);
                  Navigator.pop(ctx);
                }
              },
            ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  void _showResampleAlgorithmDialog() {
    showModalBottomSheet(
        context: context,
        backgroundColor: _cardDark,
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        builder: (ctx) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Padding(
                  padding: EdgeInsets.all(20.0),
                  child: Text('Resampling Algorithm',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold)),
                ),
                for (int i = 0; i <= 5; i++)
                  _buildRadioOption(_getResampleAlgorithmName(i),
                      _getResampleAlgorithmName(_resampleAlgorithm), (v) {
                    setState(() => _resampleAlgorithm = i);
                    widget.player.setEngineResampleAlgorithm(i);
                    _persistUiSettings();
                    Navigator.pop(ctx);
                  }),
                const SizedBox(height: 20),
              ],
            ));
  }

  void _showAnalyzerSampleSizeDialog() {
    showModalBottomSheet(
        context: context,
        backgroundColor: _cardDark,
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        builder: (ctx) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Padding(
                  padding: EdgeInsets.all(20.0),
                  child: Text('Sample Size (FFT)',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold)),
                ),
                for (final size in [256, 512, 1024, 2048, 4096, 8192])
                  _buildRadioOption(
                      size.toString(), widget.analyzerSampleSize.toString(),
                      (v) {
                    widget.onAnalyzerSampleSizeChanged(size);
                    Navigator.pop(ctx);
                  }),
                const SizedBox(height: 20),
              ],
            ));
  }

  Future<void> _showReplayGainModeDialog() async {
    return showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: _cardDark,
          title: const Text('ReplayGain Mode', style: TextStyle(color: Colors.white)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              RadioListTile<ReplayGainMode>(
                title: const Text('None', style: TextStyle(color: Colors.white)),
                activeColor: _primary,
                value: ReplayGainMode.none,
                groupValue: _replayGainMode,
                onChanged: (val) {
                  setState(() => _replayGainMode = val!);
                  _persistReplayGainSettings();
                  Navigator.pop(context);
                },
              ),
              RadioListTile<ReplayGainMode>(
                title: const Text('Track', style: TextStyle(color: Colors.white)),
                activeColor: _primary,
                value: ReplayGainMode.track,
                groupValue: _replayGainMode,
                onChanged: (val) {
                  setState(() => _replayGainMode = val!);
                  _persistReplayGainSettings();
                  Navigator.pop(context);
                },
              ),
              RadioListTile<ReplayGainMode>(
                title: const Text('Album', style: TextStyle(color: Colors.white)),
                activeColor: _primary,
                value: ReplayGainMode.album,
                groupValue: _replayGainMode,
                onChanged: (val) {
                  setState(() => _replayGainMode = val!);
                  _persistReplayGainSettings();
                  Navigator.pop(context);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  String _getDitherModeName(int mode) {
    switch (mode) {
      case 0:
        return 'None';
      case 1:
        return 'Rectangle (RPDF)';
      case 2:
        return 'Triangle (TPDF)';
      case 3:
        return 'Lipshitz';
      case 4:
        return 'F-Weighted';
      case 5:
        return 'Modified E-Weighted';
      case 6:
        return 'Shibata';
      case 7:
        return 'Low Shibata';
      case 8:
        return 'High Shibata';
      default:
        return 'None';
    }
  }

  Future<void> _showDitherModeDialog() async {
    final modes = [
      {'id': 0, 'name': 'None', 'subtitle': 'No dithering applied'},
      {'id': 1, 'name': 'Rectangle (RPDF)', 'subtitle': 'Simple flat dither'},
      {'id': 2, 'name': 'Triangle (TPDF)', 'subtitle': 'Standard flat dither (Recommended)'},
      {'id': 3, 'name': 'Lipshitz', 'subtitle': 'Classic 5th-order noise-shaped'},
      {'id': 4, 'name': 'F-Weighted', 'subtitle': 'Midrange cut noise-shaped (Acoustic/Vocal)'},
      {'id': 5, 'name': 'Modified E-Weighted', 'subtitle': 'Peak-safe noise-shaped (Pop/Rock)'},
      {'id': 6, 'name': 'Shibata', 'subtitle': 'Standard audiophile noise-shaped'},
      {'id': 7, 'name': 'Low Shibata', 'subtitle': 'Gentle audiophile noise-shaped (Safest)'},
      {'id': 8, 'name': 'High Shibata', 'subtitle': 'Steep audiophile noise-shaped'},
    ];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: _cardDark,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.75,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(20.0),
              child: Text('Dither Mode',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold)),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: modes.length,
                itemBuilder: (context, i) {
                  final item = modes[i];
                  final id = item['id'] as int;
                  final name = item['name'] as String;
                  final subtitle = item['subtitle'] as String;
                  return RadioListTile<int>(
                    title: Text(name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
                    subtitle: Text(subtitle, style: const TextStyle(color: _textDark, fontSize: 12)),
                    value: id,
                    groupValue: _ditherMode,
                    activeColor: _primary,
                    onChanged: (val) {
                      if (val != null) {
                        setState(() => _ditherMode = val);
                        widget.player.setEngineDitherMode(val);
                        _persistUiSettings();
                        Navigator.pop(ctx);
                      }
                    },
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  void _showOutputFormatDialog() {
    showModalBottomSheet(
        context: context,
        backgroundColor: _cardDark,
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        builder: (ctx) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Padding(
                  padding: EdgeInsets.all(20.0),
                  child: Text('Engine Output Format',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold)),
                ),
                for (final fmt in [
                  AudioFormat.f32,
                  AudioFormat.s32,
                  AudioFormat.s24,
                  AudioFormat.s16,
                  AudioFormat.u8
                ])
                  _buildRadioOption(_formatAudioDepth(fmt),
                      _formatAudioDepth(widget.outputFormat), (v) {
                    widget.onOutputFormatChanged(fmt);
                    widget.player.setOutputFormat(fmt);
                    Navigator.pop(ctx);
                  }),
                const SizedBox(height: 20),
              ],
            ));
  }

  void _showSampleRateDialog() {
    final rates = [0, 44100, 48000, 96000, 192000];
    showModalBottomSheet(
        context: context,
        backgroundColor: _cardDark,
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        builder: (ctx) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Padding(
                  padding: EdgeInsets.all(20.0),
                  child: Text('Engine Sample Rate',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold)),
                ),
                ...rates.map((r) => _buildRadioOption(
                        r == 0 ? 'Native' : '$r Hz',
                        widget.outputSampleRate == 0
                            ? 'Native'
                            : '${widget.outputSampleRate} Hz', (v) {
                      final val = v == 'Native'
                          ? 0
                          : int.parse(v!.replaceAll(' Hz', ''));
                      widget.onOutputSampleRateChanged(val);
                      widget.player.setOutputSampleRate(val);
                      Navigator.pop(ctx);
                    })),
                const SizedBox(height: 20),
              ],
            ));
  }

  void _showChannelsDialog() {
    showModalBottomSheet(
        context: context,
        backgroundColor: _cardDark,
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        builder: (ctx) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Padding(
                  padding: EdgeInsets.all(20.0),
                  child: Text('Engine Output Channels',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold)),
                ),
                _buildRadioOption(
                    'Mono', widget.outputChannels == 1 ? 'Mono' : 'Stereo',
                    (v) {
                  widget.onOutputChannelsChanged(1);
                  widget.player.setOutputChannels(1);
                  Navigator.pop(ctx);
                }),
                _buildRadioOption(
                    'Stereo', widget.outputChannels == 1 ? 'Mono' : 'Stereo',
                    (v) {
                  widget.onOutputChannelsChanged(2);
                  widget.player.setOutputChannels(2);
                  Navigator.pop(ctx);
                }),
                const SizedBox(height: 20),
              ],
            ));
  }

  Widget _buildRadioOption(
      String title, String groupValue, ValueChanged<String?> onChanged) {
    return RadioListTile<String>(
      title: Text(title, style: const TextStyle(color: Colors.white)),
      value: title,
      groupValue: groupValue,
      onChanged: onChanged,
      activeColor: _primary,
    );
  }

  void _showSubsonicDialog() {
    final options = [
      (0.0, 'Disabled (Off)'),
      (15.0, '15 Hz (Ultra Sub-bass)'),
      (20.0, '20 Hz (Standard Subwoofer)'),
      (25.0, '25 Hz (Recommended for Small Woofers)'),
      (30.0, '30 Hz (Bookshelf / Mobile Speakers)'),
    ];

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: _cardDark,
          title: const Text('Subsonic High-Pass Filter',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: options.map((opt) {
              final selected = (opt.$1 == _subsonicCutoffHz);
              return RadioListTile<double>(
                value: opt.$1,
                groupValue: _subsonicCutoffHz,
                activeColor: _primary,
                title: Text(opt.$2,
                    style: TextStyle(
                        color: selected ? Colors.white : _textDark,
                        fontWeight: selected ? FontWeight.w600 : FontWeight.normal)),
                onChanged: (val) {
                  if (val != null) {
                    setState(() => _subsonicCutoffHz = val);
                    _persistSpeakerProtectionSettings();
                  }
                  Navigator.pop(context);
                },
              );
            }).toList(),
          ),
        );
      },
    );
  }

  void _showUltrasonicDialog() {
    final options = [
      (24000.0, 'Disabled (Off)'),
      (22000.0, '22 kHz (Hi-Res Limit)'),
      (20000.0, '20 kHz (Standard Human Hearing)'),
      (18000.0, '18 kHz (Tweeter Guard)'),
    ];

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: _cardDark,
          title: const Text('Ultrasonic Low-Pass Guard',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: options.map((opt) {
              final selected = (opt.$1 == _ultrasonicCutoffHz);
              return RadioListTile<double>(
                value: opt.$1,
                groupValue: _ultrasonicCutoffHz,
                activeColor: _primary,
                title: Text(opt.$2,
                    style: TextStyle(
                        color: selected ? Colors.white : _textDark,
                        fontWeight: selected ? FontWeight.w600 : FontWeight.normal)),
                onChanged: (val) {
                  if (val != null) {
                    setState(() => _ultrasonicCutoffHz = val);
                    _persistSpeakerProtectionSettings();
                  }
                  Navigator.pop(context);
                },
              );
            }).toList(),
          ),
        );
      },
    );
  }
}
