import 'package:flutter/material.dart';

import 'album_detail_screen.dart'; // For TrackInfo
import 'home_screen.dart';
import 'isolate_player.dart';
import 'library_screen.dart';
import 'models/cached_stream_item.dart';
import 'models/liked_song.dart';
import 'search_screen.dart';
import 'services/app_theme_service.dart';

class CombinedHomeScreen extends StatefulWidget {
  final Future<void> Function(List<TrackInfo> tracks, {int initialIndex})?
      onPlayTracks;
  final VoidCallback? onGoToDownloads;
  final Future<void> Function(List<String> audioFilePaths, {int initialIndex})
      onPlayFolder;
  final Future<void> Function(List<LikedSong> tracks, {int initialIndex})
      onPlayLikedSongs;
  final Future<void> Function(List<CachedStreamItem> tracks, {int initialIndex})?
      onPlayCachedStreams;
  final Function(TrackInfo track)? onQueueTrack;
  final Function(String filePath)? onDeleteTrack;
  final IsolateAudioPlayer? player;
  final void Function(String filePath, String title, String artist)? onPlayNetworkFile;
  final void Function(List<dynamic> entries, dynamic config, int initialIndex)? onPlayFtpFolder;

  const CombinedHomeScreen({
    super.key,
    this.onPlayTracks,
    this.onGoToDownloads,
    required this.onPlayFolder,
    required this.onPlayLikedSongs,
    this.onPlayCachedStreams,
    this.onQueueTrack,
    this.onDeleteTrack,
    this.player,
    this.onPlayNetworkFile,
    this.onPlayFtpFolder,
  });

  @override
  State<CombinedHomeScreen> createState() => _CombinedHomeScreenState();
}

class _CombinedHomeScreenState extends State<CombinedHomeScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  Color get _bgDark => context.bgDark;
  Color get _surfaceColor => context.cardDark;
  Color get _primary => context.primaryColor;
  Color get _textPrimary => context.textPrimary;
  Color get _textDark => context.textMuted;
  Color get _outline => context.outlineColor;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Widget _buildTab(int index, String title, IconData icon, {bool isDesktop = false}) {
    return AnimatedBuilder(
      animation: _tabController,
      builder: (context, _) {
        final isSelected = _tabController.index == index;
        return Expanded(
          child: GestureDetector(
            onTap: () => _tabController.animateTo(index),
            behavior: HitTestBehavior.opaque,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeInOut,
              padding: EdgeInsets.symmetric(
                vertical: isDesktop ? 10 : 8,
                horizontal: 8,
              ),
              decoration: BoxDecoration(
                color: isSelected
                    ? _primary.withValues(alpha: 0.22)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(isDesktop ? 10 : 8),
                border: isSelected
                    ? Border.all(
                        color: _primary.withValues(alpha: 0.4),
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
                    size: isDesktop ? 18 : 16,
                    color: isSelected ? _primary : _textDark,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: isDesktop ? 15 : 13,
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                      color: isSelected ? _textPrimary : _textDark,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  int _libraryTabIndex = 0;

  void _goToLibraryDownloads() {
    setState(() {
      _libraryTabIndex = 1;
    });
    _tabController.animateTo(1);
    if (widget.onGoToDownloads != null) {
      widget.onGoToDownloads!();
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth >= 800;

        return Scaffold(
          backgroundColor: _bgDark,
          body: SafeArea(
            bottom: false,
            child: Column(
              children: [
                // Custom segmented control at the top
                Container(
                  padding: EdgeInsets.fromLTRB(
                    isDesktop ? 32 : 16,
                    isDesktop ? 16 : 10,
                    isDesktop ? 32 : 16,
                    6,
                  ),
                  color: _bgDark,
                  child: Row(
                    children: [
                      Expanded(
                        child: Container(
                          padding: EdgeInsets.all(isDesktop ? 5 : 4),
                          decoration: BoxDecoration(
                            color: _surfaceColor,
                            borderRadius:
                                BorderRadius.circular(isDesktop ? 14 : 12),
                            border: Border.all(
                              color: _outline.withValues(alpha: 0.3),
                            ),
                          ),
                          child: Row(
                            children: [
                              _buildTab(0, 'Discover',
                                  Icons.compass_calibration_rounded,
                                  isDesktop: isDesktop),
                              _buildTab(1, 'Library', Icons.library_music_rounded,
                                  isDesktop: isDesktop),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      IconButton(
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => SearchScreen(
                                onPlayTracks: widget.onPlayTracks,
                              ),
                            ),
                          );
                        },
                        tooltip: 'Search Music',
                        icon: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: _surfaceColor,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: _outline.withValues(alpha: 0.3),
                            ),
                          ),
                          child: Icon(
                            Icons.search_rounded,
                            color: _textPrimary,
                            size: 20,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                // Tab content
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      HomeScreen(
                        onPlayTracks: widget.onPlayTracks,
                        onGoToDownloads: _goToLibraryDownloads,
                        isNested: true,
                      ),
                      LibraryScreen(
                        onPlayFolder: widget.onPlayFolder,
                        onPlayLikedSongs: widget.onPlayLikedSongs,
                        onPlayCachedStreams: widget.onPlayCachedStreams,
                        onPlayTracks: widget.onPlayTracks,
                        onQueueTrack: widget.onQueueTrack,
                        onDeleteTrack: widget.onDeleteTrack,
                        player: widget.player,
                        onPlayNetworkFile: widget.onPlayNetworkFile,
                        onPlayFtpFolder: widget.onPlayFtpFolder,
                        isNested: true,
                        initialTabIndex: _libraryTabIndex,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
