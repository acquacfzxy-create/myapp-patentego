import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:in_app_purchase/in_app_purchase.dart';

import '../config/app_config.dart';
import '../config/app_strings.dart';
import 'firebase_status.dart';

/// 单个 token 的验证结论。
enum VerificationOutcome {
  /// 服务端确认该 token 当前有效。
  active,

  /// 服务端完成核对，该 token 当前不授予权益（整个账号是否有 VIP 见 [AccountEntitlement]）。
  inactive,

  /// 请求或该 token 被拒绝（400 / 403 / 本地数据不合法）；不代表账号没有 VIP。
  rejected,

  /// 无法确认：网络、超时、401、5xx、响应格式异常、请求期间换账号等。
  unknown,
}

/// 服务端对整个账号（所有 token）汇总后的权益，与 users/{uid} 写入内容一致。
class AccountEntitlement {
  const AccountEntitlement({
    required this.isVip,
    required this.expiresAtMs,
    required this.pendingRenewal,
    required this.pendingExpiresAtMs,
  });

  final bool isVip;
  final int expiresAtMs;

  /// 仍有订阅在等待 Play 反映续订（仅是续订意图，不是付款证据）。
  final bool pendingRenewal;

  /// 等待续订的那个周期的原始（Play）到期时间。
  final int pendingExpiresAtMs;

  static AccountEntitlement? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final isVip = raw['isVip'];
    final expiresAtMs = raw['expiresAtMs'];
    if (isVip is! bool || expiresAtMs is! num) return null;
    final pending = raw['pendingRenewal'];
    final pendingAt = raw['pendingExpiresAtMs'];
    return AccountEntitlement(
      isVip: isVip,
      expiresAtMs: expiresAtMs.toInt(),
      pendingRenewal: pending == true,
      pendingExpiresAtMs: pendingAt is num ? pendingAt.toInt() : 0,
    );
  }
}

class PurchaseVerificationResult {
  const PurchaseVerificationResult._({
    required this.outcome,
    this.errorMessage,
    this.account,
  });

  const PurchaseVerificationResult.verified({AccountEntitlement? account})
      : this._(outcome: VerificationOutcome.active, account: account);

  const PurchaseVerificationResult.rejected(String message)
      : this._(outcome: VerificationOutcome.rejected, errorMessage: message);

  const PurchaseVerificationResult.inactive(
    String message, {
    AccountEntitlement? account,
  }) : this._(
          outcome: VerificationOutcome.inactive,
          errorMessage: message,
          account: account,
        );

  const PurchaseVerificationResult.unknown(String message)
      : this._(outcome: VerificationOutcome.unknown, errorMessage: message);

  final VerificationOutcome outcome;
  final String? errorMessage;

  /// 服务端返回的账号汇总；旧版后端或未到达服务端时为 null。
  final AccountEntitlement? account;

  bool get isVerified => outcome == VerificationOutcome.active;
}

class PurchaseVerificationService {
  const PurchaseVerificationService({
    this.verifyOnServer,
    this.checkOnServer,
    this.timeout = const Duration(seconds: 30),
  });

  /// 仅用于测试的简化注入：true = 有效，false = 被拒绝。
  final Future<bool> Function(String productId, String token)? verifyOnServer;

  /// 测试注入：直接返回服务端结论。
  final Future<PurchaseVerificationResult> Function(
      String productId, String token)? checkOnServer;

  final Duration timeout;

  static String get _failed =>
      AppStrings.get('iap_purchase_verification_failed');

  Future<PurchaseVerificationResult> _checkOnServer(
    String productId,
    String token, {
    bool apple = false,
  }) async {
    final user = FirebaseStatus.auth?.currentUser;
    if (user == null || user.isAnonymous) {
      return PurchaseVerificationResult.unknown(_failed);
    }
    final idToken = await user.getIdToken();
    if (idToken == null) return PurchaseVerificationResult.unknown(_failed);
    final response = await http
        .post(
          Uri.parse(apple
              ? AppConfig.appStoreVerificationUrl
              : AppConfig.purchaseVerificationUrl),
          headers: {
            'Authorization': 'Bearer $idToken',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'data': apple
                // iOS：token 是 StoreKit 2 交易的 JWS，由服务端验签并向 Apple 查证。
                ? {'productId': productId, 'signedTransaction': token}
                : {'productId': productId, 'purchaseToken': token},
          }),
        )
        .timeout(timeout);
    // 请求期间换了账号：结论不属于当前账号。
    if (FirebaseStatus.auth?.currentUser?.uid != user.uid) {
      return PurchaseVerificationResult.unknown(_failed);
    }
    return interpretResponse(response.statusCode, response.body);
  }

  /// 把 callable 的 HTTP 响应映射为三类结论（公开以便测试）。
  static PurchaseVerificationResult interpretResponse(
    int statusCode,
    String body, {
    int? nowMs,
  }) {
    // invalid-argument / permission-denied：只否定这次请求或这个 token。
    if (statusCode == 400 || statusCode == 403) {
      return PurchaseVerificationResult.rejected(_failed);
    }
    // 401、5xx 及其他：无法确认。
    if (statusCode != 200) return PurchaseVerificationResult.unknown(_failed);
    try {
      final result = (jsonDecode(body) as Map<String, dynamic>)['result'];
      if (result is! Map ||
          result['isVerified'] is! bool ||
          result['expiresAtMs'] is! num) {
        return PurchaseVerificationResult.unknown(_failed);
      }
      final account = AccountEntitlement.tryParse(result['account']);
      final now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
      if (result['isVerified'] == true &&
          (result['expiresAtMs'] as num) > now) {
        return PurchaseVerificationResult.verified(account: account);
      }
      return PurchaseVerificationResult.inactive(_failed, account: account);
    } catch (_) {
      return PurchaseVerificationResult.unknown(_failed);
    }
  }

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
    if (!hasServerData) {
      return const PurchaseVerificationResult.rejected(
        'Purchase verification data is missing.',
      );
    }
    final isApple = verificationData.source == 'app_store';
    if (verificationData.source != 'google_play' && !isApple) {
      return PurchaseVerificationResult.rejected(_failed);
    }

    final token = verificationData.serverVerificationData;
    try {
      final simple = verifyOnServer;
      if (simple != null) {
        return await simple(purchase.productID, token)
            ? const PurchaseVerificationResult.verified()
            : PurchaseVerificationResult.rejected(_failed);
      }
      return await (checkOnServer ??
          (productId, token) =>
              _checkOnServer(productId, token, apple: isApple))(
        purchase.productID,
        token,
      );
    } catch (_) {
      // 网络 / 超时 / 凭证刷新失败：无法确认。不向 UI 暴露 token 或传输细节。
      return PurchaseVerificationResult.unknown(_failed);
    }
  }
}
