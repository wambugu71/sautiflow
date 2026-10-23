import 'dart:io';

/// Represents a projectM / Milkdrop visualizer preset.
class ProjectMPreset {
  const ProjectMPreset({
    required this.id,
    required this.displayName,
    required this.category,
    this.description = '',
    this.inlineMilkData,
    this.filePath,
  });

  /// Unique identifier (e.g. 'neon_hyperspace').
  final String id;

  /// User-facing title.
  final String displayName;

  /// Preset category (e.g. 'Hyperspace', 'Cosmic', 'Beat', 'Spectrum', 'Wave').
  final String category;

  /// Optional descriptive subtitle.
  final String description;

  /// Raw Milkdrop preset equations and directives.
  final String? inlineMilkData;

  /// Local filesystem path if loaded from disk.
  final String? filePath;

  /// Creates a custom preset from a `.milk` file on disk.
  factory ProjectMPreset.fromFile(File file) {
    final fileName = file.uri.pathSegments.isNotEmpty ? file.uri.pathSegments.last : 'preset.milk';
    final baseName = fileName.replaceAll(RegExp(r'\.milk$', caseSensitive: false), '');
    final cleanTitle = baseName
        .replaceAll(RegExp(r'^\d+-'), '')
        .replaceAll('-', ' ')
        .replaceAll('_', ' ')
        .split(' ')
        .map((w) => w.isNotEmpty ? '${w[0].toUpperCase()}${w.substring(1)}' : '')
        .join(' ');

    return ProjectMPreset(
      id: 'custom_${file.path.hashCode}',
      displayName: cleanTitle.isEmpty ? fileName : cleanTitle,
      category: 'Custom',
      description: 'Imported from storage',
      filePath: file.path,
    );
  }

  /// Creates a custom preset from raw string data.
  factory ProjectMPreset.fromData({
    required String id,
    required String displayName,
    required String milkData,
    String category = 'Custom',
    String description = 'Imported Milkdrop preset',
  }) {
    return ProjectMPreset(
      id: id,
      displayName: displayName,
      category: category,
      description: description,
      inlineMilkData: milkData,
    );
  }
}

/// Curated library of built-in projectM / Milkdrop visualizer presets.
class ProjectMPresetLibrary {
  ProjectMPresetLibrary._();

  static const ProjectMPreset neonHyperspace = ProjectMPreset(
    id: 'neon_hyperspace',
    displayName: 'Neon Hyperspace',
    category: 'Hyperspace',
    description: 'Pulsing warp tunnel with bass-reactive camera rotation',
    inlineMilkData: _presetNeonHyperspace,
  );

  static const ProjectMPreset cosmicKaleidoscope = ProjectMPreset(
    id: 'cosmic_kaleidoscope',
    displayName: 'Cosmic Kaleidoscope',
    category: 'Cosmic',
    description: 'Prismatic mandala with symmetry reflections and mid-frequency warp',
    inlineMilkData: _presetCosmicKaleidoscope,
  );

  static const ProjectMPreset spectrumWave = ProjectMPreset(
    id: 'spectrum_wave',
    displayName: 'Spectrum Waveform',
    category: 'Spectrum',
    description: 'Reactive oscillating audio frequency ribbon',
    inlineMilkData: _presetSpectrumWave,
  );

  static const ProjectMPreset beatDetectTrinity = ProjectMPreset(
    id: 'beat_detect_trinity',
    displayName: '3-Band Beat Trinity',
    category: 'Beat',
    description: 'Dedicated frequency-isolated meters for Bass, Mid, and Treble hits',
    inlineMilkData: _presetBeatDetectTrinity,
  );

  static const ProjectMPreset wavecodeDualSpectrum = ProjectMPreset(
    id: 'wavecode_dual_spectrum',
    displayName: 'Dual Spectrum Analyzer',
    category: 'Spectrum',
    description: 'Simultaneous frequency spectrum analysis & PCM waveform traces',
    inlineMilkData: _presetWavecodeDualSpectrum,
  );

  static const ProjectMPreset smoothAuroraWave = ProjectMPreset(
    id: 'smooth_aurora_wave',
    displayName: 'Smooth Aurora Wave',
    category: 'Wave',
    description: 'Ultra-smooth decaying fluid neon ribbons',
    inlineMilkData: _presetSmoothAuroraWave,
  );

  static const ProjectMPreset radialWarp = ProjectMPreset(
    id: 'radial_warp',
    displayName: 'Radial Warp Vortex',
    category: 'Hyperspace',
    description: 'Space-time dilation with deep bass gravitational pulls',
    inlineMilkData: _presetRadialWarp,
  );

  static const ProjectMPreset prismaticNoise = ProjectMPreset(
    id: 'prismatic_noise',
    displayName: 'Prismatic Flow',
    category: 'Cosmic',
    description: 'Complex noise field with multi-color shifting waves',
    inlineMilkData: _presetPrismaticNoise,
  );

  /// All built-in curated presets.
  static const List<ProjectMPreset> all = [
    neonHyperspace,
    cosmicKaleidoscope,
    spectrumWave,
    beatDetectTrinity,
    wavecodeDualSpectrum,
    smoothAuroraWave,
    radialWarp,
    prismaticNoise,
  ];

  /// Dynamically registered external presets (imported from disk or downloaded packs).
  static final List<ProjectMPreset> _customPresets = [];

  /// Returns unmodifiable list of dynamically registered custom presets.
  static List<ProjectMPreset> get customPresets => List.unmodifiable(_customPresets);

  /// All presets combined (built-in equations + dynamically registered disk presets).
  static List<ProjectMPreset> get allWithCustom => [...all, ..._customPresets];

  /// Register an external preset dynamically.
  static void registerCustomPreset(ProjectMPreset preset) {
    final idx = _customPresets.indexWhere((p) => p.id == preset.id || (p.filePath != null && p.filePath == preset.filePath));
    if (idx >= 0) {
      _customPresets[idx] = preset;
    } else {
      _customPresets.add(preset);
    }
  }

  /// Register multiple external presets dynamically.
  static void registerCustomPresets(Iterable<ProjectMPreset> presets) {
    for (final preset in presets) {
      registerCustomPreset(preset);
    }
  }

  /// Remove a registered custom preset by ID.
  static void removeCustomPreset(String id) {
    _customPresets.removeWhere((p) => p.id == id || p.filePath == id);
  }

  /// Clear all registered custom presets.
  static void clearCustomPresets() {
    _customPresets.clear();
  }

  /// Default preset loaded on startup.
  static const ProjectMPreset defaultPreset = neonHyperspace;

  /// Distinct preset categories.
  static List<String> get categories {
    final set = <String>{};
    for (final p in allWithCustom) {
      set.add(p.category);
    }
    return set.toList();
  }

  /// Retrieve all presets in a given category.
  static List<ProjectMPreset> byCategory(String category) {
    return allWithCustom.where((p) => p.category.toLowerCase() == category.toLowerCase()).toList();
  }

  /// Find a preset by ID, name, or file path (case-insensitive with fallback).
  static ProjectMPreset findById(String id, {ProjectMPreset fallback = defaultPreset}) {
    final lower = id.toLowerCase().trim();

    // 1. Check custom & built-in registered presets
    for (final p in allWithCustom) {
      if (p.id == id ||
          p.id.toLowerCase() == lower ||
          (p.filePath != null && p.filePath == id) ||
          p.displayName.toLowerCase() == lower ||
          p.displayName.toLowerCase().replaceAll(' ', '_') == lower) {
        return p;
      }
    }

    // 2. If ID is a direct disk path to an existing .milk file, resolve on the fly
    try {
      final file = File(id);
      if (file.existsSync() && id.toLowerCase().endsWith('.milk')) {
        final preset = ProjectMPreset.fromFile(file);
        registerCustomPreset(preset);
        return preset;
      }
    } catch (_) {}

    return fallback;
  }
}

// =============================================================================
// Milkdrop Preset Equations (Pure text equations evaluated by projectM core)
// =============================================================================

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
warp=0.01000
sx=1.00000
sy=1.00000
wave_r=0.000
wave_g=1.000
wave_b=0.500
wave_x=0.500
wave_y=0.500
ob_size=0.000
ib_size=0.000
per_frame_1=wave_r = 0.5 + 0.5*sin(time*2.0);
per_frame_2=wave_g = 0.5 + 0.5*cos(time*1.7);
per_frame_3=wave_b = 0.8 + 0.2*sin(time*3.1);
per_frame_4=dx = 0.003*sin(time*0.7);
per_frame_5=dy = 0.003*cos(time*0.9);
per_pixel_1=zoom = 1.0 + 0.03*sin(rad*6.0 - time*3.0)*bass;
''';

const _presetBeatDetectTrinity = '''
[preset00]
fDecay=0.780
fWarpScale=2.853
fZoomExponent=1.000
warp=0.000
wave_a=0
cy=1.0
cx=0.5
sx=1.0
sy=1.0
dx=0.0
dy=0.015
zoom=1.0
ob_size=0.0
ib_size=0.0

per_pixel_1=cx=x;

wavecode_0_enabled=1
wavecode_0_mode=0
wavecode_0_bDrawThick=1
wavecode_0_bAdditive=1
wavecode_0_scaling=1.2
wavecode_0_smoothing=0.2
wavecode_0_r=0.0
wavecode_0_g=0.9
wavecode_0_b=1.0
wavecode_0_a=1.0
wave_0_per_frame1=t1=if(above(bass,1.8),0.92,bass*0.4);
wave_0_per_point1=x=0.02 + 0.28*sample;
wave_0_per_point2=y=t1 + value1*0.08;

wavecode_1_enabled=1
wavecode_1_mode=0
wavecode_1_bDrawThick=1
wavecode_1_bAdditive=1
wavecode_1_scaling=1.2
wavecode_1_smoothing=0.2
wavecode_1_r=0.6
wavecode_1_g=0.2
wavecode_1_b=1.0
wavecode_1_a=1.0
wave_1_per_frame1=t1=if(above(mid,1.8),0.92,mid*0.4);
wave_1_per_point1=x=0.36 + 0.28*sample;
wave_1_per_point2=y=t1 + value2*0.08;

wavecode_2_enabled=1
wavecode_2_mode=0
wavecode_2_bDrawThick=1
wavecode_2_bAdditive=1
wavecode_2_scaling=1.2
wavecode_2_smoothing=0.2
wavecode_2_r=1.0
wavecode_2_g=0.1
wavecode_2_b=0.6
wavecode_2_a=1.0
wave_2_per_frame1=t1=if(above(treb,1.8),0.92,treb*0.4);
wave_2_per_point1=x=0.70 + 0.28*sample;
wave_2_per_point2=y=t1 + value1*0.08;
''';

const _presetWavecodeDualSpectrum = '''
[preset00]
fDecay=0.880
warp=0.000
wave_a=0
zoom=1.002
rot=0.001

wavecode_0_enabled=1
wavecode_0_bSpectrum=0
wavecode_0_scaling=0.3
wavecode_0_r=0.0
wavecode_0_g=0.9
wavecode_0_b=1.0
wavecode_0_a=0.95
wavecode_0_x=0.5
wavecode_0_y=0.75
wave_0_per_point1=x=sample;
wave_0_per_point2=y=0.75+value1*0.25;

wavecode_1_enabled=1
wavecode_1_bSpectrum=1
wavecode_1_scaling=1.1
wavecode_1_r=1.0
wavecode_1_g=0.3
wavecode_1_b=0.8
wavecode_1_a=0.95
wavecode_1_x=0.5
wavecode_1_y=0.30
wave_1_per_point1=x=sample;
wave_1_per_point2=y=0.30+value1*0.45;
''';

const _presetSmoothAuroraWave = '''
[preset00]
fDecay=0.960
fWarpScale=1.000
warp=0.010
wave_a=1.0
wave_r=0.2
wave_g=0.9
wave_b=0.8
wave_x=0.5
wave_y=0.5
zoom=1.010
rot=0.002
cx=0.5
cy=0.5

per_frame_1=wave_r=0.3 + 0.5*sin(time*0.9);
per_frame_2=wave_g=0.6 + 0.4*cos(time*1.3);
per_frame_3=wave_b=0.8 + 0.2*sin(time*0.7);
per_frame_4=rot=rot + 0.008*sin(time*0.4) + 0.005*bass;
per_frame_5=zoom=1.005 + 0.02*bass_att;
per_pixel_1=warp=0.03*sin(rad*4.0 + time*1.2);
''';

const _presetRadialWarp = '''
[preset00]
fDecay=0.970
fWarpScale=2.853
warp=0.030
zoom=0.985
rot=0.008
cx=0.5
cy=0.5
wave_a=0.7
wave_r=1.0
wave_g=0.4
wave_b=0.1

per_frame_1=wave_r=0.8 + 0.2*sin(time*1.8);
per_frame_2=wave_g=0.4 + 0.4*cos(time*2.2);
per_frame_3=wave_b=0.2 + 0.3*sin(time*1.5);
per_frame_4=zoom=zoom + 0.04*bass;
per_pixel_1=zoom=zoom + 0.03*sin(ang*8.0 + time*2.0);
per_pixel_2=rot=rot + 0.02*(rad-0.5)*bass;
''';

const _presetPrismaticNoise = '''
[preset00]
fDecay=0.940
warp=0.040
zoom=1.015
rot=0.003
cx=0.5
cy=0.5
wave_a=0.9
wave_r=0.9
wave_g=0.1
wave_b=0.9

per_frame_1=wave_r=0.5 + 0.5*sin(time*1.1);
per_frame_2=wave_g=0.5 + 0.5*sin(time*1.7 + 2.0);
per_frame_3=wave_b=0.5 + 0.5*cos(time*1.4 + 4.0);
per_frame_4=dx=0.004*sin(time*0.8);
per_frame_5=dy=0.004*cos(time*0.6);
per_pixel_1=warp=0.06*sin(rad*6.0 + time*1.5 + ang*3.0);
''';
