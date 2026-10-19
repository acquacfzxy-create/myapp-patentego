import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lingua_patente/config/app_locales.dart';
import 'package:lingua_patente/config/app_strings.dart';
import 'package:lingua_patente/config/app_theme.dart';
import 'package:lingua_patente/providers/user_state_provider.dart';
import 'package:lingua_patente/screens/practice_screen.dart';
import 'package:lingua_patente/screens/subscription_page.dart';
import 'package:lingua_patente/services/iap_service.dart';
import 'support/screenshot_iap.dart';
import 'package:lingua_patente/services/database_service.dart';
import 'package:lingua_patente/widgets/question_widget.dart';
import 'package:lingua_patente/widgets/session_mistake_review_sheet.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('free session review pauses, resumes and never records answers',
      (tester) async {
    // In-memory preferences leave the installed learner's settings untouched.
    final now = DateTime.now();
    final today =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    SharedPreferences.setMockInitialValues({
      'current_language': 'zh',
      'daily_explanation_count': 10,
      'last_access_date': today,
    });
    await DatabaseService.init();
    final seeds = await DatabaseService.getQuestions(lang: 'it', limit: 3);
    final questions = (await Future.wait(seeds.map((question) =>
            DatabaseService.getQuestionWithTranslation(question.id))))
        .map((question) => question!)
        .toList();
    expect(questions.length, 3);
    for (final question in questions) {
      expect(question.getQuestionText('it'), isNotEmpty);
    }
    final provider = UserStateProvider();
    final boundaryKey = GlobalKey();
    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: provider,
      child: MaterialApp(
          locale: AppLocales.localeFor('zh'),
          supportedLocales: AppLocales.supportedLocales,
          localizationsDelegates: AppLocales.delegates,
          theme: AppTheme.lightTheme(language: 'zh'),
          builder: (_, child) =>
              RepaintBoundary(key: boundaryKey, child: child!),
          home: Scaffold(
            body: Center(
                child: Builder(
                    builder: (context) => TextButton(
                          onPressed: () => Navigator.of(context)
                              .push(MaterialPageRoute<void>(
                            builder: (_) =>
                                PracticeScreen(questions: questions),
                          )),
                          child: const Text('start'),
                        ))),
          )),
    ));
    await tester.pump(const Duration(seconds: 1));
    await provider.changeLanguage('zh');
    AppStrings.setLanguage('zh');
    expect(provider.isVip, isFalse);
    await tester.tap(find.text('start'));
    await tester.pump(const Duration(seconds: 1));
    expect(find.byKey(const Key('session_mistakes_button')), findsNothing);
    final initialDailyCount = provider.dailyQuizCount;
    final initialExplanations = provider.remainingExplanations;
    expect(initialExplanations, 0,
        reason: 'Legacy quota is exhausted but explanations remain accessible');
    final progressDb = await DatabaseService.userProgressDatabase;
    Future<List<Map<String, Object?>>> firstProgress() => progressDb.query(
          'user_progress',
          where: 'user_id = ? AND question_id = ?',
          whereArgs: [provider.effectiveUserId, questions.first.id],
        );

    Future<void> answer(bool value) async {
      final card = tester.widget<QuestionWidget>(find.byType(QuestionWidget));
      await card.onAnswerSelected(value);
      await tester.pump(const Duration(milliseconds: 50));
      expect(
          tester.widget<QuestionWidget>(find.byType(QuestionWidget)).isAnswered,
          isTrue);
    }

    Future<void> capture(String name) async {
      final dir = Directory(
          '${(await getApplicationDocumentsDirectory()).path}/session_review_evidence');
      await dir.create(recursive: true);
      await tester.pump(const Duration(milliseconds: 100));
      final boundary = boundaryKey.currentContext!.findRenderObject()
          as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 2);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await File('${dir.path}/$name.png')
          .writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
      debugPrint('SESSION_REVIEW_EVIDENCE=${dir.path}');
    }

    await answer(!questions.first.answer);
    expect(provider.dailyQuizCount, initialDailyCount + 1);
    final recordedProgress = await firstProgress();
    await tester.tap(find.byKey(const Key('session_mistakes_button')));
    await tester.pump(const Duration(seconds: 2));
    expect(find.byType(SessionMistakeReviewSheet), findsOneWidget);
    expect(
        tester.widget<QuestionWidget>(find.byType(QuestionWidget)).question.id,
        questions.first.id);
    await capture('review');
    await tester.tap(find.byKey(const Key('session_review_close')));
    await tester.pump(const Duration(milliseconds: 500));
    expect(
        tester.widget<QuestionWidget>(find.byType(QuestionWidget)).question.id,
        questions.first.id);
    await tester.pump(const Duration(seconds: 2));
    expect(
        tester.widget<QuestionWidget>(find.byType(QuestionWidget)).question.id,
        questions[1].id);
    expect(provider.dailyQuizCount, initialDailyCount + 1);
    expect(provider.remainingExplanations, initialExplanations);
    expect(await firstProgress(), recordedProgress);
    await capture('practice_button');

    // Full review, including expanded supplements, is free and never consumes usage.
    await tester.tap(find.byKey(const Key('session_mistakes_button')));
    await tester.pump(const Duration(milliseconds: 400));
    await capture('more_collapsed');
    final more = find.byKey(const Key('session_review_more'));
    await tester.ensureVisible(more);
    await tester.tap(more);
    await tester.pump(const Duration(milliseconds: 500));
    expect(provider.remainingExplanations, initialExplanations);
    expect(provider.dailyQuizCount, initialDailyCount + 1);
    expect(await firstProgress(), recordedProgress);
    await tester.ensureVisible(
        find.text(AppStrings.getWithLanguage('zh', 'study_tip_title')).last);
    await capture('more_expanded');
    await tester.ensureVisible(more);
    await tester.tap(more);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(more);
    await tester.pump(const Duration(milliseconds: 500));
    expect(provider.remainingExplanations, initialExplanations);
    await tester.tap(find.byKey(const Key('session_review_close')));
    await tester.pump(const Duration(milliseconds: 400));
    expect(
        tester.widget<QuestionWidget>(find.byType(QuestionWidget)).question.id,
        questions[1].id);

    // Translation opened before answering must also suspend the pending advance.
    await tester.tap(find.byIcon(Icons.translate).last);
    await answer(!questions[1].answer);
    await tester.pump(const Duration(seconds: 2));
    expect(
        tester.widget<QuestionWidget>(find.byType(QuestionWidget)).question.id,
        questions[1].id);
    await tester.tap(find.byIcon(Icons.translate).last);
    await tester.pump(const Duration(seconds: 2));
    expect(
        tester.widget<QuestionWidget>(find.byType(QuestionWidget)).question.id,
        questions[2].id);

    // A real explanation must pause and keep its own question as well.
    await answer(!questions[2].answer);
    await tester.tap(find.byIcon(Icons.menu_book_outlined));
    await tester.pump(const Duration(seconds: 2));
    expect(find.byKey(const Key('session_summary_review')), findsNothing);
    expect(
        tester.widget<QuestionWidget>(find.byType(QuestionWidget)).question.id,
        questions[2].id);
    Navigator.of(tester.element(find.byType(BottomSheet).last)).pop();
    await tester.pump(const Duration(seconds: 2));
    expect(find.byKey(const Key('session_summary_review')), findsOneWidget);
    await capture('summary');
    final dailyBeforeReview = provider.dailyQuizCount;
    final explanationsBeforeReview = provider.remainingExplanations;
    await tester.tap(find.byKey(const Key('session_summary_review')));
    await tester.pump(const Duration(seconds: 2));
    expect(
        tester
            .widget<Text>(find.byKey(const Key('session_review_position')))
            .data,
        '1/3');
    await capture('three_mistakes_1');
    await tester.tap(find.byKey(const Key('session_review_next')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(
        tester
            .widget<Text>(find.byKey(const Key('session_review_position')))
            .data,
        '2/3');
    await capture('three_mistakes_2');
    await tester.tap(find.byKey(const Key('session_review_next')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(
        tester
            .widget<Text>(find.byKey(const Key('session_review_position')))
            .data,
        '3/3');
    await capture('three_mistakes_3');
    await tester.tap(find.byKey(const Key('session_review_done')));
    await tester.pump(const Duration(seconds: 2));
    expect(find.byKey(const Key('session_summary_review')), findsOneWidget);
    expect(provider.dailyQuizCount, dailyBeforeReview);
    expect(provider.remainingExplanations, explanationsBeforeReview);
    expect(await firstProgress(), recordedProgress);
    expect(tester.takeException(), isNull);
    await tester.tap(
        find.text(AppStrings.getWithLanguage('zh', 'growth_finish_session')));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('start'), findsOneWidget);
    final service = IapService(iap: ScreenshotIap(), billingSupported: true);
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<UserStateProvider>.value(value: provider),
        ChangeNotifierProvider<IapService>.value(value: service),
      ],
      child: MaterialApp(
        locale: AppLocales.localeFor('zh'),
        supportedLocales: AppLocales.supportedLocales,
        localizationsDelegates: AppLocales.delegates,
        theme: AppTheme.lightTheme(language: 'zh'),
        builder: (_, child) => RepaintBoundary(key: boundaryKey, child: child!),
        home: const SubscriptionPage(),
      ),
    ));
    await tester.pump(const Duration(seconds: 2));
    await tester.ensureVisible(find.text('完整解析免费不限次'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('判断逻辑、考点总结和教练提示，所有用户均可免费查看'), findsOneWidget);
    expect(find.text('不限次数的完整解析 ✨'), findsNothing);
    await capture('subscription_free_explanations');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    provider.dispose();
    service.dispose();
  });
}
