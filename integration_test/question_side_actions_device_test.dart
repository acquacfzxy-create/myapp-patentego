import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lingua_patente/config/app_locales.dart';
import 'package:lingua_patente/config/app_strings.dart';
import 'package:lingua_patente/config/app_theme.dart';
import 'package:lingua_patente/models/question.dart';
import 'package:lingua_patente/providers/user_state_provider.dart';
import 'package:lingua_patente/services/database_service.dart';
import 'package:lingua_patente/widgets/glass_card.dart';
import 'package:lingua_patente/widgets/question_widget.dart';
import 'package:lingua_patente/widgets/translation_panel.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/l10n_sample_question.dart';
import 'support/l10n_sample_image_question.dart';

/// Run in a separately installed UI test build so learner progress is isolated.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('device side actions, translation, explanation and answers',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'current_language': 'zh',
      'question_speech_system_voice_choice_v1': true,
    });
    await DatabaseService.init();
    final provider = UserStateProvider();
    await provider.changeLanguage('zh');
    AppStrings.setLanguage('zh');
    final boundaryKey = GlobalKey();
    bool? answer;

    Question fixture(String json) {
      final q = jsonDecode(json) as Map<String, dynamic>;
      return Question(
        id: q['id'] as String,
        imageName: q['image_name'] as String?,
        answer: q['answer'] as bool,
        translations: Map<String, String>.from(q['translations'] as Map),
        explanations: Map<String, String>.from(q['explanations'] as Map),
        keywordsJson: q['keywords_json'] as String?,
      );
    }

    Future<void> show(Question question, {double scale = 1}) async {
      await tester.pumpWidget(ChangeNotifierProvider.value(
        value: provider,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          locale: AppLocales.localeFor('zh'),
          supportedLocales: AppLocales.supportedLocales,
          localizationsDelegates: AppLocales.delegates,
          theme: AppTheme.retroTheme(language: 'zh'),
          builder: (context, child) => RepaintBoundary(
            key: boundaryKey,
            child: MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
          ),
          home: Scaffold(
            appBar: AppBar(title: const Text('UI TEST · 1/30')),
            body: SafeArea(
              child: QuestionWidget(
                key: ValueKey('${question.id}-$scale'),
                question: question,
                currentLanguage: 'zh',
                onAnswerSelected: (value) => answer = value,
              ),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
    }

    Future<void> scrollToEnd() async {
      final scroll = tester.state<ScrollableState>(find
          .descendant(
            of: find.byType(SingleChildScrollView).first,
            matching: find.byType(Scrollable),
          )
          .first);
      scroll.position.jumpTo(scroll.position.maxScrollExtent);
      await tester.pumpAndSettle();
    }

    Future<void> capture(String name) async {
      await tester.pump();
      final boundary = boundaryKey.currentContext!.findRenderObject()
          as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 2);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final dir = Directory(
          '${(await getApplicationDocumentsDirectory()).path}/side_actions_evidence');
      await dir.create(recursive: true);
      await File('${dir.path}/$name.png')
          .writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
      debugPrint('SIDE_ACTIONS_CAPTURE=$name');
      // Give the host time to capture Android's compositor, including system bars.
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 1500)));
    }

    void checkLayout() {
      final rects = <Rect>[];
      for (final icon in [
        Icons.favorite_border,
        Icons.volume_up_outlined,
        Icons.menu_book_outlined,
        Icons.translate,
      ]) {
        // TranslationPanel also contains a decorative translation icon.
        final button = find.byIcon(icon).last;
        expect(button.hitTestable(), findsOneWidget);
        rects.add(tester.getRect(
            find.ancestor(of: button, matching: find.byType(GlassCard)).first));
      }
      final content = tester.getRect(find.byType(SingleChildScrollView).first);
      final answer = tester.getRect(find.text('VERO'));
      for (var i = 0; i < rects.length; i++) {
        expect(rects[i].left, rects.first.left);
        expect(rects[i].overlaps(content), isFalse);
        expect(rects[i].bottom, lessThan(answer.top));
        if (i > 0) expect(rects[i].top, greaterThan(rects[i - 1].bottom));
      }
      expect(tester.takeException(), isNull);
    }

    final question = fixture(kL10nSampleQuestionJson);
    await show(question);
    checkLayout();
    await capture('01_side_actions');
    await tester.tap(find.byIcon(Icons.translate));
    await tester.pumpAndSettle();
    expect(find.byType(TranslationPanel), findsOneWidget);
    checkLayout();
    await scrollToEnd();
    checkLayout();
    await capture('02_translation');
    await tester.tap(find.byIcon(Icons.translate).last);
    await tester.pumpAndSettle();
    expect(find.byType(TranslationPanel), findsNothing);

    await tester.tap(find.byIcon(Icons.favorite_border));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.favorite), findsOneWidget);
    await tester.tap(find.byIcon(Icons.favorite));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.favorite_border), findsOneWidget);

    await tester.tap(find.byIcon(Icons.menu_book_outlined));
    await tester.pumpAndSettle();
    expect(
        find.text(
            AppStrings.getWithLanguage('zh', 'modal_correct_answer_label')),
        findsOneWidget);
    await capture('03_explanation');
    Navigator.of(tester.element(find.byType(QuestionWidget))).pop();
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.volume_up_outlined));
    await tester.pump(const Duration(seconds: 2));
    await capture('04_speech');
    debugPrint('SIDE_ACTIONS_SPEECH_STOP_VISIBLE='
        '${find.byIcon(Icons.stop_circle_outlined).evaluate().isNotEmpty}');
    if (find.byIcon(Icons.stop_circle_outlined).evaluate().isNotEmpty) {
      await tester.tap(find.byIcon(Icons.stop_circle_outlined));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.text('VERO'));
    await tester.pump();
    expect(answer, isTrue);
    await tester.tap(find.text('FALSO'));
    await tester.pump();
    expect(answer, isFalse);

    await show(fixture(kL10nSampleImageQuestionJson));
    checkLayout();
    expect(find.byType(Image), findsWidgets);
    await scrollToEnd();
    checkLayout();
    await capture('05_image_question');
    await show(question, scale: 1.5);
    checkLayout();
    await tester.tap(find.byIcon(Icons.translate));
    await tester.pumpAndSettle();
    checkLayout();
    await scrollToEnd();
    checkLayout();
    await capture('06_large_text');
    debugPrint('SIDE_ACTIONS_DEVICE_PASS');
  });
}
