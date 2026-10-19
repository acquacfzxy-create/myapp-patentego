import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lingua_patente/config/app_strings.dart';

/// iOS 版不得出现 Google Play 字样（App Review 2.3.10：不得提及其他平台）。
/// 设置页「管理订阅」副标题在非 Play 结算时必须使用 App Store 文案。
void main() {
  test('store subtitle names the App Store, never Google Play', () {
    for (final lang in ['it', 'zh', 'en', 'ru', 'ur', 'pa', 'uk']) {
      final value = AppStrings.getWithLanguage(
          lang, 'manage_subscription_subtitle_store');
      expect(value, isNot('manage_subscription_subtitle_store'),
          reason: '$lang is missing the key');
      expect(value, contains('App Store'), reason: lang);
      expect(value, isNot(contains('Google Play')), reason: lang);
    }
  });

  test('settings picks the Play subtitle only for Google Play billing', () {
    final source = File('lib/screens/settings_screen.dart').readAsStringSync();
    final flat = source.replaceAll(RegExp(r'\s+'), ' ');
    expect(
        flat,
        contains(
            "iapService!.usesGooglePlayBilling ? 'manage_subscription_subtitle' : 'manage_subscription_subtitle_store'"));
  });

  test('iOS purchase-flow messages never mention Google Play', () {
    for (final lang in ['it', 'zh', 'en', 'ru', 'ur', 'pa', 'uk']) {
      for (final key in [
        'iap_product_unavailable_for_account_store',
        'iap_purchase_verification_pending_store',
      ]) {
        final value = AppStrings.getWithLanguage(lang, key);
        expect(value, isNot(key), reason: '$lang.$key missing');
        expect(value, contains('App Store'), reason: '$lang.$key');
        expect(value, isNot(contains('Google Play')), reason: '$lang.$key');
      }
    }
  });

  test('IapService and SubscriptionPage pick copy by billing platform', () {
    String flat(String path) =>
        File(path).readAsStringSync().replaceAll(RegExp(r'\s+'), ' ');
    final service = flat('lib/services/iap_service.dart');
    expect(
        service,
        contains(
            "usesGooglePlayBilling ? 'iap_purchase_verification_pending' : 'iap_purchase_verification_pending_store'"));
    expect(
        service,
        contains(
            "usesGooglePlayBilling ? 'iap_product_unavailable_for_account' : 'iap_product_unavailable_for_account_store'"));
    final page = flat('lib/screens/subscription_page.dart');
    expect(
        RegExp(r"usesGooglePlayBilling \? 'iap_product_unavailable_for_account' : 'iap_product_unavailable_for_account_store'")
            .allMatches(page)
            .length,
        2);
  });
}
