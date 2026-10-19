import 'dart:async';

import '../config/app_config.dart';
import 'iap_service.dart' show RenewalCheckOutcome;

/// 服务端写入 users/{uid} 的权益快照（客户端只读）。
class EntitlementSnapshot {
  const EntitlementSnapshot({
    required this.isVip,
    required this.expiresAtMs,
    this.willRenew = false,
    this.pendingRenewal = false,
    this.pendingExpiresAtMs = 0,
  });

  static const EntitlementSnapshot none =
      EntitlementSnapshot(isVip: false, expiresAtMs: 0);

  /// 续订相关字段（willRenew / pendingRenewal / pendingExpiresAtMs）只在由新版后端
  /// 同一次写入时可信：`v2UpdatedAt == updatedAt`。旧版后端（回滚后）的 merge 只更新
  /// updatedAt，残留的新字段一律忽略，退回原有的到期判定。
  factory EntitlementSnapshot.fromUserDoc(Map<String, dynamic>? data) {
    final subscription = data?['subscription'];
    final sub = subscription is Map ? subscription : const {};
    num? read(String key) => sub[key] is num ? sub[key] as num : null;
    final stamp = sub['v2UpdatedAt'];
    final current = stamp != null && stamp == sub['updatedAt'];
    return EntitlementSnapshot(
      isVip: data?['isVip'] == true,
      expiresAtMs: read('expiresAtMs')?.toInt() ?? 0,
      willRenew: current && sub['willRenew'] == true,
      pendingRenewal: current && sub['pendingRenewal'] == true,
      pendingExpiresAtMs: current ? read('pendingExpiresAtMs')?.toInt() ?? 0 : 0,
    );
  }

  final bool isVip;

  /// Play 的原始到期时间（服务端不加缓冲）。
  final int expiresAtMs;

  /// 服务端汇总：以 [expiresAtMs] 结束的这个周期是否打算续订（意图，不是付款证据）。
  /// 已取消续订（CANCELED）的订阅为 false，到期即结束，不进入等待。
  final bool willRenew;

  /// 服务端确认：该账号仍在等待 Play 反映续订（续订意图，不是付款证据）。
  final bool pendingRenewal;

  /// 等待续订的那个周期的原始到期时间。
  final int pendingExpiresAtMs;
}

enum EntitlementStatus {
  none,
  active,

  /// 同一账号、同一周期先前已确认有效，周期刚结束、正在等待续订同步。
  awaitingRenewal,
}

class EntitlementDecision {
  const EntitlementDecision._(this.status, {this.periodEndMs, this.deadlineMs, this.nextEvaluationMs});

  final EntitlementStatus status;
  final int? periodEndMs;
  final int? deadlineMs;

  /// 下一次必须重新评估的时刻（到期 / 等待上限）。
  final int? nextEvaluationMs;

  bool get isVip => status != EntitlementStatus.none;
}

/// 续订等待的纯状态机（每个账号一个实例，换账号即丢弃）。
///
/// - 只有本会话内对同一账号确认过有效的周期，才可能在周期结束后进入等待；
///   首次购买、冷启动时已过期都不会等待。
/// - 等待期限固定为该周期的原始到期时间 + [limit]，任何重试、重复快照都不延长。
/// - 服务端确认该周期之后没有权益（快照不再是本周期、也不是本周期的 pendingRenewal）
///   时立即停止等待；未知 / 离线不视为终止。
/// - 超过期限取消暂时保留；之后服务端确认新周期仍会恢复为有效。
class RenewalGraceTracker {
  RenewalGraceTracker({Duration? limit, this.graceEnabled = true})
      : limit = limit ?? AppConfig.subscriptionRenewalGraceLimit;

  final Duration limit;

  /// 仅 Android Play Billing（有续订核对）启用等待；关闭时就是原有的到期判定。
  bool graceEnabled;
  int? _confirmedPeriodEndMs;
  int? _endedPeriodEndMs;

  int? get confirmedPeriodEndMs => _confirmedPeriodEndMs;

  /// 本周期已等待超时，但服务端尚未给出结论（之后仍值得核对）。
  bool isLapsedUnresolved(EntitlementSnapshot? snapshot, int nowMs) {
    final end = _confirmedPeriodEndMs;
    if (end == null || _endedPeriodEndMs == end) return false;
    return nowMs >= end + limit.inMilliseconds && _stillAboutPeriod(snapshot, end);
  }

  EntitlementDecision evaluate(EntitlementSnapshot? snapshot, int nowMs) {
    if (snapshot != null && snapshot.isVip && snapshot.expiresAtMs > nowMs) {
      _confirmedPeriodEndMs = snapshot.expiresAtMs;
      return EntitlementDecision._(
        EntitlementStatus.active,
        periodEndMs: snapshot.expiresAtMs,
        nextEvaluationMs: snapshot.expiresAtMs,
      );
    }
    final end = _confirmedPeriodEndMs;
    // 从未在本会话确认过有效：不能用等待授予权益。
    if (!graceEnabled || end == null || _endedPeriodEndMs == end) {
      return const EntitlementDecision._(EntitlementStatus.none);
    }
    if (!_stillAboutPeriod(snapshot, end)) {
      // 服务端已就本周期之后给出结论：没有权益。
      _endedPeriodEndMs = end;
      return const EntitlementDecision._(EntitlementStatus.none);
    }
    final deadline = end + limit.inMilliseconds;
    if (nowMs < end || nowMs >= deadline) {
      return EntitlementDecision._(EntitlementStatus.none, periodEndMs: end);
    }
    return EntitlementDecision._(
      EntitlementStatus.awaitingRenewal,
      periodEndMs: end,
      deadlineMs: deadline,
      nextEvaluationMs: deadline,
    );
  }

  /// 快照仍停留在该周期且服务端表示该周期会续订（尚无新消息），
  /// 或服务端明确表示正在等待该周期续订。已取消续订的周期不在此列。
  static bool _stillAboutPeriod(EntitlementSnapshot? s, int periodEndMs) {
    if (s == null) return false;
    if (s.isVip) return s.expiresAtMs == periodEndMs && s.willRenew;
    return s.pendingRenewal && s.pendingExpiresAtMs == periodEndMs;
  }
}

typedef RenewalChecker = Future<RenewalCheckOutcome> Function(String uid);
typedef MonitorTimerFactory = Timer Function(Duration delay, void Function() callback);

/// 单个账号的权益监视：状态机 + 精确计时 + 有界的续订核对。
/// 换账号或释放时由调用方 [dispose]，其后所有回调与晚到结果一律忽略。
class EntitlementMonitor {
  EntitlementMonitor({
    required this.uid,
    required void Function(bool isVip) onChanged,
    RenewalChecker? checker,
    Duration? limit,
    this.retryDelays = const [Duration.zero, Duration(seconds: 15), Duration(seconds: 45)],
    int Function()? nowMs,
    MonitorTimerFactory? timerFactory,
  })  : _onChanged = onChanged,
        _checker = checker,
        // 没有 Play 续订核对（Web 等）就不进入等待。
        _tracker = RenewalGraceTracker(limit: limit, graceEnabled: checker != null),
        _now = nowMs ?? (() => DateTime.now().millisecondsSinceEpoch),
        _timer = timerFactory ?? Timer.new;

  final String uid;
  final List<Duration> retryDelays;
  final void Function(bool isVip) _onChanged;
  final RenewalGraceTracker _tracker;
  final int Function() _now;
  final MonitorTimerFactory _timer;
  RenewalChecker? _checker;

  EntitlementSnapshot? _snapshot;
  bool? _lastFromCache;
  bool _isVip = false;
  bool _disposed = false;
  EntitlementDecision _decision = const EntitlementDecision._(EntitlementStatus.none);
  Timer? _evaluationTimer;
  final List<Timer> _retryTimers = [];
  int? _retryPlanPeriodMs;
  Future<RenewalCheckOutcome>? _checkInFlight;

  bool get isVip => _isVip;
  EntitlementStatus get status => _decision.status;
  int? get deadlineMs => _decision.deadlineMs;

  set checker(RenewalChecker? value) {
    _checker = value;
    _tracker.graceEnabled = value != null;
    evaluate();
  }

  /// 快照到达（含 metadata 变化）。离线缓存切回服务端视为“恢复联网”，推进未完成的核对。
  void updateSnapshot(EntitlementSnapshot? snapshot, {bool fromCache = false}) {
    if (_disposed) return;
    final reconnected = _lastFromCache == true && !fromCache;
    _lastFromCache = fromCache;
    _snapshot = snapshot;
    evaluate();
    if (reconnected) _checkIfUnresolved();
  }

  /// 回前台：推进未完成的核对。
  void onResumed() {
    if (_disposed) return;
    evaluate();
    _checkIfUnresolved();
  }

  void evaluate() {
    if (_disposed) return;
    final now = _now();
    final decision = _tracker.evaluate(_snapshot, now);
    _decision = decision;

    _evaluationTimer?.cancel();
    final next = decision.nextEvaluationMs;
    if (next != null && next >= now) {
      _evaluationTimer = _timer(Duration(milliseconds: next - now), evaluate);
    }

    if (decision.status == EntitlementStatus.awaitingRenewal) {
      _startRetryPlan(decision.periodEndMs!, decision.deadlineMs!, now);
    } else {
      _cancelRetryPlan();
    }

    if (decision.isVip != _isVip) {
      _isVip = decision.isVip;
      _onChanged(_isVip);
    }
  }

  /// 每个周期只制定一次重试计划：重试时间点相对进入等待的时刻，且都在期限之内。
  void _startRetryPlan(int periodEndMs, int deadlineMs, int now) {
    if (_retryPlanPeriodMs == periodEndMs) return;
    _cancelRetryPlan();
    _retryPlanPeriodMs = periodEndMs;
    for (final delay in retryDelays) {
      if (now + delay.inMilliseconds >= deadlineMs) continue;
      _retryTimers.add(_timer(delay, _requestCheck));
    }
  }

  void _cancelRetryPlan() {
    for (final t in _retryTimers) {
      t.cancel();
    }
    _retryTimers.clear();
  }

  void _checkIfUnresolved() {
    final now = _now();
    if (_decision.status == EntitlementStatus.awaitingRenewal ||
        _tracker.isLapsedUnresolved(_snapshot, now)) {
      _requestCheck();
    }
  }

  /// 同时发生的触发合并为一次；结论只用于决定是否继续，权益以快照为准。
  void _requestCheck() {
    final checker = _checker;
    if (_disposed || checker == null || _checkInFlight != null) return;
    final task = checker(uid);
    _checkInFlight = task;
    unawaited(task.then((_) {}, onError: (Object _) {}).whenComplete(() {
      if (identical(_checkInFlight, task)) _checkInFlight = null;
    }));
  }

  void dispose() {
    _disposed = true;
    _evaluationTimer?.cancel();
    _cancelRetryPlan();
    _checker = null;
  }
}
