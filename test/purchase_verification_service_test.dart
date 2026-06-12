import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:italy_quiz_app/config/app_config.dart';
import 'package:italy_quiz_app/services/purchase_verification_service.dart';

void main() {
  group('PurchaseVerificationService', () {
    test('accepts completed monthly subscription with verification data',
        () async {
      const verifier = PurchaseVerificationService();

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

    test('accepts restored monthly subscription with local receipt data',
        () async {
      const verifier = PurchaseVerificationService();

      final result = await verifier.verify(
        _purchase(
          productID: AppConfig.monthlySubscriptionProductId,
          status: PurchaseStatus.restored,
          localVerificationData: 'local-receipt',
        ),
      );

      expect(result.isVerified, isTrue);
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
      const verifier = PurchaseVerificationService(
        requireServerVerification: true,
      );

      final result = await verifier.verify(
        _purchase(
          productID: AppConfig.monthlySubscriptionProductId,
          status: PurchaseStatus.purchased,
          serverVerificationData: 'server-receipt',
        ),
      );

      expect(result.isVerified, isFalse);
      expect(result.errorMessage, contains('server'));
    });
  });
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
      source: 'test',
    ),
  );
}
