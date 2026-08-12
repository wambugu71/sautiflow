import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:loading_indicator_m3e/loading_indicator_m3e.dart';
import 'package:file_picker/file_picker.dart';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:dart_ytmusic_api/dart_ytmusic_api.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_lyric/flutter_lyric.dart';
import 'package:sautiflow/sautiflow.dart';

import 'album_detail_screen.dart'; // For TrackInfo
import 'effects_screen.dart';
import 'isolate_player.dart';
import 'models/liked_song.dart';
import 'queue_screen.dart'; // NEW
import 'services/audio_file_inspector.dart';
import 'services/audio_hardware_inspector.dart';
import 'services/fft_processor.dart';
import 'services/liked_songs_service.dart';
import 'services/waveform_extractor_service.dart';
import 'widgets/adaptive_marquee_text.dart';
import 'widgets/audio_engine_diagnostic_panel.dart';
import 'widgets/music_info_dialog.dart';
import 'widgets/playback_speed_modal.dart';
import 'widgets/synced_lyrics_widget.dart';
import 'widgets/waveform_seek_bar_widget.dart';
import 'services/app_state_service.dart';
import 'services/app_theme_service.dart';

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

class _NowPlayingScreenState extends State<NowPlayingScreen>
    with SingleTickerProviderStateMixin {
  late bool _isAnalyzerEnabled;
  late final AnimationController _rotationController;
  late final PageController _pageController;

  final ValueNotifier<List<double>> _analyzerValuesNotifier = ValueNotifier([]);
  StreamSubscription? _analyzerSub;
  FftProcessor? _fftProcessor;

  final bool _showLyrics = false;
  String? _lyricsRaw;
  bool _isLoadingLyrics = false;
  bool _showLyricsOverlayOnAlbumArt = false;
  bool _isCustomLyricsLoaded = false;
  String? _customLyricsFileName;

  // ── Live hardware specs (updates on route change) ─────────────────────────
  AudioHardwareSpecs? _hardwareSpecs;
  StreamSubscription<AudioHardwareSpecs>? _hardwareSub;
  final LyricController _lyricController = LyricController();
  final YTMusic _ytMusic = YTMusic();

  int _fileSizeBytes = 0;
  String _originalBitDepth = '';
  String _sampleRate = '...';
  String _channels = '...';
  String? _detectedCodec;

  String? _customTitle;
  String? _customArtist;
  String _customAlbum = 'Unknown Album';
  String _customGenre = 'Unknown Genre';
  String _customYear = '';
  String _customTrackNum = '';

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
  double _currentPitch = 1.0;

  // ── A-B Repeat ────────────────────────────────────────────────────────────
  // State machine: 0 = off, 1 = point A set (waiting for B), 2 = active loop
  int _abRepeatState = 0;
  double? _abPointAMs;
  double? _abPointBMs;

  // ── Waveform Seek Bar ──────────────────────────────────────────────────────
  bool _useWaveformSeekBar = false;
  List<double>? _currentWaveformPeaks;
  StreamSubscription<bool>? _waveformSub;
  int _lastKnownTrackIndex = -1;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: 0);
    _isAnalyzerEnabled = widget.analyzerEnabled;
    _ytMusic.initialize();
    _fetchLyrics();
    _fetchAudioProperties();
    _loadPlaybackSpeed();
    _loadWaveformSetting();

    _setupAnalyzer(_isAnalyzerEnabled);
    _initHardwareSpecs();

    _rotationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 20),
    );

    // Watch engine status to detect when a pending seek has landed.
    widget.statusNotifier.addListener(_onStatusChanged);
  }

  Future<void> _loadWaveformSetting() async {
    final enabled = await AppStateService.instance.loadUseWaveformSeekBar();
    if (mounted) {
      setState(() => _useWaveformSeekBar = enabled);
      if (enabled) _updateCurrentTrackWaveform();
    }
    _waveformSub = AppStateService.instance.useWaveformSeekBarChanged.stream
        .listen((enabled) {
      if (mounted) {
        setState(() => _useWaveformSeekBar = enabled);
        if (enabled && _currentWaveformPeaks == null) {
          _updateCurrentTrackWaveform();
        }
      }
    });
  }

  Future<void> _updateCurrentTrackWaveform() async {
    final status = widget.statusNotifier.value;
    String trackPath = '';
    if (widget.queue.isNotEmpty &&
        status.currentIndex >= 0 &&
        status.currentIndex < widget.queue.length) {
      final track = widget.queue[status.currentIndex];
      trackPath = track.videoId.isNotEmpty ? track.videoId : track.title;
    }
    if (trackPath.isEmpty) {
      trackPath = widget.videoId ?? widget.getTitle(status.currentIndex);
    }
    if (trackPath.isEmpty) return;

    final peaks =
        await WaveformExtractorService.instance.getWaveform(trackPath);
    if (mounted) {
      setState(() {
        _currentWaveformPeaks = peaks;
      });
    }
  }

  Future<void> _loadPlaybackSpeed() async {
    final pitch = await AppStateService.instance.loadPlaybackSpeed();
    if (mounted) {
      setState(() => _currentPitch = pitch);
      if ((pitch - 1.0).abs() > 0.01) {
        widget.player.setPitch(pitch);
      }
    }
  }

  /// Called on every engine status poll (~200 ms).  Once the engine's reported
  /// position is within 4 seconds of the seek target we consider the seek
  /// landed and release the position override.
  void _onStatusChanged() {
    final status = widget.statusNotifier.value;
    if (status.isPlaying) {
      if (!_rotationController.isAnimating) {
        _rotationController.repeat();
      }
    } else {
      if (_rotationController.isAnimating) {
        _rotationController.stop();
      }
    }

    if (status.currentIndex != _lastKnownTrackIndex) {
      _lastKnownTrackIndex = status.currentIndex;
      _pendingSeekMs = null;
      _isDragging = false;
      _seekTimeoutTimer?.cancel();
      _abRepeatState = 0;
      _abPointAMs = null;
      _abPointBMs = null;
      widget.player.setAbRepeat(enabled: false, startSeconds: 0, endSeconds: 0);
      if (_useWaveformSeekBar) {
        _updateCurrentTrackWaveform();
      }
    }

    final target = _pendingSeekMs;
    if (target == null) return;
    final enginePosMs = status.positionSeconds * 1000.0;
    if ((enginePosMs - target).abs() < 4000 ||
        (enginePosMs < 2000 && target > 5000)) {
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
    if (oldWidget.videoId != widget.videoId ||
        oldWidget.sourceType != widget.sourceType) {
      _pendingSeekMs = null;
      _isDragging = false;
      _seekTimeoutTimer?.cancel();
      _fetchAudioProperties();
      _fetchLyrics();
      if (_useWaveformSeekBar) {
        _updateCurrentTrackWaveform();
      }
    }
  }

  @override
  void dispose() {
    widget.statusNotifier.removeListener(_onStatusChanged);
    _seekTimeoutTimer?.cancel();
    _analyzerSub?.cancel();
    _hardwareSub?.cancel();
    _waveformSub?.cancel();
    _analyzerValuesNotifier.dispose();
    _rotationController.dispose();
    _pageController.dispose();
    // Always clear A-B repeat when leaving the screen
    widget.player.setAbRepeat(enabled: false, startSeconds: 0, endSeconds: 0);
    super.dispose();
  }

  Future<void> _initHardwareSpecs() async {
    final initial = await AudioHardwareInspector.inspectAsync(widget.player);
    if (mounted) setState(() => _hardwareSpecs = initial);
    _subscribeHardwareStream();
  }

  void _subscribeHardwareStream() {
    _hardwareSub?.cancel();
    _hardwareSub = AudioHardwareInspector.hardwareStream(widget.player).listen(
      (specs) {
        if (mounted) setState(() => _hardwareSpecs = specs);
      },
      onError: (_) {/* ignore — stream errors are handled in the service */},
    );
  }

  void _setupAnalyzer(bool enabled) {
    if (enabled) {
      final sr = widget.outputSampleRate > 0 ? widget.outputSampleRate : 48000;
      _fftProcessor ??= FftProcessor(sampleRate: sr);
      widget.player.setAnalyzerEnabled(true);
      _analyzerSub ??= widget.player.analyzerStream.listen((frame) {
        if (frame.isEmpty) return;
        final bins = _fftProcessor!.processFrame(frame, targetBins: 96);
        _analyzerValuesNotifier.value = bins;
      });
    } else {
      widget.player.setAnalyzerEnabled(false);
      _analyzerSub?.cancel();
      _analyzerSub = null;
      _fftProcessor?.reset();
      _analyzerValuesNotifier.value = [];
    }
  }

  String _formatSampleRate(int rateHz) {
    if (rateHz <= 0) return '44.1 kHz';
    if (rateHz % 1000 == 0) {
      return '${rateHz ~/ 1000}.0 kHz';
    }
    final double kHz = rateHz / 1000.0;
    return '${kHz.toStringAsFixed(1)} kHz';
  }

  Future<void> _fetchAudioProperties() async {
    _fileSizeBytes = 0;
    _originalBitDepth = '';
    _detectedCodec = null;

    try {
      final props = await widget.player.getAudioProperties();
      final pipelineState = await widget.player.getPipelineState();
      String? sampleRateStr;
      String? channelsStr;
      String? depthStr;
      String? codecStr;

      String? cleanPath = widget.videoId;
      if (cleanPath != null && cleanPath.startsWith('file://')) {
        cleanPath = Uri.tryParse(cleanPath)?.toFilePath();
      }

      if (cleanPath != null) {
        try {
          final file = File(cleanPath);
          if (file.existsSync()) {
            _fileSizeBytes = file.lengthSync();
            final info = await AudioFileInspector.inspectNative(
                widget.player, cleanPath);
            sampleRateStr = info.formattedSampleRate;
            depthStr = info.formattedBitDepth;
            channelsStr = info.formattedChannels;
            codecStr = info.codec;

            try {
              final metadata = readMetadata(file, getImage: false);
              if (metadata.album != null && metadata.album!.isNotEmpty) {
                _customAlbum = metadata.album!;
              }
              if (metadata.genres.isNotEmpty &&
                  metadata.genres.first.isNotEmpty) {
                _customGenre = metadata.genres.first;
              }
              if (metadata.year != null) {
                _customYear = metadata.year.toString();
              }
              if (metadata.trackNumber != null) {
                _customTrackNum = metadata.trackNumber.toString();
              }
            } catch (_) {}
          }
        } catch (e) {
          debugPrint('[NowPlaying] Audio file inspector error: $e');
        }
      }

      // Fallback to live native pipeline state if file inspector didn't run or missed
      if (sampleRateStr == null && pipelineState.inputSampleRate > 0) {
        sampleRateStr = _formatSampleRate(pipelineState.inputSampleRate);
      }
      if (channelsStr == null && pipelineState.inputChannels > 0) {
        channelsStr = pipelineState.inputChannels == 1 ? 'MONO' : 'STEREO';
      }
      if (depthStr == null) {
        switch (pipelineState.inputFormat) {
          case 0:
            depthStr = '32 bit float';
            break;
          case 3:
            depthStr = '24 bit';
            break;
          case 4:
            depthStr = '32 bit';
            break;
          case 2:
            depthStr = '8 bit';
            break;
          case 1:
          default:
            depthStr = '16 bit';
            break;
        }
      }

      if (mounted) {
        setState(() {
          final int rate = props['sampleRate'] as int? ?? 44100;
          _sampleRate = sampleRateStr ?? _formatSampleRate(rate);

          final int channels = props['channels'] as int? ?? 2;
          _channels = channelsStr ?? (channels == 1 ? 'MONO' : 'STEREO');
          _originalBitDepth = depthStr ?? '16 bit';
          _detectedCodec = codecStr;
        });
      }
    } catch (e) {
      debugPrint('[NowPlaying] Failed to fetch audio properties: $e');
    }
  }

  String _buildAudioInfoBadgeText(String trackPosition) {
    final depthPart = _originalBitDepth.isNotEmpty ? '$_originalBitDepth ' : '';
    final codecPart = _detectedCodec ?? widget.codec;
    final speedPart = (_currentPitch - 1.0).abs() > 0.01
        ? ' ${_currentPitch.toStringAsFixed(2)}X'
        : '';
    return '$trackPosition $depthPart$_sampleRate $codecPart$speedPart'
        .toUpperCase();
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

  Future<void> _pickLrcFile() async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['lrc', 'txt'],
      );

      if (result != null && result.files.single.path != null) {
        final file = File(result.files.single.path!);
        final content = await file.readAsString();
        if (content.trim().isEmpty) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Selected lyrics file is empty.'),
                backgroundColor: Color(0xFF1E2D3D),
              ),
            );
          }
          return;
        }

        String lrcToLoad = content;
        final hasTimestamp = RegExp(r'\[\d{2,}:\d{2}').hasMatch(content);
        if (!hasTimestamp) {
          final overrideSecs = widget.durationOverride;
          final baseDurationSecs = (overrideSecs != null && overrideSecs > 0)
              ? overrideSecs.toDouble()
              : widget.statusNotifier.value.durationSeconds;
          final durationMs = (baseDurationSecs * 1000).round();
          lrcToLoad = _generateFakeLrc(content, durationMs);
        }

        _lyricController.loadLyric(lrcToLoad);

        if (mounted) {
          setState(() {
            _lyricsRaw = content;
            _isCustomLyricsLoaded = true;
            _customLyricsFileName = result.files.single.name;
            _showLyricsOverlayOnAlbumArt = true;
          });

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  Icon(Icons.lyrics_outlined,
                      color: AppThemeService.instance.currentData.primary,
                      size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Loaded lyrics: ${_customLyricsFileName!}',
                      style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.bold),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              backgroundColor: const Color(0xFF1E2D3D),
              duration: const Duration(seconds: 2),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('[NowPlaying] Failed to load .lrc file: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to read .lrc file: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  void _clearCustomLyrics() {
    setState(() {
      _isCustomLyricsLoaded = false;
      _customLyricsFileName = null;
      _showLyricsOverlayOnAlbumArt = false;
    });
    _fetchLyrics();
  }

  void _showMoreOptionsMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF18232E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Center(
                      child: Container(
                        width: 36,
                        height: 4,
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: Colors.white24,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0),
                      child: Text(
                        'TRACK OPTIONS',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.2,
                          color: AppThemeService.instance.currentData.primary,
                        ),
                      ),
                    ),
                    ListTile(
                      leading:
                          const Icon(Icons.info_outline, color: Colors.white),
                      title: const Text('Song Info & Tags',
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600)),
                      subtitle: const Text('View or edit track metadata',
                          style:
                              TextStyle(color: Colors.white54, fontSize: 12)),
                      onTap: () {
                        Navigator.pop(sheetContext);
                        _showMusicInfoDialog(context);
                      },
                    ),
                    ListTile(
                      leading: Icon(Icons.subtitles_outlined,
                          color: AppThemeService.instance.currentData.primary),
                      title: const Text('Add .lrc Lyrics File',
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600)),
                      subtitle: Text(
                        _isCustomLyricsLoaded
                            ? 'Loaded: ${_customLyricsFileName ?? "Custom LRC"}'
                            : 'Select synchronized .lrc / .txt file from storage',
                        style: const TextStyle(
                            color: Colors.white54, fontSize: 12),
                        overflow: TextOverflow.ellipsis,
                      ),
                      onTap: () {
                        Navigator.pop(sheetContext);
                        _pickLrcFile();
                      },
                    ),
                    SwitchListTile(
                      secondary: Icon(
                        _showLyricsOverlayOnAlbumArt
                            ? Icons.layers
                            : Icons.layers_clear,
                        color: _showLyricsOverlayOnAlbumArt
                            ? AppThemeService.instance.currentData.primary
                            : Colors.white54,
                      ),
                      title: const Text('Lyrics Overlay on Album Art',
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600)),
                      subtitle: const Text(
                          'Display synchronized lyrics over album cover',
                          style:
                              TextStyle(color: Colors.white54, fontSize: 12)),
                      activeThumbColor:
                          AppThemeService.instance.currentData.primary,
                      value: _showLyricsOverlayOnAlbumArt,
                      onChanged: (_lyricsRaw == null && !_isCustomLyricsLoaded)
                          ? null
                          : (val) {
                              setSheetState(
                                  () => _showLyricsOverlayOnAlbumArt = val);
                              setState(
                                  () => _showLyricsOverlayOnAlbumArt = val);
                            },
                    ),
                    if (_isCustomLyricsLoaded)
                      ListTile(
                        leading: const Icon(Icons.cleaning_services_outlined,
                            color: Colors.redAccent),
                        title: const Text('Reset to Default Lyrics',
                            style: TextStyle(
                                color: Colors.redAccent,
                                fontWeight: FontWeight.w600)),
                        onTap: () {
                          Navigator.pop(sheetContext);
                          _clearCustomLyrics();
                        },
                      ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildAlbumArtLyricsOverlay({
    required double borderRadius,
    required double bottomOffset,
    required double displayPosMs,
  }) {
    if (!_showLyricsOverlayOnAlbumArt) return const SizedBox.shrink();

    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      bottom: bottomOffset,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(borderRadius),
            bottom: Radius.circular(bottomOffset > 0 ? 16.0 : borderRadius),
          ),
          color: Colors.black.withValues(alpha: 0.88),
          border: Border.all(
            color: AppThemeService.instance.currentData.primary
                .withValues(alpha: 0.4),
            width: 1.5,
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(borderRadius),
            bottom: Radius.circular(bottomOffset > 0 ? 16.0 : borderRadius),
          ),
          child: Stack(
            children: [
              Positioned.fill(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 40, 12, 12),
                  child: SyncedLyricsWidget(
                    lyricsRaw: _lyricsRaw ?? '',
                    currentPosition:
                        Duration(milliseconds: displayPosMs.toInt()),
                    onSeek: (targetTime) {
                      widget.player.seekTo(targetTime);
                    },
                  ),
                ),
              ),
              // Top Banner & Close Button
              Positioned(
                top: 8,
                left: 12,
                right: 8,
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppThemeService.instance.currentData.primary
                            .withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.lyrics,
                              size: 12,
                              color:
                                  AppThemeService.instance.currentData.primary),
                          const SizedBox(width: 4),
                          Text(
                            _isCustomLyricsLoaded
                                ? (_customLyricsFileName ?? 'Custom LRC')
                                : 'Synced Lyrics',
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Colors.white70,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close,
                          size: 18, color: Colors.white70),
                      onPressed: () {
                        setState(() => _showLyricsOverlayOnAlbumArt = false);
                      },
                      tooltip: 'Hide Lyrics Overlay',
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
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

  void _showMusicInfoDialog(BuildContext context) {
    final status = widget.statusNotifier.value;
    final overrideSecs = widget.durationOverride;
    final baseDurationSecs = (overrideSecs != null && overrideSecs > 0)
        ? overrideSecs.toDouble()
        : status.durationSeconds;
    final duration = Duration(milliseconds: (baseDurationSecs * 1000).round());
    final rawTitle = widget.getTitle(status.currentIndex);

    showDialog(
      context: context,
      builder: (context) => MusicInfoDialog(
        title: _customTitle ?? rawTitle,
        artist: _customArtist ?? widget.artist,
        album: _customAlbum,
        genre: _customGenre,
        year: _customYear,
        trackNumber: _customTrackNum,
        albumArt: widget.albumArt,
        sourceType: widget.sourceType,
        videoId: widget.videoId,
        codec: _detectedCodec ?? widget.codec,
        sampleRate: _sampleRate,
        channels: _channels,
        bitDepth: _originalBitDepth,
        fileSizeBytes: _fileSizeBytes,
        duration: duration,
        onSaveTags: ({
          required String title,
          required String artist,
          required String album,
          required String genre,
          required String year,
          required String trackNumber,
        }) {
          setState(() {
            _customTitle = title.isNotEmpty ? title : null;
            _customArtist = artist.isNotEmpty ? artist : null;
            _customAlbum = album;
            _customGenre = genre;
            _customYear = year;
            _customTrackNum = trackNumber;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Song tags updated successfully'),
              duration: Duration(seconds: 2),
            ),
          );
        },
      ),
    );
  }

  void _showHardwareSpecsModal(BuildContext context) {
    if (_hardwareSpecs == null) {
      AudioHardwareInspector.inspectAsync(widget.player).then((specs) {
        if (mounted) setState(() => _hardwareSpecs = specs);
      });
    }

    final initial = _hardwareSpecs ?? AudioHardwareInspector.currentSpecs;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: const Color(0xFF18232E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetContext) {
        return StreamBuilder<AudioHardwareSpecs>(
          initialData: initial,
          stream: AudioHardwareInspector.hardwareStream(widget.player),
          builder: (context, snapshot) {
            final specs =
                snapshot.data ?? initial ?? AudioHardwareInspector.currentSpecs;
            return ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.92,
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20.0, 16.0, 20.0, 24.0),
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: specs == null
                      ? SizedBox(
                          height: 160,
                          child: Center(
                            child: CircularProgressIndicator(
                              color:
                                  AppThemeService.instance.currentData.primary,
                            ),
                          ),
                        )
                      : _buildHardwareSheetContent(specs),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildHardwareSheetContent(AudioHardwareSpecs specs) {
    final primaryColor = AppThemeService.instance.currentData.primary;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Drag handle ──────────────────────────────────────────────────────
        Center(
          child: Container(
            width: 36,
            height: 4,
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        // ── Header row ───────────────────────────────────────────────────────
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: primaryColor.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(Icons.equalizer, color: primaryColor),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'AUDIO OUTPUT CHAIN',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                      color: primaryColor,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    specs.isBluetooth
                        ? (specs.bluetoothDeviceName ?? specs.deviceName)
                        : specs.deviceName,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            // Live indicator dot
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: const Color(0xFF22C55E),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF22C55E).withValues(alpha: 0.5),
                    blurRadius: 6,
                    spreadRadius: 1,
                  )
                ],
              ),
            ),
            const SizedBox(width: 6),
            const Text(
              'LIVE',
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.bold,
                color: Color(0xFF22C55E),
                letterSpacing: 1.0,
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        const Divider(color: Colors.white12),
        const SizedBox(height: 16),

        const Text(
          'AUDIO SIGNAL CHAIN',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.0,
            color: Colors.white38,
          ),
        ),
        const SizedBox(height: 12),
        _buildSignalChain(specs),
        const SizedBox(height: 20),
        const Divider(color: Colors.white12),
        const SizedBox(height: 16),

        // ── Detail Chips ─────────────────────────────────────────────────────
        const Text(
          'HARDWARE SPECS',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.0,
            color: Colors.white38,
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _buildSpecChip(Icons.api, 'Backend', specs.backendName),
            _buildSpecChip(
              Icons.headset,
              'Route',
              specs.deviceType,
            ),
            _buildSpecChip(
              Icons.speed,
              'Sample Rate',
              specs.formattedSampleRate,
              isHiRes: specs.isHiResAudio,
            ),
            _buildSpecChip(
              Icons.high_quality,
              'Bit Depth',
              specs.formattedBitDepth,
            ),
            _buildSpecChip(
              Icons.timer_outlined,
              'Buffer Latency',
              specs.formattedLatency,
            ),
            _buildSpecChip(
              Icons.surround_sound,
              'Channels',
              '${specs.channels} Ch (Stereo)',
            ),
            _buildSpecChip(
              Icons.lock_outline,
              'Mode',
              specs.isExclusiveMode ? 'Bit-Perfect Exclusive' : 'Shared Mixer',
            ),
            if (specs.bluetoothCodec != null)
              _buildSpecChip(
                Icons.bluetooth_audio,
                'BT Codec',
                specs.formattedBtCodec ?? specs.bluetoothCodec!,
                isHiRes: specs.bluetoothCodec == 'LDAC' ||
                    specs.bluetoothCodec == 'aptX HD' ||
                    specs.bluetoothCodec == 'LC3',
              ),
          ],
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildSignalChain(AudioHardwareSpecs specs) {
    final nodes = specs.buildPowerampSignalChain(
      sourceCodec: _detectedCodec ?? widget.codec,
      sourceSampleRate: _sampleRate,
      sourceBitDepth: _originalBitDepth,
      sourceChannels: _channels,
    );
    return SizedBox(
      height: 96,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: nodes.length,
        separatorBuilder: (_, __) => _buildChainArrow(),
        itemBuilder: (context, i) => _buildChainNode(nodes[i]),
      ),
    );
  }

  Widget _buildChainArrow() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 16,
              height: 1.5,
              color: Colors.white24,
            ),
            const Icon(
              Icons.arrow_forward_ios,
              size: 10,
              color: Colors.white38,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChainNode(SignalChainNode node) {
    final primaryColor = AppThemeService.instance.currentData.primary;
    final accent = node.isHighlight ? primaryColor : Colors.white24;
    final labelColor = node.isHighlight ? primaryColor : Colors.white70;

    return Container(
      width: 130,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: node.isHighlight
            ? primaryColor.withValues(alpha: 0.12)
            : Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: accent.withValues(alpha: node.isHighlight ? 0.6 : 0.3),
          width: node.isHighlight ? 1.5 : 1.0,
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            _iconDataForNode(node.icon),
            size: 18,
            color: labelColor,
          ),
          const SizedBox(height: 6),
          Text(
            node.label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: labelColor,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (node.sublabel != null) ...[
            const SizedBox(height: 2),
            Text(
              node.sublabel!,
              style: TextStyle(
                fontSize: 10,
                color: node.isHighlight
                    ? primaryColor.withValues(alpha: 0.8)
                    : Colors.white38,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }

  IconData _iconDataForNode(SignalChainIcon icon) {
    switch (icon) {
      case SignalChainIcon.source:
        return Icons.audio_file;
      case SignalChainIcon.dsp:
        return Icons.graphic_eq;
      case SignalChainIcon.backend:
        return Icons.developer_board;
      case SignalChainIcon.bluetooth:
        return Icons.bluetooth_audio;
      case SignalChainIcon.wiredHeadphone:
        return Icons.headphones;
      case SignalChainIcon.usbDac:
        return Icons.usb;
      case SignalChainIcon.speaker:
        return Icons.speaker;
      case SignalChainIcon.hdmi:
        return Icons.tv;
      case SignalChainIcon.output:
        return Icons.output;
    }
  }

  Widget _buildSpecChip(IconData icon, String label, String value,
      {bool isHiRes = false}) {
    return Container(
      width: 160,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isHiRes
              ? AppThemeService.instance.currentData.primary
                  .withValues(alpha: 0.6)
              : Colors.white.withValues(alpha: 0.08),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon,
                  size: 14,
                  color: isHiRes
                      ? AppThemeService.instance.currentData.primary
                      : Colors.white54),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label.toUpperCase(),
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: isHiRes
                        ? AppThemeService.instance.currentData.primary
                        : Colors.white54,
                    letterSpacing: 0.5,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<PlayerStatus>(
      valueListenable: widget.statusNotifier,
      builder: (context, status, _) {
        if (status.isPlaying) {
          if (!_rotationController.isAnimating) {
            _rotationController.repeat();
          }
        } else {
          if (_rotationController.isAnimating) {
            _rotationController.stop();
          }
        }

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

        final rawTitle = widget.getTitle(status.currentIndex);
        final title = _customTitle ?? rawTitle;
        final subtitle = _customArtist ?? widget.artist;

        // Theme colors matching the HTML mockup
        final Color primaryColor = AppThemeService.instance.currentData.primary;
        final Color bgColor = AppThemeService.instance.currentData.bgDark;
        const Color surfaceColor = Color(0xFF18232E);
        const Color textLight = Colors.white;
        final Color textDark =
            AppThemeService.instance.currentData.textDark; // slate-400

        return Theme(
          data: ThemeData.dark().copyWith(
            scaffoldBackgroundColor: bgColor,
            primaryColor: primaryColor,
            colorScheme: ColorScheme.dark(
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
                          primaryColor.withValues(alpha: 0.15),
                          bgColor,
                        ],
                      ),
                    ),
                  ),
                ),
                PageView(
                  controller: _pageController,
                  scrollDirection: Axis.vertical,
                  physics: const BouncingScrollPhysics(),
                  children: [
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
                                    style: TextStyle(
                                        color: textDark, fontSize: 16),
                                  ),
                                )
                              : SyncedLyricsWidget(
                                  lyricsRaw: _lyricsRaw!,
                                  currentPosition: Duration(
                                      milliseconds: displayPosMs.toInt()),
                                  onSeek: (targetTime) {
                                    widget.player.seekTo(targetTime);
                                  },
                                );

                      Widget content;
                      if (isDesktop) {
                        content = Column(
                          children: [
                            const SizedBox(height: 24),
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 64.0, vertical: 24.0),
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
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            32.0),
                                                    color: surfaceColor,
                                                    boxShadow: [
                                                      BoxShadow(
                                                        color: Colors.black
                                                            .withValues(
                                                                alpha: 0.5),
                                                        blurRadius: 40,
                                                        spreadRadius: 2,
                                                        offset:
                                                            const Offset(0, 10),
                                                      ),
                                                    ],
                                                  ),
                                                  child: ClipRRect(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            32.0),
                                                    child: (widget.albumArt !=
                                                                null &&
                                                            widget.albumArt!
                                                                .isNotEmpty)
                                                        ? Container(
                                                            decoration:
                                                                BoxDecoration(
                                                              image:
                                                                  DecorationImage(
                                                                image: MemoryImage(
                                                                    widget
                                                                        .albumArt!),
                                                                fit: BoxFit
                                                                    .cover,
                                                              ),
                                                            ),
                                                          )
                                                        : RotationTransition(
                                                            turns:
                                                                _rotationController,
                                                            child: Container(
                                                              color:
                                                                  surfaceColor,
                                                              padding:
                                                                  const EdgeInsets
                                                                      .all(
                                                                      32.0),
                                                              child:
                                                                  Image.asset(
                                                                'assets/icon/splash.png',
                                                                fit: BoxFit
                                                                    .contain,
                                                              ),
                                                            ),
                                                          ),
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
                                                    borderRadius:
                                                        const BorderRadius
                                                            .vertical(
                                                            bottom:
                                                                Radius.circular(
                                                                    32.0)),
                                                    gradient: LinearGradient(
                                                      begin:
                                                          Alignment.topCenter,
                                                      end: Alignment
                                                          .bottomCenter,
                                                      colors: [
                                                        Colors.transparent,
                                                        Colors.black.withValues(
                                                            alpha: 0.9),
                                                      ],
                                                    ),
                                                  ),
                                                ),
                                              ),
                                              // Lyrics Overlay on Album Art
                                              _buildAlbumArtLyricsOverlay(
                                                borderRadius: 32.0,
                                                bottomOffset: 130.0,
                                                displayPosMs: displayPosMs,
                                              ),
                                              // Text (Title, Artist)
                                              Positioned(
                                                left: 32,
                                                bottom: 80,
                                                right: 32,
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    AdaptiveMarqueeText(
                                                      text: title,
                                                      style: const TextStyle(
                                                        fontSize: 36,
                                                        fontWeight:
                                                            FontWeight.bold,
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
                                                        fontWeight:
                                                            FontWeight.w600,
                                                        color: Colors.white70,
                                                      ),
                                                      maxLines: 1,
                                                      overflow:
                                                          TextOverflow.ellipsis,
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
                                                  mainAxisAlignment:
                                                      MainAxisAlignment
                                                          .spaceBetween,
                                                  children: [
                                                    Row(
                                                      children: [
                                                        // Like
                                                        ValueListenableBuilder<
                                                            List<LikedSong>>(
                                                          valueListenable:
                                                              LikedSongsService
                                                                  .instance
                                                                  .likedSongsNotifier,
                                                          builder: (context,
                                                              likedSongs, _) {
                                                            final trackId = widget
                                                                    .videoId ??
                                                                widget.getTitle(
                                                                    status
                                                                        .currentIndex);
                                                            final isCurrentlyLiked =
                                                                likedSongs.any((s) =>
                                                                    s.videoId ==
                                                                    trackId);
                                                            return GestureDetector(
                                                              onTap: () async {
                                                                if (trackId
                                                                    .isEmpty) {
                                                                  return;
                                                                }
                                                                if (isCurrentlyLiked) {
                                                                  await LikedSongsService
                                                                      .instance
                                                                      .removeLikedSong(
                                                                          trackId);
                                                                } else {
                                                                  await LikedSongsService
                                                                      .instance
                                                                      .addLikedSong(
                                                                          LikedSong(
                                                                    videoId:
                                                                        trackId,
                                                                    title:
                                                                        title,
                                                                    artist:
                                                                        subtitle,
                                                                    thumbnailUrl: widget.albumArt ==
                                                                            null
                                                                        ? null
                                                                        : trackId,
                                                                    durationSeconds:
                                                                        duration
                                                                            .inSeconds,
                                                                    likedAt:
                                                                        DateTime
                                                                            .now(),
                                                                  ));
                                                                }
                                                              },
                                                              child:
                                                                  CircleAvatar(
                                                                backgroundColor: isCurrentlyLiked
                                                                    ? primaryColor
                                                                    : Colors
                                                                        .white
                                                                        .withValues(
                                                                            alpha:
                                                                                0.2),
                                                                radius: 24,
                                                                child: Icon(
                                                                    isCurrentlyLiked
                                                                        ? Icons
                                                                            .thumb_up
                                                                        : Icons
                                                                            .thumb_up_outlined,
                                                                    color: Colors
                                                                        .white,
                                                                    size: 24),
                                                              ),
                                                            );
                                                          },
                                                        ),
                                                        const SizedBox(
                                                            width: 16),
                                                        // Dislike
                                                        CircleAvatar(
                                                          backgroundColor:
                                                              Colors.white
                                                                  .withValues(
                                                                      alpha:
                                                                          0.2),
                                                          radius: 24,
                                                          child: const Icon(
                                                              Icons
                                                                  .thumb_down_outlined,
                                                              color:
                                                                  Colors.white,
                                                              size: 24),
                                                        ),
                                                      ],
                                                    ),
                                                    Row(
                                                      children: [
                                                        // Queue/Playlist
                                                        GestureDetector(
                                                          onTap: () =>
                                                              _showQueueSheet(
                                                                  context),
                                                          child: CircleAvatar(
                                                            backgroundColor:
                                                                Colors.white
                                                                    .withValues(
                                                                        alpha:
                                                                            0.2),
                                                            radius: 24,
                                                            child: const Icon(
                                                                Icons
                                                                    .playlist_play,
                                                                color: Colors
                                                                    .white,
                                                                size: 24),
                                                          ),
                                                        ),
                                                        const SizedBox(
                                                            width: 16),
                                                        // More options
                                                        IconButton(
                                                          icon: Icon(
                                                            Icons.more_vert,
                                                            color: _isCustomLyricsLoaded
                                                                ? const Color(
                                                                    0xFF137FEC)
                                                                : Colors.white,
                                                          ),
                                                          onPressed: () =>
                                                              _showMoreOptionsMenu(
                                                                  context),
                                                          tooltip:
                                                              'Track Options',
                                                        ),
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
                                                  icon: const Icon(
                                                      Icons.keyboard_arrow_down,
                                                      size: 40,
                                                      color: textLight),
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
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          if (_showLyrics)
                                            Expanded(child: pureLyrics)
                                          else
                                            const Spacer(),

                                          // Action Buttons Row
                                          FittedBox(
                                            fit: BoxFit.scaleDown,
                                            child: Row(
                                              mainAxisAlignment:
                                                  MainAxisAlignment.center,
                                              children: [
                                                _buildActionIcon(
                                                    Icons.graphic_eq, () {
                                                  Navigator.push(
                                                      context,
                                                      MaterialPageRoute(
                                                          builder: (context) =>
                                                              EffectsScreen(
                                                                player: widget
                                                                    .player,
                                                                analyzerEnabled:
                                                                    _isAnalyzerEnabled,
                                                                analyzerType: widget
                                                                    .analyzerType,
                                                                analyzerAutoFit:
                                                                    widget
                                                                        .analyzerAutoFit,
                                                                analyzerShowGrids:
                                                                    widget
                                                                        .analyzerShowGrids,
                                                                outputSampleRate:
                                                                    widget
                                                                        .outputSampleRate,
                                                              )));
                                                }),
                                                _buildActionIcon(
                                                  (_currentPitch - 1.0).abs() >
                                                          0.01
                                                      ? Icons.speed_rounded
                                                      : Icons.speed_outlined,
                                                  () => showPlaybackSpeedModal(
                                                    context,
                                                    widget.player,
                                                    currentPitch: _currentPitch,
                                                    onPitchChanged: (p) =>
                                                        setState(() =>
                                                            _currentPitch = p),
                                                  ),
                                                ),
                                                _buildActionIcon(
                                                    _loopIcon(status.loopMode),
                                                    () {
                                                  final currentMode =
                                                      status.loopMode;
                                                  final nextMode =
                                                      currentMode ==
                                                              LoopMode.off
                                                          ? LoopMode.all
                                                          : (currentMode ==
                                                                  LoopMode.all
                                                              ? LoopMode.one
                                                              : LoopMode.off);
                                                  widget.player
                                                      .setLoopMode(nextMode);
                                                }),
                                                _buildActionIcon(
                                                    status.shuffleEnabled
                                                        ? Icons.shuffle_on
                                                        : Icons.shuffle, () {
                                                  widget.player
                                                      .setShuffleModeEnabled(
                                                          !status
                                                              .shuffleEnabled);
                                                }),
                                                // A-B Repeat button
                                                _buildAbRepeatButton(
                                                  currentPositionMs:
                                                      displayPosMs,
                                                  maxMs: maxMs,
                                                ),
                                              ],
                                            ),
                                          ),
                                          const SizedBox(height: 48),

                                          // Playback Controls
                                          Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            children: [
                                              IconButton(
                                                icon: const Icon(
                                                    Icons.fast_rewind,
                                                    size: 36,
                                                    color: Colors.white54),
                                                onPressed: () {
                                                  widget.player.seekTo(Duration(
                                                      milliseconds:
                                                          (displayPosMs - 10000)
                                                              .toInt()
                                                              .clamp(
                                                                  0,
                                                                  maxMs
                                                                      .toInt())));
                                                },
                                              ),
                                              const SizedBox(width: 16),
                                              IconButton(
                                                icon: const Icon(
                                                    Icons.skip_previous,
                                                    size: 48,
                                                    color: Colors.white),
                                                onPressed: widget
                                                    .player.seekToPrevious,
                                              ),
                                              const SizedBox(width: 24),
                                              GestureDetector(
                                                onTap: status.isPlaying
                                                    ? widget.player.pause
                                                    : widget.player.play,
                                                child: Container(
                                                  width: 96,
                                                  height: 96,
                                                  decoration:
                                                      const BoxDecoration(
                                                    shape: BoxShape.circle,
                                                    color: Colors.black,
                                                  ),
                                                  child: Icon(
                                                    status.isPlaying
                                                        ? Icons.pause
                                                        : Icons.play_arrow,
                                                    size: 56,
                                                    color: Colors.white,
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 24),
                                              IconButton(
                                                icon: const Icon(
                                                    Icons.skip_next,
                                                    size: 48,
                                                    color: Colors.white),
                                                onPressed:
                                                    widget.player.seekToNext,
                                              ),
                                              const SizedBox(width: 16),
                                              IconButton(
                                                icon: const Icon(
                                                    Icons.fast_forward,
                                                    size: 36,
                                                    color: Colors.white54),
                                                onPressed: () {
                                                  widget.player.seekTo(Duration(
                                                      milliseconds:
                                                          (displayPosMs + 10000)
                                                              .toInt()
                                                              .clamp(
                                                                  0,
                                                                  maxMs
                                                                      .toInt())));
                                                },
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 40),
                                          // Progress Bar & Info Badge
                                          Column(
                                            children: [
                                              // A-B region labels
                                              if (_abRepeatState >= 1)
                                                _buildAbRegionLabels(
                                                    maxMs: maxMs),
                                              LayoutBuilder(
                                                builder:
                                                    (context, constraints) {
                                                  return _buildSeekBarWidget(
                                                    displayPosMs: displayPosMs,
                                                    maxMs: maxMs,
                                                    totalWidth:
                                                        constraints.maxWidth,
                                                    isMobile: false,
                                                    primaryColor: primaryColor,
                                                  );
                                                },
                                              ),
                                              const SizedBox(height: 8),
                                              Row(
                                                mainAxisAlignment:
                                                    MainAxisAlignment
                                                        .spaceBetween,
                                                children: [
                                                  Text(
                                                    _fmt(Duration(
                                                        milliseconds:
                                                            displayPosMs
                                                                .toInt())),
                                                    style: const TextStyle(
                                                        fontSize: 16,
                                                        color: Colors.white,
                                                        fontWeight:
                                                            FontWeight.bold),
                                                  ),
                                                  // Audio Info Badge
                                                  GestureDetector(
                                                    onTap: () =>
                                                        showAudioEngineDiagnosticPanel(
                                                            context,
                                                            widget.player),
                                                    child: Container(
                                                      padding: const EdgeInsets
                                                          .symmetric(
                                                          horizontal: 14,
                                                          vertical: 5),
                                                      decoration: BoxDecoration(
                                                        color: primaryColor
                                                            .withValues(
                                                                alpha: 0.15),
                                                        borderRadius:
                                                            BorderRadius
                                                                .circular(20),
                                                        border: Border.all(
                                                          color: primaryColor
                                                              .withValues(
                                                                  alpha: 0.35),
                                                          width: 1,
                                                        ),
                                                      ),
                                                      child: Row(
                                                        mainAxisSize:
                                                            MainAxisSize.min,
                                                        children: [
                                                          Icon(
                                                            Icons
                                                                .equalizer_rounded,
                                                            size: 13,
                                                            color: primaryColor,
                                                          ),
                                                          const SizedBox(
                                                              width: 6),
                                                          Text(
                                                            _buildAudioInfoBadgeText(
                                                                trackPosition),
                                                            style: const TextStyle(
                                                                letterSpacing:
                                                                    0.5),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                  ),
                                                  Text(
                                                    _fmt(duration),
                                                    style: const TextStyle(
                                                        fontSize: 16,
                                                        color: Colors.white,
                                                        fontWeight:
                                                            FontWeight.bold),
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
                                    icon: const Icon(Icons.keyboard_arrow_down,
                                        size: 32, color: textLight),
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
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 16.0),
                                child: Center(
                                  child: AspectRatio(
                                    aspectRatio: 1.0,
                                    child: Stack(
                                      children: [
                                        // Album Art Image
                                        Positioned.fill(
                                          child: Container(
                                            decoration: BoxDecoration(
                                              borderRadius:
                                                  BorderRadius.circular(24.0),
                                              color: surfaceColor,
                                            ),
                                            child: ClipRRect(
                                              borderRadius:
                                                  BorderRadius.circular(24.0),
                                              child: (widget.albumArt != null &&
                                                      widget
                                                          .albumArt!.isNotEmpty)
                                                  ? Container(
                                                      decoration: BoxDecoration(
                                                        image: DecorationImage(
                                                          image: MemoryImage(
                                                              widget.albumArt!),
                                                          fit: BoxFit.cover,
                                                        ),
                                                      ),
                                                    )
                                                  : RotationTransition(
                                                      turns:
                                                          _rotationController,
                                                      child: Container(
                                                        color: surfaceColor,
                                                        padding:
                                                            const EdgeInsets
                                                                .all(24.0),
                                                        child: Image.asset(
                                                          'assets/icon/splash.png',
                                                          fit: BoxFit.contain,
                                                        ),
                                                      ),
                                                    ),
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
                                              borderRadius:
                                                  const BorderRadius.vertical(
                                                      bottom: Radius.circular(
                                                          24.0)),
                                              gradient: LinearGradient(
                                                begin: Alignment.topCenter,
                                                end: Alignment.bottomCenter,
                                                colors: [
                                                  Colors.transparent,
                                                  Colors.black
                                                      .withValues(alpha: 0.8),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                        // Lyrics Overlay on Album Art
                                        _buildAlbumArtLyricsOverlay(
                                          borderRadius: 24.0,
                                          bottomOffset: 100.0,
                                          displayPosMs: displayPosMs,
                                        ),
                                        // Text (Title, Artist)
                                        Positioned(
                                          left: 16,
                                          bottom: 60,
                                          right: 16,
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
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
                                            mainAxisAlignment:
                                                MainAxisAlignment.spaceBetween,
                                            children: [
                                              Row(
                                                children: [
                                                  // Like
                                                  ValueListenableBuilder<
                                                      List<LikedSong>>(
                                                    valueListenable:
                                                        LikedSongsService
                                                            .instance
                                                            .likedSongsNotifier,
                                                    builder: (context,
                                                        likedSongs, _) {
                                                      final trackId = widget
                                                              .videoId ??
                                                          widget.getTitle(status
                                                              .currentIndex);
                                                      final isCurrentlyLiked =
                                                          likedSongs.any((s) =>
                                                              s.videoId ==
                                                              trackId);
                                                      return GestureDetector(
                                                        onTap: () async {
                                                          if (trackId.isEmpty) {
                                                            return;
                                                          }
                                                          if (isCurrentlyLiked) {
                                                            await LikedSongsService
                                                                .instance
                                                                .removeLikedSong(
                                                                    trackId);
                                                          } else {
                                                            await LikedSongsService
                                                                .instance
                                                                .addLikedSong(
                                                                    LikedSong(
                                                              videoId: trackId,
                                                              title: title,
                                                              artist: subtitle,
                                                              thumbnailUrl:
                                                                  widget.albumArt ==
                                                                          null
                                                                      ? null
                                                                      : trackId,
                                                              durationSeconds:
                                                                  duration
                                                                      .inSeconds,
                                                              likedAt: DateTime
                                                                  .now(),
                                                            ));
                                                          }
                                                        },
                                                        child: CircleAvatar(
                                                          backgroundColor:
                                                              isCurrentlyLiked
                                                                  ? primaryColor
                                                                  : Colors.white
                                                                      .withValues(
                                                                          alpha:
                                                                              0.2),
                                                          radius: 18,
                                                          child: Icon(
                                                              isCurrentlyLiked
                                                                  ? Icons
                                                                      .thumb_up
                                                                  : Icons
                                                                      .thumb_up_outlined,
                                                              color:
                                                                  Colors.white,
                                                              size: 18),
                                                        ),
                                                      );
                                                    },
                                                  ),
                                                  const SizedBox(width: 8),
                                                  // Dislike
                                                  CircleAvatar(
                                                    backgroundColor: Colors
                                                        .white
                                                        .withValues(alpha: 0.2),
                                                    radius: 18,
                                                    child: const Icon(
                                                        Icons
                                                            .thumb_down_outlined,
                                                        color: Colors.white,
                                                        size: 18),
                                                  ),
                                                ],
                                              ),
                                              Row(
                                                children: [
                                                  // Queue/Playlist
                                                  GestureDetector(
                                                    onTap: () =>
                                                        _showQueueSheet(
                                                            context),
                                                    child: CircleAvatar(
                                                      backgroundColor: Colors
                                                          .white
                                                          .withValues(
                                                              alpha: 0.2),
                                                      radius: 18,
                                                      child: const Icon(
                                                          Icons.playlist_play,
                                                          color: Colors.white,
                                                          size: 18),
                                                    ),
                                                  ),
                                                  const SizedBox(width: 8),
                                                  // More options
                                                  IconButton(
                                                    icon: const Icon(
                                                        Icons.more_vert,
                                                        color: Colors.white),
                                                    onPressed: () =>
                                                        _showMoreOptionsMenu(
                                                            context),
                                                    tooltip: 'Song Info & Tags',
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),

                            const SizedBox(height: 32),

                            // Playback Controls
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.fast_rewind,
                                      size: 32, color: Colors.white54),
                                  onPressed: () {
                                    widget.player.seekTo(Duration(
                                        milliseconds: (displayPosMs - 10000)
                                            .toInt()
                                            .clamp(0, maxMs.toInt())));
                                  },
                                ),
                                const SizedBox(width: 8),
                                IconButton(
                                  icon: const Icon(Icons.skip_previous,
                                      size: 40, color: Colors.white),
                                  onPressed: widget.player.seekToPrevious,
                                ),
                                const SizedBox(width: 16),
                                GestureDetector(
                                  onTap: status.isPlaying
                                      ? widget.player.pause
                                      : widget.player.play,
                                  child: Container(
                                    width: 80,
                                    height: 80,
                                    decoration: const BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: Colors.black,
                                    ),
                                    child: Icon(
                                      status.isPlaying
                                          ? Icons.pause
                                          : Icons.play_arrow,
                                      size: 48,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 16),
                                IconButton(
                                  icon: const Icon(Icons.skip_next,
                                      size: 40, color: Colors.white),
                                  onPressed: widget.player.seekToNext,
                                ),
                                const SizedBox(width: 8),
                                IconButton(
                                  icon: const Icon(Icons.fast_forward,
                                      size: 32, color: Colors.white54),
                                  onPressed: () {
                                    widget.player.seekTo(Duration(
                                        milliseconds: (displayPosMs + 10000)
                                            .toInt()
                                            .clamp(0, maxMs.toInt())));
                                  },
                                ),
                              ],
                            ),

                            const SizedBox(height: 24),

                            // Progress Bar & Info Badge
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 24.0),
                              child: Column(
                                children: [
                                  // A-B region labels
                                  if (_abRepeatState >= 1)
                                    _buildAbRegionLabels(maxMs: maxMs),
                                  LayoutBuilder(
                                    builder: (context, constraints) {
                                      return _buildSeekBarWidget(
                                        displayPosMs: displayPosMs,
                                        maxMs: maxMs,
                                        totalWidth: constraints.maxWidth,
                                        isMobile: true,
                                        primaryColor: primaryColor,
                                      );
                                    },
                                  ),
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        _fmt(Duration(
                                            milliseconds:
                                                displayPosMs.toInt())),
                                        style: const TextStyle(
                                            fontSize: 12,
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold),
                                      ),
                                      // Audio Info Badge
                                      Flexible(
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 6.0),
                                          child: GestureDetector(
                                            onTap: () =>
                                                showAudioEngineDiagnosticPanel(
                                                    context, widget.player),
                                            child: Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 10,
                                                      vertical: 4),
                                              decoration: BoxDecoration(
                                                color: primaryColor
                                                    .withValues(alpha: 0.15),
                                                borderRadius:
                                                    BorderRadius.circular(16),
                                                border: Border.all(
                                                  color: primaryColor
                                                      .withValues(alpha: 0.35),
                                                  width: 1,
                                                ),
                                              ),
                                              child: FittedBox(
                                                fit: BoxFit.scaleDown,
                                                child: Row(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: [
                                                    Icon(
                                                        Icons.equalizer_rounded,
                                                        size: 11,
                                                        color: primaryColor),
                                                    const SizedBox(width: 4),
                                                    Text(
                                                      _buildAudioInfoBadgeText(
                                                          trackPosition),
                                                      style: const TextStyle(
                                                          fontSize: 10,
                                                          color: Colors.white,
                                                          fontWeight:
                                                              FontWeight.w600,
                                                          letterSpacing: 0.5),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                      Text(
                                        _fmt(duration),
                                        style: const TextStyle(
                                            fontSize: 12,
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),

                            const SizedBox(height: 32),

                            // Action Buttons Row (Eq, Timer, Repeat, Shuffle)
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 16.0),
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceEvenly,
                                  children: [
                                    _buildActionIcon(Icons.graphic_eq, () {
                                      Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                              builder: (context) =>
                                                  EffectsScreen(
                                                    player: widget.player,
                                                    analyzerEnabled:
                                                        _isAnalyzerEnabled,
                                                    analyzerType:
                                                        widget.analyzerType,
                                                    analyzerAutoFit:
                                                        widget.analyzerAutoFit,
                                                    analyzerShowGrids: widget
                                                        .analyzerShowGrids,
                                                    outputSampleRate:
                                                        widget.outputSampleRate,
                                                  )));
                                    }),
                                    _buildActionIcon(
                                      (_currentPitch - 1.0).abs() > 0.01
                                          ? Icons.speed_rounded
                                          : Icons.speed_outlined,
                                      () => showPlaybackSpeedModal(
                                        context,
                                        widget.player,
                                        currentPitch: _currentPitch,
                                        onPitchChanged: (p) =>
                                            setState(() => _currentPitch = p),
                                      ),
                                    ),
                                    _buildActionIcon(_loopIcon(status.loopMode),
                                        () {
                                      final currentMode = status.loopMode;
                                      final nextMode =
                                          currentMode == LoopMode.off
                                              ? LoopMode.all
                                              : (currentMode == LoopMode.all
                                                  ? LoopMode.one
                                                  : LoopMode.off);
                                      widget.player.setLoopMode(nextMode);
                                    }),
                                    _buildActionIcon(
                                        status.shuffleEnabled
                                            ? Icons.shuffle_on
                                            : Icons.shuffle, () {
                                      widget.player.setShuffleModeEnabled(
                                          !status.shuffleEnabled);
                                    }),
                                    // A-B Repeat button
                                    _buildAbRepeatButton(
                                      currentPositionMs: displayPosMs,
                                      maxMs: maxMs,
                                    ),
                                  ],
                                ),
                              ),
                            ),

                            const SizedBox(height: 48),
                          ],
                        );
                      }

                      final bottomPadding =
                          MediaQuery.of(context).padding.bottom;

                      return Stack(
                        children: [
                          Align(
                            alignment: Alignment.topCenter,
                            child: ConstrainedBox(
                              constraints: BoxConstraints(
                                  maxWidth:
                                      isDesktop ? double.infinity : 600.0),
                              child: SafeArea(
                                child: content,
                              ),
                            ),
                          ),
                          Positioned(
                            bottom: bottomPadding + 6,
                            left: 0,
                            right: 0,
                            child: Center(
                              child: GestureDetector(
                                onTap: () => _showQueueSheet(context),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 14, vertical: 5),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                      color:
                                          Colors.white.withValues(alpha: 0.15),
                                      width: 1,
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: const [
                                      Icon(Icons.keyboard_arrow_up,
                                          size: 16, color: Colors.white70),
                                      SizedBox(width: 4),
                                      Text(
                                        'UP NEXT',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          letterSpacing: 1.0,
                                          color: Colors.white70,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      );
                    }),
                    Align(
                      alignment: Alignment.topCenter,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                            maxWidth: MediaQuery.of(context).size.width >= 800
                                ? double.infinity
                                : 600.0),
                        child: SafeArea(
                          child: QueueScreen(
                            queue: widget.queue,
                            videoId: widget.videoId,
                            albumArt: widget.albumArt,
                            onPlayQueueIndex: widget.onPlayQueueIndex,
                            onReorderQueue: widget.onReorderQueue,
                            statusNotifier: widget.statusNotifier,
                            onClose: () {
                              if (_pageController.hasClients) {
                                _pageController.animateToPage(
                                  0,
                                  duration: const Duration(milliseconds: 350),
                                  curve: Curves.easeOutCubic,
                                );
                              }
                            },
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildActionIcon(IconData icon, VoidCallback onTap,
      [bool isActive = false]) {
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

  // ignore: unused_element
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
            color: primaryColor.withValues(alpha: 0.7 + (visualData[i] * 0.3)),
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
    if (_pageController.hasClients) {
      _pageController.animateToPage(
        1,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
      );
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // A-B Repeat helpers
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildAbRepeatButton({
    required double currentPositionMs,
    required double maxMs,
  }) {
    String tooltip;

    switch (_abRepeatState) {
      case 1:
        tooltip = 'Set Point B';
        break;
      case 2:
        tooltip = 'Clear A-B Repeat';
        break;
      default:
        tooltip = 'Set Point A';
    }

    return GestureDetector(
      onLongPress:
          _abRepeatState == 2 ? () => _showAbRepeatSheet(context, maxMs) : null,
      child: Tooltip(
        message: tooltip,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () {
            setState(() {
              if (_abRepeatState == 0) {
                // Set Point A at current position
                _abPointAMs = currentPositionMs;
                _abRepeatState = 1;
              } else if (_abRepeatState == 1) {
                // Set Point B and activate loop
                final b = currentPositionMs;
                final a = _abPointAMs!;
                if (b > a + 500) {
                  // Require at least 500ms gap
                  _abPointBMs = b;
                  _abRepeatState = 2;
                  widget.player.setAbRepeat(
                    enabled: true,
                    startSeconds: a / 1000.0,
                    endSeconds: b / 1000.0,
                  );
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Row(
                        children: [
                          Icon(Icons.repeat_on_rounded,
                              color:
                                  AppThemeService.instance.currentData.primary,
                              size: 18),
                          const SizedBox(width: 8),
                          Text(
                            'A-B Loop Active: ${_fmt(Duration(milliseconds: a.toInt()))} ⇄ ${_fmt(Duration(milliseconds: b.toInt()))}',
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      backgroundColor: const Color(0xFF1E2D3D),
                      duration: const Duration(seconds: 2),
                    ),
                  );
                } else {
                  // B too close to A — reset
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content:
                          Text('Point B must be at least 0.5s after Point A'),
                      backgroundColor: Color(0xFF1E2D3D),
                      duration: Duration(seconds: 2),
                    ),
                  );
                }
              } else {
                // Clear A-B repeat
                _abRepeatState = 0;
                _abPointAMs = null;
                _abPointBMs = null;
                widget.player.setAbRepeat(
                    enabled: false, startSeconds: 0, endSeconds: 0);
              }
            });
          },
          child: _AbRepeatCustomIcon(state: _abRepeatState),
        ),
      ),
    );
  }

  Widget _buildAbRegionLabels({required double maxMs}) {
    if (_abPointAMs == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 2.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Point A label
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xFFFFA726).withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: const Color(0xFFFFA726), width: 1),
            ),
            child: Text(
              'A ${_fmt(Duration(milliseconds: _abPointAMs!.toInt()))}',
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: Color(0xFFFFA726),
              ),
            ),
          ),
          if (_abRepeatState == 2 && _abPointBMs != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AppThemeService.instance.currentData.primary
                    .withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                    color: AppThemeService.instance.currentData.primary,
                    width: 1),
              ),
              child: Text(
                'B ${_fmt(Duration(milliseconds: _abPointBMs!.toInt()))}',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: AppThemeService.instance.currentData.primary,
                ),
              ),
            )
          else
            const Text(
              '← tap button to set B',
              style: TextStyle(fontSize: 10, color: Colors.white38),
            ),
        ],
      ),
    );
  }

  void _showAbRepeatSheet(BuildContext context, double maxMs) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF18232E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        double localA = _abPointAMs ?? 0;
        double localB = _abPointBMs ?? maxMs;
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            void apply() {
              setState(() {
                _abPointAMs = localA;
                _abPointBMs = localB;
              });
              widget.player.setAbRepeat(
                enabled: true,
                startSeconds: localA / 1000.0,
                endSeconds: localB / 1000.0,
              );
            }

            return Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Text(
                    'A-B REPEAT FINE-TUNE',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                      color: AppThemeService.instance.currentData.primary,
                    ),
                  ),
                  const SizedBox(height: 20),
                  // Point A
                  Row(
                    children: [
                      const Text('Point A',
                          style: TextStyle(
                              color: Color(0xFFFFA726),
                              fontWeight: FontWeight.bold)),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.remove, color: Colors.white70),
                        onPressed: () {
                          setSheetState(() {
                            localA = (localA - 100).clamp(0, localB - 500);
                          });
                          apply();
                        },
                        tooltip: '-100ms',
                      ),
                      Text(_fmt(Duration(milliseconds: localA.toInt())),
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold)),
                      IconButton(
                        icon: const Icon(Icons.add, color: Colors.white70),
                        onPressed: () {
                          setSheetState(() {
                            localA = (localA + 100).clamp(0, localB - 500);
                          });
                          apply();
                        },
                        tooltip: '+100ms',
                      ),
                    ],
                  ),
                  // Point B
                  Row(
                    children: [
                      Text('Point B',
                          style: TextStyle(
                              color:
                                  AppThemeService.instance.currentData.primary,
                              fontWeight: FontWeight.bold)),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.remove, color: Colors.white70),
                        onPressed: () {
                          setSheetState(() {
                            localB = (localB - 100).clamp(localA + 500, maxMs);
                          });
                          apply();
                        },
                        tooltip: '-100ms',
                      ),
                      Text(_fmt(Duration(milliseconds: localB.toInt())),
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold)),
                      IconButton(
                        icon: const Icon(Icons.add, color: Colors.white70),
                        onPressed: () {
                          setSheetState(() {
                            localB = (localB + 100).clamp(localA + 500, maxMs);
                          });
                          apply();
                        },
                        tooltip: '+100ms',
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: Colors.white24),
                            foregroundColor: Colors.white70,
                          ),
                          icon: const Icon(Icons.close, size: 16),
                          label: const Text('Clear A-B'),
                          onPressed: () {
                            setState(() {
                              _abRepeatState = 0;
                              _abPointAMs = null;
                              _abPointBMs = null;
                            });
                            widget.player.setAbRepeat(
                                enabled: false, startSeconds: 0, endSeconds: 0);
                            Navigator.pop(ctx);
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildSeekBarWidget({
    required double displayPosMs,
    required double maxMs,
    required double totalWidth,
    required bool isMobile,
    required Color primaryColor,
  }) {
    if (_useWaveformSeekBar &&
        _currentWaveformPeaks != null &&
        _currentWaveformPeaks!.isNotEmpty) {
      return WaveformSeekBarWidget(
        peaks: _currentWaveformPeaks!,
        displayPosMs: displayPosMs,
        maxMs: maxMs,
        abRepeatState: _abRepeatState,
        abPointAMs: _abPointAMs,
        abPointBMs: _abPointBMs,
        height: isMobile ? 42.0 : 48.0,
        activeColor: primaryColor,
        onDragStateChanged: (dragging) {
          setState(() {
            _isDragging = dragging;
          });
        },
        onDragUpdate: (v) {
          setState(() {
            _dragPositionMs = v;
          });
        },
        onSeekEnd: (v) {
          _seekTimeoutTimer?.cancel();
          setState(() {
            _isDragging = false;
            _pendingSeekMs = v;
          });
          widget.player.seekTo(Duration(milliseconds: v.toInt()));
          _seekTimeoutTimer = Timer(const Duration(seconds: 45), () {
            if (mounted) setState(() => _pendingSeekMs = null);
          });
        },
      );
    }

    return Stack(
      children: [
        if (_abRepeatState >= 1 && _abPointAMs != null)
          Positioned.fill(
            child: ClipRect(
              child: _AbRegionPainter(
                abRepeatState: _abRepeatState,
                pointAMs: _abPointAMs!,
                pointBMs: _abPointBMs,
                maxMs: maxMs,
                totalWidth: totalWidth,
              ),
            ),
          ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: isMobile ? 4.0 : 6.0,
            activeTrackColor: Colors.white54,
            inactiveTrackColor: Colors.white12,
            thumbColor: Colors.white,
            overlayColor: Colors.white24,
            thumbShape:
                RoundSliderThumbShape(enabledThumbRadius: isMobile ? 6.0 : 8.0),
            overlayShape:
                RoundSliderOverlayShape(overlayRadius: isMobile ? 14.0 : 16.0),
          ),
          child: Slider(
            value: displayPosMs,
            min: 0.0,
            max: maxMs,
            onChangeStart: (v) {
              setState(() {
                _isDragging = true;
                _dragPositionMs = v;
              });
            },
            onChanged: (v) {
              setState(() => _dragPositionMs = v);
            },
            onChangeEnd: (v) {
              _seekTimeoutTimer?.cancel();
              setState(() {
                _isDragging = false;
                _pendingSeekMs = v;
              });
              widget.player.seekTo(Duration(milliseconds: v.toInt()));
              _seekTimeoutTimer = Timer(const Duration(seconds: 45), () {
                if (mounted) setState(() => _pendingSeekMs = null);
              });
            },
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Custom painter that draws the A-B highlight region under the seekbar track
// ─────────────────────────────────────────────────────────────────────────────
class _AbRegionPainter extends StatelessWidget {
  final int abRepeatState;
  final double pointAMs;
  final double? pointBMs;
  final double maxMs;
  final double totalWidth;

  const _AbRegionPainter({
    required this.abRepeatState,
    required this.pointAMs,
    this.pointBMs,
    required this.maxMs,
    required this.totalWidth,
  });

  @override
  Widget build(BuildContext context) {
    if (maxMs <= 0) return const SizedBox.shrink();
    const double thumbRadius = 8.0;
    const double horizontalPadding =
        24.0; // matches Flutter Slider internal padding
    final double usable = totalWidth - horizontalPadding * 2 - thumbRadius * 2;
    final double left =
        horizontalPadding + thumbRadius + (pointAMs / maxMs) * usable;
    final double? right = (abRepeatState == 2 && pointBMs != null)
        ? (horizontalPadding + thumbRadius + (pointBMs! / maxMs) * usable)
        : null;
    return CustomPaint(
      painter: _AbHighlightCustomPainter(
        abRepeatState: abRepeatState,
        left: left,
        right: right,
      ),
    );
  }
}

class _AbHighlightCustomPainter extends CustomPainter {
  final int abRepeatState;
  final double left;
  final double? right;

  const _AbHighlightCustomPainter({
    required this.abRepeatState,
    required this.left,
    this.right,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (abRepeatState == 2 && right != null) {
      // Highlight band
      final paint = Paint()
        ..color =
            AppThemeService.instance.currentData.primary.withValues(alpha: 0.25)
        ..style = PaintingStyle.fill;
      canvas.drawRect(Rect.fromLTRB(left, 0, right!, size.height), paint);

      // Pin B
      final pinBPaint = Paint()
        ..color = AppThemeService.instance.currentData.primary
        ..style = PaintingStyle.fill;
      canvas.drawRect(
          Rect.fromLTRB(right! - 1.5, 0, right! + 1.5, size.height), pinBPaint);
    }

    // Pin A
    final pinPaint = Paint()
      ..color = const Color(0xFFFFA726)
      ..style = PaintingStyle.fill;
    canvas.drawRect(
        Rect.fromLTRB(left - 1.5, 0, left + 1.5, size.height), pinPaint);
  }

  @override
  bool shouldRepaint(_AbHighlightCustomPainter old) =>
      old.abRepeatState != abRepeatState ||
      old.left != left ||
      old.right != right;
}

// ─────────────────────────────────────────────────────────────────────────────
// Custom stylized A-B Repeat icon badge
// ─────────────────────────────────────────────────────────────────────────────
class _AbRepeatCustomIcon extends StatelessWidget {
  final int state; // 0 = off, 1 = point A set, 2 = active loop

  const _AbRepeatCustomIcon({required this.state});

  @override
  Widget build(BuildContext context) {
    Color borderClr;
    Color bgClr;
    Color textClr;
    String label;
    IconData iconData;

    switch (state) {
      case 1:
        borderClr = const Color(0xFFFFA726);
        bgClr = const Color(0xFFFFA726).withValues(alpha: 0.22);
        textClr = const Color(0xFFFFA726);
        label = 'A →';
        iconData = Icons.repeat_one_rounded;
        break;
      case 2:
        borderClr = AppThemeService.instance.currentData.primary;
        bgClr = AppThemeService.instance.currentData.primary
            .withValues(alpha: 0.25);
        textClr = const Color(0xFF38BDF8);
        label = 'A-B';
        iconData = Icons.repeat_on_rounded;
        break;
      default:
        borderClr = Colors.white24;
        bgClr = Colors.white10;
        textClr = Colors.white70;
        label = 'A-B';
        iconData = Icons.repeat_rounded;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: bgClr,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: state > 0 ? borderClr : Colors.transparent,
          width: 1.2,
        ),
        boxShadow: state > 0
            ? [
                BoxShadow(
                  color: borderClr.withValues(alpha: 0.35),
                  blurRadius: 8,
                  spreadRadius: 0,
                ),
              ]
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            iconData,
            size: 20,
            color: textClr,
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.8,
              color: textClr,
            ),
          ),
        ],
      ),
    );
  }
}
