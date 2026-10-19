import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:lingua_patente/config/app_strings.dart';
import 'package:lingua_patente/providers/user_state_provider.dart';
import 'package:lingua_patente/screens/subscription_page.dart';
import 'package:lingua_patente/services/iap_service.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../integration_test/support/screenshot_iap.dart';

/// 验证两个截图集成测试使用的 IAP 接线：关闭态与假 IAP 都能驱动真实的
/// SubscriptionPage，且不会触碰真实商店插件。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppStrings.setLanguage('en');
  });

  Future<void> pumpPage(WidgetTester tester, IapService service) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<UserStateProvider>(
            create: (_) => UserStateProvider(),
          ),
          ChangeNotifierProvider<IapService>.value(value: service),
        ],
        child: const MaterialApp(home: SubscriptionPage()),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(seconds: 1));
  }

  testWidgets('disabled IAP renders the degraded state and never touches Play',
      (tester) async {
    final iap = _CountingIap();
    final service = IapService(iap: iap, billingSupported: false);
    addTearDown(service.dispose);

    await pumpPage(tester, service);

    expect(tester.takeException(), isNull);
    expect(find.byType(SubscriptionPage), findsOneWidget);
    expect(find.text('--'), findsWidgets, reason: 'no product price');
    expect(service.isAvailable, isFalse);
    expect(service.errorMessage, isNotNull);
    expect(iap.touches, 0);
    expect(find.text('Free unlimited explanations'), findsOneWidget);
    expect(
        find.text(
            'Decision logic, key points, and study tips are free for everyone'),
        findsOneWidget);
  });

  testWidgets('fake screenshot IAP shows the price without real Billing',
      (tester) async {
    final service = IapService(iap: ScreenshotIap(), billingSupported: true);
    addTearDown(service.dispose);

    await pumpPage(tester, service);

    expect(tester.takeException(), isNull);
    expect(find.text(kScreenshotMonthlyPrice), findsWidgets);
    expect(service.monthlyProduct, isNotNull);
  });

  testWidgets('leaving the page does not dispose the app-level service',
      (tester) async {
    final iap = _CountingIap();
    final service = IapService(iap: iap, billingSupported: false);
    addTearDown(service.dispose);

    await pumpPage(tester, service);
    await tester.pumpWidget(const SizedBox.shrink()); // 页面被销毁
    await tester.pump();

    expect(tester.takeException(), isNull);
    // 服务仍可用（若页面 dispose 了它，这里会因 use-after-dispose 抛断言）。
    await service.loadProducts();
    service.addListener(() {});
    expect(tester.takeException(), isNull);
  });
}

class _CountingIap implements InAppPurchase {
  int touches = 0;

  @override
  Stream<List<PurchaseDetails>> get purchaseStream {
    touches++;
    return const Stream<List<PurchaseDetails>>.empty();
  }

  @override
  Future<bool> isAvailable() async {
    touches++;
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    touches++;
    return super.noSuchMethod(invocation);
  }
}
