import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:loading_indicator_m3e/loading_indicator_m3e.dart';

import 'package:dart_ytmusic_api/dart_ytmusic_api.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_lyric/flutter_lyric.dart';
import 'package:sautiflow/sautiflow.dart';

import 'album_detail_screen.dart'; // For TrackInfo
import 'artist_profile_screen.dart'; // NEW
import 'effects_screen.dart';
import 'isolate_player.dart';
import 'models/liked_song.dart';
import 'queue_screen.dart'; // NEW
import 'services/fft_processor.dart';
import 'services/liked_songs_service.dart';
import 'widgets/adaptive_marquee_text.dart';

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
  final bool analyzerEnabled;
  final ValueChanged<bool> onAnalyzerEnabledChanged;
  final String analyzerType;
  final bool analyzerAutoFit;
  final bool analyzerShowGrids;
  final int outputSampleRate;
  final VoidCallback? onNavigateToHistory;

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
    required this.analyzerEnabled,
    required this.onAnalyzerEnabledChanged,
    required this.analyzerType,
    required this.analyzerAutoFit,
    required this.analyzerShowGrids,
    required this.outputSampleRate,
    this.onNavigateToHistory,
  });

  @override
  State<NowPlayingScreen> createState() => _NowPlayingScreenState();
}

class _NowPlayingScreenState extends State<NowPlayingScreen> {
  late bool _isAnalyzerEnabled;

  List<double> _analyzerValues = [];
  StreamSubscription? _analyzerSub;
  FftProcessor? _fftProcessor;

  bool _showLyrics = false;
  String? _lyricsRaw;
  bool _isLoadingLyrics = false;
  final LyricController _lyricController = LyricController();
  final YTMusic _ytMusic = YTMusic();

  int _fileSizeBytes = 0;
  String _originalBitDepth = '';
  String _sampleRate = '...';
  String _channels = '...';

  // ── Seek-state machine ────────────────────────────────────────────────────
  //
  // Phase 1 – DRAGGING: finger is on the slider.
  //   _isDragging = true, _dragPositionMs = finger position.
  //   → Slider shows _dragPositionMs. Zero seeks are fired.
  //
  // Phase 2 – SEEKING: finger lifted, seek command sent, waiting for engine.
  //   _isDragging = false, _pendingSeekMs = target.
  //   → Slider shows _pendingSeekMs so it doesn't bounce back.
  //   → _onStatusChanged watches statusNotifier; clears _pendingSeekMs once
  //     the engine's reported position lands within ~4 s of the target.
  //
  // Phase 3 – IDLE: engine confirmed position, or safety timeout fired.
  //   _pendingSeekMs = null → Slider follows the engine normally.
  bool _isDragging = false;
  double _dragPositionMs = 0.0;
  double? _pendingSeekMs; // non-null while seek is in-flight
  Timer? _seekTimeoutTimer;

  @override
  void initState() {
    super.initState();
    _isAnalyzerEnabled = widget.analyzerEnabled;
    _ytMusic.initialize();
    _fetchLyrics();
    _fetchAudioProperties();

    _setupAnalyzer(_isAnalyzerEnabled);

    // Watch engine status to detect when a pending seek has landed.
    widget.statusNotifier.addListener(_onStatusChanged);
  }

  /// Called on every engine status poll (~200 ms).  Once the engine's reported
  /// position is within 4 seconds of the seek target we consider the seek
  /// landed and release the position override.
  void _onStatusChanged() {
    final target = _pendingSeekMs;
    if (target == null) return;
    final enginePosMs = widget.statusNotifier.value.positionSeconds * 1000.0;
    if ((enginePosMs - target).abs() < 4000) {
      _seekTimeoutTimer?.cancel();
      if (mounted) setState(() => _pendingSeekMs = null);
    }
  }

  @override
  void didUpdateWidget(covariant NowPlayingScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.analyzerEnabled != widget.analyzerEnabled) {
      _isAnalyzerEnabled = widget.analyzerEnabled;
      _setupAnalyzer(_isAnalyzerEnabled);
    }
    if (oldWidget.videoId != widget.videoId || oldWidget.sourceType != widget.sourceType) {
      _fetchAudioProperties();
      _fetchLyrics();
    }
  }

  @override
  void dispose() {
    widget.statusNotifier.removeListener(_onStatusChanged);
    _seekTimeoutTimer?.cancel();
    _analyzerSub?.cancel();
    super.dispose();
  }

  void _setupAnalyzer(bool enabled) {
    if (enabled) {
      final sr = widget.outputSampleRate > 0 ? widget.outputSampleRate : 48000;
      _fftProcessor ??= FftProcessor(sampleRate: sr);
      widget.player.setAnalyzerEnabled(true);
      _analyzerSub ??= widget.player.analyzerStream.listen((frame) {
        if (frame.isEmpty) return;
        final bins = _fftProcessor!.processFrame(frame, targetBins: 96);
        if (mounted) setState(() => _analyzerValues = bins);
      });
    } else {
      widget.player.setAnalyzerEnabled(false);
      _analyzerSub?.cancel();
      _analyzerSub = null;
      _fftProcessor?.reset();
      if (mounted) setState(() => _analyzerValues = []);
    }
  }

  Future<String?> _getOriginalBitDepth(String path) async {
    try {
      final ext = path.split('.').last.toLowerCase();
      if (ext == 'mp3' || ext == 'm4a' || ext == 'aac' || ext == 'ogg') {
        return '16 bit';
      }
      
      final file = File(path);
      if (!file.existsSync()) return null;

      final raf = file.openSync();
      try {
        if (ext == 'flac') {
          final header = raf.readSync(4);
          if (String.fromCharCodes(header) == 'fLaC') {
            final blockHeader = raf.readSync(4);
            final blockType = blockHeader[0] & 0x7F;
            final blockLength = (blockHeader[1] << 16) | (blockHeader[2] << 8) | blockHeader[3];
            if (blockType == 0 && blockLength == 34) {
              final streamInfo = raf.readSync(34);
              final b12 = streamInfo[12];
              final b13 = streamInfo[13];
              final bitsPerSample = (((b12 & 0x01) << 4) | ((b13 & 0xF0) >> 4)) + 1;
              return '$bitsPerSample bit';
            }
          }
        } else if (ext == 'wav') {
          raf.setPositionSync(34);
          final bits = raf.readSync(2);
          final bitsPerSample = bits[0] | (bits[1] << 8);
          return '$bitsPerSample bit';
        }
      } finally {
        raf.closeSync();
      }
    } catch (_) {}
    return null;
  }

  Future<void> _fetchAudioProperties() async {
    _fileSizeBytes = 0;
    _originalBitDepth = '';
    
    try {
      final props = await widget.player.getAudioProperties();
      
      if (widget.sourceType == 'local' && widget.videoId != null) {
        try {
          final file = File(widget.videoId!);
          if (file.existsSync()) {
            _fileSizeBytes = file.lengthSync();
          }
          final depth = await _getOriginalBitDepth(widget.videoId!);
          if (mounted && depth != null) {
            setState(() {
              _originalBitDepth = depth;
            });
          }
        } catch (_) {}
      } else {
        // Fallback for streams where file size is unavailable
        if (mounted) setState(() { _originalBitDepth = '16 bit'; });
      }

      if (mounted) {
        setState(() {
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

        final trackTotal = widget.queue.isNotEmpty ? widget.queue.length : 0;
        final trackIdx = status.currentIndex >= 0 ? status.currentIndex + 1 : 1;
        final trackPosition = trackTotal > 0 ? '$trackIdx/$trackTotal' : '';

        final duration =
            Duration(milliseconds: (baseDurationSecs * 1000).round());
        final maxMs = duration.inMilliseconds <= 0
            ? 1.0
            : duration.inMilliseconds.toDouble();
        // Raw engine position in milliseconds (used as fallback when idle).
        final posMs = status.positionSeconds * 1000.0;

        // Composite display position:
        //   • While dragging          → finger position (_dragPositionMs)
        //   • While seek in-flight    → frozen at seek target (_pendingSeekMs)
        //   • Otherwise               → engine-reported position (posMs)
        final displayPosMs = _isDragging
            ? _dragPositionMs.clamp(0.0, maxMs)
            : (_pendingSeekMs?.clamp(0.0, maxMs) ?? posMs.clamp(0.0, maxMs));

        // Sync lyrics to the display position so they follow the seek
        // preview, not the (stale) engine position during a pending seek.
        _lyricController
            .setProgress(Duration(milliseconds: displayPosMs.toInt()));

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


                  Widget content;
                  if (isDesktop) {
                    content = Column(
                      children: [
                        const SizedBox(height: 24),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 64.0, vertical: 24.0),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                // Left Column (Album Art with Overlay)
                                Expanded(
                                  flex: 10,
                                  child: Center(
                                    child: AspectRatio(
                                      aspectRatio: 1.0,
                                      child: Stack(
                                        children: [
                                          // Album Art Image
                                          Positioned.fill(
                                            child: Container(
                                              decoration: BoxDecoration(
                                                borderRadius: BorderRadius.circular(32.0),
                                                color: surfaceColor,
                                                boxShadow: [
                                                  BoxShadow(
                                                    color: Colors.black.withValues(alpha: 0.5),
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
                                          // Gradient Overlay at the bottom
                                          Positioned(
                                            bottom: 0,
                                            left: 0,
                                            right: 0,
                                            height: 160,
                                            child: Container(
                                              decoration: BoxDecoration(
                                                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(32.0)),
                                                gradient: LinearGradient(
                                                  begin: Alignment.topCenter,
                                                  end: Alignment.bottomCenter,
                                                  colors: [
                                                    Colors.transparent,
                                                    Colors.black.withValues(alpha: 0.9),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ),
                                          // Text (Title, Artist)
                                          Positioned(
                                            left: 32,
                                            bottom: 80,
                                            right: 32,
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                AdaptiveMarqueeText(
                                         text: title,
                                         style: const TextStyle(
                                           fontSize: 36,
                                           fontWeight: FontWeight.bold,
                                           color: textLight,
                                         ),
                                         blankSpace: 40.0,
                                         velocity: 30.0,
                                       ),
                                                const SizedBox(height: 8),
                                                Text(
                                                  subtitle,
                                                  style: const TextStyle(
                                                    fontSize: 20,
                                                    fontWeight: FontWeight.w600,
                                                    color: Colors.white70,
                                                  ),
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ],
                                            ),
                                          ),
                                          // Buttons at the bottom edge
                                          Positioned(
                                            bottom: 24,
                                            left: 32,
                                            right: 32,
                                            child: Row(
                                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                              children: [
                                                Row(
                                                  children: [
                                                    // Like
                                                    ValueListenableBuilder<List<LikedSong>>(
                                                      valueListenable: LikedSongsService.instance.likedSongsNotifier,
                                                      builder: (context, likedSongs, _) {
                                                        final trackId = widget.videoId ?? widget.getTitle(status.currentIndex);
                                                        final isCurrentlyLiked = likedSongs.any((s) => s.videoId == trackId);
                                                        return GestureDetector(
                                                          onTap: () async {
                                                            if (trackId.isEmpty) return;
                                                            if (isCurrentlyLiked) {
                                                              await LikedSongsService.instance.removeLikedSong(trackId);
                                                            } else {
                                                              await LikedSongsService.instance.addLikedSong(LikedSong(
                                                                videoId: trackId,
                                                                title: title,
                                                                artist: subtitle,
                                                                thumbnailUrl: widget.albumArt == null ? null : trackId,
                                                                durationSeconds: duration.inSeconds,
                                                                likedAt: DateTime.now(),
                                                              ));
                                                            }
                                                          },
                                                          child: CircleAvatar(
                                                            backgroundColor: isCurrentlyLiked ? primaryColor : Colors.white.withValues(alpha: 0.2),
                                                            radius: 24,
                                                            child: Icon(isCurrentlyLiked ? Icons.thumb_up : Icons.thumb_up_outlined, color: Colors.white, size: 24),
                                                          ),
                                                        );
                                                      },
                                                    ),
                                                    const SizedBox(width: 16),
                                                    // Dislike
                                                    CircleAvatar(
                                                      backgroundColor: Colors.white.withValues(alpha: 0.2),
                                                      radius: 24,
                                                      child: const Icon(Icons.thumb_down_outlined, color: Colors.white, size: 24),
                                                    ),
                                                  ],
                                                ),
                                                Row(
                                                  children: [
                                                    // Queue/Playlist
                                                    GestureDetector(
                                                      onTap: () => _showQueueSheet(context),
                                                      child: CircleAvatar(
                                                        backgroundColor: Colors.white.withValues(alpha: 0.2),
                                                        radius: 24,
                                                        child: const Icon(Icons.playlist_play, color: Colors.white, size: 24),
                                                      ),
                                                    ),
                                                    const SizedBox(width: 16),
                                                    // More options
                                                    const Icon(Icons.more_vert, color: Colors.white, size: 32),
                                                  ],
                                                ),
                                              ],
                                            ),
                                          ),
                                          // Minimize icon at top left
                                          Positioned(
                                            top: 24,
                                            left: 24,
                                            child: IconButton(
                                              icon: const Icon(Icons.keyboard_arrow_down, size: 40, color: textLight),
                                              onPressed: widget.onMinimize,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 64),
                                // Right Column (Lyrics/Spacer, Controls)
                                Expanded(
                                  flex: 11,
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      if (_showLyrics)
                                        Expanded(child: pureLyrics)
                                      else
                                        const Spacer(),
                                        
                                      // Action Buttons Row
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                        children: [
                                          _buildActionIcon(Icons.graphic_eq, () {
                                            Navigator.push(context, MaterialPageRoute(builder: (context) => EffectsScreen(
                                  player: widget.player,
                                  analyzerEnabled: _isAnalyzerEnabled,
                                  analyzerType: widget.analyzerType,
                                  analyzerAutoFit: widget.analyzerAutoFit,
                                  analyzerShowGrids: widget.analyzerShowGrids,
                                  outputSampleRate: widget.outputSampleRate,
                                )));
                                          }),
                                          _buildActionIcon(Icons.access_time, () {}),
                                          _buildActionIcon(_loopIcon(status.loopMode), () {
                                            final currentMode = status.loopMode;
                                            final nextMode = currentMode == LoopMode.off ? LoopMode.all : (currentMode == LoopMode.all ? LoopMode.one : LoopMode.off);
                                            widget.player.setLoopMode(nextMode);
                                          }),
                                          _buildActionIcon(status.shuffleEnabled ? Icons.shuffle_on : Icons.shuffle, () { widget.player.setShuffleModeEnabled(!status.shuffleEnabled); }),
                                        ],
                                      ),
                                      const SizedBox(height: 48),
                                      
                                      // Playback Controls
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          IconButton(
                                            icon: const Icon(Icons.fast_rewind, size: 36, color: Colors.white54),
                                            onPressed: () { widget.player.seekTo(Duration(milliseconds: (displayPosMs - 10000).toInt().clamp(0, maxMs.toInt()))); },
                                          ),
                                          const SizedBox(width: 16),
                                          IconButton(
                                            icon: const Icon(Icons.skip_previous, size: 48, color: Colors.white),
                                            onPressed: widget.player.seekToPrevious,
                                          ),
                                          const SizedBox(width: 24),
                                          GestureDetector(
                                            onTap: status.isPlaying ? widget.player.pause : widget.player.play,
                                            child: Container(
                                              width: 96,
                                              height: 96,
                                              decoration: const BoxDecoration(
                                                shape: BoxShape.circle,
                                                color: Colors.black,
                                              ),
                                              child: Icon(
                                                status.isPlaying ? Icons.pause : Icons.play_arrow,
                                                size: 56,
                                                color: Colors.white,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 24),
                                          IconButton(
                                            icon: const Icon(Icons.skip_next, size: 48, color: Colors.white),
                                            onPressed: widget.player.seekToNext,
                                          ),
                                          const SizedBox(width: 16),
                                          IconButton(
                                            icon: const Icon(Icons.fast_forward, size: 36, color: Colors.white54),
                                            onPressed: () { widget.player.seekTo(Duration(milliseconds: (displayPosMs + 10000).toInt().clamp(0, maxMs.toInt()))); },
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 40),
                                      
                                      // Progress Bar & Info Badge
                                      Column(
                                        children: [
                                          SliderTheme(
                                            data: SliderTheme.of(context).copyWith(
                                              trackHeight: 6.0,
                                              activeTrackColor: Colors.white54,
                                              inactiveTrackColor: Colors.white12,
                                              thumbColor: Colors.white,
                                              overlayColor: Colors.white24,
                                              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8.0),
                                              overlayShape: const RoundSliderOverlayShape(overlayRadius: 16.0),
                                            ),
                                            child: Slider(
                                              value: displayPosMs,
                                              min: 0.0,
                                              max: maxMs,
                                              onChangeStart: (v) { setState(() { _isDragging = true; _dragPositionMs = v; }); },
                                              onChanged: (v) { setState(() => _dragPositionMs = v); },
                                              onChangeEnd: (v) {
                                                _seekTimeoutTimer?.cancel();
                                                setState(() { _isDragging = false; _pendingSeekMs = v; });
                                                widget.player.seekTo(Duration(milliseconds: v.toInt()));
                                                _seekTimeoutTimer = Timer(const Duration(seconds: 45), () { if (mounted) setState(() => _pendingSeekMs = null); });
                                              },
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                          Row(
                                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                            children: [
                                              Text(
                                                _fmt(Duration(milliseconds: displayPosMs.toInt())),
                                                style: const TextStyle(fontSize: 16, color: Colors.white, fontWeight: FontWeight.bold),
                                              ),
                                              // Audio Info Badge
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                                                decoration: BoxDecoration(
                                                  color: Colors.white.withValues(alpha: 0.1),
                                                  borderRadius: BorderRadius.circular(16),
                                                ),
                                                child: Text(
                                                  '$trackPosition $_sampleRate ${widget.codec}'.toUpperCase(),
                                                  style: const TextStyle(fontSize: 12, color: Colors.white70, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                                                ),
                                              ),
                                              Text(
                                                _fmt(duration),
                                                style: const TextStyle(fontSize: 16, color: Colors.white, fontWeight: FontWeight.bold),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
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
                        const SizedBox(height: 16),
                        // ── AppBar-style header ───────────────────────────
                        Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8.0, vertical: 4.0),
                          child: Row(
                            children: [
                              IconButton(
                                icon: const Icon(
                                    Icons.keyboard_arrow_down,
                                    size: 32,
                                    color: textLight),
                                onPressed: widget.onMinimize,
                              ),
                              Expanded(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
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
                            ],
                          ),
                        ),
                        const SizedBox(height: 4),
                        // Top Album Art Section
                        Expanded(
                          flex: 5,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16.0),
                            child: Stack(
                              children: [
                                // Album Art Image
                                Positioned.fill(
                                  child: Container(
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(24.0),
                                      color: surfaceColor,
                                      image: widget.albumArt != null
                                          ? DecorationImage(
                                              image: MemoryImage(widget.albumArt!),
                                              fit: BoxFit.cover,
                                            )
                                          : null,
                                    ),
                                  ),
                                ),
                                // Gradient Overlay at the bottom
                                Positioned(
                                  bottom: 0,
                                  left: 0,
                                  right: 0,
                                  height: 120,
                                  child: Container(
                                    decoration: BoxDecoration(
                                      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(24.0)),
                                      gradient: LinearGradient(
                                        begin: Alignment.topCenter,
                                        end: Alignment.bottomCenter,
                                        colors: [
                                          Colors.transparent,
                                          Colors.black.withValues(alpha: 0.8),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                                // Text (Title, Artist)
                                Positioned(
                                  left: 16,
                                  bottom: 60,
                                  right: 16,
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      AdaptiveMarqueeText(
                                        text: title,
                                        style: const TextStyle(
                                          fontSize: 24,
                                          fontWeight: FontWeight.bold,
                                          color: textLight,
                                        ),
                                        blankSpace: 40.0,
                                        velocity: 30.0,
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        subtitle,
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.white70,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),
                                // Buttons at the bottom edge
                                Positioned(
                                  bottom: 12,
                                  left: 16,
                                  right: 16,
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Row(
                                        children: [
                                          // Like
                                          ValueListenableBuilder<List<LikedSong>>(
                                            valueListenable: LikedSongsService.instance.likedSongsNotifier,
                                            builder: (context, likedSongs, _) {
                                              final trackId = widget.videoId ?? widget.getTitle(status.currentIndex);
                                              final isCurrentlyLiked = likedSongs.any((s) => s.videoId == trackId);
                                              return GestureDetector(
                                                onTap: () async {
                                                  if (trackId.isEmpty) return;
                                                  if (isCurrentlyLiked) {
                                                    await LikedSongsService.instance.removeLikedSong(trackId);
                                                  } else {
                                                    await LikedSongsService.instance.addLikedSong(LikedSong(
                                                      videoId: trackId,
                                                      title: title,
                                                      artist: subtitle,
                                                      thumbnailUrl: widget.albumArt == null ? null : trackId,
                                                      durationSeconds: duration.inSeconds,
                                                      likedAt: DateTime.now(),
                                                    ));
                                                  }
                                                },
                                                child: CircleAvatar(
                                                  backgroundColor: isCurrentlyLiked ? primaryColor : Colors.white.withValues(alpha: 0.2),
                                                  radius: 18,
                                                  child: Icon(isCurrentlyLiked ? Icons.thumb_up : Icons.thumb_up_outlined, color: Colors.white, size: 18),
                                                ),
                                              );
                                            },
                                          ),
                                          const SizedBox(width: 8),
                                          // Dislike
                                          CircleAvatar(
                                            backgroundColor: Colors.white.withValues(alpha: 0.2),
                                            radius: 18,
                                            child: const Icon(Icons.thumb_down_outlined, color: Colors.white, size: 18),
                                          ),
                                        ],
                                      ),
                                      Row(
                                        children: [
                                          // Queue/Playlist
                                          GestureDetector(
                                            onTap: () => _showQueueSheet(context),
                                            child: CircleAvatar(
                                              backgroundColor: Colors.white.withValues(alpha: 0.2),
                                              radius: 18,
                                              child: const Icon(Icons.playlist_play, color: Colors.white, size: 18),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          // More options
                                          const Icon(Icons.more_vert, color: Colors.white),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        
                        const SizedBox(height: 32),
                        
                        // Playback Controls
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.fast_rewind, size: 32, color: Colors.white54),
                              onPressed: () { widget.player.seekTo(Duration(milliseconds: (displayPosMs - 10000).toInt().clamp(0, maxMs.toInt()))); },
                            ),
                            const SizedBox(width: 8),
                            IconButton(
                              icon: const Icon(Icons.skip_previous, size: 40, color: Colors.white),
                              onPressed: widget.player.seekToPrevious,
                            ),
                            const SizedBox(width: 16),
                            GestureDetector(
                              onTap: status.isPlaying ? widget.player.pause : widget.player.play,
                              child: Container(
                                width: 80,
                                height: 80,
                                decoration: const BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Colors.black,
                                ),
                                child: Icon(
                                  status.isPlaying ? Icons.pause : Icons.play_arrow,
                                  size: 48,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                            const SizedBox(width: 16),
                            IconButton(
                              icon: const Icon(Icons.skip_next, size: 40, color: Colors.white),
                              onPressed: widget.player.seekToNext,
                            ),
                            const SizedBox(width: 8),
                            IconButton(
                              icon: const Icon(Icons.fast_forward, size: 32, color: Colors.white54),
                              onPressed: () { widget.player.seekTo(Duration(milliseconds: (displayPosMs + 10000).toInt().clamp(0, maxMs.toInt()))); },
                            ),
                          ],
                        ),
                        
                        const SizedBox(height: 24),
                        
                        // Progress Bar & Info Badge
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24.0),
                          child: Column(
                            children: [
                              SliderTheme(
                                data: SliderTheme.of(context).copyWith(
                                  trackHeight: 4.0,
                                  activeTrackColor: Colors.white54,
                                  inactiveTrackColor: Colors.white12,
                                  thumbColor: Colors.white,
                                  overlayColor: Colors.white24,
                                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6.0),
                                  overlayShape: const RoundSliderOverlayShape(overlayRadius: 14.0),
                                ),
                                child: Slider(
                                  value: displayPosMs,
                                  min: 0.0,
                                  max: maxMs,
                                  onChangeStart: (v) { setState(() { _isDragging = true; _dragPositionMs = v; }); },
                                  onChanged: (v) { setState(() => _dragPositionMs = v); },
                                  onChangeEnd: (v) {
                                    _seekTimeoutTimer?.cancel();
                                    setState(() { _isDragging = false; _pendingSeekMs = v; });
                                    widget.player.seekTo(Duration(milliseconds: v.toInt()));
                                    _seekTimeoutTimer = Timer(const Duration(seconds: 45), () { if (mounted) setState(() => _pendingSeekMs = null); });
                                  },
                                ),
                              ),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    _fmt(Duration(milliseconds: displayPosMs.toInt())),
                                    style: const TextStyle(fontSize: 12, color: Colors.white, fontWeight: FontWeight.bold),
                                  ),
                                  // Audio Info Badge
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      '$trackPosition $_sampleRate ${widget.codec}'.toUpperCase(),
                                      style: const TextStyle(fontSize: 10, color: Colors.white70, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                                    ),
                                  ),
                                  Text(
                                    _fmt(duration),
                                    style: const TextStyle(fontSize: 12, color: Colors.white, fontWeight: FontWeight.bold),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        
                        const SizedBox(height: 32),
                        
                        // Action Buttons Row (Eq, Timer, Repeat, Shuffle)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24.0),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              _buildActionIcon(Icons.graphic_eq, () {
                                Navigator.push(context, MaterialPageRoute(builder: (context) => EffectsScreen(
                                  player: widget.player,
                                  analyzerEnabled: _isAnalyzerEnabled,
                                  analyzerType: widget.analyzerType,
                                  analyzerAutoFit: widget.analyzerAutoFit,
                                  analyzerShowGrids: widget.analyzerShowGrids,
                                  outputSampleRate: widget.outputSampleRate,
                                )));
                              }),
                              _buildActionIcon(Icons.access_time, () {}),
                              _buildActionIcon(_loopIcon(status.loopMode), () {
                                final currentMode = status.loopMode;
                                final nextMode = currentMode == LoopMode.off ? LoopMode.all : (currentMode == LoopMode.all ? LoopMode.one : LoopMode.off);
                                widget.player.setLoopMode(nextMode);
                              }),
                              _buildActionIcon(status.shuffleEnabled ? Icons.shuffle_on : Icons.shuffle, () { widget.player.setShuffleModeEnabled(!status.shuffleEnabled); }),
                            ],
                          ),
                        ),
                        
                        const SizedBox(height: 24),
                        
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

  Widget _buildActionIcon(IconData icon, VoidCallback onTap, [bool isActive = false]) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          color: isActive ? Colors.white24 : Colors.white10,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Icon(icon, color: Colors.white70, size: 24),
      ),
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
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false, // allows the Now Playing screen to show behind the transparent background
        pageBuilder: (context, animation, secondaryAnimation) => QueueScreen(
          queue: widget.queue,
          videoId: widget.videoId,
          albumArt: widget.albumArt,
          onPlayQueueIndex: widget.onPlayQueueIndex,
          onReorderQueue: widget.onReorderQueue,
        ),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          const begin = Offset(0.0, 1.0);
          const end = Offset.zero;
          const curve = Curves.easeOutCubic;

          var tween = Tween(begin: begin, end: end).chain(CurveTween(curve: curve));
          var offsetAnimation = animation.drive(tween);

          return SlideTransition(
            position: offsetAnimation,
            child: child,
          );
        },
      ),
    );
  }
}
