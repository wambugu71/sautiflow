import 'dart:io';
import 'package:material_ui/material_ui.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:flutter_m3shapes_extended/flutter_m3shapes_extended.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';
import 'package:shimmer/shimmer.dart';

import 'models/local_song_item.dart';
import 'services/app_theme_service.dart';
import 'services/m3u_playlist_service.dart';
import 'widgets/local_album_art.dart';

sealed class PlaylistDetailState {
  const PlaylistDetailState();
}

class PlaylistDetailLoading extends PlaylistDetailState {
  const PlaylistDetailLoading();
}

class PlaylistDetailLoaded extends PlaylistDetailState {
  final SavedM3uPlaylist playlist;
  final List<LocalSongItem> tracks;
  const PlaylistDetailLoaded({required this.playlist, required this.tracks});
}

class PlaylistDetailError extends PlaylistDetailState {
  final String message;
  const PlaylistDetailError(this.message);
}

class PlaylistDetailReactiveController extends ValueNotifier<PlaylistDetailState> {
  SavedM3uPlaylist playlist;

  PlaylistDetailReactiveController({required this.playlist})
      : super(PlaylistDetailLoaded(
          playlist: playlist,
          tracks: List.from(playlist.tracks),
        ));

  SavedM3uPlaylist get currentPlaylist => playlist;
  List<LocalSongItem> get tracks {
    final s = value;
    return s is PlaylistDetailLoaded ? s.tracks : playlist.tracks;
  }

  void updatePlaylist(SavedM3uPlaylist updated) {
    playlist = updated;
    value = PlaylistDetailLoaded(
      playlist: playlist,
      tracks: List.from(playlist.tracks),
    );
  }

  Future<bool> rename(String newName) async {
    final updated = await M3uPlaylistService.instance.renamePlaylist(
      playlistId: playlist.id,
      newName: newName,
    );
    if (updated != null) {
      updatePlaylist(updated);
      return true;
    }
    return false;
  }

  Future<bool> removeTrack(LocalSongItem track) async {
    final updated = await M3uPlaylistService.instance.removeTrackFromPlaylist(
      playlistId: playlist.id,
      trackPath: track.path,
    );
    if (updated != null) {
      updatePlaylist(updated);
      return true;
    }
    return false;
  }
}

class _PlaylistDetailShimmerView extends StatelessWidget {
  final bool isDesktop;

  const _PlaylistDetailShimmerView({required this.isDesktop});

  @override
  Widget build(BuildContext context) {
    final surface = context.cardDark;
    final highlight = surface.withValues(alpha: 0.55);

    return Shimmer.fromColors(
      baseColor: surface,
      highlightColor: highlight,
      child: Column(
        children: [
          // Banner Skeleton
          Container(
            margin: EdgeInsets.symmetric(
              horizontal: isDesktop ? 32 : 16,
              vertical: 12,
            ),
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: surface,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Row(
              children: [
                Container(
                  width: isDesktop ? 80 : 64,
                  height: isDesktop ? 80 : 64,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 160,
                        height: 18,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        width: 110,
                        height: 12,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  width: 72,
                  height: 38,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
              ],
            ),
          ),
          // Track Rows Skeleton
          Expanded(
            child: ListView.builder(
              padding: EdgeInsets.symmetric(
                horizontal: isDesktop ? 32 : 16,
                vertical: 8,
              ),
              itemCount: 8,
              itemBuilder: (context, i) {
                final isFirst = i == 0;
                final isLast = i == 7;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 3.0),
                  child: Container(
                    height: isDesktop ? 68 : 58,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: surface,
                      borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(isFirst ? 20 : 6),
                        topRight: Radius.circular(isFirst ? 20 : 6),
                        bottomLeft: Radius.circular(isLast ? 20 : 6),
                        bottomRight: Radius.circular(isLast ? 20 : 6),
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: isDesktop ? 48 : 42,
                          height: isDesktop ? 48 : 42,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: double.infinity,
                                height: 13,
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ),
                              const SizedBox(height: 6),
                              Container(
                                width: 140,
                                height: 10,
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Container(
                          width: 24,
                          height: 24,
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

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
  late final PlaylistDetailReactiveController _controller;

  Color get _bgDark => context.bgDark;
  Color get _surfaceDark => context.cardDark;
  Color get _primary => context.primaryColor;
  Color get _textPrimary => context.textPrimary;
  Color get _textDark => context.textMuted;
  Color get _outline => context.outlineColor;

  SavedM3uPlaylist get _currentPlaylist => _controller.currentPlaylist;
  List<LocalSongItem> get _tracks => _controller.tracks;

  @override
  void initState() {
    super.initState();
    _controller = PlaylistDetailReactiveController(playlist: widget.playlist);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
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

  void _playAt(int index) {
    if (_tracks.isEmpty || index < 0 || index >= _tracks.length) return;
    final paths = _tracks.map((e) => e.path).toList();
    widget.onPlayFolder(paths, initialIndex: index);
  }

  Future<void> _renamePlaylist() async {
    final textController = TextEditingController(text: _currentPlaylist.name);
    final confirm = await M3EDialog.show<bool>(
      context,
      dialog: M3EDialog(
        title: 'Rename Playlist',
        topDivider: true,
        bottomDivider: true,
        content: Material(
          color: Colors.transparent,
          child: TextField(
            controller: textController,
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

    if (confirm == true && textController.text.trim().isNotEmpty) {
      final success = await _controller.rename(textController.text.trim());
      if (success && mounted) {
        widget.onPlaylistUpdated?.call();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Renamed playlist to "${_currentPlaylist.name}"')),
        );
      }
    }
  }

  Future<void> _removeTrack(LocalSongItem track) async {
    final success = await _controller.removeTrack(track);
    if (success && mounted) {
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

  String _formatFileSize(int bytes) {
    if (bytes <= 0) return '';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
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
            title: ValueListenableBuilder<PlaylistDetailState>(
              valueListenable: _controller,
              builder: (context, _, __) {
                return Text(
                  _currentPlaylist.name,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: _textPrimary,
                    fontSize: isDesktop ? 22 : 18,
                  ),
                );
              },
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
                child: ValueListenableBuilder<PlaylistDetailState>(
                  valueListenable: _controller,
                  builder: (context, state, _) {
                    if (state is PlaylistDetailLoading) {
                      return _PlaylistDetailShimmerView(isDesktop: isDesktop);
                    }

                    return Column(
                      children: [
                        // Header Banner Card
                        _buildBannerCard(isDesktop),

                        // Track List
                        Expanded(
                          child: _tracks.isEmpty
                              ? _buildEmptyState()
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
                                    return _buildTrackRow(
                                      index,
                                      song,
                                      isDesktop: isDesktop,
                                      isFirst: isFirst,
                                      isLast: isLast,
                                    );
                                  },
                                ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildBannerCard(bool isDesktop) {
    return Container(
      margin: EdgeInsets.symmetric(
        horizontal: isDesktop ? 32 : 16,
        vertical: 12,
      ),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _surfaceDark,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _outline.withValues(alpha: 0.15)),
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
                  style: TextStyle(color: _textDark, fontSize: 13),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: Icon(Icons.shuffle_rounded, color: _primary, size: 24),
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
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.playlist_remove_rounded,
              size: 56, color: _textDark.withValues(alpha: 0.4)),
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
            style: TextStyle(color: _textDark, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildTrackRow(
    int index,
    LocalSongItem song, {
    required bool isDesktop,
    required bool isFirst,
    required bool isLast,
  }) {
    final borderRadius = BorderRadius.only(
      topLeft: Radius.circular(isFirst ? 20 : 6),
      topRight: Radius.circular(isFirst ? 20 : 6),
      bottomLeft: Radius.circular(isLast ? 20 : 6),
      bottomRight: Radius.circular(isLast ? 20 : 6),
    );

    final rawExt = p.extension(song.path).replaceFirst('.', '').toUpperCase();
    final formatTag = rawExt.isNotEmpty ? rawExt : 'AUDIO';
    final hasAlbum = song.album.isNotEmpty && song.album != 'Unknown Album';
    final sizeStr = _formatFileSize(song.sizeBytes);

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
          onTap: () => _playAt(index),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
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
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        song.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: isDesktop ? 15 : 13.5,
                          fontWeight: FontWeight.w600,
                          color: _textPrimary,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              song.artist != 'Unknown Artist'
                                  ? song.artist
                                  : 'Local File',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: isDesktop ? 13 : 11.5,
                                color: _textDark,
                              ),
                            ),
                          ),
                          if (hasAlbum) ...[
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 5),
                              child: Container(
                                width: 3,
                                height: 3,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: _textDark.withValues(alpha: 0.5),
                                ),
                              ),
                            ),
                            Icon(Icons.album_outlined,
                                size: 11,
                                color: _textDark.withValues(alpha: 0.7)),
                            const SizedBox(width: 3),
                            Flexible(
                              child: Text(
                                song.album,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: isDesktop ? 12.5 : 11,
                                  color: _textDark.withValues(alpha: 0.8),
                                ),
                              ),
                            ),
                          ],
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 4.5, vertical: 1),
                            decoration: BoxDecoration(
                              color: _primary.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              formatTag,
                              style: TextStyle(
                                color: _primary,
                                fontSize: 9.5,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.4,
                              ),
                            ),
                          ),
                          if (sizeStr.isNotEmpty) ...[
                            const SizedBox(width: 4),
                            Text(
                              sizeStr,
                              style: TextStyle(
                                color: _textDark.withValues(alpha: 0.7),
                                fontSize: 10.5,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.play_circle_outline_rounded, size: 22),
                  color: _primary,
                  tooltip: 'Play track',
                  onPressed: () => _playAt(index),
                ),
                M3EMenu(
                  anchorBuilder: (context, open) => IconButton(
                    icon: Icon(
                      Icons.more_vert_rounded,
                      color: _textDark.withValues(alpha: 0.7),
                      size: 18,
                    ),
                    onPressed: open,
                  ),
                  children: [
                    M3EMenuGroup.entries(
                      entries: [
                        M3EMenuEntry(
                          label: 'Play',
                          leading: const Icon(Icons.play_arrow_rounded, size: 18),
                          onPressed: () => _playAt(index),
                        ),
                        M3EMenuEntry(
                          label: 'Share Audio File',
                          leading: const Icon(Icons.share_outlined, size: 18),
                          onPressed: () {
                            Share.shareXFiles([XFile(song.path)], text: song.title);
                          },
                        ),
                        M3EMenuEntry(
                          label: 'Remove from Playlist',
                          leading: const Icon(Icons.delete_outline_rounded,
                              color: Colors.redAccent, size: 18),
                          onPressed: () => _removeTrack(song),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
