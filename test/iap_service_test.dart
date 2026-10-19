import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:lingua_patente/config/app_config.dart';
import 'package:lingua_patente/config/app_strings.dart';
import 'package:lingua_patente/services/iap_service.dart';
import 'package:lingua_patente/services/purchase_verification_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _Harness h;

  Future<void> settle() => pumpEventQueue(times: 40);

  tearDown(() async {
    h.service.dispose();
    await h.auth.close();
    await h.fake.controller.close();
  });

  group('App-level purchase lifecycle', () {
    test('a purchase is processed even after the subscription page is gone',
        () async {
      h = _Harness();
      await h.start();

      // 模拟订阅页：挂上监听后又销毁（页面 dispose）。
      void pageListener() {}
      h.service.addListener(pageListener);
      final pageSub = h.service.verifiedPurchases.listen((_) {});
      h.service.removeListener(pageListener);
      await pageSub.cancel();

      h.fake.controller.add([_purchase('t1', PurchaseStatus.purchased)]);
      await settle();

      expect(h.verifyCalls, ['t1']);
      expect(h.entitlementCalls, 1);
      expect(h.fake.completed.map(_token), ['t1']);
    });

    test('an owned but unverified purchase is discovered at startup', () async {
      h = _Harness();
      h.fake.restoreScript = [
        [_purchase('owned', PurchaseStatus.restored)],
      ];

      await h.start();
      await settle();

      expect(h.fake.restoreCalls, 1);
      expect(h.verifyCalls, ['owned']);
      expect(h.entitlementCalls, 1);
      expect(h.fake.completed.map(_token), ['owned']);
      expect(h.service.errorMessage, isNull, reason: 'background is silent');
    });

    test('pending completes in the background and a quick resume verifies it',
        () async {
      h = _Harness();
      // 插件把查询结果统一标为 restored；付款仍 pending 时由服务端判定不有效。
      var paid = false;
      h.checkImpl = (_) async => paid
          ? const PurchaseVerificationResult.verified()
          : const PurchaseVerificationResult.inactive('PENDING');
      h.fake.restoreScript = [
        [_purchase('t', PurchaseStatus.restored)],
        [_purchase('t', PurchaseStatus.restored)],
      ];
      await h.start();
      await settle();
      expect(h.verifyCalls, ['t'], reason: 'server says the payment is pending');
      expect(h.fake.completed, isEmpty, reason: 'never acknowledged while pending');
      expect(h.entitlementCalls, 0);
      paid = true;

      // App 切到后台，pending 在后台完成，用户几秒内回到前台：
      // 距离上一次查询远不足一分钟，仍必须再次查询并验证。
      h.service.didChangeAppLifecycleState(AppLifecycleState.paused);
      h.service.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await settle();

      expect(h.fake.restoreCalls, 2);
      expect(h.verifyCalls, ['t', 't'], reason: 'not cached while unverified');
      expect(h.entitlementCalls, 1);
      expect(h.fake.completed.map(_token), ['t']);
    });

    test('every real resume triggers a query, with no time-based throttle',
        () async {
      h = _Harness();
      await h.start();
      await settle();
      expect(h.fake.restoreCalls, 1, reason: 'startup / sign-in query');

      // 两次真实 resume 紧挨着发生（远小于 60 秒）：两次都必须查询。
      h.service.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await settle();
      h.service.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await settle();

      expect(h.fake.restoreCalls, 3);
    });

    test('a resume during a running query is single-flight plus one trailing',
        () async {
      h = _Harness();
      h.fake.restoreGate = Completer<void>();
      await h.start();
      await settle();
      expect(h.fake.restoreCalls, 1, reason: 'first query is now running');

      // 查询执行期间发生 resume（两次）+ 登录事件：不得并发，且合并为一次尾随查询。
      h.service.didChangeAppLifecycleState(AppLifecycleState.resumed);
      h.service.didChangeAppLifecycleState(AppLifecycleState.resumed);
      h.auth.add('uid-1');
      await settle();
      expect(h.fake.restoreCalls, 1, reason: 'no second concurrent query');
      expect(h.fake.maxConcurrentRestores, 1);

      final gate = h.fake.restoreGate!;
      h.fake.restoreGate = null; // 之后的查询不再阻塞
      gate.complete();
      await settle();

      expect(h.fake.restoreCalls, 2, reason: 'exactly one trailing query');
      expect(h.fake.maxConcurrentRestores, 1);

      // 尾随查询结束后不会自行再查。
      await settle();
      expect(h.fake.restoreCalls, 2);
    });

    test(
        'a purchase that appears during a running query is caught by the trailing query',
        () async {
      h = _Harness();
      h.fake.restoreGate = Completer<void>();
      h.fake.restoreScript = [
        <PurchaseDetails>[], // 第一次查询时还没有购买
        [_purchase('late', PurchaseStatus.restored)],
      ];
      await h.start();
      await settle();

      h.service.didChangeAppLifecycleState(AppLifecycleState.resumed);
      final gate = h.fake.restoreGate!;
      h.fake.restoreGate = null;
      gate.complete();
      await settle();

      expect(h.verifyCalls, ['late']);
      expect(h.fake.completed.map(_token), ['late']);
    });

    test(
        'a trigger while signed out never queries, and a queued trailing sync is dropped after sign-out',
        () async {
      h = _Harness();
      h.fake.restoreGate = Completer<void>();
      await h.start();
      await settle();
      expect(h.fake.restoreCalls, 1);

      h.service.didChangeAppLifecycleState(AppLifecycleState.resumed); // queued
      h.uid = null; // 退出登录
      final gate = h.fake.restoreGate!;
      h.fake.restoreGate = null;
      gate.complete();
      await settle();

      expect(h.fake.restoreCalls, 1, reason: 'signed out: trailing dropped');
      h.service.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await settle();
      expect(h.fake.restoreCalls, 1);
    });

    test('the same token from every source is processed exactly once',
        () async {
      h = _Harness();
      final gate = Completer<bool>();
      h.verifyImpl = (_) => gate.future;
      h.fake.restoreScript = [
        [_purchase('dup', PurchaseStatus.restored)],
      ];
      final events = <IapVerifiedEvent>[];
      await h.start();
      h.service.verifiedPurchases.listen(events.add);
      await settle();

      // startup query (script #1) + live stream + another live stream
      h.fake.controller.add([_purchase('dup', PurchaseStatus.purchased)]);
      h.fake.controller.add([_purchase('dup', PurchaseStatus.restored)]);
      await settle();
      expect(h.verifyCalls, ['dup'], reason: 'in-flight token is joined');

      gate.complete(true);
      await settle();

      // Later foreground query and a late stream re-delivery.
      h.fake.restoreScript = [
        [_purchase('dup', PurchaseStatus.restored)],
      ];
      h.fake.restoreCalls = 0;
      h.service.didChangeAppLifecycleState(AppLifecycleState.resumed);
      h.fake.controller.add([_purchase('dup', PurchaseStatus.purchased)]);
      await settle();

      expect(h.verifyCalls, ['dup']);
      expect(h.entitlementCalls, 1);
      expect(events, hasLength(1));
      expect(h.fake.completed.map(_token), ['dup']);
    });

    test('different tokens are verified one at a time', () async {
      h = _Harness();
      final gateA = Completer<bool>();
      h.verifyImpl =
          (token) => token == 'A' ? gateA.future : Future.value(true);
      await h.start();
      await settle();

      h.fake.controller.add([
        _purchase('A', PurchaseStatus.restored),
        _purchase('B', PurchaseStatus.restored),
      ]);
      await settle();
      expect(h.verifyCalls, ['A'], reason: 'B waits for A');

      gateA.complete(true);
      await settle();
      expect(h.verifyCalls, ['A', 'B']);
      expect(h.fake.completed.map(_token), ['A', 'B']);
    });

    test('a rejected verification stays unacknowledged and retries later',
        () async {
      h = _Harness();
      h.verifyImpl = (_) async => false;
      await h.start();
      await settle();

      h.fake.controller.add([_purchase('t', PurchaseStatus.purchased)]);
      await settle();
      expect(h.verifyCalls, ['t']);
      expect(h.fake.completed, isEmpty);
      expect(h.entitlementCalls, 0);
      expect(h.service.errorMessage, isNull, reason: 'background is silent');

      h.verifyImpl = (_) async => true;
      h.fake.restoreScript = [
        [_purchase('t', PurchaseStatus.restored)],
      ];
      h.fake.restoreCalls = 0;
      h.service.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await settle();

      expect(h.verifyCalls, ['t', 't']);
      expect(h.fake.completed.map(_token), ['t']);
      expect(h.entitlementCalls, 1);
    });
  });

  group('Account handling', () {
    test('a signed-out user never binds, verifies or acknowledges a purchase',
        () async {
      h = _Harness(uid: null);
      await h.start();
      await settle();

      h.fake.controller.add([_purchase('x', PurchaseStatus.purchased)]);
      await settle();

      expect(h.fake.restoreCalls, 0, reason: 'no query while signed out');
      expect(h.verifyCalls, isEmpty);
      expect(h.fake.completed, isEmpty);
      expect(h.entitlementCalls, 0);
    });

    test('after sign-in the current account purchase is processed', () async {
      h = _Harness(uid: null);
      await h.start();
      h.fake.controller.add([_purchase('x', PurchaseStatus.purchased)]);
      await settle();
      expect(h.verifyCalls, isEmpty);

      h.fake.restoreScript = [
        [_purchase('x', PurchaseStatus.restored)],
      ];
      h.signIn('uid-1');
      await settle();

      expect(h.fake.restoreCalls, 1);
      expect(h.verifyCalls, ['x']);
      expect(h.entitlementCalls, 1);
      expect(h.fake.completed.map(_token), ['x']);
    });

    test('switching account mid-verification records and acknowledges nothing',
        () async {
      h = _Harness();
      final gate = Completer<bool>();
      h.verifyImpl = (_) => gate.future;
      await h.start();
      await settle();

      h.fake.controller.add([_purchase('t', PurchaseStatus.purchased)]);
      await settle();
      h.uid = 'uid-2'; // account changed while the server call is running
      gate.complete(true);
      await settle();

      expect(h.entitlementCalls, 0);
      expect(h.fake.completed, isEmpty);
    });

    test(
        'the same token under two accounts never shares an in-flight verification',
        () async {
      h = _Harness();
      final gateUid1 = Completer<bool>();
      var calls = 0;
      h.verifyImpl = (_) => ++calls == 1 ? gateUid1.future : Future.value(true);
      await h.start();
      await settle();

      h.fake.controller.add([_purchase('T', PurchaseStatus.purchased)]);
      await settle();
      expect(h.verifyUids, ['uid-1'], reason: 'uid-1 is verifying, gated');

      // 账号在 Auth 事件到达之前就已切换（异步窗口）：同一 token 不能复用 uid-1 的 Future，
      // 也不能被 uid-1 的慢请求阻塞。
      h.uid = 'uid-2';
      h.fake.controller.add([_purchase('T', PurchaseStatus.purchased)]);
      await settle();

      expect(h.verifyCalls, ['T', 'T']);
      expect(h.verifyUids, ['uid-1', 'uid-2']);
      expect(h.entitlementCalls, 1, reason: 'uid-2 finished independently');
      expect(h.fake.completed.map(_token), ['T']);

      // uid-1 的旧请求之后才完成：自然结束，但不污染 uid-2。
      gateUid1.complete(true);
      await settle();
      expect(h.entitlementCalls, 1);
      expect(h.fake.completed, hasLength(1));
    });

    test('a job queued under account A never sends a request once the user is B',
        () async {
      h = _Harness();
      final gateFirst = Completer<bool>();
      h.verifyImpl =
          (token) => token == 'first' ? gateFirst.future : Future.value(true);
      await h.start();
      await settle();

      // A 的队列：'first' 正在验证（被卡住），'T' 已入队但尚未开始执行。
      h.fake.controller.add([_purchase('first', PurchaseStatus.purchased)]);
      await settle();
      h.fake.controller.add([_purchase('T', PurchaseStatus.purchased)]);
      await settle();
      expect(h.verifyCalls, ['first'], reason: "'T' is queued behind 'first'");

      // 在 'T' 的 job 开始执行之前切换到 B，然后放行 A 队列。
      h.uid = 'uid-2';
      gateFirst.complete(true);
      await settle();

      // 旧账号排队的 job 根本没有调用 PurchaseVerificationService。
      expect(h.verifyCalls, ['first'],
          reason: 'stale job for A must not use B credentials');
      expect(h.verifyUids, ['uid-1']);
      expect(h.entitlementCalls, 0);
      expect(h.fake.completed, isEmpty);

      // B 之后通过自己的同步独立正常处理。
      h.fake.restoreScript = [
        [_purchase('T', PurchaseStatus.restored)],
      ];
      h.fake.restoreCalls = 0;
      h.signIn('uid-2');
      await settle();

      expect(h.verifyCalls, ['first', 'T']);
      expect(h.verifyUids, ['uid-1', 'uid-2']);
      expect(h.entitlementCalls, 1);
      expect(h.fake.completed.map(_token), ['T']);
    });

    test(
        'a token verified for one account is not treated as verified for another',
        () async {
      h = _Harness();
      await h.start();
      h.fake.controller.add([_purchase('t', PurchaseStatus.purchased)]);
      await settle();
      expect(h.verifyUids, ['uid-1']);

      h.uid = 'uid-2'; // 没有任何 Auth 事件，只是 currentUser 变了
      h.fake.controller.add([_purchase('t', PurchaseStatus.purchased)]);
      await settle();

      expect(h.verifyUids, ['uid-1', 'uid-2']);
    });

    test('a new account does not reuse the previous account verification cache',
        () async {
      h = _Harness();
      await h.start();
      h.fake.controller.add([_purchase('t', PurchaseStatus.purchased)]);
      await settle();
      expect(h.verifyCalls, ['t']);

      h.fake.restoreScript = [
        [_purchase('t', PurchaseStatus.restored)],
      ];
      h.fake.restoreCalls = 0;
      h.signIn('uid-2');
      await settle();

      expect(h.verifyCalls, ['t', 't'], reason: 'server re-checks ownership');
    });
  });

  group('Manual restore', () {
    test('restores a purchase and reports success', () async {
      h = _Harness();
      await h.start();
      await settle();
      h.fake.restoreScript = [
        [_purchase('t', PurchaseStatus.restored)],
      ];
      h.fake.restoreCalls = 0;

      final restored = await h.service.restorePurchases();

      expect(restored, isTrue);
      expect(h.verifyCalls, ['t']);
      expect(h.service.isRestoring, isFalse);
      expect(h.fake.completed.map(_token), ['t']);
    });

    test('an empty result is "not found" without an error message', () async {
      h = _Harness();
      await h.start();
      await settle();
      h.fake.restoreScript = [<PurchaseDetails>[]];
      h.fake.restoreCalls = 0;

      expect(await h.service.restorePurchases(), isFalse);
      expect(h.service.errorMessage, isNull);
    });

    test('slow verification is not mistaken for "no purchase"', () async {
      h = _Harness(restoreBatchTimeout: const Duration(milliseconds: 10));
      h.verifyImpl = (_) async {
        await Future<void>.delayed(const Duration(milliseconds: 300));
        return true;
      };
      await h.start();
      await settle();
      h.fake.restoreScript = [
        [_purchase('slow', PurchaseStatus.restored)],
      ];
      h.fake.restoreCalls = 0;

      final pending = h.service.restorePurchases();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(h.service.isRestoring, isTrue, reason: 'still waiting for server');

      expect(await pending, isTrue);
      expect(h.verifyCalls, ['slow']);
    });

    test('a failed verification surfaces an error and returns false', () async {
      h = _Harness();
      h.verifyImpl = (_) async => false;
      await h.start();
      await settle();
      h.fake.restoreScript = [
        [_purchase('bad', PurchaseStatus.restored)],
      ];
      h.fake.restoreCalls = 0;

      expect(await h.service.restorePurchases(), isFalse);
      expect(h.service.errorMessage, isNotNull);
      expect(h.fake.completed, isEmpty);
    });

    test('re-verifies with the server even if the token was verified before',
        () async {
      h = _Harness();
      await h.start();
      h.fake.controller.add([_purchase('t', PurchaseStatus.purchased)]);
      await settle();
      expect(h.verifyCalls, ['t']);

      h.fake.restoreScript = [
        [_purchase('t', PurchaseStatus.restored)],
      ];
      h.fake.restoreCalls = 0;
      expect(await h.service.restorePurchases(), isTrue);
      expect(h.verifyCalls, ['t', 't']);
    });

    test('gives up only if Play never delivers the local query result',
        () async {
      h = _Harness(restoreBatchTimeout: const Duration(milliseconds: 20));
      await h.start();
      await settle();
      h.fake.emitOnRestore = false;

      expect(await h.service.restorePurchases(), isFalse);
      expect(h.service.isRestoring, isFalse);
    });
  });

  group('Purchase flow', () {
    test('binds the purchase to sha256(uid) and flags user-initiated success',
        () async {
      h = _Harness();
      await h.start();
      await h.service.loadProducts();
      final events = <IapVerifiedEvent>[];
      h.service.verifiedPurchases.listen(events.add);

      await h.service.buyMonthly();
      expect(h.service.isBuying, isTrue);
      expect(
        h.fake.lastBuy!.applicationUserName,
        sha256.convert(utf8.encode('uid-1')).toString(),
      );
      expect(
        h.fake.lastBuy!.productDetails.id,
        AppConfig.monthlySubscriptionProductId,
      );

      h.fake.controller.add([_purchase('new', PurchaseStatus.purchased)]);
      await settle();

      expect(h.verifyCalls, ['new']);
      expect(events.single.userInitiatedPurchase, isTrue);
      expect(h.service.isBuying, isFalse);
    });

    test('a purchase found in the background is not a user-initiated success',
        () async {
      h = _Harness();
      final events = <IapVerifiedEvent>[];
      h.fake.restoreScript = [
        [_purchase('bg', PurchaseStatus.restored)],
      ];
      h.service.verifiedPurchases.listen(events.add);
      await h.start();
      await settle();

      expect(events.single.userInitiatedPurchase, isFalse);
    });

    test('buying while signed out is refused before reaching Play', () async {
      h = _Harness(uid: null);
      await h.start();
      await h.service.loadProducts();

      await h.service.buyMonthly();

      expect(h.fake.lastBuy, isNull);
      expect(h.service.errorMessage, isNotNull);
      expect(h.service.isBuying, isFalse);
    });

    test('canceling the Play sheet releases the purchase lock', () async {
      h = _Harness();
      await h.start();
      await h.service.loadProducts();
      await h.service.buyMonthly();
      expect(h.service.isBuying, isTrue);

      h.fake.controller.add([_purchase('c', PurchaseStatus.canceled)]);
      await settle();

      expect(h.service.isBuying, isFalse);
      expect(h.verifyCalls, isEmpty);
    });

    test('a second buy while one is active is ignored', () async {
      h = _Harness();
      await h.start();
      await h.service.loadProducts();
      await h.service.buyMonthly();
      h.fake.lastBuy = null;

      await h.service.buyMonthly();

      expect(h.fake.lastBuy, isNull);
    });
  });

  group('Android results without a product (P1 regression)', () {
    Future<void> startBuying() async {
      h = _Harness();
      await h.start();
      await h.service.loadProducts();
      await h.service.buyMonthly();
      expect(h.service.isBuying, isTrue);
    }

    test('canceling the Play sheet with an empty productID releases the lock',
        () async {
      await startBuying();

      h.fake.controller.add([_resultWithoutProduct(PurchaseStatus.canceled)]);
      await settle();

      expect(h.service.isBuying, isFalse);
      expect(h.service.isPurchasing, isFalse);
      expect(h.service.errorMessage, isNull, reason: 'cancel is not an error');
      expect(h.verifyCalls, isEmpty);
      expect(h.fake.completed, isEmpty);

      // 同一会话内可以再次发起购买。
      h.fake.lastBuy = null;
      await h.service.buyMonthly();
      expect(h.fake.lastBuy, isNotNull);
    });

    test('a purchase error with an empty productID releases the lock',
        () async {
      await startBuying();

      h.fake.controller.add([_resultWithoutProduct(PurchaseStatus.error)]);
      await settle();

      expect(h.service.isBuying, isFalse);
      expect(h.service.errorMessage, isNotNull);
      expect(h.service.errorMessage, isNot(contains('BillingResponse')));
      expect(h.verifyCalls, isEmpty);
      expect(h.fake.completed, isEmpty);
    });

    test('after a cancel, a normal purchase is still verified and completed',
        () async {
      await startBuying();
      h.fake.controller.add([_resultWithoutProduct(PurchaseStatus.canceled)]);
      await settle();

      final events = <IapVerifiedEvent>[];
      h.service.verifiedPurchases.listen(events.add);
      await h.service.buyMonthly();
      h.fake.controller.add([_purchase('ok', PurchaseStatus.purchased)]);
      await settle();

      expect(h.verifyCalls, ['ok']);
      expect(h.fake.completed.map(_token), ['ok']);
      expect(events.single.userInitiatedPurchase, isTrue);
      expect(h.service.isBuying, isFalse);
    });

    test('after a cancel, manual restore works and still verifies', () async {
      await startBuying();
      h.fake.controller.add([_resultWithoutProduct(PurchaseStatus.canceled)]);
      await settle();

      h.fake.restoreScript = [
        [_purchase('r', PurchaseStatus.restored)],
      ];
      h.fake.restoreCalls = 0;
      expect(await h.service.restorePurchases(), isTrue);
      expect(h.verifyCalls, ['r']);
      expect(h.fake.completed.map(_token), ['r']);
      expect(h.service.isPurchasing, isFalse);
    });

    test('an empty-product result never reaches verification', () async {
      await startBuying();

      // responseCode 为 ok 但没有购买：插件同样给出空商品，状态为 purchased。
      h.fake.controller.add([_resultWithoutProduct(PurchaseStatus.purchased)]);
      await settle();

      expect(h.verifyCalls, isEmpty);
      expect(h.fake.completed, isEmpty);
      expect(h.service.isBuying, isTrue, reason: 'not treated as a cancel');
    });

    test('pending is not treated as a cancel', () async {
      await startBuying();

      h.fake.controller.add([_purchase('p', PurchaseStatus.pending)]);
      h.fake.controller.add([_resultWithoutProduct(PurchaseStatus.pending)]);
      await settle();

      expect(h.service.isBuying, isTrue);
      expect(h.verifyCalls, isEmpty);
    });

    test('an empty-product cancel does not interrupt a running verification',
        () async {
      await startBuying();
      final gate = Completer<bool>();
      h.verifyImpl = (_) => gate.future;

      h.fake.controller.add([_purchase('v', PurchaseStatus.purchased)]);
      await settle();
      expect(h.verifyCalls, ['v']);

      h.fake.controller.add([_resultWithoutProduct(PurchaseStatus.canceled)]);
      h.fake.controller.add([_resultWithoutProduct(PurchaseStatus.error)]);
      await settle();
      expect(h.service.isBuying, isTrue, reason: 'still verifying');
      expect(h.service.errorMessage, isNull);

      gate.complete(true);
      await settle();
      expect(h.service.isBuying, isFalse);
      expect(h.fake.completed.map(_token), ['v']);
      expect(h.entitlementCalls, 1);
    });

    test('empty-product results outside a purchase change nothing', () async {
      h = _Harness();
      await h.start();
      await settle();

      h.fake.controller.add([_resultWithoutProduct(PurchaseStatus.canceled)]);
      h.fake.controller.add([_resultWithoutProduct(PurchaseStatus.error)]);
      await settle();

      expect(h.service.isPurchasing, isFalse);
      expect(h.service.errorMessage, isNull);
      expect(h.verifyCalls, isEmpty);
    });

    test('an empty-product result does not abort a manual restore', () async {
      h = _Harness(restoreBatchTimeout: const Duration(seconds: 5));
      await h.start();
      await settle();
      h.fake.restoreGate = Completer<void>();
      h.fake.restoreScript = [
        [_purchase('r', PurchaseStatus.restored)],
      ];
      h.fake.restoreCalls = 0;

      final pending = h.service.restorePurchases();
      await settle();
      h.fake.controller.add([_resultWithoutProduct(PurchaseStatus.canceled)]);
      await settle();
      expect(h.service.isRestoring, isTrue);

      final gate = h.fake.restoreGate!;
      h.fake.restoreGate = null;
      gate.complete();
      expect(await pending, isTrue);
      expect(h.verifyCalls, ['r']);
    });

    test('events for an unrelated product neither release nor verify',
        () async {
      await startBuying();

      h.fake.controller.add([
        _otherProduct('x1', PurchaseStatus.canceled),
        _otherProduct('x2', PurchaseStatus.error),
        _otherProduct('x3', PurchaseStatus.purchased),
      ]);
      await settle();

      expect(h.service.isBuying, isTrue);
      expect(h.service.errorMessage, isNull);
      expect(h.verifyCalls, isEmpty);
      expect(h.fake.completed, isEmpty);
    });
  });

  group('Purchase-flow verification retry (K1)', () {
    const unknown = PurchaseVerificationResult.unknown('network');
    late _FakeTimers timers;

    Future<void> buy(String token) async {
      await h.service.loadProducts();
      await h.service.buyMonthly();
      h.fake.controller.add([_purchase(token, PurchaseStatus.purchased)]);
      await settle();
    }

    Future<void> fire() async {
      timers.active.first.fire();
      await settle();
    }

    setUp(() => timers = _FakeTimers());

    test('an unknown result is retried and a later success completes once',
        () async {
      h = _Harness(retryTimerFactory: timers.create);
      final results = [unknown, const PurchaseVerificationResult.verified()];
      h.checkImpl = (_) async => results.removeAt(0);
      await h.start();
      final events = <IapVerifiedEvent>[];
      h.service.verifiedPurchases.listen(events.add);

      await buy('k1');
      expect(h.verifyCalls, ['k1']);
      expect(h.fake.completed, isEmpty,
          reason: 'never acknowledged unverified');
      expect(h.service.errorMessage,
          AppStrings.get('iap_purchase_verification_pending'));
      expect(h.service.isBuying, isFalse, reason: 'buttons are released');
      expect(timers.active.single.duration, const Duration(seconds: 5));

      await fire();
      expect(h.verifyCalls, ['k1', 'k1']);
      expect(h.fake.completed.map(_token), ['k1']);
      expect(events.single.userInitiatedPurchase, isTrue);
      expect(h.entitlementCalls, 1);
      expect(timers.active, isEmpty);
    });

    test('a persistent unknown stops after 5 / 15 / 45 s and stays unacked',
        () async {
      h = _Harness(retryTimerFactory: timers.create);
      h.checkImpl = (_) async => unknown;
      await h.start();

      await buy('k1');
      for (final seconds in [5, 15, 45]) {
        expect(timers.active.single.duration, Duration(seconds: seconds));
        await fire();
      }
      expect(h.verifyCalls, ['k1', 'k1', 'k1', 'k1']);
      expect(timers.active, isEmpty);
      expect(h.fake.completed, isEmpty);
      expect(h.entitlementCalls, 0);
    });

    test('403 is not retried and gets its own message', () async {
      h = _Harness(retryTimerFactory: timers.create);
      h.checkImpl =
          (_) async => const PurchaseVerificationResult.rejected('403');
      await h.start();

      await buy('k1');
      expect(h.verifyCalls, ['k1']);
      expect(timers.active, isEmpty);
      expect(h.service.errorMessage,
          AppStrings.get('iap_purchase_verification_rejected'));
      expect(h.fake.completed, isEmpty);
    });

    test('a server answer of "inactive" is not retried', () async {
      h = _Harness(retryTimerFactory: timers.create);
      h.checkImpl =
          (_) async => const PurchaseVerificationResult.inactive('PENDING');
      await h.start();

      await buy('k1');
      expect(h.verifyCalls, ['k1']);
      expect(timers.active, isEmpty);
    });

    test('background results are not retried (resume handles them)', () async {
      h = _Harness(retryTimerFactory: timers.create);
      h.checkImpl = (_) async => unknown;
      await h.start();

      h.fake.controller.add([_purchase('bg', PurchaseStatus.purchased)]);
      await settle();
      expect(h.verifyCalls, ['bg']);
      expect(timers.active, isEmpty);
      expect(h.service.errorMessage, isNull);
    });

    test('switching account cancels the pending retry', () async {
      h = _Harness(retryTimerFactory: timers.create);
      h.checkImpl = (_) async => unknown;
      await h.start();

      await buy('k1');
      expect(timers.active, hasLength(1));
      h.signIn('uid-2');
      await settle();
      expect(timers.active, isEmpty);
      expect(h.verifyUids, ['uid-1'], reason: 'never retried as uid-2');
    });

    test('dispose cancels the pending retry', () async {
      h = _Harness(retryTimerFactory: timers.create);
      h.checkImpl = (_) async => unknown;
      await h.start();

      await buy('k1');
      final timer = timers.active.single;
      h.service.dispose();
      expect(timer.isActive, isFalse);
      timer.fire();
      await settle();
      expect(h.verifyCalls, ['k1']);
      // tearDown 会再 dispose 一次：换成新的 harness，旧的在这里收尾。
      final old = h;
      h = _Harness();
      await old.auth.close();
      await old.fake.controller.close();
    });

    test('a resume that verifies first makes the retry a no-op', () async {
      h = _Harness(retryTimerFactory: timers.create);
      h.checkImpl = (_) async => unknown;
      await h.start();

      await buy('k1');
      h.checkImpl = (_) async => const PurchaseVerificationResult.verified();
      h.fake.restoreScript = [
        [_purchase('k1', PurchaseStatus.restored)],
      ];
      h.fake.restoreCalls = 0;
      h.service.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await settle();
      expect(h.verifyCalls, ['k1', 'k1']);

      await fire();
      expect(h.verifyCalls, ['k1', 'k1'], reason: 'no request after success');
      expect(h.fake.completed.map(_token), ['k1']);
      expect(timers.active, isEmpty);
    });

    test('a retry and a manual restore share one in-flight request', () async {
      h = _Harness(retryTimerFactory: timers.create);
      h.checkImpl = (_) async => unknown;
      await h.start();
      await buy('k1');

      final gate = Completer<PurchaseVerificationResult>();
      h.checkImpl = (_) => gate.future;
      await fire(); // 重试请求进行中
      h.fake.restoreScript = [
        [_purchase('k1', PurchaseStatus.restored)],
      ];
      h.fake.restoreCalls = 0;
      final restored = h.service.restorePurchases();
      await settle();
      expect(h.verifyCalls, ['k1', 'k1'], reason: 'restore joined the retry');

      gate.complete(const PurchaseVerificationResult.verified());
      expect(await restored, isTrue);
      await settle();
      expect(h.verifyCalls, ['k1', 'k1']);
      expect(h.fake.completed.map(_token), ['k1']);
      expect(timers.active, isEmpty);
    });
  });

  group('Renewal check (P2)', () {
    const account = AccountEntitlement(
      isVip: false,
      expiresAtMs: 0,
      pendingRenewal: true,
      pendingExpiresAtMs: 1,
    );

    Future<void> startVerified(String token) async {
      h = _Harness();
      await h.start();
      h.fake.controller.add([_purchase(token, PurchaseStatus.purchased)]);
      await settle();
      expect(h.verifyCalls, [token]);
    }

    test('bypasses the verified-token cache and re-asks the server', () async {
      await startVerified('t');
      h.fake.restoreScript = [
        [_purchase('t', PurchaseStatus.restored)],
      ];
      h.fake.restoreCalls = 0;

      expect(await h.service.checkRenewal('uid-1'),
          RenewalCheckOutcome.confirmedActive);
      expect(h.verifyCalls, ['t', 't']);
    });

    test('concurrent checks for one account share one query and one request',
        () async {
      await startVerified('t');
      final gate = Completer<PurchaseVerificationResult>();
      h.checkImpl = (_) => gate.future;
      h.fake.restoreScript = [
        [_purchase('t', PurchaseStatus.restored)],
      ];
      h.fake.restoreCalls = 0;

      final a = h.service.checkRenewal('uid-1');
      final b = h.service.checkRenewal('uid-1');
      h.service.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await settle();
      final c = h.service.checkRenewal('uid-1');
      expect(identical(a, b), isTrue);
      expect(identical(a, c), isTrue);

      gate.complete(const PurchaseVerificationResult.verified());
      expect(await a, RenewalCheckOutcome.confirmedActive);
      expect(h.verifyCalls.where((t) => t == 't'), hasLength(2),
          reason: 'initial purchase + exactly one renewal request');
    });

    test('a failed Play query is unknown, never "no purchase"', () async {
      await startVerified('t');
      h.fake.restoreError = StateError('BillingResponse.serviceUnavailable');

      expect(await h.service.checkRenewal('uid-1'), RenewalCheckOutcome.unknown);
      expect(h.verifyCalls, ['t']);
    });

    test('a successful empty query is "no local purchase"', () async {
      await startVerified('t');
      h.fake.restoreScript = [<PurchaseDetails>[]];
      h.fake.restoreCalls = 0;

      expect(await h.service.checkRenewal('uid-1'),
          RenewalCheckOutcome.noLocalPurchase);
    });

    test('a batch that never arrives is unknown', () async {
      h = _Harness(restoreBatchTimeout: const Duration(milliseconds: 20));
      await h.start();
      await settle();
      h.fake.emitOnRestore = false;

      expect(await h.service.checkRenewal('uid-1'), RenewalCheckOutcome.unknown);
    });

    test('server outcomes map to unknown / answered / confirmedActive',
        () async {
      await startVerified('t');
      Future<RenewalCheckOutcome> run(PurchaseVerificationResult r) {
        h.checkImpl = (_) async => r;
        h.fake.restoreScript = [
          [_purchase('t', PurchaseStatus.restored)],
        ];
        h.fake.restoreCalls = 0;
        return h.service.checkRenewal('uid-1');
      }

      expect(await run(const PurchaseVerificationResult.unknown('503')),
          RenewalCheckOutcome.unknown);
      expect(await run(const PurchaseVerificationResult.rejected('403')),
          RenewalCheckOutcome.answered);
      expect(
          await run(const PurchaseVerificationResult.inactive('pending',
              account: account)),
          RenewalCheckOutcome.answered);
      expect(await run(const PurchaseVerificationResult.verified()),
          RenewalCheckOutcome.confirmedActive);
    });

    test('an unknown server answer never acknowledges or caches the token',
        () async {
      h = _Harness();
      h.checkImpl = (_) async => const PurchaseVerificationResult.unknown('x');
      h.fake.restoreScript = [
        <PurchaseDetails>[],
        [_purchase('t', PurchaseStatus.restored)],
      ];
      await h.start();
      await settle();

      expect(await h.service.checkRenewal('uid-1'), RenewalCheckOutcome.unknown);
      expect(h.fake.completed, isEmpty);
      expect(h.entitlementCalls, 0);
    });

    test('switching account during a check discards the result', () async {
      await startVerified('t');
      final gate = Completer<PurchaseVerificationResult>();
      h.checkImpl = (_) => gate.future;
      h.fake.restoreScript = [
        [_purchase('t', PurchaseStatus.restored)],
      ];
      h.fake.restoreCalls = 0;

      final pending = h.service.checkRenewal('uid-1');
      await settle();
      h.uid = 'uid-2';
      gate.complete(const PurchaseVerificationResult.verified());

      expect(await pending, RenewalCheckOutcome.discarded);
      expect(await h.service.checkRenewal('uid-1'),
          RenewalCheckOutcome.discarded,
          reason: 'a stale uid is never checked');
    });

    test('a disposed service reports discarded', () async {
      await startVerified('t');
      final gate = Completer<void>();
      h.fake.restoreGate = gate;
      final pending = h.service.checkRenewal('uid-1');
      await settle();
      h.service.dispose();
      h.fake.restoreGate = null;
      gate.complete();
      expect(await pending, RenewalCheckOutcome.discarded);
      // tearDown 会再 dispose 一次：换成新的 harness，旧的在这里收尾。
      final old = h;
      h = _Harness();
      await old.auth.close();
      await old.fake.controller.close();
    });

    test('onResumed is forwarded to the entitlement layer', () async {
      h = _Harness();
      var resumed = 0;
      await h.service.start(
        onEntitlementActive: () async {},
        onResumed: () => resumed++,
      );
      h.service.didChangeAppLifecycleState(AppLifecycleState.resumed);
      h.service.didChangeAppLifecycleState(AppLifecycleState.paused);
      expect(resumed, 1);
    });
  });

  group('Query correlation without request IDs (P2)', () {
    test('a late batch after a caller timeout is not claimed by the next query',
        () async {
      h = _Harness(queryTimeout: const Duration(milliseconds: 30));
      await h.start();
      await settle();
      h.fake.restoreGate = Completer<void>();
      h.fake.restoreScript = [
        [_purchase('late', PurchaseStatus.restored)], // belongs to query #1
        <PurchaseDetails>[], // query #2: nothing owned
      ];
      h.fake.restoreCalls = 0;

      final first = h.service.checkRenewal('uid-1');
      expect(await first, RenewalCheckOutcome.unknown, reason: 'timed out');
      final second = h.service.checkRenewal('uid-1');

      final gate = h.fake.restoreGate!;
      h.fake.restoreGate = null;
      gate.complete();
      await settle();

      expect(await second, RenewalCheckOutcome.noLocalPurchase,
          reason: 'query #2 gets its own (empty) batch, not the late one');
      expect(h.fake.maxConcurrentRestores, 1, reason: 'queries are serialized');
      expect(h.verifyCalls, ['late'], reason: 'late batch handled in background');
    });

    test('background sync and manual restore each get their own batch',
        () async {
      h = _Harness();
      h.fake.restoreGate = Completer<void>();
      h.fake.restoreScript = [
        <PurchaseDetails>[], // startup sync
        [_purchase('r', PurchaseStatus.restored)], // manual restore
      ];
      await h.start();
      await settle();
      final restore = h.service.restorePurchases();

      final gate = h.fake.restoreGate!;
      h.fake.restoreGate = null;
      gate.complete();

      expect(await restore, isTrue);
      expect(h.verifyCalls, ['r']);
      expect(h.fake.maxConcurrentRestores, 1);
    });

    test('a manual restore reports a Play failure instead of "not found"',
        () async {
      h = _Harness();
      await h.start();
      await settle();
      h.fake.restoreError = StateError('BillingResponse.serviceUnavailable');

      expect(await h.service.restorePurchases(), isFalse);
      expect(h.service.errorMessage, contains('serviceUnavailable'));
      expect(h.service.isRestoring, isFalse);
    });
  });

  group('Live pending events never claim a query batch (R4-2)', () {
    test('manual restore: pending arrives first, the real batch later',
        () async {
      h = _Harness();
      await h.start();
      await settle();
      h.fake.restoreGate = Completer<void>();
      h.fake.restoreScript = [
        [_purchase('r', PurchaseStatus.restored)],
      ];
      h.fake.restoreCalls = 0;

      final restore = h.service.restorePurchases();
      await settle();
      // 另一笔购买流程的 pending 实时事件先到达。
      h.fake.controller.add([_purchase('p', PurchaseStatus.pending)]);
      await settle();
      expect(h.service.isRestoring, isTrue, reason: 'still waiting for its batch');

      final gate = h.fake.restoreGate!;
      h.fake.restoreGate = null;
      gate.complete();

      expect(await restore, isTrue);
      expect(h.verifyCalls, ['r']);
      expect(h.fake.completed.map(_token), ['r']);
    });

    test('renewal check: pending first, then the batch; the cache is bypassed',
        () async {
      h = _Harness();
      await h.start();
      h.fake.controller.add([_purchase('t', PurchaseStatus.purchased)]);
      await settle();
      expect(h.verifyCalls, ['t'], reason: 't is now in the verified cache');

      h.fake.restoreGate = Completer<void>();
      h.fake.restoreScript = [
        [_purchase('t', PurchaseStatus.restored)],
      ];
      h.fake.restoreCalls = 0;
      final check = h.service.checkRenewal('uid-1');
      await settle();
      h.fake.controller.add([_purchase('p', PurchaseStatus.pending)]);
      await settle();

      final gate = h.fake.restoreGate!;
      h.fake.restoreGate = null;
      gate.complete();

      expect(await check, RenewalCheckOutcome.confirmedActive);
      expect(h.verifyCalls, ['t', 't'], reason: 'server re-asked despite cache');
    });

    test('a pending purchase flow is still handled as pending, not as a result',
        () async {
      h = _Harness();
      await h.start();
      await h.service.loadProducts();
      h.fake.restoreGate = Completer<void>();
      final sync = h.service.syncPurchases();
      await settle();
      await h.service.buyMonthly(); // 查询等待期间用户发起购买
      h.fake.controller.add([_purchase('p', PurchaseStatus.pending)]);
      await settle();
      expect(h.service.isBuying, isTrue, reason: 'pending keeps the purchase open');

      final gate = h.fake.restoreGate!;
      h.fake.restoreGate = null;
      gate.complete();
      await sync;
      h.fake.controller.add([_purchase('p', PurchaseStatus.purchased)]);
      await settle();
      expect(h.verifyCalls, ['p']);
      expect(h.service.isBuying, isFalse);
    });
  });

  group('Platforms where billing is not enabled', () {
    test('start / sync / restore never touch the IAP platform', () async {
      h = _Harness(supported: false);
      await h.start();
      await settle();
      h.service.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await h.service.syncPurchases();

      expect(h.fake.controller.hasListener, isFalse);
      expect(h.fake.restoreCalls, 0);
      expect(await h.service.restorePurchases(), isFalse);
      expect(h.service.errorMessage, isNotNull);
      expect(h.fake.touches, 0);
    });

    test('loadProducts does not touch the IAP platform and reports unavailable',
        () async {
      h = _Harness(supported: false);

      await h.service.loadProducts();

      expect(h.fake.touches, 0, reason: 'no isAvailable / queryProductDetails');
      expect(h.fake.isAvailableCalls, 0);
      expect(h.fake.queryCalls, 0);
      expect(h.service.isAvailable, isFalse);
      expect(h.service.monthlyProduct, isNull);
      expect(h.service.isLoading, isFalse);
      expect(h.service.errorMessage, isNotNull);

      await h.service.buyMonthly();
      expect(h.fake.touches, 0);
      expect(h.fake.lastBuy, isNull);
    });

    test('loadProducts works with no IAP platform injected at all', () async {
      h = _Harness(supported: false); // 仅供全局 tearDown 使用
      // 不注入任何 iap：若误触 InAppPurchase.instance，会去碰真实的商店插件。
      final service = IapService(
        billingSupported: false,
        currentUid: () => 'uid-1',
        authUidChanges: () => const Stream<String?>.empty(),
      );
      addTearDown(service.dispose);

      await service.loadProducts();
      await service.start(onEntitlementActive: () async {});
      await service.syncPurchases();

      expect(service.isAvailable, isFalse);
      expect(service.monthlyProduct, isNull);
      expect(service.errorMessage, isNotNull);
    });

    test('loadProducts still queries the store when billing is supported',
        () async {
      h = _Harness();
      await h.service.loadProducts();

      expect(h.fake.isAvailableCalls, greaterThan(0));
      expect(h.fake.queryCalls, 1);
      expect(h.service.monthlyProduct, isNotNull);
    });
  });
}

String _token(PurchaseDetails p) => p.verificationData.serverVerificationData;

PurchaseDetails _purchase(String token, PurchaseStatus status) {
  return PurchaseDetails(
    productID: AppConfig.monthlySubscriptionProductId,
    status: status,
    transactionDate: '1710000000000',
    verificationData: PurchaseVerificationData(
      localVerificationData: token,
      serverVerificationData: token,
      source: 'google_play',
    ),
  )..pendingCompletePurchase = status != PurchaseStatus.pending;
}

/// 与 in_app_purchase_android 在用户取消 / 购买失败且没有购买记录时送达的结果一致：
/// productID、purchaseID 为空，没有验证数据。
PurchaseDetails _resultWithoutProduct(PurchaseStatus status) {
  return PurchaseDetails(
    purchaseID: '',
    productID: '',
    status: status,
    transactionDate: null,
    verificationData: PurchaseVerificationData(
      localVerificationData: '',
      serverVerificationData: '',
      source: 'google_play',
    ),
  )..error = status == PurchaseStatus.error
      ? IAPError(
          source: 'google_play',
          code: 'purchase_error',
          message: 'BillingResponse.error',
        )
      : null;
}

PurchaseDetails _otherProduct(String token, PurchaseStatus status) {
  return PurchaseDetails(
    productID: 'some_other_product',
    status: status,
    transactionDate: '1710000000000',
    verificationData: PurchaseVerificationData(
      localVerificationData: token,
      serverVerificationData: token,
      source: 'google_play',
    ),
  )..pendingCompletePurchase = status != PurchaseStatus.pending;
}

/// K1 测试用的假计时器：只在测试显式触发时执行。
class _FakeTimers {
  final List<_FakeTimer> _all = [];

  Timer create(Duration duration, void Function() callback) {
    final timer = _FakeTimer(duration, callback);
    _all.add(timer);
    return timer;
  }

  List<_FakeTimer> get active => _all.where((t) => t.isActive).toList();
}

class _FakeTimer implements Timer {
  _FakeTimer(this.duration, this._callback);

  final Duration duration;
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

class _Harness {
  _Harness({
    this.uid = 'uid-1',
    bool supported = true,
    Duration restoreBatchTimeout = const Duration(seconds: 15),
    Duration queryTimeout = const Duration(seconds: 30),
    Timer Function(Duration, void Function())? retryTimerFactory,
  }) {
    service = IapService(
      retryTimerFactory: retryTimerFactory,
      iap: fake,
      billingSupported: supported,
      currentUid: () => uid,
      authUidChanges: () async* {
        yield uid; // FirebaseAuth emits the current user first
        yield* auth.stream;
      },
      restoreBatchTimeout: restoreBatchTimeout,
      queryTimeout: queryTimeout,
      purchaseVerifier: PurchaseVerificationService(
        checkOnServer: (productId, token) async {
          verifyCalls.add(token);
          verifyUids.add(uid);
          final check = checkImpl;
          if (check != null) return check(token);
          return await verifyImpl(token)
              ? const PurchaseVerificationResult.verified()
              : const PurchaseVerificationResult.rejected('rejected');
        },
      ),
    );
  }

  final _FakeIap fake = _FakeIap();
  final StreamController<String?> auth = StreamController<String?>.broadcast();
  late final IapService service;
  String? uid;
  final List<String> verifyCalls = [];
  final List<String?> verifyUids = [];
  int entitlementCalls = 0;
  Future<bool> Function(String token) verifyImpl = (_) async => true;
  Future<PurchaseVerificationResult> Function(String token)? checkImpl;

  Future<void> start() async {
    await service.start(onEntitlementActive: () async {
      entitlementCalls++;
    });
    await pumpEventQueue(times: 40);
  }

  void signIn(String? newUid) {
    uid = newUid;
    auth.add(newUid);
  }
}

class _FakeIap implements InAppPurchase {
  final StreamController<List<PurchaseDetails>> controller =
      StreamController<List<PurchaseDetails>>.broadcast();
  final List<PurchaseDetails> completed = [];
  List<List<PurchaseDetails>> restoreScript = [];
  int restoreCalls = 0;
  bool emitOnRestore = true;
  Object? restoreError; // Play 查询失败：抛出且不送达批次（与插件一致）
  PurchaseParam? lastBuy;
  Completer<void>? restoreGate;
  int _runningRestores = 0;
  int maxConcurrentRestores = 0;
  int touches = 0; // 任何对 IAP 平台的访问
  int isAvailableCalls = 0;
  int queryCalls = 0;

  final ProductDetails product = ProductDetails(
    id: AppConfig.monthlySubscriptionProductId,
    title: 'VIP',
    description: 'VIP monthly',
    price: '€4.99',
    rawPrice: 4.99,
    currencyCode: 'EUR',
  );

  @override
  Stream<List<PurchaseDetails>> get purchaseStream {
    touches++;
    return controller.stream;
  }

  @override
  Future<bool> isAvailable() async {
    touches++;
    isAvailableCalls++;
    return true;
  }

  @override
  Future<ProductDetailsResponse> queryProductDetails(
    Set<String> identifiers,
  ) async {
    touches++;
    queryCalls++;
    return ProductDetailsResponse(
      productDetails: [product],
      notFoundIDs: const [],
    );
  }

  @override
  Future<bool> buyNonConsumable({required PurchaseParam purchaseParam}) async {
    touches++;
    lastBuy = purchaseParam;
    return true;
  }

  @override
  Future<void> completePurchase(PurchaseDetails purchase) async {
    touches++;
    completed.add(purchase);
  }

  @override
  Future<void> restorePurchases({String? applicationUserName}) async {
    touches++;
    final index = restoreCalls++;
    _runningRestores++;
    if (_runningRestores > maxConcurrentRestores) {
      maxConcurrentRestores = _runningRestores;
    }
    try {
      final gate = restoreGate;
      if (gate != null) await gate.future;
      final error = restoreError;
      if (error != null) throw error;
      if (!emitOnRestore) return;
      // 与 in_app_purchase_android 0.5.0 一致：restorePurchases 把每条结果都标为
      // restored（即使 Play 侧 purchaseState 仍是 pending），不会出现 pending 状态。
      controller.add(
        index < restoreScript.length
            ? [for (final p in restoreScript[index]) p..status = PurchaseStatus.restored]
            : <PurchaseDetails>[],
      );
    } finally {
      _runningRestores--;
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
