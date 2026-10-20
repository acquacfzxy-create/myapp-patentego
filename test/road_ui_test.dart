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
import 'package:lingua_patente/screens/mock_test_result_screen.dart';
import 'package:lingua_patente/widgets/learning_route_card.dart';
import 'package:lingua_patente/widgets/question_widget.dart';
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
