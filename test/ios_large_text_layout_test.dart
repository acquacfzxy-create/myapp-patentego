import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lingua_patente/config/app_locales.dart';
import 'package:lingua_patente/config/app_strings.dart';
import 'package:lingua_patente/config/app_theme.dart';
import 'package:lingua_patente/models/user_state.dart';
import 'package:lingua_patente/providers/user_state_provider.dart';
import 'package:lingua_patente/screens/home_screen.dart';
import 'package:lingua_patente/screens/language_selection_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// iOS 辅助功能最大字级（accessibility-extra-extra-extra-large，正文 53pt / 17pt ≈ 3.12 倍）
/// 下，首页与语言选择页在 iPhone 16e（390×844）与 17 Pro Max（440×956）上
/// 不得出现 RenderFlex overflow 或被压扁的文字。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const sizes = {
    'iPhone 16e 390x844': Size(390, 844),
    'iPhone 17 Pro Max 440x956': Size(440, 956),
  };
  const scales = [1.0, 3.12];

  setUpAll(_loadAppFonts);

  Future<void> pump(
    WidgetTester tester, {
    required Size size,
    required double scale,
    required String language,
    required Widget home,
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
        child: MaterialApp(
          locale: AppLocales.localeFor(language),
          supportedLocales: AppLocales.supportedLocales,
          localizationsDelegates: AppLocales.delegates,
          theme: AppTheme.lightTheme(language: language),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: home,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(seconds: 2));
  }

  Future<void> expectNoOverflow(WidgetTester tester, String where) async {
    expect(tester.takeException(), isNull, reason: '$where: first viewport');
    for (final element in find.byType(Scrollable).evaluate().toList()) {
      final position =
          ((element as StatefulElement).state as ScrollableState).position;
      if (position.hasContentDimensions && position.maxScrollExtent > 0) {
        position.jumpTo(position.maxScrollExtent);
      }
    }
    await tester.pump();
    expect(tester.takeException(), isNull, reason: '$where: scrolled to end');
  }

  /// 不得有被 maxLines 省略的文字（用户看到的「…」截断）。
  void expectNoEllipsis(WidgetTester tester, String where) {
    final cut = <String>[];
    for (final element in find.byType(RichText).evaluate()) {
      final paragraph = element.renderObject as RenderParagraph;
      if (paragraph.hasSize && paragraph.didExceedMaxLines) {
        cut.add(paragraph.text.toPlainText());
      }
    }
    expect(cut, isEmpty, reason: '$where: text truncated by maxLines');
  }

  for (final size in sizes.entries) {
    for (final scale in scales) {
      for (final language in ['en', 'zh', 'ru', 'uk', 'pa', 'ur']) {
        testWidgets('HomeScreen ${size.key} x$scale [$language]',
            (tester) async {
          await pump(tester,
              size: size.value,
              scale: scale,
              language: language,
              home: const HomeScreen());
          await expectNoOverflow(tester, 'HomeScreen');
          expectNoEllipsis(tester, 'HomeScreen');
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump(const Duration(seconds: 2));
        });
      }
      testWidgets('LanguageSelectionScreen ${size.key} x$scale',
          (tester) async {
        await pump(tester,
            size: size.value,
            scale: scale,
            language: 'zh',
            home: const LanguageSelectionScreen());
        await expectNoOverflow(tester, 'LanguageSelectionScreen');
        for (final name in UserState.languageNames.values) {
          expect(find.text(name), findsOneWidget);
        }
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 2));
      });
    }
  }
}

Future<void> _loadAppFonts() async {
  const families = {
    'NotoSans': [
      'NotoSans-Regular.ttf',
      'NotoSans-Medium.ttf',
      'NotoSans-SemiBold.ttf',
      'NotoSans-Bold.ttf',
    ],
    'NotoSansSC': [
      'NotoSansCJKsc-Regular.otf',
      'NotoSansCJKsc-Medium.otf',
      'NotoSansCJKsc-Bold.otf',
    ],
    'NotoNastaliqUrdu': [
      'NotoNastaliqUrdu-Regular.ttf',
      'NotoNastaliqUrdu-Bold.ttf',
    ],
    'NotoSansGurmukhi': [
      'NotoSansGurmukhi-Regular.ttf',
      'NotoSansGurmukhi-Medium.ttf',
      'NotoSansGurmukhi-SemiBold.ttf',
      'NotoSansGurmukhi-Bold.ttf',
    ],
  };
  for (final entry in families.entries) {
    final loader = FontLoader(entry.key);
    for (final file in entry.value) {
      final bytes = File('assets/fonts/noto/$file').readAsBytesSync();
      loader.addFont(Future.value(ByteData.sublistView(bytes)));
    }
    await loader.load();
  }
  // Material 图标，便于按图标查找按钮。
  final iconFont = File(
    '${Platform.environment['FLUTTER_ROOT'] ?? '/opt/homebrew/share/flutter'}'
    '/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
  );
  if (iconFont.existsSync()) {
    final loader = FontLoader('MaterialIcons')
      ..addFont(Future.value(ByteData.sublistView(iconFont.readAsBytesSync())));
    await loader.load();
  }
  // 保证服务层使用的平台通道在测试中安静失败即可。
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('flutter_tts'),
    (call) async => null,
  );
}
