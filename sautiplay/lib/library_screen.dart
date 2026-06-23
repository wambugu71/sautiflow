import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:loading_indicator_m3e/loading_indicator_m3e.dart';
import 'package:path/path.dart' as p;
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'liked_songs_screen.dart'; // NEW
import 'models/liked_song.dart'; // NEW
import 'models/local_song_item.dart';
import 'widgets/local_album_art.dart';

class LibraryScreen extends StatefulWidget {
  final Future<void> Function(List<String> audioFilePaths, {int initialIndex})
      onPlayFolder;
  final Future<void> Function(List<LikedSong> tracks, {int initialIndex})
      onPlayLikedSongs; // NEW
  final bool isNested;

  const LibraryScreen({
    super.key,
    required this.onPlayFolder,
    required this.onPlayLikedSongs,
    this.isNested = false,
  });

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;
  static const String _prefsKey = 'sautiplay_library_folders';

  // State
  List<Map<String, dynamic>> _folders = [];
  List<LocalSongItem> _allSongs = [];
  List<LocalSongItem> _filteredSongs = [];
  bool _isLoading = true;
  int _tabIndex = 0;

  // Search & Sort filters
  final TextEditingController _searchController = TextEditingController();
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
    _loadSavedFolders();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadSavedFolders() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedData = prefs.getStringList(_prefsKey) ?? [];

      final loadedFolders = savedData
          .map((item) => jsonDecode(item) as Map<String, dynamic>)
          .toList();

      setState(() {
        _folders = loadedFolders;
      });
      await _updateAllSongs();
    } catch (e) {
      debugPrint('Error loading folders: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _updateAllSongs() async {
    setState(() => _isLoading = true);
    final allItems = <LocalSongItem>[];
    for (final f in _folders) {
      final paths = await _scanForAudioFiles(f['path'] as String);
      for (final path in paths) {
        try {
          final stat = await File(path).stat();
          allItems.add(LocalSongItem.fallback(path, stat.size, stat.modified));
        } catch (_) {
          allItems.add(LocalSongItem.fallback(path, 0, DateTime.now()));
        }
      }
    }
    if (mounted) {
      setState(() {
        _allSongs = allItems;
        _isLoading = false;
        _applySearchAndSort();
      });
    }
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

  Widget _buildTab(int index, String title, {bool isDesktop = false}) {
    final isSelected = _tabIndex == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _tabIndex = index),
        child: Container(
          padding: EdgeInsets.symmetric(vertical: isDesktop ? 10 : 6),
          decoration: BoxDecoration(
            color:
                isSelected ? Colors.white.withOpacity(0.1) : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 2,
                      offset: const Offset(0, 1),
                    ),
                  ]
                : null,
          ),
          alignment: Alignment.center,
          child: Text(title,
              style: TextStyle(
                  fontSize: isDesktop ? 16 : 14,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                  color: isSelected ? Colors.white : const Color(0xFF94A3B8))),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    // Theme colors from mockup
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
                              top: widget.isNested ? 8.0 : (isDesktop ? 40.0 : 24.0),
                              left: isDesktop ? 32.0 : 16.0,
                              right: isDesktop ? 32.0 : 16.0,
                              bottom: isDesktop ? 16.0 : 8.0),
                          decoration: BoxDecoration(
                            color: bgDark.withOpacity(0.95),
                            border: Border(
                              bottom: BorderSide(
                                  color: Colors.white.withOpacity(0.05)),
                            ),
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
                                            fontSize: isDesktop ? 34 : 24,
                                            fontWeight: FontWeight.bold,
                                            color: textLight,
                                            letterSpacing: -0.5,
                                          ),
                                        ),
                                    ],
                                  ),
                                  IconButton(
                                    onPressed: _addDirectory,
                                    icon: Icon(Icons.add,
                                        color: textDark,
                                        size: isDesktop ? 32 : 24),
                                    splashRadius: isDesktop ? 32 : 24,
                                    tooltip: 'Add Local Folder',
                                  ),
                                ],
                              ),
                              SizedBox(height: isDesktop ? 24 : 16),
                              // Segmented Control
                              Container(
                                padding: EdgeInsets.all(isDesktop ? 6 : 4),
                                decoration: BoxDecoration(
                                  color: surfaceColor,
                                  borderRadius:
                                      BorderRadius.circular(isDesktop ? 12 : 8),
                                ),
                                child: Row(
                                  children: [
                                    _buildTab(0, 'Playlists',
                                        isDesktop: isDesktop),
                                    _buildTab(1, 'Downloads',
                                        isDesktop: isDesktop),
                                    _buildTab(2, 'Artists',
                                        isDesktop: isDesktop),
                                  ],
                                ),
                              ),
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
                                  : _buildEmptyState(textDark,
                                      message:
                                          'Artists section coming soon...')),
                        ),
                      ],
                    ),
                    if (_isLoading)
                      Container(
                        color: bgDark.withOpacity(0.5),
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
    if (_folders.isEmpty && !_isLoading) {
      return _buildEmptyState(textDark);
    }
    return ListView(
      padding: EdgeInsets.only(top: isDesktop ? 32 : 16, bottom: 120),
      children: [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: isDesktop ? 32.0 : 16.0),
          child: ElevatedButton.icon(
            onPressed: _shufflePlayAll,
            icon: const Icon(Icons.shuffle, color: Colors.white),
            label: Text('Shuffle Play',
                style: TextStyle(
                    fontSize: isDesktop ? 18 : 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white)),
            style: ElevatedButton.styleFrom(
              backgroundColor: primaryColor,
              foregroundColor: Colors.white,
              padding: EdgeInsets.symmetric(vertical: isDesktop ? 20 : 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(30)),
              elevation: 0,
            ),
          ),
        ),
        SizedBox(height: isDesktop ? 24 : 16),
        _buildLibraryItem(
          title: 'Liked Songs',
          subtitle: 'Playlist • Saved Tracks',
          iconData: Icons.favorite,
          iconGradient: const LinearGradient(
            colors: [Color(0xFF4527A0), Color(0xFF6A1B9A)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => LikedSongsScreen(
                  onPlayTracks: widget.onPlayLikedSongs,
                ),
              ),
            );
          },
          context: context,
          isDesktop: isDesktop,
        ),
        SizedBox(height: isDesktop ? 12 : 8),
        ..._folders.asMap().entries.map((entry) {
          final index = entry.key;
          final f = entry.value;
          return _buildLibraryItem(
            title: f['name'] as String,
            subtitle: '${f['count']} Songs • Folder',
            iconData: Icons.folder,
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
        // Search & Sort Bar
        Padding(
          padding: EdgeInsets.symmetric(
              horizontal: isDesktop ? 32.0 : 16.0,
              vertical: isDesktop ? 16.0 : 8.0),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  style: TextStyle(
                      color: Colors.white, fontSize: isDesktop ? 18 : 16),
                  decoration: InputDecoration(
                    hintText: 'Search downloaded songs...',
                    hintStyle: TextStyle(
                        color: textDark, fontSize: isDesktop ? 18 : 16),
                    prefixIcon: Icon(Icons.search,
                        color: textDark, size: isDesktop ? 28 : 24),
                    filled: true,
                    fillColor: const Color(0xFF18232E),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(isDesktop ? 16 : 12),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(vertical: 0),
                  ),
                  onChanged: (v) => _applySearchAndSort(),
                ),
              ),
              const SizedBox(width: 8),
              PopupMenuButton<String>(
                icon: Icon(Icons.sort, color: textDark),
                color: const Color(0xFF18232E),
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
                                fontSize: isDesktop ? 16 : 14,
                                color: _currentSort == choice
                                    ? primaryColor
                                    : Colors.white),
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
              : ListView.builder(
                  padding: EdgeInsets.only(bottom: 120),
                  itemCount: _filteredSongs.length + 1,
                  itemBuilder: (context, index) {
                    if (index == 0) {
                      return Padding(
                        padding: EdgeInsets.all(isDesktop ? 32.0 : 16.0),
                        child: ElevatedButton.icon(
                          onPressed: () {
                            if (_filteredSongs.isEmpty) return;
                            final paths =
                                _filteredSongs.map((e) => e.path).toList();
                            paths.shuffle();
                            widget.onPlayFolder(paths);
                          },
                          icon: Icon(Icons.shuffle,
                              color: Colors.white, size: isDesktop ? 28 : 24),
                          label: Text('Shuffle All',
                              style: TextStyle(
                                  fontSize: isDesktop ? 18 : 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: primaryColor,
                            foregroundColor: Colors.white,
                            padding: EdgeInsets.symmetric(
                                vertical: isDesktop ? 20 : 14),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(30)),
                            elevation: 0,
                          ),
                        ),
                      );
                    }

                    final realIndex = index - 1;
                    final song = _filteredSongs[realIndex];
                    return _buildLibraryItem(
                      title: song.title,
                      subtitle:
                          'Local Audio • ${(song.sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB',
                      customIcon: LocalAlbumArt(
                          path: song.path,
                          size: isDesktop ? 96 : 64,
                          borderRadius: 12),
                      onTap: () {
                        final paths =
                            _filteredSongs.map((e) => e.path).toList();
                        widget.onPlayFolder(paths, initialIndex: realIndex);
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
              size: isDesktop ? 96 : 64, color: textDark.withOpacity(0.5)),
          SizedBox(height: isDesktop ? 24 : 16),
          Text(
            message,
            style: TextStyle(
                fontSize: isDesktop ? 24 : 18,
                fontWeight: FontWeight.w600,
                color: textDark),
          ),
          SizedBox(height: isDesktop ? 12 : 8),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: isDesktop ? 64.0 : 32.0),
            child: Text(
              subMessage,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: isDesktop ? 16 : 14,
                  color: textDark.withOpacity(0.7)),
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
    bool isDesktop = false,
  }) {
    final isLossless = subtitle.contains('Lossless');

    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress ??
          () {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                  content: Text('Hold to remove folders that you imported.')),
            );
          },
      child: Padding(
        padding: EdgeInsets.symmetric(
            horizontal: isDesktop ? 32.0 : 16.0,
            vertical: isDesktop ? 12.0 : 8.0),
        child: Row(
          children: [
            Container(
              width: isDesktop ? 96 : 64,
              height: isDesktop ? 96 : 64,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
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
                    color: Colors.black.withOpacity(0.2),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: customIcon ??
                  (imageAsset == null && iconData != null
                      ? Center(
                          child: Icon(iconData,
                              color: Colors.white.withOpacity(0.5),
                              size: isDesktop ? 48 : 32))
                      : null),
            ),
            SizedBox(width: isDesktop ? 24 : 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: isDesktop ? 20 : 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  SizedBox(height: isDesktop ? 8 : 4),
                  Row(
                    children: [
                      if (subtitle.contains('Playlist') ||
                          subtitle.contains('Folder'))
                        Padding(
                          padding: const EdgeInsets.only(right: 6.0),
                          child: Icon(Icons.download_done,
                              size: isDesktop ? 18 : 14, color: Colors.green),
                        ),
                      if (isLossless)
                        Container(
                          margin: const EdgeInsets.only(right: 6.0),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 4, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFF18232E),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'LOSSLESS',
                            style: TextStyle(
                                fontSize: isDesktop ? 12 : 10,
                                fontWeight: FontWeight.bold,
                                color: const Color(0xFF94A3B8)),
                          ),
                        ),
                      Expanded(
                        child: Text(
                          subtitle.replaceAll(' • Lossless', ''),
                          style: TextStyle(
                            fontSize: isDesktop ? 16 : 14,
                            color: const Color(0xFF94A3B8),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            IconButton(
              icon: Icon(Icons.more_vert,
                  color: const Color(0xFF94A3B8), size: isDesktop ? 28 : 24),
              onPressed: () {},
            ),
          ],
        ),
      ),
    );
  }
}
