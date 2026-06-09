import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:italy_quiz_app/config/app_strings.dart';
import 'package:italy_quiz_app/providers/user_state_provider.dart';
import 'package:italy_quiz_app/screens/auth_page.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('auth flow localization screenshots', () {
    testWidgets('captures ru uk ur pa auth and account dialogs',
        (tester) async {
      final outputDir = await _prepareOutputDirectory();
      final languages = ['ru', 'uk', 'ur', 'pa'];

      for (final language in languages) {
        await _pumpLocalizedPage(
          tester,
          language: language,
          page: const AuthPage(),
        );
        await _capture(tester, outputDir, '${language}_auth_page');

        await tester.tap(
          find.text(AppStrings.getWithLanguage(language, 'auth_google')),
        );
        await tester.pump(const Duration(milliseconds: 500));
        await _capture(tester, outputDir, '${language}_auth_google_error');
        await tester.pump(const Duration(seconds: 5));

        await _pumpLocalizedPage(
          tester,
          language: language,
          page: _DialogPreviewPage(
            language: language,
            titleKey: 'merge_progress_title',
            messageKey: 'merge_progress_message',
            secondaryActionKey: 'merge_progress_later',
            primaryActionKey: 'merge_progress_confirm',
          ),
        );
        await _capture(tester, outputDir, '${language}_merge_dialog');

        await _pumpLocalizedPage(
          tester,
          language: language,
          page: _DialogPreviewPage(
            language: language,
            titleKey: 'delete_cloud_data_on_signout_title',
            messageKey: 'delete_cloud_data_on_signout_message',
            secondaryActionKey: 'sign_out_only',
            primaryActionKey: 'sign_out_and_delete_data',
            destructivePrimary: true,
          ),
        );
        await _capture(tester, outputDir, '${language}_signout_dialog');
      }

      debugPrint('AUTH_SCREENSHOTS_READY=${outputDir.path}');
      if (const bool.fromEnvironment('KEEP_SCREENSHOT_CONTAINER')) {
        await Future<void>.delayed(const Duration(seconds: 30));
      }
    });
  });
}

Future<void> _pumpLocalizedPage(
  WidgetTester tester, {
  required String language,
  required Widget page,
}) async {
  final provider = UserStateProvider();
  await tester.pump(const Duration(milliseconds: 300));
  await provider.changeLanguage(language);
  await provider.updateUserState(currentLanguage: language);
  AppStrings.setLanguage(language);

  final textDirection =
      language == 'ur' ? TextDirection.rtl : TextDirection.ltr;

  await tester.pumpWidget(
    RepaintBoundary(
      key: _screenshotKey,
      child: ChangeNotifierProvider<UserStateProvider>.value(
        value: provider,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          builder: (context, child) {
            return Directionality(
              textDirection: textDirection,
              child: child ?? const SizedBox.shrink(),
            );
          },
          home: page,
        ),
      ),
    ),
  );

  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump(const Duration(seconds: 1));
}

Future<void> _capture(
  WidgetTester tester,
  Directory outputDir,
  String name,
) async {
  await tester.pump(const Duration(milliseconds: 300));
  final boundary = _screenshotKey.currentContext!.findRenderObject()
      as RenderRepaintBoundary;
  final image = await boundary.toImage(pixelRatio: 2);
  final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
  final bytes = byteData!.buffer.asUint8List();
  await File('${outputDir.path}/$name.png').writeAsBytes(bytes, flush: true);
}

final _screenshotKey = GlobalKey();

Future<Directory> _prepareOutputDirectory() async {
  final documentsDir = await getApplicationDocumentsDirectory();
  final outputDir = Directory('${documentsDir.path}/localization_auth_flow');
  if (outputDir.existsSync()) {
    outputDir.deleteSync(recursive: true);
  }
  outputDir.createSync(recursive: true);
  debugPrint('AUTH_SCREENSHOT_OUTPUT_DIR=${outputDir.path}');
  return outputDir;
}

class _DialogPreviewPage extends StatelessWidget {
  const _DialogPreviewPage({
    required this.language,
    required this.titleKey,
    required this.messageKey,
    required this.secondaryActionKey,
    required this.primaryActionKey,
    this.destructivePrimary = false,
  });

  final String language;
  final String titleKey;
  final String messageKey;
  final String secondaryActionKey;
  final String primaryActionKey;
  final bool destructivePrimary;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFEAF7FC),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: AlertDialog(
            title: Text(AppStrings.getWithLanguage(language, titleKey)),
            content: Text(AppStrings.getWithLanguage(language, messageKey)),
            actions: [
              TextButton(
                onPressed: () {},
                child: Text(
                  AppStrings.getWithLanguage(language, secondaryActionKey),
                ),
              ),
              TextButton(
                onPressed: () {},
                style: destructivePrimary
                    ? TextButton.styleFrom(foregroundColor: Colors.red)
                    : null,
                child: Text(
                  AppStrings.getWithLanguage(language, primaryActionKey),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
