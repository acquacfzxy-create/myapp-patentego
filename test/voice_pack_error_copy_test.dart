import 'dart:async';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lingua_patente/config/app_locales.dart';
import 'package:lingua_patente/config/app_strings.dart';
import 'package:lingua_patente/config/app_theme.dart';
import 'package:lingua_patente/config/user_error_copy.dart';
import 'package:lingua_patente/models/user_state.dart';
import 'package:lingua_patente/screens/voice_pack_screen.dart';
import 'package:lingua_patente/services/voice_pack_service.dart';

/// 语音包目录加载 / 下载失败只显示本地化文案，不显示原始 SDK、HTTP 或文件系统错误。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('VoicePackService.errorCodeFor', () {
    test('classifies known failures', () {
      expect(
        VoicePackService.errorCodeFor(
          FirebaseException(
              plugin: 'firebase_storage', code: 'retry-limit-exceeded'),
        ),
        'voice_pack_error_network',
      );
      expect(
        VoicePackService.errorCodeFor(
          FirebaseException(plugin: 'firebase_storage', code: 'unauthorized'),
        ),
        'voice_pack_error_unavailable',
      );
      expect(
        VoicePackService.errorCodeFor(
          FirebaseException(
              plugin: 'firebase_storage', code: 'invalid-checksum'),
        ),
        'voice_pack_error_corrupted',
      );
      expect(
        VoicePackService.errorCodeFor(
            const SocketException('Failed host lookup')),
        'voice_pack_error_network',
      );
      expect(
        VoicePackService.errorCodeFor(TimeoutException('slow')),
        'voice_pack_error_network',
      );
      expect(
        VoicePackService.errorCodeFor(
          HttpException(
            'Voice pack download failed with HTTP 403.',
            uri: Uri.parse('https://example.invalid/pack.zip?token=secret'),
          ),
        ),
        'voice_pack_error_unavailable',
      );
      expect(
        VoicePackService.errorCodeFor(
          const FormatException(
              'Voice pack archive file count does not match the manifest.'),
        ),
        'voice_pack_error_corrupted',
      );
      expect(
        VoicePackService.errorCodeFor(
          const FileSystemException('write failed', '/data/pack',
              OSError('No space left on device', 28)),
        ),
        'voice_pack_error_storage_full',
      );
      expect(
        VoicePackService.errorCodeFor(
          const FileSystemException(
              'write failed', '/data/pack', OSError('Permission denied', 13)),
        ),
        'voice_pack_error_storage',
      );
      expect(
        VoicePackService.errorCodeFor(StateError('unexpected')),
        'voice_pack_error_generic',
      );
    });

    test('never returns the raw error text', () {
      const secret = 'token=abc123';
      final code = VoicePackService.errorCodeFor(
        HttpException('failed https://storage.example/pack?$secret'),
      );
      expect(code, isNot(contains(secret)));
      expect(code, startsWith('voice_pack_error_'));
    });
  });

  group('UserErrorCopy.voicePack', () {
    const codes = [
      'voice_pack_error_network',
      'voice_pack_error_unavailable',
      'voice_pack_error_storage_full',
      'voice_pack_error_storage',
      'voice_pack_error_corrupted',
      'voice_pack_error_cancelled',
      'voice_pack_error_generic',
    ];

    for (final language in UserState.supportedLanguages) {
      test('codes are localized and unknown values fall back [$language]', () {
        final english =
            AppStrings.getWithLanguage('en', 'voice_pack_error_generic');
        for (final code in codes) {
          final copy = UserErrorCopy.voicePack(code, language: language);
          expect(copy, AppStrings.getWithLanguage(language, code));
          expect(copy, isNot(code), reason: 'missing $language/$code');
          if (language != 'en' && code == 'voice_pack_error_generic') {
            expect(copy, isNot(english));
          }
        }
        final generic =
            AppStrings.getWithLanguage(language, 'voice_pack_error_generic');
        // 旧版本残留的原始文字、未知值、空值都显示通用提示。
        expect(
            UserErrorCopy.voicePack('Firebase Storage error (unauthorized).',
                language: language),
            generic);
        expect(
            UserErrorCopy.voicePack('voice_pack_error_made_up',
                language: language),
            generic);
        expect(UserErrorCopy.voicePack(null, language: language), generic);
      });
    }
  });

  group('VoicePackScreen catalog failure', () {
    setUpAll(() async {
      for (final entry in const {
        'NotoSans': [
          'NotoSans-Regular.ttf',
          'NotoSans-SemiBold.ttf',
          'NotoSans-Bold.ttf'
        ],
        'NotoSansSC': ['NotoSansCJKsc-Regular.otf', 'NotoSansCJKsc-Bold.otf'],
        'NotoNastaliqUrdu': [
          'NotoNastaliqUrdu-Regular.ttf',
          'NotoNastaliqUrdu-Bold.ttf'
        ],
        'NotoSansGurmukhi': [
          'NotoSansGurmukhi-Regular.ttf',
          'NotoSansGurmukhi-Bold.ttf'
        ],
      }.entries) {
        final loader = FontLoader(entry.key);
        for (final file in entry.value) {
          final bytes = File('assets/fonts/noto/$file').readAsBytesSync();
          loader.addFont(Future.value(ByteData.sublistView(bytes)));
        }
        await loader.load();
      }
    });

    for (final language in UserState.supportedLanguages) {
      for (final scale in const [1.0, 1.5]) {
        testWidgets(
            'shows localized copy only, fits 320px [$language, x$scale]',
            (tester) async {
          tester.view.physicalSize = const Size(320, 640);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          AppStrings.setLanguage(language);

          // 测试环境没有 path_provider / Firebase，目录初始化会真实地失败。
          await tester.pumpWidget(MaterialApp(
            locale: AppLocales.localeFor(language),
            supportedLocales: AppLocales.supportedLocales,
            localizationsDelegates: AppLocales.delegates,
            theme: AppTheme.lightTheme(language: language),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: const VoicePackScreen(),
          ));
          // 插件调用的失败在真实事件循环中返回，需要让真实异步推进。
          for (var i = 0; i < 20; i++) {
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 20)),
            );
            await tester.pump(const Duration(milliseconds: 100));
            if (find
                .text(AppStrings.getWithLanguage(
                    language, 'voice_pack_catalog_error'))
                .evaluate()
                .isNotEmpty) {
              break;
            }
          }

          String t(String key) => AppStrings.getWithLanguage(language, key);
          expect(find.text(t('voice_pack_catalog_error')), findsOneWidget);
          expect(find.text(t('voice_pack_error_generic')), findsOneWidget);
          for (final raw in [
            'MissingPluginException',
            'Exception',
            'Firebase',
            'plugins.flutter.io'
          ]) {
            expect(find.textContaining(raw), findsNothing,
                reason: 'raw "$raw" is visible');
          }
          expect(tester.takeException(), isNull);
          expect(
            Directionality.of(tester.element(find.byType(VoicePackScreen))),
            language == 'ur' ? TextDirection.rtl : TextDirection.ltr,
          );

          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump(const Duration(seconds: 1));
        });
      }
    }
  });

  test('screen routes every visible voice pack error through UserErrorCopy',
      () {
    final source =
        File('lib/screens/voice_pack_screen.dart').readAsStringSync();
    expect(source, isNot(contains('detail: catalogError,')));
    expect(source, isNot(contains('state.error!,')));
    expect(source, isNot(contains('error.toString()')));
    expect(RegExp(r'UserErrorCopy\.voicePack\(').allMatches(source).length, 2);
  });
}
