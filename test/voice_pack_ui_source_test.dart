import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lingua_patente/config/app_strings.dart';
import 'package:lingua_patente/models/user_state.dart';

void main() {
  const voicePackKeys = [
    'voice_pack_title',
    'voice_pack_settings_subtitle',
    'voice_pack_intro',
    'voice_pack_total_installed',
    'voice_pack_chapter_number',
    'voice_pack_uncategorized',
    'voice_pack_all_questions',
    'voice_pack_question_count',
    'voice_pack_status_not_downloaded',
    'voice_pack_status_downloading',
    'voice_pack_status_paused',
    'voice_pack_status_installed',
    'voice_pack_status_failed',
    'voice_pack_download',
    'voice_pack_download_all',
    'voice_pack_download_confirm_title',
    'voice_pack_download_confirm_wifi_message',
    'voice_pack_download_confirm_mobile_message',
    'voice_pack_continue_download',
    'voice_pack_storage_insufficient_title',
    'voice_pack_storage_insufficient_message',
    'voice_pack_offline_title',
    'voice_pack_offline_message',
    'voice_pack_ok',
    'voice_pack_pause',
    'voice_pack_resume',
    'voice_pack_cancel',
    'voice_pack_delete',
    'voice_pack_retry',
    'voice_pack_loading_catalog',
    'voice_pack_empty_catalog',
    'voice_pack_catalog_error',
    'voice_pack_downloaded_of',
    'voice_pack_delete_confirm_title',
    'voice_pack_delete_confirm_message',
    'voice_pack_delete_confirm',
    'voice_pack_prompt_title',
    'voice_pack_prompt_message',
    'voice_pack_manage',
    'voice_pack_use_system_voice',
  ];

  test('every supported language has voice pack copy', () {
    for (final language in UserState.supportedLanguages) {
      for (final key in voicePackKeys) {
        expect(
          AppStrings.getWithLanguage(language, key),
          isNot(key),
          reason: '$language is missing $key',
        );
      }
    }
  });

  test('Simplified Chinese voice pack copy has no common traditional forms',
      () {
    final copy = voicePackKeys
        .map((key) => AppStrings.getWithLanguage('zh', key))
        .join();

    expect(copy, isNot(matches(RegExp('[個這實際離線語聲繼續載後時與總確認刪]'))));
  });

  group('voice pack screen source guards', () {
    final source =
        File('lib/screens/voice_pack_screen.dart').readAsStringSync();

    test('covers every download state and operation', () {
      for (final status in [
        'notDownloaded',
        'downloading',
        'paused',
        'installed',
        'failed',
      ]) {
        expect(source, contains('VoicePackDownloadStatus.$status'));
      }

      for (final operation in [
        '.download(',
        '.pause(',
        '.resume(',
        '.cancel(',
        '.delete(',
      ]) {
        expect(source, contains(operation));
      }
    });

    test('shows progress, catalog recovery, and delete confirmation', () {
      expect(source, contains('LinearProgressIndicator'));
      expect(source, contains('downloadedBytes'));
      expect(source, contains('totalBytes'));
      expect(source, contains('isCatalogLoading'));
      expect(source, contains('catalogError'));
      expect(source, contains('refreshCatalog'));
      expect(source, contains('showDialog<bool>'));
      expect(source, contains('DownloadPreflightService'));
      expect(source, contains('requiredStorageBytes'));
      expect(source, contains('DownloadConnectionType.offline'));
      expect(source, contains('voice_pack_download_confirm_mobile_message'));
      expect(source, contains('voice_pack_storage_insufficient_message'));
      expect(source, contains('voice_pack_delete_confirm_message'));
      expect(source, contains("AppStrings.get('voice_pack_uncategorized')"));
      expect(source, contains("AppStrings.get('voice_pack_all_questions')"));
      expect(source, contains("'voice_pack_download_all'"));
      expect(source, contains('state.pack.isAllQuestions'));
      expect(source, contains('chapterId == null'));
    });

    test('voice packs are not gated by login, VIP, or purchases', () {
      expect(source, isNot(contains('isVip')));
      expect(source, isNot(contains('isLoggedIn')));
      expect(source, isNot(contains('SubscriptionPage')));
      expect(source, isNot(contains('purchase')));
    });
  });

  test('question speech button exposes preparing and stop states', () {
    final source = File('lib/widgets/question_widget.dart').readAsStringSync();

    expect(source, contains("'speech_preparing'"));
    expect(source, contains("'speech_stop'"));
    expect(source, contains('_speechSession'));
    expect(source, contains('_isPreparingSpeech || _isSpeakingQuestion'));
    expect(source, contains('oldWidget.question.id != widget.question.id'));
    expect(source, contains('_speechService.stop()'));
  });

  test('settings has an unconditional route to voice pack management', () {
    final source = File('lib/screens/settings_screen.dart').readAsStringSync();

    expect(source, contains("import 'voice_pack_screen.dart';"));
    expect(source, contains("AppStrings.get('voice_pack_title')"));
    expect(source, contains('const VoicePackScreen()'));
  });

  test('the completed all-questions pack retires old chapter directories', () {
    final source =
        File('lib/services/voice_pack_service.dart').readAsStringSync();

    expect(source, contains('if (pack.isAllQuestions)'));
    expect(source, contains('_removeRetiredPackDirectories'));
  });
}
