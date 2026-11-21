import 'package:flutter_m3shapes_extended/flutter_m3shapes_extended.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';

import '../../services/app_theme_service.dart';
import '../../services/chromecast_service.dart';
import '../app_m3e_widgets.dart';
import '../cast_output_sheet.dart';
import '../m3e_modal_helpers.dart';

/// Mobile-first Chromecast discovery, connection, and volume control page.
class ChromecastPage extends StatelessWidget {
  final bool showAppBar;

  const ChromecastPage({super.key, this.showAppBar = true});

  @override
  Widget build(BuildContext context) {
    final body = AnimatedBuilder(
      animation: ChromecastService.instance,
      builder: (context, _) {
        final cast = ChromecastService.instance;
        final devices = cast.devices;
        final active = cast.activeDevice;
        final textTheme = Theme.of(context).textTheme;

        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            _buildHeaderCard(context, cast, devices.length, active),
            if (active != null) ...[
              const SizedBox(height: 16),
              _buildConnectedCard(context, cast, active),
            ],
            if (cast.lastError != null) ...[
              const SizedBox(height: 12),
              _buildErrorBanner(context, cast.lastError!),
            ],
            const SizedBox(height: 20),
            AppSectionHeader('Discovered Receivers (${devices.length})'),
            const SizedBox(height: 6),
            if (devices.isEmpty)
              _buildEmptyCard(context, cast.isScanning)
            else
              AppCardContainer(
                children: [
                  for (var i = 0; i < devices.length; i++) ...[
                    if (i > 0) const M3EDivider(),
                    _buildDeviceTile(
                      context,
                      cast,
                      devices[i],
                      isActive: active == devices[i],
                      textTheme: textTheme,
                    ),
                  ],
                ],
              ),
          ],
        );
      },
    );

    if (!showAppBar) return body;

    return Scaffold(
      backgroundColor: context.bgDark,
      appBar: AppBar(
        backgroundColor: context.bgDark,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: context.textPrimary),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text(
          'Chromecast',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: context.textPrimary,
                fontWeight: FontWeight.bold,
              ),
        ),
      ),
      body: body,
    );
  }

  Widget _buildHeaderCard(
    BuildContext context,
    ChromecastService cast,
    int deviceCount,
    dynamic active,
  ) {
    final primary = context.primaryColor;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.cardDark,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: context.outlineColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: primary.withAlpha(30),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.cast_connected_rounded,
                  color: primary,
                  size: 24,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Google Cast Hi-Res Audio',
                      style: textTheme.titleMedium?.copyWith(
                        color: context.textPrimary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      cast.isScanning
                          ? 'Scanning local network via mDNS…'
                          : '$deviceCount found • up to 24-bit/${cast.maxSampleRate.label}',
                      style: textTheme.bodySmall?.copyWith(
                        color: context.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: primary,
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: () {
                    if (cast.isScanning) {
                      cast.stopDiscovery();
                    } else {
                      cast.startDiscovery();
                    }
                  },
                  icon: Icon(
                    cast.isScanning ? Icons.stop_rounded : Icons.radar_rounded,
                    size: 18,
                  ),
                  label: Text(cast.isScanning ? 'Stop scan' : 'Scan'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: primary,
                    side: BorderSide(color: primary.withAlpha(120)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: () => showAddManualCastIpDialog(context),
                  icon: const Icon(Icons.add_link_rounded, size: 18),
                  label: const Text('Add IP'),
                ),
              ),
            ],
          ),
          if (active != null) ...[
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: M3EButton.tonal(
                onPressed: () => cast.disconnect(),
                child: const Text('Disconnect'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildConnectedCard(
    BuildContext context,
    ChromecastService cast,
    dynamic active,
  ) {
    final primary = context.primaryColor;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: primary.withAlpha(22),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: primary.withAlpha(100)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.speaker_rounded, color: primary, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Connected: ${active.friendlyName}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.titleSmall?.copyWith(
                    color: context.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              AppStatusBadge(
                text: cast.isStreamingLiveTap ? '24-bit WAV Tap' : 'Pass-Through',
                color: primary,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: Icon(
                  cast.isMuted
                      ? Icons.volume_off_rounded
                      : Icons.volume_up_rounded,
                  color: primary,
                  size: 20,
                ),
                onPressed: () => cast.setMuted(!cast.isMuted),
              ),
              Expanded(
                child: Slider(
                  value: cast.volumeLevel.clamp(0.0, 1.0),
                  activeColor: primary,
                  inactiveColor: context.outlineColor,
                  onChanged: cast.setVolume,
                ),
              ),
              Text(
                '${(cast.volumeLevel * 100).round()}%',
                style: textTheme.labelMedium?.copyWith(
                  color: context.textMuted,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildErrorBanner(BuildContext context, String error) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.redAccent.withAlpha(30),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.redAccent.withAlpha(110)),
      ),
      child: Text(
        error,
        style: Theme.of(context)
            .textTheme
            .bodySmall
            ?.copyWith(color: context.textPrimary),
      ),
    );
  }

  Widget _buildEmptyCard(BuildContext context, bool isScanning) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: context.cardDark,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.outlineColor),
      ),
      child: Column(
        children: [
          Icon(
            Icons.cast_rounded,
            size: 44,
            color: context.textMuted.withAlpha(120),
          ),
          const SizedBox(height: 10),
          Text(
            isScanning
                ? 'Looking for Chromecast Audio, Google TV & Cast speakers…'
                : 'No Chromecast receivers found.\nTap Scan or Add IP above.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: context.textMuted,
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildDeviceTile(
    BuildContext context,
    ChromecastService cast,
    dynamic d, {
    required bool isActive,
    required TextTheme textTheme,
  }) {
    final primary = context.primaryColor;
    final subtitle = '${d.modelName} • ${d.host}:${d.port}'
        '${d.isManual ? ' (Manual)' : ''}';

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () async {
        if (isActive) {
          await cast.disconnect();
        } else {
          final messenger = ScaffoldMessenger.of(context);
          final ok = await cast.connect(d);
          if (context.mounted && ok) {
            messenger.showSnackBar(
              SnackBar(content: Text('Connected to ${d.friendlyName}')),
            );
          }
        }
      },
      onLongPress: d.isManual
          ? () => _confirmRemoveManualDevice(context, cast, d, isActive)
          : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            M3EContainer(
              Shapes.pill,
              width: 40,
              height: 40,
              color: (isActive ? context.textPrimary : primary).withAlpha(25),
              child: Center(
                child: Icon(
                  Icons.cast_rounded,
                  color: isActive ? context.textPrimary : primary,
                  size: 20,
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    d.friendlyName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.bodyLarge?.copyWith(
                      color: context.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.bodySmall?.copyWith(
                      color: context.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (d.isManual)
              IconButton(
                tooltip: 'Remove manual device',
                icon: Icon(
                  Icons.delete_outline_rounded,
                  color: context.textMuted,
                  size: 20,
                ),
                onPressed: () =>
                    _confirmRemoveManualDevice(context, cast, d, isActive),
              ),
            if (isActive)
              AppStatusBadge(
                text: 'Connected',
                color: primary,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              )
            else
              Icon(Icons.chevron_right_rounded, color: context.textMuted),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmRemoveManualDevice(
    BuildContext context,
    ChromecastService cast,
    dynamic d,
    bool isActive,
  ) async {
    final confirmed = await showSautiM3EDialog<bool>(
      context,
      dialog: M3EDialog(
        title: 'Remove Cast Device?',
        content: Text(
          'Remove "${d.friendlyName}" (${d.host}) from saved manual devices?',
          style: TextStyle(color: context.textMuted),
        ),
        actions: [
          M3EButton.text(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          M3EButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      if (isActive) await cast.disconnect();
      cast.removeManualDevice(d);
    }
  }
}
