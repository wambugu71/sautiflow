import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import 'models/cached_stream_item.dart';
import 'services/app_theme_service.dart';
import 'services/cached_stream_service.dart';
import 'widgets/music_info_dialog.dart';
import 'album_detail_screen.dart'; // for TrackInfo

class CachedStreamsScreen extends StatefulWidget {
  final Future<void> Function(List<CachedStreamItem> tracks, {int initialIndex})
      onPlayTracks;
  final Function(TrackInfo track)? onQueueTrack;

  const CachedStreamsScreen({
    super.key,
    required this.onPlayTracks,
    this.onQueueTrack,
  });

  @override
  State<CachedStreamsScreen> createState() => _CachedStreamsScreenState();
}

class _CachedStreamsScreenState extends State<CachedStreamsScreen> {
  final TextEditingController _searchController = TextEditingController();
  bool _isSearching = false;
  String _searchQuery = '';
  String _sortBy = 'Date Added'; // 'Date Added', 'Name (A-Z)', 'Size (Largest)'

  Color get _bgDark => context.bgDark;
  Color get _surfaceColor => context.cardDark;
  Color get _primary => context.primaryColor;
  Color get _textPrimary => context.textPrimary;
  Color get _textDark => context.textMuted;
  Color get _outline => context.outlineColor;

  @override
  void initState() {
    super.initState();
    CachedStreamService.instance.refreshCache();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<CachedStreamItem> _filterAndSort(List<CachedStreamItem> items) {
    var filtered = items.where((item) {
      if (_searchQuery.isEmpty) return true;
      final q = _searchQuery.toLowerCase();
      return item.title.toLowerCase().contains(q) ||
          item.artist.toLowerCase().contains(q);
    }).toList();

    switch (_sortBy) {
      case 'Name (A-Z)':
        filtered.sort(
            (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
        break;
      case 'Name (Z-A)':
        filtered.sort(
            (a, b) => b.title.toLowerCase().compareTo(a.title.toLowerCase()));
        break;
      case 'Size (Largest)':
        filtered.sort((a, b) => b.fileSizeBytes.compareTo(a.fileSizeBytes));
        break;
      case 'Size (Smallest)':
        filtered.sort((a, b) => a.fileSizeBytes.compareTo(b.fileSizeBytes));
        break;
      case 'Date Added':
      default:
        filtered.sort((a, b) => b.cachedAt.compareTo(a.cachedAt));
        break;
    }
    return filtered;
  }

  void _confirmClearAll(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _surfaceColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Clear Stream Cache?',
          style: TextStyle(color: _textPrimary, fontWeight: FontWeight.bold),
        ),
        content: Text(
          'This will delete all locally cached audio stream files. New streams will re-cache when played.',
          style: TextStyle(color: _textDark, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('Cancel', style: TextStyle(color: _textDark)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () async {
              Navigator.of(ctx).pop();
              await CachedStreamService.instance.clearAllCache();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Stream cache cleared.')),
                );
              }
            },
            child: const Text('Clear All'),
          ),
        ],
      ),
    );
  }

  void _showTrackOptions(
      BuildContext context, CachedStreamItem track, bool isDesktop) {
    showModalBottomSheet(
      context: context,
      backgroundColor: _surfaceColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header tile with artwork
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20.0),
                  child: Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          color: _bgDark,
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: track.thumbnailUrl != null
                              ? CachedNetworkImage(
                                  imageUrl: track.thumbnailUrl!,
                                  fit: BoxFit.cover,
                                  errorWidget: (_, __, ___) => const Icon(
                                      Icons.podcasts_rounded,
                                      color: Colors.tealAccent),
                                )
                              : const Icon(Icons.podcasts_rounded,
                                  color: Colors.tealAccent),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              track.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: _textPrimary,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${track.artist} • ${track.formattedSize}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: _textDark, fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 24, thickness: 0.5),

                // Option: Queue Next
                if (widget.onQueueTrack != null)
                  ListTile(
                    leading:
                        Icon(Icons.queue_music_rounded, color: _textPrimary),
                    title: Text('Add to Queue',
                        style: TextStyle(color: _textPrimary)),
                    onTap: () {
                      Navigator.of(ctx).pop();
                      final trackInfo = TrackInfo(
                        videoId: track.filePath,
                        title: track.title,
                        artist: track.artist,
                        thumbnailUrl: track.thumbnailUrl,
                        durationSeconds: track.durationSeconds,
                      );
                      widget.onQueueTrack!(trackInfo);
                    },
                  ),

                // Option: Song Details & Diagnostics
                ListTile(
                  leading: Icon(Icons.info_outline_rounded, color: _primary),
                  title: Text('Track Details & Cache Info',
                      style: TextStyle(color: _textPrimary)),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    MusicInfoDialog.show(
                      context,
                      title: track.title,
                      artist: track.artist,
                      sourceType: 'online',
                      videoId: track.filePath,
                      codec: 'MP3 (Cached)',
                      fileSizeBytes: track.fileSizeBytes,
                      duration: Duration(seconds: track.durationSeconds),
                    );
                  },
                ),

                // Option: Share File
                if (File(track.filePath).existsSync())
                  ListTile(
                    leading:
                        Icon(Icons.share_outlined, color: Colors.blueAccent),
                    title: Text('Share Audio File',
                        style: TextStyle(color: _textPrimary)),
                    onTap: () async {
                      Navigator.of(ctx).pop();
                      try {
                        await Share.shareXFiles(
                          [XFile(track.filePath)],
                          text: '${track.title} - ${track.artist}',
                        );
                      } catch (e) {
                        debugPrint('Error sharing file: $e');
                      }
                    },
                  ),

                // Option: Remove from Cache
                ListTile(
                  leading: const Icon(Icons.delete_outline_rounded,
                      color: Colors.redAccent),
                  title: const Text('Delete from Cache',
                      style: TextStyle(color: Colors.redAccent)),
                  onTap: () async {
                    Navigator.of(ctx).pop();
                    await CachedStreamService.instance
                        .removeCachedStream(track.filePath);
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                            content: Text(
                                'Removed "${track.title}" from local cache.')),
                      );
                    }
                  },
                ),
              ],
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
        final contentMaxWidth = isDesktop ? 1000.0 : double.infinity;

        return Scaffold(
          backgroundColor: _bgDark,
          body: SafeArea(
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: contentMaxWidth),
                child: Column(
                  children: [
                    // Header Bar
                    _buildHeader(isDesktop),

                    // Search & Filter bar (if searching)
                    if (_isSearching) _buildSearchBar(isDesktop),

                    // Main Content
                    Expanded(
                      child: ValueListenableBuilder<List<CachedStreamItem>>(
                        valueListenable:
                            CachedStreamService.instance.cachedStreamsNotifier,
                        builder: (context, rawItems, _) {
                          final items = _filterAndSort(rawItems);

                          if (rawItems.isEmpty) {
                            return _buildEmptyState(isDesktop);
                          }

                          if (items.isEmpty && _searchQuery.isNotEmpty) {
                            return Center(
                              child: Text(
                                'No cached streams matching "$_searchQuery"',
                                style:
                                    TextStyle(color: _textDark, fontSize: 15),
                              ),
                            );
                          }

                          return ListView.builder(
                            padding: const EdgeInsets.only(
                                top: 8, bottom: 120, left: 16, right: 16),
                            itemCount: 1 + items.length,
                            itemBuilder: (context, index) {
                              if (index == 0) {
                                return _buildActionSummaryCard(
                                    rawItems, items, isDesktop);
                              }
                              final track = items[index - 1];
                              return _buildTrackCard(
                                  track, items, index - 1, isDesktop);
                            },
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

  Widget _buildHeader(bool isDesktop) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        isDesktop ? 32 : 16,
        isDesktop ? 24 : 16,
        isDesktop ? 32 : 16,
        12,
      ),
      decoration: BoxDecoration(
        color: _bgDark,
        border: Border(
          bottom: BorderSide(color: Colors.white.withValues(alpha: 0.05)),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              IconButton(
                icon: Icon(Icons.arrow_back_rounded,
                    color: _textPrimary, size: isDesktop ? 26 : 22),
                onPressed: () => Navigator.of(context).pop(),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Cached Streams',
                    style: TextStyle(
                      fontSize: isDesktop ? 28 : 22,
                      fontWeight: FontWeight.bold,
                      color: _textPrimary,
                      letterSpacing: -0.5,
                    ),
                  ),
                  ValueListenableBuilder<int>(
                    valueListenable:
                        CachedStreamService.instance.totalSizeBytesNotifier,
                    builder: (context, totalBytes, _) {
                      return ValueListenableBuilder<List<CachedStreamItem>>(
                        valueListenable:
                            CachedStreamService.instance.cachedStreamsNotifier,
                        builder: (context, items, _) {
                          return Text(
                            '${items.length} Tracks • ${CachedStreamService.formatBytes(totalBytes)} Cached',
                            style: TextStyle(
                              color: _textDark,
                              fontSize: isDesktop ? 13 : 11,
                              fontWeight: FontWeight.w500,
                            ),
                          );
                        },
                      );
                    },
                  ),
                ],
              ),
            ],
          ),
          Row(
            children: [
              IconButton(
                icon: Icon(
                  _isSearching ? Icons.close_rounded : Icons.search_rounded,
                  color: _textPrimary,
                  size: isDesktop ? 24 : 22,
                ),
                onPressed: () {
                  setState(() {
                    _isSearching = !_isSearching;
                    if (!_isSearching) {
                      _searchQuery = '';
                      _searchController.clear();
                    }
                  });
                },
              ),
              PopupMenuButton<String>(
                icon: Icon(Icons.sort_rounded,
                    color: _textPrimary, size: isDesktop ? 24 : 22),
                color: _surfaceColor,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
                onSelected: (val) {
                  setState(() => _sortBy = val);
                },
                itemBuilder: (ctx) => [
                  'Date Added',
                  'Name (A-Z)',
                  'Name (Z-A)',
                  'Size (Largest)',
                  'Size (Smallest)',
                ]
                    .map((option) => PopupMenuItem(
                          value: option,
                          child: Row(
                            children: [
                              if (_sortBy == option)
                                Icon(Icons.check_rounded,
                                    color: _primary, size: 18)
                              else
                                const SizedBox(width: 18),
                              const SizedBox(width: 8),
                              Text(option,
                                  style: TextStyle(color: _textPrimary)),
                            ],
                          ),
                        ))
                    .toList(),
              ),
              IconButton(
                icon: const Icon(Icons.delete_sweep_rounded,
                    color: Colors.redAccent, size: 22),
                tooltip: 'Clear Stream Cache',
                onPressed: () => _confirmClearAll(context),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar(bool isDesktop) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isDesktop ? 32 : 16,
        vertical: 8,
      ),
      color: _bgDark,
      child: TextField(
        controller: _searchController,
        autofocus: true,
        style: TextStyle(color: _textPrimary, fontSize: 14),
        decoration: InputDecoration(
          hintText: 'Search cached songs or artists...',
          hintStyle: TextStyle(color: _textDark.withValues(alpha: 0.7)),
          prefixIcon: Icon(Icons.search_rounded, color: _primary, size: 20),
          filled: true,
          fillColor: _surfaceColor,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
        ),
        onChanged: (val) {
          setState(() => _searchQuery = val.trim());
        },
      ),
    );
  }

  Widget _buildActionSummaryCard(List<CachedStreamItem> allItems,
      List<CachedStreamItem> displayedItems, bool isDesktop) {
    return Padding(
      padding: const EdgeInsets.only(top: 12.0, bottom: 16.0),
      child: Row(
        children: [
          // Play All Button
          Expanded(
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: _primary,
                foregroundColor: Colors.black,
                padding: EdgeInsets.symmetric(vertical: isDesktop ? 16 : 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              icon: const Icon(Icons.play_arrow_rounded, size: 22),
              label: Text(
                'Play All (${displayedItems.length})',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
              onPressed: () {
                widget.onPlayTracks(displayedItems, initialIndex: 0);
              },
            ),
          ),
          const SizedBox(width: 12),
          // Shuffle Button
          Expanded(
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: _textPrimary,
                side: BorderSide(
                    color: Colors.white.withValues(alpha: 0.15), width: 1),
                padding: EdgeInsets.symmetric(vertical: isDesktop ? 16 : 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              icon: const Icon(Icons.shuffle_rounded, size: 20),
              label: const Text(
                'Shuffle',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
              ),
              onPressed: () {
                final shuffled = List<CachedStreamItem>.from(displayedItems)
                  ..shuffle();
                widget.onPlayTracks(shuffled, initialIndex: 0);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTrackCard(CachedStreamItem track,
      List<CachedStreamItem> allTracks, int index, bool isDesktop) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: _surfaceColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.04)),
      ),
      child: InkWell(
        onTap: () {
          widget.onPlayTracks(allTracks, initialIndex: index);
        },
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 10.0),
          child: Row(
            children: [
              // Artwork / Thumbnail
              Container(
                width: isDesktop ? 56 : 48,
                height: isDesktop ? 56 : 48,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  color: _bgDark,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.25),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: track.thumbnailUrl != null &&
                          track.thumbnailUrl!.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: track.thumbnailUrl!,
                          fit: BoxFit.cover,
                          memCacheWidth: 140,
                          memCacheHeight: 140,
                          errorWidget: (_, __, ___) => const Icon(
                              Icons.podcasts_rounded,
                              color: Colors.tealAccent,
                              size: 24),
                        )
                      : Container(
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              colors: [Color(0xFF00796B), Color(0xFF004D40)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                          ),
                          child: const Icon(Icons.podcasts_rounded,
                              color: Colors.white, size: 24),
                        ),
                ),
              ),
              const SizedBox(width: 14),

              // Title and Subtitles
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      track.title,
                      style: TextStyle(
                        color: _textPrimary,
                        fontSize: isDesktop ? 16 : 14.5,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            track.artist,
                            style: TextStyle(
                              color: _textDark,
                              fontSize: isDesktop ? 13 : 12,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '•',
                          style: TextStyle(color: _textDark, fontSize: 10),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          track.formattedSize,
                          style: TextStyle(
                            color: Colors.tealAccent.withValues(alpha: 0.9),
                            fontSize: isDesktop ? 12 : 11,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        if (track.durationSeconds > 0) ...[
                          const SizedBox(width: 6),
                          Text(
                            '•',
                            style: TextStyle(color: _textDark, fontSize: 10),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            track.formattedDuration,
                            style: TextStyle(
                              color: _textDark,
                              fontSize: isDesktop ? 12 : 11,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),

              // Trailing Options
              IconButton(
                icon: Icon(Icons.more_vert_rounded,
                    color: _textDark, size: isDesktop ? 22 : 20),
                onPressed: () => _showTrackOptions(context, track, isDesktop),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(bool isDesktop) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  colors: [Color(0xFF00796B), Color(0xFF004D40)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF00796B).withValues(alpha: 0.3),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: const Icon(
                Icons.cloud_download_rounded,
                color: Colors.white,
                size: 40,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'No Cached Streams Yet',
              style: TextStyle(
                color: _textPrimary,
                fontSize: isDesktop ? 22 : 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 380),
              child: Text(
                'Tracks streamed from online sources are automatically saved here for quick offline replay. If the OS cleans up temp files, new streams are dynamically added.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: _textDark,
                  fontSize: isDesktop ? 14 : 13,
                  height: 1.4,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
