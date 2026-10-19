import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lingua_patente/config/app_locales.dart';
import 'package:lingua_patente/config/app_strings.dart';
import 'package:lingua_patente/config/app_theme.dart';
import 'package:lingua_patente/models/question.dart';
import 'package:lingua_patente/models/user_state.dart';
import 'package:lingua_patente/providers/user_state_provider.dart';
import 'package:lingua_patente/screens/auth_page.dart';
import 'package:lingua_patente/screens/chapter_selection_screen.dart';
import 'package:lingua_patente/screens/settings_screen.dart';
import 'package:lingua_patente/screens/subscription_page.dart';
import 'package:lingua_patente/screens/voice_pack_screen.dart';
import 'package:lingua_patente/services/database_service.dart';
import 'package:lingua_patente/services/iap_service.dart';
import 'package:lingua_patente/widgets/glass_card.dart';
import 'package:lingua_patente/widgets/question_widget.dart';
import 'package:lingua_patente/widgets/translation_panel.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import 'support/l10n_sample_image_question.dart';
import 'support/l10n_sample_question.dart';
import 'support/screenshot_iap.dart';

/// Android 多语言验收：六种界面语言下的登录、题目+译文、解析、设置、订阅（模拟购买）、
/// 语音包页面。屏幕尺寸与字体缩放取自设备的系统设置（由验收前的 adb 配置决定），
/// 不在测试中写死；截图写入应用 Documents/android_l10n_acceptance。
///
/// 不登录、不购买：订阅页使用 ScreenshotIap，不连接真实 Google Play Billing。
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Android localization acceptance: six UI languages',
      (tester) async {
    await DatabaseService.init();
    final outputDir = await _prepareOutputDirectory();
    final question = _sampleQuestion(kL10nSampleQuestionJson);
    final imageQuestion = _sampleQuestion(kL10nSampleImageQuestionJson);
    // 只跑指定页面（逗号分隔），例如 --dart-define=L10N_PAGES=question,question_image
    const pageFilter = String.fromEnvironment('L10N_PAGES');
    final view = tester.view;
    final logicalWidth = view.physicalSize.width / view.devicePixelRatio;
    final report = <String>[
      'screen=${logicalWidth.toStringAsFixed(0)}dp '
          'dpr=${view.devicePixelRatio} '
          'textScale(16)=${binding.platformDispatcher.textScaleFactor}',
    ];
    final problems = <String>[];

    for (final language in UserState.supportedLanguages) {
      final pages = <String, Widget>{
        'auth': const AuthPage(),
        'question': Scaffold(
          body: SafeArea(
            child: QuestionWidget(
              question: question,
              currentLanguage: language,
              onAnswerSelected: (_) {},
              currentIndex: 1,
              totalQuestions: 30,
            ),
          ),
        ),
        'question_image': Scaffold(
          body: SafeArea(
            child: QuestionWidget(
              question: imageQuestion,
              currentLanguage: language,
              onAnswerSelected: (_) {},
              currentIndex: 1,
              totalQuestions: 30,
            ),
          ),
        ),
        'question_answered': Scaffold(
          body: SafeArea(
            child: QuestionWidget(
              question: question,
              currentLanguage: language,
              onAnswerSelected: (_) {},
              currentIndex: 1,
              totalQuestions: 30,
              isAnswered: true,
              isCorrect: false,
              userChoice: !question.answer,
              hasPreviousQuestion: true,
              hasNextQuestion: true,
              onPreviousQuestion: () {},
              onNextQuestion: () {},
              showFavoriteBadge: true,
              showMasteredBadge: true,
            ),
          ),
        ),
        'chapters': const ChapterSelectionScreen(),
        'explanation': Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => QuestionWidget.showRichExplanation(
                  context,
                  question: question,
                  currentLanguage: language,
                  remainingExplanations: 1,
                  showVipBadgeOnStudyTip: true,
                ),
                child: const Text('open-explanation'),
              ),
            ),
          ),
        ),
        'settings': const SettingsScreen(),
        'subscription': const SubscriptionPage(),
        'voice_pack': const VoicePackScreen(),
      };

      for (final entry in pages.entries) {
        if (pageFilter.isNotEmpty &&
            !pageFilter.split(',').contains(entry.key)) {
          continue;
        }
        final name = '${language}_${entry.key}';
        final errors = <String>[];
        final previous = FlutterError.onError;
        FlutterError.onError =
            (details) => errors.add(details.exceptionAsString());

        await _pumpPage(tester, language: language, page: entry.value);

        switch (entry.key) {
          case 'question':
            final stem = tester.widget<Text>(
              find.text(question.translations['it']!),
            );
            if (stem.textDirection != TextDirection.ltr) {
              errors.add('Italian stem is not LTR');
            }
            errors.addAll(_actionOverlap(tester).map((e) => 'top: $e'));
            await tester.tap(find.byIcon(Icons.translate));
            await _settle(tester);
            final translation = tester.widget<Text>(find.descendant(
              of: find.byType(TranslationPanel),
              matching: find.text(question.translations[language]!),
            ));
            final expected = language == 'ur' || language == 'pa'
                ? TextDirection.rtl
                : TextDirection.ltr;
            if (translation.textDirection != expected) {
              errors.add('translation direction ${translation.textDirection}');
            }
            errors.addAll(await _actionOverlapWhileScrolling(tester));
          case 'question_answered':
            // 反馈气泡（精通、收藏、答错）不能盖住操作按钮。
            final bubbles = tester.getRect(
                find.byKey(const ValueKey('question-feedback-bubbles')));
            errors.addAll(_actionRects(tester)
                .where(bubbles.overlaps)
                .map((r) => 'feedback bubbles cover action $r'));
            errors.addAll(await _actionOverlapWhileScrolling(tester));
          case 'question_image':
            if (find.byType(Image).evaluate().isEmpty) {
              errors.add('question image missing');
            }
            await tester.tap(find.byIcon(Icons.translate));
            await _settle(tester);
            errors.addAll(await _actionOverlapWhileScrolling(tester));
          case 'explanation':
            await tester.tap(find.text('open-explanation'));
            await _settle(tester);
          case 'subscription':
            final close = tester.getRect(find.byIcon(Icons.close_rounded));
            final title = tester.getRect(find.text('LinguaPatente'));
            if (close.overlaps(title)) {
              errors.add('close button overlaps title');
            }
          case 'voice_pack':
            // 测试进程未初始化 Firebase：目录加载必然失败，验证失败提示已本地化。
            for (var i = 0;
                i < 20 &&
                    find
                        .text(AppStrings.get('voice_pack_catalog_error'))
                        .evaluate()
                        .isEmpty;
                i++) {
              await tester.pump(const Duration(milliseconds: 250));
            }
            if (find
                .text(AppStrings.get('voice_pack_catalog_error'))
                .evaluate()
                .isEmpty) {
              errors.add('voice pack catalog error not shown');
            }
            if (find.textContaining('Exception').evaluate().isNotEmpty ||
                find.textContaining('Firebase').evaluate().isNotEmpty) {
              errors.add('raw error text is visible');
            }
          default:
            break;
        }

        final pageDirection = Directionality.of(
          tester.element(find.byType(Scaffold).first),
        );
        final expectedPage =
            language == 'ur' ? TextDirection.rtl : TextDirection.ltr;
        if (pageDirection != expectedPage) {
          errors.add('page direction $pageDirection');
        }

        errors.addAll(_clippedText(tester));
        await _capture(tester, outputDir, name);

        // 滚到底部，检查首屏以外的内容。
        for (final element in find.byType(Scrollable).evaluate().toList()) {
          final position =
              ((element as StatefulElement).state as ScrollableState).position;
          if (position.hasContentDimensions && position.maxScrollExtent > 0) {
            position.jumpTo(position.maxScrollExtent);
          }
        }
        await tester.pump(const Duration(milliseconds: 300));
        errors.addAll(_clippedText(tester).map((e) => 'bottom: $e'));
        await _capture(tester, outputDir, '${name}_bottom');

        FlutterError.onError = previous;
        report.add('$name: ${errors.isEmpty ? 'OK' : errors.join(' | ')}');
        if (errors.isNotEmpty) problems.add(name);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(milliseconds: 300));
      }
    }

    await File('${outputDir.path}/report.txt')
        .writeAsString('${report.join('\n')}\n');
    for (final line in report) {
      debugPrint('ANDROID_L10N $line');
    }
    debugPrint('ANDROID_L10N_READY=${outputDir.path}');
    if (const bool.fromEnvironment('KEEP_SCREENSHOT_CONTAINER')) {
      await Future<void>.delayed(const Duration(seconds: 90));
    }
    expect(problems, isEmpty, reason: report.join('\n'));
  });
}

Question _sampleQuestion(String json) {
  final q = jsonDecode(json) as Map<String, dynamic>;
  return Question(
    id: q['id'] as String,
    imageName: q['image_name'] as String?,
    answer: q['answer'] as bool,
    translations: Map<String, String>.from(q['translations'] as Map),
    explanations: Map<String, String>.from(q['explanations'] as Map),
    keywordsJson: q['keywords_json'] as String?,
  );
}

const _actionIcons = [
  Icons.favorite_border,
  Icons.volume_up_outlined,
  Icons.menu_book_outlined,
  Icons.translate,
];

/// 题目页操作按钮与内容（文字、图片）、彼此、底部 VERO/FALSO 均不得重叠。
List<Rect> _actionRects(WidgetTester tester) {
  final scrollView = find.byType(SingleChildScrollView).first;
  final inContent = find
      .descendant(of: scrollView, matching: find.byType(Icon))
      .evaluate()
      .toSet();
  return [
    for (final icon in _actionIcons)
      for (final element in find.byIcon(icon).evaluate())
        if (!inContent.contains(element))
          tester.getRect(find
              .ancestor(
                of: find.byElementPredicate((e) => e == element),
                matching: find.byType(GlassCard),
              )
              .first),
  ];
}

List<String> _actionOverlap(WidgetTester tester) {
  final scrollView = find.byType(SingleChildScrollView).first;
  final viewport = tester.getRect(scrollView);
  final actions = _actionRects(tester);
  final problems = <String>[];
  if (actions.length < 3) problems.add('only ${actions.length} action buttons');
  final content = <(String, Rect)>[];
  for (final element in find
      .descendant(of: scrollView, matching: find.byType(RichText))
      .evaluate()) {
    final box = element.renderObject as RenderParagraph;
    final text = box.text.toPlainText();
    content.add((
      '"${text.length > 20 ? text.substring(0, 20) : text}"',
      (box.localToGlobal(Offset.zero) & box.size).intersect(viewport),
    ));
  }
  for (final element in find
      .descendant(of: scrollView, matching: find.byType(Image))
      .evaluate()) {
    final box = element.renderObject as RenderBox;
    content.add((
      'image',
      (box.localToGlobal(Offset.zero) & box.size).intersect(viewport)
    ));
  }
  for (final (label, rect) in content) {
    if (rect.width <= 1 || rect.height <= 1) continue;
    for (final action in actions) {
      if (rect.overlaps(action)) problems.add('$label under action button');
    }
  }
  for (var i = 0; i < actions.length; i++) {
    for (var j = i + 1; j < actions.length; j++) {
      if (actions[i].overlaps(actions[j])) {
        problems.add('action buttons overlap');
      }
    }
  }
  for (final answer in ['VERO', 'FALSO']) {
    final rect = tester.getRect(find.text(answer));
    if (actions.any(rect.overlaps)) problems.add('$answer under action button');
  }
  return problems;
}

Future<List<String>> _actionOverlapWhileScrolling(WidgetTester tester) async {
  final problems = <String>[];
  final position = tester
      .state<ScrollableState>(find
          .descendant(
            of: find.byType(SingleChildScrollView).first,
            matching: find.byType(Scrollable),
          )
          .first)
      .position;
  for (final fraction in [0.0, 0.5, 1.0]) {
    position.jumpTo(position.maxScrollExtent * fraction);
    await tester.pump(const Duration(milliseconds: 100));
    problems.addAll(_actionOverlap(tester).map((e) => 'scroll $fraction: $e'));
  }
  position.jumpTo(0);
  await tester.pump(const Duration(milliseconds: 100));
  return problems;
}

/// 解析弹窗等页面含持续动画，pumpAndSettle 会一直等到超时，改为固定时长推进。
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 150));
  }
}

/// 没有行数上限、也不省略的文字被父级压扁时会被裁切（不会报布局溢出）。
List<String> _clippedText(WidgetTester tester) {
  final clipped = <String>[];
  for (final element in find.byType(RichText).evaluate()) {
    final paragraph = element.renderObject as RenderParagraph;
    if (!paragraph.hasSize || paragraph.maxLines != null) continue;
    if (paragraph.overflow != TextOverflow.clip) continue;
    final needed = paragraph.getMaxIntrinsicHeight(paragraph.size.width);
    if (needed > paragraph.size.height + 1) {
      final text = paragraph.text.toPlainText();
      clipped.add(
          'clipped "${text.length > 30 ? text.substring(0, 30) : text}" '
          '${needed.toStringAsFixed(0)}>${paragraph.size.height.toStringAsFixed(0)}');
    }
  }
  return clipped;
}

final _boundaryKey = GlobalKey();

Future<void> _pumpPage(
  WidgetTester tester, {
  required String language,
  required Widget page,
}) async {
  final provider = UserStateProvider();
  await tester.pump(const Duration(milliseconds: 200));
  await provider.changeLanguage(language);
  AppStrings.setLanguage(language);
  final iap = IapService(iap: ScreenshotIap(), billingSupported: true);

  await tester.pumpWidget(
    RepaintBoundary(
      key: _boundaryKey,
      child: MultiProvider(
        providers: [
          ChangeNotifierProvider<UserStateProvider>.value(value: provider),
          ChangeNotifierProvider<IapService>.value(value: iap),
        ],
        // 与 main.dart 相同的语言、方向与主题配置；字体缩放来自系统设置。
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          locale: AppLocales.localeFor(language),
          supportedLocales: AppLocales.supportedLocales,
          localizationsDelegates: AppLocales.delegates,
          theme: AppTheme.lightTheme(language: language),
          home: page,
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pump(const Duration(seconds: 1));
}

Future<void> _capture(WidgetTester tester, Directory dir, String name) async {
  await tester.pump(const Duration(milliseconds: 200));
  final boundary =
      _boundaryKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
  final image = await boundary.toImage(pixelRatio: 1.5);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  await File('${dir.path}/$name.png')
      .writeAsBytes(bytes!.buffer.asUint8List(), flush: true);
}

Future<Directory> _prepareOutputDirectory() async {
  final documents = await getApplicationDocumentsDirectory();
  final dir = Directory('${documents.path}/android_l10n_acceptance');
  if (dir.existsSync()) await dir.delete(recursive: true);
  return dir.create(recursive: true);
}
