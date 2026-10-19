import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:lingua_patente/config/app_config.dart';
import 'package:lingua_patente/services/purchase_verification_service.dart';

void main() {
  group('PurchaseVerificationService', () {
    test('accepts completed monthly subscription with verification data',
        () async {
      final verifier = PurchaseVerificationService(verifyOnServer: (id, token) async {
        expect(id, AppConfig.monthlySubscriptionProductId);
        expect(token, 'server-receipt');
        return true;
      });

      final result = await verifier.verify(
        _purchase(
          productID: AppConfig.monthlySubscriptionProductId,
          status: PurchaseStatus.purchased,
          serverVerificationData: 'server-receipt',
        ),
      );

      expect(result.isVerified, isTrue);
      expect(result.errorMessage, isNull);
    });

    test('rejects restored monthly subscription with only local receipt data',
        () async {
      const verifier = PurchaseVerificationService();

      final result = await verifier.verify(
        _purchase(
          productID: AppConfig.monthlySubscriptionProductId,
          status: PurchaseStatus.restored,
          localVerificationData: 'local-receipt',
        ),
      );

      expect(result.isVerified, isFalse);
    });

    test('rejects unexpected product IDs', () async {
      const verifier = PurchaseVerificationService();

      final result = await verifier.verify(
        _purchase(
          productID: 'other_product',
          status: PurchaseStatus.purchased,
          serverVerificationData: 'server-receipt',
        ),
      );

      expect(result.isVerified, isFalse);
      expect(result.errorMessage, contains('product'));
    });

    test('rejects purchases that are not completed or restored', () async {
      const verifier = PurchaseVerificationService();

      final result = await verifier.verify(
        _purchase(
          productID: AppConfig.monthlySubscriptionProductId,
          status: PurchaseStatus.pending,
          serverVerificationData: 'server-receipt',
        ),
      );

      expect(result.isVerified, isFalse);
      expect(result.errorMessage, contains('not completed'));
    });

    test('rejects purchases without verification data', () async {
      const verifier = PurchaseVerificationService();

      final result = await verifier.verify(
        _purchase(
          productID: AppConfig.monthlySubscriptionProductId,
          status: PurchaseStatus.purchased,
        ),
      );

      expect(result.isVerified, isFalse);
      expect(result.errorMessage, contains('missing'));
    });

    test('can require server verification before granting VIP', () async {
      final verifier = PurchaseVerificationService(
        verifyOnServer: (_, __) async => false,
      );

      final result = await verifier.verify(
        _purchase(
          productID: AppConfig.monthlySubscriptionProductId,
          status: PurchaseStatus.purchased,
          serverVerificationData: 'server-receipt',
        ),
      );

      expect(result.isVerified, isFalse);
      expect(result.errorMessage, isNotEmpty);
    });
    test('transport failures never grant VIP or expose receipt data', () async {
      final verifier = PurchaseVerificationService(verifyOnServer: (_, __) async {
        throw Exception('secret-receipt');
      });
      final result = await verifier.verify(_purchase(
        productID: AppConfig.monthlySubscriptionProductId,
        status: PurchaseStatus.purchased,
        serverVerificationData: 'secret-receipt',
      ));
      expect(result.isVerified, isFalse);
      expect(result.errorMessage, isNot(contains('secret-receipt')));
    });
  });

  group('Server outcome classification (P2)', () {
    const now = 1000000;
    String ok(Object result) =>
        '{"result": ${result is String ? result : _json(result)}}';

    test('200 + isVerified + future expiry is active, with the account summary',
        () {
      final r = PurchaseVerificationService.interpretResponse(
        200,
        ok({
          'isVerified': true,
          'expiresAtMs': now + 1,
          'account': {'isVip': true, 'expiresAtMs': now + 1},
        }),
        nowMs: now,
      );
      expect(r.outcome, VerificationOutcome.active);
      expect(r.isVerified, isTrue);
      expect(r.account?.isVip, isTrue);
    });

    test('200 + not verified is inactive for the token, not for the account',
        () {
      final r = PurchaseVerificationService.interpretResponse(
        200,
        ok({
          'isVerified': false,
          'expiresAtMs': now - 1,
          'account': {
            'isVip': false,
            'expiresAtMs': 0,
            'pendingRenewal': true,
            'pendingExpiresAtMs': now - 1,
          },
        }),
        nowMs: now,
      );
      expect(r.outcome, VerificationOutcome.inactive);
      expect(r.account?.pendingRenewal, isTrue);
      expect(r.account?.pendingExpiresAtMs, now - 1);
    });

    test('a verified answer with a past expiry is not active', () {
      final r = PurchaseVerificationService.interpretResponse(
        200, ok({'isVerified': true, 'expiresAtMs': now}), nowMs: now);
      expect(r.outcome, VerificationOutcome.inactive);
    });

    test('400 / 403 reject the request or token only', () {
      for (final code in [400, 403]) {
        final r = PurchaseVerificationService.interpretResponse(code, '{}');
        expect(r.outcome, VerificationOutcome.rejected, reason: '$code');
        expect(r.account, isNull);
      }
    });

    test('401, 5xx and other statuses are unknown', () {
      for (final code in [401, 429, 500, 502, 503, 504]) {
        expect(PurchaseVerificationService.interpretResponse(code, '{}').outcome,
            VerificationOutcome.unknown, reason: '$code');
      }
    });

    test('malformed bodies are unknown', () {
      for (final body in ['', 'not json', '{"result": 1}', '{"result": {}}',
          '{"result": {"isVerified": "yes", "expiresAtMs": 1}}']) {
        expect(PurchaseVerificationService.interpretResponse(200, body).outcome,
            VerificationOutcome.unknown, reason: body);
      }
    });

    test('old backend responses without account still parse', () {
      final r = PurchaseVerificationService.interpretResponse(
          200, ok({'isVerified': true, 'expiresAtMs': now + 1}), nowMs: now);
      expect(r.isVerified, isTrue);
      expect(r.account, isNull);
    });

    test('network / timeout / credential errors are unknown, not rejected',
        () async {
      final verifier = PurchaseVerificationService(
        checkOnServer: (_, __) async => throw Exception('SocketException: secret-receipt'),
      );
      final r = await verifier.verify(_purchase(
        productID: AppConfig.monthlySubscriptionProductId,
        status: PurchaseStatus.restored,
        serverVerificationData: 'secret-receipt',
      ));
      expect(r.outcome, VerificationOutcome.unknown);
      expect(r.errorMessage, isNot(contains('secret-receipt')));
    });
  });
}

String _json(Object value) {
  if (value is Map) {
    return '{${value.entries.map((e) => '"${e.key}": ${_json(e.value as Object)}').join(', ')}}';
  }
  if (value is String) return '"$value"';
  return '$value';
}

PurchaseDetails _purchase({
  required String productID,
  required PurchaseStatus status,
  String localVerificationData = '',
  String serverVerificationData = '',
}) {
  return PurchaseDetails(
    productID: productID,
    status: status,
    transactionDate:
        status == PurchaseStatus.purchased ? '1710000000000' : null,
    verificationData: PurchaseVerificationData(
      localVerificationData: localVerificationData,
      serverVerificationData: serverVerificationData,
      source: 'google_play',
    ),
  );
}
