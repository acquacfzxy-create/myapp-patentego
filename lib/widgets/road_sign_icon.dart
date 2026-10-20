import 'package:flutter/material.dart';

import '../config/app_theme.dart';

/// 首頁功能入口的一套路牌圖標：同樣的圓角方形牌面、同樣的深色描邊與
/// 實色厚底陰影、同一組圓角線條圖示，只用道路標誌的四種底色區分：
/// 自由練習＝高速綠、章節練習＝指示藍、模擬考試＝標誌黃、錯題回顧＝警示紅。
enum RoadSignKind { freePractice, chapters, mockTest, mistakes }

class RoadSignIcon extends StatelessWidget {
  const RoadSignIcon({super.key, required this.kind, this.size = 60});

  final RoadSignKind kind;
  final double size;

  static const Color _signBlue = Color(0xFF1F4E9E);

  (Color fill, Color glyph, IconData icon) get _spec {
    switch (kind) {
      case RoadSignKind.freePractice:
        return (AppTheme.roadPrimary, Colors.white, Icons.shuffle_rounded);
      case RoadSignKind.chapters:
        return (_signBlue, Colors.white, Icons.menu_book_rounded);
      case RoadSignKind.mockTest:
        return (AppTheme.roadAccent, AppTheme.roadInk, Icons.timer_rounded);
      case RoadSignKind.mistakes:
        return (
          AppTheme.roadDanger,
          Colors.white,
          Icons.priority_high_rounded,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final (fill, glyph, icon) = _spec;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(size * 0.26),
        border: Border.all(color: AppTheme.roadInk, width: size * 0.045),
        boxShadow: [
          BoxShadow(color: AppTheme.roadInk, offset: Offset(0, size * 0.07)),
        ],
      ),
      // 牌面內一圈細白線，呼應真實路牌的反光邊框。
      child: Padding(
        padding: EdgeInsets.all(size * 0.07),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(size * 0.17),
            border: Border.all(
              color: glyph.withOpacity(0.55),
              width: size * 0.025,
            ),
          ),
          child: Icon(icon, size: size * 0.5, color: glyph),
        ),
      ),
    );
  }
}
