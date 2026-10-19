class AccessPolicy {
  const AccessPolicy._();

  static const int freeDailyQuizLimit = 30;
  static const int freeReviewPreviewLimit = 10;
  static const int freeMistakePreviewLimit = 5;
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
    // Full explanations are free for everyone, including legacy exhausted accounts.
    return true;
  }

  static bool shouldLockPreviewItem({
    required bool isVip,
    required int index,
  }) {
    return !isVip && index >= freeReviewPreviewLimit;
  }

  /// 免費錯題本最多預覽五題，但永遠保留至少一題不展示，避免錯題數
  /// 少於五題時反而能看到完整錯題本。
  static int visibleMistakePreviewCount({
    required bool isVip,
    required int totalItems,
  }) {
    if (totalItems <= 0) return 0;
    if (isVip) return totalItems;
    if (totalItems <= freeMistakePreviewLimit) return totalItems - 1;
    return freeMistakePreviewLimit;
  }
}
