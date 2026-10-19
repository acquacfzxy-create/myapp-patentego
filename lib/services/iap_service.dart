import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import '../config/app_config.dart';
import '../config/app_strings.dart';
import 'apple_account_token.dart';
import 'purchase_verification_service.dart';
import 'firebase_status.dart';

enum IapOperation {
  none,
  purchase,
  restore,
}

/// 某个 purchase token 首次通过服务端验证时发出（同一 token 只发一次）。
class IapVerifiedEvent {
  const IapVerifiedEvent({required this.userInitiatedPurchase});

  /// true 表示用户在订阅页刚完成的购买；启动/回前台自动发现的购买为 false。
  final bool userInitiatedPurchase;
}

/// 续订核对的结论。账号是否仍有权益以服务端写入的快照为准；
/// 这里只说明核对是否得到了服务端的明确答复。
enum RenewalCheckOutcome {
  /// 服务端确认本机查到的某笔购买当前有效。
  confirmedActive,

  /// 服务端对本机查到的购买都给出了明确结论（均不有效）。
  answered,

  /// Play 查询成功但本机没有本商品的购买（也可能是 Play 与 App 账号不一致）。
  noLocalPurchase,

  /// 无法确认：Play 查询失败 / 超时，或服务端无法确认。
  unknown,

  /// 核对期间换账号或服务已释放：结果作废。
  discarded,
}

enum _Origin {
  background,
  purchaseFlow,
  // 购买流程中服务端暂时无法确认后的前台限次重试（K1）：静默，成功时视为用户发起。
  purchaseRetry,
  manualRestore,
  renewalCheck,
}

/// 去重/串行的键：同一 token 在不同账号下互不共用，避免 Auth 事件与
/// `FirebaseAuth.currentUser` 之间的异步窗口造成跨账号复用。
typedef _PurchaseKey = (String uid, String token);

enum _QueryStatus { delivered, failed, timedOut }

class _QueryResult {
  const _QueryResult.delivered(this.purchases)
      : status = _QueryStatus.delivered,
        error = null;
  const _QueryResult.failed(this.error)
      : status = _QueryStatus.failed,
        purchases = const [];
  const _QueryResult.timedOut()
      : status = _QueryStatus.timedOut,
        purchases = const [],
        error = null;

  final _QueryStatus status;
  final List<PurchaseDetails> purchases;
  final Object? error;
}

/// 一次 Play 本地查询。purchaseStream 的批次不带请求 ID，因此所有查询串行执行，
/// 由“当前登记的查询”认领下一个查询批次。
class _Query {
  final Completer<List<PurchaseDetails>> batch =
      Completer<List<PurchaseDetails>>();

  /// 调用方已超时放弃：Play 之后才返回的批次按后台处理。
  bool abandoned = false;
}

/// App 级购买协调器：由 main.dart 在启动时创建并 [start]，生命周期与 App 相同，
/// 不依赖任何页面。购买一律经由 [PurchaseVerificationService] 走云端验证，
/// 客户端不会自行授予 VIP。
class IapService extends ChangeNotifier with WidgetsBindingObserver {
  IapService({
    PurchaseVerificationService purchaseVerifier =
        const PurchaseVerificationService(),
    InAppPurchase? iap,
    bool? billingSupported,
    String? Function()? currentUid,
    Stream<String?> Function()? authUidChanges,
    Duration restoreBatchTimeout = const Duration(seconds: 15),
    Duration queryTimeout = const Duration(seconds: 30),
    List<Duration> purchaseRetryDelays = const [
      Duration(seconds: 5),
      Duration(seconds: 15),
      Duration(seconds: 45),
    ],
    Timer Function(Duration duration, void Function() callback)?
        retryTimerFactory,
  })  : _purchaseVerifier = purchaseVerifier,
        _iapOverride = iap,
        _billingSupportedOverride = billingSupported,
        _currentUid = currentUid ?? _firebaseUid,
        _authUidChanges = authUidChanges ?? _firebaseUidChanges,
        _restoreBatchTimeout = restoreBatchTimeout,
        _queryTimeout = queryTimeout,
        _purchaseRetryDelays = purchaseRetryDelays,
        _retryTimerFactory = retryTimerFactory ?? Timer.new;

  static const Set<String> _productIds = {
    AppConfig.monthlySubscriptionProductId,
  };

  final InAppPurchase? _iapOverride;
  // 惰性获取：iOS / Web 等未启用购买的平台不会在启动时触碰商店插件。
  late final InAppPurchase _iap = _iapOverride ?? InAppPurchase.instance;
  final PurchaseVerificationService _purchaseVerifier;
  final bool? _billingSupportedOverride;
  final String? Function() _currentUid;
  final Stream<String?> Function() _authUidChanges;
  final Duration _restoreBatchTimeout;
  final Duration _queryTimeout;
  final List<Duration> _purchaseRetryDelays;
  final Timer Function(Duration, void Function()) _retryTimerFactory;

  final StreamController<IapVerifiedEvent> _verifiedEvents =
      StreamController<IapVerifiedEvent>.broadcast();
  StreamSubscription<List<PurchaseDetails>>? _purchaseSubscription;
  StreamSubscription<String?>? _authSubscription;
  Future<void> Function()? _onEntitlementActive;
  void Function()? _onResumed;

  // 购买处理按账号串行化（旧账号的慢请求不会阻塞新账号）；
  // 同一 (uid, token) 处理中的重复到达共用同一个 Future。
  final Map<String, Future<void>> _queueTails = {};
  final Map<_PurchaseKey, Future<PurchaseVerificationResult>> _inFlight = {};
  final Set<_PurchaseKey> _verifiedTokens = {};

  // Play 本地查询串行执行（见 [_queryOwned]）。
  Future<void> _queryTail = Future<void>.value();
  _Query? _activeQuery;
  // 续订核对按账号合并。
  final Map<String, Future<RenewalCheckOutcome>> _renewalChecks = {};

  Future<void>? _syncInFlight;
  bool _syncQueued = false;
  // 购买流程验证暂时无法确认时的前台限次重试（同一时间只跟踪一笔购买）。
  Timer? _purchaseRetryTimer;
  _PurchaseKey? _purchaseRetryKey;
  int _purchaseRetryAttempt = 0;
  Future<void>? _productsLoad;
  String? _authUid;
  bool _started = false;
  bool _disposed = false;

  bool _isAvailable = false;
  bool _isLoading = false;
  IapOperation _operation = IapOperation.none;
  // 本次购买仍在等待 Play 返回结果（尚未收到本商品的购买事件）。
  // 收到后进入服务端验证，此时不含商品的结果不能再结束购买流程。
  bool _awaitingPlayResult = false;
  String? _errorMessage;
  ProductDetails? _monthlyProduct;
  // Play 查询成功，但当前 Play 账号下没有这个订阅商品（区别于查询失败 / 网络错误）。
  bool _productNotFound = false;

  bool get isAvailable => _isAvailable;
  bool get isLoading => _isLoading;
  bool get isBuying => _operation == IapOperation.purchase;
  bool get isRestoring => _operation == IapOperation.restore;
  bool get isPurchasing => _operation != IapOperation.none;
  String? get errorMessage => _errorMessage;
  ProductDetails? get monthlyProduct => _monthlyProduct;
  bool get productNotFound => _productNotFound;
  Stream<IapVerifiedEvent> get verifiedPurchases => _verifiedEvents.stream;

  /// 只有启用 Play Billing 的平台（目前仅 Android）提供续订核对与续订等待。
  bool get supportsRenewalChecks => _billingSupported;

  /// 订阅经 Google Play 购买时，App 需提供前往 Play 订阅中心管理 / 取消的入口。
  bool get usesGooglePlayBilling => _billingSupported && !_isIos;

  /// 订阅经 App Store 购买时，App 需提供前往 App Store 订阅管理页的入口。
  /// 是否启用了任一商店结算（Play 或 App Store）。
  bool get usesStoreBilling => _billingSupported;

  bool get usesAppStoreBilling => _billingSupported && _isIos;

  /// 订阅管理页地址：按实际结算平台选择。
  String get subscriptionCenterUrl => usesAppStoreBilling
      ? AppConfig.appStoreSubscriptionCenterUrl
      : AppConfig.playSubscriptionCenterUrl;

  static bool get _isIos =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  /// Android + Google Play、iOS + App Store 各自由 build 旗标开启；Web 保持关闭。
  bool get _billingSupported =>
      _billingSupportedOverride ??
      (!kIsWeb &&
          ((AppConfig.playBillingEnabled &&
                  defaultTargetPlatform == TargetPlatform.android) ||
              (AppConfig.appStoreBillingEnabled &&
                  defaultTargetPlatform == TargetPlatform.iOS)));

  static String? _firebaseUid() {
    final user = FirebaseStatus.auth?.currentUser;
    if (user == null || user.isAnonymous) return null;
    return user.uid;
  }

  static Stream<String?> _firebaseUidChanges() {
    final auth = FirebaseStatus.auth;
    if (auth == null) return const Stream<String?>.empty();
    return auth
        .authStateChanges()
        .map((user) => user == null || user.isAnonymous ? null : user.uid);
  }

  /// 启动 App 级购买生命周期：尽早监听 purchaseStream；登录后与回前台时
  /// 自动查询 Play 中当前账号已拥有的购买并交给服务端验证。
  Future<void> start({
    required Future<void> Function() onEntitlementActive,
    void Function()? onResumed,
  }) async {
    _onEntitlementActive = onEntitlementActive;
    _onResumed = onResumed;
    if (_started || !_billingSupported) return;
    _started = true;

    _purchaseSubscription = _iap.purchaseStream.listen(
      (purchases) => unawaited(_handlePurchaseUpdates(purchases)),
      onError: (Object error) {
        _errorMessage = error.toString();
        _operation = IapOperation.none;
        notifyListeners();
      },
    );
    WidgetsBinding.instance.addObserver(this);

    await _refreshAvailability();
    if (_disposed) return;
    _authSubscription = _authUidChanges().listen(_handleAuthUid);
  }

  void _handleAuthUid(String? uid) {
    if (uid == _authUid) return;
    _authUid = uid;
    // 待重试的购买属于旧账号：换账号后不再以新账号身份重试。
    _cancelPurchaseRetry();
    // 缓存与 in-flight 已按 (uid, token) 隔离，换账号无需清空。
    if (uid != null) unawaited(syncPurchases());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(syncPurchases());
      // 让权益层推进尚未完成的续订核对（常规同步会被已验证缓存跳过）。
      _onResumed?.call();
    }
  }

  /// 静默查询 Play 中当前账号已拥有的购买（结果经 purchaseStream 送达）。
  /// 未登录不查询。single-flight：已有查询在执行时不并发启动第二个，而是登记
  /// 一次尾随查询，当前查询结束后立即再查一次（多个同时发生的触发合并为一次），
  /// 因此每次真实的 resume / 登录都保证有一次“在它之后开始”的查询。
  Future<void> syncPurchases() {
    if (!_billingSupported || _disposed || _currentUid() == null) {
      return Future<void>.value();
    }
    final running = _syncInFlight;
    if (running != null) {
      _syncQueued = true;
      return running;
    }
    final run = _runSyncLoop();
    _syncInFlight = run;
    return run;
  }

  Future<void> _runSyncLoop() async {
    try {
      do {
        _syncQueued = false;
        await _runSync();
      } while (_syncQueued && !_disposed && _currentUid() != null);
    } finally {
      // 与循环判定在同一个同步点清空：此后到来的触发一定会启动新的查询，
      // 不存在“已登记 trailing 却无人执行”的间隙。
      _syncQueued = false;
      _syncInFlight = null;
    }
  }

  Future<void> _runSync() async {
    if (!_isAvailable && !await _refreshAvailability()) return;
    final result = await _queryOwned();
    // 查询失败 / 超时静默：下一次登录 / 回前台会再次尝试。
    if (result.status == _QueryStatus.delivered) {
      _processInBackground(result.purchases);
    }
  }

  /// Play 本地查询。purchaseStream 的批次不带请求 ID：所有查询在此串行执行，
  /// 插件在 restorePurchases 的 Future 完成前就把本次批次 add 到广播流，
  /// 因此当前登记的查询认领的下一个查询批次就是它自己的结果。
  /// 调用方超时后，查询仍占住串行位置直到 Play 真正返回；晚到的批次按后台处理，
  /// 不会被后续查询冒认。失败（抛异常）与“成功但没有购买”（空批次）严格区分。
  Future<_QueryResult> _queryOwned() {
    final query = _Query();
    final outcome = Completer<_QueryResult>();
    void finish(_QueryResult result) {
      if (outcome.isCompleted) return;
      outcome.complete(result);
    }

    final run = _queryTail.then((_) async {
      if (query.abandoned) return;
      _activeQuery = query;
      try {
        await _iap.restorePurchases();
        final batch = await query.batch.future.timeout(_restoreBatchTimeout);
        if (query.abandoned) {
          _processInBackground(batch);
        } else {
          finish(_QueryResult.delivered(batch));
        }
      } on TimeoutException {
        finish(const _QueryResult.timedOut());
      } catch (e) {
        finish(_QueryResult.failed(e));
      } finally {
        if (identical(_activeQuery, query)) _activeQuery = null;
      }
    });
    _queryTail = run;
    return outcome.future.timeout(_queryTimeout, onTimeout: () {
      query.abandoned = true;
      return const _QueryResult.timedOut();
    });
  }

  bool _isOurs(PurchaseDetails p) => _productIds.contains(p.productID);

  /// 查询结果中本商品的购买（插件统一标为 restored；付款是否完成由服务端判定）。
  bool _isOwnedRestored(PurchaseDetails p) =>
      _isOurs(p) && p.status == PurchaseStatus.restored;

  /// 后台同步或晚到的查询批次：按后台来源验证。
  void _processInBackground(List<PurchaseDetails> purchases) {
    for (final purchase in purchases.where(_isOwnedRestored)) {
      unawaited(_processPurchase(purchase, _Origin.background));
    }
  }

  /// 续订核对：由权益层在“等待续订”期间调用。本地查询 Play，对查到的本商品购买
  /// 绕过已验证缓存重新向服务端确认（同 token 的并发请求仍会合并），
  /// 同一账号的并发调用合并为一次。账号是否仍有权益以服务端写入的快照为准。
  Future<RenewalCheckOutcome> checkRenewal(String uid) {
    if (!_billingSupported || _disposed || _currentUid() != uid) {
      return Future<RenewalCheckOutcome>.value(RenewalCheckOutcome.discarded);
    }
    final running = _renewalChecks[uid];
    if (running != null) return running;
    final task = _runRenewalCheck(uid);
    _renewalChecks[uid] = task;
    unawaited(task.whenComplete(() {
      if (identical(_renewalChecks[uid], task)) _renewalChecks.remove(uid);
    }));
    return task;
  }

  Future<RenewalCheckOutcome> _runRenewalCheck(String uid) async {
    bool stale() => _disposed || _currentUid() != uid;
    if (!_isAvailable && !await _refreshAvailability()) {
      return stale()
          ? RenewalCheckOutcome.discarded
          : RenewalCheckOutcome.unknown;
    }
    final query = await _queryOwned();
    if (stale()) return RenewalCheckOutcome.discarded;
    if (query.status != _QueryStatus.delivered) {
      return RenewalCheckOutcome.unknown;
    }
    final ours = query.purchases.where(_isOwnedRestored).toList();
    // 本机没有这笔购买不等于订阅终止（Play 账号可能与 App 账号不同）。
    if (ours.isEmpty) return RenewalCheckOutcome.noLocalPurchase;
    final results = await Future.wait(
      ours.map((p) => _processPurchaseResult(p, _Origin.renewalCheck)),
    );
    if (stale()) return RenewalCheckOutcome.discarded;
    if (results.any((r) => r.isVerified)) {
      return RenewalCheckOutcome.confirmedActive;
    }
    if (results.any((r) => r.outcome == VerificationOutcome.unknown)) {
      return RenewalCheckOutcome.unknown;
    }
    return RenewalCheckOutcome.answered;
  }

  Future<bool> _refreshAvailability() async {
    try {
      _isAvailable = await _iap.isAvailable();
    } catch (_) {
      _isAvailable = false;
    }
    return _isAvailable;
  }

  /// 订阅页调用：加载商品与价格。页面重复进入时会重新查询。
  Future<void> loadProducts() {
    return _productsLoad ??= _loadProducts().whenComplete(() {
      _productsLoad = null;
    });
  }

  Future<void> _loadProducts() async {
    _isLoading = true;
    _errorMessage = null;
    _productNotFound = false;

    if (!_billingSupported) {
      // 未启用购买的平台（iOS / Web / 未开启 PLAY_BILLING_ENABLED）：
      // 不触碰商店插件，直接呈现“不可用”状态；调用方在首次 build 时读取。
      _isAvailable = false;
      _monthlyProduct = null;
      _errorMessage = AppStrings.get('iap_unavailable');
      _isLoading = false;
      return;
    }

    try {
      if (!await _refreshAvailability()) {
        _errorMessage = AppStrings.get('iap_unavailable');
        return;
      }

      final response = await _iap.queryProductDetails(_productIds);
      if (response.error != null) {
        _errorMessage = response.error!.message;
      }
      if (response.notFoundIDs.isNotEmpty) {
        _productNotFound = response.error == null &&
            response.notFoundIDs
                .contains(AppConfig.monthlySubscriptionProductId);
        _errorMessage = AppStrings.get(_productNotFound
            ? (usesGooglePlayBilling
                ? 'iap_product_unavailable_for_account'
                : 'iap_product_unavailable_for_account_store')
            : 'iap_product_not_found');
      }

      for (final product in response.productDetails) {
        if (product.id == AppConfig.monthlySubscriptionProductId) {
          _monthlyProduct = product;
        }
      }
    } catch (e) {
      _errorMessage = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> buyMonthly() async {
    if (_operation != IapOperation.none) {
      return;
    }

    if (!_billingSupported) {
      _errorMessage = AppStrings.get('iap_subscription_not_ready');
      notifyListeners();
      return;
    }
    final uid = _currentUid();
    if (uid == null) {
      _errorMessage = AppStrings.get('iap_sign_in_required');
      notifyListeners();
      return;
    }

    final product = _monthlyProduct;
    if (!_isAvailable || product == null) {
      _errorMessage = AppStrings.get('iap_subscription_not_ready');
      notifyListeners();
      return;
    }

    _operation = IapOperation.purchase;
    _awaitingPlayResult = true;
    _errorMessage = null;
    notifyListeners();

    final purchaseParam = PurchaseParam(
      productDetails: product,
      // iOS：StoreKit 2 的 appAccountToken 必须是 UUID，由 uid 确定性衍生，服务端用同一算法核对。
      applicationUserName: _isIos
          ? appleAccountToken(uid)
          : sha256.convert(utf8.encode(uid)).toString(),
    );
    try {
      final started = await _iap.buyNonConsumable(purchaseParam: purchaseParam);
      if (!started) {
        _errorMessage = AppStrings.get('iap_purchase_start_failed');
        _operation = IapOperation.none;
        notifyListeners();
      }
    } catch (e) {
      _errorMessage = e.toString();
      _operation = IapOperation.none;
      notifyListeners();
    }
  }

  /// 用户手动“恢复购买”。仅对“Play 本地查询结果是否送达”设置超时；
  /// 服务端验证耗时（冷启动、网络慢）不设上限，不会被误判为“没有购买”。
  Future<bool> restorePurchases() async {
    if (_operation != IapOperation.none) return false;
    if (!_billingSupported) {
      _errorMessage = AppStrings.get('iap_subscription_not_ready');
      notifyListeners();
      return false;
    }
    if (!_isAvailable && !await _refreshAvailability()) {
      _errorMessage = AppStrings.get('iap_unavailable');
      notifyListeners();
      return false;
    }

    _operation = IapOperation.restore;
    _errorMessage = null;
    notifyListeners();

    try {
      final result = await _queryOwned();
      switch (result.status) {
        case _QueryStatus.failed:
          _errorMessage = result.error.toString();
          return false;
        case _QueryStatus.timedOut:
          return false;
        case _QueryStatus.delivered:
          // 本地查询结果已送达：此后的服务端验证耗时不再受批次超时约束。
          final results = await Future.wait(
            result.purchases
                .where(_isOwnedRestored)
                .map((p) => _processPurchase(p, _Origin.manualRestore)),
          );
          return results.any((verified) => verified);
      }
    } finally {
      if (_operation == IapOperation.restore) _operation = IapOperation.none;
      notifyListeners();
    }
  }

  Future<void> _handlePurchaseUpdates(
    List<PurchaseDetails> purchases,
  ) async {
    final ours = purchases.where(_isOurs).toList();

    // in_app_purchase_android 0.5.0 的 restorePurchases 把每条结果都标为 restored
    // （含空批次）；实时购买事件是 purchased / pending / canceled / error，
    // 因此只有全部为 restored 的批次才交给当前登记的查询。
    // 无人认领的批次（晚到 / 外部触发）按下面的常规路径处理。
    final query = _activeQuery;
    if (query != null &&
        !query.batch.isCompleted &&
        purchases.every((p) => p.status == PurchaseStatus.restored)) {
      query.batch.complete(purchases);
      return;
    }

    for (final purchase in purchases) {
      if (purchase.productID.isEmpty) _handleResultWithoutProduct(purchase);
    }

    for (final purchase in ours) {
      switch (purchase.status) {
        case PurchaseStatus.pending:
          break;
        case PurchaseStatus.error:
          _errorMessage =
              purchase.error?.message ?? AppStrings.get('iap_purchase_failed');
          _operation = IapOperation.none;
          await _completeQuietly(purchase);
          break;
        case PurchaseStatus.canceled:
          _operation = IapOperation.none;
          await _completeQuietly(purchase);
          break;
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          final origin = purchase.status == PurchaseStatus.purchased &&
                  _operation == IapOperation.purchase
              ? _Origin.purchaseFlow
              : _Origin.background;
          if (origin == _Origin.purchaseFlow) _awaitingPlayResult = false;
          final uid = _currentUid();
          unawaited(_processPurchaseResult(purchase, origin).then((result) {
            // 服务端暂时无法确认（网络 / 超时 / 5xx 等）：前台限次重试，不必等回前台。
            if (origin == _Origin.purchaseFlow &&
                result.outcome == VerificationOutcome.unknown &&
                uid != null) {
              _startPurchaseRetry(purchase, uid);
            }
            if (origin == _Origin.purchaseFlow &&
                _operation == IapOperation.purchase) {
              _operation = IapOperation.none;
              notifyListeners();
            }
          }));
          break;
      }
    }
    notifyListeners();
  }

  /// Android 在用户取消或购买失败且没有购买记录时，送达的是 productID 为空的结果，
  /// 上面的商品过滤会把它排除。它只可能是本次购买的结果：仅在购买仍等待 Play
  /// 返回时据此结束流程；已进入服务端验证的购买、恢复与后台同步都不受影响。
  void _handleResultWithoutProduct(PurchaseDetails purchase) {
    if (_operation != IapOperation.purchase || !_awaitingPlayResult) return;
    switch (purchase.status) {
      case PurchaseStatus.canceled:
        break;
      case PurchaseStatus.error:
        // 插件此处的 message 是 BillingResponse 枚举名，不适合直接展示。
        _errorMessage = AppStrings.get('iap_purchase_failed');
        break;
      case PurchaseStatus.pending:
      case PurchaseStatus.purchased:
      case PurchaseStatus.restored:
        return;
    }
    _awaitingPlayResult = false;
    _operation = IapOperation.none;
  }

  Future<bool> _processPurchase(PurchaseDetails purchase, _Origin origin) =>
      _processPurchaseResult(purchase, origin).then((r) => r.isVerified);

  /// 用户主动的操作（购买 / 手动恢复）才向 UI 报错；后台与续订核对静默。
  static bool _reportsErrors(_Origin origin) =>
      origin == _Origin.purchaseFlow || origin == _Origin.manualRestore;

  Future<PurchaseVerificationResult> _processPurchaseResult(
    PurchaseDetails purchase,
    _Origin origin,
  ) {
    final token = purchase.verificationData.serverVerificationData;
    // 验证开始前就确定归属账号；此后一律以这个 uid 为准。
    final uid = _currentUid();
    if (uid == null) {
      // 未登录不验证、不确认购买；登录后的自动查询会重新送达。
      if (_reportsErrors(origin)) {
        _errorMessage = AppStrings.get('iap_sign_in_required');
        notifyListeners();
      }
      return Future<PurchaseVerificationResult>.value(
        PurchaseVerificationResult.unknown(
          AppStrings.get('iap_sign_in_required'),
        ),
      );
    }
    if (token.isEmpty) {
      return _enqueue(
          uid, () => _verifyAndComplete(purchase, uid, token, origin));
    }

    final key = (uid, token);
    // 手动恢复与续订核对始终重新向服务端确认；自动流程对该账号已验证的 token 直接跳过。
    final bypassCache =
        origin == _Origin.manualRestore || origin == _Origin.renewalCheck;
    if (!bypassCache && _verifiedTokens.contains(key)) {
      return Future<PurchaseVerificationResult>.value(
        const PurchaseVerificationResult.verified(),
      );
    }
    final inFlight = _inFlight[key];
    if (inFlight != null) return inFlight;

    final task =
        _enqueue(uid, () => _verifyAndComplete(purchase, uid, token, origin));
    _inFlight[key] = task;
    unawaited(task.whenComplete(() {
      if (identical(_inFlight[key], task)) _inFlight.remove(key);
    }));
    return task;
  }

  Future<T> _enqueue<T>(String uid, Future<T> Function() job) {
    final tail = _queueTails[uid] ?? Future<void>.value();
    final result = tail.then((_) => job());
    final next = result.then((_) {}, onError: (Object _) {});
    _queueTails[uid] = next;
    unawaited(next.whenComplete(() {
      if (identical(_queueTails[uid], next)) _queueTails.remove(uid);
    }));
    return result;
  }

  Future<PurchaseVerificationResult> _verifyAndComplete(
    PurchaseDetails purchase,
    String uid,
    String token,
    _Origin origin,
  ) async {
    final reportErrors = _reportsErrors(origin);
    final discarded = PurchaseVerificationResult.unknown(
      AppStrings.get('iap_purchase_verification_failed'),
    );

    // 入队到真正执行之间账号可能已切换：verify() 使用的是 Firebase 当前用户的
    // ID Token，此时发请求就会拿新账号的凭证去验证旧账号队列里的购买。直接放弃，
    // 新账号会通过 auth / resume / trailing 查询自行重新处理。
    if (_currentUid() != uid) return discarded;

    PurchaseVerificationResult result;
    try {
      result = await _purchaseVerifier.verify(purchase);
    } catch (_) {
      result = discarded;
    }

    // 验证期间切换了账号：结果不属于当前账号，不记录也不确认。
    if (_currentUid() != uid) return discarded;

    if (!result.isVerified) {
      // 保持未确认状态，下次登录 / 回前台 / 手动恢复会再次尝试。
      if (reportErrors) {
        _errorMessage = _verificationErrorMessage(result, origin);
        notifyListeners();
      }
      return result;
    }

    if (token.isNotEmpty) _verifiedTokens.add((uid, token));
    unawaited(_notifyEntitlementActive());
    if (!_verifiedEvents.isClosed) {
      _verifiedEvents.add(
        IapVerifiedEvent(
          userInitiatedPurchase:
              origin == _Origin.purchaseFlow || origin == _Origin.purchaseRetry,
        ),
      );
    }
    await _completeQuietly(purchase);
    return result;
  }

  /// 购买 / 恢复失败时的提示：购买不属于当前账号（400 / 403）与暂时无法确认分开说明。
  String _verificationErrorMessage(
    PurchaseVerificationResult result,
    _Origin origin,
  ) {
    if (result.outcome == VerificationOutcome.rejected) {
      return AppStrings.get('iap_purchase_verification_rejected');
    }
    if (result.outcome == VerificationOutcome.unknown &&
        origin == _Origin.purchaseFlow) {
      return AppStrings.get(usesGooglePlayBilling
          ? 'iap_purchase_verification_pending'
          : 'iap_purchase_verification_pending_store');
    }
    return result.errorMessage ??
        AppStrings.get('iap_purchase_verification_failed');
  }

  /// K1：购买流程中服务端暂时无法确认时，按 [_purchaseRetryDelays] 在前台有限次
  /// 重试同一笔购买。400 / 403 与已有结论（inactive）不重试；每次重试仍经过
  /// [_processPurchaseResult] 的去重与按账号串行，确认顺序不变（只在验证成功后确认）。
  /// 用尽次数后购买保持未确认，由回前台 / 冷启动 / 登录 / 手动恢复继续处理。
  void _startPurchaseRetry(PurchaseDetails purchase, String uid) {
    final token = purchase.verificationData.serverVerificationData;
    if (_disposed || token.isEmpty || _currentUid() != uid) return;
    _cancelPurchaseRetry();
    final key = (uid, token);
    _purchaseRetryKey = key;
    _armPurchaseRetry(purchase, uid, key);
  }

  void _armPurchaseRetry(
    PurchaseDetails purchase,
    String uid,
    _PurchaseKey key,
  ) {
    if (_purchaseRetryAttempt >= _purchaseRetryDelays.length) {
      _cancelPurchaseRetry();
      return;
    }
    final delay = _purchaseRetryDelays[_purchaseRetryAttempt++];
    _purchaseRetryTimer = _retryTimerFactory(delay, () {
      _purchaseRetryTimer = null;
      if (!_purchaseRetryStillNeeded(key, uid)) return;
      unawaited(_processPurchaseResult(purchase, _Origin.purchaseRetry)
          .then((result) {
        if (!_purchaseRetryStillNeeded(key, uid)) return;
        if (result.outcome == VerificationOutcome.unknown) {
          _armPurchaseRetry(purchase, uid, key);
        } else {
          _cancelPurchaseRetry();
        }
      }));
    });
  }

  bool _purchaseRetryStillNeeded(_PurchaseKey key, String uid) {
    if (_disposed || _purchaseRetryKey != key || _currentUid() != uid) {
      return false;
    }
    if (_verifiedTokens.contains(key)) {
      // 已由回前台同步 / 手动恢复等其他路径验证成功。
      _cancelPurchaseRetry();
      return false;
    }
    return true;
  }

  void _cancelPurchaseRetry() {
    _purchaseRetryTimer?.cancel();
    _purchaseRetryTimer = null;
    _purchaseRetryKey = null;
    _purchaseRetryAttempt = 0;
  }

  // VIP 本身由 Firestore 权益快照驱动；此回调只做本地收尾（如同步进度），
  // 不阻塞后续购买的处理。
  Future<void> _notifyEntitlementActive() async {
    try {
      await _onEntitlementActive?.call();
    } catch (_) {}
  }

  Future<void> _completeQuietly(PurchaseDetails purchase) async {
    if (!purchase.pendingCompletePurchase) return;
    try {
      await _iap.completePurchase(purchase);
    } catch (_) {}
  }

  @override
  void notifyListeners() {
    if (_disposed) return;
    super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _cancelPurchaseRetry();
    _renewalChecks.clear();
    // 进行中的查询不再等批次：以空批次立即结束，调用方看到已释放后作废结果。
    final query = _activeQuery;
    if (query != null && !query.batch.isCompleted) {
      query.batch.complete(const <PurchaseDetails>[]);
    }
    if (_started) WidgetsBinding.instance.removeObserver(this);
    _purchaseSubscription?.cancel();
    _authSubscription?.cancel();
    _verifiedEvents.close();
    super.dispose();
  }
}
