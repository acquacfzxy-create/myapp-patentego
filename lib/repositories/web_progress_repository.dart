import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Browser-safe progress model shared by local persistence and Firestore.
class WebQuestionProgress {
  const WebQuestionProgress({
    required this.questionId,
    this.correctStreak = 0,
    this.wrongCount = 0,
    this.totalAttempts = 0,
    this.isMastered = false,
    this.isFavorite = false,
    this.lastPracticedMs = 0,
  });

  final String questionId;
  final int correctStreak;
  final int wrongCount;
  final int totalAttempts;
  final bool isMastered;
  final bool isFavorite;
  final int lastPracticedMs;

  WebQuestionProgress recordAnswer(bool isCorrect, int timestampMs) {
    final nextStreak = isCorrect ? correctStreak + 1 : 0;
    return WebQuestionProgress(
      questionId: questionId,
      correctStreak: nextStreak,
      wrongCount:
          isCorrect ? (wrongCount > 0 ? wrongCount - 1 : 0) : wrongCount + 1,
      totalAttempts: totalAttempts + 1,
      isMastered: isCorrect && nextStreak >= 3,
      isFavorite: isFavorite,
      lastPracticedMs: timestampMs,
    );
  }

  WebQuestionProgress toggleFavorite() => WebQuestionProgress(
        questionId: questionId,
        correctStreak: correctStreak,
        wrongCount: wrongCount,
        totalAttempts: totalAttempts,
        isMastered: isMastered,
        isFavorite: !isFavorite,
        lastPracticedMs: lastPracticedMs,
      );

  /// Merges independent local/cloud snapshots.
  ///
  /// `wrongCount`, `correctStreak`, and `isMastered` are the mutable state of
  /// the latest answer. Taking the maximum wrong count can resurrect a mistake
  /// that a newer answer already resolved, so only `totalAttempts` uses a max
  /// operation. If both snapshots have the same timestamp, local wins. This
  /// tie-break is deterministic and lets a local answer resolve stale cloud
  /// state when timestamps have been truncated to the same value.
  static WebQuestionProgress merge(
    WebQuestionProgress local,
    WebQuestionProgress cloud,
  ) {
    final latest =
        cloud.lastPracticedMs > local.lastPracticedMs ? cloud : local;
    return WebQuestionProgress(
      questionId: local.questionId,
      correctStreak: latest.correctStreak,
      wrongCount: latest.wrongCount,
      totalAttempts: local.totalAttempts > cloud.totalAttempts
          ? local.totalAttempts
          : cloud.totalAttempts,
      isMastered: latest.isMastered,
      isFavorite: local.isFavorite || cloud.isFavorite,
      lastPracticedMs: local.lastPracticedMs > cloud.lastPracticedMs
          ? local.lastPracticedMs
          : cloud.lastPracticedMs,
    );
  }

  /// Merges guest progress into an authenticated account.
  ///
  /// The mobile app intentionally treats guest activity as a separate set of
  /// attempts and adds its counters to the account counters. Keep this path
  /// separate from [merge], which is used for local/cloud snapshots and must
  /// not use a maximum wrong count. As in `DatabaseService.mergeGuestDataToAccount`,
  /// guest mutable state wins when timestamps are equal.
  static WebQuestionProgress mergeGuest(
    WebQuestionProgress account,
    WebQuestionProgress guest,
  ) {
    final latest =
        guest.lastPracticedMs >= account.lastPracticedMs ? guest : account;
    return WebQuestionProgress(
      questionId: account.questionId,
      correctStreak: latest.correctStreak,
      wrongCount: account.wrongCount + guest.wrongCount,
      totalAttempts: account.totalAttempts + guest.totalAttempts,
      isMastered: latest.isMastered,
      isFavorite: account.isFavorite || guest.isFavorite,
      lastPracticedMs: account.lastPracticedMs > guest.lastPracticedMs
          ? account.lastPracticedMs
          : guest.lastPracticedMs,
    );
  }

  factory WebQuestionProgress.fromJson(
    String questionId,
    Map<String, dynamic> json,
  ) {
    final lastPracticed = json['last_practiced'];
    return WebQuestionProgress(
      questionId: questionId,
      correctStreak: _asInt(json['correct_streak']),
      wrongCount: _asInt(json['wrong_count']),
      totalAttempts: _asInt(json['total_attempts']),
      isMastered: json['is_mastered'] == true || json['is_mastered'] == 1,
      isFavorite: json['is_favorite'] == true || json['is_favorite'] == 1,
      lastPracticedMs: lastPracticed is Timestamp
          ? lastPracticed.millisecondsSinceEpoch
          : _asInt(lastPracticed),
    );
  }

  Map<String, dynamic> toLocalJson() => {
        'correct_streak': correctStreak,
        'wrong_count': wrongCount,
        'total_attempts': totalAttempts,
        'is_mastered': isMastered,
        'is_favorite': isFavorite,
        'last_practiced': lastPracticedMs,
      };

  Map<String, dynamic> toCloudJson() => {
        'correct_streak': correctStreak,
        'wrong_count': wrongCount,
        'total_attempts': totalAttempts,
        'is_mastered': isMastered,
        'is_favorite': isFavorite,
        if (lastPracticedMs > 0)
          'last_practiced': Timestamp.fromMillisecondsSinceEpoch(
            lastPracticedMs,
          ),
      };

  static int _asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }
}

/// Keeps Web progress locally and merges it with the existing Firestore shape.
class WebProgressRepository {
  WebProgressRepository({
    required SharedPreferences preferences,
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
  })  : _preferences = preferences,
        _auth = auth,
        _firestore = firestore;

  static const _storagePrefix = 'web_progress_v1_';
  static const _guestActor = 'guest_user';

  final SharedPreferences _preferences;
  final FirebaseAuth? _auth;
  final FirebaseFirestore? _firestore;
  Map<String, WebQuestionProgress> _records = {};
  String _actorId = _guestActor;

  Map<String, WebQuestionProgress> get records => Map.unmodifiable(_records);
  bool get canSync => _auth?.currentUser != null && _firestore != null;

  /// Whether this browser still has progress recorded before sign-in.
  ///
  /// Guest data is intentionally kept separate until the signed-in user
  /// explicitly chooses to merge it.
  bool get hasGuestProgress => _readLocal(_guestActor).isNotEmpty;

  int get attemptedCount =>
      _records.values.where((item) => item.totalAttempts > 0).length;
  int get mistakeCount =>
      _records.values.where((item) => item.wrongCount > 0).length;
  int get favoriteCount =>
      _records.values.where((item) => item.isFavorite).length;

  Future<void> initialize() async {
    await switchToCurrentUser();
  }

  WebQuestionProgress progressFor(String questionId) =>
      _records[questionId] ?? WebQuestionProgress(questionId: questionId);

  Future<WebQuestionProgress> recordAnswer(
    String questionId, {
    required bool isCorrect,
  }) async {
    final updated = progressFor(questionId).recordAnswer(
      isCorrect,
      DateTime.now().millisecondsSinceEpoch,
    );
    _records[questionId] = updated;
    await _persistLocal();
    return updated;
  }

  Future<WebQuestionProgress> toggleFavorite(String questionId) async {
    final updated = progressFor(questionId).toggleFavorite();
    _records[questionId] = updated;
    await _persistLocal();
    return updated;
  }

  /// Records an exam mistake without granting a correct streak for unanswered
  /// questions. The native app treats omitted/wrong exam answers as mistakes;
  /// Web uses the same progress transition so mistake review stays consistent
  /// across practice and exam entry points.
  Future<WebQuestionProgress> recordExamMistake(String questionId) async {
    return recordAnswer(questionId, isCorrect: false);
  }

  /// Removes a question from the active mistake queue while preserving its
  /// attempts, favorite flag, and current mastery state.
  Future<WebQuestionProgress> clearMistake(String questionId) async {
    final current = progressFor(questionId);
    final updated = WebQuestionProgress(
      questionId: questionId,
      correctStreak: current.correctStreak,
      wrongCount: 0,
      totalAttempts: current.totalAttempts,
      isMastered: current.isMastered,
      isFavorite: current.isFavorite,
      lastPracticedMs: DateTime.now().millisecondsSinceEpoch,
    );
    _records[questionId] = updated;
    await _persistLocal();
    return updated;
  }

  /// Clears the current actor's learning progress locally and, when signed
  /// in, removes the matching cloud progress documents as well.
  Future<void> clearAllProgress() async {
    final user = _auth?.currentUser;
    final firestore = _firestore;
    if (user != null && firestore != null) {
      final userDocument = firestore.collection('users').doc(user.uid);
      for (final collectionName in const ['progress', 'daily_usage']) {
        final collection = userDocument.collection(collectionName);
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
    }

    _records = {};
    await _preferences.remove('$_storagePrefix$_actorId');
  }

  Future<void> switchToCurrentUser() async {
    final nextActor = _auth?.currentUser?.uid ?? _guestActor;
    if (_actorId == nextActor && _records.isNotEmpty) return;

    _actorId = nextActor;
    final actorRecords = _readLocal(nextActor);
    _records = actorRecords;

    if (canSync) {
      await sync();
    } else {
      await _persistLocal();
    }
  }

  /// Explicitly merges pre-sign-in guest progress into the current account.
  ///
  /// This is deliberately separate from [switchToCurrentUser] so a login does
  /// not silently consume guest data. When authenticated, the account and
  /// guest counters are merged with [WebQuestionProgress.mergeGuest], then
  /// synced. The guest snapshot is removed only after [sync] completes; a
  /// sync error leaves it available for a later retry. Calling this while
  /// signed out is a documented no-op.
  Future<void> mergeGuestIntoCurrentUser() async {
    final user = _auth?.currentUser;
    if (user == null) return;

    if (!canSync) {
      throw StateError(
        'Cannot merge guest progress until Firestore sync is available.',
      );
    }

    // Auth state listeners normally switch actors before this method is
    // called. Calling it here as well makes the public API safe to use directly
    // after a provider reports a successful sign-in.
    await switchToCurrentUser();
    final guestRecords = _readLocal(_guestActor);
    if (guestRecords.isEmpty) return;

    final accountRecords = Map<String, WebQuestionProgress>.from(_records);
    final mergedRecords = Map<String, WebQuestionProgress>.from(accountRecords);
    for (final entry in guestRecords.entries) {
      mergedRecords.update(
        entry.key,
        (current) => WebQuestionProgress.mergeGuest(current, entry.value),
        ifAbsent: () => entry.value,
      );
    }

    _records = mergedRecords;
    try {
      await sync();
    } catch (_) {
      // Keep the guest snapshot and restore the account view so retrying does
      // not add the same guest counters twice after a failed write.
      _records = accountRecords;
      await _persistLocal();
      rethrow;
    }

    await _preferences.remove('$_storagePrefix$_guestActor');
  }

  Future<void> sync() async {
    final user = _auth?.currentUser;
    final firestore = _firestore;
    if (user == null || firestore == null) return;

    final collection =
        firestore.collection('users').doc(user.uid).collection('progress');
    final snapshot = await collection.get();
    final merged = Map<String, WebQuestionProgress>.from(_records);

    for (final document in snapshot.docs) {
      final cloud = WebQuestionProgress.fromJson(document.id, document.data());
      merged.update(
        document.id,
        (local) => WebQuestionProgress.merge(local, cloud),
        ifAbsent: () => cloud,
      );
    }

    var batch = firestore.batch();
    var pendingWrites = 0;
    for (final progress in merged.values) {
      if (progress.totalAttempts == 0 && !progress.isFavorite) continue;
      batch.set(
        collection.doc(progress.questionId),
        progress.toCloudJson(),
        SetOptions(merge: true),
      );
      pendingWrites++;
      if (pendingWrites == 450) {
        await batch.commit();
        batch = firestore.batch();
        pendingWrites = 0;
      }
    }
    if (pendingWrites > 0) await batch.commit();

    _records = merged;
    await _persistLocal();
  }

  Map<String, WebQuestionProgress> _readLocal(String actorId) {
    final source = _preferences.getString('$_storagePrefix$actorId');
    if (source == null || source.isEmpty) return {};
    try {
      final decoded = jsonDecode(source);
      if (decoded is! Map<String, dynamic>) return {};
      return decoded.map(
        (questionId, value) => MapEntry(
          questionId,
          WebQuestionProgress.fromJson(
            questionId,
            Map<String, dynamic>.from(value as Map),
          ),
        ),
      );
    } catch (_) {
      return {};
    }
  }

  Future<void> _persistLocal() {
    final data = _records.map(
      (questionId, progress) => MapEntry(questionId, progress.toLocalJson()),
    );
    return _preferences.setString(
      '$_storagePrefix$_actorId',
      jsonEncode(data),
    );
  }
}
