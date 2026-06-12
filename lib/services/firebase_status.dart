import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

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
  }
}
