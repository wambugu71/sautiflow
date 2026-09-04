import 'dart:io';
import 'package:flutter/material.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:flutter_m3shapes_extended/flutter_m3shapes_extended.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';

import 'models/local_song_item.dart';
import 'services/app_theme_service.dart';
import 'services/m3u_playlist_service.dart';
import 'widgets/local_album_art.dart';

class PlaylistDetailScreen extends StatefulWidget {
  final SavedM3uPlaylist playlist;
  final Future<void> Function(List<String> audioFilePaths, {int initialIndex})
      onPlayFolder;
  final VoidCallback? onPlaylistUpdated;

  const PlaylistDetailScreen({
    super.key,
    required this.playlist,
    required this.onPlayFolder,
    this.onPlaylistUpdated,
  });

  @override
  State<PlaylistDetailScreen> createState() => _PlaylistDetailScreenState();
}

class _PlaylistDetailScreenState extends State<PlaylistDetailScreen> {
  late SavedM3uPlaylist _currentPlaylist;
  late List<LocalSongItem> _tracks;

  Color get _bgDark => context.bgDark;
  Color get _surfaceDark => context.cardDark;
  Color get _primary => context.primaryColor;
  Color get _textPrimary => context.textPrimary;
  Color get _textDark => context.textMuted;
  Color get _outline => context.outlineColor;

  @override
  void initState() {
    super.initState();
    _currentPlaylist = widget.playlist;
    _tracks = List.from(widget.playlist.tracks);
  }

  void _playAll({bool shuffle = false}) {
    if (_tracks.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No tracks to play in this playlist.')),
      );
      return;
    }
    final paths = _tracks.map((t) => t.path).toList();
    if (shuffle) {
      paths.shuffle();
    }
    widget.onPlayFolder(paths, initialIndex: 0);
  }

  Future<void> _renamePlaylist() async {
    final controller = TextEditingController(text: _currentPlaylist.name);
    final confirm = await M3EDialog.show<bool>(
      context,
      dialog: M3EDialog(
        title: 'Rename Playlist',
        topDivider: true,
        bottomDivider: true,
        content: Material(
          color: Colors.transparent,
          child: TextField(
            controller: controller,
            autofocus: true,
            style: TextStyle(color: _textPrimary),
            decoration: InputDecoration(
              labelText: 'Playlist Name',
              labelStyle: TextStyle(color: _textDark),
              filled: true,
              fillColor: _surfaceDark,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
        actions: [
          M3EButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          M3EButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Rename'),
          ),
        ],
      ),
    );

    if (confirm == true && controller.text.trim().isNotEmpty) {
      final updated = await M3uPlaylistService.instance.renamePlaylist(
        playlistId: _currentPlaylist.id,
        newName: controller.text.trim(),
      );
      if (updated != null && mounted) {
        setState(() {
          _currentPlaylist = updated;
        });
        widget.onPlaylistUpdated?.call();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Renamed playlist to "${updated.name}"')),
        );
      }
    }
  }

  Future<void> _removeTrack(LocalSongItem track) async {
    final updated = await M3uPlaylistService.instance.removeTrackFromPlaylist(
      playlistId: _currentPlaylist.id,
      trackPath: track.path,
    );
    if (updated != null && mounted) {
      setState(() {
        _currentPlaylist = updated;
        _tracks = List.from(updated.tracks);
      });
      widget.onPlaylistUpdated?.call();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Removed "${track.title}" from playlist.'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _exportM3u8() async {
    if (_tracks.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No tracks available to export.')),
      );
      return;
    }

    try {
      final sanitized =
          _currentPlaylist.name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      final exportDir = Directory(Platform.isWindows
          ? '${Platform.environment['USERPROFILE']}\\Music\\SautiPlay\\Playlists'
          : '/storage/emulated/0/Music/SautiPlay/Playlists');

      final targetPath = p.join(exportDir.path, '$sanitized.m3u8');
      final file = await M3uPlaylistService.instance.exportToM3u8(
        targetFilePath: targetPath,
        playlistName: _currentPlaylist.name,
        tracks: _tracks,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Exported to: ${file.path}'),
            action: SnackBarAction(
              label: 'Share',
              onPressed: () {
                Share.shareXFiles([XFile(file.path)],
                    text: _currentPlaylist.name);
              },
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export failed: $e')),
        );
      }
    }
  }

  Future<void> _deletePlaylist() async {
    final confirm = await M3EDialog.show<bool>(
      context,
      dialog: M3EDialog(
        title: 'Delete Playlist',
        topDivider: true,
        bottomDivider: true,
        content: Text(
          'Are you sure you want to delete "${_currentPlaylist.name}"? The audio files will remain safe on your device.',
          style: TextStyle(color: _textDark, fontSize: 14),
        ),
        actions: [
          M3EButton(
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

    if (confirm == true) {
      await M3uPlaylistService.instance.deletePlaylist(_currentPlaylist.id);
      widget.onPlaylistUpdated?.call();
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Deleted playlist "${_currentPlaylist.name}"')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth >= 800;
        final contentMaxWidth = isDesktop ? 1000.0 : double.infinity;

        return Scaffold(
          backgroundColor: _bgDark,
          appBar: AppBar(
            backgroundColor: _bgDark,
            elevation: 0,
            leading: IconButton(
              icon: Icon(Icons.keyboard_arrow_down, color: _textPrimary),
              onPressed: () => Navigator.of(context).pop(),
            ),
            title: Text(
              _currentPlaylist.name,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: _textPrimary,
                fontSize: isDesktop ? 22 : 18,
              ),
            ),
            actions: [
              M3EMenu(
                anchorBuilder: (context, open) => IconButton(
                  icon: Icon(Icons.more_vert_rounded, color: _textPrimary),
                  onPressed: open,
                ),
                children: [
                  M3EMenuGroup.entries(
                    entries: [
                      M3EMenuEntry(
                        label: 'Rename Playlist',
                        leading: Icon(Icons.edit_outlined,
                            color: _primary, size: 20),
                        onPressed: _renamePlaylist,
                      ),
                      M3EMenuEntry(
                        label: 'Export as .m3u8',
                        leading: const Icon(Icons.file_upload_outlined,
                            color: Colors.amberAccent, size: 20),
                        onPressed: _exportM3u8,
                      ),
                    ],
                  ),
                  M3EMenuGroup.entries(
                    entries: [
                      M3EMenuEntry(
                        label: 'Delete Playlist',
                        leading: const Icon(Icons.delete_outline_rounded,
                            color: Colors.redAccent, size: 20),
                        onPressed: _deletePlaylist,
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
          body: SafeArea(
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: contentMaxWidth),
                child: Column(
                  children: [
                    // Header Banner Card
                    Container(
                      margin: EdgeInsets.symmetric(
                        horizontal: isDesktop ? 32 : 16,
                        vertical: 12,
                      ),
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: _surfaceDark,
                        borderRadius: BorderRadius.circular(18),
                        border:
                            Border.all(color: _outline.withValues(alpha: 0.15)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.25),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: isDesktop ? 80 : 64,
                            height: isDesktop ? 80 : 64,
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Color(0xFF0288D1), Color(0xFF01579B)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: _tracks.isNotEmpty
                                ? LocalAlbumArt(
                                    path: _tracks.first.path,
                                    size: isDesktop ? 80 : 64,
                                    shape: Shapes.pill,
                                  )
                                : const Icon(Icons.queue_music_rounded,
                                    color: Colors.white, size: 36),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _currentPlaylist.name,
                                  style: TextStyle(
                                    fontSize: isDesktop ? 22 : 18,
                                    fontWeight: FontWeight.bold,
                                    color: _textPrimary,
                                    letterSpacing: -0.3,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${_tracks.length} Track${_tracks.length == 1 ? '' : 's'} • Custom Playlist',
                                  style:
                                      TextStyle(color: _textDark, fontSize: 13),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: Icon(Icons.shuffle_rounded,
                                    color: _primary, size: 24),
                                tooltip: 'Shuffle Play',
                                onPressed: () => _playAll(shuffle: true),
                              ),
                              const SizedBox(width: 4),
                              ElevatedButton.icon(
                                onPressed: () => _playAll(shuffle: false),
                                icon: const Icon(Icons.play_arrow_rounded,
                                    color: Colors.white, size: 20),
                                label: const Text('Play'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: _primary,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16, vertical: 10),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    // Track List
                    Expanded(
                      child: _tracks.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.playlist_remove_rounded,
                                      size: 56,
                                      color: _textDark.withValues(alpha: 0.4)),
                                  const SizedBox(height: 12),
                                  Text(
                                    'Playlist is empty',
                                    style: TextStyle(
                                      color: _textPrimary,
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Select tracks in the Tracks tab to add here.',
                                    style: TextStyle(
                                        color: _textDark, fontSize: 13),
                                  ),
                                ],
                              ),
                            )
                          : ListView.builder(
                              padding: EdgeInsets.symmetric(
                                horizontal: isDesktop ? 32 : 16,
                                vertical: 8,
                              ).copyWith(bottom: 120),
                              itemCount: _tracks.length,
                              itemBuilder: (context, index) {
                                final song = _tracks[index];
                                final isFirst = index == 0;
                                final isLast = index == _tracks.length - 1;
                                final borderRadius = BorderRadius.only(
                                  topLeft: Radius.circular(isFirst ? 20 : 6),
                                  topRight: Radius.circular(isFirst ? 20 : 6),
                                  bottomLeft: Radius.circular(isLast ? 20 : 6),
                                  bottomRight: Radius.circular(isLast ? 20 : 6),
                                );

                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 3.0),
                                  child: Material(
                                    color: _surfaceDark,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: borderRadius,
                                      side: BorderSide(
                                        color: _outline.withValues(alpha: 0.12),
                                        width: 1.0,
                                      ),
                                    ),
                                    clipBehavior: Clip.antiAlias,
                                    child: InkWell(
                                      onTap: () {
                                        final paths =
                                            _tracks.map((e) => e.path).toList();
                                        widget.onPlayFolder(paths,
                                            initialIndex: index);
                                      },
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 14, vertical: 10),
                                        child: Row(
                                          children: [
                                            LocalAlbumArt(
                                              path: song.path,
                                              size: isDesktop ? 48 : 42,
                                              shape: Shapes.pill,
                                            ),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Text(
                                                    song.title,
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: TextStyle(
                                                      fontSize:
                                                          isDesktop ? 15 : 13.5,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                      color: _textPrimary,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 2),
                                                  Text(
                                                    song.artist !=
                                                            'Unknown Artist'
                                                        ? song.artist
                                                        : 'Local File',
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: TextStyle(
                                                      fontSize:
                                                          isDesktop ? 13 : 11.5,
                                                      color: _textDark,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            IconButton(
                                              icon: Icon(
                                                Icons
                                                    .remove_circle_outline_rounded,
                                                color: Colors.redAccent
                                                    .withValues(alpha: 0.8),
                                                size: 20,
                                              ),
                                              tooltip: 'Remove from playlist',
                                              onPressed: () =>
                                                  _removeTrack(song),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
