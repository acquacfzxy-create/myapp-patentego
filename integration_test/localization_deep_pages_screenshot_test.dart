import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:italy_quiz_app/config/app_strings.dart';
import 'package:italy_quiz_app/providers/user_state_provider.dart';
import 'package:italy_quiz_app/screens/mastery_report_screen.dart';
import 'package:italy_quiz_app/screens/mistake_review_screen.dart';
import 'package:italy_quiz_app/screens/settings_screen.dart';
import 'package:italy_quiz_app/screens/subscription_page.dart';
import 'package:italy_quiz_app/services/database_service.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('deep page localization screenshots', () {
    testWidgets('captures ru uk ur pa deep pages', (tester) async {
      await DatabaseService.init();
      await _seedLearningData();

      final outputDir = await _prepareOutputDirectory();
      final languages = ['ru', 'uk', 'ur', 'pa'];
      final pages = <String, Widget>{
        'subscription': const SubscriptionPage(),
        'settings': const SettingsScreen(),
        'mistakes': const MistakeReviewScreen(initialTabIndex: 1),
        'mastery': const MasteryReportScreen(),
      };

      for (final language in languages) {
        for (final entry in pages.entries) {
          await _pumpLocalizedPage(
            tester,
            language: language,
            page: entry.value,
          );
          await _capture(
            tester,
            outputDir,
            '${language}_${entry.key}',
          );
        }
      }

      debugPrint('SCREENSHOTS_READY=${outputDir.path}');
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
  await tester.pump(const Duration(milliseconds: 500));
  await provider.changeLanguage(language);
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
  final outputDir = Directory('${documentsDir.path}/localization_deep_pages');
  if (outputDir.existsSync()) {
    outputDir.deleteSync(recursive: true);
  }
  outputDir.createSync(recursive: true);
  debugPrint('SCREENSHOT_OUTPUT_DIR=${outputDir.path}');
  return outputDir;
}

Future<void> _seedLearningData() async {
  const userId = UserStateProvider.guestUserId;
  await DatabaseService.resetAllUserProgress(userId: userId);

  final questions = await DatabaseService.getQuestions(
    lang: 'zh',
    limit: 20,
    userId: userId,
  );

  for (final question in questions.take(12)) {
    await DatabaseService.updateQuestionProgress(
      question.id,
      false,
      userId: userId,
    );
  }

  for (final result in [
    (correct: 20, wrong: 10, total: 30),
    (correct: 22, wrong: 8, total: 30),
    (correct: 24, wrong: 6, total: 30),
    (correct: 25, wrong: 5, total: 30),
    (correct: 27, wrong: 3, total: 30),
  ]) {
    await DatabaseService.saveMockTestResult(
      userId: userId,
      correctCount: result.correct,
      wrongCount: result.wrong,
      totalQuestions: result.total,
      timeUsedSeconds: 900,
    );
  }
}
