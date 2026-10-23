import 'dart:async';

/// Retains one pending advance while reading/summary surfaces overlap.
/// Resuming always gives the learner a fresh feedback interval.
///
/// The interval starts when the answer is tapped and runs alongside saving:
/// [hold] keeps the advance from firing until [release], without restarting
/// the clock. Switch timing is set here on its own, not by the length of the
/// answer motion or other feedback animations.
class PracticeAutoAdvance {
  PracticeAutoAdvance({
    this.delay = wrongDelay,
  });

  /// 答對後切題前的停留。
  static const Duration correctDelay = Duration(milliseconds: 600);

  /// 答錯後多留一點時間看清正確答案。
  static const Duration wrongDelay = Duration(milliseconds: 1000);

  final Duration delay;
  final Set<String> _pauses = {};
  final Set<String> _holds = {};
  Timer? _timer;
  void Function()? _pending;
  Duration _currentDelay = Duration.zero;
  bool _due = false;
  bool _disposed = false;

  void schedule(void Function() action, {Duration? delay}) {
    if (_disposed) return;
    cancel();
    _pending = action;
    _currentDelay = delay ?? this.delay;
    _start();
  }

  void pause(String reason) {
    _pauses.add(reason);
    _timer?.cancel();
    _timer = null;
    _due = false;
  }

  void resume(String reason) {
    if (_pauses.remove(reason)) _start();
  }

  /// Blocks firing (e.g. while the answer is still being saved) without
  /// restarting the interval; once released, a due advance fires at once.
  void hold(String reason) {
    if (_disposed) return;
    _holds.add(reason);
  }

  void release(String reason) {
    if (_holds.remove(reason)) _fireIfDue();
  }

  void _start() {
    if (_disposed || _pauses.isNotEmpty || _pending == null) return;
    _timer?.cancel();
    _due = false;
    _timer = Timer(_currentDelay, () {
      _timer = null;
      _due = true;
      _fireIfDue();
    });
  }

  void _fireIfDue() {
    if (!_due || _holds.isNotEmpty || _pauses.isNotEmpty) return;
    final action = _pending;
    _pending = null;
    _due = false;
    action?.call();
  }

  void cancel() {
    _timer?.cancel();
    _timer = null;
    _pending = null;
    _due = false;
    _holds.clear();
  }

  void dispose() {
    _disposed = true;
    cancel();
  }
}
