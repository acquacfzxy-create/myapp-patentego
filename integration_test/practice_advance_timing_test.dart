import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lingua_patente/config/app_locales.dart';
import 'package:lingua_patente/config/app_strings.dart';
import 'package:lingua_patente/config/app_theme.dart';
import 'package:lingua_patente/providers/user_state_provider.dart';
import 'package:lingua_patente/screens/practice_screen.dart';
import 'package:lingua_patente/services/database_service.dart';
import 'package:lingua_patente/widgets/question_widget.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 练习模式切题计时：按下 VERO/FALSO → 对错反馈出现 → 下一题出现。
/// 用真实题库与进度库在设备上量真实耗时，结果以 PRACTICE_TIMING 打印。
/// --dart-define=PRACTICE_TIMING_THEME=light|dark|retro（默认 light）
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('practice answer-to-next-question timing', (tester) async {
    SharedPreferences.setMockInitialValues({'current_language': 'zh'});
    await DatabaseService.init();
    final seeds = await DatabaseService.getQuestions(lang: 'it', limit: 9);
    final questions = (await Future.wait(seeds.map((question) =>
            DatabaseService.getQuestionWithTranslation(question.id))))
        .map((question) => question!)
        .toList();
    final provider = UserStateProvider();
    await provider.changeLanguage('zh');
    AppStrings.setLanguage('zh');
    final theme = switch (const String.fromEnvironment('PRACTICE_TIMING_THEME')) {
      'dark' => AppTheme.darkTheme(language: 'zh'),
      'retro' => AppTheme.retroTheme(language: 'zh'),
      _ => AppTheme.lightTheme(language: 'zh'),
    };
    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: provider,
      child: MaterialApp(
        locale: AppLocales.localeFor('zh'),
        supportedLocales: AppLocales.supportedLocales,
        localizationsDelegates: AppLocales.delegates,
        theme: theme,
        home: Scaffold(
          body: Center(
            child: Builder(
              builder: (context) => TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => PracticeScreen(questions: questions),
                  ),
                ),
                child: const Text('start'),
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.text('start'));
    await tester.pump(const Duration(seconds: 1));

    QuestionWidget card() =>
        tester.widget<QuestionWidget>(find.byType(QuestionWidget));

    final results = <String>[];
    // 交替答对、答错；最后一题会进入结算，不计时。
    for (var i = 0; i < questions.length - 1; i++) {
      final question = card().question;
      final correct = i.isEven;
      final choice = correct ? question.answer : !question.answer;
      final stopwatch = Stopwatch()..start();
      await tester.tap(find.text(choice ? 'VERO' : 'FALSO'));
      int? feedbackMs;
      while (stopwatch.elapsedMilliseconds < 6000) {
        await tester.pump(const Duration(milliseconds: 8));
        final current = card();
        if (feedbackMs == null && current.isAnswered) {
          feedbackMs = stopwatch.elapsedMilliseconds;
        }
        if (current.question.id != question.id) break;
      }
      final nextMs = stopwatch.elapsedMilliseconds;
      expect(card().question.id, isNot(question.id));
      results.add('${correct ? 'correct' : 'wrong'} '
          'feedback=${feedbackMs}ms next=${nextMs}ms');
      // 新题渲染稳定后再答下一题。
      await tester.pump(const Duration(milliseconds: 300));
    }
    for (final line in results) {
      debugPrint('PRACTICE_TIMING $line');
    }
    expect(tester.takeException(), isNull);
  });
}
