import 'package:flutter_test/flutter_test.dart';
import 'package:lingua_patente/models/web_practice_mode.dart';
import 'package:lingua_patente/services/web_practice_session.dart';

void main() {
  group('WebPracticeSession', () {
    test('random order is unique and stable for the same seed', () {
      final first = WebPracticeSession.create(
        mode: WebPracticeMode.random,
        questionIds: ['1', '2', '2', '3', '4', '5'],
        actorId: 'guest_user',
        dataVersion: 8,
        randomSeed: 42,
      );
      final second = WebPracticeSession.create(
        mode: WebPracticeMode.random,
        questionIds: ['1', '2', '2', '3', '4', '5'],
        actorId: 'guest_user',
        dataVersion: 8,
        randomSeed: 42,
      );

      expect(first.questionIds, second.questionIds);
      expect(first.questionIds.toSet(), {'1', '2', '3', '4', '5'});
      expect(first.questionIds, hasLength(5));
    });

    test('chapter and mistake modes preserve the supplied order', () {
      for (final mode in [WebPracticeMode.chapter, WebPracticeMode.mistakes]) {
        final session = WebPracticeSession.create(
          mode: mode,
          questionIds: [' 3 ', '1', '', '3', '2'],
          actorId: 'user-1',
          dataVersion: 8,
        );
        expect(session.questionIds, ['3', '1', '2']);
      }
    });

    test('each question accepts one answer and reports progress inputs', () {
      final session = WebPracticeSession.create(
        mode: WebPracticeMode.chapter,
        questionIds: ['1', '2'],
        actorId: 'user-1',
        dataVersion: 8,
      );

      final result = session.answerCurrent(
        isCorrect: true,
        becameMastered: true,
        mistakeResolved: true,
      );

      expect(result.answer.questionId, '1');
      expect(result.recommendedNextIndex, 1);
      expect(result.stats.answeredCount, 1);
      expect(result.stats.correctCount, 1);
      expect(result.stats.wrongCount, 0);
      expect(result.stats.newlyMasteredCount, 1);
      expect(result.stats.mistakesResolvedCount, 1);
      expect(result.stats.accuracy, 1);
      expect(
        () => session.answerCurrent(isCorrect: false),
        throwsStateError,
      );
    });

    test('recommended next question wraps and completion returns null', () {
      final session = WebPracticeSession.create(
        mode: WebPracticeMode.mistakes,
        questionIds: ['1', '2', '3'],
        actorId: 'user-1',
        dataVersion: 8,
      );
      session.goToIndex(2);
      expect(
        session.answerCurrent(isCorrect: false).recommendedNextIndex,
        0,
      );
      session.goToIndex(0);
      session.answerCurrent(isCorrect: true);
      session.goToIndex(1);
      final last = session.answerCurrent(isCorrect: false);

      expect(last.recommendedNextIndex, isNull);
      expect(last.stats.isComplete, isTrue);
      expect(last.stats.correctCount, 1);
      expect(last.stats.wrongCount, 2);
    });

    test('navigation is bounded and empty sessions cannot be answered', () {
      final empty = WebPracticeSession.create(
        mode: WebPracticeMode.mistakes,
        questionIds: const [],
        actorId: 'user-1',
        dataVersion: 8,
      );
      expect(empty.currentQuestionId, isNull);
      expect(
        () => empty.answerCurrent(isCorrect: true),
        throwsStateError,
      );

      final session = WebPracticeSession.create(
        mode: WebPracticeMode.chapter,
        questionIds: ['1', '2'],
        actorId: 'user-1',
        dataVersion: 8,
      );
      expect(session.movePrevious(), isFalse);
      expect(session.moveNext(), isTrue);
      expect(session.moveNext(), isFalse);
      expect(() => session.goToIndex(2), throwsRangeError);
    });

    test('mode parser rejects unknown storage values', () {
      expect(webPracticeModeFromName('random'), WebPracticeMode.random);
      expect(webPracticeModeFromName('unknown'), isNull);
      expect(webPracticeModeFromName(null), isNull);
    });
  });
}
