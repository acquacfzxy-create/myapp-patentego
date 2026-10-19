import 'package:flutter_test/flutter_test.dart';
import 'package:lingua_patente/models/chapter_strengthening_plan.dart';

ChapterStrengtheningCandidate _candidate(
  String id, {
  int wrongCount = 0,
  bool isMastered = false,
  int totalAttempts = 0,
  int lastPracticed = 0,
}) {
  return ChapterStrengtheningCandidate(
    questionId: id,
    wrongCount: wrongCount,
    isMastered: isMastered,
    totalAttempts: totalAttempts,
    lastPracticed: lastPracticed,
  );
}

void main() {
  test('orders mistakes, learning, unseen, then mastered questions', () {
    final plan = buildChapterStrengtheningPlan([
      _candidate('mastered', isMastered: true, totalAttempts: 4),
      _candidate('unseen'),
      _candidate('learning', totalAttempts: 2),
      _candidate('wrong', wrongCount: 1, totalAttempts: 2),
    ]);

    expect(plan, ['wrong', 'learning', 'unseen', 'mastered']);
  });

  test('prioritizes higher wrong counts and older practice within a group', () {
    final plan = buildChapterStrengtheningPlan([
      _candidate('recent', wrongCount: 1, lastPracticed: 200),
      _candidate('older', wrongCount: 1, lastPracticed: 100),
      _candidate('more-wrong', wrongCount: 3, lastPracticed: 300),
    ]);

    expect(plan, ['more-wrong', 'older', 'recent']);
  });

  test('limits the strengthening mission size', () {
    final plan = buildChapterStrengtheningPlan(
      List.generate(12, (index) => _candidate('$index')),
      limit: 10,
    );

    expect(plan, hasLength(10));
  });
}
