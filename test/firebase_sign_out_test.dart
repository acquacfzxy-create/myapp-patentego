// 1.0.7 D1：“仅登出”后再点“使用 Google 登录”必须能重新选择账号。
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lingua_patente/services/firebase_status.dart';

const _googleChannel = MethodChannel('plugins.flutter.io/google_sign_in');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<String> calls;
  PlatformException? signOutError;

  setUp(() {
    calls = [];
    signOutError = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_googleChannel, (call) async {
      calls.add(call.method);
      if (call.method == 'signOut' && signOutError != null) throw signOutError!;
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_googleChannel, null);
  });

  test('sign-out also clears the remembered Google account', () async {
    await FirebaseStatus.signOut();

    expect(calls, contains('signOut'));
    expect(calls, isNot(contains('disconnect')),
        reason: 'must not revoke the app grant');
  });

  test('a Google sign-out failure does not break sign-out', () async {
    signOutError = PlatformException(code: 'sign_out_failed');

    await expectLater(FirebaseStatus.signOut(), completes);
    expect(calls, contains('signOut'));
  });

  test('source: guarded for Web, never disconnects, Web path unchanged', () {
    final status = File('lib/services/firebase_status.dart').readAsStringSync();
    expect(status, contains('if (!kIsWeb)'));
    expect(status, contains('GoogleSignIn().signOut()'));
    expect(status, isNot(contains('.disconnect(')));

    final settings = File('lib/screens/settings_screen.dart').readAsStringSync();
    expect(settings, contains('await FirebaseStatus.signOut();'));

    // Web 端仍直接调用 FirebaseAuth.signOut（弹窗登录，不经过 GoogleSignIn）。
    final web = File('lib/screens/web_app_screen.dart').readAsStringSync();
    expect(web, contains('FirebaseStatus.auth?.signOut()'));
  });
}
