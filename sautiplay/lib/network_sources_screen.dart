import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_m3shapes_extended/flutter_m3shapes_extended.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'package:sautiflow/sautiflow.dart';

import 'isolate_player.dart';
import 'services/app_theme_service.dart';
import 'services/dlna_service.dart';
import 'services/ftp_service.dart';

class NetworkSourcesScreen extends StatefulWidget {
  final IsolateAudioPlayer player;
  final void Function(String filePath, String title, String artist)?
      onPlayNetworkFile;
  final void Function(List<dynamic> entries, dynamic config, int initialIndex)?
      onPlayFtpFolder;

  const NetworkSourcesScreen({
    super.key,
    required this.player,
    this.onPlayNetworkFile,
    this.onPlayFtpFolder,
  });

  @override
  State<NetworkSourcesScreen> createState() => _NetworkSourcesScreenState();
}

class _NetworkSourcesScreenState extends State<NetworkSourcesScreen>
    with SingleTickerProviderStateMixin {
  // Dynamic theme colors from BuildContext
  Color get _bgDark => context.bgDark;
  Color get _cardDark => context.cardDark;
  Color get _primary => context.primaryColor;
  Color get _textDark => context.textMuted;

  late TabController _tabController;

  // FTP State
  List<FtpConfig> _ftpConfigs = [];
  FtpConfig? _selectedFtpConfig;
  String _currentFtpPath = '/';
  List<FtpFileEntry> _ftpEntries = [];
  bool _isLoadingFtp = false;
  final List<String> _ftpPathHistory = ['/'];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadFtpConfigs();
    DlnaService.instance.addListener(_onDlnaStateChanged);
  }

  @override
  void dispose() {
    _tabController.dispose();
    DlnaService.instance.removeListener(_onDlnaStateChanged);
    super.dispose();
  }

  void _onDlnaStateChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _loadFtpConfigs() async {
    final configs = await FtpService.getSavedConfigs();
    if (!mounted) return;
    setState(() {
      _ftpConfigs = configs;
      if (_selectedFtpConfig != null) {
        final matches = configs.where((c) => c.id == _selectedFtpConfig!.id);
        if (matches.isNotEmpty) {
          _selectedFtpConfig = matches.first;
        } else {
          _selectedFtpConfig = configs.isNotEmpty ? configs.first : null;
        }
      } else if (configs.isNotEmpty) {
        _selectedFtpConfig = configs.first;
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

  bool _isAudioFile(String name) {
    final ext = name.split('.').last.toLowerCase();
    return ['mp3', 'wav', 'flac', 'aac', 'm4a', 'ogg'].contains(ext);
  }

  Future<void> _playFtpAudioFile(FtpFileEntry fileEntry) async {
    if (_selectedFtpConfig == null) return;

    if (widget.onPlayFtpFolder != null) {
      final audioEntries = _ftpEntries
          .where((e) => !e.isDirectory && _isAudioFile(e.name))
          .toList();
      final initialIndex =
          audioEntries.indexWhere((e) => e.path == fileEntry.path);
      widget.onPlayFtpFolder!(audioEntries, _selectedFtpConfig,
          initialIndex >= 0 ? initialIndex : 0);
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
      final tempDir = await getTemporaryDirectory();
      final cachePath = p.join(
        tempDir.path,
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
      debugPrint('[NetworkSources] Error playing FTP track: $e');
      messenger.showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgDark,
      appBar: AppBar(
        leading: M3EIconButton(
            icon: Icon(Icons.keyboard_arrow_down),
            onPressed: () => Navigator.of(context).pop()),
        backgroundColor: _bgDark,
        elevation: 0,
        title: const Text(
          'Network Sources (FTP & DLNA)',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: _primary,
          labelColor: _primary,
          unselectedLabelColor: _textDark,
          tabs: const [
            Tab(icon: Icon(Icons.folder_zip_rounded), text: 'FTP Remote'),
            Tab(icon: Icon(Icons.cast_connected_rounded), text: 'DLNA / UPnP'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildFtpTab(),
          _buildDlnaTab(),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // TAB 1: FTP Remote Explorer
  // ---------------------------------------------------------------------------

  Widget _buildFtpTab() {
    return Column(
      children: [
        // FTP Server Selector & Add Header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          color: _cardDark,
          child: Row(
            children: [
              Icon(Icons.dns_rounded, color: _primary),
              const SizedBox(width: 12),
              Expanded(
                child: _ftpConfigs.isEmpty
                    ? Text(
                        'No FTP servers configured',
                        style: TextStyle(color: _textDark),
                      )
                    : DropdownButtonHideUnderline(
                        child: DropdownButton<FtpConfig>(
                          value: _selectedFtpConfig,
                          dropdownColor: _cardDark,
                          isExpanded: true,
                          style: const TextStyle(
                              color: Colors.white, fontWeight: FontWeight.w600),
                          items: _ftpConfigs.map((c) {
                            return DropdownMenuItem(
                              value: c,
                              child: Text('${c.name} (${c.host})'),
                            );
                          }).toList(),
                          onChanged: (val) {
                            if (val != null) {
                              setState(() {
                                _selectedFtpConfig = val;
                                _ftpPathHistory.clear();
                                _ftpPathHistory.add(val.rootPath);
                              });
                              _loadFtpDirectory(val.rootPath);
                            }
                          },
                        ),
                      ),
              ),
              IconButton(
                icon: Icon(Icons.add_circle_outline_rounded, color: _primary),
                tooltip: 'Add FTP Server',
                onPressed: () => _showAddFtpDialog(),
              ),
              if (_selectedFtpConfig != null)
                IconButton(
                  icon: const Icon(Icons.delete_outline_rounded,
                      color: Colors.redAccent),
                  tooltip: 'Delete Server',
                  onPressed: () async {
                    await FtpService.deleteConfig(_selectedFtpConfig!.id);
                    _loadFtpConfigs();
                  },
                ),
            ],
          ),
        ),

        // Path Breadcrumb Navigation
        if (_selectedFtpConfig != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: Colors.black26,
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back_rounded,
                      color: Colors.white70, size: 20),
                  onPressed: _ftpPathHistory.length > 1 ? _navigateFtpUp : null,
                ),
                Expanded(
                  child: Text(
                    _currentFtpPath,
                    style: TextStyle(color: _textDark, fontFamily: 'monospace'),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.refresh_rounded, color: _primary, size: 20),
                  onPressed: () => _loadFtpDirectory(_currentFtpPath),
                ),
              ],
            ),
          ),

        // Directory Explorer List
        Expanded(
          child: _selectedFtpConfig == null
              ? _buildEmptyState(
                  icon: Icons.cloud_off_rounded,
                  title: 'No FTP Server Selected',
                  subtitle:
                      'Tap the "+" button above to connect your FTP music server.',
                )
              : _isLoadingFtp
                  ? Center(child: CircularProgressIndicator(color: _primary))
                  : _ftpEntries.isEmpty
                      ? _buildEmptyState(
                          icon: Icons.folder_open_rounded,
                          title: 'Directory is Empty',
                          subtitle:
                              'No compatible audio files found in this folder.',
                        )
                      : M3ECardList.builder(
                          itemCount: _ftpEntries.length,
                          itemBuilder: (context, index) {
                            final item = _ftpEntries[index];
                            if (item.isDirectory) {
                              return M3EListItem(
                                leading: M3EContainer(
                                  Shapes.pill,
                                  width: 40,
                                  height: 40,
                                  color: _primary.withAlpha(25),
                                  child: Center(
                                    child: Icon(Icons.folder_rounded,
                                        color: _primary, size: 20),
                                  ),
                                ),
                                headline: item.name,
                                trailing: Icon(Icons.chevron_right_rounded,
                                    color: _textDark, size: 20),
                                onTap: () => _navigateToFtpSubdir(item.path),
                              );
                            } else {
                              return M3EListItem(
                                leading: M3EContainer(
                                  Shapes.pill,
                                  width: 40,
                                  height: 40,
                                  color: Colors.amber.withAlpha(25),
                                  child: const Center(
                                    child: Icon(Icons.audiotrack_rounded,
                                        color: Colors.amber, size: 20),
                                  ),
                                ),
                                headline: item.name,
                                supportingText: _formatBytes(item.sizeBytes),
                                trailing: IconButton(
                                  icon: Icon(Icons.play_circle_fill_rounded,
                                      color: _primary, size: 32),
                                  onPressed: () => _playFtpAudioFile(item),
                                ),
                                onTap: () => _playFtpAudioFile(item),
                              );
                            }
                          },
                        ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // TAB 2: DLNA / UPnP Explorer & Casting
  // ---------------------------------------------------------------------------

  Widget _buildDlnaTab() {
    final dlna = DlnaService.instance;
    final servers = dlna.mediaServers;
    final renderers = dlna.mediaRenderers;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Scan Control Header
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: _cardDark,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.white.withAlpha(12)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _primary.withAlpha(30),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.wifi_tethering_rounded,
                      color: _primary, size: 28),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Local SSDP Network Scan',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        dlna.isSearching
                            ? 'Searching Wi-Fi network for DLNA hardware…'
                            : 'Found ${dlna.devices.length} total DLNA devices',
                        style: TextStyle(color: _textDark, fontSize: 13),
                      ),
                    ],
                  ),
                ),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _primary,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
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
                    color: Colors.white,
                  ),
                  label: Text(dlna.isSearching ? 'Stop' : 'Scan'),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Renderers Section (Casting targets)
          _buildSectionTitle(
              'CASTING TARGETS (MEDIA RENDERERS)', Icons.speaker_group_rounded),
          const SizedBox(height: 10),

          renderers.isEmpty
              ? _buildCardPlaceholder(
                  'No DLNA Speakers or Smart TVs found yet. Tap Scan to search local Wi-Fi.')
              : M3ECardList(
                  itemCount: renderers.length,
                  itemBuilder: (context, index) {
                    final r = renderers[index];
                    final isActive = dlna.activeRenderer?.id == r.id;
                    return M3EListItem(
                      leading: M3EContainer(
                        Shapes.pill,
                        width: 40,
                        height: 40,
                        color:
                            (isActive ? Colors.white : _primary).withAlpha(25),
                        child: Center(
                          child: Icon(
                            Icons.cast_rounded,
                            color: isActive ? Colors.white : _primary,
                            size: 20,
                          ),
                        ),
                      ),
                      headline: r.name,
                      supportingText: r.locationUrl,
                      trailing: M3EButton(
                        onPressed: () {
                          if (isActive) {
                            dlna.stop();
                          } else {
                            dlna.setActiveRenderer(r);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                  content: Text(
                                      'Set active casting device to ${r.name}')),
                            );
                          }
                        },
                        child: Text(isActive ? 'Disconnect' : 'Connect'),
                      ),
                    );
                  },
                ),

          const SizedBox(height: 24),

          // Servers Section
          _buildSectionTitle(
              'MEDIA SERVERS (NAS / PC LIBRARIES)', Icons.dns_rounded),
          const SizedBox(height: 10),

          servers.isEmpty
              ? _buildCardPlaceholder(
                  'No DLNA Media Servers detected on your local network.')
              : M3ECardList(
                  itemCount: servers.length,
                  itemBuilder: (context, index) {
                    final s = servers[index];
                    return M3EListItem(
                      leading: const M3EContainer(
                        Shapes.pill,
                        width: 40,
                        height: 40,
                        color: Color(0x19FFC107),
                        child: Center(
                          child: Icon(Icons.storage_rounded,
                              color: Colors.amber, size: 20),
                        ),
                      ),
                      headline: s.name,
                      supportingText: s.locationUrl,
                      trailing: Icon(Icons.chevron_right_rounded,
                          color: _textDark, size: 20),
                      onTap: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                              content: Text(
                                  'Connected to DLNA MediaServer ${s.name}')),
                        );
                      },
                    );
                  },
                ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Dialogs & Helpers
  // ---------------------------------------------------------------------------

  void _showAddFtpDialog() {
    final nameCtrl = TextEditingController(text: 'My Home FTP');
    final hostCtrl = TextEditingController();
    final portCtrl = TextEditingController(text: '21');
    final userCtrl = TextEditingController(text: 'anonymous');
    final passCtrl = TextEditingController();
    bool isSecure = false;

    M3EDialog.show<void>(
      context,
      dialog: M3EDialog(
        title: 'Add FTP Server',
        content: StatefulBuilder(
          builder: (context, setDlgState) {
            return SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameCtrl,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: 'Server Label',
                      labelStyle: TextStyle(color: _textDark),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: hostCtrl,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: 'Host / IP Address',
                      hintText: '192.168.1.100',
                      labelStyle: TextStyle(color: _textDark),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: portCtrl,
                          keyboardType: TextInputType.number,
                          style: const TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                            labelText: 'Port',
                            labelStyle: TextStyle(color: _textDark),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Row(
                        children: [
                          const Text('FTPS',
                              style:
                                  TextStyle(color: Colors.white, fontSize: 13)),
                          const SizedBox(width: 8),
                          M3ESwitch(
                            value: isSecure,
                            onChanged: (val) =>
                                setDlgState(() => isSecure = val),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: userCtrl,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: 'Username',
                      labelStyle: TextStyle(color: _textDark),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: passCtrl,
                    obscureText: true,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: 'Password',
                      labelStyle: TextStyle(color: _textDark),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
        actions: [
          M3EButton.text(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          M3EButton(
            onPressed: () async {
              if (hostCtrl.text.trim().isEmpty) return;
              final config = FtpConfig(
                id: DateTime.now().millisecondsSinceEpoch.toString(),
                name: nameCtrl.text.trim(),
                host: hostCtrl.text.trim(),
                port: int.tryParse(portCtrl.text.trim()) ?? 21,
                user: userCtrl.text.trim(),
                password: passCtrl.text,
                isSecure: isSecure,
              );

              final nav = Navigator.of(context);
              await FtpService.saveConfig(config);
              nav.pop();
              _loadFtpConfigs();
            },
            child: const Text('Save & Connect'),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, color: _primary, size: 18),
        const SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(
            color: _textDark,
            fontSize: 12,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
          ),
        ),
      ],
    );
  }

  Widget _buildCardPlaceholder(String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _cardDark,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withAlpha(8)),
      ),
      child: Text(
        message,
        style: TextStyle(color: _textDark, fontSize: 13),
        textAlign: TextAlign.center,
      ),
    );
  }

  Widget _buildEmptyState({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 64, color: _textDark.withAlpha(100)),
            const SizedBox(height: 16),
            Text(
              title,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: TextStyle(color: _textDark, fontSize: 14),
              textAlign: TextAlign.center,
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
    var num = bytes / (1 << (i * 10));
    return '${num.toStringAsFixed(1)} ${suffixes[i]}';
  }
}
