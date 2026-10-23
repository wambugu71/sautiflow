import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:projectm_visualizer/projectm_visualizer.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProjectMExampleApp());
}

class ProjectMExampleApp extends StatelessWidget {
  const ProjectMExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'libprojectM 4.1.8 × Milkdrop Visualizer',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true).copyWith(
        scaffoldBackgroundColor: const Color(0xFF090A0F),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF00E5FF),
          secondary: Color(0xFF9D4EDD),
          surface: Color(0xFF141722),
        ),
      ),
      home: const VisualizerScreen(),
    );
  }
}

class PresetItem {
  PresetItem({
    required this.name,
    required this.displayName,
    this.filePath,
    this.inlineMilkData,
    this.category = 'General',
  });

  final String name;
  final String displayName;
  final String? filePath;
  final String? inlineMilkData;
  final String category;
}

class VisualizerScreen extends StatefulWidget {
  const VisualizerScreen({super.key});

  @override
  State<VisualizerScreen> createState() => _VisualizerScreenState();
}

class _VisualizerScreenState extends State<VisualizerScreen> {
  ProjectMVisualizer? _controller;
  VisualizerStats? _stats;
  Timer? _telemetryTimer;
  Timer? _autoCycleTimer;

  bool _isInitialized = false;
  bool _isPlaying = true;
  String _activeSongTitle = 'No audio track loaded';
  int _targetFps = 60;
  double _volume = 1.0;
  int _autoCycleSeconds = 0; // 0 = off, 15, 30, 60
  VisualizerQuality _selectedQuality = VisualizerQuality.balanced;
  bool _batterySaver = false;

  // Aspect ratio and fit mode
  double? _selectedAspectRatio = 16 / 9;
  bool _maintainAspectRatio = true;
  BoxFit _selectedFit = BoxFit.contain;

  // Immersive HUD visibility
  bool _showHud = true;
  bool _showSpectrumOverlay = true; // Poweramp-style animated spectrum bars overlay

  final List<PresetItem> _availablePresets = [];
  int _currentPresetIndex = 0;
  String _presetSearchQuery = '';

  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _scanAndInitPresets();
    _initVisualizer();
  }

  void _scanAndInitPresets() {
    // 1. Scan filesystem for presets in tests directory
    final candidateDirs = [
      'presets/tests',
      '../../../presets/tests',
      '../../presets/tests',
      '../presets/tests',
      '${Directory.current.path}/presets/tests',
      '${Directory.current.path}/../../../presets/tests',
    ];

    Directory? foundDir;
    for (final dirPath in candidateDirs) {
      final dir = Directory(dirPath);
      if (dir.existsSync()) {
        foundDir = dir;
        break;
      }
    }

    if (foundDir != null) {
      try {
        final files = foundDir
            .listSync()
            .where((f) => f.path.endsWith('.milk'))
            .toList();
        files.sort((a, b) => a.path.compareTo(b.path));
        for (final file in files) {
          final fileName = file.uri.pathSegments.last;
          final baseName = fileName.replaceAll('.milk', '');
          String cat = 'Wave';
          if (baseName.contains('beatdetect')) cat = 'Beat';
          if (baseName.contains('shader') || baseName.contains('comp')) {
            cat = 'Shader';
          }
          if (baseName.contains('spectrum')) cat = 'Spectrum';

          _availablePresets.add(
            PresetItem(
              name: baseName,
              displayName: _formatDisplayName(baseName),
              filePath: file.path,
              category: cat,
            ),
          );
        }
      } catch (e) {
        debugPrint('Error listing presets: $e');
      }
    }

    // 2. Add fallback embedded presets if none discovered
    if (_availablePresets.isEmpty) {
      _availablePresets.addAll([
        PresetItem(
          name: 'neon_hyperspace',
          displayName: 'Neon Hyperspace Pulse',
          category: 'Hyperspace',
          inlineMilkData: _presetNeonHyperspace,
        ),
        PresetItem(
          name: 'cosmic_kaleidoscope',
          displayName: 'Cosmic Kaleidoscope',
          category: 'Cosmic',
          inlineMilkData: _presetCosmicKaleidoscope,
        ),
        PresetItem(
          name: 'audio_spectrum_wave',
          displayName: 'Audio Spectrum Waveform',
          category: 'Spectrum',
          inlineMilkData: _presetSpectrumWave,
        ),
      ]);
    }
  }

  String _formatDisplayName(String baseName) {
    return baseName
        .replaceAll(RegExp(r'^\d+-'), '')
        .replaceAll('-', ' ')
        .replaceAll('_', ' ')
        .split(' ')
        .map(
          (w) => w.isNotEmpty ? '${w[0].toUpperCase()}${w.substring(1)}' : '',
        )
        .join(' ');
  }

  Future<void> _initVisualizer() async {
    try {
      final controller = await ProjectMVisualizer.create(
        width: 960,
        height: 540,
      );
      controller.setFps(_targetFps);
      controller.setMeshSize(32, 24);
      controller.setSoftCutDuration(1.5);
      controller.setBatterySaver(_batterySaver);

      // Try playing the bundled groove track
      await _playBundledSampleGroove(controller);

      // Load initial preset
      if (_availablePresets.isNotEmpty) {
        // Prefer beat detect or spectrum preset if available
        final beatIdx = _availablePresets.indexWhere(
          (p) => p.name.contains('300') || p.name.contains('beat'),
        );
        final initialIdx = beatIdx >= 0 ? beatIdx : 0;
        _loadPreset(controller, initialIdx);
      }

      int statsCounter = 0;
      _telemetryTimer = Timer.periodic(const Duration(milliseconds: 150), (_) {
        if (mounted && _controller != null) {
          final s = _controller!.getStats();
          setState(() {
            _stats = s;
          });
          statsCounter++;
          if (statsCounter % 7 == 0) {
            stdout.writeln(
              'PMVIS_BENCHMARK: FPS=${s.fps.toStringAsFixed(1)}, frameTime=${s.frameTimeMs.toStringAsFixed(2)}ms, frames=${s.framesRendered}',
            );
          }
        }
      });

      setState(() {
        _controller = controller;
        _isInitialized = true;
      });
    } catch (e) {
      debugPrint('Failed to initialize visualizer: $e');
    }
  }

  Future<void> _playBundledSampleGroove([ProjectMVisualizer? ctrl]) async {
    final controller = ctrl ?? _controller;
    if (controller == null) return;

    try {
      final byteData = await rootBundle.load('assets/sample_groove.wav');
      final tempDir = await Directory.systemTemp.createTemp('pmvis_song_');
      final tempFile = File('${tempDir.path}/sample_groove.wav');
      await tempFile.writeAsBytes(
        byteData.buffer.asUint8List(
          byteData.offsetInBytes,
          byteData.lengthInBytes,
        ),
        flush: true,
      );

      final success = await controller.playAudioFile(tempFile.path);
      if (success) {
        setState(() {
          _activeSongTitle = 'Sample Electronic Groove (124 BPM)';
          _isPlaying = true;
        });
      }
    } catch (e) {
      debugPrint(
        'Failed loading bundled sample audio, falling back to 60Hz sine: $e',
      );
      controller.playSine(frequencyHz: 60.0);
      setState(() {
        _activeSongTitle = 'Synthetic 60Hz Sub-Bass';
        _isPlaying = true;
      });
    }
  }

  void _loadPreset(ProjectMVisualizer controller, int index) {
    if (index < 0 || index >= _availablePresets.length) return;
    _currentPresetIndex = index;
    final item = _availablePresets[index];

    if (item.filePath != null && File(item.filePath!).existsSync()) {
      controller.loadPresetFile(item.filePath!, smoothTransition: true);
    } else if (item.inlineMilkData != null) {
      controller.loadPresetData(item.inlineMilkData!, smoothTransition: true);
    } else {
      controller.loadPresetData(_presetNeonHyperspace, smoothTransition: true);
    }
    setState(() {});
  }

  void _nextPreset() {
    if (_controller == null || _availablePresets.isEmpty) return;
    _loadPreset(
      _controller!,
      (_currentPresetIndex + 1) % _availablePresets.length,
    );
  }

  void _prevPreset() {
    if (_controller == null || _availablePresets.isEmpty) return;
    _loadPreset(
      _controller!,
      (_currentPresetIndex - 1 + _availablePresets.length) %
          _availablePresets.length,
    );
  }

  void _randomPreset() {
    if (_controller == null || _availablePresets.isEmpty) return;
    final rng = Random();
    int nextIdx;
    do {
      nextIdx = rng.nextInt(_availablePresets.length);
    } while (nextIdx == _currentPresetIndex && _availablePresets.length > 1);
    _loadPreset(_controller!, nextIdx);
  }

  void _togglePlayPause() {
    if (_controller == null) return;
    if (_isPlaying) {
      _controller!.pauseAudio();
    } else {
      _controller!.resumeAudio();
    }
    setState(() {
      _isPlaying = !_isPlaying;
    });
  }

  void _toggleFps() {
    if (_controller == null) return;
    final nextFps = _targetFps == 30 ? 60 : (_targetFps == 60 ? 120 : 30);
    _controller!.setFps(nextFps);
    setState(() {
      _targetFps = nextFps;
    });
  }

  void _cycleQuality() {
    setState(() {
      if (_selectedQuality == VisualizerQuality.balanced) {
        _selectedQuality = VisualizerQuality.eco;
        _controller?.setMeshSize(24, 18);
      } else if (_selectedQuality == VisualizerQuality.eco) {
        _selectedQuality = VisualizerQuality.high;
        _controller?.setMeshSize(32, 24);
      } else {
        _selectedQuality = VisualizerQuality.balanced;
        _controller?.setMeshSize(32, 24);
      }
    });
  }

  void _toggleBatterySaver() {
    setState(() {
      _batterySaver = !_batterySaver;
      _controller?.setBatterySaver(_batterySaver);
    });
  }

  void _toggleAutoCycle() {
    final nextInterval = switch (_autoCycleSeconds) {
      0 => 15,
      15 => 30,
      30 => 60,
      _ => 0,
    };
    _autoCycleTimer?.cancel();
    if (nextInterval > 0) {
      _autoCycleTimer = Timer.periodic(Duration(seconds: nextInterval), (_) {
        if (_isPlaying) _nextPreset();
      });
    }
    setState(() {
      _autoCycleSeconds = nextInterval;
    });
  }

  void _cycleAspectRatio() {
    setState(() {
      if (_selectedAspectRatio == 16 / 9) {
        _selectedAspectRatio = 4 / 3;
        _maintainAspectRatio = true;
      } else if (_selectedAspectRatio == 4 / 3) {
        _selectedAspectRatio = 1.0;
        _maintainAspectRatio = true;
      } else if (_selectedAspectRatio == 1.0) {
        _selectedAspectRatio = null;
        _maintainAspectRatio = false;
      } else {
        _selectedAspectRatio = 16 / 9;
        _maintainAspectRatio = true;
      }
    });
  }

  String _aspectRatioLabel() {
    if (!_maintainAspectRatio || _selectedAspectRatio == null) return 'Free';
    if ((_selectedAspectRatio! - (16 / 9)).abs() < 0.01) return '16:9';
    if ((_selectedAspectRatio! - (4 / 3)).abs() < 0.01) return '4:3';
    if ((_selectedAspectRatio! - 1.0).abs() < 0.01) return '1:1';
    return '${_selectedAspectRatio!.toStringAsFixed(2)}:1';
  }

  void _cycleFit() {
    setState(() {
      if (_selectedFit == BoxFit.contain) {
        _selectedFit = BoxFit.cover;
      } else if (_selectedFit == BoxFit.cover) {
        _selectedFit = BoxFit.fill;
      } else {
        _selectedFit = BoxFit.contain;
      }
    });
  }

  String _fitLabel() {
    switch (_selectedFit) {
      case BoxFit.contain:
        return 'Contain';
      case BoxFit.cover:
        return 'Cover';
      case BoxFit.fill:
        return 'Stretch';
      default:
        return 'Fit';
    }
  }

  void _toggleHud() {
    setState(() {
      _showHud = !_showHud;
    });
  }

  void _adjustVolume(double delta) {
    setState(() {
      _volume = (_volume + delta).clamp(0.0, 1.0);
      _controller?.setVolume(_volume);
    });
  }

  void _showDisplaySettingsSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              decoration: BoxDecoration(
                color: const Color(0xFF13151F).withValues(alpha: 0.96),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: const Color(0xFF00E5FF).withValues(alpha: 0.3),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.7),
                    blurRadius: 30,
                    spreadRadius: 5,
                  ),
                ],
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Row(
                          children: [
                            Icon(
                              Icons.tune_rounded,
                              color: Color(0xFF00E5FF),
                              size: 22,
                            ),
                            SizedBox(width: 10),
                            Text(
                              'Visualizer & Display Settings',
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.white70),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                    const Divider(color: Colors.white12),
                    const SizedBox(height: 8),

                    // 1. Aspect Ratio
                    Text(
                      'ASPECT RATIO — ${_aspectRatioLabel()}',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Colors.white54,
                        letterSpacing: 1.0,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _buildSettingsChoiceChip(
                          label: '16:9 Widescreen',
                          isSelected:
                              _maintainAspectRatio &&
                              _selectedAspectRatio == 16 / 9,
                          onSelected: () {
                            setState(() {
                              _selectedAspectRatio = 16 / 9;
                              _maintainAspectRatio = true;
                            });
                            setSheetState(() {});
                          },
                        ),
                        _buildSettingsChoiceChip(
                          label: '4:3 Vintage CRT',
                          isSelected:
                              _maintainAspectRatio &&
                              _selectedAspectRatio == 4 / 3,
                          onSelected: () {
                            setState(() {
                              _selectedAspectRatio = 4 / 3;
                              _maintainAspectRatio = true;
                            });
                            setSheetState(() {});
                          },
                        ),
                        _buildSettingsChoiceChip(
                          label: '1:1 Square',
                          isSelected:
                              _maintainAspectRatio &&
                              _selectedAspectRatio == 1.0,
                          onSelected: () {
                            setState(() {
                              _selectedAspectRatio = 1.0;
                              _maintainAspectRatio = true;
                            });
                            setSheetState(() {});
                          },
                        ),
                        _buildSettingsChoiceChip(
                          label: 'Screen Freeform',
                          isSelected:
                              !_maintainAspectRatio ||
                              _selectedAspectRatio == null,
                          onSelected: () {
                            setState(() {
                              _selectedAspectRatio = null;
                              _maintainAspectRatio = false;
                            });
                            setSheetState(() {});
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // 2. Fit Scaling Mode
                    Text(
                      'SCALING & FIT — ${_fitLabel()}',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Colors.white54,
                        letterSpacing: 1.0,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _buildSettingsChoiceChip(
                          label: 'Contain (Letterbox)',
                          isSelected: _selectedFit == BoxFit.contain,
                          onSelected: () {
                            setState(() => _selectedFit = BoxFit.contain);
                            setSheetState(() {});
                          },
                        ),
                        _buildSettingsChoiceChip(
                          label: 'Cover (Full-Bleed)',
                          isSelected: _selectedFit == BoxFit.cover,
                          onSelected: () {
                            setState(() => _selectedFit = BoxFit.cover);
                            setSheetState(() {});
                          },
                        ),
                        _buildSettingsChoiceChip(
                          label: 'Stretch',
                          isSelected: _selectedFit == BoxFit.fill,
                          onSelected: () {
                            setState(() => _selectedFit = BoxFit.fill);
                            setSheetState(() {});
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // 3. Quality Profile
                    const Text(
                      'RENDER QUALITY & RESOLUTION',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Colors.white54,
                        letterSpacing: 1.0,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _buildSettingsChoiceChip(
                          label: '360p Eco (Best Battery)',
                          isSelected: _selectedQuality == VisualizerQuality.eco,
                          onSelected: () {
                            setState(() {
                              _selectedQuality = VisualizerQuality.eco;
                              _controller?.setMeshSize(24, 18);
                            });
                            setSheetState(() {});
                          },
                        ),
                        _buildSettingsChoiceChip(
                          label: '540p Balanced (Smooth)',
                          isSelected:
                              _selectedQuality == VisualizerQuality.balanced,
                          onSelected: () {
                            setState(() {
                              _selectedQuality = VisualizerQuality.balanced;
                              _controller?.setMeshSize(32, 24);
                            });
                            setSheetState(() {});
                          },
                        ),
                        _buildSettingsChoiceChip(
                          label: '720p HD (Ultra Crisp)',
                          isSelected:
                              _selectedQuality == VisualizerQuality.high,
                          onSelected: () {
                            setState(() {
                              _selectedQuality = VisualizerQuality.high;
                              _controller?.setMeshSize(32, 24);
                            });
                            setSheetState(() {});
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // 4. Target Frame Rate
                    const Text(
                      'TARGET FRAME RATE',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Colors.white54,
                        letterSpacing: 1.0,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _buildSettingsChoiceChip(
                          label: '30 FPS',
                          isSelected: _targetFps == 30,
                          onSelected: () {
                            setState(() => _targetFps = 30);
                            _controller?.setFps(30);
                            setSheetState(() {});
                          },
                        ),
                        _buildSettingsChoiceChip(
                          label: '60 FPS (Default)',
                          isSelected: _targetFps == 60,
                          onSelected: () {
                            setState(() => _targetFps = 60);
                            _controller?.setFps(60);
                            setSheetState(() {});
                          },
                        ),
                        _buildSettingsChoiceChip(
                          label: '120 FPS (High-Hz)',
                          isSelected: _targetFps == 120,
                          onSelected: () {
                            setState(() => _targetFps = 120);
                            _controller?.setFps(120);
                            setSheetState(() {});
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // 5. Battery Saver
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text(
                        'Battery Saver Mode',
                        style: TextStyle(color: Colors.white, fontSize: 14),
                      ),
                      subtitle: const Text(
                        'Throttles to 15 FPS when silent',
                        style: TextStyle(color: Colors.white38, fontSize: 11),
                      ),
                      value: _batterySaver,
                      activeThumbColor: const Color(0xFF00E676),
                      onChanged: (val) {
                        setState(() {
                          _batterySaver = val;
                          _controller?.setBatterySaver(val);
                        });
                        setSheetState(() {});
                      },
                    ),
                    const SizedBox(height: 8),

                    // 6. Auto-Cycle Presets
                    const Text(
                      'AUTO-CYCLE PRESETS',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Colors.white54,
                        letterSpacing: 1.0,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final sec in [0, 15, 30, 60])
                          _buildSettingsChoiceChip(
                            label: sec == 0 ? 'Off' : '${sec}s',
                            isSelected: _autoCycleSeconds == sec,
                            onSelected: () {
                              _autoCycleTimer?.cancel();
                              if (sec > 0) {
                                _autoCycleTimer = Timer.periodic(
                                  Duration(seconds: sec),
                                  (_) {
                                    if (_isPlaying) _nextPreset();
                                  },
                                );
                              }
                              setState(() => _autoCycleSeconds = sec);
                              setSheetState(() {});
                            },
                          ),
                      ],
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

  Widget _buildSettingsChoiceChip({
    required String label,
    required bool isSelected,
    required VoidCallback onSelected,
  }) {
    return InkWell(
      onTap: onSelected,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFF00E5FF).withValues(alpha: 0.2)
              : Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? const Color(0xFF00E5FF) : Colors.white12,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            color: isSelected ? const Color(0xFF00E5FF) : Colors.white70,
          ),
        ),
      ),
    );
  }

  /// Pick an audio song file from the local machine (MP3, WAV, FLAC, OGG, M4A)
  Future<void> _pickSongFile() async {
    try {
      final files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['mp3', 'wav', 'flac', 'ogg', 'm4a', 'aac'],
        dialogTitle: 'Pick an Audio Song for Milkdrop Visualization',
      );

      if (files.isNotEmpty) {
        final path = files.first.path;
        if (path != null && File(path).existsSync()) {
          final success = await _controller?.playAudioFile(path);
          if (success == true) {
            setState(() {
              _activeSongTitle = files.first.name;
              _isPlaying = true;
            });
          }
        }
      }
    } catch (e) {
      debugPrint('Error picking song file: $e');
    }
  }

  /// Pick a custom .milk preset file, .zip archive, or Poweramp .apk preset pack from disk
  Future<void> _pickPresetOrPack() async {
    try {
      final files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['milk', 'zip', 'apk'],
        dialogTitle: 'Select Milkdrop Preset (.milk) or Pack (.zip, .apk)',
      );

      if (files.isNotEmpty) {
        final path = files.first.path;
        if (path != null && File(path).existsSync()) {
          final fileName = files.first.name;
          final lower = fileName.toLowerCase();

          if (lower.endsWith('.zip') || lower.endsWith('.apk')) {
            await _unpackAndLoadArchive(path, fileName);
          } else {
            final newItem = PresetItem(
              name: fileName,
              displayName: _formatDisplayName(fileName.replaceAll('.milk', '')),
              filePath: path,
              category: 'Custom',
            );
            setState(() {
              _availablePresets.insert(0, newItem);
              _currentPresetIndex = 0;
            });
            if (_controller != null) {
              _controller!.loadPresetFile(path, smoothTransition: true);
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Error picking preset file/pack: $e');
    }
  }

  /// Unpack a .zip or Poweramp .apk preset pack and load its .milk files and textures
  Future<void> _unpackAndLoadArchive(String archivePath, String archiveName) async {
    try {
      final bytes = await File(archivePath).readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);
      final tempDir = await Directory.systemTemp.createTemp('pmvis_pack_');
      final texturesDir = Directory('${tempDir.path}/textures');
      await texturesDir.create(recursive: true);

      final List<PresetItem> newPresets = [];
      final packTitle = archiveName.replaceAll(RegExp(r'\.(zip|apk)$', caseSensitive: false), '');

      for (final file in archive) {
        final filename = file.name;
        if (file.isFile) {
          final data = file.content as List<int>;
          final lower = filename.toLowerCase();
          if (lower.endsWith('.milk')) {
            final simpleName = filename.split('/').last;
            final outFile = File('${tempDir.path}/$simpleName');
            await outFile.writeAsBytes(data, flush: true);
            final baseName = simpleName.replaceAll('.milk', '');
            newPresets.add(
              PresetItem(
                name: baseName,
                displayName: _formatDisplayName(baseName),
                filePath: outFile.path,
                category: 'Pack: $packTitle',
              ),
            );
          } else if (lower.contains('texture') ||
                     lower.endsWith('.jpg') ||
                     lower.endsWith('.png') ||
                     lower.endsWith('.tga') ||
                     lower.endsWith('.bmp')) {
            final simpleName = filename.split('/').last;
            final outFile = File('${texturesDir.path}/$simpleName');
            await outFile.writeAsBytes(data, flush: true);
          }
        }
      }

      if (newPresets.isNotEmpty) {
        _controller?.setTextureSearchPath(texturesDir.path);

        setState(() {
          _availablePresets.insertAll(0, newPresets);
          _currentPresetIndex = 0;
        });

        if (_controller != null && newPresets.first.filePath != null) {
          _controller!.loadPresetFile(newPresets.first.filePath!, smoothTransition: true);
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Loaded ${newPresets.length} presets from $archiveName'),
              backgroundColor: const Color(0xFF00E5FF),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('No .milk presets found inside $archiveName'),
              backgroundColor: Colors.amber,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Error unpacking preset archive: $e');
    }
  }

  void _openPresetDrawer() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final filtered = _availablePresets.where((p) {
              if (_presetSearchQuery.isEmpty) return true;
              return p.displayName.toLowerCase().contains(
                    _presetSearchQuery.toLowerCase(),
                  ) ||
                  p.name.toLowerCase().contains(
                    _presetSearchQuery.toLowerCase(),
                  );
            }).toList();

            return Container(
              height: MediaQuery.sizeOf(context).height * 0.7,
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
              decoration: BoxDecoration(
                color: const Color(0xFF13151F).withValues(alpha: 0.95),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: const Color(0xFF00E5FF).withValues(alpha: 0.3),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.7),
                    blurRadius: 30,
                    spreadRadius: 5,
                  ),
                ],
              ),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            const Icon(
                              Icons.auto_awesome,
                              color: Color(0xFF00E5FF),
                              size: 24,
                            ),
                            const SizedBox(width: 12),
                            Text(
                              'Milkdrop Presets (${_availablePresets.length})',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.white70),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 8,
                    ),
                    child: TextField(
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: 'Search presets...',
                        hintStyle: const TextStyle(color: Colors.white38),
                        prefixIcon: const Icon(
                          Icons.search,
                          color: Color(0xFF00E5FF),
                        ),
                        filled: true,
                        fillColor: Colors.white.withValues(alpha: 0.06),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      onChanged: (val) {
                        setModalState(() => _presetSearchQuery = val);
                      },
                    ),
                  ),
                  Expanded(
                    child: ListView.separated(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      itemCount: filtered.length,
                      separatorBuilder: (_, _) =>
                          const Divider(height: 1, color: Colors.white10),
                      itemBuilder: (context, idx) {
                        final item = filtered[idx];
                        final isSelected =
                            _availablePresets.indexOf(item) ==
                            _currentPresetIndex;

                        return ListTile(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          tileColor: isSelected
                              ? const Color(0xFF00E5FF).withValues(alpha: 0.15)
                              : null,
                          leading: Icon(
                            isSelected ? Icons.check_circle : Icons.blur_on,
                            color: isSelected
                                ? const Color(0xFF00E5FF)
                                : Colors.white54,
                          ),
                          title: Text(
                            item.displayName,
                            style: TextStyle(
                              color: isSelected
                                  ? const Color(0xFF00E5FF)
                                  : Colors.white,
                              fontWeight: isSelected
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                            ),
                          ),
                          subtitle: Text(
                            item.name,
                            style: const TextStyle(
                              fontSize: 11,
                              color: Colors.white38,
                            ),
                          ),
                          trailing: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              item.category,
                              style: const TextStyle(
                                fontSize: 10,
                                color: Colors.white70,
                              ),
                            ),
                          ),
                          onTap: () {
                            final originalIndex = _availablePresets.indexOf(
                              item,
                            );
                            if (_controller != null && originalIndex >= 0) {
                              _loadPreset(_controller!, originalIndex);
                            }
                            Navigator.pop(context);
                          },
                        );
                      },
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

  void _showAudioSourceSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          margin: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: const Color(0xFF13151F).withValues(alpha: 0.95),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: const Color(0xFF00E5FF).withValues(alpha: 0.3),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Row(
                  children: [
                    Icon(
                      Icons.library_music,
                      color: Color(0xFF00E5FF),
                      size: 22,
                    ),
                    SizedBox(width: 12),
                    Text(
                      'Choose Audio Source',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(color: Colors.white12),
              ListTile(
                leading: const Icon(Icons.file_open, color: Color(0xFF00E5FF)),
                title: const Text('Pick Song File from Device...'),
                subtitle: const Text(
                  'MP3, WAV, FLAC, OGG, M4A',
                  style: TextStyle(color: Colors.white38),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _pickSongFile();
                },
              ),
              ListTile(
                leading: const Icon(Icons.album, color: Color(0xFF9D4EDD)),
                title: const Text('Sample Electronic Groove (124 BPM)'),
                subtitle: const Text(
                  'Punchy sub-bass, snare, arp chords',
                  style: TextStyle(color: Colors.white38),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _playBundledSampleGroove();
                },
              ),
              ListTile(
                leading: const Icon(Icons.graphic_eq, color: Color(0xFFFF007A)),
                title: const Text('Synthetic 60Hz Deep Sub-Bass'),
                subtitle: const Text(
                  'Pure low-end sine wave test',
                  style: TextStyle(color: Colors.white38),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _controller?.playSine(frequencyHz: 60.0);
                  setState(() {
                    _activeSongTitle = 'Synthetic 60Hz Sub-Bass';
                    _isPlaying = true;
                  });
                },
              ),
              ListTile(
                leading: const Icon(Icons.flash_on, color: Color(0xFFFFB703)),
                title: const Text('Synthetic 120Hz Punch Tone'),
                subtitle: const Text(
                  'Mid-bass club frequency',
                  style: TextStyle(color: Colors.white38),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _controller?.playSine(frequencyHz: 120.0);
                  setState(() {
                    _activeSongTitle = 'Synthetic 120Hz Punch';
                    _isPlaying = true;
                  });
                },
              ),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );
  }

  void _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return;
    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowRight:
        _nextPreset();
        break;
      case LogicalKeyboardKey.arrowLeft:
        _prevPreset();
        break;
      case LogicalKeyboardKey.space:
        _togglePlayPause();
        break;
      case LogicalKeyboardKey.keyR:
        _randomPreset();
        break;
      case LogicalKeyboardKey.keyO:
        _pickSongFile();
        break;
      case LogicalKeyboardKey.keyP:
        _openPresetDrawer();
        break;
      case LogicalKeyboardKey.keyM:
        _pickPresetOrPack();
        break;
      case LogicalKeyboardKey.keyA:
        _cycleAspectRatio();
        break;
      case LogicalKeyboardKey.keyF:
        _cycleFit();
        break;
      case LogicalKeyboardKey.keyH:
        _toggleHud();
        break;
      case LogicalKeyboardKey.arrowUp:
        _adjustVolume(0.05);
        break;
      case LogicalKeyboardKey.arrowDown:
        _adjustVolume(-0.05);
        break;
    }
  }

  @override
  void dispose() {
    _telemetryTimer?.cancel();
    _autoCycleTimer?.cancel();
    _controller?.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized || _controller == null) {
      return const Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 48,
                height: 48,
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  valueColor: AlwaysStoppedAnimation(Color(0xFF00E5FF)),
                ),
              ),
              SizedBox(height: 24),
              Text(
                'libprojectM 4.1.8 & miniaudio core loading...',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 16,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final stats = _stats;
    final fps = stats?.fps ?? 0.0;
    final frameTime = stats?.frameTimeMs ?? 0.0;
    final bass = stats?.bass ?? 0.0;
    final mid = stats?.mid ?? 0.0;
    final treb = stats?.treb ?? 0.0;
    final activePreset = _availablePresets.isNotEmpty
        ? _availablePresets[_currentPresetIndex]
        : null;

    return KeyboardListener(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: Scaffold(
        body: Stack(
          fit: StackFit.expand,
          children: [
            // 1. Fullscreen High-Performance projectM Visualizer Surface
            ProjectMWidget(
              controller: _controller!,
              fit: _selectedFit,
              aspectRatio: _selectedAspectRatio,
              maintainAspectRatio: _maintainAspectRatio,
              quality: _selectedQuality,
            ),

            // 1b. Poweramp-style Reactive Spectrum Bars Overlay
            if (_showSpectrumOverlay)
              Positioned(
                bottom: _showHud ? 116 : 24,
                left: 48,
                right: 48,
                height: 80,
                child: PowerampSpectrumBars(
                  bass: bass,
                  mid: mid,
                  treb: treb,
                  isPlaying: _isPlaying,
                ),
              ),

            if (_showHud) ...[
              // 2. Top Header HUD Bar
              Positioned(
                top: 24,
                left: 24,
                right: 24,
                child: Row(
                  children: [
                    // Left: FPS & Frame Time Badge
                    _buildGlassCard(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: fps >= 55
                                  ? const Color(0xFF00E5FF)
                                  : const Color(0xFFFFB703),
                              boxShadow: [
                                BoxShadow(
                                  color:
                                      (fps >= 55
                                              ? const Color(0xFF00E5FF)
                                              : const Color(0xFFFFB703))
                                          .withValues(alpha: 0.6),
                                  blurRadius: 6,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            '${fps.toStringAsFixed(1)} FPS',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '(${frameTime.toStringAsFixed(1)}ms)',
                            style: const TextStyle(
                              fontSize: 11,
                              color: Colors.white54,
                            ),
                          ),
                          const SizedBox(width: 12),
                          InkWell(
                            onTap: _toggleFps,
                            borderRadius: BorderRadius.circular(10),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: _targetFps == 120
                                    ? const Color(0xFF7C4DFF)
                                          .withValues(alpha: 0.3)
                                    : (_targetFps == 30
                                          ? const Color(0xFF00E676)
                                                .withValues(alpha: 0.2)
                                          : Colors.white.withValues(
                                              alpha: 0.08,
                                            )),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: _targetFps == 120
                                      ? const Color(0xFF9D4EDD)
                                      : (_targetFps == 30
                                            ? const Color(0xFF00E676)
                                            : Colors.white24),
                                ),
                              ),
                              child: Text(
                                '${_targetFps}Hz',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: _targetFps == 120
                                      ? const Color(0xFFB388FF)
                                      : (_targetFps == 30
                                            ? const Color(0xFF00E676)
                                            : Colors.white70),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          InkWell(
                            onTap: _cycleQuality,
                            borderRadius: BorderRadius.circular(10),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFF00E5FF)
                                    .withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: const Color(0xFF00E5FF)
                                      .withValues(alpha: 0.4),
                                ),
                              ),
                              child: Text(
                                _selectedQuality == VisualizerQuality.eco
                                    ? '360p (Eco)'
                                    : (_selectedQuality ==
                                              VisualizerQuality.balanced
                                          ? '540p (Smooth)'
                                          : '720p (HD)'),
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF00E5FF),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          InkWell(
                            onTap: _toggleBatterySaver,
                            borderRadius: BorderRadius.circular(10),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: _batterySaver
                                    ? const Color(0xFF00E676)
                                          .withValues(alpha: 0.25)
                                    : Colors.white.withValues(alpha: 0.06),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: _batterySaver
                                      ? const Color(0xFF00E676)
                                      : Colors.white24,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.eco,
                                    size: 13,
                                    color: _batterySaver
                                        ? const Color(0xFF00E676)
                                        : Colors.white54,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    _batterySaver ? 'Saver On' : 'Saver Off',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: _batterySaver
                                          ? const Color(0xFF00E676)
                                          : Colors.white54,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const Spacer(),

                    // Center: 3-Band Audio Reactivity Meter (Bass, Mid, Treble)
                    _buildGlassCard(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _buildVuBar('BASS', bass, const Color(0xFF00E5FF)),
                          const SizedBox(width: 14),
                          _buildVuBar('MID', mid, const Color(0xFF9D4EDD)),
                          const SizedBox(width: 14),
                          _buildVuBar('TREB', treb, const Color(0xFFFF007A)),
                        ],
                      ),
                    ),

                    const Spacer(),

                    // Right: Action Buttons (Pick Song, Pick .milk, Auto-Cycle)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Spectrum Bars Toggle Pill
                        _buildPillButton(
                          icon: Icons.equalizer,
                          label: _showSpectrumOverlay ? 'Bars ON' : 'Bars OFF',
                          isActive: _showSpectrumOverlay,
                          onTap: () {
                            setState(() {
                              _showSpectrumOverlay = !_showSpectrumOverlay;
                            });
                          },
                        ),
                        const SizedBox(width: 10),

                        // Auto-Cycle Pill
                        _buildPillButton(
                          icon: Icons.sync,
                          label: _autoCycleSeconds > 0
                              ? 'Auto ${_autoCycleSeconds}s'
                              : 'Auto Off',
                          isActive: _autoCycleSeconds > 0,
                          onTap: _toggleAutoCycle,
                        ),
                        const SizedBox(width: 10),

                        // Pick Song Button
                        _buildGradientButton(
                          icon: Icons.music_note,
                          label: 'Pick Song',
                          gradient: const LinearGradient(
                            colors: [Color(0xFF00E5FF), Color(0xFF0072FF)],
                          ),
                          onTap: _showAudioSourceSheet,
                        ),
                        const SizedBox(width: 10),

                        // Load Preset / Pack (.milk, .zip, .apk) Button
                        _buildGradientButton(
                          icon: Icons.auto_awesome,
                          label: 'Load Preset/Pack',
                          gradient: const LinearGradient(
                            colors: [Color(0xFF9D4EDD), Color(0xFFFF007A)],
                          ),
                          onTap: _pickPresetOrPack,
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // 3. Floating Bottom Control Deck
              Positioned(
                bottom: 24,
                left: 32,
                right: 32,
                child: _buildGlassCard(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 14,
                  ),
                  child: Row(
                    children: [
                      // Preset Selector & Label
                      InkWell(
                        onTap: _openPresetDrawer,
                        borderRadius: BorderRadius.circular(12),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF00E5FF)
                                      .withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Icon(
                                  Icons.view_carousel,
                                  color: Color(0xFF00E5FF),
                                  size: 20,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Row(
                                    children: [
                                      Text(
                                        'MILKDROP PRESET',
                                        style: TextStyle(
                                          fontSize: 10,
                                          letterSpacing: 1.2,
                                          color: Colors.white38,
                                        ),
                                      ),
                                      SizedBox(width: 4),
                                      Icon(
                                        Icons.arrow_drop_down,
                                        color: Colors.white38,
                                        size: 14,
                                      ),
                                    ],
                                  ),
                                  ConstrainedBox(
                                    constraints: const BoxConstraints(
                                      maxWidth: 240,
                                    ),
                                    child: Text(
                                      activePreset?.displayName ??
                                          'Default Preset',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),

                      const Spacer(),

                      // Playback Controls
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Shuffle / Random Preset
                          IconButton(
                            icon: const Icon(Icons.shuffle),
                            color: Colors.white70,
                            iconSize: 22,
                            tooltip: 'Random Preset (R)',
                            onPressed: _randomPreset,
                          ),

                          // Previous Preset
                          IconButton(
                            icon: const Icon(Icons.skip_previous_rounded),
                            color: Colors.white,
                            iconSize: 28,
                            tooltip: 'Previous Preset (←)',
                            onPressed: _prevPreset,
                          ),

                          // Play / Pause Audio
                          Container(
                            margin: const EdgeInsets.symmetric(horizontal: 4),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: const LinearGradient(
                                colors: [Color(0xFF00E5FF), Color(0xFF7C4DFF)],
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFF00E5FF)
                                      .withValues(alpha: 0.4),
                                  blurRadius: 16,
                                  spreadRadius: 1,
                                ),
                              ],
                            ),
                            child: IconButton(
                              icon: Icon(
                                _isPlaying
                                    ? Icons.pause_rounded
                                    : Icons.play_arrow_rounded,
                              ),
                              color: Colors.black,
                              iconSize: 32,
                              tooltip: _isPlaying
                                  ? 'Pause Audio (Space)'
                                  : 'Play Audio (Space)',
                              onPressed: _togglePlayPause,
                            ),
                          ),

                          // Next Preset
                          IconButton(
                            icon: const Icon(Icons.skip_next_rounded),
                            color: Colors.white,
                            iconSize: 28,
                            tooltip: 'Next Preset (→)',
                            onPressed: _nextPreset,
                          ),
                        ],
                      ),

                      const Spacer(),

                      // Active Song Track Info & Volume
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          InkWell(
                            onTap: _showAudioSourceSheet,
                            borderRadius: BorderRadius.circular(8),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Text(
                                        'AUDIO TRACK',
                                        style: TextStyle(
                                          fontSize: 10,
                                          letterSpacing: 1.2,
                                          color: Colors.white38,
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      Icon(
                                        _isPlaying
                                            ? Icons.equalizer
                                            : Icons.music_off,
                                        color: _isPlaying
                                            ? const Color(0xFF00E5FF)
                                            : Colors.white38,
                                        size: 14,
                                      ),
                                    ],
                                  ),
                                  ConstrainedBox(
                                    constraints: const BoxConstraints(
                                      maxWidth: 200,
                                    ),
                                    child: Text(
                                      _activeSongTitle,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),

                          const SizedBox(width: 14),

                          // Volume Control
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: Icon(
                                  _volume == 0
                                      ? Icons.volume_off
                                      : Icons.volume_up,
                                  color: Colors.white70,
                                  size: 20,
                                ),
                                onPressed: () {
                                  final next = _volume > 0 ? 0.0 : 1.0;
                                  setState(() => _volume = next);
                                  _controller?.setVolume(next);
                                },
                              ),
                              SizedBox(
                                width: 80,
                                child: SliderTheme(
                                  data: SliderTheme.of(context).copyWith(
                                    trackHeight: 3,
                                    thumbShape: const RoundSliderThumbShape(
                                      enabledThumbRadius: 5,
                                    ),
                                    activeTrackColor: const Color(0xFF00E5FF),
                                    inactiveTrackColor: Colors.white12,
                                    thumbColor: Colors.white,
                                  ),
                                  child: Slider(
                                    value: _volume,
                                    min: 0.0,
                                    max: 1.0,
                                    onChanged: (v) {
                                      setState(() => _volume = v);
                                      _controller?.setVolume(v);
                                    },
                                  ),
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(width: 8),

                          IconButton(
                            icon: const Icon(Icons.tune_rounded),
                            color: Colors.white70,
                            iconSize: 20,
                            tooltip: 'Display Settings',
                            onPressed: _showDisplaySettingsSheet,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildVuBar(String label, double value, Color color) {
    final clamped = value.clamp(0.0, 1.0);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.bold,
            color: color.withValues(alpha: 0.8),
          ),
        ),
        const SizedBox(width: 6),
        Container(
          width: 38,
          height: 6,
          decoration: BoxDecoration(
            color: Colors.white10,
            borderRadius: BorderRadius.circular(3),
          ),
          alignment: Alignment.centerLeft,
          child: AnimatedFractionallySizedBox(
            duration: const Duration(milliseconds: 100),
            widthFactor: clamped,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(3),
                gradient: LinearGradient(
                  colors: [color.withValues(alpha: 0.6), color],
                ),
                boxShadow: [
                  BoxShadow(color: color.withValues(alpha: 0.5), blurRadius: 4),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildGlassCard({required Widget child, EdgeInsetsGeometry? padding}) {
    return Container(
      padding:
          padding ?? const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF141722).withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.5),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _buildPillButton({
    required IconData icon,
    required String label,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isActive
              ? const Color(0xFF9D4EDD).withValues(alpha: 0.25)
              : const Color(0xFF141722).withValues(alpha: 0.82),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isActive ? const Color(0xFF9D4EDD) : Colors.white12,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16,
              color: isActive ? const Color(0xFFB388FF) : Colors.white70,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: isActive ? Colors.white : Colors.white70,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGradientButton({
    required IconData icon,
    required String label,
    required Gradient gradient,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          gradient: gradient,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: Colors.black),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Colors.black,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Built-in Milkdrop Presets for instant guaranteed visuals
const _presetNeonHyperspace = '''
[preset00]
fRating=3.000
fGammaAdj=1.200
fDecay=0.960
fVideoEchoZoom=1.000
fVideoEchoAlpha=0.000
nVideoEchoOrientation=0
nWaveMode=2
bAdditiveWaves=1
bWaveDots=0
bWaveThick=1
bModWaveAlphaByVolume=1
bMaximizeWaveColor=1
bTexWrap=1
bDarkenCenter=0
bRedBlueStereo=0
bBrighten=0
bDarken=0
bSolarize=0
bInvert=0
fWaveAlpha=0.850
fWaveScale=1.150
fWaveSmoothing=0.750
fWaveParam=0.000
fModWaveAlphaStart=0.750
fModWaveAlphaEnd=0.950
fWarpAnimSpeed=1.000
fWarpScale=1.200
fZoomExponent=1.000
fShader=0.000
zoom=1.02000
rot=0.00300
cx=0.500
cy=0.500
dx=0.00000
dy=0.00000
warp=0.02000
sx=1.00000
sy=1.00000
wave_r=0.000
wave_g=0.900
wave_b=1.000
wave_x=0.500
wave_y=0.500
ob_size=0.010
ob_r=0.000
ob_g=0.000
ob_b=0.000
ob_a=0.000
ib_size=0.010
ib_r=0.250
ib_g=0.250
ib_b=0.250
ib_a=0.000
per_frame_1=wave_r = 0.5 + 0.5*sin(time*1.2);
per_frame_2=wave_g = 0.5 + 0.5*sin(time*1.6);
per_frame_3=wave_b = 0.5 + 0.5*cos(time*1.4);
per_frame_4=rot = rot + 0.015*sin(time*0.5) + 0.01*bass;
per_frame_5=zoom = zoom + 0.05*bass_att;
per_pixel_1=rot=rot+0.02*(rad-0.5)*sin(time);
per_pixel_2=zoom=zoom+0.03*sin(ang*6.0);
''';

const _presetCosmicKaleidoscope = '''
[preset00]
fRating=3.000
fGammaAdj=1.000
fDecay=0.950
fVideoEchoZoom=1.002
fVideoEchoAlpha=0.500
nVideoEchoOrientation=3
nWaveMode=7
bAdditiveWaves=1
bWaveDots=0
bWaveThick=1
bModWaveAlphaByVolume=0
bMaximizeWaveColor=0
bTexWrap=1
bDarkenCenter=0
bRedBlueStereo=0
bBrighten=0
bDarken=0
bSolarize=0
bInvert=0
fWaveAlpha=0.900
fWaveScale=1.300
fWaveSmoothing=0.500
fWaveParam=0.000
fModWaveAlphaStart=0.500
fModWaveAlphaEnd=1.000
fWarpAnimSpeed=1.000
fWarpScale=1.000
fZoomExponent=1.000
fShader=0.000
zoom=0.99000
rot=0.00500
cx=0.500
cy=0.500
dx=0.00000
dy=0.00000
warp=0.05000
sx=1.00000
sy=1.00000
wave_r=1.000
wave_g=0.200
wave_b=0.800
wave_x=0.500
wave_y=0.500
ob_size=0.010
ob_r=0.000
ob_g=0.000
ob_b=0.000
ob_a=0.000
ib_size=0.010
ib_r=0.250
ib_g=0.250
ib_b=0.250
ib_a=0.000
per_frame_1=wave_r = 0.6 + 0.4*sin(time*0.8);
per_frame_2=wave_g = 0.2 + 0.3*sin(time*1.1);
per_frame_3=wave_b = 0.8 + 0.2*cos(time*0.9);
per_frame_4=zoom = zoom + 0.04*bass;
per_frame_5=rot = rot + 0.01*mid_att;
per_pixel_1=warp = 0.08*sin(rad*8.0 + time*2.0);
''';

const _presetSpectrumWave = '''
[preset00]
fRating=3.000
fGammaAdj=1.000
fDecay=0.920
fVideoEchoZoom=1.000
fVideoEchoAlpha=0.000
nVideoEchoOrientation=0
nWaveMode=3
bAdditiveWaves=1
bWaveDots=0
bWaveThick=1
bModWaveAlphaByVolume=0
bMaximizeWaveColor=1
bTexWrap=1
bDarkenCenter=0
bRedBlueStereo=0
bBrighten=0
bDarken=0
bSolarize=0
bInvert=0
fWaveAlpha=1.000
fWaveScale=1.500
fWaveSmoothing=0.800
fWaveParam=0.000
fModWaveAlphaStart=0.800
fModWaveAlphaEnd=1.000
fWarpAnimSpeed=1.000
fWarpScale=1.000
fZoomExponent=1.000
fShader=0.000
zoom=1.00500
rot=0.00000
cx=0.500
cy=0.500
dx=0.00000
dy=0.00000
warp=0.00500
sx=1.00000
sy=1.00000
wave_r=0.000
wave_g=1.000
wave_b=0.900
wave_x=0.500
wave_y=0.500
ob_size=0.005
ob_r=0.000
ob_g=0.000
ob_b=0.000
ob_a=0.000
ib_size=0.005
ib_r=0.250
ib_g=0.250
ib_b=0.250
ib_a=0.000
per_frame_1=wave_r = 0.2 + 0.8*treb_att;
per_frame_2=wave_g = 0.8 + 0.2*mid;
per_frame_3=wave_b = 0.5 + 0.5*sin(time*2.0);
per_frame_4=dx = dx + 0.002*sin(time);
per_pixel_1=zoom = zoom + 0.04*bass_att*(1.0-rad);
''';

/// Poweramp-style animated audio frequency spectrum overlay.
///
/// Renders 32 reactive neon frequency bars across the bottom with floating peak caps,
/// matching the signature Poweramp / PowerMilk spectrum aesthetic.
class PowerampSpectrumBars extends StatefulWidget {
  const PowerampSpectrumBars({
    super.key,
    required this.bass,
    required this.mid,
    required this.treb,
    required this.isPlaying,
    this.barCount = 32,
  });

  final double bass;
  final double mid;
  final double treb;
  final bool isPlaying;
  final int barCount;

  @override
  State<PowerampSpectrumBars> createState() => _PowerampSpectrumBarsState();
}

class _PowerampSpectrumBarsState extends State<PowerampSpectrumBars>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  late List<double> _barHeights;
  late List<double> _peakHeights;

  @override
  void initState() {
    super.initState();
    _barHeights = List.filled(widget.barCount, 0.0);
    _peakHeights = List.filled(widget.barCount, 0.0);
    _ticker = createTicker(_onTick)..start();
  }

  void _onTick(Duration elapsed) {
    if (!mounted) return;

    final isAudioActive = widget.isPlaying &&
        (widget.bass > 0.01 || widget.mid > 0.01 || widget.treb > 0.01);

    setState(() {
      for (int i = 0; i < widget.barCount; i++) {
        final t = i / (widget.barCount - 1);
        double target = 0.0;

        if (isAudioActive) {
          // Logarithmic/banded distribution:
          // Low index = Bass, Mid index = Mid, High index = Treble
          final bWeight = max(0.0, 1.0 - t * 2.2);
          final mWeight = max(0.0, 1.0 - (t - 0.45).abs() * 2.4);
          final tWeight = max(0.0, (t - 0.5) * 2.0);

          final raw = widget.bass * bWeight * 0.9 +
              widget.mid * mWeight * 1.1 +
              widget.treb * tWeight * 1.3;

          // Harmonic variation across bins
          final jitter = 0.85 + 0.3 * sin(i * 1.4 + elapsed.inMilliseconds * 0.012);
          target = (raw * jitter).clamp(0.02, 1.0);
        }

        // Smooth spring up, exponential decay down
        if (target > _barHeights[i]) {
          _barHeights[i] = _barHeights[i] * 0.4 + target * 0.6;
        } else {
          _barHeights[i] = max(0.0, _barHeights[i] * 0.88 - 0.005);
        }

        // Peak caps with gravity drop
        if (_barHeights[i] >= _peakHeights[i]) {
          _peakHeights[i] = _barHeights[i];
        } else {
          _peakHeights[i] = max(0.0, _peakHeights[i] - 0.015);
        }
      }
    });
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(
        painter: _PowerampSpectrumPainter(
          barHeights: _barHeights,
          peakHeights: _peakHeights,
        ),
        size: Size.infinite,
      ),
    );
  }
}

class _PowerampSpectrumPainter extends CustomPainter {
  _PowerampSpectrumPainter({
    required this.barHeights,
    required this.peakHeights,
  });

  final List<double> barHeights;
  final List<double> peakHeights;

  @override
  void paint(Canvas canvas, Size size) {
    final count = barHeights.length;
    if (count == 0) return;

    final gap = 4.0;
    final totalGaps = (count - 1) * gap;
    final barWidth = max(2.0, (size.width - totalGaps) / count);

    final gradient = const LinearGradient(
      begin: Alignment.bottomCenter,
      end: Alignment.topCenter,
      colors: [
        Color(0xCC00E5FF), // Neon Cyan (base)
        Color(0xEE9D4EDD), // Electric Purple (mid)
        Color(0xFFFF007A), // Hot Pink (high)
      ],
      stops: [0.0, 0.6, 1.0],
    );

    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    final paint = Paint()
      ..shader = gradient.createShader(rect)
      ..style = PaintingStyle.fill;

    final peakPaint = Paint()
      ..color = const Color(0xFFFFFFFF)
      ..style = PaintingStyle.fill;

    for (int i = 0; i < count; i++) {
      final x = i * (barWidth + gap);
      final h = (barHeights[i] * size.height).clamp(2.0, size.height);
      final y = size.height - h;

      // Draw rounded frequency bar
      final barRRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, y, barWidth, h),
        const Radius.circular(3.0),
      );
      canvas.drawRRect(barRRect, paint);

      // Draw floating peak cap
      final peakY = size.height - (peakHeights[i] * size.height).clamp(4.0, size.height);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, peakY - 2.0, barWidth, 2.0),
          const Radius.circular(1.0),
        ),
        peakPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _PowerampSpectrumPainter oldDelegate) => true;
}

