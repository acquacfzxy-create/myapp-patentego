import 'package:flutter_test/flutter_test.dart';
import 'package:lingua_patente/repositories/web_exam_history_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('persists exam history locally in newest-first order', () async {
    final preferences = await SharedPreferences.getInstance();
    final repository = WebExamHistoryRepository(preferences: preferences);
    await repository.initialize();
    await repository.addAttempt(_attempt('first', 1000, passed: false));
    await repository.addAttempt(_attempt('second', 2000, passed: true));

    final restored = WebExamHistoryRepository(preferences: preferences);
    await restored.initialize();

    expect(restored.attempts.map((item) => item.id), ['second', 'first']);
    expect(restored.attempts.first.passed, isTrue);
  });

  test('active exam session survives repository recreation and can clear',
      () async {
    final preferences = await SharedPreferences.getInstance();
    final repository = WebExamHistoryRepository(preferences: preferences);
    await repository.initialize();
    await repository.saveSession({
      'schema_version': 1,
      'question_ids': List.generate(30, (index) => '$index'),
    });

    final restored = WebExamHistoryRepository(preferences: preferences);
    await restored.initialize();
    expect((await restored.loadSession())?['schema_version'], 1);

    await restored.clearSession();
    expect(await restored.loadSession(), isNull);
  });
}

WebExamAttempt _attempt(String id, int completedAt, {required bool passed}) {
  return WebExamAttempt(
    id: id,
    completedAtMs: completedAt,
    totalQuestions: 30,
    correctCount: passed ? 27 : 20,
    wrongCount: passed ? 3 : 10,
    timeUsedSeconds: 600,
    passed: passed,
    questionIds: List.generate(30, (index) => '$index'),
    selectedAnswers: const {'0': true},
  );
}
