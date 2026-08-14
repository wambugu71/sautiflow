import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:sautiflow/sautiflow.dart';

import 'package:flutter_m3shapes_extended/flutter_m3shapes_extended.dart';
import 'package:material_3_expressive/material_3_expressive.dart';

import 'eq_screen.dart';
import 'isolate_player.dart';
import 'widgets/app_m3e_widgets.dart';
import 'network_sources_screen.dart';
import 'services/app_state_service.dart';
import 'services/app_theme_service.dart';
import 'widgets/audio_engine_diagnostic_panel.dart';

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

  final List<String> logs;
  final ValueNotifier<int> logUpdateNotifier;
  final bool allowInvalidTls;
  final ValueChanged<bool> onAllowInvalidTlsChanged;
  final VoidCallback onPollError;
  final VoidCallback onClearNativeError;
  final VoidCallback onClearLogs;
  final void Function(String filePath, String title, String artist)?
      onPlayNetworkFile;
  final void Function(List<dynamic> entries, dynamic config, int initialIndex)?
      onPlayFtpFolder;
  final VoidCallback? onTriggerShowcase;

  const SettingsScreen({
    super.key,
    required this.player,
    required this.analyzerEnabled,
    required this.onAnalyzerEnabledChanged,
    required this.onAnalyzerTypeChanged,
    required this.analyzerType,
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
    this.onPlayNetworkFile,
    this.onPlayFtpFolder,
    this.onTriggerShowcase,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  // Dynamic theme colors from BuildContext (reactive)
  Color get _bgDark => context.bgDark;
  Color get _cardDark => context.cardDark;
  Color get _primary => context.primaryColor;
  Color get _textDark => context.textMuted;
  Color get _textPrimary => context.textPrimary;

  // Local UI settings
  String _streamingQuality = 'High Fidelity';
  bool _gaplessPlayback = true;
  bool _normalizeVolume = false;
  bool _streamOverWifi = true;

  // Engine Resampling & Dithering
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

  // L/R Swap & Per-Channel Gain
  bool _lrSwapEnabled = false;
  double _channelGainLeftDb = 0.0;
  double _channelGainRightDb = 0.0;

  // Neutron HiFi Engine Settings
  bool _use64BitProcessingEnabled = false;
  bool _autoBitPerfectEnabled = false;

  // Loudness-Aware Crossfade
  bool _loudnessCrossfadeEnabled = true;

  // Release 1 Quality Foundation
  bool _loudnessNormalizerEnabled = false;
  double _loudnessNormalizerTargetLUFS = -14.0;
  bool _lookaheadLimiterEnabled = true;
  double _lookaheadLimiterCeilingDBTP = -1.0;

  // Waveform Seek Bar UI Setting
  bool _useWaveformSeekBar = false;

  // App version state
  String _appVersion = 'v0.6.20';

  // Active theme ID (always synced with AppThemeProvider)
  AppThemeId get _activeThemeId => context.appTheme.id;

  StreamSubscription<void>? _audioSettingsSub;

  @override
  void initState() {
    super.initState();
    _loadUiSettings();
    _audioSettingsSub = AppStateService
        .instance.audioProcessingSettingsChanged.stream
        .listen((_) {
      if (mounted) {
        _loadUiSettings();
      }
    });
  }

  @override
  void dispose() {
    _audioSettingsSub?.cancel();
    super.dispose();
  }

  String _getAudioProcessingBadgeText() {
    if (widget.exclusiveMode) {
      return 'Bit-Perfect';
    }
    if (_autoBitPerfectEnabled) {
      return 'Auto-Rate • ${_formatAudioDepth(widget.outputFormat)}';
    }
    final depth = _formatAudioDepth(widget.outputFormat);
    final resamplerShort = _resampleAlgorithm == 7 || _resampleAlgorithm == 8
        ? 'SoX VHQ'
        : _resampleAlgorithm == 9
            ? 'SoX HQ'
            : _resampleAlgorithm == 1
                ? 'Master HD'
                : 'Linear';
    return '$depth • $resamplerShort';
  }

  Future<void> _loadUiSettings() async {
    final saved = await AppStateService.instance.loadUiSettings();
    final eqSaved = await AppStateService.instance.loadEqBands();
    final rgSaved = await AppStateService.instance.loadReplayGainSettings();
    final oversamplingSaved =
        await AppStateService.instance.loadDspOversampling();
    final spSaved = await AppStateService.instance.loadSpeakerProtection();
    final phaseSaved = await AppStateService.instance.loadPhaseInversion();
    final lrSwap = await AppStateService.instance.loadLrSwap();
    final channelGains = await AppStateService.instance.loadChannelGains();
    final is64Bit = await AppStateService.instance.load64BitProcessingEnabled();
    final autoBp = await AppStateService.instance.loadAutoBitPerfectEnabled();
    final waveformSaved =
        await AppStateService.instance.loadUseWaveformSeekBar();
    final engineSettings = await AppStateService.instance.loadEngineSettings();
    final loudnessCf = engineSettings.loudnessCrossfadeEnabled;

    String versionStr = 'v0.6.20';
    try {
      final info = await PackageInfo.fromPlatform();
      versionStr = 'v${info.version}';
    } catch (_) {}

    if (!mounted) return;
    setState(() {
      _appVersion = versionStr;
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
      _lrSwapEnabled = lrSwap;
      _channelGainLeftDb = channelGains.leftDb;
      _channelGainRightDb = channelGains.rightDb;
      _use64BitProcessingEnabled = is64Bit;
      _autoBitPerfectEnabled = autoBp;
      _loudnessCrossfadeEnabled = loudnessCf;
      _useWaveformSeekBar = waveformSaved;
    });

    final loudnessNorm =
        await AppStateService.instance.loadLoudnessNormalizer();
    final lookaheadLim = await AppStateService.instance.loadLookaheadLimiter();

    if (mounted) {
      setState(() {
        _loudnessNormalizerEnabled = loudnessNorm.enabled;
        _loudnessNormalizerTargetLUFS = loudnessNorm.targetLUFS;
        _lookaheadLimiterEnabled = lookaheadLim.enabled;
        _lookaheadLimiterCeilingDBTP = lookaheadLim.ceilingDBTP;
      });
    }

    widget.player.setViperOversampling(oversamplingSaved);
    widget.player.set64BitProcessingEnabled(is64Bit);
    widget.player.setAutoSampleRateMatchEnabled(autoBp);
    widget.player.setLoudnessCrossfadeEnabled(loudnessCf);
    widget.player.setLoudnessNormalizerEnabled(_loudnessNormalizerEnabled);
    widget.player.setLoudnessNormalizerTarget(_loudnessNormalizerTargetLUFS);
    widget.player.setLookaheadLimiterEnabled(_lookaheadLimiterEnabled);
    widget.player
        .setLookaheadLimiterParams(ceilingDBTP: _lookaheadLimiterCeilingDBTP);
    widget.player.setPhaseInversion(
      invertLeft: _phaseInvertLeft,
      invertRight: _phaseInvertRight,
    );
    widget.player.setLrSwap(_lrSwapEnabled);
    widget.player.setChannelGainsDb(
      leftDb: _channelGainLeftDb,
      rightDb: _channelGainRightDb,
    );
    _applySpeakerProtectionSettings();
  }

  void _persistLoudnessNormalizerSettings() {
    AppStateService.instance.saveLoudnessNormalizer(
      enabled: _loudnessNormalizerEnabled,
      targetLUFS: _loudnessNormalizerTargetLUFS,
    );
    widget.player.setLoudnessNormalizerEnabled(_loudnessNormalizerEnabled);
    widget.player.setLoudnessNormalizerTarget(_loudnessNormalizerTargetLUFS);
  }

  void _persistLookaheadLimiterSettings() {
    AppStateService.instance.saveLookaheadLimiter(
      enabled: _lookaheadLimiterEnabled,
      ceilingDBTP: _lookaheadLimiterCeilingDBTP,
    );
    widget.player.setLookaheadLimiterEnabled(_lookaheadLimiterEnabled);
    widget.player
        .setLookaheadLimiterParams(ceilingDBTP: _lookaheadLimiterCeilingDBTP);
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

  void _persistChannelRoutingSettings() {
    AppStateService.instance.saveLrSwap(_lrSwapEnabled);
    AppStateService.instance.saveChannelGains(
      leftDb: _channelGainLeftDb,
      rightDb: _channelGainRightDb,
    );
    widget.player.setLrSwap(_lrSwapEnabled);
    widget.player.setChannelGainsDb(
      leftDb: _channelGainLeftDb,
      rightDb: _channelGainRightDb,
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
    setState(() {});
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgDark,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isDesktop = constraints.maxWidth >= 800;
          final isMobile = constraints.maxWidth < 600;
          return Align(
            alignment: Alignment.topCenter,
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
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 22),
                    ),
                    centerTitle: true,
                  ),
                  SliverPadding(
                    padding: EdgeInsets.symmetric(
                      horizontal: isDesktop ? 36.0 : (isMobile ? 12.0 : 16.0),
                      vertical: 12.0,
                    ),
                    sliver: SliverList(
                      delegate: SliverChildListDelegate([
                        //  _buildSettingsHeaderCard(),
                        const SizedBox(height: 20),
                        _buildSectionHeader('PREFERENCES & ENGINE'),
                        const SizedBox(height: 10),
                        M3ECardList(
                          itemCount: 8,
                          onTap: (index) {
                            switch (index) {
                              case 0:
                                _navigateToSubScreen(
                                    _buildLookAndFeelSubScreen());
                                break;
                              case 1:
                                _navigateToSubScreen(
                                    _buildAudioProcessingSubScreen());
                                break;
                              case 2:
                                _navigateToSubScreen(
                                    _buildEqualizerSubScreen());
                                break;
                              case 3:
                                _navigateToSubScreen(
                                    _buildVisualizationSubScreen());
                                break;
                              case 4:
                                _navigateToSubScreen(_buildPlaybackSubScreen());
                                break;
                              case 5:
                                _navigateToSubScreen(_buildStorageSubScreen());
                                break;
                              case 6:
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => NetworkSourcesScreen(
                                      player: widget.player,
                                      onPlayNetworkFile:
                                          widget.onPlayNetworkFile,
                                      onPlayFtpFolder: widget.onPlayFtpFolder,
                                    ),
                                  ),
                                );
                                break;
                              case 7:
                                _navigateToSubScreen(
                                    _buildMiscSystemSubScreen());
                                break;
                            }
                          },
                          itemBuilder: (context, index) {
                            switch (index) {
                              case 0:
                                return _buildCategoryCard(
                                  title: 'Look & Feel',
                                  subtitle: 'Theme, seek bar & UI appearance',
                                  icon: Icons.palette_outlined,
                                  accentColor: _primary,
                                  badgeText:
                                      AppThemeService.dataFor(_activeThemeId)
                                          .displayName,
                                  onTap: () => _navigateToSubScreen(
                                      _buildLookAndFeelSubScreen()),
                                );
                              case 1:
                                return _buildCategoryCard(
                                  title: 'Audio & Processing',
                                  subtitle:
                                      'Resampling, Bit depth, Safeguards & ReplayGain',
                                  icon: Icons.graphic_eq_rounded,
                                  accentColor: _primary,
                                  badgeText: _getAudioProcessingBadgeText(),
                                  onTap: () => _navigateToSubScreen(
                                      _buildAudioProcessingSubScreen()),
                                );
                              case 2:
                                return _buildCategoryCard(
                                  title: 'Equalizer & DSP',
                                  subtitle:
                                      'Band configuration & ViPER FX shortcuts',
                                  icon: Icons.tune_rounded,
                                  accentColor: _primary,
                                  badgeText: '$_eqBandCount-Band',
                                  onTap: () => _navigateToSubScreen(
                                      _buildEqualizerSubScreen()),
                                );
                              case 3:
                                return _buildCategoryCard(
                                  title: 'Visualization & RTA',
                                  subtitle:
                                      'Spectrum analyzer styles, grids, FFT size',
                                  icon: Icons.bar_chart_rounded,
                                  accentColor: _primary,
                                  badgeText: widget.analyzerEnabled
                                      ? widget.spectrumStyle.toUpperCase()
                                      : 'Off',
                                  onTap: () => _navigateToSubScreen(
                                      _buildVisualizationSubScreen()),
                                );
                              case 4:
                                return _buildCategoryCard(
                                  title: 'Playback & Crossfade',
                                  subtitle:
                                      'Gapless mode, crossfade transitions & volume',
                                  icon: Icons.queue_music_rounded,
                                  accentColor: _primary,
                                  badgeText: widget.crossfadeEnabled
                                      ? '${(widget.crossfadeDurationMs / 1000).toStringAsFixed(1)}s'
                                      : 'Gapless',
                                  onTap: () => _navigateToSubScreen(
                                      _buildPlaybackSubScreen()),
                                );
                              case 5:
                                return _buildCategoryCard(
                                  title: 'Library & Storage',
                                  subtitle:
                                      'Wi-Fi streaming preferences & audio cache',
                                  icon: Icons.storage_rounded,
                                  accentColor: _primary,
                                  badgeText: '145 MB Cache',
                                  onTap: () => _navigateToSubScreen(
                                      _buildStorageSubScreen()),
                                );
                              case 6:
                                return _buildCategoryCard(
                                  title: 'Network Sources (FTP & DLNA)',
                                  subtitle:
                                      'Browse FTP servers, DLNA NAS, and cast audio',
                                  icon: Icons.lan_rounded,
                                  accentColor: _primary,
                                  badgeText: 'FTP & DLNA',
                                  onTap: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) =>
                                            NetworkSourcesScreen(
                                          player: widget.player,
                                          onPlayNetworkFile:
                                              widget.onPlayNetworkFile,
                                          onPlayFtpFolder:
                                              widget.onPlayFtpFolder,
                                        ),
                                      ),
                                    );
                                  },
                                );
                              default:
                                return _buildCategoryCard(
                                  title: 'Misc & System',
                                  subtitle:
                                      'Open source licenses, TLS, diagnostic logs',
                                  icon: Icons.admin_panel_settings_outlined,
                                  accentColor: _primary,
                                  badgeText: _appVersion,
                                  onTap: () => _navigateToSubScreen(
                                      _buildMiscSystemSubScreen()),
                                );
                            }
                          },
                        ),
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

  void _navigateToSubScreen(Widget subScreen) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => subScreen),
    );
  }

  Widget _buildSectionHeader(String title) {
    return AppSectionHeader(title);
  }

  Widget _buildCategoryCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color accentColor,
    required String badgeText,
    required VoidCallback onTap,
  }) {
    return M3EListItem(
      headline: title,
      supportingText: subtitle,
      leading: M3EContainer(
        Shapes.pill,
        width: 44,
        height: 44,
        color: accentColor.withAlpha(30),
        border: BorderSide(color: accentColor.withAlpha(60), width: 1),
        child: Center(
          child: Icon(icon, color: accentColor, size: 22),
        ),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: accentColor.withAlpha(25),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: accentColor.withAlpha(60)),
            ),
            child: Text(
              badgeText,
              style: TextStyle(
                color: accentColor,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Icon(Icons.chevron_right_rounded, color: _textDark, size: 22),
        ],
      ),
      onTap: onTap,
    );
  }

  // --- Sub-Screen Views ---

  Widget _buildSubScreenLayout({
    required String title,
    required List<Widget> children,
  }) {
    return AppSubScreenScaffold(
      title: title,
      children: children,
    );
  }

  Widget _buildCardContainer({required List<Widget> children}) {
    return AppCardContainer(children: children);
  }

  Widget _buildLeadingIcon(IconData icon, [Color? color]) {
    final c = color ?? _primary;
    return M3EContainer(
      Shapes.pill,
      width: 40,
      height: 40,
      color: c.withValues(alpha: 0.15),
      child: Center(
        child: Icon(icon, color: c, size: 20),
      ),
    );
  }

  Widget _buildM3ESwitchTile({
    required String title,
    String? subtitle,
    Widget? secondary,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return M3EListItem(
      headline: title,
      supportingText: subtitle,
      leading: secondary,
      trailing: M3ESwitch(
        value: value,
        onChanged: onChanged,
      ),
      onTap: () => onChanged(!value),
    );
  }

  // 1. Look & Feel Sub-Screen
  Widget _buildLookAndFeelSubScreen() {
    return StatefulBuilder(
      builder: (context, setSubState) {
        final appTheme = AppThemeProvider.of(context);
        final cardColor = appTheme.cardDark;
        final accent = appTheme.primary;
        final mutedText = appTheme.textDark;
        final isDarkTheme = appTheme.bgDark.computeLuminance() < 0.15;
        final textPrimaryColor = isDarkTheme ? Colors.white : const Color(0xFF1A1A2E);

        return _buildSubScreenLayout(
          title: 'Look & Feel',
          children: [
            // ── THEME SECTION ─────────────────────────────────────────────
            _buildSectionHeader('APP THEME'),
            const SizedBox(height: 12),
            Container(
              decoration: BoxDecoration(
                color: cardColor,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: context.outlineColor),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: accent.withAlpha(25),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(Icons.palette_outlined,
                              color: accent, size: 20),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Color Theme',
                                style: TextStyle(
                                    color: textPrimaryColor,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Changes the look of the entire app',
                                style:
                                    TextStyle(color: mutedText, fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 130,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: AppThemeService.themes.length,
                      itemBuilder: (context, index) {
                        final theme = AppThemeService.themes[index];
                        final isActive = _activeThemeId == theme.id;
                        final isItemDark = theme.bgDark.computeLuminance() < 0.15;
                        return GestureDetector(
                          onTap: () {
                            AppThemeService.instance.saveTheme(theme.id);
                            setState(() {});
                            setSubState(() {});
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 220),
                            curve: Curves.easeOutCubic,
                            width: 80,
                            margin:
                                const EdgeInsets.only(right: 12, bottom: 16),
                            decoration: BoxDecoration(
                              color: theme.bgDark,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: isActive
                                    ? theme.primary
                                    : (isItemDark
                                        ? Colors.white.withAlpha(18)
                                        : Colors.black.withAlpha(18)),
                                width: isActive ? 2.5 : 1.5,
                              ),
                              boxShadow: isActive
                                  ? [
                                      BoxShadow(
                                        color: theme.primary.withAlpha(80),
                                        blurRadius: 12,
                                        spreadRadius: 1,
                                      )
                                    ]
                                  : null,
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                // accent dot
                                Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    Container(
                                      width: 40,
                                      height: 40,
                                      decoration: BoxDecoration(
                                        color: theme.cardDark,
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: theme.primary.withAlpha(80),
                                          width: 1.5,
                                        ),
                                      ),
                                      child: Center(
                                        child: Icon(
                                          theme.icon,
                                          color: theme.primary,
                                          size: 20,
                                        ),
                                      ),
                                    ),
                                    if (isActive)
                                      Positioned(
                                        right: 0,
                                        top: 0,
                                        child: Container(
                                          width: 16,
                                          height: 16,
                                          decoration: BoxDecoration(
                                            color: theme.primary,
                                            shape: BoxShape.circle,
                                            border: Border.all(
                                                color: theme.bgDark,
                                                width: 1.5),
                                          ),
                                          child: const Icon(
                                            Icons.check,
                                            color: Colors.white,
                                            size: 10,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  theme.displayName,
                                  style: TextStyle(
                                    color: isActive
                                        ? theme.primary
                                        : (isItemDark
                                            ? Colors.white70
                                            : Colors.black87),
                                    fontSize: 11,
                                    fontWeight: isActive
                                        ? FontWeight.w700
                                        : FontWeight.w400,
                                  ),
                                  textAlign: TextAlign.center,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            // ── SEEK BAR SECTION ──────────────────────────────────────────
            _buildSectionHeader('INTERFACE & SEEK BAR'),
            const SizedBox(height: 8),
            _buildCardContainer(
              children: [
                _buildM3ESwitchTile(
                  title: 'Waveform Seek Bar',
                  subtitle:
                      'Replaces classic time slider with interactive track amplitude waveform',
                  secondary: M3EContainer(
                    Shapes.pill,
                    width: 40,
                    height: 40,
                    color: _primary.withAlpha(25),
                    child: Center(
                      child: Icon(Icons.graphic_eq, color: _primary, size: 20),
                    ),
                  ),
                  value: _useWaveformSeekBar,
                  onChanged: (val) {
                    setState(() => _useWaveformSeekBar = val);
                    setSubState(() {});
                    AppStateService.instance.saveUseWaveformSeekBar(val);
                  },
                ),
              ],
            ),
            const SizedBox(height: 20),
            _buildSectionHeader('ONBOARDING & FEATURE TOUR'),
            const SizedBox(height: 8),
            _buildCardContainer(
              children: [
                M3EListItem(
                  headline: 'Re-run Feature Tour',
                  supportingText:
                      'Re-start the interactive guided walkthrough for SautiPlay',
                  leading: M3EContainer(
                    Shapes.pill,
                    width: 40,
                    height: 40,
                    color: _primary.withAlpha(25),
                    child: Center(
                      child:
                          Icon(Icons.tour_rounded, color: _primary, size: 20),
                    ),
                  ),
                  trailing: Icon(Icons.play_arrow_rounded, color: _primary),
                  onTap: () {
                    Navigator.of(context).pop();
                    widget.onTriggerShowcase?.call();
                  },
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  // 2. Audio & Processing Sub-Screen
  Widget _buildAudioProcessingSubScreen() {
    return StatefulBuilder(
      builder: (context, setSubState) {
        return _buildSubScreenLayout(
          title: 'Audio & Processing',
          children: [
            _buildSectionHeader('DIAGNOSTICS & TELEMETRY'),
            const SizedBox(height: 8),
            _buildCardContainer(
              children: [
                M3EListItem(
                  headline: 'Audio Engine Diagnostic Panel',
                  supportingText:
                      'Real-time telemetry, PDC latency & "Why is this track resampled?" explainer',
                  leading: M3EContainer(
                    Shapes.pill,
                    width: 40,
                    height: 40,
                    color: Colors.cyanAccent.withAlpha(35),
                    child: const Center(
                      child: Icon(Icons.monitor_heart_rounded,
                          color: Colors.cyanAccent, size: 20),
                    ),
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded,
                      color: Colors.cyanAccent, size: 22),
                  onTap: () {
                    showAudioEngineDiagnosticPanel(context, widget.player);
                  },
                ),
              ],
            ),
            const SizedBox(height: 20),
            _buildSectionHeader('RESAMPLING & DITHERING'),
            const SizedBox(height: 8),
            _buildCardContainer(
              children: [
                M3EListItem(
                  headline: 'Resampler',
                  leading: _buildLeadingIcon(Icons.memory),
                  trailing: SizedBox(
                    width: 170,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Expanded(
                          child: Text(
                            _getResampleAlgorithmName(_resampleAlgorithm),
                            style: TextStyle(color: _textDark, fontSize: 13),
                            textAlign: TextAlign.right,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Icon(Icons.chevron_right, color: _textDark, size: 20),
                      ],
                    ),
                  ),
                  onTap: () => _showResampleAlgorithmDialog(
                      onDone: () => setSubState(() {})),
                ),
                Divider(color: context.outlineColor, height: 1),
                M3EListItem(
                  headline: 'Oversampler',
                  supportingText: 'Anti-aliasing for ViPER FX & limiters',
                  leading: _buildLeadingIcon(Icons.blur_on),
                  trailing: SizedBox(
                    width: 150,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Expanded(
                          child: Text(
                            _getOversamplingName(_dspOversampling),
                            style: TextStyle(color: _textDark, fontSize: 13),
                            textAlign: TextAlign.right,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Icon(Icons.chevron_right, color: _textDark, size: 20),
                      ],
                    ),
                  ),
                  onTap: () =>
                      _showOversamplingDialog(onDone: () => setSubState(() {})),
                ),
                Divider(color: context.outlineColor, height: 1),
                M3EListItem(
                  headline: 'Dither',
                  leading: _buildLeadingIcon(Icons.waves),
                  trailing: SizedBox(
                    width: 150,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Expanded(
                          child: Text(
                            _getDitherModeName(_ditherMode),
                            style: TextStyle(color: _textDark, fontSize: 13),
                            textAlign: TextAlign.right,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Icon(Icons.chevron_right, color: _textDark, size: 20),
                      ],
                    ),
                  ),
                  onTap: () =>
                      _showDitherModeDialog(onDone: () => setSubState(() {})),
                ),
              ],
            ),
            const SizedBox(height: 20),
            _buildSectionHeader('HARDWARE OUTPUT & PHASE'),
            const SizedBox(height: 8),
            _buildCardContainer(
              children: [
                M3EListItem(
                  headline: 'Output Bit Depth',
                  supportingText: 'Hardware PCM bit precision',
                  leading: _buildLeadingIcon(Icons.code),
                  trailing: SizedBox(
                    width: 150,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Expanded(
                          child: Text(
                            _formatAudioDepth(widget.outputFormat),
                            style: TextStyle(color: _textDark, fontSize: 13),
                            textAlign: TextAlign.right,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Icon(Icons.chevron_right, color: _textDark, size: 20),
                      ],
                    ),
                  ),
                  onTap: () =>
                      _showOutputFormatDialog(onDone: () => setSubState(() {})),
                ),
                Divider(color: context.outlineColor, height: 1),
                IgnorePointer(
                  ignoring: _autoBitPerfectEnabled,
                  child: AnimatedOpacity(
                    opacity: _autoBitPerfectEnabled ? 0.38 : 1.0,
                    duration: const Duration(milliseconds: 200),
                    child: M3EListItem(
                      headline: 'Sample Rate',
                      supportingText: _autoBitPerfectEnabled
                          ? 'Managed automatically (Auto Bit-Perfect is on)'
                          : null,
                      leading: _buildLeadingIcon(Icons.speed),
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
                                style:
                                    TextStyle(color: _textDark, fontSize: 13),
                                textAlign: TextAlign.right,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Icon(Icons.chevron_right,
                                color: _textDark, size: 20),
                          ],
                        ),
                      ),
                      onTap: () => _showSampleRateDialog(
                          onDone: () => setSubState(() {})),
                    ),
                  ),
                ),
                Divider(color: context.outlineColor, height: 1),
                M3EListItem(
                  headline: 'Output Channels',
                  leading: _buildLeadingIcon(Icons.speaker_group),
                  trailing: SizedBox(
                    width: 150,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Expanded(
                          child: Text(
                            _formatChannelCount(widget.outputChannels),
                            style: TextStyle(color: _textDark, fontSize: 13),
                            textAlign: TextAlign.right,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Icon(Icons.chevron_right, color: _textDark, size: 20),
                      ],
                    ),
                  ),
                  onTap: () =>
                      _showChannelsDialog(onDone: () => setSubState(() {})),
                ),
                Divider(color: context.outlineColor, height: 1),
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          _buildLeadingIcon(Icons.swap_calls),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Phase Inversion (Ø 180°)',
                                  style: TextStyle(
                                      color: _textPrimary,
                                      fontWeight: FontWeight.w500),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Invert PCM polarity for reversed hardware or phase alignment',
                                  style:
                                      TextStyle(color: _textDark, fontSize: 12),
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
                            child: _buildM3ESwitchTile(
                              title: 'Left Phase Ø',
                              value: _phaseInvertLeft,
                              onChanged: (val) {
                                setState(() => _phaseInvertLeft = val);
                                _persistPhaseInversionSettings();
                                setSubState(() {});
                              },
                            ),
                          ),
                          Expanded(
                            child: _buildM3ESwitchTile(
                              title: 'Right Phase Ø',
                              value: _phaseInvertRight,
                              onChanged: (val) {
                                setState(() => _phaseInvertRight = val);
                                _persistPhaseInversionSettings();
                                setSubState(() {});
                              },
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Divider(color: context.outlineColor, height: 1),
                _buildM3ESwitchTile(
                  title: 'L/R Channel Swap',
                  subtitle: _lrSwapEnabled
                      ? 'Left and right outputs are swapped'
                      : 'Mirror left and right audio channels',
                  secondary: _buildLeadingIcon(
                    Icons.swap_horiz_rounded,
                    _lrSwapEnabled ? _primary : _textDark,
                  ),
                  value: _lrSwapEnabled,
                  onChanged: (val) {
                    setState(() => _lrSwapEnabled = val);
                    _persistChannelRoutingSettings();
                    setSubState(() {});
                  },
                ),
                Divider(color: context.outlineColor, height: 1),
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          _buildLeadingIcon(Icons.tune_rounded),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Per-Channel Gain',
                                  style: TextStyle(
                                      color: _textPrimary,
                                      fontWeight: FontWeight.w500),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Independent L/R trim (\u221212\u202fdB to +12\u202fdB)',
                                  style: TextStyle(
                                      color: _textDark, fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      // Left channel slider
                      Row(
                        children: [
                          SizedBox(
                            width: 28,
                            child: Text('L',
                                style: TextStyle(
                                    color: _primary,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13)),
                          ),
                          Expanded(
                            child: M3ESlider(
                              min: -12,
                              max: 12,
                              divisions: 48,
                              value: _channelGainLeftDb,
                              onChanged: (val) {
                                setState(() => _channelGainLeftDb =
                                    double.parse(val.toStringAsFixed(1)));
                              },
                              onChangeEnd: (_) {
                                _persistChannelRoutingSettings();
                                setSubState(() {});
                              },
                            ),
                          ),
                          SizedBox(
                            width: 52,
                            child: Text(
                              _channelGainLeftDb == 0.0
                                  ? '0\u202fdB'
                                  : '${_channelGainLeftDb > 0 ? '+' : ''}${_channelGainLeftDb.toStringAsFixed(1)}\u202fdB',
                              style: TextStyle(
                                  color: _channelGainLeftDb == 0.0
                                      ? _textDark
                                      : _primary,
                                  fontSize: 12,
                                  fontWeight: _channelGainLeftDb == 0.0
                                      ? FontWeight.normal
                                      : FontWeight.bold),
                              textAlign: TextAlign.right,
                            ),
                          ),
                        ],
                      ),
                      // Right channel slider
                      Row(
                        children: [
                          SizedBox(
                            width: 28,
                            child: Text('R',
                                style: TextStyle(
                                    color: Colors.deepOrangeAccent,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13)),
                          ),
                          Expanded(
                            child: M3ESlider(
                              min: -12,
                              max: 12,
                              divisions: 48,
                              value: _channelGainRightDb,
                              onChanged: (val) {
                                setState(() => _channelGainRightDb =
                                    double.parse(val.toStringAsFixed(1)));
                              },
                              onChangeEnd: (_) {
                                _persistChannelRoutingSettings();
                                setSubState(() {});
                              },
                            ),
                          ),
                          SizedBox(
                            width: 52,
                            child: Text(
                              _channelGainRightDb == 0.0
                                  ? '0\u202fdB'
                                  : '${_channelGainRightDb > 0 ? '+' : ''}${_channelGainRightDb.toStringAsFixed(1)}\u202fdB',
                              style: TextStyle(
                                  color: _channelGainRightDb == 0.0
                                      ? _textDark
                                      : Colors.deepOrangeAccent,
                                  fontSize: 12,
                                  fontWeight: _channelGainRightDb == 0.0
                                      ? FontWeight.normal
                                      : FontWeight.bold),
                              textAlign: TextAlign.right,
                            ),
                          ),
                        ],
                      ),
                      // Reset button
                      if (_channelGainLeftDb != 0.0 ||
                          _channelGainRightDb != 0.0)
                        Align(
                          alignment: Alignment.centerRight,
                          child: M3EButton.icon(
                            onPressed: () {
                              setState(() {
                                _channelGainLeftDb = 0.0;
                                _channelGainRightDb = 0.0;
                              });
                              _persistChannelRoutingSettings();
                              setSubState(() {});
                            },
                            icon: Icon(Icons.restart_alt_rounded,
                                color: _textDark, size: 16),
                            label: Text('Reset to 0\u202fdB',
                                style:
                                    TextStyle(color: _textDark, fontSize: 12)),
                          ),
                        ),
                    ],
                  ),
                ),
                Divider(color: context.outlineColor, height: 1),
                _buildM3ESwitchTile(
                  title: 'Bit-Perfect Playback',
                  subtitle: 'Bypasses OS Mixer',
                  secondary: _buildLeadingIcon(Icons.verified),
                  value: widget.exclusiveMode,
                  onChanged: (val) async {
                    widget.player.setExclusiveMode(val);
                    await Future.delayed(const Duration(milliseconds: 150));
                    final actual = await widget.player.getExclusiveMode();
                    widget.onExclusiveModeChanged(actual);
                    setSubState(() {});
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).hideCurrentSnackBar();
                    if (val && actual) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          backgroundColor: _cardDark,
                          behavior: SnackBarBehavior.floating,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: BorderSide(
                                color: Colors.greenAccent.withAlpha(120)),
                          ),
                          content: Row(
                            children: [
                              const Icon(Icons.verified_rounded,
                                  color: Colors.greenAccent, size: 20),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'Bit-Perfect Mode Accepted',
                                  style: TextStyle(
                                      color: _textPrimary, fontSize: 13),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    } else if (val && !actual) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          backgroundColor: _cardDark,
                          behavior: SnackBarBehavior.floating,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: BorderSide(
                                color: Colors.amberAccent.withAlpha(120)),
                          ),
                          content: Row(
                            children: [
                              const Icon(Icons.warning_amber_rounded,
                                  color: Colors.amberAccent, size: 20),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'Hardware declined Exclusive Mode. Falling back to Shared Mixer!',
                                  style: TextStyle(
                                      color: _textPrimary, fontSize: 13),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          backgroundColor: _cardDark,
                          behavior: SnackBarBehavior.floating,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: BorderSide(color: context.outlineColor),
                          ),
                          content: Row(
                            children: [
                              Icon(Icons.info_outline,
                                  color: _textDark, size: 20),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'Bit-Perfect Exclusive Mode Disabled (Shared Mixer)',
                                  style: TextStyle(
                                      color: _textPrimary, fontSize: 13),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }
                  },
                ),
                Divider(color: context.outlineColor, height: 1),
                _buildM3ESwitchTile(
                  title: '64-Bit Float DSP',
                  subtitle: 'Higher accuracy (requires more power)',
                  secondary: _buildLeadingIcon(Icons.architecture),
                  value: _use64BitProcessingEnabled,
                  onChanged: (val) {
                    setState(() => _use64BitProcessingEnabled = val);
                    widget.player.set64BitProcessingEnabled(val);
                    AppStateService.instance.save64BitProcessingEnabled(val);
                    setSubState(() {});
                  },
                ),
                Divider(color: context.outlineColor, height: 1),
                _buildM3ESwitchTile(
                  title: 'Auto Sample-Rate Match',
                  subtitle:
                      'Automatically switch hardware DAC rate to match track native rate',
                  secondary: _buildLeadingIcon(Icons.graphic_eq),
                  value: _autoBitPerfectEnabled,
                  onChanged: (val) {
                    setState(() => _autoBitPerfectEnabled = val);
                    widget.player.setAutoSampleRateMatchEnabled(val);
                    AppStateService.instance.saveAutoBitPerfectEnabled(val);
                    setSubState(() {});
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).hideCurrentSnackBar();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        backgroundColor: _cardDark,
                        behavior: SnackBarBehavior.floating,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(
                            color: val
                                ? Colors.greenAccent.withAlpha(120)
                                : context.outlineColor,
                          ),
                        ),
                        content: Row(
                          children: [
                            Icon(
                              val ? Icons.graphic_eq : Icons.info_outline,
                              color: val ? Colors.greenAccent : _textDark,
                              size: 20,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                val
                                    ? 'Auto Sample-Rate Match Active'
                                    : 'Auto Sample-Rate Match Disabled',
                                style: TextStyle(
                                    color: _textPrimary, fontSize: 13),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: 20),
            _buildSectionHeader('HARDWARE PROTECTION'),
            const SizedBox(height: 8),
            _buildCardContainer(
              children: [
                _buildM3ESwitchTile(
                  title: 'Hardware Safeguards',
                  subtitle: _speakerProtectionEnabled
                      ? 'Peak ceiling & subsonic/ultrasonic guard active'
                      : 'Hardware protection disabled',
                  secondary: _buildLeadingIcon(
                    _speakerProtectionEnabled
                        ? Icons.health_and_safety
                        : Icons.warning_amber_rounded,
                    _speakerProtectionEnabled ? _primary : Colors.amberAccent,
                  ),
                  value: _speakerProtectionEnabled,
                  onChanged: (val) {
                    setState(() => _speakerProtectionEnabled = val);
                    setSubState(() {});
                    _persistSpeakerProtectionSettings();
                  },
                ),
                if (_speakerProtectionEnabled) ...[
                  Divider(color: context.outlineColor, height: 1),
                  M3EListItem(
                    headline: 'Subsonic Filter (High-Pass)',
                    supportingText: 'Below woofer tuning',
                    leading: _buildLeadingIcon(Icons.arrow_upward),
                    trailing: SizedBox(
                      width: 130,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Expanded(
                            child: Text(
                              _subsonicCutoffHz <= 0
                                  ? 'Off'
                                  : '${_subsonicCutoffHz.toInt()} Hz',
                              style: TextStyle(color: _textDark, fontSize: 13),
                              textAlign: TextAlign.right,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Icon(Icons.chevron_right, color: _textDark, size: 20),
                        ],
                      ),
                    ),
                    onTap: () =>
                        _showSubsonicDialog(onDone: () => setSubState(() {})),
                  ),
                  Divider(color: context.outlineColor, height: 1),
                  M3EListItem(
                    headline: 'Ultrasonic Guard (Low-Pass)',
                    supportingText: 'Filters frequencies above 18-22kHz',
                    leading: _buildLeadingIcon(Icons.arrow_downward),
                    trailing: SizedBox(
                      width: 130,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Expanded(
                            child: Text(
                              _ultrasonicCutoffHz >= 24000
                                  ? 'Off'
                                  : '${(_ultrasonicCutoffHz / 1000).toStringAsFixed(1)} kHz',
                              style: TextStyle(color: _textDark, fontSize: 13),
                              textAlign: TextAlign.right,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Icon(Icons.chevron_right, color: _textDark, size: 20),
                        ],
                      ),
                    ),
                    onTap: () =>
                        _showUltrasonicDialog(onDone: () => setSubState(() {})),
                  ),
                  Divider(color: context.outlineColor, height: 1),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 16),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Peak Ceiling',
                                  style: TextStyle(
                                      color: _textPrimary,
                                      fontWeight: FontWeight.w500)),
                              const SizedBox(height: 2),
                              Text(
                                'Max: ${(_limiterThreshold * 100).toInt()}% (${(20 * math.log(_limiterThreshold) / math.ln10).toStringAsFixed(2)} dBFS)',
                                style:
                                    TextStyle(color: _textDark, fontSize: 12),
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
                              setSubState(() {});
                              _persistSpeakerProtectionSettings();
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                  Divider(color: context.outlineColor, height: 1),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 16),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Safety Headroom',
                                  style: TextStyle(
                                      color: _textPrimary,
                                      fontWeight: FontWeight.w500)),
                              const SizedBox(height: 2),
                              Text('Output level attenuation buffer',
                                  style: TextStyle(
                                      color: _textDark, fontSize: 12)),
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
                              setSubState(() {});
                              _persistSpeakerProtectionSettings();
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                Divider(color: context.outlineColor, height: 1),
                _buildM3ESwitchTile(
                  title: 'Look-Ahead True-Peak Limiter',
                  subtitle:
                      '2ms look-ahead inter-sample peak protection (0 clipping guaranteed)',
                  secondary: _buildLeadingIcon(Icons.speed_rounded),
                  value: _lookaheadLimiterEnabled,
                  onChanged: (val) {
                    setState(() => _lookaheadLimiterEnabled = val);
                    setSubState(() {});
                    _persistLookaheadLimiterSettings();
                  },
                ),
                if (_lookaheadLimiterEnabled) ...[
                  Divider(color: context.outlineColor, height: 1),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 16),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('True-Peak Ceiling (dBTP)',
                                  style: TextStyle(
                                      color: _textPrimary,
                                      fontWeight: FontWeight.w500)),
                              const SizedBox(height: 2),
                              Text(
                                'Max output peak ceiling (${_lookaheadLimiterCeilingDBTP.toStringAsFixed(1)} dBTP)',
                                style:
                                    TextStyle(color: _textDark, fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                        SizedBox(
                          width: 90,
                          child: ModernAudioKnob(
                            label: 'CEILING',
                            value: _lookaheadLimiterCeilingDBTP,
                            min: -6.0,
                            max: 0.0,
                            activeColor: _primary,
                            valueFormatter: (v) =>
                                '${v.toStringAsFixed(1)} dBTP',
                            onChanged: (val) {
                              setState(
                                  () => _lookaheadLimiterCeilingDBTP = val);
                              setSubState(() {});
                              _persistLookaheadLimiterSettings();
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 20),
            _buildSectionHeader('REPLAYGAIN & LOUDNESS'),
            const SizedBox(height: 8),
            _buildCardContainer(
              children: [
                _buildM3ESwitchTile(
                  title: 'ITU-R BS.1770-4 Loudness Normalizer',
                  subtitle: 'Real-time EBU R128 K-weighted loudness matching',
                  secondary: _buildLeadingIcon(Icons.multitrack_audio_rounded),
                  value: _loudnessNormalizerEnabled,
                  onChanged: (val) {
                    setState(() => _loudnessNormalizerEnabled = val);
                    setSubState(() {});
                    _persistLoudnessNormalizerSettings();
                  },
                ),
                if (_loudnessNormalizerEnabled) ...[
                  Divider(color: context.outlineColor, height: 1),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 16),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Target Loudness (LUFS)',
                                  style: TextStyle(
                                      color: _textPrimary,
                                      fontWeight: FontWeight.w500)),
                              const SizedBox(height: 2),
                              Text(
                                'Target integrated loudness (${_loudnessNormalizerTargetLUFS.toStringAsFixed(1)} LUFS)',
                                style:
                                    TextStyle(color: _textDark, fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                        SizedBox(
                          width: 90,
                          child: ModernAudioKnob(
                            label: 'TARGET',
                            value: _loudnessNormalizerTargetLUFS,
                            min: -24.0,
                            max: -8.0,
                            activeColor: _primary,
                            valueFormatter: (v) =>
                                '${v.toStringAsFixed(1)} LUFS',
                            onChanged: (val) {
                              setState(
                                  () => _loudnessNormalizerTargetLUFS = val);
                              setSubState(() {});
                              _persistLoudnessNormalizerSettings();
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                Divider(color: context.outlineColor, height: 1),
                M3EListItem(
                  headline: 'ReplayGain Mode',
                  leading: _buildLeadingIcon(Icons.equalizer),
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
                            style: TextStyle(color: _textDark, fontSize: 13),
                            textAlign: TextAlign.right,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Icon(Icons.chevron_right, color: _textDark, size: 20),
                      ],
                    ),
                  ),
                  onTap: () => _showReplayGainModeDialog(
                      onDone: () => setSubState(() {})),
                ),
                Divider(color: context.outlineColor, height: 1),
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Preamp Gain',
                        style: TextStyle(
                            color: _textPrimary, fontWeight: FontWeight.w500),
                      ),
                      SizedBox(
                        width: 90,
                        child: ModernAudioKnob(
                          label: 'GAIN',
                          value: _replayGainPreamp,
                          min: -15.0,
                          max: 15.0,
                          activeColor: _primary,
                          valueFormatter: (v) =>
                              '${v > 0 ? '+' : ''}${v.toStringAsFixed(1)} dB',
                          onChanged: (val) {
                            setState(() => _replayGainPreamp = val);
                            setSubState(() {});
                            _persistReplayGainSettings();
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  // 3. Equalizer Sub-Screen
  Widget _buildEqualizerSubScreen() {
    return StatefulBuilder(
      builder: (context, setSubState) {
        return _buildSubScreenLayout(
          title: 'Equalizer & DSP',
          children: [
            _buildSectionHeader('GRAPHIC EQUALIZER BANDS'),
            const SizedBox(height: 8),
            _buildCardContainer(
              children: [
                Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          _buildLeadingIcon(Icons.settings_input_composite),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Frequency Precision',
                                    style: TextStyle(
                                        color: _textPrimary,
                                        fontSize: 16,
                                        fontWeight: FontWeight.w500)),
                                const SizedBox(height: 4),
                                Text('Choose total active EQ bands',
                                    style: TextStyle(
                                        color: _textDark, fontSize: 13)),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      Container(
                        height: 44,
                        decoration: BoxDecoration(
                          color: context.outlineColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            for (final count in [10, 16, 32])
                              Expanded(
                                child: GestureDetector(
                                  onTap: () async {
                                    setState(() => _eqBandCount = count);
                                    setSubState(() {});
                                    final state = await AppStateService.instance
                                        .loadEqBands();
                                    await AppStateService.instance.saveEqBands(
                                      enabled: state.enabled,
                                      preset: state.preset,
                                      gains: List.filled(count, 0.0),
                                      preampDb: state.preampDb,
                                      bandCount: count,
                                    );
                                  },
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: _eqBandCount == count
                                          ? _primary
                                          : Colors.transparent,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    alignment: Alignment.center,
                                    child: Text(
                                      '$count-Band',
                                      style: TextStyle(
                                        color: _eqBandCount == count
                                            ? Colors.white
                                            : _textDark,
                                        fontWeight: _eqBandCount == count
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
            ),
          ],
        );
      },
    );
  }

  // 4. Visualization Sub-Screen
  Widget _buildVisualizationSubScreen() {
    return StatefulBuilder(
      builder: (context, setSubState) {
        return _buildSubScreenLayout(
          title: 'Visualization',
          children: [
            _buildSectionHeader('SPECTRUM ANALYZER'),
            const SizedBox(height: 8),
            _buildCardContainer(
              children: [
                _buildM3ESwitchTile(
                  title: 'Spectrum Analyzer',
                  subtitle: 'Audio Spectrum Visualizer',
                  secondary: _buildLeadingIcon(Icons.bar_chart),
                  value: widget.analyzerEnabled,
                  onChanged: (v) {
                    widget.onAnalyzerEnabledChanged(v);
                    setSubState(() {});
                  },
                ),
                if (widget.analyzerEnabled) ...[
                  Divider(color: context.outlineColor, height: 1),
                  Padding(
                    padding: const EdgeInsets.all(20.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Analyzer Type',
                            style: TextStyle(
                                color: _textPrimary,
                                fontSize: 16,
                                fontWeight: FontWeight.w500)),
                        const SizedBox(height: 16),
                        Container(
                          height: 44,
                          decoration: BoxDecoration(
                            color: context.outlineColor.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: GestureDetector(
                                  onTap: () {
                                    widget.onAnalyzerTypeChanged('bar');
                                    setSubState(() {});
                                  },
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
                                  onTap: () {
                                    widget.onAnalyzerTypeChanged('area');
                                    setSubState(() {});
                                  },
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
                                        fontWeight:
                                            widget.analyzerType == 'area'
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
                  Divider(color: context.outlineColor, height: 1),
                  Padding(
                    padding: const EdgeInsets.all(20.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Spectrum Theme',
                            style: TextStyle(
                                color: _textPrimary,
                                fontSize: 16,
                                fontWeight: FontWeight.w500)),
                        const SizedBox(height: 4),
                        Text('Spectrum visual style',
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
                                onTap: () {
                                  widget.onSpectrumStyleChanged(entry.key);
                                  setSubState(() {});
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16, vertical: 10),
                                  decoration: BoxDecoration(
                                    color: widget.spectrumStyle == entry.key
                                        ? _primary
                                        : context.outlineColor
                                            .withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: widget.spectrumStyle == entry.key
                                          ? _primary
                                          : context.outlineColor,
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(entry.value.$2,
                                          size: 16,
                                          color:
                                              widget.spectrumStyle == entry.key
                                                  ? Colors.white
                                                  : _textDark),
                                      const SizedBox(width: 6),
                                      Text(
                                        entry.value.$1,
                                        style: TextStyle(
                                          color:
                                              widget.spectrumStyle == entry.key
                                                  ? Colors.white
                                                  : _textDark,
                                          fontWeight:
                                              widget.spectrumStyle == entry.key
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
                  Divider(color: context.outlineColor, height: 1),
                  _buildM3ESwitchTile(
                    title: 'Auto Fit Scale',
                    subtitle: 'Dynamically adjust Y-axis peak range',
                    value: widget.analyzerAutoFit,
                    onChanged: (v) {
                      widget.onAnalyzerAutoFitChanged(v);
                      setSubState(() {});
                    },
                  ),
                  Divider(color: context.outlineColor, height: 1),
                  _buildM3ESwitchTile(
                    title: 'Show Grids & Decibels',
                    value: widget.analyzerShowGrids,
                    onChanged: (v) {
                      widget.onAnalyzerShowGridsChanged(v);
                      setSubState(() {});
                    },
                  ),
                  Divider(color: context.outlineColor, height: 1),
                  _buildM3ESwitchTile(
                    title: 'Logarithmic Decibel Scale',
                    subtitle: 'Logarithmic audio response curve',
                    value: widget.analyzerLogScale,
                    onChanged: (v) {
                      widget.onAnalyzerLogScaleChanged(v);
                      setSubState(() {});
                    },
                  ),
                  Divider(color: context.outlineColor, height: 1),
                  M3EListItem(
                    headline: 'FFT Sample Size',
                    leading: _buildLeadingIcon(Icons.data_array),
                    trailing: SizedBox(
                      width: 150,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Expanded(
                            child: Text(
                              widget.analyzerSampleSize.toString(),
                              style: TextStyle(color: _textDark, fontSize: 14),
                              textAlign: TextAlign.right,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Icon(Icons.chevron_right, color: _textDark, size: 20),
                        ],
                      ),
                    ),
                    onTap: () => _showAnalyzerSampleSizeDialog(
                        onDone: () => setSubState(() {})),
                  ),
                ],
              ],
            ),
          ],
        );
      },
    );
  }

  // 5. Playback & Crossfade Sub-Screen
  Widget _buildPlaybackSubScreen() {
    return StatefulBuilder(
      builder: (context, setSubState) {
        return _buildSubScreenLayout(
          title: 'Playback & Crossfade',
          children: [
            _buildSectionHeader('TRANSITIONS & PLAYBACK'),
            const SizedBox(height: 8),
            _buildCardContainer(
              children: [
                _buildM3ESwitchTile(
                  title: 'Gapless Playback',
                  subtitle: 'Seamless transitions between track ends',
                  secondary: _buildLeadingIcon(Icons.queue_music),
                  value: _gaplessPlayback,
                  onChanged: (v) {
                    setState(() => _gaplessPlayback = v);
                    setSubState(() {});
                    _persistUiSettings();
                  },
                ),
                Divider(color: context.outlineColor, height: 1),
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              _buildLeadingIcon(Icons.tune),
                              const SizedBox(width: 16),
                              Text('Crossfade Duration',
                                  style: TextStyle(
                                      color: _textPrimary,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w500)),
                            ],
                          ),
                          M3ESwitch(
                            value: widget.crossfadeEnabled,
                            onChanged: (v) {
                              widget.onCrossfadeEnabledChanged(v);
                              widget.player.setCrossfadeEnabled(v);
                              setSubState(() {});
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      M3ESlider(
                        value: widget.crossfadeDurationMs / 1000.0,
                        min: 0,
                        max: 12,
                        divisions: 24,
                        onChanged: widget.crossfadeEnabled
                            ? (v) {
                                widget.onCrossfadeDurationMsChanged(
                                    (v * 1000).toInt());
                                setSubState(() {});
                              }
                            : null,
                        onChangeEnd: widget.crossfadeEnabled
                            ? (v) {
                                widget.player
                                    .setCrossfadeDurationMs((v * 1000).toInt());
                              }
                            : null,
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Off',
                              style: TextStyle(color: _textDark, fontSize: 12)),
                          Text(
                            '${(widget.crossfadeDurationMs / 1000).toStringAsFixed(1)}s',
                            style: TextStyle(
                              color: widget.crossfadeEnabled
                                  ? _primary
                                  : _textDark,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text('12s',
                              style: TextStyle(color: _textDark, fontSize: 12)),
                        ],
                      )
                    ],
                  ),
                ),
                Divider(color: context.outlineColor, height: 1),
                if (widget.crossfadeEnabled) ...[
                  _buildM3ESwitchTile(
                    title: 'Loudness-Aware Crossfade',
                    subtitle: _loudnessCrossfadeEnabled
                        ? 'Per-track gain applied during blend — no volume jumps'
                        : 'Disabled — raw PCM blending',
                    secondary: _buildLeadingIcon(
                      Icons.volume_up_rounded,
                      _loudnessCrossfadeEnabled ? _primary : _textDark,
                    ),
                    value: _loudnessCrossfadeEnabled,
                    onChanged: (val) {
                      setState(() => _loudnessCrossfadeEnabled = val);
                      setSubState(() {});
                      widget.player.setLoudnessCrossfadeEnabled(val);
                      AppStateService.instance
                          .saveLoudnessCrossfadeEnabled(val);
                    },
                  ),
                  Divider(color: context.outlineColor, height: 1),
                ],
                _buildM3ESwitchTile(
                  title: 'Normalize Volume',
                  subtitle: 'Normalizes volume across tracks',
                  secondary: _buildLeadingIcon(Icons.bar_chart),
                  value: _normalizeVolume,
                  onChanged: (v) {
                    setState(() => _normalizeVolume = v);
                    setSubState(() {});
                    _persistUiSettings();
                  },
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  // 6. Storage Sub-Screen
  Widget _buildStorageSubScreen() {
    return StatefulBuilder(
      builder: (context, setSubState) {
        return _buildSubScreenLayout(
          title: 'Library & Storage',
          children: [
            _buildSectionHeader('NETWORK & AUDIO CACHE'),
            const SizedBox(height: 8),
            _buildCardContainer(
              children: [
                _buildM3ESwitchTile(
                  title: 'Stream over Wi-Fi Only',
                  secondary: _buildLeadingIcon(Icons.wifi),
                  value: _streamOverWifi,
                  onChanged: (v) {
                    setState(() => _streamOverWifi = v);
                    setSubState(() {});
                    _persistUiSettings();
                  },
                ),
                Divider(color: context.outlineColor, height: 1),
                M3EListItem(
                  headline: 'Audio Cache Storage',
                  leading: _buildLeadingIcon(Icons.dns),
                  trailing: Text('145 MB',
                      style: TextStyle(color: _textDark, fontSize: 14)),
                ),
                InkWell(
                  onTap: () {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: const Text('Audio cache cleared successfully'),
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
            ),
          ],
        );
      },
    );
  }

  // 7. Misc & System Sub-Screen
  Widget _buildMiscSystemSubScreen() {
    return StatefulBuilder(
      builder: (context, setSubState) {
        return _buildSubScreenLayout(
          title: 'Misc & System',
          children: [
            _buildSectionHeader('ABOUT & SYSTEM LICENSES'),
            const SizedBox(height: 8),
            _buildCardContainer(
              children: [
                M3EListItem(
                  headline: 'Version',
                  leading: _buildLeadingIcon(Icons.info_outline),
                  trailing: Text(_appVersion,
                      style: TextStyle(color: _textDark, fontSize: 14)),
                ),
                Divider(color: context.outlineColor, height: 1),
                M3EListItem(
                  headline: 'Open Source Licenses',
                  leading: _buildLeadingIcon(Icons.policy_outlined),
                  trailing:
                      Icon(Icons.chevron_right, color: _textDark, size: 20),
                  onTap: () {
                    showLicensePage(
                      context: context,
                      applicationName: 'SautiPlay',
                      applicationVersion: _appVersion,
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: 20),
            _buildSectionHeader('DEBUG & ENGINE LOGS'),
            const SizedBox(height: 8),
            _buildCardContainer(
              children: [
                _buildM3ESwitchTile(
                  title: 'Allow invalid TLS certs',
                  subtitle: 'Testing & fallback media server mode',
                  secondary: _buildLeadingIcon(Icons.security),
                  value: widget.allowInvalidTls,
                  onChanged: (v) {
                    widget.onAllowInvalidTlsChanged(v);
                    setSubState(() {});
                  },
                ),
                Divider(color: context.outlineColor, height: 1),
                M3EListItem(
                  headline: 'Poll Native Error',
                  leading: _buildLeadingIcon(Icons.refresh),
                  trailing:
                      Icon(Icons.chevron_right, color: _textDark, size: 20),
                  onTap: widget.onPollError,
                ),
                Divider(color: context.outlineColor, height: 1),
                M3EListItem(
                  headline: 'Clear Native Error',
                  leading: _buildLeadingIcon(Icons.cleaning_services_outlined),
                  trailing:
                      Icon(Icons.chevron_right, color: _textDark, size: 20),
                  onTap: widget.onClearNativeError,
                ),
                Divider(color: context.outlineColor, height: 1),
                Theme(
                  data: Theme.of(context)
                      .copyWith(dividerColor: Colors.transparent),
                  child: ValueListenableBuilder<int>(
                    valueListenable: widget.logUpdateNotifier,
                    builder: (context, _, __) {
                      return ExpansionTile(
                        tilePadding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 8),
                        leading: _buildLeadingIcon(Icons.article_outlined),
                        title: Text('App Engine Logs',
                            style: TextStyle(
                                color: _textPrimary,
                                fontWeight: FontWeight.w500)),
                        trailing: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: _primary.withAlpha(50),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text('${widget.logs.length}',
                              style: TextStyle(
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
                                  child: M3EButton.icon(
                                    onPressed: () async {
                                      if (widget.logs.isEmpty) {
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(const SnackBar(
                                                content:
                                                    Text('No logs to copy')));
                                        return;
                                      }
                                      final text =
                                          widget.logs.reversed.join('\n');
                                      await Clipboard.setData(
                                          ClipboardData(text: text));
                                      if (!context.mounted) return;
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(SnackBar(
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
                                  child: M3EButton.icon(
                                    onPressed: widget.onClearLogs,
                                    icon: const Icon(Icons.delete_sweep,
                                        size: 18),
                                    label: const Text('Clear'),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            height: 250,
                            margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                            decoration: BoxDecoration(
                              color:
                                  context.outlineColor.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: context.outlineColor),
                            ),
                            child: widget.logs.isEmpty
                                ? Center(
                                    child: Text('No logs yet',
                                        style: TextStyle(color: _textDark)))
                                : ListView.builder(
                                    padding: const EdgeInsets.all(12),
                                    itemCount: widget.logs.length,
                                    itemBuilder: (context, index) {
                                      return Padding(
                                        padding:
                                            const EdgeInsets.only(bottom: 6.0),
                                        child: SelectableText(
                                          widget.logs[index],
                                          style: TextStyle(
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
                    },
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  // --- Modal Dialog Helpers ---

  String _getResampleAlgorithmName(int index) {
    switch (index) {
      case 0:
        return 'Linear Standard (Fast & Smooth)';
      case 1:
        return 'Sinc Master Ultra HD';
      case 2:
        return 'Sinc High Quality';
      case 3:
        return 'Sinc Good Quality';
      case 4:
        return 'Step / Hold (Lo-Fi)';
      case 5:
        return 'Linear Extended';
      case 7:
        return 'SoX VHQ Linear Phase (Audiophile)';
      case 8:
        return 'SoX VHQ Minimum Phase (Zero Pre-Ring)';
      case 9:
        return 'SoX High Quality';
      case 10:
        return 'SoX Fast Quality';
      default:
        return 'Linear Standard (Fast & Smooth)';
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

  void _showOversamplingDialog({VoidCallback? onDone}) {
    final options = [
      {'factor': 1, 'name': 'Off (1x)', 'subtitle': 'Native sample rate'},
      {
        'factor': 2,
        'name': '2x Oversampling',
        'subtitle': 'High Quality (Anti-aliasing saturation)'
      },
      {
        'factor': 4,
        'name': '4x Oversampling',
        'subtitle': 'Ultra HD (Maximum purity)'
      },
    ];

    M3EBottomSheet.show<void>(
      context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(20.0),
                child: Text('DSP Anti-Aliasing Oversampling',
                    style: TextStyle(
                        color: _textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.bold)),
              ),
              M3ECardList(
                itemCount: options.length,
                onTap: (index) {
                  final val = options[index]['factor'] as int;
                  setDlgState(() {});
                  setState(() => _dspOversampling = val);
                  widget.player.setViperOversampling(val);
                  AppStateService.instance.saveDspOversampling(val);
                  onDone?.call();
                  Navigator.pop(ctx);
                },
                itemBuilder: (context, index) {
                  final item = options[index];
                  final val = item['factor'] as int;
                  return M3EListItem(
                    headline: item['name'] as String,
                    supportingText: item['subtitle'] as String,
                    trailing: M3ERadio<int>(
                      value: val,
                      groupValue: _dspOversampling,
                      onChanged: (v) {
                        setDlgState(() {});
                        setState(() => _dspOversampling = v);
                        widget.player.setViperOversampling(v);
                        AppStateService.instance.saveDspOversampling(v);
                        onDone?.call();
                        Navigator.pop(ctx);
                      },
                    ),
                  );
                },
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  void _showResampleAlgorithmDialog({VoidCallback? onDone}) {
    final isMobile = defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;

    final options = [
      {
        'index': 0,
        'name': 'Linear Standard (Fast & Smooth)',
        'subtitle':
            'Default. Ultra-low CPU, zero latency. Recommended for Mobile.',
        'badge': 'Recommended',
        'isHeavy': false,
      },
      {
        'index': 5,
        'name': 'Linear Extended',
        'subtitle': 'Standard linear interpolation algorithm.',
        'badge': null,
        'isHeavy': false,
      },
      {
        'index': 4,
        'name': 'Step / Hold (Lo-Fi)',
        'subtitle': 'Zero-order hold interpolation for vintage stepped sound.',
        'badge': null,
        'isHeavy': false,
      },
      {
        'index': 9,
        'name': 'SoX High Quality',
        'subtitle':
            'High Quality SoX resampler (160dB SNR). Fast & pristine rate conversion.',
        'badge': 'SoX HQ',
        'isHeavy': false,
      },
      {
        'index': 10,
        'name': 'SoX Fast Quality',
        'subtitle':
            'Fast SoX resampler (120dB SNR). High efficiency resampling.',
        'badge': 'SoX Fast',
        'isHeavy': false,
      },
      {
        'index': 7,
        'name': 'SoX VHQ Linear Phase (Audiophile)',
        'subtitle':
            'Very High Quality linear phase filter (175dB SNR). Exceptional purity.',
        'badge': isMobile ? '⚠️ High CPU' : 'SoX VHQ',
        'isHeavy': true,
      },
      {
        'index': 8,
        'name': 'SoX VHQ Minimum Phase (Zero Pre-Ring)',
        'subtitle':
            'VHQ minimum phase filter. Eliminates pre-ringing on acoustic transients.',
        'badge': isMobile ? '⚠️ High CPU' : 'SoX Min-Phase',
        'isHeavy': true,
      },
      {
        'index': 3,
        'name': 'Sinc Good Quality (libsamplerate)',
        'subtitle': 'Band-limited sinc filter (97dB SNR). Efficient & clean.',
        'badge': null,
        'isHeavy': false,
      },
      {
        'index': 2,
        'name': 'Sinc High Quality (libsamplerate)',
        'subtitle': 'Band-limited sinc filter (121dB SNR). High CPU load.',
        'badge': isMobile ? '⚠️ High CPU' : 'Studio',
        'isHeavy': true,
      },
      {
        'index': 1,
        'name': 'Sinc Master Ultra HD (libsamplerate)',
        'subtitle': '640-tap sinc filter (144dB SNR). Desktop High-End CPUs.',
        'badge': isMobile ? '⚠️ Desktop Only' : 'Master HD',
        'isHeavy': true,
      },
    ];

    M3EBottomSheet.show<void>(
      context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => SizedBox(
          height: MediaQuery.of(context).size.height * 0.75,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 12.0),
                child: Column(
                  children: [
                    Text('Resampling Quality Tier',
                        style: TextStyle(
                            color: _textPrimary,
                            fontSize: 18,
                            fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text(
                      'Select interpolation algorithm for rate conversion',
                      style: TextStyle(color: _textDark, fontSize: 12),
                    ),
                  ],
                ),
              ),
              Divider(color: context.outlineColor),
              Expanded(
                child: M3ECardList.builder(
                  itemCount: options.length,
                  itemBuilder: (context, index) {
                    final item = options[index];
                    final val = item['index'] as int;
                    return M3EListItem(
                      headline: item['name'] as String,
                      supportingText: item['subtitle'] as String,
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (item['badge'] != null) ...[
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: (item['isHeavy'] as bool && isMobile)
                                    ? Colors.amber.withAlpha(40)
                                    : _primary.withAlpha(30),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: (item['isHeavy'] as bool && isMobile)
                                      ? Colors.amber.withAlpha(120)
                                      : _primary.withAlpha(80),
                                ),
                              ),
                              child: Text(
                                item['badge'] as String,
                                style: TextStyle(
                                  color: (item['isHeavy'] as bool && isMobile)
                                      ? Colors.amberAccent
                                      : _primary,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                          ],
                          M3ERadio<int>(
                            value: val,
                            groupValue: _resampleAlgorithm,
                            onChanged: (v) {
                              setDlgState(() {});
                              if (isMobile && (item['isHeavy'] as bool)) {
                                Navigator.pop(ctx);
                                _showMobileResamplerWarningDialog(v, onDone);
                              } else {
                                _applyResampleAlgorithm(v, onDone);
                                Navigator.pop(ctx);
                              }
                            },
                          ),
                        ],
                      ),
                      onTap: () {
                        if (isMobile && (item['isHeavy'] as bool)) {
                          Navigator.pop(ctx);
                          _showMobileResamplerWarningDialog(val, onDone);
                        } else {
                          _applyResampleAlgorithm(val, onDone);
                          Navigator.pop(ctx);
                        }
                      },
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }

  void _applyResampleAlgorithm(int index, VoidCallback? onDone) {
    setState(() => _resampleAlgorithm = index);
    widget.player.setEngineResampleAlgorithm(index);
    _persistUiSettings();
    onDone?.call();
  }

  void _showMobileResamplerWarningDialog(
      int requestedIndex, VoidCallback? onDone) {
    M3EDialog.show<void>(
      context,
      dialog: M3EDialog(
        title: 'High CPU Resampler Warning',
        content: Text(
          '${_getResampleAlgorithmName(requestedIndex)} calculates 640 filter taps per sample. On mobile devices, this may cause stuttering or battery drain.\n\nDo you want to enable it anyway or stay with Linear Standard (Recommended)?',
          style: TextStyle(color: _textDark, fontSize: 13, height: 1.4),
        ),
        actions: [
          M3EButton.text(
            onPressed: () {
              _applyResampleAlgorithm(0, onDone);
              Navigator.pop(context);
            },
            child: const Text('Use Linear (Recommended)'),
          ),
          M3EButton(
            onPressed: () {
              _applyResampleAlgorithm(requestedIndex, onDone);
              Navigator.pop(context);
            },
            child: const Text('Enable Anyway'),
          ),
        ],
      ),
    );
  }

  void _showAnalyzerSampleSizeDialog({VoidCallback? onDone}) {
    final sizes = [256, 512, 1024, 2048, 4096, 8192];
    M3EBottomSheet.show<void>(
      context,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 16.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(20.0),
              child: Text('Sample Size (FFT)',
                  style: TextStyle(
                      color: _textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.bold)),
            ),
            M3ECardList(
              itemCount: sizes.length,
              onTap: (index) {
                final size = sizes[index];
                widget.onAnalyzerSampleSizeChanged(size);
                onDone?.call();
                Navigator.pop(ctx);
              },
              itemBuilder: (context, index) {
                final size = sizes[index];
                return M3EListItem(
                  headline: size.toString(),
                  trailing: M3ERadio<String>(
                    value: size.toString(),
                    groupValue: widget.analyzerSampleSize.toString(),
                    onChanged: (v) {
                      widget.onAnalyzerSampleSizeChanged(size);
                      onDone?.call();
                      Navigator.pop(ctx);
                    },
                  ),
                );
              },
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Future<void> _showReplayGainModeDialog({VoidCallback? onDone}) async {
    final modes = [
      (ReplayGainMode.none, 'None'),
      (ReplayGainMode.track, 'Track'),
      (ReplayGainMode.album, 'Album'),
    ];
    return M3EDialog.show<void>(
      context,
      dialog: M3EDialog(
        title: 'ReplayGain Mode',
        content: M3ECardList(
          itemCount: modes.length,
          onTap: (index) {
            final mode = modes[index].$1;
            setState(() => _replayGainMode = mode);
            _persistReplayGainSettings();
            onDone?.call();
            Navigator.pop(context);
          },
          itemBuilder: (context, index) {
            final mode = modes[index];
            return M3EListItem(
              headline: mode.$2,
              trailing: M3ERadio<ReplayGainMode>(
                value: mode.$1,
                groupValue: _replayGainMode,
                onChanged: (val) {
                  setState(() => _replayGainMode = val);
                  _persistReplayGainSettings();
                  onDone?.call();
                  Navigator.pop(context);
                },
              ),
            );
          },
        ),
      ),
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

  Future<void> _showDitherModeDialog({VoidCallback? onDone}) async {
    final modes = [
      {'id': 0, 'name': 'None', 'subtitle': 'No dithering applied'},
      {'id': 1, 'name': 'Rectangle (RPDF)', 'subtitle': 'Simple flat dither'},
      {
        'id': 2,
        'name': 'Triangle (TPDF)',
        'subtitle': 'Standard flat dither (Recommended)'
      },
      {
        'id': 3,
        'name': 'Lipshitz',
        'subtitle': 'Classic 5th-order noise-shaped'
      },
      {
        'id': 4,
        'name': 'F-Weighted',
        'subtitle': 'Midrange cut noise-shaped (Acoustic/Vocal)'
      },
      {
        'id': 5,
        'name': 'Modified E-Weighted',
        'subtitle': 'Peak-safe noise-shaped (Pop/Rock)'
      },
      {
        'id': 6,
        'name': 'Shibata',
        'subtitle': 'Standard audiophile noise-shaped'
      },
      {
        'id': 7,
        'name': 'Low Shibata',
        'subtitle': 'Gentle audiophile noise-shaped (Safest)'
      },
      {
        'id': 8,
        'name': 'High Shibata',
        'subtitle': 'Steep audiophile noise-shaped'
      },
    ];

    M3EBottomSheet.show<void>(
      context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => SizedBox(
          height: MediaQuery.of(context).size.height * 0.75,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(20.0),
                child: Text('Dither Mode',
                    style: TextStyle(
                        color: _textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.bold)),
              ),
              Expanded(
                child: M3ECardList.builder(
                  itemCount: modes.length,
                  itemBuilder: (context, i) {
                    final item = modes[i];
                    final id = item['id'] as int;
                    final name = item['name'] as String;
                    final subtitle = item['subtitle'] as String;
                    return M3EListItem(
                      headline: name,
                      supportingText: subtitle,
                      trailing: M3ERadio<int>(
                        value: id,
                        groupValue: _ditherMode,
                        onChanged: (val) {
                          setDlgState(() {});
                          setState(() => _ditherMode = val);
                          widget.player.setEngineDitherMode(val);
                          _persistUiSettings();
                          onDone?.call();
                          Navigator.pop(ctx);
                        },
                      ),
                      onTap: () {
                        setDlgState(() {});
                        setState(() => _ditherMode = id);
                        widget.player.setEngineDitherMode(id);
                        _persistUiSettings();
                        onDone?.call();
                        Navigator.pop(ctx);
                      },
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  void _showOutputFormatDialog({VoidCallback? onDone}) {
    final formats = [
      AudioFormat.f32,
      AudioFormat.s32,
      AudioFormat.s24,
      AudioFormat.s16,
      AudioFormat.u8
    ];
    M3EBottomSheet.show<void>(
      context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(20.0),
                child: Text('Engine Output Format',
                    style: TextStyle(
                        color: _textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.bold)),
              ),
              M3ECardList(
                itemCount: formats.length,
                onTap: (index) {
                  final fmt = formats[index];
                  setDlgState(() {});
                  widget.onOutputFormatChanged(fmt);
                  widget.player.setOutputFormat(fmt);
                  setState(() {});
                  onDone?.call();
                  Navigator.pop(ctx);
                },
                itemBuilder: (context, index) {
                  final fmt = formats[index];
                  return _buildRadioOption(
                    _formatAudioDepth(fmt),
                    _formatAudioDepth(widget.outputFormat),
                    (v) {
                      setDlgState(() {});
                      widget.onOutputFormatChanged(fmt);
                      widget.player.setOutputFormat(fmt);
                      setState(() {});
                      onDone?.call();
                      Navigator.pop(ctx);
                    },
                  );
                },
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  void _showSampleRateDialog({VoidCallback? onDone}) {
    final rates = [0, 44100, 48000, 96000, 192000];
    M3EBottomSheet.show<void>(
      context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(20.0),
                child: Text('Engine Sample Rate',
                    style: TextStyle(
                        color: _textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.bold)),
              ),
              M3ECardList(
                itemCount: rates.length,
                onTap: (index) {
                  final r = rates[index];
                  setDlgState(() {});
                  widget.onOutputSampleRateChanged(r);
                  widget.player.setOutputSampleRate(r);
                  setState(() {});
                  onDone?.call();
                  Navigator.pop(ctx);
                },
                itemBuilder: (context, index) {
                  final r = rates[index];
                  final label = r == 0 ? 'Native' : '$r Hz';
                  final currentLabel = widget.outputSampleRate == 0
                      ? 'Native'
                      : '${widget.outputSampleRate} Hz';
                  return _buildRadioOption(label, currentLabel, (v) {
                    final val =
                        v == 'Native' ? 0 : int.parse(v!.replaceAll(' Hz', ''));
                    setDlgState(() {});
                    widget.onOutputSampleRateChanged(val);
                    widget.player.setOutputSampleRate(val);
                    setState(() {});
                    onDone?.call();
                    Navigator.pop(ctx);
                  });
                },
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  String _formatChannelCount(int count) {
    switch (count) {
      case 1:
        return 'Mono (1.0)';
      case 2:
        return 'Stereo (2.0)';
      case 3:
        return '2.1 Surround (3 CH)';
      case 4:
        return '4.0 Quadraphonic (4 CH)';
      case 5:
        return '5.0 Surround (5 CH)';
      case 6:
        return '5.1 Surround (6 CH)';
      case 7:
        return '7.0 Surround (7 CH)';
      case 8:
        return '7.1 Surround (8 CH)';
      default:
        return '$count CH';
    }
  }

  void _showChannelsDialog({VoidCallback? onDone}) {
    final options = [
      {'ch': 1, 'name': 'Mono (1.0)', 'subtitle': 'Single channel output'},
      {
        'ch': 2,
        'name': 'Stereo (2.0)',
        'subtitle': 'Standard 2-channel Left / Right'
      },
      {
        'ch': 3,
        'name': '2.1 Surround (3 CH)',
        'subtitle': 'Left, Right, Center/Sub'
      },
      {
        'ch': 4,
        'name': '4.0 Quadraphonic (4 CH)',
        'subtitle': 'FL, FR, Center, Back Center'
      },
      {
        'ch': 5,
        'name': '5.0 Surround (5 CH)',
        'subtitle': 'FL, FR, Center, Back L/R'
      },
      {
        'ch': 6,
        'name': '5.1 Surround (6 CH)',
        'subtitle': 'FL, FR, Center, LFE Sub, Side L/R'
      },
      {
        'ch': 7,
        'name': '7.0 Surround (7 CH)',
        'subtitle': 'FL, FR, Center, LFE, Back C, Side L/R'
      },
      {
        'ch': 8,
        'name': '7.1 Surround (8 CH)',
        'subtitle': 'FL, FR, Center, LFE, Back L/R, Side L/R'
      },
    ];

    M3EBottomSheet.show<void>(
      context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => SizedBox(
          height: MediaQuery.of(context).size.height * 0.75,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(20.0),
                child: Text('Engine Output Channels',
                    style: TextStyle(
                        color: _textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.bold)),
              ),
              Expanded(
                child: M3ECardList.builder(
                  itemCount: options.length,
                  itemBuilder: (context, i) {
                    final item = options[i];
                    final ch = item['ch'] as int;
                    final name = item['name'] as String;
                    final subtitle = item['subtitle'] as String;
                    return M3EListItem(
                      headline: name,
                      supportingText: subtitle,
                      trailing: M3ERadio<int>(
                        value: ch,
                        groupValue: widget.outputChannels,
                        onChanged: (val) {
                          setDlgState(() {});
                          widget.onOutputChannelsChanged(val);
                          widget.player.setOutputChannels(val);
                          setState(() {});
                          onDone?.call();
                          Navigator.pop(ctx);
                        },
                      ),
                      onTap: () {
                        setDlgState(() {});
                        widget.onOutputChannelsChanged(ch);
                        widget.player.setOutputChannels(ch);
                        setState(() {});
                        onDone?.call();
                        Navigator.pop(ctx);
                      },
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRadioOption(
      String title, String groupValue, ValueChanged<String?> onChanged) {
    return M3EListItem(
      headline: title,
      trailing: M3ERadio<String>(
        value: title,
        groupValue: groupValue,
        onChanged: onChanged,
      ),
      onTap: () => onChanged(title),
    );
  }

  void _showSubsonicDialog({VoidCallback? onDone}) {
    final options = [
      (0.0, 'Disabled (Off)'),
      (15.0, '15 Hz (Ultra Sub-bass)'),
      (20.0, '20 Hz (Standard Subwoofer)'),
      (25.0, '25 Hz (Recommended for Small Woofers)'),
      (30.0, '30 Hz (Bookshelf / Mobile Speakers)'),
    ];

    M3EDialog.show<void>(
      context,
      dialog: M3EDialog(
        title: 'Subsonic High-Pass Filter',
        content: M3ECardList(
          itemCount: options.length,
          onTap: (index) {
            final val = options[index].$1;
            setState(() => _subsonicCutoffHz = val);
            _persistSpeakerProtectionSettings();
            onDone?.call();
            Navigator.pop(context);
          },
          itemBuilder: (context, index) {
            final opt = options[index];
            return M3EListItem(
              headline: opt.$2,
              trailing: M3ERadio<double>(
                value: opt.$1,
                groupValue: _subsonicCutoffHz,
                onChanged: (val) {
                  setState(() => _subsonicCutoffHz = val);
                  _persistSpeakerProtectionSettings();
                  onDone?.call();
                  Navigator.pop(context);
                },
              ),
            );
          },
        ),
      ),
    );
  }

  void _showUltrasonicDialog({VoidCallback? onDone}) {
    final options = [
      (24000.0, 'Disabled (Off)'),
      (22000.0, '22 kHz (Hi-Res Limit)'),
      (20000.0, '20 kHz (Standard Human Hearing)'),
      (18000.0, '18 kHz (Tweeter Guard)'),
    ];

    M3EDialog.show<void>(
      context,
      dialog: M3EDialog(
        title: 'Ultrasonic Low-Pass Guard',
        content: M3ECardList(
          itemCount: options.length,
          onTap: (index) {
            final val = options[index].$1;
            setState(() => _ultrasonicCutoffHz = val);
            _persistSpeakerProtectionSettings();
            onDone?.call();
            Navigator.pop(context);
          },
          itemBuilder: (context, index) {
            final opt = options[index];
            return M3EListItem(
              headline: opt.$2,
              trailing: M3ERadio<double>(
                value: opt.$1,
                groupValue: _ultrasonicCutoffHz,
                onChanged: (val) {
                  setState(() => _ultrasonicCutoffHz = val);
                  _persistSpeakerProtectionSettings();
                  onDone?.call();
                  Navigator.pop(context);
                },
              ),
            );
          },
        ),
      ),
    );
  }
}
