import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_m3shapes_extended/flutter_m3shapes_extended.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mini_music_visualizer/mini_music_visualizer.dart';
import 'package:sautiflow/sautiflow.dart';

import 'album_detail_screen.dart';
import 'l10n/app_strings.dart';
import 'services/app_theme_service.dart';
import 'widgets/local_album_art.dart';
import 'widgets/music_info_dialog.dart';

enum _QueueItemAction { moveToTop, moveToBottom, trackInfo, remove }

class QueueScreen extends StatefulWidget {
  final List<TrackInfo> queue;
  final String? videoId;
  final Uint8List? albumArt;
  final void Function(int) onPlayQueueIndex;
  final void Function(int, int) onReorderQueue;
  final void Function(int)? onRemoveFromQueue;
  final VoidCallback? onClearQueue;
  final VoidCallback? onShuffleQueue;
  final ValueNotifier<PlayerStatus>? statusNotifier;
  final VoidCallback? onClose;

  const QueueScreen({
    super.key,
    required this.queue,
    this.videoId,
    this.albumArt,
    required this.onPlayQueueIndex,
    required this.onReorderQueue,
    this.onRemoveFromQueue,
    this.onClearQueue,
    this.onShuffleQueue,
    this.statusNotifier,
    this.onClose,
  });

  @override
  State<QueueScreen> createState() => _QueueScreenState();
}

class _QueueScreenState extends State<QueueScreen>
    with AutomaticKeepAliveClientMixin {
  static const double _baseItemExtent = 68.0;
  static const double _compactBreakpoint = 520.0;

  @override
  bool get wantKeepAlive => true;

  late final ScrollController _scrollController;
  int? _lastPlayingIndex;
  bool _hasInitialScrolled = false;
  bool _showUpcomingOnly = false;
  bool _showScrollHelper = false;
  bool _showTopButton = false;
  int _lastTapTimeMs = 0;

  double get _scaledItemExtent {
    if (!mounted) return _baseItemExtent;
    final scale = MediaQuery.textScalerOf(context).scale(1.0).clamp(1.0, 1.5);
    return _baseItemExtent * scale;
  }

  void _handleTrackTap(int actualIndex) {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastTapTimeMs < 300) return;
    _lastTapTimeMs = now;
    widget.onPlayQueueIndex(actualIndex);
  }

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController()..addListener(_onScroll);
    _lastPlayingIndex = _getPlayingIndex(widget.statusNotifier?.value);
    widget.statusNotifier?.addListener(_onStatusChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_hasInitialScrolled) {
        _scrollToPlayingItem(animate: false);
        _hasInitialScrolled = true;
      }
    });
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final playingIndex = _getPlayingIndex(widget.statusNotifier?.value);
    final displayPlayingIndex = _toDisplayIndex(playingIndex);
    final itemExtent = _scaledItemExtent;
    final visibleIndex = (_scrollController.offset / itemExtent).floor();

    final isScrolledAway = displayPlayingIndex >= 0 &&
        (visibleIndex - displayPlayingIndex).abs() > 4;
    final showTop = visibleIndex > 15;

    if (_showScrollHelper != isScrolledAway || _showTopButton != showTop) {
      setState(() {
        _showScrollHelper = isScrolledAway;
        _showTopButton = showTop;
      });
    }
  }

  @override
  void didUpdateWidget(QueueScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.statusNotifier != widget.statusNotifier) {
      oldWidget.statusNotifier?.removeListener(_onStatusChanged);
      widget.statusNotifier?.addListener(_onStatusChanged);
    }
    if (oldWidget.videoId != widget.videoId ||
        oldWidget.queue != widget.queue) {
      final newIndex = _getPlayingIndex(widget.statusNotifier?.value);
      if (_lastPlayingIndex != newIndex) {
        _lastPlayingIndex = newIndex;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _scrollToPlayingItem(animate: true);
        });
      }
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    widget.statusNotifier?.removeListener(_onStatusChanged);
    _scrollController.dispose();
    super.dispose();
  }

  void _onStatusChanged() {
    if (!mounted) return;
    final newIndex = _getPlayingIndex(widget.statusNotifier?.value);
    // Skip rebuilds on playback position ticks unless the active track changed.
    if (_lastPlayingIndex == newIndex) return;

    _lastPlayingIndex = newIndex;
    setState(() {});
    _scrollToPlayingItem(animate: true);
  }

  int _getPlayingIndex(PlayerStatus? status) {
    if (widget.queue.isEmpty) return -1;
    if (status != null &&
        status.currentIndex >= 0 &&
        status.currentIndex < widget.queue.length) {
      return status.currentIndex;
    }
    if (widget.videoId != null) {
      return widget.queue.indexWhere((t) => t.videoId == widget.videoId);
    }
    return -1;
  }

  int _toDisplayIndex(int playingIndex) {
    if (playingIndex < 0) return -1;
    return _showUpcomingOnly ? 0 : playingIndex;
  }

  void _scrollToPlayingItem({bool animate = true}) {
    if (!_scrollController.hasClients || widget.queue.isEmpty) return;

    final displayIndex =
        _toDisplayIndex(_getPlayingIndex(widget.statusNotifier?.value));
    if (displayIndex < 0) return;
    if (!_scrollController.position.hasContentDimensions) return;

    final itemExtent = _scaledItemExtent;
    final viewportHeight = _scrollController.position.viewportDimension;
    final targetOffset = ((displayIndex * itemExtent) -
            (viewportHeight / 2) +
            (itemExtent / 2))
        .clamp(0.0, _scrollController.position.maxScrollExtent);

    if (animate) {
      _scrollController.animateTo(
        targetOffset,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
      );
    } else {
      _scrollController.jumpTo(targetOffset);
    }
  }

  void _confirmClearQueue(BuildContext context) {
    M3EDialog.show<void>(
      context,
      dialog: M3EDialog(
        title: context.strings.clearQueueTitle,
        content: Text(context.strings.clearQueueConfirm),
        actions: [
          M3EButton.text(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(context.strings.cancel),
          ),
          M3EButton(
            onPressed: () {
              Navigator.of(context).pop();
              widget.onClearQueue?.call();
            },
            child: Text(context.strings.clearAll),
          ),
        ],
      ),
    );
  }

  void _showTrackInfo(BuildContext context, TrackInfo track) {
    MusicInfoDialog.show(
      context,
      title: track.title,
      artist: track.artist,
      sourceType: _isLocalTrack(track) ? 'local' : 'online',
      videoId: track.videoId,
      duration: Duration(seconds: track.durationSeconds ?? 0),
    );
  }

  void _toggleUpcomingOnly() {
    setState(() => _showUpcomingOnly = !_showUpcomingOnly);
    WidgetsBinding.instance.addPostFrameCallback((_) => _onScroll());
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final primaryColor = context.primaryColor;
    final bgColor = context.bgDark;
    final textPrimary = context.textPrimary;
    final textDark = context.textMuted;
    final outlineColor = context.outlineColor;

    final playingIndex = _getPlayingIndex(widget.statusNotifier?.value);
    final itemCount = _showUpcomingOnly && playingIndex >= 0
        ? widget.queue.length - playingIndex
        : widget.queue.length;
    final itemExtent = _scaledItemExtent;

    return Scaffold(
      backgroundColor: bgColor,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _QueueHeader(
              trackCount: widget.queue.length,
              bgColor: bgColor,
              textPrimary: textPrimary,
              textDark: textDark,
              outlineColor: outlineColor,
              onClose: widget.onClose,
            ),
            if (widget.queue.isNotEmpty)
              _QueueToolbar(
                showUpcomingOnly: _showUpcomingOnly,
                playingIndex: playingIndex,
                onToggleUpcomingOnly: _toggleUpcomingOnly,
                onScrollToPlaying: () => _scrollToPlayingItem(animate: true),
                onShuffleQueue: widget.onShuffleQueue,
                onClearQueue: widget.onClearQueue != null
                    ? () => _confirmClearQueue(context)
                    : null,
              ),
            Expanded(
              child: widget.queue.isEmpty
                  ? _QueueEmptyState(
                      primaryColor: primaryColor,
                      textPrimary: textPrimary,
                      textDark: textDark,
                    )
                  : LayoutBuilder(
                      builder: (context, constraints) {
                        final isCompact =
                            constraints.maxWidth < _compactBreakpoint;
                        return Stack(
                          children: [
                            Scrollbar(
                              controller: _scrollController,
                              thumbVisibility: true,
                              interactive: true,
                              thickness: 6.0,
                              radius: const Radius.circular(8),
                              child: ListView.builder(
                                controller: _scrollController,
                                itemExtent: itemExtent,
                                addAutomaticKeepAlives: false,
                                addRepaintBoundaries: true,
                                physics: const BouncingScrollPhysics(
                                  parent: AlwaysScrollableScrollPhysics(),
                                ),
                                padding: EdgeInsets.symmetric(
                                  horizontal: isCompact ? 8.0 : 12.0,
                                ).copyWith(bottom: 140),
                                itemCount: itemCount,
                                itemBuilder: (context, index) {
                                  final actualIndex =
                                      _showUpcomingOnly && playingIndex >= 0
                                          ? index + playingIndex
                                          : index;
                                  final track = widget.queue[actualIndex];
                                  final isPlaying =
                                      (playingIndex == actualIndex) ||
                                          (widget.videoId != null &&
                                              track.videoId == widget.videoId);

                                  return _QueueTrackTile(
                                    key: ValueKey(
                                      '${track.videoId}_${actualIndex}_${widget.queue.length}',
                                    ),
                                    track: track,
                                    actualIndex: actualIndex,
                                    queueLength: widget.queue.length,
                                    isPlaying: isPlaying,
                                    isFirst: index == 0,
                                    isLast: index == itemCount - 1,
                                    isCompact: isCompact,
                                    albumArt: widget.albumArt,
                                    primaryColor: primaryColor,
                                    textPrimary: textPrimary,
                                    textDark: textDark,
                                    outlineColor: outlineColor,
                                    onTap: () => _handleTrackTap(actualIndex),
                                    onShowInfo: () =>
                                        _showTrackInfo(context, track),
                                    onMoveToTop: () =>
                                        widget.onReorderQueue(actualIndex, 0),
                                    onMoveToBottom: () => widget.onReorderQueue(
                                      actualIndex,
                                      widget.queue.length,
                                    ),
                                    onRemove: widget.onRemoveFromQueue != null
                                        ? () => widget
                                            .onRemoveFromQueue!(actualIndex)
                                        : null,
                                  );
                                },
                              ),
                            ),
                            if (playingIndex >= 0)
                              _QueueScrollHelper(
                                visible: _showScrollHelper,
                                showTopButton: _showTopButton,
                                playingIndex: playingIndex,
                                primaryColor: primaryColor,
                                onScrollToTop: () {
                                  _scrollController.animateTo(
                                    0,
                                    duration: const Duration(milliseconds: 350),
                                    curve: Curves.easeOutCubic,
                                  );
                                },
                                onScrollToPlaying: () =>
                                    _scrollToPlayingItem(animate: true),
                              ),
                          ],
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QueueHeader extends StatelessWidget {
  final int trackCount;
  final Color bgColor;
  final Color textPrimary;
  final Color textDark;
  final Color outlineColor;
  final VoidCallback? onClose;

  const _QueueHeader({
    required this.trackCount,
    required this.bgColor,
    required this.textPrimary,
    required this.textDark,
    required this.outlineColor,
    this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      decoration: BoxDecoration(
        color: bgColor,
        border: Border(
          bottom: BorderSide(
            color: outlineColor.withValues(alpha: 0.15),
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          if (onClose != null)
            M3EIconButton(
              icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 28),
              variant: M3EIconButtonVariant.standard,
              tooltip: 'Minimize Queue',
              onPressed: onClose,
            )
          else
            const Icon(Icons.queue_music_rounded, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.strings.upNextQueue,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  context.strings.trackCount(trackCount),
                  style: TextStyle(
                    color: textDark,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _QueueToolbar extends StatelessWidget {
  final bool showUpcomingOnly;
  final int playingIndex;
  final VoidCallback onToggleUpcomingOnly;
  final VoidCallback onScrollToPlaying;
  final VoidCallback? onShuffleQueue;
  final VoidCallback? onClearQueue;

  const _QueueToolbar({
    required this.showUpcomingOnly,
    required this.playingIndex,
    required this.onToggleUpcomingOnly,
    required this.onScrollToPlaying,
    this.onShuffleQueue,
    this.onClearQueue,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        child: Row(
          children: [
            M3EChip(
              label: showUpcomingOnly
                  ? context.strings.upcomingOnly
                  : context.strings.showAll,
              leading: Icon(
                showUpcomingOnly
                    ? Icons.filter_list_rounded
                    : Icons.format_list_bulleted_rounded,
                size: 16,
              ),
              selected: showUpcomingOnly,
              onPressed: onToggleUpcomingOnly,
            ),
            if (playingIndex >= 0) ...[
              const SizedBox(width: 8),
              M3EChip(
                label: 'Playing #${playingIndex + 1}',
                leading: const Icon(Icons.my_location_rounded, size: 16),
                onPressed: onScrollToPlaying,
              ),
            ],
            if (onShuffleQueue != null) ...[
              const SizedBox(width: 8),
              M3EChip(
                label: context.strings.shuffle,
                leading: const Icon(Icons.shuffle_rounded, size: 16),
                onPressed: onShuffleQueue,
              ),
            ],
            if (onClearQueue != null) ...[
              const SizedBox(width: 8),
              M3EChip(
                label: context.strings.clearAll,
                leading: const Icon(Icons.clear_all_rounded, size: 16),
                onPressed: onClearQueue,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _QueueEmptyState extends StatelessWidget {
  final Color primaryColor;
  final Color textPrimary;
  final Color textDark;

  const _QueueEmptyState({
    required this.primaryColor,
    required this.textPrimary,
    required this.textDark,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                color: primaryColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: primaryColor.withValues(alpha: 0.3),
                  width: 1.5,
                ),
              ),
              child: Center(
                child: Icon(
                  Icons.queue_music_rounded,
                  color: primaryColor,
                  size: 44,
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              context.strings.queueIsEmpty,
              style: TextStyle(
                color: textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Play a track or album to populate the playback queue',
              style: TextStyle(
                color: textDark,
                fontSize: 13.5,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _QueueTrackTile extends StatelessWidget {
  final TrackInfo track;
  final int actualIndex;
  final int queueLength;
  final bool isPlaying;
  final bool isFirst;
  final bool isLast;
  final bool isCompact;
  final Uint8List? albumArt;
  final Color primaryColor;
  final Color textPrimary;
  final Color textDark;
  final Color outlineColor;
  final VoidCallback onTap;
  final VoidCallback onShowInfo;
  final VoidCallback onMoveToTop;
  final VoidCallback onMoveToBottom;
  final VoidCallback? onRemove;

  const _QueueTrackTile({
    super.key,
    required this.track,
    required this.actualIndex,
    required this.queueLength,
    required this.isPlaying,
    required this.isFirst,
    required this.isLast,
    required this.isCompact,
    this.albumArt,
    required this.primaryColor,
    required this.textPrimary,
    required this.textDark,
    required this.outlineColor,
    required this.onTap,
    required this.onShowInfo,
    required this.onMoveToTop,
    required this.onMoveToBottom,
    this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.only(
      topLeft: Radius.circular(isFirst ? 20 : 6),
      topRight: Radius.circular(isFirst ? 20 : 6),
      bottomLeft: Radius.circular(isLast ? 20 : 6),
      bottomRight: Radius.circular(isLast ? 20 : 6),
    );
    final durationText = _formatDuration(track.durationSeconds);

    return Padding(
      padding: const EdgeInsets.only(bottom: 3.0),
      child: Material(
        color: isPlaying
            ? primaryColor.withValues(alpha: 0.14)
            : context.cardDark,
        shape: RoundedRectangleBorder(
          borderRadius: borderRadius,
          side: BorderSide(
            color: isPlaying
                ? primaryColor.withValues(alpha: 0.45)
                : outlineColor.withValues(alpha: 0.12),
            width: isPlaying ? 1.5 : 1.0,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          onLongPress: onShowInfo,
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: isCompact ? 10 : 14,
              vertical: isCompact ? 8 : 10,
            ),
            child: Row(
              children: [
                ConstrainedBox(
                  constraints: BoxConstraints(minWidth: isCompact ? 20 : 24),
                  child: Text(
                    '${actualIndex + 1}',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: isPlaying ? primaryColor : textDark,
                      fontSize: 12,
                      fontWeight: isPlaying ? FontWeight.bold : FontWeight.w600,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                SizedBox(width: isCompact ? 8 : 10),
                _QueueTrackArtwork(
                  track: track,
                  isPlaying: isPlaying,
                  albumArt: albumArt,
                  primaryColor: primaryColor,
                  outlineColor: outlineColor,
                  size: isCompact ? 42 : 44,
                ),
                SizedBox(width: isCompact ? 10 : 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        track.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: isPlaying ? primaryColor : textPrimary,
                          fontSize: 14,
                          fontWeight:
                              isPlaying ? FontWeight.bold : FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              track.artist,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: textDark,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          if (isCompact && durationText.isNotEmpty) ...[
                            const SizedBox(width: 8),
                            Text(
                              durationText,
                              style: TextStyle(
                                color: textDark.withValues(alpha: 0.75),
                                fontSize: 11.5,
                                fontWeight: FontWeight.w500,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 4),
                if (isCompact)
                  _CompactItemMenu(
                    textDark: textDark,
                    canRemove: onRemove != null,
                    onSelected: (action) {
                      switch (action) {
                        case _QueueItemAction.moveToTop:
                          onMoveToTop();
                        case _QueueItemAction.moveToBottom:
                          onMoveToBottom();
                        case _QueueItemAction.trackInfo:
                          onShowInfo();
                        case _QueueItemAction.remove:
                          onRemove?.call();
                      }
                    },
                  )
                else ...[
                  if (durationText.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(right: 6.0),
                      child: Text(
                        durationText,
                        style: TextStyle(
                          color: textDark.withValues(alpha: 0.75),
                          fontSize: 11.5,
                          fontWeight: FontWeight.w500,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  _QueueActionButton(
                    icon: Icons.vertical_align_top_rounded,
                    tooltip: 'Move to Top',
                    color: textDark,
                    onPressed: onMoveToTop,
                  ),
                  _QueueActionButton(
                    icon: Icons.vertical_align_bottom_rounded,
                    tooltip: 'Move to Bottom',
                    color: textDark,
                    onPressed: onMoveToBottom,
                  ),
                  if (onRemove != null)
                    _QueueActionButton(
                      icon: Icons.close_rounded,
                      tooltip: 'Remove from Queue',
                      color: textDark,
                      onPressed: onRemove!,
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CompactItemMenu extends StatelessWidget {
  final Color textDark;
  final bool canRemove;
  final void Function(_QueueItemAction) onSelected;

  const _CompactItemMenu({
    required this.textDark,
    required this.canRemove,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<_QueueItemAction>(
      tooltip: 'Track actions',
      icon: Icon(Icons.more_vert_rounded, size: 20, color: textDark),
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
      style: const ButtonStyle(
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      onSelected: onSelected,
      itemBuilder: (context) => [
        const PopupMenuItem(
          value: _QueueItemAction.moveToTop,
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.vertical_align_top_rounded, size: 20),
            title: Text('Move to Top'),
          ),
        ),
        const PopupMenuItem(
          value: _QueueItemAction.moveToBottom,
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.vertical_align_bottom_rounded, size: 20),
            title: Text('Move to Bottom'),
          ),
        ),
        const PopupMenuItem(
          value: _QueueItemAction.trackInfo,
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.info_outline_rounded, size: 20),
            title: Text('Track Info'),
          ),
        ),
        if (canRemove)
          const PopupMenuItem(
            value: _QueueItemAction.remove,
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.remove_circle_outline_rounded, size: 20),
              title: Text('Remove from Queue'),
            ),
          ),
      ],
    );
  }
}

class _QueueActionButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final Color color;
  final VoidCallback onPressed;

  const _QueueActionButton({
    required this.icon,
    required this.tooltip,
    required this.color,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(icon, size: 18),
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.all(4),
      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
      style: const ButtonStyle(
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      color: color,
      tooltip: tooltip,
      onPressed: onPressed,
    );
  }
}

class _QueueScrollHelper extends StatelessWidget {
  final bool visible;
  final bool showTopButton;
  final int playingIndex;
  final Color primaryColor;
  final VoidCallback onScrollToTop;
  final VoidCallback onScrollToPlaying;

  const _QueueScrollHelper({
    required this.visible,
    required this.showTopButton,
    required this.playingIndex,
    required this.primaryColor,
    required this.onScrollToTop,
    required this.onScrollToPlaying,
  });

  @override
  Widget build(BuildContext context) {
    final onPrimary = Theme.of(context).colorScheme.onPrimary;
    return Positioned(
      bottom: 70,
      right: 16,
      child: AnimatedSlide(
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
        offset: visible ? Offset.zero : const Offset(0, 1.8),
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeInOut,
          opacity: visible ? 1.0 : 0.0,
          child: IgnorePointer(
            ignoring: !visible,
            child: Material(
              elevation: 6,
              shadowColor: Colors.black.withValues(alpha: 0.45),
              color: primaryColor,
              borderRadius: BorderRadius.circular(24),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (showTopButton) ...[
                    InkWell(
                      borderRadius: const BorderRadius.horizontal(
                        left: Radius.circular(24),
                      ),
                      onTap: onScrollToTop,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(12, 9, 8, 9),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.arrow_upward_rounded,
                              size: 16,
                              color: onPrimary,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Top',
                              style: TextStyle(
                                color: onPrimary,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Container(
                      width: 1,
                      height: 16,
                      color: onPrimary.withValues(alpha: 0.25),
                    ),
                  ],
                  InkWell(
                    borderRadius: BorderRadius.horizontal(
                      left: Radius.circular(showTopButton ? 0 : 24),
                      right: const Radius.circular(24),
                    ),
                    onTap: onScrollToPlaying,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 13,
                        vertical: 9,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.my_location_rounded,
                            size: 16,
                            color: onPrimary,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Playing #${playingIndex + 1}',
                            style: TextStyle(
                              color: onPrimary,
                              fontSize: 12.5,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _QueueTrackArtwork extends StatelessWidget {
  final TrackInfo track;
  final bool isPlaying;
  final Uint8List? albumArt;
  final Color primaryColor;
  final Color outlineColor;
  final double size;

  const _QueueTrackArtwork({
    required this.track,
    required this.isPlaying,
    this.albumArt,
    required this.primaryColor,
    required this.outlineColor,
    this.size = 44,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: context.cardDark,
        borderRadius: BorderRadius.circular(10),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          if (albumArt != null && isPlaying)
            Image.memory(
              albumArt!,
              width: size,
              height: size,
              cacheWidth: 100,
              cacheHeight: 100,
              fit: BoxFit.cover,
            )
          else if (_isLocalTrack(track))
            LocalAlbumArt(
              path: track.videoId,
              size: size,
              shape: Shapes.pill,
              useM3Shape: false,
            )
          else if (track.thumbnailUrl != null &&
              track.thumbnailUrl!.isNotEmpty)
            CachedNetworkImage(
              imageUrl: track.thumbnailUrl!,
              width: size,
              height: size,
              memCacheWidth: 100,
              memCacheHeight: 100,
              fit: BoxFit.cover,
              errorWidget: (_, __, ___) => _fallbackIcon(context),
            )
          else
            _fallbackIcon(context),
          if (isPlaying)
            RepaintBoundary(
              child: Container(
                color: Colors.black.withValues(alpha: 0.45),
                child: Center(
                  child: MiniMusicVisualizer(
                    color: primaryColor,
                    width: 4,
                    height: 15,
                    radius: 2,
                    animate: true,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _fallbackIcon(BuildContext context) {
    return Container(
      color: outlineColor.withValues(alpha: 0.08),
      child: Center(
        child: Icon(
          Icons.music_note_rounded,
          color: context.textMuted.withValues(alpha: 0.6),
          size: 22,
        ),
      ),
    );
  }
}

bool _isLocalTrack(TrackInfo track) {
  final lower = track.videoId.toLowerCase();
  return track.videoId.contains('/') ||
      track.videoId.contains('\\') ||
      lower.endsWith('.mp3') ||
      lower.endsWith('.flac') ||
      lower.endsWith('.m4a') ||
      lower.endsWith('.dsf') ||
      lower.endsWith('.dff');
}

String _formatDuration(int? durationSeconds) {
  if (durationSeconds == null || durationSeconds <= 0) return '';
  final minutes = durationSeconds ~/ 60;
  final seconds = durationSeconds % 60;
  return '$minutes:${seconds.toString().padLeft(2, '0')}';
}
