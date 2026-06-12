import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import '../config/app_config.dart';
import '../config/app_strings.dart';
import 'purchase_verification_service.dart';

enum IapOperation {
  none,
  purchase,
  restore,
}

class IapService extends ChangeNotifier {
  IapService({
    PurchaseVerificationService purchaseVerifier =
        const PurchaseVerificationService(),
  }) : _purchaseVerifier = purchaseVerifier;

  static const Set<String> _productIds = {
    AppConfig.monthlySubscriptionProductId,
  };

  final InAppPurchase _iap = InAppPurchase.instance;
  final PurchaseVerificationService _purchaseVerifier;
  StreamSubscription<List<PurchaseDetails>>? _purchaseSubscription;
  Completer<bool>? _restoreCompleter;
  Future<void> Function()? _onEntitlementActive;

  bool _isAvailable = false;
  bool _isLoading = true;
  IapOperation _operation = IapOperation.none;
  String? _errorMessage;
  ProductDetails? _monthlyProduct;

  bool get isAvailable => _isAvailable;
  bool get isLoading => _isLoading;
  bool get isBuying => _operation == IapOperation.purchase;
  bool get isRestoring => _operation == IapOperation.restore;
  bool get isPurchasing => _operation != IapOperation.none;
  String? get errorMessage => _errorMessage;
  ProductDetails? get monthlyProduct => _monthlyProduct;

  Future<void> init({
    required Future<void> Function() onEntitlementActive,
  }) async {
    _onEntitlementActive = onEntitlementActive;
    _purchaseSubscription ??= _iap.purchaseStream.listen(
      _handlePurchaseUpdates,
      onError: (Object error) {
        _errorMessage = error.toString();
        _operation = IapOperation.none;
        notifyListeners();
      },
    );

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _isAvailable = await _iap.isAvailable();
      if (!_isAvailable) {
        _errorMessage = AppStrings.get('iap_unavailable');
        return;
      }

      final response = await _iap.queryProductDetails(_productIds);
      if (response.error != null) {
        _errorMessage = response.error!.message;
      }
      if (response.notFoundIDs.isNotEmpty) {
        _errorMessage = AppStrings.get('iap_product_not_found');
      }

      for (final product in response.productDetails) {
        if (product.id == AppConfig.monthlySubscriptionProductId) {
          _monthlyProduct = product;
        }
      }
    } catch (e) {
      _errorMessage = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> buyMonthly() async {
    if (_operation != IapOperation.none) {
      return;
    }

    final product = _monthlyProduct;
    if (!_isAvailable || product == null) {
      _errorMessage = AppStrings.get('iap_subscription_not_ready');
      notifyListeners();
      return;
    }

    _operation = IapOperation.purchase;
    _errorMessage = null;
    notifyListeners();

    final purchaseParam = PurchaseParam(productDetails: product);
    try {
      final started = await _iap.buyNonConsumable(purchaseParam: purchaseParam);
      if (!started) {
        _errorMessage = AppStrings.get('iap_purchase_start_failed');
        _operation = IapOperation.none;
        notifyListeners();
      }
    } catch (e) {
      _errorMessage = e.toString();
      _operation = IapOperation.none;
      notifyListeners();
    }
  }

  Future<bool> restorePurchases({
    Duration timeout = const Duration(seconds: 6),
  }) async {
    if (!_isAvailable) {
      _errorMessage = AppStrings.get('iap_unavailable');
      notifyListeners();
      return false;
    }

    _operation = IapOperation.restore;
    _errorMessage = null;
    final restoreCompleter = Completer<bool>();
    _restoreCompleter = restoreCompleter;
    notifyListeners();

    try {
      await _iap.restorePurchases();
      final restored = await restoreCompleter.future.timeout(
        timeout,
        onTimeout: () => false,
      );

      if (identical(_restoreCompleter, restoreCompleter)) {
        _restoreCompleter = null;
      }
      if (!restored && _operation == IapOperation.restore) {
        _operation = IapOperation.none;
        notifyListeners();
      }

      return restored;
    } catch (e) {
      _errorMessage = e.toString();
      _operation = IapOperation.none;
      if (identical(_restoreCompleter, restoreCompleter)) {
        _restoreCompleter = null;
      }
      notifyListeners();
      return false;
    }
  }

  Future<void> _handlePurchaseUpdates(
    List<PurchaseDetails> purchases,
  ) async {
    for (final purchase in purchases) {
      if (!_productIds.contains(purchase.productID)) {
        continue;
      }

      var shouldCompletePurchase = purchase.pendingCompletePurchase;

      switch (purchase.status) {
        case PurchaseStatus.pending:
          shouldCompletePurchase = false;
          break;
        case PurchaseStatus.error:
          _errorMessage =
              purchase.error?.message ?? AppStrings.get('iap_purchase_failed');
          _completeRestoreResult(false);
          _operation = IapOperation.none;
          break;
        case PurchaseStatus.canceled:
          _completeRestoreResult(false);
          _operation = IapOperation.none;
          break;
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          final wasRestoring = _operation == IapOperation.restore;
          final verificationResult = await _purchaseVerifier.verify(purchase);
          if (verificationResult.isVerified) {
            await _onEntitlementActive?.call();
            if (wasRestoring) {
              _completeRestoreResult(true);
            }
          } else {
            _errorMessage = verificationResult.errorMessage ??
                AppStrings.get('iap_purchase_verification_failed');
            if (wasRestoring) {
              _completeRestoreResult(false);
            }
            shouldCompletePurchase = false;
          }
          _operation = IapOperation.none;
          break;
      }

      if (shouldCompletePurchase) {
        await _iap.completePurchase(purchase);
      }
    }
    notifyListeners();
  }

  void _completeRestoreResult(bool restored) {
    final completer = _restoreCompleter;
    if (completer != null && !completer.isCompleted) {
      completer.complete(restored);
    }
    _restoreCompleter = null;
  }

  @override
  void dispose() {
    _completeRestoreResult(false);
    _purchaseSubscription?.cancel();
    super.dispose();
  }
}
