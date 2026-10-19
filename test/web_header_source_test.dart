import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Web header uses the current App logo as a home button', () {
    final source = File('lib/screens/web_app_screen.dart').readAsStringSync();

    expect(source, contains("'assets/images/app_icon.png'"));
    expect(source, contains("ValueKey('web-home-logo-button')"));
    expect(
      source,
      contains(RegExp(r"key: const ValueKey\('web-home-logo-button'\),\s+"
          r'onTap: _leaveToHome,')),
    );
  });
}
