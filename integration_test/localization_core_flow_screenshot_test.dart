import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:italy_quiz_app/config/app_strings.dart';
import 'package:italy_quiz_app/models/question.dart';
import 'package:italy_quiz_app/providers/user_state_provider.dart';
import 'package:italy_quiz_app/screens/chapter_selection_screen.dart';
import 'package:italy_quiz_app/screens/mock_test_result_screen.dart';
import 'package:italy_quiz_app/screens/mock_test_screen.dart';
import 'package:italy_quiz_app/services/database_service.dart';
import 'package:italy_quiz_app/widgets/question_widget.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('core flow localization screenshots', () {
    testWidgets('captures ru uk ur pa core answer flows', (tester) async {
      await DatabaseService.init();
      await _seedCoreFlowData();

      final outputDir = await _prepareOutputDirectory();
      final languages = ['ru', 'uk', 'ur', 'pa'];

      for (final language in languages) {
        final question = _questionFor(language);
        await _pumpLocalizedPage(
          tester,
          language: language,
          page: const ChapterSelectionScreen(),
        );
        await _capture(tester, outputDir, '${language}_chapter_selection');

        await _pumpLocalizedPage(
          tester,
          language: language,
          page: _QuestionPreviewPage(
            question: question,
            language: language,
          ),
        );
        await _capture(tester, outputDir, '${language}_practice_unanswered');

        await _pumpLocalizedPage(
          tester,
          language: language,
          page: _QuestionPreviewPage(
            question: question,
            language: language,
            isAnswered: true,
            isCorrect: true,
            userChoice: question.answer,
          ),
        );
        await _capture(tester, outputDir, '${language}_practice_correct');

        await _pumpLocalizedPage(
          tester,
          language: language,
          page: _QuestionPreviewPage(
            question: question,
            language: language,
            isAnswered: true,
            isCorrect: false,
            userChoice: !question.answer,
          ),
        );
        await _capture(tester, outputDir, '${language}_practice_wrong');

        await _pumpLocalizedPage(
          tester,
          language: language,
          page: _ExplanationPreviewPage(
            question: question,
            language: language,
          ),
        );
        await tester.pump(const Duration(milliseconds: 500));
        await _capture(tester, outputDir, '${language}_explanation_sheet');
        await _dismissTopRoute(tester);

        await _pumpLocalizedPage(
          tester,
          language: language,
          page: const MockTestScreen(),
        );
        await tester.pump(const Duration(seconds: 2));
        await _capture(tester, outputDir, '${language}_mock_exam');

        await _pumpLocalizedPage(
          tester,
          language: language,
          page: _MockResultPreviewPage(
            question: question,
            language: language,
          ),
        );
        await _capture(tester, outputDir, '${language}_mock_result');
      }

      debugPrint('CORE_SCREENSHOTS_READY=${outputDir.path}');
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
  await provider.updateUserState(isVip: true, currentLanguage: language);
  await provider.refreshChaptersProgress();
  AppStrings.setLanguage(language);

  final textDirection =
      language == 'ur' ? TextDirection.rtl : TextDirection.ltr;

  await tester.pumpWidget(
    RepaintBoundary(
      key: _screenshotKey,
      child: ChangeNotifierProvider<UserStateProvider>.value(
        value: provider,
        child: MaterialApp(
          navigatorKey: _navigatorKey,
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
final _navigatorKey = GlobalKey<NavigatorState>();

Future<void> _dismissTopRoute(WidgetTester tester) async {
  final navigator = _navigatorKey.currentState;
  if (navigator != null && navigator.canPop()) {
    navigator.pop();
    await tester.pump(const Duration(milliseconds: 300));
  }
}

Future<Directory> _prepareOutputDirectory() async {
  final documentsDir = await getApplicationDocumentsDirectory();
  final outputDir =
      Directory('${documentsDir.path}/localization_core_flow_pages');
  if (outputDir.existsSync()) {
    outputDir.deleteSync(recursive: true);
  }
  outputDir.createSync(recursive: true);
  debugPrint('CORE_SCREENSHOT_OUTPUT_DIR=${outputDir.path}');
  return outputDir;
}

Future<void> _seedCoreFlowData() async {
  const userId = UserStateProvider.guestUserId;
  await DatabaseService.resetAllUserProgress(userId: userId);

  final questions = await DatabaseService.getQuestions(
    lang: 'zh',
    limit: 8,
    userId: userId,
  );

  for (final question in questions.take(5)) {
    await DatabaseService.updateQuestionProgress(
      question.id,
      false,
      userId: userId,
    );
  }
}

class _QuestionPreviewPage extends StatelessWidget {
  const _QuestionPreviewPage({
    required this.question,
    required this.language,
    this.isAnswered = false,
    this.isCorrect,
    this.userChoice,
  });

  final Question question;
  final String language;
  final bool isAnswered;
  final bool? isCorrect;
  final bool? userChoice;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: QuestionWidget(
        question: question,
        currentLanguage: language,
        currentIndex: 0,
        totalQuestions: 30,
        hasNextQuestion: true,
        isAnswered: isAnswered,
        isCorrect: isCorrect,
        userChoice: userChoice,
        onAnswerSelected: (_) {},
      ),
    );
  }
}

class _ExplanationPreviewPage extends StatefulWidget {
  const _ExplanationPreviewPage({
    required this.question,
    required this.language,
  });

  final Question question;
  final String language;

  @override
  State<_ExplanationPreviewPage> createState() =>
      _ExplanationPreviewPageState();
}

class _ExplanationPreviewPageState extends State<_ExplanationPreviewPage> {
  bool _opened = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_opened) return;
    _opened = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(
        QuestionWidget.showRichExplanation(
          context,
          question: widget.question,
          currentLanguage: widget.language,
          remainingExplanations: 3,
          showVipBadgeOnStudyTip: true,
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return _QuestionPreviewPage(
      question: widget.question,
      language: widget.language,
      isAnswered: true,
      isCorrect: true,
      userChoice: widget.question.answer,
    );
  }
}

class _MockResultPreviewPage extends StatelessWidget {
  const _MockResultPreviewPage({
    required this.question,
    required this.language,
  });

  final Question question;
  final String language;

  @override
  Widget build(BuildContext context) {
    return MockTestResultScreen(
      totalQuestions: 30,
      correctAnswers: 24,
      errors: 6,
      isPassed: false,
      timeRemaining: 840,
      errorIds: [question.id],
      questions: [question],
      userChoices: {0: !question.answer},
    );
  }
}

Question _questionFor(String language) {
  const it =
      'In presenza del segnale raffigurato, il conducente deve moderare la velocità e prestare particolare attenzione agli altri utenti della strada.';

  const localizedQuestions = {
    'ru':
        'При наличии показанного знака водитель должен снизить скорость и внимательно следить за другими участниками движения, особенно перед перекрёстком.',
    'uk':
        'За наявності показаного знака водій повинен зменшити швидкість і уважно стежити за іншими учасниками руху, особливо перед перехрестям.',
    'ur':
        'دکھائے گئے نشان کی موجودگی میں ڈرائیور کو رفتار کم کرنی چاہیے اور سڑک استعمال کرنے والے دوسرے افراد پر خاص توجہ دینی چاہیے۔',
    'pa':
        'ਦਿਖਾਏ ਗਏ ਨਿਸ਼ਾਨ ਦੀ ਮੌਜੂਦਗੀ ਵਿੱਚ ਡਰਾਈਵਰ ਨੂੰ ਗਤੀ ਘਟਾਉਣੀ ਚਾਹੀਦੀ ਹੈ ਅਤੇ ਸੜਕ ਵਰਤਣ ਵਾਲੇ ਹੋਰ ਲੋਕਾਂ ਵੱਲ ਖਾਸ ਧਿਆਨ ਦੇਣਾ ਚਾਹੀਦਾ ਹੈ।',
  };

  final explanation = _explanationJson(language);
  return Question(
    id: 'core-flow-$language',
    answer: true,
    translations: {
      'it': it,
      language: localizedQuestions[language]!,
    },
    explanations: {
      language: explanation,
      'it': explanation,
    },
    chapter: 1,
    keywordsJson: jsonEncode({
      language: [
        {
          'it': 'moderare la velocità',
          language: localizedQuestions[language]!.split(' ').take(3).join(' '),
          'en': 'slow down',
        },
      ],
    }),
  );
}

String _explanationJson(String language) {
  final copy = {
    'ru': (
      description:
          'Знак предупреждает о ситуации, где нужно заранее снизить скорость и быть готовым к действиям других участников движения.',
      title1: 'moderare la velocità',
      content1:
          'Снизить скорость до безопасного уровня, а не продолжать ехать как обычно.',
      title2: 'prestare attenzione',
      content2: 'Проверять обстановку вокруг и не делать резких манёвров.',
      tip:
          'Запоминайте так: если знак предупреждает об опасности, правильная реакция почти всегда начинается с **prudenza (осторожность)**.',
    ),
    'uk': (
      description:
          'Знак попереджає про ситуацію, де треба заздалегідь зменшити швидкість і бути готовим до дій інших учасників руху.',
      title1: 'moderare la velocità',
      content1:
          'Зменшити швидкість до безпечного рівня, а не їхати як зазвичай.',
      title2: 'prestare attenzione',
      content2: 'Стежити за обстановкою навколо і не робити різких маневрів.',
      tip:
          'Запам’ятайте: коли знак попереджає про небезпеку, правильна відповідь майже завжди починається з **prudenza (обережність)**.',
    ),
    'ur': (
      description:
          'یہ نشان ایسی صورتحال کی وارننگ دیتا ہے جہاں رفتار پہلے سے کم کرنا اور دوسرے افراد کی حرکت کے لیے تیار رہنا ضروری ہے۔',
      title1: 'moderare la velocità',
      content1: 'رفتار کو محفوظ حد تک کم کریں، معمول کی رفتار سے آگے نہ بڑھیں۔',
      title2: 'prestare attenzione',
      content2: 'اردگرد کی صورتحال دیکھیں اور اچانک موڑ یا حرکت نہ کریں۔',
      tip:
          'یاد رکھیں: خطرے کا نشان آئے تو درست ردعمل عموماً **prudenza (احتیاط)** سے شروع ہوتا ہے۔',
    ),
    'pa': (
      description:
          'ਇਹ ਨਿਸ਼ਾਨ ਅਜਿਹੀ ਸਥਿਤੀ ਦੀ ਚੇਤਾਵਨੀ ਦਿੰਦਾ ਹੈ ਜਿੱਥੇ ਪਹਿਲਾਂ ਹੀ ਗਤੀ ਘਟਾਉਣੀ ਅਤੇ ਹੋਰ ਲੋਕਾਂ ਦੀ ਹਰਕਤ ਲਈ ਤਿਆਰ ਰਹਿਣਾ ਜ਼ਰੂਰੀ ਹੈ।',
      title1: 'moderare la velocità',
      content1: 'ਗਤੀ ਨੂੰ ਸੁਰੱਖਿਅਤ ਪੱਧਰ ਤੱਕ ਘਟਾਓ, ਆਮ ਤਰ੍ਹਾਂ ਤੇਜ਼ ਨਾ ਚਲੋ।',
      title2: 'prestare attenzione',
      content2: 'ਆਲੇ ਦੁਆਲੇ ਦੀ ਸਥਿਤੀ ਦੇਖੋ ਅਤੇ ਅਚਾਨਕ ਮੋੜ ਜਾਂ ਹਰਕਤ ਨਾ ਕਰੋ।',
      tip:
          'ਯਾਦ ਰੱਖੋ: ਖਤਰੇ ਵਾਲਾ ਨਿਸ਼ਾਨ ਆਵੇ ਤਾਂ ਸਹੀ ਜਵਾਬ ਅਕਸਰ **prudenza (ਸਾਵਧਾਨੀ)** ਨਾਲ ਸ਼ੁਰੂ ਹੁੰਦਾ ਹੈ।',
    ),
  }[language]!;

  return jsonEncode({
    'detailed_description': copy.description,
    'key_points': [
      {'title': copy.title1, 'content': copy.content1},
      {'title': copy.title2, 'content': copy.content2},
    ],
    'study_tip': copy.tip,
  });
}
