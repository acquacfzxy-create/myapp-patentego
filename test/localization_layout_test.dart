import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lingua_patente/config/app_strings.dart';
import 'package:lingua_patente/models/user_state.dart';
import 'package:lingua_patente/providers/user_state_provider.dart';
import 'package:lingua_patente/screens/auth_page.dart';
import 'package:lingua_patente/widgets/translation_panel.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 小屏（320 宽）+ 放大字号下，各界面语言的关键页面不应出现布局溢出。
/// 测试字体每个字形都是等宽方块，比真实字体更宽，因此这里通过即代表真实字体下有余量。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const smallPhone = Size(320, 640);
  const textScales = [1.0, 1.5];
  final languages = UserState.languageNames.keys.toList();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<void> setSurface(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(smallPhone);
    tester.view.physicalSize = smallPhone;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() async {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      await tester.binding.setSurfaceSize(null);
    });
  }

  Widget shell({
    required String language,
    required double textScale,
    required Widget child,
  }) {
    return MaterialApp(
      builder: (context, inner) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: Directionality(
          textDirection:
              language == 'ur' ? TextDirection.rtl : TextDirection.ltr,
          child: inner!,
        ),
      ),
      home: child,
    );
  }

  for (final language in languages) {
    for (final scale in textScales) {
      testWidgets('AuthPage fits a 320px screen [$language, x$scale]',
          (tester) async {
        await setSurface(tester);
        final provider = UserStateProvider();
        await provider.changeLanguage(language);
        AppStrings.setLanguage(language);

        await tester.pumpWidget(
          ChangeNotifierProvider<UserStateProvider>.value(
            value: provider,
            child: shell(
              language: language,
              textScale: scale,
              child: const AuthPage(),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 500));

        expect(tester.takeException(), isNull);
        expect(
          find.text(AppStrings.getWithLanguage(language, 'auth_google')),
          findsOneWidget,
        );
      });

      testWidgets('TranslationPanel wraps long text [$language, x$scale]',
          (tester) async {
        await setSurface(tester);
        final longText = List.filled(
          6,
          AppStrings.getWithLanguage(language, 'web_offline_description'),
        ).join(' ');

        await tester.pumpWidget(
          shell(
            language: language,
            textScale: scale,
            child: Scaffold(
              body: SingleChildScrollView(
                child: TranslationPanel(
                  text: longText,
                  languageCode: language,
                ),
              ),
            ),
          ),
        );

        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('Shahmukhi translation is laid out right-to-left in the pa UI',
      (tester) async {
    const shahmukhi = 'دکھائی گئی قسم دی سڑک اُتے موڑ وچ وی اوورٹیک دی اجازت اے۔';
    await tester.pumpWidget(
      shell(
        language: 'pa',
        textScale: 1.0,
        child: const Scaffold(
          body: TranslationPanel(text: shahmukhi, languageCode: 'pa'),
        ),
      ),
    );

    final text = tester.widget<Text>(find.text(shahmukhi));
    expect(text.textDirection, TextDirection.rtl);
  });
}
