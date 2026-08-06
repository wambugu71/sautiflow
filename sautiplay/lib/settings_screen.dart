import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:sautiflow/sautiflow.dart';

import 'eq_screen.dart';
import 'isolate_player.dart';
import 'main.dart' show AppThemeProvider;
import 'network_sources_screen.dart';
import 'services/app_state_service.dart';
import 'services/app_theme_service.dart';

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
  // Dynamic theme colors
  Color get _bgDark => AppThemeService.instance.currentData.bgDark;
  Color get _cardDark => AppThemeService.instance.currentData.cardDark;
  Color get _primary => AppThemeService.instance.currentData.primary;
  Color get _textDark => AppThemeService.instance.currentData.textDark;

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

  // Neutron HiFi Engine Settings
  bool _use64BitProcessingEnabled = false;
  bool _autoBitPerfectEnabled = false;

  // Waveform Seek Bar UI Setting
  bool _useWaveformSeekBar = false;

  // App version state
  String _appVersion = 'v0.6.20';

  // Active theme ID (used to show badge & highlight swatch)
  AppThemeId _activeThemeId = AppThemeService.instance.current;

  @override
  void initState() {
    super.initState();
    _loadUiSettings();
  }

  Future<void> _loadUiSettings() async {
    final saved = await AppStateService.instance.loadUiSettings();
    final eqSaved = await AppStateService.instance.loadEqBands();
    final rgSaved = await AppStateService.instance.loadReplayGainSettings();
    final oversamplingSaved =
        await AppStateService.instance.loadDspOversampling();
    final spSaved = await AppStateService.instance.loadSpeakerProtection();
    final phaseSaved = await AppStateService.instance.loadPhaseInversion();
    final is64Bit = await AppStateService.instance.load64BitProcessingEnabled();
    final autoBp = await AppStateService.instance.loadAutoBitPerfectEnabled();
    final waveformSaved =
        await AppStateService.instance.loadUseWaveformSeekBar();

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
      _use64BitProcessingEnabled = is64Bit;
      _autoBitPerfectEnabled = autoBp;
      _useWaveformSeekBar = waveformSaved;
      _activeThemeId = AppThemeService.instance.current;
    });
    widget.player.setViperOversampling(oversamplingSaved);
    widget.player.set64BitProcessingEnabled(is64Bit);
    widget.player.setAutoBitPerfectEnabled(autoBp);
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
                        _buildCategoryCard(
                          title: 'Look & Feel',
                          subtitle: 'Theme, seek bar & UI appearance',
                          icon: Icons.palette_outlined,
                          accentColor: _primary,
                          badgeText: AppThemeService.dataFor(_activeThemeId).displayName,
                          onTap: () => _navigateToSubScreen(
                              _buildLookAndFeelSubScreen()),
                        ),
                        const SizedBox(height: 12),
                        _buildCategoryCard(
                          title: 'Audio & Processing',
                          subtitle:
                              'Resampling, Bit depth, Safeguards & ReplayGain',
                          icon: Icons.graphic_eq_rounded,
                          accentColor: _primary,
                          badgeText: widget.exclusiveMode
                              ? 'Bit-Perfect'
                              : _streamingQuality,
                          onTap: () => _navigateToSubScreen(
                              _buildAudioProcessingSubScreen()),
                        ),
                        const SizedBox(height: 12),
                        _buildCategoryCard(
                          title: 'Equalizer & DSP',
                          subtitle: 'Band configuration & ViPER FX shortcuts',
                          icon: Icons.tune_rounded,
                          accentColor: _primary,
                          badgeText: '$_eqBandCount-Band',
                          onTap: () =>
                              _navigateToSubScreen(_buildEqualizerSubScreen()),
                        ),
                        const SizedBox(height: 12),
                        _buildCategoryCard(
                          title: 'Visualization & RTA',
                          subtitle: 'Spectrum analyzer styles, grids, FFT size',
                          icon: Icons.bar_chart_rounded,
                          accentColor: _primary,
                          badgeText: widget.analyzerEnabled
                              ? widget.spectrumStyle.toUpperCase()
                              : 'Off',
                          onTap: () => _navigateToSubScreen(
                              _buildVisualizationSubScreen()),
                        ),
                        const SizedBox(height: 12),
                        _buildCategoryCard(
                          title: 'Playback & Crossfade',
                          subtitle:
                              'Gapless mode, crossfade transitions & volume',
                          icon: Icons.queue_music_rounded,
                          accentColor: _primary,
                          badgeText: widget.crossfadeEnabled
                              ? '${(widget.crossfadeDurationMs / 1000).toStringAsFixed(1)}s'
                              : 'Gapless',
                          onTap: () =>
                              _navigateToSubScreen(_buildPlaybackSubScreen()),
                        ),
                        const SizedBox(height: 12),
                        _buildCategoryCard(
                          title: 'Library & Storage',
                          subtitle: 'Wi-Fi streaming preferences & audio cache',
                          icon: Icons.storage_rounded,
                          accentColor: _primary,
                          badgeText: '145 MB Cache',
                          onTap: () =>
                              _navigateToSubScreen(_buildStorageSubScreen()),
                        ),
                        const SizedBox(height: 12),
                        _buildCategoryCard(
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
                                builder: (context) => NetworkSourcesScreen(
                                  player: widget.player,
                                  onPlayNetworkFile: widget.onPlayNetworkFile,
                                  onPlayFtpFolder: widget.onPlayFtpFolder,
                                ),
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 12),
                        _buildCategoryCard(
                          title: 'Misc & System',
                          subtitle:
                              'Open source licenses, TLS, diagnostic logs',
                          icon: Icons.admin_panel_settings_outlined,
                          accentColor: _primary,
                          badgeText: _appVersion,
                          onTap: () =>
                              _navigateToSubScreen(_buildMiscSystemSubScreen()),
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
    return Padding(
      padding: const EdgeInsets.only(left: 4.0, bottom: 4.0),
      child: Text(
        title,
        style: TextStyle(
          color: _textDark,
          fontSize: 12,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  Widget _buildCategoryCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color accentColor,
    required String badgeText,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        splashColor: accentColor.withAlpha(40),
        highlightColor: accentColor.withAlpha(20),
        child: Ink(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: _cardDark,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white.withAlpha(12)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: accentColor.withAlpha(30),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: accentColor, size: 24),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(color: _textDark, fontSize: 13),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
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
              Icon(Icons.chevron_right_rounded,
                  color: _textDark, size: 22),
            ],
          ),
        ),
      ),
    );
  }

  // --- Sub-Screen Views ---

  Widget _buildSubScreenLayout({
    required String title,
    required List<Widget> children,
  }) {
    return Scaffold(
      backgroundColor: _bgDark,
      appBar: AppBar(
        backgroundColor: _bgDark,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          title,
          style:
              const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800.0),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCardContainer({required List<Widget> children}) {
    return Container(
      decoration: BoxDecoration(
        color: _cardDark,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withAlpha(10)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
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
                border: Border.all(color: Colors.white.withAlpha(10)),
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
                              const Text(
                                'Color Theme',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Changes the look of the entire app',
                                style: TextStyle(
                                    color: mutedText, fontSize: 12),
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
                        return GestureDetector(
                          onTap: () {
                            AppThemeService.instance.saveTheme(theme.id);
                            setState(() => _activeThemeId = theme.id);
                            setSubState(() {});
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 220),
                            curve: Curves.easeOutCubic,
                            width: 80,
                            margin: const EdgeInsets.only(right: 12, bottom: 16),
                            decoration: BoxDecoration(
                              color: theme.bgDark,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: isActive
                                    ? theme.primary
                                    : Colors.white.withAlpha(18),
                                width: isActive ? 2.5 : 1.5,
                              ),
                              boxShadow: isActive
                                  ? [
                                      BoxShadow(
                                        color:
                                            theme.primary.withAlpha(80),
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
                                        : Colors.white70,
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
                SwitchListTile(
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  activeThumbColor: Colors.white,
                  activeTrackColor: _primary,
                  inactiveThumbColor: Colors.white70,
                  inactiveTrackColor: Colors.white10,
                  title: const Text('Waveform Seek Bar',
                      style: TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w500)),
                  subtitle: Text(
                    'Replaces classic time slider with interactive track amplitude waveform',
                    style: TextStyle(color: _textDark, fontSize: 12),
                  ),
                  secondary: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: _primary.withAlpha(25),
                      shape: BoxShape.circle,
                    ),
                    child:
                        Icon(Icons.graphic_eq, color: _primary, size: 20),
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
                ListTile(
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  leading: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: _primary.withAlpha(25),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.tour_rounded, color: _primary, size: 20),
                  ),
                  title: const Text('Re-run Feature Tour',
                      style: TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w500)),
                  subtitle: Text(
                    'Re-start the interactive guided walkthrough for SautiPlay',
                    style: TextStyle(color: _textDark, fontSize: 12),
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
            _buildSectionHeader('STREAMING QUALITY'),
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
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: _primary.withAlpha(25),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(Icons.graphic_eq,
                                color: _primary, size: 24),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Streaming Quality',
                                    style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 16,
                                        fontWeight: FontWeight.w500)),
                                const SizedBox(height: 4),
                                Text('Higher quality uses more network data',
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
                          color: Colors.black26,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: GestureDetector(
                                onTap: () {
                                  setState(() =>
                                      _streamingQuality = 'High Fidelity');
                                  setSubState(() {});
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
                                      color:
                                          _streamingQuality == 'High Fidelity'
                                              ? Colors.white
                                              : _textDark,
                                      fontWeight:
                                          _streamingQuality == 'High Fidelity'
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
                                  setState(
                                      () => _streamingQuality = 'Data Saver');
                                  setSubState(() {});
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
                                      fontWeight:
                                          _streamingQuality == 'Data Saver'
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
            const SizedBox(height: 20),
            _buildSectionHeader('RESAMPLING & DITHERING'),
            const SizedBox(height: 8),
            _buildCardContainer(
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
                    child: const Icon(Icons.memory,
                        color: Colors.white70, size: 20),
                  ),
                  title: const Text('Resampler',
                      style: TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w500)),
                  trailing: SizedBox(
                    width: 170,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Expanded(
                          child: Text(
                            _getResampleAlgorithmName(_resampleAlgorithm),
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
                  onTap: () => _showResampleAlgorithmDialog(
                      onDone: () => setSubState(() {})),
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
                    child: const Icon(Icons.blur_on,
                        color: Colors.white70, size: 20),
                  ),
                  title: const Text('Oversampler',
                      style: TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w500)),
                  subtitle: Text('Anti-aliasing for ViPER FX & limiters',
                      style: TextStyle(color: _textDark, fontSize: 12)),
                  trailing: SizedBox(
                    width: 150,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Expanded(
                          child: Text(
                            _getOversamplingName(_dspOversampling),
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
                  onTap: () =>
                      _showOversamplingDialog(onDone: () => setSubState(() {})),
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
                    child: const Icon(Icons.waves,
                        color: Colors.white70, size: 20),
                  ),
                  title: const Text('Dither',
                      style: TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w500)),
                  trailing: SizedBox(
                    width: 150,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Expanded(
                          child: Text(
                            _getDitherModeName(_ditherMode),
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
                        const Icon(Icons.code, color: Colors.white70, size: 20),
                  ),
                  title: const Text('Output Bit Depth',
                      style: TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w500)),
                  subtitle: Text('Hardware PCM bit precision',
                      style: TextStyle(color: _textDark, fontSize: 12)),
                  trailing: SizedBox(
                    width: 150,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Expanded(
                          child: Text(
                            _formatAudioDepth(widget.outputFormat),
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
                  onTap: () =>
                      _showOutputFormatDialog(onDone: () => setSubState(() {})),
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
                    child: const Icon(Icons.speed,
                        color: Colors.white70, size: 20),
                  ),
                  title: const Text('Sample Rate',
                      style: TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w500)),
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
                  onTap: () =>
                      _showSampleRateDialog(onDone: () => setSubState(() {})),
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
                    child: const Icon(Icons.speaker_group,
                        color: Colors.white70, size: 20),
                  ),
                  title: const Text('Output Channels',
                      style: TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w500)),
                  trailing: SizedBox(
                    width: 150,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Expanded(
                          child: Text(
                            _formatChannelCount(widget.outputChannels),
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
                  onTap: () =>
                      _showChannelsDialog(onDone: () => setSubState(() {})),
                ),
                const Divider(color: Colors.white10, height: 1),
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
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
                            child: const Icon(Icons.swap_calls,
                                color: Colors.white70, size: 20),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Phase Inversion (Ø 180°)',
                                  style: TextStyle(
                                      color: Colors.white,
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
                            child: SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              title: const Text('Left Phase Ø',
                                  style: TextStyle(
                                      color: Colors.white, fontSize: 13)),
                              value: _phaseInvertLeft,
                              activeThumbColor: _primary,
                              onChanged: (val) {
                                setState(() => _phaseInvertLeft = val);
                                _persistPhaseInversionSettings();
                                setSubState(() {});
                              },
                            ),
                          ),
                          Expanded(
                            child: SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              title: const Text('Right Phase Ø',
                                  style: TextStyle(
                                      color: Colors.white, fontSize: 13)),
                              value: _phaseInvertRight,
                              activeThumbColor: _primary,
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
                    child: const Icon(Icons.verified,
                        color: Colors.white70, size: 20),
                  ),
                  title: const Text('Bit-Perfect Playback',
                      style: TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w500)),
                  subtitle: Text(
                      'Bypasses OS Mixer & DSP (Exclusive Mode)',
                      style: TextStyle(color: _textDark, fontSize: 12)),
                  value: widget.exclusiveMode,
                  activeThumbColor: _primary,
                  onChanged: (val) async {
                    widget.player.setExclusiveMode(val);
                    await Future.delayed(const Duration(milliseconds: 150));
                    final actual = await widget.player.getExclusiveMode();
                    widget.onExclusiveModeChanged(actual);
                    setSubState(() {});
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).hideCurrentSnackBar();
                    if (val && !actual) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          backgroundColor: _cardDark,
                          behavior: SnackBarBehavior.floating,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: BorderSide(
                                color: Colors.amberAccent.withAlpha(80)),
                          ),
                          content: const Row(
                            children: [
                              Icon(Icons.warning_amber_rounded,
                                  color: Colors.amberAccent, size: 20),
                              SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'Hardware rejected Exclusive Mode. Falling back!',
                                  style: TextStyle(
                                      color: Colors.white, fontSize: 13),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }
                  },
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
                    child: const Icon(Icons.architecture,
                        color: Colors.white70, size: 20),
                  ),
                  title: const Text('64-Bit Float DSP',
                      style: TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w500)),
                  subtitle: Text('Double-precision',
                      style: TextStyle(color: _textDark, fontSize: 12)),
                  value: _use64BitProcessingEnabled,
                  activeThumbColor: _primary,
                  onChanged: (val) {
                    setState(() => _use64BitProcessingEnabled = val);
                    widget.player.set64BitProcessingEnabled(val);
                    AppStateService.instance.save64BitProcessingEnabled(val);
                    setSubState(() {});
                  },
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
                    child: const Icon(Icons.graphic_eq,
                        color: Colors.white70, size: 20),
                  ),
                  title: const Text('Auto Bit-Perfect',
                      style: TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w500)),
                  subtitle: Text('DAC to match audio track sample rate',
                      style: TextStyle(color: _textDark, fontSize: 12)),
                  value: _autoBitPerfectEnabled,
                  activeThumbColor: _primary,
                  onChanged: (val) {
                    setState(() => _autoBitPerfectEnabled = val);
                    widget.player.setAutoBitPerfectEnabled(val);
                    AppStateService.instance.saveAutoBitPerfectEnabled(val);
                    setSubState(() {});
                  },
                ),
              ],
            ),
            const SizedBox(height: 20),
            _buildSectionHeader('HARDWARE PROTECTION'),
            const SizedBox(height: 8),
            _buildCardContainer(
              children: [
                SwitchListTile(
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  activeThumbColor: Colors.white,
                  activeTrackColor: _primary,
                  inactiveThumbColor: Colors.white70,
                  inactiveTrackColor: Colors.white10,
                  title: const Text('Hardware Safeguards',
                      style: TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w500)),
                  subtitle: Text(
                    _speakerProtectionEnabled
                        ? 'Peak ceiling & subsonic/ultrasonic guard active'
                        : 'Hardware protection disabled',
                    style: TextStyle(
                      color: _speakerProtectionEnabled
                          ? Colors.greenAccent.shade200
                          : Colors.amberAccent,
                      fontSize: 12,
                    ),
                  ),
                  secondary: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: (_speakerProtectionEnabled
                              ? _primary
                              : Colors.amberAccent)
                          .withAlpha(25),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      _speakerProtectionEnabled
                          ? Icons.health_and_safety
                          : Icons.warning_amber_rounded,
                      color: _speakerProtectionEnabled
                          ? _primary
                          : Colors.amberAccent,
                      size: 20,
                    ),
                  ),
                  value: _speakerProtectionEnabled,
                  onChanged: (val) {
                    setState(() => _speakerProtectionEnabled = val);
                    setSubState(() {});
                    _persistSpeakerProtectionSettings();
                  },
                ),
                if (_speakerProtectionEnabled) ...[
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
                      child: const Icon(Icons.arrow_upward,
                          color: Colors.white70, size: 20),
                    ),
                    title: const Text('Subsonic Filter (High-Pass)',
                        style: TextStyle(
                            color: Colors.white, fontWeight: FontWeight.w500)),
                    subtitle: Text('Below woofer tuning',
                        style: TextStyle(color: _textDark, fontSize: 12)),
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
                    onTap: () =>
                        _showSubsonicDialog(onDone: () => setSubState(() {})),
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
                      child: const Icon(Icons.arrow_downward,
                          color: Colors.white70, size: 20),
                    ),
                    title: const Text('Ultrasonic Guard (Low-Pass)',
                        style: TextStyle(
                            color: Colors.white, fontWeight: FontWeight.w500)),
                    subtitle: Text('Filters frequencies above 18-22kHz',
                        style: TextStyle(color: _textDark, fontSize: 12)),
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
                              style: TextStyle(
                                  color: _textDark, fontSize: 13),
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
                    onTap: () =>
                        _showUltrasonicDialog(onDone: () => setSubState(() {})),
                  ),
                  const Divider(color: Colors.white10, height: 1),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 16),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Peak Ceiling',
                                  style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w500)),
                              const SizedBox(height: 2),
                              Text(
                                'Max: ${(_limiterThreshold * 100).toInt()}% (${(20 * math.log(_limiterThreshold) / math.ln10).toStringAsFixed(2)} dBFS)',
                                style: TextStyle(
                                    color: _textDark, fontSize: 12),
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
                  const Divider(color: Colors.white10, height: 1),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 16),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Safety Headroom',
                                  style: TextStyle(
                                      color: Colors.white,
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
            const SizedBox(height: 20),
            _buildSectionHeader('REPLAYGAIN & LOUDNESS'),
            const SizedBox(height: 8),
            _buildCardContainer(
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
                    child: const Icon(Icons.equalizer,
                        color: Colors.white70, size: 20),
                  ),
                  title: const Text('ReplayGain Mode',
                      style: TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w500)),
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
                  onTap: () => _showReplayGainModeDialog(
                      onDone: () => setSubState(() {})),
                ),
                const Divider(color: Colors.white10, height: 1),
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Preamp Gain',
                        style: TextStyle(
                            color: Colors.white, fontWeight: FontWeight.w500),
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
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: _primary.withAlpha(25),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(Icons.settings_input_composite,
                                color: _primary, size: 24),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Frequency Precision',
                                    style: TextStyle(
                                        color: Colors.white,
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
                          color: Colors.black26,
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
                SwitchListTile(
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  secondary: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white.withAlpha(10),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.bar_chart,
                        color: Colors.white70, size: 20),
                  ),
                  title: const Text('Spectrum Analyzer',
                      style: TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w500)),
                  subtitle: Text('Audio Spectrum Visualizer',
                      style: TextStyle(color: _textDark, fontSize: 12)),
                  value: widget.analyzerEnabled,
                  activeThumbColor: _primary,
                  onChanged: (v) {
                    widget.onAnalyzerEnabledChanged(v);
                    setSubState(() {});
                  },
                ),
                if (widget.analyzerEnabled) ...[
                  const Divider(color: Colors.white10, height: 1),
                  Padding(
                    padding: const EdgeInsets.all(20.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Analyzer Type',
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
                  const Divider(color: Colors.white10, height: 1),
                  Padding(
                    padding: const EdgeInsets.all(20.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Spectrum Theme',
                            style: TextStyle(
                                color: Colors.white,
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
                  const Divider(color: Colors.white10, height: 1),
                  SwitchListTile(
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                    activeThumbColor: Colors.white,
                    activeTrackColor: _primary,
                    inactiveThumbColor: Colors.white70,
                    inactiveTrackColor: Colors.white10,
                    title: const Text('Auto Fit Scale',
                        style: TextStyle(
                            color: Colors.white, fontWeight: FontWeight.w500)),
                    subtitle: Text('Dynamically adjust Y-axis peak range',
                        style: TextStyle(color: _textDark, fontSize: 12)),
                    value: widget.analyzerAutoFit,
                    onChanged: (v) {
                      widget.onAnalyzerAutoFitChanged(v);
                      setSubState(() {});
                    },
                  ),
                  const Divider(color: Colors.white10, height: 1),
                  SwitchListTile(
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                    activeThumbColor: Colors.white,
                    activeTrackColor: _primary,
                    inactiveThumbColor: Colors.white70,
                    inactiveTrackColor: Colors.white10,
                    title: const Text('Show Grids & Decibels',
                        style: TextStyle(
                            color: Colors.white, fontWeight: FontWeight.w500)),
                    value: widget.analyzerShowGrids,
                    onChanged: (v) {
                      widget.onAnalyzerShowGridsChanged(v);
                      setSubState(() {});
                    },
                  ),
                  const Divider(color: Colors.white10, height: 1),
                  SwitchListTile(
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                    activeThumbColor: Colors.white,
                    activeTrackColor: _primary,
                    inactiveThumbColor: Colors.white70,
                    inactiveTrackColor: Colors.white10,
                    title: const Text('Logarithmic Decibel Scale',
                        style: TextStyle(
                            color: Colors.white, fontWeight: FontWeight.w500)),
                    subtitle: Text('Logarithmic audio response curve',
                        style: TextStyle(color: _textDark, fontSize: 12)),
                    value: widget.analyzerLogScale,
                    onChanged: (v) {
                      widget.onAnalyzerLogScaleChanged(v);
                      setSubState(() {});
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
                      child: const Icon(Icons.data_array,
                          color: Colors.white70, size: 20),
                    ),
                    title: const Text('FFT Sample Size',
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
                              style: TextStyle(
                                  color: _textDark, fontSize: 14),
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
                SwitchListTile(
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  activeThumbColor: Colors.white,
                  activeTrackColor: _primary,
                  inactiveThumbColor: Colors.white70,
                  inactiveTrackColor: Colors.white10,
                  title: const Text('Gapless Playback',
                      style: TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w500)),
                  subtitle: Text(
                      'Seamless transitions between track ends',
                      style: TextStyle(color: _textDark, fontSize: 12)),
                  secondary: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white.withAlpha(10),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.queue_music,
                        color: Colors.white70, size: 20),
                  ),
                  value: _gaplessPlayback,
                  onChanged: (v) {
                    setState(() => _gaplessPlayback = v);
                    setSubState(() {});
                    _persistUiSettings();
                  },
                ),
                const Divider(color: Colors.white10, height: 1),
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
                              const Text('Crossfade Duration',
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
                                setSubState(() {});
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
                          disabledInactiveTrackColor:
                              Colors.white10.withAlpha(50),
                          disabledThumbColor: Colors.white54,
                        ),
                        child: Slider(
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
                                  widget.player.setCrossfadeDurationMs(
                                      (v * 1000).toInt());
                                }
                              : null,
                        ),
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
                const Divider(color: Colors.white10, height: 1),
                SwitchListTile(
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  activeThumbColor: Colors.white,
                  activeTrackColor: _primary,
                  inactiveThumbColor: Colors.white70,
                  inactiveTrackColor: Colors.white10,
                  title: const Text('Normalize Volume',
                      style: TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w500)),
                  subtitle: Text('Normalizes volume across tracks',
                      style: TextStyle(color: _textDark, fontSize: 12)),
                  secondary: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white.withAlpha(10),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.bar_chart,
                        color: Colors.white70, size: 20),
                  ),
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
                SwitchListTile(
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  activeThumbColor: Colors.white,
                  activeTrackColor: _primary,
                  inactiveThumbColor: Colors.white70,
                  inactiveTrackColor: Colors.white10,
                  title: const Text('Stream over Wi-Fi Only',
                      style: TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w500)),
                  secondary: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white.withAlpha(10),
                      shape: BoxShape.circle,
                    ),
                    child:
                        const Icon(Icons.wifi, color: Colors.white70, size: 20),
                  ),
                  value: _streamOverWifi,
                  onChanged: (v) {
                    setState(() => _streamOverWifi = v);
                    setSubState(() {});
                    _persistUiSettings();
                  },
                ),
                const Divider(color: Colors.white10, height: 1),
                ListTile(
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  leading: const Icon(Icons.dns, color: Colors.white70, size: 20),
                  title: const Text('Audio Cache Storage',
                      style: TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w500)),
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
                ListTile(
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  leading:
                      const Icon(Icons.info_outline, color: Colors.white70, size: 20),
                  title: const Text('Version',
                      style: TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w500)),
                  trailing: Text(_appVersion,
                      style: const TextStyle(color: Colors.white54, fontSize: 14)),
                ),
                const Divider(color: Colors.white10, height: 1),
                ListTile(
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  leading: const Icon(Icons.policy_outlined,
                      color: Colors.white70, size: 20),
                  title: const Text('Open Source Licenses',
                      style: TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w500)),
                  trailing: Icon(Icons.chevron_right,
                      color: _textDark, size: 20),
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
                SwitchListTile(
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  activeThumbColor: Colors.white,
                  activeTrackColor: _primary,
                  inactiveThumbColor: Colors.white70,
                  inactiveTrackColor: Colors.white10,
                  title: const Text('Allow invalid TLS certs',
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w500,
                          fontSize: 14)),
                  subtitle: Text('Testing & fallback media server mode',
                      style: TextStyle(color: _textDark, fontSize: 12)),
                  secondary: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white.withAlpha(10),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.security,
                        color: Colors.white70, size: 20),
                  ),
                  value: widget.allowInvalidTls,
                  onChanged: (v) {
                    widget.onAllowInvalidTlsChanged(v);
                    setSubState(() {});
                  },
                ),
                const Divider(color: Colors.white10, height: 1),
                ListTile(
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  leading: const Icon(Icons.refresh,
                      color: Colors.white70, size: 20),
                  title: const Text('Poll Native Error',
                      style: TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w500)),
                  trailing: Icon(Icons.chevron_right,
                      color: _textDark, size: 20),
                  onTap: widget.onPollError,
                ),
                const Divider(color: Colors.white10, height: 1),
                ListTile(
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  leading: const Icon(Icons.cleaning_services_outlined,
                      color: Colors.white70, size: 20),
                  title: const Text('Clear Native Error',
                      style: TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w500)),
                  trailing: Icon(Icons.chevron_right,
                      color: _textDark, size: 20),
                  onTap: widget.onClearNativeError,
                ),
                const Divider(color: Colors.white10, height: 1),
                Theme(
                  data: Theme.of(context)
                      .copyWith(dividerColor: Colors.transparent),
                  child: ValueListenableBuilder<int>(
                    valueListenable: widget.logUpdateNotifier,
                    builder: (context, _, __) {
                      return ExpansionTile(
                        tilePadding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 8),
                        leading: const Icon(Icons.article_outlined,
                            color: Colors.white70, size: 20),
                        title: const Text('App Engine Logs',
                            style: TextStyle(
                                color: Colors.white,
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
                                  child: OutlinedButton.icon(
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
                                  child: OutlinedButton.icon(
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
                              color: Colors.black26,
                              borderRadius: BorderRadius.circular(12),
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
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w500)),
              subtitle: Text(item['subtitle'] as String,
                  style: TextStyle(color: _textDark, fontSize: 12)),
              value: item['factor'] as int,
              groupValue: _dspOversampling,
              activeColor: _primary,
              onChanged: (val) {
                if (val != null) {
                  setState(() => _dspOversampling = val);
                  widget.player.setViperOversampling(val);
                  AppStateService.instance.saveDspOversampling(val);
                  onDone?.call();
                  Navigator.pop(ctx);
                }
              },
            ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  void _showResampleAlgorithmDialog({VoidCallback? onDone}) {
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
              onDone?.call();
              Navigator.pop(ctx);
            }),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  void _showAnalyzerSampleSizeDialog({VoidCallback? onDone}) {
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
                size.toString(), widget.analyzerSampleSize.toString(), (v) {
              widget.onAnalyzerSampleSizeChanged(size);
              onDone?.call();
              Navigator.pop(ctx);
            }),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Future<void> _showReplayGainModeDialog({VoidCallback? onDone}) async {
    return showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: _cardDark,
          title: const Text('ReplayGain Mode',
              style: TextStyle(color: Colors.white)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              RadioListTile<ReplayGainMode>(
                title:
                    const Text('None', style: TextStyle(color: Colors.white)),
                activeColor: _primary,
                value: ReplayGainMode.none,
                groupValue: _replayGainMode,
                onChanged: (val) {
                  setState(() => _replayGainMode = val!);
                  _persistReplayGainSettings();
                  onDone?.call();
                  Navigator.pop(context);
                },
              ),
              RadioListTile<ReplayGainMode>(
                title:
                    const Text('Track', style: TextStyle(color: Colors.white)),
                activeColor: _primary,
                value: ReplayGainMode.track,
                groupValue: _replayGainMode,
                onChanged: (val) {
                  setState(() => _replayGainMode = val!);
                  _persistReplayGainSettings();
                  onDone?.call();
                  Navigator.pop(context);
                },
              ),
              RadioListTile<ReplayGainMode>(
                title:
                    const Text('Album', style: TextStyle(color: Colors.white)),
                activeColor: _primary,
                value: ReplayGainMode.album,
                groupValue: _replayGainMode,
                onChanged: (val) {
                  setState(() => _replayGainMode = val!);
                  _persistReplayGainSettings();
                  onDone?.call();
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
                    title: Text(name,
                        style: const TextStyle(
                            color: Colors.white, fontWeight: FontWeight.w500)),
                    subtitle: Text(subtitle,
                        style: TextStyle(color: _textDark, fontSize: 12)),
                    value: id,
                    groupValue: _ditherMode,
                    activeColor: _primary,
                    onChanged: (val) {
                      if (val != null) {
                        setState(() => _ditherMode = val);
                        widget.player.setEngineDitherMode(val);
                        _persistUiSettings();
                        onDone?.call();
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

  void _showOutputFormatDialog({VoidCallback? onDone}) {
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
            _buildRadioOption(
                _formatAudioDepth(fmt), _formatAudioDepth(widget.outputFormat),
                (v) {
              widget.onOutputFormatChanged(fmt);
              widget.player.setOutputFormat(fmt);
              onDone?.call();
              Navigator.pop(ctx);
            }),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  void _showSampleRateDialog({VoidCallback? onDone}) {
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
                final val =
                    v == 'Native' ? 0 : int.parse(v!.replaceAll(' Hz', ''));
                widget.onOutputSampleRateChanged(val);
                widget.player.setOutputSampleRate(val);
                onDone?.call();
                Navigator.pop(ctx);
              })),
          const SizedBox(height: 20),
        ],
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
      {'ch': 2, 'name': 'Stereo (2.0)', 'subtitle': 'Standard 2-channel Left / Right'},
      {'ch': 3, 'name': '2.1 Surround (3 CH)', 'subtitle': 'Left, Right, Center/Sub'},
      {'ch': 4, 'name': '4.0 Quadraphonic (4 CH)', 'subtitle': 'FL, FR, Center, Back Center'},
      {'ch': 5, 'name': '5.0 Surround (5 CH)', 'subtitle': 'FL, FR, Center, Back L/R'},
      {'ch': 6, 'name': '5.1 Surround (6 CH)', 'subtitle': 'FL, FR, Center, LFE Sub, Side L/R'},
      {'ch': 7, 'name': '7.0 Surround (7 CH)', 'subtitle': 'FL, FR, Center, LFE, Back C, Side L/R'},
      {'ch': 8, 'name': '7.1 Surround (8 CH)', 'subtitle': 'FL, FR, Center, LFE, Back L/R, Side L/R'},
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
              child: Text('Engine Output Channels',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold)),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: options.length,
                itemBuilder: (context, i) {
                  final item = options[i];
                  final ch = item['ch'] as int;
                  final name = item['name'] as String;
                  final subtitle = item['subtitle'] as String;
                  return RadioListTile<int>(
                    title: Text(name,
                        style: const TextStyle(
                            color: Colors.white, fontWeight: FontWeight.w500)),
                    subtitle: Text(subtitle,
                        style: TextStyle(color: _textDark, fontSize: 12)),
                    value: ch,
                    groupValue: widget.outputChannels,
                    activeColor: _primary,
                    onChanged: (val) {
                      if (val != null) {
                        widget.onOutputChannelsChanged(val);
                        widget.player.setOutputChannels(val);
                        onDone?.call();
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

  void _showSubsonicDialog({VoidCallback? onDone}) {
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
              style:
                  TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
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
                        fontWeight:
                            selected ? FontWeight.w600 : FontWeight.normal)),
                onChanged: (val) {
                  if (val != null) {
                    setState(() => _subsonicCutoffHz = val);
                    _persistSpeakerProtectionSettings();
                    onDone?.call();
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

  void _showUltrasonicDialog({VoidCallback? onDone}) {
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
              style:
                  TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
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
                        fontWeight:
                            selected ? FontWeight.w600 : FontWeight.normal)),
                onChanged: (val) {
                  if (val != null) {
                    setState(() => _ultrasonicCutoffHz = val);
                    _persistSpeakerProtectionSettings();
                    onDone?.call();
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
