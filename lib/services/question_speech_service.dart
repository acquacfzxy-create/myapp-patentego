import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'voice_pack_service.dart';
import 'web_voice_stream_service.dart';

/// 題目朗讀入口：App 優先播放已下載語音，Web 優先串流同一份 MP3；
/// 真人語音不可用時回退意大利語系統 TTS。
class QuestionSpeechService {
  QuestionSpeechService({
    VoicePackService? voicePackService,
    WebVoiceStreamService? webVoiceStreamService,
    FlutterTts? tts,
    AudioPlayer? audioPlayer,
  })  : _voicePackService = voicePackService ?? VoicePackService.instance,
        _webVoiceStreamService =
            webVoiceStreamService ?? WebVoiceStreamService(),
        _tts = tts ?? FlutterTts(),
        _audioPlayer = audioPlayer ?? AudioPlayer();

  static const String _systemVoiceChoiceKey =
      'question_speech_system_voice_choice_v1';
  static const Duration _webVoiceWaitTimeout = Duration(milliseconds: 900);
  static const Duration _webVoicePollInterval = Duration(milliseconds: 100);
  static const String _italianVoiceUnavailableMessage =
      'No Italian speech voice is available in this browser.';

  final VoicePackService _voicePackService;
  final WebVoiceStreamService _webVoiceStreamService;
  final FlutterTts _tts;
  final AudioPlayer _audioPlayer;

  StreamSubscription<PlayerState>? _playerStateSubscription;
  bool _isConfigured = false;
  bool _isNaturalAudioPlaying = false;
  bool _isDisposed = false;
  int _playbackRequest = 0;
  VoidCallback? _naturalOnStop;
  ValueChanged<dynamic>? _naturalOnError;
  Future<bool> Function()? _naturalFallback;

  /// 首次使用且本題沒有真人語音時，讓使用者先選擇下載或沿用系統語音。
  Future<bool> shouldOfferVoicePack(String questionId) async {
    if (kIsWeb) return false;
    if (await hasNaturalAudio(questionId)) return false;
    final preferences = await SharedPreferences.getInstance();
    return !(preferences.getBool(_systemVoiceChoiceKey) ?? false);
  }

  /// 記住使用者接受系統語音；日後下載語音包後仍會自動優先播放真人語音。
  Future<void> rememberSystemVoiceChoice() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_systemVoiceChoiceKey, true);
  }

  Future<bool> hasNaturalAudio(String questionId) async {
    if (kIsWeb) return false;
    try {
      await _voicePackService.initialize();
      final path = _voicePackService.localAudioPath(questionId);
      return path != null && File(path).existsSync();
    } catch (_) {
      return false;
    }
  }

  Future<bool> speakItalian(
    String text, {
    String? questionId,
    bool preferNaturalAudio = true,
    VoidCallback? onStart,
    VoidCallback? onStop,
    ValueChanged<dynamic>? onError,
  }) async {
    final content = text.trim();
    if (content.isEmpty || _isDisposed) return false;

    await stop();
    final playbackRequest = _playbackRequest;

    if (kIsWeb && preferNaturalAudio && questionId != null) {
      try {
        final audioUri = await _webVoiceStreamService.audioUriFor(questionId);
        if (playbackRequest != _playbackRequest) return false;
        if (audioUri != null) {
          final started = await _playStreamedAudio(
            audioUri,
            playbackRequest: playbackRequest,
            onStart: onStart,
            onStop: onStop,
            onError: onError,
            fallback: () => _speakWithSystemTts(
              content,
              onStart: onStart,
              onStop: onStop,
              onError: onError,
              playbackRequest: playbackRequest,
            ),
          );
          if (started) return true;
        }
      } catch (_) {
        // Missing/slow Web audio falls through to the Italian system voice.
      }
    }

    if (!kIsWeb && preferNaturalAudio && questionId != null) {
      try {
        await _voicePackService.initialize();
        if (playbackRequest != _playbackRequest) return false;
        final audioPath = _voicePackService.localAudioPath(questionId);
        if (audioPath != null && File(audioPath).existsSync()) {
          final started = await _playNaturalAudio(
            audioPath,
            playbackRequest: playbackRequest,
            onStart: onStart,
            onStop: onStop,
            onError: onError,
            fallback: () => _speakWithSystemTts(
              content,
              onStart: onStart,
              onStop: onStop,
              onError: onError,
              playbackRequest: playbackRequest,
            ),
          );
          if (started) return true;
        }
      } catch (_) {
        // 本地語音損壞或播放器不支援時，無感回退到系統 TTS。
      }
    }

    return _speakWithSystemTts(
      content,
      onStart: onStart,
      onStop: onStop,
      onError: onError,
      playbackRequest: playbackRequest,
    );
  }

  Future<bool> _playNaturalAudio(
    String path, {
    required int playbackRequest,
    VoidCallback? onStart,
    VoidCallback? onStop,
    ValueChanged<dynamic>? onError,
    Future<bool> Function()? fallback,
  }) async {
    await _playerStateSubscription?.cancel();
    await _audioPlayer.setFilePath(path);
    if (playbackRequest != _playbackRequest) return false;

    return _startPreparedAudio(
      onStart: onStart,
      onStop: onStop,
      onError: onError,
      fallback: fallback,
    );
  }

  Future<bool> _playStreamedAudio(
    Uri uri, {
    required int playbackRequest,
    VoidCallback? onStart,
    VoidCallback? onStop,
    ValueChanged<dynamic>? onError,
    Future<bool> Function()? fallback,
  }) async {
    await _playerStateSubscription?.cancel();
    await _audioPlayer.setUrl(uri.toString());
    if (playbackRequest != _playbackRequest) return false;

    return _startPreparedAudio(
      onStart: onStart,
      onStop: onStop,
      onError: onError,
      fallback: fallback,
    );
  }

  Future<bool> _startPreparedAudio({
    VoidCallback? onStart,
    VoidCallback? onStop,
    ValueChanged<dynamic>? onError,
    Future<bool> Function()? fallback,
  }) async {
    _naturalOnStop = onStop;
    _naturalOnError = onError;
    _naturalFallback = fallback;
    _isNaturalAudioPlaying = true;
    _playerStateSubscription = _audioPlayer.playerStateStream.listen(
      (state) {
        if (state.processingState == ProcessingState.completed) {
          _finishNaturalAudio();
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        _handleNaturalAudioError(error);
      },
    );

    onStart?.call();
    unawaited(
      _audioPlayer.play().catchError((Object error, StackTrace stackTrace) {
        _handleNaturalAudioError(error);
      }),
    );
    return true;
  }

  Future<bool> _speakWithSystemTts(
    String content, {
    VoidCallback? onStart,
    VoidCallback? onStop,
    ValueChanged<dynamic>? onError,
    required int playbackRequest,
  }) async {
    var didReportError = false;
    void reportError(dynamic error) {
      if (didReportError) return;
      didReportError = true;
      onError?.call(error);
    }

    try {
      final configured = await _configure(
        onStart: onStart,
        onStop: onStop,
        onError: reportError,
      );
      if (!configured) {
        reportError(StateError(_italianVoiceUnavailableMessage));
        return false;
      }
      if (playbackRequest != _playbackRequest) return false;

      final result = await _tts.speak(content, focus: true);
      // flutter_tts Web completes a successful method call with null, while
      // native implementations report success with the integer value 1.
      return kIsWeb ? true : result == 1;
    } catch (error) {
      reportError(error);
      return false;
    }
  }

  void _finishNaturalAudio({Object? error}) {
    if (!_isNaturalAudioPlaying) return;
    _isNaturalAudioPlaying = false;
    final onStop = _naturalOnStop;
    final onError = _naturalOnError;
    _naturalOnStop = null;
    _naturalOnError = null;
    _naturalFallback = null;
    onStop?.call();
    if (error != null) onError?.call(error);
  }

  void _handleNaturalAudioError(Object error) {
    if (!_isNaturalAudioPlaying) return;
    final fallback = _naturalFallback;
    final onError = _naturalOnError;
    _finishNaturalAudio();
    if (fallback == null) {
      onError?.call(error);
      return;
    }
    unawaited(
      fallback().then((started) {
        if (!started) onError?.call(error);
      }).catchError((Object fallbackError, StackTrace stackTrace) {
        onError?.call(fallbackError);
      }),
    );
  }

  Future<void> stop() async {
    _playbackRequest++;
    if (_isNaturalAudioPlaying) {
      await _audioPlayer.stop();
      _finishNaturalAudio();
    }
    await _tts.stop();
  }

  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;
    unawaited(_disposeAsync());
  }

  Future<void> _disposeAsync() async {
    await _playerStateSubscription?.cancel();
    await _audioPlayer.dispose();
    await _tts.stop();
  }

  Future<bool> _configure({
    VoidCallback? onStart,
    VoidCallback? onStop,
    ValueChanged<dynamic>? onError,
  }) async {
    _tts.setStartHandler(() {
      onStart?.call();
    });
    _tts.setCompletionHandler(() {
      onStop?.call();
    });
    _tts.setCancelHandler(() {
      onStop?.call();
    });
    _tts.setErrorHandler((message) {
      onStop?.call();
      onError?.call(message);
    });

    if (_isConfigured) return true;

    await _tts.awaitSpeakCompletion(false);
    if (kIsWeb) {
      final voice = await _waitForItalianWebVoice();
      if (voice == null) return false;
      await _tts.setLanguage(voice['locale']!);
      await _tts.setVoice(voice);
    } else {
      await _tts.setLanguage('it-IT');
    }
    await _tts.setSpeechRate(kIsWeb ? 0.9 : 0.46);
    await _tts.setVolume(1.0);
    await _tts.setPitch(1.0);
    _isConfigured = true;
    return true;
  }

  Future<Map<String, String>?> _waitForItalianWebVoice() async {
    final stopwatch = Stopwatch()..start();
    while (true) {
      final voices = await _tts.getVoices;
      if (voices is Iterable) {
        final voice = selectItalianWebVoice(voices);
        if (voice != null) return voice;
      }

      final remaining = _webVoiceWaitTimeout - stopwatch.elapsed;
      if (remaining <= Duration.zero) return null;
      await Future<void>.delayed(
        remaining < _webVoicePollInterval ? remaining : _webVoicePollInterval,
      );
    }
  }

  @visibleForTesting
  static Map<String, String>? selectItalianWebVoice(
    Iterable<dynamic> voices,
  ) {
    Map<String, String>? bestVoice;
    var bestScore = -1;

    for (final rawVoice in voices) {
      if (rawVoice is! Map) continue;
      final name = rawVoice['name']?.toString().trim() ?? '';
      final locale = rawVoice['locale']?.toString().trim() ?? '';
      if (name.isEmpty || locale.isEmpty) continue;

      final normalizedLocale = locale.toLowerCase().replaceAll('_', '-');
      final localeScore = switch (normalizedLocale) {
        'it-it' => 1000,
        _ when normalizedLocale.startsWith('it-') => 500,
        'it' => 250,
        _ => -1,
      };
      if (localeScore < 0) continue;

      final normalizedName = name.toLowerCase();
      var qualityScore = 0;
      const qualityHints = <String, int>{
        'natural': 80,
        'neural': 70,
        'premium': 60,
        'enhanced': 50,
        'wavenet': 40,
        'online': 20,
        'google': 10,
      };
      for (final hint in qualityHints.entries) {
        if (normalizedName.contains(hint.key)) qualityScore += hint.value;
      }

      final score = localeScore + qualityScore;
      if (score > bestScore) {
        bestScore = score;
        bestVoice = <String, String>{'name': name, 'locale': locale};
      }
    }

    return bestVoice;
  }
}
