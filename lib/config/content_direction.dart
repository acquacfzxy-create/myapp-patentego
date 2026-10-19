import 'package:flutter/widgets.dart';

/// 根据内容实际使用的文字决定排版方向。
///
/// 题库译文不一定与界面语言同一文字体系：例如旁遮普语（pa）界面为 Gurmukhi（从左到右），
/// 但部分题干译文是 Shahmukhi（阿拉伯字母，从右到左）。这类内容应按自身文字排版，
/// 而不是跟随界面方向。字母数量相同或无法判断时返回 [fallback]。
TextDirection contentTextDirection(
  String text, {
  TextDirection fallback = TextDirection.ltr,
}) {
  var rtl = 0;
  var ltr = 0;
  for (final rune in text.runes) {
    if (_isRtlLetter(rune)) {
      rtl++;
    } else if (_isLtrLetter(rune)) {
      ltr++;
    }
  }
  if (rtl == ltr) return fallback;
  return rtl > ltr ? TextDirection.rtl : TextDirection.ltr;
}

bool _isRtlLetter(int rune) =>
    (rune >= 0x0590 && rune <= 0x08FF) || // Hebrew, Arabic, Syriac, Thaana…
    (rune >= 0xFB1D && rune <= 0xFDFF) || // Presentation forms A
    (rune >= 0xFE70 && rune <= 0xFEFF); // Presentation forms B

bool _isLtrLetter(int rune) {
  if (rune < 0x80) {
    return (rune >= 0x41 && rune <= 0x5A) || (rune >= 0x61 && rune <= 0x7A);
  }
  if (_isRtlLetter(rune)) return false;
  return (rune >= 0x00C0 && rune <= 0x024F) || // Latin extended
      (rune >= 0x0370 && rune <= 0x052F) || // Greek, Cyrillic
      (rune >= 0x0900 && rune <= 0x0DFF) || // Indic scripts incl. Gurmukhi
      (rune >= 0x3040 && rune <= 0x9FFF); // Kana, CJK
}
