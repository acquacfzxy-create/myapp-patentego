import 'dart:ui';
import 'package:flutter/material.dart';

/// 玻璃态卡片组件
/// 参考 Stitch 设计稿的 glass-card 样式
class GlassCard extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry? padding;
  final BorderRadius? borderRadius;
  final bool enableScaleAnimation;

  const GlassCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding,
    this.borderRadius,
    this.enableScaleAnimation = true,
  });

  @override
  Widget build(BuildContext context) {
    final card = Container(
      decoration: BoxDecoration(
        borderRadius: borderRadius ?? BorderRadius.circular(32),
        // 玻璃态效果：半透明背景 + 模糊
        color: Colors.white.withOpacity(0.3),
        border: Border.all(
          color: Colors.white.withOpacity(0.6),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1F2687).withOpacity(0.03),
            blurRadius: 32,
            offset: const Offset(0, 8),
          ),
          // 内阴影效果
          BoxShadow(
            color: Colors.white.withOpacity(0.4),
            blurRadius: 0,
            offset: const Offset(0, 0),
            spreadRadius: 1,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: borderRadius ?? BorderRadius.circular(32),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: Padding(
            padding: padding ?? EdgeInsets.zero,
            child: child,
          ),
        ),
      ),
    );

    if (onTap == null) {
      return card;
    }

    return GestureDetector(
      onTap: onTap,
      child: AnimatedScale(
        scale: enableScaleAnimation ? 1.0 : 0.98,
        duration: const Duration(milliseconds: 200),
        child: card,
      ),
    );
  }
}
