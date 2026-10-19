import 'package:flutter_test/flutter_test.dart';
import 'package:lingua_patente/providers/user_state_provider.dart';

void main() {
  group('UserStateProvider local VIP cache', () {
    test('ignores stale secure VIP after a clean reinstall', () {
      expect(
        UserStateProvider.resolveVipFromLocalCache(
          secureVip: true,
          sharedVip: null,
          legacyPremium: null,
          hasVipInstallBinding: false,
        ),
        isFalse,
      );
    });

    test('trusts secure VIP when it is bound to the current install', () {
      expect(
        UserStateProvider.resolveVipFromLocalCache(
          secureVip: true,
          sharedVip: null,
          legacyPremium: null,
          hasVipInstallBinding: true,
        ),
        isTrue,
      );
    });

    test('keeps shared preference migration paths working', () {
      expect(
        UserStateProvider.resolveVipFromLocalCache(
          secureVip: null,
          sharedVip: true,
          legacyPremium: null,
          hasVipInstallBinding: false,
        ),
        isTrue,
      );
      expect(
        UserStateProvider.resolveVipFromLocalCache(
          secureVip: null,
          sharedVip: null,
          legacyPremium: true,
          hasVipInstallBinding: false,
        ),
        isTrue,
      );
    });
  });

  group('Daily study goal planning bounds', () {
    test('normalizer supports preview goals above the free quota', () {
      expect(
        UserStateProvider.normalizeDailyStudyGoal(238),
        238,
      );
    });

    test('allows a two-month full-bank pace', () {
      expect(
        UserStateProvider.normalizeDailyStudyGoal(119),
        119,
      );
    });

    test('caps the goal at the question-bank size', () {
      expect(
        UserStateProvider.normalizeDailyStudyGoal(9000),
        7139,
      );
    });

    test('keeps the minimum goal at ten questions', () {
      expect(
        UserStateProvider.normalizeDailyStudyGoal(1),
        10,
      );
    });

    test('free users execute at most thirty questions per day', () {
      expect(
        UserStateProvider.effectiveDailyStudyGoal(
          isVip: false,
          savedGoal: 79,
        ),
        30,
      );
      expect(
        UserStateProvider.effectiveDailyStudyGoal(
          isVip: false,
          savedGoal: 20,
        ),
        20,
      );
    });

    test('VIP users retain a higher daily goal', () {
      expect(
        UserStateProvider.effectiveDailyStudyGoal(
          isVip: true,
          savedGoal: 79,
        ),
        79,
      );
    });
  });

  group('Daily quiz counter loading', () {
    test('daily reset wins over a stale secure counter', () {
      expect(
        UserStateProvider.resolveDailyQuizCount(
          wasDailyReset: true,
          secureCount: '30',
          sharedCount: 0,
        ),
        0,
      );
    });

    test('same-day loading prefers the secure counter', () {
      expect(
        UserStateProvider.resolveDailyQuizCount(
          wasDailyReset: false,
          secureCount: '18',
          sharedCount: 12,
        ),
        18,
      );
    });

    test('same-day loading falls back to shared preferences', () {
      expect(
        UserStateProvider.resolveDailyQuizCount(
          wasDailyReset: false,
          secureCount: null,
          sharedCount: 7,
        ),
        7,
      );
    });
  });
}
