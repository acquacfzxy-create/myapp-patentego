class AccessPolicy {
  const AccessPolicy._();

  static const int freeDailyQuizLimit = 30;
  static const int freeReviewPreviewLimit = 10;
  static const int maxFreeExplanations = 10;

  static int remainingExplanations({
    required bool isVip,
    required int dailyExplanationCount,
  }) {
    if (isVip) return maxFreeExplanations;
    return (maxFreeExplanations - dailyExplanationCount)
        .clamp(0, maxFreeExplanations);
  }

  static bool canPractice({
    required bool isVip,
    required int dailyQuizCount,
  }) {
    return isVip || dailyQuizCount < freeDailyQuizLimit;
  }

  static bool canStartExam({
    required bool isVip,
    required bool isExamUsedToday,
  }) {
    return isVip || !isExamUsedToday;
  }

  static bool canViewExplanation({
    required bool isVip,
    required bool isUnlockedToday,
    required int dailyExplanationCount,
  }) {
    return isVip ||
        isUnlockedToday ||
        dailyExplanationCount < maxFreeExplanations;
  }

  static bool shouldLockPreviewItem({
    required bool isVip,
    required int index,
  }) {
    return !isVip && index >= freeReviewPreviewLimit;
  }
}
