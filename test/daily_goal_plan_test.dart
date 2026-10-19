import 'package:flutter_test/flutter_test.dart';
import 'package:lingua_patente/models/daily_goal_plan.dart';

void main() {
  group('DailyGoalPlan', () {
    test('calculates one- and two-month full-bank goals', () {
      expect(
        DailyGoalPlan.goalForDuration(
          remainingQuestions: 7139,
          days: 30,
        ),
        238,
      );
      expect(
        DailyGoalPlan.goalForDuration(
          remainingQuestions: 7139,
          days: 60,
        ),
        119,
      );
    });

    test('uses only remaining questions for an updated plan', () {
      expect(DailyGoalPlan.remainingQuestions(1139), 6000);
      expect(
        DailyGoalPlan.goalForDuration(
          remainingQuestions: 6000,
          days: 60,
        ),
        100,
      );
    });

    test('estimates completion days and handles a finished bank', () {
      expect(
        DailyGoalPlan.estimatedDays(
          remainingQuestions: 7139,
          dailyGoal: 238,
        ),
        30,
      );
      expect(
        DailyGoalPlan.estimatedDays(
          remainingQuestions: 0,
          dailyGoal: 30,
        ),
        0,
      );
    });

    test('keeps custom goals within meaningful bounds', () {
      expect(DailyGoalPlan.normalizeGoal(1), 10);
      expect(DailyGoalPlan.normalizeGoal(238), 238);
      expect(DailyGoalPlan.normalizeGoal(9000), 7139);
    });

    test('splits a daily goal into new and review work by coverage stage', () {
      final early = DailyGoalPlan.allocateTotalGoal(
        totalGoal: 100,
        remainingQuestions: 6000,
        attemptedQuestions: 1139,
        today: DateTime(2026, 8, 12),
      );
      final late = DailyGoalPlan.allocateTotalGoal(
        totalGoal: 100,
        remainingQuestions: 700,
        attemptedQuestions: 6439,
        today: DateTime(2026, 8, 12),
      );

      expect((early.newGoal, early.reviewGoal), (80, 20));
      expect((late.newGoal, late.reviewGoal), (30, 70));
    });

    test('recalculates remaining daily work against a fixed target date', () {
      final plan = DailyGoalPlan.recalculateForTarget(
        remainingQuestions: 600,
        attemptedQuestions: 1000,
        targetDate: DateTime(2026, 8, 17),
        fallbackTotalGoal: 100,
        today: DateTime(2026, 8, 12),
      );

      expect(plan.daysRemaining, 6);
      expect(plan.newGoal, 100);
      expect(plan.reviewGoal, 25);
      expect(plan.totalGoal, 125);
    });

    test('derives a completion date from productive new-question work', () {
      final target = DailyGoalPlan.targetDateForTotalGoal(
        remainingQuestions: 800,
        attemptedQuestions: 1000,
        totalGoal: 100,
        today: DateTime(2026, 8, 12),
      );

      expect(target, DateTime(2026, 8, 21));
    });

    test('uses only due reviews and shifts unused slots to new questions', () {
      final base = DailyGoalPlan.allocateTotalGoal(
        totalGoal: 30,
        remainingQuestions: 6000,
        attemptedQuestions: 1139,
        today: DateTime(2026, 8, 31),
      );
      final constrained = DailyGoalPlan.constrainToDueReviews(
        plan: base,
        dueReviewCount: 2,
        completedReviewCount: 0,
        remainingQuestions: 6000,
      );

      expect((base.newGoal, base.reviewGoal), (24, 6));
      expect((constrained.newGoal, constrained.reviewGoal), (28, 2));
      expect(constrained.totalGoal, 30);
    });

    test('completed due reviews keep todays review target stable', () {
      final base = DailyPlanAllocation(
        newGoal: 24,
        reviewGoal: 6,
        targetDate: DateTime(2026, 9, 1),
        daysRemaining: 2,
        reviewRatio: 0.2,
      );
      final constrained = DailyGoalPlan.constrainToDueReviews(
        plan: base,
        dueReviewCount: 4,
        completedReviewCount: 2,
        remainingQuestions: 6000,
      );

      expect(constrained.reviewGoal, 6);
      expect(constrained.newGoal, 24);
    });

    test('keeps dynamic new and review targets within the daily total', () {
      final plan = DailyGoalPlan.constrainToTotalGoal(
        plan: DailyPlanAllocation(
          newGoal: 25,
          reviewGoal: 6,
          targetDate: DateTime(2026, 10, 1),
          daysRemaining: 31,
          reviewRatio: 0.2,
        ),
        totalGoal: 30,
      );

      expect(plan.newGoal, 25);
      expect(plan.reviewGoal, 5);
      expect(plan.totalGoal, 30);
    });

    test('caps an overdue new-question target at the daily capacity', () {
      final plan = DailyGoalPlan.constrainToTotalGoal(
        plan: DailyPlanAllocation(
          newGoal: 36,
          reviewGoal: 7,
          targetDate: DateTime(2026, 9, 1),
          daysRemaining: 1,
          reviewRatio: 0.2,
        ),
        totalGoal: 30,
      );

      expect(plan.newGoal, 30);
      expect(plan.reviewGoal, 0);
      expect(plan.totalGoal, 30);
    });
  });
}
