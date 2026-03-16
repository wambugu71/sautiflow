import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:dart_ytmusic_api/dart_ytmusic_api.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_lyric/flutter_lyric.dart';
import 'package:loading_indicator_m3e/loading_indicator_m3e.dart';
import 'package:sautiflow/sautiflow.dart';

import 'album_detail_screen.dart'; // For TrackInfo
import 'artist_profile_screen.dart'; // NEW
import 'eq_screen.dart';
import 'isolate_player.dart';
import 'models/liked_song.dart';
import 'services/liked_songs_service.dart';

class NowPlayingScreen extends StatefulWidget {
  final ValueNotifier<PlayerStatus> statusNotifier;
  final IsolateAudioPlayer player;
  final String Function(int index) getTitle;
  final String artist;
  final Uint8List? albumArt;
  final String codec; // e.g. 'FLAC'
  final int? durationOverride; // Override duration for online streams
  final String? videoId;
  final VoidCallback onMinimize;
  final List<TrackInfo> queue;
  final void Function(int) onPlayQueueIndex;
  final void Function(int, int) onReorderQueue;
  final String sourceType;
  final Future<void> Function(List<TrackInfo> tracks, {int initialIndex})?
      onPlayTracks;

  const NowPlayingScreen({
    super.key,
    required this.statusNotifier,
    required this.player,
    required this.getTitle,
    required this.artist,
    this.albumArt,
    this.codec = 'MP3',
    this.durationOverride,
    this.videoId,
    required this.onMinimize,
    this.queue = const [],
    required this.onPlayQueueIndex,
    required this.onReorderQueue,
    required this.sourceType,
    this.onPlayTracks,
  });

  @override
  State<NowPlayingScreen> createState() => _NowPlayingScreenState();
}

class _NowPlayingScreenState extends State<NowPlayingScreen> {
  List<double> _analyzerValues = [];
  StreamSubscription? _analyzerSub;

  bool _showLyrics = false;
  String? _lyricsRaw;
  bool _isLoadingLyrics = false;
  final LyricController _lyricController = LyricController();
  final YTMusic _ytMusic = YTMusic();

  String _audioFormat = '...';
  String _sampleRate = '...';
  String _channels = '...';

  @override
  void initState() {
    super.initState();
    _ytMusic.initialize();
    _fetchLyrics();
    _fetchAudioProperties();

    // Ensure analyzer is enabled for visualization
    widget.player.setAnalyzerEnabled(true);

    _analyzerSub = widget.player.analyzerStream.listen((frame) {
      if (frame.isEmpty) return;
      const targetBins = 96;
      final bins = List<double>.filled(targetBins, 0.0);
      final srcLen = frame.length;
      for (var i = 0; i < targetBins; i++) {
        final from = (i * srcLen / targetBins).floor();
        final to = ((i + 1) * srcLen / targetBins).ceil();
        var sum = 0.0;
        var count = 0;
        for (var j = from; j < to && j < srcLen; j++) {
          sum += frame[j].abs();
          count++;
        }
        bins[i] = count > 0 ? sum / count : 0.0;
      }
      if (mounted) setState(() => _analyzerValues = bins);
    });
  }

  @override
  void dispose() {
    _analyzerSub?.cancel();
    super.dispose();
  }

  Future<void> _fetchAudioProperties() async {
    try {
      final props = await widget.player.getAudioProperties();
      if (mounted) {
        setState(() {
          final rawFormat = props['format']?.toString() ?? 'f32';
          _audioFormat = _formatAudioDepth(rawFormat);

          final int rate = props['sampleRate'] as int? ?? 48000;
          _sampleRate = '${rate ~/ 1000}KHZ';

          final int channels = props['channels'] as int? ?? 2;
          _channels = channels == 1 ? 'MONO' : 'STEREO';
        });
      }
    } catch (e) {
      debugPrint('[NowPlaying] Failed to fetch audio properties: $e');
    }
  }

  String _formatAudioDepth(String raw) {
    final lower = raw.toLowerCase();
    if (lower.contains('f32')) return '32 bit float';
    if (lower.contains('s32')) return '32 bit';
    if (lower.contains('s24')) return '24 bit';
    if (lower.contains('s16')) return '16 bit';
    if (lower.contains('u8')) return '8 bit';
    return raw.toUpperCase();
  }

  Future<void> _fetchLyrics() async {
    if (widget.videoId == null) return;
    try {
      if (mounted) setState(() => _isLoadingLyrics = true);
      final raw = await _ytMusic.getLyrics(widget.videoId!);
      if (raw != null && raw.isNotEmpty && mounted) {
        setState(() {
          _lyricsRaw = raw;
        });
        _processLyrics(raw);
      }
    } catch (e) {
      debugPrint('[NowPlaying] Failed to fetch lyrics: $e');
    } finally {
      if (mounted) setState(() => _isLoadingLyrics = false);
    }
  }

  void _processLyrics(String rawLyrics) {
    // Generate a fake LRC using the known duration
    final overrideSecs = widget.durationOverride;
    final baseDurationSecs = (overrideSecs != null && overrideSecs > 0)
        ? overrideSecs.toDouble()
        : widget.statusNotifier.value.durationSeconds;

    final durationMs = (baseDurationSecs * 1000).round();
    final lrcString = _generateFakeLrc(rawLyrics, durationMs);

    // Using flutter_lyric v3 loadLyric
    _lyricController.loadLyric(lrcString);
  }

  String _generateFakeLrc(String text, int totalDurationMs) {
    final lines = text
        .split('\n')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    if (lines.isEmpty || totalDurationMs <= 0) return '';

    // Distribute lines evenly across the duration
    final msPerLine = (totalDurationMs / lines.length).floor();
    final sb = StringBuffer();

    for (int i = 0; i < lines.length; i++) {
      final currentMs = i * msPerLine;
      final dur = Duration(milliseconds: currentMs);
      final mm = dur.inMinutes.remainder(60).toString().padLeft(2, '0');
      final ss = (dur.inSeconds % 60).toString().padLeft(2, '0');
      final xx = ((dur.inMilliseconds % 1000) ~/ 10)
          .toString()
          .padLeft(2, '0'); // hundredths
      sb.writeln('[$mm:$ss.$xx] ${lines[i]}');
    }

    return sb.toString();
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    final h = d.inHours;
    return h > 0 ? '${h.toString().padLeft(2, '0')}:$m:$s' : '$m:$s';
  }

  IconData _loopIcon(LoopMode mode) {
    switch (mode) {
      case LoopMode.off:
        return Icons.repeat;
      case LoopMode.all:
        return Icons.repeat_on;
      case LoopMode.one:
        return Icons.repeat_one_on;
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<PlayerStatus>(
      valueListenable: widget.statusNotifier,
      builder: (context, status, _) {
        final overrideSecs = widget.durationOverride;
        final baseDurationSecs = (overrideSecs != null && overrideSecs > 0)
            ? overrideSecs.toDouble()
            : status.durationSeconds;

        final duration =
            Duration(milliseconds: (baseDurationSecs * 1000).round());
        final position =
            Duration(milliseconds: (status.positionSeconds * 1000).round());
        final maxMs = duration.inMilliseconds <= 0
            ? 1.0
            : duration.inMilliseconds.toDouble();
        final posMs = position.inMilliseconds
            .clamp(
                0, duration.inMilliseconds <= 0 ? 0 : duration.inMilliseconds)
            .toDouble();

        // Sync lyrics
        _lyricController.setProgress(position);

        final title = widget.getTitle(status.currentIndex);
        final subtitle = widget.artist;
        final sourceType = widget.sourceType;

        // Theme colors matching the HTML mockup
        const Color primaryColor = Color(0xFF137FEC);
        const Color bgColor = Color(0xFF101922);
        const Color surfaceColor = Color(0xFF18232E);
        const Color textLight = Colors.white;
        const Color textDark = Color(0xFF94A3B8); // slate-400

        return Theme(
          data: ThemeData.dark().copyWith(
            scaffoldBackgroundColor: bgColor,
            primaryColor: primaryColor,
            colorScheme: const ColorScheme.dark(
              primary: primaryColor,
              surface: surfaceColor,
            ),
          ),
          child: Scaffold(
            body: Stack(
              children: [
                // Background Gradient Blur
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          primaryColor.withOpacity(0.15),
                          bgColor,
                        ],
                      ),
                    ),
                  ),
                ),
                LayoutBuilder(builder: (context, constraints) {
                  final isDesktop = constraints.maxWidth >= 800;

                  final topAppBar = Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16.0, vertical: 8.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.keyboard_arrow_down,
                              size: 32, color: textLight),
                          onPressed: widget.onMinimize,
                        ),
                        Flexible(
                          child: Column(
                            children: [
                              Text(
                                'PLAYING FROM PLAYLIST',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1.5,
                                  color: primaryColor,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              const Text(
                                'Now Playing',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                  color: textLight,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 48),
                      ],
                    ),
                  );

                  final pureAlbumArt = Padding(
                    padding: EdgeInsets.all(isDesktop ? 32.0 : 0.0),
                    child: Center(
                      child: AspectRatio(
                        aspectRatio: 1.0,
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius:
                                BorderRadius.circular(isDesktop ? 16.0 : 8.0),
                            color: surfaceColor,
                            boxShadow: [
                              BoxShadow(
                                color: primaryColor.withOpacity(0.3),
                                blurRadius: 40,
                                spreadRadius: 2,
                                offset: const Offset(0, 10),
                              ),
                            ],
                            image: widget.albumArt != null
                                ? DecorationImage(
                                    image: MemoryImage(widget.albumArt!),
                                    fit: BoxFit.cover,
                                  )
                                : null,
                          ),
                        ),
                      ),
                    ),
                  );

                  final pureLyrics = _isLoadingLyrics
                      ? Center(
                          child: LoadingIndicatorM3E(
                              color: primaryColor,
                              containerColor: primaryColor.withAlpha(50)))
                      : _lyricsRaw == null
                          ? Center(
                              child: Text(
                                'No lyrics available',
                                style: TextStyle(color: textDark, fontSize: 16),
                              ),
                            )
                          : LyricView(
                              controller: _lyricController,
                            );

                  final metadataWidget = Padding(
                    padding: EdgeInsets.symmetric(
                        horizontal: isDesktop ? 0.0 : 32.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                title,
                                style: const TextStyle(
                                  fontSize: 28,
                                  fontWeight: FontWeight.bold,
                                  color: textLight,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 4),
                              InkWell(
                                onTap: subtitle.isNotEmpty &&
                                        title.isNotEmpty &&
                                        !title.contains("content://") &&
                                        sourceType != 'local'
                                    ? () {
                                        Navigator.of(context).push(
                                          MaterialPageRoute(
                                            builder: (_) => ArtistProfileScreen(
                                              artistName: subtitle,
                                              onPlayTracks: widget.onPlayTracks,
                                            ),
                                          ),
                                        );
                                      }
                                    : null,
                                borderRadius: BorderRadius.circular(4),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 2.0, horizontal: 4.0),
                                  child: Text(
                                    subtitle,
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w500,
                                      color: textDark,
                                      decoration: sourceType != 'local'
                                          ? TextDecoration.underline
                                          : TextDecoration.none,
                                      decorationColor:
                                          textDark.withValues(alpha: 0.5),
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        ValueListenableBuilder<List<LikedSong>>(
                          valueListenable:
                              LikedSongsService.instance.likedSongsNotifier,
                          builder: (context, likedSongs, _) {
                            final trackId = widget.videoId ??
                                widget.getTitle(status.currentIndex);
                            final isCurrentlyLiked =
                                likedSongs.any((s) => s.videoId == trackId);
                            return IconButton(
                              icon: Icon(
                                  isCurrentlyLiked
                                      ? Icons.favorite
                                      : Icons.favorite_border,
                                  size: 28,
                                  color: primaryColor),
                              onPressed: () async {
                                if (trackId.isEmpty) return;
                                if (isCurrentlyLiked) {
                                  await LikedSongsService.instance
                                      .removeLikedSong(trackId);
                                } else {
                                  await LikedSongsService.instance
                                      .addLikedSong(LikedSong(
                                    videoId: trackId,
                                    title: title,
                                    artist: subtitle,
                                    thumbnailUrl: widget.albumArt == null
                                        ? null
                                        : trackId,
                                    durationSeconds: duration.inSeconds,
                                    likedAt: DateTime.now(),
                                  ));
                                }
                              },
                            );
                          },
                        ),
                      ],
                    ),
                  );

                  final visualizerWidget = _analyzerValues.isNotEmpty
                      ? Padding(
                          padding: EdgeInsets.symmetric(
                              horizontal: isDesktop ? 0.0 : 24.0,
                              vertical: 24.0),
                          child: SizedBox(
                            height: 60,
                            child:
                                _buildVisualizer(primaryColor, _analyzerValues),
                          ),
                        )
                      : const SizedBox(height: 108);

                  final progressBarWidget = Padding(
                    padding: EdgeInsets.symmetric(
                        horizontal: isDesktop ? 0.0 : 24.0),
                    child: Column(
                      children: [
                        SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            trackHeight: 4.0,
                            activeTrackColor: primaryColor,
                            inactiveTrackColor: Colors.white24,
                            thumbColor: Colors.white,
                            overlayColor: primaryColor.withOpacity(0.2),
                            thumbShape: const RoundSliderThumbShape(
                                enabledThumbRadius: 6.0),
                            overlayShape: const RoundSliderOverlayShape(
                                overlayRadius: 14.0),
                          ),
                          child: Slider(
                            value: posMs,
                            min: 0.0,
                            max: maxMs,
                            onChanged: (v) {
                              widget.player
                                  .seekTo(Duration(milliseconds: v.toInt()));
                            },
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8.0),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(_fmt(position),
                                  style: const TextStyle(
                                      fontSize: 12,
                                      color: textDark,
                                      fontFamily: 'monospace')),
                              Text(_fmt(duration),
                                  style: const TextStyle(
                                      fontSize: 12,
                                      color: textDark,
                                      fontFamily: 'monospace')),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );

                  final playbackControlsWidget = Padding(
                    padding: EdgeInsets.symmetric(
                        horizontal: isDesktop ? 0.0 : 24.0, vertical: 16.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        IconButton(
                          icon: Icon(
                              status.shuffleEnabled
                                  ? Icons.shuffle_on
                                  : Icons.shuffle,
                              color: status.shuffleEnabled
                                  ? primaryColor
                                  : textDark),
                          onPressed: () {
                            widget.player
                                .setShuffleModeEnabled(!status.shuffleEnabled);
                          },
                        ),
                        IconButton(
                          icon: const Icon(Icons.skip_previous,
                              size: 36, color: textLight),
                          onPressed: widget.player.seekToPrevious,
                        ),
                        GestureDetector(
                          onTap: status.isPlaying
                              ? widget.player.pause
                              : widget.player.play,
                          child: Container(
                            width: 72,
                            height: 72,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: primaryColor,
                              boxShadow: [
                                BoxShadow(
                                  color: primaryColor.withOpacity(0.4),
                                  blurRadius: 20,
                                  spreadRadius: 2,
                                  offset: const Offset(0, 8),
                                ),
                              ],
                            ),
                            child: Icon(
                              status.isPlaying ? Icons.pause : Icons.play_arrow,
                              size: 40,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.skip_next,
                              size: 36, color: textLight),
                          onPressed: widget.player.seekToNext,
                        ),
                        PopupMenuButton<LoopMode>(
                          initialValue: status.loopMode,
                          icon: Icon(_loopIcon(status.loopMode),
                              color: status.loopMode != LoopMode.off
                                  ? primaryColor
                                  : textDark),
                          onSelected: widget.player.setLoopMode,
                          itemBuilder: (_) => const [
                            PopupMenuItem(
                                value: LoopMode.off, child: Text('Loop Off')),
                            PopupMenuItem(
                                value: LoopMode.all, child: Text('Loop All')),
                            PopupMenuItem(
                                value: LoopMode.one, child: Text('Loop One')),
                          ],
                        ),
                      ],
                    ),
                  );

                  final extraControlsWidget = Padding(
                    padding: EdgeInsets.symmetric(
                        horizontal: isDesktop ? 0.0 : 48.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.tune,
                              color: textLight, size: 26),
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => EqScreen(
                                  player: widget.player,
                                  analyzerEnabled: true,
                                  analyzerType: 'bar',
                                ),
                              ),
                            );
                          },
                        ),
                        IconButton(
                          icon: Icon(
                            _showLyrics
                                ? Icons.music_note
                                : Icons.lyrics_outlined,
                            color: _showLyrics ? primaryColor : textLight,
                            size: 26,
                          ),
                          onPressed: () {
                            setState(() {
                              _showLyrics = !_showLyrics;
                            });
                          },
                        ),
                        IconButton(
                          icon: const Icon(Icons.queue_music_outlined,
                              color: textLight, size: 26),
                          onPressed: () => _showQueueSheet(context),
                        ),
                      ],
                    ),
                  );

                  final audioInfoWidget = Container(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      border: Border(
                        top: BorderSide(
                          color: Colors.white.withValues(alpha: 0.05),
                        ),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.graphic_eq,
                                size: 14,
                                color: textDark.withValues(alpha: 0.6)),
                            const SizedBox(width: 4),
                            Text('$_audioFormat   / $_sampleRate',
                                style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 1.2,
                                    color: textDark.withValues(alpha: 0.6))),
                          ],
                        ),
                        Container(
                          width: 1,
                          height: 12,
                          margin: const EdgeInsets.symmetric(horizontal: 12),
                          color: Colors.white.withValues(alpha: 0.1),
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.speaker_group,
                                size: 14,
                                color: textDark.withValues(alpha: 0.6)),
                            const SizedBox(width: 4),
                            Text(_channels,
                                style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 1.2,
                                    color: textDark.withValues(alpha: 0.6))),
                          ],
                        ),
                        Container(
                          width: 1,
                          height: 12,
                          margin: const EdgeInsets.symmetric(horizontal: 12),
                          color: Colors.white.withValues(alpha: 0.1),
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.code,
                                size: 14,
                                color: textDark.withValues(alpha: 0.6)),
                            const SizedBox(width: 4),
                            Text(widget.codec,
                                style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 1.2,
                                    color: textDark.withValues(alpha: 0.6))),
                          ],
                        ),
                      ],
                    ),
                  );

                  Widget content;
                  if (isDesktop) {
                    content = Column(
                      children: [
                        topAppBar,
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 64.0, vertical: 24.0),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                // Left Column (Album Art, Visualizer, Progress, Info)
                                Expanded(
                                  flex: 10,
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Expanded(flex: 8, child: pureAlbumArt),
                                      const SizedBox(height: 24),
                                      visualizerWidget,
                                      progressBarWidget,
                                      const SizedBox(height: 16),
                                      audioInfoWidget,
                                      const Spacer(),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 64),
                                // Right Column (Lyrics/Spacer, Metadata, Controls)
                                Expanded(
                                  flex: 11,
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      if (_showLyrics)
                                        Expanded(child: pureLyrics)
                                      else
                                        const Spacer(),
                                      metadataWidget,
                                      const SizedBox(height: 32),
                                      playbackControlsWidget,
                                      const SizedBox(height: 16),
                                      extraControlsWidget,
                                      if (!_showLyrics) const Spacer(),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    );
                  } else {
                    content = Column(
                      children: [
                        const SizedBox(height: 24),
                        topAppBar,
                        Expanded(
                          child: _showLyrics
                              ? Padding(
                                  padding: const EdgeInsets.symmetric(),
                                  child: pureLyrics)
                              : Padding(
                                  padding: const EdgeInsets.symmetric(),
                                  child: pureAlbumArt),
                        ),
                        metadataWidget,
                        visualizerWidget,
                        progressBarWidget,
                        const SizedBox(height: 16),
                        playbackControlsWidget,
                        extraControlsWidget,
                        const SizedBox(height: 16),
                        audioInfoWidget,
                      ],
                    );
                  }

                  return Align(
                    alignment: Alignment.topCenter,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                          maxWidth: isDesktop ? double.infinity : 600.0),
                      child: SafeArea(
                        child: content,
                      ),
                    ),
                  );
                }),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildVisualizer(
      Color primaryColor, List<double> currentAnalyzerValues) {
    // Determine how many bars we want based on what fits nicely
    const int numBars = 50;

    // Smooth and resample the analyzer values for the UI
    final visualData = <double>[];
    if (currentAnalyzerValues.isEmpty) {
      for (int i = 0; i < numBars; i++) {
        visualData.add(0.0);
      }
    } else {
      // Very simple downsample
      final step = math.max(1, currentAnalyzerValues.length / numBars);
      for (int i = 0; i < numBars; i++) {
        final index =
            (i * step).floor().clamp(0, currentAnalyzerValues.length - 1);
        final val = (currentAnalyzerValues[index] * 8.0).clamp(0.0, 1.0);
        visualData.add(val);
      }
    }

    final barGroups = List.generate(numBars, (i) {
      return BarChartGroupData(
        x: i,
        barRods: [
          BarChartRodData(
            toY:
                math.max(0.05, visualData[i]), // Minimum height to show the bar
            color: primaryColor.withOpacity(0.7 + (visualData[i] * 0.3)),
            width: 4,
            borderRadius: BorderRadius.circular(2),
          ),
        ],
      );
    });

    return BarChart(
      BarChartData(
        barTouchData: BarTouchData(enabled: false),
        alignment: BarChartAlignment.spaceBetween,
        maxY: 1.0,
        minY: 0,
        barGroups: barGroups,
        titlesData: const FlTitlesData(show: false),
        borderData: FlBorderData(show: false),
        gridData: const FlGridData(show: false),
      ),
    );
  }

  void _showQueueSheet(BuildContext context) {
    const Color primaryColor = Color(0xFF137FEC);
    const Color sheetBg = Color(0xFF1C252E);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.65,
          minChildSize: 0.3,
          maxChildSize: 0.9,
          builder: (_, scrollController) {
            return Container(
              decoration: const BoxDecoration(
                color: sheetBg,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Column(
                children: [
                  // Drag handle
                  Padding(
                    padding: const EdgeInsets.only(top: 12, bottom: 8),
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  // Header
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Up Next',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          '${widget.queue.length} tracks',
                          style: const TextStyle(
                            color: Colors.white38,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Divider(color: Colors.white10, height: 1),
                  // Queue list
                  Expanded(
                    child: widget.queue.isEmpty
                        ? const Center(
                            child: Text(
                              'Queue is empty',
                              style: TextStyle(
                                  color: Colors.white54, fontSize: 16),
                            ),
                          )
                        : Theme(
                            data: Theme.of(context).copyWith(
                              canvasColor: Colors.transparent,
                            ),
                            child: ReorderableListView.builder(
                              scrollController: scrollController,
                              itemCount: widget.queue.length,
                              onReorder: widget.onReorderQueue,
                              itemBuilder: (context, index) {
                                final track = widget.queue[index];
                                final currentVideoId = widget.videoId;
                                final isPlaying = currentVideoId != null &&
                                    track.videoId == currentVideoId;

                                return Card(
                                  key: ValueKey(
                                      track.videoId + index.toString()),
                                  color: isPlaying
                                      ? primaryColor.withValues(alpha: 0.15)
                                      : Colors.white.withValues(alpha: 0.04),
                                  elevation: 0,
                                  margin: const EdgeInsets.symmetric(
                                      vertical: 3, horizontal: 12),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12)),
                                  child: ListTile(
                                    contentPadding: const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 4),
                                    leading: ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: SizedBox(
                                        width: 48,
                                        height: 48,
                                        child: track.thumbnailUrl != null
                                            ? Image.network(
                                                track.thumbnailUrl!,
                                                fit: BoxFit.cover,
                                                errorBuilder: (_, __, ___) =>
                                                    const Icon(Icons.music_note,
                                                        color: Colors.white54),
                                              )
                                            : const Icon(Icons.music_note,
                                                color: Colors.white54),
                                      ),
                                    ),
                                    title: Text(
                                      track.title,
                                      style: TextStyle(
                                        color: isPlaying
                                            ? primaryColor
                                            : Colors.white
                                                .withValues(alpha: 0.9),
                                        fontWeight: isPlaying
                                            ? FontWeight.bold
                                            : FontWeight.w500,
                                        fontSize: 14,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    subtitle: Text(
                                      track.artist,
                                      style: TextStyle(
                                        color:
                                            Colors.white.withValues(alpha: 0.5),
                                        fontSize: 12,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    trailing: ReorderableDragStartListener(
                                      index: index,
                                      child: const Icon(Icons.drag_handle,
                                          color: Colors.white54),
                                    ),
                                    onTap: () {
                                      widget.onPlayQueueIndex(index);
                                      Navigator.of(sheetCtx).pop();
                                    },
                                  ),
                                );
                              },
                            ),
                          ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
