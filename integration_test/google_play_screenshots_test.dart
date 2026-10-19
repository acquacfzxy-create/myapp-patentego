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
import 'package:provider/provider.dart';

import 'support/screenshot_iap.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('captures Google Play listing screenshots', (tester) async {
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

    debugPrint('GOOGLE_PLAY_SCREENSHOTS_READY=${outputDir.path}');
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
          // 商店截图需要显示订阅价格：使用假 IAP，绝不连接真实 Google Play Billing。
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
  final image = await boundary.toImage(pixelRatio: 2);
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
  final outputDir = Directory('${documentsDir.path}/google_play_screenshots');
  if (outputDir.existsSync()) {
    outputDir.deleteSync(recursive: true);
  }
  outputDir.createSync(recursive: true);
  debugPrint('GOOGLE_PLAY_SCREENSHOT_OUTPUT_DIR=${outputDir.path}');
  return outputDir;
}

Future<void> _seedStoreListingData() async {
  const userId = UserStateProvider.guestUserId;
  await DatabaseService.resetAllUserProgress(userId: userId);

  final questions = await DatabaseService.getQuestions(
    lang: 'en',
    limit: 20,
    userId: userId,
  );

  for (final question in questions.take(12)) {
    await DatabaseService.updateQuestionProgress(
      question.id,
      false,
      userId: userId,
    );
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

Question _storeQuestion() {
  const fallbackExplanation = {
    'detailed_description':
        'This question checks whether the driver recognizes when to reduce speed and pay close attention to other road users.',
    'key_points': [
      {
        'title': 'moderare la velocita',
        'content': 'Slow down to a safe speed before the situation becomes risky.'
      },
      {
        'title': 'prestare attenzione',
        'content': 'Look around carefully and be ready to react.'
      }
    ],
    'study_tip':
        'When a road sign warns about danger, the safe answer usually starts with **prudenza (caution)**.',
  };

  return Question(
    id: 'google-play-preview',
    answer: true,
    translations: const {
      'it':
          'In presenza del segnale raffigurato, il conducente deve moderare la velocita e prestare particolare attenzione.',
      'en':
          'When this road sign is present, the driver must slow down and pay special attention.',
    },
    explanations: {'en': jsonEncode(fallbackExplanation)},
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
