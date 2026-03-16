import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:dart_ytmusic_api/dart_ytmusic_api.dart'; // Added
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:metadata_god/metadata_god.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:sautiflow/sautiflow.dart';

import 'album_detail_screen.dart'; // For TrackInfo
import 'eq_screen.dart';
import 'home_screen.dart';
import 'isolate_player.dart';
import 'library_screen.dart';
import 'mini_player.dart';
import 'models/liked_song.dart';
import 'models/recently_played_track.dart';
import 'now_playing_screen.dart';
import 'recently_played_screen.dart';
import 'search_screen.dart';
import 'services/app_state_service.dart';
import 'services/recently_played_service.dart';
import 'settings_screen.dart';
import 'shimmer_mini_player.dart';
import 'streaming_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MetadataGod.initialize();
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    debugPrint('[flutter-error] ${details.exceptionAsString()}');
    if (details.stack != null) {
      debugPrint('${details.stack}');
    }
  };

  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('[platform-error] $error');
    debugPrint('$stack');
    return false;
  };

  runApp(const DemoApp());
}

class DemoApp extends StatelessWidget {
  const DemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SautiPlay',
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF101922),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF137fec),
          surface: Color(0xFF1C252E),
          onSurface: Colors.white,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF101922),
          elevation: 0,
          scrolledUnderElevation: 0, // prevents color change on scroll
        ),
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: const Color(0xFF101922),
          indicatorColor: const Color(0xFF137fec).withValues(alpha: 0.3),
          labelTextStyle: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return const TextStyle(
                  color: Color(0xFF137fec),
                  fontSize: 12,
                  fontWeight: FontWeight.w600);
            }
            return TextStyle(
                color: Colors.white.withValues(alpha: 0.7), fontSize: 12);
          }),
          iconTheme: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return const IconThemeData(color: Color(0xFF137fec));
            }
            return IconThemeData(color: Colors.white.withValues(alpha: 0.7));
          }),
        ),
        bottomSheetTheme: const BottomSheetThemeData(
          backgroundColor: Color(0xFF1C252E),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
        ),
      ),
      home: const PlayerShell(),
    );
  }
}

enum EqScreenMode {
  multibandEq('Enable Multiband EQ'),
  mixEq('Enable Mix EQ');

  const EqScreenMode(this.label);
  final String label;
}

class TrackMetadata {
  final String artist;
  final Uint8List? albumArt;
  const TrackMetadata(this.artist, this.albumArt);
}

class PlayerShell extends StatefulWidget {
  const PlayerShell({super.key});

  @override
  State<PlayerShell> createState() => _PlayerShellState();
}

class _PlayerShellState extends State<PlayerShell> {
  final IsolateAudioPlayer _player = IsolateAudioPlayer();

  final ValueNotifier<PlayerStatus> _status = ValueNotifier(
    const PlayerStatus(
      positionSeconds: 0,
      durationSeconds: 0,
      isPlaying: false,
      currentIndex: -1,
      playlistCount: 0,
      shuffleEnabled: false,
      loopMode: LoopMode.off,
    ),
  );
  final ValueNotifier<TrackMetadata> _metadata = ValueNotifier(
    const TrackMetadata('Unknown Artist', null),
  );

  final List<AudioSource> _playlist = <AudioSource>[];
  final List<TrackInfo> _currentUiQueue = <TrackInfo>[];
  final List<String> _logs = <String>[];
  final ValueNotifier<int> _logUpdateCounter = ValueNotifier(0);
  int _tabIndex = 0;

  // Metadata mapping for online tracks stored in local temporary files
  final Map<Uri, TrackInfo> _onlineTrackMetadata = {};
  final Map<String, Uint8List> _thumbnailCache = {};

  bool _nativeNetworkStreamingSupported = false;
  bool _allowInvalidTlsForDownloads = false;
  int _lastPublishedNowPlayingIndex = -1;
  bool _isLoading = false; // Added loading state for miniplayer

  final List<double> _eqFrequencies = const [
    31.25,
    62.5,
    125,
    250,
    500,
    1000,
    2000,
    4000,
    8000,
    16000
  ];

  AudioFormat _outputFormat = AudioFormat.f32;
  int _outputSampleRate = 0; // 0=Native
  int _outputChannels = 2; // Stereo
  bool _crossfadeEnabled = false;
  int _crossfadeDurationMs = 250;

  bool _analyzerEnabled = false;
  String _analyzerType = 'area';
  int _analyzerSampleSize = 1024;

  @override
  void initState() {
    super.initState();
    // Initialize the engine with defaults
    _player.init(enableSystemAudio: true);

    // Initialize the multiband EQ (safe to call even if unnecessary, but good practice)
    _player.initMultibandEq(_eqFrequencies);
    _nativeNetworkStreamingSupported = _player.isNetworkStreamingSupported();
    _logs.insert(
      0,
      _nativeNetworkStreamingSupported
          ? '[init] Native URL byte-streaming: enabled'
          : '[init] Native URL byte-streaming: disabled (download fallback for URLs)',
    );
    final initErr = _player.getLastError();
    if (initErr.isNotEmpty) {
      _logs.insert(0, '[init] $initErr');
    }
    _player.statusStream.listen((s) {
      // Save position periodically (every ~5s)
      if (s.isPlaying && (s.positionSeconds % 5 == 0)) {
        AppStateService.instance.saveQueue(
          tracks: _currentUiQueue.map((t) => t.toJson()).toList(),
          index: s.currentIndex,
          positionMs: (s.positionSeconds * 1000).toInt(),
        );
      }

      _status.value = s;
      _publishNowPlayingFromStatus(s);
    });
    _player.logStream.listen((line) {
      _logs.insert(0, '[${DateTime.now().toIso8601String()}] $line');
      if (_logs.length > 200) {
        _logs.removeRange(200, _logs.length);
      }
      _logUpdateCounter.value++;
    });

    if (Platform.isAndroid) {
      unawaited(_ensureNotificationPermission());
    }

    // Load persisted app state (settings, queue, etc.)
    _loadAppState();
  }

  Future<void> _loadAppState() async {
    final engine = await AppStateService.instance.loadEngineSettings();

    setState(() {
      _outputFormat = AudioFormat.values[engine.outputFormatIndex];
      _outputSampleRate = engine.sampleRate;
      _outputChannels = engine.channels;
      _crossfadeEnabled = engine.crossfadeEnabled;
      _crossfadeDurationMs = engine.crossfadeMs;
      _analyzerEnabled = engine.analyzerEnabled;
      _analyzerType = engine.analyzerType;
      _analyzerSampleSize = engine.analyzerSampleSize;
      _allowInvalidTlsForDownloads = engine.allowInvalidTls;
    });

    // Apply basic engine settings
    _player.setCrossfadeEnabled(_crossfadeEnabled);
    _player.setCrossfadeDurationMs(_crossfadeDurationMs);
    _player.setAnalyzerEnabled(_analyzerEnabled);
    _player.configureAnalyzer(frameSize: _analyzerSampleSize);

    // Load and restore queue
    final queueData = await AppStateService.instance.loadQueue();
    if (queueData.tracks.isNotEmpty) {
      _logs.insert(0,
          '[init] Restoring saved queue (${queueData.tracks.length} tracks)...');
      final tracks =
          queueData.tracks.map((t) => TrackInfo.fromJson(t)).toList();

      // Perform restoration - similar to _playOnlineTracks but stay paused
      final sources = <AudioSource>[];
      for (final t in tracks) {
        final uri = Uri.parse(
            t.videoId.startsWith('http') ? t.videoId : 'file://${t.videoId}');
        final src = await _materializeSource(uri);
        if (src != null) {
          sources.add(src);
          _onlineTrackMetadata[src.uri] = t;
        }
      }

      if (sources.isNotEmpty) {
        setState(() {
          _currentUiQueue.clear();
          _currentUiQueue.addAll(tracks);
          _playlist.clear();
          _playlist.addAll(sources);
        });

        int initialIndex = queueData.index;
        if (initialIndex < 0 || initialIndex >= sources.length) {
          initialIndex = 0;
        }

        _player.setAudioSources(
          _playlist,
          initialIndex: initialIndex,
          initialPosition: Duration(milliseconds: queueData.positionMs),
          useLazyPreparation: true,
        );

        _logs.insert(0,
            '[init] Queue restored at index $initialIndex position ${queueData.positionMs}ms');
      }
    }
  }

  void _saveQueue() {
    AppStateService.instance.saveQueue(
      tracks: _currentUiQueue.map((t) => t.toJson()).toList(),
      index: _status.value.currentIndex,
      positionMs: (_status.value.positionSeconds * 1000).toInt(),
    );
  }

  void _saveEngineSettings() {
    AppStateService.instance.saveEngineSettings(
      outputFormatIndex: _outputFormat.index,
      sampleRate: _outputSampleRate,
      channels: _outputChannels,
      crossfadeEnabled: _crossfadeEnabled,
      crossfadeMs: _crossfadeDurationMs,
      analyzerEnabled: _analyzerEnabled,
      analyzerType: _analyzerType,
      analyzerSampleSize: _analyzerSampleSize,
      allowInvalidTls: _allowInvalidTlsForDownloads,
    );
  }

  @override
  void dispose() {
    _status.dispose();
    _player.dispose();
    super.dispose();
  }

  Future<void> _ensureNotificationPermission() async {
    final notif = await Permission.notification.status;
    if (notif.isGranted) return;

    final req = await Permission.notification.request();
    if (!req.isGranted) {
      _logs.insert(
        0,
        '[permission] Notification permission denied. Media notification may not appear.',
      );
      if (req.isPermanentlyDenied) {
        _logs.insert(
          0,
          '[permission] Notification permission permanently denied. Open app settings.',
        );
      }
    }
  }

  void _publishNowPlayingFromStatus(PlayerStatus status) {
    final idx = status.currentIndex;
    if (idx < 0 || idx >= _playlist.length) return;
    if (idx == _lastPublishedNowPlayingIndex) return;

    final source = _playlist[idx];
    final title = _nameFromSource(source);
    final subtitle = _subtitleFromSource(source);

    final overrideDuration = _durationFromSource(source);
    final finalDurationSecs = (overrideDuration != null && overrideDuration > 0)
        ? overrideDuration
        : status.durationSeconds.toInt();

    _lastPublishedNowPlayingIndex = idx;

    // We need to wait for metadata to be updated before publishing to system audio
    // so that the album art is included.
    _updateMetadata(source).then((_) async {
      final artUri = await _resolveNowPlayingArtUri(
        source,
        _metadata.value.albumArt,
      );
      unawaited(
        _player.updateNowPlaying(
          id: 'track_$idx',
          title: title,
          artist: subtitle,
          duration: Duration(milliseconds: finalDurationSecs * 1000),
          artUri: artUri,
        ),
      );

      // Record in History
      String videoIdToSave = title; // fallback
      String? thumbnailUrlToSave;
      if (_onlineTrackMetadata.containsKey(source.uri)) {
        videoIdToSave = _onlineTrackMetadata[source.uri]!.videoId;
        thumbnailUrlToSave = _onlineTrackMetadata[source.uri]!.thumbnailUrl;
      } else if (source.uri.scheme == 'file') {
        final path = _safeFilePathFromUri(source.uri);
        if (path != null) videoIdToSave = path;
      }

      unawaited(
        RecentlyPlayedService.instance.addTrack(
          RecentlyPlayedTrack(
            videoId: videoIdToSave,
            title: title,
            artist: subtitle,
            thumbnailUrl: thumbnailUrlToSave,
            durationSeconds: finalDurationSecs,
            playedAt: DateTime.now(),
          ),
        ),
      );
    });
  }

  Future<String?> _resolveNowPlayingArtUri(
    AudioSource source,
    Uint8List? albumArt,
  ) async {
    final onlineTrack = _onlineTrackMetadata[source.uri];
    final thumbUrl = onlineTrack?.thumbnailUrl;
    if (thumbUrl != null && thumbUrl.isNotEmpty) {
      try {
        final cachedFile = await DefaultCacheManager().getSingleFile(thumbUrl);
        return cachedFile.uri.toString();
      } catch (e) {
        _logs.insert(
            0, '[metadata] Artwork cache failed, using URL directly: $e');
        return thumbUrl;
      }
    }

    return _buildNowPlayingArtUri(albumArt);
  }

  Future<String?> _buildNowPlayingArtUri(Uint8List? albumArt) async {
    if (albumArt == null || albumArt.isEmpty) return null;
    try {
      final tempDir = Directory.systemTemp;
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final artFile = File(
        '${tempDir.path}${Platform.pathSeparator}sautiplay_now_playing_art_$timestamp.jpg',
      );
      await artFile.writeAsBytes(albumArt, flush: true);
      return artFile.uri.toString();
    } catch (e) {
      _logs.insert(
          0, '[metadata] Failed to persist album art for now playing: $e');
      if (mounted) setState(() {});
      return null;
    }
  }

  Future<void> _updateMetadata(AudioSource source) async {
    String artist = 'Unknown Artist';
    Uint8List? albumArt;

    if (_onlineTrackMetadata.containsKey(source.uri)) {
      final track = _onlineTrackMetadata[source.uri]!;
      artist = track.artist;
      if (track.thumbnailUrl != null) {
        if (_thumbnailCache.containsKey(track.thumbnailUrl)) {
          albumArt = _thumbnailCache[track.thumbnailUrl];
        } else {
          try {
            final client = HttpClient();
            final req = await client.getUrl(Uri.parse(track.thumbnailUrl!));
            final res = await req.close();
            if (res.statusCode == 200) {
              final bytes = <int>[];
              await for (var chunk in res) {
                bytes.addAll(chunk);
              }
              albumArt = Uint8List.fromList(bytes);
              _thumbnailCache[track.thumbnailUrl!] = albumArt;
            }
            client.close(force: true);
          } catch (e) {
            _logs.insert(0, '[metadata] Failed to download thumbnail: $e');
            if (mounted) setState(() {});
          }
        }
      }
      _metadata.value = TrackMetadata(artist, albumArt);
      return;
    }

    try {
      final uri = source.uri;
      String? filePath;

      if (uri.scheme == 'file') {
        filePath = _safeFilePathFromUri(uri);
      } else {
        final str = uri.toString();
        if (str.startsWith(RegExp(r'^[a-zA-Z]:[\\/]'))) {
          filePath = str;
        }
      }

      if (filePath != null) {
        final md = await MetadataGod.readMetadata(file: filePath);
        if (md.artist != null && md.artist!.isNotEmpty) {
          artist = md.artist!;
        }
        if (md.picture != null) {
          albumArt = md.picture!.data;
        }
      } else {
        _logs.insert(0, '[metadata] Could not resolve file path for $uri');
        if (mounted) setState(() {});
      }
    } catch (e) {
      _logs.insert(0, '[metadata] Read error: $e');
      if (mounted) setState(() {});
    }

    _metadata.value = TrackMetadata(artist, albumArt);
  }

  String? _safeFilePathFromUri(Uri uri) {
    if (uri.scheme != 'file') return null;
    try {
      return uri.toFilePath();
    } catch (_) {
      return null;
    }
  }

  Future<AudioSource?> _materializeSource(Uri uri) async {
    if (uri.scheme == 'file') {
      final filePath = _safeFilePathFromUri(uri);
      if (filePath == null || filePath.isEmpty) {
        _logs.insert(0, '[source] Invalid file URI: $uri');
        return null;
      }
      final file = File(filePath);
      if (!file.existsSync()) {
        _logs.insert(0, '[source] Local file not found: ${file.path}');
        return null;
      }
      return AudioSource.uri(uri);
    }

    if (uri.scheme != 'http' && uri.scheme != 'https') {
      _logs.insert(0, '[source] Unsupported URI scheme: ${uri.scheme}');
      return null;
    }

    final supportsNativeNetwork = _player.isNetworkStreamingSupported();
    if (supportsNativeNetwork) {
      _logs.insert(0, '[source] Using native network source in playlist: $uri');
      return AudioSource.network(uri.toString());
    }

    _logs.insert(
        0, '[source] Downloading URL for playlist compatibility: $uri');

    final cacheDir = Directory(
      '${Directory.systemTemp.path}${Platform.pathSeparator}miniaudiodart_stream_cache',
    );
    if (!cacheDir.existsSync()) {
      cacheDir.createSync(recursive: true);
    }

    final ext = () {
      final path = uri.path.toLowerCase();
      if (path.endsWith('.mp3')) return '.mp3';
      if (path.endsWith('.aac')) return '.aac';
      if (path.endsWith('.m4a')) return '.m4a';
      if (path.endsWith('.wav')) return '.wav';
      if (path.endsWith('.ogg')) return '.ogg';
      if (path.endsWith('.flac')) return '.flac';
      return '.mp3';
    }();

    final file = File(
      '${cacheDir.path}${Platform.pathSeparator}stream_${DateTime.now().microsecondsSinceEpoch}$ext',
    );

    final client = HttpClient();
    if (_allowInvalidTlsForDownloads && uri.scheme == 'https') {
      client.badCertificateCallback = (_, __, ___) => true;
    }
    try {
      final req = await client.getUrl(uri);
      req.headers.set('User-Agent', 'MiniAudioDart/1.0 (Flutter)');
      req.headers.set('Accept', '*/*');

      final res = await req.close();
      if (res.statusCode < 200 || res.statusCode >= 300) {
        _logs.insert(0, '[source] HTTP ${res.statusCode}: $uri');
        return null;
      }

      final sink = file.openWrite();
      await sink.addStream(res);
      await sink.flush();
      await sink.close();

      return AudioSource.uri(file.uri);
    } on HandshakeException catch (e) {
      final message = e.toString();
      if (message.contains('CERTIFICATE_VERIFY_FAILED') &&
          message.contains('not yet valid')) {
        _logs.insert(
          0,
          '[source] TLS certificate date check failed. Verify device/system clock and timezone, then retry.',
        );
        if (!_allowInvalidTlsForDownloads) {
          _logs.insert(
            0,
            '[source] Tip: enable "Allow invalid TLS certs" in Logs tab for testing only.',
          );
        }
      }
      _logs.insert(0, '[source] Download failed: $e');
      return null;
    } catch (e) {
      _logs.insert(0, '[source] Download failed: $e');
      return null;
    } finally {
      client.close(force: true);
    }
  }

  Future<void> _playFolder(List<String> paths, {int initialIndex = 0}) async {
    final sources = <AudioSource>[];
    final uiQueue = <TrackInfo>[];

    for (int i = 0; i < paths.length; i++) {
      final file = File(paths[i]);
      final uri = file.absolute.uri;
      final src = await _materializeSource(uri);

      if (src != null) {
        sources.add(src);
        // Populate UI queue with local file info
        uiQueue.add(TrackInfo(
          videoId: file.absolute.path,
          title: file.uri.pathSegments.where((s) => s.isNotEmpty).last,
          artist: 'Local File',
          thumbnailUrl: null,
        ));
      } else if (i < initialIndex) {
        // If a file before the initialIndex fails to materialize, decrement the index so we stay on track
        initialIndex--;
      }
    }

    if (sources.isEmpty) {
      _logs.insert(0, '[folder] No valid audio sources found in the folder.');
      setState(() {});
      return;
    }

    if (initialIndex < 0 || initialIndex >= sources.length) {
      initialIndex = 0;
    }

    setState(() {
      _currentUiQueue.clear();
      _currentUiQueue.addAll(uiQueue);

      _playlist
        ..clear()
        ..addAll(sources);
    });

    _player.setAudioSources(
      _playlist,
      initialIndex: initialIndex,
      initialPosition: Duration.zero,
      useLazyPreparation: true,
    );

    _saveQueue();

    final msg = _player.getLastError();
    if (msg.isNotEmpty) {
      _logs.insert(0, '[folder-play] $msg');
      setState(() {});
    }

    _showNowPlayingScreen();
  }

  Future<void> _fetchAndAppendUpNext(String videoId) async {
    _logs.insert(0, '[stream] Fetching "Up Next" suggestions...');
    try {
      final yt = YTMusic();
      await yt.initialize();
      final upNexts = await yt.getUpNexts(videoId);

      if (upNexts.isEmpty) {
        _logs.insert(0, '[stream] No recommendations found.');
        return;
      }

      final newTracks = <TrackInfo>[];
      for (final item in upNexts) {
        // Only include songs, skip videos if needed, but UpNextsDetails usually are songs/videos
        // Filter out the currently playing song if returned
        if (item.videoId == videoId) continue;

        // Find the largest thumbnail
        String? thumbUrl;
        if (item.thumbnails.isNotEmpty) {
          item.thumbnails.sort((a, b) => b.width.compareTo(a.width));
          thumbUrl = item.thumbnails.first.url;
        }

        newTracks.add(TrackInfo(
          videoId: item.videoId,
          title: item.title,
          artist: item.artists.name,
          durationSeconds: item.duration, // integer seconds
          thumbnailUrl: thumbUrl,
        ));
      }

      if (newTracks.isEmpty) return;

      _logs.insert(0, '[stream] Adding ${newTracks.length} tracks to queue...');
      // Update UI queue
      setState(() {
        _currentUiQueue.addAll(newTracks);
      });

      // Lazily resolve URLs for these new tracks
      // We don't block; we just add them to the playlist as they resolve
      // Or better yet, we can add them to the playlist as unresolved items if our player supported it,
      // but here we resolve them one by one or in batches.
      // For now, let's resolve them sequentially in the background.
      _resolveAndAppendTracks(newTracks);
    } catch (e) {
      _logs.insert(0, '[stream] Failed to fetch Up Next: $e');
    }
  }

  Future<void> _resolveAndAppendTracks(List<TrackInfo> tracks) async {
    final videoIds = tracks.map((t) => t.videoId).toList();
    final urls = await StreamingService.resolveBatchStreamUrls(videoIds);

    for (int i = 0; i < tracks.length; i++) {
      final url = urls[i];
      if (url == null) continue;
      try {
        final src = await _materializeSource(Uri.parse(url));
        if (src != null && mounted) {
          _onlineTrackMetadata[src.uri] = tracks[i];
          setState(() {
            _playlist.add(src);
          });
          _player.addAudioSource(src);
        }
      } catch (e) {
        // Ignore failures for background suggestions
      }
    }
    _logs.insert(
        0, '[stream] Up Next tracks added to playlist (batch resolved).');
  }

  /// Plays online tracks from album/playlist detail screen.
  /// Resolves videoIds → MP3 URLs via the streaming API.
  Future<void> _playOnlineTracks(
    List<TrackInfo> tracks, {
    int initialIndex = 0,
  }) async {
    if (tracks.isEmpty) return;

    _logs.insert(0,
        '[stream] Resolving ${tracks.length} tracks (starting at #${initialIndex + 1})...');
    setState(() {
      _isLoading = true; // Start loading
    });

    // Resolve the tapped track first for instant playback
    final tappedTrack = tracks[initialIndex];
    final firstUrl =
        await StreamingService.resolveStreamUrl(tappedTrack.videoId);
    if (firstUrl == null) {
      _logs.insert(0, '[stream] Failed to resolve: ${tappedTrack.title}');
      setState(() {
        _isLoading = false; // Stop loading on failure
      });
      return;
    }

    // Create the initial source and start playback immediately
    final firstSource = await _materializeSource(Uri.parse(firstUrl));
    if (firstSource == null) {
      _logs.insert(0, '[stream] Failed to materialize: $firstUrl');
      setState(() {
        _isLoading = false; // Stop loading on failure
      });
      return;
    }

    _onlineTrackMetadata[firstSource.uri] = tappedTrack;

    // Populate UI queue immediately
    setState(() {
      _currentUiQueue.clear();
      _currentUiQueue.addAll(tracks);
    });

    // Populate playlist with placeholder sources; replace as resolved
    setState(() {
      _playlist
        ..clear()
        ..add(firstSource);
    });

    _player.setAudioSources(
      _playlist,
      initialIndex: 0,
      initialPosition: Duration.zero,
      useLazyPreparation: true,
    );

    // Stop loading once audio sources are set and player command sent
    setState(() {
      _isLoading = false;
    });

    // If only one track was selected, fetch "Up Next" suggestions
    if (tracks.length == 1) {
      _fetchAndAppendUpNext(tappedTrack.videoId);
    }

    // Lazily resolve remaining tracks in batch (concurrent across both servers)
    final remainingTracks = [
      for (int i = 0; i < tracks.length; i++)
        if (i != initialIndex) tracks[i],
    ];

    if (remainingTracks.isNotEmpty) {
      final remainingVideoIds = remainingTracks.map((t) => t.videoId).toList();
      final urls =
          await StreamingService.resolveBatchStreamUrls(remainingVideoIds);

      for (int i = 0; i < remainingTracks.length; i++) {
        final url = urls[i];
        if (url == null) {
          _logs.insert(
              0, '[stream] Skip: ${remainingTracks[i].title} (no URL)');
          continue;
        }
        try {
          final src = await _materializeSource(Uri.parse(url));
          if (src != null && mounted) {
            _onlineTrackMetadata[src.uri] = remainingTracks[i];
            setState(() => _playlist.add(src));
            _player.setAudioSources(
              _playlist,
              initialIndex: _status.value.currentIndex >= 0
                  ? _status.value.currentIndex
                  : 0,
              initialPosition: Duration(
                seconds: _status.value.positionSeconds.toInt(),
              ),
              useLazyPreparation: true,
            );
          }
        } catch (e) {
          _logs.insert(0,
              '[stream] Error materializing ${remainingTracks[i].title}: $e');
        }
      }
    }

    _logs.insert(
        0, '[stream] ✓ Resolved ${_playlist.length}/${tracks.length} tracks');
    setState(() {});
  }

  /// Prioritizes resolving and playing a track from the _currentUiQueue.
  Future<void> _playQueueIndex(int queueIndex) async {
    if (queueIndex < 0 || queueIndex >= _currentUiQueue.length) return;

    final targetTrack = _currentUiQueue[queueIndex];
    _logs.insert(0, '[queue] Prioritizing: ${targetTrack.title}');

    // If it's already in the playlist, just jump to it
    // We assume the playlist order roughly matches the queue order of resolved tracks
    final existingIndex = _playlist.indexWhere((src) {
      if (_onlineTrackMetadata.containsKey(src.uri)) {
        return _onlineTrackMetadata[src.uri]?.videoId == targetTrack.videoId;
      } else if (src.uri.scheme == 'file') {
        final path = _safeFilePathFromUri(src.uri);
        return path != null && path == targetTrack.videoId;
      }
      return false;
    });

    if (existingIndex != -1) {
      // Track is already resolved and in the playlist. Just seek to it.
      // Wait, IsolateAudioPlayer handles continuous play. We can fake jumping by
      // clearing and re-setting the playlist from this index if needed, OR
      // just set the sources with the new initial index.
      _player.setAudioSources(
        _playlist,
        initialIndex: existingIndex,
        initialPosition: Duration.zero,
        useLazyPreparation: true,
      );
      return;
    }

    // It's unresolved. Resolve immediately and play.
    try {
      final url = await StreamingService.resolveStreamUrl(targetTrack.videoId);
      if (url != null) {
        final src = await _materializeSource(Uri.parse(url));
        if (src != null && mounted) {
          _onlineTrackMetadata[src.uri] = targetTrack;

          // Insert it into the playlist at the correct relative position if possible,
          // but for simplicity, let's append it or reset the playlist to play it now.
          // Since we want the queue to continue, we can reset the audio engine's playlist
          // from this point forward, or simply append and jump.
          setState(() {
            _playlist.add(src);
          });

          _player.setAudioSources(
            _playlist,
            initialIndex: _playlist.length - 1,
            initialPosition: Duration.zero,
            useLazyPreparation: true,
          );
        }
      } else {
        _logs.insert(0, '[queue] Skip: ${targetTrack.title} (no URL)');
      }
    } catch (e) {
      _logs.insert(0, '[queue] Error resolving ${targetTrack.title}: $e');
    }
  }

  void _reorderQueue(int oldIndex, int newIndex) {
    setState(() {
      if (oldIndex < newIndex) {
        newIndex -= 1;
      }
      final item = _currentUiQueue.removeAt(oldIndex);
      _currentUiQueue.insert(newIndex, item);

      // Attempt to reorder _playlist to match if the items are resolved
      final resolvedOldIndex = _playlist.indexWhere((src) {
        if (_onlineTrackMetadata.containsKey(src.uri)) {
          return _onlineTrackMetadata[src.uri]?.videoId == item.videoId;
        } else if (src.uri.scheme == 'file') {
          final path = _safeFilePathFromUri(src.uri);
          return path != null && path == item.videoId;
        }
        return false;
      });
      if (resolvedOldIndex != -1) {
        // Find the resolved new index based on the nearest resolved neighbor
        // This is complex, so for simplicity we just reorder the UI queue and
        // let the audio engine rely on `_playlist`'s current order unless we
        // fully reconstruct `_playlist`.
        // For now, we will just move the item in `_playlist` to the end if we can't figure it out,
        // or ideally, we'd rebuild `_playlist` securely based on `_currentUiQueue`.

        // Simple reconstruction of `_playlist` based on `_currentUiQueue` order
        final newPlaylist = <AudioSource>[];
        for (final track in _currentUiQueue) {
          final existingSrc = _playlist.firstWhere((src) {
            if (_onlineTrackMetadata.containsKey(src.uri)) {
              return _onlineTrackMetadata[src.uri]?.videoId == track.videoId;
            } else if (src.uri.scheme == 'file') {
              final path = _safeFilePathFromUri(src.uri);
              return path != null && path == track.videoId;
            }
            return false;
          }, orElse: () => AudioSource.uri(Uri()) // Dummy that won't match
              );
          if (existingSrc.uri.toString().isNotEmpty) {
            newPlaylist.add(existingSrc);
          }
        }
        _playlist.addAll(newPlaylist);

        final currentIndex = _status.value.currentIndex;
        _player.setAudioSources(
          _playlist,
          initialIndex: currentIndex >= 0 && currentIndex < _playlist.length
              ? currentIndex
              : 0,
          initialPosition:
              Duration(seconds: _status.value.positionSeconds.toInt()),
          useLazyPreparation: true,
        );
      }
    });
  }

  /// Plays tracks selected from the Recently Played history list.
  Future<void> _playHistoryTracks(
    List<RecentlyPlayedTrack> tracks, {
    int initialIndex = 0,
  }) async {
    if (tracks.isEmpty) return;

    // We can convert RecentlyPlayedTrack to TrackInfo and re-use _playOnlineTracks
    // because it handles both local file paths and online streams smoothly due to our earlier fixes.
    final trackInfos = tracks
        .map((t) => TrackInfo(
              videoId: t.videoId,
              title: t.title,
              artist: t.artist,
              thumbnailUrl: t.thumbnailUrl,
              durationSeconds: t.durationSeconds,
            ))
        .toList();

    await _playOnlineTracks(trackInfos, initialIndex: initialIndex);
  }

  /// Plays tracks selected from the Liked Songs list.
  Future<void> _playLikedSongs(
    List<LikedSong> tracks, {
    int initialIndex = 0,
  }) async {
    if (tracks.isEmpty) return;

    final trackInfos = tracks
        .map((t) => TrackInfo(
              videoId: t.videoId,
              title: t.title,
              artist: t.artist,
              thumbnailUrl: t.thumbnailUrl,
              durationSeconds: t.durationSeconds,
            ))
        .toList();

    await _playOnlineTracks(trackInfos, initialIndex: initialIndex);
  }

  String _nameFromSource(AudioSource source) {
    if (_onlineTrackMetadata.containsKey(source.uri)) {
      return _onlineTrackMetadata[source.uri]!.title;
    }
    final uri = source.uri;
    if (uri.scheme == 'file') {
      final p = _safeFilePathFromUri(uri);
      if (p == null || p.isEmpty) {
        return uri.toString();
      }
      final sep = Platform.pathSeparator;
      final i = p.lastIndexOf(sep);
      return i >= 0 ? p.substring(i + 1) : p;
    }
    if (uri.pathSegments.isNotEmpty) {
      final last = uri.pathSegments.last;
      if (last.isNotEmpty) return last;
    }
    return uri.toString();
  }

  String _subtitleFromSource(AudioSource source) {
    if (_onlineTrackMetadata.containsKey(source.uri)) {
      return _onlineTrackMetadata[source.uri]!.artist;
    }
    final uri = source.uri;
    if (uri.scheme == 'file') {
      final p = _safeFilePathFromUri(uri);
      return (p == null || p.isEmpty) ? uri.toString() : p;
    }
    return uri.toString();
  }

  int? _durationFromSource(AudioSource source) {
    if (_onlineTrackMetadata.containsKey(source.uri)) {
      return _onlineTrackMetadata[source.uri]!.durationSeconds;
    }
    return null;
  }

  String _codecFromCurrentTrack() {
    final status = _status.value;
    final idx = status.currentIndex;
    if (idx < 0 || idx >= _playlist.length) return 'AUDIO';
    final name = _nameFromSource(_playlist[idx]).toLowerCase();
    if (name.endsWith('.flac')) return 'FLAC';
    if (name.endsWith('.wav')) return 'WAV';
    if (name.endsWith('.ogg')) return 'OGG';
    if (name.endsWith('.m4a')) return 'AAC';
    if (name.endsWith('.aac')) return 'AAC';
    if (name.endsWith('.mp3')) return 'MP3';
    // Try to extract extension
    final dotIdx = name.lastIndexOf('.');
    if (dotIdx > 0 && dotIdx < name.length - 1) {
      return name.substring(dotIdx + 1).toUpperCase();
    }
    return 'AUDIO';
  }

  void _showNowPlayingScreen() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: false,
      constraints: BoxConstraints(
        maxWidth: MediaQuery.of(context).size.width,
        maxHeight: MediaQuery.of(context).size.height,
      ),
      builder: (context) {
        return ValueListenableBuilder<TrackMetadata>(
          valueListenable: _metadata,
          builder: (context, meta, _) {
            return NowPlayingScreen(
              statusNotifier: _status,
              player: _player,
              albumArt: meta.albumArt,
              artist: meta.artist,
              codec: _codecFromCurrentTrack(),
              durationOverride: _playlist.isNotEmpty &&
                      _status.value.currentIndex >= 0 &&
                      _status.value.currentIndex < _playlist.length
                  ? _durationFromSource(_playlist[_status.value.currentIndex])
                  : null,
              videoId: _playlist.isNotEmpty &&
                      _status.value.currentIndex >= 0 &&
                      _status.value.currentIndex < _playlist.length
                  ? (_onlineTrackMetadata[
                          _playlist[_status.value.currentIndex].uri]
                      ?.videoId)
                  : null,
              getTitle: (index) => (index >= 0 && index < _playlist.length)
                  ? _nameFromSource(_playlist[index])
                  : 'No track selected',
              onMinimize: () => Navigator.of(context).pop(),
              queue: _currentUiQueue,
              onPlayQueueIndex: _playQueueIndex,
              onReorderQueue: _reorderQueue,
              sourceType: (_playlist.isNotEmpty &&
                      _status.value.currentIndex >= 0 &&
                      _status.value.currentIndex < _playlist.length &&
                      !_onlineTrackMetadata.containsKey(
                          _playlist[_status.value.currentIndex].uri))
                  ? 'local'
                  : 'online',
              onPlayTracks: _playOnlineTracks,
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // appBar: AppBar(title: const Text('MiniAudio Playlist Demo')),
      body: IndexedStack(
        index: _tabIndex,
        children: [
          HomeScreen(onPlayTracks: _playOnlineTracks),
          SearchScreen(onPlayTracks: _playOnlineTracks),
          RecentlyPlayedScreen(onPlayTracks: _playHistoryTracks),
          EqScreen(
            player: _player,
            analyzerEnabled: _analyzerEnabled,
            analyzerType: _analyzerType,
          ),
          LibraryScreen(
            onPlayFolder: _playFolder,
            onPlayLikedSongs: _playLikedSongs,
          ),
          SettingsScreen(
              player: _player,
              analyzerEnabled: _analyzerEnabled,
              onAnalyzerEnabledChanged: (v) {
                setState(() => _analyzerEnabled = v);
                _player.setAnalyzerEnabled(v);
                _saveEngineSettings();
              },
              analyzerType: _analyzerType,
              onAnalyzerTypeChanged: (v) {
                setState(() => _analyzerType = v);
                _saveEngineSettings();
              },
              analyzerSampleSize: _analyzerSampleSize,
              onAnalyzerSampleSizeChanged: (v) {
                setState(() => _analyzerSampleSize = v);
                _player.configureAnalyzer(frameSize: v);
                _saveEngineSettings();
              },
              outputFormat: _outputFormat,
              onOutputFormatChanged: (v) {
                setState(() => _outputFormat = v);
                _saveEngineSettings();
              },
              outputSampleRate: _outputSampleRate,
              onOutputSampleRateChanged: (v) {
                setState(() => _outputSampleRate = v);
                _saveEngineSettings();
              },
              outputChannels: _outputChannels,
              onOutputChannelsChanged: (v) {
                setState(() => _outputChannels = v);
                _saveEngineSettings();
              },
              crossfadeEnabled: _crossfadeEnabled,
              onCrossfadeEnabledChanged: (v) {
                setState(() => _crossfadeEnabled = v);
                _player.setCrossfadeEnabled(v);
                _saveEngineSettings();
              },
              crossfadeDurationMs: _crossfadeDurationMs,
              onCrossfadeDurationMsChanged: (v) {
                setState(() => _crossfadeDurationMs = v);
                _player.setCrossfadeDurationMs(v);
                _saveEngineSettings();
              },
              logs: _logs,
              logUpdateNotifier: _logUpdateCounter,
              allowInvalidTls: _allowInvalidTlsForDownloads,
              onAllowInvalidTlsChanged: (selected) {
                setState(() => _allowInvalidTlsForDownloads = selected);
                _logs.insert(
                  0,
                  selected
                      ? '[security] Invalid TLS cert acceptance enabled for fallback downloads.'
                      : '[security] Invalid TLS cert acceptance disabled.',
                );
                _logUpdateCounter.value++;
                _saveEngineSettings();
              },
              onPollError: () {
                final msg = _player.getLastError();
                _logs.insert(0, '[poll] ${msg.isEmpty ? "(no error)" : msg}');
                _logUpdateCounter.value++;
              },
              onClearNativeError: () {
                _player.clearLastError();
                _logs.insert(0, '[action] Cleared native error state');
                _logUpdateCounter.value++;
              },
              onClearLogs: () {
                _logs.clear();
                _logUpdateCounter.value++;
              }),
        ],
      ),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ValueListenableBuilder<PlayerStatus>(
            valueListenable: _status,
            builder: (context, status, _) {
              if (_isLoading) {
                return const ShimmerMiniPlayer();
              }

              final idx = status.currentIndex;
              if (_playlist.isEmpty || idx < 0 || idx >= _playlist.length) {
                return const SizedBox.shrink();
              }
              final src = _playlist[idx];
              final overrideDuration = _durationFromSource(src);
              final finalDurationSecs =
                  (overrideDuration != null && overrideDuration > 0)
                      ? overrideDuration.toDouble()
                      : status.durationSeconds;

              final progress = finalDurationSecs > 0
                  ? (status.positionSeconds / finalDurationSecs).clamp(0.0, 1.0)
                  : 0.0;

              if (_isLoading) {
                return const ShimmerMiniPlayer();
              }
              return ValueListenableBuilder<TrackMetadata>(
                valueListenable: _metadata,
                builder: (context, meta, _) {
                  return MiniPlayer(
                    title: _nameFromSource(src),
                    artist: meta.artist,
                    albumArt: meta.albumArt,
                    progress: progress,
                    isPlaying: status.isPlaying,
                    onPlayPause: () {
                      if (status.isPlaying) {
                        _player.pause();
                      } else {
                        _player.play();
                      }
                    },
                    onNext: () => _player.next(),
                    onTap: _showNowPlayingScreen,
                  );
                },
              );
            },
          ),
          NavigationBar(
            selectedIndex: _tabIndex,
            onDestinationSelected: (i) => setState(() => _tabIndex = i),
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.home_rounded),
                label: 'Home',
              ),
              NavigationDestination(
                icon: Icon(Icons.search),
                label: 'Search',
              ),
              NavigationDestination(
                icon: Icon(Icons.history),
                label: 'History',
              ),
              NavigationDestination(
                icon: Icon(Icons.equalizer),
                label: 'Equalizer',
              ),
              NavigationDestination(
                icon: Icon(Icons.library_music),
                label: 'Library',
              ),
              NavigationDestination(
                icon: Icon(Icons.settings),
                label: 'Settings',
              ),
            ],
          ),
        ],
      ),
    );
  }
}
