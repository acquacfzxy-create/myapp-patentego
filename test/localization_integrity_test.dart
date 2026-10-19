import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lingua_patente/config/app_strings.dart';
import 'package:lingua_patente/config/content_direction.dart';
import 'package:lingua_patente/config/locale_format.dart';
import 'package:lingua_patente/models/user_state.dart';

final _placeholder = RegExp(r'\{([A-Za-z_][A-Za-z0-9_]*)\}');

Set<String> _placeholders(String value) =>
    _placeholder.allMatches(value).map((m) => m.group(1)!).toSet();

void main() {
  final tables = AppStrings.tablesForTesting;
  const uiLanguages = ['it', 'zh', 'en', 'ru', 'uk', 'pa', 'ur'];

  group('AppStrings integrity', () {
    test('every selectable language and Italian have a string table', () {
      for (final language in [...UserState.languageNames.keys, 'it']) {
        expect(tables.containsKey(language), isTrue, reason: language);
      }
      expect(tables.keys.toSet(), uiLanguages.toSet());
    });

    test('all languages define exactly the same keys', () {
      final reference = tables['en']!.keys.toSet();
      for (final language in uiLanguages) {
        final keys = tables[language]!.keys.toSet();
        expect(reference.difference(keys), isEmpty,
            reason: '$language is missing keys');
        expect(keys.difference(reference), isEmpty,
            reason: '$language has keys not in en');
      }
    });

    test('placeholders match English in every language', () {
      final english = tables['en']!;
      for (final language in uiLanguages) {
        tables[language]!.forEach((key, value) {
          expect(_placeholders(value), _placeholders(english[key]!),
              reason: '$language/$key');
        });
      }
    });

    test('no value is empty', () {
      for (final language in uiLanguages) {
        tables[language]!.forEach((key, value) {
          expect(value.trim(), isNotEmpty, reason: '$language/$key');
        });
      }
    });

    test('user-facing errors do not expose developer terminology', () {
      const jargon = ['firebase', 'identity token', 'configuration'];
      for (final language in uiLanguages) {
        tables[language]!.forEach((key, value) {
          if (!key.startsWith('auth_error_')) return;
          for (final term in jargon) {
            expect(value.toLowerCase().contains(term), isFalse,
                reason: '$language/$key mentions "$term"');
          }
        });
      }
    });

    test('no user-facing copy names backend products', () {
      for (final language in uiLanguages) {
        tables[language]!.forEach((key, value) {
          expect(value, isNot(contains('Firestore')), reason: '$language/$key');
        });
      }
    });

    test('only the official exam labels stay in Italian', () {
      // IDONEO / NON IDONEO / CONSEGNA 与考场界面一致，其余文案应已翻译。
      const italianOnPurpose = {
        'app_title',
        'sub_title',
        'idoneo',
        'non_idoneo',
        'submit_exam'
      };
      final italian = tables['it']!;
      for (final language in ['zh', 'en', 'ru', 'uk', 'pa', 'ur']) {
        tables[language]!.forEach((key, value) {
          if (italianOnPurpose.contains(key)) return;
          if (RegExp(r'[A-Za-z]{6,}').hasMatch(value) &&
              value == italian[key]) {
            fail('$language/$key is still the Italian source: $value');
          }
        });
      }
    });

    test('"mastered" is not rendered as "expert" in Punjabi and Urdu', () {
      // all_questions_mastered 的主语是“你”（成为专家），这里用 ਮਾਹਰ 是通顺的。
      for (final key in tables['pa']!.keys.where(
          (k) => k.contains('mastered') && k != 'all_questions_mastered')) {
        expect(tables['pa']![key], isNot(contains('ਮਾਹਰ')), reason: 'pa/$key');
      }
      for (final key
          in tables['ur']!.keys.where((k) => k.contains('mastered'))) {
        expect(tables['ur']![key], isNot(contains('ماہر')), reason: 'ur/$key');
      }
    });

    test('count sentences read correctly when the count is 1', () {
      // 数量为 1 时不能出现复数名词；这些文案都改成了“名词: 数字”的写法。
      final wrongWithOne = {
        'en': RegExp(r'\b1 (days|questions|reviews|errors|wrong questions)\b',
            caseSensitive: false),
        'it': RegExp(r'\b1 (giorni|domande|ripassi|errori)\b'),
        'pa': RegExp(r'\b1 ਗਲਤੀਆਂ'),
        'ur': RegExp(r'\b1 (سوالات|غلطیاں)'),
        'ru': RegExp(r'\b1 (вопросов|дней|ошибок)\b'),
        'uk': RegExp(r'\b1 (питань|днів|помилок)\b'),
      };
      for (final entry in wrongWithOne.entries) {
        tables[entry.key]!.forEach((key, value) {
          // 这些数量不可能为 1：时长选项固定为 30/60/90/180 天；
          // 章节与语音包题数最少 94（按章节打包）。
          const neverOne = {
            'daily_goal_duration_option',
            'voice_pack_question_count',
            'web_chapter_question_count',
            'chapter_stat_bank',
          };
          if (neverOne.contains(key)) return;
          final rendered =
              value.replaceAll('{count}', '1').replaceAll('{days}', '1');
          // {goal} 最小为 10（DailyGoalPlan.minDailyGoal），不会取到 1。
          expect(entry.value.hasMatch(rendered), isFalse,
              reason: '${entry.key}/$key renders as "$rendered"');
        });
      }
    });

    test('web voice help names the listen button the user actually sees', () {
      // 网页朗读按钮显示 listen_question；说明文字要引用同一个词。
      for (final language in uiLanguages) {
        final label = tables[language]!['listen_question']!;
        expect(
            tables[language]!['web_browser_voice_description'], contains(label),
            reason: '$language description should mention "$label"');
      }
    });

    test('Chinese sign-out copy does not read as account deletion', () {
      expect(tables['zh']!['sign_out'], isNot(contains('注销')));
    });
  });

  group('Web copy uses the shared string table', () {
    final source = File('lib/screens/web_app_screen.dart').readAsStringSync();

    test('web keys resolve in every language', () {
      final mapping =
          RegExp(r"^    '([A-Za-z]+)': '([a-z_]+)',$", multiLine: true)
              .allMatches(source)
              .map((m) => m.group(2)!)
              .toSet();
      expect(mapping.length, greaterThan(40));
      for (final language in uiLanguages) {
        for (final key in mapping) {
          expect(tables[language]!.containsKey(key), isTrue,
              reason: '$language/$key');
        }
      }
    });

    test('the web screen no longer carries its own bilingual tables', () {
      expect(source, isNot(contains('const english = {')));
      expect(source, isNot(contains('const chinese = {')));
      expect(source, isNot(contains("'Selected: ")));
    });
  });

  group('contentTextDirection', () {
    test('Arabic-script text is right-to-left, Gurmukhi is not', () {
      expect(contentTextDirection('ਦਿਖਾਈ ਗਈ'), TextDirection.ltr);
      expect(contentTextDirection('دکھائے گئے نشان والی سڑک پر'),
          TextDirection.rtl);
      expect(contentTextDirection('ABS والی گاڑی میں بریک'), TextDirection.rtl);
    });

    test('Latin, Cyrillic and Chinese text is left-to-right', () {
      expect(contentTextDirection('Il segnale raffigurato'), TextDirection.ltr);
      expect(contentTextDirection('Представленный знак'), TextDirection.ltr);
      expect(contentTextDirection('图中标志'), TextDirection.ltr);
    });

    test('text without letters falls back to the ambient direction', () {
      expect(contentTextDirection('123 — 4', fallback: TextDirection.rtl),
          TextDirection.rtl);
      expect(contentTextDirection(''), TextDirection.ltr);
    });
  });

  group('LocaleFormat', () {
    final date = DateTime(2026, 3, 7);

    test('dates follow each language convention', () {
      expect(LocaleFormat.date('zh', date), '2026年3月7日');
      expect(LocaleFormat.date('en', date), '2026-03-07');
      expect(LocaleFormat.date('ru', date), '07.03.2026');
      expect(LocaleFormat.date('uk', date), '07.03.2026');
      expect(LocaleFormat.date('it', date), '07/03/2026');
      expect(LocaleFormat.date('pa', date), '07/03/2026');
    });

    test('short chart dates are not ambiguous for day-first languages', () {
      final d = DateTime(2026, 3, 7);
      expect(LocaleFormat.shortDate('zh', d), '3/7');
      expect(LocaleFormat.shortDate('en', d), '03-07');
      expect(LocaleFormat.shortDate('ru', d), '07.03');
      expect(LocaleFormat.shortDate('uk', d), '07.03');
      expect(LocaleFormat.shortDate('it', d), '7/3');
      expect(LocaleFormat.shortDate('pa', d), '7/3');
      expect(LocaleFormat.shortDate('ur', d), '7/3');
      expect(LocaleFormat.decimal('ru', 72.5, 1), '72,5');
      expect(LocaleFormat.decimal('zh', 72.5, 1), '72.5');
    });

    test('file sizes use local decimal separators and units', () {
      const size = 1572864; // 1.5 MB
      expect(LocaleFormat.fileSize('en', size), '1.5 MB');
      expect(LocaleFormat.fileSize('zh', size), '1.5 MB');
      expect(LocaleFormat.fileSize('it', size), '1,5 MB');
      expect(LocaleFormat.fileSize('ru', size), '1,5 МБ');
      expect(LocaleFormat.fileSize('uk', 2048), '2,0 КБ');
      expect(LocaleFormat.fileSize('ur', 512), '512 B');
    });
  });
}
