import 'dart:convert';

import 'package:crypto/crypto.dart';

/// 由 Firebase uid 确定性衍生的 UUID（v5 布局），作为 StoreKit 2 的 appAccountToken。
/// 算法必须与 functions/apple_subscription.js 的 appleAccountToken 一致。
String appleAccountToken(String uid) {
  final bytes = sha256
      .convert(utf8.encode('patentego-apple-account:$uid'))
      .bytes
      .sublist(0, 16);
  bytes[6] = (bytes[6] & 0x0f) | 0x50;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}
