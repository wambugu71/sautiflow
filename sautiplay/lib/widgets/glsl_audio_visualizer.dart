import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import '../services/fft_processor.dart';

enum GlslShaderStyle {
  cyberTunnel(
    displayName: 'Cyber Tunnel',
    assetPath: 'shaders/audio_cyber_tunnel.frag',
  ),
  plasmaSphere(
    displayName: 'Plasma Sphere',
    assetPath: 'shaders/audio_plasma_sphere.frag',
  ),
  neonSpectrum(
    displayName: 'Liquid Spectrum',
    assetPath: 'shaders/audio_neon_spectrum.frag',
  ),
  warpVortex(
    displayName: 'Hyper Warp Vortex',
    assetPath: 'shaders/audio_warp_vortex.frag',
  ),
  solarFlare(
    displayName: 'Solar Flare Ring',
    assetPath: 'shaders/audio_solar_flare.frag',
  ),
  cyberGrid(
    displayName: 'Synthwave Grid',
    assetPath: 'shaders/audio_cyber_grid.frag',
  ),
  quantumNebula(
    displayName: 'Cosmic Nebula',
    assetPath: 'shaders/audio_quantum_nebula.frag',
  ),
  electricRing(
    displayName: 'Electric Arc Ring',
    assetPath: 'shaders/audio_electric_ring.frag',
  ),
  equalizerBars3D(
    displayName: '3D Equalizer Bars',
    assetPath: 'shaders/audio_bars_3d.frag',
  ),
  kaleidoscope(
    displayName: 'Prismatic Mandala',
    assetPath: 'shaders/audio_kaleidoscope.frag',
  ),
  cyberLattice(
    displayName: 'Crystal Lattice',
    assetPath: 'shaders/audio_lattice.frag',
  ),
  biolumWaves(
    displayName: 'Ocean Bioluminescence',
    assetPath: 'shaders/audio_biolum_waves.frag',
  ),
  sonicStarburst(
    displayName: 'Sonic Starburst',
    assetPath: 'shaders/audio_starburst.frag',
  ),
  matrixRain(
    displayName: 'Audio Matrix Rain',
    assetPath: 'shaders/audio_matrix_rain.frag',
  ),
  vaporwaveSun(
    displayName: 'Vaporwave Horizon',
    assetPath: 'shaders/audio_vaporwave_sun.frag',
  );

  final String displayName;
  final String assetPath;

  const GlslShaderStyle({
    required this.displayName,
    required this.assetPath,
  });

  static GlslShaderStyle fromString(String id) {
    return GlslShaderStyle.values.firstWhere(
      (e) => e.name == id || e.assetPath.endsWith('$id.frag'),
      orElse: () => GlslShaderStyle.cyberTunnel,
    );
  }
}

/// Loads GLSL runtime shaders and updates uniforms at 60 FPS using FFT audio energy metrics.
class GlslAudioVisualizerWidget extends StatefulWidget {
  final Stream<Float32List>? analyzerStream;
  final bool isPlaying;
  final GlslShaderStyle style;
  final Color primaryColor;
  final double height;
  final double width;

  const GlslAudioVisualizerWidget({
    super.key,
    this.analyzerStream,
    this.isPlaying = true,
    this.style = GlslShaderStyle.cyberTunnel,
    this.primaryColor = const Color(0xFF137fec),
    this.height = 160.0,
    this.width = double.infinity,
  });

  @override
  State<GlslAudioVisualizerWidget> createState() =>
      _GlslAudioVisualizerWidgetState();
}

class _GlslAudioVisualizerWidgetState extends State<GlslAudioVisualizerWidget>
    with SingleTickerProviderStateMixin {
  ui.FragmentProgram? _program;
  bool _isLoading = true;
  String? _error;

  late Ticker _ticker;
  double _elapsedTime = 0.0;
  DateTime? _lastTickTime;

  StreamSubscription? _analyzerSub;
  FftProcessor? _fftProcessor;

  // Smoothed Audio Energy Bands [0.0 - 1.0+]
  double _bass = 0.0;
  double _mid = 0.0;
  double _treble = 0.0;
  double _energy = 0.0;

  @override
  void initState() {
    super.initState();
    _fftProcessor = FftProcessor(sampleRate: 48000);
    _loadShader(widget.style);
    _setupTicker();
    _setupAudioStream();
  }

  @override
  void didUpdateWidget(covariant GlslAudioVisualizerWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.style != widget.style) {
      _loadShader(widget.style);
    }
    if (oldWidget.analyzerStream != widget.analyzerStream) {
      _setupAudioStream();
    }
  }

  Future<void> _loadShader(GlslShaderStyle style) async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final program = await ui.FragmentProgram.fromAsset(style.assetPath);
      if (mounted) {
        setState(() {
          _program = program;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  void _setupTicker() {
    _ticker = createTicker((elapsed) {
      if (!mounted) return;
      final now = DateTime.now();
      if (_lastTickTime != null) {
        final dt = now.difference(_lastTickTime!).inMicroseconds / 1000000.0;
        if (widget.isPlaying) {
          _elapsedTime += dt;
        }
      }
      _lastTickTime = now;

      // Natural decay for audio energy bands if no stream input
      if (widget.analyzerStream == null || !widget.isPlaying) {
        _bass = (_bass * 0.92).clamp(0.0, 1.0);
        _mid = (_mid * 0.92).clamp(0.0, 1.0);
        _treble = (_treble * 0.92).clamp(0.0, 1.0);
        _energy = (_energy * 0.92).clamp(0.0, 1.0);
      }

      setState(() {});
    });
    _ticker.start();
  }

  void _setupAudioStream() {
    _analyzerSub?.cancel();
    _analyzerSub = null;

    if (widget.analyzerStream != null) {
      _analyzerSub = widget.analyzerStream!.listen((pcmData) {
        if (pcmData.isEmpty || !mounted || _fftProcessor == null || !widget.isPlaying) return;
        const int numBins = 32;
        final bins = _fftProcessor!.processFrame(pcmData, targetBins: numBins);

        // Group 32 bins into Bass (0-7), Mid (8-21), and Treble (22-31)
        double bassSum = 0.0;
        for (int i = 0; i < 8; i++) {
          bassSum += bins[i];
        }
        double rawBass = (bassSum / 8.0).clamp(0.0, 1.0);
        // Boost gain sensitivity for bass
        rawBass = math.pow(rawBass, 0.65).toDouble() * 1.8;

        double midSum = 0.0;
        for (int i = 8; i < 22; i++) {
          midSum += bins[i];
        }
        double rawMid = (midSum / 14.0).clamp(0.0, 1.0);
        rawMid = math.pow(rawMid, 0.65).toDouble() * 1.6;

        double trebleSum = 0.0;
        for (int i = 22; i < 32; i++) {
          trebleSum += bins[i];
        }
        double rawTreble = (trebleSum / 10.0).clamp(0.0, 1.0);
        rawTreble = math.pow(rawTreble, 0.65).toDouble() * 1.6;

        double totalEnergy = (rawBass * 0.5 + rawMid * 0.3 + rawTreble * 0.2);

        // Dynamic attack & decay smoothing
        _bass = rawBass > _bass
            ? _bass * 0.3 + rawBass * 0.7
            : _bass * 0.82 + rawBass * 0.18;
        _mid = rawMid > _mid
            ? _mid * 0.3 + rawMid * 0.7
            : _mid * 0.82 + rawMid * 0.18;
        _treble = rawTreble > _treble
            ? _treble * 0.3 + rawTreble * 0.7
            : _treble * 0.82 + rawTreble * 0.18;
        _energy = totalEnergy > _energy
            ? _energy * 0.3 + totalEnergy * 0.7
            : _energy * 0.82 + totalEnergy * 0.18;
      });
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _analyzerSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Container(
        height: widget.height,
        width: widget.width,
        decoration: BoxDecoration(
          color: Colors.black26,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(
                strokeWidth: 2, color: Colors.white54),
          ),
        ),
      );
    }

    if (_error != null || _program == null) {
      return Container(
        height: widget.height,
        width: widget.width,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.black26,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.redAccent.withValues(alpha: 0.3)),
        ),
        child: Center(
          child: Text(
            'GLSL Shader Unavailable: ${_error ?? "Failed to compile shader"}',
            style: const TextStyle(color: Colors.white70, fontSize: 11),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        height: widget.height,
        width: widget.width,
        child: CustomPaint(
          painter: _GlslShaderPainter(
            program: _program!,
            time: _elapsedTime,
            bass: _bass,
            mid: _mid,
            treble: _treble,
            energy: _energy,
            primaryColor: widget.primaryColor,
          ),
        ),
      ),
    );
  }
}

class _GlslShaderPainter extends CustomPainter {
  final ui.FragmentProgram program;
  final double time;
  final double bass;
  final double mid;
  final double treble;
  final double energy;
  final Color primaryColor;

  _GlslShaderPainter({
    required this.program,
    required this.time,
    required this.bass,
    required this.mid,
    required this.treble,
    required this.energy,
    required this.primaryColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final shader = program.fragmentShader();

    // Uniform index 0, 1: uSize (width, height)
    shader.setFloat(0, size.width);
    shader.setFloat(1, size.height);

    // Uniform index 2: uTime
    shader.setFloat(2, time);

    // Uniform index 3: uBass
    shader.setFloat(3, bass);

    // Uniform index 4: uMid
    shader.setFloat(4, mid);

    // Uniform index 5: uTreble
    shader.setFloat(5, treble);

    // Uniform index 6: uEnergy
    shader.setFloat(6, energy);

    // Uniform index 7, 8, 9: uPrimaryColor (R, G, B in 0.0 - 1.0)
    shader.setFloat(7, primaryColor.r);
    shader.setFloat(8, primaryColor.g);
    shader.setFloat(9, primaryColor.b);

    final paint = Paint()..shader = shader;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), paint);
  }

  @override
  bool shouldRepaint(covariant _GlslShaderPainter oldDelegate) {
    return oldDelegate.time != time ||
        oldDelegate.bass != bass ||
        oldDelegate.mid != mid ||
        oldDelegate.treble != treble ||
        oldDelegate.energy != energy ||
        oldDelegate.primaryColor != primaryColor ||
        oldDelegate.program != program;
  }
}
