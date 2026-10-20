import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 連對徽章的持續抖動：像被火烤得坐不住。[strength] 0 不動、1 輕抖、2 明顯抖；
/// 系統「減少動態效果」時保持靜止。
class StreakJitter extends StatefulWidget {
  const StreakJitter({super.key, required this.strength, required this.child});

  final int strength;
  final Widget child;

  @override
  State<StreakJitter> createState() => _StreakJitterState();
}

class _StreakJitterState extends State<StreakJitter>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(StreakJitter oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  void _sync() {
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (widget.strength > 0 && !reduceMotion) {
      if (!_controller.isAnimating) _controller.repeat();
    } else {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.strength <= 0) return widget.child;
    final amp = widget.strength >= 2 ? 1.0 : 0.55;
    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) {
        final t = _controller.value * 2 * math.pi;
        // 幾個不同頻率疊加，抖動不呆板。
        final dx = (math.sin(t * 5) + 0.6 * math.sin(t * 11 + 1)) * 1.6 * amp;
        final dy = math.sin(t * 7 + 2) * 1.1 * amp;
        final angle = math.sin(t * 6 + 0.5) * 0.045 * amp;
        final scale = 1 + math.sin(t * 4) * 0.035 * amp;
        return Transform.translate(
          offset: Offset(dx, dy),
          child: Transform.rotate(
            angle: angle,
            child: Transform.scale(scale: scale, child: child),
          ),
        );
      },
    );
  }
}
