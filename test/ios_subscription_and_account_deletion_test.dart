// iOS 订阅（App Store）与 App 内删除账号：本地可验证的部分。
// 服务端逻辑见 functions/test/apple_subscription.test.js；沙盒 / 真机验证需人工执行。
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:lingua_patente/config/app_config.dart';
import 'package:lingua_patente/config/app_strings.dart';
import 'package:lingua_patente/services/account_deletion_service.dart';
import 'package:lingua_patente/services/apple_account_token.dart';
import 'package:lingua_patente/services/database_service.dart';
import 'package:lingua_patente/services/iap_service.dart';
import 'package:lingua_patente/services/purchase_verification_service.dart';

void main() {
  group('appleAccountToken', () {
    test('matches the backend algorithm (pinned value from functions test)',
        () {
      // 与 functions/test/apple_subscription.test.js 中 'test-uid-1' 的固定值一致。
      expect(appleAccountToken('test-uid-1'),
          '72f0676e-e7de-5a6e-a6bb-3ed5239a7f44');
    });

    test('is a stable, uid-specific UUID', () {
      final a = appleAccountToken('uid-a');
      expect(
          RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-5[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')
              .hasMatch(a),
          isTrue);
      expect(appleAccountToken('uid-a'), a);
      expect(appleAccountToken('uid-b'), isNot(a));
    });
  });

  group('IapService on iOS', () {
    tearDown(() => debugDefaultTargetPlatformOverride = null);

    test('uses App Store billing and the App Store subscription page', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final service = IapService(billingSupported: true);
      addTearDown(service.dispose);
      expect(service.usesStoreBilling, isTrue);
      expect(service.usesAppStoreBilling, isTrue);
      expect(service.usesGooglePlayBilling, isFalse);
      expect(service.subscriptionCenterUrl,
          AppConfig.appStoreSubscriptionCenterUrl);
    });

    test('Android keeps Google Play billing and the Play subscription page',
        () {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final service = IapService(billingSupported: true);
      addTearDown(service.dispose);
      expect(service.usesGooglePlayBilling, isTrue);
      expect(service.usesAppStoreBilling, isFalse);
      expect(
          service.subscriptionCenterUrl, AppConfig.playSubscriptionCenterUrl);
    });

    test('billing stays off without its build flag', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final service = IapService();
      addTearDown(service.dispose);
      expect(service.usesStoreBilling, AppConfig.appStoreBillingEnabled);
      expect(AppConfig.appStoreBillingEnabled, isFalse,
          reason:
              'must stay off until the backend is deployed and sandbox-tested');
    });
  });

  group('PurchaseVerificationService for App Store purchases', () {
    PurchaseDetails purchase(String source, String data) => PurchaseDetails(
          productID: AppConfig.monthlySubscriptionProductId,
          status: PurchaseStatus.purchased,
          transactionDate: '1710000000000',
          verificationData: PurchaseVerificationData(
            localVerificationData: '',
            serverVerificationData: data,
            source: source,
          ),
        );

    test('an app_store purchase is sent for server verification with its JWS',
        () async {
      String? sent;
      final verifier = PurchaseVerificationService(
        checkOnServer: (productId, token) async {
          sent = token;
          return const PurchaseVerificationResult.verified();
        },
      );
      final result =
          await verifier.verify(purchase('app_store', 'jws.token.sig'));
      expect(result.isVerified, isTrue);
      expect(sent, 'jws.token.sig');
    });

    test('unknown purchase sources are rejected', () async {
      const verifier = PurchaseVerificationService();
      final result = await verifier.verify(purchase('other_store', 'x'));
      expect(result.outcome, VerificationOutcome.rejected);
    });

    test('source: iOS uses its own endpoint and sends signedTransaction', () {
      final source = File('lib/services/purchase_verification_service.dart')
          .readAsStringSync();
      expect(source, contains('AppConfig.appStoreVerificationUrl'));
      expect(source, contains("'signedTransaction': token"));
      expect(source, contains("'purchaseToken': token"));
    });
  });

  group('AccountDeletionService.interpretResponse', () {
    test('200 with deleted:true is success', () {
      expect(
          AccountDeletionService.interpretResponse(
              200, '{"result":{"deleted":true}}'),
          AccountDeletionOutcome.deleted);
    });

    test('200 without deleted:true is not trusted', () {
      expect(AccountDeletionService.interpretResponse(200, '{"result":{}}'),
          AccountDeletionOutcome.failed);
      expect(AccountDeletionService.interpretResponse(200, 'not json'),
          AccountDeletionOutcome.failed);
    });

    test('recent-login-required is reported separately', () {
      expect(
        AccountDeletionService.interpretResponse(400,
            '{"error":{"message":"recent-login-required","status":"FAILED_PRECONDITION"}}'),
        AccountDeletionOutcome.recentLoginRequired,
      );
    });

    test('other errors fail without claiming deletion', () {
      for (final code in [400, 401, 500, 503]) {
        expect(AccountDeletionService.interpretResponse(code, '{}'),
            AccountDeletionOutcome.failed);
      }
    });
  });

  group('cloud data cleanup on sign-out', () {
    test('covers every user subcollection the rules let the owner delete', () {
      expect(DatabaseService.cloudUserDataSubcollections,
          ['progress', 'daily_usage', 'exam_history', 'exam_sessions']);
      final rules = File('firestore.rules').readAsStringSync();
      for (final name in DatabaseService.cloudUserDataSubcollections) {
        final start = rules.indexOf('match /$name/');
        expect(start, greaterThan(-1), reason: name);
        final next = rules.indexOf('match /', start + 10);
        final block = rules.substring(start, next == -1 ? rules.length : next);
        expect(block, contains('allow delete: if isOwner(uid)'), reason: name);
      }
    });
  });

  group('delete-account UI', () {
    const keys = [
      'delete_account',
      'delete_account_subtitle',
      'delete_account_confirm_title',
      'delete_account_confirm_message',
      'delete_account_confirm_action',
      'delete_account_progress',
      'delete_account_success',
      'delete_account_failed',
      'delete_account_cancelled',
      'delete_account_recent_login',
    ];

    test('every language has every key', () {
      for (final entry in AppStrings.allTables.entries) {
        for (final key in keys) {
          expect(entry.value[key], isNotNull, reason: '${entry.key}:$key');
          expect(entry.value[key]!.trim(), isNotEmpty,
              reason: '${entry.key}:$key');
        }
      }
    });

    test('Simplified Chinese copy contains no Traditional-only characters', () {
      const traditional = '刪帳號設訂購銷經據歷錄們這來開關應該與務選擇權錯誤';
      for (final key in keys) {
        final text = AppStrings.allTables['zh']![key]!;
        for (final char in traditional.split('')) {
          expect(text.contains(char), isFalse, reason: '$key contains $char');
        }
      }
    });

    test('source: entry is in settings, signed-in only, calls the service', () {
      final settings =
          File('lib/screens/settings_screen.dart').readAsStringSync();
      expect(settings, contains("AppStrings.get('delete_account')"));
      expect(settings,
          contains('AccountDeletionService().deleteCurrentAccount()'));
      final isLoggedInBlock = settings.indexOf('if (isLoggedIn) ...[');
      expect(settings.indexOf('_handleDeleteAccount(context)'),
          greaterThan(isLoggedInBlock));
    });
  });
}
