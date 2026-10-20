import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../config/app_theme.dart';

/// 首頁功能入口的路牌圖標，取意大利道路標誌的形狀：
/// 自由練習＝藍色圓形指示牌、章節練習＝藍色方形資訊牌、
/// 模擬考試＝黃色計時牌、錯題回顧＝紅邊三角警告牌。
enum RoadSignKind { freePractice, chapters, mockTest, mistakes }

class RoadSignIcon extends StatelessWidget {
  const RoadSignIcon({super.key, required this.kind, this.size = 60});

  final RoadSignKind kind;
  final double size;

  static const Color _signBlue = Color(0xFF1F4E9E);

  @override
  Widget build(BuildContext context) {
    switch (kind) {
      case RoadSignKind.freePractice:
        return _circleSign(Icons.shuffle_rounded);
      case RoadSignKind.chapters:
        return _squareSign(Icons.menu_book_rounded);
      case RoadSignKind.mockTest:
        return _timerSign();
      case RoadSignKind.mistakes:
        return SizedBox(
          width: size,
          height: size,
          child: CustomPaint(painter: _WarningTrianglePainter()),
        );
    }
  }

  Widget _circleSign(IconData icon) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: _signBlue,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: size * 0.05),
        boxShadow: const [
          BoxShadow(color: AppTheme.roadInk, offset: Offset(0, 3)),
        ],
      ),
      child: Icon(icon, size: size * 0.52, color: Colors.white),
    );
  }

  Widget _squareSign(IconData icon) {
    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(size * 0.06),
      decoration: BoxDecoration(
        color: _signBlue,
        borderRadius: BorderRadius.circular(size * 0.18),
        boxShadow: const [
          BoxShadow(color: AppTheme.roadInk, offset: Offset(0, 3)),
        ],
      ),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(size * 0.12),
          border: Border.all(color: Colors.white, width: size * 0.035),
        ),
        child: Icon(icon, size: size * 0.46, color: Colors.white),
      ),
    );
  }

  Widget _timerSign() {
    // 略微傾斜，像剛按下的計時器，讓入口不那麼死板。
    return Transform.rotate(
      angle: -8 * math.pi / 180,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: AppTheme.roadAccent,
          borderRadius: BorderRadius.circular(size * 0.22),
          border: Border.all(color: AppTheme.roadInk, width: size * 0.05),
          boxShadow: const [
            BoxShadow(color: AppTheme.roadInk, offset: Offset(0, 3)),
          ],
        ),
        child: Icon(
          Icons.timer_outlined,
          size: size * 0.56,
          color: AppTheme.roadInk,
        ),
      ),
    );
  }
}

/// 白底紅邊三角警告牌，中間一個深色驚嘆號。
class _WarningTrianglePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    Path triangle(double inset) {
      return Path()
        ..moveTo(w / 2, h * 0.06 + inset)
        ..lineTo(w - w * 0.04 - inset * 1.15, h * 0.9 - inset * 0.6)
        ..lineTo(w * 0.04 + inset * 1.15, h * 0.9 - inset * 0.6)
        ..close();
    }

    final outer = triangle(0);
    // 底部厚陰影，與其他入口的實色陰影一致。
    canvas.drawPath(
      outer.shift(const Offset(0, 3)),
      Paint()..color = AppTheme.roadInk,
    );
    canvas.drawPath(
      outer,
      Paint()
        ..color = AppTheme.roadDanger
        ..style = PaintingStyle.fill
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.drawPath(triangle(w * 0.11), Paint()..color = Colors.white);

    final bar = Paint()
      ..color = AppTheme.roadInk
      ..strokeWidth = w * 0.085
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(w / 2, h * 0.38), Offset(w / 2, h * 0.6), bar);
    canvas.drawCircle(Offset(w / 2, h * 0.73), w * 0.05, bar);
  }

  @override
  bool shouldRepaint(_WarningTrianglePainter oldDelegate) => false;
}
