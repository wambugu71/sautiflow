import 'package:flutter/material.dart';
import 'package:flutter_m3shapes_extended/flutter_m3shapes_extended.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import '../services/app_theme_service.dart';
import '../services/chromecast_service.dart';
import '../services/dlna_service.dart';

/// Opens the unified Cast Output bottom sheet for Chromecast (up to 24-bit /
/// 192 kHz) and DLNA / UPnP renderers.
Future<void> showCastOutputModal(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: AppThemeService.instance.currentData.cardDark,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (sheetContext) => const _CastOutputSheet(),
  );
}

/// Prompts for a Chromecast LAN IP (useful when subnet isolation / VLANs block
/// mDNS multicast discovery) and connects after optional eureka_info lookup.
Future<void> showAddManualCastIpDialog(
  BuildContext context, {
  bool connectAfterAdd = true,
}) async {
  final ipCtrl = TextEditingController();
  final nameCtrl = TextEditingController();
  final theme = AppThemeService.instance.currentData;

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dlgCtx) => AlertDialog(
      backgroundColor: theme.cardDark,
      title: const Text(
        'Add Chromecast IP',
        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: ipCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              labelText: 'Device IP Address',
              hintText: '192.168.1.42',
              labelStyle: TextStyle(color: theme.textDark),
              hintStyle: TextStyle(color: theme.textDark.withAlpha(120)),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: theme.textDark.withAlpha(80)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: theme.primary),
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: nameCtrl,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              labelText: 'Friendly Name (optional)',
              hintText: 'Living Room TV',
              labelStyle: TextStyle(color: theme.textDark),
              hintStyle: TextStyle(color: theme.textDark.withAlpha(120)),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: theme.textDark.withAlpha(80)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: theme.primary),
              ),
            ),
          ),
        ],
      ),
      actions: [
        M3EButton.text(
          onPressed: () => Navigator.of(dlgCtx).pop(false),
          child: const Text('Cancel'),
        ),
        M3EButton.filled(
          onPressed: () => Navigator.of(dlgCtx).pop(true),
          child: const Text('Add'),
        ),
      ],
    ),
  );

  final ip = ipCtrl.text.trim();
  final name = nameCtrl.text.trim();
  ipCtrl.dispose();
  nameCtrl.dispose();

  if (confirmed != true || ip.isEmpty) return;

  final added = await ChromecastService.instance.addManualDevice(
    ip,
    friendlyName: name.isEmpty ? null : name,
  );
  if (added != null && connectAfterAdd) {
    await ChromecastService.instance.connect(added);
  }
}

/// Shared selector card for Cast / DLNA audio delivery mode and sample-rate
/// ceiling (`192 kHz`, `96 kHz`, `48 kHz`).
class CastModeAndRateCard extends StatelessWidget {
  const CastModeAndRateCard({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = AppThemeService.instance.currentData;
    return AnimatedBuilder(
      animation: ChromecastService.instance,
      builder: (context, _) {
        final cast = ChromecastService.instance;
        final mode = cast.audioMode;
        final maxRate = cast.maxSampleRate;

        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: theme.bgDark.withAlpha(170),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white.withAlpha(18)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.high_quality_rounded,
                      color: theme.primary, size: 18),
                  const SizedBox(width: 8),
                  const Text(
                    'Cast Audio Pipeline',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _ModeChoiceTile(
                      label: 'Bit-Perfect',
                      subtitle: 'Pass-through',
                      icon: Icons.verified_rounded,
                      selected: mode == CastAudioMode.bitPerfect,
                      primary: theme.primary,
                      onTap: () => cast.setAudioMode(CastAudioMode.bitPerfect),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _ModeChoiceTile(
                      label: 'With DSP',
                      subtitle: '24-bit WAV tap',
                      icon: Icons.graphic_eq_rounded,
                      selected: mode == CastAudioMode.dspProcessed,
                      primary: theme.primary,
                      onTap: () => cast.setAudioMode(CastAudioMode.dspProcessed),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                mode == CastAudioMode.bitPerfect
                    ? 'Direct original file pass-through up to ${maxRate.label}; auto-uses DSP-bypassed 24-bit WAV for DSD, float, >${maxRate.label}, CUE slices & ALAC.'
                    : 'Streams live 24-bit LPCM WAV post-DSP (EQ, Crossfeed, Surround, Limiter & Loudness preserved up to ${maxRate.label}).',
                style: TextStyle(color: theme.textDark, fontSize: 11.5),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Text(
                    'Sample-Rate Ceiling:',
                    style: TextStyle(
                      color: theme.textDark,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  for (final rate in CastMaxSampleRate.values) ...[
                    const SizedBox(width: 6),
                    ChoiceChip(
                      label: Text(
                        rate.label,
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: maxRate == rate
                              ? Colors.black
                              : Colors.white.withAlpha(220),
                        ),
                      ),
                      selected: maxRate == rate,
                      selectedColor: theme.primary,
                      backgroundColor: Colors.white.withAlpha(14),
                      side: BorderSide.none,
                      visualDensity: VisualDensity.compact,
                      onSelected: (_) => cast.setMaxSampleRate(rate),
                    ),
                  ],
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ModeChoiceTile extends StatelessWidget {
  final String label;
  final String subtitle;
  final IconData icon;
  final bool selected;
  final Color primary;
  final VoidCallback onTap;

  const _ModeChoiceTile({
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.selected,
    required this.primary,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? primary.withAlpha(38) : Colors.white.withAlpha(10),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? primary : Colors.white.withAlpha(20),
            width: selected ? 1.4 : 1.0,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: selected ? primary : Colors.white70),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: selected ? primary : Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 12.5,
                    ),
                  ),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white60,
                      fontSize: 10.5,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CastOutputSheet extends StatefulWidget {
  const _CastOutputSheet();

  @override
  State<_CastOutputSheet> createState() => _CastOutputSheetState();
}

class _CastOutputSheetState extends State<_CastOutputSheet> {
  @override
  void initState() {
    super.initState();
    if (!ChromecastService.instance.isScanning) {
      ChromecastService.instance.startDiscovery();
    }
    if (!DlnaService.instance.isSearching) {
      DlnaService.instance.startSearch();
    }
  }

  Future<void> _rescan() async {
    await Future.wait([
      ChromecastService.instance.startDiscovery(),
      DlnaService.instance.startSearch(),
    ]);
  }

  Future<void> _disconnectAll() async {
    await ChromecastService.instance.disconnect();
    if (DlnaService.instance.activeRenderer != null) {
      try {
        await DlnaService.instance.stop();
      } catch (_) {}
      DlnaService.instance.setActiveRenderer(null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = AppThemeService.instance.currentData;
    return AnimatedBuilder(
      animation: Listenable.merge([
        ChromecastService.instance,
        DlnaService.instance,
      ]),
      builder: (context, _) {
        final cast = ChromecastService.instance;
        final dlna = DlnaService.instance;
        final activeCast = cast.activeDevice;
        final activeDlna = dlna.activeRenderer;
        final isScanning = cast.isScanning || dlna.isSearching;

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      Icon(Icons.cast_connected_rounded,
                          color: theme.primary, size: 22),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          'Cast Output',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Add Cast IP manually',
                        icon: Icon(Icons.add_link_rounded, color: theme.primary),
                        onPressed: () => showAddManualCastIpDialog(context),
                      ),
                      if (isScanning)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          child: SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: theme.primary,
                            ),
                          ),
                        )
                      else
                        IconButton(
                          tooltip: 'Scan network',
                          icon: Icon(Icons.refresh_rounded, color: theme.primary),
                          onPressed: _rescan,
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (activeCast != null || activeDlna != null) ...[
                    _ActiveCastBanner(
                      deviceName: activeCast?.friendlyName ?? activeDlna!.name,
                      protocolLabel:
                          activeCast != null ? 'Google Cast' : 'DLNA / UPnP',
                      streamModeLabel: activeCast != null
                          ? (cast.isStreamingLiveTap
                              ? 'Live 24-bit LPCM Stream (up to ${cast.maxSampleRate.label})'
                              : 'Direct File Pass-Through')
                          : (cast.audioMode == CastAudioMode.dspProcessed
                              ? 'Live 24-bit LPCM Stream'
                              : 'Bit-Perfect / Auto'),
                      primary: theme.primary,
                      textMuted: theme.textDark,
                      showVolumeSlider: activeCast != null,
                      volume: cast.volumeLevel,
                      muted: cast.isMuted,
                      onVolumeChanged: cast.setVolume,
                      onToggleMute: () => cast.setMuted(!cast.isMuted),
                      onDisconnect: _disconnectAll,
                    ),
                    const SizedBox(height: 12),
                  ],
                  const CastModeAndRateCard(),
                  if (cast.lastError != null) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.redAccent.withAlpha(30),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.redAccent.withAlpha(110),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline_rounded,
                              color: Colors.redAccent, size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              cast.lastError!,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  Text(
                    'CHROMECAST & GOOGLE CAST',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.1,
                      color: theme.primary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (cast.devices.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Text(
                        cast.isScanning
                            ? 'Scanning LAN via mDNS for Google Cast speakers & TVs...'
                            : 'No Chromecast devices discovered yet. Tap Scan or Add IP.',
                        style: TextStyle(color: theme.textDark, fontSize: 12.5),
                      ),
                    )
                  else
                    ...cast.devices.map((device) {
                      final isConnected = activeCast == device;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: M3EListItem(
                          selected: isConnected,
                          leading: M3EContainer(
                            Shapes.circle,
                            width: 40,
                            height: 40,
                            color: (isConnected ? theme.primary : Colors.white)
                                .withAlpha(24),
                            child: Center(
                              child: Icon(
                                Icons.cast_rounded,
                                size: 20,
                                color: isConnected ? theme.primary : Colors.white70,
                              ),
                            ),
                          ),
                          headline: device.friendlyName,
                          supportingText: '${device.modelName} • ${device.host}',
                          trailing: cast.isConnecting && activeCast == device
                              ? SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: theme.primary,
                                  ),
                                )
                              : isConnected
                                  ? Icon(Icons.check_circle_rounded,
                                      color: theme.primary)
                                  : Icon(Icons.chevron_right_rounded,
                                      color: theme.textDark),
                          onTap: () {
                            if (isConnected) {
                              cast.disconnect();
                            } else {
                              cast.connect(device);
                            }
                          },
                        ),
                      );
                    }),
                  const SizedBox(height: 14),
                  Text(
                    'DLNA / UPNP RENDERERS',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.1,
                      color: theme.primary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (dlna.mediaRenderers.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        dlna.isSearching
                            ? 'Searching LAN via SSDP for DLNA renderers...'
                            : 'No DLNA renderers found.',
                        style: TextStyle(color: theme.textDark, fontSize: 12.5),
                      ),
                    )
                  else
                    ...dlna.mediaRenderers.map((renderer) {
                      final isConnected = activeDlna?.id == renderer.id;
                      final rendererHost =
                          Uri.tryParse(renderer.locationUrl)?.host ??
                              renderer.locationUrl;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: M3EListItem(
                          selected: isConnected,
                          leading: M3EContainer(
                            Shapes.circle,
                            width: 40,
                            height: 40,
                            color: (isConnected ? theme.primary : Colors.white)
                                .withAlpha(24),
                            child: Center(
                              child: Icon(
                                Icons.speaker_group_rounded,
                                size: 20,
                                color: isConnected ? theme.primary : Colors.white70,
                              ),
                            ),
                          ),
                          headline: renderer.name,
                          supportingText: rendererHost,
                          trailing: isConnected
                              ? Icon(Icons.check_circle_rounded,
                                  color: theme.primary)
                              : Icon(Icons.chevron_right_rounded,
                                  color: theme.textDark),
                          onTap: () async {
                            if (isConnected) {
                              try {
                                await dlna.stop();
                              } catch (_) {}
                              dlna.setActiveRenderer(null);
                            } else {
                              await cast.disconnect();
                              dlna.setActiveRenderer(renderer);
                            }
                          },
                        ),
                      );
                    }),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ActiveCastBanner extends StatelessWidget {
  final String deviceName;
  final String protocolLabel;
  final String streamModeLabel;
  final Color primary;
  final Color textMuted;
  final bool showVolumeSlider;
  final double volume;
  final bool muted;
  final ValueChanged<double> onVolumeChanged;
  final VoidCallback onToggleMute;
  final VoidCallback onDisconnect;

  const _ActiveCastBanner({
    required this.deviceName,
    required this.protocolLabel,
    required this.streamModeLabel,
    required this.primary,
    required this.textMuted,
    required this.showVolumeSlider,
    required this.volume,
    required this.muted,
    required this.onVolumeChanged,
    required this.onToggleMute,
    required this.onDisconnect,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: primary.withAlpha(26),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: primary.withAlpha(110)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.cast_connected_rounded, color: primary, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      deviceName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                    Text(
                      '$protocolLabel • $streamModeLabel',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: textMuted, fontSize: 11.5),
                    ),
                  ],
                ),
              ),
              M3EButton.tonal(
                onPressed: onDisconnect,
                child: const Text('Disconnect'),
              ),
            ],
          ),
          if (showVolumeSlider) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: Icon(
                    muted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                    color: primary,
                    size: 20,
                  ),
                  onPressed: onToggleMute,
                ),
                Expanded(
                  child: Slider(
                    value: volume.clamp(0.0, 1.0),
                    activeColor: primary,
                    inactiveColor: Colors.white24,
                    onChanged: onVolumeChanged,
                  ),
                ),
                Text(
                  '${(volume * 100).round()}%',
                  style: TextStyle(color: textMuted, fontSize: 11.5),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
