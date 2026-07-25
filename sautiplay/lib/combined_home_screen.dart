import 'package:flutter/material.dart';

import 'album_detail_screen.dart'; // For TrackInfo
import 'home_screen.dart';
import 'library_screen.dart';
import 'models/liked_song.dart';
import 'search_screen.dart';

class CombinedHomeScreen extends StatefulWidget {
  final Future<void> Function(List<TrackInfo> tracks, {int initialIndex})?
      onPlayTracks;
  final VoidCallback? onGoToDownloads;
  final Future<void> Function(List<String> audioFilePaths, {int initialIndex})
      onPlayFolder;
  final Future<void> Function(List<LikedSong> tracks, {int initialIndex})
      onPlayLikedSongs;
  final Function(TrackInfo track)? onQueueTrack;
  final Function(String filePath)? onDeleteTrack;

  const CombinedHomeScreen({
    super.key,
    this.onPlayTracks,
    this.onGoToDownloads,
    required this.onPlayFolder,
    required this.onPlayLikedSongs,
    this.onQueueTrack,
    this.onDeleteTrack,
  });

  @override
  State<CombinedHomeScreen> createState() => _CombinedHomeScreenState();
}

class _CombinedHomeScreenState extends State<CombinedHomeScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final Color _bgDark = const Color(0xFF101922);
  final Color _surfaceColor = const Color(0xFF18232E);

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Widget _buildTab(int index, String title, {bool isDesktop = false}) {
    return AnimatedBuilder(
      animation: _tabController,
      builder: (context, _) {
        final isSelected = _tabController.index == index;
        return Expanded(
          child: GestureDetector(
            onTap: () => _tabController.animateTo(index),
            child: Container(
              padding: EdgeInsets.symmetric(vertical: isDesktop ? 10 : 8),
              decoration: BoxDecoration(
                color: isSelected
                    ? Colors.white.withValues(alpha: 0.1)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
                boxShadow: isSelected
                    ? [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.1),
                          blurRadius: 2,
                          offset: const Offset(0, 1),
                        ),
                      ]
                    : null,
              ),
              alignment: Alignment.center,
              child: Text(
                title,
                style: TextStyle(
                  fontSize: isDesktop ? 16 : 14,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                  color: isSelected
                      ? Colors.white
                      : const Color(0xFF94A3B8),
                ),
              ),
            ),
          ),
        );
      },
    );
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
                    isDesktop ? 24 : 12,
                    isDesktop ? 32 : 16,
                    8,
                  ),
                  color: _bgDark.withValues(alpha: 0.95),
                  child: Container(
                    padding: EdgeInsets.all(isDesktop ? 6 : 4),
                    decoration: BoxDecoration(
                      color: _surfaceColor,
                      borderRadius: BorderRadius.circular(isDesktop ? 12 : 10),
                    ),
                    child: Row(
                      children: [
                        _buildTab(0, 'Discover', isDesktop: isDesktop),
                        _buildTab(1, 'Search', isDesktop: isDesktop),
                        _buildTab(2, 'My Library', isDesktop: isDesktop),
                      ],
                    ),
                  ),
                ),
                // Tab content
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      HomeScreen(
                        onPlayTracks: widget.onPlayTracks,
                        onGoToDownloads: widget.onGoToDownloads,
                        isNested: true,
                      ),
                      SearchScreen(
                        onPlayTracks: widget.onPlayTracks,
                      ),
                      LibraryScreen(
                        onPlayFolder: widget.onPlayFolder,
                        onPlayLikedSongs: widget.onPlayLikedSongs,
                        onPlayTracks: widget.onPlayTracks,
                        onQueueTrack: widget.onQueueTrack,
                        onDeleteTrack: widget.onDeleteTrack,
                        isNested: true,
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
