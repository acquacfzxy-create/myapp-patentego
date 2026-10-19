import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lingua_patente/config/app_locales.dart';
import 'package:lingua_patente/config/app_strings.dart';
import 'package:lingua_patente/models/question.dart';
import 'package:lingua_patente/providers/user_state_provider.dart';
import 'package:lingua_patente/services/access_policy.dart';
import 'package:lingua_patente/widgets/session_mistake_review_sheet.dart';
import 'package:lingua_patente/widgets/question_widget.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _ReviewUser extends UserStateProvider {
  bool vip = false;
  int used = 0;
  int charges = 0;
  final unlocked = <String>{};

  @override
  bool get isVip => vip;
  @override
  int get remainingExplanations => AccessPolicy.remainingExplanations(
      isVip: vip, dailyExplanationCount: used);
  @override
  Future<bool> checkAndResetDailyCounters({SharedPreferences? prefs}) async =>
      false;
  @override
  bool canViewExplanation(String id) => AccessPolicy.canViewExplanation(
      isVip: vip,
      isUnlockedToday: unlocked.contains(id),
      dailyExplanationCount: used);
  @override
  bool isExplanationUnlockedToday(String id) => unlocked.contains(id);
  @override
  Future<int> incrementExplanationCount(String id) async {
    charges++;
    used++;
    unlocked.add(id);
    return used;
  }
}

SessionMistake _entry(String id, {bool plain = false}) => SessionMistake(
      question: Question(
        id: id,
        answer: true,
        translations: {'it': 'Originale $id', 'zh': '题意 $id'},
        explanations: {
          'zh': plain
              ? '基本原因 $id'
              : jsonEncode({
                  'detailed_description': '基本原因 $id',
                  'key_points': [
                    {'title': 'non', 'content': '考点 $id'}
                  ],
                  'study_tip': '**non (不)** 教练提示 $id',
                })
        },
      ),
      selectedAnswer: false,
    );

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            (_) => Completer<Object?>().future);
  });

  test('legacy exhausted explanation usage never blocks or receives new writes',
      () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('daily_explanation_count', 10);
    final user = UserStateProvider();
    expect(user.canViewExplanation('new-question'), isTrue);
    await user.incrementExplanationCount('new-question');
    await user.incrementExplanationCount('another-question');
    expect(prefs.getInt('daily_explanation_count'), 10);
    expect(prefs.getStringList('today_unlocked_explanations'), isNull);
    user.dispose();
  });

  Future<void> pump(WidgetTester tester, _ReviewUser user,
      {String language = 'zh', bool plain = false, bool small = false}) async {
    if (small) {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
    }
    await tester.pumpWidget(ChangeNotifierProvider<UserStateProvider>.value(
      value: user,
      child: MaterialApp(
        locale: AppLocales.localeFor(language),
        supportedLocales: AppLocales.supportedLocales,
        localizationsDelegates: AppLocales.delegates,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(small ? 2 : 1)),
          child: child!,
        ),
        home: Scaffold(
            body: SessionMistakeReviewSheet(
          mistakes: [_entry('one', plain: plain), _entry('two')],
          language: language,
        )),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 300));
    addTearDown(user.dispose);
  }

  Future<void> toggle(WidgetTester tester) async {
    final button = find.byKey(const Key('session_review_more'));
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    await tester.tap(button);
    // Allow scrolling to settle before hitting the expansion control.
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets(
      'supplements expand freely without duplicate reason or quota writes',
      (tester) async {
    final user = _ReviewUser()..used = 9;
    await pump(tester, user);
    expect(user.charges, 0);
    expect(find.text('基本原因 one'), findsOneWidget);
    expect(find.textContaining('考点 one'), findsNothing);
    await toggle(tester);
    expect(user.charges, 0);
    expect(user.remainingExplanations, 1);
    expect(find.text('基本原因 one'), findsOneWidget);
    expect(find.textContaining('考点 one', findRichText: true), findsOneWidget);
    expect(find.text('✨ VIP'), findsNothing);
    await toggle(tester);
    expect(find.textContaining('考点 one', findRichText: true), findsNothing);
    await toggle(tester);
    expect(user.charges, 0);
    expect(find.textContaining('考点 one', findRichText: true), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('legacy exhausted quota still allows full details',
      (tester) async {
    final user = _ReviewUser()..used = 10;
    await pump(tester, user);
    await toggle(tester);
    expect(find.text('基本原因 one'), findsOneWidget);
    expect(find.textContaining('考点 one', findRichText: true), findsOneWidget);
    expect(
        find.text(
            AppStrings.getWithLanguage('zh', 'remaining_free_explanations')),
        findsNothing);
    expect(user.charges, 0);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('already unlocked at zero quota remains readable',
      (tester) async {
    final user = _ReviewUser()..used = 10;
    user.unlocked.add('one');
    await pump(tester, user);
    await toggle(tester);
    expect(find.textContaining('考点 one', findRichText: true), findsOneWidget);
    expect(user.charges, 0);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('VIP details show no upgrade badge and use no free quota',
      (tester) async {
    final user = _ReviewUser()
      ..vip = true
      ..used = 10;
    await pump(tester, user);
    await toggle(tester);
    expect(find.textContaining('考点 one', findRichText: true), findsOneWidget);
    expect(find.text('✨ VIP'), findsNothing);
    expect(user.charges, 0);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('full explanation ignores legacy quota and VIP badge arguments',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Builder(
      builder: (context) => TextButton(
        onPressed: () => QuestionWidget.showRichExplanation(
          context,
          question: _entry('one').question,
          currentLanguage: 'zh',
          remainingExplanations: 0,
          showVipBadgeOnStudyTip: true,
        ),
        child: const Text('open'),
      ),
    ))));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.textContaining('考点 one', findRichText: true), findsOneWidget);
    expect(find.text('✨ VIP'), findsNothing);
    expect(find.textContaining('今日剩余免费解析次数'), findsNothing);
    expect(find.textContaining('额度已用完'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('plain explanations have no redundant expand button',
      (tester) async {
    final user = _ReviewUser();
    await pump(tester, user, plain: true);
    expect(find.byKey(const Key('session_review_more')), findsNothing);
    expect(user.charges, 0);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final language in ['it', 'zh', 'en', 'ru', 'uk', 'ur', 'pa']) {
    testWidgets('expanded details fit narrow large-text screens [$language]',
        (tester) async {
      final user = _ReviewUser()..vip = true;
      await pump(tester, user, language: language, small: true);
      // This fixture has Chinese supplements only; provide them as fallback
      // Italian as well so every UI language exercises the expanded layout.
      final sheet = tester.widget<SessionMistakeReviewSheet>(
          find.byType(SessionMistakeReviewSheet));
      for (final entry in sheet.mistakes) {
        entry.question.explanations['it'] = entry.question.explanations['zh']!;
      }
      await tester.pumpWidget(const SizedBox.shrink());
      // Re-pump with the fallback available on the actual question snapshots.
      await tester.pumpWidget(ChangeNotifierProvider<UserStateProvider>.value(
        value: user,
        child: MaterialApp(
          locale: AppLocales.localeFor(language),
          supportedLocales: AppLocales.supportedLocales,
          localizationsDelegates: AppLocales.delegates,
          builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(2)),
              child: child!),
          home: Scaffold(
              body: SessionMistakeReviewSheet(
                  mistakes: sheet.mistakes, language: language)),
        ),
      ));
      await tester.pump();
      await toggle(tester);
      expect(tester.takeException(), isNull);
      await tester.drag(
          find.byType(SingleChildScrollView), const Offset(0, -800));
      await tester.pump();
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const Key('session_review_next')));
      await tester.pump();
      expect(find.text('2/2'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
