// 用 Firestore emulator 真实写出的 users 文档（functions/test/emulator.integration.test.js
// 导出的 fixture）验证客户端解析。时间戳还原为真实的 cloud_firestore Timestamp。
// 运行：LP_FIRESTORE_FIXTURE=<fixture.json> flutter test test/firestore_emulator_fixture_test.dart
// 未提供 fixture 时跳过。
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lingua_patente/config/app_config.dart';
import 'package:lingua_patente/services/iap_service.dart';
import 'package:lingua_patente/services/subscription_entitlement.dart';

void main() {
  final path = Platform.environment['LP_FIRESTORE_FIXTURE'];
  final skip = path == null ? 'LP_FIRESTORE_FIXTURE not set' : null;
  Map<String, Map<String, dynamic>> docs = {};

  setUpAll(() {
    if (path == null) return;
    final raw = jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;
    docs = raw.map((k, v) => MapEntry(k, _withTimestamps(v as Map<String, dynamic>)));
  });

  Map<String, dynamic> doc(String name) => docs[name]!;
  Map sub(String name) => doc(name)['subscription'] as Map;
  EntitlementSnapshot parse(String name) => EntitlementSnapshot.fromUserDoc(doc(name));

  test('stamps are real Timestamps and equal for a v2 write', () {
    expect(sub('activeRenewing')['updatedAt'], isA<Timestamp>());
    expect(sub('activeRenewing')['v2UpdatedAt'], isA<Timestamp>());
    expect(sub('activeRenewing')['updatedAt'], sub('activeRenewing')['v2UpdatedAt']);
    final s = parse('activeRenewing');
    expect(s.isVip, isTrue);
    expect(s.willRenew, isTrue, reason: 'trusted v2 renewal fields');
  }, skip: skip);

  test('canceled: VIP until expiry, then no wait', () {
    final s = parse('canceled');
    expect(s.isVip, isTrue);
    expect(s.willRenew, isFalse);
    final clock = _Clock(s.expiresAtMs - 1000);
    final changes = <bool>[];
    final m = _monitor(clock, changes)..updateSnapshot(s);
    clock.advanceTo(s.expiresAtMs);
    expect(m.isVip, isFalse);
    expect(changes, [true, false]);
  }, skip: skip);

  test('expired: no VIP, no pending', () {
    final s = parse('expired');
    expect(s.isVip, isFalse);
    expect(s.pendingRenewal, isFalse);
  }, skip: skip);

  test('pendingRenewal written by the backend keeps the confirmed period waiting',
      () {
    final before = parse('pendingBefore');
    final pending = parse('pending');
    expect(pending.pendingRenewal, isTrue);
    expect(pending.pendingExpiresAtMs, before.expiresAtMs);
    final clock = _Clock(before.expiresAtMs - 1000);
    final m = _monitor(clock, [])..updateSnapshot(before);
    clock.advanceTo(before.expiresAtMs + 500);
    m.updateSnapshot(pending);
    expect(m.status, EntitlementStatus.awaitingRenewal);
    expect(m.deadlineMs,
        before.expiresAtMs + AppConfig.subscriptionRenewalGraceLimit.inMilliseconds);

    // 旧版后端 merge 写入后：时间戳不同，残留的 pendingRenewal 被忽略。
    expect(sub('rolledBack')['pendingRenewal'], isTrue);
    expect(sub('rolledBack')['updatedAt'] == sub('rolledBack')['v2UpdatedAt'], isFalse);
    final rolledBack = parse('rolledBack');
    expect(rolledBack.pendingRenewal, isFalse);
    expect(rolledBack.willRenew, isFalse);
    m.updateSnapshot(rolledBack);
    expect(m.isVip, isFalse);
  }, skip: skip);
}

Map<String, dynamic> _withTimestamps(Map<String, dynamic> d) {
  final out = Map<String, dynamic>.from(d);
  final s = Map<String, dynamic>.from(out['subscription'] as Map);
  for (final key in ['updatedAt', 'v2UpdatedAt']) {
    final t = s[key];
    if (t is Map) s[key] = Timestamp(t['seconds'] as int, t['nanoseconds'] as int);
  }
  out['subscription'] = s;
  return out;
}

EntitlementMonitor _monitor(_Clock clock, List<bool> changes) => EntitlementMonitor(
      uid: 'u1',
      onChanged: changes.add,
      checker: (_) async => RenewalCheckOutcome.unknown,
      nowMs: () => clock.now,
      timerFactory: clock.timer,
    );

class _Clock {
  _Clock(this.now);
  int now;
  final List<_T> _timers = [];
  Timer timer(Duration d, void Function() cb) {
    final t = _T(now + d.inMilliseconds, cb);
    _timers.add(t);
    return t;
  }

  void advanceTo(int target) {
    while (true) {
      final due = _timers.where((t) => t.isActive && t.due <= target).toList()
        ..sort((a, b) => a.due.compareTo(b.due));
      if (due.isEmpty) break;
      now = due.first.due > now ? due.first.due : now;
      due.first.fire();
    }
    now = target;
  }
}

class _T implements Timer {
  _T(this.due, this._cb);
  final int due;
  final void Function() _cb;
  bool _active = true;
  void fire() {
    if (!_active) return;
    _active = false;
    _cb();
  }

  @override
  void cancel() => _active = false;
  @override
  bool get isActive => _active;
  @override
  int get tick => 0;
}
