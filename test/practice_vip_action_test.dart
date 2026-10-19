import 'package:flutter_test/flutter_test.dart';
import 'package:lingua_patente/screens/practice_screen.dart';

void main() {
  group('Practice after VIP is gained or restored (P3)', () {
    test('a loaded question is never reloaded; answers and progress stay', () {
      expect(
        practiceActionAfterVipGained(
            hasLoadedQuestion: true, isLoading: false, quotaExceeded: false),
        PracticeVipAction.none,
      );
    });

    test('a quota block on a loaded question is only lifted', () {
      expect(
        practiceActionAfterVipGained(
            hasLoadedQuestion: true, isLoading: false, quotaExceeded: true),
        PracticeVipAction.clearQuotaBlock,
      );
    });

    test('only an empty practice (blocked before loading) is initialized', () {
      expect(
        practiceActionAfterVipGained(
            hasLoadedQuestion: false, isLoading: false, quotaExceeded: true),
        PracticeVipAction.initialize,
      );
    });

    test('a load already in progress is not started twice', () {
      expect(
        practiceActionAfterVipGained(
            hasLoadedQuestion: false, isLoading: true, quotaExceeded: false),
        PracticeVipAction.none,
      );
    });
  });
}
