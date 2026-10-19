import 'dart:async';

import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:lingua_patente/config/app_config.dart';

/// 商店截图用的示例价格。仅用于画面展示，发布前请改成 Play Console 中的实际标价。
const String kScreenshotMonthlyPrice = '€4.99';

/// 截图测试专用的假 IAP：只返回一个固定商品，永远不连接真实 Google Play Billing。
/// 配合 `IapService(iap: ScreenshotIap(), billingSupported: true)` 使用。
class ScreenshotIap implements InAppPurchase {
  ScreenshotIap({this.price = kScreenshotMonthlyPrice});

  /// 画面上显示的价格文字（默认示例价；App Store 审核截图用 --dart-define=SUB_PRICE 传入真实价格）。
  final String price;

  final StreamController<List<PurchaseDetails>> _stream =
      StreamController<List<PurchaseDetails>>.broadcast();

  @override
  Stream<List<PurchaseDetails>> get purchaseStream => _stream.stream;

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<ProductDetailsResponse> queryProductDetails(
    Set<String> identifiers,
  ) async {
    return ProductDetailsResponse(
      productDetails: [
        ProductDetails(
          id: AppConfig.monthlySubscriptionProductId,
          title: 'VIP',
          description: 'VIP monthly',
          price: price,
          rawPrice: 4.99,
          currencyCode: 'EUR',
        ),
      ],
      notFoundIDs: const [],
    );
  }

  @override
  Future<bool> buyNonConsumable({required PurchaseParam purchaseParam}) async =>
      false;

  @override
  Future<void> completePurchase(PurchaseDetails purchase) async {}

  @override
  Future<void> restorePurchases({String? applicationUserName}) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
