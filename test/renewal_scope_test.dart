import 'package:flutter_test/flutter_test.dart';
import 'package:lingua_patente/services/iap_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('renewal checks are offered only where Play Billing is enabled (R4)', () {
    final android = IapService(
      billingSupported: true,
      currentUid: () => 'uid-1',
      authUidChanges: () => const Stream<String?>.empty(),
    );
    final web = IapService(
      billingSupported: false,
      currentUid: () => 'uid-1',
      authUidChanges: () => const Stream<String?>.empty(),
    );
    addTearDown(android.dispose);
    addTearDown(web.dispose);
    expect(android.supportsRenewalChecks, isTrue);
    expect(web.supportsRenewalChecks, isFalse);
  });
}
