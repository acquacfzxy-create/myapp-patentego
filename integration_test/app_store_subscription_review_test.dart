// App Store Connect 订阅「审核用截图」草稿：未订阅状态的订阅页（含购买按钮）。
// 价格只用于画面展示，用 --dart-define=SUB_PRICE='€x.xx' 传入定价后的真实价格；
// 默认 €X.XX 明显是占位，不可当作正式价格上传。
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lingua_patente/config/app_strings.dart';
import 'package:lingua_patente/providers/user_state_provider.dart';
import 'package:lingua_patente/screens/subscription_page.dart';
import 'package:lingua_patente/services/database_service.dart';
import 'package:lingua_patente/services/iap_service.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/screenshot_iap.dart';

const _price = String.fromEnvironment('SUB_PRICE', defaultValue: '€X.XX');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('captures the subscription paywall for App Review',
      (tester) async {
    await DatabaseService.init();
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();

    final key = GlobalKey();
    final provider = UserStateProvider();
    await tester.pump(const Duration(milliseconds: 300));
    await provider.changeLanguage('en');
    await provider.updateUserState(isVip: false, currentLanguage: 'en');
    AppStrings.setLanguage('en');

    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: MultiProvider(
          providers: [
            ChangeNotifierProvider<UserStateProvider>.value(value: provider),
            ChangeNotifierProvider<IapService>(
              create: (_) => IapService(
                  iap: ScreenshotIap(price: _price), billingSupported: true),
            ),
          ],
          child: const MaterialApp(
            debugShowCheckedModeBanner: false,
            home: SubscriptionPage(),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(seconds: 2));

    final boundary =
        key.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 3);
    final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!
        .buffer
        .asUint8List();
    final dir = Directory(
        '${(await getApplicationDocumentsDirectory()).path}/subscription_review')
      ..createSync(recursive: true);
    await File('${dir.path}/01_subscription_paywall.png')
        .writeAsBytes(bytes, flush: true);
    debugPrint('SUBSCRIPTION_REVIEW_READY=${dir.path}');
    if (const bool.fromEnvironment('KEEP_SCREENSHOT_CONTAINER')) {
      await Future<void>.delayed(const Duration(seconds: 60));
    }
  });
}
