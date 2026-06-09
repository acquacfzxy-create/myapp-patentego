import 'package:in_app_purchase/in_app_purchase.dart';

import '../config/app_config.dart';

class PurchaseVerificationResult {
  const PurchaseVerificationResult._({
    required this.isVerified,
    this.errorMessage,
  });

  const PurchaseVerificationResult.verified() : this._(isVerified: true);

  const PurchaseVerificationResult.rejected(String message)
      : this._(isVerified: false, errorMessage: message);

  final bool isVerified;
  final String? errorMessage;
}

class PurchaseVerificationService {
  const PurchaseVerificationService({
    this.requireServerVerification =
        AppConfig.requireServerPurchaseVerification,
  });

  final bool requireServerVerification;

  Future<PurchaseVerificationResult> verify(PurchaseDetails purchase) async {
    if (purchase.productID != AppConfig.monthlySubscriptionProductId) {
      return const PurchaseVerificationResult.rejected(
        'Purchase product does not match this app.',
      );
    }

    if (purchase.status != PurchaseStatus.purchased &&
        purchase.status != PurchaseStatus.restored) {
      return const PurchaseVerificationResult.rejected(
        'Purchase is not completed yet.',
      );
    }

    final verificationData = purchase.verificationData;
    final hasServerData =
        verificationData.serverVerificationData.trim().isNotEmpty;
    final hasLocalData =
        verificationData.localVerificationData.trim().isNotEmpty;

    if (!hasServerData && !hasLocalData) {
      return const PurchaseVerificationResult.rejected(
        'Purchase verification data is missing.',
      );
    }

    if (requireServerVerification) {
      return const PurchaseVerificationResult.rejected(
        'Purchase must be verified by the server before VIP is unlocked.',
      );
    }

    return const PurchaseVerificationResult.verified();
  }
}
