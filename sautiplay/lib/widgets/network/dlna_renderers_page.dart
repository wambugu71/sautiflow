import 'package:flutter_m3shapes_extended/flutter_m3shapes_extended.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';

import '../../database/preferences_store.dart';
import '../../services/app_theme_service.dart';
import '../../services/chromecast_service.dart';
import '../../services/dlna_renderer_service.dart';
import '../../services/dlna_service.dart';
import '../app_m3e_widgets.dart';

/// Mobile-first DLNA / UPnP speakers (renderers) and local cast receiver page.
class DlnaRenderersPage extends StatelessWidget {
  final bool showAppBar;

  const DlnaRenderersPage({super.key, this.showAppBar = true});

  @override
  Widget build(BuildContext context) {
    final body = AnimatedBuilder(
      animation: DlnaService.instance,
      builder: (context, _) {
        final dlna = DlnaService.instance;
        final renderers = dlna.mediaRenderers;

        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            _buildScanCard(context, dlna, renderers.length),
            const SizedBox(height: 12),
            _buildReceiverToggle(context),
            const SizedBox(height: 20),
            AppSectionHeader('Casting Targets (${renderers.length})'),
            const SizedBox(height: 6),
            if (renderers.isEmpty)
              _buildEmptyCard(
                context,
                dlna.isSearching
                    ? 'Searching Wi-Fi network for DLNA speakers & Smart TVs…'
                    : 'No DLNA speakers or Smart TVs found yet. Tap Scan above.',
              )
            else
              AppCardContainer(
                children: [
                  for (var i = 0; i < renderers.length; i++) ...[
                    if (i > 0) const M3EDivider(),
                    _buildRendererTile(context, dlna, renderers[i]),
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
          'DLNA Speakers',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: context.textPrimary,
                fontWeight: FontWeight.bold,
              ),
        ),
      ),
      body: body,
    );
  }

  Widget _buildScanCard(
    BuildContext context,
    DlnaService dlna,
    int rendererCount,
  ) {
    final primary = context.primaryColor;
    final textTheme = Theme.of(context).textTheme;
    final hasError = dlna.lastError != null && !dlna.isSearching;

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
                  Icons.wifi_tethering_rounded,
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
                      'Local SSDP Network Scan',
                      style: textTheme.titleMedium?.copyWith(
                        color: context.textPrimary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      dlna.isSearching
                          ? 'Searching Wi-Fi for DLNA hardware…'
                          : dlna.lastError ??
                              '$rendererCount speaker(s) • ${dlna.devices.length} total devices',
                      style: textTheme.bodySmall?.copyWith(
                        color: hasError ? Colors.orangeAccent : context.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: primary,
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: () {
                if (dlna.isSearching) {
                  dlna.stopSearch();
                } else {
                  dlna.startSearch();
                }
              },
              icon: Icon(
                dlna.isSearching ? Icons.stop_rounded : Icons.search_rounded,
                size: 18,
              ),
              label: Text(dlna.isSearching ? 'Stop scan' : 'Scan network'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReceiverToggle(BuildContext context) {
    final primary = context.primaryColor;
    final textTheme = Theme.of(context).textTheme;

    return ListenableBuilder(
      listenable: DlnaRendererService.instance,
      builder: (context, _) {
        final renderer = DlnaRendererService.instance;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: context.cardDark,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: renderer.isRunning
                  ? primary.withAlpha(90)
                  : context.outlineColor,
            ),
          ),
          child: Row(
            children: [
              Icon(
                Icons.speaker_rounded,
                color: renderer.isRunning ? primary : context.textMuted,
                size: 24,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Receive casts (act as DLNA speaker)',
                      style: textTheme.bodyMedium?.copyWith(
                        color: context.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      renderer.isRunning
                          ? 'Visible as "${renderer.friendlyName}"'
                          : 'Let phones, PCs and TVs cast audio here',
                      style: textTheme.bodySmall?.copyWith(
                        color: renderer.isRunning ? primary : context.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              Switch(
                value: renderer.isRunning,
                activeThumbColor: primary,
                onChanged: (v) async {
                  await PreferencesStore.instance
                      .setBool('dlna_receiver_enabled', v);
                  if (v) {
                    await DlnaRendererService.instance.start();
                  } else {
                    await DlnaRendererService.instance.stop();
                  }
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildRendererTile(
    BuildContext context,
    DlnaService dlna,
    dynamic r,
  ) {
    final primary = context.primaryColor;
    final isActive = dlna.activeRenderer?.id == r.id;
    final textTheme = Theme.of(context).textTheme;
    final hostLabel = Uri.tryParse(r.locationUrl)?.host ?? r.locationUrl;

    return Padding(
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
                  r.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.bodyLarge?.copyWith(
                    color: context.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  hostLabel,
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
          M3EButton(
            onPressed: () async {
              if (isActive) {
                try {
                  await dlna.stop();
                } catch (_) {}
                dlna.setActiveRenderer(null);
              } else {
                final messenger = ScaffoldMessenger.of(context);
                await ChromecastService.instance.disconnect();
                dlna.setActiveRenderer(r);
                if (!context.mounted) return;
                messenger.showSnackBar(
                  SnackBar(
                    content: Text('Set active casting device to ${r.name}'),
                  ),
                );
              }
            },
            child: Text(isActive ? 'Disconnect' : 'Connect'),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyCard(BuildContext context, String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: context.cardDark,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.outlineColor),
      ),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: context.textMuted,
            ),
      ),
    );
  }
}
