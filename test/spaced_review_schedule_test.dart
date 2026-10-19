import 'package:flutter_test/flutter_test.dart';
import 'package:lingua_patente/models/spaced_review_schedule.dart';

void main() {
  group('SpacedReviewSchedule', () {
    final answerDate = DateTime(2026, 8, 31, 22, 45);

    test('correct answers advance through 3, 7, 14, and 30 days', () {
      final expected = <(int, int)>[(1, 3), (2, 7), (3, 14), (4, 30)];

      for (final (stage, days) in expected) {
        final state = SpacedReviewSchedule.afterAnswer(
          currentStage: stage - 1,
          isCorrect: true,
          answeredAt: answerDate,
        );
        expect(state.stage, stage);
        expect(
            state.nextReviewDate,
            DateTime(2026, 8, 31).add(
              Duration(days: days),
            ));
      }
    });

    test('the final stage remains on a thirty-day interval', () {
      final state = SpacedReviewSchedule.afterAnswer(
        currentStage: 4,
        isCorrect: true,
        answeredAt: answerDate,
      );

      expect(state.stage, 4);
      expect(state.nextReviewDate, DateTime(2026, 9, 30));
    });

    test('a wrong answer resets the stage and becomes due tomorrow', () {
      final state = SpacedReviewSchedule.afterAnswer(
        currentStage: 4,
        isCorrect: false,
        answeredAt: answerDate,
      );

      expect(state.stage, 0);
      expect(state.nextReviewDate, DateTime(2026, 9, 1));
    });

    test('all due dates are normalized to local midnight', () {
      final state = SpacedReviewSchedule.afterAnswer(
        currentStage: 0,
        isCorrect: true,
        answeredAt: answerDate,
      );

      expect(state.nextReviewDate.hour, 0);
      expect(state.nextReviewDate.minute, 0);
    });

    test('reconstructs cloud due dates from stage and last practice', () {
      expect(
        SpacedReviewSchedule.nextReviewDateForStage(
          stage: 3,
          lastPracticedAt: answerDate,
        ),
        DateTime(2026, 9, 14),
      );
      expect(
        SpacedReviewSchedule.nextReviewDateForStage(
          stage: 0,
          lastPracticedAt: answerDate,
        ),
        DateTime(2026, 9, 1),
      );
    });
  });
}
