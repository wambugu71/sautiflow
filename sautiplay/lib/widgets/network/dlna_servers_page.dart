import 'package:flutter_m3shapes_extended/flutter_m3shapes_extended.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';

import '../../services/app_theme_service.dart';
import '../../services/dlna_service.dart';
import '../app_m3e_widgets.dart';

/// Mobile-first DLNA / UPnP media servers discovery page.
class DlnaServersPage extends StatelessWidget {
  final bool showAppBar;

  const DlnaServersPage({super.key, this.showAppBar = true});

  @override
  Widget build(BuildContext context) {
    final body = AnimatedBuilder(
      animation: DlnaService.instance,
      builder: (context, _) {
        final dlna = DlnaService.instance;
        final servers = dlna.mediaServers;
        final primary = context.primaryColor;
        final textTheme = Theme.of(context).textTheme;

        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            Container(
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
                          Icons.dns_rounded,
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
                              'DLNA / UPnP Media Servers',
                              style: textTheme.titleMedium?.copyWith(
                                color: context.textPrimary,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              dlna.isSearching
                                  ? 'Searching local network…'
                                  : '${servers.length} media server(s) found',
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
                        dlna.isSearching
                            ? Icons.stop_rounded
                            : Icons.search_rounded,
                        size: 18,
                      ),
                      label: Text(
                        dlna.isSearching ? 'Stop scan' : 'Scan network',
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            AppSectionHeader('Detected Libraries (${servers.length})'),
            const SizedBox(height: 6),
            if (servers.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: context.cardDark,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: context.outlineColor),
                ),
                child: Text(
                  dlna.isSearching
                      ? 'Scanning local Wi-Fi for DLNA media servers…'
                      : 'No DLNA media servers detected on your local network.',
                  textAlign: TextAlign.center,
                  style: textTheme.bodyMedium?.copyWith(
                    color: context.textMuted,
                  ),
                ),
              )
            else
              AppCardContainer(
                children: [
                  for (var i = 0; i < servers.length; i++) ...[
                    if (i > 0) const M3EDivider(),
                    _buildServerTile(context, servers[i], textTheme),
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
          'DLNA Media Servers',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: context.textPrimary,
                fontWeight: FontWeight.bold,
              ),
        ),
      ),
      body: body,
    );
  }

  Widget _buildServerTile(
    BuildContext context,
    dynamic s,
    TextTheme textTheme,
  ) {
    final hostLabel = Uri.tryParse(s.locationUrl)?.host ?? s.locationUrl;

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Selected DLNA MediaServer ${s.name}')),
        );
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            const M3EContainer(
              Shapes.pill,
              width: 40,
              height: 40,
              color: Color(0x19FFC107),
              child: Center(
                child: Icon(
                  Icons.storage_rounded,
                  color: Colors.amber,
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
                    s.name,
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
            Icon(Icons.chevron_right_rounded, color: context.textMuted),
          ],
        ),
      ),
    );
  }
}
