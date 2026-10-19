/// Minimal spaced-review rules shared by persistence, planning, and tests.
///
/// A correct answer advances through 3, 7, 14, and 30-day intervals. A wrong
/// answer resets the sequence and makes the question due the following day.
class SpacedReviewSchedule {
  const SpacedReviewSchedule._();

  static const List<int> correctIntervalsDays = <int>[3, 7, 14, 30];
  static const int wrongIntervalDays = 1;
  static const int maxStage = 4;

  static DateTime dateOnly(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  static SpacedReviewState afterAnswer({
    required int currentStage,
    required bool isCorrect,
    DateTime? answeredAt,
  }) {
    final answeredDate = dateOnly(answeredAt ?? DateTime.now());
    if (!isCorrect) {
      return SpacedReviewState(
        stage: 0,
        nextReviewDate:
            answeredDate.add(const Duration(days: wrongIntervalDays)),
      );
    }

    final normalizedStage = currentStage.clamp(0, maxStage).toInt();
    final nextStage = (normalizedStage + 1).clamp(1, maxStage).toInt();
    final intervalDays = correctIntervalsDays[nextStage - 1];
    return SpacedReviewState(
      stage: nextStage,
      nextReviewDate: answeredDate.add(Duration(days: intervalDays)),
    );
  }

  static int toEpochSeconds(DateTime value) =>
      value.millisecondsSinceEpoch ~/ Duration.millisecondsPerSecond;

  /// Rebuilds a due date from fields already supported by older cloud clients.
  /// This keeps cross-device progress compatible without requiring a rules
  /// rollout before the app update reaches users.
  static DateTime nextReviewDateForStage({
    required int stage,
    required DateTime lastPracticedAt,
  }) {
    final normalizedStage = stage.clamp(0, maxStage).toInt();
    final intervalDays = normalizedStage == 0
        ? wrongIntervalDays
        : correctIntervalsDays[normalizedStage - 1];
    return dateOnly(lastPracticedAt).add(Duration(days: intervalDays));
  }

  static int dueAtStartOfDayEpochSeconds([DateTime? now]) =>
      toEpochSeconds(dateOnly(now ?? DateTime.now()));
}

class SpacedReviewState {
  const SpacedReviewState({
    required this.stage,
    required this.nextReviewDate,
  });

  final int stage;
  final DateTime nextReviewDate;

  int get nextReviewAtEpochSeconds =>
      SpacedReviewSchedule.toEpochSeconds(nextReviewDate);
}
