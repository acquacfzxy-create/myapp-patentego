import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lingua_patente/config/app_locales.dart';
import 'package:lingua_patente/config/app_strings.dart';
import 'package:lingua_patente/config/app_theme.dart';
import 'package:lingua_patente/models/question.dart';
import 'package:lingua_patente/models/user_state.dart';
import 'package:lingua_patente/providers/user_state_provider.dart';
import 'package:lingua_patente/widgets/glass_card.dart';
import 'package:lingua_patente/widgets/question_widget.dart';
import 'package:lingua_patente/widgets/translation_panel.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 题目页的操作按钮（收藏、朗读、解析、翻译）与内容必须拥有互不重叠的布局空间。
///
/// 六种界面语言 × 320dp / 411dp × 字号 1.0 / 1.5，真实 Noto 字体，
/// 两道真实题目：长题干 + 长译文（5769，pa 译文为 Shahmukhi）与带图题目（2665）。
/// 在滚动的开头、中间、末尾逐一检查：内容文字与图片不被按钮覆盖，
/// 按钮彼此不重叠、不压住底部 VERO/FALSO，均可点按，最后一段能完整看到。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const sizes = [Size(320, 640), Size(411, 860)];
  const scales = [1.0, 1.5];
  const actionIcons = [
    Icons.favorite_border,
    Icons.volume_up_outlined,
    Icons.menu_book_outlined,
    Icons.translate,
  ];
  late Question longQuestion;
  late Question imageQuestion;

  setUpAll(() async {
    await _loadAppFonts();
    // 收藏状态会访问用户进度库；测试中让 path_provider 调用保持挂起，
    // 既不返回也不报错（图片解码需要让出真实异步，否则会触发插件缺失异常）。
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (_) => Completer<Object?>().future,
    );
    longQuestion = _fixture('test/fixtures/l10n_sample_question.json');
    imageQuestion = _fixture('test/fixtures/l10n_sample_image_question.json');
  });

  Future<void> pumpQuestion(
    WidgetTester tester, {
    required String language,
    required Size size,
    required double scale,
    required Question question,
    TargetPlatform platform = TargetPlatform.android,
    bool isExamMode = false,
    bool isAnswered = false,
    bool showBadges = false,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({'current_language': language});
    final user = UserStateProvider();
    await user.changeLanguage(language);
    AppStrings.setLanguage(language);

    await tester.pumpWidget(
      ChangeNotifierProvider<UserStateProvider>.value(
        value: user,
        child: MaterialApp(
          locale: AppLocales.localeFor(language),
          supportedLocales: AppLocales.supportedLocales,
          localizationsDelegates: AppLocales.delegates,
          theme: AppTheme.lightTheme(language: language)
              .copyWith(platform: platform),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: Scaffold(
            body: QuestionWidget(
              question: question,
              currentLanguage: language,
              onAnswerSelected: (_) {},
              currentIndex: 1,
              totalQuestions: 30,
              isExamMode: isExamMode,
              isAnswered: isAnswered,
              isCorrect: isAnswered ? false : null,
              userChoice: isAnswered ? !question.answer : null,
              hasPreviousQuestion: isAnswered,
              hasNextQuestion: isAnswered,
              onPreviousQuestion: isAnswered ? () {} : null,
              onNextQuestion: isAnswered ? () {} : null,
              showFavoriteBadge: showBadges,
              showMasteredBadge: showBadges,
            ),
          ),
        ),
      ),
    );
    // 图片解码在真实异步中完成。
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump(const Duration(milliseconds: 500));
  }

  /// 每个操作按钮的圆形卡片区域（只算滚动内容之外的图标：
  /// 译文面板标题里也有翻译图标，那是内容的一部分）。
  List<Rect> actionRects(WidgetTester tester) {
    final scrollView = find.byType(SingleChildScrollView).first;
    final inContent = find
        .descendant(of: scrollView, matching: find.byType(Icon))
        .evaluate()
        .toSet();
    return [
      for (final icon in actionIcons)
        for (final element in find.byIcon(icon).evaluate())
          if (!inContent.contains(element))
            tester.getRect(find
                .ancestor(
                  of: find.byElementPredicate((e) => e == element),
                  matching: find.byType(GlassCard),
                )
                .first),
    ];
  }

  /// 可滚动内容中当前可见的文字段落与图片区域（已裁到视口内）。
  List<(String, Rect)> visibleContent(WidgetTester tester) {
    final scrollView = find.byType(SingleChildScrollView).first;
    final viewport = tester.getRect(scrollView);
    final result = <(String, Rect)>[];
    void add(String label, Rect rect) {
      final visible = rect.intersect(viewport);
      if (visible.width > 1 && visible.height > 1) result.add((label, visible));
    }

    for (final element in find
        .descendant(of: scrollView, matching: find.byType(RichText))
        .evaluate()) {
      final paragraph = element.renderObject as RenderParagraph;
      final text = paragraph.text.toPlainText();
      final box = paragraph.localToGlobal(Offset.zero) & paragraph.size;
      add('"${text.length > 24 ? text.substring(0, 24) : text}"', box);
    }
    for (final element in find
        .descendant(of: scrollView, matching: find.byType(Image))
        .evaluate()) {
      final box = element.renderObject as RenderBox;
      add('image', box.localToGlobal(Offset.zero) & box.size);
    }
    return result;
  }

  void expectNoOverlap(WidgetTester tester, String where) {
    final actions = actionRects(tester);
    expect(actions.length, greaterThanOrEqualTo(3), reason: where);
    final problems = <String>[];
    for (final (label, rect) in visibleContent(tester)) {
      for (final action in actions) {
        if (rect.overlaps(action)) problems.add('$label $rect under $action');
      }
    }
    for (var i = 0; i < actions.length; i++) {
      for (var j = i + 1; j < actions.length; j++) {
        if (actions[i].overlaps(actions[j])) {
          problems.add('buttons $i/$j overlap');
        }
      }
    }
    for (final answer in ['VERO', 'FALSO']) {
      final rect = tester.getRect(find.text(answer));
      for (final action in actions) {
        if (rect.overlaps(action)) problems.add('$answer under $action');
      }
    }
    expect(problems, isEmpty, reason: where);
    expect(tester.takeException(), isNull, reason: where);
  }

  Future<void> scrollTo(WidgetTester tester, double fraction) async {
    final state = tester.state<ScrollableState>(find
        .descendant(
          of: find.byType(SingleChildScrollView).first,
          matching: find.byType(Scrollable),
        )
        .first);
    final position = state.position;
    position.jumpTo(position.maxScrollExtent * fraction);
    await tester.pump();
  }

  for (final language in UserState.supportedLanguages) {
    for (final size in sizes) {
      for (final scale in scales) {
        final label = '[$language, ${size.width.toInt()}dp, x$scale]';

        testWidgets('long stem and translation keep clear of actions $label',
            (tester) async {
          await pumpQuestion(tester,
              language: language,
              size: size,
              scale: scale,
              question: longQuestion);

          final stem =
              tester.widget<Text>(find.text(longQuestion.translations['it']!));
          expect(stem.textDirection, TextDirection.ltr);
          expectNoOverlap(tester, 'stem before translation');

          // 四个操作按钮的中心都能点到按钮本身（没有被其他元素盖住）。
          for (final icon in actionIcons) {
            expect(find.byIcon(icon).hitTestable(), findsWidgets,
                reason: 'action $icon is not tappable');
          }

          await tester.tap(find.byIcon(Icons.translate));
          await tester.pump(const Duration(milliseconds: 400));
          final translation = tester.widget<Text>(find.descendant(
            of: find.byType(TranslationPanel),
            matching: find.text(longQuestion.translations[language]!),
          ));
          expect(
            translation.textDirection,
            language == 'ur' || language == 'pa'
                ? TextDirection.rtl
                : TextDirection.ltr,
          );

          for (final fraction in [0.0, 0.5, 1.0]) {
            await scrollTo(tester, fraction);
            expectNoOverlap(tester, 'scroll $fraction');
          }

          // 滚到底时最后一段内容完整位于视口内。
          final viewport =
              tester.getRect(find.byType(SingleChildScrollView).first);
          final last = visibleContent(tester)
              .map((e) => e.$2)
              .reduce((a, b) => a.bottom > b.bottom ? a : b);
          final lastParagraphs = find
              .descendant(
                of: find.byType(SingleChildScrollView).first,
                matching: find.byType(RichText),
              )
              .evaluate()
              .map((e) {
            final p = e.renderObject as RenderParagraph;
            return p.localToGlobal(Offset.zero) & p.size;
          }).reduce((a, b) => a.bottom > b.bottom ? a : b);
          expect(
              lastParagraphs.bottom, lessThanOrEqualTo(viewport.bottom + 0.5),
              reason: 'last paragraph $lastParagraphs cut off by $viewport');
          expect(last.bottom, lessThanOrEqualTo(viewport.bottom + 0.5));
        });

        testWidgets('image question keeps clear of actions $label',
            (tester) async {
          await pumpQuestion(tester,
              language: language,
              size: size,
              scale: scale,
              question: imageQuestion);
          expect(find.byType(Image), findsWidgets);
          for (final fraction in [0.0, 0.5, 1.0]) {
            await scrollTo(tester, fraction);
            expectNoOverlap(tester, 'image scroll $fraction');
          }
          await tester.tap(find.byIcon(Icons.translate));
          await tester.pump(const Duration(milliseconds: 400));
          for (final fraction in [0.0, 1.0]) {
            await scrollTo(tester, fraction);
            expectNoOverlap(tester, 'image+translation scroll $fraction');
          }
        });
      }
    }
  }

  /// 反馈气泡（答对/答错、收藏、掌握）所在区域。
  Rect? bubbleRect(WidgetTester tester) {
    final keyed = find.byKey(const ValueKey('question-feedback-bubbles'));
    final finder = keyed.evaluate().isNotEmpty
        ? keyed
        : find
            .descendant(
              of: find
                  .byWidgetPredicate((w) => w is Positioned && w.bottom == 120),
              matching: find.byType(Column),
            )
            .first;
    if (finder.evaluate().isEmpty) return null;
    return tester.getRect(finder);
  }

  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    testWidgets('phone actions stay on the side on $platform', (tester) async {
      await pumpQuestion(tester,
          language: 'zh',
          size: const Size(360, 780),
          scale: 1.5,
          platform: platform,
          question: longQuestion);
      final actions = actionRects(tester);
      expect(actions.length, 4);
      for (var i = 0; i < actions.length; i++) {
        expect(actions[i].left, actions.first.left);
        expect(actions[i].center.dx, greaterThan(180));
        if (i > 0) expect(actions[i].top, greaterThan(actions[i - 1].bottom));
      }
      expectNoOverlap(tester, '$platform side actions');
      await tester.tap(find.byIcon(Icons.translate));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(TranslationPanel), findsOneWidget);
      expectNoOverlap(tester, '$platform translated');
    });
  }

  group('第五轮复核', () {
    for (final language in UserState.supportedLanguages) {
      for (final size in sizes) {
        testWidgets(
            'answered state: feedback bubbles and actions do not overlap '
            '[$language, ${size.width.toInt()}dp]', (tester) async {
          await pumpQuestion(tester,
              language: language,
              size: size,
              scale: 1.0,
              question: longQuestion,
              isAnswered: true,
              showBadges: true);
          final bubbles = bubbleRect(tester);
          expect(bubbles, isNotNull);
          for (final action in actionRects(tester)) {
            expect(bubbles!.overlaps(action), isFalse,
                reason: 'feedback bubbles $bubbles cover action $action');
          }
          expectNoOverlap(tester, 'answered');
          await scrollTo(tester, 1.0);
          expectNoOverlap(tester, 'answered, scrolled to end');
        });

        testWidgets(
            'exam mode shows only favourite and keeps clear '
            '[$language, ${size.width.toInt()}dp]', (tester) async {
          await pumpQuestion(tester,
              language: language,
              size: size,
              scale: 1.5,
              question: longQuestion,
              isExamMode: true);
          expect(find.byIcon(Icons.translate), findsNothing);
          expect(
              find.byIcon(Icons.favorite_border).hitTestable(), findsOneWidget);
          final favorite = actionRects(tester).single;
          for (final (label, rect) in visibleContent(tester)) {
            expect(rect.overlaps(favorite), isFalse, reason: label);
          }
          await scrollTo(tester, 1.0);
          for (final (label, rect) in visibleContent(tester)) {
            expect(rect.overlaps(favorite), isFalse, reason: 'end $label');
          }
        });
      }
    }

    // 手机各宽度均维持侧边竖排，并且不遮挡内容。
    for (final language in ['en', 'ur']) {
      for (final width in [320.0, 379.0, 380.0, 411.0]) {
        testWidgets('boundary ${width.toInt()}dp [$language]', (tester) async {
          await pumpQuestion(tester,
              language: language,
              size: Size(width, 800),
              scale: 1.0,
              question: longQuestion);
          final actions = actionRects(tester);
          final sameColumn =
              actions.every((r) => (r.left - actions.first.left).abs() < 1);
          expect(sameColumn, isTrue, reason: 'expected a side action column');
          // 行尾一侧：LTR 在右，RTL 在左。
          final left = actions.first.left;
          expect(
              language == 'ur' ? left < width / 2 : left > width / 2, isTrue);
          await tester.tap(find.byIcon(Icons.translate));
          await tester.pump(const Duration(milliseconds: 400));
          for (final fraction in [0.0, 1.0]) {
            await scrollTo(tester, fraction);
            expectNoOverlap(tester, 'boundary scroll $fraction');
          }
        });
      }
    }

    // Android 验收发现：俄语“已加入收藏”气泡在 320dp、1.5 倍字号下横向溢出。
    for (final language in UserState.supportedLanguages) {
      testWidgets('feedback bubbles wrap instead of overflowing [$language]',
          (tester) async {
        await pumpQuestion(tester,
            language: language,
            size: const Size(320, 640),
            scale: 1.5,
            question: longQuestion,
            isAnswered: true,
            showBadges: true);
        expect(tester.takeException(), isNull);
        final bubbles = bubbleRect(tester)!;
        expect(bubbles.left, greaterThanOrEqualTo(0));
        expect(bubbles.right, lessThanOrEqualTo(320));
      });
    }

    testWidgets('narrow side actions follow reading direction in Urdu',
        (tester) async {
      await pumpQuestion(tester,
          language: 'ur',
          size: const Size(320, 640),
          scale: 1.0,
          question: longQuestion);
      final favorite = tester.getRect(find.byIcon(Icons.favorite_border));
      final translate = tester.getRect(find.byIcon(Icons.translate).first);
      expect(favorite.left, translate.left);
      expect(favorite.top, lessThan(translate.top));
      expect(favorite.center.dx, lessThan(160),
          reason: 'RTL side actions stay on the left');
    });

    testWidgets('screen readers announce action buttons as buttons with state',
        (tester) async {
      final semantics = tester.ensureSemantics();
      await pumpQuestion(tester,
          language: 'ur',
          size: const Size(411, 860),
          scale: 1.0,
          question: longQuestion);
      SemanticsData data(String key) => tester
          .getSemantics(
              find.bySemanticsLabel(AppStrings.getWithLanguage('ur', key)).last)
          .getSemanticsData();
      for (final key in [
        'favorite',
        'listen_question',
        'btn_explanation',
        'translation'
      ]) {
        expect(data(key).hasFlag(SemanticsFlag.isButton), isTrue,
            reason: '$key is not announced as a button');
        expect(data(key).hasAction(SemanticsAction.tap), isTrue,
            reason: '$key has no tap action');
      }
      expect(
          data('translation').hasFlag(SemanticsFlag.hasToggledState), isTrue);
      expect(data('translation').hasFlag(SemanticsFlag.isToggled), isFalse);
      await tester.tap(find.byIcon(Icons.translate).first);
      await tester.pump(const Duration(milliseconds: 400));
      expect(data('translation').hasFlag(SemanticsFlag.isToggled), isTrue);
      semantics.dispose();
    });

    testWidgets('translate and explanation buttons still work', (tester) async {
      await pumpQuestion(tester,
          language: 'ru',
          size: const Size(320, 640),
          scale: 1.5,
          question: longQuestion);
      expect(find.byType(TranslationPanel), findsNothing);
      await tester.tap(find.byIcon(Icons.translate));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(TranslationPanel), findsOneWidget);
      await tester.tap(find.byIcon(Icons.translate).last);
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(TranslationPanel), findsNothing);

      await tester.tap(find.byIcon(Icons.menu_book_outlined));
      await tester.pump(const Duration(seconds: 1));
      expect(
        find.text(
            AppStrings.getWithLanguage('ru', 'modal_correct_answer_label')),
        findsOneWidget,
      );
    });
  });
}

Question _fixture(String path) {
  final q = (jsonDecode(File(path).readAsStringSync())
      as Map<String, dynamic>)['question'] as Map<String, dynamic>;
  return Question(
    id: q['id'] as String,
    imageName: q['image_name'] as String?,
    answer: q['answer'] as bool,
    translations: Map<String, String>.from(q['translations'] as Map),
    explanations: Map<String, String>.from(q['explanations'] as Map),
    keywordsJson: q['keywords_json'] as String?,
  );
}

Future<void> _loadAppFonts() async {
  const families = {
    'NotoSans': [
      'NotoSans-Regular.ttf',
      'NotoSans-Medium.ttf',
      'NotoSans-SemiBold.ttf',
      'NotoSans-Bold.ttf'
    ],
    'NotoSansSC': [
      'NotoSansCJKsc-Regular.otf',
      'NotoSansCJKsc-Medium.otf',
      'NotoSansCJKsc-Bold.otf'
    ],
    'NotoNastaliqUrdu': [
      'NotoNastaliqUrdu-Regular.ttf',
      'NotoNastaliqUrdu-Bold.ttf'
    ],
    'NotoSansGurmukhi': [
      'NotoSansGurmukhi-Regular.ttf',
      'NotoSansGurmukhi-Medium.ttf',
      'NotoSansGurmukhi-SemiBold.ttf',
      'NotoSansGurmukhi-Bold.ttf'
    ],
  };
  for (final entry in families.entries) {
    final loader = FontLoader(entry.key);
    for (final file in entry.value) {
      final bytes = File('assets/fonts/noto/$file').readAsBytesSync();
      loader.addFont(Future.value(ByteData.sublistView(bytes)));
    }
    await loader.load();
  }
  final iconFont = File(
    '${Platform.environment['FLUTTER_ROOT'] ?? '/opt/homebrew/share/flutter'}'
    '/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
  );
  if (iconFont.existsSync()) {
    await (FontLoader('MaterialIcons')
          ..addFont(
              Future.value(ByteData.sublistView(iconFont.readAsBytesSync()))))
        .load();
  }
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
          const MethodChannel('flutter_tts'), (_) async => null);
}
