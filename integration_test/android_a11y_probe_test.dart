import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lingua_patente/config/app_locales.dart';
import 'package:lingua_patente/config/app_strings.dart';
import 'package:lingua_patente/config/app_theme.dart';
import 'package:lingua_patente/models/question.dart';
import 'package:lingua_patente/providers/user_state_provider.dart';
import 'package:lingua_patente/services/database_service.dart';
import 'package:lingua_patente/widgets/question_widget.dart';
import 'package:provider/provider.dart';

import 'support/l10n_sample_question.dart';

/// Android 无障碍探测：显示乌尔都语题目页并保持一段时间，供宿主用
/// `adb shell uiautomator dump` 导出 Android 无障碍节点树（TalkBack 读取的数据），
/// 核对操作按钮的名称、可点击与开关状态。不登录、不购买、不改数据。
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('expose the Urdu question page to Android accessibility',
      (tester) async {
    await DatabaseService.init();
    const language =
        String.fromEnvironment('A11Y_LANGUAGE', defaultValue: 'ur');
    final q = jsonDecode(kL10nSampleQuestionJson) as Map<String, dynamic>;
    final question = Question(
      id: q['id'] as String,
      answer: q['answer'] as bool,
      translations: Map<String, String>.from(q['translations'] as Map),
      explanations: Map<String, String>.from(q['explanations'] as Map),
      keywordsJson: q['keywords_json'] as String?,
    );
    final provider = UserStateProvider();
    await provider.changeLanguage(language);
    AppStrings.setLanguage(language);

    await tester.pumpWidget(
      ChangeNotifierProvider<UserStateProvider>.value(
        value: provider,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          locale: AppLocales.localeFor(language),
          supportedLocales: AppLocales.supportedLocales,
          localizationsDelegates: AppLocales.delegates,
          theme: AppTheme.lightTheme(language: language),
          home: Scaffold(
            body: SafeArea(
              child: QuestionWidget(
                question: question,
                currentLanguage: language,
                onAnswerSelected: (_) {},
                currentIndex: 1,
                totalQuestions: 30,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    // 打开翻译，便于核对开关状态。
    await tester.tap(find.byIcon(Icons.translate).first);
    await tester.pump(const Duration(seconds: 1));
    for (final key in [
      'favorite',
      'listen_question',
      'btn_explanation',
      'translation'
    ]) {
      debugPrint(
          'A11Y_LABEL $key=${AppStrings.getWithLanguage(language, key)}');
    }
    debugPrint('A11Y_READY');
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
  });
}
