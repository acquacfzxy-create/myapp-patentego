import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lingua_patente/config/app_locales.dart';
import 'package:lingua_patente/config/app_strings.dart';
import 'package:lingua_patente/models/question.dart';
import 'package:lingua_patente/widgets/session_mistake_review_sheet.dart';

SessionMistake mistake(String id, bool correct) => SessionMistake(
      question: Question(
        id: id,
        answer: correct,
        translations: {'it': 'Originale $id', 'zh': '题意 $id'},
        explanations: {
          'zh': jsonEncode({
            'detailed_description': '原因 $id',
            'study_tip': 'VIP tip must not leak into basic review',
          }),
          'it': 'Spiegazione $id',
        },
      ),
      selectedAnswer: !correct,
    );

void main() {
  testWidgets('partial records do not render raw JSON or lose the question',
      (tester) async {
    final entry = mistake('partial', true);
    entry.question.translations.remove('it');
    entry.question.explanations['zh'] =
        jsonEncode({'study_tip': 'private tip'});
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
          body: SessionMistakeReviewSheet(
        mistakes: [entry],
        language: 'zh',
      )),
    ));
    await tester.pumpAndSettle();
    expect(find.text('题意 partial'), findsOneWidget);
    expect(find.textContaining('private tip'), findsNothing);
    expect(
        find.text(
            AppStrings.getWithLanguage('zh', 'explanation_missing_short')),
        findsOneWidget);
  });

  testWidgets(
      'basic review needs no provider, preserves answers and changes reason',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
          body: Builder(
              builder: (context) => TextButton(
                    onPressed: () => showModalBottomSheet<void>(
                      context: context,
                      isScrollControlled: true,
                      builder: (_) => SessionMistakeReviewSheet(
                        language: 'zh',
                        mistakes: [mistake('one', true), mistake('two', false)],
                      ),
                    ),
                    child: const Text('open'),
                  ))),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Originale one'), findsOneWidget);
    expect(find.text('原因 one'), findsOneWidget);
    expect(find.text('你的答案: Falso'), findsOneWidget);
    expect(find.text('正确答案: Vero'), findsOneWidget);
    expect(find.textContaining('VIP tip'), findsNothing);
    await tester.tap(find.byKey(const Key('session_review_next')));
    await tester.pumpAndSettle();
    expect(find.text('Originale two'), findsOneWidget);
    expect(find.text('原因 two'), findsOneWidget);
    expect(find.text('原因 one'), findsNothing);
    expect(find.text('你的答案: Vero'), findsOneWidget);
    await tester.tap(find.byKey(const Key('session_review_previous')));
    await tester.pumpAndSettle();
    expect(find.text('Originale one'), findsOneWidget);
    await tester.tap(find.byKey(const Key('session_review_close')));
    await tester.pumpAndSettle();
    expect(find.text('open'), findsOneWidget);
    expect(find.byType(SessionMistakeReviewSheet), findsNothing);
  });

  for (final language in ['it', 'zh', 'en', 'ru', 'uk', 'ur', 'pa']) {
    testWidgets('review is scrollable at 320px with large text [$language]',
        (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MaterialApp(
        locale: AppLocales.localeFor(language),
        supportedLocales: AppLocales.supportedLocales,
        localizationsDelegates: AppLocales.delegates,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: Scaffold(
            body: SessionMistakeReviewSheet(
          language: language,
          mistakes: [mistake('one', true), mistake('two', false)],
        )),
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const Key('session_review_next')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('2/2'), findsOneWidget);
      for (final key in [
        'session_mistakes_button',
        'session_mistakes_title',
        'session_mistakes_review',
        'session_mistakes_reason',
        'session_mistakes_done'
      ]) {
        expect(AppStrings.getWithLanguage(language, key), isNot(key));
      }
    });
  }
}
