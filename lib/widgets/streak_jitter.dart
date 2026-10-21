import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../config/app_theme.dart';

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
    if (AppTheme.isRetroFor(context)) {
      // 復古主題：約 8fps 逐格跳動，位移取 2 像素整數格，不旋轉不縮放。
      return AnimatedBuilder(
        animation: _controller,
        child: RepaintBoundary(child: widget.child),
        builder: (context, child) {
          final step = (_controller.value * 7).floor();
          const pattern = [
            Offset(0, 0),
            Offset(2, -2),
            Offset(0, 0),
            Offset(-2, 0),
            Offset(0, -2),
            Offset(2, 0),
            Offset(-2, -2),
          ];
          final o = pattern[step % pattern.length] * amp;
          final moved = Transform.translate(
            offset: Offset(o.dx.roundToDouble(), o.dy.roundToDouble()),
            child: child,
          );
          // 每隔一格變淡一次，像老掌機的閃爍提示（顏色仍在復古色板內）。
          return step.isOdd ? Opacity(opacity: 0.45, child: moved) : moved;
        },
      );
    }
    return AnimatedBuilder(
      animation: _controller,
      // 徽章本身（含大光暈陰影）單獨快取，抖動時只變換位置，不必每幀重畫。
      child: RepaintBoundary(child: widget.child),
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
