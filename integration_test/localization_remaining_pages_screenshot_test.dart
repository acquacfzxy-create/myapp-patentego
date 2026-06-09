import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:italy_quiz_app/config/app_strings.dart';
import 'package:italy_quiz_app/models/question.dart';
import 'package:italy_quiz_app/models/user_state.dart';
import 'package:italy_quiz_app/providers/user_state_provider.dart';
import 'package:italy_quiz_app/screens/exam_review_screen.dart';
import 'package:italy_quiz_app/screens/favorite_review_screen.dart';
import 'package:italy_quiz_app/screens/language_selection_screen.dart';
import 'package:italy_quiz_app/services/database_service.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('remaining page localization screenshots', () {
    testWidgets('captures exam review favorites and language selection',
        (tester) async {
      await DatabaseService.init();

      final outputDir = await _prepareOutputDirectory();
      final languages = ['ru', 'uk', 'ur', 'pa'];

      await _pumpLocalizedPage(
        tester,
        language: 'zh',
        page: const LanguageSelectionScreen(),
      );
      await _capture(tester, outputDir, 'language_selection_default');

      await tester.tap(find.text(UserState.languageNames['ur']!));
      await tester.pump(const Duration(milliseconds: 500));
      await _capture(tester, outputDir, 'language_selection_ur_selected');

      for (final language in languages) {
        final reviewQuestions = await _questionsFor(language, limit: 10);
        final userChoices = _userChoicesFor(reviewQuestions);

        await _pumpLocalizedPage(
          tester,
          language: language,
          page: ExamReviewScreen(
            questions: reviewQuestions,
            userChoices: userChoices,
          ),
        );
        await _capture(tester, outputDir, '${language}_exam_review');

        await _tapFirstIcon(tester, Icons.translate);
        await _capture(
            tester, outputDir, '${language}_exam_review_translation');

        await _clearFavorites();
        await _pumpLocalizedPage(
          tester,
          language: language,
          page: FavoriteReviewScreen(
            key: ValueKey('${language}_favorite_empty'),
          ),
        );
        await _capture(tester, outputDir, '${language}_favorite_empty');

        await _seedFavorites(reviewQuestions.take(4));
        await _pumpLocalizedPage(
          tester,
          language: language,
          page: FavoriteReviewScreen(
            key: ValueKey('${language}_favorite_list'),
          ),
        );
        await _capture(tester, outputDir, '${language}_favorite_list');

        await _tapFirstIcon(tester, Icons.translate);
        await _capture(tester, outputDir, '${language}_favorite_translation');
      }

      debugPrint('REMAINING_SCREENSHOTS_READY=${outputDir.path}');
      if (const bool.fromEnvironment('KEEP_SCREENSHOT_CONTAINER')) {
        await Future<void>.delayed(const Duration(seconds: 60));
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
  await provider.updateUserState(isVip: true, currentLanguage: language);
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

Future<void> _tapFirstIcon(WidgetTester tester, IconData icon) async {
  final finder = find.byIcon(icon);
  await _waitForFinder(tester, finder);
  await tester.ensureVisible(finder.first);
  await tester.tap(finder.first);
  await tester.pump(const Duration(milliseconds: 500));
}

Future<void> _waitForFinder(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 200));
    if (finder.evaluate().isNotEmpty) return;
  }

  fail('Expected ${finder.description} to appear within $timeout.');
}

final _screenshotKey = GlobalKey();

Future<Directory> _prepareOutputDirectory() async {
  final documentsDir = await getApplicationDocumentsDirectory();
  final outputDir =
      Directory('${documentsDir.path}/localization_remaining_pages');
  if (outputDir.existsSync()) {
    outputDir.deleteSync(recursive: true);
  }
  outputDir.createSync(recursive: true);
  debugPrint('REMAINING_SCREENSHOT_OUTPUT_DIR=${outputDir.path}');
  return outputDir;
}

Future<List<Question>> _questionsFor(String language,
    {required int limit}) async {
  final baseQuestions = await DatabaseService.getQuestions(
    lang: 'it',
    limit: limit,
    userId: UserStateProvider.guestUserId,
  );

  final questions = <Question>[];
  for (final question in baseQuestions) {
    final translated = await DatabaseService.getQuestionById(
      question.id,
      lang: language,
    );
    questions.add(
        translated == null ? question : question.mergeLanguages(translated));
  }
  return questions;
}

Map<int, bool?> _userChoicesFor(List<Question> questions) {
  return {
    for (var index = 0; index < questions.length; index++)
      index: index.isEven ? !questions[index].answer : questions[index].answer,
  };
}

Future<void> _clearFavorites() async {
  await DatabaseService.resetAllUserProgress(
      userId: UserStateProvider.guestUserId);
}

Future<void> _seedFavorites(Iterable<Question> questions) async {
  await _clearFavorites();
  for (final question in questions) {
    await DatabaseService.toggleFavorite(
      question.id,
      userId: UserStateProvider.guestUserId,
    );
  }
}
