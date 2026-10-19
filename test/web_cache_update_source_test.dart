import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Web bootstrap URL carries a release token', () {
    final index = File('web/index.html').readAsStringSync();
    expect(
      index,
      contains(RegExp(r'flutter_bootstrap\.js\?v=[^"\s]+')),
      reason: 'An unversioned bootstrap can be trapped by an older Flutter '
          'service worker on mobile browsers.',
    );
  });

  test('HTML and Flutter update files always revalidate', () {
    final config = jsonDecode(File('firebase.json').readAsStringSync())
        as Map<String, dynamic>;
    final hosting = config['hosting'] as Map<String, dynamic>;
    final headers = hosting['headers'] as List<dynamic>;

    for (final source in <String>[
      '/',
      '/index.html',
      '/flutter_bootstrap.js',
      '/flutter_service_worker.js',
    ]) {
      final rule = headers.cast<Map<String, dynamic>>().singleWhere(
            (item) => item['source'] == source,
          );
      final values = (rule['headers'] as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .where((item) => item['key'] == 'Cache-Control')
          .map((item) => item['value']);
      expect(values, contains('no-cache,max-age=0,must-revalidate'));
    }
  });
}
