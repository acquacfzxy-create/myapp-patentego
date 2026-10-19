// 1.0.6 补丁：Play 订阅管理 / 取消入口、按平台的续订说明、商品不可用时的诚实提示。
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:lingua_patente/config/app_config.dart';
import 'package:lingua_patente/config/app_strings.dart';
import 'package:lingua_patente/providers/user_state_provider.dart';
import 'package:lingua_patente/screens/settings_screen.dart';
import 'package:lingua_patente/screens/subscription_page.dart';
import 'package:lingua_patente/services/iap_service.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _urlChannel = MethodChannel('plugins.flutter.io/url_launcher');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<String> launched;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    PackageInfo.setMockInitialValues(
      appName: 'LinguaPatente',
      packageName: 'com.patentego.app',
      version: '1.0.6',
      buildNumber: '8',
      buildSignature: '',
    );
    AppStrings.setLanguage('en');
    launched = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_urlChannel, (call) async {
      if (call.method == 'launch') {
        launched.add((call.arguments as Map)['url'] as String);
        return true;
      }
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_urlChannel, null);
  });

  test('subscription center URL targets this app and product', () {
    final uri = Uri.parse(AppConfig.playSubscriptionCenterUrl);
    expect(uri.host, 'play.google.com');
    expect(uri.path, '/store/account/subscriptions');
    expect(uri.queryParameters['sku'], 'patentego_vip_monthly');
    expect(uri.queryParameters['package'], 'com.patentego.app');
  });

  Future<void> pumpSubscription(
    WidgetTester tester,
    IapService service, {
    bool vip = false,
  }) async {
    tester.view.physicalSize = const Size(1080, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<UserStateProvider>(
            create: (_) => vip ? _VipUserState() : UserStateProvider(),
          ),
          ChangeNotifierProvider<IapService>.value(value: service),
        ],
        child: const MaterialApp(home: SubscriptionPage()),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(seconds: 1));
  }

  group('SubscriptionPage on Google Play', () {
    testWidgets('footer link opens the Play subscription center',
        (tester) async {
      final service =
          IapService(iap: _FakePlay.withProduct(), billingSupported: true);
      addTearDown(service.dispose);
      await pumpSubscription(tester, service);

      final link = find.widgetWithText(
          TextButton, AppStrings.get('manage_subscription'));
      expect(link, findsOneWidget);
      await tester.tap(link);
      await tester.pump();
      expect(launched, [AppConfig.playSubscriptionCenterUrl]);
    });

    testWidgets('active member sees a manage / cancel button', (tester) async {
      final service =
          IapService(iap: _FakePlay.withProduct(), billingSupported: true);
      addTearDown(service.dispose);
      await pumpSubscription(tester, service, vip: true);

      final button = find.text(AppStrings.get('manage_subscription_play'));
      expect(button, findsOneWidget);
      await tester.tap(button);
      await tester.pump();
      expect(launched, [AppConfig.playSubscriptionCenterUrl]);
    });

    testWidgets('renewal disclosure follows Google Play, not App Store',
        (tester) async {
      final service =
          IapService(iap: _FakePlay.withProduct(), billingSupported: true);
      addTearDown(service.dispose);
      await pumpSubscription(tester, service);

      expect(find.text(AppStrings.get('sub_disclaimer_text_play')),
          findsOneWidget);
      expect(find.text(AppStrings.get('sub_disclaimer_text')), findsNothing);
      expect(find.textContaining('24 hours'), findsNothing);
    });

    testWidgets('product missing from a clean query shows the honest message',
        (tester) async {
      final service =
          IapService(iap: _FakePlay.notFound(), billingSupported: true);
      addTearDown(service.dispose);
      await pumpSubscription(tester, service);

      expect(service.productNotFound, isTrue);
      final message = AppStrings.get('iap_product_unavailable_for_account');
      expect(find.text(message), findsOneWidget);
      expect(message, isNot(contains('try again')));
      expect(find.text(AppStrings.get('iap_subscription_not_ready')),
          findsNothing);
    });

    testWidgets('a failed query is not reported as unavailable for the account',
        (tester) async {
      final service =
          IapService(iap: _FakePlay.queryError(), billingSupported: true);
      addTearDown(service.dispose);
      await pumpSubscription(tester, service);

      expect(service.productNotFound, isFalse);
      expect(find.text(AppStrings.get('iap_subscription_not_ready')),
          findsOneWidget);
      expect(find.text(AppStrings.get('iap_product_unavailable_for_account')),
          findsNothing);
    });

    testWidgets('a later successful query clears the not-found state',
        (tester) async {
      final play = _FakePlay.notFound();
      final service = IapService(iap: play, billingSupported: true);
      addTearDown(service.dispose);
      await pumpSubscription(tester, service);
      expect(service.productNotFound, isTrue);

      play.products = [_product()];
      await service.loadProducts();
      expect(service.productNotFound, isFalse);
      expect(service.monthlyProduct, isNotNull);
    });
  });

  testWidgets('without Play Billing: no Play entry, store-neutral disclosure',
      (tester) async {
    final service =
        IapService(iap: _FakePlay.withProduct(), billingSupported: false);
    addTearDown(service.dispose);
    await pumpSubscription(tester, service);

    expect(find.text(AppStrings.get('manage_subscription')), findsNothing);
    expect(find.text(AppStrings.get('sub_disclaimer_text')), findsOneWidget);
  });

  group('SettingsScreen', () {
    Future<void> pumpSettings(WidgetTester tester, IapService? service) async {
      tester.view.physicalSize = const Size(1080, 6000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final page = MaterialApp(home: const SettingsScreen());
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<UserStateProvider>(
              create: (_) => UserStateProvider(),
            ),
            if (service != null)
              ChangeNotifierProvider<IapService>.value(value: service),
          ],
          child: page,
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(seconds: 1));
    }

    testWidgets('shows a persistent Play manage entry that opens Play',
        (tester) async {
      final service =
          IapService(iap: _FakePlay.withProduct(), billingSupported: true);
      addTearDown(service.dispose);
      await pumpSettings(tester, service);

      final entry = find.text(AppStrings.get('manage_subscription'));
      expect(entry, findsOneWidget);
      expect(find.text(AppStrings.get('manage_subscription_subtitle')),
          findsOneWidget);
      await tester.tap(entry);
      await tester.pump();
      expect(launched, [AppConfig.playSubscriptionCenterUrl]);
    });

    testWidgets('hidden when Play Billing is off or no service is provided',
        (tester) async {
      final service =
          IapService(iap: _FakePlay.withProduct(), billingSupported: false);
      addTearDown(service.dispose);
      await pumpSettings(tester, service);
      expect(find.text(AppStrings.get('manage_subscription')), findsNothing);

      await pumpSettings(tester, null);
      expect(tester.takeException(), isNull);
      expect(find.text(AppStrings.get('manage_subscription')), findsNothing);
    });
  });

  group('SubscriptionPage on iOS (App Store)', () {
    testWidgets('product missing names the App Store account, not Google Play',
        (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      try {
        final service =
            IapService(iap: _FakePlay.notFound(), billingSupported: true);
        addTearDown(service.dispose);
        await pumpSubscription(tester, service);

        expect(service.usesGooglePlayBilling, isFalse);
        expect(service.productNotFound, isTrue);
        final message =
            AppStrings.get('iap_product_unavailable_for_account_store');
        expect(find.text(message), findsOneWidget);
        expect(message, contains('App Store'));
        expect(message, isNot(contains('Google Play')));
        expect(find.text(AppStrings.get('iap_product_unavailable_for_account')),
            findsNothing);
        expect(service.errorMessage, message);
        // 页面树里不得出现任何 Google Play 字样。
        expect(find.textContaining('Google Play'), findsNothing);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  });

  test('every language defines the new keys', () {
    const keys = [
      'sub_disclaimer_text_play',
      'manage_subscription',
      'manage_subscription_subtitle',
      'manage_subscription_play',
      'iap_product_unavailable_for_account',
      'iap_purchase_verification_pending',
      'iap_purchase_verification_rejected',
      'iap_product_unavailable_for_account_store',
      'iap_purchase_verification_pending_store',
    ];
    for (final lang in ['it', 'zh', 'en', 'ru', 'ur', 'pa', 'uk']) {
      for (final key in keys) {
        final value = AppStrings.getWithLanguage(lang, key);
        expect(value, isNot(key), reason: '$lang.$key');
        if (lang != 'en') {
          expect(value, isNot(AppStrings.getWithLanguage('en', key)),
              reason: '$lang.$key falls back to English');
        }
      }
      final play = AppStrings.getWithLanguage(lang, 'sub_disclaimer_text_play');
      expect(play, isNot(contains('24')), reason: lang);
      expect(play, contains('Google Play'), reason: lang);
    }
  });
}

class _VipUserState extends UserStateProvider {
  @override
  bool get isVip => true;
}

ProductDetails _product() => ProductDetails(
      id: AppConfig.monthlySubscriptionProductId,
      title: 'VIP',
      description: 'VIP monthly',
      price: '€6.99',
      rawPrice: 6.99,
      currencyCode: 'EUR',
    );

class _FakePlay implements InAppPurchase {
  _FakePlay.withProduct() : products = [_product()];
  _FakePlay.notFound() : products = [];
  _FakePlay.queryError()
      : products = [],
        error = IAPError(
            source: 'google_play',
            code: 'BillingResponse.serviceUnavailable',
            message: 'Service unavailable');

  List<ProductDetails> products;
  IAPError? error;
  final StreamController<List<PurchaseDetails>> _stream =
      StreamController<List<PurchaseDetails>>.broadcast();

  @override
  Stream<List<PurchaseDetails>> get purchaseStream => _stream.stream;

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<ProductDetailsResponse> queryProductDetails(
      Set<String> identifiers) async {
    return ProductDetailsResponse(
      productDetails: products,
      notFoundIDs: [
        for (final id in identifiers)
          if (!products.any((p) => p.id == id)) id
      ],
      error: error,
    );
  }

  @override
  Future<void> restorePurchases({String? applicationUserName}) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
