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

  @override
  void initState() {
    super.initState();
    _loadUiSettings();
  }

  Future<void> _loadUiSettings() async {
    final saved = await AppStateService.instance.loadUiSettings();
    final eqSaved = await AppStateService.instance.loadEqBands();
    final rgSaved = await AppStateService.instance.loadReplayGainSettings();
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
    });
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
                        _buildSectionTitle('AUDIO QUALITY'),
                        _buildAudioQualityCard(),
                        const SizedBox(height: 24),
                        _buildSectionTitle('PLAYBACK'),
                        _buildPlaybackCard(),
                        const SizedBox(height: 24),
                        _buildSectionTitle('EQUALIZER'),
                        _buildEqualizerCard(),
                        const SizedBox(height: 24),
                        _buildSectionTitle('VISUALIZATION'),
                        _buildVisualizationCard(),
                        const SizedBox(height: 24),
                        _buildSectionTitle('STORAGE & DATA'),
                        _buildStorageCard(),
                        const SizedBox(height: 24),
                        _buildSectionTitle('ABOUT & LICENSES'),
                        _buildAboutCard(context),
                        const SizedBox(height: 24),
                        _buildSectionTitle('DEBUG & LOGS'),
                        _buildDebugAndLogsCard(),
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

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 8.0),
      child: Text(
        title,
        style: const TextStyle(
          color: _textDark,
          fontSize: 12,
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

  Widget _buildCard({required List<Widget> children}) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16.0),
      decoration: BoxDecoration(
        color: _cardDark,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }

  Widget _buildAudioQualityCard() {
    return _buildCard(
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
                    _ditherMode == 0
                        ? 'None'
                        : _ditherMode == 1
                            ? 'Rectangle'
                            : 'Triangle',
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
          title: const Text('True Bit-Perfect Output',
              style:
                  TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
          subtitle: const Text('Bypass OS Mixer & DSP. Forces exclusive mode.',
              style: TextStyle(color: _textDark, fontSize: 12)),
          value: widget.exclusiveMode,
          activeThumbColor: _primary,
          onChanged: (val) async {
            widget.player.setExclusiveMode(val);
            await Future.delayed(const Duration(milliseconds: 150));
            final actual = await widget.player.getExclusiveMode();
            widget.onExclusiveModeChanged(actual);
            if (val && !actual) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                      content: Text(
                          'Hardware rejected Exclusive Mode. Falling back! Try changing Sample Rate/Format.',
                          style: TextStyle(color: Colors.white))),
                );
              }
            } else if (val && actual) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                      content: Text('Exclusive Mode Enabled! DSP bypassed.',
                          style: TextStyle(color: Colors.white))),
                );
              }
            }
          },
        ),
      ],
    );
  }

  Widget _buildEqualizerCard() {
    return _buildCard(
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

  Widget _buildVisualizationCard() {
    return _buildCard(
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

  Widget _buildPlaybackCard() {
    return _buildCard(
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

  Widget _buildStorageCard() {
    return _buildCard(
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

  Widget _buildAboutCard(BuildContext context) {
    return _buildCard(
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

  Widget _buildDebugAndLogsCard() {
    return _buildCard(
      children: [
        SwitchListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          activeThumbColor: Colors.white,
          activeTrackColor: _primary,
          inactiveThumbColor: Colors.white70,
          inactiveTrackColor: Colors.white10,
          title: const Text('Allow invalid TLS certs (test only)',
              style: TextStyle(
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

  Future<void> _showDitherModeDialog() async {
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
                  child: Text('Dither Mode',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold)),
                ),
                _buildRadioOption(
                    'None',
                    _ditherMode == 0
                        ? 'None'
                        : _ditherMode == 1
                            ? 'Rectangle'
                            : 'Triangle (Best)', (v) {
                  setState(() => _ditherMode = 0);
                  widget.player.setEngineDitherMode(0);
                  Navigator.pop(ctx);
                }),
                _buildRadioOption(
                    'Rectangle',
                    _ditherMode == 0
                        ? 'None'
                        : _ditherMode == 1
                            ? 'Rectangle'
                            : 'Triangle (Best)', (v) {
                  setState(() => _ditherMode = 1);
                  widget.player.setEngineDitherMode(1);
                  Navigator.pop(ctx);
                }),
                _buildRadioOption(
                    'Triangle (Best)',
                    _ditherMode == 0
                        ? 'None'
                        : _ditherMode == 1
                            ? 'Rectangle'
                            : 'Triangle (Best)', (v) {
                  setState(() => _ditherMode = 2);
                  widget.player.setEngineDitherMode(2);
                  Navigator.pop(ctx);
                }),
                const SizedBox(height: 20),
              ],
            ));
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
}
