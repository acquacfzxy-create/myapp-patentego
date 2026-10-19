import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import 'app_strings.dart';

/// 错误提示的展示层：把异常转换成用户可读、已本地化的文案。
///
/// 只决定「显示什么」，不参与认证、购买、权益或同步的判断；原始 SDK 信息与凭据
/// 不会出现在界面上，仅在 debug 构建中输出类型与错误码供排查。
class UserErrorCopy {
  UserErrorCopy._();

  static const Map<String, String> _authCodeKeys = {
    'network-request-failed': 'auth_error_network_failed',
    'network_error': 'auth_error_network_failed',
    'too-many-requests': 'auth_error_too_many_requests',
    'user-disabled': 'auth_error_user_disabled',
    'user-not-found': 'auth_error_user_not_found',
    'wrong-password': 'auth_error_wrong_password',
    'invalid-email': 'auth_error_invalid_email',
    'email-already-in-use': 'auth_error_email_in_use',
    'weak-password': 'auth_error_weak_password',
    'sign_in_canceled': 'auth_error_google_cancelled',
    'popup-closed-by-user': 'auth_error_google_cancelled',
    'cancelled-popup-request': 'auth_error_google_cancelled',
    'web-context-canceled': 'auth_error_google_cancelled',
  };

  /// 已由现有服务本地化、可以原样展示的登录错误 key（不含带原始信息的前缀 key）。
  static const List<String> _presentableAuthKeys = [
    'auth_error_firebase_unavailable',
    'auth_error_google_cancelled',
    'auth_error_apple_identity_missing',
    'auth_error_user_not_found',
    'auth_error_wrong_password',
    'auth_error_invalid_email',
    'auth_error_user_disabled',
    'auth_error_too_many_requests',
    'auth_error_network_failed',
    'auth_error_password_too_short',
    'auth_error_register_unavailable',
    'auth_error_email_in_use',
    'auth_error_weak_password',
    'auth_error_email_register_disabled',
  ];

  /// 登录 / 注册失败时展示的文案。
  static String auth(Object error, {required String language}) {
    _log('auth', error);
    String? key;
    if (error is FirebaseAuthException) {
      key = _authCodeKeys[error.code];
    } else if (error is PlatformException) {
      key = _authCodeKeys[error.code];
    } else if (error is SignInWithAppleAuthorizationException) {
      key = error.code == AuthorizationErrorCode.canceled
          ? 'auth_error_google_cancelled'
          : null;
    }
    if (key != null) return AppStrings.getWithLanguage(language, key);

    final message = _messageOf(error);
    if (_matchesAny(message, _presentableAuthKeys)) return message;

    final registerPrefix =
        AppStrings.getWithLanguage(language, 'auth_error_register_failed_prefix');
    return AppStrings.getWithLanguage(
      language,
      message.startsWith(registerPrefix.trim())
          ? 'auth_error_register_generic'
          : 'auth_error_sign_in_generic',
    );
  }

  /// 订阅 / 恢复购买相关的错误文案。[message] 通常来自 IapService.errorMessage。
  static String purchase(Object? error, {required String language}) {
    if (error == null) {
      return AppStrings.getWithLanguage(language, 'iap_error_generic');
    }
    final message = _messageOf(error);
    if (message.isNotEmpty && _isLocalizedPurchaseCopy(message)) {
      return message;
    }
    _log('iap', error);
    return AppStrings.getWithLanguage(language, 'iap_error_generic');
  }

  /// 云端同步失败的文案（不附带原始异常）。
  static String sync(Object error, {required String language}) {
    _log('sync', error);
    return AppStrings.getWithLanguage(language, 'sync_failed_generic');
  }

  /// 语音包目录加载 / 下载失败的文案。[code] 来自 VoicePackService.errorCodeFor，
  /// 历史版本或未知的值一律显示通用提示。
  static String voicePack(String? code, {required String language}) {
    final english = AppStrings.allTables['en']!;
    if (code != null &&
        code.startsWith('voice_pack_error_') &&
        english.containsKey(code)) {
      return AppStrings.getWithLanguage(language, code);
    }
    return AppStrings.getWithLanguage(language, 'voice_pack_error_generic');
  }

  static bool _isLocalizedPurchaseCopy(String message) {
    for (final table in AppStrings.allTables.values) {
      for (final entry in table.entries) {
        final key = entry.key;
        if ((key.startsWith('iap_') || key.startsWith('sub_restore_')) &&
            entry.value == message) {
          return true;
        }
      }
    }
    return false;
  }

  static bool _matchesAny(String message, List<String> keys) {
    for (final table in AppStrings.allTables.values) {
      for (final key in keys) {
        if (table[key] == message) return true;
      }
    }
    return false;
  }

  static String _messageOf(Object error) {
    final text = error.toString();
    return text.startsWith('Exception: ')
        ? text.substring('Exception: '.length)
        : text;
  }

  static void _log(String area, Object error) {
    if (!kDebugMode) return;
    final code = switch (error) {
      FirebaseAuthException() => error.code,
      PlatformException() => error.code,
      SignInWithAppleAuthorizationException() => error.code.name,
      _ => '-',
    };
    debugPrint('[$area] ${error.runtimeType} code=$code');
  }
}
