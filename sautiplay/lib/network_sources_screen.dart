import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';

import 'database/preferences_store.dart';
import 'isolate_player.dart';
import 'services/app_theme_service.dart';
import 'services/chromecast_service.dart';
import 'services/dlna_renderer_service.dart';
import 'services/dlna_service.dart';
import 'services/ftp_service.dart';
import 'services/sftp_service.dart';
import 'services/smb_service.dart';
import 'services/subsonic_service.dart';
import 'services/webdav_service.dart';
import 'widgets/app_m3e_widgets.dart';
import 'widgets/cast_output_sheet.dart';
import 'widgets/network/chromecast_page.dart';
import 'widgets/network/dlna_renderers_page.dart';
import 'widgets/network/dlna_servers_page.dart';
import 'widgets/network/ftp_page.dart';
import 'widgets/network/remote_browser_tab.dart';
import 'widgets/network/subsonic_tab.dart';

enum _NetworkDestination {
  chromecast,
  dlnaRenderers,
  navidrome,
  smb,
  webdav,
  sftp,
  ftp,
  dlnaServers,
}

class NetworkSourcesScreen extends StatefulWidget {
  final IsolateAudioPlayer player;
  final void Function(String filePath, String title, String artist)?
      onPlayNetworkFile;
  final void Function(List<dynamic> entries, dynamic config, int initialIndex)?
      onPlayFtpFolder;
  final PlayRemoteQueueCallback? onPlayRemoteQueue;

  const NetworkSourcesScreen({
    super.key,
    required this.player,
    this.onPlayNetworkFile,
    this.onPlayFtpFolder,
    this.onPlayRemoteQueue,
  });

  @override
  State<NetworkSourcesScreen> createState() => _NetworkSourcesScreenState();
}

class _NetworkSourcesScreenState extends State<NetworkSourcesScreen> {
  _NetworkDestination _selectedPane = _NetworkDestination.chromecast;

  int _subsonicCount = 0;
  String? _subsonicPrimaryHost;
  int _smbCount = 0;
  int _webdavCount = 0;
  int _sftpCount = 0;
  int _ftpCount = 0;

  @override
  void initState() {
    super.initState();
    _loadSourceCounts();
    DlnaService.instance.addListener(_onServiceStateChanged);
    ChromecastService.instance.addListener(_onServiceStateChanged);
    DlnaRendererService.instance.addListener(_onServiceStateChanged);
  }

  @override
  void dispose() {
    DlnaService.instance.removeListener(_onServiceStateChanged);
    ChromecastService.instance.removeListener(_onServiceStateChanged);
    DlnaRendererService.instance.removeListener(_onServiceStateChanged);
    super.dispose();
  }

  void _onServiceStateChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _loadSourceCounts() async {
    final results = await Future.wait([
      SubsonicService.getSavedConfigs(),
      SmbService.getSavedConfigs(),
      WebDavService.getSavedConfigs(),
      SftpService.getSavedConfigs(),
      FtpService.getSavedConfigs(),
    ]);

    if (!mounted) return;
    final subsonic = results[0] as List<SubsonicConfig>;
    setState(() {
      _subsonicCount = subsonic.length;
      _subsonicPrimaryHost = subsonic.isNotEmpty
          ? (Uri.tryParse(subsonic.first.normalizedBaseUrl)?.host ??
              subsonic.first.name)
          : null;
      _smbCount = results[1].length;
      _webdavCount = results[2].length;
      _sftpCount = results[3].length;
      _ftpCount = results[4].length;
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isExpanded = constraints.maxWidth >= 840;

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
              'Local & Network',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: context.textPrimary,
                    fontWeight: FontWeight.bold,
                  ),
            ),
          ),
          body: isExpanded
              ? Row(
                  children: [
                    SizedBox(
                      width: 360,
                      child: _buildHubList(context, isExpanded: true),
                    ),
                    VerticalDivider(width: 1, color: context.outlineColor),
                    Expanded(child: _buildDetailPane(context)),
                  ],
                )
              : _buildHubList(context, isExpanded: false),
        );
      },
    );
  }

  Widget _buildHubList(BuildContext context, {required bool isExpanded}) {
    final cast = ChromecastService.instance;
    final dlna = DlnaService.instance;
    final renderer = DlnaRendererService.instance;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        if (cast.activeDevice != null || dlna.activeRenderer != null) ...[
          _buildNowCastingBanner(context, cast, dlna),
          const SizedBox(height: 16),
        ],
        const AppSectionHeader('Play to'),
        AppCardContainer(
          children: [
            _buildHubTile(
              context,
              title: 'Chromecast',
              subtitle: _chromecastSummary(cast),
              icon: Icons.cast_rounded,
              selected:
                  isExpanded && _selectedPane == _NetworkDestination.chromecast,
              onTap: () =>
                  _openDestination(_NetworkDestination.chromecast, isExpanded),
            ),
            const M3EDivider(),
            _buildHubTile(
              context,
              title: 'DLNA speakers',
              subtitle: _dlnaRendererSummary(dlna),
              icon: Icons.cast_connected_rounded,
              selected: isExpanded &&
                  _selectedPane == _NetworkDestination.dlnaRenderers,
              onTap: () => _openDestination(
                  _NetworkDestination.dlnaRenderers, isExpanded),
            ),
            const M3EDivider(),
            AppSettingsTile(
              title: 'Receive casts',
              subtitle: renderer.isRunning
                  ? 'Visible as "${renderer.friendlyName}"'
                  : 'Act as a DLNA speaker on Wi-Fi',
              leading: _buildIconBadge(
                context,
                Icons.speaker_rounded,
                active: renderer.isRunning,
              ),
              trailing: Switch(
                value: renderer.isRunning,
                activeThumbColor: context.primaryColor,
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
            ),
            const M3EDivider(),
            _buildHubTile(
              context,
              title: 'Cast quality',
              subtitle: _castQualitySummary(cast),
              icon: Icons.high_quality_rounded,
              selected: false,
              onTap: () => _showCastQualitySheet(context),
            ),
          ],
        ),
        const SizedBox(height: 16),
        const AppSectionHeader('Browse'),
        AppCardContainer(
          children: [
            _buildHubTile(
              context,
              title: 'Navidrome',
              subtitle: _subsonicCount == 0
                  ? 'Not set up'
                  : _subsonicCount == 1 && _subsonicPrimaryHost != null
                      ? _subsonicPrimaryHost!
                      : '$_subsonicCount servers',
              icon: Icons.album_rounded,
              selected:
                  isExpanded && _selectedPane == _NetworkDestination.navidrome,
              onTap: () =>
                  _openDestination(_NetworkDestination.navidrome, isExpanded),
            ),
            const M3EDivider(),
            _buildHubTile(
              context,
              title: 'SMB / NAS',
              subtitle: _countLabel(_smbCount, 'share', 'shares'),
              icon: Icons.storage_rounded,
              selected: isExpanded && _selectedPane == _NetworkDestination.smb,
              onTap: () => _openDestination(_NetworkDestination.smb, isExpanded),
            ),
            const M3EDivider(),
            _buildHubTile(
              context,
              title: 'WebDAV',
              subtitle: _countLabel(_webdavCount, 'server', 'servers'),
              icon: Icons.cloud_queue_rounded,
              selected:
                  isExpanded && _selectedPane == _NetworkDestination.webdav,
              onTap: () =>
                  _openDestination(_NetworkDestination.webdav, isExpanded),
            ),
            const M3EDivider(),
            _buildHubTile(
              context,
              title: 'SFTP',
              subtitle: _countLabel(_sftpCount, 'server', 'servers'),
              icon: Icons.lock_outline_rounded,
              selected: isExpanded && _selectedPane == _NetworkDestination.sftp,
              onTap: () =>
                  _openDestination(_NetworkDestination.sftp, isExpanded),
            ),
            const M3EDivider(),
            _buildHubTile(
              context,
              title: 'FTP / FTPS',
              subtitle: _countLabel(_ftpCount, 'server', 'servers'),
              icon: Icons.folder_zip_rounded,
              selected: isExpanded && _selectedPane == _NetworkDestination.ftp,
              onTap: () => _openDestination(_NetworkDestination.ftp, isExpanded),
            ),
            const M3EDivider(),
            _buildHubTile(
              context,
              title: 'DLNA media servers',
              subtitle: dlna.isSearching
                  ? 'Scanning network…'
                  : dlna.mediaServers.isEmpty
                      ? 'Tap to scan'
                      : '${dlna.mediaServers.length} on network',
              icon: Icons.dns_rounded,
              selected: isExpanded &&
                  _selectedPane == _NetworkDestination.dlnaServers,
              onTap: () =>
                  _openDestination(_NetworkDestination.dlnaServers, isExpanded),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildNowCastingBanner(
    BuildContext context,
    ChromecastService cast,
    DlnaService dlna,
  ) {
    final primary = context.primaryColor;
    final textTheme = Theme.of(context).textTheme;
    final isCast = cast.activeDevice != null;
    final deviceName = isCast
        ? cast.activeDevice!.friendlyName
        : dlna.activeRenderer!.name;
    final modeText = isCast
        ? (cast.isStreamingLiveTap ? '24-bit WAV Tap' : 'Pass-Through')
        : 'DLNA';

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
                  deviceName,
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
                text: modeText,
                color: primary,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              ),
            ],
          ),
          if (isCast) ...[
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
          ] else
            const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: M3EButton.tonal(
              onPressed: () async {
                if (isCast) {
                  await cast.disconnect();
                } else {
                  try {
                    await dlna.stop();
                  } catch (_) {}
                  dlna.setActiveRenderer(null);
                }
              },
              child: const Text('Disconnect'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHubTile(
    BuildContext context, {
    required String title,
    required String subtitle,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final primary = context.primaryColor;
    return Container(
      decoration: selected
          ? BoxDecoration(
              color: primary.withAlpha(24),
              borderRadius: BorderRadius.circular(12),
            )
          : null,
      child: AppSettingsTile(
        title: title,
        subtitle: subtitle,
        leading: _buildIconBadge(context, icon, active: selected),
        trailing: Icon(
          Icons.chevron_right_rounded,
          color: selected ? primary : context.textMuted,
          size: 20,
        ),
        onTap: onTap,
      ),
    );
  }

  Widget _buildIconBadge(
    BuildContext context,
    IconData icon, {
    bool active = false,
  }) {
    final primary = context.primaryColor;
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: primary.withAlpha(active ? 40 : 22),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(icon, color: primary, size: 20),
    );
  }

  void _openDestination(_NetworkDestination dest, bool isExpanded) async {
    if (isExpanded) {
      setState(() => _selectedPane = dest);
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (ctx) => _buildFullScreenPage(ctx, dest),
      ),
    );
    _loadSourceCounts();
  }

  Widget _buildFullScreenPage(BuildContext context, _NetworkDestination dest) {
    switch (dest) {
      case _NetworkDestination.chromecast:
        return const ChromecastPage();
      case _NetworkDestination.dlnaRenderers:
        return const DlnaRenderersPage();
      case _NetworkDestination.dlnaServers:
        return const DlnaServersPage();
      case _NetworkDestination.ftp:
        return FtpPage(
          player: widget.player,
          onPlayNetworkFile: widget.onPlayNetworkFile,
          onPlayFtpFolder: widget.onPlayFtpFolder,
        );
      case _NetworkDestination.navidrome:
        return _wrapTabInScaffold(
          context,
          title: 'Navidrome / Subsonic',
          child: SubsonicTab(onPlayQueue: widget.onPlayRemoteQueue),
        );
      case _NetworkDestination.smb:
        return _wrapTabInScaffold(
          context,
          title: 'SMB / NAS',
          child: RemoteBrowserTab(
            protocol: RemoteProtocolKind.smb,
            onPlayQueue: widget.onPlayRemoteQueue,
          ),
        );
      case _NetworkDestination.webdav:
        return _wrapTabInScaffold(
          context,
          title: 'WebDAV',
          child: RemoteBrowserTab(
            protocol: RemoteProtocolKind.webdav,
            onPlayQueue: widget.onPlayRemoteQueue,
          ),
        );
      case _NetworkDestination.sftp:
        return _wrapTabInScaffold(
          context,
          title: 'SFTP',
          child: RemoteBrowserTab(
            protocol: RemoteProtocolKind.sftp,
            onPlayQueue: widget.onPlayRemoteQueue,
          ),
        );
    }
  }

  Widget _buildDetailPane(BuildContext context) {
    switch (_selectedPane) {
      case _NetworkDestination.chromecast:
        return const ChromecastPage(showAppBar: false);
      case _NetworkDestination.dlnaRenderers:
        return const DlnaRenderersPage(showAppBar: false);
      case _NetworkDestination.dlnaServers:
        return const DlnaServersPage(showAppBar: false);
      case _NetworkDestination.ftp:
        return FtpPage(
          player: widget.player,
          onPlayNetworkFile: widget.onPlayNetworkFile,
          onPlayFtpFolder: widget.onPlayFtpFolder,
          showAppBar: false,
        );
      case _NetworkDestination.navidrome:
        return SubsonicTab(onPlayQueue: widget.onPlayRemoteQueue);
      case _NetworkDestination.smb:
        return RemoteBrowserTab(
          protocol: RemoteProtocolKind.smb,
          onPlayQueue: widget.onPlayRemoteQueue,
        );
      case _NetworkDestination.webdav:
        return RemoteBrowserTab(
          protocol: RemoteProtocolKind.webdav,
          onPlayQueue: widget.onPlayRemoteQueue,
        );
      case _NetworkDestination.sftp:
        return RemoteBrowserTab(
          protocol: RemoteProtocolKind.sftp,
          onPlayQueue: widget.onPlayRemoteQueue,
        );
    }
  }

  Widget _wrapTabInScaffold(
    BuildContext context, {
    required String title,
    required Widget child,
  }) {
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
          title,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: context.textPrimary,
                fontWeight: FontWeight.bold,
              ),
        ),
      ),
      body: child,
    );
  }

  void _showCastQualitySheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: context.cardDark,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetCtx) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Cast Audio Quality',
                      style: Theme.of(sheetCtx).textTheme.titleLarge?.copyWith(
                            color: sheetCtx.textPrimary,
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close_rounded, color: sheetCtx.textMuted),
                    onPressed: () => Navigator.of(sheetCtx).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const CastModeAndRateCard(),
            ],
          ),
        );
      },
    );
  }

  String _chromecastSummary(ChromecastService cast) {
    if (cast.activeDevice != null) {
      return 'Connected • ${cast.activeDevice!.friendlyName}';
    }
    if (cast.isScanning) return 'Scanning network…';
    if (cast.devices.isEmpty) return 'Tap to scan or add IP';
    return '${cast.devices.length} found • 24-bit/${cast.maxSampleRate.label}';
  }

  String _dlnaRendererSummary(DlnaService dlna) {
    if (dlna.activeRenderer != null) {
      return 'Connected • ${dlna.activeRenderer!.name}';
    }
    if (dlna.isSearching) return 'Scanning network…';
    final count = dlna.mediaRenderers.length;
    if (count == 0) return 'Tap to scan';
    return '$count found';
  }

  String _castQualitySummary(ChromecastService cast) {
    final mode = cast.audioMode == CastAudioMode.bitPerfect
        ? 'Bit-Perfect'
        : 'With DSP';
    return '$mode • up to ${cast.maxSampleRate.label}';
  }

  String _countLabel(int count, String singular, String plural) {
    if (count == 0) return 'Not set up';
    return '$count ${count == 1 ? singular : plural}';
  }
}
