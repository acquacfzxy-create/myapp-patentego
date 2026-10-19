import 'dart:async';

/// Retains one pending advance while reading/summary surfaces overlap.
/// Resuming always gives the learner a fresh feedback interval.
class PracticeAutoAdvance {
  PracticeAutoAdvance({
    this.delay = const Duration(milliseconds: 1250),
  });

  final Duration delay;
  final Set<String> _pauses = {};
  Timer? _timer;
  void Function()? _pending;
  bool _disposed = false;

  void schedule(void Function() action) {
    if (_disposed) return;
    cancel();
    _pending = action;
    _start();
  }

  void pause(String reason) {
    _pauses.add(reason);
    _timer?.cancel();
    _timer = null;
  }

  void resume(String reason) {
    if (_pauses.remove(reason)) _start();
  }

  void _start() {
    if (_disposed || _pauses.isNotEmpty || _pending == null) return;
    _timer?.cancel();
    _timer = Timer(delay, () {
      final action = _pending;
      _pending = null;
      _timer = null;
      action?.call();
    });
  }

  void cancel() {
    _timer?.cancel();
    _timer = null;
    _pending = null;
  }

  void dispose() {
    _disposed = true;
    cancel();
  }
}
