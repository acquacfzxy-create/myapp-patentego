// 发布前补证：真实 IapService + EntitlementMonitor 串联，Play / 服务端 / 时钟为隔离替身。
// A：Play 已确认续订但 RTDN 晚到 > 90 s（App 在线）
// B：Play 自身超过 90 s 仍未反映新周期（App 在线）
// C：本机 Play 查询为空（Play 与 App 账号不一致）或服务端 403 不会撤销云端权益
import 'dart:async';

import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:lingua_patente/config/app_config.dart';
import 'package:lingua_patente/services/iap_service.dart';
import 'package:lingua_patente/services/purchase_verification_service.dart';
import 'package:lingua_patente/services/subscription_entitlement.dart';

const int e = 10000000; // 当前周期的 Play 原始到期时间
const int e2 = e + 300000; // 续订后的周期
final int limit = AppConfig.subscriptionRenewalGraceLimit.inMilliseconds;

EntitlementSnapshot active(int exp) =>
    EntitlementSnapshot(isVip: true, expiresAtMs: exp, willRenew: true);
EntitlementSnapshot pendingFor(int periodEnd) => EntitlementSnapshot(
    isVip: false,
    expiresAtMs: 0,
    willRenew: true,
    pendingRenewal: true,
    pendingExpiresAtMs: periodEnd);

PurchaseDetails owned(String token) => PurchaseDetails(
      productID: AppConfig.monthlySubscriptionProductId,
      status: PurchaseStatus.restored,
      transactionDate: '1',
      verificationData: PurchaseVerificationData(
        localVerificationData: token,
        serverVerificationData: token,
        source: 'google_play',
      ),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _World w;
  tearDown(() => w.dispose());

  test('A: Play renewed, RTDN never arrives within 120 s -> own check keeps VIP',
      () async {
    w = _World();
    // 服务端：Play 已确认新周期，主动核对时写入新快照（RTDN 始终未到）。
    w.server = (token) {
      w.pushSnapshot(active(e2));
      return const PurchaseVerificationResult.verified();
    };
    w.play.owned = [owned('t')];
    await w.start();
    w.pushSnapshot(active(e));
    expect(w.changes, [true]);

    await w.advanceTo(e);
    expect(w.serverCalls, 1, reason: 'client checks at the boundary itself');
    expect(w.monitor.status, EntitlementStatus.active);

    await w.advanceTo(e + 120000); // 远超 90 s，仍无 RTDN
    expect(w.monitor.isVip, isTrue);
    expect(w.changes, [true], reason: 'VIP never dropped');
  });

  test('B: Play still has not renewed -> VIP ends at the fixed deadline, then recovers',
      () async {
    w = _World();
    w.server = (token) {
      // 服务端读到 Play 仍是旧周期：写 pendingRenewal（新版后端行为）。
      w.pushSnapshot(pendingFor(e));
      return const PurchaseVerificationResult.inactive('pending',
          account: AccountEntitlement(
              isVip: false,
              expiresAtMs: 0,
              pendingRenewal: true,
              pendingExpiresAtMs: e));
    };
    w.play.owned = [owned('t')];
    await w.start();
    w.pushSnapshot(active(e));

    await w.advanceTo(e);
    expect(w.monitor.status, EntitlementStatus.awaitingRenewal);
    final deadline = w.monitor.deadlineMs;
    expect(deadline, e + limit);

    await w.advanceTo(e + 50000); // +0 / +15 / +45 s 的重试都已发生
    expect(w.serverCalls, greaterThanOrEqualTo(3));
    expect(w.monitor.deadlineMs, deadline, reason: 'retries never extend it');
    expect(w.monitor.isVip, isTrue);

    await w.advanceTo(e + limit - 1);
    expect(w.monitor.isVip, isTrue);
    await w.advanceTo(e + limit);
    expect(w.monitor.isVip, isFalse, reason: 'ends exactly at the fixed cap');

    // 之后 Play 终于反映续订（RTDN 或对账写入新快照）。
    await w.advanceTo(e + 240000);
    w.pushSnapshot(active(e2));
    expect(w.monitor.isVip, isTrue);
    expect(w.changes, [true, false, true]);
  });

  test('C1: empty Play query (other Play account) never revokes cloud VIP',
      () async {
    w = _World();
    w.play.owned = []; // 本机 Play 账号下查不到这笔购买
    await w.start();
    w.pushSnapshot(active(e2)); // 云端：该 uid 有效至 e2

    w.service.didChangeAppLifecycleState(AppLifecycleState.resumed);
    final outcome = await w.service.checkRenewal('uid-1');
    expect(outcome, RenewalCheckOutcome.noLocalPurchase);
    await w.advanceTo(e);
    expect(w.monitor.isVip, isTrue);
    expect(w.serverCalls, 0, reason: 'nothing to verify, nothing written');
    expect(w.changes, [true]);
  });

  test('C2: a 403 (purchase owned by another uid) is token-level only', () async {
    w = _World();
    w.server = (token) => const PurchaseVerificationResult.rejected('403');
    w.play.owned = [owned('foreign')];
    await w.start();
    w.pushSnapshot(active(e2));

    expect(await w.service.checkRenewal('uid-1'), RenewalCheckOutcome.answered);
    expect(w.monitor.isVip, isTrue, reason: 'snapshot, not the token, decides');
    expect(w.play.completed, isEmpty, reason: 'foreign purchase not acknowledged');
  });
}

class _World {
  _World() {
    service = IapService(
      iap: play,
      billingSupported: true,
      currentUid: () => 'uid-1',
      authUidChanges: () => const Stream<String?>.empty(),
      purchaseVerifier: PurchaseVerificationService(
        checkOnServer: (productId, token) async {
          serverCalls++;
          return server(token);
        },
      ),
    );
    monitor = EntitlementMonitor(
      uid: 'uid-1',
      onChanged: changes.add,
      checker: service.checkRenewal,
      nowMs: () => clock.now,
      timerFactory: clock.timer,
    );
  }

  final _Clock clock = _Clock(e - 60000);
  final _FakePlay play = _FakePlay();
  late final IapService service;
  late final EntitlementMonitor monitor;
  final List<bool> changes = [];
  int serverCalls = 0;
  PurchaseVerificationResult Function(String token) server =
      (_) => const PurchaseVerificationResult.unknown('unset');

  Future<void> start() async {
    await service.start(onEntitlementActive: () async {}, onResumed: monitor.onResumed);
    await pumpEventQueue(times: 40);
  }

  void pushSnapshot(EntitlementSnapshot s) => monitor.updateSnapshot(s);

  /// 推进假时钟并让异步核对（Play 查询 → 服务端）跑完。
  Future<void> advanceTo(int t) async {
    while (true) {
      final next = clock.nextDue(t);
      if (next == null) break;
      clock.fireNext(t);
      await pumpEventQueue(times: 40);
    }
    clock.now = t;
    await pumpEventQueue(times: 40);
  }

  void dispose() {
    monitor.dispose();
    service.dispose();
    play.controller.close();
  }
}

class _Clock {
  _Clock(this.now);
  int now;
  final List<_T> _timers = [];
  Timer timer(Duration d, void Function() cb) {
    final t = _T(now + d.inMilliseconds, cb);
    _timers.add(t);
    return t;
  }

  _T? nextDue(int target) {
    final due = _timers.where((t) => t.isActive && t.due <= target).toList()
      ..sort((a, b) => a.due.compareTo(b.due));
    return due.isEmpty ? null : due.first;
  }

  void fireNext(int target) {
    final t = nextDue(target)!;
    if (t.due > now) now = t.due;
    t.fire();
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

/// 与 in_app_purchase_android 0.5.0 一致：restorePurchases 在 Future 完成前送达批次，全部标为 restored。
class _FakePlay implements InAppPurchase {
  final StreamController<List<PurchaseDetails>> controller =
      StreamController<List<PurchaseDetails>>.broadcast();
  List<PurchaseDetails> owned = [];
  final List<PurchaseDetails> completed = [];

  @override
  Stream<List<PurchaseDetails>> get purchaseStream => controller.stream;
  @override
  Future<bool> isAvailable() async => true;
  @override
  Future<void> restorePurchases({String? applicationUserName}) async {
    controller.add([for (final p in owned) p..status = PurchaseStatus.restored]);
  }

  @override
  Future<void> completePurchase(PurchaseDetails purchase) async {
    completed.add(purchase);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
