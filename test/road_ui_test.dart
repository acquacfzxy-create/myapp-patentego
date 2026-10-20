import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lingua_patente/config/app_strings.dart';
import 'package:lingua_patente/config/app_theme.dart';
import 'package:lingua_patente/models/question.dart';
import 'package:lingua_patente/providers/user_state_provider.dart';
import 'package:lingua_patente/screens/exam_review_screen.dart';
import 'package:lingua_patente/screens/mock_test_result_screen.dart';
import 'package:lingua_patente/widgets/answer_motion.dart';
import 'package:lingua_patente/widgets/bouncy_press.dart';
import 'package:lingua_patente/widgets/learning_route_card.dart';
import 'package:lingua_patente/widgets/question_widget.dart';
import 'package:lingua_patente/widgets/road_segmented_tabs.dart';
import 'package:lingua_patente/widgets/streak_fire_overlay.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 道路標誌改版 P0：學習路線、答題即時對錯、模擬駕照結果頁。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    // 收藏狀態會訪問用戶進度庫；讓 path_provider 保持掛起即可。
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (_) => Completer<Object?>().future,
    );
  });

  setUp(() => AppStrings.setLanguage('zh'));

  group('LearningRouteCard', () {
    testWidgets('marks the current station and reports taps', (tester) async {
      LearningRouteStation? tapped;
      const stations = [
        LearningRouteStation(
          chapterId: 1,
          title: '交通标志',
          masteredPercent: 92,
          isDone: true,
          isCurrent: false,
          isLocked: false,
        ),
        LearningRouteStation(
          chapterId: 2,
          title: '优先通行权',
          masteredPercent: 41,
          isDone: false,
          isCurrent: true,
          isLocked: false,
        ),
        LearningRouteStation(
          chapterId: 3,
          title: '停车与临时停车',
          masteredPercent: 0,
          isDone: false,
          isCurrent: false,
          isLocked: true,
        ),
      ];
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme(language: 'zh'),
          home: Scaffold(
            body: LearningRouteCard(
              title: '学习路线',
              summary: '已通过 1/25 站',
              stations: stations,
              stationLabel: (s) => '第 ${s.chapterId} 站',
              onStationTap: (s) => tapped = s,
            ),
          ),
        ),
      );

      expect(find.text('优先通行权'), findsOneWidget);
      expect(find.byIcon(Icons.directions_car_filled_rounded), findsOneWidget);
      expect(find.byIcon(Icons.check_rounded), findsOneWidget);
      expect(find.byIcon(Icons.lock_rounded), findsOneWidget);

      await tester.tap(find.text('优先通行权'));
      expect(tapped?.chapterId, 2);
    });

    testWidgets('long RTL copy at accessibility text size does not overflow',
        (tester) async {
      tester.view.physicalSize = const Size(320, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      String t(String key) => AppStrings.getWithLanguage('ur', key);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme(language: 'ur'),
          builder: (context, child) => Directionality(
            textDirection: TextDirection.rtl,
            child: MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(3.12)),
              child: child!,
            ),
          ),
          home: Scaffold(
            body: SingleChildScrollView(
              child: LearningRouteCard(
                title: t('learning_route_title'),
                summary: t('learning_route_summary')
                    .replaceAll('{done}', '3')
                    .replaceAll('{total}', '25'),
                stations: const [
                  LearningRouteStation(
                    chapterId: 7,
                    title: 'سڑک کے نشانات اور سگنلز کی تفصیل',
                    masteredPercent: 41,
                    isDone: false,
                    isCurrent: true,
                    isLocked: false,
                  ),
                  LearningRouteStation(
                    chapterId: 8,
                    title: 'ترجیح',
                    masteredPercent: 0,
                    isDone: false,
                    isCurrent: false,
                    isLocked: true,
                  ),
                ],
                stationLabel: (s) => t('learning_route_station_current')
                    .replaceAll('{n}', '${s.chapterId}')
                    .replaceAll('{percent}', '${s.masteredPercent}'),
                onStationTap: (_) {},
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('streak fire', () {
    test('intensity starts at 5 in a row and is full at 10', () {
      expect(StreakFireOverlay.intensityFor(4), 0);
      expect(StreakFireOverlay.intensityFor(5), greaterThan(0.3));
      expect(StreakFireOverlay.intensityFor(7),
          greaterThan(StreakFireOverlay.intensityFor(5)));
      expect(StreakFireOverlay.intensityFor(10), 1);
      expect(StreakFireOverlay.intensityFor(25), 1);
    });

    testWidgets('overlay is hidden below 5 and fades in from 5',
        (tester) async {
      Widget app(int streak) => MaterialApp(
            home: Stack(children: [
              Positioned.fill(child: StreakFireOverlay(streak: streak)),
            ]),
          );
      double opacity() => tester
          .widget<AnimatedOpacity>(find.byKey(const Key('streak_fire_overlay')))
          .opacity;
      await tester.pumpWidget(app(3));
      expect(opacity(), 0);
      await tester.pumpWidget(app(6));
      expect(opacity(), 1);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpWidget(app(0));
      expect(opacity(), 0, reason: 'a wrong answer puts the fire out');
      await tester.pump(const Duration(seconds: 1));
    });
  });

  group('AnswerMotion', () {
    Future<void> pumpMotion(WidgetTester tester, AnswerMotionKind kind,
        {bool reduceMotion = false}) async {
      Widget app(AnswerMotionKind k) => MediaQuery(
            data: MediaQueryData(disableAnimations: reduceMotion),
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: Center(
                child: AnswerMotion(
                  kind: k,
                  child: const SizedBox(width: 80, height: 40),
                ),
              ),
            ),
          );
      await tester.pumpWidget(app(AnswerMotionKind.none));
      await tester.pumpWidget(app(kind));
      await tester.pump(); // post-frame start
      await tester.pump(const Duration(milliseconds: 90));
    }

    Matrix4? transformNow(WidgetTester tester) {
      final finder = find.descendant(
        of: find.byType(AnswerMotion),
        matching: find.byType(Transform),
      );
      if (finder.evaluate().isEmpty) return null;
      return tester.widget<Transform>(finder.first).transform;
    }

    testWidgets('correct answer pops above full size', (tester) async {
      await pumpMotion(tester, AnswerMotionKind.correctPop);
      expect(transformNow(tester)!.getMaxScaleOnAxis(), greaterThan(1.01));
      await tester.pumpAndSettle();
      expect(transformNow(tester), isNull);
    });

    testWidgets('wrong answer shakes sideways', (tester) async {
      await pumpMotion(tester, AnswerMotionKind.wrongShake);
      expect(transformNow(tester)!.getTranslation().x.abs(), greaterThan(0.5));
      await tester.pumpAndSettle();
      expect(transformNow(tester), isNull);
    });

    testWidgets('reduce motion keeps the button still', (tester) async {
      await pumpMotion(tester, AnswerMotionKind.wrongShake, reduceMotion: true);
      expect(transformNow(tester), isNull);
    });
  });

  testWidgets('bouncy press shrinks while held and springs back',
      (tester) async {
    var taps = 0;
    await tester.pumpWidget(MaterialApp(
      home: Center(
        child: BouncyPress(
          child: GestureDetector(
            onTap: () => taps++,
            child: const SizedBox(width: 100, height: 100, child: Text('tile')),
          ),
        ),
      ),
    ));
    double scale() => tester
        .widget<ScaleTransition>(find.descendant(
          of: find.byType(BouncyPress),
          matching: find.byType(ScaleTransition),
        ))
        .scale
        .value;
    final gesture =
        await tester.startGesture(tester.getCenter(find.text('tile')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    expect(scale(), lessThan(0.95));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(scale(), closeTo(1.0, 0.001));
    expect(taps, 1, reason: 'the wrapped tap still fires');
  });

  testWidgets('segmented tabs report taps and mark the selected tab',
      (tester) async {
    var selected = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme(language: 'zh'),
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => RoadSegmentedTabs(
              labels: const ['专项复习', '错题列表'],
              selectedIndex: selected,
              onSelected: (i) => setState(() => selected = i),
            ),
          ),
        ),
      ),
    );
    Color? colorOf(String label) =>
        tester.widget<Text>(find.text(label)).style?.color;
    expect(colorOf('专项复习'), Colors.white);
    await tester.tap(find.text('错题列表'));
    await tester.pumpAndSettle();
    expect(selected, 1);
    expect(colorOf('错题列表'), Colors.white);
    expect(colorOf('专项复习'), AppTheme.roadInk);
  });

  group('QuestionWidget road answers', () {
    late Question question;
    setUpAll(() {
      question = _fixture('test/fixtures/l10n_sample_question.json');
    });

    Future<void> pumpAnswered(WidgetTester tester, {required bool correct}) {
      SharedPreferences.setMockInitialValues({'current_language': 'zh'});
      final pick = correct ? question.answer : !question.answer;
      return tester.pumpWidget(
        ChangeNotifierProvider<UserStateProvider>.value(
          value: UserStateProvider(),
          child: MaterialApp(
            theme: AppTheme.lightTheme(language: 'zh'),
            home: Scaffold(
              body: QuestionWidget(
                question: question,
                currentLanguage: 'zh',
                onAnswerSelected: (_) {},
                isAnswered: true,
                isCorrect: correct,
                userChoice: pick,
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('a wrong pick shows the right answer without extra taps',
        (tester) async {
      await pumpAnswered(tester, correct: false);
      await tester.pump(const Duration(milliseconds: 400));

      final answer = question.answer ? 'VERO' : 'FALSO';
      expect(find.text('差一点！答案是 $answer'), findsOneWidget);
      expect(find.byIcon(Icons.check_rounded), findsOneWidget);
      expect(find.byIcon(Icons.close_rounded), findsOneWidget);
      // 反饋層不提供「下一題」按鈕：跳題交給練習頁的自動前進。
      expect(find.text('下一题'), findsNothing);
    });

    testWidgets('streak chip grows with the streak', (tester) async {
      SharedPreferences.setMockInitialValues({'current_language': 'zh'});
      for (final (streak, tier) in [(2, 0), (4, 1), (6, 2), (12, 3)]) {
        await tester.pumpWidget(
          ChangeNotifierProvider<UserStateProvider>.value(
            value: UserStateProvider(),
            child: MaterialApp(
              theme: AppTheme.lightTheme(language: 'zh'),
              home: Scaffold(
                body: QuestionWidget(
                  key: ValueKey(streak),
                  question: question,
                  currentLanguage: 'zh',
                  onAnswerSelected: (_) {},
                  isAnswered: true,
                  isCorrect: true,
                  userChoice: question.answer,
                  sessionCorrectStreak: streak,
                ),
              ),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 600));
        expect(find.byKey(ValueKey('streak-chip-tier-$tier')), findsOneWidget,
            reason: 'streak $streak');
      }
    });

    testWidgets('a correct pick marks only that option', (tester) async {
      await pumpAnswered(tester, correct: true);
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byIcon(Icons.check_rounded), findsOneWidget);
      expect(find.byIcon(Icons.close_rounded), findsNothing);
    });
  });

  group('MockTestResultScreen road layout', () {
    Widget screen({required int errors, int timeRemaining = 600}) {
      return MaterialApp(
        theme: AppTheme.lightTheme(language: 'zh'),
        home: MockTestResultScreen(
          totalQuestions: 30,
          correctAnswers: 30 - errors,
          errors: errors,
          isPassed: errors <= 3,
          timeRemaining: timeRemaining,
          errorIds: List.generate(errors, (i) => '$i'),
          questions: const [],
          userChoices: const {},
        ),
      );
    }

    testWidgets('a pass shows the practice licence and stickers',
        (tester) async {
      await tester.pumpWidget(screen(errors: 0, timeRemaining: 1200));
      await tester.pump();

      expect(find.byKey(const Key('mock_result_license_card')), findsOneWidget);
      expect(find.text('PATENTE DI GUIDA'), findsOneWidget);
      expect(find.text('30 / 30'), findsOneWidget);
      expect(find.text('零失误'), findsOneWidget);
      expect(find.text('又快又准'), findsOneWidget);
    });

    testWidgets('a fail stays gentle and has no licence', (tester) async {
      await tester.pumpWidget(screen(errors: 5));
      await tester.pump();

      expect(find.byKey(const Key('mock_result_license_card')), findsNothing);
      expect(find.byKey(const Key('mock_result_stickers')), findsNothing);
      expect(find.textContaining('错题，下次就能过'), findsOneWidget);
    });

    testWidgets('NON IDONEO stays on one line on a 360dp phone',
        (tester) async {
      tester.view.physicalSize = const Size(360, 780);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(screen(errors: 6));
      await tester.pump();

      final headline = tester.widget<Text>(find.text('NON IDONEO'));
      expect(headline.maxLines, 1);
      expect(
        find.ancestor(
            of: find.text('NON IDONEO'), matching: find.byType(FittedBox)),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('a failed rating uses the warning color, not green',
        (tester) async {
      await tester.pumpWidget(screen(errors: 6));
      await tester.pump();

      final rating =
          tester.widget<Text>(find.text(AppStrings.get('keep_trying')));
      expect(rating.style?.color, AppTheme.roadDanger);
    });
  });

  testWidgets('exam review frames wrong answers and badges the wrong pick',
      (tester) async {
    SharedPreferences.setMockInitialValues({'current_language': 'zh'});
    final question = _fixture('test/fixtures/l10n_sample_question.json');
    await tester.pumpWidget(
      ChangeNotifierProvider<UserStateProvider>.value(
        value: UserStateProvider(),
        child: MaterialApp(
          theme: AppTheme.lightTheme(language: 'zh'),
          home: ExamReviewScreen(
            questions: [question, question],
            userChoices: {0: !question.answer, 1: question.answer},
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byKey(const Key('exam_review_wrong_0')), findsOneWidget);
    expect(find.byKey(const Key('exam_review_wrong_1')), findsNothing);
    expect(find.byKey(const Key('exam_review_wrong_pick')), findsOneWidget);
  });
}

Question _fixture(String path) {
  final q = (jsonDecode(File(path).readAsStringSync())
      as Map<String, dynamic>)['question'] as Map<String, dynamic>;
  return Question(
    id: q['id'] as String,
    imageName: q['image_name'] as String?,
    answer: q['answer'] as bool,
    translations: Map<String, String>.from(q['translations'] as Map),
    explanations: Map<String, String>.from(q['explanations'] as Map),
    keywordsJson: q['keywords_json'] as String?,
  );
}
