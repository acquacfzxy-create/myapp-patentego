import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lingua_patente/config/app_theme.dart';
import 'package:lingua_patente/widgets/explanation_emphasis.dart';

/// 解析重點標記規範：對錯只標明確判定、意大利語術語統一高亮、
/// 括號統一變淡、**加粗** 三段通用且不露星號。
void main() {
  const base = TextStyle(fontSize: 14, color: AppTheme.roadInk);
  late BuildContext ctx;

  Future<void> pumpContext(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.lightTheme(language: 'zh'),
      home: Builder(builder: (context) {
        ctx = context;
        return const SizedBox.shrink();
      }),
    ));
  }

  /// 拍平成 (文字, 樣式) 列表，便於斷言。
  List<(String, TextStyle?)> flatten(TextSpan span) {
    final out = <(String, TextStyle?)>[];
    void walk(InlineSpan s) {
      if (s is TextSpan) {
        if (s.text != null && s.text!.isNotEmpty) out.add((s.text!, s.style));
        s.children?.forEach(walk);
      }
    }

    walk(span);
    return out;
  }

  TextStyle? styleOf(List<(String, TextStyle?)> parts, String text) =>
      parts.firstWhere((p) => p.$1 == text).$2;

  String plainOf(List<(String, TextStyle?)> parts) =>
      parts.map((p) => p.$1).join();

  testWidgets('everyday 错/没错 stay plain; only real verdicts are colored',
      (tester) async {
    await pumpContext(tester);
    final parts = flatten(ExplanationEmphasis.build(
      ctx,
      '很多人会搞错，这没错。答案是错，所以选Falso（错）。',
      base: base,
    ));
    expect(plainOf(parts), '很多人会搞错，这没错。答案是错，所以选Falso（错）。');
    expect(styleOf(parts, '很多人会搞错，这没错。')?.color, AppTheme.roadInk);
    expect(styleOf(parts, '答案是')?.color, AppTheme.roadInk);
    expect(styleOf(parts, '错')?.color, AppTheme.roadDanger);
    expect(styleOf(parts, 'Falso（错）')?.color, AppTheme.roadDanger);
  });

  testWidgets('Vero/Falso are colored in any language', (tester) async {
    await pumpContext(tester);
    final parts = flatten(ExplanationEmphasis.build(
      ctx,
      'Ответ Vero, а не Falso.',
      base: base,
    ));
    expect(styleOf(parts, 'Vero')?.color, AppTheme.roadPrimary);
    expect(styleOf(parts, 'Falso')?.color, AppTheme.roadDanger);
  });

  testWidgets('quoted Italian terms are highlighted, Chinese quotes are not',
      (tester) async {
    await pumpContext(tester);
    final parts = flatten(ExplanationEmphasis.build(
      ctx,
      '记住『sorpassare』，也就是「超车」，“fare attenzione”要留意。',
      base: base,
    ));
    for (final term in ['『sorpassare』', '“fare attenzione”']) {
      final style = styleOf(parts, term);
      expect(style?.fontWeight, FontWeight.w700, reason: term);
      expect(style?.color, AppTheme.roadPrimary, reason: term);
    }
    final chinese = styleOf(parts, '「超车」');
    expect(chinese?.color, AppTheme.roadInk,
        reason: 'Chinese-only quotes stay plain');
    expect(chinese?.fontWeight, isNot(FontWeight.w700));
  });

  testWidgets('full and half width parentheses are both muted',
      (tester) async {
    await pumpContext(tester);
    final parts = flatten(ExplanationEmphasis.build(
      ctx,
      'carreggiata（车行道）和 corsia (车道)',
      base: base,
    ));
    expect(styleOf(parts, '（车行道）')?.color, AppTheme.roadMuted);
    expect(styleOf(parts, '(车道)')?.color, AppTheme.roadMuted);
  });

  testWidgets('**bold** renders without asterisks and stray * disappear',
      (tester) async {
    await pumpContext(tester);
    final parts = flatten(ExplanationEmphasis.build(
      ctx,
      '* 注意 **实线** 不能跨越 *',
      base: base,
    ));
    expect(plainOf(parts).contains('*'), isFalse);
    expect(styleOf(parts, '实线')?.fontWeight, FontWeight.w700);
  });
}
