class ChapterStrengtheningCandidate {
  const ChapterStrengtheningCandidate({
    required this.questionId,
    required this.wrongCount,
    required this.isMastered,
    required this.totalAttempts,
    required this.lastPracticed,
  });

  final String questionId;
  final int wrongCount;
  final bool isMastered;
  final int totalAttempts;
  final int lastPracticed;

  int get priority {
    if (wrongCount > 0) return 0;
    if (!isMastered && totalAttempts > 0) return 1;
    if (!isMastered) return 2;
    return 3;
  }
}

List<String> buildChapterStrengtheningPlan(
  Iterable<ChapterStrengtheningCandidate> candidates, {
  int limit = 10,
}) {
  if (limit <= 0) return const [];

  final ranked = candidates.toList()
    ..sort((a, b) {
      final priorityComparison = a.priority.compareTo(b.priority);
      if (priorityComparison != 0) return priorityComparison;

      if (a.priority == 0) {
        final wrongComparison = b.wrongCount.compareTo(a.wrongCount);
        if (wrongComparison != 0) return wrongComparison;
      }
      final practicedComparison = a.lastPracticed.compareTo(b.lastPracticed);
      if (practicedComparison != 0) return practicedComparison;
      return a.questionId.compareTo(b.questionId);
    });
  return ranked.take(limit).map((candidate) => candidate.questionId).toList();
}
