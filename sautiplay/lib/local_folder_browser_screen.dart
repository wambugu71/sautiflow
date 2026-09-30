import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_m3shapes_extended/flutter_m3shapes_extended.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:path/path.dart' as p;
import 'package:sautiflow/sautiflow.dart';

import 'isolate_player.dart';
import 'services/app_theme_service.dart';
import 'services/storage_volume_service.dart';
import 'widgets/song_options_menu.dart';

/// Full-featured, senior-engineered hierarchical local folder navigator.
/// Seamlessly bridges Internal Storage and Removable SD Cards (Memory Cards).
class LocalFolderBrowserScreen extends StatefulWidget {
  final IsolateAudioPlayer? player;
  final String? initialPath;
  final List<String> trackedFolders;
  final Future<void> Function(List<String> audioFilePaths, {int initialIndex})?
      onPlayFolder;
  final Function(TrackInfo track)? onQueueTrack;
  final Future<void> Function(String folderPath)? onToggleTrackFolder;

  const LocalFolderBrowserScreen({
    super.key,
    this.player,
    this.initialPath,
    this.trackedFolders = const [],
    this.onPlayFolder,
    this.onQueueTrack,
    this.onToggleTrackFolder,
  });

  @override
  State<LocalFolderBrowserScreen> createState() =>
      _LocalFolderBrowserScreenState();
}

class _LocalFolderBrowserScreenState extends State<LocalFolderBrowserScreen> {
  Color get _bgDark => context.bgDark;
  Color get _cardDark => context.cardDark;
  Color get _primary => context.primaryColor;
  Color get _textDark => context.textMuted;
  Color get _textPrimary => context.textPrimary;
  Color get _outline => context.outlineColor;

  List<StorageVolume> _volumes = [];
  StorageVolume? _selectedVolume;
  String _currentPath = '';
  FolderContents? _contents;
  bool _isLoading = true;
  bool _hasPermission = true;
  late Set<String> _trackedFoldersSet;

  final ScrollController _breadcrumbScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _trackedFoldersSet = widget.trackedFolders
        .map((f) => p.canonicalize(f).toLowerCase())
        .toSet();
    _initBrowser();
  }

  @override
  void dispose() {
    _breadcrumbScrollController.dispose();
    super.dispose();
  }

  Future<void> _initBrowser() async {
    setState(() => _isLoading = true);

    final hasPerm = await StorageVolumeService.ensureStoragePermissions();
    if (!mounted) return;

    if (!hasPerm) {
      setState(() {
        _hasPermission = false;
        _isLoading = false;
      });
      return;
    }

    final volumes = await StorageVolumeService.getStorageVolumes();
    if (!mounted) return;

    StorageVolume? matchedVolume;
    String targetPath = '';

    if (widget.initialPath != null && widget.initialPath!.isNotEmpty) {
      targetPath = p.canonicalize(widget.initialPath!);
      for (final v in volumes) {
        if (targetPath.startsWith(v.path) ||
            p.isWithin(v.path, targetPath) ||
            v.path == targetPath) {
          matchedVolume = v;
          break;
        }
      }
    }

    if (matchedVolume == null && volumes.isNotEmpty) {
      matchedVolume = volumes.first;
      targetPath = matchedVolume.path;
    }

    setState(() {
      _hasPermission = true;
      _volumes = volumes;
      _selectedVolume = matchedVolume;
      _currentPath = targetPath;
    });

    if (_currentPath.isNotEmpty) {
      await _loadDirectory(_currentPath);
    } else {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadDirectory(String path, {bool forceRefresh = false}) async {
    setState(() {
      _isLoading = true;
      _currentPath = p.canonicalize(path);
    });

    final contents = await StorageVolumeService.instance.listDirectoryContents(
      _currentPath,
      forceRefresh: forceRefresh,
    );

    if (!mounted) return;
    setState(() {
      _contents = contents;
      _isLoading = false;
    });

    // Auto scroll breadcrumbs to the far right so current folder is visible
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_breadcrumbScrollController.hasClients) {
        _breadcrumbScrollController.animateTo(
          _breadcrumbScrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  bool _isFolderTracked(String folderPath) {
    return _trackedFoldersSet.contains(p.canonicalize(folderPath).toLowerCase());
  }

  Future<void> _toggleTrackCurrentFolder() async {
    if (_currentPath.isEmpty) return;
    final canonical = p.canonicalize(_currentPath);
    final isTracked = _isFolderTracked(canonical);

    if (widget.onToggleTrackFolder != null) {
      await widget.onToggleTrackFolder!(canonical);
      setState(() {
        if (isTracked) {
          _trackedFoldersSet.remove(canonical.toLowerCase());
        } else {
          _trackedFoldersSet.add(canonical.toLowerCase());
        }
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isTracked
                  ? 'Removed "${p.basename(canonical)}" from Library.'
                  : 'Added "${p.basename(canonical)}" to Library.',
            ),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  Future<void> _playCurrentFolder({bool shuffle = false}) async {
    if (_contents == null) return;
    setState(() => _isLoading = true);

    List<String> audioPaths =
        _contents!.audioFiles.map((a) => a.path).toList();

    // If folder has subdirectories or few direct tracks, scan recursively
    if (_contents!.subdirectories.isNotEmpty || audioPaths.isEmpty) {
      final recursivePaths =
          await StorageVolumeService.scanAudioFilesRecursively(_currentPath);
      if (recursivePaths.isNotEmpty) {
        audioPaths = recursivePaths;
      }
    }

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (audioPaths.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No playable audio tracks found in this folder.'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    if (shuffle) {
      audioPaths.shuffle();
    }

    widget.onPlayFolder?.call(audioPaths, initialIndex: 0);
  }

  Future<void> _playSubfolder(String subfolderPath) async {
    setState(() => _isLoading = true);
    final paths =
        await StorageVolumeService.scanAudioFilesRecursively(subfolderPath);
    if (!mounted) return;
    setState(() => _isLoading = false);

    if (paths.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No playable audio tracks found in subfolder.'),
        ),
      );
      return;
    }

    widget.onPlayFolder?.call(paths, initialIndex: 0);
  }

  void _playTrackAt(int index) {
    if (_contents == null || _contents!.audioFiles.isEmpty) return;
    final paths = _contents!.audioFiles.map((a) => a.path).toList();
    widget.onPlayFolder?.call(paths, initialIndex: index);
  }

  void _queueTrack(AudioFileEntry audio) {
    if (widget.onQueueTrack != null) {
      widget.onQueueTrack!(TrackInfo(
        videoId: audio.path,
        title: audio.title,
        artist: audio.artist != 'Unknown Artist' ? audio.artist : 'Local File',
      ));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Queued "${audio.title}"'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  // ---------------------------------------------------------------------------
  // BREADCRUMB BUILDER
  // ---------------------------------------------------------------------------

  List<Map<String, String>> _computeBreadcrumbs() {
    if (_currentPath.isEmpty) return [];

    final crumbs = <Map<String, String>>[];
    String rootPath = '';
    String rootLabel = 'Root';

    if (_selectedVolume != null &&
        (_currentPath.startsWith(_selectedVolume!.path) ||
            p.canonicalize(_currentPath) == _selectedVolume!.path)) {
      rootPath = _selectedVolume!.path;
      rootLabel = _selectedVolume!.label;
    } else {
      rootPath = p.rootPrefix(_currentPath);
      rootLabel = rootPath.isEmpty ? '/' : rootPath;
    }

    crumbs.add({'label': rootLabel, 'path': rootPath});

    if (_currentPath == rootPath) {
      return crumbs;
    }

    String relative = p.relative(_currentPath, from: rootPath);
    if (relative.isNotEmpty && relative != '.') {
      final parts = p.split(relative);
      String runningPath = rootPath;
      for (final part in parts) {
        runningPath = p.join(runningPath, part);
        crumbs.add({'label': part, 'path': runningPath});
      }
    }

    return crumbs;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgDark,
      appBar: AppBar(
        backgroundColor: _bgDark,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _currentPath.isEmpty
                  ? 'Storage Explorer'
                  : p.basename(_currentPath).isEmpty
                      ? (_selectedVolume?.label ?? 'Storage')
                      : p.basename(_currentPath),
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (_selectedVolume != null)
              Text(
                _selectedVolume!.label,
                style: TextStyle(
                  color: _primary,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
          ],
        ),
        actions: [
          // Storage Volume Switcher (Internal Storage vs SD Card)
          if (_volumes.length > 1)
            PopupMenuButton<StorageVolume>(
              tooltip: 'Select Storage Volume',
              icon: Icon(
                _selectedVolume?.icon ?? Icons.storage_rounded,
                color: _primary,
              ),
              color: _cardDark,
              onSelected: (volume) {
                setState(() {
                  _selectedVolume = volume;
                });
                _loadDirectory(volume.path);
              },
              itemBuilder: (context) {
                return _volumes.map((v) {
                  final isSelected = v.path == _selectedVolume?.path;
                  return PopupMenuItem<StorageVolume>(
                    value: v,
                    child: Row(
                      children: [
                        Icon(
                          v.icon,
                          color: isSelected ? _primary : _textDark,
                          size: 20,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            v.label,
                            style: TextStyle(
                              color: isSelected ? _primary : _textPrimary,
                              fontWeight: isSelected
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                            ),
                          ),
                        ),
                        if (isSelected)
                          Icon(Icons.check_rounded, color: _primary, size: 18),
                      ],
                    ),
                  );
                }).toList();
              },
            ),

          // Track / Untrack folder in Library toggle
          if (_currentPath.isNotEmpty && widget.onToggleTrackFolder != null)
            IconButton(
              icon: Icon(
                _isFolderTracked(_currentPath)
                    ? Icons.bookmark_rounded
                    : Icons.bookmark_add_outlined,
                color: _isFolderTracked(_currentPath)
                    ? _primary
                    : Colors.white70,
              ),
              tooltip: _isFolderTracked(_currentPath)
                  ? 'Tracked in Library'
                  : 'Track Folder in Library',
              onPressed: _toggleTrackCurrentFolder,
            ),

          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Colors.white70),
            tooltip: 'Refresh',
            onPressed: () => _loadDirectory(_currentPath, forceRefresh: true),
          ),
        ],
      ),
      body: !_hasPermission
          ? _buildPermissionDeniedView()
          : Column(
              children: [
                _buildVolumeSelectorBar(),
                _buildBreadcrumbsBar(),
                if (_contents != null && !_contents!.isEmpty)
                  _buildActionBar(),
                Expanded(
                  child: _isLoading
                      ? Center(child: CircularProgressIndicator(color: _primary))
                      : _buildContentsList(),
                ),
              ],
            ),
    );
  }

  // ---------------------------------------------------------------------------
  // VOLUME CHIPS SELECTOR BAR
  // ---------------------------------------------------------------------------

  Widget _buildVolumeSelectorBar() {
    if (_volumes.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: _cardDark.withAlpha(120),
      child: Row(
        children: [
          Text(
            'Storage:',
            style: TextStyle(
              color: _textDark,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: _volumes.map((vol) {
                  final isSelected = vol.path == _selectedVolume?.path;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8.0),
                    child: InkWell(
                      onTap: () {
                        setState(() => _selectedVolume = vol);
                        _loadDirectory(vol.path);
                      },
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? _primary.withAlpha(40)
                              : Colors.white.withAlpha(12),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: isSelected ? _primary : _outline,
                            width: 1,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              vol.icon,
                              size: 14,
                              color: isSelected ? _primary : Colors.white70,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              vol.label,
                              style: TextStyle(
                                color: isSelected ? _primary : Colors.white,
                                fontSize: 12,
                                fontWeight: isSelected
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // BREADCRUMBS BAR
  // ---------------------------------------------------------------------------

  Widget _buildBreadcrumbsBar() {
    final crumbs = _computeBreadcrumbs();
    final canGoUp = _contents?.parentPath != null &&
        (_selectedVolume == null ||
            _currentPath != _selectedVolume!.path);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      color: Colors.black26,
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_upward_rounded, size: 20),
            color: canGoUp ? Colors.white70 : Colors.white24,
            tooltip: 'Up one folder',
            onPressed: canGoUp
                ? () => _loadDirectory(_contents!.parentPath!)
                : null,
          ),
          Expanded(
            child: SingleChildScrollView(
              controller: _breadcrumbScrollController,
              scrollDirection: Axis.horizontal,
              child: Row(
                children: List.generate(crumbs.length, (index) {
                  final crumb = crumbs[index];
                  final isLast = index == crumbs.length - 1;
                  return Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      InkWell(
                        onTap: isLast
                            ? null
                            : () => _loadDirectory(crumb['path']!),
                        borderRadius: BorderRadius.circular(6),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 4),
                          child: Text(
                            crumb['label']!,
                            style: TextStyle(
                              color: isLast ? _primary : Colors.white70,
                              fontWeight: isLast
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ),
                      if (!isLast)
                        const Icon(
                          Icons.chevron_right_rounded,
                          size: 16,
                          color: Colors.white24,
                        ),
                    ],
                  );
                }),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // ACTION BAR (Play All, Shuffle, Status)
  // ---------------------------------------------------------------------------

  Widget _buildActionBar() {
    final audioCount = _contents!.audioFiles.length;
    final folderCount = _contents!.subdirectories.length;
    final isTracked = _isFolderTracked(_currentPath);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: _cardDark,
        border: Border(bottom: BorderSide(color: _outline, width: 0.5)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '$audioCount Track${audioCount == 1 ? '' : 's'}'
              '${folderCount > 0 ? ' • $folderCount Subfolder${folderCount == 1 ? '' : 's'}' : ''}',
              style: TextStyle(color: _textDark, fontSize: 13),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (audioCount > 0 || folderCount > 0) ...[
            M3EButton(
              onPressed: () => _playCurrentFolder(shuffle: false),
              icon: const Icon(Icons.play_arrow_rounded, size: 18),
              label: const Text('Play'),
              style: M3EButtonStyle.filled,
            ),
            const SizedBox(width: 8),
            M3EIconButton(
              icon: const Icon(Icons.shuffle_rounded, size: 18),
              onPressed: () => _playCurrentFolder(shuffle: true),
              tooltip: 'Shuffle All',
            ),
          ],
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // CONTENTS LIST (Subdirectories + Audio Files)
  // ---------------------------------------------------------------------------

  Widget _buildContentsList() {
    if (_contents == null || _contents!.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.folder_open_rounded, size: 56, color: _textDark),
              const SizedBox(height: 16),
              const Text(
                'No audio files or subfolders found',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'This directory does not contain supported audio files (.mp3, .flac, .wav, etc.)',
                style: TextStyle(color: _textDark, fontSize: 13),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    final subdirectories = _contents!.subdirectories;
    final audioFiles = _contents!.audioFiles;

    return ListView.builder(
      itemCount: subdirectories.length + audioFiles.length,
      itemBuilder: (context, index) {
        if (index < subdirectories.length) {
          final sub = subdirectories[index];
          return _buildSubdirectoryTile(sub);
        } else {
          final audioIndex = index - subdirectories.length;
          final audio = audioFiles[audioIndex];
          return _buildAudioFileTile(audio, audioIndex);
        }
      },
    );
  }

  Widget _buildSubdirectoryTile(FolderEntry sub) {
    final isTracked = _isFolderTracked(sub.path);

    return ListTile(
      leading: M3EContainer(
        Shapes.roundedRectangle,
        width: 44,
        height: 44,
        color: _primary.withAlpha(20),
        child: Center(
          child: Icon(
            isTracked ? Icons.folder_special_rounded : Icons.folder_rounded,
            color: _primary,
            size: 24,
          ),
        ),
      ),
      title: Text(
        sub.name,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w600,
          fontSize: 15,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        sub.audioCount > 0
            ? '${sub.audioCount} audio track${sub.audioCount == 1 ? '' : 's'}'
            : 'Folder',
        style: TextStyle(color: _textDark, fontSize: 12),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.play_circle_outline_rounded, size: 22),
            color: _primary,
            tooltip: 'Play Subfolder',
            onPressed: () => _playSubfolder(sub.path),
          ),
          PopupMenuButton<String>(
            icon: Icon(Icons.more_vert_rounded, color: _textDark, size: 20),
            color: _cardDark,
            onSelected: (val) {
              if (val == 'play') {
                _playSubfolder(sub.path);
              } else if (val == 'track' && widget.onToggleTrackFolder != null) {
                widget.onToggleTrackFolder!(sub.path);
                setState(() {
                  if (isTracked) {
                    _trackedFoldersSet.remove(sub.path.toLowerCase());
                  } else {
                    _trackedFoldersSet.add(sub.path.toLowerCase());
                  }
                });
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'play',
                child: Row(
                  children: [
                    Icon(Icons.play_arrow_rounded, color: _primary, size: 18),
                    const SizedBox(width: 8),
                    const Text('Play Subfolder',
                        style: TextStyle(color: Colors.white)),
                  ],
                ),
              ),
              if (widget.onToggleTrackFolder != null)
                PopupMenuItem(
                  value: 'track',
                  child: Row(
                    children: [
                      Icon(
                        isTracked
                            ? Icons.bookmark_remove_rounded
                            : Icons.bookmark_add_rounded,
                        color: _primary,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        isTracked ? 'Untrack in Library' : 'Track in Library',
                        style: const TextStyle(color: Colors.white),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
      onTap: () => _loadDirectory(sub.path),
    );
  }

  Widget _buildAudioFileTile(AudioFileEntry audio, int audioIndex) {
    return ListTile(
      leading: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: _cardDark,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: _outline, width: 0.5),
        ),
        child: Center(
          child: Text(
            audio.extension,
            style: TextStyle(
              color: _primary,
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
      title: Text(
        audio.title,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w500,
          fontSize: 14,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        '${audio.extension} • ${audio.formattedSize}',
        style: TextStyle(color: _textDark, fontSize: 12),
      ),
      trailing: IconButton(
        icon: const Icon(Icons.playlist_add_rounded, size: 22),
        color: Colors.white70,
        tooltip: 'Play Next',
        onPressed: () => _queueTrack(audio),
      ),
      onTap: () => _playTrackAt(audioIndex),
    );
  }

  // ---------------------------------------------------------------------------
  // PERMISSION DENIED VIEW
  // ---------------------------------------------------------------------------

  Widget _buildPermissionDeniedView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.folder_off_rounded, size: 64, color: Colors.orangeAccent),
            const SizedBox(height: 20),
            const Text(
              'Storage Access Required',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'To navigate folders and play audio files from both Internal Storage and Memory Cards, Sautiplay requires storage permission.',
              style: TextStyle(color: _textDark, fontSize: 14),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            M3EButton(
              onPressed: _initBrowser,
              icon: const Icon(Icons.lock_open_rounded),
              label: const Text('Grant Storage Permission'),
              style: M3EButtonStyle.filled,
            ),
          ],
        ),
      ),
    );
  }
}
