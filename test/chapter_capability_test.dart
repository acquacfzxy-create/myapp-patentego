import 'package:flutter_test/flutter_test.dart';
import 'package:lingua_patente/models/chapter_capability.dart';

ChapterCapability _capability({
  required int total,
  required int practiced,
  required int mastered,
  required int mistakes,
}) {
  return ChapterCapability(
    chapterId: 1,
    total: total,
    practiced: practiced,
    mastered: mastered,
    mistakes: mistakes,
    lastPracticed: 0,
  );
}

void main() {
  test('unpracticed chapters are not started', () {
    expect(
      _capability(total: 100, practiced: 0, mastered: 0, mistakes: 0).state,
      ChapterCapabilityState.notStarted,
    );
  });

  test('high mistake density marks a chapter for attention', () {
    expect(
      _capability(total: 100, practiced: 20, mastered: 4, mistakes: 3).state,
      ChapterCapabilityState.needsAttention,
    );
  });

  test('high coverage and mastery marks a chapter stable', () {
    expect(
      _capability(total: 100, practiced: 90, mastered: 80, mistakes: 2).state,
      ChapterCapabilityState.stable,
    );
  });

  test('other practiced chapters remain in learning', () {
    expect(
      _capability(total: 100, practiced: 40, mastered: 20, mistakes: 2).state,
      ChapterCapabilityState.learning,
    );
  });
}
