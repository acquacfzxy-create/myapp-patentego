import 'package:flutter_test/flutter_test.dart';
import 'package:italy_quiz_app/services/access_policy.dart';

void main() {
  group('AccessPolicy', () {
    test('free users can practice until the daily quiz limit', () {
      expect(
        AccessPolicy.canPractice(isVip: false, dailyQuizCount: 29),
        isTrue,
      );
      expect(
        AccessPolicy.canPractice(isVip: false, dailyQuizCount: 30),
        isFalse,
      );
      expect(
        AccessPolicy.canPractice(isVip: true, dailyQuizCount: 300),
        isTrue,
      );
    });

    test('free users can start one mock exam per day', () {
      expect(
        AccessPolicy.canStartExam(isVip: false, isExamUsedToday: false),
        isTrue,
      );
      expect(
        AccessPolicy.canStartExam(isVip: false, isExamUsedToday: true),
        isFalse,
      );
      expect(
        AccessPolicy.canStartExam(isVip: true, isExamUsedToday: true),
        isTrue,
      );
    });

    test('free explanation access respects unlocked questions and daily count',
        () {
      expect(
        AccessPolicy.canViewExplanation(
          isVip: false,
          isUnlockedToday: false,
          dailyExplanationCount: 9,
        ),
        isTrue,
      );
      expect(
        AccessPolicy.canViewExplanation(
          isVip: false,
          isUnlockedToday: false,
          dailyExplanationCount: 10,
        ),
        isFalse,
      );
      expect(
        AccessPolicy.canViewExplanation(
          isVip: false,
          isUnlockedToday: true,
          dailyExplanationCount: 10,
        ),
        isTrue,
      );
      expect(
        AccessPolicy.canViewExplanation(
          isVip: true,
          isUnlockedToday: false,
          dailyExplanationCount: 10,
        ),
        isTrue,
      );
    });

    test('remaining explanations are clamped', () {
      expect(
        AccessPolicy.remainingExplanations(
          isVip: false,
          dailyExplanationCount: 0,
        ),
        10,
      );
      expect(
        AccessPolicy.remainingExplanations(
          isVip: false,
          dailyExplanationCount: 12,
        ),
        0,
      );
      expect(
        AccessPolicy.remainingExplanations(
          isVip: true,
          dailyExplanationCount: 12,
        ),
        10,
      );
    });

    test('free users only preview the first ten review items', () {
      expect(
        AccessPolicy.shouldLockPreviewItem(isVip: false, index: 9),
        isFalse,
      );
      expect(
        AccessPolicy.shouldLockPreviewItem(isVip: false, index: 10),
        isTrue,
      );
      expect(
        AccessPolicy.shouldLockPreviewItem(isVip: true, index: 99),
        isFalse,
      );
    });
  });
}
