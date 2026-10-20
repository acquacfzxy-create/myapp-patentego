import 'package:flutter/material.dart';

/// 按下時輕微縮小、放開後彈性回彈。只監聽原始指標事件，不參與手勢競爭，
/// 因此可直接包住已有 onTap 的卡片；[enabled] 為 false 時不做動畫。
class BouncyPress extends StatefulWidget {
  const BouncyPress({super.key, required this.child, this.enabled = true});

  final Widget child;
  final bool enabled;

  @override
  State<BouncyPress> createState() => _BouncyPressState();
}

class _BouncyPressState extends State<BouncyPress>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    // 上下界留出空間，彈性曲線的過衝（略大於 1）才不會被截掉。
    lowerBound: 0.8,
    upperBound: 1.1,
    value: 1.0,
  );

  void _press() {
    if (!widget.enabled) return;
    _controller.animateTo(
      0.92,
      duration: const Duration(milliseconds: 90),
      curve: Curves.easeOut,
    );
  }

  void _release() {
    // 按下後卡片可能立刻變成不可點（例如答題後），仍要彈回原大小。
    if (_controller.value == 1.0) return;
    _controller.animateTo(
      1.0,
      duration: const Duration(milliseconds: 480),
      curve: Curves.elasticOut,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) => _press(),
      onPointerUp: (_) => _release(),
      onPointerCancel: (_) => _release(),
      child: ScaleTransition(scale: _controller, child: widget.child),
    );
  }
}
