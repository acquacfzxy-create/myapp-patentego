import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import '../config/app_config.dart';
import 'firebase_status.dart';

enum AccountDeletionOutcome {
  /// 云端数据与账号已删除，且已在本机登出。
  deleted,

  /// 用户取消了重新验证（Apple / Google 登录弹窗）。
  cancelled,

  /// 服务端要求最近登录（重新验证没有生效）。
  recentLoginRequired,

  /// 其他失败（网络、服务端暂时错误等）；账号保持原样，可以重试。
  failed,
}

/// App 内删除账号（App Store 审核指南 5.1.1(v)）。
///
/// 步骤：重新验证 → （Apple）撤销 Sign in with Apple token → 调用 deleteAccount 云函数
/// （服务端删除云端数据、匿名化购买记录、删除 Firebase Auth 账号）→ 本机登出。
/// 订阅不会因此取消，用户需要在商店订阅管理中取消。
class AccountDeletionService {
  AccountDeletionService({
    http.Client? client,
    this.timeout = const Duration(seconds: 60),
  }) : _client = client ?? http.Client();

  final http.Client _client;
  final Duration timeout;

  /// 把 callable 的 HTTP 响应映射为结论（公开以便测试）。
  static AccountDeletionOutcome interpretResponse(int statusCode, String body) {
    if (statusCode == 200) {
      try {
        final result = (jsonDecode(body) as Map<String, dynamic>)['result'];
        if (result is Map && result['deleted'] == true) {
          return AccountDeletionOutcome.deleted;
        }
      } catch (_) {}
      return AccountDeletionOutcome.failed;
    }
    if (statusCode == 400) {
      try {
        final error = (jsonDecode(body) as Map<String, dynamic>)['error'];
        if (error is Map &&
            error['message'] == 'recent-login-required' &&
            error['status'] == 'FAILED_PRECONDITION') {
          return AccountDeletionOutcome.recentLoginRequired;
        }
      } catch (_) {}
    }
    return AccountDeletionOutcome.failed;
  }

  Future<AccountDeletionOutcome> deleteCurrentAccount() async {
    final auth = FirebaseStatus.auth;
    final user = auth?.currentUser;
    if (auth == null || user == null || user.isAnonymous) {
      return AccountDeletionOutcome.failed;
    }

    try {
      final providers = user.providerData.map((p) => p.providerId).toSet();
      if (providers.contains('apple.com')) {
        if (!await _reauthenticateWithApple(auth, user)) {
          return AccountDeletionOutcome.cancelled;
        }
      } else if (providers.contains('google.com')) {
        if (!await _reauthenticateWithGoogle(user)) {
          return AccountDeletionOutcome.cancelled;
        }
      }
    } on SignInWithAppleAuthorizationException catch (e) {
      return e.code == AuthorizationErrorCode.canceled
          ? AccountDeletionOutcome.cancelled
          : AccountDeletionOutcome.failed;
    } catch (_) {
      return AccountDeletionOutcome.failed;
    }

    final AccountDeletionOutcome outcome;
    try {
      // 强制刷新，使 token 的 auth_time 反映刚完成的重新验证。
      final idToken = await user.getIdToken(true);
      if (idToken == null) return AccountDeletionOutcome.failed;
      final response = await _client
          .post(
            Uri.parse(AppConfig.deleteAccountUrl),
            headers: {
              'Authorization': 'Bearer $idToken',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({'data': <String, dynamic>{}}),
          )
          .timeout(timeout);
      outcome = interpretResponse(response.statusCode, response.body);
    } catch (_) {
      return AccountDeletionOutcome.failed;
    }

    if (outcome == AccountDeletionOutcome.deleted) {
      // 账号已被服务端删除；本机登出失败不影响结果。
      try {
        await FirebaseStatus.signOut();
      } catch (_) {}
    }
    return outcome;
  }

  /// 返回 false 表示用户取消。Apple 要求删除账号时撤销 Sign in with Apple token。
  Future<bool> _reauthenticateWithApple(FirebaseAuth auth, User user) async {
    final rawNonce = _generateNonce();
    final apple = await SignInWithApple.getAppleIDCredential(
      scopes: [AppleIDAuthorizationScopes.email],
      nonce: sha256.convert(utf8.encode(rawNonce)).toString(),
    );
    final identityToken = apple.identityToken;
    if (identityToken == null) return false;
    await user.reauthenticateWithCredential(
      OAuthProvider('apple.com').credential(
        idToken: identityToken,
        rawNonce: rawNonce,
      ),
    );
    // 在删除账号前撤销；撤销失败则中止，避免留下仍有效的 Apple 授权。
    await auth.revokeTokenWithAuthorizationCode(apple.authorizationCode);
    return true;
  }

  Future<bool> _reauthenticateWithGoogle(User user) async {
    final googleUser = await GoogleSignIn().signIn();
    if (googleUser == null) return false;
    final googleAuth = await googleUser.authentication;
    await user.reauthenticateWithCredential(
      GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      ),
    );
    return true;
  }

  static String _generateNonce([int length = 32]) {
    const charset =
        '0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._';
    final random = Random.secure();
    return List.generate(length, (_) => charset[random.nextInt(charset.length)])
        .join();
  }
}
