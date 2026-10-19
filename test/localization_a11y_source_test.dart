import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 只有图标的按钮必须提供 tooltip（读屏文字，随界面语言本地化）。
void main() {
  test('every IconButton has a tooltip', () {
    final missing = <String>[];
    for (final file in Directory('lib').listSync(recursive: true)) {
      if (file is! File || !file.path.endsWith('.dart')) continue;
      final source = file.readAsStringSync();
      for (final match
          in RegExp(r'IconButton(\.(filled|outlined|filledTonal))?\(')
              .allMatches(source)) {
        var depth = 1;
        var i = match.end;
        while (depth > 0 && i < source.length) {
          final ch = source[i];
          if (ch == '(') depth++;
          if (ch == ')') depth--;
          i++;
        }
        if (!source.substring(match.start, i).contains('tooltip')) {
          final line =
              '\n'.allMatches(source.substring(0, match.start)).length + 1;
          missing.add('${file.path}:$line');
        }
      }
    }
    expect(missing, isEmpty);
  });
}
