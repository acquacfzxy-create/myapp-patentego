import 'package:flutter/material.dart';

import '../config/app_theme.dart';

/// 解析文字的統一重點標記規則（詳細說明、考點總結、教練小貼士共用）：
///
/// 1. 對錯顏色只給明確判定：Vero/Falso（以及大寫 True/False）在所有語言標色；
///    中文「對/錯/正確/錯誤」只在緊跟 Vero/Falso 的括號裡，或跟在
///    「答案是」「結論是」「所以是」「選」「判為」之後才標色，「搞錯」「沒錯」不標。
/// 2. 『』「」“” 中含意大利語（拉丁字母）的內容統一顯示為加粗主色術語，保留引號；
///    純中文引用保持普通文字。
/// 3. 全形（）與半形 () 括號內的補充說明統一變淡。
/// 4. `**加粗**` 在三段裡都生效，不露出星號；落單的 `*` 不顯示。
class ExplanationEmphasis {
  const ExplanationEmphasis._();

  static const _verdictWords = r'对|错|正确|错误|對|錯|正確|錯誤';

  static final RegExp _bold = RegExp(r'\*\*(.+?)\*\*', dotAll: true);

  static final RegExp _token = RegExp(
    // 1) Vero/Falso 後緊跟中文判定括號：Falso（错）、『Vero』(对)
    '(?<vp>[『「“]?(?<vpw>Vero|Falso|VERO|FALSO|vero|falso|True|False)[』」”]?'
    '\\s*[（(](?<vpc>$_verdictWords)[）)])'
    // 2) 判定提示詞 + 中文判定詞
    '|(?<cue>(?:答案是|结论是|結論是|所以是|判为|判為|选|選)[：:\\s]*[『「“]?)'
    '(?<cw>$_verdictWords)(?![\\u4e00-\\u9fff])'
    // 3) 引號
    '|(?<q>[『「“])(?<qi>[^『』「」“”\\n]{1,80})(?<qc>[』」”])'
    // 4) 括號
    '|(?<p>（[^（）\\n]*）|\\([^()\\n]*\\))'
    // 5) 單獨的 Vero/Falso/True/False
    '|(?<v>\\b(?:Vero|Falso|VERO|FALSO|vero|falso|True|False)\\b)',
  );

  static final RegExp _latin = RegExp(r'[A-Za-zÀ-ÿ]');

  static bool _isTrueWord(String word) {
    final w = word.toLowerCase();
    return w == 'vero' ||
        w == 'true' ||
        word == '对' ||
        word == '對' ||
        word == '正确' ||
        word == '正確';
  }

  /// 將解析文字轉成帶重點樣式的 [TextSpan]；[base] 決定字號、行高與正文顏色。
  static TextSpan build(
    BuildContext context,
    String text, {
    required TextStyle base,
  }) {
    final styles = _Styles.of(context, base);
    final spans = <InlineSpan>[];
    var index = 0;
    for (final m in _bold.allMatches(text)) {
      if (m.start > index) {
        _addTokens(spans, text.substring(index, m.start), styles, bold: false);
      }
      _addTokens(spans, m.group(1) ?? '', styles, bold: true);
      index = m.end;
    }
    if (index < text.length) {
      _addTokens(spans, text.substring(index), styles, bold: false);
    }
    return TextSpan(style: base, children: spans);
  }

  static void _addTokens(
    List<InlineSpan> spans,
    String raw,
    _Styles s, {
    required bool bold,
  }) {
    // 落單的 * 是排版殘留，直接去掉。
    final text = raw.replaceAll('*', '');
    final plain = bold ? s.bold : s.base;
    var current = 0;
    for (final m in _token.allMatches(text)) {
      if (m.start > current) {
        spans.add(TextSpan(text: text.substring(current, m.start), style: plain));
      }
      if (m.namedGroup('vp') != null) {
        final style =
            _isTrueWord(m.namedGroup('vpc')!) ? s.verdictTrue : s.verdictFalse;
        spans.add(TextSpan(text: m.group(0), style: style));
      } else if (m.namedGroup('cw') != null) {
        spans.add(TextSpan(text: m.namedGroup('cue'), style: plain));
        final word = m.namedGroup('cw')!;
        spans.add(TextSpan(
          text: word,
          style: _isTrueWord(word) ? s.verdictTrue : s.verdictFalse,
        ));
      } else if (m.namedGroup('q') != null) {
        final inner = m.namedGroup('qi')!;
        final trimmed = inner.trim();
        final TextStyle style;
        if (RegExp(r'^(Vero|Falso|VERO|FALSO|True|False)$').hasMatch(trimmed)) {
          style = _isTrueWord(trimmed) ? s.verdictTrue : s.verdictFalse;
        } else if (_latin.hasMatch(inner)) {
          style = s.term;
        } else {
          style = plain;
        }
        spans.add(TextSpan(text: m.group(0), style: style));
      } else if (m.namedGroup('p') != null) {
        spans.add(TextSpan(text: m.group(0), style: s.muted));
      } else {
        final word = m.namedGroup('v')!;
        spans.add(TextSpan(
          text: word,
          style: _isTrueWord(word) ? s.verdictTrue : s.verdictFalse,
        ));
      }
      current = m.end;
    }
    if (current < text.length) {
      spans.add(TextSpan(text: text.substring(current), style: plain));
    }
  }
}

class _Styles {
  const _Styles({
    required this.base,
    required this.bold,
    required this.term,
    required this.muted,
    required this.verdictTrue,
    required this.verdictFalse,
  });

  factory _Styles.of(BuildContext context, TextStyle base) {
    return _Styles(
      base: base,
      bold: base.copyWith(fontWeight: FontWeight.w700),
      term: base.copyWith(
        fontWeight: FontWeight.w700,
        color: AppTheme.primaryFor(context),
      ),
      muted: base.copyWith(color: AppTheme.mutedFor(context)),
      verdictTrue: base.copyWith(
        fontWeight: FontWeight.w700,
        color: AppTheme.successFor(context),
      ),
      verdictFalse: base.copyWith(
        fontWeight: FontWeight.w700,
        color: AppTheme.dangerFor(context),
      ),
    );
  }

  final TextStyle base;
  final TextStyle bold;
  final TextStyle term;
  final TextStyle muted;
  final TextStyle verdictTrue;
  final TextStyle verdictFalse;
}
