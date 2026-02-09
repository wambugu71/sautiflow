import 'dart:io';
import 'dart:ui';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:miniaudiodart/miniaudiodart.dart';
import 'package:permission_handler/permission_handler.dart';

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
  final MiniAudioPlayer _player = MiniAudioPlayer();
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

  bool _eqEnabled = false;
  bool _reverbEnabled = false;
  bool _lowpassEnabled = false;
  bool _highpassEnabled = false;
  bool _delayEnabled = false;

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
    _player.init();
    final initErr = _player.getLastError();
    if (initErr.isNotEmpty) {
      _logs.insert(0, '[init] $initErr');
    }
    _player.statusStream.listen((s) {
      _status.value = s;
      if (mounted) setState(() {});
    });
    _player.logStream.listen((line) {
      _logs.insert(0, '[${DateTime.now().toIso8601String()}] $line');
      if (_logs.length > 200) {
        _logs.removeRange(200, _logs.length);
      }
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _singleUrlController.dispose();
    _multiUrlController.dispose();
    _status.dispose();
    _player.dispose();
    super.dispose();
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

    // Desktop builds can use native progressive URL decoding (when available
    // in the bundled native library). Mobile currently falls back to
    // download-to-temp until native URL streaming is enabled there.
    if (Platform.isLinux || Platform.isMacOS) {
      return AudioSource.uri(uri);
    }

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

    final sources = <AudioSource>[];
    for (final uri in uris) {
      final src = await _materializeSource(uri);
      if (src != null) sources.add(src);
    }
    if (sources.isEmpty) {
      _logs.insert(
        0,
        '[sources-set] No playable sources after validation/download.',
      );
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

    for (final uri in uris) {
      final src = await _materializeSource(uri);
      if (src == null) continue;
      _playlist.add(src);
      _player.addAudioSource(src);
      final msg = _player.getLastError();
      if (msg.isNotEmpty) {
        _logs.insert(0, '[sources-add] $msg');
      }
    }
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
      allowedExtensions: const ['mp3', 'ogg', 'wav', 'flac', 'm4a', 'aac'],
    );
    if (result == null || result.files.isEmpty) return;

    final sources = result.files
        .where((f) => f.path != null && f.path!.isNotEmpty)
        .map((f) => AudioSource.uri(Uri.file(f.path!)))
        .toList();

    if (sources.isEmpty) return;

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
      allowedExtensions: const ['mp3', 'ogg', 'wav', 'flac', 'm4a', 'aac'],
    );
    if (result == null || result.files.isEmpty) return;

    for (final f in result.files) {
      if (f.path == null || f.path!.isEmpty) continue;
      final src = AudioSource.uri(Uri.file(f.path!));
      _playlist.add(src);
      _player.addAudioSource(src);
      final msg = _player.getLastError();
      if (msg.isNotEmpty) {
        _logs.insert(0, '[add] $msg');
      }
    }
    setState(() {});
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
    final st = _status.value;
    final duration = Duration(
      milliseconds: (st.durationSeconds * 1000).round(),
    );
    final position = Duration(
      milliseconds: (st.positionSeconds * 1000).round(),
    );
    final maxMs = duration.inMilliseconds <= 0
        ? 1.0
        : duration.inMilliseconds.toDouble();
    final posMs = position.inMilliseconds
        .clamp(0, duration.inMilliseconds <= 0 ? 0 : duration.inMilliseconds)
        .toDouble();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _pickSongsAndSetPlaylist,
                  icon: const Icon(Icons.library_music),
                  label: const Text('Pick Playlist'),
                ),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: _addSongs,
                icon: const Icon(Icons.queue_music),
                label: const Text('Add Songs'),
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
        const SizedBox(height: 8),
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
        const Divider(),
        Expanded(
          child: ReorderableListView.builder(
            itemCount: _playlist.length,
            onReorder: (oldIndex, newIndex) {
              if (newIndex > oldIndex) newIndex -= 1;
              final item = _playlist.removeAt(oldIndex);
              _playlist.insert(newIndex, item);
              _player.moveAudioSource(oldIndex, newIndex);
              setState(() {});
            },
            itemBuilder: (context, index) {
              final isCurrent = _status.value.currentIndex == index;
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
          ),
        ),
      ],
    );
  }

  Widget _buildEqScreen() {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        SwitchListTile(
          title: const Text('Enable EQ'),
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
