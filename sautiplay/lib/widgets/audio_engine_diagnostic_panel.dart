import 'dart:async';
import 'dart:math' as math;
import 'package:material_ui/material_ui.dart';
import 'package:material_3_expressive/components/progress_indicators/m3e_progress_indicators.dart';
import 'package:sautiflow/sautiflow.dart';
import 'package:sautiplay/isolate_player.dart';
import 'package:sautiplay/services/app_state_service.dart';
import 'package:sautiplay/services/app_theme_service.dart';
import 'package:sautiplay/services/audio_hardware_inspector.dart';
import 'package:sautiplay/services/chromecast_service.dart';
import 'package:sautiplay/services/dlna_renderer_service.dart';
import 'package:sautiplay/services/dlna_service.dart';
import 'package:sautiplay/widgets/adaptive_marquee_text.dart';
import 'package:sautiplay/widgets/signal_path.dart';
import 'package:sautiplay/widgets/signal_path_card.dart';

/// Shows the Developer & Audiophile Audio Engine Diagnostic Panel as a glassmorphic bottom sheet.
void showAudioEngineDiagnosticPanel(
    BuildContext context, IsolateAudioPlayer player,
    {String? filePath}) {
  final isDark = context.isDark;
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: isDark ? 0.65 : 0.35),
    builder: (ctx) =>
        AudioEngineDiagnosticPanel(player: player, filePath: filePath),
  );
}

class AudioEngineDiagnosticPanel extends StatefulWidget {
  final IsolateAudioPlayer player;
  final String? filePath;

  const AudioEngineDiagnosticPanel({
    super.key,
    required this.player,
    this.filePath,
  });

  @override
  State<AudioEngineDiagnosticPanel> createState() =>
      _AudioEngineDiagnosticPanelState();
}

class _AudioEngineDiagnosticPanelState
    extends State<AudioEngineDiagnosticPanel> {
  Timer? _telemetryTimer;
  StreamSubscription<AudioHardwareSpecs>? _hardwareSub;
  StreamSubscription<AppThemeId>? _themeSub;
  AudioHardwareSpecs? _hardwareSpecs;
  Map<String, dynamic>? _telemetry;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _themeSub = AppThemeService.instance.themeChanged.stream.listen((_) {
      if (mounted) {
        setState(() {});
      }
    });

    _hardwareSpecs = AudioHardwareInspector.currentSpecs;
    _hardwareSub =
        AudioHardwareInspector.hardwareStream(widget.player).listen((specs) {
      if (mounted) {
        setState(() {
          _hardwareSpecs = specs;
        });
      }
    });
    AudioHardwareInspector.inspectAsync(widget.player).then((specs) {
      if (mounted) {
        setState(() {
          _hardwareSpecs = specs;
        });
      }
    });

    widget.player.setClippingDetectionEnabled(true);
    widget.player.setTruePeakMeterEnabled(true);
    widget.player.setLoudnessMeterEnabled(true);

    _fetchTelemetry();
    _telemetryTimer = Timer.periodic(const Duration(milliseconds: 250), (_) {
      _fetchTelemetry();
    });
  }

  @override
  void dispose() {
    _themeSub?.cancel();
    _telemetryTimer?.cancel();
    _hardwareSub?.cancel();
    widget.player.setTruePeakMeterEnabled(false);
    widget.player.setLoudnessMeterEnabled(false);
    super.dispose();
  }

  Future<void> _fetchTelemetry() async {
    try {
      final data = await widget.player.getEngineTelemetry();
      if (mounted) {
        setState(() {
          _telemetry = data;
          _loading = false;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final theme = Theme.of(context);
    final hasAppTheme =
        context.dependOnInheritedWidgetOfExactType<AppThemeProvider>() != null;
    final appTheme = context.appTheme;
    final isDark =
        hasAppTheme ? context.isDark : (theme.brightness == Brightness.dark);
    final primary = hasAppTheme ? appTheme.primary : theme.colorScheme.primary;
    final textPrimary = hasAppTheme
        ? context.textPrimary
        : (isDark ? Colors.white : const Color(0xFF1A1A2E));
    final outlineColor = hasAppTheme
        ? context.outlineColor
        : textPrimary.withValues(alpha: 0.12);

    final sheetSurface = isDark
        ? (appTheme.id == AppThemeId.amoledBlack
            ? const Color(0xFF0A0A0A)
            : appTheme.cardDark)
        : appTheme.cardDark;

    return Container(
      constraints: BoxConstraints(
        maxHeight: mediaQuery.size.height * 0.90,
      ),
      decoration: BoxDecoration(
        color: sheetSurface.withValues(alpha: isDark ? 0.96 : 0.98),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        border: Border.all(
          color: isDark ? primary.withValues(alpha: 0.25) : outlineColor,
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: primary.withValues(alpha: isDark ? 0.15 : 0.08),
            blurRadius: 32,
            spreadRadius: 2,
          )
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Drag handle
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 42,
              height: 5,
              decoration: BoxDecoration(
                color: isDark ? Colors.white24 : Colors.black26,
                borderRadius: BorderRadius.circular(2.5),
              ),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Row(
              children: [
                const SizedBox(width: 4),
                Expanded(
                  child: Row(
                    children: [
                      Flexible(
                        child: AdaptiveMarqueeText(
                          text: 'Audio Info & Diagnostics',
                          style: TextStyle(
                            color: textPrimary,
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                            letterSpacing: 1.1,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          color: isDark
                              ? const Color(0xFF4ADE80)
                              : const Color(0xFF16A34A),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'LIVE',
                        style: TextStyle(
                          fontFamily: 'monospace',
                          color: isDark
                              ? const Color(0xFF4ADE80)
                              : const Color(0xFF16A34A),
                          fontWeight: FontWeight.bold,
                          fontSize: 10,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.08)
                        : Colors.black.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Center(
                    child: IconButton(
                      padding: EdgeInsets.zero,
                      icon: Icon(
                        Icons.close_rounded,
                        color: textPrimary.withValues(alpha: 0.7),
                        size: 20,
                      ),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ),
                )
              ],
            ),
          ),

          Divider(color: outlineColor, height: 1),

          // Body
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: _loading
                  ? const Padding(
                      padding: EdgeInsets.all(40),
                      child: Center(child: M3EProgressIndicator.circularWavy()),
                    )
                  : _error != null
                      ? Padding(
                          padding: const EdgeInsets.all(20),
                          child: Text(
                            'Engine Telemetry Error: $_error',
                            style: TextStyle(
                              color: isDark
                                  ? Colors.redAccent
                                  : const Color(0xFFDC2626),
                            ),
                          ),
                        )
                      : _buildDiagnosticsContent(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDiagnosticsContent(BuildContext context) {
    final t = _telemetry!;
    final hw = (t['hardware'] as Map?)?.cast<String, dynamic>() ?? {};

    final specs = _hardwareSpecs ??
        AudioHardwareInspector.currentSpecs ??
        AudioHardwareInspector.inspect(widget.player);

    final activeDlna = DlnaService.instance.activeRenderer;
    final activeCast = ChromecastService.instance.activeDevice;
    final dlnaRenderer = DlnaRendererService.instance;
    final isCastingDlna = activeDlna != null;
    final isCastingChromecast = activeCast != null && !isCastingDlna;
    final isCastingOut = isCastingDlna || isCastingChromecast;
    final isReceivingDlna = !isCastingOut &&
        dlnaRenderer.isRunning &&
        dlnaRenderer.currentUri.isNotEmpty &&
        (dlnaRenderer.transportState == 'PLAYING' ||
            dlnaRenderer.transportState == 'PAUSED_PLAYBACK' ||
            dlnaRenderer.transportState == 'TRANSITIONING');

    final String activeDeviceName = isCastingDlna
        ? activeDlna.name
        : isCastingChromecast
            ? activeCast.friendlyName
            : (specs.isBluetooth
                ? (specs.bluetoothDeviceName?.isNotEmpty == true
                    ? specs.bluetoothDeviceName!
                    : specs.deviceName)
                : specs.deviceName);
    final String activeDeviceType = isCastingDlna
        ? 'DLNA / UPnP Renderer'
        : isCastingChromecast
            ? 'Google Cast (Chromecast)'
            : specs.deviceType;

    final String fileType = (t['fileType'] as String? ?? 'PCM').toUpperCase();
    final int bitrateKbps = t['bitrateKbps'] as int? ?? 0;
    final int fileSizeBytes = t['fileSizeBytes'] as int? ?? 0;

    double? rgTrack = (t['replayGainTrack'] as num?)?.toDouble();
    double? rgAlbum = (t['replayGainAlbum'] as num?)?.toDouble();
    final String? activeFilePath =
        (t['filePath'] as String?) ?? widget.filePath;

    // Fallback: If telemetry did not provide ReplayGain and a local file path exists,
    // read directly via the metadata reader.
    if (rgTrack == null &&
        rgAlbum == null &&
        activeFilePath != null &&
        activeFilePath.isNotEmpty) {
      try {
        final meta = readMetadata(activeFilePath, getImage: false);
        if (meta.trackGainDb != 0.0) rgTrack = meta.trackGainDb;
        if (meta.albumGainDb != 0.0) rgAlbum = meta.albumGainDb;
      } catch (_) {}
    }

    String replayGainDisplay = 'null';
    bool hasReplayGain = false;
    if (rgTrack != null && rgAlbum != null) {
      hasReplayGain = true;
      final tStr = '${rgTrack >= 0 ? "+" : ""}${rgTrack.toStringAsFixed(2)} dB';
      final aStr = '${rgAlbum >= 0 ? "+" : ""}${rgAlbum.toStringAsFixed(2)} dB';
      replayGainDisplay = '$tStr (Track) / $aStr (Album)';
    } else if (rgTrack != null) {
      hasReplayGain = true;
      final tStr = '${rgTrack >= 0 ? "+" : ""}${rgTrack.toStringAsFixed(2)} dB';
      replayGainDisplay = '$tStr (Track)';
    } else if (rgAlbum != null) {
      hasReplayGain = true;
      final aStr = '${rgAlbum >= 0 ? "+" : ""}${rgAlbum.toStringAsFixed(2)} dB';
      replayGainDisplay = '$aStr (Album)';
    }

    String bitrateDisplay = 'N/A';
    if (bitrateKbps > 0) {
      bitrateDisplay = '$bitrateKbps kbps';
      if (['FLAC', 'ALAC'].contains(fileType)) {
        bitrateDisplay += '';
      } else if (['WAV', 'AIFF'].contains(fileType)) {
        bitrateDisplay += '';
      } else if (['MP3', 'AAC', 'M4A', 'OGG', 'OPUS'].contains(fileType)) {
        bitrateDisplay += '';
      }
    }

    final int srcRate = t['inputSampleRate'] as int? ?? 48000;
    final int srcDepth =
        t['inputBitDepth'] as int? ?? ((hw['bitDepth'] as int?) ?? 16);
    final bool srcDepthInferred = t['inputBitDepthInferred'] == true;
    final int dspRate = (t['engineSampleRate'] as int?) ??
        (t['processingSampleRate'] as int? ?? 48000);
    final int dspChannels = t['processingChannels'] as int? ?? 2;
    final int activeDsdModeInt = t['activeDsdMode'] as int? ?? 0;
    final int sourceDsdRate = t['sourceDsdRate'] as int? ?? 0;
    final int dsdOutModeInt = t['dsdOutputMode'] as int? ?? 0;
    final double dsdGainBoostDb =
        (t['dsdGainBoostDb'] as num?)?.toDouble() ?? 6.0;
    final bool nativeDsdSup = t['isNativeDsdSupported'] == true;
    final bool dopSup = t['isDopSupported'] == true;
    final ActiveDsdMode activeDsdMode =
        ActiveDsdMode.fromValue(activeDsdModeInt);
    final bool isDsdActive =
        activeDsdMode != ActiveDsdMode.none && sourceDsdRate > 0;
    final castService = ChromecastService.instance;
    final castMode = castService.audioMode;
    final castCeiling = castService.maxSampleRate;
    final bool isExclusive =
        hw['isExclusiveMode'] as bool? ?? specs.isExclusiveMode;
    final String backend = hw['backendName'] as String? ?? specs.backendName;
    final int periodFrames =
        hw['periodSizeFrames'] as int? ?? specs.periodSizeFrames;
    final int periodCount = hw['periodCount'] as int? ?? specs.periodCount;

    final bool eqOn = t['eqEnabled'] == true;
    final bool reverbOn = t['reverbEnabled'] == true;
    final String reverbEngineName =
        (t['reverbEngine'] as String?) ?? 'Dattorro Plate';
    final double crossfeedMix = (t['crossfeedMix'] as num?)?.toDouble() ?? 0.0;
    final String crossfeedAlgo =
        formatCrossfeedAlgoName(t['crossfeedAlgo']?.toString(), crossfeedMix);
    final bool sautiDspOn = t['sautiDspEnabled'] == true;
    final bool lookaheadOn = t['lookaheadLimiterEnabled'] == true;
    final bool simpleLimiterOn = t['simpleLimiterEnabled'] == true ||
        (t['limiterEnabled'] == true && !lookaheadOn);
    final bool limiterOn = lookaheadOn || simpleLimiterOn;

    final bool normOn = t['loudnessNormalizerEnabled'] == true;
    final double normTarget =
        (t['loudnessNormalizerTarget'] as num?)?.toDouble() ?? -14.0;
    final double normGainDb =
        (t['loudnessNormalizerGainDb'] as num?)?.toDouble() ?? 0.0;
    final bool isAntiClipActive =
        normOn && (normTarget - (-12.0)).abs() < 0.5 && lookaheadOn;
    String normDisplay = 'OFF';
    if (normOn) {
      final sign = normGainDb >= 0.0 ? '+' : '';
      normDisplay =
          'ON (${normTarget.toStringAsFixed(1)} LUFS, $sign${normGainDb.toStringAsFixed(1)} dB)';
    }

    final String? castOutputLabel = isCastingDlna
        ? 'DLNA Output (${activeDlna.name})'
        : isCastingChromecast
            ? 'Cast Output (${activeCast.friendlyName})'
            : null;
    final String? dlnaSourceLabel = isReceivingDlna
        ? 'Source / DLNA Stream (${dlnaRenderer.friendlyName})'
        : null;

    final signalPath = buildSignalPath(
      t,
      specs,
      activeDeviceType: activeDeviceType,
      isCastingOut: isCastingOut,
      castMode: castMode,
      castMaxSampleRateHz: castCeiling.hz,
      castOutputLabel: castOutputLabel,
      dlnaSourceLabel: dlnaSourceLabel,
    );

    final String dspPrecisionLabel = signalPath.dspPrecisionLabel;
    final String limiterDisplay = signalPath.limiterLabel;
    final String resamplerAlgo = signalPath.resamplerLabel;
    final bool isSrcActive = signalPath.srcLabel.startsWith('ON');

    final double hwLatencyMs =
        (t['deviceLatencyMs'] as num?)?.toDouble() ?? specs.latencyMs;
    final double totalMeasuredMs =
        signalPath.totalMeasuredLatencyMs ?? hwLatencyMs;
    final int clippedCount = t['clippedCount'] as int? ?? 0;
    final int underrunCount = t['underrunCount'] as int? ?? 0;
    final double truePeakDBTP =
        (t['truePeakDBTP'] as num?)?.toDouble() ?? -100.0;

    final appTheme = context.appTheme;
    final isDark = context.isDark;
    final primary = appTheme.primary;
    final textPrimary = context.textPrimary;
    final textMuted = context.textMuted;
    final outlineColor = context.outlineColor;

    final cardBg = isDark
        ? (appTheme.id == AppThemeId.amoledBlack
            ? const Color(0xFF000000)
            : appTheme.bgDark.withValues(alpha: 0.7))
        : appTheme.bgDark.withValues(alpha: 0.6);

    final signalPathCard = SignalPathCard(
      path: signalPath,
      cardBg: cardBg,
      outlineColor: outlineColor,
      isDark: isDark,
      textPrimary: textPrimary,
      textMuted: textMuted,
    );

    final dspTelemetryCard = Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isDark ? textPrimary.withValues(alpha: 0.08) : outlineColor,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'DSP Status',
                    style: TextStyle(
                      fontFamily: 'monospace',
                      color: textPrimary.withValues(alpha: 0.85),
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.5,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Divider(
                color: isDark
                    ? textPrimary.withValues(alpha: 0.08)
                    : outlineColor,
                height: 1,
              ),
              const SizedBox(height: 12),
              _buildTelemetryRow('Device', activeDeviceName,
                  isValueActive: true, context: context),
              _buildTelemetryRow('Device Type', activeDeviceType,
                  isValueActive: true, context: context),
              if (isCastingOut)
                _buildTelemetryRow(
                  'Cast Pipeline',
                  '${castMode == CastAudioMode.bitPerfect ? "Bit-Perfect" : "With DSP (24-bit WAV)"} • Max ${castCeiling.label}',
                  isValueActive: true,
                  context: context,
                ),
              if (isReceivingDlna)
                _buildTelemetryRow(
                  'DLNA Receiver',
                  'Playing as "${dlnaRenderer.friendlyName}"',
                  isValueActive: true,
                  context: context,
                ),
              if (!isCastingOut && specs.bluetoothCodec != null)
                _buildTelemetryRow(
                  'BT Codec',
                  specs.formattedBtCodec ?? specs.bluetoothCodec!,
                  isValueActive: true,
                  context: context,
                ),
              _buildTelemetryRow('File Format', fileType,
                  isValueActive: true, context: context),
              _buildTelemetryRow('Bitrate', bitrateDisplay,
                  isValueActive: bitrateKbps > 0, context: context),
              if (fileSizeBytes > 0)
                _buildTelemetryRow('File Size',
                    '${(fileSizeBytes / (1024 * 1024)).toStringAsFixed(2)} MB',
                    isValueActive: true, context: context),
              _buildTelemetryRow('ReplayGain', replayGainDisplay,
                  isValueActive: hasReplayGain, context: context),
              _buildTelemetryRow(
                  'Source',
                  isDsdActive
                      ? '${ActiveDsdMode.formatDsdRateName(sourceDsdRate)} (${(sourceDsdRate / 1000000.0).toStringAsFixed(4)} MHz / 1-bit SDM)'
                      : '${(srcRate / 1000.0).toStringAsFixed(1)} kHz / $srcDepth-bit${srcDepthInferred ? " (inferred)" : ""} PCM',
                  isValueActive: isDsdActive,
                  context: context),
              _buildTelemetryRow(
                  'Decoder',
                  isDsdActive
                      ? switch (activeDsdMode) {
                          ActiveDsdMode.nativeDsd =>
                            'Native DSD 1-Bit Stream',
                          ActiveDsdMode.dop =>
                            'DoP v1.1 Frame Packer (0x05/0xFA)',
                          ActiveDsdMode.d2p =>
                            '128-Tap Blackman-Harris D2P Decimator (+${dsdGainBoostDb.toStringAsFixed(1)} dB)',
                          ActiveDsdMode.none =>
                            '${(srcRate / 1000.0).toStringAsFixed(1)} kHz PCM',
                        }
                      : '${(srcRate / 1000.0).toStringAsFixed(1)} kHz PCM',
                  isValueActive: isDsdActive,
                  context: context),
              if (isDsdActive) ...[
                _buildTelemetryRow(
                    'DSD Output',
                    '${activeDsdMode.shortLabel} (Pref: ${DsdOutputMode.fromValue(dsdOutModeInt).displayName})',
                    isValueActive: true,
                    context: context),
                _buildTelemetryRow(
                    'DAC DSD Support',
                    'Native: ${nativeDsdSup ? "Supported" : "No"} • DoP v1.1: ${dopSup ? "Supported" : "No"}',
                    isValueActive: nativeDsdSup || dopSup,
                    context: context),
              ],
              _buildTelemetryRow('DSP',
                  '${(dspRate / 1000.0).toStringAsFixed(1)} kHz $dspPrecisionLabel ($dspChannels ch)',
                  context: context),
              _buildTelemetryRow(
                  'Output',
                  signalPath.outputLabel,
                  context: context),
              if (!isCastingOut &&
                  specs.socName != null &&
                  specs.socName!.isNotEmpty)
                _buildTelemetryRow('SoC Processor', specs.socName!,
                    isValueActive: true, context: context),
              if (!isCastingOut &&
                  specs.dspHardware != null &&
                  specs.dspHardware!.isNotEmpty)
                _buildTelemetryRow('DSP Hardware', specs.dspHardware!,
                    isValueActive: true, context: context),
              _buildTelemetryRow(
                  'Backend',
                  isCastingDlna
                      ? 'DLNA / UPnP AVTransport (Local Media Server)'
                      : isCastingChromecast
                          ? 'Google Cast V2 TLS (Local Media Server)'
                          : '$backend (${specs.isDirectPcm ? "Hi-Res Bit-Perfect" : (isExclusive ? "Exclusive" : "Shared")})',
                  context: context),
              _buildTelemetryRow(
                  'Buffer',
                  periodCount > 1
                      ? '$periodFrames frames × $periodCount periods (${periodFrames * periodCount} total)'
                      : '$periodFrames frames',
                  context: context),
              _buildTelemetryRow('Total Latency',
                  '${totalMeasuredMs.toStringAsFixed(2)} ms (Measured)',
                  context: context),
              _buildTelemetryRow(
                  'SRC',
                  signalPath.srcLabel,
                  isValueActive: isSrcActive,
                  context: context),
              _buildTelemetryRow('Resampler', resamplerAlgo,
                  context: context),
              _buildTelemetryRow(
                  'True-Peak', '${truePeakDBTP.toStringAsFixed(1)} dBTP',
                  isValueActive: truePeakDBTP > -90.0,
                  isWarning: truePeakDBTP > -0.5,
                  context: context),
              _buildTelemetryRow('Loudness (LUFS)',
                  'Mom: ${((t['momentaryLUFS'] as num?)?.toDouble() ?? -100.0).toStringAsFixed(1)} / Int: ${((t['integratedLUFS'] as num?)?.toDouble() ?? -100.0).toStringAsFixed(1)}',
                  context: context),
              _buildTelemetryRow(
                'Normalizer',
                normDisplay,
                isValueActive: normOn,
                context: context,
                trailing: InkWell(
                  onTap: () => _toggleNormalizer(normOn, normTarget),
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: normOn
                          ? primary.withValues(alpha: isDark ? 0.15 : 0.12)
                          : (isDark
                              ? Colors.white.withValues(alpha: 0.08)
                              : Colors.black.withValues(alpha: 0.05)),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: normOn
                            ? primary.withValues(alpha: isDark ? 0.4 : 0.3)
                            : (isDark
                                ? Colors.white.withValues(alpha: 0.2)
                                : Colors.black.withValues(alpha: 0.12)),
                        width: 0.8,
                      ),
                    ),
                    child: Text(
                      normOn ? 'TOGGLE' : 'ENABLE',
                      style: TextStyle(
                        fontFamily: 'monospace',
                        color: normOn ? primary : textMuted,
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),
              _buildTelemetryRow('Limiter GR',
                  '${((t['limiterGainReductionDB'] as num?)?.toDouble() ?? 0.0).toStringAsFixed(1)} dB',
                  isValueActive:
                      ((t['limiterGainReductionDB'] as num?)?.toDouble() ??
                              0.0) <
                          -0.1,
                  context: context),
              _buildTelemetryRow('EQ', eqOn ? 'ON' : 'OFF',
                  isValueActive: eqOn, context: context),
              _buildTelemetryRow('Crossfeed', crossfeedAlgo,
                  isValueActive: crossfeedAlgo != 'OFF', context: context),
              _buildTelemetryRow('Reverb', reverbOn ? 'ON ($reverbEngineName)' : 'OFF',
                  isValueActive: reverbOn, context: context),
              _buildTelemetryRow('Sauti DSP', sautiDspOn ? 'ON' : 'OFF',
                  isValueActive: sautiDspOn, context: context),
              _buildTelemetryRow(
                'Limiter',
                limiterDisplay,
                isValueActive: limiterOn,
                context: context,
                trailing: InkWell(
                  onTap: () => _showLimiterSelectionSheet(
                      context, lookaheadOn, simpleLimiterOn,
                      isAntiClipActive: isAntiClipActive),
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: limiterOn
                          ? primary.withValues(alpha: isDark ? 0.15 : 0.12)
                          : (isDark
                              ? Colors.white.withValues(alpha: 0.08)
                              : Colors.black.withValues(alpha: 0.05)),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: limiterOn
                            ? primary.withValues(alpha: isDark ? 0.4 : 0.3)
                            : (isDark
                                ? Colors.white.withValues(alpha: 0.2)
                                : Colors.black.withValues(alpha: 0.12)),
                        width: 0.8,
                      ),
                    ),
                    child: Text(
                      limiterOn ? 'CONFIG' : 'ENABLE',
                      style: TextStyle(
                        fontFamily: 'monospace',
                        color: limiterOn ? primary : textMuted,
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),
              _buildTelemetryRow(
                'Anti-Clip Guard',
                isAntiClipActive
                    ? 'ACTIVE (-12 dB + Look-Ahead)'
                    : (clippedCount > 0 ? 'RECOMMENDED' : 'INACTIVE'),
                isValueActive: isAntiClipActive,
                isWarning: !isAntiClipActive && clippedCount > 0,
                context: context,
                trailing: !isAntiClipActive
                    ? InkWell(
                        onTap: () => _applyAntiClippingNormalizerAndLimiter(),
                        borderRadius: BorderRadius.circular(6),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: (isDark
                                    ? Colors.amberAccent
                                    : const Color(0xFFD97706))
                                .withValues(alpha: isDark ? 0.15 : 0.12),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: (isDark
                                      ? Colors.amberAccent
                                      : const Color(0xFFD97706))
                                  .withValues(alpha: 0.4),
                              width: 0.8,
                            ),
                          ),
                          child: Text(
                            'APPLY -12dB',
                            style: TextStyle(
                              fontFamily: 'monospace',
                              color: isDark
                                  ? Colors.amberAccent
                                  : const Color(0xFFD97706),
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      )
                    : null,
              ),
              _buildTelemetryRow(
                'Clipping',
                '$clippedCount samples',
                isWarning: clippedCount > 0,
                context: context,
                trailing: clippedCount > 0
                    ? InkWell(
                        onTap: () {
                          widget.player.resetClippedSamplesCount();
                          _fetchTelemetry();
                        },
                        borderRadius: BorderRadius.circular(6),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: (isDark
                                    ? Colors.redAccent
                                    : const Color(0xFFDC2626))
                                .withValues(alpha: isDark ? 0.18 : 0.12),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: (isDark
                                      ? Colors.redAccent
                                      : const Color(0xFFDC2626))
                                  .withValues(alpha: 0.5),
                              width: 0.8,
                            ),
                          ),
                          child: Text(
                            'RESET',
                            style: TextStyle(
                              fontFamily: 'monospace',
                              color: isDark
                                  ? Colors.redAccent
                                  : const Color(0xFFDC2626),
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      )
                    : null,
              ),
              _buildTelemetryRow(
                'Underruns',
                '$underrunCount',
                isValueActive: underrunCount > 0,
                isWarning: underrunCount > 0,
                context: context,
              ),
              const SizedBox(height: 12),
              Divider(
                color: isDark
                    ? textPrimary.withValues(alpha: 0.08)
                    : outlineColor,
                height: 1,
              ),
              const SizedBox(height: 8),
            ],
          ),
        );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 840) {
          return Padding(
            padding: const EdgeInsets.only(top: 16, bottom: 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: signalPathCard),
                const SizedBox(width: 16),
                Expanded(child: dspTelemetryCard),
              ],
            ),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 16),
            signalPathCard,
            const SizedBox(height: 16),
            dspTelemetryCard,
            const SizedBox(height: 16),
          ],
        );
      },
    );
  }

  Widget _buildTelemetryRow(
    String label,
    String value, {
    bool isValueActive = false,
    bool isWarning = false,
    Widget? trailing,
    required BuildContext context,
  }) {
    final appTheme = context.appTheme;
    final isDark = context.isDark;
    final primary = appTheme.primary;
    final textPrimary = context.textPrimary;
    final textMuted = context.textMuted;
    final warningColor =
        isDark ? Colors.redAccent : const Color(0xFFDC2626);

    Color valColor = textPrimary;
    if (isWarning) {
      valColor = warningColor;
    } else if (isValueActive) {
      valColor = primary;
    }

    final labelStyle = TextStyle(
      fontFamily: 'monospace',
      color: textMuted,
      fontSize: 12,
    );
    final valueStyle = TextStyle(
      fontFamily: 'monospace',
      color: valColor,
      fontWeight: isValueActive ? FontWeight.bold : FontWeight.normal,
      fontSize: 12,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final textScaler = MediaQuery.textScalerOf(context);
                final effectiveDirection =
                    Directionality.maybeOf(context) ?? TextDirection.ltr;
                final labelPainter = TextPainter(
                  text: TextSpan(text: label, style: labelStyle),
                  maxLines: 1,
                  textDirection: effectiveDirection,
                  textScaler: textScaler,
                )..layout(maxWidth: double.infinity);

                final double gap = constraints.maxWidth > 12.0 ? 12.0 : 0.0;
                final double usableWidth =
                    math.max(0.0, constraints.maxWidth - gap);
                // Reserve minimum space for value so trailing controls and long
                // labels cannot cause RenderFlex overflow on narrow mobile screens.
                final double minValueWidth = math.min(usableWidth * 0.4, 96.0);
                final double maxLabelWidth =
                    math.max(0.0, usableWidth - minValueWidth);
                final double resolvedLabelWidth =
                    math.min(labelPainter.width + 0.5, maxLabelWidth);

                return Row(
                  children: [
                    SizedBox(
                      width: resolvedLabelWidth,
                      child: AdaptiveMarqueeText(
                        text: label,
                        style: labelStyle,
                      ),
                    ),
                    SizedBox(width: gap),
                    Expanded(
                      child: Align(
                        alignment: AlignmentDirectional.centerEnd,
                        child: AdaptiveMarqueeText(
                          text: value,
                          textAlign: TextAlign.right,
                          style: valueStyle,
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 8),
            trailing,
          ],
        ],
      ),
    );
  }

  void _enableLookaheadLimiter() {
    widget.player.setLookaheadLimiterEnabled(true);
    widget.player.setLookaheadLimiterParams(ceilingDBTP: -1.0);
    AppStateService.instance
        .saveLookaheadLimiter(enabled: true, ceilingDBTP: -1.0);
    widget.player.resetClippedSamplesCount();
    _fetchTelemetry();
    if (mounted) {
      final appTheme = context.appTheme;
      final textPrimary = context.textPrimary;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Look-Ahead True-Peak Limiter (-1.0 dBTP) activated',
            style: TextStyle(color: textPrimary),
          ),
          duration: const Duration(seconds: 2),
          backgroundColor: appTheme.cardDark,
        ),
      );
    }
  }

  void _enableAntiClippingLimiter() {
    widget.player.setLimiterEnabled(true);
    widget.player
        .setLimiterParams(threshold: 0.95, attackMs: 2.0, releaseMs: 50.0);
    AppStateService.instance.saveLimiter(
        enabled: true, threshold: 0.95, attackMs: 2.0, releaseMs: 50.0);
    widget.player.resetClippedSamplesCount();
    _fetchTelemetry();
    if (mounted) {
      final appTheme = context.appTheme;
      final textPrimary = context.textPrimary;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Anti-Clipping Limiter (95% ceiling) activated',
            style: TextStyle(color: textPrimary),
          ),
          duration: const Duration(seconds: 2),
          backgroundColor: appTheme.cardDark,
        ),
      );
    }
  }

  void _applyAntiClippingNormalizerAndLimiter() {
    widget.player.setLoudnessNormalizerEnabled(true);
    widget.player.setLoudnessNormalizerTarget(-12.0);
    AppStateService.instance.saveLoudnessNormalizer(
      enabled: true,
      targetLUFS: -12.0,
    );

    widget.player.setLookaheadLimiterEnabled(true);
    widget.player.setLookaheadLimiterParams(ceilingDBTP: -1.0);
    AppStateService.instance.saveLookaheadLimiter(
      enabled: true,
      ceilingDBTP: -1.0,
    );

    widget.player.resetClippedSamplesCount();
    _fetchTelemetry();

    if (mounted) {
      final appTheme = context.appTheme;
      final textPrimary = context.textPrimary;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Anti-Clip Guard active: Normalizer @ -12 dB + Look-Ahead Limiter (-1.0 dBTP)',
            style: TextStyle(color: textPrimary),
          ),
          duration: const Duration(seconds: 2),
          backgroundColor: appTheme.cardDark,
        ),
      );
    }
  }

  void _toggleNormalizer(bool currentNormOn, double currentTarget) {
    final nextState = !currentNormOn;
    widget.player.setLoudnessNormalizerEnabled(nextState);
    final target =
        (currentTarget < -24.0 || currentTarget > -6.0) ? -12.0 : currentTarget;
    widget.player.setLoudnessNormalizerTarget(target);
    AppStateService.instance.saveLoudnessNormalizer(
      enabled: nextState,
      targetLUFS: target,
    );
    _fetchTelemetry();
    if (mounted) {
      final appTheme = context.appTheme;
      final textPrimary = context.textPrimary;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            nextState
                ? 'Loudness Normalizer enabled (${target.toStringAsFixed(1)} LUFS)'
                : 'Loudness Normalizer disabled',
            style: TextStyle(color: textPrimary),
          ),
          duration: const Duration(seconds: 2),
          backgroundColor: appTheme.cardDark,
        ),
      );
    }
  }

  void _disableLimiters() {
    widget.player.setLookaheadLimiterEnabled(false);
    widget.player.setLimiterEnabled(false);
    AppStateService.instance
        .saveLookaheadLimiter(enabled: false, ceilingDBTP: -1.0);
    AppStateService.instance.saveLimiter(
        enabled: false, threshold: 0.95, attackMs: 2.0, releaseMs: 50.0);
    _fetchTelemetry();
  }

  void _showLimiterSelectionSheet(
      BuildContext context, bool lookaheadOn, bool simpleLimiterOn,
      {bool isAntiClipActive = false}) {
    final appTheme = context.appTheme;
    final isDark = context.isDark;
    final primary = appTheme.primary;
    final textPrimary = context.textPrimary;
    final textMuted = context.textMuted;
    final outlineColor = context.outlineColor;
    final successColor =
        isDark ? const Color(0xFF4ADE80) : const Color(0xFF16A34A);
    final dangerColor =
        isDark ? Colors.redAccent : const Color(0xFFDC2626);

    showModalBottomSheet(
      context: context,
      backgroundColor: appTheme.cardDark,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: primary.withValues(alpha: isDark ? 0.15 : 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(Icons.shield_rounded,
                          color: primary, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'Limiter & Anti-Clipping Setup',
                      style: TextStyle(
                        color: textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                ListTile(
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(
                      color: isAntiClipActive
                          ? primary
                          : outlineColor,
                      width: isAntiClipActive ? 1.5 : 1.0,
                    ),
                  ),
                  tileColor: isAntiClipActive
                      ? primary.withValues(alpha: isDark ? 0.1 : 0.06)
                      : null,
                  leading: Icon(Icons.security_rounded,
                      color: primary),
                  title: Text('Anti-Clip Guard (-12 dB + Look-Ahead)',
                      style: TextStyle(
                          color: textPrimary, fontWeight: FontWeight.bold)),
                  subtitle: Text(
                      'Normalizer @ -12 dB LUFS + Look-Ahead Limiter (-1.0 dBTP). Provides 12 dB headroom and catches inter-sample peaks.',
                      style: TextStyle(color: textMuted, fontSize: 12)),
                  trailing: isAntiClipActive
                      ? Icon(Icons.check_circle_rounded,
                          color: primary)
                      : null,
                  onTap: () {
                    Navigator.pop(ctx);
                    _applyAntiClippingNormalizerAndLimiter();
                  },
                ),
                const SizedBox(height: 10),
                ListTile(
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(
                      color: lookaheadOn
                          ? primary
                          : outlineColor,
                    ),
                  ),
                  leading:
                      Icon(Icons.speed_rounded, color: primary),
                  title: Text('Look-Ahead True-Peak Limiter',
                      style: TextStyle(
                          color: textPrimary, fontWeight: FontWeight.bold)),
                  subtitle: Text(
                      'True-peak brickwall limiting at -1.0 dBTP. Eliminates inter-sample clipping.',
                      style: TextStyle(color: textMuted, fontSize: 12)),
                  trailing: lookaheadOn
                      ? Icon(Icons.check_circle_rounded,
                          color: primary)
                      : null,
                  onTap: () {
                    Navigator.pop(ctx);
                    _enableLookaheadLimiter();
                  },
                ),
                const SizedBox(height: 10),
                ListTile(
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(
                      color: simpleLimiterOn
                          ? successColor
                          : outlineColor,
                    ),
                  ),
                  leading: Icon(Icons.compress_rounded,
                      color: successColor),
                  title: Text('Anti-Clipping Limiter',
                      style: TextStyle(
                          color: textPrimary, fontWeight: FontWeight.bold)),
                  subtitle: Text(
                      'Fast dynamic peak suppression at 95% threshold (2ms attack / 50ms release).',
                      style: TextStyle(color: textMuted, fontSize: 12)),
                  trailing: simpleLimiterOn
                      ? Icon(Icons.check_circle_rounded,
                          color: successColor)
                      : null,
                  onTap: () {
                    Navigator.pop(ctx);
                    _enableAntiClippingLimiter();
                  },
                ),
                if (lookaheadOn || simpleLimiterOn) ...[
                  const SizedBox(height: 10),
                  ListTile(
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(
                        color: dangerColor.withValues(alpha: isDark ? 0.3 : 0.2),
                      ),
                    ),
                    leading: Icon(Icons.power_settings_new_rounded,
                        color: dangerColor),
                    title: Text('Disable All Limiters',
                        style: TextStyle(color: dangerColor)),
                    subtitle: Text(
                        'Unprotected output. High volumes or EQ boosts can cause digital clipping.',
                        style: TextStyle(
                            color: textMuted.withValues(alpha: 0.8),
                            fontSize: 12)),
                    onTap: () {
                      Navigator.pop(ctx);
                      _disableLimiters();
                    },
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}
