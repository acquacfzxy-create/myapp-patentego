enum ChapterCapabilityState {
  notStarted,
  learning,
  needsAttention,
  stable,
}

class ChapterCapability {
  const ChapterCapability({
    required this.chapterId,
    required this.total,
    required this.practiced,
    required this.mastered,
    required this.mistakes,
    required this.lastPracticed,
  });

  factory ChapterCapability.fromMap(Map<String, int> map) {
    return ChapterCapability(
      chapterId: map['chapter'] ?? 0,
      total: map['total'] ?? 0,
      practiced: map['practiced'] ?? 0,
      mastered: map['mastered'] ?? 0,
      mistakes: map['mistakes'] ?? 0,
      lastPracticed: map['lastPracticed'] ?? 0,
    );
  }

  final int chapterId;
  final int total;
  final int practiced;
  final int mastered;
  final int mistakes;
  final int lastPracticed;

  double get coverageRatio => total == 0 ? 0 : practiced / total;

  double get masteryRatio => total == 0 ? 0 : mastered / total;

  double get mistakeDensity => practiced == 0 ? 0 : mistakes / practiced;

  ChapterCapabilityState get state {
    if (practiced == 0) return ChapterCapabilityState.notStarted;
    if (coverageRatio >= 0.8 && masteryRatio >= 0.7 && mistakeDensity <= 0.05) {
      return ChapterCapabilityState.stable;
    }
    if (mistakeDensity >= 0.15) {
      return ChapterCapabilityState.needsAttention;
    }
    return ChapterCapabilityState.learning;
  }
}
