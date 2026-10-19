import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lingua_patente/config/app_config.dart';
import 'package:lingua_patente/services/iap_service.dart';
import 'package:lingua_patente/services/subscription_entitlement.dart';

const int e = 1000000; // 本周期 Play 原始到期时间
const int e2 = e + 300000; // 续订后的下一个周期
final int limit = AppConfig.subscriptionRenewalGraceLimit.inMilliseconds;

/// 仍会续订（willRenew=true）的有效周期。
EntitlementSnapshot vip(int exp) =>
    EntitlementSnapshot(isVip: true, expiresAtMs: exp, willRenew: true);
EntitlementSnapshot pending(int periodEnd) => EntitlementSnapshot(
    isVip: false, expiresAtMs: 0, pendingRenewal: true, pendingExpiresAtMs: periodEnd);
const ended = EntitlementSnapshot(isVip: false, expiresAtMs: 0);

void main() {
  reviewRound4();

  group('RenewalGraceTracker', () {
    test('the grace limit is centrally defined as 90 seconds for now', () {
      expect(AppConfig.subscriptionRenewalGraceLimit, const Duration(seconds: 90));
    });

    test('a first purchase or a cold start never gets a waiting grant', () {
      final t = RenewalGraceTracker();
      expect(t.evaluate(vip(e), e + 1).isVip, isFalse, reason: 'expired on arrival');
      expect(t.evaluate(pending(e), e + 1).isVip, isFalse,
          reason: 'pendingRenewal alone never grants');
    });

    test('a confirmed period waits after expiry, until the fixed deadline', () {
      final t = RenewalGraceTracker();
      expect(t.evaluate(vip(e), e - 1).status, EntitlementStatus.active);
      final d = t.evaluate(vip(e), e);
      expect(d.status, EntitlementStatus.awaitingRenewal);
      expect(d.deadlineMs, e + limit);
      expect(t.evaluate(vip(e), e + limit - 1).isVip, isTrue);
      expect(t.evaluate(vip(e), e + limit).isVip, isFalse);
    });

    test('API still returning the old expiry (pendingRenewal) keeps waiting', () {
      final t = RenewalGraceTracker()..evaluate(vip(e), e - 1);
      expect(t.evaluate(pending(e), e + 2000).status,
          EntitlementStatus.awaitingRenewal);
    });

    test('a pendingRenewal for a different period is a confirmed end', () {
      final t = RenewalGraceTracker()..evaluate(vip(e), e - 1);
      expect(t.evaluate(pending(e - 5000), e + 1).isVip, isFalse);
      expect(t.evaluate(vip(e), e + 2).isVip, isFalse,
          reason: 'an ended period never waits again');
    });

    test('a server-confirmed end stops waiting immediately', () {
      final t = RenewalGraceTracker()..evaluate(vip(e), e - 1);
      expect(t.evaluate(vip(e), e + 1).isVip, isTrue);
      expect(t.evaluate(ended, e + 3000).isVip, isFalse);
      expect(t.evaluate(vip(e), e + 4000).isVip, isFalse);
    });

    test('a renewal confirmed after the deadline restores access', () {
      final t = RenewalGraceTracker()..evaluate(vip(e), e - 1);
      expect(t.evaluate(vip(e), e + limit + 1).isVip, isFalse);
      expect(t.evaluate(vip(e2), e + limit + 2).status, EntitlementStatus.active);
    });

    test('a server end before expiry (refund) is immediate and not a wait', () {
      final t = RenewalGraceTracker()..evaluate(vip(e), e - 10000);
      expect(t.evaluate(ended, e - 5000).isVip, isFalse);
      expect(t.evaluate(ended, e + 1).isVip, isFalse);
    });
  });

  group('EntitlementMonitor', () {
    late _Clock clock;
    late List<bool> changes;
    late List<Completer<RenewalCheckOutcome>> checks;
    late EntitlementMonitor m;

    EntitlementMonitor build({String uid = 'u1'}) => EntitlementMonitor(
          uid: uid,
          onChanged: changes.add,
          checker: (_) {
            final c = Completer<RenewalCheckOutcome>();
            checks.add(c);
            return c.future;
          },
          nowMs: () => clock.now,
          timerFactory: clock.timer,
        );

    setUp(() {
      clock = _Clock(e - 60000);
      changes = [];
      checks = [];
      m = build();
    });

    test('renewal notification 5 s late: VIP never drops', () async {
      m.updateSnapshot(vip(e));
      expect(changes, [true]);
      clock.advanceTo(e + 5000);
      expect(m.status, EntitlementStatus.awaitingRenewal);
      m.updateSnapshot(vip(e2));
      expect(m.status, EntitlementStatus.active);
      expect(changes, [true], reason: 'no false in between');
    });

    test('an unknown check result (offline / 401 / 503) is not an end', () async {
      m.updateSnapshot(vip(e));
      clock.advanceTo(e);
      expect(checks, hasLength(1));
      checks.single.complete(RenewalCheckOutcome.unknown);
      await pumpEventQueue();
      clock.advanceTo(e + limit - 1);
      expect(m.isVip, isTrue);
      clock.advanceTo(e + limit);
      expect(m.isVip, isFalse);
      expect(changes, [true, false]);
    });

    test('retries are bounded, merged, and never extend the deadline', () async {
      m.updateSnapshot(vip(e));
      clock.advanceTo(e);
      final deadline = m.deadlineMs;
      expect(checks, hasLength(1), reason: 'immediate check');

      // 仍在进行中：回前台、重复快照、恢复联网都合并到同一次。
      m.onResumed();
      m.updateSnapshot(vip(e), fromCache: true);
      m.updateSnapshot(vip(e));
      expect(checks, hasLength(1));
      expect(m.deadlineMs, deadline);

      checks.last.complete(RenewalCheckOutcome.unknown);
      await pumpEventQueue();
      clock.advanceTo(e + 15000);
      expect(checks, hasLength(2), reason: '+15 s retry');
      checks.last.complete(RenewalCheckOutcome.unknown);
      await pumpEventQueue();
      clock.advanceTo(e + 45000);
      expect(checks, hasLength(3), reason: '+45 s retry');
      checks.last.complete(RenewalCheckOutcome.unknown);
      await pumpEventQueue();
      clock.advanceTo(e + limit - 1);
      expect(checks, hasLength(3), reason: 'no unbounded retries');
      expect(m.deadlineMs, deadline);
      clock.advanceTo(e + limit);
      expect(m.isVip, isFalse);
    });

    test('resume and reconnect still advance an unfinished check', () async {
      m.updateSnapshot(vip(e));
      clock.advanceTo(e);
      checks.single.complete(RenewalCheckOutcome.unknown);
      await pumpEventQueue();
      clock.advanceTo(e + 5000);
      m.onResumed();
      expect(checks, hasLength(2));
      checks.last.complete(RenewalCheckOutcome.unknown);
      await pumpEventQueue();
      m.updateSnapshot(vip(e), fromCache: true);
      m.updateSnapshot(vip(e), fromCache: false); // 恢复联网
      expect(checks, hasLength(3));
    });

    test('after the deadline, resume still checks but grants nothing', () async {
      m.updateSnapshot(vip(e));
      clock.advanceTo(e);
      checks.single.complete(RenewalCheckOutcome.unknown);
      await pumpEventQueue();
      clock.advanceTo(e + limit + 1000);
      for (final c in checks.where((c) => !c.isCompleted)) {
        c.complete(RenewalCheckOutcome.unknown);
      }
      await pumpEventQueue();
      final before = checks.length;
      m.onResumed();
      expect(checks.length, before + 1);
      expect(m.isVip, isFalse);
      m.updateSnapshot(vip(e2)); // 之后核对成功
      expect(m.isVip, isTrue);
    });

    test('a canceled subscription ends on a server snapshot, no extra time',
        () async {
      m.updateSnapshot(vip(e));
      clock.advanceTo(e + 1500);
      m.updateSnapshot(ended); // RTDN EXPIRED 已写入
      expect(m.isVip, isFalse);
      expect(changes, [true, false]);
      final n = checks.length;
      m.onResumed();
      expect(checks.length, n, reason: 'resolved: nothing left to check');
    });

    test('account switch / dispose: timers and late results are ignored',
        () async {
      m.updateSnapshot(vip(e));
      clock.advanceTo(e);
      final late = checks.single;
      m.dispose();
      final other = build(uid: 'u2');
      late.complete(RenewalCheckOutcome.confirmedActive);
      await pumpEventQueue();
      clock.advanceTo(e + limit + 10);
      expect(changes, [true], reason: 'old monitor never reports again');
      expect(other.isVip, isFalse, reason: 'new account inherits nothing');
      other.updateSnapshot(vip(e), fromCache: false);
      expect(other.isVip, isFalse, reason: 'expired period, never confirmed');
    });

    test('a snapshot arriving exactly at the old expiry is the waiting state',
        () {
      m.updateSnapshot(vip(e));
      clock.advanceTo(e);
      m.updateSnapshot(pending(e));
      expect(m.status, EntitlementStatus.awaitingRenewal);
      expect(m.deadlineMs, e + limit);
    });
  });
}

/// 按 users/{uid} 真实形状构造文档；stamp 与 updatedAt 相同表示由新版后端同一次写入。
Map<String, dynamic> userDoc({
  required bool isVip,
  required int expiresAtMs,
  Object? updatedAt = 't1',
  Object? stamp = 't1',
  bool? willRenew,
  bool? pendingRenewal,
  int? pendingExpiresAtMs,
  String? state,
}) =>
    {
      'isVip': isVip,
      'subscription': {
        'provider': 'google_play',
        'expiresAtMs': expiresAtMs,
        'updatedAt': updatedAt,
        if (stamp != null) 'v2UpdatedAt': stamp,
        if (willRenew != null) 'willRenew': willRenew,
        if (pendingRenewal != null) 'pendingRenewal': pendingRenewal,
        if (pendingExpiresAtMs != null) 'pendingExpiresAtMs': pendingExpiresAtMs,
        if (state != null) 'state': state,
      },
    };

void reviewRound4() {
  group('Review round 4', () {
    late _Clock clock;
    late List<bool> changes;
    late int checks;

    EntitlementMonitor build({bool withChecker = true}) => EntitlementMonitor(
          uid: 'u1',
          onChanged: changes.add,
          checker: withChecker
              ? (_) async {
                  checks++;
                  return RenewalCheckOutcome.unknown;
                }
              : null,
          nowMs: () => clock.now,
          timerFactory: clock.timer,
        );
    EntitlementSnapshot snap(Map<String, dynamic> d) =>
        EntitlementSnapshot.fromUserDoc(d);

    setUp(() {
      clock = _Clock(e - 60000);
      changes = [];
      checks = 0;
    });

    test('R4-1 cancel delivered, then offline: ends exactly at expiry, no wait',
        () async {
      final m = build();
      m.updateSnapshot(snap(userDoc(isVip: true, expiresAtMs: e, willRenew: true,
          state: 'SUBSCRIPTION_STATE_ACTIVE')));
      // RTDN SUBSCRIPTION_CANCELED 已送达并写入；之后设备离线，没有新通知。
      m.updateSnapshot(snap(userDoc(isVip: true, expiresAtMs: e, willRenew: false,
          updatedAt: 't2', stamp: 't2', state: 'SUBSCRIPTION_STATE_CANCELED')));
      m.updateSnapshot(
          snap(userDoc(isVip: true, expiresAtMs: e, willRenew: false,
              updatedAt: 't2', stamp: 't2', state: 'SUBSCRIPTION_STATE_CANCELED')),
          fromCache: true);
      clock.advanceTo(e - 1);
      expect(m.isVip, isTrue, reason: 'paid period is kept');
      clock.advanceTo(e);
      await pumpEventQueue();
      expect(m.isVip, isFalse);
      expect(m.status, EntitlementStatus.none);
      expect(changes, [true, false]);
      expect(checks, 0, reason: 'nothing is expected to renew');
    });

    test('R4-1 multi-token: another valid subscription keeps VIP past the canceled period',
        () {
      final m = build();
      // 汇总结果：取消的那笔在 e 结束，另一笔有效订阅到 e2。
      m.updateSnapshot(snap(userDoc(isVip: true, expiresAtMs: e2, willRenew: false)));
      clock.advanceTo(e + 1000);
      expect(m.status, EntitlementStatus.active);
      expect(m.isVip, isTrue);
    });

    test('R4-4 rollback: stale willRenew left by merge is not trusted', () {
      final m = build();
      m.updateSnapshot(snap(userDoc(isVip: true, expiresAtMs: e, willRenew: true)));
      // 回滚到旧后端：merge 只重写 isVip / expiresAtMs / updatedAt，新字段残留。
      m.updateSnapshot(snap(userDoc(isVip: true, expiresAtMs: e2, updatedAt: 't9',
          stamp: 't1', willRenew: true)));
      clock.advanceTo(e2);
      expect(m.isVip, isFalse, reason: 'stale v2 fields must not start a wait');
    });

    test('R4-4 rollback: a stale pendingRenewal for the same period is not trusted',
        () {
      final m = build();
      m.updateSnapshot(snap(userDoc(isVip: true, expiresAtMs: e, willRenew: true)));
      clock.advanceTo(e + 1000);
      m.updateSnapshot(snap(userDoc(isVip: false, expiresAtMs: 0, updatedAt: 't2',
          stamp: 't2', willRenew: true, pendingRenewal: true, pendingExpiresAtMs: e)));
      expect(m.status, EntitlementStatus.awaitingRenewal, reason: 'fresh v2 write');
      // 旧后端随后写入：isVip=false、updatedAt 变了，但残留 pendingRenewal=e。
      m.updateSnapshot(snap(userDoc(isVip: false, expiresAtMs: 0, updatedAt: 't3',
          stamp: 't2', willRenew: true, pendingRenewal: true, pendingExpiresAtMs: e)));
      expect(m.isVip, isFalse);
    });

    test('R4-4 rollback via real merge semantics: old write over a v2 document',
        () {
      // 新版后端写入（同一次写入，两个时间戳相同）。
      final v2 = userDoc(isVip: false, expiresAtMs: 0, updatedAt: 't1', stamp: 't1',
          willRenew: true, pendingRenewal: true, pendingExpiresAtMs: e);
      // 回滚后旧版后端的写法：set({isVip, subscription:{provider, expiresAtMs, updatedAt}}, merge)。
      final merged = _firestoreMerge(v2, {
        'isVip': false,
        'subscription': {'provider': 'google_play', 'expiresAtMs': 0, 'updatedAt': 't2'},
      });
      expect((merged['subscription'] as Map)['pendingRenewal'], isTrue,
          reason: 'merge keeps the stale v2 field');
      final parsed = EntitlementSnapshot.fromUserDoc(merged);
      expect(parsed.pendingRenewal, isFalse);
      expect(parsed.willRenew, isFalse);

      final m = build();
      m.updateSnapshot(snap(userDoc(isVip: true, expiresAtMs: e, willRenew: true)));
      clock.advanceTo(e + 1000);
      m.updateSnapshot(parsed);
      expect(m.isVip, isFalse, reason: 'falls back to the strict expiry check');
    });

    test('R4-4 an old-backend document (no v2 fields) never starts a wait', () {
      final m = build();
      m.updateSnapshot(snap(userDoc(isVip: true, expiresAtMs: e, stamp: null)));
      clock.advanceTo(e);
      expect(m.isVip, isFalse);
    });

    test('R4 web / no Play Billing: no renewal wait at all', () {
      final m = build(withChecker: false);
      m.updateSnapshot(snap(userDoc(isVip: true, expiresAtMs: e, willRenew: true)));
      clock.advanceTo(e);
      expect(m.isVip, isFalse);
      expect(changes, [true, false]);
    });

    test('R4 control: a fresh v2 renewing subscription on Android still waits',
        () {
      final m = build();
      m.updateSnapshot(snap(userDoc(isVip: true, expiresAtMs: e, willRenew: true)));
      clock.advanceTo(e);
      expect(m.status, EntitlementStatus.awaitingRenewal);
      expect(m.deadlineMs, e + limit);
    });
  });
}

/// Firestore `set(data, {merge: true})`：嵌套 map 逐字段合并，未写的字段保留。
Map<String, dynamic> _firestoreMerge(Map<String, dynamic> base, Map<String, dynamic> write) {
  final out = Map<String, dynamic>.from(base);
  write.forEach((k, v) {
    out[k] = v is Map<String, dynamic> && out[k] is Map<String, dynamic>
        ? _firestoreMerge(out[k] as Map<String, dynamic>, v)
        : v;
  });
  return out;
}

class _Clock {
  _Clock(this.now);
  int now;
  final List<_FakeTimer> _timers = [];

  Timer timer(Duration delay, void Function() callback) {
    final t = _FakeTimer(now + delay.inMilliseconds, callback);
    _timers.add(t);
    return t;
  }

  void advanceTo(int target) {
    while (true) {
      final due = _timers.where((t) => t.isActive && t.due <= target).toList()
        ..sort((a, b) => a.due.compareTo(b.due));
      if (due.isEmpty) break;
      final next = due.first;
      now = next.due > now ? next.due : now;
      next.fire();
    }
    now = target;
  }
}

class _FakeTimer implements Timer {
  _FakeTimer(this.due, this._callback);
  final int due;
  final void Function() _callback;
  bool _active = true;

  void fire() {
    if (!_active) return;
    _active = false;
    _callback();
  }

  @override
  void cancel() => _active = false;
  @override
  bool get isActive => _active;
  @override
  int get tick => 0;
}
