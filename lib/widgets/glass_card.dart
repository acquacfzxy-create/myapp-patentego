import 'dart:ui';
import 'package:flutter/material.dart';
import '../config/app_theme.dart';

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
        borderRadius: borderRadius ?? BorderRadius.circular(AppTheme.radiusLg),
        color: AppTheme.surface,
        border: Border.all(
          color: Colors.white.withOpacity(0.78),
          width: 1,
        ),
        boxShadow: AppTheme.cardShadow,
      ),
      child: ClipRRect(
        borderRadius: borderRadius ?? BorderRadius.circular(AppTheme.radiusLg),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
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
