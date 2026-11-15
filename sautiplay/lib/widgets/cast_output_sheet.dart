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

/// Shared selector card for Cast and DLNA audio delivery mode and sample-rate
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
                    ? 'Original file up to ${maxRate.label}. Uses 24-bit WAV (no DSP) for DSD, float, CUE, or ALAC.'
                    : 'Live 24-bit LPCM WAV up to ${maxRate.label} with EQ, crossfeed, surround, and limiter.',
                style: TextStyle(color: theme.textDark, fontSize: 11.5),
              ),
              const SizedBox(height: 12),
              Text(
                'Sample-Rate Ceiling',
                style: TextStyle(
                  color: theme.textDark,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final rate in CastMaxSampleRate.values)
                    M3EChip(
                      label: rate.label,
                      type: M3EChipType.filter,
                      selected: maxRate == rate,
                      onPressed: () => cast.setMaxSampleRate(rate),
                    ),
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
                      width: 38,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 14),
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: theme.primary.withAlpha(35),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          Icons.cast_connected_rounded,
                          color: theme.primary,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Cast Output',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            Text(
                              'Chromecast and DLNA',
                              style: TextStyle(
                                color: theme.textDark,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Tooltip(
                        message: 'Add Cast IP manually',
                        child: M3EIconButton(
                          variant: M3EIconButtonVariant.tonal,
                          icon: Icon(
                            Icons.add_link_rounded,
                            color: theme.primary,
                          ),
                          onPressed: () => showAddManualCastIpDialog(context),
                        ),
                      ),
                      const SizedBox(width: 6),
                      SizedBox(
                        width: 40,
                        height: 40,
                        child: Center(
                          child: isScanning
                              ? SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: theme.primary,
                                  ),
                                )
                              : Tooltip(
                                  message: 'Scan network',
                                  child: M3EIconButton(
                                    variant: M3EIconButtonVariant.tonal,
                                    icon: Icon(
                                      Icons.refresh_rounded,
                                      color: theme.primary,
                                    ),
                                    onPressed: _rescan,
                                  ),
                                ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (activeCast != null || activeDlna != null) ...[
                    _ActiveCastBanner(
                      deviceName: activeCast?.friendlyName ?? activeDlna!.name,
                      protocolLabel:
                          activeCast != null ? 'Google Cast' : 'DLNA / UPnP',
                      deviceDetail: activeCast != null
                          ? (activeCast.modelName.isNotEmpty
                              ? '${activeCast.modelName} (${activeCast.host})'
                              : activeCast.host)
                          : (Uri.tryParse(activeDlna!.locationUrl)?.host ??
                              activeDlna.locationUrl),
                      streamModeLabel: activeCast != null
                          ? (cast.isStreamingLiveTap
                              ? 'Live 24-bit LPCM'
                              : 'Direct Pass-Through')
                          : (cast.audioMode == CastAudioMode.dspProcessed
                              ? 'Live 24-bit LPCM'
                              : 'Bit-Perfect'),
                      rateCeilingLabel: 'Max ${cast.maxSampleRate.label}',
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
                            ? 'Scanning local network for Chromecast devices...'
                            : 'No Chromecast devices found. Tap Refresh or Add IP.',
                        style: TextStyle(color: theme.textDark, fontSize: 12.5),
                      ),
                    )
                  else
                    ...cast.devices.map((device) {
                      final isConnected = activeCast == device;
                      final hostLabel = device.modelName.isNotEmpty
                          ? '${device.modelName} (${device.host})'
                          : device.host;
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
                          supportingText:
                              device.isManual ? '$hostLabel (Manual)' : hostLabel,
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
                            ? 'Scanning local network for DLNA renderers...'
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
  final String deviceDetail;
  final String streamModeLabel;
  final String rateCeilingLabel;
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
    required this.deviceDetail,
    required this.streamModeLabel,
    required this.rateCeilingLabel,
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
                        fontSize: 14.5,
                      ),
                    ),
                    if (deviceDetail.isNotEmpty)
                      Text(
                        deviceDetail,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: textMuted, fontSize: 11.5),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              M3EButton.tonal(
                onPressed: onDisconnect,
                child: const Text('Disconnect'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _CastInfoPill(label: protocolLabel, color: primary),
              _CastInfoPill(label: streamModeLabel, color: Colors.white),
              _CastInfoPill(label: rateCeilingLabel, color: textMuted),
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
                SizedBox(
                  width: 38,
                  child: Text(
                    '${(volume * 100).round()}%',
                    textAlign: TextAlign.end,
                    style: TextStyle(color: textMuted, fontSize: 11.5),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _CastInfoPill extends StatelessWidget {
  final String label;
  final Color color;

  const _CastInfoPill({
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withAlpha(24),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withAlpha(70)),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
