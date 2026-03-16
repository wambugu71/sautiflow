import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import 'models/recently_played_track.dart';
import 'services/recently_played_service.dart';

class RecentlyPlayedScreen extends StatefulWidget {
  final Future<void> Function(List<RecentlyPlayedTrack> tracks,
      {int initialIndex}) onPlayTracks;

  const RecentlyPlayedScreen({
    super.key,
    required this.onPlayTracks,
  });

  @override
  State<RecentlyPlayedScreen> createState() => _RecentlyPlayedScreenState();
}

class _RecentlyPlayedScreenState extends State<RecentlyPlayedScreen> {
  bool _isLoading = true;
  List<RecentlyPlayedTrack> _history = [];

  // Grouped history
  final List<RecentlyPlayedTrack> _today = [];
  final List<RecentlyPlayedTrack> _yesterday = [];
  final List<RecentlyPlayedTrack> _earlier = [];

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    setState(() => _isLoading = true);
    final history = await RecentlyPlayedService.instance.getHistory();

    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final yesterdayStart = todayStart.subtract(const Duration(days: 1));

    _today.clear();
    _yesterday.clear();
    _earlier.clear();

    for (final track in history) {
      if (track.playedAt.isAfter(todayStart)) {
        _today.add(track);
      } else if (track.playedAt.isAfter(yesterdayStart)) {
        _yesterday.add(track);
      } else {
        _earlier.add(track);
      }
    }

    setState(() {
      _history = history;
      _isLoading = false;
    });
  }

  Future<void> _clearHistory() async {
    await RecentlyPlayedService.instance.clearHistory();
    await _loadHistory();
  }

  String _formatDuration(int seconds) {
    if (seconds <= 0) return 'Unknown';
    final d = Duration(seconds: seconds);
    final min = d.inMinutes;
    final sec = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$min:$sec';
  }

  Widget _buildSection(String title, List<RecentlyPlayedTrack> tracks) {
    if (tracks.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Text(
            title.toUpperCase(),
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.2,
              color: Color(0xFFA0A0A0), // text-secondary from mockup
            ),
          ),
        ),
        ListView.builder(
          padding: EdgeInsets.zero,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: tracks.length,
          itemBuilder: (context, index) {
            final track = tracks[index];
            return _buildTrackItem(track, tracks, index);
          },
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildTrackItem(RecentlyPlayedTrack track,
      List<RecentlyPlayedTrack> sectionGroup, int sectionIndex) {
    return InkWell(
      onTap: () {
        // Find the index of this track in the COMPLETE history
        // to pass the whole history block to the player
        final idxInFullList = _history.indexOf(track);
        if (idxInFullList >= 0) {
          widget.onPlayTracks(_history, initialIndex: idxInFullList);
        }
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
        child: Row(
          children: [
            // Thumbnail
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                color: const Color(0xFF1E1E1E),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.4),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: track.thumbnailUrl != null
                    ? CachedNetworkImage(
                        imageUrl: track.thumbnailUrl!,
                        fit: BoxFit.cover,
                        errorWidget: (context, url, error) =>
                            const Icon(Icons.music_note, color: Colors.white54),
                      )
                    : const Icon(Icons.music_note, color: Colors.white54),
              ),
            ),
            const SizedBox(width: 16),

            // Text Details
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          track.title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (!track.isLocal) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                                color: Colors.white.withOpacity(0.05)),
                          ),
                          child: const Text(
                            'ONLINE',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFFA0A0A0),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${track.artist} • ${_formatDuration(track.durationSeconds)}',
                    style: const TextStyle(
                      color: Color(0xFFA0A0A0),
                      fontSize: 14,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),

            // Context Menu Button
            IconButton(
              icon: const Icon(Icons.more_vert, color: Color(0xFFA0A0A0)),
              onPressed: () {
                // Future contextual actions
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const Color bgDark = Color(0xFF121212); // background-dark from mockup
    const Color primaryColor = Color(0xFF256AF4); // primary from mockup

    return Scaffold(
      backgroundColor: bgDark,
      body: LayoutBuilder(builder: (context, constraints) {
        final isDesktop = constraints.maxWidth >= 800;
        return Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1000.0),
            child: SafeArea(
              child: Column(
                children: [
                  // Header
                  Container(
                    padding: EdgeInsets.fromLTRB(isDesktop ? 48 : 24,
                        isDesktop ? 48 : 24, isDesktop ? 48 : 24, 16),
                    decoration: BoxDecoration(
                      color: bgDark.withOpacity(0.95),
                      border: Border(
                        bottom:
                            BorderSide(color: Colors.white.withOpacity(0.05)),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Recently Played',
                          style: TextStyle(
                            fontSize:
                                isDesktop ? 36 : 28, // Matches text-3xl roughly
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            letterSpacing: -0.5,
                          ),
                        ),
                        TextButton(
                          onPressed: _history.isEmpty ? null : _clearHistory,
                          style: TextButton.styleFrom(
                            foregroundColor: primaryColor,
                            textStyle: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: isDesktop ? 16 : 14),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(30)),
                          ),
                          child: const Text('Clear History'),
                        ),
                      ],
                    ),
                  ),

                  // Content
                  Expanded(
                    child: _isLoading
                        ? const Center(
                            child:
                                CircularProgressIndicator(color: primaryColor))
                        : _history.isEmpty
                            ? const Center(
                                child: Text(
                                  'No recent history.',
                                  style: TextStyle(color: Color(0xFFA0A0A0)),
                                ),
                              )
                            : RefreshIndicator(
                                color: primaryColor,
                                backgroundColor: bgDark,
                                onRefresh: _loadHistory,
                                child: ListView(
                                  padding: EdgeInsets.only(
                                      top: 16,
                                      bottom: 120,
                                      left: isDesktop ? 24 : 0,
                                      right: isDesktop ? 24 : 0),
                                  children: [
                                    _buildSection('Today', _today),
                                    _buildSection('Yesterday', _yesterday),
                                    _buildSection(
                                        'Earlier This Week', _earlier),
                                  ],
                                ),
                              ),
                  ),
                ],
              ),
            ),
          ),
        );
      }),
    );
  }
}
