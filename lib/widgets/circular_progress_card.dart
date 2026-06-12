import 'dart:math' as math;
import 'package:flutter/material.dart';

/// 圆形进度条卡片组件
/// 参考 Stitch 设计稿的双环进度条
class CircularProgressCard extends StatelessWidget {
  final double coveragePercentage; // 覆盖率百分比 (0-100)
  final double masteryPercentage; // 精通度百分比 (0-100)
  final int attemptedCount; // 已覆盖题目数
  final int masteredCount; // 已精通题目数
  final String questionUnit; // 题目单位（如"题"、"domande"等）

  const CircularProgressCard({
    super.key,
    required this.coveragePercentage,
    required this.masteryPercentage,
    required this.attemptedCount,
    required this.masteredCount,
    required this.questionUnit,
  });

  @override
  Widget build(BuildContext context) {
    // 计算总百分比（覆盖率）
    final totalPercentage = coveragePercentage.clamp(0.0, 100.0);
    final masteryPercent = masteryPercentage.clamp(0.0, 100.0);

    // 外环半径和周长
    const double outerRadius = 60.0;
    const double outerCircumference = 2 * math.pi * outerRadius;

    // 内环半径和周长
    const double innerRadius = 46.0;
    const double innerCircumference = 2 * math.pi * innerRadius;

    // 计算外环（覆盖率）的 stroke-dashoffset
    // 从顶部开始，逆时针绘制，所以 offset = circumference * (1 - percentage / 100)
    final outerOffset = outerCircumference * (1 - totalPercentage / 100);

    // 计算内环（精通度）的 stroke-dashoffset
    final innerOffset = innerCircumference * (1 - masteryPercent / 100);

    return SizedBox(
      width: 140,
      height: 140,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // SVG 圆形进度条
          CustomPaint(
            size: const Size(140, 140),
            painter: _CircularProgressPainter(
              outerRadius: outerRadius,
              innerRadius: innerRadius,
              outerOffset: outerOffset,
              innerOffset: innerOffset,
              outerCircumference: outerCircumference,
              innerCircumference: innerCircumference,
            ),
          ),
          // 中心百分比文字
          Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                totalPercentage.toStringAsFixed(1),
                style: const TextStyle(
                  fontSize: 42,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1d1d1f),
                  letterSpacing: -1.0,
                  height: 1.0,
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '%',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: const Color(0xFF1d1d1f).withOpacity(0.4),
                    height: 1.0,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 圆形进度条绘制器
class _CircularProgressPainter extends CustomPainter {
  final double outerRadius;
  final double innerRadius;
  final double outerOffset;
  final double innerOffset;
  final double outerCircumference;
  final double innerCircumference;

  _CircularProgressPainter({
    required this.outerRadius,
    required this.innerRadius,
    required this.outerOffset,
    required this.innerOffset,
    required this.outerCircumference,
    required this.innerCircumference,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);

    // 绘制背景圆环（灰色）
    final backgroundPaint = Paint()
      ..color = const Color(0xFFE5E7EB).withOpacity(0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 12
      ..strokeCap = StrokeCap.round;

    // 外环背景
    canvas.drawCircle(center, outerRadius, backgroundPaint);
    // 内环背景
    canvas.drawCircle(center, innerRadius, backgroundPaint);

    // 绘制进度圆环（外环 - 覆盖率，天蓝色渐变）
    const outerGradient = SweepGradient(
      colors: [
        const Color(0xFF38BDF8), // sky-400
        const Color(0xFF0EA5E9), // sky-500
      ],
      startAngle: -math.pi / 2, // 从顶部开始
    );

    final outerPaint = Paint()
      ..shader = outerGradient.createShader(
        Rect.fromCircle(center: center, radius: outerRadius),
      )
      ..style = PaintingStyle.stroke
      ..strokeWidth = 12
      ..strokeCap = StrokeCap.round;

    // 绘制外环进度
    // 计算进度角度：从顶部开始，顺时针绘制
    final outerProgress = (outerCircumference - outerOffset) / outerCircumference;
    final outerSweepAngle = 2 * math.pi * outerProgress;

    final outerPath = Path();
    outerPath.addArc(
      Rect.fromCircle(center: center, radius: outerRadius),
      -math.pi / 2, // 从顶部开始
      outerSweepAngle,
    );
    canvas.drawPath(outerPath, outerPaint);

    // 绘制进度圆环（内环 - 精通度，薄荷绿渐变）
    const innerGradient = SweepGradient(
      colors: [
        const Color(0xFF34D399), // emerald-400
        const Color(0xFF10B981), // emerald-500
      ],
      startAngle: -math.pi / 2,
    );

    final innerPaint = Paint()
      ..shader = innerGradient.createShader(
        Rect.fromCircle(center: center, radius: innerRadius),
      )
      ..style = PaintingStyle.stroke
      ..strokeWidth = 12
      ..strokeCap = StrokeCap.round;

    // 绘制内环进度
    final innerProgress = (innerCircumference - innerOffset) / innerCircumference;
    final innerSweepAngle = 2 * math.pi * innerProgress;

    final innerPath = Path();
    innerPath.addArc(
      Rect.fromCircle(center: center, radius: innerRadius),
      -math.pi / 2,
      innerSweepAngle,
    );
    canvas.drawPath(innerPath, innerPaint);
  }

  @override
  bool shouldRepaint(covariant _CircularProgressPainter oldDelegate) {
    return oldDelegate.outerOffset != outerOffset ||
        oldDelegate.innerOffset != innerOffset;
  }
}
