import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:italy_quiz_app/config/app_config.dart';
import 'package:italy_quiz_app/config/app_strings.dart';
import 'package:italy_quiz_app/models/user_state.dart';

void main() {
  group('PatenteGo release smoke tests', () {
    test('free users can access only the configured free chapters', () {
      expect(AppConfig.freeChapterLimit, 3);
      expect(AppConfig.isChapterLocked(1, isVip: false), isFalse);
      expect(AppConfig.isChapterLocked(2, isVip: false), isFalse);
      expect(AppConfig.isChapterLocked(3, isVip: false), isFalse);
      expect(AppConfig.isChapterLocked(4, isVip: false), isTrue);
      expect(AppConfig.isChapterLocked(25, isVip: true), isFalse);
    });

    test('monthly subscription product and legal URLs are configured', () {
      expect(
        AppConfig.monthlySubscriptionProductId,
        'patentego_vip_monthly',
      );
      expect(
        AppConfig.privacyPolicyUrl,
        'https://acquacfzxy-create.github.io/myapp-patentego/privacy.html',
      );
      expect(
        AppConfig.termsOfServiceUrl,
        'https://acquacfzxy-create.github.io/myapp-patentego/terms.html',
      );
      expect(
        AppConfig.supportContactUrl,
        'mailto:patentegoapp@gmail.com?subject=PatenteGo%20Support',
      );
    });

    test('chapter lock upgrade copy is configured', () {
      for (final language in ['zh', 'en', 'it']) {
        final title =
            AppStrings.getWithLanguage(language, 'chapter_locked_title');
        final message =
            AppStrings.getWithLanguage(language, 'chapter_locked_message');

        expect(title, isNot('chapter_locked_title'));
        expect(title, isNotEmpty);
        expect(message, isNot('chapter_locked_message'));
        expect(message, isNotEmpty);
      }
    });

    test('subscription copy does not promise a free trial', () {
      const languages = ['zh', 'en', 'it'];
      const checkedKeys = [
        'sub_price_main',
        'sub_price_per_day',
        'sub_price_billing_note',
        'sub_cta_subscribe_button',
        'sub_disclaimer_text',
      ];
      const forbiddenPhrases = [
        'free trial',
        '14 days',
        '14天',
        '免费试用',
        'prova gratuita',
        '14 giorni',
      ];

      for (final language in languages) {
        for (final key in checkedKeys) {
          final value = AppStrings.getWithLanguage(language, key).toLowerCase();
          for (final phrase in forbiddenPhrases) {
            expect(
              value.contains(phrase.toLowerCase()),
              isFalse,
              reason: '$language/$key still contains "$phrase"',
            );
          }
        }
      }
    });

    test('supported UI languages define the complete English key set', () {
      final source = File('lib/config/app_strings.dart').readAsStringSync();
      final keyPattern = RegExp(r"^      '([^']+)':", multiLine: true);
      final englishKeys = keyPattern
          .allMatches(_languageSource(source, 'en'))
          .map((match) => match.group(1)!)
          .toSet();

      for (final language in UserState.supportedLanguages) {
        final languageSource = _languageSource(source, language);
        final languageKeys = keyPattern
            .allMatches(languageSource)
            .map((match) => match.group(1)!)
            .toSet();

        expect(
          languageKeys.difference(englishKeys),
          isEmpty,
          reason: '$language has keys not present in English baseline',
        );
        expect(
          englishKeys.difference(languageKeys),
          isEmpty,
          reason: '$language should define every English baseline key',
        );
      }
    });

    test('non-Chinese language string values do not contain Chinese text', () {
      final source = File('lib/config/app_strings.dart').readAsStringSync();
      final valueLinePattern = RegExp(
        r"^      '[^']+':\s*'.*[\u4e00-\u9fff].*'",
        multiLine: true,
      );

      for (final language in ['it', 'en', 'ru', 'ur', 'pa', 'uk']) {
        expect(
          valueLinePattern
              .allMatches(_languageSource(source, language))
              .map((match) => match.group(0))
              .toList(),
          isEmpty,
          reason: '$language should not contain Chinese UI text',
        );
      }
    });

    test('RTL handling only applies to Urdu UI', () {
      final mainSource = File('lib/main.dart').readAsStringSync();
      final splashSource =
          File('lib/screens/splash_screen.dart').readAsStringSync();
      final languageSelectionSource =
          File('lib/screens/language_selection_screen.dart').readAsStringSync();

      expect(mainSource, contains("currentLang == 'ur'"));
      expect(mainSource, contains('builder: (context, child)'));
      expect(mainSource, contains('Directionality('));
      expect(mainSource, isNot(contains("currentLang == 'pa'")));
      expect(splashSource, contains('UserState.supportedLanguages'));
      expect(languageSelectionSource, contains('AppStrings.getWithLanguage'));
      expect(languageSelectionSource, contains("lang == 'ur'"));
    });

    test('reviewed Chinese page copy is not hardcoded in screens', () {
      final homeSource =
          File('lib/screens/home_screen.dart').readAsStringSync();
      final mockTestSource =
          File('lib/screens/mock_test_screen.dart').readAsStringSync();

      expect(homeSource, isNot(contains("const Text('返回首页')")));
      expect(homeSource, isNot(contains("const Text('去订阅解锁')")));
      expect(mockTestSource, isNot(contains('数据库中没有意大利语题目')));
      expect(mockTestSource, isNot(contains("Text('图片加载失败'")));
    });

    test('user-facing provider exceptions are localized or neutral', () {
      final providerSource =
          File('lib/providers/user_state_provider.dart').readAsStringSync();
      final databaseSource =
          File('lib/services/database_service.dart').readAsStringSync();

      expect(providerSource, isNot(contains("throw Exception('登录")));
      expect(providerSource, isNot(contains("throw Exception('注册")));
      expect(providerSource, isNot(contains("throw Exception('仅 VIP")));
      expect(databaseSource, isNot(contains("throw Exception('无法打开")));
      expect(databaseSource, isNot(contains("TimeoutException('云端同步'")));
    });

    test('IAP fallback errors use localization keys', () {
      final source = File('lib/config/app_strings.dart').readAsStringSync();
      final iapSource =
          File('lib/services/iap_service.dart').readAsStringSync();
      const keys = [
        'iap_unavailable',
        'iap_product_not_found',
        'iap_subscription_not_ready',
        'iap_purchase_start_failed',
        'iap_purchase_failed',
        'iap_purchase_verification_failed',
      ];

      for (final language in ['it', ...UserState.supportedLanguages]) {
        final languageSource = _languageSource(source, language);
        for (final key in keys) {
          expect(
            languageSource,
            contains("'$key':"),
            reason: '$language should define $key',
          );
        }
      }

      expect(iapSource, isNot(contains('Subscription product not found')));
      expect(iapSource, isNot(contains('Subscription is not ready yet')));
      expect(iapSource, isNot(contains('Purchase could not be started')));
      expect(iapSource, isNot(contains('Purchase could not be verified')));
    });
  });
}

String _languageSource(String source, String language) {
  final languageStart = source.indexOf("    '$language': {");
  expect(languageStart, isNonNegative, reason: 'missing $language map');
  final nextLanguageStart = source.indexOf(
    RegExp(r"^    '[a-z]{2}': \{", multiLine: true),
    languageStart + 1,
  );
  return source.substring(
    languageStart,
    nextLanguageStart == -1 ? source.indexOf('  };') : nextLanguageStart,
  );
}
