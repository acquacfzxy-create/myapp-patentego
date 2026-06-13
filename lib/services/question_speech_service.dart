import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

class QuestionSpeechService {
  final FlutterTts _tts = FlutterTts();
  bool _isConfigured = false;

  Future<bool> speakItalian(
    String text, {
    VoidCallback? onStart,
    VoidCallback? onStop,
    ValueChanged<dynamic>? onError,
  }) async {
    final content = text.trim();
    if (content.isEmpty) return false;

    await _configure(
      onStart: onStart,
      onStop: onStop,
      onError: onError,
    );

    await _tts.stop();
    final result = await _tts.speak(content, focus: true);
    return result == 1;
  }

  Future<void> stop() async {
    await _tts.stop();
  }

  void dispose() {
    _tts.stop();
  }

  Future<void> _configure({
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

    if (_isConfigured) return;

    await _tts.awaitSpeakCompletion(false);
    await _tts.setLanguage('it-IT');
    await _tts.setSpeechRate(0.46);
    await _tts.setVolume(1.0);
    await _tts.setPitch(1.0);
    _isConfigured = true;
  }
}
