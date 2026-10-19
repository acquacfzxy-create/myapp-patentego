import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lingua_patente/config/app_locales.dart';
import 'package:lingua_patente/config/app_strings.dart';
import 'package:lingua_patente/config/user_error_copy.dart';
import 'package:lingua_patente/models/user_state.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

void main() {
  String t(String language, String key) =>
      AppStrings.getWithLanguage(language, key);

  group('UserErrorCopy.auth', () {
    for (final language in UserState.supportedLanguages) {
      test('known codes map to localized copy [$language]', () {
        expect(
          UserErrorCopy.auth(
            FirebaseAuthException(code: 'network-request-failed'),
            language: language,
          ),
          t(language, 'auth_error_network_failed'),
        );
        expect(
          UserErrorCopy.auth(
            const SignInWithAppleAuthorizationException(
              code: AuthorizationErrorCode.canceled,
              message: 'The operation couldn’t be completed. (1001)',
            ),
            language: language,
          ),
          t(language, 'auth_error_google_cancelled'),
        );
      });

      test(
          'messages already localized by the provider pass through [$language]',
          () {
        final message = t(language, 'auth_error_user_not_found');
        expect(
          UserErrorCopy.auth(Exception(message), language: language),
          message,
        );
      });

      test('raw SDK errors are replaced by generic copy [$language]', () {
        const raw =
            'PlatformException(sign_in_failed, com.google.android.gms.common.api.ApiException: 10: , null, null)';
        final fromPlatform = UserErrorCopy.auth(
          PlatformException(code: 'sign_in_failed', message: raw),
          language: language,
        );
        expect(fromPlatform, t(language, 'auth_error_sign_in_generic'));

        // Provider format: localized prefix + raw FirebaseAuth message.
        final prefixed = Exception(
          '${t(language, 'auth_error_login_failed_prefix')}'
          'The supplied auth credential is incorrect, malformed or has expired.',
        );
        final copy = UserErrorCopy.auth(prefixed, language: language);
        expect(copy, t(language, 'auth_error_sign_in_generic'));
        expect(copy, isNot(contains('credential')));

        final register = Exception(
          '${t(language, 'auth_error_register_failed_prefix')}[firebase_auth/internal-error]',
        );
        expect(
          UserErrorCopy.auth(register, language: language),
          t(language, 'auth_error_register_generic'),
        );
      });
    }
  });

  group('UserErrorCopy.purchase and sync', () {
    test('localized IAP messages pass through, raw store errors do not', () {
      final known = t('ru', 'iap_purchase_failed');
      expect(UserErrorCopy.purchase(known, language: 'ru'), known);
      expect(
        UserErrorCopy.purchase(Exception(t('uk', 'iap_sign_in_required')),
            language: 'uk'),
        t('uk', 'iap_sign_in_required'),
      );
      const raw =
          'IAPError(code: purchase_error, source: google_play, message: BillingResponse.developerError, details: null)';
      expect(UserErrorCopy.purchase(raw, language: 'pa'),
          t('pa', 'iap_error_generic'));
      expect(UserErrorCopy.purchase(null, language: 'ur'),
          t('ur', 'iap_error_generic'));
    });

    test('sync errors never include the exception text', () {
      final copy = UserErrorCopy.sync(
        FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied'),
        language: 'zh',
      );
      expect(copy, t('zh', 'sync_failed_generic'));
      expect(copy, isNot(contains('permission')));
    });
  });

  group('Pages route errors through the display layer', () {
    const pages = [
      'lib/screens/auth_page.dart',
      'lib/screens/subscription_page.dart',
      'lib/screens/settings_screen.dart',
      'lib/screens/web_app_screen.dart',
    ];
    for (final path in pages) {
      test(path, () {
        final source = File(path).readAsStringSync();
        expect(source, isNot(contains('Text(e.toString())')));
        expect(source, isNot(contains('_showMessage(error.toString())')));
        expect(source, isNot(contains('_error = error.toString()')));
        expect(source, isNot(contains("replaceFirst('Exception: ', '')")));
        expect(source, isNot(contains("sync_failed_prefix')}\$e")));
        expect(source, isNot(contains("sync_failed_prefix')}\$error")));
      });
    }
  });

  group('AppLocales', () {
    test('declares exactly the selectable UI languages', () {
      expect(
        AppLocales.supportedLocales.map((l) => l.languageCode).toList(),
        UserState.supportedLanguages,
      );
      expect(AppLocales.localeFor('ur').languageCode, 'ur');
      expect(AppLocales.localeFor('it').languageCode, 'zh',
          reason: 'Italian is a question language, not a UI language');
    });

    test('MaterialApp in main.dart uses the shared locale config', () {
      final source = File('lib/main.dart').readAsStringSync();
      expect(source, contains('localizationsDelegates: AppLocales.delegates'));
      expect(source, contains('supportedLocales: AppLocales.supportedLocales'));
      expect(source, contains('locale: AppLocales.localeFor(currentLang)'));
    });
  });
}
