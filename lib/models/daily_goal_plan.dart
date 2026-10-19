import 'dart:math';

/// Pure study-plan calculations shared by onboarding, settings, and tests.
class DailyGoalPlan {
  const DailyGoalPlan._();

  static const int totalQuestions = 7139;
  static const int minDailyGoal = 10;
  static const int maxDailyGoal = totalQuestions;
  static const int sliderMaxGoal = 300;
  static const int habitMinimumQuestions = 10;
  static const List<int> suggestedDurations = <int>[30, 60, 90, 180];

  static DateTime dateOnly(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  static int normalizeGoal(int goal) {
    return goal.clamp(minDailyGoal, maxDailyGoal).toInt();
  }

  static int remainingQuestions(int attemptedQuestions) {
    return (totalQuestions - attemptedQuestions)
        .clamp(0, totalQuestions)
        .toInt();
  }

  static int goalForDuration({
    required int remainingQuestions,
    required int days,
  }) {
    if (days <= 0) throw ArgumentError.value(days, 'days');
    if (remainingQuestions <= 0) return minDailyGoal;
    return normalizeGoal((remainingQuestions / days).ceil());
  }

  static int estimatedDays({
    required int remainingQuestions,
    required int dailyGoal,
  }) {
    if (remainingQuestions <= 0) return 0;
    return max(1, (remainingQuestions / normalizeGoal(dailyGoal)).ceil());
  }

  /// Review grows as the learner moves from coverage to consolidation.
  static double reviewRatioForCoverage({
    required int attemptedQuestions,
  }) {
    final coverage =
        attemptedQuestions.clamp(0, totalQuestions) / totalQuestions;
    if (coverage < 0.5) return 0.2;
    if (coverage < 0.85) return 0.3;
    return 0.7;
  }

  static DailyPlanAllocation allocateTotalGoal({
    required int totalGoal,
    required int remainingQuestions,
    required int attemptedQuestions,
    DateTime? targetDate,
    DateTime? today,
  }) {
    final normalizedTotal = normalizeGoal(totalGoal);
    final availableNew = remainingQuestions.clamp(0, totalQuestions).toInt();
    final availableReview = attemptedQuestions.clamp(0, totalQuestions).toInt();
    final reviewRatio = reviewRatioForCoverage(
      attemptedQuestions: attemptedQuestions,
    );

    var reviewGoal = availableReview == 0
        ? 0
        : max(1, (normalizedTotal * reviewRatio).round());
    reviewGoal = min(reviewGoal, availableReview);
    var newGoal = min(availableNew, normalizedTotal - reviewGoal);

    if (newGoal == 0 && availableNew > 0) {
      newGoal = min(availableNew, normalizedTotal);
      reviewGoal = min(availableReview, normalizedTotal - newGoal);
    } else if (availableNew == 0) {
      reviewGoal = min(availableReview, normalizedTotal);
    }

    final effectiveToday = dateOnly(today ?? DateTime.now());
    final effectiveTarget = targetDate == null
        ? effectiveToday.add(
            Duration(
              days: max(
                  0,
                  estimatedDays(
                        remainingQuestions: availableNew,
                        dailyGoal: max(1, newGoal),
                      ) -
                      1),
            ),
          )
        : dateOnly(targetDate);

    return DailyPlanAllocation(
      newGoal: newGoal,
      reviewGoal: reviewGoal,
      targetDate: effectiveTarget,
      daysRemaining:
          max(1, effectiveTarget.difference(effectiveToday).inDays + 1),
      reviewRatio: reviewRatio,
    );
  }

  /// Keeps the daily plan achievable by assigning review work only when it is
  /// due today. Review slots that are not yet due become new-question slots.
  /// Already completed review work is included so the target does not shrink
  /// while the learner progresses through today's session.
  static DailyPlanAllocation constrainToDueReviews({
    required DailyPlanAllocation plan,
    required int dueReviewCount,
    required int completedReviewCount,
    required int remainingQuestions,
  }) {
    final availableDue = max(0, dueReviewCount) + max(0, completedReviewCount);
    final reviewGoal = min(plan.reviewGoal, availableDue).toInt();
    final shiftedReviewSlots = plan.reviewGoal - reviewGoal;
    final newGoal = min(
      max(0, remainingQuestions),
      plan.newGoal + shiftedReviewSlots,
    ).toInt();
    return DailyPlanAllocation(
      newGoal: newGoal,
      reviewGoal: reviewGoal,
      targetDate: plan.targetDate,
      daysRemaining: plan.daysRemaining,
      reviewRatio: plan.reviewRatio,
    );
  }

  /// Keeps the displayed new/review targets within the learner's configured
  /// daily total. New-question work is preserved first because it determines
  /// whether the selected completion date remains achievable.
  static DailyPlanAllocation constrainToTotalGoal({
    required DailyPlanAllocation plan,
    required int totalGoal,
  }) {
    final normalizedTotal = normalizeGoal(totalGoal);
    if (plan.totalGoal <= normalizedTotal) return plan;

    final newGoal = min(plan.newGoal, normalizedTotal).toInt();
    final reviewGoal = min(
      plan.reviewGoal,
      max(0, normalizedTotal - newGoal),
    ).toInt();
    return DailyPlanAllocation(
      newGoal: newGoal,
      reviewGoal: reviewGoal,
      targetDate: plan.targetDate,
      daysRemaining: plan.daysRemaining,
      reviewRatio: plan.reviewRatio,
    );
  }

  /// Recalculates today's work from the remaining unseen questions and the
  /// fixed target date. Missing a day therefore redistributes only the work
  /// that is still outstanding.
  static DailyPlanAllocation recalculateForTarget({
    required int remainingQuestions,
    required int attemptedQuestions,
    required DateTime targetDate,
    required int fallbackTotalGoal,
    DateTime? today,
  }) {
    final effectiveToday = dateOnly(today ?? DateTime.now());
    final effectiveTarget = dateOnly(targetDate);
    final daysRemaining =
        max(1, effectiveTarget.difference(effectiveToday).inDays + 1);
    final availableNew = remainingQuestions.clamp(0, totalQuestions).toInt();
    final availableReview = attemptedQuestions.clamp(0, totalQuestions).toInt();

    if (availableNew == 0) {
      return DailyPlanAllocation(
        newGoal: 0,
        reviewGoal: min(availableReview, normalizeGoal(fallbackTotalGoal)),
        targetDate: effectiveTarget,
        daysRemaining: daysRemaining,
        reviewRatio: 1,
      );
    }

    final newGoal = min(availableNew, (availableNew / daysRemaining).ceil());
    final reviewRatio = reviewRatioForCoverage(
      attemptedQuestions: attemptedQuestions,
    );
    final reviewGoal = availableReview == 0
        ? 0
        : min(
            availableReview,
            max(1, (newGoal * reviewRatio / (1 - reviewRatio)).round()),
          );

    return DailyPlanAllocation(
      newGoal: newGoal,
      reviewGoal: reviewGoal,
      targetDate: effectiveTarget,
      daysRemaining: daysRemaining,
      reviewRatio: reviewRatio,
    );
  }

  static DateTime targetDateForTotalGoal({
    required int remainingQuestions,
    required int attemptedQuestions,
    required int totalGoal,
    DateTime? today,
  }) {
    final effectiveToday = dateOnly(today ?? DateTime.now());
    final allocation = allocateTotalGoal(
      totalGoal: totalGoal,
      remainingQuestions: remainingQuestions,
      attemptedQuestions: attemptedQuestions,
      today: effectiveToday,
    );
    if (remainingQuestions <= 0) return effectiveToday;
    final productiveNewGoal = max(1, allocation.newGoal);
    final days = (remainingQuestions / productiveNewGoal).ceil();
    return effectiveToday.add(Duration(days: max(0, days - 1)));
  }
}

class DailyPlanAllocation {
  const DailyPlanAllocation({
    required this.newGoal,
    required this.reviewGoal,
    required this.targetDate,
    required this.daysRemaining,
    required this.reviewRatio,
  });

  final int newGoal;
  final int reviewGoal;
  final DateTime targetDate;
  final int daysRemaining;
  final double reviewRatio;

  int get totalGoal => newGoal + reviewGoal;
}

class LearningStreakStats {
  const LearningStreakStats({
    required this.current,
    required this.longest,
    required this.activeToday,
  });

  static const empty = LearningStreakStats(
    current: 0,
    longest: 0,
    activeToday: false,
  );

  final int current;
  final int longest;
  final bool activeToday;
}
