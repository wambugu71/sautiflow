import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Interactive dynamic audio diagnostics badge row rendering active format,
/// bit depth, sampling rate, and bit-perfect mode indicators.
class AudioDiagnosticsBadgeRow extends StatelessWidget {
  final String? format;
  final String? bitDepth;
  final String? sampleRate;
  final bool isBitPerfect;
  final String? dsdBadgeLabel;
  final VoidCallback? onOpenDiagnostics;
  final Color? color;
  final Color? bitPerfectColor;
  final double height;

  const AudioDiagnosticsBadgeRow({
    super.key,
    this.format,
    this.bitDepth,
    this.sampleRate,
    this.isBitPerfect = false,
    this.dsdBadgeLabel,
    this.onOpenDiagnostics,
    this.color,
    this.bitPerfectColor,
    this.height = 20.0,
  });

  static String _resolveFormatSvg(String? raw) {
    if (raw != null && raw.trim().isNotEmpty) {
      final f = raw.toLowerCase().trim();

      if (f.contains('flac')) return 'assets/icons/audio_badges/format_flac_32.svg';
      if (f.contains('wav') || f.contains('wave') || f.contains('riff')) {
        return 'assets/icons/audio_badges/format_wav_32.svg';
      }
      if (f.contains('dsd') || f.contains('dsf') || f.contains('dff')) {
        return 'assets/icons/audio_badges/format_dsd_32.svg';
      }
      if (f.contains('alac')) return 'assets/icons/audio_badges/format_alac_32.svg';
      if (f.contains('aiff') || f.contains('aif')) {
        return 'assets/icons/audio_badges/format_aiff_32.svg';
      }
      if (f.contains('mp3') ||
          f.contains('mpeg') ||
          f.contains('id3') ||
          f.contains('mp2') ||
          f.contains('mpa')) {
        return 'assets/icons/audio_badges/format_mp3_32.svg';
      }
      if (f.contains('aac') || f.contains('adts')) {
        return 'assets/icons/audio_badges/format_aac_32.svg';
      }
      if (f.contains('opus')) return 'assets/icons/audio_badges/format_opus_32.svg';
      if (f.contains('m4a') ||
          f.contains('m4b') ||
          f.contains('m4p') ||
          f.contains('mp4')) {
        return 'assets/icons/audio_badges/format_m4a_32.svg';
      }
      if (f.contains('ogg') || f.contains('vorbis') || f.contains('spx')) {
        return 'assets/icons/audio_badges/format_ogg_32.svg';
      }
      if (f.contains('pcm') || f.contains('raw') || f.contains('audio')) {
        return 'assets/icons/audio_badges/format_pcm_32.svg';
      }
    }

    // Default generic audio icon fallback (never mislabel unknown formats as FLAC)
    return 'assets/icons/audio_badges/format_pcm_32.svg';
  }

  static String? _resolveBitDepthSvg(String? rawDepth, String? rawFormat) {
    if (rawDepth == null || rawDepth.trim().isEmpty) return null;
    final d = rawDepth.toLowerCase().trim();
    final f = rawFormat?.toLowerCase().trim() ?? '';

    // Check if lossy format without valid bit depth
    final isLossy = f.contains('mp3') ||
        f.contains('aac') ||
        f.contains('opus') ||
        f.contains('ogg') ||
        f.contains('vorbis') ||
        (f.contains('m4a') && !f.contains('alac'));

    if (d == '0' || d.contains('0 bit') || d == 'unknown') {
      return null;
    }

    if (d.contains('32') || d.contains('64')) {
      return 'assets/icons/audio_badges/bits_32bit_32.svg';
    }
    if (d.contains('24')) {
      return 'assets/icons/audio_badges/bits_24bit_32.svg';
    }
    if (d.contains('16')) {
      return 'assets/icons/audio_badges/bits_16bit_32.svg';
    }
    if (d.contains('8') &&
        !d.contains('18') &&
        !d.contains('28') &&
        !d.contains('38') &&
        !d.contains('48')) {
      return 'assets/icons/audio_badges/bits_8bit_32.svg';
    }

    // Gracefully hide for lossy if not explicitly decoded bits
    if (isLossy) return null;

    return null;
  }

  static String? _resolveSampleRateSvg(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    final s = raw.toLowerCase().replaceAll(' ', '').trim();

    if (s.contains('384')) {
      return 'assets/icons/audio_badges/sample_rate_384khz_32.svg';
    }
    if (s.contains('192')) {
      return 'assets/icons/audio_badges/sample_rate_192khz_32.svg';
    }
    if (s.contains('176.4') || s.contains('1764') || s.contains('176_4')) {
      return 'assets/icons/audio_badges/sample_rate_176_4khz_32.svg';
    }
    if (s.contains('96')) {
      return 'assets/icons/audio_badges/sample_rate_96khz_32.svg';
    }
    if (s.contains('88.2') || s.contains('882') || s.contains('88_2')) {
      return 'assets/icons/audio_badges/sample_rate_88_2khz_32.svg';
    }
    if (s.contains('88.1') || s.contains('881') || s.contains('88_1')) {
      return 'assets/icons/audio_badges/sample_rate_88_1khz_32.svg';
    }
    if (s.contains('48')) {
      return 'assets/icons/audio_badges/sample_rate_48khz_32.svg';
    }
    if (s.contains('44.1') ||
        s.contains('441') ||
        s.contains('44_1') ||
        s.contains('44')) {
      return 'assets/icons/audio_badges/sample_rate_44_1khz_32.svg';
    }

    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final badgeColor = color ?? theme.colorScheme.primary;
    final bpColor = bitPerfectColor ?? const Color(0xFF38BDF8);

    // Guaranteed song format type icon
    final formatSvg = _resolveFormatSvg(format);
    final bitDepthSvg = _resolveBitDepthSvg(bitDepth, format);
    final sampleRateSvg = _resolveSampleRateSvg(sampleRate);

    final List<Widget> badgeWidgets = [
      SvgPicture.asset(
        formatSvg,
        height: height,
        colorFilter: ColorFilter.mode(badgeColor, BlendMode.srcIn),
      ),
    ];

    if (bitDepthSvg != null) {
      badgeWidgets.add(const SizedBox(width: 4));
      badgeWidgets.add(
        SvgPicture.asset(
          bitDepthSvg,
          height: height,
          colorFilter: ColorFilter.mode(badgeColor, BlendMode.srcIn),
        ),
      );
    }

    if (sampleRateSvg != null) {
      badgeWidgets.add(const SizedBox(width: 4));
      badgeWidgets.add(
        SvgPicture.asset(
          sampleRateSvg,
          height: height,
          colorFilter: ColorFilter.mode(badgeColor, BlendMode.srcIn),
        ),
      );
    }

    if (isBitPerfect) {
      badgeWidgets.add(const SizedBox(width: 4));
      badgeWidgets.add(
        SvgPicture.asset(
          'assets/icons/audio_badges/bit_perfect_check_32.svg',
          height: height,
          colorFilter: ColorFilter.mode(bpColor, BlendMode.srcIn),
        ),
      );
    }

    if (dsdBadgeLabel != null && dsdBadgeLabel!.isNotEmpty) {
      badgeWidgets.add(const SizedBox(width: 4));
      badgeWidgets.add(
        Container(
          padding: EdgeInsets.symmetric(
            horizontal: height * 0.28,
            vertical: height * 0.05,
          ),
          decoration: BoxDecoration(
            color: bpColor.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: bpColor.withValues(alpha: 0.45),
              width: 0.7,
            ),
          ),
          child: Text(
            dsdBadgeLabel!,
            style: TextStyle(
              color: bpColor,
              fontSize: (height * 0.48).clamp(8.0, 12.0),
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
              height: 1.1,
            ),
          ),
        ),
      );
    }

    return Semantics(
      label: 'Open Audio Engine Diagnostics Panel',
      button: true,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          splashColor: badgeColor.withValues(alpha: 0.15),
          highlightColor: badgeColor.withValues(alpha: 0.08),
          onTap: onOpenDiagnostics,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 3.0),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.08),
                width: 0.8,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: badgeWidgets,
            ),
          ),
        ),
      ),
    );
  }
}
