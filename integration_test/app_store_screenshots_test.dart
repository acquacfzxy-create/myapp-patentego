import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lingua_patente/config/app_strings.dart';
import 'package:lingua_patente/models/question.dart';
import 'package:lingua_patente/providers/user_state_provider.dart';
import 'package:lingua_patente/screens/chapter_selection_screen.dart';
import 'package:lingua_patente/screens/home_screen.dart';
import 'package:lingua_patente/screens/language_selection_screen.dart';
import 'package:lingua_patente/screens/mastery_report_screen.dart';
import 'package:lingua_patente/screens/mistake_review_screen.dart';
import 'package:lingua_patente/screens/mock_test_result_screen.dart';
import 'package:lingua_patente/screens/mock_test_screen.dart';
import 'package:lingua_patente/screens/subscription_page.dart';
import 'package:lingua_patente/services/database_service.dart';
import 'package:lingua_patente/services/iap_service.dart';
import 'package:lingua_patente/widgets/question_widget.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';

import 'support/l10n_sample_image_question.dart';
import 'support/screenshot_iap.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('captures App Store listing screenshots (iPhone 6.9")',
      (tester) async {
    await DatabaseService.init();
    await _seedStoreListingData();

    const language = 'en';
    final outputDir = await _prepareOutputDirectory();
    final question = _storeQuestion();

    await _pumpListingPage(
      tester,
      language: language,
      page: const LanguageSelectionScreen(),
    );
    await tester.tap(find.text('English'));
    await tester.pump(const Duration(milliseconds: 500));
    await _capture(tester, outputDir, '01_language_selection');

    await _pumpListingPage(
      tester,
      language: language,
      page: const HomeScreen(),
    );
    await tester.pump(const Duration(seconds: 2));
    await _capture(tester, outputDir, '02_home');

    await _pumpListingPage(
      tester,
      language: language,
      page: const ChapterSelectionScreen(),
    );
    await _capture(tester, outputDir, '03_chapters');

    await _pumpListingPage(
      tester,
      language: language,
      page: _QuestionPreviewPage(
        question: question,
        language: language,
      ),
    );
    await _capture(tester, outputDir, '04_practice_question');

    await _pumpListingPage(
      tester,
      language: language,
      page: _ExplanationPreviewPage(
        question: question,
        language: language,
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    await _capture(tester, outputDir, '05_explanation');
    await _dismissTopRoute(tester);

    await _pumpListingPage(
      tester,
      language: language,
      page: const MockTestScreen(),
    );
    await tester.pump(const Duration(seconds: 2));
    await _capture(tester, outputDir, '06_mock_exam');

    await _pumpListingPage(
      tester,
      language: language,
      page: _MockResultPreviewPage(question: question),
    );
    await _capture(tester, outputDir, '07_mock_result');

    await _pumpListingPage(
      tester,
      language: language,
      page: const MasteryReportScreen(),
    );
    await _capture(tester, outputDir, '08_mastery_report');

    await _pumpListingPage(
      tester,
      language: language,
      page: const MistakeReviewScreen(initialTabIndex: 1),
    );
    await _capture(tester, outputDir, '09_mistake_review');

    await _pumpListingPage(
      tester,
      language: language,
      page: const SubscriptionPage(),
    );
    await _capture(tester, outputDir, '10_subscription');

    debugPrint('APP_STORE_SCREENSHOTS_READY=${outputDir.path}');
    if (const bool.fromEnvironment('KEEP_SCREENSHOT_CONTAINER')) {
      await Future<void>.delayed(const Duration(seconds: 60));
    }
  });
}

Future<void> _pumpListingPage(
  WidgetTester tester, {
  required String language,
  required Widget page,
}) async {
  final provider = UserStateProvider();
  await tester.pump(const Duration(milliseconds: 300));
  await provider.changeLanguage(language);
  await provider.updateUserState(isVip: true, currentLanguage: language);
  await provider.refreshChaptersProgress();
  AppStrings.setLanguage(language);

  await tester.pumpWidget(
    RepaintBoundary(
      key: _screenshotKey,
      child: MultiProvider(
        providers: [
          ChangeNotifierProvider<UserStateProvider>.value(value: provider),
          // 商店截图需要显示订阅价格：使用假 IAP，绝不连接真实 App Store / Play 结算。
          ChangeNotifierProvider<IapService>(
            create: (_) => IapService(
              iap: ScreenshotIap(),
              billingSupported: true,
            ),
          ),
        ],
        child: MaterialApp(
          navigatorKey: _navigatorKey,
          debugShowCheckedModeBanner: false,
          home: page,
        ),
      ),
    ),
  );

  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump(const Duration(seconds: 1));
}

Future<void> _capture(
  WidgetTester tester,
  Directory outputDir,
  String name,
) async {
  await tester.pump(const Duration(milliseconds: 300));
  final boundary = _screenshotKey.currentContext!.findRenderObject()
      as RenderRepaintBoundary;
  final image = await boundary.toImage(pixelRatio: 3);
  final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
  final bytes = byteData!.buffer.asUint8List();
  await File('${outputDir.path}/$name.png').writeAsBytes(bytes, flush: true);
}

final _screenshotKey = GlobalKey();
final _navigatorKey = GlobalKey<NavigatorState>();

Future<void> _dismissTopRoute(WidgetTester tester) async {
  final navigator = _navigatorKey.currentState;
  if (navigator != null && navigator.canPop()) {
    navigator.pop();
    await tester.pump(const Duration(milliseconds: 300));
  }
}

Future<Directory> _prepareOutputDirectory() async {
  final documentsDir = await getApplicationDocumentsDirectory();
  final outputDir = Directory('${documentsDir.path}/app_store_screenshots');
  if (outputDir.existsSync()) {
    outputDir.deleteSync(recursive: true);
  }
  outputDir.createSync(recursive: true);
  debugPrint('APP_STORE_SCREENSHOT_OUTPUT_DIR=${outputDir.path}');
  return outputDir;
}

Future<void> _seedStoreListingData() async {
  const userId = UserStateProvider.guestUserId;
  // 模拟器容器可能保留上一次运行的每日计数（SharedPreferences），首页会取其与数据库的较大值，
  // 所以先清空，保证截图只反映下面的种子数据。
  final prefs = await SharedPreferences.getInstance();
  await prefs.clear();
  await DatabaseService.resetAllUserProgress(userId: userId);

  final questions = await DatabaseService.getQuestions(
    lang: 'en',
    limit: 220,
    userId: userId,
  );

  // 非敏感的访客测试数据：一部分题目答对 4 次（掌握），一部分答对 1 次，一部分答错（进入错题本）。
  for (final entry in questions.indexed) {
    final (index, question) = entry;
    if (index < 70) {
      for (var i = 0; i < 4; i++) {
        await DatabaseService.updateQuestionProgress(question.id, true,
            userId: userId);
      }
    } else if (index < 130) {
      await DatabaseService.updateQuestionProgress(question.id, true,
          userId: userId);
    } else if (index < 170) {
      await DatabaseService.updateQuestionProgress(question.id, false,
          userId: userId);
    }
  }

  // 最近 7 天的学习成长（含一天休息），用于「本周成长」图表。
  final now = DateTime.now();
  // newCount：当天「新题」数，其余为复习题。今天的复习数必须不超过首页「今日目标」的复习目标，
  // 否则首页会出现「Review 10 / 6」这种分子大于分母的画面（只调整截图种子，不改产品计算）。
  const week = [
    (daysAgo: 6, answered: 18, correct: 11, newCount: 12),
    (daysAgo: 5, answered: 26, correct: 19, newCount: 17),
    (daysAgo: 4, answered: 0, correct: 0, newCount: 0),
    (daysAgo: 3, answered: 31, correct: 24, newCount: 21),
    (daysAgo: 2, answered: 40, correct: 31, newCount: 27),
    (daysAgo: 1, answered: 22, correct: 17, newCount: 15),
    (daysAgo: 0, answered: 14, correct: 11, newCount: 9),
  ];
  for (final day in week) {
    for (var i = 0; i < day.answered; i++) {
      final isCorrect = i < day.correct;
      await DatabaseService.recordDailyGrowth(
        userId: userId,
        isCorrect: isCorrect,
        isNewQuestion: i < day.newCount,
        newlyMastered: isCorrect && i % 9 == 0,
        mistakeResolved: isCorrect && i % 11 == 0,
        occurredAt: now.subtract(Duration(days: day.daysAgo)),
      );
    }
  }

  for (final result in [
    (correct: 20, wrong: 10, total: 30),
    (correct: 22, wrong: 8, total: 30),
    (correct: 24, wrong: 6, total: 30),
    (correct: 25, wrong: 5, total: 30),
    (correct: 27, wrong: 3, total: 30),
  ]) {
    await DatabaseService.saveMockTestResult(
      userId: userId,
      correctCount: result.correct,
      wrongCount: result.wrong,
      totalQuestions: result.total,
      timeUsedSeconds: 900,
    );
  }
}

// 题库只读导出的真实带路牌图题目（2665），含英文解析：练习页与解析弹窗显示真实内容。
Question _storeQuestion() {
  final q = jsonDecode(kL10nSampleImageQuestionJson) as Map<String, dynamic>;
  return Question(
    id: q['id'] as String,
    imageName: q['image_name'] as String?,
    answer: q['answer'] as bool,
    translations: Map<String, String>.from(q['translations'] as Map),
    explanations: Map<String, String>.from(q['explanations'] as Map),
    keywordsJson: q['keywords_json'] as String?,
    chapter: 1,
  );
}

class _QuestionPreviewPage extends StatelessWidget {
  const _QuestionPreviewPage({
    required this.question,
    required this.language,
  });

  final Question question;
  final String language;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: QuestionWidget(
        question: question,
        currentLanguage: language,
        currentIndex: 0,
        totalQuestions: 30,
        hasNextQuestion: true,
        isAnswered: false,
        onAnswerSelected: (_) {},
      ),
    );
  }
}

class _ExplanationPreviewPage extends StatefulWidget {
  const _ExplanationPreviewPage({
    required this.question,
    required this.language,
  });

  final Question question;
  final String language;

  @override
  State<_ExplanationPreviewPage> createState() =>
      _ExplanationPreviewPageState();
}

class _ExplanationPreviewPageState extends State<_ExplanationPreviewPage> {
  bool _opened = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_opened) return;
    _opened = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(
        QuestionWidget.showRichExplanation(
          context,
          question: widget.question,
          currentLanguage: widget.language,
          remainingExplanations: 3,
          showVipBadgeOnStudyTip: true,
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: QuestionWidget(
        question: widget.question,
        currentLanguage: widget.language,
        currentIndex: 0,
        totalQuestions: 30,
        hasNextQuestion: true,
        isAnswered: true,
        isCorrect: true,
        userChoice: widget.question.answer,
        onAnswerSelected: (_) {},
      ),
    );
  }
}

class _MockResultPreviewPage extends StatelessWidget {
  const _MockResultPreviewPage({required this.question});

  final Question question;

  @override
  Widget build(BuildContext context) {
    return MockTestResultScreen(
      totalQuestions: 30,
      correctAnswers: 24,
      errors: 6,
      isPassed: false,
      timeRemaining: 840,
      errorIds: [question.id],
      questions: [question],
      userChoices: {0: !question.answer},
    );
  }
}
