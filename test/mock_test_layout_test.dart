import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lingua_patente/config/app_locales.dart';
import 'package:lingua_patente/config/app_strings.dart';
import 'package:lingua_patente/config/app_theme.dart';
import 'package:lingua_patente/models/question.dart';
import 'package:lingua_patente/providers/user_state_provider.dart';
import 'package:lingua_patente/screens/mock_test_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 模擬考列表：每道題的意大利語題幹必須完整可讀，交卷按鈕不得壓住題目或答案。
///
/// 題目取自題庫（唯讀匯出）：使用者截圖中的第 18–21 題（有圖 4904、4341，
/// 無圖 4643、4411），以及最長的無圖題 5568 與有圖題 2665。30 道題循環排列，
/// 最後一題是有圖長題。320dp / 360dp × 字號 1.0 / 1.5，中文與烏爾都語介面，真實 Noto 字體。
///
/// 檢查的是排版結果而不是 Text 物件是否存在：
/// RenderParagraph 未被 maxLines 截斷（didExceedMaxLines=false）、高度容納全部行、
/// 換行不切斷單詞；每題捲動後 VERO/FALSO 能被點中；交卷按鈕不覆蓋題目列表，
/// 答完 30 題後交卷可點。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const sizes = [Size(320, 640), Size(360, 780)];
  const scales = [1.0, 1.5];
  const languages = ['zh', 'ur'];
  late List<Question> samples;

  setUpAll(() async {
    await _loadAppFonts();
    // 作答會觸發進度記錄；測試中讓 path_provider 調用保持掛起，不寫任何資料。
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (_) => Completer<Object?>().future,
    );
    samples = _fixtures('test/fixtures/mock_exam_long_stems.json');
  });

  for (final language in languages) {
    for (final size in sizes) {
      for (final scale in scales) {
        final label = '$language ${size.width.toInt()}dp x$scale';
        testWidgets('mock exam stems are complete and reachable ($label)',
            (tester) async {
          final questions = [for (var i = 0; i < 30; i++) samples[i % 6]];
          await _pumpExam(tester, language, size, scale, questions);
          final problems = <String>[];
          final report = <String>[];

          final list = find.byType(ListView);
          final submitText = AppStrings.get('submit_exam');
          final submit = find.ancestor(
              of: find.text(submitText), matching: find.byType(InkWell));
          final viewport = tester.getRect(list);
          final submitRect = tester.getRect(submit);
          if (viewport.overlaps(submitRect)) {
            problems.add('submit button covers the question list: '
                'list=$viewport submit=$submitRect');
          }
          // 可見區域：列表視口去掉被交卷按鈕蓋住的部分。
          final visibleBottom = viewport.overlaps(submitRect)
              ? math.min(viewport.bottom, submitRect.top)
              : viewport.bottom;

          for (var i = 0; i < questions.length; i++) {
            final card = find.byKey(ValueKey('mock-test-question-card-$i'));
            await tester.scrollUntilVisible(card, 300,
                scrollable: find.byType(Scrollable).first);
            final stem = find.descendant(
                of: card, matching: find.text(questions[i].translations['it']!));
            final vero = find.descendant(of: card, matching: find.text('VERO'));
            final falso =
                find.descendant(of: card, matching: find.text('FALSO'));

            // 1) 題幹排版完整。
            await tester.ensureVisible(stem);
            await tester.pump();
            final p = tester.renderObject<RenderParagraph>(stem);
            final width = p.constraints.maxWidth;
            final lines = _lineCount(p);
            final broken = _brokenWords(p);
            final fullHeight = p.getMaxIntrinsicHeight(width);
            if (i < 6 || i == questions.length - 1) {
              report.add('q${questions[i].id} img=${questions[i].imageName != null} '
                  'width=${width.toStringAsFixed(0)} lines=$lines '
                  'maxLines=${p.maxLines} exceeded=${p.didExceedMaxLines}');
            }
            if (p.maxLines != null || p.didExceedMaxLines) {
              problems.add('#${i + 1} q${questions[i].id}: stem truncated '
                  '(maxLines=${p.maxLines}, didExceedMaxLines=${p.didExceedMaxLines}, '
                  'needs $lines lines)');
            }
            if (p.size.height + 0.5 < fullHeight) {
              problems.add('#${i + 1} q${questions[i].id}: stem clipped '
                  '${p.size.height.toStringAsFixed(1)} < ${fullHeight.toStringAsFixed(1)}');
            }
            if (broken.isNotEmpty) {
              problems.add('#${i + 1} q${questions[i].id}: words split across '
                  'lines at width ${width.toStringAsFixed(0)}: ${broken.join(', ')}');
            }
            if (p.textDirection != TextDirection.ltr) {
              problems.add('#${i + 1}: Italian stem is not LTR');
            }
            // 首行與最末行都能捲進可見區域（題幹比可見區域還高時分兩次看）。
            final stemRect = tester.getRect(stem);
            if (stemRect.top < viewport.top - 0.5 ||
                stemRect.top > visibleBottom) {
              problems.add('#${i + 1} q${questions[i].id}: first line not '
                  'reachable ($stemRect, visible ${viewport.top}..$visibleBottom)');
            }
            await Scrollable.ensureVisible(tester.element(stem), alignment: 1);
            await tester.pump();
            final stemEnd = tester.getRect(stem);
            if (stemEnd.bottom > visibleBottom + 0.5 ||
                stemEnd.bottom < viewport.top) {
              problems.add('#${i + 1} q${questions[i].id}: last line not '
                  'reachable ($stemEnd, visible ${viewport.top}..$visibleBottom)');
            }
            if (stemRect.height > visibleBottom - viewport.top) {
              report.add('#${i + 1} q${questions[i].id} stem '
                  '${stemRect.height.toStringAsFixed(0)}dp taller than visible '
                  '${(visibleBottom - viewport.top).toStringAsFixed(0)}dp; '
                  'last line reached by scrolling');
            }

            // 2) 答案按鈕捲到後能被點中，不被交卷按鈕擋住。
            await tester.ensureVisible(vero);
            await tester.pump();
            for (final (name, answer) in [('VERO', vero), ('FALSO', falso)]) {
              final detector = find
                  .ancestor(of: answer, matching: find.byType(GestureDetector))
                  .first;
              if (!_hits(tester, detector, tester.getCenter(answer))) {
                problems.add('#${i + 1}: $name cannot be tapped '
                    '(${tester.getRect(answer)}, submit $submitRect)');
              }
              if (tester.getRect(answer).overlaps(submitRect)) {
                problems.add('#${i + 1}: $name lies under the submit button');
              }
            }
            await tester.tapAt(tester.getCenter(vero));
            await tester.pump();
          }

          // 3) 最後一題可完整捲出（卡片底部不被按鈕或視口截掉）。
          final lastCard = find.byKey(
              ValueKey('mock-test-question-card-${questions.length - 1}'));
          final lastRect = tester.getRect(lastCard);
          if (lastRect.bottom > visibleBottom + 0.5) {
            problems.add('last card ends at ${lastRect.bottom}, '
                'visible bottom $visibleBottom');
          }

          // 4) 答完 30 題後交卷按鈕啟用且可點中（不實際交卷）。
          if (tester.widget<InkWell>(submit).onTap == null) {
            problems.add('submit button still disabled after answering 30');
          }
          if (!_hits(tester, submit, tester.getCenter(submit))) {
            problems.add('submit button cannot be tapped');
          }

          debugPrint('MOCK_EXAM_LAYOUT $label\n  ${report.join('\n  ')}'
              '\n  problems=${problems.length}');
          expect(problems, isEmpty, reason: problems.join('\n'));
        });
      }
    }
  }
}

Future<void> _pumpExam(WidgetTester tester, String language, Size size,
    double scale, List<Question> questions) async {
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
        theme: AppTheme.lightTheme(language: language),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: MockTestScreen(debugQuestions: questions),
      ),
    ),
  );
  // 圖片解碼在真實異步中完成。
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 50)),
  );
  await tester.pump(const Duration(milliseconds: 300));
}

/// 以 [p] 實際收到的寬度重新排版，不限行數，得到完整題幹需要的行數。
TextPainter _painterFor(RenderParagraph p) => TextPainter(
      text: p.text,
      textDirection: p.textDirection,
      textScaler: p.textScaler,
      textAlign: p.textAlign,
    )..layout(maxWidth: p.constraints.maxWidth);

int _lineCount(RenderParagraph p) {
  final painter = _painterFor(p);
  final count = painter.computeLineMetrics().length;
  painter.dispose();
  return count;
}

/// 換行處不在空白、連字號或斜線旁的位置，即單詞被拆到兩行。
List<String> _brokenWords(RenderParagraph p) {
  final plain = p.text.toPlainText();
  final painter = _painterFor(p);
  final result = <String>[];
  var offset = 0;
  while (offset < plain.length) {
    final end = painter.getLineBoundary(TextPosition(offset: offset)).end;
    if (end <= offset) break;
    if (end < plain.length) {
      final before = plain[end - 1];
      final after = plain[end];
      if (before.trim().isNotEmpty &&
          after.trim().isNotEmpty &&
          !'-/'.contains(before)) {
        result.add('"${plain.substring(math.max(0, end - 10), end)}|'
            '${plain.substring(end, math.min(plain.length, end + 6))}"');
      }
    }
    offset = end;
  }
  painter.dispose();
  return result;
}

/// 在 [position] 點擊時，指標事件能否到達 [target] 子樹內的任一渲染物件。
bool _hits(WidgetTester tester, Finder target, Offset position) {
  final objects = <RenderObject>{};
  void visit(Element element) {
    if (element is RenderObjectElement) objects.add(element.renderObject);
    element.visitChildren(visit);
  }

  visit(target.evaluate().first);
  final result = HitTestResult();
  tester.binding.hitTestInView(result, position, tester.view.viewId);
  return result.path.any((entry) => objects.contains(entry.target));
}

List<Question> _fixtures(String path) {
  final data = jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;
  return [
    for (final q in (data['questions'] as List).cast<Map<String, dynamic>>())
      Question(
        id: q['id'] as String,
        imageName: q['image_name'] as String?,
        answer: q['answer'] as bool,
        translations: {'it': q['it'] as String},
        explanations: const {},
      ),
  ];
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
}
