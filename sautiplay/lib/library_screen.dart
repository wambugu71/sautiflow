import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:audio_metadata_reader/audio_metadata_reader.dart' as amr;
import 'package:file_picker/file_picker.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:loading_indicator_m3e/loading_indicator_m3e.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:flutter_m3shapes_extended/flutter_m3shapes_extended.dart';
import 'package:path/path.dart' as p;
import 'package:permission_handler/permission_handler.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sautiflow/sautiflow.dart';
import 'services/m3u_playlist_service.dart';

import 'album_detail_screen.dart';
import 'artist_profile_screen.dart';
import 'isolate_player.dart';
import 'services/app_theme_service.dart';
import 'liked_songs_screen.dart'; // NEW
import 'models/liked_song.dart'; // NEW
import 'models/local_song_item.dart';
import 'network_sources_screen.dart';
import 'services/audio_file_inspector.dart';
import 'widgets/local_album_art.dart';
import 'widgets/music_info_dialog.dart';
import 'widgets/song_options_menu.dart';

class LibraryScreen extends StatefulWidget {
  final Future<void> Function(List<String> audioFilePaths, {int initialIndex})
      onPlayFolder;
  final Future<void> Function(List<LikedSong> tracks, {int initialIndex})
      onPlayLikedSongs; // NEW
  final Future<void> Function(List<TrackInfo> tracks, {int initialIndex})?
      onPlayTracks;
  final Function(TrackInfo track)? onQueueTrack;
  final Function(String filePath)? onDeleteTrack;
  final IsolateAudioPlayer? player;
  final void Function(String filePath, String title, String artist)?
      onPlayNetworkFile;
  final void Function(List<dynamic> entries, dynamic config, int initialIndex)?
      onPlayFtpFolder;
  final bool isNested;
  final int initialTabIndex;

  const LibraryScreen({
    super.key,
    required this.onPlayFolder,
    required this.onPlayLikedSongs,
    this.onPlayTracks,
    this.onQueueTrack,
    this.onDeleteTrack,
    this.player,
    this.onPlayNetworkFile,
    this.onPlayFtpFolder,
    this.isNested = false,
    this.initialTabIndex = 0,
  });

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

enum TrackViewMode {
  list('Standard List', Icons.view_list_rounded),
  compact('Compact List', Icons.format_list_bulleted_rounded),
  grid('Grid View', Icons.grid_view_rounded);

  const TrackViewMode(this.label, this.icon);
  final String label;
  final IconData icon;
}

class _LibraryScreenState extends State<LibraryScreen>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;
  static const String _prefsKey = 'sautiplay_library_folders';
  static const String _cachedSongsKey = 'sautiplay_library_cached_songs';

  Color get _bgDark => context.bgDark;
  Color get _surfaceDark => context.cardDark;
  Color get _primary => context.primaryColor;
  Color get _textPrimary => context.textPrimary;
  Color get _textDark => context.textMuted;
  Color get _outline => context.outlineColor;

  // State
  List<Map<String, dynamic>> _folders = [];
  List<LocalSongItem> _allSongs = [];
  List<LocalSongItem> _filteredSongs = [];
  List<SavedM3uPlaylist> _m3uPlaylists = [];
  bool _isLoading = true;
  bool _isScanning = false;
  String _scanStatus = 'Checking library for changes...';
  int _tabIndex = 0;
  TrackViewMode _trackViewMode = TrackViewMode.list;
  String _groupByOption = 'None';

  // Search & Sort filters
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _artistSearchController = TextEditingController();
  final TextEditingController _albumSearchController = TextEditingController();
  final TextEditingController _genreSearchController = TextEditingController();
  String _currentSort = 'Name (A-Z)';
  static const List<String> _sortOptions = [
    'Name (A-Z)',
    'Name (Z-A)',
    'Date Added (New-Old)',
    'Date Added (Old-New)',
    'Size (Largest)',
    'Size (Smallest)',
  ];
  static const List<String> _groupByOptions = [
    'None',
    'Album',
    'Artist',
    'Genre',
    'Folder',
  ];

  @override
  void initState() {
    super.initState();
    _tabIndex = widget.initialTabIndex;
    _loadSavedFolders();
    _loadSavedM3uPlaylists();
  }

  @override
  void didUpdateWidget(LibraryScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialTabIndex != widget.initialTabIndex) {
      setState(() {
        _tabIndex = widget.initialTabIndex;
      });
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _artistSearchController.dispose();
    _albumSearchController.dispose();
    _genreSearchController.dispose();
    super.dispose();
  }

  Future<void> _loadSavedM3uPlaylists() async {
    try {
      final list = await M3uPlaylistService.instance.loadPlaylists();
      if (mounted) {
        setState(() {
          _m3uPlaylists = list;
        });
      }
    } catch (e) {
      debugPrint('Error loading M3U playlists: $e');
    }
  }

  Future<void> _importM3uFile() async {
    final hasPerm = await _requestPermissions();
    if (!hasPerm) return;

    String? path;
    try {
      if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
        const typeGroup = XTypeGroup(
          label: 'M3U Playlists',
          extensions: <String>['m3u', 'm3u8'],
        );
        final XFile? file =
            await openFile(acceptedTypeGroups: <XTypeGroup>[typeGroup]);
        path = file?.path;
      } else {
        final result = await FilePicker.pickFiles(
          type: FileType.custom,
          allowedExtensions: ['m3u', 'm3u8'],
        );
        if (result != null && result.files.isNotEmpty) {
          path = result.files.single.path;
        }
      }
    } catch (e) {
      debugPrint('Error picking M3U file: $e');
    }

    if (path == null || path.isEmpty) return;

    setState(() => _isLoading = true);

    try {
      final sources = await AudioSource.fromM3u(path);
      final playlistName = p.basenameWithoutExtension(path);
      final tracks = sources.map((s) {
        return LocalSongItem(
          path: s.uri.scheme == 'file' ? s.uri.toFilePath() : s.uri.toString(),
          title: s.title ??
              (s.uri.scheme == 'file'
                  ? p.basenameWithoutExtension(s.uri.toFilePath())
                  : s.uri.toString()),
          artist: s.artist ?? 'Unknown Artist',
          album: playlistName,
          sizeBytes: 0,
          lastModified: DateTime.now(),
        );
      }).toList();

      final newPlaylist = SavedM3uPlaylist(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        name: playlistName,
        pathOrUrl: path,
        isNetwork: false,
        tracks: tracks,
        dateAdded: DateTime.now(),
      );

      await M3uPlaylistService.instance.saveSinglePlaylist(newPlaylist);
      await _loadSavedM3uPlaylists();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  'Imported M3U playlist "$playlistName" (${tracks.length} tracks)')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to import M3U file: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _importM3uUrlDialog() async {
    final urlController = TextEditingController();
    final nameController = TextEditingController();
    final textDark = context.textMuted;
    final cardDark = context.cardDark;
    final textPrimary = context.textPrimary;

    final isMobile = MediaQuery.of(context).size.width < 600;

    final dialogContent = Material(
      color: Colors.transparent,
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: nameController,
            style: TextStyle(color: textPrimary),
            decoration: InputDecoration(
              labelText: 'Playlist Name (Optional)',
              labelStyle: TextStyle(color: textDark),
              hintText: 'e.g. Live Radio Stations',
              hintStyle: TextStyle(color: textDark.withValues(alpha: 0.6)),
              filled: true,
              fillColor: cardDark,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: urlController,
            style: TextStyle(color: textPrimary),
            decoration: InputDecoration(
              labelText: 'Stream / M3U URL',
              labelStyle: TextStyle(color: textDark),
              hintText: 'https://example.com/playlist.m3u8',
              hintStyle: TextStyle(color: textDark.withValues(alpha: 0.6)),
              filled: true,
              fillColor: cardDark,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          ],
        ),
      ),
    );

    final confirm = isMobile
        ? await M3EBottomSheet.show<bool>(
            context,
            builder: (ctx) => Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 20,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Import Stream URL',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  dialogContent,
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      M3EButton(
                        onPressed: () => Navigator.of(ctx).pop(false),
                        child: const Text('Cancel'),
                      ),
                      const SizedBox(width: 10),
                      M3EButton(
                        onPressed: () => Navigator.of(ctx).pop(true),
                        child: const Text('Import Stream'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          )
        : await M3EDialog.show<bool>(
            context,
            dialog: M3EDialog(
              title: 'Import Stream URL',
              topDivider: true,
              bottomDivider: true,
              content: SizedBox(
                width: 480,
                child: dialogContent,
              ),
              actions: [
                M3EButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Cancel'),
                ),
                M3EButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('Import Stream'),
                ),
              ],
            ),
          );

    if (confirm != true || urlController.text.trim().isEmpty) return;

    final url = urlController.text.trim();
    final customName = nameController.text.trim();

    setState(() => _isLoading = true);

    try {
      final sources = await AudioSource.fromM3u(url);
      final playlistName =
          customName.isNotEmpty ? customName : 'M3U Web Stream';
      final tracks = sources.map((s) {
        return LocalSongItem(
          path: s.uri.scheme == 'file' ? s.uri.toFilePath() : s.uri.toString(),
          title: s.title ??
              (s.uri.scheme == 'file'
                  ? p.basenameWithoutExtension(s.uri.toFilePath())
                  : s.uri.toString()),
          artist: s.artist ?? 'Radio Stream',
          album: playlistName,
          sizeBytes: 0,
          lastModified: DateTime.now(),
        );
      }).toList();

      final newPlaylist = SavedM3uPlaylist(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        name: playlistName,
        pathOrUrl: url,
        isNetwork: true,
        tracks: tracks,
        dateAdded: DateTime.now(),
      );

      await M3uPlaylistService.instance.saveSinglePlaylist(newPlaylist);
      await _loadSavedM3uPlaylists();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  'Imported M3U stream "$playlistName" (${tracks.length} tracks)')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load M3U URL: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _playM3uPlaylist(SavedM3uPlaylist playlist) {
    if (playlist.tracks.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Playlist has no playable tracks.')),
      );
      return;
    }
    final paths = playlist.tracks.map((t) => t.path).toList();
    widget.onPlayFolder(paths);
  }

  Future<void> _showM3uPlaylistOptions(SavedM3uPlaylist playlist) async {
    await M3EBottomSheet.show<void>(
      context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              M3EListItem(
                headline: 'Play "${playlist.name}"',
                leading: Icon(
                  Icons.play_arrow_rounded,
                  color: AppThemeService.instance.currentData.primary,
                ),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _playM3uPlaylist(playlist);
                },
              ),
              M3EListItem(
                headline: 'Export Playlist as .m3u8',
                leading: const Icon(
                  Icons.file_upload_outlined,
                  color: Colors.amberAccent,
                ),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _exportPlaylistToM3u8(playlist.name, playlist.tracks);
                },
              ),
              M3EListItem(
                headline: 'Delete Playlist',
                leading: const Icon(
                  Icons.delete_outline_rounded,
                  color: Colors.redAccent,
                ),
                onTap: () async {
                  Navigator.of(ctx).pop();
                  await M3uPlaylistService.instance.deletePlaylist(playlist.id);
                  await _loadSavedM3uPlaylists();
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Deleted playlist "${playlist.name}"'),
                      ),
                    );
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _exportPlaylistToM3u8(
      String name, List<LocalSongItem> tracks) async {
    if (tracks.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No tracks available to export.')),
      );
      return;
    }
    String? targetPath;
    final m3uContent = M3uPlaylistService.instance.generateM3u8Content(
      playlistName: name,
      tracks: tracks,
    );
    final bytes = Uint8List.fromList(utf8.encode(m3uContent));

    try {
      if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
        final FileSaveLocation? location = await getSaveLocation(
          suggestedName: '${name.replaceAll(' ', '_')}.m3u8',
          acceptedTypeGroups: const [
            XTypeGroup(label: 'M3U8 Playlist', extensions: ['m3u8']),
          ],
        );
        targetPath = location?.path;
        if (targetPath != null && targetPath.isNotEmpty) {
          await M3uPlaylistService.instance.exportToM3u8(
            targetFilePath: targetPath,
            playlistName: name,
            tracks: tracks,
          );
        }
      } else {
        targetPath = await FilePicker.saveFile(
          dialogTitle: 'Export Playlist to M3U8',
          fileName: '${name.replaceAll(' ', '_')}.m3u8',
          type: FileType.custom,
          allowedExtensions: ['m3u8'],
          bytes: bytes,
        );
      }
    } catch (e) {
      debugPrint('Error opening save dialog: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to export playlist: $e')),
        );
      }
      return;
    }

    if (targetPath != null && targetPath.isNotEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Exported playlist to ${p.basename(targetPath)}')),
        );
      }
    }
  }

  Future<void> _loadSavedFolders() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedData = prefs.getStringList(_prefsKey) ?? [];

      final loadedFolders = savedData
          .map((item) => jsonDecode(item) as Map<String, dynamic>)
          .toList();

      final cachedSongsData = prefs.getStringList(_cachedSongsKey) ?? [];
      final loadedSongs = <LocalSongItem>[];
      for (final jsonStr in cachedSongsData) {
        try {
          final map = jsonDecode(jsonStr) as Map<String, dynamic>;
          loadedSongs.add(LocalSongItem.fromJson(map));
        } catch (_) {}
      }

      setState(() {
        _folders = loadedFolders;
        _allSongs = loadedSongs;
        _isLoading = false; // Show cached songs immediately!
        _applySearchAndSort();
      });

      // Run non-blocking delta scan in the background
      await _smartScanFolders(
          showFullLoading: loadedSongs.isEmpty && loadedFolders.isNotEmpty);
    } catch (e) {
      debugPrint('Error loading folders: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _saveCachedSongs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final strList = _allSongs.map((s) => jsonEncode(s.toJson())).toList();
      await prefs.setStringList(_cachedSongsKey, strList);
    } catch (e) {
      debugPrint('Error saving cached songs: $e');
    }
  }

  static Future<String> _computeFastFileHash(File file, int sizeBytes) async {
    if (sizeBytes <= 0) return '';
    try {
      if (!await file.exists()) return '';
      final raf = await file.open(mode: FileMode.read);
      try {
        final sampleSize = sizeBytes > 65536 ? 65536 : sizeBytes;
        final headerBytes = await raf.read(sampleSize);

        int checksum = 5381;
        for (int i = 0; i < headerBytes.length; i += 4) {
          checksum = ((checksum << 5) + checksum) ^ headerBytes[i];
        }

        if (sizeBytes > 131072) {
          await raf.setPosition(sizeBytes - 65536);
          final tailBytes = await raf.read(65536);
          for (int i = 0; i < tailBytes.length; i += 4) {
            checksum = ((checksum << 5) + checksum) ^ tailBytes[i];
          }
        }

        return '${sizeBytes}_${checksum.toRadixString(16)}';
      } finally {
        await raf.close();
      }
    } catch (_) {
      return '';
    }
  }

  Future<void> _smartScanFolders({bool showFullLoading = false}) async {
    if (_folders.isEmpty) {
      if (mounted) {
        setState(() {
          _allSongs = [];
          _filteredSongs = [];
          _isLoading = false;
          _isScanning = false;
        });
      }
      await _saveCachedSongs();
      return;
    }

    if (showFullLoading) {
      setState(() => _isLoading = true);
    } else {
      setState(() {
        _isScanning = true;
        _scanStatus = 'Checking folders for updates...';
      });
    }

    final existingSongsMap = <String, LocalSongItem>{
      for (final song in _allSongs)
        p.canonicalize(song.path).toLowerCase(): song
    };

    final updatedSongs = <LocalSongItem>[];
    final seenSongHashes = <String>{};
    bool changesDetected = false;
    int newSongsScanned = 0;

    for (final f in _folders) {
      final folderPath = f['path'] as String;
      final audioPaths = await _scanForAudioFiles(folderPath);

      if (f['count'] != audioPaths.length) {
        f['count'] = audioPaths.length;
        changesDetected = true;
      }

      for (final path in audioPaths) {
        final canonicalPath = p.canonicalize(path);
        final key = canonicalPath.toLowerCase();

        try {
          final file = File(canonicalPath);
          final stat = await file.stat();
          final existing = existingSongsMap[key];

          String? hash = existing?.fileHash;
          if (hash == null || hash.isEmpty) {
            hash = await _computeFastFileHash(file, stat.size);
          }

          final dedupeKey = hash.isNotEmpty ? hash : key;

          // Ensure each physical file content is added to updatedSongs ONLY ONCE by hash
          if (!seenSongHashes.add(dedupeKey)) {
            continue;
          }

          // Re-use cached metadata if file size and modified timestamp match
          if (existing != null &&
              existing.sizeBytes == stat.size &&
              existing.lastModified.millisecondsSinceEpoch ==
                  stat.modified.millisecondsSinceEpoch) {
            updatedSongs.add(existing.fileHash == hash
                ? existing
                : LocalSongItem.fallback(
                    existing.path,
                    existing.sizeBytes,
                    existing.lastModified,
                    title: existing.title,
                    artist: existing.artist,
                    album: existing.album,
                    genre: existing.genre,
                    fileHash: hash,
                  ));
          } else {
            changesDetected = true;
            newSongsScanned++;
            if (mounted && !showFullLoading) {
              setState(() {
                _scanStatus = 'Scanning new songs ($newSongsScanned)...';
              });
            }

            String? metaTitle;
            String? metaArtist;
            String? metaAlbum;
            String? metaGenre;
            try {
              final meta = amr.readMetadata(file, getImage: false);
              if (meta.title != null && meta.title!.isNotEmpty) {
                metaTitle = meta.title;
              }
              if (meta.artist != null && meta.artist!.isNotEmpty) {
                metaArtist = meta.artist;
              }
              if (meta.album != null && meta.album!.isNotEmpty) {
                metaAlbum = meta.album;
              }
              if (meta.genres.isNotEmpty && meta.genres.first.isNotEmpty) {
                metaGenre = meta.genres.first;
              }
            } catch (_) {}

            updatedSongs.add(LocalSongItem.fallback(
              canonicalPath,
              stat.size,
              stat.modified,
              title: metaTitle,
              artist: metaArtist,
              album: metaAlbum,
              genre: metaGenre,
              fileHash: hash,
            ));
          }
        } catch (_) {
          updatedSongs
              .add(LocalSongItem.fallback(canonicalPath, 0, DateTime.now()));
        }
      }
    }

    if (updatedSongs.length != _allSongs.length) {
      changesDetected = true;
    }

    if (mounted) {
      setState(() {
        _allSongs = updatedSongs;
        _isLoading = false;
        _isScanning = false;
        _applySearchAndSort();
      });
    }

    if (changesDetected) {
      await _saveFolders();
      await _saveCachedSongs();
    }
  }

  Future<void> _updateAllSongs() async {
    await _smartScanFolders(showFullLoading: false);
  }

  void _applySearchAndSort() {
    var list = _allSongs.toList();
    final query = _searchController.text.toLowerCase();

    if (query.isNotEmpty) {
      list = list.where((s) => s.title.toLowerCase().contains(query)).toList();
    }

    switch (_currentSort) {
      case 'Name (A-Z)':
        list.sort((a, b) => a.title.compareTo(b.title));
        break;
      case 'Name (Z-A)':
        list.sort((a, b) => b.title.compareTo(a.title));
        break;
      case 'Date Added (New-Old)':
        list.sort((a, b) => b.lastModified.compareTo(a.lastModified));
        break;
      case 'Date Added (Old-New)':
        list.sort((a, b) => a.lastModified.compareTo(b.lastModified));
        break;
      case 'Size (Largest)':
        list.sort((a, b) => b.sizeBytes.compareTo(a.sizeBytes));
        break;
      case 'Size (Smallest)':
        list.sort((a, b) => a.sizeBytes.compareTo(b.sizeBytes));
        break;
    }

    setState(() {
      _filteredSongs = list;
    });
  }

  Future<void> _saveFolders() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final strList = _folders.map((f) => jsonEncode(f)).toList();
      await prefs.setStringList(_prefsKey, strList);
    } catch (e) {
      debugPrint('Error saving folders: $e');
    }
  }

  Future<bool> _requestPermissions() async {
    if (Platform.isAndroid) {
      var status = await Permission.storage.status;
      if (!status.isGranted) {
        status = await Permission.storage.request();
      }
      var audioStatus = await Permission.audio.status;
      if (!audioStatus.isGranted) {
        audioStatus = await Permission.audio.request();
      }
      return status.isGranted || audioStatus.isGranted;
    }
    return true; // Assume iOS/Desktop permissions are handled at pick time
  }

  Future<List<String>> _scanForAudioFiles(String dirPath) async {
    final audioFiles = <String>[];
    final seenPaths = <String>{};
    final dir = Directory(dirPath);
    if (!await dir.exists()) return audioFiles;

    const allowedExtensions = {'.mp3', '.m4a', '.wav', '.flac', '.aac', '.ogg'};

    try {
      await for (final entity
          in dir.list(recursive: true, followLinks: false)) {
        if (entity is File) {
          final ext = p.extension(entity.path).toLowerCase();
          if (allowedExtensions.contains(ext)) {
            final canonicalPath = p.canonicalize(entity.path);
            if (seenPaths.add(canonicalPath.toLowerCase())) {
              audioFiles.add(canonicalPath);
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Error reading directory: $e');
    }

    return audioFiles;
  }

  void _navigateToNetworkSources() {
    if (widget.player == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Player engine unavailable.')),
      );
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => NetworkSourcesScreen(
          player: widget.player!,
          onPlayNetworkFile: widget.onPlayNetworkFile,
          onPlayFtpFolder: widget.onPlayFtpFolder,
        ),
      ),
    );
  }

  Future<void> _addDirectory() async {
    final hasPerm = await _requestPermissions();
    if (!hasPerm) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Storage permissions are required to add folders.')),
      );
      return;
    }

    String? selectedDirectory;
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      selectedDirectory = await getDirectoryPath();
    } else {
      selectedDirectory = await FilePicker.getDirectoryPath();
    }
    if (selectedDirectory == null) return;

    final canonicalSelected = p.canonicalize(selectedDirectory);

    // 1. Check if selectedDirectory is inside/subfolder of an existing tracked folder
    bool isAlreadyCovered = false;
    for (final f in _folders) {
      final existingPath = p.canonicalize(f['path'] as String);
      if (canonicalSelected == existingPath ||
          p.isWithin(existingPath, canonicalSelected)) {
        isAlreadyCovered = true;
        break;
      }
    }

    if (isAlreadyCovered) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Folder (or its parent) is already in your library.'),
        ),
      );
      return;
    }

    // 2. Check if selectedDirectory is a parent of any existing tracked folder(s)
    final remainingFolders = <Map<String, dynamic>>[];
    int subsumedCount = 0;
    for (final f in _folders) {
      final existingPath = p.canonicalize(f['path'] as String);
      if (p.isWithin(canonicalSelected, existingPath)) {
        subsumedCount++;
      } else {
        remainingFolders.add(f);
      }
    }

    setState(() => _isLoading = true);

    final audioPaths = await _scanForAudioFiles(canonicalSelected);

    final newFolder = {
      'path': canonicalSelected,
      'name': p.basename(canonicalSelected),
      'count': audioPaths.length,
    };

    setState(() {
      _folders = remainingFolders..add(newFolder);
    });

    await _saveFolders();
    await _updateAllSongs();

    if (mounted && subsumedCount > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Added folder and merged $subsumedCount subfolder(s) into parent library entry.',
          ),
        ),
      );
    }
  }

  Future<void> _removeFolder(int index) async {
    final folderName = _folders[index]['name'] as String;
    final confirm = await M3EDialog.show<bool>(
      context,
      dialog: M3EDialog(
        title: 'Remove Folder?',
        topDivider: true,
        bottomDivider: true,
        content: Text(
          'Remove "$folderName" from your library? Audio files on disk will not be deleted.',
          style: TextStyle(
              color: AppThemeService.instance.currentData.textDark,
              fontSize: 14),
        ),
        actions: [
          M3EButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          M3EButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Remove Folder'),
          ),
        ],
      ),
    );

    if (confirm != true) return;
    setState(() {
      _folders.removeAt(index);
    });
    await _saveFolders();
    await _updateAllSongs();
  }

  Future<void> _removeDuplicateSongs() async {
    if (_allSongs.isEmpty && _folders.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Library is empty.')),
      );
      return;
    }

    final uniqueSongs = <LocalSongItem>[];
    final seenKeys = <String>{};
    int removedSongsCount = 0;

    for (final song in _allSongs) {
      final canonicalPath = p.canonicalize(song.path).toLowerCase();
      final key = (song.fileHash != null && song.fileHash!.isNotEmpty)
          ? song.fileHash!
          : (canonicalPath.isNotEmpty
              ? canonicalPath
              : '${song.title.toLowerCase()}_${song.artist.toLowerCase()}_${song.sizeBytes}');

      if (seenKeys.add(key)) {
        uniqueSongs.add(song);
      } else {
        removedSongsCount++;
      }
    }

    // Deduplicate folder hierarchy in _folders
    final uniqueFolders = <Map<String, dynamic>>[];
    for (final f in _folders) {
      final folderPath = p.canonicalize(f['path'] as String);
      final isSubsumed = uniqueFolders.any((uf) {
        final ufPath = p.canonicalize(uf['path'] as String);
        return folderPath == ufPath || p.isWithin(ufPath, folderPath);
      });
      if (!isSubsumed) {
        uniqueFolders.removeWhere((uf) {
          final ufPath = p.canonicalize(uf['path'] as String);
          return p.isWithin(folderPath, ufPath);
        });
        uniqueFolders.add(f);
      }
    }

    final bool foldersChanged = uniqueFolders.length != _folders.length;

    setState(() {
      _allSongs = uniqueSongs;
      _folders = uniqueFolders;
      _applySearchAndSort();
    });

    await _saveCachedSongs();
    if (foldersChanged) {
      await _saveFolders();
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            (removedSongsCount > 0 || foldersChanged)
                ? 'Removed $removedSongsCount duplicate track(s) and cleaned folder structure.'
                : 'No duplicate songs found in your library.',
          ),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  Future<void> _playFolder(String dirPath) async {
    setState(() => _isLoading = true);
    final audioPaths = await _scanForAudioFiles(dirPath);
    setState(() => _isLoading = false);

    if (audioPaths.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No audio files found in this folder.')),
      );
      return;
    }

    final uniquePaths = <String>[];
    final seen = <String>{};
    for (final path in audioPaths) {
      final key = p.canonicalize(path).toLowerCase();
      if (seen.add(key)) {
        uniquePaths.add(path);
      }
    }

    // Hand off to main player
    widget.onPlayFolder(uniquePaths);
  }

  Future<void> _shufflePlayAll() async {
    if (_allSongs.isEmpty) return;

    final paths = _allSongs.map((e) => e.path).toList();
    paths.shuffle();
    widget.onPlayFolder(paths);
  }

  Future<void> _handleSongOption(LocalSongItem song, SongOption option) async {
    switch (option) {
      case SongOption.queue:
        _queueSong(song);
        break;
      case SongOption.info:
        await _showSongInfo(song);
        break;
      case SongOption.share:
        await _shareSong(song);
        break;
      case SongOption.delete:
        await _confirmAndDeleteSong(song);
        break;
    }
  }

  void _queueSong(LocalSongItem song) {
    final track = TrackInfo(
      videoId: song.path,
      title: song.title,
      artist: song.artist != 'Unknown Artist' ? song.artist : 'Local File',
      thumbnailUrl: null,
    );
    if (widget.onQueueTrack != null) {
      widget.onQueueTrack!(track);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Added "${song.title}" to Queue (Play Next)'),
          duration: const Duration(seconds: 2),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Player queue control unavailable.')),
      );
    }
  }

  Future<void> _showSongInfo(LocalSongItem song) async {
    final file = File(song.path);
    String artist = song.artist;
    String title = song.title;
    String album = 'Unknown Album';
    String genre = 'Unknown Genre';
    String year = '';
    String trackNumber = '';
    Uint8List? albumArt;
    Duration duration = Duration.zero;

    final fileInfo = await AudioFileInspector.inspect(song.path);

    try {
      if (file.existsSync()) {
        final meta = amr.readMetadata(file, getImage: true);
        if (meta.title != null && meta.title!.isNotEmpty) title = meta.title!;
        if (meta.artist != null && meta.artist!.isNotEmpty) {
          artist = meta.artist!;
        }
        if (meta.album != null && meta.album!.isNotEmpty) album = meta.album!;
        if (meta.genres.isNotEmpty && meta.genres.first.isNotEmpty) {
          genre = meta.genres.first;
        }
        if (meta.year != null) year = meta.year.toString();
        if (meta.trackNumber != null) trackNumber = meta.trackNumber.toString();
        if (meta.pictures.isNotEmpty) albumArt = meta.pictures.first.bytes;
        if (meta.duration != null) duration = meta.duration!;
      }
    } catch (_) {}

    if (!mounted) return;

    await MusicInfoDialog.show(
      context,
      title: title,
      artist: artist,
      album: album,
      genre: genre,
      year: year,
      trackNumber: trackNumber,
      albumArt: albumArt,
      sourceType: 'local',
      videoId: song.path,
      codec: fileInfo.codec,
      sampleRate: fileInfo.formattedSampleRate,
      channels: fileInfo.formattedChannels,
      bitDepth: fileInfo.formattedBitDepth,
      fileSizeBytes: song.sizeBytes,
      duration: duration,
      onSaveTags: ({
        required String title,
        required String artist,
        required String album,
        required String genre,
        required String year,
        required String trackNumber,
      }) async {
        setState(() {
          final targetIndex = _allSongs.indexWhere((s) => s.path == song.path);
          if (targetIndex != -1) {
            _allSongs[targetIndex] = LocalSongItem.fallback(
              song.path,
              song.sizeBytes,
              song.lastModified,
              title: title.isNotEmpty ? title : song.title,
              artist: artist.isNotEmpty ? artist : song.artist,
              album: album.isNotEmpty ? album : song.album,
              genre: genre.isNotEmpty ? genre : song.genre,
              fileHash: song.fileHash,
            );
          }
          _applySearchAndSort();
        });
        await _saveCachedSongs();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text(
                    'Saved tags for "${title.isNotEmpty ? title : song.title}"')),
          );
        }
      },
    );
  }

  Future<void> _shareSong(LocalSongItem song) async {
    final file = File(song.path);
    if (!file.existsSync()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Audio file does not exist on disk.')),
      );
      return;
    }
    try {
      final xfile = XFile(song.path);
      await Share.shareXFiles([xfile], text: song.title);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not share file: $e')),
      );
    }
  }

  Future<void> _confirmAndDeleteSong(LocalSongItem song) async {
    final confirm = await M3EDialog.show<bool>(
      context,
      dialog: M3EDialog(
        title: 'Delete Song File',
        topDivider: true,
        bottomDivider: true,
        content: Text(
          'Are you sure you want to delete "${song.title}"? The file will be permanently removed from your storage.',
          style: TextStyle(
              color: AppThemeService.instance.currentData.textDark,
              fontSize: 14),
        ),
        actions: [
          M3EButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          M3EButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete Permanently'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      final file = File(song.path);
      if (file.existsSync()) {
        await file.delete();
      }

      setState(() {
        _allSongs.removeWhere((s) => s.path == song.path);
        _filteredSongs.removeWhere((s) => s.path == song.path);
      });
      await _saveCachedSongs();

      if (widget.onDeleteTrack != null) {
        widget.onDeleteTrack!(song.path);
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Deleted "${song.title}" permanently.'),
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to delete file: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    // Theme colors
    final Color primaryColor = context.primaryColor;
    final Color bgDark = context.bgDark;
    final Color surfaceColor = context.cardDark;
    final Color textLight = context.textPrimary;
    final Color textDark = context.textMuted;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth >= 800;
        final contentMaxWidth = isDesktop ? 1000.0 : double.infinity;

        return Scaffold(
          backgroundColor: bgDark,
          body: SafeArea(
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: contentMaxWidth),
                child: Stack(
                  children: [
                    Column(
                      children: [
                        // Header Region
                        Container(
                          padding: EdgeInsets.only(
                              top: widget.isNested
                                  ? 8.0
                                  : (isDesktop ? 32.0 : 16.0),
                              left: isDesktop ? 32.0 : 16.0,
                              right: isDesktop ? 32.0 : 16.0,
                              bottom: isDesktop ? 12.0 : 8.0),
                          decoration: BoxDecoration(
                            color: bgDark,
                          ),
                          child: Column(
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Row(
                                    children: [
                                      if (!widget.isNested)
                                        Text(
                                          'Your Library',
                                          style: TextStyle(
                                            fontSize: isDesktop ? 30 : 22,
                                            fontWeight: FontWeight.bold,
                                            color: textLight,
                                            letterSpacing: -0.5,
                                          ),
                                        ),
                                    ],
                                  ),
                                  M3EMenu(
                                    anchorBuilder: (context, open) => InkWell(
                                      onTap: open,
                                      borderRadius: BorderRadius.circular(20),
                                      child: Container(
                                        padding: const EdgeInsets.all(6),
                                        decoration: BoxDecoration(
                                          color: surfaceColor,
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                              color: Colors.white
                                                  .withValues(alpha: 0.08)),
                                        ),
                                        child: Icon(Icons.add_rounded,
                                            color: textLight,
                                            size: isDesktop ? 22 : 20),
                                      ),
                                    ),
                                    children: [
                                      M3EMenuGroup.entries(
                                        entries: [
                                          M3EMenuEntry(
                                            label: 'Add Local Folder',
                                            leading: const Icon(
                                                Icons.create_new_folder_rounded,
                                                color: Colors.blueAccent,
                                                size: 20),
                                            onPressed: _addDirectory,
                                          ),
                                          M3EMenuEntry(
                                            label: 'Import M3U / M3U8 File',
                                            leading: const Icon(
                                                Icons.playlist_add_rounded,
                                                color: Colors.cyanAccent,
                                                size: 20),
                                            onPressed: _importM3uFile,
                                          ),
                                          M3EMenuEntry(
                                            label: 'Import M3U Stream URL',
                                            leading: const Icon(
                                                Icons.podcasts_rounded,
                                                color: Colors.tealAccent,
                                                size: 20),
                                            onPressed: _importM3uUrlDialog,
                                          ),
                                          M3EMenuEntry(
                                            label:
                                                'Network Stream (FTP & DLNA)',
                                            leading: const Icon(
                                                Icons.lan_rounded,
                                                color: Colors.lightBlueAccent,
                                                size: 20),
                                            onPressed:
                                                _navigateToNetworkSources,
                                          ),
                                          M3EMenuEntry(
                                            label: 'Clean Up Duplicates',
                                            leading: const Icon(
                                                Icons.cleaning_services_rounded,
                                                color: Colors.orangeAccent,
                                                size: 20),
                                            onPressed: _removeDuplicateSongs,
                                          ),
                                          M3EMenuEntry(
                                            label: 'Export Library to M3U8',
                                            leading: const Icon(
                                                Icons.file_upload_rounded,
                                                color: Colors.amberAccent,
                                                size: 20),
                                            onPressed: () =>
                                                _exportPlaylistToM3u8(
                                                    'SautiPlay_Library',
                                                    _allSongs),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                              SizedBox(height: isDesktop ? 16 : 12),
                              // Segmented Control
                              RepaintBoundary(
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(
                                      isDesktop ? 18 : 14),
                                  child: M3ETabs(
                                    variant: M3ETabsVariant.secondary,
                                    selectedIndex: _tabIndex,
                                    onTabSelected: (i) {
                                      Future.microtask(() {
                                        if (mounted) {
                                          setState(() => _tabIndex = i);
                                        }
                                      });
                                    },
                                    tabs: const [
                                      M3ETab(
                                          label: 'Playlists',
                                          icon:
                                              Icon(Icons.queue_music_rounded)),
                                      M3ETab(
                                          label: 'Tracks',
                                          icon: Icon(Icons.audiotrack_rounded)),
                                      M3ETab(
                                          label: 'Artists',
                                          icon: Icon(
                                              Icons.person_outline_rounded)),
                                      M3ETab(
                                          label: 'Albums',
                                          icon: Icon(Icons.album_outlined)),
                                      M3ETab(
                                          label: 'Genres',
                                          icon: Icon(Icons.style_outlined)),
                                    ],
                                  ),
                                ),
                              ),
                              if (_isScanning) ...[
                                SizedBox(height: isDesktop ? 10 : 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: surfaceColor,
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(
                                        color: primaryColor.withValues(
                                            alpha: 0.3)),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      SizedBox(
                                        width: 14,
                                        height: 14,
                                        child: LoadingIndicatorM3E(
                                          color: primaryColor,
                                          containerColor:
                                              primaryColor.withAlpha(40),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        _scanStatus,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: textDark,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),

                        // Main List Area
                        Expanded(
                          child: _buildSelectedTabBody(primaryColor, textDark,
                              isDesktop: isDesktop),
                        ),
                      ],
                    ),
                    if (_isLoading)
                      Container(
                        color: bgDark.withValues(alpha: 0.5),
                        child: Center(
                          child: LoadingIndicatorM3E(
                              color: primaryColor,
                              containerColor: primaryColor.withAlpha(50)),
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

  Widget _buildPlaylistsTab(Color primaryColor, Color textDark,
      {bool isDesktop = false}) {
    if (_folders.isEmpty && _m3uPlaylists.isEmpty && !_isLoading) {
      return _buildEmptyState(textDark);
    }
    return ListView(
      primary: false,
      padding: EdgeInsets.only(top: isDesktop ? 20 : 12, bottom: 140),
      children: [
        // Featured Quick Action Cards
        Padding(
          padding: EdgeInsets.symmetric(horizontal: isDesktop ? 32.0 : 16.0),
          child: Row(
            children: [
              // Liked Songs Card
              Expanded(
                child: InkWell(
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => LikedSongsScreen(
                          onPlayTracks: widget.onPlayLikedSongs,
                        ),
                      ),
                    );
                  },
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF4527A0), Color(0xFF6A1B9A)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF4527A0).withValues(alpha: 0.3),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.favorite_rounded,
                            color: Colors.white, size: 28),
                        SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Liked Songs',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              SizedBox(height: 2),
                              Text(
                                'Favorites',
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // Shuffle Play Card
              Expanded(
                child: InkWell(
                  onTap: _shufflePlayAll,
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [primaryColor, const Color(0xFF0288D1)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color: primaryColor.withValues(alpha: 0.3),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.shuffle_rounded,
                            color: Colors.white, size: 28),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Shuffle Library',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${_allSongs.length} Tracks',
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: isDesktop ? 24 : 16),
        Padding(
          padding: EdgeInsets.symmetric(
            horizontal: isDesktop ? 32.0 : 16.0,
            vertical: 4.0,
          ),
          child: Text(
            'PLAYLISTS & FOLDERS',
            style: TextStyle(
              color: textDark,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
          ),
        ),
        const SizedBox(height: 6),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: isDesktop ? 32.0 : 16.0),
          child: RepaintBoundary(
            child: ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: 1 + _m3uPlaylists.length + _folders.length,
              itemBuilder: (context, index) {
                if (index == 0) {
                  return _buildLibraryItem(
                    title: 'Network Stream (FTP & DLNA)',
                    subtitle: 'FTP Remote Explorer & DLNA Media Casting',
                    iconData: Icons.lan_rounded,
                    iconGradient: const LinearGradient(
                      colors: [Color(0xFF00897B), Color(0xFF004D40)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    onTap: _navigateToNetworkSources,
                    context: context,
                    isDesktop: isDesktop,
                  );
                } else if (index <= _m3uPlaylists.length) {
                  final pl = _m3uPlaylists[index - 1];
                  return _buildLibraryItem(
                    title: pl.name,
                    subtitle:
                        '${pl.tracks.length} Songs • M3U ${pl.isNetwork ? 'Stream' : 'Playlist'}',
                    iconData: pl.isNetwork
                        ? Icons.podcasts_rounded
                        : Icons.queue_music_rounded,
                    iconGradient: pl.isNetwork
                        ? const LinearGradient(
                            colors: [Color(0xFF00897B), Color(0xFF004D40)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          )
                        : const LinearGradient(
                            colors: [Color(0xFF0288D1), Color(0xFF01579B)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                    onTap: () => _playM3uPlaylist(pl),
                    onLongPress: () => _showM3uPlaylistOptions(pl),
                    context: context,
                    isDesktop: isDesktop,
                  );
                } else {
                  final folderIdx = index - 1 - _m3uPlaylists.length;
                  final f = _folders[folderIdx];
                  return _buildLibraryItem(
                    title: f['name'] as String,
                    subtitle: '${f['count']} Songs • Local Folder',
                    iconData: Icons.folder_rounded,
                    onTap: () => _playFolder(f['path'] as String),
                    onLongPress: () => _removeFolder(folderIdx),
                    context: context,
                    isDesktop: isDesktop,
                  );
                }
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDownloadsTab(Color primaryColor, Color textDark,
      {bool isDesktop = false}) {
    return Column(
      children: [
        // Search & Sort Bar + Layout Switcher
        Padding(
          padding: EdgeInsets.symmetric(
              horizontal: isDesktop ? 32.0 : 16.0,
              vertical: isDesktop ? 12.0 : 6.0),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  style: TextStyle(
                      color: _textPrimary, fontSize: isDesktop ? 16 : 14),
                  decoration: InputDecoration(
                    hintText: 'Search local tracks...',
                    hintStyle: TextStyle(
                        color: _textDark, fontSize: isDesktop ? 16 : 14),
                    prefixIcon: Icon(Icons.search_rounded,
                        color: _textDark, size: isDesktop ? 24 : 20),
                    filled: true,
                    fillColor: _surfaceDark,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(isDesktop ? 14 : 12),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(vertical: 0),
                  ),
                  onChanged: (v) => _applySearchAndSort(),
                ),
              ),
              const SizedBox(width: 8),
              // Sort Button
              M3EMenu(
                anchorBuilder: (context, open) => InkWell(
                  onTap: open,
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: _surfaceDark,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: _outline.withValues(alpha: 0.2)),
                    ),
                    child: Icon(Icons.sort_rounded, color: _textDark, size: 20),
                  ),
                ),
                children: [
                  M3EMenuGroup.entries(
                    label: 'Sort Tracks',
                    entries: _sortOptions.map((choice) {
                      final isSelected = _currentSort == choice;
                      return M3EMenuEntry(
                        label: choice,
                        leading: isSelected
                            ? Icon(Icons.check_rounded,
                                color: primaryColor, size: 18)
                            : const SizedBox(width: 18),
                        onPressed: () {
                          setState(() {
                            _currentSort = choice;
                            _applySearchAndSort();
                          });
                        },
                      );
                    }).toList(),
                  ),
                ],
              ),
              const SizedBox(width: 6),
              // Layout Switcher Button
              M3EMenu(
                anchorBuilder: (context, open) => InkWell(
                  onTap: open,
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: _surfaceDark,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: _outline.withValues(alpha: 0.2)),
                    ),
                    child: Icon(_trackViewMode.icon,
                        color: primaryColor, size: 20),
                  ),
                ),
                children: [
                  M3EMenuGroup.entries(
                    label: 'Layout Mode',
                    entries: TrackViewMode.values.map((mode) {
                      final isSelected = _trackViewMode == mode;
                      return M3EMenuEntry(
                        label: mode.label,
                        leading: Icon(
                          mode.icon,
                          size: 18,
                          color: isSelected ? primaryColor : _textDark,
                        ),
                        trailingText: isSelected ? '✓' : null,
                        onPressed: () {
                          setState(() {
                            _trackViewMode = mode;
                          });
                        },
                      );
                    }).toList(),
                  ),
                ],
              ),
              const SizedBox(width: 6),
              // Group By Button
              M3EMenu(
                anchorBuilder: (context, open) => InkWell(
                  onTap: open,
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: _surfaceDark,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _groupByOption != 'None'
                            ? primaryColor.withValues(alpha: 0.5)
                            : _outline.withValues(alpha: 0.2),
                      ),
                    ),
                    child: Icon(
                      Icons.account_tree_rounded,
                      color: _groupByOption != 'None' ? primaryColor : _textDark,
                      size: 20,
                    ),
                  ),
                ),
                children: [
                  M3EMenuGroup.entries(
                    label: 'Group Tracks By',
                    entries: _groupByOptions.map((choice) {
                      final isSelected = _groupByOption == choice;
                      final iconData = choice == 'None'
                          ? Icons.list_rounded
                          : (choice == 'Album'
                              ? Icons.album_outlined
                              : (choice == 'Artist'
                                  ? Icons.person_outline_rounded
                                  : (choice == 'Genre'
                                      ? Icons.style_outlined
                                      : Icons.folder_outlined)));
                      return M3EMenuEntry(
                        label: choice == 'None' ? 'No Grouping' : 'By $choice',
                        leading: Icon(
                          iconData,
                          size: 18,
                          color: isSelected ? primaryColor : textDark,
                        ),
                        trailingText: isSelected ? '✓' : null,
                        onPressed: () {
                          setState(() {
                            _groupByOption = choice;
                          });
                        },
                      );
                    }).toList(),
                  ),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: _filteredSongs.isEmpty && !_isLoading
              ? _buildEmptyState(textDark,
                  message: 'No songs found',
                  subMessage: _searchController.text.isNotEmpty
                      ? 'No matches for your search.'
                      : 'Add local folders in the Playlists tab to view your songs here.',
                  isDesktop: isDesktop)
              : _buildTrackView(isDesktop: isDesktop),
        ),
      ],
    );
  }

  Widget _buildTrackView({bool isDesktop = false}) {
    if (_groupByOption != 'None') {
      final Map<String, List<LocalSongItem>> groupedMap = {};
      for (final song in _filteredSongs) {
        String key = 'Unknown';
        if (_groupByOption == 'Album') {
          key = song.album.trim().isNotEmpty
              ? song.album.trim()
              : 'Unknown Album';
        } else if (_groupByOption == 'Artist') {
          key = song.artist.trim().isNotEmpty
              ? song.artist.trim()
              : 'Unknown Artist';
        } else if (_groupByOption == 'Genre') {
          key = song.genre.trim().isNotEmpty
              ? song.genre.trim()
              : 'Unknown Genre';
        } else if (_groupByOption == 'Folder') {
          key = p.basename(p.dirname(song.path));
        }
        groupedMap.putIfAbsent(key, () => []).add(song);
      }

      final groupKeys = groupedMap.keys.toList()
        ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

      return ListView.builder(
        primary: false,
        padding: const EdgeInsets.only(bottom: 140),
        itemCount: groupKeys.length,
        itemBuilder: (context, groupIdx) {
          final key = groupKeys[groupIdx];
          final songs = groupedMap[key]!;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Group Header Banner
              InkWell(
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => LocalGroupDetailScreen(
                        groupTitle: key,
                        groupType: _groupByOption,
                        songs: songs,
                        onPlayFolder: widget.onPlayFolder,
                        onPlayTracks: widget.onPlayTracks,
                        onQueueTrack: widget.onQueueTrack,
                        onDeleteTrack: (path) {
                          widget.onDeleteTrack?.call(path);
                          _updateAllSongs();
                        },
                      ),
                    ),
                  );
                },
                child: Container(
                  margin: EdgeInsets.symmetric(
                    horizontal: isDesktop ? 32.0 : 16.0,
                    vertical: 8.0,
                  ),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: _surfaceDark,
                    borderRadius: BorderRadius.circular(12),
                    border:
                        Border.all(color: _outline.withValues(alpha: 0.2)),
                  ),
                  child: Row(
                    children: [
                      LocalAlbumArt(
                        path: songs.first.path,
                        size: 40,
                        borderRadius: 8,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              key,
                              style: TextStyle(
                                fontSize: isDesktop ? 16 : 14,
                                fontWeight: FontWeight.bold,
                                color: _textPrimary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${songs.length} Track${songs.length == 1 ? '' : 's'} • $_groupByOption',
                              style: TextStyle(
                                fontSize: 11,
                                color: AppThemeService
                                    .instance.currentData.textDark,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: Icon(Icons.play_circle_fill_rounded,
                            color: AppThemeService.instance.currentData.primary,
                            size: 28),
                        onPressed: () {
                          final paths = songs.map((s) => s.path).toList();
                          widget.onPlayFolder(paths, initialIndex: 0);
                        },
                        tooltip: 'Play Group',
                      ),
                    ],
                  ),
                ),
              ),

              // Group Tracks
              ...songs.map((song) {
                return _buildLibraryItem(
                  title: song.title,
                  subtitle:
                      '${song.artist != "Unknown Artist" ? song.artist : "Local File"} • ${(song.sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB',
                  customIcon: LocalAlbumArt(
                      path: song.path,
                      size: isDesktop ? 80 : 56,
                      shape: Shapes.pill),
                  onTap: () {
                    final paths = songs.map((e) => e.path).toList();
                    final songIdx = songs.indexOf(song);
                    widget.onPlayFolder(paths, initialIndex: songIdx);
                  },
                  onOptionSelected: (option) => _handleSongOption(song, option),
                  context: context,
                  isDesktop: isDesktop,
                );
              }),
              const SizedBox(height: 12),
            ],
          );
        },
      );
    }

    if (_trackViewMode == TrackViewMode.compact) {
      return ListView.builder(
        padding: EdgeInsets.symmetric(
          horizontal: isDesktop ? 32 : 16,
          vertical: 8,
        ).copyWith(bottom: 140),
        itemCount: _filteredSongs.length,
        itemBuilder: (context, index) {
          final song = _filteredSongs[index];
          return _buildCompactSongItem(song, index, isDesktop: isDesktop);
        },
      );
    } else if (_trackViewMode == TrackViewMode.grid) {
      return GridView.builder(
        primary: false,
        padding: EdgeInsets.fromLTRB(
          isDesktop ? 32 : 16,
          8,
          isDesktop ? 32 : 16,
          140,
        ),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: isDesktop ? 4 : 2,
          childAspectRatio: 0.78,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
        ),
        itemCount: _filteredSongs.length,
        itemBuilder: (context, index) {
          final song = _filteredSongs[index];
          return _buildGridSongItem(song, index, isDesktop: isDesktop);
        },
      );
    } else {
      // Standard Virtualized ListView with zero UI thread overhead
      return ListView.builder(
        padding: EdgeInsets.symmetric(
          horizontal: isDesktop ? 32 : 16,
          vertical: 8,
        ).copyWith(bottom: 140),
        itemCount: _filteredSongs.length,
        itemBuilder: (context, index) {
          final song = _filteredSongs[index];
          return _buildLibraryItem(
            title: song.title,
            subtitle:
                '${song.artist != "Unknown Artist" ? song.artist : "Local File"} • ${(song.sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB',
            customIcon: LocalAlbumArt(
                path: song.path,
                size: isDesktop ? 60 : 48,
                shape: Shapes.pill),
            onTap: () {
              final paths = _filteredSongs.map((e) => e.path).toList();
              widget.onPlayFolder(paths, initialIndex: index);
            },
            onOptionSelected: (option) => _handleSongOption(song, option),
            context: context,
            isDesktop: isDesktop,
          );
        },
      );
    }
  }

  Widget _buildCompactSongItem(LocalSongItem song, int index,
      {bool isDesktop = false}) {
    final artistName =
        song.artist != 'Unknown Artist' ? song.artist : 'Local File';
    return Padding(
      padding: const EdgeInsets.only(bottom: 2.0),
      child: Material(
        color: _surfaceDark,
        borderRadius: BorderRadius.circular(10),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () {
            final paths = _filteredSongs.map((e) => e.path).toList();
            widget.onPlayFolder(paths, initialIndex: index);
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Row(
              children: [
                LocalAlbumArt(
                  path: song.path,
                  size: isDesktop ? 40 : 34,
                  borderRadius: 6,
                  shape: Shapes.pill,
                ),
                const SizedBox(width: 10),
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
                          fontSize: isDesktop ? 14 : 12.5,
                          fontWeight: FontWeight.w600,
                          color: _textPrimary,
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        artistName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: isDesktop ? 12 : 11,
                          color: _textDark,
                        ),
                      ),
                    ],
                  ),
                ),
                SongOptionsMenuButton(
                  iconSize: isDesktop ? 18 : 16,
                  onOptionSelected: (option) => _handleSongOption(song, option),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGridSongItem(LocalSongItem song, int index,
      {bool isDesktop = false}) {
    final artistName =
        song.artist != 'Unknown Artist' ? song.artist : 'Local File';
    final primaryColor = context.primaryColor;
    final cardColor = context.cardDark;

    const Shapes itemShape = Shapes.slanted;

    return RepaintBoundary(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            final paths = _filteredSongs.map((e) => e.path).toList();
            widget.onPlayFolder(paths, initialIndex: index);
          },
          child: M3EContainer(
            Shapes.bun,
            width: double.infinity,
            height: double.infinity,
            color: cardColor.withAlpha(240),
            border: BorderSide(
              color: primaryColor.withValues(alpha: 0.18),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.35),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
            padding: const EdgeInsets.all(10),
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: M3EContainer(
                          itemShape,
                          color: cardColor,
                          clipBehavior: Clip.antiAlias,
                          border: BorderSide(
                            color: primaryColor.withValues(alpha: 0.3),
                            width: 1.5,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: primaryColor.withValues(alpha: 0.15),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ],
                          child: LocalAlbumArt(
                            path: song.path,
                            shape: itemShape,
                            useM3Shape: true,
                          ),
                        ),
                      ),
                      // Top-Right Options Badge
                      Positioned(
                        top: 4,
                        right: 4,
                        child: M3EContainer.circle(
                          width: 32,
                          height: 32,
                          color: Colors.black.withValues(alpha: 0.65),
                          child: SongOptionsMenuButton(
                            iconSize: 18,
                            onOptionSelected: (option) =>
                                _handleSongOption(song, option),
                          ),
                        ),
                      ),
                      // Bottom-Right Play Badge
                      Positioned(
                        bottom: 4,
                        right: 4,
                        child: M3EContainer.circle(
                          width: 32,
                          height: 32,
                          gradient: LinearGradient(
                            colors: [
                              primaryColor,
                              primaryColor.withValues(alpha: 0.8),
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.4),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                          child: const Center(
                            child: Icon(
                              Icons.play_arrow_rounded,
                              size: 20,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  song.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: isDesktop ? 14 : 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        artistName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: AppThemeService.instance.currentData.textDark,
                          fontSize: 11,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    M3EShape(
                      itemShape,
                      width: 12,
                      height: 12,
                      color: primaryColor.withValues(alpha: 0.8),
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

  Widget _buildArtistsTab(Color primaryColor, Color textDark,
      {bool isDesktop = false}) {
    final Map<String, List<LocalSongItem>> artistMap = {};
    for (final song in _allSongs) {
      final artist =
          song.artist.trim().isNotEmpty ? song.artist.trim() : 'Unknown Artist';
      artistMap.putIfAbsent(artist, () => []).add(song);
    }

    final query = _artistSearchController.text.trim().toLowerCase();
    final artistKeys = artistMap.keys.where((a) {
      if (query.isEmpty) return true;
      return a.toLowerCase().contains(query);
    }).toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    return Column(
      children: [
        // Search bar for Artists
        Padding(
          padding: EdgeInsets.symmetric(
            horizontal: isDesktop ? 32.0 : 16.0,
            vertical: isDesktop ? 12.0 : 6.0,
          ),
          child: TextField(
            controller: _artistSearchController,
            style:
                TextStyle(color: Colors.white, fontSize: isDesktop ? 16 : 14),
            decoration: InputDecoration(
              hintText: 'Search artists...',
              hintStyle:
                  TextStyle(color: textDark, fontSize: isDesktop ? 16 : 14),
              prefixIcon: Icon(Icons.search_rounded,
                  color: textDark, size: isDesktop ? 24 : 20),
              filled: true,
              fillColor: AppThemeService.instance.currentData.cardDark,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(isDesktop ? 14 : 12),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(vertical: 0),
            ),
            onChanged: (v) => setState(() {}),
          ),
        ),

        Expanded(
          child: artistKeys.isEmpty && !_isLoading
              ? _buildEmptyState(
                  textDark,
                  message: 'No artists found',
                  subMessage: _artistSearchController.text.isNotEmpty
                      ? 'No matches for "${_artistSearchController.text}".'
                      : 'Add local folders in Playlists to view artists here.',
                  isDesktop: isDesktop,
                )
              : ListView.builder(
                  padding: EdgeInsets.symmetric(
                    horizontal: isDesktop ? 32 : 16,
                    vertical: 8,
                  ).copyWith(bottom: 140),
                  itemCount: artistKeys.length,
                  itemBuilder: (context, index) {
                    final artistName = artistKeys[index];
                    final songs = artistMap[artistName] ?? [];
                    final sampleSongPath =
                        songs.isNotEmpty ? songs.first.path : null;

                    return _buildLibraryItem(
                      title: artistName,
                      subtitle:
                          '${songs.length} Song${songs.length == 1 ? '' : 's'} • Artist',
                      iconData: Icons.person_rounded,
                      isArtist: true,
                      customIcon: sampleSongPath != null
                          ? LocalAlbumArt(
                              path: sampleSongPath,
                              size: isDesktop ? 60 : 48,
                              shape: Shapes.circle,
                            )
                          : null,
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => LocalGroupDetailScreen(
                              groupTitle: artistName,
                              groupType: 'Artist',
                              songs: songs,
                              onPlayFolder: widget.onPlayFolder,
                              onPlayTracks: widget.onPlayTracks,
                              onQueueTrack: widget.onQueueTrack,
                              onDeleteTrack: (path) {
                                widget.onDeleteTrack?.call(path);
                                _updateAllSongs();
                              },
                            ),
                          ),
                        );
                      },
                      context: context,
                      isDesktop: isDesktop,
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildSelectedTabBody(Color primaryColor, Color textDark,
      {bool isDesktop = false}) {
    switch (_tabIndex) {
      case 0:
        return _buildPlaylistsTab(primaryColor, textDark, isDesktop: isDesktop);
      case 1:
        return _buildDownloadsTab(primaryColor, textDark, isDesktop: isDesktop);
      case 2:
        return _buildArtistsTab(primaryColor, textDark, isDesktop: isDesktop);
      case 3:
        return _buildAlbumsTab(primaryColor, textDark, isDesktop: isDesktop);
      case 4:
        return _buildGenresTab(primaryColor, textDark, isDesktop: isDesktop);
      default:
        return _buildPlaylistsTab(primaryColor, textDark, isDesktop: isDesktop);
    }
  }

  Widget _buildAlbumsTab(Color primaryColor, Color textDark,
      {bool isDesktop = false}) {
    final Map<String, List<LocalSongItem>> albumMap = {};
    for (final song in _allSongs) {
      final album =
          song.album.trim().isNotEmpty ? song.album.trim() : 'Unknown Album';
      albumMap.putIfAbsent(album, () => []).add(song);
    }

    final query = _albumSearchController.text.trim().toLowerCase();
    final albumKeys = albumMap.keys.where((a) {
      if (query.isEmpty) return true;
      return a.toLowerCase().contains(query);
    }).toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    return Column(
      children: [
        Padding(
          padding: EdgeInsets.symmetric(
            horizontal: isDesktop ? 32.0 : 16.0,
            vertical: isDesktop ? 12.0 : 6.0,
          ),
          child: TextField(
            controller: _albumSearchController,
            style:
                TextStyle(color: Colors.white, fontSize: isDesktop ? 16 : 14),
            decoration: InputDecoration(
              hintText: 'Search albums...',
              hintStyle:
                  TextStyle(color: textDark, fontSize: isDesktop ? 16 : 14),
              prefixIcon: Icon(Icons.search_rounded,
                  color: textDark, size: isDesktop ? 24 : 20),
              filled: true,
              fillColor: AppThemeService.instance.currentData.cardDark,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(isDesktop ? 14 : 12),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(vertical: 0),
            ),
            onChanged: (v) => setState(() {}),
          ),
        ),
        Expanded(
          child: albumKeys.isEmpty && !_isLoading
              ? _buildEmptyState(
                  textDark,
                  message: 'No albums found',
                  subMessage: _albumSearchController.text.isNotEmpty
                      ? 'No matches for "${_albumSearchController.text}".'
                      : 'Add local folders in Playlists to view albums here.',
                  isDesktop: isDesktop,
                )
              : ListView.builder(
                  padding: EdgeInsets.symmetric(
                    horizontal: isDesktop ? 32 : 16,
                    vertical: 8,
                  ).copyWith(bottom: 140),
                  itemCount: albumKeys.length,
                  itemBuilder: (context, index) {
                    final albumName = albumKeys[index];
                    final songs = albumMap[albumName] ?? [];
                    final sampleSongPath =
                        songs.isNotEmpty ? songs.first.path : null;
                    final artistName = songs.isNotEmpty
                        ? songs.first.artist
                        : 'Unknown Artist';

                    return _buildLibraryItem(
                      title: albumName,
                      subtitle:
                          '${songs.length} Song${songs.length == 1 ? '' : 's'} • $artistName',
                      iconData: Icons.album_rounded,
                      customIcon: sampleSongPath != null
                          ? LocalAlbumArt(
                              path: sampleSongPath,
                              size: isDesktop ? 60 : 48,
                              shape: Shapes.pill,
                            )
                          : null,
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => LocalGroupDetailScreen(
                              groupTitle: albumName,
                              groupType: 'Album',
                              songs: songs,
                              onPlayFolder: widget.onPlayFolder,
                              onPlayTracks: widget.onPlayTracks,
                              onQueueTrack: widget.onQueueTrack,
                              onDeleteTrack: (path) {
                                widget.onDeleteTrack?.call(path);
                                _updateAllSongs();
                              },
                            ),
                          ),
                        );
                      },
                      context: context,
                      isDesktop: isDesktop,
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildGenresTab(Color primaryColor, Color textDark,
      {bool isDesktop = false}) {
    final Map<String, List<LocalSongItem>> genreMap = {};
    for (final song in _allSongs) {
      final genre =
          song.genre.trim().isNotEmpty ? song.genre.trim() : 'Unknown Genre';
      genreMap.putIfAbsent(genre, () => []).add(song);
    }

    final query = _genreSearchController.text.trim().toLowerCase();
    final genreKeys = genreMap.keys.where((g) {
      if (query.isEmpty) return true;
      return g.toLowerCase().contains(query);
    }).toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    return Column(
      children: [
        Padding(
          padding: EdgeInsets.symmetric(
            horizontal: isDesktop ? 32.0 : 16.0,
            vertical: isDesktop ? 12.0 : 6.0,
          ),
          child: TextField(
            controller: _genreSearchController,
            style:
                TextStyle(color: Colors.white, fontSize: isDesktop ? 16 : 14),
            decoration: InputDecoration(
              hintText: 'Search genres...',
              hintStyle:
                  TextStyle(color: textDark, fontSize: isDesktop ? 16 : 14),
              prefixIcon: Icon(Icons.search_rounded,
                  color: textDark, size: isDesktop ? 24 : 20),
              filled: true,
              fillColor: AppThemeService.instance.currentData.cardDark,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(isDesktop ? 14 : 12),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(vertical: 0),
            ),
            onChanged: (v) => setState(() {}),
          ),
        ),
        Expanded(
          child: genreKeys.isEmpty && !_isLoading
              ? _buildEmptyState(
                  textDark,
                  message: 'No genres found',
                  subMessage: _genreSearchController.text.isNotEmpty
                      ? 'No matches for "${_genreSearchController.text}".'
                      : 'Add local folders in Playlists to view genres here.',
                  isDesktop: isDesktop,
                )
              : ListView.builder(
                  padding: EdgeInsets.symmetric(
                    horizontal: isDesktop ? 32 : 16,
                    vertical: 8,
                  ).copyWith(bottom: 140),
                  itemCount: genreKeys.length,
                  itemBuilder: (context, index) {
                    final genreName = genreKeys[index];
                    final songs = genreMap[genreName] ?? [];
                    final sampleSongPath =
                        songs.isNotEmpty ? songs.first.path : null;

                    return _buildLibraryItem(
                      title: genreName,
                      subtitle:
                          '${songs.length} Song${songs.length == 1 ? '' : 's'} • Genre',
                      iconData: Icons.style_rounded,
                      customIcon: sampleSongPath != null
                          ? LocalAlbumArt(
                              path: sampleSongPath,
                              size: isDesktop ? 60 : 48,
                              shape: Shapes.pill,
                            )
                          : null,
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => LocalGroupDetailScreen(
                              groupTitle: genreName,
                              groupType: 'Genre',
                              songs: songs,
                              onPlayFolder: widget.onPlayFolder,
                              onPlayTracks: widget.onPlayTracks,
                              onQueueTrack: widget.onQueueTrack,
                              onDeleteTrack: (path) {
                                widget.onDeleteTrack?.call(path);
                                _updateAllSongs();
                              },
                            ),
                          ),
                        );
                      },
                      context: context,
                      isDesktop: isDesktop,
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildEmptyState(Color textDark,
      {String message = 'Your library is empty',
      String subMessage = 'Tap the + button to add local music folders.',
      bool isDesktop = false}) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.library_music_outlined,
              size: isDesktop ? 80 : 56,
              color: textDark.withValues(alpha: 0.4)),
          SizedBox(height: isDesktop ? 20 : 14),
          Text(
            message,
            style: TextStyle(
                fontSize: isDesktop ? 20 : 16,
                fontWeight: FontWeight.bold,
                color: Colors.white),
          ),
          SizedBox(height: isDesktop ? 10 : 6),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: isDesktop ? 64.0 : 32.0),
            child: Text(
              subMessage,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: isDesktop ? 15 : 13, color: textDark),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLibraryItem({
    required String title,
    required String subtitle,
    required BuildContext context,
    IconData? iconData,
    Widget? customIcon,
    String? imageAsset,
    Gradient? iconGradient,
    VoidCallback? onTap,
    VoidCallback? onLongPress,
    ValueChanged<SongOption>? onOptionSelected,
    bool isDesktop = false,
    bool isArtist = false,
  }) {
    final thumbSize = isDesktop ? 60.0 : 48.0;

    final leadingWidget = customIcon ??
        Container(
          width: thumbSize,
          height: thumbSize,
          decoration: BoxDecoration(
            gradient: iconGradient,
            color: iconGradient == null ? _surfaceDark : null,
            shape: isArtist ? BoxShape.circle : BoxShape.rectangle,
            borderRadius: isArtist ? null : BorderRadius.circular(10),
          ),
          child: Center(
            child: Icon(
              iconData ?? Icons.music_note_rounded,
              color: Colors.white.withValues(alpha: 0.7),
              size: isDesktop ? 28 : 22,
            ),
          ),
        );

    return Padding(
      padding: const EdgeInsets.only(bottom: 4.0),
      child: Material(
        color: _surfaceDark,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                leadingWidget,
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: isDesktop ? 15 : 13.5,
                          fontWeight: FontWeight.w600,
                          color: _textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: isDesktop ? 13 : 11.5,
                          color: _textDark,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                if (onOptionSelected != null)
                  SongOptionsMenuButton(
                    iconSize: isDesktop ? 22 : 18,
                    onOptionSelected: onOptionSelected,
                  )
                else
                  Icon(
                    Icons.chevron_right_rounded,
                    color: const Color(0xFF64748B),
                    size: isDesktop ? 20 : 18,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class LocalGroupDetailScreen extends StatefulWidget {
  final String groupTitle;
  final String groupType; // 'Artist', 'Album', 'Genre', 'Folder'
  final List<LocalSongItem> songs;
  final Future<void> Function(List<String> audioFilePaths, {int initialIndex})
      onPlayFolder;
  final Future<void> Function(List<TrackInfo> tracks, {int initialIndex})?
      onPlayTracks;
  final Function(TrackInfo track)? onQueueTrack;
  final Function(String filePath)? onDeleteTrack;

  const LocalGroupDetailScreen({
    super.key,
    required this.groupTitle,
    this.groupType = 'Group',
    required this.songs,
    required this.onPlayFolder,
    this.onPlayTracks,
    this.onQueueTrack,
    this.onDeleteTrack,
  });

  @override
  State<LocalGroupDetailScreen> createState() => _LocalGroupDetailScreenState();
}

class _LocalGroupDetailScreenState extends State<LocalGroupDetailScreen> {
  late List<LocalSongItem> _groupSongs;

  @override
  void initState() {
    super.initState();
    _groupSongs = List.from(widget.songs);
  }

  @override
  Widget build(BuildContext context) {
    final bgDark = context.bgDark;
    final surfaceColor = context.cardDark;
    final primaryColor = context.primaryColor;
    final textPrimary = context.textPrimary;
    final textDark = context.textMuted;
    final outlineColor = context.outlineColor;

    return Scaffold(
      backgroundColor: bgDark,
      appBar: AppBar(
        backgroundColor: bgDark,
        elevation: 0,
        title: Text(
          widget.groupTitle,
          style: TextStyle(fontWeight: FontWeight.bold, color: textPrimary),
        ),
        actions: [
          if (widget.onPlayTracks != null && widget.groupType == 'Artist')
            IconButton(
              icon: Icon(Icons.language, color: textDark),
              tooltip: 'View Online Discography',
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ArtistProfileScreen(
                      artistName: widget.groupTitle,
                      onPlayTracks: widget.onPlayTracks,
                    ),
                  ),
                );
              },
            ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Header Card
            Container(
              padding: const EdgeInsets.all(20),
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: surfaceColor,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: outlineColor),
              ),
              child: Row(
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: primaryColor.withValues(alpha: 0.2),
                      borderRadius: widget.groupType == 'Artist'
                          ? BorderRadius.circular(32)
                          : BorderRadius.circular(12),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: _groupSongs.isNotEmpty
                        ? LocalAlbumArt(
                            path: _groupSongs.first.path,
                            size: 64,
                            shape: widget.groupType == 'Artist'
                                ? Shapes.circle
                                : Shapes.pill,
                          )
                        : Icon(
                            widget.groupType == 'Artist'
                                ? Icons.person
                                : (widget.groupType == 'Album'
                                    ? Icons.album
                                    : Icons.style),
                            color: primaryColor,
                            size: 36),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.groupTitle,
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: textPrimary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${_groupSongs.length} Track${_groupSongs.length == 1 ? '' : 's'} • ${widget.groupType}',
                          style: TextStyle(
                              color: textDark,
                              fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: () {
                      if (_groupSongs.isEmpty) return;
                      final paths = _groupSongs.map((e) => e.path).toList();
                      widget.onPlayFolder(paths, initialIndex: 0);
                    },
                    icon: const Icon(Icons.play_arrow, color: Colors.white),
                    label: const Text('Play All'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primaryColor,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Track List
            Expanded(
              child: _groupSongs.isEmpty
                  ? Center(
                      child: Text(
                        'No songs left in this group.',
                        style: TextStyle(color: textDark),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 8)
                          .copyWith(bottom: 120),
                      itemCount: _groupSongs.length,
                      itemBuilder: (context, index) {
                        final song = _groupSongs[index];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 4.0),
                          child: Material(
                            color: surfaceColor,
                            borderRadius: BorderRadius.circular(12),
                            clipBehavior: Clip.antiAlias,
                            child: InkWell(
                              onTap: () {
                                final paths =
                                    _groupSongs.map((e) => e.path).toList();
                                widget.onPlayFolder(paths, initialIndex: index);
                              },
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 8),
                                child: Row(
                                  children: [
                                    LocalAlbumArt(
                                      path: song.path,
                                      size: 48,
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
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w600,
                                              color: textPrimary,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            '${song.artist} • ${song.album}',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: textDark,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    SongOptionsMenuButton(
                                      iconSize: 20,
                                      onOptionSelected: (option) =>
                                          _handleDetailSongOption(song, option),
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
    );
  }

  Future<void> _handleDetailSongOption(
      LocalSongItem song, SongOption option) async {
    switch (option) {
      case SongOption.queue:
        if (widget.onQueueTrack != null) {
          widget.onQueueTrack!(TrackInfo(
            videoId: song.path,
            title: song.title,
            artist: song.artist,
          ));
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Added "${song.title}" to Queue')),
          );
        }
        break;
      case SongOption.info:
        final file = File(song.path);
        final fileInfo = await AudioFileInspector.inspect(song.path);
        Duration d = Duration.zero;
        Uint8List? art;
        try {
          final meta = amr.readMetadata(file, getImage: true);
          if (meta.duration != null) d = meta.duration!;
          if (meta.pictures.isNotEmpty) art = meta.pictures.first.bytes;
        } catch (_) {}
        await MusicInfoDialog.show(
          context,
          title: song.title,
          artist: song.artist,
          album: song.album,
          genre: song.genre,
          albumArt: art,
          sourceType: 'local',
          videoId: song.path,
          codec: fileInfo.codec,
          sampleRate: fileInfo.formattedSampleRate,
          channels: fileInfo.formattedChannels,
          bitDepth: fileInfo.formattedBitDepth,
          fileSizeBytes: song.sizeBytes,
          duration: d,
          onSaveTags: ({
            required String title,
            required String artist,
            required String album,
            required String genre,
            required String year,
            required String trackNumber,
          }) async {
            setState(() {
              final idx = _groupSongs.indexWhere((s) => s.path == song.path);
              if (idx != -1) {
                _groupSongs[idx] = LocalSongItem.fallback(
                  song.path,
                  song.sizeBytes,
                  song.lastModified,
                  title: title.isNotEmpty ? title : song.title,
                  artist: artist.isNotEmpty ? artist : song.artist,
                  album: album.isNotEmpty ? album : song.album,
                  genre: genre.isNotEmpty ? genre : song.genre,
                  fileHash: song.fileHash,
                );
              }
            });
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                    content: Text(
                        'Saved tags for "${title.isNotEmpty ? title : song.title}"')),
              );
            }
          },
        );
        break;
      case SongOption.share:
        try {
          await Share.shareXFiles([XFile(song.path)], text: song.title);
        } catch (e) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not share: $e')),
          );
        }
        break;
      case SongOption.delete:
        final confirm = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: context.cardDark,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.redAccent.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.delete_forever_rounded,
                      color: Colors.redAccent, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Delete Song?',
                    style: TextStyle(
                        color: context.textPrimary,
                        fontWeight: FontWeight.bold,
                        fontSize: 18),
                  ),
                ),
              ],
            ),
            content: Text(
              'Are you sure you want to delete "${song.title}"? This action cannot be undone.',
              style: TextStyle(
                  color: context.textMuted,
                  fontSize: 14),
            ),
            actionsPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            actions: [
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor:
                      context.textMuted,
                  side: BorderSide(
                      color: context.textMuted
                          .withValues(alpha: 0.3)),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.redAccent,
                  foregroundColor: Colors.white,
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Delete Permanently',
                    style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        );
        if (confirm == true) {
          try {
            await File(song.path).delete();
            widget.onDeleteTrack?.call(song.path);
            setState(() {
              _groupSongs.removeWhere((s) => s.path == song.path);
            });
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Deleted "${song.title}" permanently.')),
            );
          } catch (e) {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Failed to delete: $e')),
            );
          }
        }
        break;
    }
  }
}

class LocalArtistDetailScreen extends LocalGroupDetailScreen {
  const LocalArtistDetailScreen({
    super.key,
    required String artistName,
    required super.songs,
    required super.onPlayFolder,
    super.onPlayTracks,
    super.onQueueTrack,
    super.onDeleteTrack,
  }) : super(
          groupTitle: artistName,
          groupType: 'Artist',
        );
}
