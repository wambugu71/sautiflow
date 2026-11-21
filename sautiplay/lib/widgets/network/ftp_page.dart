import 'dart:io';

import 'package:flutter_m3shapes_extended/flutter_m3shapes_extended.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sautiflow/sautiflow.dart';

import '../../isolate_player.dart';
import '../../services/app_theme_service.dart';
import '../../services/ftp_service.dart';
import '../m3e_modal_helpers.dart';

/// Mobile-first FTP / FTPS server browser with chip-based server switching,
/// scrollable breadcrumb navigation, confirmed deletion, and keyboard-safe
/// bottom-sheet server setup.
class FtpPage extends StatefulWidget {
  final IsolateAudioPlayer player;
  final void Function(String filePath, String title, String artist)?
      onPlayNetworkFile;
  final void Function(List<dynamic> entries, dynamic config, int initialIndex)?
      onPlayFtpFolder;
  final bool showAppBar;

  const FtpPage({
    super.key,
    required this.player,
    this.onPlayNetworkFile,
    this.onPlayFtpFolder,
    this.showAppBar = true,
  });

  @override
  State<FtpPage> createState() => _FtpPageState();
}

class _FtpPageState extends State<FtpPage> {
  List<FtpConfig> _ftpConfigs = [];
  FtpConfig? _selectedFtpConfig;
  String _currentFtpPath = '/';
  List<FtpFileEntry> _ftpEntries = [];
  bool _isLoadingFtp = false;
  final List<String> _ftpPathHistory = ['/'];
  final ScrollController _breadcrumbController = ScrollController();

  @override
  void initState() {
    super.initState();
    _loadFtpConfigs();
  }

  @override
  void dispose() {
    _breadcrumbController.dispose();
    super.dispose();
  }

  Future<void> _loadFtpConfigs() async {
    final configs = await FtpService.getSavedConfigs();
    if (!mounted) return;
    setState(() {
      _ftpConfigs = configs;
      if (_selectedFtpConfig != null) {
        final matches = configs.where((c) => c.id == _selectedFtpConfig!.id);
        _selectedFtpConfig = matches.isNotEmpty
            ? matches.first
            : (configs.isNotEmpty ? configs.first : null);
      } else if (configs.isNotEmpty) {
        _selectedFtpConfig = configs.first;
      }
      if (_selectedFtpConfig != null) {
        _currentFtpPath = _selectedFtpConfig!.rootPath;
        _ftpPathHistory
          ..clear()
          ..add(_currentFtpPath);
      }
    });
    if (_selectedFtpConfig != null) {
      _loadFtpDirectory(_currentFtpPath);
    }
  }

  Future<void> _loadFtpDirectory(String path) async {
    if (_selectedFtpConfig == null) return;
    setState(() {
      _isLoadingFtp = true;
      _currentFtpPath = path;
    });

    final entries = await FtpService.listDirectory(
      _selectedFtpConfig!,
      dirPath: path,
    );

    if (!mounted) return;
    setState(() {
      _ftpEntries = entries;
      _isLoadingFtp = false;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_breadcrumbController.hasClients) {
        _breadcrumbController.animateTo(
          _breadcrumbController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _navigateToFtpSubdir(String path) {
    _ftpPathHistory.add(path);
    _loadFtpDirectory(path);
  }

  void _navigateFtpUp() {
    if (_ftpPathHistory.length > 1) {
      _ftpPathHistory.removeLast();
      _loadFtpDirectory(_ftpPathHistory.last);
    }
  }

  void _jumpToHistoryIndex(int index) {
    if (index < 0 || index >= _ftpPathHistory.length) return;
    final target = _ftpPathHistory[index];
    _ftpPathHistory.removeRange(index + 1, _ftpPathHistory.length);
    _loadFtpDirectory(target);
  }

  Future<void> _playFtpAudioFile(FtpFileEntry fileEntry) async {
    if (_selectedFtpConfig == null) return;

    if (widget.onPlayFtpFolder != null) {
      final audioEntries = _ftpEntries
          .where((e) => !e.isDirectory && e.isAudioFile)
          .toList();
      final initialIndex =
          audioEntries.indexWhere((e) => e.path == fileEntry.path);
      widget.onPlayFtpFolder!(
        audioEntries,
        _selectedFtpConfig,
        initialIndex >= 0 ? initialIndex : 0,
      );
      return;
    }

    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      SnackBar(
        content: Text('Downloading ${fileEntry.name} from FTP…'),
        duration: const Duration(seconds: 2),
      ),
    );

    try {
      final supportDir = await getApplicationSupportDirectory();
      final cachePath = p.join(
        supportDir.path,
        'ftp_cache',
        _selectedFtpConfig!.id,
        fileEntry.name,
      );
      final localFile = File(cachePath);

      final success = await FtpService.downloadFile(
        _selectedFtpConfig!,
        fileEntry.path,
        localFile,
      );

      if (success && localFile.existsSync()) {
        if (mounted) {
          Navigator.of(context).popUntil((route) => route.isFirst);
        }
        if (widget.onPlayNetworkFile != null) {
          widget.onPlayNetworkFile!(
            localFile.path,
            fileEntry.name,
            _selectedFtpConfig!.name,
          );
        } else {
          widget.player.load(AudioSource.file(localFile.path));
          widget.player.play();
        }

        messenger.showSnackBar(
          SnackBar(
            content: Text('Playing ${fileEntry.name}'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Failed to download audio file from FTP server'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } catch (e) {
      debugPrint('[FtpPage] Error playing FTP track: $e');
      messenger.showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  Future<void> _confirmDeleteSelectedServer() async {
    final config = _selectedFtpConfig;
    if (config == null) return;

    final confirmed = await showSautiM3EDialog<bool>(
      context,
      dialog: M3EDialog(
        title: 'Delete FTP Server?',
        content: Text(
          'Remove "${config.name}" (${config.host}) from saved servers?',
          style: TextStyle(color: context.textMuted),
        ),
        actions: [
          M3EButton.text(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          M3EButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await FtpService.deleteConfig(config.id);
      _selectedFtpConfig = null;
      await _loadFtpConfigs();
    }
  }

  void _showAddFtpSheet() {
    final nameCtrl = TextEditingController(text: 'My Home FTP');
    final hostCtrl = TextEditingController();
    final portCtrl = TextEditingController(text: '21');
    final userCtrl = TextEditingController(text: 'anonymous');
    final passCtrl = TextEditingController();
    bool isSecure = false;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: context.cardDark,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetCtx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            final bottomInset = MediaQuery.viewInsetsOf(ctx).bottom;
            final textTheme = Theme.of(ctx).textTheme;

            return Padding(
              padding: EdgeInsets.fromLTRB(20, 16, 20, 20 + bottomInset),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Add FTP Server',
                            style: textTheme.titleLarge?.copyWith(
                              color: ctx.textPrimary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: Icon(Icons.close_rounded, color: ctx.textMuted),
                          onPressed: () => Navigator.of(ctx).pop(),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: nameCtrl,
                      style: TextStyle(color: ctx.textPrimary),
                      decoration: InputDecoration(
                        labelText: 'Server Label',
                        labelStyle: TextStyle(color: ctx.textMuted),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: hostCtrl,
                      style: TextStyle(color: ctx.textPrimary),
                      decoration: InputDecoration(
                        labelText: 'Host / IP Address',
                        hintText: '192.168.1.100',
                        labelStyle: TextStyle(color: ctx.textMuted),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: portCtrl,
                      keyboardType: TextInputType.number,
                      style: TextStyle(color: ctx.textPrimary),
                      decoration: InputDecoration(
                        labelText: 'Port',
                        labelStyle: TextStyle(color: ctx.textMuted),
                      ),
                    ),
                    const SizedBox(height: 10),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        'Use FTPS (TLS)',
                        style: TextStyle(color: ctx.textPrimary),
                      ),
                      subtitle: Text(
                        'Encrypt credentials and directory traffic',
                        style: TextStyle(color: ctx.textMuted, fontSize: 12),
                      ),
                      value: isSecure,
                      activeThumbColor: ctx.primaryColor,
                      onChanged: (val) => setSheetState(() => isSecure = val),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: userCtrl,
                      style: TextStyle(color: ctx.textPrimary),
                      decoration: InputDecoration(
                        labelText: 'Username',
                        labelStyle: TextStyle(color: ctx.textMuted),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: passCtrl,
                      obscureText: true,
                      style: TextStyle(color: ctx.textPrimary),
                      decoration: InputDecoration(
                        labelText: 'Password',
                        labelStyle: TextStyle(color: ctx.textMuted),
                      ),
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: ctx.primaryColor,
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        onPressed: () async {
                          if (hostCtrl.text.trim().isEmpty) return;
                          final config = FtpConfig(
                            id: DateTime.now()
                                .millisecondsSinceEpoch
                                .toString(),
                            name: nameCtrl.text.trim().isEmpty
                                ? hostCtrl.text.trim()
                                : nameCtrl.text.trim(),
                            host: hostCtrl.text.trim(),
                            port: int.tryParse(portCtrl.text.trim()) ?? 21,
                            user: userCtrl.text.trim(),
                            password: passCtrl.text,
                            isSecure: isSecure,
                          );
                          final nav = Navigator.of(ctx);
                          await FtpService.saveConfig(config);
                          nav.pop();
                          await _loadFtpConfigs();
                        },
                        child: const Text('Save & Connect'),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    ).whenComplete(() {
      nameCtrl.dispose();
      hostCtrl.dispose();
      portCtrl.dispose();
      userCtrl.dispose();
      passCtrl.dispose();
    });
  }

  @override
  Widget build(BuildContext context) {
    final primary = context.primaryColor;

    final body = Column(
      children: [
        _buildServerChipBar(context),
        if (_selectedFtpConfig != null) _buildBreadcrumbBar(context),
        Expanded(child: _buildExplorerBody(context)),
      ],
    );

    if (!widget.showAppBar) {
      return Stack(
        children: [
          body,
          Positioned(
            right: 16,
            bottom: 16,
            child: FloatingActionButton.extended(
              heroTag: 'ftp_add_fab_embedded',
              backgroundColor: primary,
              foregroundColor: Colors.black,
              onPressed: _showAddFtpSheet,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add server'),
            ),
          ),
        ],
      );
    }

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
          'FTP / FTPS',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: context.textPrimary,
                fontWeight: FontWeight.bold,
              ),
        ),
        actions: [
          if (_selectedFtpConfig != null)
            IconButton(
              icon: const Icon(
                Icons.delete_outline_rounded,
                color: Colors.redAccent,
              ),
              tooltip: 'Delete selected server',
              onPressed: _confirmDeleteSelectedServer,
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'ftp_add_fab',
        backgroundColor: primary,
        foregroundColor: Colors.black,
        onPressed: _showAddFtpSheet,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add server'),
      ),
      body: body,
    );
  }

  Widget _buildServerChipBar(BuildContext context) {
    final primary = context.primaryColor;

    return Container(
      width: double.infinity,
      color: context.cardDark,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final config in _ftpConfigs) ...[
              ChoiceChip(
                label: Text('${config.name} (${config.host})'),
                selected: _selectedFtpConfig?.id == config.id,
                selectedColor: primary.withAlpha(45),
                labelStyle: TextStyle(
                  color: _selectedFtpConfig?.id == config.id
                      ? primary
                      : context.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
                onSelected: (_) {
                  setState(() {
                    _selectedFtpConfig = config;
                    _ftpPathHistory
                      ..clear()
                      ..add(config.rootPath);
                  });
                  _loadFtpDirectory(config.rootPath);
                },
              ),
              const SizedBox(width: 8),
            ],
            ActionChip(
              avatar: Icon(Icons.add_rounded, size: 18, color: primary),
              label: Text(
                'Add',
                style: TextStyle(color: primary, fontWeight: FontWeight.w600),
              ),
              onPressed: _showAddFtpSheet,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBreadcrumbBar(BuildContext context) {
    final primary = context.primaryColor;

    return Container(
      color: context.bgDark.withAlpha(180),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          IconButton(
            icon: Icon(
              Icons.arrow_back_rounded,
              color: _ftpPathHistory.length > 1
                  ? context.textPrimary
                  : context.textMuted.withAlpha(100),
              size: 20,
            ),
            onPressed: _ftpPathHistory.length > 1 ? _navigateFtpUp : null,
          ),
          Expanded(
            child: SingleChildScrollView(
              controller: _breadcrumbController,
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (var i = 0; i < _ftpPathHistory.length; i++) ...[
                    if (i > 0)
                      Icon(
                        Icons.chevron_right_rounded,
                        size: 16,
                        color: context.textMuted,
                      ),
                    TextButton(
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      onPressed: i == _ftpPathHistory.length - 1
                          ? null
                          : () => _jumpToHistoryIndex(i),
                      child: Text(
                        _segmentLabel(_ftpPathHistory[i]),
                        style: TextStyle(
                          color: i == _ftpPathHistory.length - 1
                              ? primary
                              : context.textMuted,
                          fontFamily: 'monospace',
                          fontWeight: i == _ftpPathHistory.length - 1
                              ? FontWeight.w700
                              : FontWeight.normal,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          IconButton(
            icon: Icon(Icons.refresh_rounded, color: primary, size: 20),
            onPressed: () => _loadFtpDirectory(_currentFtpPath),
          ),
        ],
      ),
    );
  }

  String _segmentLabel(String path) {
    if (path == '/' || path.isEmpty) return 'root';
    final parts = path.split('/').where((s) => s.isNotEmpty).toList();
    return parts.isEmpty ? 'root' : parts.last;
  }

  Widget _buildExplorerBody(BuildContext context) {
    final primary = context.primaryColor;

    if (_selectedFtpConfig == null) {
      return _buildEmptyState(
        context,
        icon: Icons.cloud_off_rounded,
        title: 'No FTP Server Selected',
        subtitle: 'Tap "Add server" to connect your FTP or FTPS music server.',
      );
    }

    if (_isLoadingFtp) {
      return Center(child: CircularProgressIndicator(color: primary));
    }

    if (_ftpEntries.isEmpty) {
      return _buildEmptyState(
        context,
        icon: Icons.folder_open_rounded,
        title: 'Directory is Empty',
        subtitle: 'No compatible audio files found in this folder.',
      );
    }

    return M3EList.scrollable(
      itemCount: _ftpEntries.length,
      itemBuilder: (context, index) {
        final item = _ftpEntries[index];
        if (item.isDirectory) {
          return M3EListItem(
            leading: M3EContainer(
              Shapes.pill,
              width: 40,
              height: 40,
              color: primary.withAlpha(25),
              child: Center(
                child: Icon(Icons.folder_rounded, color: primary, size: 20),
              ),
            ),
            headline: item.name,
            trailing: Icon(
              Icons.chevron_right_rounded,
              color: context.textMuted,
              size: 20,
            ),
            onTap: () => _navigateToFtpSubdir(item.path),
          );
        }

        return M3EListItem(
          leading: M3EContainer(
            Shapes.pill,
            width: 40,
            height: 40,
            color: Colors.amber.withAlpha(25),
            child: const Center(
              child: Icon(
                Icons.audiotrack_rounded,
                color: Colors.amber,
                size: 20,
              ),
            ),
          ),
          headline: item.name,
          supportingText: _formatBytes(item.sizeBytes),
          trailing: IconButton(
            icon: Icon(
              Icons.play_circle_fill_rounded,
              color: primary,
              size: 32,
            ),
            onPressed: () => _playFtpAudioFile(item),
          ),
          onTap: () => _playFtpAudioFile(item),
        );
      },
    );
  }

  Widget _buildEmptyState(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    final textTheme = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 56, color: context.textMuted.withAlpha(110)),
            const SizedBox(height: 14),
            Text(
              title,
              style: textTheme.titleMedium?.copyWith(
                color: context.textPrimary,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: textTheme.bodyMedium?.copyWith(color: context.textMuted),
            ),
          ],
        ),
      ),
    );
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
    var i = (bytes.toString().length - 1) ~/ 3;
    if (i >= suffixes.length) i = suffixes.length - 1;
    final num = bytes / (1 << (i * 10));
    return '${num.toStringAsFixed(1)} ${suffixes[i]}';
  }
}
