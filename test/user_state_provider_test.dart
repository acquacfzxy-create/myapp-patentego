import 'package:flutter_test/flutter_test.dart';
import 'package:italy_quiz_app/providers/user_state_provider.dart';

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
}
