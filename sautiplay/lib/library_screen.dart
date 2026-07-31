import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:audio_metadata_reader/audio_metadata_reader.dart' as amr;
import 'package:file_picker/file_picker.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:loading_indicator_m3e/loading_indicator_m3e.dart';
import 'package:path/path.dart' as p;
import 'package:permission_handler/permission_handler.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sautiflow/sautiflow.dart';
import 'services/m3u_playlist_service.dart';

import 'album_detail_screen.dart';
import 'artist_profile_screen.dart';
import 'liked_songs_screen.dart'; // NEW
import 'models/liked_song.dart'; // NEW
import 'models/local_song_item.dart';
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
  final bool isNested;
  final int initialTabIndex;

  const LibraryScreen({
    super.key,
    required this.onPlayFolder,
    required this.onPlayLikedSongs,
    this.onPlayTracks,
    this.onQueueTrack,
    this.onDeleteTrack,
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

  // Search & Sort filters
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _artistSearchController = TextEditingController();
  String _currentSort = 'Name (A-Z)';
  static const List<String> _sortOptions = [
    'Name (A-Z)',
    'Name (Z-A)',
    'Date Added (New-Old)',
    'Date Added (Old-New)',
    'Size (Largest)',
    'Size (Smallest)',
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
        final XFile? file = await openFile(acceptedTypeGroups: <XTypeGroup>[typeGroup]);
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
          title: s.title ?? (s.uri.scheme == 'file' ? p.basenameWithoutExtension(s.uri.toFilePath()) : s.uri.toString()),
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
          SnackBar(content: Text('Imported M3U playlist "$playlistName" (${tracks.length} tracks)')),
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

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF18232E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Import M3U / M3U8 Stream URL', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'Playlist Name (Optional)',
                labelStyle: TextStyle(color: Color(0xFF94A3B8)),
                hintText: 'e.g. Live Radio Stations',
                hintStyle: TextStyle(color: Color(0xFF64748B)),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: urlController,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'M3U / M3U8 URL',
                labelStyle: TextStyle(color: Color(0xFF94A3B8)),
                hintText: 'https://example.com/playlist.m3u8',
                hintStyle: TextStyle(color: Color(0xFF64748B)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel', style: TextStyle(color: Color(0xFF94A3B8))),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF137FEC),
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Import'),
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
      final playlistName = customName.isNotEmpty ? customName : 'M3U Web Stream';
      final tracks = sources.map((s) {
        return LocalSongItem(
          path: s.uri.scheme == 'file' ? s.uri.toFilePath() : s.uri.toString(),
          title: s.title ?? (s.uri.scheme == 'file' ? p.basenameWithoutExtension(s.uri.toFilePath()) : s.uri.toString()),
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
          SnackBar(content: Text('Imported M3U stream "$playlistName" (${tracks.length} tracks)')),
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
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF18232E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.play_arrow, color: Color(0xFF137FEC)),
            title: Text('Play "${playlist.name}"', style: const TextStyle(color: Colors.white)),
            onTap: () {
              Navigator.of(ctx).pop();
              _playM3uPlaylist(playlist);
            },
          ),
          ListTile(
            leading: const Icon(Icons.file_upload, color: Colors.amberAccent),
            title: const Text('Export Playlist as .m3u8', style: TextStyle(color: Colors.white)),
            onTap: () {
              Navigator.of(ctx).pop();
              _exportPlaylistToM3u8(playlist.name, playlist.tracks);
            },
          ),
          ListTile(
            leading: const Icon(Icons.delete, color: Colors.redAccent),
            title: const Text('Delete Playlist', style: TextStyle(color: Colors.redAccent)),
            onTap: () async {
              Navigator.of(ctx).pop();
              await M3uPlaylistService.instance.deletePlaylist(playlist.id);
              await _loadSavedM3uPlaylists();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Deleted playlist "${playlist.name}"')),
                );
              }
            },
          ),
        ],
      ),
    );
  }

  Future<void> _exportPlaylistToM3u8(String name, List<LocalSongItem> tracks) async {
    if (tracks.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No tracks available to export.')),
      );
      return;
    }
    String? targetPath;
    try {
      if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
        final FileSaveLocation? location = await getSaveLocation(
          suggestedName: '${name.replaceAll(' ', '_')}.m3u8',
          acceptedTypeGroups: const [
            XTypeGroup(label: 'M3U8 Playlist', extensions: ['m3u8']),
          ],
        );
        targetPath = location?.path;
      } else {
        targetPath = await FilePicker.saveFile(
          dialogTitle: 'Export Playlist to M3U8',
          fileName: '${name.replaceAll(' ', '_')}.m3u8',
          type: FileType.custom,
          allowedExtensions: ['m3u8'],
        );
      }
    } catch (e) {
      debugPrint('Error opening save dialog: $e');
    }
    if (targetPath == null || targetPath.isEmpty) return;

    try {
      await M3uPlaylistService.instance.exportToM3u8(
        targetFilePath: targetPath,
        playlistName: name,
        tracks: tracks,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Exported playlist to ${p.basename(targetPath)}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to export playlist: $e')),
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
      await _smartScanFolders(showFullLoading: loadedSongs.isEmpty && loadedFolders.isNotEmpty);
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
      for (final song in _allSongs) song.path: song
    };

    final updatedSongs = <LocalSongItem>[];
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
        try {
          final file = File(path);
          final stat = await file.stat();
          final existing = existingSongsMap[path];

          // Re-use cached metadata if file size and modified timestamp match
          if (existing != null &&
              existing.sizeBytes == stat.size &&
              existing.lastModified.millisecondsSinceEpoch == stat.modified.millisecondsSinceEpoch) {
            updatedSongs.add(existing);
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
            try {
              final meta = amr.readMetadata(file, getImage: false);
              if (meta.title != null && meta.title!.isNotEmpty) metaTitle = meta.title;
              if (meta.artist != null && meta.artist!.isNotEmpty) metaArtist = meta.artist;
              if (meta.album != null && meta.album!.isNotEmpty) metaAlbum = meta.album;
            } catch (_) {}

            updatedSongs.add(LocalSongItem.fallback(
              path,
              stat.size,
              stat.modified,
              title: metaTitle,
              artist: metaArtist,
              album: metaAlbum,
            ));
          }
        } catch (_) {
          updatedSongs.add(LocalSongItem.fallback(path, 0, DateTime.now()));
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
    final dir = Directory(dirPath);
    if (!await dir.exists()) return audioFiles;

    const allowedExtensions = {'.mp3', '.m4a', '.wav', '.flac', '.aac', '.ogg'};

    try {
      await for (final entity
          in dir.list(recursive: true, followLinks: false)) {
        if (entity is File) {
          final ext = p.extension(entity.path).toLowerCase();
          if (allowedExtensions.contains(ext)) {
            audioFiles.add(entity.path);
          }
        }
      }
    } catch (e) {
      debugPrint('Error reading directory: $e');
    }

    return audioFiles;
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

    // Check if duplicate
    if (_folders.any((f) => f['path'] == selectedDirectory)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Folder is already in your library.')),
      );
      return;
    }

    setState(() => _isLoading = true);

    final audioPaths = await _scanForAudioFiles(selectedDirectory);

    final newFolder = {
      'path': selectedDirectory,
      'name': p.basename(selectedDirectory),
      'count': audioPaths.length,
    };

    setState(() {
      _folders.add(newFolder);
    });

    await _saveFolders();
    await _updateAllSongs();
  }

  Future<void> _removeFolder(int index) async {
    setState(() {
      _folders.removeAt(index);
    });
    await _saveFolders();
    await _updateAllSongs();
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

    // Hand off to main player
    widget.onPlayFolder(audioPaths);
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
        if (meta.artist != null && meta.artist!.isNotEmpty) artist = meta.artist!;
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

    showDialog(
      context: context,
      builder: (_) => MusicInfoDialog(
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
      ),
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
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF18232E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Delete Song Permanently?',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: Text(
          'Are you sure you want to delete "${song.title}"? The file will be permanently removed from your storage.',
          style: const TextStyle(color: Color(0xFF94A3B8)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel', style: TextStyle(color: Color(0xFF94A3B8))),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete', style: TextStyle(fontWeight: FontWeight.bold)),
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

  Widget _buildTab(int index, String title, IconData icon, {bool isDesktop = false}) {
    final isSelected = _tabIndex == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _tabIndex = index),
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          padding: EdgeInsets.symmetric(vertical: isDesktop ? 9 : 7, horizontal: 6),
          decoration: BoxDecoration(
            color: isSelected
                ? const Color(0xFF137fec).withValues(alpha: 0.22)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(isDesktop ? 10 : 8),
            border: isSelected
                ? Border.all(
                    color: const Color(0xFF137fec).withValues(alpha: 0.4),
                    width: 1,
                  )
                : Border.all(color: Colors.transparent, width: 1),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: isDesktop ? 18 : 15,
                color: isSelected ? const Color(0xFF137fec) : const Color(0xFF94A3B8),
              ),
              const SizedBox(width: 6),
              Text(
                title,
                style: TextStyle(
                  fontSize: isDesktop ? 15 : 13,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                  color: isSelected ? Colors.white : const Color(0xFF94A3B8),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    // Theme colors
    const Color primaryColor = Color(0xFF137FEC);
    const Color bgDark = Color(0xFF101922);
    const Color surfaceColor = Color(0xFF18232E);
    const Color textLight = Colors.white;
    const Color textDark = Color(0xFF94A3B8); // slate-400

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
                              top: widget.isNested ? 8.0 : (isDesktop ? 32.0 : 16.0),
                              left: isDesktop ? 32.0 : 16.0,
                              right: isDesktop ? 32.0 : 16.0,
                              bottom: isDesktop ? 12.0 : 8.0),
                          decoration: const BoxDecoration(
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
                                  PopupMenuButton<String>(
                                    icon: Container(
                                      padding: const EdgeInsets.all(6),
                                      decoration: BoxDecoration(
                                        color: surfaceColor,
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                            color: Colors.white.withValues(alpha: 0.08)),
                                      ),
                                      child: Icon(Icons.add_rounded,
                                          color: textLight,
                                          size: isDesktop ? 22 : 20),
                                    ),
                                    tooltip: 'Add Music or Playlist',
                                    color: surfaceColor,
                                    shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(14)),
                                    onSelected: (value) {
                                      if (value == 'folder') {
                                        _addDirectory();
                                      } else if (value == 'm3u_file') {
                                        _importM3uFile();
                                      } else if (value == 'm3u_url') {
                                        _importM3uUrlDialog();
                                      } else if (value == 'export_m3u') {
                                        _exportPlaylistToM3u8(
                                            'SautiPlay_Library', _allSongs);
                                      }
                                    },
                                    itemBuilder: (ctx) => [
                                      const PopupMenuItem(
                                        value: 'folder',
                                        child: Row(
                                          children: [
                                            Icon(Icons.create_new_folder_rounded,
                                                color: Colors.blueAccent, size: 20),
                                            SizedBox(width: 10),
                                            Text('Add Local Folder',
                                                style: TextStyle(color: Colors.white)),
                                          ],
                                        ),
                                      ),
                                      const PopupMenuItem(
                                        value: 'm3u_file',
                                        child: Row(
                                          children: [
                                            Icon(Icons.playlist_add_rounded,
                                                color: Colors.cyanAccent, size: 20),
                                            SizedBox(width: 10),
                                            Text('Import M3U / M3U8 File',
                                                style: TextStyle(color: Colors.white)),
                                          ],
                                        ),
                                      ),
                                      const PopupMenuItem(
                                        value: 'm3u_url',
                                        child: Row(
                                          children: [
                                            Icon(Icons.podcasts_rounded,
                                                color: Colors.tealAccent, size: 20),
                                            SizedBox(width: 10),
                                            Text('Import M3U Stream URL',
                                                style: TextStyle(color: Colors.white)),
                                          ],
                                        ),
                                      ),
                                      const PopupMenuItem(
                                        value: 'export_m3u',
                                        child: Row(
                                          children: [
                                            Icon(Icons.file_upload_rounded,
                                                color: Colors.amberAccent, size: 20),
                                            SizedBox(width: 10),
                                            Text('Export Library to M3U8',
                                                style: TextStyle(color: Colors.white)),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                              SizedBox(height: isDesktop ? 16 : 12),
                              // Segmented Control
                              Container(
                                padding: EdgeInsets.all(isDesktop ? 5 : 4),
                                decoration: BoxDecoration(
                                  color: surfaceColor,
                                  borderRadius:
                                      BorderRadius.circular(isDesktop ? 14 : 12),
                                  border: Border.all(
                                    color: Colors.white.withValues(alpha: 0.05),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    _buildTab(0, 'Playlists', Icons.queue_music_rounded,
                                        isDesktop: isDesktop),
                                    _buildTab(1, 'Tracks', Icons.audiotrack_rounded,
                                        isDesktop: isDesktop),
                                    _buildTab(2, 'Artists', Icons.person_outline_rounded,
                                        isDesktop: isDesktop),
                                  ],
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
                                        color: primaryColor.withValues(alpha: 0.3)),
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
                          child: _tabIndex == 0
                              ? _buildPlaylistsTab(primaryColor, textDark,
                                  isDesktop: isDesktop)
                              : (_tabIndex == 1
                                  ? _buildDownloadsTab(primaryColor, textDark,
                                      isDesktop: isDesktop)
                                  : _buildArtistsTab(primaryColor, textDark,
                                      isDesktop: isDesktop)),
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
        ..._m3uPlaylists.map((pl) {
          return Padding(
            padding: EdgeInsets.only(bottom: isDesktop ? 8 : 4),
            child: _buildLibraryItem(
              title: pl.name,
              subtitle:
                  '${pl.tracks.length} Songs • M3U ${pl.isNetwork ? 'Stream' : 'Playlist'}',
              iconData: pl.isNetwork ? Icons.podcasts_rounded : Icons.queue_music_rounded,
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
            ),
          );
        }),
        ..._folders.asMap().entries.map((entry) {
          final index = entry.key;
          final f = entry.value;
          return _buildLibraryItem(
            title: f['name'] as String,
            subtitle: '${f['count']} Songs • Local Folder',
            iconData: Icons.folder_rounded,
            onTap: () => _playFolder(f['path'] as String),
            onLongPress: () => _removeFolder(index),
            context: context,
            isDesktop: isDesktop,
          );
        }),
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
                      color: Colors.white, fontSize: isDesktop ? 16 : 14),
                  decoration: InputDecoration(
                    hintText: 'Search local tracks...',
                    hintStyle: TextStyle(
                        color: textDark, fontSize: isDesktop ? 16 : 14),
                    prefixIcon: Icon(Icons.search_rounded,
                        color: textDark, size: isDesktop ? 24 : 20),
                    filled: true,
                    fillColor: const Color(0xFF18232E),
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
              PopupMenuButton<String>(
                icon: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF18232E),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
                  ),
                  child: Icon(Icons.sort_rounded, color: textDark, size: 20),
                ),
                tooltip: 'Sort Tracks',
                color: const Color(0xFF18232E),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                onSelected: (String result) {
                  setState(() {
                    _currentSort = result;
                    _applySearchAndSort();
                  });
                },
                itemBuilder: (BuildContext context) => _sortOptions
                    .map((String choice) => PopupMenuItem<String>(
                          value: choice,
                          child: Text(
                            choice,
                            style: TextStyle(
                                fontSize: isDesktop ? 15 : 13,
                                color: _currentSort == choice
                                    ? primaryColor
                                    : Colors.white),
                          ),
                        ))
                    .toList(),
              ),
              const SizedBox(width: 6),
              // Layout Switcher Button
              PopupMenuButton<TrackViewMode>(
                icon: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF18232E),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
                  ),
                  child: Icon(_trackViewMode.icon, color: primaryColor, size: 20),
                ),
                tooltip: 'Layout Mode',
                color: const Color(0xFF18232E),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                onSelected: (TrackViewMode mode) {
                  setState(() {
                    _trackViewMode = mode;
                  });
                },
                itemBuilder: (BuildContext context) => TrackViewMode.values
                    .map((TrackViewMode mode) => PopupMenuItem<TrackViewMode>(
                          value: mode,
                          child: Row(
                            children: [
                              Icon(
                                mode.icon,
                                size: 18,
                                color: _trackViewMode == mode
                                    ? primaryColor
                                    : const Color(0xFF94A3B8),
                              ),
                              const SizedBox(width: 10),
                              Text(
                                mode.label,
                                style: TextStyle(
                                  fontSize: isDesktop ? 15 : 13,
                                  fontWeight: _trackViewMode == mode
                                      ? FontWeight.w600
                                      : FontWeight.w400,
                                  color: _trackViewMode == mode
                                      ? primaryColor
                                      : Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ))
                    .toList(),
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
    if (_trackViewMode == TrackViewMode.compact) {
      return ListView.builder(
        primary: false,
        padding: const EdgeInsets.only(bottom: 140),
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
          childAspectRatio: 0.82,
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
      // Standard List
      return ListView.builder(
        primary: false,
        padding: const EdgeInsets.only(bottom: 140),
        itemCount: _filteredSongs.length,
        itemBuilder: (context, index) {
          final song = _filteredSongs[index];
          return _buildLibraryItem(
            title: song.title,
            subtitle:
                '${song.artist != "Unknown Artist" ? song.artist : "Local File"} • ${(song.sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB',
            customIcon: LocalAlbumArt(
                path: song.path,
                size: isDesktop ? 80 : 56,
                borderRadius: 10),
            onTap: () {
              final paths = _filteredSongs.map((e) => e.path).toList();
              widget.onPlayFolder(paths, initialIndex: index);
            },
            onOptionSelected: (option) =>
                _handleSongOption(song, option),
            context: context,
            isDesktop: isDesktop,
          );
        },
      );
    }
  }

  Widget _buildCompactSongItem(LocalSongItem song, int index, {bool isDesktop = false}) {
    final artistName = song.artist != 'Unknown Artist' ? song.artist : 'Local File';
    return InkWell(
      onTap: () {
        final paths = _filteredSongs.map((e) => e.path).toList();
        widget.onPlayFolder(paths, initialIndex: index);
      },
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: isDesktop ? 32.0 : 16.0,
          vertical: isDesktop ? 6.0 : 4.0,
        ),
        child: Row(
          children: [
            LocalAlbumArt(
              path: song.path,
              size: isDesktop ? 44 : 36,
              borderRadius: 6,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    song.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: isDesktop ? 14 : 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    artistName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF94A3B8),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            SongOptionsMenuButton(
              iconSize: isDesktop ? 20 : 18,
              onOptionSelected: (option) => _handleSongOption(song, option),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGridSongItem(LocalSongItem song, int index, {bool isDesktop = false}) {
    final artistName = song.artist != 'Unknown Artist' ? song.artist : 'Local File';
    return GestureDetector(
      onTap: () {
        final paths = _filteredSongs.map((e) => e.path).toList();
        widget.onPlayFolder(paths, initialIndex: index);
      },
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF18232E),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.25),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: LocalAlbumArt(
                      path: song.path,
                      borderRadius: 10,
                    ),
                  ),
                  Positioned(
                    top: 4,
                    right: 4,
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.6),
                        shape: BoxShape.circle,
                      ),
                      child: SongOptionsMenuButton(
                        iconSize: 18,
                        onOptionSelected: (option) =>
                            _handleSongOption(song, option),
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
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              artistName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFF94A3B8),
                fontSize: 11,
              ),
            ),
          ],
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
            style: TextStyle(
                color: Colors.white, fontSize: isDesktop ? 16 : 14),
            decoration: InputDecoration(
              hintText: 'Search artists...',
              hintStyle: TextStyle(
                  color: textDark, fontSize: isDesktop ? 16 : 14),
              prefixIcon: Icon(Icons.search_rounded,
                  color: textDark, size: isDesktop ? 24 : 20),
              filled: true,
              fillColor: const Color(0xFF18232E),
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
                  primary: false,
                  padding: const EdgeInsets.only(bottom: 140),
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
                              size: isDesktop ? 80 : 56,
                              borderRadius: 40) // Circular avatar
                          : null,
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => LocalArtistDetailScreen(
                              artistName: artistName,
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
              size: isDesktop ? 80 : 56, color: textDark.withValues(alpha: 0.4)),
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
              style: TextStyle(
                  fontSize: isDesktop ? 15 : 13,
                  color: textDark),
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
    final thumbSize = isDesktop ? 68.0 : 52.0;

    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Padding(
        padding: EdgeInsets.symmetric(
            horizontal: isDesktop ? 32.0 : 16.0,
            vertical: isDesktop ? 10.0 : 6.0),
        child: Row(
          children: [
            Container(
              width: thumbSize,
              height: thumbSize,
              decoration: BoxDecoration(
                borderRadius: isArtist
                    ? BorderRadius.circular(thumbSize / 2)
                    : BorderRadius.circular(10),
                color: const Color(0xFF18232E),
                image: imageAsset != null
                    ? DecorationImage(
                        image: NetworkImage(imageAsset),
                        fit: BoxFit.cover,
                      )
                    : null,
                gradient: iconGradient,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.2),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: customIcon ??
                  (imageAsset == null && iconData != null
                      ? Center(
                          child: Icon(iconData,
                              color: Colors.white.withValues(alpha: 0.6),
                              size: isDesktop ? 32 : 24))
                      : null),
            ),
            SizedBox(width: isDesktop ? 20 : 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: isDesktop ? 16 : 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF94A3B8),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (onOptionSelected != null)
              SongOptionsMenuButton(
                iconSize: isDesktop ? 24 : 20,
                onOptionSelected: onOptionSelected,
              )
            else
              Icon(
                Icons.chevron_right_rounded,
                color: const Color(0xFF64748B),
                size: isDesktop ? 22 : 18,
              ),
          ],
        ),
      ),
    );
  }
}

class LocalArtistDetailScreen extends StatefulWidget {
  final String artistName;
  final List<LocalSongItem> songs;
  final Future<void> Function(List<String> audioFilePaths, {int initialIndex})
      onPlayFolder;
  final Future<void> Function(List<TrackInfo> tracks, {int initialIndex})?
      onPlayTracks;
  final Function(TrackInfo track)? onQueueTrack;
  final Function(String filePath)? onDeleteTrack;

  const LocalArtistDetailScreen({
    super.key,
    required this.artistName,
    required this.songs,
    required this.onPlayFolder,
    this.onPlayTracks,
    this.onQueueTrack,
    this.onDeleteTrack,
  });

  @override
  State<LocalArtistDetailScreen> createState() =>
      _LocalArtistDetailScreenState();
}

class _LocalArtistDetailScreenState extends State<LocalArtistDetailScreen> {
  late List<LocalSongItem> _artistSongs;

  @override
  void initState() {
    super.initState();
    _artistSongs = List.from(widget.songs);
  }

  @override
  Widget build(BuildContext context) {
    const bgDark = Color(0xFF101922);
    const surfaceColor = Color(0xFF18232E);
    const primaryColor = Color(0xFF137FEC);

    return Scaffold(
      backgroundColor: bgDark,
      appBar: AppBar(
        backgroundColor: bgDark,
        elevation: 0,
        title: Text(
          widget.artistName,
          style:
              const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        actions: [
          if (widget.onPlayTracks != null)
            IconButton(
              icon: const Icon(Icons.language, color: Colors.white70),
              tooltip: 'View Online Discography',
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ArtistProfileScreen(
                      artistName: widget.artistName,
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
              ),
              child: Row(
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: primaryColor.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: _artistSongs.isNotEmpty
                        ? LocalAlbumArt(
                            path: _artistSongs.first.path,
                            size: 64,
                            borderRadius: 12)
                        : const Icon(Icons.person,
                            color: primaryColor, size: 36),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.artistName,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${_artistSongs.length} Track${_artistSongs.length == 1 ? '' : 's'} • Local Library',
                          style: const TextStyle(
                              color: Color(0xFF94A3B8), fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: () {
                      if (_artistSongs.isEmpty) return;
                      final paths = _artistSongs.map((e) => e.path).toList();
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
              child: _artistSongs.isEmpty
                  ? const Center(
                      child: Text(
                        'No songs left for this artist.',
                        style: TextStyle(color: Color(0xFF94A3B8)),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.only(bottom: 120),
                      itemCount: _artistSongs.length,
                      itemBuilder: (context, index) {
                        final song = _artistSongs[index];
                        return ListTile(
                          leading: LocalAlbumArt(
                              path: song.path, size: 48, borderRadius: 8),
                          title: Text(
                            song.title,
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            song.album,
                            style: const TextStyle(
                                color: Color(0xFF94A3B8), fontSize: 12),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onTap: () {
                            final paths =
                                _artistSongs.map((e) => e.path).toList();
                            widget.onPlayFolder(paths, initialIndex: index);
                          },
                          trailing: SongOptionsMenuButton(
                            onOptionSelected: (option) =>
                                _handleDetailSongOption(song, option),
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
        if (!mounted) return;
        showDialog(
          context: context,
          builder: (_) => MusicInfoDialog(
            title: song.title,
            artist: song.artist,
            album: song.album,
            albumArt: art,
            sourceType: 'local',
            videoId: song.path,
            codec: fileInfo.codec,
            sampleRate: fileInfo.formattedSampleRate,
            channels: fileInfo.formattedChannels,
            bitDepth: fileInfo.formattedBitDepth,
            fileSizeBytes: song.sizeBytes,
            duration: d,
          ),
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
            backgroundColor: const Color(0xFF18232E),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16)),
            title: const Text('Delete Song Permanently?',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            content: Text(
              'Are you sure you want to delete "${song.title}"? This action cannot be undone.',
              style: const TextStyle(color: Color(0xFF94A3B8)),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancel',
                      style: TextStyle(color: Color(0xFF94A3B8)))),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.redAccent,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Delete',
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
              _artistSongs.removeWhere((s) => s.path == song.path);
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
