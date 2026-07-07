import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:audio_session/audio_session.dart';

/// Audio service for playing synchronized audio with canvas timeline
class AudioService {
  final AudioPlayer _player = AudioPlayer();
  final _stateController = StreamController<AudioServiceState>.broadcast();

  Stream<AudioServiceState> get stateStream => _stateController.stream;

  String? _currentUrl;
  bool _isInitialized = false;
  late final Future<void> _initFuture;

  AudioService() {
    _initFuture = _init();
  }

  Future<void> _init() async {
    try {
      // Configure audio session
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration(
        avAudioSessionCategory: AVAudioSessionCategory.playback,
        avAudioSessionCategoryOptions: AVAudioSessionCategoryOptions.mixWithOthers,
        avAudioSessionMode: AVAudioSessionMode.defaultMode,
        androidAudioAttributes: AndroidAudioAttributes(
          contentType: AndroidAudioContentType.speech,
          usage: AndroidAudioUsage.media,
        ),
        androidAudioFocusGainType: AndroidAudioFocusGainType.gainTransientMayDuck,
      ));

      // Listen to player state changes
      _player.playerStateStream.listen((state) {
        if (_stateController.isClosed) return; // dispose sonrası add → crash
        _stateController.add(AudioServiceState(
          isPlaying: state.playing,
          processingState: state.processingState,
          position: _player.position,
          duration: _player.duration,
          currentUrl: _currentUrl,
        ));
      });

      _isInitialized = true;
    } catch (e) {
      debugPrint('[AudioService] Init error: $e');
    }
  }

  /// Play audio from URL or asset path
  Future<void> play(String url, {int startTimeMs = 0}) async {
    // Init bitmeden gelen erken play çağrısı sessizce düşmesin — bekle.
    await _initFuture;
    if (!_isInitialized) {
      debugPrint('[AudioService] Not initialized');
      return;
    }

    try {
      // Load new source if different
      if (_currentUrl != url) {
        _currentUrl = url;

        AudioSource source;
        if (url.startsWith('http://') || url.startsWith('https://')) {
          source = AudioSource.uri(Uri.parse(url));
        } else if (url.startsWith('asset://') || url.startsWith('assets/')) {
          // Asset path
          final assetPath = url.replaceFirst('asset://', '').replaceFirst('assets/', '');
          source = AudioSource.asset('assets/$assetPath');
        } else {
          // Assume it's a file path
          source = AudioSource.file(url);
        }

        await _player.setAudioSource(source);
      }

      // Seek if needed
      if (startTimeMs > 0) {
        await _player.seek(Duration(milliseconds: startTimeMs));
      }

      await _player.play();
    } catch (e) {
      debugPrint('[AudioService] Play error: $e');
      if (!_stateController.isClosed) _stateController.addError(e);
    }
  }

  /// Pause playback
  Future<void> pause() async {
    try {
      await _player.pause();
    } catch (e) {
      debugPrint('[AudioService] Pause error: $e');
    }
  }

  /// Stop playback
  Future<void> stop() async {
    try {
      await _player.stop();
      _currentUrl = null;
    } catch (e) {
      debugPrint('[AudioService] Stop error: $e');
    }
  }

  /// Seek to position
  Future<void> seek(int milliseconds) async {
    try {
      await _player.seek(Duration(milliseconds: milliseconds));
    } catch (e) {
      debugPrint('[AudioService] Seek error: $e');
    }
  }

  /// Set playback speed
  Future<void> setSpeed(double speed) async {
    try {
      await _player.setSpeed(speed);
    } catch (e) {
      debugPrint('[AudioService] SetSpeed error: $e');
    }
  }

  /// Set volume (0.0 to 1.0)
  Future<void> setVolume(double volume) async {
    try {
      await _player.setVolume(volume.clamp(0.0, 1.0));
    } catch (e) {
      debugPrint('[AudioService] SetVolume error: $e');
    }
  }

  /// Get current position in milliseconds
  int get currentPositionMs => _player.position.inMilliseconds;

  /// Get total duration in milliseconds
  int get durationMs => _player.duration?.inMilliseconds ?? 0;

  /// Check if playing
  bool get isPlaying => _player.playing;

  void dispose() {
    _player.dispose();
    _stateController.close();
  }
}

/// Audio service state
class AudioServiceState {
  final bool isPlaying;
  final ProcessingState processingState;
  final Duration? position;
  final Duration? duration;
  final String? currentUrl;

  AudioServiceState({
    required this.isPlaying,
    required this.processingState,
    this.position,
    this.duration,
    this.currentUrl,
  });

  int get positionMs => position?.inMilliseconds ?? 0;
  int get durationMs => duration?.inMilliseconds ?? 0;
  bool get isLoading => processingState == ProcessingState.loading;
  bool get isBuffering => processingState == ProcessingState.buffering;
  bool get isCompleted => processingState == ProcessingState.completed;
}
