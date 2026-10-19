// 设置页的 VIP 订阅 / 管理订阅入口：只导航到既有 SubscriptionPage，不含任何订阅逻辑。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lingua_patente/config/app_strings.dart';
import 'package:lingua_patente/providers/user_state_provider.dart';
import 'package:lingua_patente/screens/settings_screen.dart';
import 'package:lingua_patente/screens/subscription_page.dart';
import 'package:lingua_patente/services/iap_service.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _VipUserState extends UserStateProvider {
  @override
  bool get isVip => true;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    PackageInfo.setMockInitialValues(
      appName: 'LinguaPatente',
      packageName: 'com.patentego.app',
      version: '1.0.8',
      buildNumber: '10',
      buildSignature: '',
    );
    AppStrings.setLanguage('en');
  });

  Future<void> pumpSettings(WidgetTester tester, {required bool vip}) async {
    tester.view.physicalSize = const Size(1080, 6000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final service = IapService(billingSupported: false);
    addTearDown(service.dispose);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<UserStateProvider>(
            create: (_) => vip ? _VipUserState() : UserStateProvider(),
          ),
          ChangeNotifierProvider<IapService>.value(value: service),
        ],
        child: const MaterialApp(home: SettingsScreen()),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(seconds: 1));
  }

  testWidgets('free user sees the VIP card and it opens the subscription page',
      (tester) async {
    await pumpSettings(tester, vip: false);

    expect(find.text(AppStrings.get('sub_title')), findsOneWidget);
    expect(find.text(AppStrings.get('go_subscribe_unlock')), findsOneWidget);
    expect(find.byType(SubscriptionPage), findsNothing);

    await tester.tap(find.text(AppStrings.get('sub_title')));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(SubscriptionPage), findsOneWidget);
  });

  testWidgets('VIP user sees a manage wording and the same destination',
      (tester) async {
    await pumpSettings(tester, vip: true);

    expect(find.text(AppStrings.get('sub_title')), findsOneWidget);
    expect(find.text(AppStrings.get('manage_subscription')), findsOneWidget);
    expect(find.text(AppStrings.get('go_subscribe_unlock')), findsNothing);

    await tester.tap(find.text(AppStrings.get('sub_title')));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(SubscriptionPage), findsOneWidget);
  });

  test('every supported language has the strings the entry uses', () {
    for (final entry in AppStrings.allTables.entries) {
      for (final key in [
        'sub_title',
        'manage_subscription',
        'go_subscribe_unlock'
      ]) {
        expect(entry.value[key]?.trim(), isNotEmpty,
            reason: '${entry.key}:$key');
      }
    }
    expect(AppStrings.allTables.keys.toSet(),
        {'it', 'zh', 'en', 'ru', 'ur', 'pa', 'uk'});
  });
}
