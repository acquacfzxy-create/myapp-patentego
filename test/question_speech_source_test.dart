import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lingua_patente/services/question_speech_service.dart';

void main() {
  group('question speech integration guards', () {
    test('downloaded natural audio is checked before system TTS fallback', () {
      final source =
          File('lib/services/question_speech_service.dart').readAsStringSync();

      expect(source, contains('localAudioPath(questionId)'));
      expect(source, contains('_playNaturalAudio('));
      expect(source, contains('return _speakWithSystemTts('));
    });

    test('question UI offers voice pack management before first fallback', () {
      final source =
          File('lib/widgets/question_widget.dart').readAsStringSync();

      expect(source, contains('shouldOfferVoicePack(widget.question.id)'));
      expect(source, contains('VoicePackScreen'));
      expect(source, contains('rememberSystemVoiceChoice()'));
      expect(source, contains('questionId: widget.question.id'));
    });

    test('storage rules expose voice packs as read-only assets', () {
      final source = File('storage.rules').readAsStringSync();

      expect(source, contains('match /voice_packs/{path=**}'));
      expect(source, contains('allow read: if true'));
      expect(source, contains('allow write: if false'));
    });

    test('Web practice streams the App voice and keeps a TTS fallback', () {
      final screen = File('lib/screens/web_app_screen.dart').readAsStringSync();
      final speech =
          File('lib/services/question_speech_service.dart').readAsStringSync();

      expect(screen, contains('questionId: question.id'));
      expect(screen, contains('preferNaturalAudio: true'));
      expect(
          speech, contains('_webVoiceStreamService.audioUriFor(questionId)'));
      expect(speech, contains('_playStreamedAudio('));
      expect(speech, contains('Missing/slow Web audio falls through'));
    });

    test('web and native system voices use platform-appropriate rates', () {
      final source =
          File('lib/services/question_speech_service.dart').readAsStringSync();

      expect(source, contains('kIsWeb ? 0.9 : 0.46'));
      expect(source, contains('return kIsWeb ? true : result == 1'));
    });
  });

  group('Italian web voice selection', () {
    test('prefers it-IT over another Italian locale', () {
      final selected = QuestionSpeechService.selectItalianWebVoice([
        {'name': 'Premium Natural Voice', 'locale': 'it-CH'},
        {'name': 'Standard Italian', 'locale': 'it-IT'},
      ]);

      expect(selected, {
        'name': 'Standard Italian',
        'locale': 'it-IT',
      });
    });

    test('uses natural-quality name hints within the same locale', () {
      final selected = QuestionSpeechService.selectItalianWebVoice([
        {'name': 'Italiano standard', 'locale': 'it-IT'},
        {'name': 'Microsoft Elsa Online (Natural)', 'locale': 'it-IT'},
      ]);

      expect(selected?['name'], 'Microsoft Elsa Online (Natural)');
    });

    test('falls back to another it locale and accepts underscore tags', () {
      final selected = QuestionSpeechService.selectItalianWebVoice([
        {'name': 'English Natural', 'locale': 'en-US'},
        {'name': 'Voce italiana', 'locale': 'it_CH'},
      ]);

      expect(selected, {'name': 'Voce italiana', 'locale': 'it_CH'});
    });

    test('accepts a bare it locale as the last Italian fallback', () {
      final selected = QuestionSpeechService.selectItalianWebVoice([
        {'name': 'Voce generica', 'locale': 'it'},
        {'name': 'English Natural', 'locale': 'en-US'},
      ]);

      expect(selected, {'name': 'Voce generica', 'locale': 'it'});
    });

    test('returns null instead of selecting a non-Italian default voice', () {
      final selected = QuestionSpeechService.selectItalianWebVoice([
        {'name': 'English Natural', 'locale': 'en-US'},
        {'name': 'Deutsch Neural', 'locale': 'de-DE'},
        {'name': '', 'locale': 'it-IT'},
      ]);

      expect(selected, isNull);
    });
  });
}
