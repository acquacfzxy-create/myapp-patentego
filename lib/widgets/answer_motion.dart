import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 答題按鈕的對錯動效：答對時輕輕彈起（放大到約 1.06 再落回），
/// 答錯時左右輕抖兩下。整段約 0.42 秒，在 1.25 秒自動跳題前結束；
/// 系統開啟「減少動態效果」時不播放，只保留顏色變化。
enum AnswerMotionKind { none, correctPop, wrongShake }

class AnswerMotion extends StatefulWidget {
  const AnswerMotion({super.key, required this.kind, required this.child});

  final AnswerMotionKind kind;
  final Widget child;

  @override
  State<AnswerMotion> createState() => _AnswerMotionState();
}

class _AnswerMotionState extends State<AnswerMotion>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );

  static final Animatable<double> _pop = TweenSequence<double>([
    TweenSequenceItem(
      tween: Tween(begin: 1.0, end: 1.06)
          .chain(CurveTween(curve: Curves.easeOut)),
      weight: 35,
    ),
    TweenSequenceItem(
      tween: Tween(begin: 1.06, end: 1.0)
          .chain(CurveTween(curve: Curves.elasticOut)),
      weight: 65,
    ),
  ]);

  @override
  void initState() {
    super.initState();
    _maybePlay(AnswerMotionKind.none);
  }

  @override
  void didUpdateWidget(AnswerMotion oldWidget) {
    super.didUpdateWidget(oldWidget);
    _maybePlay(oldWidget.kind);
  }

  void _maybePlay(AnswerMotionKind previous) {
    if (widget.kind == AnswerMotionKind.none || widget.kind == previous) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) return;
      _controller.forward(from: 0);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) {
        final t = _controller.value;
        if (!_controller.isAnimating && t == 0 || t == 1) return child!;
        switch (widget.kind) {
          case AnswerMotionKind.correctPop:
            return Transform.scale(scale: _pop.transform(t), child: child);
          case AnswerMotionKind.wrongShake:
            // 兩次來回、逐漸減弱的水平抖動，最大 7dp。
            final dx = math.sin(t * math.pi * 4) * 7 * (1 - t);
            return Transform.translate(offset: Offset(dx, 0), child: child);
          case AnswerMotionKind.none:
            return child!;
        }
      },
    );
  }
}
