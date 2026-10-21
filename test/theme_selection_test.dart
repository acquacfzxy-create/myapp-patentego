import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lingua_patente/config/app_strings.dart';
import 'package:lingua_patente/config/app_theme.dart';
import 'package:lingua_patente/providers/user_state_provider.dart';
import 'package:lingua_patente/screens/theme_selection_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 首次啟動的主題選擇頁：點選即時套用並保存，大字號與 RTL 下不溢出。
void main() {
  Future<UserStateProvider> pump(
    WidgetTester tester, {
    String language = 'zh',
    double scale = 1.0,
    Size size = const Size(390, 844),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({'current_language': language});
    final user = UserStateProvider();
    await user.changeLanguage(language);
    AppStrings.setLanguage(language);
    await tester.pumpWidget(
      ChangeNotifierProvider<UserStateProvider>.value(
        value: user,
        child: Consumer<UserStateProvider>(
          builder: (context, u, _) => MaterialApp(
            theme: switch (u.themeMode) {
              AppThemeMode.retro => AppTheme.retroTheme(language: language),
              AppThemeMode.night => AppTheme.darkTheme(language: language),
              AppThemeMode.classic => AppTheme.lightTheme(language: language),
            },
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: const ThemeSelectionScreen(),
          ),
        ),
      ),
    );
    await tester.pump();
    return user;
  }

  testWidgets('shows the three renamed themes and applies a tap at once',
      (tester) async {
    final user = await pump(tester);
    expect(find.text('晴天公路'), findsOneWidget);
    expect(find.text('夜间公路'), findsOneWidget);
    expect(find.text('像素掌机'), findsOneWidget);

    await tester.tap(find.byKey(const Key('theme_option_retro')));
    await tester.pumpAndSettle();
    expect(user.themeMode, AppThemeMode.retro);
    expect(AppTheme.isRetroFor(tester.element(find.text('像素掌机'))), isTrue);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('theme_mode'), 'retro');
  });

  testWidgets('large text in Urdu does not overflow', (tester) async {
    await pump(tester,
        language: 'ur', scale: 2.0, size: const Size(320, 640));
    expect(tester.takeException(), isNull);
  });
}
