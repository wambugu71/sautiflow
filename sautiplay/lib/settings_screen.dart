import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:sautiflow/sautiflow.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:flutter_m3shapes_extended/flutter_m3shapes_extended.dart';
import 'package:material_3_expressive/material_3_expressive.dart';

import 'eq_screen.dart';
import 'isolate_player.dart';
import 'widgets/app_m3e_widgets.dart';
import 'network_sources_screen.dart';
import 'services/app_state_service.dart';
import 'services/app_theme_service.dart';
import 'services/cached_stream_service.dart';
import 'services/lastfm_service.dart';
import 'streaming_service.dart';
import 'services/app_update_service.dart';
import 'widgets/app_update_dialog.dart';
import 'widgets/album_art_shape_selector.dart';
import 'faq_screen.dart';

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
  final String analyzerWindowType;
  final ValueChanged<String> onAnalyzerWindowTypeChanged;
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
    this.analyzerWindowType = 'hann',
    required this.onAnalyzerWindowTypeChanged,
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
  AudioQualityPreset _streamingQualityPreset = AudioQualityPreset.audiophile;
  bool _preferNativeAac = false;
  bool _enableHostedFallback = true;
  bool _gaplessPlayback = true;
  bool _normalizeVolume = false;
  bool _streamOverWifi = true;

  // Engine Resampling & Dithering
  int _resampleAlgorithm = 0;
  int _ditherMode = 0;
  int _eqBandCount = 10;

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

  // Fixed Output Buffer & Latency
  int _outputBufferFrames = 0;
  int _outputBufferPeriods = 0;

  // Android Audio Output Backend & Hardware
  AudioOutputBackend _selectedBackend = AudioOutputBackend.auto;
  String _detectedDspHardware = '';
  // String _detectedSocModel = '';

  // Neutron HiFi Engine Settings
  bool _use64BitProcessingEnabled = false;
  bool _autoBitPerfectEnabled = true;

  // Loudness-Aware Crossfade
  bool _loudnessCrossfadeEnabled = true;

  // Waveform & Slider Seek Bar UI Settings
  bool _useWaveformSeekBar = false;
  bool _useWavySlider = true;
  double _previewSliderValue = 42.0;

  // Album Art Shape UI Settings
  bool _useM3EAlbumArtShape = false;
  StreamSubscription<bool>? _useM3EShapeSub;

  // App version state
  String _appVersion = 'v0.6.20';
  bool _autoCheckUpdates = true;

  // Changelog loaded from assets/CHANGELOG.md
  List<Map<String, dynamic>> _changelog = [];

  // Active theme ID (always synced with AppThemeProvider)
  AppThemeId get _activeThemeId => context.appTheme.id;

  StreamSubscription<void>? _audioSettingsSub;
  StreamSubscription<PlayerStatus>? _playerStatusSub;
  StreamSubscription<String>? _lastFmAuthSub;
  bool _isPlaying = false;

  @override
  void initState() {
    super.initState();
    _useM3EAlbumArtShape = AppThemeService.instance.useM3EAlbumArtShape;
    _useM3EShapeSub = AppThemeService.instance.useM3EAlbumArtShapeChanged.stream
        .listen((enabled) {
      if (mounted) {
        setState(() => _useM3EAlbumArtShape = enabled);
      }
    });
    _loadUiSettings();
    _loadChangelog();
    _audioSettingsSub = AppStateService
        .instance.audioProcessingSettingsChanged.stream
        .listen((_) {
      if (mounted) {
        _loadUiSettings();
      }
    });
    _playerStatusSub = widget.player.statusStream.listen((status) {
      if (mounted && _isPlaying != status.isPlaying) {
        setState(() => _isPlaying = status.isPlaying);
      }
    });
    _lastFmAuthSub =
        LastFmService.instance.authSuccessStream.listen((username) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Connected to Last.fm as $username!'),
            backgroundColor: const Color(0xFFD51007),
          ),
        );
      }
    });
  }

  /// Parses assets/CHANGELOG.md into a list of version entries.
  Future<void> _loadChangelog() async {
    try {
      final raw = await rootBundle.loadString('assets/CHANGELOG.md');
      final entries = <Map<String, dynamic>>[];
      Map<String, dynamic>? current;
      for (final line in raw.split('\n')) {
        final trimmed = line.trim();
        if (trimmed.startsWith('## ')) {
          if (current != null) entries.add(current);
          // Parse "## vX.Y.Z — YYYY-MM-DD" or "## vX.Y.Z — YYYY-MM"
          final header = trimmed.substring(3).trim();
          final parts = header.split(RegExp(r'\s*[–—-]\s*'));
          current = {
            'version': parts.isNotEmpty ? parts[0].trim() : header,
            'date': parts.length > 1 ? parts[1].trim() : '',
            'changes': <String>[],
          };
        } else if (trimmed.startsWith('- ') && current != null) {
          (current['changes'] as List<String>).add(trimmed.substring(2).trim());
        }
      }
      if (current != null) entries.add(current);
      if (mounted) setState(() => _changelog = entries);
    } catch (_) {}
  }

  @override
  void dispose() {
    _audioSettingsSub?.cancel();
    _playerStatusSub?.cancel();
    _lastFmAuthSub?.cancel();
    _useM3EShapeSub?.cancel();
    super.dispose();
  }

  String _getAudioProcessingSubtitle() {
    if (widget.exclusiveMode) {
      return 'Bit-Perfect exclusive mode active';
    }
    if (_autoBitPerfectEnabled) {
      return 'Auto-rate match • ${_formatAudioDepth(widget.outputFormat)}';
    }
    final depth = _formatAudioDepth(widget.outputFormat);
    final resamplerShort = _resampleAlgorithm == 12 || _resampleAlgorithm == 8
        ? 'Studio Natural'
        : _resampleAlgorithm == 11 ||
                _resampleAlgorithm == 7 ||
                _resampleAlgorithm == 9 ||
                _resampleAlgorithm == 10
            ? 'Studio Neutral'
            : _resampleAlgorithm == 1
                ? 'Ultra High Sinc'
                : _resampleAlgorithm == 2
                    ? 'High Sinc'
                    : _resampleAlgorithm == 3
                        ? 'Balanced Sinc'
                        : 'Standard Linear';
    return '$depth • $resamplerShort';
  }

  String _getAudioProcessingBadgeText() {
    return _getAudioProcessingSubtitle();
  }

  String _getStreamingQualityBadgeText() {
    switch (_streamingQualityPreset) {
      case AudioQualityPreset.low:
        return 'Data Saver';
      case AudioQualityPreset.medium:
        return 'Balanced';
      case AudioQualityPreset.high:
        return 'High';
      case AudioQualityPreset.audiophile:
        return 'Max';
    }
  }

  Future<void> _loadUiSettings() async {
    final saved = await AppStateService.instance.loadUiSettings();
    final eqSaved = await AppStateService.instance.loadEqBands();
    final oversamplingSaved =
        await AppStateService.instance.loadDspOversampling();
    final spSaved = await AppStateService.instance.loadSpeakerProtection();
    final phaseSaved = await AppStateService.instance.loadPhaseInversion();
    final lrSwap = await AppStateService.instance.loadLrSwap();
    final channelGains = await AppStateService.instance.loadChannelGains();
    final bufferConfig = await AppStateService.instance.loadOutputBuffer();
    final is64Bit = await AppStateService.instance.load64BitProcessingEnabled();
    final autoBp = await AppStateService.instance.loadAutoBitPerfectEnabled();
    final waveformSaved =
        await AppStateService.instance.loadUseWaveformSeekBar();
    final wavySaved = await AppStateService.instance.loadUseWavySlider();
    final engineSettings = await AppStateService.instance.loadEngineSettings();
    final loudnessCf = engineSettings.loudnessCrossfadeEnabled;
    final streamingPreset =
        await AppStateService.instance.loadStreamingQualityPreset();
    final preferAac = await AppStateService.instance.loadPreferNativeAac();
    final fallback = await AppStateService.instance.loadEnableHostedFallback();

    String versionStr = 'v0.6.20';
    try {
      final info = await PackageInfo.fromPlatform();
      versionStr = 'v${info.version}';
    } catch (_) {}

    final prefs = await SharedPreferences.getInstance();
    final autoCheck = prefs.getBool('auto_check_updates') ?? true;

    if (!mounted) return;
    setState(() {
      _appVersion = versionStr;
      _autoCheckUpdates = autoCheck;
      _streamingQualityPreset = streamingPreset;
      _preferNativeAac = preferAac;
      _enableHostedFallback = fallback;
      _streamingQuality = saved.streamingQuality;
      _gaplessPlayback = saved.gaplessPlayback;
      _normalizeVolume = saved.normalizeVolume;
      _streamOverWifi = saved.streamOverWifi;
      _resampleAlgorithm = saved.resampleAlgorithm;
      _ditherMode = saved.ditherMode;
      _eqBandCount = eqSaved.bandCount;
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
      _outputBufferFrames = bufferConfig.periodFrames;
      _outputBufferPeriods = bufferConfig.periodCount;
      _use64BitProcessingEnabled = is64Bit;
      _autoBitPerfectEnabled = autoBp;
      _loudnessCrossfadeEnabled = loudnessCf;
      _useWaveformSeekBar = waveformSaved;
      _useWavySlider = wavySaved;
      _useM3EAlbumArtShape = AppThemeService.instance.useM3EAlbumArtShape;
    });

    final loudnessNorm =
        await AppStateService.instance.loadLoudnessNormalizer();
    final lookaheadLim = await AppStateService.instance.loadLookaheadLimiter();

    widget.player.set64BitProcessingEnabled(is64Bit);
    widget.player.setAutoSampleRateMatchEnabled(autoBp);
    widget.player.setLoudnessCrossfadeEnabled(loudnessCf);
    widget.player.setLoudnessNormalizerEnabled(loudnessNorm.enabled);
    widget.player.setLoudnessNormalizerTarget(loudnessNorm.targetLUFS);
    widget.player.setLookaheadLimiterEnabled(lookaheadLim.enabled);
    widget.player
        .setLookaheadLimiterParams(ceilingDBTP: lookaheadLim.ceilingDBTP);
    widget.player.setPhaseInversion(
      invertLeft: _phaseInvertLeft,
      invertRight: _phaseInvertRight,
    );
    widget.player.setLrSwap(_lrSwapEnabled);
    widget.player.setChannelGainsDb(
      leftDb: _channelGainLeftDb,
      rightDb: _channelGainRightDb,
    );
    widget.player.setOutputBuffer(
      periodFrames: _outputBufferFrames,
      periodCount: _outputBufferPeriods,
    );
    _applySpeakerProtectionSettings();

    if (Platform.isAndroid) {
      widget.player.getOutputBackend().then((bk) {
        if (mounted) setState(() => _selectedBackend = bk);
      });
      widget.player.getHardwareInfo().then((info) {
        if (mounted) {
          setState(() {
            _detectedDspHardware = info.dspHardware;
            //  _detectedSocModel = info.socName;
          });
        }
      });
    }
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
                        const SizedBox(height: 12),

                        // ── GROUP 1: PLAYBACK & SOUND ──
                        _buildSectionHeader('PLAYBACK & SOUND'),
                        const SizedBox(height: 8),
                        AppCardContainer(
                          children: [
                            _buildCategoryCard(
                              title: 'Appearance',
                              subtitle:
                                  '${AppThemeService.dataFor(_activeThemeId).displayName} • ${_useWaveformSeekBar ? "Waveform" : "Classic slider"}',
                              icon: Icons.palette_outlined,
                              accentColor: _primary,
                              onTap: () => _navigateToSubScreen(
                                  _buildLookAndFeelSubScreen()),
                            ),
                            const M3EDivider(),
                            _buildCategoryCard(
                              title: 'Audio Engine',
                              subtitle: _getAudioProcessingSubtitle(),
                              icon: Icons.graphic_eq_rounded,
                              accentColor: _primary,
                              onTap: () => _navigateToSubScreen(
                                  _buildAudioProcessingSubScreen()),
                            ),
                            const M3EDivider(),
                            _buildCategoryCard(
                              title: 'Equalizer',
                              subtitle: '$_eqBandCount bands • Sound tuning',
                              icon: Icons.tune_rounded,
                              accentColor: _primary,
                              onTap: () => _navigateToSubScreen(
                                  _buildEqualizerSubScreen()),
                            ),
                            const M3EDivider(),
                            _buildCategoryCard(
                              title: 'Visualizer',
                              subtitle: widget.analyzerEnabled
                                  ? '${widget.spectrumStyle.toUpperCase()} • Live Meter'
                                  : 'Visualizer off',
                              icon: Icons.bar_chart_rounded,
                              accentColor: _primary,
                              onTap: () => _navigateToSubScreen(
                                  _buildVisualizationSubScreen()),
                            ),
                            const M3EDivider(),
                            _buildCategoryCard(
                              title: 'Playback',
                              subtitle: widget.crossfadeEnabled
                                  ? '${(widget.crossfadeDurationMs / 1000).toStringAsFixed(1)}s crossfade'
                                  : 'Gapless playback',
                              icon: Icons.queue_music_rounded,
                              accentColor: _primary,
                              onTap: () => _navigateToSubScreen(
                                  _buildPlaybackSubScreen()),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),

                        // ── GROUP 2: SOURCES & DATA ──
                        _buildSectionHeader('SOURCES & DATA'),
                        const SizedBox(height: 8),
                        AppCardContainer(
                          children: [
                            _buildCategoryCard(
                              title: 'Streaming & Storage',
                              subtitle:
                                  '${_getStreamingQualityBadgeText()} quality • Offline cache',
                              icon: Icons.stream_rounded,
                              accentColor: _primary,
                              onTap: () => _navigateToSubScreen(
                                  _buildDataAndStreamingSubScreen()),
                            ),
                            const M3EDivider(),
                            _buildCategoryCard(
                              title: 'Local & Network Audio',
                              subtitle: 'FTP servers & DLNA media hubs',
                              icon: Icons.lan_rounded,
                              accentColor: _primary,
                              onTap: () {
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
                              },
                            ),
                            const M3EDivider(),
                            AnimatedBuilder(
                              animation: LastFmService.instance,
                              builder: (context, _) {
                                final lastFm = LastFmService.instance;
                                return _buildCategoryCard(
                                  title: 'Last.fm',
                                  subtitle: lastFm.isLoggedIn
                                      ? 'Connected as ${lastFm.username}'
                                      : 'Connect account to sync scrobbles',
                                  icon: Icons.radio_rounded,
                                  accentColor: const Color(0xFFD51007),
                                  onTap: () => _navigateToSubScreen(
                                      _buildLastFmSubScreen()),
                                );
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),

                        // ── GROUP 3: SYSTEM & ABOUT ──
                        _buildSectionHeader('SYSTEM & ABOUT'),
                        const SizedBox(height: 8),
                        AppCardContainer(
                          children: [
                            ListenableBuilder(
                              listenable: AppUpdateService.instance,
                              builder: (context, _) {
                                final hasUpdate =
                                    AppUpdateService.instance.stage ==
                                            UpdateStage.available ||
                                        AppUpdateService.instance.stage ==
                                            UpdateStage.downloaded ||
                                        AppUpdateService.instance.stage ==
                                            UpdateStage.downloading;
                                return _buildCategoryCard(
                                  title: 'About & Diagnostics',
                                  subtitle: hasUpdate
                                      ? 'New update available to install'
                                      : 'v$_appVersion • FAQs & error logs',
                                  icon: Icons.admin_panel_settings_outlined,
                                  accentColor:
                                      hasUpdate ? Colors.greenAccent : _primary,
                                  alertBadge: hasUpdate ? 'Update' : null,
                                  onTap: () => _navigateToSubScreen(
                                      _buildMiscSystemSubScreen()),
                                );
                              },
                            ),
                          ],
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
    String? alertBadge,
    required VoidCallback onTap,
  }) {
    return AppSettingsTile(
      title: title,
      subtitle: subtitle,
      leading: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: accentColor.withAlpha(25),
          shape: BoxShape.circle,
        ),
        child: Center(
          child: Icon(icon, color: accentColor, size: 20),
        ),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (alertBadge != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.greenAccent.withAlpha(30),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.greenAccent.withAlpha(120)),
              ),
              child: Text(
                alertBadge,
                style: const TextStyle(
                  color: Colors.greenAccent,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 6),
          ],
          Icon(Icons.chevron_right_rounded, color: _textDark, size: 20),
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
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.15),
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Icon(icon, color: c, size: 18),
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
    return AppM3ESwitchTile(
      title: title,
      subtitle: subtitle,
      leading: secondary,
      value: value,
      onChanged: onChanged,
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
        final textPrimaryColor =
            isDarkTheme ? Colors.white : const Color(0xFF1A1A2E);

        return _buildSubScreenLayout(
          title: 'Appearance',
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
                                'Personalize colors and accent styling',
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
                        final isItemDark =
                            theme.bgDark.computeLuminance() < 0.15;
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
            // ── NOW PLAYING ALBUM ART SHAPE SECTION ─────────────────────────
            _buildSectionHeader('ALBUM ART SHAPE'),
            const SizedBox(height: 8),
            _buildCardContainer(
              children: [
                _buildM3ESwitchTile(
                  title: 'Material Shapes',
                  subtitle:
                      'Use expressive geometric shapes for album art (classic square if disabled)',
                  secondary: _buildLeadingIcon(Icons.crop_original_rounded),
                  value: _useM3EAlbumArtShape,
                  onChanged: (val) {
                    setState(() => _useM3EAlbumArtShape = val);
                    setSubState(() {});
                    AppThemeService.instance.saveUseM3EAlbumArtShape(val);
                  },
                ),
                if (_useM3EAlbumArtShape) ...[
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16.0),
                    child: M3EDivider(),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                    child: AlbumArtShapeSelector(
                      showLivePreview: true,
                      onShapeSelected: (newShape) {
                        setState(() {});
                        setSubState(() {});
                      },
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 20),
            // ── SEEK BAR & SLIDER SECTION ─────────────────────────────────
            _buildSectionHeader('SEEK BAR & PROGRESS'),
            const SizedBox(height: 8),
            _buildCardContainer(
              children: [
                _buildM3ESwitchTile(
                  title: 'Waveform Seek Bar',
                  subtitle:
                      'Display interactive audio waveforms instead of a flat progress line',
                  secondary: Center(
                    child: Icon(Icons.graphic_eq_rounded,
                        color: _primary, size: 20),
                  ),
                  value: _useWaveformSeekBar,
                  onChanged: (val) {
                    setState(() => _useWaveformSeekBar = val);
                    setSubState(() {});
                    AppStateService.instance.saveUseWaveformSeekBar(val);
                  },
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16.0),
                  child: M3EDivider(),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Center(
                            child: Icon(
                              _useWavySlider
                                  ? Icons.waves_rounded
                                  : Icons.linear_scale_rounded,
                              color: _primary,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Slider & Mini Player Animation',
                                  style: TextStyle(
                                    color: textPrimaryColor,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  _useWavySlider
                                      ? 'Travelling sine-wave animation'
                                      : 'Classic straight progress line',
                                  style: TextStyle(
                                    color: mutedText,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      // Live interactive preview of the selected M3E Slider & Mini Player Progress
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: isDarkTheme
                              ? Colors.black.withAlpha(50)
                              : Colors.black.withAlpha(10),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: context.outlineColor.withAlpha(40),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _useWavySlider
                                ? M3ESlider.wavy(
                                    value: _previewSliderValue,
                                    min: 0.0,
                                    max: 100.0,
                                    trackThickness: 8.0,
                                    cornerRadius: 8,
                                    thumbLength: 24.0,
                                    showValueIndicator: false,
                                    onChanged: (v) {
                                      setState(() => _previewSliderValue = v);
                                      setSubState(() {});
                                    },
                                  )
                                : M3ESlider(
                                    value: _previewSliderValue,
                                    min: 0.0,
                                    max: 100.0,
                                    trackThickness: 8.0,
                                    cornerRadius: 8,
                                    thumbLength: 24.0,
                                    showValueIndicator: false,
                                    onChanged: (v) {
                                      setState(() => _previewSliderValue = v);
                                      setSubState(() {});
                                    },
                                  ),
                            const SizedBox(height: 8),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: _useWavySlider
                                  ? M3EProgressIndicator.linearWavy(
                                      wavelength: 60,
                                      waveSpeed: 25,
                                      strokeWidth: 4,
                                      value: (_previewSliderValue / 100.0)
                                          .clamp(0.0, 1.0),
                                      linearSize: M3EProgressIndicatorSize.s,
                                      trackColor: Colors.white.withAlpha(20),
                                      color: _primary,
                                    )
                                  : M3EProgressIndicator.linear(
                                      value: (_previewSliderValue / 100.0)
                                          .clamp(0.0, 1.0),
                                      linearSize: M3EProgressIndicatorSize.s,
                                      trackColor: Colors.white.withAlpha(20),
                                      color: _primary,
                                    ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      // M3E Segmented button selection
                      SizedBox(
                        width: double.infinity,
                        child: M3ESegmentedButton<bool>(
                          segments: const [
                            M3ESegment<bool>(
                              value: true,
                              label: 'Wavy',
                              icon: Icon(Icons.waves_rounded, size: 18),
                            ),
                            M3ESegment<bool>(
                              value: false,
                              label: 'Straight',
                              icon: Icon(Icons.linear_scale_rounded, size: 18),
                            ),
                          ],
                          selected: {_useWavySlider},
                          onSelectionChanged: (newSelection) {
                            if (newSelection.isNotEmpty) {
                              final isWavy = newSelection.first;
                              setState(() => _useWavySlider = isWavy);
                              setSubState(() {});
                              AppStateService.instance
                                  .saveUseWavySlider(isWavy);
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            _buildSectionHeader('ONBOARDING & FEATURE TOUR'),
            const SizedBox(height: 8),
            _buildCardContainer(
              children: [
                AppSettingsTile(
                  title: 'Re-run Feature Tour',
                  subtitle:
                      'Restart the guided walkthrough of SautiPlay features',
                  leading: _buildLeadingIcon(Icons.tour_rounded),
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
          title: 'Audio Engine',
          children: [
            const SizedBox(height: 20),
            _buildSectionHeader('RESAMPLING & DITHERING'),
            const SizedBox(height: 8),
            _buildCardContainer(
              children: [
                AppSettingsValueTile(
                  headline: 'Resampler Quality',
                  supportingText:
                      _getResampleAlgorithmSupportingText(_resampleAlgorithm),
                  value: _getResampleAlgorithmShortName(_resampleAlgorithm),
                  leading: _buildLeadingIcon(Icons.memory),
                  onTap: () => _showResampleAlgorithmDialog(
                      onDone: () => setSubState(() {})),
                ),
                const M3EDivider(),
                AppSettingsValueTile(
                  headline: 'Oversampling',
                  supportingText: 'Internal anti-aliasing for audio filters',
                  value: _getOversamplingName(_dspOversampling),
                  leading: _buildLeadingIcon(Icons.blur_on),
                  onTap: () =>
                      _showOversamplingDialog(onDone: () => setSubState(() {})),
                ),
                const M3EDivider(),
                AppSettingsValueTile(
                  headline: 'Dithering',
                  supportingText:
                      'Eliminates truncation noise when bit depth changes',
                  value: _getDitherModeName(_ditherMode),
                  leading: _buildLeadingIcon(Icons.waves),
                  onTap: () =>
                      _showDitherModeDialog(onDone: () => setSubState(() {})),
                ),
              ],
            ),
            const SizedBox(height: 20),
            _buildSectionHeader('HARDWARE OUTPUT'),
            const SizedBox(height: 8),
            _buildCardContainer(
              children: [
                AppSettingsValueTile(
                  headline: 'Output Bit Depth',
                  supportingText: 'Hardware playback resolution',
                  value: _formatAudioDepth(widget.outputFormat),
                  leading: _buildLeadingIcon(Icons.code),
                  onTap: () =>
                      _showOutputFormatDialog(onDone: () => setSubState(() {})),
                ),
                const M3EDivider(),
                IgnorePointer(
                  ignoring: _autoBitPerfectEnabled,
                  child: AnimatedOpacity(
                    opacity: _autoBitPerfectEnabled ? 0.38 : 1.0,
                    duration: const Duration(milliseconds: 200),
                    child: AppSettingsValueTile(
                      headline: 'Sample Rate',
                      supportingText: _autoBitPerfectEnabled
                          ? 'Managed automatically by Auto-Match'
                          : 'Hardware output sample rate',
                      value: widget.outputSampleRate == 0
                          ? 'Native'
                          : '${widget.outputSampleRate} Hz',
                      leading: _buildLeadingIcon(Icons.speed),
                      onTap: () => _showSampleRateDialog(
                          onDone: () => setSubState(() {})),
                    ),
                  ),
                ),
                const M3EDivider(),
                AppSettingsValueTile(
                  headline: 'Output Channels',
                  supportingText: 'Speaker channel layout',
                  value: _formatChannelCount(widget.outputChannels),
                  leading: _buildLeadingIcon(Icons.speaker_group),
                  onTap: () =>
                      _showChannelsDialog(onDone: () => setSubState(() {})),
                ),
                const M3EDivider(),
                AppSettingsValueTile(
                  headline: 'Buffer & Latency',
                  supportingText: 'Hardware audio buffer size and periods',
                  value: _formatOutputBuffer(
                      _outputBufferFrames, _outputBufferPeriods),
                  leading: _buildLeadingIcon(Icons.av_timer_rounded),
                  onTap: () =>
                      _showOutputBufferDialog(onDone: () => setSubState(() {})),
                ),
                const M3EDivider(),
                _buildM3ESwitchTile(
                  title: 'Invert Left Channel Phase',
                  subtitle: 'Invert left audio polarity (180°)',
                  secondary: _buildLeadingIcon(Icons.swap_calls),
                  value: _phaseInvertLeft,
                  onChanged: (val) {
                    setState(() => _phaseInvertLeft = val);
                    _persistPhaseInversionSettings();
                    setSubState(() {});
                  },
                ),
                const M3EDivider(),
                _buildM3ESwitchTile(
                  title: 'Invert Right Channel Phase',
                  subtitle: 'Invert right audio polarity (180°)',
                  secondary: _buildLeadingIcon(Icons.swap_calls),
                  value: _phaseInvertRight,
                  onChanged: (val) {
                    setState(() => _phaseInvertRight = val);
                    _persistPhaseInversionSettings();
                    setSubState(() {});
                  },
                ),
                const M3EDivider(),
                _buildM3ESwitchTile(
                  title: 'Swap Stereo Channels',
                  subtitle: _lrSwapEnabled
                      ? 'Left and right audio channels are swapped'
                      : 'Standard stereo channel orientation',
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
                const M3EDivider(),
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
                                  style:
                                      TextStyle(color: _textDark, fontSize: 12),
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
                const M3EDivider(),
                IgnorePointer(
                  ignoring: _autoBitPerfectEnabled,
                  child: AnimatedOpacity(
                    opacity: _autoBitPerfectEnabled ? 0.38 : 1.0,
                    duration: const Duration(milliseconds: 200),
                    child: _buildM3ESwitchTile(
                      title: 'Bit-Perfect Playback',
                      subtitle: _autoBitPerfectEnabled
                          ? 'Managed automatically (Auto-Match enabled)'
                          : 'Bypasses system sound mixer for direct stream',
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
                  ),
                ),
                const M3EDivider(),
                _buildM3ESwitchTile(
                  title: '64-Bit Studio DSP',
                  subtitle: 'Ultra-high precision floating point processing',
                  secondary: _buildLeadingIcon(Icons.architecture),
                  value: _use64BitProcessingEnabled,
                  onChanged: (val) {
                    setState(() => _use64BitProcessingEnabled = val);
                    widget.player.set64BitProcessingEnabled(val);
                    AppStateService.instance.save64BitProcessingEnabled(val);
                    setSubState(() {});
                  },
                ),
                const M3EDivider(),
                _buildM3ESwitchTile(
                  title: 'Auto Sample-Rate Match',
                  subtitle: 'Auto match hardware rate to source (Recomended)',
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
                if (Platform.isAndroid) ...[
                  const M3EDivider(),
                  AppSettingsValueTile(
                    headline: 'Android Audio Backend',
                    supportingText:
                        'Low-level driver (${_selectedBackend.displayName})',
                    value: _selectedBackend.displayName,
                    leading: _buildLeadingIcon(Icons.developer_board_rounded),
                    onTap: () =>
                        _showAndroidBackendPicker(context, setSubState),
                  ),
                  if (_detectedDspHardware.isNotEmpty) ...[
                    const M3EDivider(),
                    AppSettingsTile(
                      title: 'Hardware Audio DSP',
                      subtitle: _detectedDspHardware,
                      leading: _buildLeadingIcon(Icons.memory_rounded),
                    ),
                  ],
                ],
              ],
            ),
            const SizedBox(height: 20),
            _buildSectionHeader('SPEAKER & EAR PROTECTION'),
            const SizedBox(height: 8),
            _buildCardContainer(
              children: [
                _buildM3ESwitchTile(
                  title: 'Speaker & Ear Safeguards',
                  subtitle: _speakerProtectionEnabled
                      ? 'Peak ceiling limiter & frequency filters active'
                      : 'Protection filters disabled',
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
                  const M3EDivider(),
                  AppSettingsValueTile(
                    headline: 'Sub-Bass Rumble Filter',
                    supportingText: 'Cuts frequencies below speaker limit',
                    value: _subsonicCutoffHz <= 0
                        ? 'Off'
                        : '${_subsonicCutoffHz.toInt()} Hz',
                    leading: _buildLeadingIcon(Icons.arrow_upward),
                    onTap: () =>
                        _showSubsonicDialog(onDone: () => setSubState(() {})),
                  ),
                  const M3EDivider(),
                  AppSettingsValueTile(
                    headline: 'Ultrasonic Noise Filter',
                    supportingText: 'Cuts inaudible high-frequency noise',
                    value: _ultrasonicCutoffHz >= 24000
                        ? 'Off'
                        : '${(_ultrasonicCutoffHz / 1000).toStringAsFixed(1)} kHz',
                    leading: _buildLeadingIcon(Icons.keyboard_arrow_down),
                    onTap: () =>
                        _showUltrasonicDialog(onDone: () => setSubState(() {})),
                  ),
                  const M3EDivider(),
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
                  const M3EDivider(),
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
              ],
            ),
            const SizedBox(height: 32),
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
          title: 'Equalizer',
          children: [
            const SizedBox(height: 20),
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
                                Text('EQ Band Layout',
                                    style: TextStyle(
                                        color: _textPrimary,
                                        fontSize: 16,
                                        fontWeight: FontWeight.w500)),
                                const SizedBox(height: 4),
                                Text('Select number of graphic frequency bands',
                                    style: TextStyle(
                                        color: _textDark, fontSize: 13)),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        child: M3ESegmentedButton<int>(
                          segments: const [
                            M3ESegment<int>(
                              value: 10,
                              label: '10-Band',
                              icon: Icon(Icons.graphic_eq_rounded, size: 16),
                            ),
                            M3ESegment<int>(
                              value: 16,
                              label: '16-Band',
                              icon: Icon(Icons.equalizer_rounded, size: 16),
                            ),
                            M3ESegment<int>(
                              value: 32,
                              label: '32-Band',
                              icon: Icon(Icons.tune_rounded, size: 16),
                            ),
                          ],
                          selected: {_eqBandCount},
                          onSelectionChanged: (newSelection) async {
                            if (newSelection.isNotEmpty) {
                              final count = newSelection.first;
                              setState(() => _eqBandCount = count);
                              setSubState(() {});
                              final state =
                                  await AppStateService.instance.loadEqBands();
                              await AppStateService.instance.saveEqBands(
                                enabled: state.enabled,
                                preset: state.preset,
                                gains: List.filled(count, 0.0),
                                preampDb: state.preampDb,
                                bandCount: count,
                              );
                            }
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

  // 4. Visualization Sub-Screen
  Widget _buildVisualizationSubScreen() {
    return StatefulBuilder(
      builder: (context, setSubState) {
        final isArea = widget.analyzerType == 'area';
        final activeStyleName = widget.spectrumStyle.toLowerCase();

        return _buildSubScreenLayout(
          title: 'Visualizer',
          children: [
            const SizedBox(height: 20),
            // ── TOP LIVE RTA & RMS LOUDNESS CARD ────────────────────────────
            _buildSectionHeader('LIVE VOLUME & PEAK METER'),
            const SizedBox(height: 8),
            AppCardContainer(
              padding: const EdgeInsets.all(16.0),
              children: [
                Row(
                  children: [
                    AppShapeIcon(
                      Icons.speed_rounded,
                      shape: Shapes.pill,
                      color: widget.analyzerEnabled ? _primary : _textDark,
                      size: 38,
                      iconSize: 20,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'RMS Level & Peak',
                            style: TextStyle(
                              color: _textPrimary,
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            widget.analyzerEnabled
                                ? (_isPlaying
                                    ? 'Live stereo level meter'
                                    : 'Awaiting playback')
                                : 'Level meter bypassed',
                            style: TextStyle(
                              color: _textDark,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    AppStatusBadge(
                      text: widget.analyzerEnabled
                          ? (_isPlaying ? 'ACTIVE' : 'STANDBY')
                          : 'OFF',
                      color: widget.analyzerEnabled
                          ? (_isPlaying ? Colors.greenAccent : _primary)
                          : _textDark,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Container(
                  decoration: BoxDecoration(
                    color: context.bgDark.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: widget.analyzerEnabled
                          ? _primary.withValues(alpha: 0.25)
                          : context.outlineColor,
                    ),
                  ),
                  clipBehavior: Clip.antiAlias,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12.0, vertical: 12.0),
                  child: widget.analyzerEnabled
                      ? RmsMeterWidget(
                          analyzerStream: widget.player.analyzerStream,
                          isPlaying: _isPlaying,
                        )
                      : Container(
                          height: 52,
                          alignment: Alignment.center,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.graphic_eq_rounded,
                                color: _textDark.withValues(alpha: 0.4),
                                size: 22,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Audio meter paused',
                                style: TextStyle(
                                  color: _textDark,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                ),
              ],
            ),

            const SizedBox(height: 20),

            // ── SPECTRUM ENGINE & RENDERING CARD ──────────────────────────
            _buildSectionHeader('SPECTRUM DISPLAY & STYLE'),
            const SizedBox(height: 8),
            _buildCardContainer(
              children: [
                _buildM3ESwitchTile(
                  title: 'Spectrum Analyzer',
                  subtitle: 'Real-time audio frequency visualizer',
                  secondary: _buildLeadingIcon(Icons.bar_chart_rounded),
                  value: widget.analyzerEnabled,
                  onChanged: (v) {
                    widget.onAnalyzerEnabledChanged(v);
                    setSubState(() {});
                  },
                ),
                if (widget.analyzerEnabled) ...[
                  const M3EDivider(),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20.0, vertical: 16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Visual Style',
                          style: TextStyle(
                            color: _textPrimary,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Frequency bars or continuous wave',
                          style: TextStyle(color: _textDark, fontSize: 12),
                        ),
                        const SizedBox(height: 14),
                        SizedBox(
                          width: double.infinity,
                          child: M3ESegmentedButton<String>(
                            segments: const [
                              M3ESegment(
                                value: 'bar',
                                label: 'Bars',
                                icon: Icon(Icons.bar_chart_rounded, size: 18),
                              ),
                              M3ESegment(
                                value: 'area',
                                label: 'Wave',
                                icon: Icon(Icons.show_chart_rounded, size: 18),
                              ),
                            ],
                            selected: {isArea ? 'area' : 'bar'},
                            onSelectionChanged: (val) {
                              if (val.isNotEmpty) {
                                widget.onAnalyzerTypeChanged(val.first);
                                setSubState(() {});
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                  const M3EDivider(),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20.0, vertical: 16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Color Theme',
                          style: TextStyle(
                            color: _textPrimary,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Gradient color preset for spectrum bars',
                          style: TextStyle(color: _textDark, fontSize: 12),
                        ),
                        const SizedBox(height: 14),
                        SizedBox(
                          width: double.infinity,
                          child: M3ESegmentedButton<String>(
                            segments: const [
                              M3ESegment(
                                value: 'neon',
                                label: 'Neon',
                                icon:
                                    Icon(Icons.auto_awesome_rounded, size: 16),
                              ),
                              M3ESegment(
                                value: 'fire',
                                label: 'Fire',
                                icon: Icon(Icons.local_fire_department_rounded,
                                    size: 16),
                              ),
                              M3ESegment(
                                value: 'minimal',
                                label: 'Clean',
                                icon: Icon(Icons.horizontal_rule_rounded,
                                    size: 16),
                              ),
                              M3ESegment(
                                value: 'pill',
                                label: 'Pill',
                                icon: Icon(Icons.lens_blur_rounded, size: 16),
                              ),
                            ],
                            selected: {
                              ['neon', 'fire', 'minimal', 'pill']
                                      .contains(activeStyleName)
                                  ? activeStyleName
                                  : 'minimal'
                            },
                            onSelectionChanged: (val) {
                              if (val.isNotEmpty) {
                                widget.onSpectrumStyleChanged(val.first);
                                setSubState(() {});
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                  const M3EDivider(),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20.0, vertical: 14.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Visualizer Presets',
                              style: TextStyle(
                                color: _textPrimary,
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Quick 1-tap style configurations',
                              style: TextStyle(color: _textDark, fontSize: 12),
                            ),
                          ],
                        ),
                        M3EMenu(
                          anchorBuilder: (context, open) => M3EButton.icon(
                            onPressed: open,
                            icon: const Icon(Icons.auto_fix_high_rounded,
                                size: 16),
                            label: const Text('Presets'),
                          ),
                          children: [
                            M3EMenuGroup.entries(
                              entries: [
                                M3EMenuEntry(
                                  label: 'Balanced (Bars • Neon)',
                                  leading: const Icon(Icons.bar_chart_rounded,
                                      size: 18),
                                  onPressed: () => _applyVisualizerPreset(
                                      'balanced', setSubState),
                                ),
                                M3EMenuEntry(
                                  label: 'Smooth Wave (Fire)',
                                  leading: const Icon(Icons.show_chart_rounded,
                                      size: 18),
                                  onPressed: () => _applyVisualizerPreset(
                                      'smooth_curve', setSubState),
                                ),
                                M3EMenuEntry(
                                  label: 'Studio Detail (Pills)',
                                  leading: const Icon(Icons.lens_blur_rounded,
                                      size: 18),
                                  onPressed: () => _applyVisualizerPreset(
                                      'audiophile_precision', setSubState),
                                ),
                                M3EMenuEntry(
                                  label: 'Minimalist (Clean Wave)',
                                  leading: const Icon(
                                      Icons.horizontal_rule_rounded,
                                      size: 18),
                                  onPressed: () => _applyVisualizerPreset(
                                      'minimalist', setSubState),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),

            const SizedBox(height: 20),

            // ── SCALING & GRID DYNAMICS CARD ──────────────────────────────
            if (widget.analyzerEnabled) ...[
              _buildSectionHeader('SCALING & DISPLAY'),
              const SizedBox(height: 8),
              _buildCardContainer(
                children: [
                  _buildM3ESwitchTile(
                    title: 'Auto-Fit Peak Height',
                    subtitle: 'Dynamically adapts visualizer height to volume',
                    secondary: _buildLeadingIcon(Icons.fit_screen_rounded),
                    value: widget.analyzerAutoFit,
                    onChanged: (v) {
                      widget.onAnalyzerAutoFitChanged(v);
                      setSubState(() {});
                    },
                  ),
                  const M3EDivider(),
                  _buildM3ESwitchTile(
                    title: 'Show Grids & Decibels',
                    subtitle: 'Display level grid and frequency axis markers',
                    secondary: _buildLeadingIcon(Icons.grid_4x4_rounded),
                    value: widget.analyzerShowGrids,
                    onChanged: (v) {
                      widget.onAnalyzerShowGridsChanged(v);
                      setSubState(() {});
                    },
                  ),
                  const M3EDivider(),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20.0, vertical: 14.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            _buildLeadingIcon(Icons.tune_rounded),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Frequency Scale',
                                    style: TextStyle(
                                      color: _textPrimary,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    widget.analyzerLogScale
                                        ? 'Logarithmic: Follows natural hearing'
                                        : 'Linear: Even spacing across bandwidth',
                                    style: TextStyle(
                                        color: _textDark, fontSize: 12),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: M3ESegmentedButton<bool>(
                            segments: const [
                              M3ESegment(
                                value: true,
                                label: 'Logarithmic',
                                icon: Icon(Icons.tune_rounded, size: 16),
                              ),
                              M3ESegment(
                                value: false,
                                label: 'Linear',
                                icon:
                                    Icon(Icons.linear_scale_rounded, size: 16),
                              ),
                            ],
                            selected: {widget.analyzerLogScale},
                            onSelectionChanged: (val) {
                              if (val.isNotEmpty) {
                                widget.onAnalyzerLogScaleChanged(val.first);
                                setSubState(() {});
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // ── FFT RESOLUTION & PERFORMANCE CARD ───────────────────────
              _buildSectionHeader('FREQUENCY RESOLUTION & FILTER'),
              const SizedBox(height: 8),
              _buildCardContainer(
                children: [
                  AppSettingsValueTile(
                    headline: 'Resolution & Speed',
                    supportingText:
                        _getFftSampleSizeDescription(widget.analyzerSampleSize),
                    value: '${widget.analyzerSampleSize} pts',
                    leading: _buildLeadingIcon(Icons.data_array_rounded),
                    onTap: () => _showAnalyzerSampleSizeDialog(
                      onDone: () => setSubState(() {}),
                    ),
                  ),
                  const M3EDivider(),
                  AppSettingsValueTile(
                    headline: 'Window Filter Shape',
                    supportingText:
                        _getFftWindowDescription(widget.analyzerWindowType),
                    value: _getFftWindowDisplayName(widget.analyzerWindowType),
                    leading: _buildLeadingIcon(Icons.waves_rounded),
                    onTap: () => _showAnalyzerWindowDialog(
                      onDone: () => setSubState(() {}),
                    ),
                  ),
                ],
              ),
            ],
          ],
        );
      },
    );
  }

  String _getFftWindowDisplayName(String type) {
    return FftWindowType.fromString(type).displayName;
  }

  String _getFftWindowDescription(String type) {
    switch (FftWindowType.fromString(type)) {
      case FftWindowType.hann:
        return 'Smooth, balanced visual response (Recommended)';
      case FftWindowType.hamming:
        return 'Sharp peak separation for tonal music';
      case FftWindowType.blackmanHarris:
        return 'Maximum clarity with lowest spectral blur';
      case FftWindowType.flatTop:
        return 'Calibrated amplitude accuracy';
    }
  }

  String _getFftSampleSizeDescription(int size) {
    switch (size) {
      case 256:
        return 'Fastest response • Lowest latency';
      case 512:
        return 'Snappy & responsive';
      case 1024:
        return 'Balanced detail and speed (Recommended)';
      case 2048:
        return 'High resolution frequency bars';
      case 4096:
        return 'Studio precision detail';
      case 8192:
        return 'Ultra-high resolution';
      default:
        return '$size samples';
    }
  }

  void _applyVisualizerPreset(String preset, StateSetter setSubState) {
    switch (preset) {
      case 'balanced':
        widget.onAnalyzerEnabledChanged(true);
        widget.onAnalyzerTypeChanged('bar');
        widget.onSpectrumStyleChanged('neon');
        widget.onAnalyzerAutoFitChanged(true);
        widget.onAnalyzerShowGridsChanged(true);
        widget.onAnalyzerLogScaleChanged(true);
        widget.onAnalyzerSampleSizeChanged(1024);
        widget.onAnalyzerWindowTypeChanged('hann');
        widget.player.configureAnalyzer(frameSize: 1024, windowType: 'hann');
        break;
      case 'smooth_curve':
        widget.onAnalyzerEnabledChanged(true);
        widget.onAnalyzerTypeChanged('area');
        widget.onSpectrumStyleChanged('fire');
        widget.onAnalyzerAutoFitChanged(true);
        widget.onAnalyzerShowGridsChanged(true);
        widget.onAnalyzerLogScaleChanged(true);
        widget.onAnalyzerSampleSizeChanged(2048);
        widget.onAnalyzerWindowTypeChanged('hann');
        widget.player.configureAnalyzer(frameSize: 2048, windowType: 'hann');
        break;
      case 'audiophile_precision':
        widget.onAnalyzerEnabledChanged(true);
        widget.onAnalyzerTypeChanged('bar');
        widget.onSpectrumStyleChanged('pill');
        widget.onAnalyzerAutoFitChanged(false);
        widget.onAnalyzerShowGridsChanged(true);
        widget.onAnalyzerLogScaleChanged(true);
        widget.onAnalyzerSampleSizeChanged(4096);
        widget.onAnalyzerWindowTypeChanged('blackman_harris');
        widget.player
            .configureAnalyzer(frameSize: 4096, windowType: 'blackman_harris');
        break;
      case 'minimalist':
        widget.onAnalyzerEnabledChanged(true);
        widget.onAnalyzerTypeChanged('area');
        widget.onSpectrumStyleChanged('minimal');
        widget.onAnalyzerAutoFitChanged(true);
        widget.onAnalyzerShowGridsChanged(false);
        widget.onAnalyzerLogScaleChanged(false);
        widget.onAnalyzerSampleSizeChanged(512);
        widget.onAnalyzerWindowTypeChanged('hamming');
        widget.player.configureAnalyzer(frameSize: 512, windowType: 'hamming');
        break;
    }
    setSubState(() {});
    setState(() {});
  }

  // 5. Playback & Crossfade Sub-Screen
  Widget _buildPlaybackSubScreen() {
    return StatefulBuilder(
      builder: (context, setSubState) {
        return _buildSubScreenLayout(
          title: 'Playback',
          children: [
            const SizedBox(height: 20),
            _buildSectionHeader('TRANSITIONS & PLAYBACK'),
            const SizedBox(height: 8),
            _buildCardContainer(
              children: [
                _buildM3ESwitchTile(
                  title: 'Gapless Playback',
                  subtitle:
                      'Seamless transitions between continuous album tracks',
                  secondary: _buildLeadingIcon(Icons.queue_music),
                  value: _gaplessPlayback,
                  onChanged: (v) {
                    setState(() => _gaplessPlayback = v);
                    setSubState(() {});
                    _persistUiSettings();
                  },
                ),
                const M3EDivider(),
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
                const M3EDivider(),
                if (widget.crossfadeEnabled) ...[
                  _buildM3ESwitchTile(
                    title: 'Smart Loudness Crossfade',
                    subtitle: _loudnessCrossfadeEnabled
                        ? 'Equalizes track volume before crossfading'
                        : 'Off (standard volume blend)',
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
                  const M3EDivider(),
                ],
                _buildM3ESwitchTile(
                  title: 'ReplayGain Volume Normalization',
                  subtitle: 'Keeps consistent volume level across tracks',
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

  // 6. Data & Streaming Sub-Screen
  Widget _buildDataAndStreamingSubScreen() {
    return StatefulBuilder(
      builder: (context, setSubState) {
        return _buildSubScreenLayout(
          title: 'Streaming & Storage',
          children: [
            const SizedBox(height: 20),
            // ── AUDIO STREAMING QUALITY ──────────────────────────────────────
            _buildSectionHeader('STREAMING QUALITY'),
            const SizedBox(height: 8),
            _buildCardContainer(
              children: [
                _buildQualityOptionTile(
                  title: 'Max Quality',
                  subtitle: 'Highest bitrate, best dynamic range',
                  preset: AudioQualityPreset.audiophile,
                  badge: 'Max',
                  setSubState: setSubState,
                ),
                const M3EDivider(),
                _buildQualityOptionTile(
                  title: 'High Quality',
                  subtitle: 'Balanced quality with good hardware decoding',
                  preset: AudioQualityPreset.high,
                  badge: 'High',
                  setSubState: setSubState,
                ),
                const M3EDivider(),
                _buildQualityOptionTile(
                  title: 'Balanced',
                  subtitle: 'Good balance of quality and data usage',
                  preset: AudioQualityPreset.medium,
                  badge: 'Balanced',
                  setSubState: setSubState,
                ),
                const M3EDivider(),
                _buildQualityOptionTile(
                  title: 'Data Saver',
                  subtitle: 'Minimal bandwidth',
                  preset: AudioQualityPreset.low,
                  badge: 'Data Saver',
                  setSubState: setSubState,
                ),
              ],
            ),
            const SizedBox(height: 20),

            // ── HARDWARE & CONTAINER PREFERENCES ────────────────────────────
            _buildSectionHeader('STREAMING OPTIMIZATION'),
            const SizedBox(height: 8),
            _buildCardContainer(
              children: [
                _buildM3ESwitchTile(
                  title: 'Prioritize Native AAC Audio',
                  subtitle:
                      'Plays M4A streams directly for lower battery usage',
                  secondary: _buildLeadingIcon(Icons.memory_rounded),
                  value: _preferNativeAac,
                  onChanged: (val) {
                    setState(() => _preferNativeAac = val);
                    setSubState(() {});
                    AppStateService.instance.savePreferNativeAac(val);
                  },
                ),
                const M3EDivider(),
                _buildM3ESwitchTile(
                  title: 'Stream Mirror Fallback',
                  subtitle:
                      'Automatically try alternate servers if playback fails',
                  secondary: _buildLeadingIcon(
                    Icons.cloud_sync_rounded,
                    _enableHostedFallback ? _primary : _textDark,
                  ),
                  value: _enableHostedFallback,
                  onChanged: (val) {
                    setState(() => _enableHostedFallback = val);
                    setSubState(() {});
                    AppStateService.instance.saveEnableHostedFallback(val);
                  },
                ),
              ],
            ),
            const SizedBox(height: 20),

            // ── CACHE & STORAGE ─────────────────────────────────────────────
            _buildSectionHeader('OFFLINE STREAM CACHE'),
            const SizedBox(height: 8),
            _buildCardContainer(
              children: [
                ValueListenableBuilder<int>(
                  valueListenable:
                      CachedStreamService.instance.totalSizeBytesNotifier,
                  builder: (context, totalBytes, _) {
                    return AppSettingsTile(
                      title: 'Cached Audio Data',
                      subtitle: 'Stored audio files for instant playback',
                      leading: _buildLeadingIcon(Icons.dns_rounded),
                      trailing: Text(
                        CachedStreamService.formatBytes(totalBytes),
                        style: TextStyle(
                          color: _primary,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    );
                  },
                ),
                const M3EDivider(),
                AppSettingsTile(
                  title: 'Clear Audio Cache',
                  subtitle: 'Free up local storage without affecting playlists',
                  leading: _buildLeadingIcon(
                      Icons.cleaning_services_rounded, Colors.redAccent),
                  trailing: const Icon(Icons.chevron_right_rounded,
                      color: Colors.redAccent, size: 20),
                  onTap: () async {
                    await CachedStreamService.instance.clearAllCache();
                    StreamingService.clearCache();
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: const Text('Audio cache purged successfully'),
                        backgroundColor: _cardDark,
                      ));
                    }
                  },
                ),
              ],
            ),
            const SizedBox(height: 30),
          ],
        );
      },
    );
  }

  Widget _buildQualityOptionTile({
    required String title,
    required String subtitle,
    required AudioQualityPreset preset,
    required String badge,
    required StateSetter setSubState,
  }) {
    final isSelected = _streamingQualityPreset == preset;
    return InkWell(
      onTap: () {
        setState(() => _streamingQualityPreset = preset);
        setSubState(() {});
        AppStateService.instance.saveStreamingQualityPreset(preset);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(
              isSelected
                  ? Icons.radio_button_checked_rounded
                  : Icons.radio_button_off_rounded,
              color: isSelected ? _primary : _textDark,
              size: 22,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          color: isSelected ? _primary : _textPrimary,
                          fontWeight:
                              isSelected ? FontWeight.bold : FontWeight.w500,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? _primary.withValues(alpha: 0.15)
                              : _cardDark,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: isSelected
                                ? _primary.withValues(alpha: 0.3)
                                : Colors.white10,
                          ),
                        ),
                        child: Text(
                          badge,
                          style: TextStyle(
                            color: isSelected ? _primary : _textDark,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(color: _textDark, fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showChangelogBottomSheet() {
    M3EBottomSheet.show<void>(
      context,
      builder: (ctx) => _buildModalBottomSheetLayout(
        title: 'Release Notes & Changelog',
        subtitle: 'What\'s new and improved in SautiPlay',
        height: MediaQuery.of(context).size.height * 0.85,
        child: _buildChangelogView(),
      ),
    );
  }

  Widget _buildChangelogView() {
    if (_changelog.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(32),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      itemCount: _changelog.length,
      separatorBuilder: (_, __) => const SizedBox(height: 14),
      itemBuilder: (context, index) {
        final entry = _changelog[index];
        final version = (entry['version'] as String?) ?? '';
        final date = (entry['date'] as String?) ?? '';
        final changes = (entry['changes'] as List<dynamic>?) ?? [];
        final isCurrentVersion = version
                .toLowerCase()
                .contains(_appVersion.toLowerCase().replaceAll('v', '')) ||
            _appVersion
                .toLowerCase()
                .contains(version.toLowerCase().replaceAll('v', ''));

        return Container(
          decoration: BoxDecoration(
            color: isCurrentVersion
                ? _primary.withValues(alpha: 0.08)
                : context.cardDark,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isCurrentVersion
                  ? _primary.withValues(alpha: 0.45)
                  : context.outlineColor,
              width: isCurrentVersion ? 1.5 : 1.0,
            ),
          ),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: _primary.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                      border:
                          Border.all(color: _primary.withValues(alpha: 0.4)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.new_releases_rounded,
                            size: 14, color: _primary),
                        const SizedBox(width: 6),
                        Text(
                          version,
                          style: TextStyle(
                            color: _primary,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (isCurrentVersion) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.green.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: Colors.green.withValues(alpha: 0.4)),
                      ),
                      child: const Text(
                        'CURRENT',
                        style: TextStyle(
                          color: Colors.greenAccent,
                          fontWeight: FontWeight.bold,
                          fontSize: 10,
                        ),
                      ),
                    ),
                  ],
                  const Spacer(),
                  if (date.isNotEmpty)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.calendar_today_outlined,
                            size: 13, color: _textDark),
                        const SizedBox(width: 4),
                        Text(
                          date,
                          style: TextStyle(
                            color: _textDark,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                ],
              ),
              if (changes.isNotEmpty) ...[
                const SizedBox(height: 12),
                const M3EDivider(),
                const SizedBox(height: 10),
                ...changes.map((c) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8.0),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          margin: const EdgeInsets.only(top: 7, right: 10),
                          decoration: BoxDecoration(
                            color: isCurrentVersion
                                ? _primary
                                : _textDark.withValues(alpha: 0.6),
                            shape: BoxShape.circle,
                          ),
                        ),
                        Expanded(
                          child: _buildFormattedMarkdownText(
                            c as String,
                            baseStyle: TextStyle(
                              color:
                                  isCurrentVersion ? _textPrimary : _textDark,
                              fontSize: 13,
                              height: 1.45,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildFormattedMarkdownText(String text, {TextStyle? baseStyle}) {
    final style =
        baseStyle ?? TextStyle(color: _textDark, fontSize: 13, height: 1.45);
    final spans = <InlineSpan>[];
    final regex = RegExp(r'(`[^`]+`|\*\*[^*]+\*\*|\*[^*]+\*)');
    int lastMatchEnd = 0;

    for (final match in regex.allMatches(text)) {
      if (match.start > lastMatchEnd) {
        spans.add(TextSpan(
          text: text.substring(lastMatchEnd, match.start),
          style: style,
        ));
      }
      final matchedText = match.group(0)!;
      if (matchedText.startsWith('`') && matchedText.endsWith('`')) {
        final codeContent = matchedText.substring(1, matchedText.length - 1);
        spans.add(
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
              margin: const EdgeInsets.symmetric(horizontal: 2),
              decoration: BoxDecoration(
                color: _primary.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: _primary.withValues(alpha: 0.3)),
              ),
              child: Text(
                codeContent,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: (style.fontSize ?? 13) * 0.88,
                  fontWeight: FontWeight.w600,
                  color: _primary,
                ),
              ),
            ),
          ),
        );
      } else if (matchedText.startsWith('**') && matchedText.endsWith('**')) {
        final boldContent = matchedText.substring(2, matchedText.length - 2);
        spans.add(TextSpan(
          text: boldContent,
          style:
              style.copyWith(fontWeight: FontWeight.bold, color: _textPrimary),
        ));
      } else if (matchedText.startsWith('*') && matchedText.endsWith('*')) {
        final italicContent = matchedText.substring(1, matchedText.length - 1);
        spans.add(TextSpan(
          text: italicContent,
          style: style.copyWith(fontStyle: FontStyle.italic),
        ));
      }
      lastMatchEnd = match.end;
    }

    if (lastMatchEnd < text.length) {
      spans.add(TextSpan(
        text: text.substring(lastMatchEnd),
        style: style,
      ));
    }

    return Text.rich(TextSpan(children: spans));
  }

  // 7. Misc & System Sub-Screen
  Widget _buildMiscSystemSubScreen() {
    return StatefulBuilder(
      builder: (context, setSubState) {
        return _buildSubScreenLayout(
          title: 'About & Diagnostics',
          children: [
            const SizedBox(height: 20),
            _buildSectionHeader('ABOUT & SYSTEM LICENSES'),
            const SizedBox(height: 8),
            _buildCardContainer(
              children: [
                AppSettingsTile(
                  title: 'Version',
                  leading: _buildLeadingIcon(Icons.info_outline),
                  trailing: Text(_appVersion,
                      style: TextStyle(color: _textDark, fontSize: 14)),
                ),
                const M3EDivider(),
                ListenableBuilder(
                  listenable: AppUpdateService.instance,
                  builder: (context, _) {
                    final updateService = AppUpdateService.instance;
                    final isChecking =
                        updateService.stage == UpdateStage.checking;
                    final isAvailable =
                        updateService.stage == UpdateStage.available;
                    final isDownloaded =
                        updateService.stage == UpdateStage.downloaded;
                    final isDownloading =
                        updateService.stage == UpdateStage.downloading;

                    String subtitle = 'Check GitHub for new releases';
                    Widget? trailing;

                    if (isChecking) {
                      subtitle = 'Checking for updates...';
                      trailing = SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(_primary),
                        ),
                      );
                    } else if (isDownloading) {
                      final pct =
                          (updateService.downloadProgress * 100).toInt();
                      subtitle = 'Downloading update ($pct%)...';
                      trailing = Text(
                        '$pct%',
                        style: TextStyle(
                          color: _primary,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      );
                    } else if (isAvailable || isDownloaded) {
                      final release = updateService.release;
                      subtitle = isDownloaded
                          ? 'Downloaded ${release?.tagName ?? ""}. Ready to install!'
                          : 'New version ${release?.tagName ?? ""} available!';
                      trailing = Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.green.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                              color: Colors.greenAccent.withValues(alpha: 0.5)),
                        ),
                        child: const Text(
                          'UPDATE',
                          style: TextStyle(
                            color: Colors.greenAccent,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      );
                    } else if (updateService.stage == UpdateStage.error) {
                      subtitle = 'Update check failed. Tap to retry.';
                      trailing = const Icon(Icons.refresh_rounded,
                          color: Colors.orangeAccent, size: 20);
                    } else {
                      trailing = Icon(Icons.chevron_right_rounded,
                          color: _textDark, size: 20);
                    }

                    return AppSettingsTile(
                      title: 'Check for Updates',
                      subtitle: subtitle,
                      leading: _buildLeadingIcon(
                        Icons.system_update_rounded,
                        (isAvailable || isDownloaded)
                            ? Colors.greenAccent
                            : _primary,
                      ),
                      trailing: trailing,
                      onTap: () async {
                        if (isDownloading || isAvailable || isDownloaded) {
                          AppUpdateDialog.show(context);
                        } else {
                          final hasUpdate = await updateService.checkForUpdates(
                              isManual: true);
                          if (context.mounted) {
                            if (hasUpdate) {
                              AppUpdateDialog.show(context);
                            } else if (updateService.stage !=
                                UpdateStage.error) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    'Sautiplay is up to date ($_appVersion)',
                                  ),
                                  duration: const Duration(seconds: 2),
                                ),
                              );
                            }
                          }
                        }
                      },
                    );
                  },
                ),
                const M3EDivider(),
                _buildM3ESwitchTile(
                  title: 'Check Updates on Startup',
                  subtitle:
                      'Automatically check for new releases when app launches',
                  secondary: _buildLeadingIcon(Icons.update_rounded),
                  value: _autoCheckUpdates,
                  onChanged: (val) async {
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.setBool('auto_check_updates', val);
                    setSubState(() => _autoCheckUpdates = val);
                    setState(() => _autoCheckUpdates = val);
                  },
                ),
                const M3EDivider(),
                AppSettingsTile(
                  title: 'Developer',
                  subtitle: 'Created by Wambugu Kinyua',
                  leading: _buildLeadingIcon(Icons.person_outline),
                ),
                const M3EDivider(),
                AppSettingsTile(
                  title: 'Copyright',
                  subtitle:
                      '© ${DateTime.now().year} Wambugu Kinyua. All rights reserved.',
                  leading: _buildLeadingIcon(Icons.copyright_outlined),
                ),
                const M3EDivider(),
                AppSettingsTile(
                  title: 'Open Source Licenses',
                  subtitle: 'Third-party libraries & acknowledgments',
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
                const M3EDivider(),
                AppSettingsTile(
                  title: 'Release Notes & Changelog',
                  subtitle: 'What\'s new and improved in SautiPlay',
                  leading: _buildLeadingIcon(Icons.history_edu_outlined),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: _primary.withAlpha(25),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: _primary.withAlpha(60)),
                        ),
                        child: Text(
                          _appVersion,
                          style: TextStyle(
                            color: _primary,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Icon(Icons.chevron_right_rounded,
                          color: _textDark, size: 20),
                    ],
                  ),
                  onTap: _showChangelogBottomSheet,
                ),
                const M3EDivider(),
                AppSettingsTile(
                  title: 'Telegram Community',
                  subtitle:
                      'Join community discussions, feedback & beta updates',
                  leading: _buildLeadingIcon(
                      Icons.send_rounded, const Color(0xFF229ED9)),
                  trailing: Icon(Icons.open_in_new_rounded,
                      color: _textDark, size: 20),
                  onTap: () async {
                    final uri = Uri.parse('https://t.me/+MilnrgkNkbFiYmY0');
                    try {
                      await launchUrl(uri,
                          mode: LaunchMode.externalApplication);
                    } catch (_) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text('Could not open Telegram link')),
                        );
                      }
                    }
                  },
                ),
              ],
            ),
            const SizedBox(height: 20),
            _buildSectionHeader('HELP & SUPPORT'),
            const SizedBox(height: 8),
            _buildCardContainer(
              children: [
                AppSettingsTile(
                  title: 'Frequently Asked Questions',
                  subtitle:
                      'Bit-perfect, AAudio, resamplers & performance guide',
                  leading: _buildLeadingIcon(Icons.quiz_outlined),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: _primary.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                              color: _primary.withValues(alpha: 0.4)),
                        ),
                        child: Text(
                          'FAQ',
                          style: TextStyle(
                            color: _primary,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Icon(Icons.chevron_right_rounded,
                          color: _textDark, size: 20),
                    ],
                  ),
                  onTap: () => _navigateToSubScreen(const FaqScreen()),
                ),
              ],
            ),
            const SizedBox(height: 20),
            _buildSectionHeader('DEBUG & DIAGNOSTICS'),
            const SizedBox(height: 8),
            _buildCardContainer(
              children: [
                _buildM3ESwitchTile(
                  title: 'Allow Invalid TLS Certificates',
                  subtitle: 'For local media servers and testing only',
                  secondary: _buildLeadingIcon(Icons.security),
                  value: widget.allowInvalidTls,
                  onChanged: (v) {
                    widget.onAllowInvalidTlsChanged(v);
                    setSubState(() {});
                  },
                ),
                const M3EDivider(),
                AppSettingsTile(
                  title: 'Poll Native Audio Errors',
                  subtitle: 'Check low-level engine status',
                  leading: _buildLeadingIcon(Icons.refresh),
                  trailing:
                      Icon(Icons.chevron_right, color: _textDark, size: 20),
                  onTap: widget.onPollError,
                ),
                const M3EDivider(),
                AppSettingsTile(
                  title: 'Clear Native Errors',
                  subtitle: 'Reset engine error flags',
                  leading: _buildLeadingIcon(Icons.cleaning_services_outlined),
                  trailing:
                      Icon(Icons.chevron_right, color: _textDark, size: 20),
                  onTap: widget.onClearNativeError,
                ),
              ],
            ),
            const SizedBox(height: 20),
            _buildSectionHeader('ENGINE LOGS TERMINAL'),
            const SizedBox(height: 8),
            ValueListenableBuilder<int>(
              valueListenable: widget.logUpdateNotifier,
              builder: (context, _, __) {
                return M3EExpandableList(
                  style: M3EExpandableStyle(
                    color: context.cardDark,
                    gap: 8,
                    headerPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    bodyPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  ),
                  data: [
                    M3EExpandableData(
                      title: 'App Engine Logs',
                      subtitle: '${widget.logs.length} logged entries',
                      leading: _buildLeadingIcon(Icons.article_outlined),
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
                      body: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
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
                                child: M3EButton.icon(
                                  onPressed: widget.onClearLogs,
                                  icon:
                                      const Icon(Icons.delete_sweep, size: 18),
                                  label: const Text('Clear'),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Container(
                            height: 250,
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
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
        );
      },
    );
  }

  // 8. Last.fm Scrobbler Sub-Screen
  Widget _buildLastFmSubScreen() {
    return AnimatedBuilder(
      animation: LastFmService.instance,
      builder: (context, _) {
        final lastFm = LastFmService.instance;
        const lastFmRed = Color(0xFFD51007);
        final isAuthenticating = lastFm.isAuthenticating;

        return StatefulBuilder(
          builder: (context, setSubState) {
            return _buildSubScreenLayout(
              title: 'Last.fm',
              children: [
                // ── ACCOUNT STATUS & PROFILE BANNER ────────────────────────
                _buildSectionHeader('ACCOUNT & CONNECTION'),
                const SizedBox(height: 8),
                _buildCardContainer(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Row(
                        children: [
                          Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: lastFmRed.withAlpha(30),
                              shape: BoxShape.circle,
                              border: Border.all(
                                  color: lastFmRed.withAlpha(80), width: 1.5),
                            ),
                            child: const Center(
                              child: Icon(Icons.radio_rounded,
                                  color: lastFmRed, size: 24),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  lastFm.isLoggedIn
                                      ? (lastFm.username ?? 'Connected Account')
                                      : (isAuthenticating
                                          ? 'Awaiting Authorization...'
                                          : 'Not Connected'),
                                  style: TextStyle(
                                    color: _textPrimary,
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  lastFm.isLoggedIn
                                      ? 'Scrobbles sync automatically to your Last.fm profile'
                                      : (isAuthenticating
                                          ? 'Approve in browser; app connects automatically on return'
                                          : 'Connect your Last.fm account to track listening history'),
                                  style: TextStyle(
                                    color: _textDark,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const M3EDivider(),
                    if (!lastFm.isLoggedIn) ...[
                      Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (!isAuthenticating) ...[
                              M3EButton.icon(
                                onPressed: () async {
                                  final token =
                                      await lastFm.fetchRequestToken();
                                  if (token != null) {
                                    await lastFm.launchAuthorizationUrl(token);
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                              'Authorize Sautiplay in your browser. Connection will complete automatically upon return!'),
                                        ),
                                      );
                                    }
                                  } else {
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                              'Failed to connect to Last.fm API. Check internet connection.'),
                                        ),
                                      );
                                    }
                                  }
                                },
                                icon: const Icon(Icons.login_rounded, size: 18),
                                label: const Text('Connect Last.fm Account'),
                              ),
                            ] else ...[
                              Container(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: _primary.withAlpha(20),
                                  borderRadius: BorderRadius.circular(12),
                                  border:
                                      Border.all(color: _primary.withAlpha(60)),
                                ),
                                child: Column(
                                  children: [
                                    Row(
                                      children: [
                                        SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2.2,
                                            valueColor:
                                                AlwaysStoppedAnimation<Color>(
                                                    _primary),
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Text(
                                            lastFm.isCheckingSession
                                                ? 'Verifying authorization...'
                                                : 'Waiting for browser authorization...',
                                            style: TextStyle(
                                              color: _textPrimary,
                                              fontSize: 13,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      'Approve Sautiplay in your browser, then return here. The app connects automatically.',
                                      style: TextStyle(
                                          color: _textDark, fontSize: 12),
                                    ),
                                    const SizedBox(height: 12),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: M3EButton.outlined(
                                            onPressed: () async {
                                              await lastFm
                                                  .cancelAuthentication();
                                            },
                                            child: const Text('Cancel'),
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: M3EButton(
                                            onPressed: lastFm.isCheckingSession
                                                ? null
                                                : () async {
                                                    final success = await lastFm
                                                        .checkPendingAuthorization();
                                                    if (success) {
                                                      if (context.mounted) {
                                                        ScaffoldMessenger.of(
                                                                context)
                                                            .showSnackBar(
                                                          SnackBar(
                                                            content: Text(
                                                                'Connected to Last.fm as ${lastFm.username}!'),
                                                          ),
                                                        );
                                                      }
                                                    } else {
                                                      if (context.mounted) {
                                                        ScaffoldMessenger.of(
                                                                context)
                                                            .showSnackBar(
                                                          const SnackBar(
                                                            content: Text(
                                                                'Authorization not completed yet. Please approve on the Last.fm webpage.'),
                                                          ),
                                                        );
                                                      }
                                                    }
                                                  },
                                            child: Text(lastFm.isCheckingSession
                                                ? 'Verifying...'
                                                : 'Check Now'),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ] else ...[
                      AppSettingsTile(
                        title: 'Disconnect Last.fm Account',
                        subtitle: 'Sign out and stop scrobbling',
                        leading: _buildLeadingIcon(
                            Icons.logout_rounded, Colors.redAccent),
                        trailing: const Icon(Icons.chevron_right_rounded,
                            color: Colors.redAccent, size: 20),
                        onTap: () async {
                          await lastFm.logout();
                          setSubState(() {});
                        },
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 20),

                // ── SCROBBLING SETTINGS ──────────────────────────────────────
                _buildSectionHeader('SCROBBLING PREFERENCES'),
                const SizedBox(height: 8),
                _buildCardContainer(
                  children: [
                    _buildM3ESwitchTile(
                      title: 'Scrobble Tracks',
                      subtitle:
                          'Save played songs to your Last.fm listening history',
                      secondary:
                          _buildLeadingIcon(Icons.history_rounded, lastFmRed),
                      value: lastFm.isScrobbleEnabled,
                      onChanged: (val) async {
                        await lastFm.setScrobbleEnabled(val);
                        setSubState(() {});
                      },
                    ),
                    const M3EDivider(),
                    _buildM3ESwitchTile(
                      title: 'Update "Now Playing"',
                      subtitle: 'Broadcast currently active song in real-time',
                      secondary: _buildLeadingIcon(
                          Icons.graphic_eq_rounded, lastFmRed),
                      value: lastFm.isNowPlayingEnabled,
                      onChanged: (val) async {
                        await lastFm.setNowPlayingEnabled(val);
                        setSubState(() {});
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // ── RULES & DETAILS ─────────────────────────────────────────
                _buildSectionHeader('LAST.FM SCROBBLER RULES'),
                const SizedBox(height: 8),
                _buildCardContainer(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.info_outline_rounded,
                                  color: _primary, size: 18),
                              const SizedBox(width: 8),
                              Text(
                                'How scrobbling works',
                                style: TextStyle(
                                    color: _primary,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '• Tracks shorter than 30 seconds are ignored as per Last.fm guidelines.\n'
                            '• A scrobble is sent after listening to 50% of the track or 4 minutes (whichever comes first).\n'
                            '• Real-time "Now Playing" updates appear instantly on your Last.fm profile when playback begins.',
                            style: TextStyle(
                                color: _textDark, fontSize: 12, height: 1.45),
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
      },
    );
  }

  // --- Modal Dialog Helpers ---

  String _getResampleAlgorithmName(int index) {
    switch (index) {
      case 0:
        return 'Fast & Smooth (Linear)';
      case 1:
        return 'Ultra HD Sinc (Desktop)';
      case 2:
        return 'High Quality Sinc';
      case 3:
        return 'Standard Sinc';
      case 4:
        return 'Vintage Lo-Fi (Step)';
      case 5:
        return 'Fast Linear Extended';
      case 7:
      case 9:
      case 10:
      case 11:
        return 'Studio Linear (r8brain LP)';
      case 8:
      case 12:
        return 'Studio Natural (r8brain MP)';
      default:
        return 'Fast & Smooth (Linear)';
    }
  }

  String _getResampleAlgorithmShortName(int index) {
    switch (index) {
      case 0:
        return 'Fast Linear';
      case 1:
        return 'Ultra Sinc';
      case 2:
        return 'HQ Sinc';
      case 3:
        return 'Standard Sinc';
      case 4:
        return 'Lo-Fi Step';
      case 5:
        return 'Linear Ext';
      case 7:
      case 9:
      case 10:
      case 11:
        return 'r8brain LP';
      case 8:
      case 12:
        return 'r8brain MP';
      default:
        return 'Fast Linear';
    }
  }

  String _getResampleAlgorithmSupportingText(int index) {
    switch (index) {
      case 0:
        return 'Fast and battery-friendly interpolation';
      case 1:
        return 'Maximum precision desktop sinc filter';
      case 2:
        return 'High-precision audio conversion';
      case 3:
        return 'Clean and efficient conversion';
      case 4:
        return 'Retro stepped interpolation';
      case 5:
        return 'Standard linear interpolation';
      case 7:
      case 9:
      case 10:
      case 11:
        return 'Mastering-grade linear phase conversion';
      case 8:
      case 12:
        return 'Zero pre-ringing natural response';
      default:
        return 'Audio sample rate conversion';
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

  Widget _buildModalBottomSheetLayout({
    required String title,
    String? subtitle,
    required Widget child,
    double? height,
  }) {
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: height ?? MediaQuery.of(context).size.height * 0.75,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24.0, 4.0, 24.0, 12.0),
            child: Column(
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: _textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(color: _textDark, fontSize: 12),
                    textAlign: TextAlign.center,
                  ),
                ],
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20.0),
            child: M3EDivider(),
          ),
          const SizedBox(height: 8),
          if (height != null)
            Expanded(child: child)
          else
            Flexible(child: child),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  void _showOversamplingDialog({VoidCallback? onDone}) {
    final options = [
      {
        'factor': 1,
        'name': 'Off (1x)',
        'subtitle': 'Native sample rate (Saves battery)'
      },
      {
        'factor': 2,
        'name': '2x Oversampling',
        'subtitle': 'Enhanced clarity for EQ and DSP effects (Recommended)',
      },
      {
        'factor': 4,
        'name': '4x Oversampling',
        'subtitle': 'Maximum purity and anti-aliasing (Higher CPU usage)',
      },
    ];

    M3EBottomSheet.show<void>(
      context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => _buildModalBottomSheetLayout(
          title: 'Anti-Aliasing Oversampling',
          subtitle: 'Improves DSP effects clarity and prevents harshness',
          child: M3ECardList(
            margin: const EdgeInsets.fromLTRB(20.0, 4.0, 20.0, 16.0),
            padding:
                const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
            gap: 6.0,
            outerRadius: 20.0,
            innerRadius: 6.0,
            itemCount: options.length,
            onTap: (index) {
              final val = options[index]['factor'] as int;
              setDlgState(() {});
              setState(() => _dspOversampling = val);
              AppStateService.instance.saveDspOversampling(val);
              onDone?.call();
              Navigator.pop(ctx);
            },
            itemBuilder: (context, index) {
              final item = options[index];
              final val = item['factor'] as int;
              final isSelected = val == _dspOversampling;
              return M3EListItem(
                headline: item['name'] as String,
                supportingText: item['subtitle'] as String,
                selected: isSelected,
                trailing: M3ERadio<int>(
                  value: val,
                  groupValue: _dspOversampling,
                  onChanged: (v) {
                    setDlgState(() {});
                    setState(() => _dspOversampling = v);
                    AppStateService.instance.saveDspOversampling(v);
                    onDone?.call();
                    Navigator.pop(ctx);
                  },
                ),
              );
            },
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
        'index': 12,
        'name': 'Studio Natural (r8brain Minimum Phase)',
        'subtitle':
            'Punchy transients with zero pre-ringing. Best for music listening.',
        'badge': 'Audiophile',
        'isHeavy': true,
      },
      {
        'index': 11,
        'name': 'Mastering Linear Phase (r8brain)',
        'subtitle':
            'Flat frequency response and perfect phase. Demands high CPU.',
        'badge': isMobile ? 'High CPU' : 'Mastering',
        'isHeavy': true,
      },
      {
        'index': 1,
        'name': 'Ultra HD Sinc (Master)',
        'subtitle':
            'Extremely steep anti-alias filter. Designed for high-end desktop systems.',
        'badge': isMobile ? 'Desktop' : 'Ultra HD',
        'isHeavy': true,
      },
      {
        'index': 2,
        'name': 'High Quality Sinc',
        'subtitle': 'Clean frequency cutoff with studio-grade anti-aliasing.',
        'badge': isMobile ? 'High CPU' : 'Studio',
        'isHeavy': true,
      },
      {
        'index': 3,
        'name': 'Standard Sinc',
        'subtitle': 'Balanced anti-aliasing with moderate CPU usage.',
        'badge': null,
        'isHeavy': false,
      },
      {
        'index': 0,
        'name': 'Fast & Smooth (Linear)',
        'subtitle': 'Ultra-efficient with instant response. Ideal for phones.',
        'badge': 'Recommended',
        'isHeavy': false,
      },
      {
        'index': 5,
        'name': 'Linear Extended',
        'subtitle': 'Alternative lightweight linear interpolation.',
        'badge': null,
        'isHeavy': false,
      },
      {
        'index': 4,
        'name': 'Vintage Step (Lo-Fi)',
        'subtitle':
            'Zero-order hold interpolation for a retro digital character.',
        'badge': null,
        'isHeavy': false,
      },
    ];

    M3EBottomSheet.show<void>(
      context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => _buildModalBottomSheetLayout(
          title: 'Resampling Quality',
          subtitle:
              'Method used when converting audio between different sample rates',
          height: MediaQuery.of(context).size.height * 0.78,
          child: M3ECardList.builder(
            margin: const EdgeInsets.fromLTRB(20.0, 4.0, 20.0, 16.0),
            listPadding: const EdgeInsets.symmetric(vertical: 4.0),
            padding:
                const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
            gap: 6.0,
            outerRadius: 20.0,
            innerRadius: 6.0,
            itemCount: options.length,
            onTap: (index) {
              final item = options[index];
              final val = item['index'] as int;
              if (isMobile && (item['isHeavy'] as bool)) {
                Navigator.pop(ctx);
                _showMobileResamplerWarningDialog(val, onDone);
              } else {
                _applyResampleAlgorithm(val, onDone);
                Navigator.pop(ctx);
              }
            },
            itemBuilder: (context, index) {
              final item = options[index];
              final val = item['index'] as int;
              final isSelected = val == _resampleAlgorithm;
              return M3EListItem(
                headline: item['name'] as String,
                supportingText: item['subtitle'] as String,
                selected: isSelected,
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (item['badge'] != null) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
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
              );
            },
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
    final name = _getResampleAlgorithmName(requestedIndex);
    final String techDetails;
    if (requestedIndex == 11 || requestedIndex == 12) {
      techDetails =
          '$name uses heavy multi-stage filtering. On mobile devices, this may increase battery drain.';
    } else if (requestedIndex == 1) {
      techDetails =
          '$name is designed for desktop processors and may cause audio stuttering on phones.';
    } else {
      techDetails =
          '$name uses precision audio filtering which increases CPU and battery usage.';
    }

    M3EDialog.show<void>(
      context,
      dialog: M3EDialog(
        contentPadding:
            const EdgeInsets.symmetric(vertical: 16.0, horizontal: 8.0),
        title: 'High CPU Resampler',
        content: Text(
          '$techDetails\n\nWould you like to keep Fast & Smooth (Recommended) or enable anyway?',
          style: TextStyle(color: _textDark, fontSize: 13, height: 1.4),
        ),
        actions: [
          M3EButton.text(
            onPressed: () {
              _applyResampleAlgorithm(0, onDone);
              Navigator.pop(context);
            },
            child: const Text('Recommended'),
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
    final sizes = [
      (256, '256 points', 'Fastest reaction, minimal battery use'),
      (512, '512 points', 'Snappy response for beats and transients'),
      (1024, '1024 points (Default)', 'Balanced visual smoothness and detail'),
      (2048, '2048 points', 'Sharp low-end frequency detail'),
      (4096, '4096 points', 'Studio precision frequency analysis'),
      (8192, '8192 points', 'Maximum pitch resolution (Higher CPU)'),
    ];
    M3EBottomSheet.show<void>(
      context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => _buildModalBottomSheetLayout(
          title: 'Spectrum Analyzer Resolution',
          subtitle:
              'Balances visual smoothness against pitch frequency accuracy',
          child: M3ECardList(
            margin: const EdgeInsets.fromLTRB(20.0, 4.0, 20.0, 16.0),
            padding:
                const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
            gap: 6.0,
            outerRadius: 20.0,
            innerRadius: 6.0,
            itemCount: sizes.length,
            onTap: (index) {
              final size = sizes[index].$1;
              setDlgState(() {});
              widget.onAnalyzerSampleSizeChanged(size);
              widget.player.configureAnalyzer(frameSize: size);
              onDone?.call();
              Navigator.pop(ctx);
            },
            itemBuilder: (context, index) {
              final item = sizes[index];
              final size = item.$1;
              final isSelected = size == widget.analyzerSampleSize;
              return M3EListItem(
                headline: item.$2,
                supportingText: item.$3,
                selected: isSelected,
                trailing: M3ERadio<int>(
                  value: size,
                  groupValue: widget.analyzerSampleSize,
                  onChanged: (v) {
                    setDlgState(() {});
                    widget.onAnalyzerSampleSizeChanged(v);
                    widget.player.configureAnalyzer(frameSize: v);
                    onDone?.call();
                    Navigator.pop(ctx);
                  },
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  void _showAnalyzerWindowDialog({VoidCallback? onDone}) {
    final windows = [
      (
        'hann',
        'Hann (Balanced)',
        'Smooth and natural response. Recommended default for music visualization.',
      ),
      (
        'hamming',
        'Hamming (Sharp)',
        'Crisp separation of closely spaced notes and vocal tones.',
      ),
      (
        'blackman_harris',
        'Blackman-Harris (Pristine)',
        'Ultra-clean isolation eliminating bleed across neighboring frequency bands.',
      ),
      (
        'flat_top',
        'Flat-Top (Accurate Levels)',
        'Calibrated for accurate decibel volume and SPL readings with minimal amplitude error.',
      ),
    ];
    M3EBottomSheet.show<void>(
      context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => _buildModalBottomSheetLayout(
          title: 'Spectrum Window Shape',
          subtitle:
              'Smoothing filter shaping how frequencies appear in the visualizer',
          child: M3ECardList(
            margin: const EdgeInsets.fromLTRB(20.0, 4.0, 20.0, 16.0),
            padding:
                const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
            gap: 6.0,
            outerRadius: 20.0,
            innerRadius: 6.0,
            itemCount: windows.length,
            onTap: (index) {
              final winId = windows[index].$1;
              setDlgState(() {});
              widget.onAnalyzerWindowTypeChanged(winId);
              widget.player.configureAnalyzer(
                frameSize: widget.analyzerSampleSize,
                windowType: winId,
              );
              onDone?.call();
              Navigator.pop(ctx);
            },
            itemBuilder: (context, index) {
              final item = windows[index];
              final winId = item.$1;
              final isSelected = winId == widget.analyzerWindowType;
              return M3EListItem(
                headline: item.$2,
                supportingText: item.$3,
                selected: isSelected,
                trailing: M3ERadio<String>(
                  value: winId,
                  groupValue: widget.analyzerWindowType,
                  onChanged: (v) {
                    setDlgState(() {});
                    widget.onAnalyzerWindowTypeChanged(v);
                    widget.player.configureAnalyzer(
                      frameSize: widget.analyzerSampleSize,
                      windowType: v,
                    );
                    onDone?.call();
                    Navigator.pop(ctx);
                  },
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  String _getDitherModeName(int mode) {
    switch (mode) {
      case 0:
        return 'None';
      case 1:
        return 'Rectangular';
      case 2:
        return 'Triangular (Standard)';
      case 3:
        return 'Lipshitz (Shaped)';
      case 4:
        return 'F-Weighted (Vocal)';
      case 5:
        return 'Modified E (Pop/Rock)';
      case 6:
        return 'Shibata (Audiophile)';
      case 7:
        return 'Low Shibata (Subtle)';
      case 8:
        return 'High Shibata (High-Res)';
      default:
        return 'None';
    }
  }

  Future<void> _showDitherModeDialog({VoidCallback? onDone}) async {
    final modes = [
      {
        'id': 0,
        'name': 'None',
        'subtitle': 'No dithering applied (Truncate samples)'
      },
      {
        'id': 1,
        'name': 'Rectangular (Simple)',
        'subtitle': 'Flat random noise'
      },
      {
        'id': 2,
        'name': 'Triangular (Standard)',
        'subtitle': 'Clean, neutral noise floor (Recommended standard)',
      },
      {
        'id': 3,
        'name': 'Lipshitz (Shaped)',
        'subtitle':
            'Classic noise shaping shifting hiss away from audible frequencies',
      },
      {
        'id': 4,
        'name': 'F-Weighted (Vocal & Acoustic)',
        'subtitle':
            'Clears midrange noise for acoustic, folk, and vocal clarity',
      },
      {
        'id': 5,
        'name': 'Modified E-Weighted (Pop & Rock)',
        'subtitle': 'Maintains headroom and punch for high-energy music',
      },
      {
        'id': 6,
        'name': 'Shibata (Audiophile)',
        'subtitle':
            'Advanced psychoacoustic curve pushing noise beyond audible range',
      },
      {
        'id': 7,
        'name': 'Low Shibata (Subtle)',
        'subtitle':
            'Gentle audiophile noise shaping with low ultrasonic energy',
      },
      {
        'id': 8,
        'name': 'High Shibata (High-Res)',
        'subtitle': 'Maximum high-frequency noise shifting for high-res DACs',
      },
    ];

    M3EBottomSheet.show<void>(
      context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => _buildModalBottomSheetLayout(
          title: 'Dither & Noise Shaping',
          subtitle:
              'Prevents harsh quantization artifacts when reducing bit depth',
          height: MediaQuery.of(context).size.height * 0.78,
          child: M3ECardList.builder(
            margin: const EdgeInsets.fromLTRB(20.0, 4.0, 20.0, 16.0),
            listPadding: const EdgeInsets.symmetric(vertical: 4.0),
            padding:
                const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
            gap: 6.0,
            outerRadius: 20.0,
            innerRadius: 6.0,
            itemCount: modes.length,
            onTap: (i) {
              final item = modes[i];
              final id = item['id'] as int;
              setDlgState(() {});
              setState(() => _ditherMode = id);
              widget.player.setEngineDitherMode(id);
              _persistUiSettings();
              onDone?.call();
              Navigator.pop(ctx);
            },
            itemBuilder: (context, i) {
              final item = modes[i];
              final id = item['id'] as int;
              final name = item['name'] as String;
              final subtitle = item['subtitle'] as String;
              final isSelected = id == _ditherMode;
              return M3EListItem(
                headline: name,
                supportingText: subtitle,
                selected: isSelected,
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
              );
            },
          ),
        ),
      ),
    );
  }

  void _showOutputFormatDialog({VoidCallback? onDone}) {
    final formats = [
      (
        AudioFormat.f32,
        '32-Bit Float',
        'Highest dynamic range with headroom to prevent clipping (Recommended)'
      ),
      (
        AudioFormat.s32,
        '32-Bit Integer',
        'Direct 32-bit hardware PCM for high-end DACs'
      ),
      (
        AudioFormat.s24,
        '24-Bit Integer',
        'Studio standard high-resolution audio format'
      ),
      (
        AudioFormat.s16,
        '16-Bit Integer',
        'Standard CD quality PCM (Universal compatibility)'
      ),
      (AudioFormat.u8, '8-Bit Integer', 'Legacy 8-bit PCM format'),
    ];
    M3EBottomSheet.show<void>(
      context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => _buildModalBottomSheetLayout(
          title: 'Output Bit Depth',
          subtitle: 'Target PCM resolution sent to audio hardware or DAC',
          child: M3ECardList(
            margin: const EdgeInsets.fromLTRB(20.0, 4.0, 20.0, 16.0),
            padding:
                const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
            gap: 6.0,
            outerRadius: 20.0,
            innerRadius: 6.0,
            itemCount: formats.length,
            onTap: (index) {
              final fmt = formats[index].$1;
              setDlgState(() {});
              widget.onOutputFormatChanged(fmt);
              widget.player.setOutputFormat(fmt);
              setState(() {});
              onDone?.call();
              Navigator.pop(ctx);
            },
            itemBuilder: (context, index) {
              final item = formats[index];
              final fmt = item.$1;
              final isSelected = fmt == widget.outputFormat;
              return M3EListItem(
                headline: item.$2,
                supportingText: item.$3,
                selected: isSelected,
                trailing: M3ERadio<AudioFormat>(
                  value: fmt,
                  groupValue: widget.outputFormat,
                  onChanged: (v) {
                    setDlgState(() {});
                    widget.onOutputFormatChanged(fmt);
                    widget.player.setOutputFormat(fmt);
                    setState(() {});
                    onDone?.call();
                    Navigator.pop(ctx);
                  },
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  void _showSampleRateDialog({VoidCallback? onDone}) {
    final rates = [
      (
        0,
        'Native (Auto)',
        'Matches connected hardware to avoid extra resampling'
      ),
      (44100, '44.1 kHz', 'Standard CD audio sample rate'),
      (48000, '48.0 kHz', 'Standard digital media and video audio rate'),
      (96000, '96.0 kHz', 'High-Resolution 24/96 studio rate'),
      (192000, '192.0 kHz', 'Ultra HD Master high-resolution rate'),
    ];
    M3EBottomSheet.show<void>(
      context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => _buildModalBottomSheetLayout(
          title: 'Output Sample Rate',
          subtitle: 'Target sample rate sent to the audio output stream',
          child: M3ECardList(
            margin: const EdgeInsets.fromLTRB(20.0, 4.0, 20.0, 16.0),
            padding:
                const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
            gap: 6.0,
            outerRadius: 20.0,
            innerRadius: 6.0,
            itemCount: rates.length,
            onTap: (index) {
              final r = rates[index].$1;
              setDlgState(() {});
              widget.onOutputSampleRateChanged(r);
              widget.player.setOutputSampleRate(r);
              setState(() {});
              onDone?.call();
              Navigator.pop(ctx);
            },
            itemBuilder: (context, index) {
              final item = rates[index];
              final r = item.$1;
              final isSelected = r == widget.outputSampleRate;
              return M3EListItem(
                headline: item.$2,
                supportingText: item.$3,
                selected: isSelected,
                trailing: M3ERadio<int>(
                  value: r,
                  groupValue: widget.outputSampleRate,
                  onChanged: (v) {
                    setDlgState(() {});
                    widget.onOutputSampleRateChanged(r);
                    widget.player.setOutputSampleRate(r);
                    setState(() {});
                    onDone?.call();
                    Navigator.pop(ctx);
                  },
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  void _showAndroidBackendPicker(
      BuildContext context, StateSetter setSubState) {
    final backends = [
      (
        AudioOutputBackend.auto,
        'Auto (Recommended)',
        'Automatically chooses the lowest latency driver for your device',
        Icons.auto_awesome_rounded,
      ),
      (
        AudioOutputBackend.aaudio,
        'AAudio (Fast & Direct)',
        'Modern high-performance Android driver (Android 8.0+)',
        Icons.speed_rounded,
      ),
      (
        AudioOutputBackend.openSl,
        'OpenSL ES (Legacy)',
        'Reliable fallback driver for older Android versions',
        Icons.history_toggle_off_rounded,
      ),
      (
        AudioOutputBackend.audioTrack,
        'AudioTrack (Standard)',
        'Standard Android audio framework pipeline',
        Icons.layers_rounded,
      ),
      (
        AudioOutputBackend.directHiRes,
        'Direct Hi-Res (Bit-Perfect)',
        'Bypasses system mixer on supported high-res hardware',
        Icons.verified_rounded,
      ),
    ];

    M3EBottomSheet.show<void>(
      context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => _buildModalBottomSheetLayout(
          title: 'Android Audio Driver',
          subtitle: 'Select the low-level audio driver for sound output',
          child: M3ECardList(
            margin: const EdgeInsets.fromLTRB(20.0, 4.0, 20.0, 16.0),
            padding:
                const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
            gap: 6.0,
            outerRadius: 20.0,
            innerRadius: 6.0,
            itemCount: backends.length,
            onTap: (index) {
              final selected = backends[index].$1;
              widget.player.setOutputBackend(selected);
              setState(() {
                _selectedBackend = selected;
              });
              setSubState(() {});
              Navigator.pop(ctx);
            },
            itemBuilder: (context, index) {
              final item = backends[index];
              final bk = item.$1;
              final isSelected = bk == _selectedBackend;
              return M3EListItem(
                leading: Icon(item.$4,
                    color: isSelected ? _primary : _textDark, size: 22),
                headline: item.$2,
                supportingText: item.$3,
                selected: isSelected,
                trailing: M3ERadio<AudioOutputBackend>(
                  value: bk,
                  groupValue: _selectedBackend,
                  onChanged: (v) {
                    widget.player.setOutputBackend(v);
                    setState(() {
                      _selectedBackend = v;
                    });
                    setSubState(() {});
                    Navigator.pop(ctx);
                  },
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  String _formatChannelCount(int count) {
    switch (count) {
      case 1:
        return 'Mono';
      case 2:
        return 'Stereo';
      case 3:
        return '2.1 Surround';
      case 4:
        return '4.0 Quadraphonic';
      case 5:
        return '5.0 Surround';
      case 6:
        return '5.1 Surround';
      case 7:
        return '7.0 Surround';
      case 8:
        return '7.1 Surround';
      default:
        return '$count CH';
    }
  }

  void _showChannelsDialog({VoidCallback? onDone}) {
    final options = [
      {'ch': 1, 'name': 'Mono', 'subtitle': 'Single channel mono output'},
      {
        'ch': 2,
        'name': 'Stereo',
        'subtitle': 'Standard 2-channel Left / Right stereo (Recommended)'
      },
      {
        'ch': 3,
        'name': '2.1 Surround',
        'subtitle': 'Left, Right, and dedicated Subwoofer'
      },
      {
        'ch': 4,
        'name': '4.0 Quadraphonic',
        'subtitle': 'Front Left/Right and Rear Left/Right'
      },
      {
        'ch': 5,
        'name': '5.0 Surround',
        'subtitle': 'Front Left/Right, Center, and Rear Left/Right'
      },
      {
        'ch': 6,
        'name': '5.1 Surround',
        'subtitle': '5 speakers plus dedicated subwoofer'
      },
      {
        'ch': 7,
        'name': '7.0 Surround',
        'subtitle': '7-channel full surround layout'
      },
      {
        'ch': 8,
        'name': '7.1 Surround',
        'subtitle': '7 speakers plus dedicated subwoofer'
      },
    ];

    M3EBottomSheet.show<void>(
      context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => _buildModalBottomSheetLayout(
          title: 'Speaker Configuration',
          subtitle: 'Select speaker layout for output channels',
          height: MediaQuery.of(context).size.height * 0.78,
          child: M3ECardList.builder(
            margin: const EdgeInsets.fromLTRB(20.0, 4.0, 20.0, 16.0),
            listPadding: const EdgeInsets.symmetric(vertical: 4.0),
            padding:
                const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
            gap: 6.0,
            outerRadius: 20.0,
            innerRadius: 6.0,
            itemCount: options.length,
            onTap: (i) {
              final item = options[i];
              final ch = item['ch'] as int;
              setDlgState(() {});
              widget.onOutputChannelsChanged(ch);
              widget.player.setOutputChannels(ch);
              setState(() {});
              onDone?.call();
              Navigator.pop(ctx);
            },
            itemBuilder: (context, i) {
              final item = options[i];
              final ch = item['ch'] as int;
              final name = item['name'] as String;
              final subtitle = item['subtitle'] as String;
              final isSelected = ch == widget.outputChannels;
              return M3EListItem(
                headline: name,
                supportingText: subtitle,
                selected: isSelected,
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
              );
            },
          ),
        ),
      ),
    );
  }

  String _formatOutputBuffer(int frames, int periods) {
    if (frames <= 0 || periods <= 0) {
      return 'Auto (Default)';
    }
    return '$frames f • ${periods}x';
  }

  void _showOutputBufferDialog({VoidCallback? onDone}) {
    final options = [
      {
        'frames': 0,
        'periods': 0,
        'name': 'Auto (System Optimal)',
        'subtitle': 'Automatically matches device hardware buffer (~10–25ms)',
        'badge': 'Recommended',
      },
      {
        'frames': 128,
        'periods': 2,
        'name': 'Ultra-Low (~2.7ms)',
        'subtitle': 'Instant response. Requires high-performance hardware.',
        'badge': 'Ultra Low',
      },
      {
        'frames': 256,
        'periods': 2,
        'name': 'Low Latency (~5.3ms)',
        'subtitle': 'Snappy response for fast playback controls',
        'badge': 'Low Latency',
      },
      {
        'frames': 512,
        'periods': 2,
        'name': 'Standard (~10.7ms)',
        'subtitle': 'Balanced latency and stutter-free stability',
        'badge': 'Standard',
      },
      {
        'frames': 1024,
        'periods': 3,
        'name': 'High Stability (~21.3ms)',
        'subtitle': 'Extra buffering to prevent skips during multitasking',
        'badge': 'Stable',
      },
      {
        'frames': 2048,
        'periods': 4,
        'name': 'Maximum Stability (~42.6ms)',
        'subtitle': 'Heaviest buffering for stutter-free background playback',
        'badge': 'Max Safe',
      },
    ];

    M3EBottomSheet.show<void>(
      context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => _buildModalBottomSheetLayout(
          title: 'Output Buffer & Latency',
          subtitle:
              'Balance instant audio response against stutter-free playback',
          height: MediaQuery.of(context).size.height * 0.78,
          child: M3ECardList.builder(
            margin: const EdgeInsets.fromLTRB(20.0, 4.0, 20.0, 16.0),
            listPadding: const EdgeInsets.symmetric(vertical: 4.0),
            padding:
                const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
            gap: 6.0,
            outerRadius: 20.0,
            innerRadius: 6.0,
            itemCount: options.length,
            onTap: (i) {
              final item = options[i];
              final f = item['frames'] as int;
              final p = item['periods'] as int;
              setDlgState(() {});
              setState(() {
                _outputBufferFrames = f;
                _outputBufferPeriods = p;
              });
              widget.player.setOutputBuffer(
                periodFrames: f,
                periodCount: p,
              );
              AppStateService.instance.saveOutputBuffer(
                periodFrames: f,
                periodCount: p,
              );
              onDone?.call();
              Navigator.pop(ctx);
            },
            itemBuilder: (context, i) {
              final item = options[i];
              final f = item['frames'] as int;
              final p = item['periods'] as int;
              final name = item['name'] as String;
              final subtitle = item['subtitle'] as String;
              final isSelected =
                  _outputBufferFrames == f && _outputBufferPeriods == p;
              return M3EListItem(
                headline: name,
                supportingText: subtitle,
                selected: isSelected,
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (item['badge'] != null) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: _primary.withAlpha(40),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          item['badge'] as String,
                          style: TextStyle(
                            color: _primary,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    M3ERadio<bool>(
                      value: true,
                      groupValue: isSelected ? true : null,
                      onChanged: (_) {
                        setDlgState(() {});
                        setState(() {
                          _outputBufferFrames = f;
                          _outputBufferPeriods = p;
                        });
                        widget.player.setOutputBuffer(
                          periodFrames: f,
                          periodCount: p,
                        );
                        AppStateService.instance.saveOutputBuffer(
                          periodFrames: f,
                          periodCount: p,
                        );
                        onDone?.call();
                        Navigator.pop(ctx);
                      },
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  void _showSubsonicDialog({VoidCallback? onDone}) {
    final options = [
      (0.0, 'Disabled', 'Passes full sub-bass spectrum unfiltered'),
      (
        15.0,
        '15 Hz (Gentle)',
        'Removes direct-current rumble while keeping deepest bass'
      ),
      (
        20.0,
        '20 Hz (Standard)',
        'Cuts inaudible sub-bass and saves amplifier power (Recommended)'
      ),
      (
        25.0,
        '25 Hz (Compact Speakers)',
        'Protects smaller speakers and phone drivers from bass distortion'
      ),
    ];

    M3EBottomSheet.show<void>(
      context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => _buildModalBottomSheetLayout(
          title: 'Sub-Bass Protection Filter',
          subtitle:
              'Removes inaudible rumble below human hearing to protect woofers',
          child: M3ECardList(
            margin: const EdgeInsets.fromLTRB(20.0, 4.0, 20.0, 16.0),
            padding:
                const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
            gap: 6.0,
            outerRadius: 20.0,
            innerRadius: 6.0,
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
              final isSelected = opt.$1 == _subsonicCutoffHz;
              return M3EListItem(
                headline: opt.$2,
                supportingText: opt.$3,
                selected: isSelected,
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
      ),
    );
  }

  void _showUltrasonicDialog({VoidCallback? onDone}) {
    final options = [
      (24000.0, 'Disabled', 'Passes ultra-high frequencies without cutoff'),
      (
        22000.0,
        '22 kHz (Hi-Res Limit)',
        'Retains high-res harmonics while blocking high-band noise'
      ),
      (
        20000.0,
        '20 kHz (Hearing Limit)',
        'Standard limit of human hearing. Reduces listener fatigue (Recommended)'
      ),
      (
        18000.0,
        '18 kHz (Tweeter Guard)',
        'Protects sensitive tweeters from radio frequency hiss and noise'
      ),
    ];

    M3EBottomSheet.show<void>(
      context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => _buildModalBottomSheetLayout(
          title: 'High-Frequency Guard Filter',
          subtitle:
              'Filters ultrasonic frequencies above human hearing to protect tweeters and ears',
          child: M3ECardList(
            margin: const EdgeInsets.fromLTRB(20.0, 4.0, 20.0, 16.0),
            padding:
                const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
            gap: 6.0,
            outerRadius: 20.0,
            innerRadius: 6.0,
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
              final isSelected = opt.$1 == _ultrasonicCutoffHz;
              return M3EListItem(
                headline: opt.$2,
                supportingText: opt.$3,
                selected: isSelected,
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
      ),
    );
  }
}
