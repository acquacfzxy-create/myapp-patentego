import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../config/app_theme.dart';

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
  int _shownStreak = 0;
  List<ui.Image>? _sprites;
  double _spriteDpr = 0;

  @override
  void initState() {
    super.initState();
    _shownIntensity = StreakFireOverlay.intensityFor(widget.streak);
    _shownStreak = widget.streak;
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
    if (next > 0) {
      _shownIntensity = next;
      _shownStreak = widget.streak;
    }
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
    for (final image in _sprites ?? const <ui.Image>[]) {
      image.dispose();
    }
    super.dispose();
  }

  /// 火苗貼圖：三層火舌與模糊光暈只畫一次，之後每幀只做縮放、傾斜貼上，
  /// 避免每幀對幾十條火舌即時模糊（真機上原本每幀繪製約 30ms）。
  List<ui.Image> _spritesFor(double dpr) {
    if (_sprites != null && _spriteDpr == dpr) return _sprites!;
    for (final image in _sprites ?? const <ui.Image>[]) {
      image.dispose();
    }
    _spriteDpr = dpr;
    _sprites = [
      _FlameSprite.render(dpr, curl: 0.35),
      _FlameSprite.render(dpr, curl: -0.45),
    ];
    return _sprites!;
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
          child: target <= 0 && !_ticker.isAnimating && _sprites == null
              ? const SizedBox.expand()
              : AppTheme.isRetroFor(context)
                  // 復古主題：像素方塊火焰，約 8fps 逐格切換。
                  ? AnimatedBuilder(
                      animation: _ticker,
                      builder: (context, _) => CustomPaint(
                        size: Size.infinite,
                        painter: _PixelFirePainter(
                          frame: (_ticker.value * 19).floor(),
                          streak: _shownStreak,
                          intensity: _shownIntensity,
                        ),
                      ),
                    )
                  : AnimatedBuilder(
                      animation: _ticker,
                      builder: (context, _) => CustomPaint(
                        size: Size.infinite,
                        painter: _EdgeFirePainter(
                          // 火焰以約 30fps 更新即可，其餘幀跳過重繪。
                          time: (_ticker.value * 72).floor() / 72,
                          intensity: _shownIntensity,
                          sprites: _spritesFor(
                              MediaQuery.devicePixelRatioOf(context)),
                        ),
                      ),
                    ),
        ),
      ),
    );
  }
}

class _EdgeFirePainter extends CustomPainter {
  _EdgeFirePainter({
    required this.time,
    required this.intensity,
    required this.sprites,
  });

  final double time;
  final double intensity;
  final List<ui.Image> sprites;

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
        Paint()..color = Color.lerp(_yellow, _red, life)!.withOpacity(alpha),
      );
    }
  }

  /// 一條火苗：取預先畫好的火苗貼圖，平移、旋轉到位，按高度縮放並隨時間
  /// 左右傾斜，模擬火舌舔動。
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
    final sprite = sprites[(phase * 10).round().abs() % sprites.length];
    final sway = math.sin(t * 4.3 + phase * 1.3) * 0.22 +
        math.sin(t * 3.1 + phase) * 0.12;
    canvas.save();
    canvas.translate(base.dx, base.dy);
    canvas.rotate(angle);
    canvas.skew(sway, 0);
    canvas.drawImageRect(
      sprite,
      Rect.fromLTWH(0, 0, sprite.width.toDouble(), sprite.height.toDouble()),
      Rect.fromLTWH(-width / 2, -height, width, height),
      Paint()
        ..filterQuality = FilterQuality.low
        ..color = Color.fromRGBO(0, 0, 0, intensity.clamp(0.55, 1.0)),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_EdgeFirePainter old) =>
      old.time != time || old.intensity != intensity || old.sprites != sprites;
}

/// 一張朝上的火苗貼圖（局部 60×120，按螢幕密度放大）：外層暗紅模糊光暈、
/// 中層橙色、內芯亮黃白；[curl] 決定火舌的彎曲方向，讓兩種貼圖不雷同。
class _FlameSprite {
  static const double w = 60;
  static const double h = 120;

  static ui.Image render(double dpr, {required double curl}) {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.scale(dpr);
    const base = Offset(w / 2, h);

    Path tongue(double scaleW, double scaleH) {
      final th = (h - 8) * scaleH;
      final hw = w * 0.4 * scaleW;
      final bend = curl * hw;
      final tip = Offset(base.dx + bend * 0.8, base.dy - th);
      return Path()
        ..moveTo(base.dx - hw, base.dy)
        ..cubicTo(base.dx - hw * 1.05, base.dy - th * 0.35,
            base.dx - hw * 0.35 + bend, base.dy - th * 0.6, tip.dx, tip.dy)
        ..cubicTo(base.dx + hw * 0.25 + bend, base.dy - th * 0.55,
            base.dx + hw * 1.05, base.dy - th * 0.3, base.dx + hw, base.dy)
        ..close();
    }

    Shader shade(Path path, List<Color> colors, List<double> stops) =>
        LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: colors,
          stops: stops,
        ).createShader(path.getBounds());

    final outer = tongue(1, 1);
    canvas.drawPath(
      outer,
      Paint()
        ..shader = shade(outer, [
          _EdgeFirePainter._red.withOpacity(0.75),
          _EdgeFirePainter._deep.withOpacity(0.45),
          _EdgeFirePainter._deep.withOpacity(0),
        ], const [
          0,
          0.6,
          1
        ])
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
    );
    final mid = tongue(0.72, 0.8);
    canvas.drawPath(
      mid,
      Paint()
        ..shader = shade(mid, [
          _EdgeFirePainter._yellow.withOpacity(0.9),
          _EdgeFirePainter._orange.withOpacity(0.8),
          _EdgeFirePainter._red.withOpacity(0),
        ], const [
          0,
          0.5,
          1
        ])
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
    );
    final core = tongue(0.38, 0.5);
    canvas.drawPath(
      core,
      Paint()
        ..shader = shade(core, [
          _EdgeFirePainter._white.withOpacity(0.95),
          _EdgeFirePainter._yellow.withOpacity(0.7),
          _EdgeFirePainter._yellow.withOpacity(0),
        ], const [
          0,
          0.55,
          1
        ])
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.2),
    );
    return recorder
        .endRecording()
        .toImageSync((w * dpr).ceil(), (h * dpr).ceil());
  }
}

/// 復古主題的像素火焰：經典 8-bit 火把造型的火苗點陣圖，三幀輪流切換，
/// 每株火苗錯開節奏。只在兩側：火苗朝螢幕內伸、根部藏在螢幕外，
/// 另有暖色像素火星往上飄。顏色借用復古主題的深棕，再配暗橙、暗黃，
/// 飽和度壓低以融入橄欖綠底色。同色方塊合併成一條路徑一次畫完。
class _PixelFirePainter extends CustomPainter {
  _PixelFirePainter({
    required this.frame,
    required this.intensity,
    required this.streak,
  });

  final int streak;

  final int frame;
  final double intensity;

  /// 每個像素點的邊長（邏輯像素）。
  static const double px = 3;

  /// 'o' 外焰（深棕）、'm' 火身（暗橙）、'c' 火芯（暗黃）。
  static const List<List<String>> _frames = [
    [
      '...o...',
      '..oo...',
      '..omo..',
      '.oomo..',
      '.ommoo.',
      'oomcmo.',
      'omccmoo',
      'omcccmo',
      'omcccmo',
      'oommmoo',
      '.ooooo.',
    ],
    [
      '....o..',
      '...oo..',
      '..omo..',
      '..ommo.',
      '.oomcmo',
      '.omcmo.',
      'omccmoo',
      'omcccmo',
      'omcccmo',
      'oommmoo',
      '.ooooo.',
    ],
    [
      '.......',
      '...o...',
      '..oo...',
      '..omo..',
      '.ommoo.',
      'oomcmo.',
      'omccmoo',
      'omcccmo',
      'omcccmo',
      'oommmoo',
      '.ooooo.',
    ],
  ];

  static const _outer = AppTheme.retroDanger; // 深棕
  static const _body = Color(0xFFA85A2A); // 暗橙
  static const _core = Color(0xFFE2BC5A); // 暗黃

  static const double _spriteW = 7 * px;
  static const double _spriteH = 11 * px;

  @override
  void paint(Canvas canvas, Size size) {
    if (intensity <= 0 || size.isEmpty) return;
    final outer = Path();
    final body = Path();
    final core = Path();

    /// 在局部座標（火苗朝上、底部中點在原點）把一株火苗的點陣加進路徑，
    /// 再由 [toScreen] 轉成螢幕座標。
    void flame(int frameIndex, Offset Function(Offset local) toScreen) {
      final rows = _frames[frameIndex % _frames.length];
      for (var r = 0; r < rows.length; r++) {
        final row = rows[r];
        for (var c = 0; c < row.length; c++) {
          final ch = row[c];
          if (ch == '.') continue;
          final local = Offset(c * px - _spriteW / 2, r * px - _spriteH);
          final a = toScreen(local);
          final b = toScreen(local + const Offset(px, px));
          final rect = Rect.fromPoints(a, b);
          (ch == 'o'
                  ? outer
                  : ch == 'm'
                      ? body
                      : core)
              .addRect(rect);
        }
      }
    }

    void sized(double scale, int frameIndex, Offset Function(Offset) place) {
      flame(frameIndex, (l) => place(l * scale));
    }

    /// 在左側或右側某個高度放一株火苗：橫放朝內，根部藏在螢幕外。
    void sideFlame(bool left, double y, double scale, int f,
        {double hiddenRatio = 0.4}) {
      final hidden = _spriteH * scale * hiddenRatio;
      if (left) {
        sized(scale, f, (l) => Offset(-l.dy - hidden, y + l.dx));
      } else {
        sized(scale, f, (l) => Offset(size.width + l.dy + hidden, y - l.dx));
      }
    }

    // 5 連對 1 株，每多答對 1 題多 1 株，最多 14 株；
    // 左側從下往上、右側從按鈕上方往上，左右交替長出，株距緊湊成串。
    const scale = 5 / px;
    const step = _spriteW * scale + 8;
    final count = (streak - 4).clamp(1, 14);
    var leftRow = 0;
    var rightRow = 0;
    for (var k = 0; k < count; k++) {
      final left = k.isEven;
      final y = left
          // 左側起點在答題按鈕上方，不壓到 VERO。
          ? size.height * 0.78 - leftRow++ * step
          : size.height * 0.46 - rightRow++ * step;
      sideFlame(left, y, scale, frame + k * 2);
    }

    // 底邊不放火苗：那裡是系統導航列與答題按鈕，火苗會被導航列蓋住發白。

    // 像素火星：從兩側往上飄、逐漸變暗。
    final embers = (3 + 5 * intensity).round();
    for (var i = 0; i < embers; i++) {
      final speed = 2 + i % 3;
      final life = ((frame * speed + i * 7) % 24) / 24;
      final fromLeft = i.isEven;
      final x = fromLeft ? px * (2 + i % 3) : size.width - px * (3 + i % 3);
      final y0 = size.height * (0.3 + ((i * 0.618) % 0.65));
      final raw = y0 - life * 120;
      final y = raw - (raw % px);
      (life < 0.5 ? core : body).addRect(Offset(x, y) & const Size(px, px));
    }

    final a = intensity.clamp(0.6, 1.0);
    canvas.drawPath(outer, Paint()..color = _outer.withOpacity(0.92 * a));
    canvas.drawPath(body, Paint()..color = _body.withOpacity(0.92 * a));
    canvas.drawPath(core, Paint()..color = _core.withOpacity(0.95 * a));
  }

  @override
  bool shouldRepaint(_PixelFirePainter old) =>
      old.frame != frame || old.intensity != intensity || old.streak != streak;
}
