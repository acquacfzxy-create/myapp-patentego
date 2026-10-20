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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isRetro = AppTheme.isRetroFor(context);
    final card = Container(
      decoration: BoxDecoration(
        borderRadius: isRetro
            ? BorderRadius.zero
            : borderRadius ?? BorderRadius.circular(AppTheme.radiusLg),
        color: AppTheme.surfaceFor(context),
        border: Border.all(
          color: isRetro
              ? AppTheme.retroLine
              : AppTheme.usesRoadPalette
                  ? AppTheme.lineFor(context)
                  : isDark
                      ? AppTheme.nightLine.withOpacity(0.9)
                      : Colors.white.withOpacity(0.78),
          width: AppTheme.usesRoadPalette && !isRetro ? 1.5 : 1,
        ),
        boxShadow: AppTheme.cardShadowFor(context),
      ),
      child: ClipRRect(
        borderRadius: isRetro
            ? BorderRadius.zero
            : borderRadius ?? BorderRadius.circular(AppTheme.radiusLg),
        child: BackdropFilter(
          // 道路主題卡片為實色底，不需要背景模糊。
          filter: isRetro || AppTheme.usesRoadPalette
              ? ImageFilter.blur(sigmaX: 0, sigmaY: 0)
              : ImageFilter.blur(sigmaX: 14, sigmaY: 14),
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
