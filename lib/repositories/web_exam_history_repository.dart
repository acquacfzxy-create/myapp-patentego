import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

class WebExamAttempt {
  const WebExamAttempt({
    required this.id,
    required this.completedAtMs,
    required this.totalQuestions,
    required this.correctCount,
    required this.wrongCount,
    required this.timeUsedSeconds,
    required this.passed,
    required this.questionIds,
    required this.selectedAnswers,
  });

  final String id;
  final int completedAtMs;
  final int totalQuestions;
  final int correctCount;
  final int wrongCount;
  final int timeUsedSeconds;
  final bool passed;
  final List<String> questionIds;
  final Map<String, bool> selectedAnswers;

  factory WebExamAttempt.fromJson(Map<String, dynamic> json) {
    final rawIds = json['question_ids'];
    final rawAnswers = json['selected_answers'];
    return WebExamAttempt(
      id: json['attempt_id']?.toString() ?? '',
      completedAtMs: _asInt(json['completed_at_ms']),
      totalQuestions: _asInt(json['total_questions']),
      correctCount: _asInt(json['correct_count']),
      wrongCount: _asInt(json['wrong_count']),
      timeUsedSeconds: _asInt(json['time_used_seconds']),
      passed: json['passed'] == true,
      questionIds:
          rawIds is List ? rawIds.map((item) => item.toString()).toList() : [],
      selectedAnswers: rawAnswers is Map
          ? rawAnswers.map(
              (key, value) => MapEntry(key.toString(), value == true),
            )
          : {},
    );
  }

  Map<String, dynamic> toJson() => {
        'attempt_id': id,
        'completed_at_ms': completedAtMs,
        'total_questions': totalQuestions,
        'correct_count': correctCount,
        'wrong_count': wrongCount,
        'time_used_seconds': timeUsedSeconds,
        'passed': passed,
        'question_ids': questionIds,
        'selected_answers': selectedAnswers,
      };

  static int _asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }
}

/// Persists Web exam history and the active paper locally, then mirrors both
/// to Firestore for signed-in users.
class WebExamHistoryRepository {
  WebExamHistoryRepository({
    required SharedPreferences preferences,
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
  })  : _preferences = preferences,
        _auth = auth,
        _firestore = firestore;

  static const _guestActor = 'guest_user';
  static const _historyPrefix = 'web_exam_history_v1_';
  static const _sessionPrefix = 'web_exam_session_v2_';

  final SharedPreferences _preferences;
  final FirebaseAuth? _auth;
  final FirebaseFirestore? _firestore;
  String _actorId = _guestActor;
  List<WebExamAttempt> _attempts = [];

  List<WebExamAttempt> get attempts => List.unmodifiable(_attempts);
  bool get canSync => _auth?.currentUser != null && _firestore != null;

  Future<void> initialize() => switchToCurrentUser();

  Future<void> switchToCurrentUser() async {
    _actorId = _auth?.currentUser?.uid ?? _guestActor;
    _attempts = _readLocalHistory(_actorId);
    if (!canSync) return;

    final user = _auth!.currentUser!;
    QuerySnapshot<Map<String, dynamic>> snapshot;
    try {
      snapshot = await _firestore!
          .collection('users')
          .doc(user.uid)
          .collection('exam_history')
          .orderBy('completed_at_ms', descending: true)
          .limit(50)
          .get();
    } catch (_) {
      return;
    }
    final merged = <String, WebExamAttempt>{
      for (final attempt in _attempts) attempt.id: attempt,
    };
    for (final document in snapshot.docs) {
      final attempt = WebExamAttempt.fromJson(document.data());
      if (attempt.id.isNotEmpty) merged[attempt.id] = attempt;
    }
    _attempts = merged.values.toList()
      ..sort((a, b) => b.completedAtMs.compareTo(a.completedAtMs));
    if (_attempts.length > 50) _attempts = _attempts.take(50).toList();
    await _persistHistory();
  }

  Future<void> addAttempt(WebExamAttempt attempt) async {
    _attempts.removeWhere((item) => item.id == attempt.id);
    _attempts.insert(0, attempt);
    if (_attempts.length > 50) _attempts = _attempts.take(50).toList();
    await _persistHistory();

    final user = _auth?.currentUser;
    final firestore = _firestore;
    if (user != null && firestore != null) {
      await firestore
          .collection('users')
          .doc(user.uid)
          .collection('exam_history')
          .doc(attempt.id)
          .set(attempt.toJson());
    }
  }

  Future<Map<String, dynamic>?> loadSession() async {
    final local = _readLocalSession(_actorId);
    final user = _auth?.currentUser;
    final firestore = _firestore;
    if (user == null || firestore == null) return local?.session;

    DocumentSnapshot<Map<String, dynamic>> document;
    try {
      document = await firestore
          .collection('users')
          .doc(user.uid)
          .collection('exam_sessions')
          .doc('current')
          .get();
    } catch (_) {
      return local?.session;
    }
    final cloudData = document.data();
    final cloud =
        cloudData == null ? null : _StoredExamSession.fromJson(cloudData);
    final latest = cloud != null &&
            (local == null || cloud.updatedAtMs > local.updatedAtMs)
        ? cloud
        : local;
    if (latest != null) await _persistSession(latest);
    return latest?.session;
  }

  Future<void> saveSession(Map<String, dynamic> session) async {
    final stored = _StoredExamSession(
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
      session: session,
    );
    await _persistSession(stored);
    final user = _auth?.currentUser;
    final firestore = _firestore;
    if (user != null && firestore != null) {
      await firestore
          .collection('users')
          .doc(user.uid)
          .collection('exam_sessions')
          .doc('current')
          .set(stored.toJson());
    }
  }

  Future<void> clearSession() async {
    await _preferences.remove('$_sessionPrefix$_actorId');
    final user = _auth?.currentUser;
    final firestore = _firestore;
    if (user != null && firestore != null) {
      await firestore
          .collection('users')
          .doc(user.uid)
          .collection('exam_sessions')
          .doc('current')
          .delete();
    }
  }

  Future<void> clearHistory() async {
    _attempts = [];
    await _preferences.remove('$_historyPrefix$_actorId');
    final user = _auth?.currentUser;
    final firestore = _firestore;
    if (user == null || firestore == null) return;

    final collection =
        firestore.collection('users').doc(user.uid).collection('exam_history');
    while (true) {
      final snapshot = await collection.limit(450).get();
      if (snapshot.docs.isEmpty) break;
      final batch = firestore.batch();
      for (final document in snapshot.docs) {
        batch.delete(document.reference);
      }
      await batch.commit();
      if (snapshot.docs.length < 450) break;
    }
  }

  List<WebExamAttempt> _readLocalHistory(String actorId) {
    final source = _preferences.getString('$_historyPrefix$actorId');
    if (source == null) return [];
    try {
      final decoded = jsonDecode(source);
      if (decoded is! List) return [];
      return decoded
          .whereType<Map>()
          .map((item) =>
              WebExamAttempt.fromJson(Map<String, dynamic>.from(item)))
          .where((item) => item.id.isNotEmpty)
          .toList();
    } catch (_) {
      return [];
    }
  }

  _StoredExamSession? _readLocalSession(String actorId) {
    final source = _preferences.getString('$_sessionPrefix$actorId');
    if (source == null) return null;
    try {
      final decoded = jsonDecode(source);
      return decoded is Map
          ? _StoredExamSession.fromJson(Map<String, dynamic>.from(decoded))
          : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> _persistHistory() => _preferences.setString(
        '$_historyPrefix$_actorId',
        jsonEncode(_attempts.map((item) => item.toJson()).toList()),
      );

  Future<void> _persistSession(_StoredExamSession stored) =>
      _preferences.setString(
        '$_sessionPrefix$_actorId',
        jsonEncode(stored.toJson()),
      );
}

class _StoredExamSession {
  const _StoredExamSession({
    required this.updatedAtMs,
    required this.session,
  });

  final int updatedAtMs;
  final Map<String, dynamic> session;

  factory _StoredExamSession.fromJson(Map<String, dynamic> json) {
    final rawSession = json['session'];
    if (rawSession is! Map) {
      throw const FormatException('Exam session payload is missing.');
    }
    return _StoredExamSession(
      updatedAtMs: WebExamAttempt._asInt(json['updated_at_ms']),
      session: Map<String, dynamic>.from(rawSession),
    );
  }

  Map<String, dynamic> toJson() => {
        'updated_at_ms': updatedAtMs,
        'session': session,
      };
}
