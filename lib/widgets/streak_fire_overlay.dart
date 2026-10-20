import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 連對 5 題起，畫面四周開始燃燒：底邊與兩側冒出跳動的火苗，越連對越旺，
/// 10 題起火力全開並持續燃燒。只畫在螢幕邊緣、不攔截觸控，不遮題目與按鈕；
/// 答錯（連對歸零）時淡出；系統「減少動態效果」時火焰靜止。
class StreakFireOverlay extends StatefulWidget {
  const StreakFireOverlay({super.key, required this.streak});

  final int streak;

  /// 連對數對應的火勢 0～1：5 題起燃，10 題滿格。
  static double intensityFor(int streak) {
    if (streak < 5) return 0;
    if (streak >= 10) return 1;
    return 0.35 + (streak - 5) * 0.13;
  }

  @override
  State<StreakFireOverlay> createState() => _StreakFireOverlayState();
}

class _StreakFireOverlayState extends State<StreakFireOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ticker = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  );
  double _shownIntensity = 0;

  @override
  void initState() {
    super.initState();
    _shownIntensity = StreakFireOverlay.intensityFor(widget.streak);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncTicker();
  }

  @override
  void didUpdateWidget(StreakFireOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = StreakFireOverlay.intensityFor(widget.streak);
    if (next > 0) _shownIntensity = next;
    _syncTicker();
  }

  void _syncTicker() {
    final burning = StreakFireOverlay.intensityFor(widget.streak) > 0;
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (burning && !reduceMotion) {
      if (!_ticker.isAnimating) _ticker.repeat();
    } else if (!burning) {
      // 淡出結束後再停，避免火焰在淡出途中定格。
      Future<void>.delayed(const Duration(milliseconds: 700), () {
        if (mounted && StreakFireOverlay.intensityFor(widget.streak) == 0) {
          _ticker.stop();
        }
      });
    } else {
      _ticker.stop();
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final target = StreakFireOverlay.intensityFor(widget.streak);
    return IgnorePointer(
      child: AnimatedOpacity(
        key: const Key('streak_fire_overlay'),
        opacity: target > 0 ? 1 : 0,
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeOut,
        child: RepaintBoundary(
          child: AnimatedBuilder(
            animation: _ticker,
            builder: (context, _) => CustomPaint(
              size: Size.infinite,
              painter: _EdgeFirePainter(
                time: _ticker.value,
                intensity: _shownIntensity,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EdgeFirePainter extends CustomPainter {
  _EdgeFirePainter({required this.time, required this.intensity});

  final double time;
  final double intensity;

  static const _deep = Color(0xFFB31B00);
  static const _red = Color(0xFFFF3D00);
  static const _orange = Color(0xFFFF8A1F);
  static const _yellow = Color(0xFFFFD43B);
  static const _white = Color(0xFFFFF6D6);

  @override
  void paint(Canvas canvas, Size size) {
    if (intensity <= 0 || size.isEmpty) return;
    final t = time * 2 * math.pi;

    // 邊緣暖光：整圈橙紅色暈，火越旺越明顯。
    final glow = 0.12 + 0.22 * intensity;
    final edge = 30 + 34 * intensity;
    void edgeGlow(Rect rect, Alignment begin, Alignment end) {
      canvas.drawRect(
        rect,
        Paint()
          ..shader = LinearGradient(
            begin: begin,
            end: end,
            colors: [_red.withOpacity(glow), _red.withOpacity(0)],
          ).createShader(rect),
      );
    }

    edgeGlow(Rect.fromLTWH(0, 0, edge, size.height), Alignment.centerLeft,
        Alignment.centerRight);
    edgeGlow(Rect.fromLTWH(size.width - edge, 0, edge, size.height),
        Alignment.centerRight, Alignment.centerLeft);
    edgeGlow(Rect.fromLTWH(0, 0, size.width, edge * 0.7), Alignment.topCenter,
        Alignment.bottomCenter);

    // 兩側：火舌從螢幕外橫向舔進來（略微上揚），根部整段藏在螢幕外，
    // 看不到被截平的底邊。
    const sideCount = 7;
    final sideH = size.height / sideCount;
    final sideW = sideH * 0.95;
    final sideReach = 34 + 34 * intensity;
    const tilt = 70 * math.pi / 180; // 從「向上」順時針轉 70°：朝內、略向上
    final hiddenBase = sideW / 2 * math.cos(tilt) + 10;
    for (var i = 0; i < sideCount; i++) {
      final phase = i * 2.1;
      for (final left in [true, false]) {
        final p = phase + (left ? 0 : 3.3);
        final f = 0.62 +
            0.25 * math.sin(t * 2.2 + p) +
            0.13 * math.sin(t * 5.3 + p * 1.7);
        _flame(
          canvas,
          base: Offset(
            left ? -hiddenBase : size.width + hiddenBase,
            sideH * (i + 0.6),
          ),
          angle: left ? tilt : -tilt,
          width: sideW,
          // 先補上藏在螢幕外的那段，再加上真正露出的火舌長度。
          height: hiddenBase + sideReach * f,
          t: t,
          phase: p,
        );
      }
    }

    // 底邊：一排高低起伏的火舌，壓低在答題按鈕下方。
    const count = 10;
    final maxH = 18 + 22 * intensity;
    final w = size.width / count;
    for (var i = 0; i < count; i++) {
      final phase = i * 1.7;
      final f = 0.6 +
          0.25 * math.sin(t * (2 + (i % 3) * 0.5) + phase) +
          0.15 * math.sin(t * 4.7 + phase * 2);
      _flame(
        canvas,
        // 根部壓在螢幕底邊以下，連模糊光暈一起藏住。
        base: Offset(w * (i + 0.5), size.height + 12),
        angle: 0,
        width: w * 1.3,
        height: 12 + maxH * f,
        t: t,
        phase: phase,
      );
    }

    // 火星：從火焰裡往上飄、邊飄邊熄。
    final embers = (6 + 14 * intensity).round();
    for (var i = 0; i < embers; i++) {
      final seed = i * 37.0;
      final speed = 0.35 + (i % 5) * 0.08;
      final life = (time * speed * 3 + (i * 0.137) % 1) % 1;
      final fromLeft = i.isEven;
      final x0 = fromLeft ? 6 + (seed % 23) : size.width - 6 - (seed % 23);
      final y0 = size.height * (0.25 + ((i * 0.618) % 0.75));
      final pos = Offset(
        x0 + math.sin(t * 2 + i) * 6 + (fromLeft ? 1 : -1) * life * 14,
        y0 - life * (60 + 50 * intensity),
      );
      final alpha = (1 - life) * (0.55 + 0.45 * intensity);
      canvas.drawCircle(
        pos,
        1.2 + (1 - life) * 1.6,
        Paint()
          ..color = Color.lerp(_yellow, _red, life)!.withOpacity(alpha)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.2),
      );
    }
  }

  /// 一條火苗：外層暗紅模糊光暈、中層橙色、內芯亮黃白；
  /// 尖端細長，邊緣隨時間左右彎曲，像真的火舌一樣舔動。
  void _flame(
    Canvas canvas, {
    required Offset base,
    required double width,
    required double height,
    required double angle,
    required double t,
    required double phase,
  }) {
    if (height <= 2) return;
    // 在局部座標裡畫一條朝上的火苗，再平移、旋轉到指定位置與方向。
    canvas.save();
    canvas.translate(base.dx, base.dy);
    canvas.rotate(angle);
    base = Offset.zero;
    const lean = 0.0;
    Path tongue(double scaleW, double scaleH) {
      final h = height * scaleH;
      final hw = width * scaleW / 2;
      final sway1 = math.sin(t * 3.1 + phase) * hw * 0.35;
      final sway2 = math.sin(t * 4.3 + phase * 1.3) * hw * 0.5;
      final tip = Offset(base.dx + lean * h + sway2, base.dy - h);
      return Path()
        ..moveTo(base.dx - hw, base.dy)
        ..cubicTo(
          base.dx - hw * 1.05,
          base.dy - h * 0.35,
          base.dx - hw * 0.35 + sway1 + lean * h * 0.4,
          base.dy - h * 0.6,
          tip.dx,
          tip.dy,
        )
        ..cubicTo(
          base.dx + hw * 0.25 + sway1 + lean * h * 0.5,
          base.dy - h * 0.55,
          base.dx + hw * 1.05,
          base.dy - h * 0.3,
          base.dx + hw,
          base.dy,
        )
        ..close();
    }

    Shader shade(Rect r, List<Color> colors, List<double> stops) =>
        LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: colors,
          stops: stops,
        ).createShader(r);

    final a = intensity.clamp(0.55, 1.0);
    final outer = tongue(1.0, 1.0);
    final bounds = outer.getBounds();
    canvas.drawPath(
      outer,
      Paint()
        ..shader = shade(bounds, [
          _red.withOpacity(0.75 * a),
          _deep.withOpacity(0.45 * a),
          _deep.withOpacity(0),
        ], const [
          0,
          0.6,
          1
        ])
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    final mid = tongue(0.72, 0.8);
    canvas.drawPath(
      mid,
      Paint()
        ..shader = shade(mid.getBounds(), [
          _yellow.withOpacity(0.9 * a),
          _orange.withOpacity(0.8 * a),
          _red.withOpacity(0),
        ], const [
          0,
          0.5,
          1
        ])
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5),
    );
    final core = tongue(0.38, 0.5);
    canvas.drawPath(
      core,
      Paint()
        ..shader = shade(core.getBounds(), [
          _white.withOpacity(0.95 * a),
          _yellow.withOpacity(0.7 * a),
          _yellow.withOpacity(0),
        ], const [
          0,
          0.55,
          1
        ])
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.5),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_EdgeFirePainter old) =>
      old.time != time || old.intensity != intensity;
}
