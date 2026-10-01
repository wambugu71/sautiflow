import 'dart:async';
import 'package:flutter/material.dart';
import 'package:material_3_expressive/components/progress_indicators/m3e_progress_indicators.dart';
import 'package:sautiflow/sautiflow.dart';
import 'package:sautiplay/isolate_player.dart';
import 'package:sautiplay/services/app_state_service.dart';
import 'package:sautiplay/services/audio_hardware_inspector.dart';

/// Shows the Developer & Audiophile Audio Engine Diagnostic Panel as a glassmorphic bottom sheet.
void showAudioEngineDiagnosticPanel(
    BuildContext context, IsolateAudioPlayer player,
    {String? filePath}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.65),
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
  AudioHardwareSpecs? _hardwareSpecs;
  Map<String, dynamic>? _telemetry;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
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

    return Container(
      constraints: BoxConstraints(
        maxHeight: mediaQuery.size.height * 0.90,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFF0F121A).withValues(alpha: 0.96),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        border: Border.all(color: const Color(0xFF2A324B), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.cyanAccent.withValues(alpha: 0.12),
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
                color: Colors.white24,
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
                      const Text(
                        'Audio Info & Diagnostics',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          letterSpacing: 1.1,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        width: 7,
                        height: 7,
                        decoration: const BoxDecoration(
                          color: Colors.greenAccent,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Text(
                        'LIVE',
                        style: TextStyle(
                          fontFamily: 'monospace',
                          color: Colors.greenAccent,
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
                    color: const Color(0xFF222B40),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Center(
                    child: IconButton(
                      padding: EdgeInsets.zero,
                      icon: const Icon(Icons.close_rounded,
                          color: Colors.white70, size: 20),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ),
                )
              ],
            ),
          ),

          const Divider(color: Color(0xFF222B40), height: 1),

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
                            style: const TextStyle(color: Colors.redAccent),
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

    final String activeDeviceName = specs.isBluetooth
        ? (specs.bluetoothDeviceName?.isNotEmpty == true
            ? specs.bluetoothDeviceName!
            : specs.deviceName)
        : specs.deviceName;

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
    final int dspRate = t['processingSampleRate'] as int? ?? 48000;
    final int dspChannels = t['processingChannels'] as int? ?? 2;
    final int dacRate = t['outputSampleRate'] as int? ??
        (hw['sampleRate'] as int? ?? specs.sampleRate);
    final int dacDepth = hw['bitDepth'] as int? ?? specs.bitDepth;
    final bool isExclusive =
        hw['isExclusiveMode'] as bool? ?? specs.isExclusiveMode;
    final String backend = hw['backendName'] as String? ?? specs.backendName;
    final int periodFrames =
        hw['periodSizeFrames'] as int? ?? specs.periodSizeFrames;
    final int periodCount = hw['periodCount'] as int? ?? specs.periodCount;

    final bool eqOn = t['eqEnabled'] == true;
    final bool reverbOn = t['reverbEnabled'] == true;
    final double crossfeedMix = (t['crossfeedMix'] as num?)?.toDouble() ?? 0.0;
    final String crossfeedAlgo =
        _formatCrossfeedAlgo(t['crossfeedAlgo']?.toString(), crossfeedMix);
    final bool sautiDspOn = t['sautiDspEnabled'] == true;
    final bool lookaheadOn = t['lookaheadLimiterEnabled'] == true;
    final bool simpleLimiterOn = t['simpleLimiterEnabled'] == true ||
        (t['limiterEnabled'] == true && !lookaheadOn);
    final bool limiterOn = lookaheadOn || simpleLimiterOn;
    String limiterDisplay = 'OFF';
    if (lookaheadOn && simpleLimiterOn) {
      limiterDisplay = 'ON (Dual Limiter)';
    } else if (lookaheadOn) {
      limiterDisplay = 'ON (Look-Ahead)';
    } else if (simpleLimiterOn) {
      limiterDisplay = 'ON (Anti-Clipping)';
    }

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

    final bool stereoWidenOn = t['stereoWidenEnabled'] == true;
    final bool stereoEnhanceOn = t['stereoEnhancementEnabled'] == true;

    // Calculate node latencies across 7-Zone Studio Architecture
    final nodeLatencies = _calculatePerNodeLatencies(
      sampleRate: dspRate,
      hwLatencyMs:
          (t['deviceLatencyMs'] as num?)?.toDouble() ?? specs.latencyMs,
      crossfeedAlgo: crossfeedAlgo,
      crossfeedDelayMs: (t['crossfeedDelayMs'] as num?)?.toDouble() ?? 0.40,
      limiterOn: limiterOn,
      stereoWidenOn: stereoWidenOn,
      stereoEnhanceOn: stereoEnhanceOn,
      reverbOn: reverbOn,
      sautiDspOn: sautiDspOn,
      eqOn: eqOn,
      isSrcActive: (srcRate != dacRate),
      resampleLatencyMs: (t['resampleLatencyMs'] as num?)?.toDouble(),
      deviceType: specs.deviceType,
    );

    // Sum DSP node latencies
    double sumDspMs = 0.0;
    double sumDspSamples = 0.0;
    for (final n in nodeLatencies) {
      if (n.nodeName != 'Source / Decoder' && !n.isHardware) {
        sumDspMs += n.latencyMs;
        sumDspSamples += n.latencySamples;
      }
    }

    final double hwLatencyMs =
        (t['deviceLatencyMs'] as num?)?.toDouble() ?? specs.latencyMs;
    final double totalEndToEndLatencyMs = hwLatencyMs + sumDspMs;
    final int clippedCount = t['clippedCount'] as int? ?? 0;
    final int underrunCount = t['underrunCount'] as int? ?? 0;
    final double truePeakDBTP =
        (t['truePeakDBTP'] as num?)?.toDouble() ?? -100.0;

    final bool isSrcActive = (srcRate != dacRate);
    final String resamplerAlgo =
        _formatResamplerAlgo(t['resampleAlgorithm']?.toString());

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 1. Hardware Output Device Card (Speakers, Built-in Earpiece, 3.5mm, BT, USB DAC, etc.)
        //  _buildHardwareDeviceCard(specs, activeDeviceName),

        const SizedBox(height: 16),

        // 2. Per-Node Latency Breakdown Card (Source -> DAC)
        _buildPerNodeLatencyCard(
            nodeLatencies, totalEndToEndLatencyMs, sumDspSamples),

        const SizedBox(height: 16),

        // 3. Terminal Matrix Display Box (DSP & Telemetry Details)
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF080A10),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFF1E2638)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'DSP Status',
                    style: TextStyle(
                      fontFamily: 'monospace',
                      color: Colors.white70,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.5,
                    ),
                  ),
                  /*  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: isSrcActive
                          ? Colors.amber.withValues(alpha: 0.2)
                          : Colors.greenAccent.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      isSrcActive ? 'SRC ACTIVE' : 'BIT-PERFECT',
                      style: TextStyle(
                        fontFamily: 'monospace',
                        color: isSrcActive
                            ? Colors.amberAccent
                            : Colors.greenAccent,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ), */
                ],
              ),
              const SizedBox(height: 12),
              const Divider(color: Color(0xFF1B2336), height: 1),
              const SizedBox(height: 12),
              _buildTelemetryRow('Device', activeDeviceName,
                  isValueActive: true),
              _buildTelemetryRow('Device Type', specs.deviceType,
                  isValueActive: true),
              if (specs.bluetoothCodec != null)
                _buildTelemetryRow(
                  'BT Codec',
                  specs.formattedBtCodec ?? specs.bluetoothCodec!,
                  isValueActive: true,
                ),
              _buildTelemetryRow('File Format', fileType, isValueActive: true),
              _buildTelemetryRow('Bitrate', bitrateDisplay,
                  isValueActive: bitrateKbps > 0),
              if (fileSizeBytes > 0)
                _buildTelemetryRow('File Size',
                    '${(fileSizeBytes / (1024 * 1024)).toStringAsFixed(2)} MB',
                    isValueActive: true),
              _buildTelemetryRow('ReplayGain', replayGainDisplay,
                  isValueActive: hasReplayGain),
              _buildTelemetryRow('Source',
                  '${(srcRate / 1000.0).toStringAsFixed(1)} kHz / $srcDepth-bit PCM'),
              _buildTelemetryRow('Decoder',
                  '${(srcRate / 1000.0).toStringAsFixed(1)} kHz PCM'),
              _buildTelemetryRow('DSP',
                  '${(dspRate / 1000.0).toStringAsFixed(1)} kHz Float32 ($dspChannels ch)'),
              _buildTelemetryRow('Output',
                  '${(dacRate / 1000.0).toStringAsFixed(1)} kHz / $dacDepth-bit (${specs.deviceType})'),
              if (specs.socName != null && specs.socName!.isNotEmpty)
                _buildTelemetryRow('SoC Processor', specs.socName!,
                    isValueActive: true),
              if (specs.dspHardware != null && specs.dspHardware!.isNotEmpty)
                _buildTelemetryRow('DSP Hardware', specs.dspHardware!,
                    isValueActive: true),
              _buildTelemetryRow('Backend',
                  '$backend (${specs.isDirectPcm ? "Hi-Res Bit-Perfect" : (isExclusive ? "Exclusive" : "Shared")})'),
              _buildTelemetryRow(
                  'Buffer',
                  periodCount > 1
                      ? '$periodFrames frames × $periodCount periods (${periodFrames * periodCount} total)'
                      : '$periodFrames frames'),
              _buildTelemetryRow('Total Latency',
                  '${totalEndToEndLatencyMs.toStringAsFixed(2)} ms (DSP: ${sumDspMs.toStringAsFixed(2)} ms + Hardware: ${hwLatencyMs.toStringAsFixed(2)} ms)'),
              _buildTelemetryRow(
                  'SRC',
                  isSrcActive
                      ? 'ON (${(srcRate / 1000.0).toStringAsFixed(1)} → ${(dacRate / 1000.0).toStringAsFixed(1)} kHz)'
                      : 'OFF'),
              _buildTelemetryRow('Resampler', resamplerAlgo),
              _buildTelemetryRow(
                  'True-Peak', '${truePeakDBTP.toStringAsFixed(1)} dBTP',
                  isValueActive: truePeakDBTP > -90.0,
                  isWarning: truePeakDBTP > -0.5),
              _buildTelemetryRow('Loudness (LUFS)',
                  'Mom: ${((t['momentaryLUFS'] as num?)?.toDouble() ?? -100.0).toStringAsFixed(1)} / Int: ${((t['integratedLUFS'] as num?)?.toDouble() ?? -100.0).toStringAsFixed(1)}'),
              _buildTelemetryRow(
                'Normalizer',
                normDisplay,
                isValueActive: normOn,
                trailing: InkWell(
                  onTap: () => _toggleNormalizer(normOn, normTarget),
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: normOn
                          ? Colors.cyanAccent.withValues(alpha: 0.15)
                          : Colors.white.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: normOn
                            ? Colors.cyanAccent.withValues(alpha: 0.4)
                            : Colors.white.withValues(alpha: 0.2),
                        width: 0.8,
                      ),
                    ),
                    child: Text(
                      normOn ? 'TOGGLE' : 'ENABLE',
                      style: TextStyle(
                        fontFamily: 'monospace',
                        color: normOn ? Colors.cyanAccent : Colors.white70,
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
                          -0.1),
              _buildTelemetryRow('EQ', eqOn ? 'ON' : 'OFF',
                  isValueActive: eqOn),
              _buildTelemetryRow('Crossfeed', crossfeedAlgo,
                  isValueActive: crossfeedAlgo != 'OFF'),
              _buildTelemetryRow('Reverb', reverbOn ? 'ON' : 'OFF',
                  isValueActive: reverbOn),
              _buildTelemetryRow('Sauti DSP', sautiDspOn ? 'ON' : 'OFF',
                  isValueActive: sautiDspOn),
              _buildTelemetryRow(
                'Limiter',
                limiterDisplay,
                isValueActive: limiterOn,
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
                          ? Colors.cyanAccent.withValues(alpha: 0.15)
                          : Colors.white.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: limiterOn
                            ? Colors.cyanAccent.withValues(alpha: 0.4)
                            : Colors.white.withValues(alpha: 0.2),
                        width: 0.8,
                      ),
                    ),
                    child: Text(
                      limiterOn ? 'CONFIG' : 'ENABLE',
                      style: TextStyle(
                        fontFamily: 'monospace',
                        color: limiterOn ? Colors.cyanAccent : Colors.white70,
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
                trailing: !isAntiClipActive
                    ? InkWell(
                        onTap: () => _applyAntiClippingNormalizerAndLimiter(),
                        borderRadius: BorderRadius.circular(6),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.amberAccent.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: Colors.amberAccent.withValues(alpha: 0.4),
                              width: 0.8,
                            ),
                          ),
                          child: const Text(
                            'APPLY -12dB',
                            style: TextStyle(
                              fontFamily: 'monospace',
                              color: Colors.amberAccent,
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
                            color: Colors.redAccent.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: Colors.redAccent.withValues(alpha: 0.5),
                              width: 0.8,
                            ),
                          ),
                          child: const Text(
                            'RESET',
                            style: TextStyle(
                              fontFamily: 'monospace',
                              color: Colors.redAccent,
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
              ),
              const SizedBox(height: 12),
              const Divider(color: Color(0xFF1B2336), height: 1),
              const SizedBox(height: 8),
            ],
          ),
        ),

        const SizedBox(height: 16),
      ],
    );
  }

  /// Builds a dedicated, sleek hardware output device card
  /* Widget _buildHardwareDeviceCard(
      AudioHardwareSpecs specs, String activeDeviceName) {
    final deviceIcon = _getDeviceIcon(specs.deviceType);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF0C101A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF1E2840)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header Row with Icon, Device Name, and Live badge
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.cyanAccent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  deviceIcon,
                  color: Colors.cyanAccent,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Text(
                          'HARDWARE OUTPUT',
                          style: TextStyle(
                            fontFamily: 'monospace',
                            color: Colors.cyanAccent,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.2,
                          ),
                        ),
                        /* if (specs.isHiResAudio) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.amber.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: Colors.amber.withValues(alpha: 0.4),
                                width: 0.8,
                              ),
                            ),
                            child: const Text(
                              'HI-RES',
                              style: TextStyle(
                                fontFamily: 'monospace',
                                color: Colors.amberAccent,
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],*/
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      activeDeviceName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.greenAccent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: Colors.greenAccent.withValues(alpha: 0.3),
                    width: 0.8,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                        color: Colors.greenAccent,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 5),
                    const Text(
                      'ACTIVE',
                      style: TextStyle(
                        fontFamily: 'monospace',
                        color: Colors.greenAccent,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(color: Color(0xFF1A2234), height: 1),
          const SizedBox(height: 12),

          // Wrap of specs badges
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildMiniSpecBadge(
                icon: Icons.alt_route_rounded,
                label: 'Route',
                value: specs.deviceType,
                highlight: true,
              ),
              _buildMiniSpecBadge(
                icon: Icons.developer_board_rounded,
                label: 'Backend',
                value: specs.backendName,
              ),
              _buildMiniSpecBadge(
                icon: Icons.speed_rounded,
                label: 'Format',
                value:
                    '${specs.formattedSampleRate} / ${specs.formattedBitDepth}',
                highlight: specs.isHiResAudio,
              ),
              _buildMiniSpecBadge(
                icon: (specs.isDirectPcm || specs.isExclusiveMode)
                    ? Icons.lock_outline_rounded
                    : Icons.lock_open_rounded,
                label: 'Mode',
                value: specs.isDirectPcm
                    ? 'Direct Hi-Res'
                    : (specs.isExclusiveMode ? 'Bit-Perfect' : 'Shared Mixer'),
                highlight: specs.isDirectPcm || specs.isExclusiveMode,
              ),
              if (specs.dspHardware != null && specs.dspHardware!.isNotEmpty)
                _buildMiniSpecBadge(
                  icon: Icons.memory_rounded,
                  label: 'DSP',
                  value: specs.dspHardware!,
                  highlight: true,
                ),
              if (specs.bluetoothCodec != null)
                _buildMiniSpecBadge(
                  icon: Icons.bluetooth_audio_rounded,
                  label: 'BT Codec',
                  value: specs.formattedBtCodec ?? specs.bluetoothCodec!,
                  highlight: specs.bluetoothCodec == 'LDAC' ||
                      specs.bluetoothCodec == 'aptX HD' ||
                      specs.bluetoothCodec == 'LC3',
                ),
              _buildMiniSpecBadge(
                icon: Icons.timer_outlined,
                label: 'HW Latency',
                value: specs.formattedLatency,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMiniSpecBadge({
    required IconData icon,
    required String label,
    required String value,
    bool highlight = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: highlight
            ? Colors.cyanAccent.withValues(alpha: 0.1)
            : const Color(0xFF141A29),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: highlight
              ? Colors.cyanAccent.withValues(alpha: 0.4)
              : const Color(0xFF232D42),
          width: 0.8,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 13,
            color: highlight ? Colors.cyanAccent : Colors.white60,
          ),
          const SizedBox(width: 6),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label.toUpperCase(),
                style: TextStyle(
                  fontFamily: 'monospace',
                  color: highlight
                      ? Colors.cyanAccent.withValues(alpha: 0.8)
                      : Colors.white38,
                  fontSize: 8,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                value,
                style: TextStyle(
                  fontFamily: 'monospace',
                  color: highlight ? Colors.white : Colors.white70,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  IconData _getDeviceIcon(String type) {
    final lower = type.toLowerCase();
    if (lower.contains('earpiece')) {
      return Icons.phone_in_talk_rounded;
    } else if (lower.contains('usb') || lower.contains('dac')) {
      return Icons.usb_rounded;
    } else if (lower.contains('3.5mm') ||
        lower.contains('headphone') ||
        lower.contains('headset') ||
        lower.contains('jack')) {
      return Icons.headphones_rounded;
    } else if (lower.contains('bluetooth') ||
        lower.contains('wireless') ||
        lower.contains('buds') ||
        lower.contains('airpods')) {
      return Icons.bluetooth_audio_rounded;
    } else if (lower.contains('hdmi') || lower.contains('tv')) {
      return Icons.tv_rounded;
    } else if (lower.contains('line') || lower.contains('aux')) {
      return Icons.settings_input_component_rounded;
    }
    return Icons.speaker_rounded;
  }
*/

  Widget _buildPerNodeLatencyCard(
      List<_NodeLatencyInfo> nodes, double totalMs, double dspSamples) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF0C101A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF1E2840)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Text(
                    'Chain Latency',
                    style: TextStyle(
                      fontFamily: 'monospace',
                      color: Colors.white70,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                    ),
                  ),
                ],
              ),
              Text(
                '${totalMs.toStringAsFixed(2)} ms',
                style: const TextStyle(
                  fontFamily: 'monospace',
                  color: Colors.greenAccent,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Divider(color: Color(0xFF1A2234), height: 1),
          const SizedBox(height: 10),
          ...nodes.map((node) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Text(
                          node.stepNumber,
                          style: TextStyle(
                            fontFamily: 'monospace',
                            color: Colors.white.withValues(alpha: 0.4),
                            fontSize: 11,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          node.nodeName,
                          style: TextStyle(
                            fontFamily: 'monospace',
                            color: node.latencyMs > 0
                                ? Colors.white
                                : Colors.white54,
                            fontSize: 11,
                            fontWeight: node.latencyMs > 0
                                ? FontWeight.bold
                                : FontWeight.normal,
                          ),
                        ),
                      ],
                    ),
                    Text(
                      node.latencyMs > 0
                          ? '${node.latencyMs.toStringAsFixed(2)} ms'
                          : '0.00 ms',
                      style: TextStyle(
                        fontFamily: 'monospace',
                        color: node.latencyMs > 0
                            ? Colors.amberAccent
                            : Colors.white38,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }

  Widget _buildTelemetryRow(
    String label,
    String value, {
    bool isValueActive = false,
    bool isWarning = false,
    Widget? trailing,
  }) {
    Color valColor = Colors.white;
    if (isWarning) {
      valColor = Colors.redAccent;
    } else if (isValueActive) {
      valColor = Colors.cyanAccent;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontFamily: 'monospace',
              color: Colors.white.withValues(alpha: 0.5),
              fontSize: 12,
            ),
          ),
          Flexible(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    value,
                    textAlign: TextAlign.right,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      color: valColor,
                      fontWeight:
                          isValueActive ? FontWeight.bold : FontWeight.normal,
                      fontSize: 12,
                    ),
                  ),
                ),
                if (trailing != null) ...[
                  const SizedBox(width: 8),
                  trailing,
                ],
              ],
            ),
          ),
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Look-Ahead True-Peak Limiter (-1.0 dBTP) activated'),
          duration: Duration(seconds: 2),
          backgroundColor: Color(0xFF1E2840),
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Anti-Clipping Limiter (95% ceiling) activated'),
          duration: Duration(seconds: 2),
          backgroundColor: Color(0xFF1E2840),
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Anti-Clip Guard active: Normalizer @ -12 dB + Look-Ahead Limiter (-1.0 dBTP)',
          ),
          duration: Duration(seconds: 2),
          backgroundColor: Color(0xFF1E2840),
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            nextState
                ? 'Loudness Normalizer enabled (${target.toStringAsFixed(1)} LUFS)'
                : 'Loudness Normalizer disabled',
          ),
          duration: const Duration(seconds: 2),
          backgroundColor: const Color(0xFF1E2840),
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
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0F121A),
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
                        color: Colors.cyanAccent.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.shield_rounded,
                          color: Colors.cyanAccent, size: 20),
                    ),
                    const SizedBox(width: 12),
                    const Text(
                      'Limiter & Anti-Clipping Setup',
                      style: TextStyle(
                        color: Colors.white,
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
                          ? Colors.cyanAccent
                          : const Color(0xFF1E2840),
                      width: isAntiClipActive ? 1.5 : 1.0,
                    ),
                  ),
                  tileColor: isAntiClipActive
                      ? Colors.cyanAccent.withValues(alpha: 0.08)
                      : null,
                  leading: const Icon(Icons.security_rounded,
                      color: Colors.cyanAccent),
                  title: const Text('Anti-Clip Guard (-12 dB + Look-Ahead)',
                      style: TextStyle(
                          color: Colors.white, fontWeight: FontWeight.bold)),
                  subtitle: const Text(
                      'Normalizer @ -12 dB LUFS + Look-Ahead Limiter (-1.0 dBTP). Provides 12 dB headroom and catches inter-sample peaks.',
                      style: TextStyle(color: Colors.white70, fontSize: 12)),
                  trailing: isAntiClipActive
                      ? const Icon(Icons.check_circle_rounded,
                          color: Colors.cyanAccent)
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
                          ? Colors.cyanAccent
                          : const Color(0xFF1E2840),
                    ),
                  ),
                  leading:
                      const Icon(Icons.speed_rounded, color: Colors.cyanAccent),
                  title: const Text('Look-Ahead True-Peak Limiter',
                      style: TextStyle(
                          color: Colors.white, fontWeight: FontWeight.bold)),
                  subtitle: const Text(
                      'True-peak brickwall limiting at -1.0 dBTP. Eliminates inter-sample clipping.',
                      style: TextStyle(color: Colors.white60, fontSize: 12)),
                  trailing: lookaheadOn
                      ? const Icon(Icons.check_circle_rounded,
                          color: Colors.cyanAccent)
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
                          ? Colors.greenAccent
                          : const Color(0xFF1E2840),
                    ),
                  ),
                  leading: const Icon(Icons.compress_rounded,
                      color: Colors.greenAccent),
                  title: const Text('Anti-Clipping Limiter',
                      style: TextStyle(
                          color: Colors.white, fontWeight: FontWeight.bold)),
                  subtitle: const Text(
                      'Fast dynamic peak suppression at 95% threshold (2ms attack / 50ms release).',
                      style: TextStyle(color: Colors.white60, fontSize: 12)),
                  trailing: simpleLimiterOn
                      ? const Icon(Icons.check_circle_rounded,
                          color: Colors.greenAccent)
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
                      side: const BorderSide(color: Color(0xFF2A1515)),
                    ),
                    leading: const Icon(Icons.power_settings_new_rounded,
                        color: Colors.redAccent),
                    title: const Text('Disable All Limiters',
                        style: TextStyle(color: Colors.redAccent)),
                    subtitle: const Text(
                        'Unprotected output. High volumes or EQ boosts can cause digital clipping.',
                        style: TextStyle(color: Colors.white38, fontSize: 12)),
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

  List<_NodeLatencyInfo> _calculatePerNodeLatencies({
    required int sampleRate,
    required double hwLatencyMs,
    required String crossfeedAlgo,
    required double crossfeedDelayMs,
    required bool limiterOn,
    required bool stereoWidenOn,
    required bool stereoEnhanceOn,
    required bool reverbOn,
    required bool sautiDspOn,
    required bool eqOn,
    required bool isSrcActive,
    double? resampleLatencyMs,
    String? deviceType,
  }) {
    final list = <_NodeLatencyInfo>[];
    int step = 1;

    // 1. Source / Decoder
    list.add(_NodeLatencyInfo('${step++}.', 'Source / Decoder', 0.0, 0.0));

    // Zone 1: Restorative Filtering (Subsonic HPF, Studio Noise Gate, Downward Expander)
    list.add(_NodeLatencyInfo(
      '${step++}.',
      'Restoration',
      0.0,
      0.0,
      zoneBadge: 'Z1',
    ));

    // Zone 2: Corrective Tone & Sibilance (Dynamic EQ, De-Esser)
    list.add(_NodeLatencyInfo(
      '${step++}.',
      'Tone & De-Esser',
      0.0,
      0.0,
      zoneBadge: 'Z2',
    ));

    // Zone 3: Harmonics & Character (Analog Warmth, Tape Drift, Bass Exciter, Clarity)
    list.add(_NodeLatencyInfo(
      '${step++}.',
      'Harmonics & Character',
      0.0,
      0.0,
      zoneBadge: 'Z3',
    ));

    // Zone 4: Macro Dynamics & Master EQ (Compressor, Parametric/Graphic EQ)
    list.add(_NodeLatencyInfo(
      '${step++}.',
      'Dynamics & Master EQ',
      0.0,
      0.0,
      zoneBadge: 'Z4',
    ));

    // Zone 5: Spatialization & Acoustics
    if (crossfeedAlgo != 'OFF') {
      final double delayMs = crossfeedDelayMs > 0 ? crossfeedDelayMs : 0.40;
      final double samples = delayMs * 0.001 * sampleRate;
      list.add(_NodeLatencyInfo(
        '${step++}.',
        'Crossfeed ($crossfeedAlgo)',
        delayMs,
        samples,
        zoneBadge: 'Z5',
      ));
    }
    if (stereoWidenOn) {
      const double delayMs = 15.0;
      final double samples = delayMs * 0.001 * sampleRate;
      list.add(_NodeLatencyInfo(
        '${step++}.',
        'Stereo Widen',
        delayMs,
        samples,
        zoneBadge: 'Z5',
      ));
    }
    if (stereoEnhanceOn) {
      const double delayMs = 1.20;
      final double samples = delayMs * 0.001 * sampleRate;
      list.add(_NodeLatencyInfo(
        '${step++}.',
        'Stereo Enhancement',
        delayMs,
        samples,
        zoneBadge: 'Z5',
      ));
    }
    if (reverbOn) {
      list.add(_NodeLatencyInfo(
        '${step++}.',
        'Dattorro Reverb Tank',
        0.0,
        0.0,
        zoneBadge: 'Z5',
      ));
    }
    if (crossfeedAlgo == 'OFF' &&
        !stereoWidenOn &&
        !stereoEnhanceOn &&
        !reverbOn) {
      list.add(_NodeLatencyInfo(
        '${step++}.',
        'Spatial & Acoustic Space',
        0.0,
        0.0,
        zoneBadge: 'Z5',
      ));
    }

    // Zone 6: Transducer Calibration & Delivery Stage (AutoEQ FIR Convolver, Leveller AGC, Metering)
    if (sautiDspOn) {
      const double dspMs = 0.50; // Low-latency partitioned convolution
      final double samples = dspMs * 0.001 * sampleRate;
      list.add(_NodeLatencyInfo(
        '${step++}.',
        'AutoEQ FIR & Leveller',
        dspMs,
        samples,
        zoneBadge: 'Z6',
      ));
    } else {
      list.add(_NodeLatencyInfo(
        '${step++}.',
        'Transducer & Delivery',
        0.0,
        0.0,
        zoneBadge: 'Z6',
      ));
    }

    // Zone 7: Mastering Peak Limiter & Output Stage (Master Brickwall Limiter)
    if (limiterOn) {
      const double attackMs = 2.0; // 2 ms Lookahead window
      final double samples = attackMs * 0.001 * sampleRate;
      list.add(_NodeLatencyInfo(
        '${step++}.',
        'Master Lookahead Limiter',
        attackMs,
        samples,
        zoneBadge: 'Z7',
      ));
    } else {
      list.add(_NodeLatencyInfo(
        '${step++}.',
        'Master Output Limiter',
        0.0,
        0.0,
        zoneBadge: 'Z7',
      ));
    }

    // Resampler Node
    if (isSrcActive) {
      final double resampleMs =
          (resampleLatencyMs != null && resampleLatencyMs > 0.0)
              ? resampleLatencyMs
              : 0.50;
      final double samples = resampleMs * 0.001 * sampleRate;
      list.add(_NodeLatencyInfo(
        '${step++}.',
        'SRC Resampler',
        resampleMs,
        samples,
      ));
    }

    // Hardware Output DAC
    final double hwSamples = hwLatencyMs * 0.001 * sampleRate;
    final hwLabel = deviceType != null && deviceType.isNotEmpty
        ? 'HW Output ($deviceType)'
        : 'HW Output DAC';
    list.add(_NodeLatencyInfo(
      '${step++}.',
      hwLabel,
      hwLatencyMs,
      hwSamples,
      isHardware: true,
    ));

    return list;
  }

  String _formatResamplerAlgo(String? algo) {
    if (algo == null) return 'Miniaudio Linear';
    switch (algo) {
      case 'miniaudioLinear':
        return 'Miniaudio Linear';
      case 'srcSincBestQuality':
        return 'SRC Sinc Best Quality';
      case 'srcSincMediumQuality':
        return 'SRC Sinc Medium Quality';
      case 'srcSincFastest':
        return 'SRC Sinc Fastest';
      case 'soxrVHQLinearPhase':
      case 'soxrHQ':
      case 'soxrFast':
        return 'r8brain Linear Phase (Legacy SoX)';
      case 'soxrVHQMinimumPhase':
        return 'r8brain Minimum Phase (Legacy SoX)';
      case 'r8brain24LinearPhase':
        return 'r8brain Linear Phase';
      case 'r8brain24MinimumPhase':
        return 'r8brain Minimum Phase';
      default:
        return algo;
    }
  }

  String _formatCrossfeedAlgo(String? algo, double mix) {
    if (algo == null || algo == 'off' || algo == 'OFF' || mix <= 0.0001) {
      return 'OFF';
    }
    switch (algo.toLowerCase()) {
      case 'simple':
        return 'Simple ITD';
      case 'bs2b':
        return 'BS2B Chu Moy';
      case 'meier':
        return 'Jan Meier';
      case 'natural':
        return 'Natural Crossfeed';
      case 'race':
        return 'Ambiophonics RACE';
      case 'openstage':
        return 'OpenStage Acoustic';
      default:
        return algo.toUpperCase();
    }
  }
}

class _NodeLatencyInfo {
  final String stepNumber;
  final String nodeName;
  final double latencyMs;
  final double latencySamples;
  final bool isHardware;
  final String? zoneBadge;

  _NodeLatencyInfo(
    this.stepNumber,
    this.nodeName,
    this.latencyMs,
    this.latencySamples, {
    this.isHardware = false,
    this.zoneBadge,
  });
}
