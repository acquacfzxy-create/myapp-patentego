import 'package:flutter_test/flutter_test.dart';
import 'package:lingua_patente/services/web_exam_session.dart';

void main() {
  final ids = List.generate(40, (index) => 'q$index');
  final correctAnswers = {for (final id in ids) id: true};
  final start = DateTime.utc(2026, 8, 12, 12);

  WebExamSession create({int seed = 7}) => WebExamSession.create(
        questionIds: [...ids, 'q1'],
        correctAnswers: correctAnswers,
        actorId: 'user-1',
        dataVersion: 8,
        now: start,
        randomSeed: seed,
      );

  group('WebExamSession', () {
    test('selects exactly 30 stable unique questions', () {
      final first = create();
      final second = create();

      expect(first.questionIds, hasLength(30));
      expect(first.questionIds.toSet(), hasLength(30));
      expect(first.questionIds, second.questionIds);
      expect(
        () => WebExamSession.create(
          questionIds: ids.take(29),
          correctAnswers: correctAnswers,
          actorId: 'user-1',
          dataVersion: 8,
          now: start,
        ),
        throwsArgumentError,
      );
    });

    test('answers can be changed before submission', () {
      final session = create();
      final id = session.currentQuestionId;

      session.selectCurrentAnswer(false, now: start);
      expect(session.answerFor(id), isFalse);
      session.selectAnswer(id, true,
          now: start.add(const Duration(minutes: 1)));
      expect(session.answerFor(id), isTrue);
      expect(session.answeredCount, 1);
      expect(session.unansweredCount, 29);
    });

    test('unanswered questions are wrong and three wrong still passes', () {
      final passing = create();
      for (final id in passing.questionIds.take(27)) {
        passing.selectAnswer(id, true, now: start);
      }
      final passingResult = passing.submit(now: start);
      expect(passingResult.correctCount, 27);
      expect(passingResult.unansweredCount, 3);
      expect(passingResult.wrongCount, 3);
      expect(passingResult.passed, isTrue);

      final failing = create(seed: 8);
      for (final id in failing.questionIds.take(26)) {
        failing.selectAnswer(id, true, now: start);
      }
      final failingResult = failing.submit(now: start);
      expect(failingResult.wrongCount, 4);
      expect(failingResult.passed, isFalse);
    });

    test('countdown expires at 20 minutes and locks answers', () {
      final session = create();

      expect(session.remainingSeconds(start), 1200);
      expect(
        session.remainingSeconds(
          start.add(const Duration(milliseconds: 1199500)),
        ),
        1,
      );
      expect(
        session.isExpired(start.add(const Duration(minutes: 20))),
        isTrue,
      );
      expect(
        () => session.selectCurrentAnswer(
          true,
          now: start.add(const Duration(minutes: 20)),
        ),
        throwsStateError,
      );
    });

    test('map round-trip restores order, navigation and answers', () {
      final session = create();
      session.selectCurrentAnswer(true, now: start);
      session.goToIndex(12);

      final restored = WebExamSession.fromMap(
        session.toMap(),
        expectedActorId: 'user-1',
        expectedDataVersion: 8,
        correctAnswers: correctAnswers,
      );

      expect(restored.questionIds, session.questionIds);
      expect(restored.currentIndex, 12);
      expect(restored.selectedAnswers, session.selectedAnswers);
      expect(restored.deadlineMs, session.deadlineMs);
      expect(restored.randomSeed, session.randomSeed);
    });

    test('restore validates actor, data version and session shape', () {
      final map = create().toMap();

      expect(
        WebExamSession.tryRestore(
          map,
          expectedActorId: 'other-user',
          expectedDataVersion: 8,
          correctAnswers: correctAnswers,
        ),
        isNull,
      );
      expect(
        WebExamSession.tryRestore(
          map,
          expectedActorId: 'user-1',
          expectedDataVersion: 9,
          correctAnswers: correctAnswers,
        ),
        isNull,
      );

      final duplicateIds = Map<String, dynamic>.from(map)
        ..['question_ids'] = List.filled(30, 'q1');
      expect(
        WebExamSession.tryRestore(
          duplicateIds,
          expectedActorId: 'user-1',
          expectedDataVersion: 8,
          correctAnswers: correctAnswers,
        ),
        isNull,
      );
    });

    test('submitted result survives restoration and remains locked', () {
      final session = create();
      session.selectCurrentAnswer(true, now: start);
      final original =
          session.submit(now: start.add(const Duration(minutes: 2)));

      final restored = WebExamSession.fromMap(
        session.toMap(),
        expectedActorId: 'user-1',
        expectedDataVersion: 8,
        correctAnswers: correctAnswers,
      );

      expect(restored.isSubmitted, isTrue);
      expect(restored.result!.correctCount, original.correctCount);
      expect(
        () => restored.selectCurrentAnswer(
          false,
          now: start.add(const Duration(minutes: 3)),
        ),
        throwsStateError,
      );
    });
  });
}
