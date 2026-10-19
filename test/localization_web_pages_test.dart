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
import 'package:lingua_patente/screens/web_app_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 网页端（WebAppScreen）在 320px、1.0/1.5 倍字号、六种界面语言下的布局检查。
/// 只覆盖不需要登录与网络的页面：首页、章节列表、设置。题库来自打包的
/// assets/web/questions，Firebase 在测试中不可用，页面按离线模式运行。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    // rootBundle 会缓存 loadString 的结果，且大文件在 isolate 中解码：先在真实异步中
    // 读取一次清单，避免之后的用例在 FakeAsync 中等待一个永远不会完成的解码。
    await rootBundle.loadString('assets/web/questions/manifest.json');
    for (final entry in const {
      'NotoSans': [
        'NotoSans-Regular.ttf',
        'NotoSans-SemiBold.ttf',
        'NotoSans-Bold.ttf'
      ],
      'NotoSansSC': ['NotoSansCJKsc-Regular.otf', 'NotoSansCJKsc-Bold.otf'],
      'NotoNastaliqUrdu': [
        'NotoNastaliqUrdu-Regular.ttf',
        'NotoNastaliqUrdu-Bold.ttf'
      ],
      'NotoSansGurmukhi': [
        'NotoSansGurmukhi-Regular.ttf',
        'NotoSansGurmukhi-Bold.ttf'
      ],
    }.entries) {
      final loader = FontLoader(entry.key);
      for (final file in entry.value) {
        final bytes = File('assets/fonts/noto/$file').readAsBytesSync();
        loader.addFont(Future.value(ByteData.sublistView(bytes)));
      }
      await loader.load();
    }
  });

  Future<void> pumpWeb(
      WidgetTester tester, String language, double scale) async {
    tester.view.physicalSize = const Size(320, 640);
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
          theme: AppTheme.webTheme(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: const WebAppScreen(),
        ),
      ),
    );
    // 题库清单通过真实的 asset 读取与解码，需在真实异步中完成。
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump(const Duration(milliseconds: 100));
      if (find
          .text(AppStrings.getWithLanguage(language, 'web_hub_subtitle'))
          .evaluate()
          .isNotEmpty) {
        break;
      }
    }
  }

  Future<void> expectNoOverflowWhileScrolling(
      WidgetTester tester, String where) async {
    expect(tester.takeException(), isNull, reason: '$where first viewport');
    expect(_clippedText(), isEmpty, reason: '$where first viewport');
    for (final element in find.byType(Scrollable).evaluate().toList()) {
      final position =
          ((element as StatefulElement).state as ScrollableState).position;
      if (position.hasContentDimensions && position.maxScrollExtent > 0) {
        position.jumpTo(position.maxScrollExtent);
      }
    }
    await tester.pump();
    expect(tester.takeException(), isNull, reason: '$where scrolled');
    expect(_clippedText(), isEmpty, reason: '$where scrolled');
  }

  for (final language in UserState.supportedLanguages) {
    for (final scale in const [1.0, 1.5]) {
      testWidgets(
          'web hub, chapters and settings fit 320px [$language, x$scale]',
          (tester) async {
        await pumpWeb(tester, language, scale);
        String t(String key) => AppStrings.getWithLanguage(language, key);

        expect(find.text(t('web_hub_subtitle')), findsOneWidget);
        expect(
          Directionality.of(tester.element(find.byType(WebAppScreen))),
          language == 'ur' ? TextDirection.rtl : TextDirection.ltr,
        );
        await expectNoOverflowWhileScrolling(tester, 'hub');

        // 章节列表（只读清单元数据，不需要登录）。
        final chapters = find.text(t('chapter_practice'));
        await tester.ensureVisible(chapters.first);
        await tester.tap(chapters.first);
        for (var i = 0; i < 10; i++) {
          await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 30)));
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(
            find.text(t('web_chapter_progress')).evaluate().isNotEmpty ||
                find.textContaining('1').evaluate().isNotEmpty,
            isTrue);
        await expectNoOverflowWhileScrolling(tester, 'chapters');

        // 设置页。
        await tester.tap(find.byTooltip(t('settings')).first);
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.text(t('web_skip_mastered_description')), findsWidgets);
        await expectNoOverflowWhileScrolling(tester, 'settings');

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 1));
      });
    }
  }
}

/// 没有行数上限、也不省略的文字，不能被父级压扁裁切。
List<String> _clippedText() {
  final clipped = <String>[];
  for (final element in find.byType(RichText).evaluate()) {
    final paragraph = element.renderObject as RenderParagraph;
    if (!paragraph.hasSize || paragraph.maxLines != null) continue;
    if (paragraph.overflow != TextOverflow.clip) continue;
    final needed = paragraph.getMaxIntrinsicHeight(paragraph.size.width);
    if (needed > paragraph.size.height + 1) {
      clipped.add(
          '"${paragraph.text.toPlainText()}" $needed>${paragraph.size.height}');
    }
  }
  return clipped;
}
