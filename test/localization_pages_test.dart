import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lingua_patente/config/app_locales.dart';
import 'package:lingua_patente/config/app_strings.dart';
import 'package:lingua_patente/config/app_theme.dart';
import 'package:lingua_patente/models/question.dart';
import 'package:lingua_patente/models/user_state.dart';
import 'package:lingua_patente/providers/user_state_provider.dart';
import 'package:lingua_patente/screens/auth_page.dart';
import 'package:lingua_patente/screens/daily_goal_setup_screen.dart';
import 'package:lingua_patente/screens/exam_review_screen.dart';
import 'package:lingua_patente/screens/language_selection_screen.dart';
import 'package:lingua_patente/screens/settings_screen.dart';
import 'package:lingua_patente/screens/subscription_page.dart';
import 'package:lingua_patente/services/iap_service.dart';
import 'package:lingua_patente/widgets/question_widget.dart';
import 'package:lingua_patente/widgets/translation_panel.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../integration_test/support/screenshot_iap.dart';

/// 六种界面语言 × 320px 小屏 × 1.0/1.5 倍字号，使用 App 实际打包的 Noto 字体，
/// 检查关键页面无布局溢出，并验证 RTL（乌尔都语）、旁遮普语双文字、意大利语题干 LTR。
///
/// 题目数据来自 test/fixtures/l10n_sample_question.json（题库只读导出的真实题目：
/// 旁遮普语题干为 Shahmukhi，解析为 Gurmukhi）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const smallPhone = Size(320, 640);
  const textScales = [1.0, 1.5];
  const languages = UserState.supportedLanguages;
  late Question sample;

  setUpAll(() async {
    await _loadAppFonts();
    final fixture = jsonDecode(
      File('test/fixtures/l10n_sample_question.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    final q = fixture['question'] as Map<String, dynamic>;
    sample = Question(
      id: q['id'] as String,
      answer: q['answer'] as bool,
      translations: Map<String, String>.from(q['translations'] as Map),
      explanations: Map<String, String>.from(q['explanations'] as Map),
      keywordsJson: q['keywords_json'] as String?,
    );
  });

  Future<void> pumpPage(
    WidgetTester tester, {
    required String language,
    required double textScale,
    required Widget home,
  }) async {
    tester.view.physicalSize = smallPhone;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SharedPreferences.setMockInitialValues({'current_language': language});
    PackageInfo.setMockInitialValues(
      appName: 'LinguaPatente',
      packageName: 'com.patentego.app',
      version: '1.0.8',
      buildNumber: '10',
      buildSignature: '',
    );
    final user = UserStateProvider();
    await user.changeLanguage(language);
    AppStrings.setLanguage(language);
    final iap = IapService(iap: ScreenshotIap(), billingSupported: true);
    addTearDown(iap.dispose);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<UserStateProvider>.value(value: user),
          ChangeNotifierProvider<IapService>.value(value: iap),
        ],
        child: MaterialApp(
          locale: AppLocales.localeFor(language),
          supportedLocales: AppLocales.supportedLocales,
          localizationsDelegates: AppLocales.delegates,
          theme: AppTheme.lightTheme(language: language),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          home: home,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(seconds: 1));
  }

  /// 没有行数上限、也不省略的文字，不能被父级压扁裁切（布局溢出不会报出这类问题）。
  void expectNoClippedText(WidgetTester tester, String where) {
    final clipped = <String>[];
    for (final element in find.byType(RichText).evaluate()) {
      final paragraph = element.renderObject as RenderParagraph;
      if (!paragraph.hasSize || paragraph.maxLines != null) continue;
      if (paragraph.overflow != TextOverflow.clip) continue;
      final needed = paragraph.getMaxIntrinsicHeight(paragraph.size.width);
      if (needed > paragraph.size.height + 1) {
        final text = paragraph.text.toPlainText();
        clipped.add('"${text.length > 40 ? text.substring(0, 40) : text}" '
            'needs ${needed.toStringAsFixed(0)} has ${paragraph.size.height.toStringAsFixed(0)}');
      }
    }
    expect(clipped, isEmpty, reason: '$where: clipped text');
  }

  /// 首屏与滚动到底部后都不应出现布局异常。
  Future<void> expectNoOverflowWhileScrolling(WidgetTester tester) async {
    expect(tester.takeException(), isNull, reason: 'first viewport');
    expectNoClippedText(tester, 'first viewport');
    for (final element in find.byType(Scrollable).evaluate().toList()) {
      final state = (element as StatefulElement).state as ScrollableState;
      final position = state.position;
      if (position.hasContentDimensions && position.maxScrollExtent > 0) {
        position.jumpTo(position.maxScrollExtent);
      }
    }
    await tester.pump();
    expect(tester.takeException(), isNull, reason: 'scrolled to bottom');
    expectNoClippedText(tester, 'scrolled to bottom');
  }

  Future<void> disposePage(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  }

  TextDirection expectedDirection(String language) =>
      language == 'ur' ? TextDirection.rtl : TextDirection.ltr;

  String t(String language, String key) =>
      AppStrings.getWithLanguage(language, key);

  // 页面构造器 + 该页已真正渲染出内容（而非仅加载圈）的标志文本。
  final pages = <String,
      (Widget Function(String language), Finder Function(String language))>{
    'AuthPage': (
      (_) => const AuthPage(),
      (l) => find.text(t(l, 'auth_google')),
    ),
    'SubscriptionPage (fake IAP)': (
      (_) => const SubscriptionPage(),
      (l) => find.text(kScreenshotMonthlyPrice),
    ),
    'SettingsScreen': (
      (_) => const SettingsScreen(),
      (l) => find.text(t(l, 'settings_title')),
    ),
    'LanguageSelectionScreen': (
      (_) => const LanguageSelectionScreen(),
      (l) => find.text(UserState.languageNames['uk']!),
    ),
    'DailyGoalSetupScreen': (
      (_) => const DailyGoalSetupScreen(),
      (l) => find.text(t(l, 'daily_goal_setup_title')),
    ),
    'DailyGoalSetupScreen (editing)': (
      (_) => const DailyGoalSetupScreen(isEditing: true),
      (l) => find.text(t(l, 'daily_goal_manage_title')),
    ),
    'ExamReviewScreen': (
      (_) =>
          ExamReviewScreen(questions: [sample], userChoices: const {0: true}),
      (l) => find.text(sample.translations['it']!),
    ),
  };

  for (final language in languages) {
    for (final scale in textScales) {
      for (final entry in pages.entries) {
        testWidgets('${entry.key} fits 320px [$language, x$scale]',
            (tester) async {
          final (build, marker) = entry.value;
          final home = build(language);
          await pumpPage(tester,
              language: language, textScale: scale, home: home);
          expect(marker(language), findsWidgets,
              reason: '${entry.key} did not render its content');

          final pageElement = tester.element(find.byWidget(home));
          expect(Directionality.of(pageElement), expectedDirection(language));
          if (home is SubscriptionPage) {
            // 关闭按钮不能压在顶栏标题上（任何语言、任何方向）。
            final close = tester.getRect(find.byIcon(Icons.close_rounded));
            final title = tester.getRect(find.text('LinguaPatente'));
            expect(close.overlaps(title), isFalse,
                reason: 'close button $close overlaps title $title');
            // 品牌大标题不能在单词中间断行：实际高度不超过单行高度。
            final brand = tester.renderObject<RenderParagraph>(
                find.text(t(language, 'sub_title')));
            final oneLine = TextPainter(
              text: brand.text,
              textDirection: brand.textDirection,
              textScaler: brand.textScaler,
              maxLines: 1,
            )..layout();
            expect(brand.size.height, lessThanOrEqualTo(oneLine.height + 0.5),
                reason: 'sub_title wraps onto several lines');
            oneLine.dispose();
            // 主按钮文字必须完整显示（乌尔都语 Nastaliq 行高很大，固定按钮高度会把文字压扁裁切）。
            final cta = tester.renderObject<RenderParagraph>(
                find.text(t(language, 'sub_cta_subscribe_button')));
            final needed = cta.getMaxIntrinsicHeight(cta.size.width);
            expect(needed, lessThanOrEqualTo(cta.size.height + 0.5),
                reason:
                    'CTA text needs ${needed}px but has ${cta.size.height}px');
          }
          await expectNoOverflowWhileScrolling(tester);
          await disposePage(tester);
        });
      }

      testWidgets('question with translation fits 320px [$language, x$scale]',
          (tester) async {
        await pumpPage(
          tester,
          language: language,
          textScale: scale,
          home: Scaffold(
            body: QuestionWidget(
              question: sample,
              currentLanguage: language,
              onAnswerSelected: (_) {},
              currentIndex: 1,
              totalQuestions: 30,
            ),
          ),
        );

        // 意大利语题干在任何界面语言下都从左到右。
        final stem = tester.widget<Text>(find.text(sample.translations['it']!));
        expect(stem.textDirection, TextDirection.ltr);

        await tester.tap(find.byIcon(Icons.translate));
        await tester.pump(const Duration(milliseconds: 500));

        final translation = sample.translations[language]!;
        final translationText = tester.widget<Text>(find.descendant(
          of: find.byType(TranslationPanel),
          matching: find.text(translation),
        ));
        // pa 题干是 Shahmukhi（阿拉伯字母），在 LTR 的 pa 界面里也要按 RTL 排版。
        expect(
          translationText.textDirection,
          language == 'ur' || language == 'pa'
              ? TextDirection.rtl
              : TextDirection.ltr,
        );
        await expectNoOverflowWhileScrolling(tester);
        await disposePage(tester);
      });

      testWidgets('explanation sheet fits 320px [$language, x$scale]',
          (tester) async {
        await pumpPage(
          tester,
          language: language,
          textScale: scale,
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => QuestionWidget.showRichExplanation(
                    context,
                    question: sample,
                    currentLanguage: language,
                    remainingExplanations: 1,
                    showVipBadgeOnStudyTip: true,
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('open'));
        await tester.pump(const Duration(seconds: 1));

        expect(
          find.text(AppStrings.getWithLanguage(
              language, 'modal_correct_answer_label')),
          findsOneWidget,
        );
        await expectNoOverflowWhileScrolling(tester);
        await disposePage(tester);
      });
    }
  }

  test('real app fonts are loaded (not the square test font)', () {
    double width(String text, String family) {
      final painter = TextPainter(
        text: TextSpan(
            text: text, style: TextStyle(fontFamily: family, fontSize: 20)),
        textDirection: TextDirection.ltr,
      )..layout();
      return painter.width;
    }

    double height(String text, String family) {
      final painter = TextPainter(
        text: TextSpan(
            text: text, style: TextStyle(fontFamily: family, fontSize: 20)),
        textDirection: TextDirection.rtl,
      )..layout();
      return painter.height;
    }

    // 测试默认字体每个字形宽 1em：'iiii' 与 'WWWW' 等宽。真实字体下 i 明显更窄。
    for (final family in ['NotoSans', 'NotoSansSC']) {
      expect(width('iiii', family), lessThan(width('WWWW', family) * 0.6),
          reason: family);
    }
    // Nastaliq 行高远大于 1em；Gurmukhi 元音符号不占 1em 宽。
    expect(height('سڑک', 'NotoNastaliqUrdu'), greaterThan(30));
    expect(width('ਕਿ', 'NotoSansGurmukhi'),
        lessThan(width('ਕਕ', 'NotoSansGurmukhi')));
  });

  group('Flutter built-in widgets follow the UI language', () {
    const expectedBack = {
      'zh': '返回',
      'en': 'Back',
      'ru': 'Назад',
      'uk': 'Назад',
      'pa': 'ਪਿੱਛੇ',
      'ur': 'پیچھے',
    };

    for (final language in languages) {
      testWidgets('back tooltip, text menu and direction [$language]',
          (tester) async {
        final controller = TextEditingController(text: 'Il segnale');
        addTearDown(controller.dispose);
        late BuildContext captured;
        await tester.pumpWidget(
          MaterialApp(
            locale: AppLocales.localeFor(language),
            supportedLocales: AppLocales.supportedLocales,
            localizationsDelegates: AppLocales.delegates,
            home: Builder(builder: (context) {
              captured = context;
              return Scaffold(
                appBar: AppBar(leading: const BackButton()),
                body: Center(child: TextField(controller: controller)),
              );
            }),
          ),
        );

        final material = MaterialLocalizations.of(captured);
        expect(material.backButtonTooltip, expectedBack[language]);
        expect(Directionality.of(captured), expectedDirection(language));
        expect(
          find.byTooltip(material.backButtonTooltip),
          findsOneWidget,
        );

        // 选中部分文字并打开文本菜单，按钮应使用该语言的「复制 / 全选」。
        await tester.tap(find.byType(TextField));
        await tester.pump();
        controller.selection =
            const TextSelection(baseOffset: 0, extentOffset: 2);
        await tester.pump();
        tester
            .state<EditableTextState>(find.byType(EditableText))
            .showToolbar();
        await tester.pumpAndSettle();
        expect(find.text(material.copyButtonLabel), findsOneWidget);
        expect(find.text(material.selectAllButtonLabel), findsOneWidget);
      });
    }
  });
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
