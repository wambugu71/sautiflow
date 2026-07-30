import 'dart:async';
import 'dart:ffi' as ffi;
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:http/http.dart' as http;

import '../audio_engine_ffi.dart';
import '../viper_dsp.dart';
import 'miniaudio_filters.dart';
import 'mobile_system_audio.dart';

class MiniAudioPlayer {
  MiniAudioPlayer({
    String? libraryPath,
    this.statusPollInterval = const Duration(milliseconds: 200),
    this.analyzerPollInterval = const Duration(milliseconds: 33),
  }) : _engine = AudioEngineFFI(libraryPath: libraryPath);

  final AudioEngineFFI _engine;
  late final ViperDsp _viper = ViperDsp(_engine);
  final Duration statusPollInterval;
  final Duration analyzerPollInterval;

  final _statusController = StreamController<PlayerStatus>.broadcast();
  final _logController = StreamController<String>.broadcast();
  final _analyzerController = StreamController<Float32List>.broadcast();
  late final MiniAudioSystemAudioController _systemAudio =
      MiniAudioSystemAudioController(
    statusStream: _statusController.stream,
    onPlay: () {
      play();
    },
    onPause: () {
      pause();
    },
    onStop: () {
      stop();
    },
    onNext: () {
      seekToNext();
    },
    onPrevious: () {
      seekToPrevious();
    },
    onSeek: (position) {
      seekTo(position);
    },
    onSetGain: (gain) {
      setGain(gain);
    },
  );
  Timer? _statusTimer;
  Timer? _analyzerTimer;
  String _lastLog = '';
  bool _analyzerEnabled = false;

  Stream<PlayerStatus> get statusStream => _statusController.stream;
  Stream<String> get logStream => _logController.stream;
  Stream<Float32List> get analyzerStream => _analyzerController.stream;

  /// Provides direct access to all ViPER DSP features.
  ViperDsp get viper => _viper;

  bool init({
    int sampleRate = 48000,
    int channels = 2,
    bool enableSystemAudio = false,
    MiniAudioSystemAudioConfig? systemAudioConfig,
  }) {
    final ok = _engine.create(sampleRate: sampleRate, channels: channels);
    if (ok) {
      _startStatusPolling();
      _startAnalyzerPolling();
      if (enableSystemAudio) {
        unawaited(
          _systemAudio.enable(
            config: systemAudioConfig ?? const MiniAudioSystemAudioConfig(),
          ),
        );
      }
    }
    return ok;
  }

  void dispose() {
    unawaited(_systemAudio.disable());
    _statusTimer?.cancel();
    _analyzerTimer?.cancel();
    _statusController.close();
    _logController.close();
    _analyzerController.close();
    _engine.dispose();
  }

  bool setAudioSources(
    List<AudioSource> sources, {
    int initialIndex = 0,
    Duration initialPosition = Duration.zero,
    bool useLazyPreparation = true,
    Object? shuffleOrder,
  }) {
    final supportsNetwork = isNetworkStreamingSupported();
    for (final source in sources) {
      if (source.isNetwork && !supportsNetwork) {
        throw ArgumentError(
          'Network URLs are not supported in this native build (found: ${source.uri}). Rebuild with network streaming enabled, or use local files/pushStream().',
        );
      }
    }
    return _engine.setAudioSources(
      sources,
      initialIndex: initialIndex,
      initialPosition: initialPosition,
      useLazyPreparation: useLazyPreparation,
      shuffleOrder: shuffleOrder,
    );
  }

  bool addAudioSource(AudioSource source) {
    if (source.isNetwork && !isNetworkStreamingSupported()) {
      throw ArgumentError(
        'Network URLs are not supported in this native build (found: ${source.uri}). Rebuild with network streaming enabled, or use local files/pushStream().',
      );
    }
    return _engine.addAudioSourceUri(source.uri);
  }

  bool insertAudioSource(int index, AudioSource source) =>
      _engine.insertAudioSource(
        index,
        source.uri.scheme == 'file'
            ? source.uri.toFilePath()
            : source.uri.toString(),
      );
  bool removeAudioSourceAt(int index) => _engine.removeAudioSourceAt(index);
  void clearAudioSources() => _engine.clearPlaylist();
  bool moveAudioSource(int fromIndex, int toIndex) =>
      _engine.moveAudioSource(fromIndex, toIndex);

  bool play() => _engine.play();
  bool pause() => _engine.pause();
  bool stop() => _engine.stop();

  bool seek(Duration position, {int? index}) =>
      _engine.seekTo(position, index: index);
  bool seekTo(Duration position, {int? index}) =>
      _engine.seekTo(position, index: index);
  bool seekToNext() => _engine.seekToNext();
  bool seekToPrevious() => _engine.seekToPrevious();

  void setLoopMode(LoopMode mode) => _engine.setLoopMode(mode);
  void setShuffleModeEnabled(bool enabled) =>
      _engine.setShuffleModeEnabled(enabled);
  void reshuffle() => _engine.reshuffle();
  void setAbRepeat({
    required bool enabled,
    double startSeconds = 0.0,
    double endSeconds = 0.0,
  }) =>
      _engine.setAbRepeat(
        enabled: enabled,
        startSeconds: startSeconds,
        endSeconds: endSeconds,
      );
  ({bool enabled, double startSeconds, double endSeconds}) getAbRepeat() =>
      _engine.getAbRepeat();
  void setCrossfadeEnabled(bool enabled) =>
      _engine.setCrossfadeEnabled(enabled);
  bool getCrossfadeEnabled() => _engine.getCrossfadeEnabled();
  void setCrossfadeDurationMs(int durationMs) =>
      _engine.setCrossfadeDurationMs(durationMs);
  int getCrossfadeDurationMs() => _engine.getCrossfadeDurationMs();

  PlayerStatus get status => _engine.getStatus();
  double get deviceLatencyMs => _engine.getDeviceLatencyMs();
  PipelineAudioState get pipelineState => _engine.getPipelineState();
  String getLastError() => _engine.getLastError();
  void clearLastError() => _engine.clearLastError();
  TrackNativeInfo? inspectFile(String path) => _engine.inspectFile(path);
  AEHardwareInfo getHardwareInfo() => _engine.getHardwareInfo();
  bool isNetworkStreamingSupported() => _engine.isNetworkStreamingSupported();
  int getPushStreamBufferedBytes() => _engine.getPushStreamBufferedBytes();
  int getAnalyzerFrameSize() => _engine.getAnalyzerFrameSize();
  int getAnalyzerDroppedFrames() => _engine.getAnalyzerDroppedFrames();
  bool get supportsSystemMediaControls => _systemAudio.isSupported;
  bool get systemMediaControlsEnabled => _systemAudio.isEnabled;

  void configureAnalyzer({int frameSize = 512}) =>
      _engine.configureAnalyzer(frameSize);

  void setAnalyzerEnabled(bool enabled) {
    _analyzerEnabled = enabled;
    _engine.setAnalyzerEnabled(enabled);
  }

  Float32List getLatestAnalyzerFrame({int? maxSamples}) =>
      _engine.pollAnalyzerFrame(maxSamples: maxSamples);

  Future<bool> enableSystemMediaControls({
    MiniAudioSystemAudioConfig config = const MiniAudioSystemAudioConfig(),
  }) =>
      _systemAudio.enable(config: config);

  Future<void> disableSystemMediaControls() => _systemAudio.disable();

  Future<void> updateNowPlaying({
    required String title,
    String? artist,
    String? album,
    String? id,
    Duration? duration,
    Uri? artUri,
  }) =>
      _systemAudio.updateNowPlaying(
        title: title,
        artist: artist,
        album: album,
        id: id,
        duration: duration,
        artUri: artUri,
      );

  void setReverbEnabled(bool enabled) => _engine.setReverbEnabled(enabled);

  void setReverbParams({
    double mix = 0.5,
    double feedback = 0.5,
    double delayMs = 50.0,
  }) {
    _engine.setReverbParams(mix: mix, feedback: feedback, delayMs: delayMs);
  }

  void setOldEqEnabled(bool enabled) => _engine.setEqEnabled(enabled);

  void setOldEqGains({
    double lowGain = 1.0,
    double midGain = 1.0,
    double highGain = 1.0,
  }) {
    _engine.setEqGains(low: lowGain, mid: midGain, high: highGain);
  }

  // --- Advanced Audio Controls ---

  /// Request True Bit-Perfect Output (Exclusive Mode).
  /// Bypasses the system mixer and locks the DAC to the exact requested format.
  /// If the hardware rejects the format natively, it safely falls back to Shared mode.
  /// This will momentarily restart the audio connection.
  void setExclusiveMode(bool enabled) => _engine.setExclusiveMode(enabled);

  /// Check if the engine is actually running in Exclusive Mode successfully.
  bool getExclusiveMode() => _engine.getExclusiveMode();

  /// Set the desired output audio format (f32, s16, u8).
  /// This may cause the audio engine to restart.
  void setOutputFormat(AudioFormat format) => _engine.setOutputFormat(format);

  /// Get the current output audio format.
  AudioFormat getOutputFormat() => _engine.getOutputFormat();

  /// Set the desired output sample rate (e.g., 44100, 48000).
  /// Set to 0 to use the device's native sample rate.
  /// This may cause the audio engine to restart.
  void setOutputSampleRate(int rate) => _engine.setOutputSampleRate(rate);

  /// Get the current output sample rate (0 usually means native/auto).
  int getOutputSampleRate() => _engine.getOutputSampleRate();

  /// Set number of output channels.
  void setOutputChannels(int channels) => _engine.setOutputChannels(channels);

  /// Get output channel count.
  int getOutputChannels() => _engine.getOutputChannels();

  /// Set Phase Inversion (180° polarity flip) for Left and Right channels.
  void setPhaseInversion({required bool invertLeft, required bool invertRight}) =>
      _engine.setPhaseInversion(invertLeft: invertLeft, invertRight: invertRight);

  /// Get current Phase Inversion status.
  ({bool left, bool right}) getPhaseInversion() => _engine.getPhaseInversion();

  /// Initialize the multiband equalizer.
  /// provide a list of center frequencies (Hz) for the bands.
  /// Optional [qFactors] lists the Q factor for each band (defaults to 1.0).
  /// Example 10-band ISO: [31.25, 62.5, 125, 250, 500, 1000, 2000, 4000, 8000, 16000]
  void initMultibandEq(List<double> frequencies, {List<double>? qFactors}) =>
      _engine.initMultibandEq(
        frequencies.length,
        frequencies,
        qFactors: qFactors,
      );

  /// Enable or disable the multiband equalizer.
  void setMultibandEqEnabled(bool enabled) =>
      _engine.setMultibandEqEnabled(enabled);

  /// Set the gain (in dB) for a specific EQ band.
  void setMultibandEqBandGain(int bandIndex, double gainDb) =>
      _engine.setMultibandEqGain(bandIndex, gainDb);

  /// Get the current gain (in dB) for a specific EQ band.
  double getMultibandEqBandGain(int bandIndex) =>
      _engine.getMultibandEqGain(bandIndex);

  /// Configure a mixed multiband FX chain where each band can be a different
  /// filter type (peak, bandpass, notch, lowshelf, highshelf).
  void initMultibandFx(List<EqBandConfig> bands, {bool enabled = true}) {
    _engine.setMultibandFxBands(bands);
    _engine.setMultibandFxEnabled(enabled);
  }

  /// Replace all bands in the mixed multiband FX chain.
  void setMultibandFxBands(List<EqBandConfig> bands) =>
      _engine.setMultibandFxBands(bands);

  /// Enable or disable the mixed multiband FX chain.
  void setMultibandFxEnabled(bool enabled) =>
      _engine.setMultibandFxEnabled(enabled);

  /// Clears all mixed multiband FX bands and disables the chain.
  void clearMultibandFx() => _engine.clearMultibandFx();

  void setReverb({
    required double mix,
    required double feedback,
    required double delayMs,
  }) {
    _engine.setReverbParams(mix: mix, feedback: feedback, delayMs: delayMs);
  }

  void setEqEnabled(bool enabled) => _engine.setEqEnabled(enabled);
  void setEq({required double low, required double mid, required double high}) {
    _engine.setEqGains(low: low, mid: mid, high: high);
  }

  void setGain(double gain) => _engine.setGain(gain);
  void setReplayGain(double gainDb) => _engine.setReplayGain(gainDb);
  void setVolume(double volume) => setGain(volume);
  void setPan(double pan) => _engine.setPan(pan);
  void setPitch(double pitch) => _engine.setPitch(pitch);

  // --- Spatialization ---
  void setSpatializationEnabled(bool enabled) =>
      _engine.setSpatializationEnabled(enabled);
  void setPosition({required double x, required double y, required double z}) =>
      _engine.setPosition(x: x, y: y, z: z);
  void setDirection(
          {required double x, required double y, required double z}) =>
      _engine.setDirection(x: x, y: y, z: z);
  void setVelocity({required double x, required double y, required double z}) =>
      _engine.setVelocity(x: x, y: y, z: z);
  void setAttenuationModel(int model) => _engine.setAttenuationModel(model);
  void setRolloff(double rolloff) => _engine.setRolloff(rolloff);
  void setMinGain(double minGain) => _engine.setMinGain(minGain);
  void setMaxGain(double maxGain) => _engine.setMaxGain(maxGain);
  void setMinDistance(double minDistance) =>
      _engine.setMinDistance(minDistance);
  void setMaxDistance(double maxDistance) =>
      _engine.setMaxDistance(maxDistance);
  void setDopplerFactor(double dopplerFactor) =>
      _engine.setDopplerFactor(dopplerFactor);

  // --- Fading & Scheduling ---
  void setFade(double startVol, double endVol, int durationMs) =>
      _engine.setFade(startVol, endVol, durationMs);
  void scheduleStartTimeInPcmFrames(int absoluteTime) =>
      _engine.scheduleStartTimeInPcmFrames(absoluteTime);
  void scheduleStopTimeInPcmFrames(int absoluteTime) =>
      _engine.scheduleStopTimeInPcmFrames(absoluteTime);
  int getEngineTimeInPcmFrames() => _engine.getEngineTimeInPcmFrames();
  void setEndCallback(
      ffi.Pointer<
              ffi.NativeFunction<
                  ffi.Void Function(
                      ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Void>)>>
          callback,
      ffi.Pointer<ffi.Void> userData) {
    _engine.setEndCallback(callback, userData);
  }

  void setLowpass({required bool enabled, required double cutoffHz}) {
    _engine.setLowpassEnabled(enabled);
    _engine.setLowpassCutoff(cutoffHz);
  }

  void setHighpass({required bool enabled, required double cutoffHz}) {
    _engine.setHighpassEnabled(enabled);
    _engine.setHighpassCutoff(cutoffHz);
  }

  void setDelay({
    required bool enabled,
    required double mix,
    required double feedback,
    required double delayMs,
  }) {
    _engine.setDelayEnabled(enabled);
    _engine.setDelayParams(mix: mix, feedback: feedback, delayMs: delayMs);
  }

  void setStereoWiden({
    required bool enabled,
    required double width,
    required double delayMs,
  }) {
    _engine.setStereoWiden(enabled: enabled, width: width, delayMs: delayMs);
  }

  void setStereoEnhancement({
    required bool enabled,
    double mix = 0.5,
  }) {
    _engine.setStereoEnhancementEnabled(enabled);
    _engine.setStereoEnhancementMix(mix);
  }

  void setCrossfeed({required bool enabled, required int preset}) {
    _engine.setCrossfeedEnabled(enabled);
    _engine.setCrossfeedPreset(preset);
  }

  void setDynamicBass({
    required bool enabled,
    int preset = 18,
    double gain = 100.0,
  }) {
    _engine.setDynamicBassEnabled(enabled);
    _engine.setDynamicBassParams(preset: preset, gain: gain);
  }

  /// Enable or disable the Crystalizer and set its parameters.
  ///
  /// [enabled]          – main on/off switch.
  /// [intensity]        – transient reconstruction strength [0.0 – 1.0].
  /// [highShelfEnabled] – add "air" high-shelf above 8 kHz.
  /// [highShelfGainDb]  – shelf boost in dB [0.0 – 6.0].
  void setCrystalizer({
    required bool enabled,
    double intensity = 0.5,
    bool highShelfEnabled = true,
    double highShelfGainDb = 2.0,
  }) {
    _engine.setCrystalizerEnabled(enabled);
    _engine.setCrystalizerParams(
      intensity: intensity,
      highShelfEnabled: highShelfEnabled,
      highShelfGainDb: highShelfGainDb,
    );
  }

  void setBandpass({
    required bool enabled,
    required double cutoffHz,
    double q = 0.707,
  }) {
    _engine.setBandpassEnabled(enabled);
    _engine.setBandpassParams(cutoffHz: cutoffHz, q: q);
  }

  void setPeakEq({
    required bool enabled,
    required double gainDb,
    required double q,
    required double frequencyHz,
  }) {
    _engine.setPeakEqEnabled(enabled);
    _engine.setPeakEqParams(gainDb: gainDb, q: q, frequencyHz: frequencyHz);
  }

  void setNotch({
    required bool enabled,
    required double q,
    required double frequencyHz,
  }) {
    _engine.setNotchEnabled(enabled);
    _engine.setNotchParams(q: q, frequencyHz: frequencyHz);
  }

  void setLowshelf({
    required bool enabled,
    required double gainDb,
    double slope = 1.0,
    required double frequencyHz,
  }) {
    _engine.setLowshelfEnabled(enabled);
    _engine.setLowshelfParams(
      gainDb: gainDb,
      slope: slope,
      frequencyHz: frequencyHz,
    );
  }

  void setHighshelf({
    required bool enabled,
    required double gainDb,
    double slope = 1.0,
    required double frequencyHz,
  }) {
    _engine.setHighshelfEnabled(enabled);
    _engine.setHighshelfParams(
      gainDb: gainDb,
      slope: slope,
      frequencyHz: frequencyHz,
    );
  }

  void setCustomLpf1({required bool enabled, required double cutoffHz}) {
    _engine.setCustomLpf1Params(enabled: enabled, cutoffHz: cutoffHz);
  }

  void setCustomHpf1({required bool enabled, required double cutoffHz}) {
    _engine.setCustomHpf1Params(enabled: enabled, cutoffHz: cutoffHz);
  }

  void setCustomBiquad({
    required bool enabled,
    required double b0,
    required double b1,
    required double b2,
    required double a0,
    required double a1,
    required double a2,
  }) {
    _engine.setCustomBiquadParams(
      enabled: enabled,
      b0: b0,
      b1: b1,
      b2: b2,
      a0: a0,
      a1: a1,
      a2: a2,
    );
  }

  void setEngineResampleAlgorithm(ResampleAlgorithm algorithm) {
    _engine.setEngineResampleAlgorithm(algorithm.index);
  }

  void setEngineDitherMode(int ditherMode) {
    _engine.setEngineDitherMode(ditherMode);
  }

  // --- Limiter & Clipping Detection ---

  /// Enable or disable the soft limiter.
  void setLimiterEnabled(bool enabled) => _engine.setLimiterEnabled(enabled);

  /// Configure limiter parameters.
  /// [threshold] linear amplitude ceiling (0.1–1.0, default 0.95).
  /// [attackMs]  attack time in ms (0.1–100, default 2).
  /// [releaseMs] release time in ms (10–1000, default 50).
  void setLimiterParams({
    double threshold = 0.95,
    double attackMs = 2.0,
    double releaseMs = 50.0,
  }) =>
      _engine.setLimiterParams(
        threshold: threshold,
        attackMs: attackMs,
        releaseMs: releaseMs,
      );

  /// Enable or disable clipping detection.
  void setClippingDetectionEnabled(bool enabled) =>
      _engine.setClippingDetectionEnabled(enabled);

  /// Total number of samples that exceeded ±1.0 since last reset.
  int getClippedSamplesCount() => _engine.getClippedSamplesCount();

  /// Reset the clipped-sample counter to zero.
  void resetClippedSamplesCount() => _engine.resetClippedSamplesCount();

  Future<void> pushStream({required String url}) async {
    _engine.initPushStream();

    final client = http.Client();
    try {
      final request = http.Request('GET', Uri.parse(url));
      final response = await client.send(request);

      int bytesReceived = 0;
      bool playbackStarted = false;
      // 64KB buffer threshold before starting playback
      const bufferThreshold = 64 * 1024;

      await for (final chunk in response.stream) {
        final size = chunk.length;
        final ptr = calloc<ffi.Uint8>(size);
        final list = ptr.asTypedList(size);
        list.setAll(0, chunk);

        _engine.pushStreamChunk(ptr, size);
        calloc.free(ptr);

        bytesReceived += size;
        if (!playbackStarted && bytesReceived >= bufferThreshold) {
          play();
          playbackStarted = true;
        }
      }
    } catch (e) {
      rethrow;
    } finally {
      client.close();
      _engine.endPushStream();
    }
  }

  void _startStatusPolling() {
    _statusTimer?.cancel();
    _statusTimer = Timer.periodic(statusPollInterval, (_) {
      if (_statusController.isClosed) return;
      _statusController.add(_engine.getStatus());

      if (!_logController.isClosed) {
        final msg = _engine.getLastError();
        if (msg.isNotEmpty && msg != _lastLog) {
          _lastLog = msg;
          _logController.add(msg);
        }
      }
    });
  }

  void _startAnalyzerPolling() {
    _analyzerTimer?.cancel();
    _analyzerTimer = Timer.periodic(analyzerPollInterval, (_) {
      if (_analyzerController.isClosed || !_analyzerEnabled) return;
      final frame = _engine.pollAnalyzerFrame();
      if (frame.isNotEmpty) {
        _analyzerController.add(frame);
      }
    });
  }
}
