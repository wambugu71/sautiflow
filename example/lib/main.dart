import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:sautiflow/sautiflow.dart';

import 'isolate_player.dart';

void main() {
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
      title: 'MiniAudio Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const PlayerShell(),
    );
  }
}

class PlayerShell extends StatefulWidget {
  const PlayerShell({super.key});

  @override
  State<PlayerShell> createState() => _PlayerShellState();
}

class _PlayerShellState extends State<PlayerShell> {
  final IsolateAudioPlayer _player = IsolateAudioPlayer();
  final TextEditingController _singleUrlController = TextEditingController();
  final TextEditingController _multiUrlController = TextEditingController();
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

  final List<AudioSource> _playlist = <AudioSource>[];
  final List<String> _logs = <String>[];
  int _tabIndex = 0;
  int _lazyLoadSession = 0;
  bool _nativeNetworkStreamingSupported = false;
  bool _allowInvalidTlsForDownloads = false;
  bool _systemMediaControlsEnabled = false;
  int _lastPublishedNowPlayingIndex = -1;

  bool _eqEnabled = false;
  bool _reverbEnabled = false;
  bool _lowpassEnabled = false;
  bool _highpassEnabled = false;
  bool _delayEnabled = false;

  // Advanced Audio State
  bool _multibandEqEnabled = false;
  final List<double> _eqBandGains = List.filled(10, 0.0);
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

  double _low = 1.0;
  double _mid = 1.0;
  double _high = 1.0;
  double _gain = 1.0;
  double _pan = 0.0;
  double _lpCutoff = 12000;
  double _hpCutoff = 80;
  double _rvMix = 0.15;
  double _rvFeedback = 0.65;
  double _rvDelay = 95;
  double _dlMix = 0.2;
  double _dlFeedback = 0.35;
  double _dlDelay = 240;

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
      _status.value = s;
      _publishNowPlayingFromStatus(s);
      // Removed setState to prevent full rebuilds on every status update
    });
    _player.logStream.listen((line) {
      _logs.insert(0, '[${DateTime.now().toIso8601String()}] $line');
      if (_logs.length > 200) {
        _logs.removeRange(200, _logs.length);
      }
      if (mounted && _tabIndex == 2)
        setState(() {}); // Only rebuild if Logs tab is active
    });

    if (Platform.isAndroid) {
      unawaited(_ensureNotificationPermission());
    }
  }

  @override
  void dispose() {
    _singleUrlController.dispose();
    _multiUrlController.dispose();
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
    _lastPublishedNowPlayingIndex = idx;

    unawaited(
      _player.updateNowPlaying(
        id: 'track_$idx',
        title: title,
        artist: subtitle,
        duration:
            Duration(milliseconds: (status.durationSeconds * 1000).round()),
      ),
    );
  }

  Uri? _parseInputToUri(String raw) {
    final text = raw
        .trim()
        .replaceAll('"', '')
        .replaceAll("'", '')
        .replaceAll('<', '')
        .replaceAll('>', '');
    if (text.isEmpty) return null;

    final isWindowsDrivePath = RegExp(r'^[a-zA-Z]:[\\/]').hasMatch(text);
    final isUncPath = text.startsWith('\\\\');
    if (isWindowsDrivePath || isUncPath) {
      return File(text).absolute.uri;
    }

    final uri = Uri.tryParse(text);
    if (uri == null) return null;

    if (uri.scheme == 'http' || uri.scheme == 'https') {
      if (!uri.hasAuthority || uri.host.trim().isEmpty) return null;
      final host = uri.host.toLowerCase().trim();
      if (host == 'link' || host == 'your-link' || host == 'placeholder') {
        return null;
      }
      return uri;
    }

    if (uri.scheme == 'file') {
      return uri;
    }

    if (!uri.hasScheme) {
      return File(text).absolute.uri;
    }

    return null;
  }

  List<Uri> _parseInputUris(String rawList) {
    final seen = <String>{};
    final out = <Uri>[];
    final parts = rawList
        .split(RegExp(r'[\r\n,;]+'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty);
    for (final part in parts) {
      final uri = _parseInputToUri(part);
      if (uri == null) continue;
      final key = uri.toString();
      if (seen.add(key)) out.add(uri);
    }
    return out;
  }

  String? _safeFilePathFromUri(Uri uri) {
    if (uri.scheme != 'file') return null;
    try {
      return uri.toFilePath();
    } catch (_) {
      return null;
    }
  }

  Future<AudioSource?> _sourceFromPickedFile(PlatformFile f) async {
    if (f.path != null && f.path!.isNotEmpty) {
      final file = File(f.path!);
      if (file.existsSync()) {
        return AudioSource.uri(file.uri);
      }
    }

    final cacheDir = Directory(
      '${Directory.systemTemp.path}${Platform.pathSeparator}miniaudiodart_pick_cache',
    );
    if (!cacheDir.existsSync()) {
      cacheDir.createSync(recursive: true);
    }

    final ext = (() {
      final fromExt = f.extension?.trim();
      if (fromExt != null && fromExt.isNotEmpty) {
        return '.${fromExt.toLowerCase()}';
      }
      final fromName = f.name;
      final dot = fromName.lastIndexOf('.');
      if (dot > 0 && dot < fromName.length - 1) {
        return '.${fromName.substring(dot + 1).toLowerCase()}';
      }
      return '.bin';
    })();

    final out = File(
      '${cacheDir.path}${Platform.pathSeparator}pick_${DateTime.now().microsecondsSinceEpoch}_${f.name.hashCode}$ext',
    );

    if (f.readStream != null) {
      final sink = out.openWrite();
      try {
        await sink.addStream(f.readStream!);
        await sink.flush();
      } finally {
        await sink.close();
      }
      if (out.existsSync() && out.lengthSync() > 0) {
        return AudioSource.uri(out.uri);
      }
    }

    if (f.bytes != null && f.bytes!.isNotEmpty) {
      await out.writeAsBytes(f.bytes!, flush: true);
      if (out.existsSync() && out.lengthSync() > 0) {
        return AudioSource.uri(out.uri);
      }
    }

    _logs.insert(
      0,
      '[pick] Could not materialize: ${f.name} (no usable path/stream/bytes)',
    );
    return null;
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

  Future<void> _playSingleUrl() async {
    final uri = _parseInputToUri(_singleUrlController.text);
    if (uri == null) {
      _logs.insert(
        0,
        '[source] Invalid input. Use a local path, file:// URI, or http(s) URL.',
      );
      setState(() {});
      return;
    }

    if (uri.scheme == 'http' || uri.scheme == 'https') {
      _logs.insert(
        0,
        '[source] URL input detected. Downloading to local cache before playback: $uri',
      );
    }

    final src = await _materializeSource(uri);
    if (src == null) {
      setState(() {});
      return;
    }

    setState(() {
      _playlist
        ..clear()
        ..add(src);
    });

    _player.setAudioSources(
      _playlist,
      initialIndex: 0,
      initialPosition: Duration.zero,
      useLazyPreparation: true,
    );
    _player.play();

    final msg = _player.getLastError();
    if (msg.isNotEmpty) {
      _logs.insert(0, '[url-play] $msg');
      setState(() {});
    }
  }

  Future<void> _setMultiUrlPlaylist() async {
    final uris = _parseInputUris(_multiUrlController.text);
    if (uris.isEmpty) {
      _logs.insert(0, '[sources] No valid entries found. Use one per line.');
      setState(() {});
      return;
    }

    final resolved = await Future.wait(uris.map(_materializeSource));
    final sources = <AudioSource>[];
    for (final resolvedSrc in resolved) {
      if (resolvedSrc == null) continue;
      sources.add(resolvedSrc);
    }

    if (sources.isEmpty) {
      _logs.insert(0, '[sources] No valid entries found after resolution.');
      setState(() {});
      return;
    }

    setState(() {
      _playlist
        ..clear()
        ..addAll(sources);
    });

    _player.setAudioSources(
      _playlist,
      initialIndex: 0,
      initialPosition: Duration.zero,
      useLazyPreparation: true,
    );

    final msg = _player.getLastError();
    if (msg.isNotEmpty) {
      _logs.insert(0, '[sources-set] $msg');
      setState(() {});
    }
  }

  Future<void> _addMultiUrls() async {
    final uris = _parseInputUris(_multiUrlController.text);
    if (uris.isEmpty) {
      _logs.insert(0, '[sources] No valid entries found to add.');
      setState(() {});
      return;
    }

    final resolved = await Future.wait(uris.map(_materializeSource));
    for (final src in resolved.whereType<AudioSource>()) {
      _playlist.add(src);
      _player.addAudioSource(src);
      final msg = _player.getLastError();
      if (msg.isNotEmpty) {
        _logs.insert(0, '[sources-add] $msg');
      }
    }
    setState(() {});
  }

  Future<void> _appendPickedFilesLazily(
    List<PlatformFile> files, {
    required int sessionTag,
    int? skipIndex,
    String logPrefix = '[lazy]',
  }) async {
    var added = 0;
    for (var i = 0; i < files.length; i++) {
      if (skipIndex != null && i == skipIndex) continue;
      if (!mounted || sessionTag != _lazyLoadSession) return;

      final src = await _sourceFromPickedFile(files[i]);
      if (src == null) continue;
      if (!mounted || sessionTag != _lazyLoadSession) return;

      _playlist.add(src);
      _player.addAudioSource(src);
      added++;

      final msg = _player.getLastError();
      if (msg.isNotEmpty) {
        _logs.insert(0, '$logPrefix $msg');
      }

      if (added % 5 == 0) {
        setState(() {});
      }
    }

    if (!mounted || sessionTag != _lazyLoadSession) return;
    _logs.insert(0, '$logPrefix Added $added tracks in background');
    setState(() {});
  }

  Future<void> _pickSongsAndSetPlaylist() async {
    final hasPermission = await _ensureMediaPermission();
    if (!hasPermission) {
      _logs.insert(0, '[permission] Media permission denied');
      if (mounted) setState(() {});
      return;
    }

    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.custom,
      withReadStream: true,
      allowedExtensions: const ['mp3', 'ogg', 'wav', 'flac', 'm4a', 'aac'],
    );
    if (result == null || result.files.isEmpty) return;

    final sessionTag = ++_lazyLoadSession;
    AudioSource? firstSource;
    var firstIndex = -1;
    for (var i = 0; i < result.files.length; i++) {
      final src = await _sourceFromPickedFile(result.files[i]);
      if (src != null) {
        firstSource = src;
        firstIndex = i;
        break;
      }
    }

    if (firstSource == null) {
      _logs.insert(0, '[playlist] No playable picked files.');
      if (mounted) setState(() {});
      return;
    }

    setState(() {
      _playlist
        ..clear()
        ..add(firstSource!);
    });

    _player.setAudioSources(
      _playlist,
      initialIndex: 0,
      initialPosition: Duration.zero,
      useLazyPreparation: true,
    );

    final msg = _player.getLastError();
    if (msg.isNotEmpty) {
      _logs.insert(0, '[playlist] $msg');
      setState(() {});
    }

    _logs.insert(
      0,
      '[lazy] Playlist ready instantly with 1 track. Loading remaining tracks in background...',
    );
    setState(() {});

    unawaited(
      _appendPickedFilesLazily(
        result.files,
        sessionTag: sessionTag,
        skipIndex: firstIndex,
        logPrefix: '[playlist-lazy]',
      ),
    );
  }

  Future<void> _pickFolderAndSetPlaylist() async {
    final hasPermission = await _ensureMediaPermission();
    if (!hasPermission) {
      _logs.insert(0, '[permission] Media permission denied');
      if (mounted) setState(() {});
      return;
    }

    final String? selectedDirectory =
        await FilePicker.platform.getDirectoryPath();
    if (selectedDirectory == null) return;

    final dir = Directory(selectedDirectory);
    if (!dir.existsSync()) return;

    final List<File> audioFiles = [];
    final extensions = ['.mp3', '.ogg', '.wav', '.flac', '.m4a', '.aac'];

    try {
      await for (final entity in dir.list(recursive: true)) {
        if (entity is File) {
          final lowerPath = entity.path.toLowerCase();
          if (extensions.any((ext) => lowerPath.endsWith(ext))) {
            audioFiles.add(entity);
          }
        }
      }
    } catch (e) {
      _logs.insert(0, '[folder] Error listing files: $e');
    }

    if (audioFiles.isEmpty) {
      _logs.insert(0, '[playlist] No playable files found in folder.');
      if (mounted) setState(() {});
      return;
    }

    // Convert to PlatformFiles to reuse _appendPickedFilesLazily logic or handle directly
    // Since we have Files, we can create AudioSources directly.

    final sources = audioFiles.map((f) => AudioSource.uri(f.uri)).toList();

    setState(() {
      _playlist
        ..clear()
        ..addAll(sources);
    });

    _player.setAudioSources(
      _playlist,
      initialIndex: 0,
      initialPosition: Duration.zero,
      useLazyPreparation: true,
    );
    _logs.insert(
      0,
      '[folder] Playlist ready with ${sources.length} tracks from ${dir.path}',
    );

    final msg = _player.getLastError();
    if (msg.isNotEmpty) {
      _logs.insert(0, '[playlist] $msg');
      setState(() {});
    }
  }

  Future<void> _addSongs() async {
    final hasPermission = await _ensureMediaPermission();
    if (!hasPermission) {
      _logs.insert(0, '[permission] Media permission denied');
      if (mounted) setState(() {});
      return;
    }

    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.custom,
      withReadStream: true,
      allowedExtensions: const ['mp3', 'ogg', 'wav', 'flac', 'm4a', 'aac'],
    );
    if (result == null || result.files.isEmpty) return;

    final sessionTag = ++_lazyLoadSession;
    _logs.insert(
      0,
      '[add-lazy] Adding ${result.files.length} picked songs in background...',
    );
    setState(() {});

    unawaited(
      _appendPickedFilesLazily(
        result.files,
        sessionTag: sessionTag,
        logPrefix: '[add-lazy]',
      ),
    );
  }

  String _nameFromSource(AudioSource source) {
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
    final uri = source.uri;
    if (uri.scheme == 'file') {
      final p = _safeFilePathFromUri(uri);
      return (p == null || p.isEmpty) ? uri.toString() : p;
    }
    return uri.toString();
  }

  Widget _buildPlayerScreen() {
    return Column(
      children: [
        Expanded(
          flex: 3,
          child: SingleChildScrollView(
            child: Column(
              children: [
                _buildInputSection(),
                const SizedBox(height: 8),
                ValueListenableBuilder<PlayerStatus>(
                  valueListenable: _status,
                  builder: (context, st, _) => _buildPlayerControls(st),
                ),
              ],
            ),
          ),
        ),
        const Divider(),
        Expanded(
          flex: 2,
          child: ValueListenableBuilder<PlayerStatus>(
            valueListenable: _status,
            builder: (context, st, _) => _buildPlaylist(st),
          ),
        ),
      ],
    );
  }

  Widget _buildInputSection() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _pickSongsAndSetPlaylist,
                      icon: const Icon(Icons.library_music),
                      label: const Text('Pick Files'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _pickFolderAndSetPlaylist,
                      icon: const Icon(Icons.folder_open),
                      label: const Text('Pick Folder'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _addSongs,
                      icon: const Icon(Icons.queue_music),
                      label: const Text('Add Songs'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Column(
            children: [
              TextField(
                controller: _singleUrlController,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(
                  labelText:
                      'Single source (local path, file://, or http/https)',
                  hintText:
                      r'C:\Music\song.mp3  or  https://example.com/live.mp3',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _playSingleUrl,
                      icon: const Icon(Icons.link),
                      label: const Text('Play URL'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton(
                      child: const Text('Stream'),
                      onPressed: () async {
                        final uri = _parseInputToUri(_singleUrlController.text);
                        if (uri == null) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Invalid URL/path')),
                          );
                          return;
                        }

                        if (uri.scheme == 'http' || uri.scheme == 'https') {
                          _logs.insert(
                            0,
                            '[stream] Direct push streaming disabled in demo for stability. Falling back to cached URL playback.',
                          );
                          if (mounted) setState(() {});
                        }

                        await _playSingleUrl();
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _multiUrlController,
                keyboardType: TextInputType.multiline,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Multiple sources (one per line)',
                  hintText: 'C:\\Music\\a.mp3\nhttps://example.com/b.mp3',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _setMultiUrlPlaylist,
                      icon: const Icon(
                        Icons.playlist_add_check_circle_outlined,
                      ),
                      label: const Text('Set URL Playlist'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _addMultiUrls,
                      icon: const Icon(Icons.playlist_add),
                      label: const Text('Add URLs'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPlayerControls(PlayerStatus st) {
    final duration = Duration(
      milliseconds: (st.durationSeconds * 1000).round(),
    );
    final position = Duration(
      milliseconds: (st.positionSeconds * 1000).round(),
    );
    final maxMs =
        duration.inMilliseconds <= 0 ? 1.0 : duration.inMilliseconds.toDouble();
    final posMs = position.inMilliseconds
        .clamp(0, duration.inMilliseconds <= 0 ? 0 : duration.inMilliseconds)
        .toDouble();
    final currentIndex = st.currentIndex;
    final currentTitle = (currentIndex >= 0 && currentIndex < _playlist.length)
        ? _nameFromSource(_playlist[currentIndex])
        : 'No track selected';
    final currentSubtitle =
        (currentIndex >= 0 && currentIndex < _playlist.length)
            ? _subtitleFromSource(_playlist[currentIndex])
            : 'Pick songs or set URL playlist';

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Card(
            child: ListTile(
              leading: Icon(
                st.isPlaying ? Icons.graphic_eq : Icons.music_note_outlined,
              ),
              title: Text(
                currentTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                currentSubtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: Icon(
                _systemMediaControlsEnabled
                    ? Icons.notifications_active
                    : Icons.notifications_off,
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Column(
            children: [
              Slider(
                value: posMs,
                max: maxMs,
                onChanged: (v) {
                  _player.seekTo(Duration(milliseconds: v.toInt()));
                },
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [Text(_fmt(position)), Text(_fmt(duration))],
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                onPressed: _player.seekToPrevious,
                iconSize: 32,
                icon: const Icon(Icons.skip_previous),
              ),
              IconButton(
                onPressed: st.isPlaying ? _player.pause : _player.play,
                iconSize: 42,
                icon: Icon(
                  st.isPlaying ? Icons.pause_circle : Icons.play_circle,
                ),
              ),
              IconButton(
                onPressed: _player.seekToNext,
                iconSize: 32,
                icon: const Icon(Icons.skip_next),
              ),
              const SizedBox(width: 12),
              IconButton(
                onPressed: () {
                  final enabled = !st.shuffleEnabled;
                  _player.setShuffleModeEnabled(enabled);
                },
                icon: Icon(
                  st.shuffleEnabled ? Icons.shuffle_on : Icons.shuffle,
                ),
              ),
              PopupMenuButton<LoopMode>(
                initialValue: st.loopMode,
                icon: Icon(_loopIcon(st.loopMode)),
                onSelected: _player.setLoopMode,
                itemBuilder: (_) => const [
                  PopupMenuItem(value: LoopMode.off, child: Text('Loop Off')),
                  PopupMenuItem(value: LoopMode.all, child: Text('Loop All')),
                  PopupMenuItem(value: LoopMode.one, child: Text('Loop One')),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPlaylist(PlayerStatus st) {
    return ReorderableListView.builder(
      itemCount: _playlist.length,
      onReorder: (oldIndex, newIndex) {
        if (newIndex > oldIndex) newIndex -= 1;
        final item = _playlist.removeAt(oldIndex);
        _playlist.insert(newIndex, item);
        _player.moveAudioSource(oldIndex, newIndex);
        setState(() {});
      },
      itemBuilder: (context, index) {
        final isCurrent = st.currentIndex == index;
        return ListTile(
          key: ValueKey('song_$index'),
          leading: Icon(isCurrent ? Icons.graphic_eq : Icons.music_note),
          title: Text(_nameFromSource(_playlist[index])),
          subtitle: Text(_subtitleFromSource(_playlist[index])),
          onTap: () => _player.seekTo(Duration.zero, index: index),
          trailing: IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: () {
              _player.removeAudioSourceAt(index);
              _playlist.removeAt(index);
              setState(() {});
            },
          ),
        );
      },
    );
  }

  Widget _buildAdvancedSettings() {
    return ExpansionTile(
      title: const Text('Advanced Audio Settings'),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Column(
            children: [
              // Output Format
              DropdownButtonFormField<AudioFormat>(
                value: _outputFormat,
                decoration: const InputDecoration(labelText: 'Audio Format'),
                items: AudioFormat.values.map((f) {
                  return DropdownMenuItem(value: f, child: Text(f.name));
                }).toList(),
                onChanged: (v) {
                  if (v == null) return;
                  setState(() => _outputFormat = v);
                  _player.setOutputFormat(v);
                },
              ),
              const SizedBox(height: 8),
              // Sample Rate
              DropdownButtonFormField<int>(
                value: _outputSampleRate,
                decoration: const InputDecoration(labelText: 'Sample Rate'),
                items: const [
                  DropdownMenuItem(value: 0, child: Text('Native')),
                  DropdownMenuItem(value: 44100, child: Text('44100 Hz')),
                  DropdownMenuItem(value: 48000, child: Text('48000 Hz')),
                  DropdownMenuItem(value: 96000, child: Text('96000 Hz')),
                ],
                onChanged: (v) {
                  if (v == null) return;
                  setState(() => _outputSampleRate = v);
                  _player.setOutputSampleRate(v);
                },
              ),
              // Mono/Stereo
              SwitchListTile(
                title: const Text('Stereo Output'),
                subtitle: Text(
                    _outputChannels == 2 ? '2 Channels' : '1 Channel (Mono)'),
                value: _outputChannels == 2,
                onChanged: (v) {
                  setState(() => _outputChannels = v ? 2 : 1);
                  _player.setOutputChannels(_outputChannels);
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildEqScreen() {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        _buildAdvancedSettings(),
        const Divider(),
        SwitchListTile(
          title: const Text('Enable 10-Band EQ'),
          value: _multibandEqEnabled,
          onChanged: (v) {
            setState(() => _multibandEqEnabled = v);
            _player.setMultibandEqEnabled(v);
            // Initialize if enabling
            if (v) {
              _player.initMultibandEq(_eqFrequencies);
              for (int i = 0; i < _eqFrequencies.length; ++i) {
                _player.setMultibandEqBandGain(i, _eqBandGains[i]);
              }
            }
          },
        ),
        if (_multibandEqEnabled)
          SizedBox(
            height: 300,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _eqFrequencies.length,
              itemBuilder: (context, index) {
                final freq = _eqFrequencies[index];
                final label = freq >= 1000
                    ? '${(freq / 1000).toStringAsFixed(1)}k'
                    : '${freq.toInt()}';
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Expanded(
                      child: RotatedBox(
                        quarterTurns: 3,
                        child: Slider(
                          value: _eqBandGains[index],
                          min: -12.0,
                          max: 12.0,
                          onChanged: (v) {
                            setState(() => _eqBandGains[index] = v);
                            _player.setMultibandEqBandGain(index, v);
                          },
                        ),
                      ),
                    ),
                    Text(
                      '${_eqBandGains[index].toStringAsFixed(1)} dB',
                      style: const TextStyle(fontSize: 10),
                    ),
                    Text(label, style: const TextStyle(fontSize: 10)),
                  ],
                );
              },
            ),
          ),
        const Divider(),
        SwitchListTile(
          title: const Text('Enable 3-Band EQ'),
          value: _eqEnabled,
          onChanged: (v) {
            setState(() => _eqEnabled = v);
            _player.setEqEnabled(v);
          },
        ),
        _slider('Low', _low, 0, 4, (v) {
          setState(() => _low = v);
          _player.setEq(low: _low, mid: _mid, high: _high);
        }),
        _slider('Mid', _mid, 0, 4, (v) {
          setState(() => _mid = v);
          _player.setEq(low: _low, mid: _mid, high: _high);
        }),
        _slider('High', _high, 0, 4, (v) {
          setState(() => _high = v);
          _player.setEq(low: _low, mid: _mid, high: _high);
        }),
        const Divider(),
        _slider('Gain', _gain, 0, 4, (v) {
          setState(() => _gain = v);
          _player.setGain(v);
        }),
        _slider('Pan', _pan, -1, 1, (v) {
          setState(() => _pan = v);
          _player.setPan(v);
        }),
        const Divider(),
        SwitchListTile(
          title: const Text('Enable Reverb'),
          value: _reverbEnabled,
          onChanged: (v) {
            setState(() => _reverbEnabled = v);
            _player.setReverbEnabled(v);
          },
        ),
        _slider('Reverb Mix', _rvMix, 0, 1, (v) {
          setState(() => _rvMix = v);
          _player.setReverb(
            mix: _rvMix,
            feedback: _rvFeedback,
            delayMs: _rvDelay,
          );
        }),
        _slider('Reverb Feedback', _rvFeedback, 0, 0.98, (v) {
          setState(() => _rvFeedback = v);
          _player.setReverb(
            mix: _rvMix,
            feedback: _rvFeedback,
            delayMs: _rvDelay,
          );
        }),
        _slider('Reverb Delay ms', _rvDelay, 20, 350, (v) {
          setState(() => _rvDelay = v);
          _player.setReverb(
            mix: _rvMix,
            feedback: _rvFeedback,
            delayMs: _rvDelay,
          );
        }),
        const Divider(),
        SwitchListTile(
          title: const Text('Enable Low-pass'),
          value: _lowpassEnabled,
          onChanged: (v) {
            setState(() => _lowpassEnabled = v);
            _player.setLowpass(enabled: v, cutoffHz: _lpCutoff);
          },
        ),
        _slider('Low-pass cutoff (Hz)', _lpCutoff, 20, 18000, (v) {
          setState(() => _lpCutoff = v);
          _player.setLowpass(enabled: _lowpassEnabled, cutoffHz: _lpCutoff);
        }),
        SwitchListTile(
          title: const Text('Enable High-pass'),
          value: _highpassEnabled,
          onChanged: (v) {
            setState(() => _highpassEnabled = v);
            _player.setHighpass(enabled: v, cutoffHz: _hpCutoff);
          },
        ),
        _slider('High-pass cutoff (Hz)', _hpCutoff, 10, 5000, (v) {
          setState(() => _hpCutoff = v);
          _player.setHighpass(enabled: _highpassEnabled, cutoffHz: _hpCutoff);
        }),
        const Divider(),
        SwitchListTile(
          title: const Text('Enable Delay'),
          value: _delayEnabled,
          onChanged: (v) {
            setState(() => _delayEnabled = v);
            _player.setDelay(
              enabled: v,
              mix: _dlMix,
              feedback: _dlFeedback,
              delayMs: _dlDelay,
            );
          },
        ),
        _slider('Delay Mix', _dlMix, 0, 1, (v) {
          setState(() => _dlMix = v);
          _player.setDelay(
            enabled: _delayEnabled,
            mix: _dlMix,
            feedback: _dlFeedback,
            delayMs: _dlDelay,
          );
        }),
        _slider('Delay Feedback', _dlFeedback, 0, 0.98, (v) {
          setState(() => _dlFeedback = v);
          _player.setDelay(
            enabled: _delayEnabled,
            mix: _dlMix,
            feedback: _dlFeedback,
            delayMs: _dlDelay,
          );
        }),
        _slider('Delay Time ms', _dlDelay, 10, 1200, (v) {
          setState(() => _dlDelay = v);
          _player.setDelay(
            enabled: _delayEnabled,
            mix: _dlMix,
            feedback: _dlFeedback,
            delayMs: _dlDelay,
          );
        }),
        _buildAdvancedSettings(),
      ],
    );
  }

  Widget _buildLogsScreen() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: () {
                  final msg = _player.getLastError();
                  _logs.insert(0, '[poll] ${msg.isEmpty ? "(no error)" : msg}');
                  setState(() {});
                },
                icon: const Icon(Icons.refresh),
                label: const Text('Poll Error'),
              ),
              OutlinedButton.icon(
                onPressed: () {
                  _player.clearLastError();
                  _logs.insert(0, '[action] Cleared native error state');
                  setState(() {});
                },
                icon: const Icon(Icons.cleaning_services_outlined),
                label: const Text('Clear Native Error'),
              ),
              FilterChip(
                selected: _allowInvalidTlsForDownloads,
                label: const Text('Allow invalid TLS certs (test only)'),
                onSelected: (selected) {
                  setState(() => _allowInvalidTlsForDownloads = selected);
                  _logs.insert(
                    0,
                    selected
                        ? '[security] Invalid TLS cert acceptance enabled for fallback downloads.'
                        : '[security] Invalid TLS cert acceptance disabled.',
                  );
                },
              ),
              OutlinedButton.icon(
                onPressed: () async {
                  if (_logs.isEmpty) {
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('No logs to copy')),
                    );
                    return;
                  }

                  final text = _logs.reversed.join('\n');
                  await Clipboard.setData(ClipboardData(text: text));
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Copied ${_logs.length} log lines')),
                  );
                },
                icon: const Icon(Icons.copy_all_outlined),
                label: const Text('Copy Logs'),
              ),
              OutlinedButton.icon(
                onPressed: () {
                  _logs.clear();
                  setState(() {});
                },
                icon: const Icon(Icons.delete_sweep_outlined),
                label: const Text('Clear Log View'),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: _logs.isEmpty
              ? const Center(child: Text('No logs yet'))
              : ListView.builder(
                  itemCount: _logs.length,
                  itemBuilder: (_, i) => ListTile(
                    dense: true,
                    visualDensity: VisualDensity.compact,
                    title: Text(_logs[i]),
                  ),
                ),
        ),
      ],
    );
  }

  Widget _slider(
    String title,
    double value,
    double min,
    double max,
    ValueChanged<double> onChanged,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$title: ${value.toStringAsFixed(2)}'),
        Slider(value: value, min: min, max: max, onChanged: onChanged),
      ],
    );
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

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    final h = d.inHours;
    return h > 0 ? '${h.toString().padLeft(2, '0')}:$m:$s' : '$m:$s';
  }

  Future<bool> _ensureMediaPermission() async {
    if (!Platform.isAndroid) return true;

    final audio = await Permission.audio.request();
    if (audio.isGranted) return true;

    final storage = await Permission.storage.request();
    if (storage.isGranted) return true;

    if (audio.isPermanentlyDenied || storage.isPermanentlyDenied) {
      _logs.insert(0, '[permission] Permanently denied. Open app settings.');
      await openAppSettings();
    }

    return false;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('MiniAudio Playlist Demo')),
      body: IndexedStack(
        index: _tabIndex,
        children: [_buildPlayerScreen(), _buildEqScreen(), _buildLogsScreen()],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tabIndex,
        onDestinationSelected: (i) => setState(() => _tabIndex = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.playlist_play),
            label: 'Player',
          ),
          NavigationDestination(
            icon: Icon(Icons.equalizer),
            label: 'Equalizer',
          ),
          NavigationDestination(
            icon: Icon(Icons.article_outlined),
            label: 'Logs',
          ),
        ],
      ),
    );
  }
}
