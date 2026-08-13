import 'dart:async';
import 'package:flutter/material.dart';
import 'package:sautiplay/isolate_player.dart';

/// Shows the Developer & Audiophile Audio Engine Diagnostic Panel as a glassmorphic bottom sheet.
void showAudioEngineDiagnosticPanel(
    BuildContext context, IsolateAudioPlayer player) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.65),
    builder: (ctx) => AudioEngineDiagnosticPanel(player: player),
  );
}

class AudioEngineDiagnosticPanel extends StatefulWidget {
  final IsolateAudioPlayer player;

  const AudioEngineDiagnosticPanel({
    super.key,
    required this.player,
  });

  @override
  State<AudioEngineDiagnosticPanel> createState() =>
      _AudioEngineDiagnosticPanelState();
}

class _AudioEngineDiagnosticPanelState
    extends State<AudioEngineDiagnosticPanel> {
  Timer? _telemetryTimer;
  Map<String, dynamic>? _telemetry;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchTelemetry();
    _telemetryTimer = Timer.periodic(const Duration(milliseconds: 250), (_) {
      _fetchTelemetry();
    });
  }

  @override
  void dispose() {
    _telemetryTimer?.cancel();
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
                /* Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.cyanAccent.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.graphic_eq_rounded,
                    color: Colors.cyanAccent,
                    size: 22,
                  ),
                ),*/
                const SizedBox(width: 12),
                Expanded(
                  child: Row(
                    //crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Audio Info',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          letterSpacing: 1.2,
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
                    ],
                  ),
                ),
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: const Color(0xFF222B40),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Center(
                    child: IconButton(
                      icon: const Icon(Icons.close_rounded,
                          color: Colors.white70),
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
                      child: Center(
                        child:
                            CircularProgressIndicator(color: Colors.cyanAccent),
                      ),
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
    final hw = t['hardware'] as Map<String, dynamic>? ?? {};

    final int srcRate = t['inputSampleRate'] as int? ?? 48000;
    final int srcDepth =
        t['inputBitDepth'] as int? ?? ((hw['bitDepth'] as int?) ?? 16);
    final int dspRate = t['processingSampleRate'] as int? ?? 48000;
    final int dspChannels = t['processingChannels'] as int? ?? 2;
    final int dacRate =
        t['outputSampleRate'] as int? ?? (hw['sampleRate'] as int? ?? 48000);
    final int dacDepth = hw['bitDepth'] as int? ?? 24;
    final bool isExclusive = hw['isExclusiveMode'] as bool? ?? false;
    final String backend = hw['backendName'] as String? ?? 'Audio Backend';
    final int periodFrames = hw['periodSizeFrames'] as int? ?? 256;
    final int periodCount = hw['periodCount'] as int? ?? 2;

    final bool eqOn = t['eqEnabled'] == true;
    final double crossfeedMix = (t['crossfeedMix'] as num?)?.toDouble() ?? 0.0;
    final String crossfeedAlgo =
        _formatCrossfeedAlgo(t['crossfeedAlgo']?.toString(), crossfeedMix);
    final bool viperOn = t['viperEnabled'] == true;
    final bool limiterOn = t['limiterEnabled'] == true;
    final bool stereoWidenOn = t['stereoWidenEnabled'] == true;
    final bool stereoEnhanceOn = t['stereoEnhancementEnabled'] == true;

    // Calculate node latencies
    final nodeLatencies = _calculatePerNodeLatencies(
      sampleRate: dspRate,
      hwLatencyMs: (t['deviceLatencyMs'] as num?)?.toDouble() ?? 0.0,
      crossfeedAlgo: crossfeedAlgo,
      crossfeedDelayMs: (t['crossfeedDelayMs'] as num?)?.toDouble() ?? 0.40,
      limiterOn: limiterOn,
      stereoWidenOn: stereoWidenOn,
      stereoEnhanceOn: stereoEnhanceOn,
      viperOn: viperOn,
      isSrcActive: (srcRate != dacRate),
    );

    // Sum DSP node latencies
    double sumDspMs = 0.0;
    double sumDspSamples = 0.0;
    for (final n in nodeLatencies) {
      if (n.nodeName != 'Source / Decoder' &&
          n.nodeName != 'Hardware Output DAC') {
        sumDspMs += n.latencyMs;
        sumDspSamples += n.latencySamples;
      }
    }

    final double hwLatencyMs =
        (t['deviceLatencyMs'] as num?)?.toDouble() ?? 0.0;
    final double totalEndToEndLatencyMs = hwLatencyMs + sumDspMs;
    final int clippedCount = t['clippedCount'] as int? ?? 0;

    final bool isSrcActive = (srcRate != dacRate);
    final String resamplerAlgo =
        _formatResamplerAlgo(t['resampleAlgorithm']?.toString());

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Resampling Explanation Box
        /*   _buildResamplingExplainerCard(
          srcRate: srcRate,
          dacRate: dacRate,
          isExclusive: isExclusive,
          isSrcActive: isSrcActive,
          resamplerAlgo: resamplerAlgo,
        ),*/

        const SizedBox(height: 16),

        // Per-Node Latency Breakdown Card (Source -> DAC)
        _buildPerNodeLatencyCard(
            nodeLatencies, totalEndToEndLatencyMs, sumDspSamples),

        const SizedBox(height: 16),

        // Terminal Matrix Display Box
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
                  /* Container(
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
                  )*/
                ],
              ),
              const SizedBox(height: 12),
              const Divider(color: Color(0xFF1B2336), height: 1),
              const SizedBox(height: 12),
              _buildTelemetryRow('Source',
                  '${(srcRate / 1000.0).toStringAsFixed(1)} kHz / $srcDepth-bit PCM'),
              _buildTelemetryRow('Decoder',
                  '${(srcRate / 1000.0).toStringAsFixed(1)} kHz PCM'),
              _buildTelemetryRow('DSP',
                  '${(dspRate / 1000.0).toStringAsFixed(1)} kHz Float32 ($dspChannels ch)'),
              _buildTelemetryRow('Output',
                  '${(dacRate / 1000.0).toStringAsFixed(1)} kHz / $dacDepth-bit'),
              _buildTelemetryRow('Backend',
                  '$backend (${isExclusive ? "Exclusive" : "Shared"})'),
              _buildTelemetryRow(
                  'Buffer', '$periodFrames frames ($periodCount periods)'),
              _buildTelemetryRow('Total Latency',
                  '${totalEndToEndLatencyMs.toStringAsFixed(2)} ms (DSP: ${sumDspMs.toStringAsFixed(2)} ms + Hardware: ${hwLatencyMs.toStringAsFixed(2)} ms)'),
              _buildTelemetryRow(
                  'SRC',
                  isSrcActive
                      ? 'ON (${(srcRate / 1000.0).toStringAsFixed(1)} → ${(dacRate / 1000.0).toStringAsFixed(1)} kHz)'
                      : 'OFF'),
              _buildTelemetryRow('Resampler', resamplerAlgo),
              _buildTelemetryRow('True-Peak',
                  '${((t['truePeakDBTP'] as num?)?.toDouble() ?? -100.0).toStringAsFixed(1)} dBTP',
                  isValueActive:
                      ((t['truePeakDBTP'] as num?)?.toDouble() ?? -100.0) >
                          -90.0,
                  isWarning:
                      ((t['truePeakDBTP'] as num?)?.toDouble() ?? -100.0) >
                          -0.5),
              _buildTelemetryRow('Loudness (LUFS)',
                  'Mom: ${((t['momentaryLUFS'] as num?)?.toDouble() ?? -100.0).toStringAsFixed(1)} / Int: ${((t['integratedLUFS'] as num?)?.toDouble() ?? -100.0).toStringAsFixed(1)}'),
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
              _buildTelemetryRow('ViPER DSP', viperOn ? 'ON' : 'OFF',
                  isValueActive: viperOn),
              _buildTelemetryRow('Limiter', limiterOn ? 'ON' : 'OFF',
                  isValueActive: limiterOn),
              _buildTelemetryRow('Clipping', '$clippedCount samples',
                  isWarning: clippedCount > 0),
              _buildTelemetryRow('Underruns', '0', isValueActive: false),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // Action Quick Switches
        /*
Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                icon: Icon(
                  isExclusive
                      ? Icons.lock_outline_rounded
                      : Icons.lock_open_rounded,
                  size: 16,
                  color: Colors.cyanAccent,
                ),
                label: Text(
                  isExclusive ? 'Exclusive Mode: ON' : 'Exclusive Mode: OFF',
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Color(0xFF2B3754)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () {
                  widget.player.setExclusiveMode(!isExclusive);
                  _fetchTelemetry();
                },
              ),
            ),
          ],
        ),*/
      ],
    );
  }

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
              Row(
                children: [
                  // const Icon(Icons.timer_outlined,
                  //color: Colors.cyanAccent, size: 16),
                  // const SizedBox(width: 6),
                  const Text(
                    'Latency Breakdown',
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
                '${totalMs.toStringAsFixed(2)} ms Total',
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

  Widget _buildTelemetryRow(String label, String value,
      {bool isValueActive = false, bool isWarning = false}) {
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
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontFamily: 'monospace',
                color: valColor,
                fontWeight: isValueActive ? FontWeight.bold : FontWeight.normal,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
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
    required bool viperOn,
    required bool isSrcActive,
  }) {
    final list = <_NodeLatencyInfo>[];
    int step = 1;

    // 1. Source / Decoder
    list.add(_NodeLatencyInfo('${step++}.', 'Source / Decoder', 0.0, 0.0));

    // 2. Crossfeed Node
    if (crossfeedAlgo != 'OFF') {
      final double delayMs = crossfeedDelayMs > 0 ? crossfeedDelayMs : 0.40;
      final double samples = delayMs * 0.001 * sampleRate;
      list.add(_NodeLatencyInfo(
          '${step++}.', 'Crossfeed ($crossfeedAlgo)', delayMs, samples));
    } else {
      list.add(_NodeLatencyInfo('${step++}.', 'Crossfeed Node', 0.0, 0.0));
    }

    // 3. ViPER DSP Node (Oversampling FIR & Effects)
    if (viperOn) {
      const double viperMs =
          1.00; // Base polyphase oversampling FIR & FX latency
      final double samples = viperMs * 0.001 * sampleRate;
      list.add(_NodeLatencyInfo(
          '${step++}.', 'ViPER DSP (Oversampling & FX)', viperMs, samples));
    } else {
      list.add(_NodeLatencyInfo('${step++}.', 'ViPER DSP Node', 0.0, 0.0));
    }

    // 4. Stereo Widen (Haas delay)
    if (stereoWidenOn) {
      const double delayMs = 15.0;
      final double samples = delayMs * 0.001 * sampleRate;
      list.add(_NodeLatencyInfo(
          '${step++}.', 'Stereo Widen (Haas)', delayMs, samples));
    }

    // 5. Stereo Enhancement (PFB analysis)
    if (stereoEnhanceOn) {
      const double delayMs = 1.20;
      final double samples = delayMs * 0.001 * sampleRate;
      list.add(_NodeLatencyInfo(
          '${step++}.', 'Stereo Enhancement (PFB)', delayMs, samples));
    }

    // 6. Lookahead Limiter Node
    if (limiterOn) {
      const double attackMs = 2.0;
      final double samples = attackMs * 0.001 * sampleRate;
      list.add(_NodeLatencyInfo(
          '${step++}.', 'Software Limiter (Lookahead)', attackMs, samples));
    } else {
      list.add(_NodeLatencyInfo('${step++}.', 'Software Limiter', 0.0, 0.0));
    }

    // 7. Resampler Node
    if (isSrcActive) {
      const double resampleMs = 0.50;
      final double samples = resampleMs * 0.001 * sampleRate;
      list.add(
          _NodeLatencyInfo('${step++}.', 'SRC Resampler', resampleMs, samples));
    }

    // 8. Hardware Output DAC
    final double hwSamples = hwLatencyMs * 0.001 * sampleRate;
    list.add(_NodeLatencyInfo(
        '${step++}.', 'Hardware Output DAC', hwLatencyMs, hwSamples));

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
        return 'SOXR VHQ Linear Phase';
      case 'soxrVHQMinimumPhase':
        return 'SOXR VHQ Minimum Phase';
      case 'soxrHQ':
        return 'SOXR HQ';
      case 'soxrFast':
        return 'SOXR Fast';
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

  _NodeLatencyInfo(
      this.stepNumber, this.nodeName, this.latencyMs, this.latencySamples);
}
