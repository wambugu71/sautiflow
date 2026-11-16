import 'package:sautiflow/sautiflow.dart';
import 'package:sautiplay/services/audio_hardware_inspector.dart';
import 'package:sautiplay/services/chromecast_service.dart';

/// Bitmask constants matching `precision64_reasons` in `audio_engine.cpp`.
abstract final class Precision64Reason {
  static const int user = 1;
  static const int exclusive = 2;
  static const int intOutput = 4;

  static String describe(int mask) {
    final reasons = <String>[];
    if ((mask & user) != 0) reasons.add('user');
    if ((mask & exclusive) != 0) reasons.add('exclusive');
    if ((mask & intOutput) != 0) reasons.add('int output');
    if (reasons.isEmpty) return '';
    if ((mask & user) != 0 && reasons.length == 1) return 'user';
    if ((mask & user) == 0) return 'auto · ${reasons.join(' + ')}';
    return reasons.join(' + ');
  }
}

/// Bitmask constants matching `active_node_mask` in `audio_engine.cpp`.
abstract final class ActiveNodeMask {
  static const int z1Restoration = 1 << 0;
  static const int z2ToneDeEsser = 1 << 1;
  static const int z3Harmonics = 1 << 2;
  static const int z4DynamicsEq = 1 << 3;
  static const int z5Spatial = 1 << 4;
  static const int z6AutoEqFir = 1 << 5;
  static const int z6Leveller = 1 << 6;
  static const int dynamicLoudness = 1 << 7;
  static const int preGain = 1 << 8;
  static const int floatIslandZ1Z3 = 1 << 9;
  static const int floatIslandZ5 = 1 << 10;
  static const int floatIslandZ6 = 1 << 11;
  static const int z1Subsonic = 1 << 12;
  static const int z1NoiseGate = 1 << 13;
  static const int z1Expander = 1 << 14;
}

enum ChainNodeKind {
  source,
  decoderSrc,
  precision,
  preGain,
  zone,
  bypassedDsp,
  volume,
  dynamicLoudness,
  limiter,
  deviceSrc,
  dither,
  output,
}

enum FormatConversionKind {
  none,
  promotion,
  downcast,
  quantize,
  rateChange,
}

class SignalPathArrow {
  final String formatLabel;
  final FormatConversionKind conversionKind;
  final String? note;

  const SignalPathArrow({
    required this.formatLabel,
    this.conversionKind = FormatConversionKind.none,
    this.note,
  });
}

class SignalPathNode {
  final ChainNodeKind kind;
  final String title;
  final String detail;
  final double? latencyMs;
  final bool isEstimatedLatency;
  final bool isBypassed;
  final bool isWarning;
  final String? badge;
  final SignalPathArrow? outgoingArrow;

  const SignalPathNode({
    required this.kind,
    required this.title,
    required this.detail,
    this.latencyMs,
    this.isEstimatedLatency = false,
    this.isBypassed = false,
    this.isWarning = false,
    this.badge,
    this.outgoingArrow,
  });

  SignalPathNode copyWith({SignalPathArrow? outgoingArrow}) {
    return SignalPathNode(
      kind: kind,
      title: title,
      detail: detail,
      latencyMs: latencyMs,
      isEstimatedLatency: isEstimatedLatency,
      isBypassed: isBypassed,
      isWarning: isWarning,
      badge: badge,
      outgoingArrow: outgoingArrow ?? this.outgoingArrow,
    );
  }
}

class SignalPathResult {
  final List<SignalPathNode> nodes;
  final List<String> inactiveStageNames;
  final String dspPrecisionLabel;
  final String outputLabel;
  final String srcLabel;
  final String resamplerLabel;
  final String limiterLabel;
  final double? totalMeasuredLatencyMs;

  const SignalPathResult({
    required this.nodes,
    required this.inactiveStageNames,
    required this.dspPrecisionLabel,
    required this.outputLabel,
    required this.srcLabel,
    required this.resamplerLabel,
    required this.limiterLabel,
    this.totalMeasuredLatencyMs,
  });

  int get inactiveStageCount => inactiveStageNames.length;
}

String formatResamplerAlgoName(String? algo) {
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

String formatDeviceResamplerAlgo(int algoCode) {
  switch (algoCode) {
    case 0:
      return 'Linear LPF4';
    case 1:
      return 'SRC Sinc Best';
    case 2:
      return 'SRC Sinc Medium';
    case 3:
      return 'SRC Sinc Fastest';
    case 4:
    case 5:
    case 6:
      return 'Miniaudio Linear';
    default:
      return 'Linear LPF4';
  }
}

String formatCrossfeedAlgoName(String? algo, double mix) {
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

int? _parseAeFormatCode(dynamic value) {
  if (value is int) return value >= 0 ? value : null;
  if (value is num) {
    final i = value.toInt();
    return i >= 0 ? i : null;
  }
  if (value is String) {
    switch (value.toLowerCase()) {
      case 'f32':
      case 'float32':
      case 'float':
        return 0;
      case 's16':
      case 'int16':
        return 1;
      case 'u8':
      case 'uint8':
        return 2;
      case 's24':
      case 'int24':
        return 3;
      case 's32':
      case 'int32':
        return 4;
      case 'f64':
      case 'float64':
        return 64;
    }
  }
  return null;
}

String _formatAeCodeShort(int? code, {int? validBitDepth}) {
  switch (code) {
    case 0:
    case 5:
      return 'F32';
    case 1:
      return 'S16';
    case 2:
      return 'U8';
    case 3:
      return 'S24';
    case 4:
      final v = (validBitDepth != null && validBitDepth > 0 && validBitDepth < 32)
          ? validBitDepth
          : 32;
      return v < 32 ? 'S32/$v' : 'S32';
    case 64:
      return 'F64';
    default:
      return 'F32';
  }
}

String _formatRateKhz(int hz) => '${(hz / 1000.0).toStringAsFixed(1)} kHz';

/// Pure builder converting engine telemetry + hardware specs into a verified
/// signal path matching `data_callback` order in `audio_engine.cpp`.
SignalPathResult buildSignalPath(
  Map<String, dynamic> t,
  AudioHardwareSpecs specs, {
  required String activeDeviceType,
  required bool isCastingOut,
  required CastAudioMode castMode,
  required int castMaxSampleRateHz,
  String? castOutputLabel,
  String? dlnaSourceLabel,
}) {
  final hw = (t['hardware'] as Map?)?.cast<String, dynamic>() ?? const {};

  final String fileType = (t['fileType'] as String? ?? 'PCM').toUpperCase();
  final int srcRate = t['inputSampleRate'] as int? ?? 48000;
  final int srcChannels = t['inputChannels'] as int? ?? 2;
  final int srcDepth =
      t['inputBitDepth'] as int? ?? ((hw['bitDepth'] as int?) ?? 16);
  final bool srcDepthInferred = t['inputBitDepthInferred'] == true;
  final int? inFmtCode = t['inputFormat'] as int?;

  final int dspRate = (t['engineSampleRate'] as int?) ??
      (t['processingSampleRate'] as int? ?? 48000);
  final int dspChannels = t['processingChannels'] as int? ?? 2;
  final int? procFmtCode = t['processingFormat'] as int?;
  final int dacRate = t['outputSampleRate'] as int? ??
      (hw['sampleRate'] as int? ?? specs.sampleRate);

  // F1: Real negotiated device format first (`hw['outputFormat']` or `deviceFormatActual`),
  // falling back to `ps.outputFormat` only when hardware format is unknown.
  final int? hwOutFmt = _parseAeFormatCode(hw['outputFormat']);
  final int? devFmtActual = _parseAeFormatCode(t['deviceFormatActual']);
  final int? psOutFmt = _parseAeFormatCode(t['outputFormat']);
  final int? realOutFmt = hwOutFmt ?? devFmtActual ?? psOutFmt;

  final int? hwBitDepth = hw['bitDepth'] as int?;
  final int dacValidBits = t['dacValidBitDepth'] as int? ?? 24;
  final int dacDepth = (hwBitDepth != null && hwBitDepth > 0)
      ? hwBitDepth
      : switch (realOutFmt) {
          0 => 32,
          4 => (dacValidBits > 0 ? dacValidBits : 32),
          3 => 24,
          1 => 16,
          2 => 8,
          _ => specs.bitDepth,
        };
  final String dacFormatType = switch (realOutFmt) {
    0 => 'Float',
    1 || 2 || 3 || 4 => 'Int',
    _ => (hw['isFloat'] as bool? ?? specs.isFloat) ? 'Float' : 'Int',
  };

  // F2 & F3: Precision & bypass flags from native single source of truth
  final int p64Reasons = t['precision64Reasons'] as int? ?? 0;
  final bool is64BitDsp = (p64Reasons != 0) ||
      (t['is64BitProcessing'] == true) ||
      (procFmtCode == 64);
  final bool hasFloat64EndToEndField = t.containsKey('float64EndToEnd');
  final bool decoderSrcActive = t['decoderSrcActive'] as bool? ??
      (srcRate > 0 && dspRate > 0 && srcRate != dspRate);
  final bool deviceSrcActive = t['deviceSrcActive'] as bool? ??
      (dspRate > 0 && dacRate > 0 && dspRate != dacRate);
  final bool float64EndToEnd = hasFloat64EndToEndField
      ? (t['float64EndToEnd'] == true)
      : (is64BitDsp && !deviceSrcActive);
  final bool appDspBypassed = t['appDspBypassed'] == true ||
      specs.isDirectPcm ||
      (hw['isExclusiveMode'] == true && !t.containsKey('appDspBypassed'));

  // DSD state
  final int activeDsdModeInt = t['activeDsdMode'] as int? ?? 0;
  final int sourceDsdRate = t['sourceDsdRate'] as int? ?? 0;
  final double dsdGainBoostDb =
      (t['dsdGainBoostDb'] as num?)?.toDouble() ?? 6.0;
  final ActiveDsdMode activeDsdMode = ActiveDsdMode.fromValue(activeDsdModeInt);
  final bool isDsdActive =
      activeDsdMode != ActiveDsdMode.none && sourceDsdRate > 0;
  final bool isDsdPassthrough = activeDsdMode == ActiveDsdMode.dop ||
      activeDsdMode == ActiveDsdMode.nativeDsd;

  // F5-F7: SRC & Resampler labels
  final String decoderAlgo =
      formatResamplerAlgoName(t['resampleAlgorithm']?.toString());
  final int devAlgoCode = t['deviceResamplerAlgo'] as int? ?? 0;
  final String deviceAlgo = formatDeviceResamplerAlgo(devAlgoCode);
  final bool anySrcActive = decoderSrcActive || deviceSrcActive;

  final String srcLabel;
  if (isDsdPassthrough) {
    srcLabel = 'OFF (DSD Bit-Perfect)';
  } else if (decoderSrcActive && deviceSrcActive) {
    srcLabel =
        'ON (${_formatRateKhz(srcRate)} → ${_formatRateKhz(dspRate)} → ${_formatRateKhz(dacRate)})';
  } else if (decoderSrcActive) {
    srcLabel = 'ON (${_formatRateKhz(srcRate)} → ${_formatRateKhz(dspRate)})';
  } else if (deviceSrcActive) {
    srcLabel = 'ON (${_formatRateKhz(dspRate)} → ${_formatRateKhz(dacRate)})';
  } else {
    srcLabel = 'OFF';
  }

  final String resamplerLabel;
  if (!anySrcActive || isDsdPassthrough) {
    resamplerLabel = '—';
  } else if (decoderSrcActive && deviceSrcActive) {
    resamplerLabel = '$decoderAlgo (Dec) + $deviceAlgo (Dev)';
  } else if (decoderSrcActive) {
    resamplerLabel = '$decoderAlgo (Decoder)';
  } else {
    resamplerLabel = '$deviceAlgo (Device)';
  }

  // F4: Limiter priority (Master > Look-Ahead > Simple)
  final int activeLimiter = t['activeLimiter'] as int? ??
      ((t['lookaheadLimiterEnabled'] == true)
          ? 2
          : (t['simpleLimiterEnabled'] == true || t['limiterEnabled'] == true
              ? 3
              : 0));
  final String limiterLabel = switch (activeLimiter) {
    1 => 'ON (Master Brickwall)',
    2 => 'ON (Look-Ahead)',
    3 => 'ON (Anti-Clipping)',
    _ => 'OFF',
  };

  // F10: DSP precision summary label
  final String reasonText = Precision64Reason.describe(p64Reasons);
  final String dspPrecisionLabel;
  if (isCastingOut) {
    dspPrecisionLabel = (castMode == CastAudioMode.bitPerfect)
        ? 'Bypassed (Bit-Perfect Cast)'
        : (is64BitDsp
            ? 'Float64 → 24-bit WAV Tap (With DSP)'
            : 'F32 → 24-bit WAV Tap (With DSP)');
  } else if (isDsdPassthrough) {
    dspPrecisionLabel = 'Bypassed (DSD Bit-Perfect)';
  } else if (appDspBypassed) {
    dspPrecisionLabel = 'Bypassed (Exclusive)';
  } else if (is64BitDsp) {
    final base = dacFormatType == 'Int'
        ? 'Float64 → $dacDepth-bit Int'
        : 'Float64';
    final suffix = <String>[];
    if (!float64EndToEnd) {
      suffix.add(deviceSrcActive ? '→F32 @ SRC' : 'F32 island');
    }
    if (reasonText.isNotEmpty && (p64Reasons & Precision64Reason.user) == 0) {
      suffix.add(reasonText);
    }
    dspPrecisionLabel =
        suffix.isEmpty ? base : '$base (${suffix.join(', ')})';
  } else {
    dspPrecisionLabel = 'Float32';
  }

  // Output summary label
  final String outputLabel;
  if (isCastingOut) {
    final castTargetRate = castMode == CastAudioMode.bitPerfect
        ? srcRate
        : ChromecastService.resolveCastTargetSampleRate(
            srcRate, castMaxSampleRateHz);
    final castBits = castMode == CastAudioMode.bitPerfect ? srcDepth : 24;
    outputLabel =
        '${_formatRateKhz(castTargetRate)} / $castBits-bit (${castOutputLabel ?? "Cast"})';
  } else {
    outputLabel = switch (activeDsdMode) {
      ActiveDsdMode.nativeDsd =>
        '${ActiveDsdMode.formatDsdRateName(sourceDsdRate)} / 1-bit Native DSD ($activeDeviceType)',
      ActiveDsdMode.dop =>
        '${_formatRateKhz(dacRate)} DoP Container ($activeDeviceType)',
      _ =>
        '${_formatRateKhz(dacRate)} / $dacDepth-bit $dacFormatType ($activeDeviceType)',
    };
  }

  // Latencies (F8: measured only)
  final double? measuredResampleMs =
      (t['resampleLatencyMs'] as num?)?.toDouble();
  final double? hwLatencyMs = isCastingOut
      ? null
      : ((t['deviceLatencyMs'] as num?)?.toDouble() ??
          (specs.latencyMs > 0 ? specs.latencyMs : null));

  // Build Signal Path Nodes
  final nodes = <SignalPathNode>[];
  final inactiveStages = <String>[];

  final String srcFmtShort = isDsdActive
      ? 'DSD 1-bit'
      : (inFmtCode != null
          ? _formatAeCodeShort(inFmtCode)
          : 'int$srcDepth');
  final String srcDetail = isDsdActive
      ? '${ActiveDsdMode.formatDsdRateName(sourceDsdRate)} · ${(sourceDsdRate / 1000000.0).toStringAsFixed(4)} MHz · $srcChannels ch'
      : '$fileType · ${_formatRateKhz(srcRate)} · $srcDepth-bit${srcDepthInferred ? " (inferred)" : ""} · $srcChannels ch';

  // DSD Passthrough fast-path
  if (isDsdPassthrough) {
    nodes.add(SignalPathNode(
      kind: ChainNodeKind.source,
      title: dlnaSourceLabel ?? 'SOURCE',
      detail: srcDetail,
      outgoingArrow: SignalPathArrow(
        formatLabel: srcFmtShort,
        conversionKind: FormatConversionKind.none,
      ),
    ));
    nodes.add(SignalPathNode(
      kind: ChainNodeKind.bypassedDsp,
      title: activeDsdMode == ActiveDsdMode.nativeDsd
          ? 'NATIVE DSD STREAM'
          : 'DoP v1.1 PACKER',
      detail: '7-Zone DSP & SRC bypassed (Bit-Perfect)',
      isBypassed: true,
      outgoingArrow: SignalPathArrow(
        formatLabel: activeDsdMode == ActiveDsdMode.nativeDsd
            ? 'DSD 1-bit'
            : 'DoP (${_formatRateKhz(dacRate)})',
        conversionKind: FormatConversionKind.none,
      ),
    ));
    nodes.add(SignalPathNode(
      kind: ChainNodeKind.output,
      title: 'OUTPUT',
      detail: outputLabel,
      latencyMs: hwLatencyMs,
    ));
    return SignalPathResult(
      nodes: nodes,
      inactiveStageNames: const [],
      dspPrecisionLabel: dspPrecisionLabel,
      outputLabel: outputLabel,
      srcLabel: srcLabel,
      resamplerLabel: resamplerLabel,
      limiterLabel: limiterLabel,
      totalMeasuredLatencyMs: hwLatencyMs,
    );
  }

  // Standard PCM / D2P chain
  final String decoderOutFmt = isDsdActive
      ? 'F32 (D2P +${dsdGainBoostDb.toStringAsFixed(1)} dB)'
      : 'F32';

  nodes.add(SignalPathNode(
    kind: ChainNodeKind.source,
    title: dlnaSourceLabel ?? 'SOURCE',
    detail: srcDetail,
    outgoingArrow: SignalPathArrow(
      formatLabel: srcFmtShort,
      conversionKind: srcFmtShort == 'F32'
          ? FormatConversionKind.none
          : FormatConversionKind.promotion,
    ),
  ));

  if (decoderSrcActive) {
    nodes.add(SignalPathNode(
      kind: ChainNodeKind.decoderSrc,
      title: 'DECODER SRC',
      detail:
          '$decoderAlgo · ${_formatRateKhz(srcRate)} → ${_formatRateKhz(dspRate)}',
      latencyMs: (measuredResampleMs != null && measuredResampleMs > 0)
          ? measuredResampleMs
          : null,
      outgoingArrow: SignalPathArrow(
        formatLabel: decoderOutFmt,
        conversionKind: FormatConversionKind.rateChange,
      ),
    ));
  } else {
    inactiveStages.add('Decoder SRC');
  }

  // Precision promotion node
  final String dspFmt = is64BitDsp ? 'F64' : 'F32';
  nodes.add(SignalPathNode(
    kind: ChainNodeKind.precision,
    title: 'PRECISION',
    detail: is64BitDsp ? 'Float64 ($dspChannels ch)' : 'Float32 ($dspChannels ch)',
    badge: reasonText.isNotEmpty ? reasonText : null,
    outgoingArrow: SignalPathArrow(
      formatLabel: dspFmt,
      conversionKind: is64BitDsp
          ? FormatConversionKind.promotion
          : FormatConversionKind.none,
    ),
  ));

  final int nodeMask = t['activeNodeMask'] as int? ?? 0;
  final bool hasMask = t.containsKey('activeNodeMask');

  // Stage 1: Pre-Gain (ReplayGain / Normalizer)
  final bool normOn = t['loudnessNormalizerEnabled'] == true;
  final double normTarget =
      (t['loudnessNormalizerTarget'] as num?)?.toDouble() ?? -14.0;
  final double normGainDb =
      (t['loudnessNormalizerGainDb'] as num?)?.toDouble() ?? 0.0;
  final bool preGainActive =
      ((nodeMask & ActiveNodeMask.preGain) != 0) || normOn;
  if (preGainActive) {
    final parts = <String>[];
    if (normOn) {
      final sign = normGainDb >= 0 ? '+' : '';
      parts.add(
          'Norm ${normTarget.toStringAsFixed(1)} LUFS ($sign${normGainDb.toStringAsFixed(1)} dB)');
    }
    if ((nodeMask & ActiveNodeMask.preGain) != 0 && !normOn) {
      parts.add('ReplayGain');
    }
    nodes.add(SignalPathNode(
      kind: ChainNodeKind.preGain,
      title: 'PRE-GAIN',
      detail: parts.isEmpty ? 'Active' : parts.join(' · '),
      outgoingArrow: SignalPathArrow(formatLabel: dspFmt),
    ));
  } else {
    inactiveStages.add('Pre-Gain');
  }

  // App DSP Zones Z1..Z6
  if (appDspBypassed) {
    nodes.add(SignalPathNode(
      kind: ChainNodeKind.bypassedDsp,
      title: 'APP DSP BYPASSED',
      detail: isCastingOut
          ? 'Bit-Perfect Cast (Zones 1–7 skipped)'
          : 'Exclusive / Direct mode (Zones 1–7 skipped)',
      isBypassed: true,
      outgoingArrow: SignalPathArrow(formatLabel: dspFmt),
    ));
  } else {
    void addZone({
      required bool active,
      required String badge,
      required String title,
      required String detail,
      bool hasFloatIsland = false,
    }) {
      if (!active) {
        inactiveStages.add('$badge $title');
        return;
      }
      final islandArrow = (is64BitDsp && hasFloatIsland)
          ? const SignalPathArrow(
              formatLabel: 'F64 → F32 → F64',
              conversionKind: FormatConversionKind.downcast,
              note: 'float island',
            )
          : SignalPathArrow(formatLabel: dspFmt);
      nodes.add(SignalPathNode(
        kind: ChainNodeKind.zone,
        badge: badge,
        title: title,
        detail: detail,
        isWarning: is64BitDsp && hasFloatIsland,
        outgoingArrow: islandArrow,
      ));
    }

    final z1Parts = <String>[];
    if ((nodeMask & ActiveNodeMask.z1Subsonic) != 0) {
      z1Parts.add('Subsonic / Protection Filter');
    }
    if ((nodeMask & ActiveNodeMask.z1NoiseGate) != 0) {
      z1Parts.add('Noise Gate');
    }
    if ((nodeMask & ActiveNodeMask.z1Expander) != 0) {
      z1Parts.add('Expander');
    }
    addZone(
      active: (nodeMask & ActiveNodeMask.z1Restoration) != 0,
      badge: 'Z1',
      title: 'RESTORATION',
      detail: z1Parts.isEmpty
          ? 'Subsonic / Noise Gate / Expander'
          : z1Parts.join(' · '),
      hasFloatIsland: (nodeMask & ActiveNodeMask.floatIslandZ1Z3) != 0,
    );
    addZone(
      active: (nodeMask & ActiveNodeMask.z2ToneDeEsser) != 0,
      badge: 'Z2',
      title: 'TONE & DE-ESSER',
      detail: 'Dynamic EQ / De-Esser',
      hasFloatIsland: (nodeMask & ActiveNodeMask.floatIslandZ1Z3) != 0,
    );
    addZone(
      active: (nodeMask & ActiveNodeMask.z3Harmonics) != 0,
      badge: 'Z3',
      title: 'HARMONICS',
      detail: 'Harmonic Bass / Warmth / Tape / Clarity',
      hasFloatIsland: (nodeMask & ActiveNodeMask.floatIslandZ1Z3) != 0,
    );

    final bool eqOn = t['eqEnabled'] == true;
    final bool z4Active = hasMask
        ? (nodeMask & ActiveNodeMask.z4DynamicsEq) != 0
        : eqOn;
    addZone(
      active: z4Active,
      badge: 'Z4',
      title: 'DYNAMICS & EQ',
      detail: eqOn ? 'EQ / Compressor' : 'Compressor / Multiband EQ',
    );

    final double crossfeedMix = (t['crossfeedMix'] as num?)?.toDouble() ?? 0.0;
    final String crossfeedAlgo =
        formatCrossfeedAlgoName(t['crossfeedAlgo']?.toString(), crossfeedMix);
    final bool stereoWidenOn = t['stereoWidenEnabled'] == true;
    final bool stereoEnhanceOn = t['stereoEnhancementEnabled'] == true;
    final bool reverbOn = t['reverbEnabled'] == true;
    final bool z5Active = hasMask
        ? (nodeMask & ActiveNodeMask.z5Spatial) != 0
        : (crossfeedAlgo != 'OFF' ||
            stereoWidenOn ||
            stereoEnhanceOn ||
            reverbOn);
    final z5Parts = <String>[];
    if (crossfeedAlgo != 'OFF') z5Parts.add('Crossfeed ($crossfeedAlgo)');
    if (stereoWidenOn) z5Parts.add('Widen');
    if (stereoEnhanceOn) z5Parts.add('Enhance');
    if (reverbOn) {
      z5Parts.add('Reverb (${t['reverbEngine'] ?? 'Dattorro'})');
    }
    final bool z5FloatIsland = hasMask
        ? (nodeMask & ActiveNodeMask.floatIslandZ5) != 0
        : (stereoWidenOn || stereoEnhanceOn || reverbOn);
    addZone(
      active: z5Active,
      badge: 'Z5',
      title: 'SPATIAL',
      detail: z5Parts.isEmpty ? 'Spatializer' : z5Parts.join(' · '),
      hasFloatIsland: z5FloatIsland,
    );

    final bool autoEqOn = t['fftConvolverEnabled'] == true ||
        (nodeMask & ActiveNodeMask.z6AutoEqFir) != 0;
    final bool levellerOn = t['levellerEnabled'] == true ||
        (nodeMask & ActiveNodeMask.z6Leveller) != 0;
    final z6Parts = <String>[];
    if (autoEqOn) z6Parts.add('AutoEQ FIR');
    if (levellerOn) z6Parts.add('Broadcast Leveller');
    addZone(
      active: autoEqOn || levellerOn,
      badge: 'Z6',
      title: 'DELIVERY',
      detail: z6Parts.join(' · '),
      hasFloatIsland: autoEqOn,
    );

    // Stage 3: Master Volume (shown when non-unity)
    final double gain = (t['gain'] as num?)?.toDouble() ?? 1.0;
    if ((gain - 1.0).abs() > 1e-4) {
      nodes.add(SignalPathNode(
        kind: ChainNodeKind.volume,
        title: 'VOLUME',
        detail: 'Gain ×${gain.toStringAsFixed(2)}',
        outgoingArrow: SignalPathArrow(formatLabel: dspFmt),
      ));
    }

    // Dynamic Loudness
    if ((nodeMask & ActiveNodeMask.dynamicLoudness) != 0) {
      nodes.add(SignalPathNode(
        kind: ChainNodeKind.dynamicLoudness,
        title: 'DYNAMIC LOUDNESS',
        detail: 'ISO 226 Contour',
        outgoingArrow: SignalPathArrow(formatLabel: dspFmt),
      ));
    }

    // Z7 Limiter
    if (activeLimiter != 0) {
      final double gr =
          (t['limiterGainReductionDB'] as num?)?.toDouble() ?? 0.0;
      final name = switch (activeLimiter) {
        1 => 'Master Brickwall',
        2 => 'Look-Ahead',
        _ => 'Anti-Clipping',
      };
      nodes.add(SignalPathNode(
        kind: ChainNodeKind.limiter,
        badge: 'Z7',
        title: 'LIMITER',
        detail: '$name · GR ${gr.toStringAsFixed(1)} dB',
        outgoingArrow: SignalPathArrow(formatLabel: dspFmt),
      ));
    } else {
      inactiveStages.add('Z7 Limiter');
    }
  }

  // Device SRC stage
  String postSrcFmt = dspFmt;
  if (deviceSrcActive) {
    postSrcFmt = 'F32';
    nodes.add(SignalPathNode(
      kind: ChainNodeKind.deviceSrc,
      title: 'DEVICE SRC',
      detail:
          '$deviceAlgo · ${_formatRateKhz(dspRate)} → ${_formatRateKhz(dacRate)}',
      latencyMs: (!decoderSrcActive &&
              measuredResampleMs != null &&
              measuredResampleMs > 0)
          ? measuredResampleMs
          : null,
      isWarning: is64BitDsp,
      outgoingArrow: SignalPathArrow(
        formatLabel: is64BitDsp ? 'F64 → F32' : 'F32',
        conversionKind: is64BitDsp
            ? FormatConversionKind.downcast
            : FormatConversionKind.rateChange,
        note: is64BitDsp ? 'SRC downcast' : null,
      ),
    ));
  } else {
    inactiveStages.add('Device SRC');
  }

  // Quantization / Output stage
  final String outFmtShort =
      _formatAeCodeShort(realOutFmt, validBitDepth: dacDepth);
  if (outFmtShort != postSrcFmt && outFmtShort != 'F32') {
    nodes.add(SignalPathNode(
      kind: ChainNodeKind.dither,
      title: 'DITHER & QUANTIZE',
      detail: '$postSrcFmt → $dacDepth-bit $dacFormatType',
      outgoingArrow: SignalPathArrow(
        formatLabel: outFmtShort,
        conversionKind: FormatConversionKind.quantize,
      ),
    ));
  }

  nodes.add(SignalPathNode(
    kind: ChainNodeKind.output,
    title: 'OUTPUT',
    detail: outputLabel,
    latencyMs: hwLatencyMs,
  ));

  double? totalMeasuredMs;
  double sum = 0.0;
  bool anyLat = false;
  for (final n in nodes) {
    if (n.latencyMs != null) {
      sum += n.latencyMs!;
      anyLat = true;
    }
  }
  if (anyLat) totalMeasuredMs = sum;

  return SignalPathResult(
    nodes: nodes,
    inactiveStageNames: inactiveStages,
    dspPrecisionLabel: dspPrecisionLabel,
    outputLabel: outputLabel,
    srcLabel: srcLabel,
    resamplerLabel: resamplerLabel,
    limiterLabel: limiterLabel,
    totalMeasuredLatencyMs: totalMeasuredMs,
  );
}
