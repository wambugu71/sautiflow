import 'package:material_ui/material_ui.dart';
import 'package:sautiflow/sautiflow.dart';

import '../../album_detail_screen.dart' show TrackInfo;
import '../../services/app_theme_service.dart';
import '../../services/local_media_server.dart';
import '../../services/remote_file_entry.dart';
import '../../services/remote_stream_relay.dart';
import '../../services/sftp_service.dart';
import '../../services/smb_service.dart';
import '../../services/webdav_service.dart';
import 'subsonic_tab.dart' show PlayRemoteQueueCallback;

enum RemoteProtocolKind { smb, webdav, sftp }

class RemoteBrowserTab extends StatefulWidget {
  final RemoteProtocolKind protocol;
  final PlayRemoteQueueCallback? onPlayQueue;

  const RemoteBrowserTab({
    super.key,
    required this.protocol,
    this.onPlayQueue,
  });

  @override
  State<RemoteBrowserTab> createState() => _RemoteBrowserTabState();
}

class _RemoteBrowserTabState extends State<RemoteBrowserTab> {
  List<dynamic> _configs = [];
  dynamic _selectedConfig;

  String _currentPath = '/';
  final List<String> _pathHistory = ['/'];
  List<RemoteFileEntry> _entries = [];
  bool _isLoading = false;
  bool _isStartingPlayback = false;
  String? _error;

  Color get _cardDark => context.cardDark;
  Color get _primary => context.primaryColor;
  Color get _textMuted => context.textMuted;

  String get _protocolTitle {
    switch (widget.protocol) {
      case RemoteProtocolKind.smb:
        return 'SMB / NAS Share';
      case RemoteProtocolKind.webdav:
        return 'WebDAV Server';
      case RemoteProtocolKind.sftp:
        return 'SFTP (SSH) Server';
    }
  }

  IconData get _protocolIcon {
    switch (widget.protocol) {
      case RemoteProtocolKind.smb:
        return Icons.storage_rounded;
      case RemoteProtocolKind.webdav:
        return Icons.cloud_queue_rounded;
      case RemoteProtocolKind.sftp:
        return Icons.lock_outline_rounded;
    }
  }

  @override
  void initState() {
    super.initState();
    _loadConfigs();
  }

  Future<void> _loadConfigs() async {
    final List<dynamic> loaded;
    switch (widget.protocol) {
      case RemoteProtocolKind.smb:
        loaded = await SmbService.getSavedConfigs();
        break;
      case RemoteProtocolKind.webdav:
        loaded = await WebDavService.getSavedConfigs();
        break;
      case RemoteProtocolKind.sftp:
        loaded = await SftpService.getSavedConfigs();
        break;
    }
    if (!mounted) return;
    setState(() {
      _configs = loaded;
      if (_selectedConfig != null) {
        final match = loaded.where((c) => _configId(c) == _configId(_selectedConfig));
        _selectedConfig = match.isNotEmpty
            ? match.first
            : (loaded.isNotEmpty ? loaded.first : null);
      } else if (loaded.isNotEmpty) {
        _selectedConfig = loaded.first;
      }
      if (_selectedConfig != null) {
        final root = _configRoot(_selectedConfig);
        _currentPath = root;
        _pathHistory
          ..clear()
          ..add(root);
      }
    });
    if (_selectedConfig != null) {
      _loadDirectory(_currentPath);
    }
  }

  String _configId(dynamic c) {
    if (c is SmbConfig) return c.id;
    if (c is WebDavConfig) return c.id;
    if (c is SftpConfig) return c.id;
    return '';
  }

  String _configLabel(dynamic c) {
    if (c is SmbConfig) return '${c.name} (${c.host})';
    if (c is WebDavConfig) return '${c.name} (${c.baseUrl})';
    if (c is SftpConfig) return '${c.name} (${c.host}:${c.port})';
    return '';
  }

  String _configName(dynamic c) {
    if (c is SmbConfig) return c.name;
    if (c is WebDavConfig) return c.name;
    if (c is SftpConfig) return c.name;
    return 'Remote';
  }

  String _configRoot(dynamic c) {
    if (c is SmbConfig) return c.rootPath.isEmpty ? '/' : c.rootPath;
    if (c is WebDavConfig) return c.rootPath.isEmpty ? '/' : c.rootPath;
    if (c is SftpConfig) return c.rootPath.isEmpty ? '/' : c.rootPath;
    return '/';
  }

  Future<void> _loadDirectory(String path) async {
    final cfg = _selectedConfig;
    if (cfg == null) return;
    setState(() {
      _isLoading = true;
      _error = null;
      _currentPath = path;
    });

    try {
      final List<RemoteFileEntry> list;
      switch (widget.protocol) {
        case RemoteProtocolKind.smb:
          list = await SmbService.listDirectory(cfg as SmbConfig, dirPath: path);
          break;
        case RemoteProtocolKind.webdav:
          list = await WebDavService.listDirectory(
            cfg as WebDavConfig,
            dirPath: path,
          );
          break;
        case RemoteProtocolKind.sftp:
          list = await SftpService.listDirectory(cfg as SftpConfig, dirPath: path);
          break;
      }
      if (!mounted) return;
      setState(() {
        _entries = list;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  void _navigateInto(String path) {
    _pathHistory.add(path);
    _loadDirectory(path);
  }

  void _navigateUp() {
    if (_pathHistory.length > 1) {
      _pathHistory.removeLast();
      _loadDirectory(_pathHistory.last);
    }
  }

  RemoteByteSource _createSource(RemoteFileEntry entry) {
    switch (widget.protocol) {
      case RemoteProtocolKind.smb:
        return SmbService.createByteSource(_selectedConfig as SmbConfig, entry);
      case RemoteProtocolKind.webdav:
        return WebDavService.createByteSource(
          _selectedConfig as WebDavConfig,
          entry,
        );
      case RemoteProtocolKind.sftp:
        return SftpService.createByteSource(_selectedConfig as SftpConfig, entry);
    }
  }

  Future<void> _playFolderFromEntry(RemoteFileEntry? tapped) async {
    if (_selectedConfig == null || widget.onPlayQueue == null) return;
    final audioFiles = _entries.where((e) => e.isAudioFile).toList();
    if (audioFiles.isEmpty) return;

    final initialIndex = tapped == null
        ? 0
        : audioFiles.indexWhere((e) => e.path == tapped.path).clamp(0, audioFiles.length - 1);

    setState(() => _isStartingPlayback = true);
    try {
      final trackInfos = <TrackInfo>[];
      final sources = <AudioSource>[];
      final serverName = _configName(_selectedConfig);

      for (final file in audioFiles) {
        final byteSource = _createSource(file);
        final url = await LocalMediaServer.instance.registerRemoteSource(byteSource);
        if (url == null) {
          throw StateError('Local media relay failed to start');
        }
        trackInfos.add(TrackInfo(
          videoId: url,
          title: file.name,
          artist: serverName,
          thumbnailUrl: null,
        ));
        sources.add(AudioSource.network(
          url,
          title: file.name,
          artist: serverName,
        ));
      }

      if (!mounted) return;
      await widget.onPlayQueue!(trackInfos, sources, initialIndex);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to start stream: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
    } finally {
      if (mounted) setState(() => _isStartingPlayback = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final audioCount = _entries.where((e) => e.isAudioFile).length;
    return Column(
      children: [
        _buildHeader(),
        if (_selectedConfig != null) _buildBreadcrumbBar(audioCount),
        Expanded(child: _buildBody()),
      ],
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: _cardDark,
      child: Row(
        children: [
          Icon(_protocolIcon, color: _primary),
          const SizedBox(width: 12),
          Expanded(
            child: _configs.isEmpty
                ? Text(
                    'No $_protocolTitle configured',
                    style: TextStyle(color: _textMuted),
                  )
                : DropdownButtonHideUnderline(
                    child: DropdownButton<dynamic>(
                      value: _selectedConfig,
                      dropdownColor: _cardDark,
                      isExpanded: true,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                      items: _configs
                          .map((c) => DropdownMenuItem(
                                value: c,
                                child: Text(
                                  _configLabel(c),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ))
                          .toList(),
                      onChanged: (val) {
                        if (val != null) {
                          final root = _configRoot(val);
                          setState(() {
                            _selectedConfig = val;
                            _pathHistory
                              ..clear()
                              ..add(root);
                          });
                          _loadDirectory(root);
                        }
                      },
                    ),
                  ),
          ),
          IconButton(
            icon: Icon(Icons.add_circle_outline_rounded, color: _primary),
            tooltip: 'Add $_protocolTitle',
            onPressed: () => _showServerDialog(),
          ),
          if (_selectedConfig != null) ...[
            IconButton(
              icon: const Icon(Icons.edit_outlined, color: Colors.white70, size: 20),
              tooltip: 'Edit',
              onPressed: () => _showServerDialog(existing: _selectedConfig),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline_rounded,
                  color: Colors.redAccent, size: 20),
              tooltip: 'Delete',
              onPressed: () async {
                final id = _configId(_selectedConfig);
                switch (widget.protocol) {
                  case RemoteProtocolKind.smb:
                    await SmbService.deleteConfig(id);
                    break;
                  case RemoteProtocolKind.webdav:
                    await WebDavService.deleteConfig(id);
                    break;
                  case RemoteProtocolKind.sftp:
                    await SftpService.deleteConfig(id);
                    break;
                }
                _selectedConfig = null;
                _loadConfigs();
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBreadcrumbBar(int audioCount) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      color: Colors.black26,
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_rounded,
                color: Colors.white70, size: 20),
            onPressed: _pathHistory.length > 1 ? _navigateUp : null,
          ),
          Expanded(
            child: Text(
              _currentPath,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: _textMuted, fontSize: 13),
            ),
          ),
          if (audioCount > 0)
            TextButton.icon(
              onPressed: _isStartingPlayback ? null : () => _playFolderFromEntry(null),
              icon: _isStartingPlayback
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(Icons.play_arrow_rounded, color: _primary, size: 18),
              label: Text(
                'Play ($audioCount)',
                style: TextStyle(color: _primary, fontSize: 12),
              ),
            ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Colors.white70, size: 20),
            onPressed: () => _loadDirectory(_currentPath),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_selectedConfig == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(_protocolIcon,
                  size: 64, color: _textMuted.withValues(alpha: 0.45)),
              const SizedBox(height: 16),
              Text(
                'Add $_protocolTitle',
                style: const TextStyle(
                    color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                'Browse and stream lossless audio directly with HTTP byte-range seeking.',
                textAlign: TextAlign.center,
                style: TextStyle(color: _textMuted, fontSize: 13),
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: _primary,
                  foregroundColor: Colors.black,
                ),
                onPressed: () => _showServerDialog(),
                icon: const Icon(Icons.add_rounded),
                label: Text('Add $_protocolTitle'),
              ),
            ],
          ),
        ),
      );
    }

    if (_isLoading) {
      return Center(child: CircularProgressIndicator(color: _primary));
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded,
                  color: Colors.redAccent, size: 48),
              const SizedBox(height: 12),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: () => _loadDirectory(_currentPath),
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (_entries.isEmpty) {
      return Center(
        child: Text(
          'No folders or audio files here',
          style: TextStyle(color: _textMuted),
        ),
      );
    }

    return ListView.separated(
      itemCount: _entries.length,
      separatorBuilder: (_, __) =>
          Divider(height: 1, color: Colors.white.withValues(alpha: 0.05)),
      itemBuilder: (context, index) {
        final entry = _entries[index];
        return ListTile(
          leading: Icon(
            entry.isDirectory ? Icons.folder_rounded : Icons.audiotrack_rounded,
            color: entry.isDirectory ? Colors.amberAccent : _primary,
          ),
          title: Text(
            entry.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white),
          ),
          subtitle: entry.isDirectory
              ? null
              : Text(
                  [
                    entry.formatBadge,
                    if (entry.formattedSize.isNotEmpty) entry.formattedSize,
                  ].join(' • '),
                  style: TextStyle(color: _textMuted, fontSize: 12),
                ),
          trailing: entry.isDirectory
              ? const Icon(Icons.chevron_right_rounded, color: Colors.white54)
              : IconButton(
                  icon: Icon(Icons.play_circle_fill_rounded, color: _primary),
                  onPressed: _isStartingPlayback
                      ? null
                      : () => _playFolderFromEntry(entry),
                ),
          onTap: () {
            if (entry.isDirectory) {
              _navigateInto(entry.path);
            } else if (!_isStartingPlayback) {
              _playFolderFromEntry(entry);
            }
          },
        );
      },
    );
  }

  void _showServerDialog({dynamic existing}) {
    final nameCtrl = TextEditingController(
      text: existing != null ? _configName(existing) : _protocolTitle,
    );
    final hostOrUrlCtrl = TextEditingController(
      text: existing is SmbConfig
          ? existing.host
          : existing is WebDavConfig
              ? existing.baseUrl
              : existing is SftpConfig
                  ? existing.host
                  : '',
    );
    final portCtrl = TextEditingController(
      text: existing is SftpConfig ? '${existing.port}' : '22',
    );
    final domainCtrl = TextEditingController(
      text: existing is SmbConfig ? existing.domain : '',
    );
    final userCtrl = TextEditingController(
      text: existing is SmbConfig
          ? existing.username
          : existing is WebDavConfig
              ? existing.username
              : existing is SftpConfig
                  ? existing.username
                  : '',
    );
    final passCtrl = TextEditingController(
      text: existing is SmbConfig
          ? existing.password
          : existing is WebDavConfig
              ? existing.password
              : existing is SftpConfig
                  ? existing.password
                  : '',
    );
    final rootCtrl = TextEditingController(
      text: existing != null ? _configRoot(existing) : '/',
    );
    final keyCtrl = TextEditingController(
      text: existing is SftpConfig ? existing.privateKeyPem : '',
    );
    final passphraseCtrl = TextEditingController(
      text: existing is SftpConfig ? existing.passphrase : '',
    );

    bool boolFlag = existing is WebDavConfig
        ? existing.allowSelfSigned
        : existing is SmbConfig
            ? existing.forceSmb1
            : false;

    bool testing = false;
    String? testStatus;
    bool testOk = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) {
          dynamic buildDraft() {
            final id = existing != null
                ? _configId(existing)
                : DateTime.now().millisecondsSinceEpoch.toString();
            final name = nameCtrl.text.trim().isEmpty
                ? _protocolTitle
                : nameCtrl.text.trim();
            final root = rootCtrl.text.trim().isEmpty ? '/' : rootCtrl.text.trim();

            switch (widget.protocol) {
              case RemoteProtocolKind.smb:
                return SmbConfig(
                  id: id,
                  name: name,
                  host: hostOrUrlCtrl.text.trim(),
                  domain: domainCtrl.text.trim(),
                  username: userCtrl.text.trim(),
                  password: passCtrl.text,
                  rootPath: root,
                  forceSmb1: boolFlag,
                );
              case RemoteProtocolKind.webdav:
                return WebDavConfig(
                  id: id,
                  name: name,
                  baseUrl: hostOrUrlCtrl.text.trim(),
                  username: userCtrl.text.trim(),
                  password: passCtrl.text,
                  rootPath: root,
                  allowSelfSigned: boolFlag,
                );
              case RemoteProtocolKind.sftp:
                return SftpConfig(
                  id: id,
                  name: name,
                  host: hostOrUrlCtrl.text.trim(),
                  port: int.tryParse(portCtrl.text.trim()) ?? 22,
                  username: userCtrl.text.trim(),
                  password: passCtrl.text,
                  privateKeyPem: keyCtrl.text,
                  passphrase: passphraseCtrl.text,
                  rootPath: root,
                );
            }
          }

          return AlertDialog(
            backgroundColor: _cardDark,
            title: Text(
              existing == null ? 'Add $_protocolTitle' : 'Edit $_protocolTitle',
              style: const TextStyle(color: Colors.white),
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameCtrl,
                    style: const TextStyle(color: Colors.white),
                    decoration: _inputDeco('Display Name'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: hostOrUrlCtrl,
                    style: const TextStyle(color: Colors.white),
                    decoration: _inputDeco(
                      widget.protocol == RemoteProtocolKind.webdav
                          ? 'Base URL (e.g. https://nas.local/remote.php/dav/files/user)'
                          : 'Host / IP (e.g. 192.168.1.50)',
                    ),
                  ),
                  if (widget.protocol == RemoteProtocolKind.sftp) ...[
                    const SizedBox(height: 10),
                    TextField(
                      controller: portCtrl,
                      keyboardType: TextInputType.number,
                      style: const TextStyle(color: Colors.white),
                      decoration: _inputDeco('Port (default 22)'),
                    ),
                  ],
                  if (widget.protocol == RemoteProtocolKind.smb) ...[
                    const SizedBox(height: 10),
                    TextField(
                      controller: domainCtrl,
                      style: const TextStyle(color: Colors.white),
                      decoration: _inputDeco('Domain / Workgroup (optional)'),
                    ),
                  ],
                  const SizedBox(height: 10),
                  TextField(
                    controller: userCtrl,
                    style: const TextStyle(color: Colors.white),
                    decoration: _inputDeco('Username'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: passCtrl,
                    obscureText: true,
                    style: const TextStyle(color: Colors.white),
                    decoration: _inputDeco('Password'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: rootCtrl,
                    style: const TextStyle(color: Colors.white),
                    decoration: _inputDeco(
                      widget.protocol == RemoteProtocolKind.smb
                          ? 'Initial Path (e.g. / or /Music)'
                          : 'Root Path (default /)',
                    ),
                  ),
                  if (widget.protocol == RemoteProtocolKind.sftp) ...[
                    const SizedBox(height: 10),
                    TextField(
                      controller: keyCtrl,
                      maxLines: 3,
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                      decoration: _inputDeco('Private Key PEM (optional)'),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: passphraseCtrl,
                      obscureText: true,
                      style: const TextStyle(color: Colors.white),
                      decoration: _inputDeco('Key Passphrase (optional)'),
                    ),
                  ],
                  if (widget.protocol == RemoteProtocolKind.webdav ||
                      widget.protocol == RemoteProtocolKind.smb)
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        widget.protocol == RemoteProtocolKind.webdav
                            ? 'Allow Self-Signed SSL'
                            : 'Force Legacy SMBv1',
                        style: const TextStyle(color: Colors.white70, fontSize: 13),
                      ),
                      value: boolFlag,
                      activeThumbColor: _primary,
                      onChanged: (v) => setDlg(() => boolFlag = v),
                    ),
                  if (testStatus != null)
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(top: 8),
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: (testOk ? Colors.green : Colors.redAccent)
                            .withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        testStatus!,
                        style: TextStyle(
                          color: testOk ? Colors.greenAccent : Colors.redAccent,
                          fontSize: 12,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: testing
                    ? null
                    : () async {
                        setDlg(() {
                          testing = true;
                          testStatus = null;
                        });
                        final draft = buildDraft();
                        String? err;
                        switch (widget.protocol) {
                          case RemoteProtocolKind.smb:
                            err = await SmbService.testConnection(draft as SmbConfig);
                            break;
                          case RemoteProtocolKind.webdav:
                            err = await WebDavService.testConnection(
                              draft as WebDavConfig,
                            );
                            break;
                          case RemoteProtocolKind.sftp:
                            err = await SftpService.testConnection(
                              draft as SftpConfig,
                            );
                            break;
                        }
                        if (!ctx.mounted) return;
                        setDlg(() {
                          testing = false;
                          testOk = err == null;
                          testStatus = err ?? 'Connected successfully!';
                        });
                      },
                child: testing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text('Test', style: TextStyle(color: _primary)),
              ),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: _primary,
                  foregroundColor: Colors.black,
                ),
                onPressed: () async {
                  if (hostOrUrlCtrl.text.trim().isEmpty) return;
                  final draft = buildDraft();
                  switch (widget.protocol) {
                    case RemoteProtocolKind.smb:
                      await SmbService.saveConfig(draft as SmbConfig);
                      break;
                    case RemoteProtocolKind.webdav:
                      await WebDavService.saveConfig(draft as WebDavConfig);
                      break;
                    case RemoteProtocolKind.sftp:
                      await SftpService.saveConfig(draft as SftpConfig);
                      break;
                  }
                  _selectedConfig = draft;
                  if (ctx.mounted) Navigator.of(ctx).pop();
                  _loadConfigs();
                },
                child: const Text('Save'),
              ),
            ],
          );
        },
      ),
    );
  }

  InputDecoration _inputDeco(String label) => InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: _textMuted, fontSize: 13),
        isDense: true,
        enabledBorder: OutlineInputBorder(
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.15)),
          borderRadius: BorderRadius.circular(8),
        ),
        focusedBorder: OutlineInputBorder(
          borderSide: BorderSide(color: _primary),
          borderRadius: BorderRadius.circular(8),
        ),
      );
}
