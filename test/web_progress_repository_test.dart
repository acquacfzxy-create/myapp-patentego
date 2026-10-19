import 'package:flutter_test/flutter_test.dart';
import 'package:lingua_patente/repositories/web_progress_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('records answers and restores progress from browser storage', () async {
    final preferences = await SharedPreferences.getInstance();
    final first = WebProgressRepository(preferences: preferences);
    await first.initialize();

    await first.recordAnswer('5', isCorrect: false);
    await first.recordAnswer('5', isCorrect: true);

    final restored = WebProgressRepository(preferences: preferences);
    await restored.initialize();
    final progress = restored.progressFor('5');
    expect(progress.totalAttempts, 2);
    expect(progress.wrongCount, 0);
    expect(progress.correctStreak, 1);
    expect(restored.attemptedCount, 1);
    expect(restored.mistakeCount, 0);
  });

  test('reports guest progress without requiring authentication', () async {
    final preferences = await SharedPreferences.getInstance();
    final repository = WebProgressRepository(preferences: preferences);
    await repository.initialize();

    expect(repository.hasGuestProgress, isFalse);

    await repository.recordAnswer('guest-question', isCorrect: false);

    expect(repository.hasGuestProgress, isTrue);
  });

  test('guest merge is a no-op while signed out and keeps guest data',
      () async {
    final preferences = await SharedPreferences.getInstance();
    final repository = WebProgressRepository(preferences: preferences);
    await repository.initialize();
    await repository.recordAnswer('guest-question', isCorrect: false);

    await repository.mergeGuestIntoCurrentUser();

    expect(repository.hasGuestProgress, isTrue);
    expect(repository.progressFor('guest-question').wrongCount, 1);
  });

  test('marks a question mastered after three correct answers', () {
    var progress = const WebQuestionProgress(questionId: '7');
    progress = progress.recordAnswer(true, 1);
    progress = progress.recordAnswer(true, 2);
    progress = progress.recordAnswer(true, 3);

    expect(progress.correctStreak, 3);
    expect(progress.isMastered, isTrue);
  });

  test('correct answers reduce wrong count while building the streak', () {
    const progress = WebQuestionProgress(
      questionId: '8',
      correctStreak: 2,
      wrongCount: 2,
      totalAttempts: 4,
      lastPracticedMs: 100,
    );

    final updated = progress.recordAnswer(true, 200);

    expect(updated.correctStreak, 3);
    expect(updated.wrongCount, 1);
    expect(updated.totalAttempts, 5);
    expect(updated.isMastered, isTrue);
  });

  test('a wrong answer revokes mastery and resets the streak', () {
    const progress = WebQuestionProgress(
      questionId: '9',
      correctStreak: 3,
      wrongCount: 0,
      totalAttempts: 3,
      isMastered: true,
      lastPracticedMs: 100,
    );

    final updated = progress.recordAnswer(false, 200);

    expect(updated.correctStreak, 0);
    expect(updated.wrongCount, 1);
    expect(updated.totalAttempts, 4);
    expect(updated.isMastered, isFalse);
  });

  test('exam mistakes enter the same mistake queue as practice answers',
      () async {
    final preferences = await SharedPreferences.getInstance();
    final repository = WebProgressRepository(preferences: preferences);
    await repository.initialize();

    final progress = await repository.recordExamMistake('exam-1');

    expect(progress.wrongCount, 1);
    expect(progress.totalAttempts, 1);
    expect(repository.mistakeCount, 1);
  });

  test('clearing a mistake preserves attempts and favorite state', () async {
    final preferences = await SharedPreferences.getInstance();
    final repository = WebProgressRepository(preferences: preferences);
    await repository.initialize();
    await repository.toggleFavorite('mistake-1');
    await repository.recordAnswer('mistake-1', isCorrect: false);

    final cleared = await repository.clearMistake('mistake-1');

    expect(cleared.wrongCount, 0);
    expect(cleared.totalAttempts, 1);
    expect(cleared.isFavorite, isTrue);
    expect(repository.mistakeCount, 0);
  });

  test('clears all guest progress from memory and browser storage', () async {
    final preferences = await SharedPreferences.getInstance();
    final repository = WebProgressRepository(preferences: preferences);
    await repository.initialize();
    await repository.recordAnswer('question-1', isCorrect: false);
    await repository.toggleFavorite('question-2');

    await repository.clearAllProgress();

    expect(repository.records, isEmpty);
    expect(repository.hasGuestProgress, isFalse);
    final restored = WebProgressRepository(preferences: preferences);
    await restored.initialize();
    expect(restored.records, isEmpty);
  });

  test('merge uses the newer mutable state and preserves favorite/max attempts',
      () {
    const local = WebQuestionProgress(
      questionId: '8',
      correctStreak: 3,
      wrongCount: 2,
      totalAttempts: 3,
      isMastered: true,
      isFavorite: false,
      lastPracticedMs: 100,
    );
    const cloud = WebQuestionProgress(
      questionId: '8',
      correctStreak: 1,
      wrongCount: 0,
      totalAttempts: 5,
      isMastered: false,
      isFavorite: true,
      lastPracticedMs: 200,
    );

    final merged = WebQuestionProgress.merge(local, cloud);
    expect(merged.correctStreak, 1);
    expect(merged.wrongCount, 0);
    expect(merged.totalAttempts, 5);
    expect(merged.isMastered, isFalse);
    expect(merged.isFavorite, isTrue);
    expect(merged.lastPracticedMs, 200);
  });

  test('merge tie deterministically favors local mutable state', () {
    const local = WebQuestionProgress(
      questionId: '10',
      correctStreak: 1,
      wrongCount: 0,
      totalAttempts: 4,
      lastPracticedMs: 300,
    );
    const cloud = WebQuestionProgress(
      questionId: '10',
      correctStreak: 0,
      wrongCount: 4,
      totalAttempts: 5,
      lastPracticedMs: 300,
    );

    final merged = WebQuestionProgress.merge(local, cloud);

    expect(merged.correctStreak, 1);
    expect(merged.wrongCount, 0);
    expect(merged.totalAttempts, 5);
  });

  test('guest merge adds counters but uses the latest guest state on a tie',
      () {
    const account = WebQuestionProgress(
      questionId: '11',
      correctStreak: 3,
      wrongCount: 1,
      totalAttempts: 4,
      isMastered: true,
      isFavorite: false,
      lastPracticedMs: 500,
    );
    const guest = WebQuestionProgress(
      questionId: '11',
      correctStreak: 0,
      wrongCount: 2,
      totalAttempts: 3,
      isMastered: false,
      isFavorite: true,
      lastPracticedMs: 500,
    );

    final merged = WebQuestionProgress.mergeGuest(account, guest);

    expect(merged.correctStreak, 0);
    expect(merged.wrongCount, 3);
    expect(merged.totalAttempts, 7);
    expect(merged.isMastered, isFalse);
    expect(merged.isFavorite, isTrue);
    expect(merged.lastPracticedMs, 500);
  });
}
