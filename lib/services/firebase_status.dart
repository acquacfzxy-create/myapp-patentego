import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:google_sign_in/google_sign_in.dart';

class FirebaseStatus {
  static bool _initialized = false;
  static Object? _initializationError;

  static bool get isInitialized => _initialized && Firebase.apps.isNotEmpty;
  static Object? get initializationError => _initializationError;

  static void markInitialized() {
    _initialized = true;
    _initializationError = null;
  }

  static void markUnavailable(Object error) {
    _initialized = false;
    _initializationError = error;
  }

  static FirebaseAuth? get auth {
    if (!isInitialized) return null;
    try {
      return FirebaseAuth.instance;
    } catch (_) {
      return null;
    }
  }

  static FirebaseFirestore? get firestore {
    if (!isInitialized) return null;
    try {
      return FirebaseFirestore.instance;
    } catch (_) {
      return null;
    }
  }

  static bool get isSignedIn => auth?.currentUser != null;
  static String? get currentUserUid => auth?.currentUser?.uid;
  static String? get currentUserDisplayName => auth?.currentUser?.displayName;
  static String? get currentUserEmail => auth?.currentUser?.email;

  static Future<void> signOut() async {
    await auth?.signOut();
    // 同时清除 Google 登录记住的账号，下次“使用 Google 登录”才会重新显示账号选择器。
    // 只用 signOut()，不调用 disconnect()：不撤销应用授权，也不移除设备上的 Google 账号。
    // Web 端使用弹窗登录，不经过 GoogleSignIn。
    if (!kIsWeb) {
      try {
        await GoogleSignIn().signOut();
      } catch (_) {
        // 清除失败不影响已完成的 Firebase 登出。
      }
    }
  }
}
