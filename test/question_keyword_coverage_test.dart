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
import 'package:lingua_patente/widgets/question_widget.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 重点词汇 10 题试改：真实 `Question.getKeyWords` 与题目页真实的词汇区。
///
/// 数据是试改后从 assets/italy_quiz.db 只读导出的 10 道题
/// （test/fixtures/keyword_pilot_questions.json，keywords_json 为库中原字符串）。
/// 模型：六种语言都返回完整列表，每条用本语言释义，没有回退到英文/中文。
/// 界面：真实 QuestionWidget，320dp、字号 1.0 / 1.5、六种语言（ur 为 RTL），
/// 展开翻译后每个词条都能完整读到：不横向溢出、不截断、不互相重叠、不被按钮盖住。
///
/// 长词边界（test/fixtures/keyword_long_term_questions.json，第 4 批后只读导出）：
/// 题 5949 的意大利语词条长 41 个字符、题 6659 长 47 个字符，超过试改题最长的 37 个字符；
/// 同样用真实模型与真实词汇区检查，并确认长词确实在词条内换行。
///
/// 长释义边界（test/fixtures/keyword_long_gloss_questions.json，第 7 批后只读导出）：
/// 题 6674 保留的词条俄语释义 66 个字符、乌克兰语 63 个字符，题 6414 的俄语、乌克兰语释义
/// 各 59 个字符，都超过此前测过的最长释义；整份词条未作任何删短，同样用真实模型与真实词汇区检查。
///
/// 第 8 批边界（test/fixtures/keyword_batch8_boundary_questions.json，第 8 批后只读导出）：
/// 题 6006 保留的意大利语词条长 54 个字符（此前最长 47），题 6693 保留的词条俄语释义 71 个字符
/// （此前最长 66）、英语释义 52 个字符（此前最长 50）；整份词条未作任何删短。
///
/// 第 10 批条数边界（test/fixtures/keyword_batch10_boundary_questions.json，第 10 批后只读导出）：
/// 题 5497 有 19 条、题 4196 有 18 条、题 5568 有 16 条词条，超过此前样本最多的 14 条。
/// 每题条数没有上限；这里只验证更多词条时每一条仍可滚动到、完整可读、互不遮挡。
///
/// 第 11 批释义边界（test/fixtures/keyword_batch11_boundary_questions.json，第 11 批后只读导出）：
/// 题 5269 的词条 sorpassi in scia 英语释义 56 个字符（此前最长 52）；整份词条未作任何删短。
///
/// 第 12 批释义边界（test/fixtures/keyword_batch12_boundary_questions.json，第 12 批后只读导出）：
/// 题 6695 保留的词条 assicurazione R.C.A. 英语释义 58 个字符、乌克兰语 69、旁遮普语 49、乌尔都语 52
/// （此前最长 56／63／47／51；俄语 71 与此前相同）；整份词条未作任何删短。
///
/// 第 13 批释义边界（test/fixtures/keyword_batch13_boundary_questions.json，第 13 批后只读导出）：
/// 题 6694 保留的词条 assicurazione R.C.A. 乌尔都语释义 53 个字符（此前最长 52）；整份词条未作任何删短。
///
/// 第 14 批长词边界（test/fixtures/keyword_batch14_boundary_questions.json，第 14 批后只读导出）：
/// 题 6696 的意大利语词条 assicurazione per la responsabilità civile auto (R.C.A.) 长 56 个字符
/// （此前最长 54）；这是题干的连续短语，整份词条未作任何删短。
///
/// 第 16 批释义边界（test/fixtures/keyword_batch16_boundary_questions.json，第 17 批后重新只读导出）：
/// 题 6676、6677 的词条 polizza di assicurazione R.C.A. 英语释义 61／65 个字符、俄语 79、乌克兰语 77
/// （第 16 批起，此前最长 58／71／69）；第 17 批按复核意见把旁遮普语、乌尔都语改为本语短义后，
/// 两题都是旁遮普语 61、乌尔都语 64（第 16 批为 54／52、56／63）；整份词条未作任何删短。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const expectedCounts = {
    '560': 4,
    '584': 4,
    '91': 4,
    '116': 7,
    '5173': 6,
    '5107': 6,
    '4159': 14,
    '4220': 12,
    '6913': 3,
    '6593': 4,
  };
  final questions = _fixtures('test/fixtures/keyword_pilot_questions.json');
  final longTermQuestions =
      _fixtures('test/fixtures/keyword_long_term_questions.json');
  const longTerms = {
    '5949': 'temperatura del liquido di raffreddamento',
    '6659': 'assicurazione per la responsabilità civile auto',
  };
  final longGlossQuestions =
      _fixtures('test/fixtures/keyword_long_gloss_questions.json');
  const longGlosses = {
    '6674': {
      'ru':
          'Страховой полис R.C.A. (гражданская ответственность автовладельца)',
      'uk': 'Страховий поліс R.C.A. (цивільна відповідальність автовласника)',
    },
    '6414': {
      'ru': 'световая сигнализация об опасности (аварийная сигнализация)',
      'uk': 'світлова сигналізація про небезпеку (аварійна сигналізація)',
    },
  };
  final batch8Questions =
      _fixtures('test/fixtures/keyword_batch8_boundary_questions.json');
  const batch8LongTerms = {
    '6006': 'autorizzazione ad esercitarsi alla guida (foglio rosa)',
  };
  const batch8LongGlosses = {
    '6693': {
      'en': 'R.C.A. insurance (motor vehicle liability insurance)',
      'ru':
          'Страхование гражданской ответственности владельцев транспортных средств',
    },
  };
  final batch10Questions =
      _fixtures('test/fixtures/keyword_batch10_boundary_questions.json');
  const batch10EntryCounts = {'5497': 19, '4196': 18, '5568': 16};
  final batch11Questions =
      _fixtures('test/fixtures/keyword_batch11_boundary_questions.json');
  const batch11LongGlosses = {
    '5269': {
      'en': "overtaking in another vehicle's wake (one after another)",
    },
  };
  final batch12Questions =
      _fixtures('test/fixtures/keyword_batch12_boundary_questions.json');
  // 题 6695 的词条 assicurazione R.C.A.：六语释义的长度（zh 较短，其余都在或超过此前的边界）。
  const batch12GlossLengths = {
    'en': 58,
    'ru': 71,
    'uk': 69,
    'pa': 49,
    'ur': 52
  };
  const batch12LongGlosses = {
    '6695': {
      'en': 'R.C.A. insurance (motor vehicle civil liability insurance)',
      'ru':
          'страхование гражданской ответственности владельцев транспортных средств',
      'uk':
          'страхування цивільної відповідальності власників транспортних засобів',
    },
  };
  final batch13Questions =
      _fixtures('test/fixtures/keyword_batch13_boundary_questions.json');
  // 题 6694 的词条 assicurazione R.C.A.：乌尔都语释义 53 个字符；英语、俄语与此前的边界相同。
  const batch13GlossLengths = {'en': 58, 'ru': 71, 'ur': 53};
  const batch13LongGlosses = {
    '6694': {
      'en': 'R.C.A. insurance (motor vehicle civil liability insurance)',
      'ru':
          'Страхование гражданской ответственности владельцев транспортных средств',
    },
  };
  final batch14Questions =
      _fixtures('test/fixtures/keyword_batch14_boundary_questions.json');
  // 题 6696 的意大利语词条：56 个字符，是题干的连续短语。
  const batch14LongTerms = {
    '6696': 'assicurazione per la responsabilità civile auto (R.C.A.)',
  };
  const allLongTerms = {
    ...longTerms,
    ...batch8LongTerms,
    ...batch14LongTerms
  };
  final batch16Questions =
      _fixtures('test/fixtures/keyword_batch16_boundary_questions.json');
  // 题 6676、6677 的词条 polizza di assicurazione R.C.A.：五种语言的释义都比此前的样本长
  // （旁遮普语、乌尔都语为第 17 批补正后的值）。
  const batch16GlossLengths = {
    '6676': {'en': 61, 'ru': 79, 'uk': 77, 'pa': 61, 'ur': 64},
    '6677': {'en': 65, 'ru': 79, 'uk': 77, 'pa': 61, 'ur': 64},
  };
  const batch16LongGlosses = {
    '6676': {
      'en': 'R.C.A. insurance policy (third-party liability car insurance)',
      'ru':
          'страховой полис R.C.A. (страхование гражданской ответственности автовладельцев)',
      'uk':
          'страховий поліс R.C.A. (страхування цивільної відповідальності автовласників)',
      'pa': 'ਆਰ.ਸੀ.ਏ. ਬੀਮਾ ਪਾਲਿਸੀ (ਗੱਡੀ ਨਾਲ ਦੂਜਿਆਂ ਨੂੰ ਹੋਏ ਨੁਕਸਾਨ ਦਾ ਬੀਮਾ)',
      'ur': 'آر سی اے بیمہ پالیسی (گاڑی سے دوسروں کو ہونے والے نقصان کا بیمہ)',
    },
    '6677': {
      'en': 'R.C.A. insurance policy (motor vehicle civil liability insurance)',
      'ru':
          'страховой полис R.C.A. (страхование гражданской ответственности автовладельцев)',
      'uk':
          'страховий поліс R.C.A. (страхування цивільної відповідальності автовласників)',
      'pa': 'ਆਰ.ਸੀ.ਏ. ਬੀਮਾ ਪਾਲਿਸੀ (ਗੱਡੀ ਨਾਲ ਦੂਜਿਆਂ ਨੂੰ ਹੋਏ ਨੁਕਸਾਨ ਦਾ ਬੀਮਾ)',
      'ur': 'آر سی اے بیمہ پالیسی (گاڑی سے دوسروں کو ہونے والے نقصان کا بیمہ)',
    },
  };
  const allLongGlosses = {
    ...longGlosses,
    ...batch8LongGlosses,
    ...batch11LongGlosses,
    ...batch12LongGlosses,
    ...batch13LongGlosses,
    ...batch16LongGlosses
  };
  Question byId(String id) =>
      questions[id] ??
      longTermQuestions[id] ??
      longGlossQuestions[id] ??
      batch8Questions[id] ??
      batch10Questions[id] ??
      batch11Questions[id] ??
      batch12Questions[id] ??
      batch13Questions[id] ??
      batch14Questions[id] ??
      batch16Questions[id]!;
  List<Map<String, dynamic>> stored(Question q) =>
      (jsonDecode(q.keywordsJson!) as List).cast<Map<String, dynamic>>();

  group('Question.getKeyWords', () {
    test('fixture holds the ten pilot questions', () {
      expect(questions.keys.toSet(), expectedCounts.keys.toSet());
    });

    for (final language in UserState.supportedLanguages) {
      test('returns every entry with its own $language meaning', () {
        for (final q in questions.values) {
          final entries = stored(q);
          final result = q.getKeyWords(language);
          expect(result.length, expectedCounts[q.id],
              reason: 'question ${q.id}');
          expect(result.length, entries.length, reason: 'question ${q.id}');
          for (var i = 0; i < entries.length; i++) {
            final where = 'question ${q.id} entry $i';
            expect(result[i]['it'], entries[i]['it'], reason: where);
            expect(result[i][language], isNotEmpty, reason: where);
            // 本语言自己的释义，而不是回退值。
            expect(result[i][language], entries[i][language], reason: where);
            expect(q.translations['it'], isNotNull);
          }
        }
      });
    }

    test('long-term fixture holds the 41- and 47-character Italian terms', () {
      expect(longTermQuestions.keys.toSet(), longTerms.keys.toSet());
      expect(longTerms['5949']!.length, 41);
      expect(longTerms['6659']!.length, 47);
      for (final id in longTerms.keys) {
        expect(stored(longTermQuestions[id]!).map((e) => e['it']),
            contains(longTerms[id]));
      }
    });

    for (final language in UserState.supportedLanguages) {
      test(
          'long-term questions return every entry with its own $language meaning',
          () {
        for (final q in longTermQuestions.values) {
          final entries = stored(q);
          final result = q.getKeyWords(language);
          expect(result.length, entries.length, reason: 'question ${q.id}');
          for (var i = 0; i < entries.length; i++) {
            final where = 'question ${q.id} entry $i';
            expect(result[i]['it'], entries[i]['it'], reason: where);
            expect(result[i][language], isNotEmpty, reason: where);
            expect(result[i][language], entries[i][language], reason: where);
          }
        }
      });
    }

    test('long-gloss fixture holds the 66/63- and 59-character meanings', () {
      expect(longGlossQuestions.keys.toSet(), longGlosses.keys.toSet());
      expect(longGlosses['6674']!['ru']!.length, 66);
      expect(longGlosses['6674']!['uk']!.length, 63);
      expect(longGlosses['6414']!['ru']!.length, 59);
      expect(longGlosses['6414']!['uk']!.length, 59);
      for (final id in longGlosses.keys) {
        final entries = stored(longGlossQuestions[id]!);
        for (final language in longGlosses[id]!.keys) {
          expect(entries.map((e) => e[language]),
              contains(longGlosses[id]![language]),
              reason: '$id $language');
        }
      }
    });

    for (final language in UserState.supportedLanguages) {
      test(
          'long-gloss questions return every entry with its own $language meaning',
          () {
        for (final q in longGlossQuestions.values) {
          final entries = stored(q);
          final result = q.getKeyWords(language);
          expect(result.length, entries.length, reason: 'question ${q.id}');
          for (var i = 0; i < entries.length; i++) {
            final where = 'question ${q.id} entry $i';
            expect(result[i]['it'], entries[i]['it'], reason: where);
            expect(result[i][language], isNotEmpty, reason: where);
            expect(result[i][language], entries[i][language], reason: where);
          }
        }
      });
    }

    test(
        'batch-8 fixture holds the 54-character term and the 71/52-character meanings',
        () {
      expect(batch8Questions.keys.toSet(),
          {...batch8LongTerms.keys, ...batch8LongGlosses.keys});
      expect(batch8LongTerms['6006']!.length, 54);
      expect(batch8LongGlosses['6693']!['ru']!.length, 71);
      expect(batch8LongGlosses['6693']!['en']!.length, 52);
      expect(stored(batch8Questions['6006']!).map((e) => e['it']),
          contains(batch8LongTerms['6006']));
      final entries = stored(batch8Questions['6693']!);
      for (final language in batch8LongGlosses['6693']!.keys) {
        expect(entries.map((e) => e[language]),
            contains(batch8LongGlosses['6693']![language]),
            reason: '6693 $language');
      }
    });

    for (final language in UserState.supportedLanguages) {
      test(
          'batch-8 boundary questions return every entry with its own $language meaning',
          () {
        for (final q in batch8Questions.values) {
          final entries = stored(q);
          final result = q.getKeyWords(language);
          expect(result.length, entries.length, reason: 'question ${q.id}');
          for (var i = 0; i < entries.length; i++) {
            final where = 'question ${q.id} entry $i';
            expect(result[i]['it'], entries[i]['it'], reason: where);
            expect(result[i][language], isNotEmpty, reason: where);
            expect(result[i][language], entries[i][language], reason: where);
          }
        }
      });
    }

    test('batch-10 fixture holds the 19-, 18- and 16-entry questions', () {
      expect(batch10Questions.keys.toSet(), batch10EntryCounts.keys.toSet());
      for (final id in batch10EntryCounts.keys) {
        final entries = stored(batch10Questions[id]!);
        expect(entries.length, batch10EntryCounts[id], reason: 'question $id');
        expect(entries.length, greaterThan(14), reason: 'question $id');
        // 每条都是七个非空栏位，没有为测试删短或拿掉。
        for (final entry in entries) {
          expect(
              entry.keys.toList(), ['it', 'zh', 'en', 'ru', 'uk', 'pa', 'ur'],
              reason: 'question $id ${entry['it']}');
          expect(entry.values.every((v) => (v as String).isNotEmpty), isTrue,
              reason: 'question $id ${entry['it']}');
        }
      }
    });

    for (final language in UserState.supportedLanguages) {
      test(
          'batch-10 many-entry questions return every entry with its own $language meaning',
          () {
        for (final q in batch10Questions.values) {
          final entries = stored(q);
          final result = q.getKeyWords(language);
          expect(result.length, batch10EntryCounts[q.id],
              reason: 'question ${q.id}');
          for (var i = 0; i < entries.length; i++) {
            final where = 'question ${q.id} entry $i';
            expect(result[i]['it'], entries[i]['it'], reason: where);
            expect(result[i][language], isNotEmpty, reason: where);
            expect(result[i][language], entries[i][language], reason: where);
          }
        }
      });
    }

    test('batch-11 fixture holds the 56-character English meaning', () {
      expect(batch11Questions.keys.toSet(), batch11LongGlosses.keys.toSet());
      expect(batch11LongGlosses['5269']!['en']!.length, 56);
      final entries = stored(batch11Questions['5269']!);
      expect(entries.map((e) => e['en']),
          contains(batch11LongGlosses['5269']!['en']));
      for (final entry in entries) {
        expect(entry.keys.toList(), ['it', 'zh', 'en', 'ru', 'uk', 'pa', 'ur'],
            reason: '5269 ${entry['it']}');
        expect(entry.values.every((v) => (v as String).isNotEmpty), isTrue,
            reason: '5269 ${entry['it']}');
      }
    });

    for (final language in UserState.supportedLanguages) {
      test(
          'batch-11 boundary question returns every entry with its own $language meaning',
          () {
        for (final q in batch11Questions.values) {
          final entries = stored(q);
          final result = q.getKeyWords(language);
          expect(result.length, entries.length, reason: 'question ${q.id}');
          for (var i = 0; i < entries.length; i++) {
            final where = 'question ${q.id} entry $i';
            expect(result[i]['it'], entries[i]['it'], reason: where);
            expect(result[i][language], isNotEmpty, reason: where);
            expect(result[i][language], entries[i][language], reason: where);
          }
        }
      });
    }

    test('batch-12 fixture holds the 58/69/49/52-character meanings', () {
      expect(batch12Questions.keys.toSet(), batch12LongGlosses.keys.toSet());
      expect(batch12GlossLengths,
          {'en': 58, 'ru': 71, 'uk': 69, 'pa': 49, 'ur': 52});
      final entries = stored(batch12Questions['6695']!);
      final entry =
          entries.firstWhere((e) => e['it'] == 'assicurazione R.C.A.');
      for (final language in batch12GlossLengths.keys) {
        expect(
            (entry[language] as String).length, batch12GlossLengths[language],
            reason: '6695 $language');
      }
      for (final language in batch12LongGlosses['6695']!.keys) {
        expect(entry[language], batch12LongGlosses['6695']![language],
            reason: '6695 $language');
      }
      for (final e in entries) {
        expect(e.keys.toList(), ['it', 'zh', 'en', 'ru', 'uk', 'pa', 'ur'],
            reason: '6695 ${e['it']}');
        expect(e.values.every((v) => (v as String).isNotEmpty), isTrue,
            reason: '6695 ${e['it']}');
      }
    });

    for (final language in UserState.supportedLanguages) {
      test(
          'batch-12 boundary question returns every entry with its own $language meaning',
          () {
        for (final q in batch12Questions.values) {
          final entries = stored(q);
          final result = q.getKeyWords(language);
          expect(result.length, entries.length, reason: 'question ${q.id}');
          for (var i = 0; i < entries.length; i++) {
            final where = 'question ${q.id} entry $i';
            expect(result[i]['it'], entries[i]['it'], reason: where);
            expect(result[i][language], isNotEmpty, reason: where);
            expect(result[i][language], entries[i][language], reason: where);
          }
        }
      });
    }

    test('batch-13 fixture holds the 53-character Urdu meaning', () {
      expect(batch13Questions.keys.toSet(), batch13LongGlosses.keys.toSet());
      expect(batch13GlossLengths, {'en': 58, 'ru': 71, 'ur': 53});
      final entries = stored(batch13Questions['6694']!);
      final entry =
          entries.firstWhere((e) => e['it'] == 'assicurazione R.C.A.');
      for (final language in batch13GlossLengths.keys) {
        expect(
            (entry[language] as String).length, batch13GlossLengths[language],
            reason: '6694 $language');
      }
      for (final language in batch13LongGlosses['6694']!.keys) {
        expect(entry[language], batch13LongGlosses['6694']![language],
            reason: '6694 $language');
      }
      for (final e in entries) {
        expect(e.keys.toList(), ['it', 'zh', 'en', 'ru', 'uk', 'pa', 'ur'],
            reason: '6694 ${e['it']}');
        expect(e.values.every((v) => (v as String).isNotEmpty), isTrue,
            reason: '6694 ${e['it']}');
      }
    });

    for (final language in UserState.supportedLanguages) {
      test(
          'batch-13 boundary question returns every entry with its own $language meaning',
          () {
        for (final q in batch13Questions.values) {
          final entries = stored(q);
          final result = q.getKeyWords(language);
          expect(result.length, entries.length, reason: 'question ${q.id}');
          for (var i = 0; i < entries.length; i++) {
            final where = 'question ${q.id} entry $i';
            expect(result[i]['it'], entries[i]['it'], reason: where);
            expect(result[i][language], isNotEmpty, reason: where);
            expect(result[i][language], entries[i][language], reason: where);
          }
        }
      });
    }

    test('batch-14 fixture holds the 56-character Italian term', () {
      expect(batch14Questions.keys.toSet(), batch14LongTerms.keys.toSet());
      expect(batch14LongTerms['6696']!.length, 56);
      final question = batch14Questions['6696']!;
      final entries = stored(question);
      expect(entries.map((e) => e['it']), contains(batch14LongTerms['6696']));
      // 题干的连续短语（库中原有写法少了 per la）。
      expect(question.translations['it'], contains(batch14LongTerms['6696']));
      for (final e in entries) {
        expect(e.keys.toList(), ['it', 'zh', 'en', 'ru', 'uk', 'pa', 'ur'],
            reason: '6696 ${e['it']}');
        expect(e.values.every((v) => (v as String).isNotEmpty), isTrue,
            reason: '6696 ${e['it']}');
      }
    });

    for (final language in UserState.supportedLanguages) {
      test(
          'batch-14 boundary question returns every entry with its own $language meaning',
          () {
        for (final q in batch14Questions.values) {
          final entries = stored(q);
          final result = q.getKeyWords(language);
          expect(result.length, entries.length, reason: 'question ${q.id}');
          for (var i = 0; i < entries.length; i++) {
            final where = 'question ${q.id} entry $i';
            expect(result[i]['it'], entries[i]['it'], reason: where);
            expect(result[i][language], isNotEmpty, reason: where);
            expect(result[i][language], entries[i][language], reason: where);
          }
        }
      });
    }

    test('batch-16 fixture holds the long meanings of the R.C.A. policy entry',
        () {
      expect(batch16Questions.keys.toSet(), batch16LongGlosses.keys.toSet());
      expect(batch16GlossLengths.keys.toSet(), batch16LongGlosses.keys.toSet());
      for (final id in batch16LongGlosses.keys) {
        final entries = stored(batch16Questions[id]!);
        final entry = entries
            .firstWhere((e) => e['it'] == 'polizza di assicurazione R.C.A.');
        for (final language in batch16GlossLengths[id]!.keys) {
          expect((entry[language] as String).length,
              batch16GlossLengths[id]![language],
              reason: '$id $language');
          expect(entry[language], batch16LongGlosses[id]![language],
              reason: '$id $language');
        }
        for (final e in entries) {
          expect(e.keys.toList(), ['it', 'zh', 'en', 'ru', 'uk', 'pa', 'ur'],
              reason: '$id ${e['it']}');
          expect(e.values.every((v) => (v as String).isNotEmpty), isTrue,
              reason: '$id ${e['it']}');
        }
      }
    });

    for (final language in UserState.supportedLanguages) {
      test(
          'batch-16 boundary questions return every entry with their own $language meaning',
          () {
        for (final q in batch16Questions.values) {
          final entries = stored(q);
          final result = q.getKeyWords(language);
          expect(result.length, entries.length, reason: 'question ${q.id}');
          for (var i = 0; i < entries.length; i++) {
            final where = 'question ${q.id} entry $i';
            expect(result[i]['it'], entries[i]['it'], reason: where);
            expect(result[i][language], isNotEmpty, reason: where);
            expect(result[i][language], entries[i][language], reason: where);
          }
        }
      });
    }

    test('dosso and cunetta carry the meaning of the warning signs', () {
      Map<String, String> entry(String id, String it, String language) =>
          questions[id]!.getKeyWords(language).firstWhere((e) => e['it'] == it);
      expect(entry('560', 'dosso', 'zh')['zh'], '凸起路段');
      expect(entry('584', 'cunetta', 'zh')['zh'], '凹陷路段');
      for (final language in UserState.supportedLanguages) {
        final dosso = entry('560', 'dosso', language)[language]!;
        final cunetta = entry('584', 'cunetta', language)[language]!;
        for (final wrong in [
          'bump',
          '路拱',
          '减速带',
          'лежач',
          'اسپیڈ',
          'ditch',
          '排水沟',
          'канава',
          'ਖਾਈ',
          'کھائی',
        ]) {
          expect(dosso.contains(wrong), isFalse, reason: '$language $dosso');
          expect(cunetta.contains(wrong), isFalse,
              reason: '$language $cunetta');
        }
      }
    });
  });

  group('vocabulary area of QuestionWidget', () {
    setUpAll(() async {
      await _loadAppFonts();
      // 收藏状态会访问用户进度库；测试中让 path_provider 调用保持挂起。
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (_) => Completer<Object?>().future,
      );
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
              const MethodChannel('flutter_tts'), (_) async => null);
    });

    Future<void> pumpQuestion(
      WidgetTester tester, {
      required String language,
      required Size size,
      required double scale,
      required Question question,
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
            theme: AppTheme.lightTheme(language: language),
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
              ),
            ),
          ),
        ),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump(const Duration(milliseconds: 500));
    }

    // 词汇区里每个词条内部的 Wrap（意大利语词、圆点、释义）。
    final chipFinder = find.byWidgetPredicate(
        (w) => w is Wrap && w.spacing == 6 && w.runSpacing == 2);

    Rect paragraphRect(Element element) {
      final paragraph = element.renderObject as RenderParagraph;
      return paragraph.localToGlobal(Offset.zero) & paragraph.size;
    }

    for (final language in UserState.supportedLanguages) {
      for (final scale in [1.0, 1.5]) {
        for (final id in [
          '4159',
          '4220',
          '116',
          '560',
          '6913',
          ...longTerms.keys,
          ...longGlosses.keys,
          ...batch8Questions.keys,
          ...batch10Questions.keys,
          ...batch11Questions.keys,
          ...batch12Questions.keys,
          ...batch13Questions.keys,
          ...batch14Questions.keys,
          ...batch16Questions.keys
        ]) {
          testWidgets('all entries of $id readable [$language, 320dp, x$scale]',
              (tester) async {
            const size = Size(320, 640);
            final question = byId(id);
            final entries = stored(question);
            await pumpQuestion(tester,
                language: language,
                size: size,
                scale: scale,
                question: question);
            expect(chipFinder, findsNothing);

            await tester.tap(find.byIcon(Icons.translate));
            await tester.pump(const Duration(milliseconds: 400));
            expect(tester.takeException(), isNull);
            expect(
                find.text(
                    AppStrings.getWithLanguage(language, 'key_vocabulary')),
                findsOneWidget);
            expect(Directionality.of(tester.element(chipFinder.first)),
                language == 'ur' ? TextDirection.rtl : TextDirection.ltr);

            final chips = chipFinder.evaluate().toList();
            expect(chips.length, entries.length);
            if (batch10EntryCounts.containsKey(id)) {
              // 多词条题：页面上的词条数就是完整的条数，没有被截掉。
              expect(chips.length, batch10EntryCounts[id]);
            }
            final chipRects = <Rect>[];
            var shownLongGlosses = 0;
            for (var i = 0; i < chips.length; i++) {
              final where = '$id entry $i (${entries[i]['it']})';
              final chip = find.byElementPredicate((e) => e == chips[i]);
              final texts =
                  find.descendant(of: chip, matching: find.byType(RichText));
              final paragraphs = texts.evaluate().toList();
              expect(
                paragraphs
                    .map((e) =>
                        (e.renderObject as RenderParagraph).text.toPlainText())
                    .toList(),
                [entries[i]['it'], '•', entries[i][language]],
                reason: where,
              );

              // 滚到可见位置后，词与释义都在屏幕内，中心点可点到（没有被按钮盖住）。
              await Scrollable.ensureVisible(chips[i], alignment: 0.5);
              await tester.pump();
              for (final element in paragraphs) {
                final paragraph = element.renderObject as RenderParagraph;
                final rect = paragraphRect(element);
                expect(rect.left, greaterThanOrEqualTo(0), reason: where);
                expect(rect.right, lessThanOrEqualTo(size.width),
                    reason: where);
                expect(rect.top, greaterThanOrEqualTo(0), reason: where);
                expect(rect.bottom, lessThanOrEqualTo(size.height),
                    reason: where);
                expect(paragraph.didExceedMaxLines, isFalse, reason: where);
                // 每一行都不比词条宽：没有超出宽度而被截掉的文字。
                final painter = TextPainter(
                  text: paragraph.text,
                  textDirection: paragraph.textDirection,
                  textScaler: paragraph.textScaler,
                  locale: paragraph.locale,
                  strutStyle: paragraph.strutStyle,
                )..layout(maxWidth: paragraph.constraints.maxWidth);
                addTearDown(painter.dispose);
                expect(painter.size, paragraph.size, reason: where);
                final lines = painter.computeLineMetrics();
                expect(lines, isNotEmpty, reason: where);
                if (paragraph.text.toPlainText() == allLongTerms[id]) {
                  // 长词放不进一行：确实换行了，而不是被压缩或截断。
                  expect(lines.length, greaterThan(1), reason: where);
                  expect(paragraph.textDirection, TextDirection.ltr,
                      reason: where);
                }
                final longGloss = allLongGlosses[id]?[language];
                if (longGloss != null &&
                    paragraph.text.toPlainText() == longGloss) {
                  // 长释义完整显示（文字与库中字符串逐字相同），并且换成了多行。
                  expect(lines.length, greaterThan(1), reason: where);
                  shownLongGlosses++;
                }
                for (final line in lines) {
                  expect(
                      line.width, lessThanOrEqualTo(paragraph.size.width + 0.5),
                      reason: '$where line ${line.lineNumber}');
                }
                expect(paragraph.size.height, greaterThan(0), reason: where);
                expect(
                    find.byElementPredicate((e) => e == element).hitTestable(),
                    findsOneWidget,
                    reason: '$where is covered');
              }
              final container = find
                  .ancestor(of: chip, matching: find.byType(Container))
                  .first;
              final chipRect = tester.getRect(container);
              expect(chipRect.left, greaterThanOrEqualTo(0), reason: where);
              expect(chipRect.right, lessThanOrEqualTo(size.width),
                  reason: where);
              // 记录相对内容的位置（与滚动无关），用于检查词条互不重叠。
              final scrollable = Scrollable.of(chips[i]);
              chipRects
                  .add(chipRect.shift(Offset(0, scrollable.position.pixels)));
              expect(tester.takeException(), isNull, reason: where);
            }
            for (var i = 0; i < chipRects.length; i++) {
              for (var j = i + 1; j < chipRects.length; j++) {
                expect(chipRects[i].overlaps(chipRects[j]), isFalse,
                    reason: 'entries $i and $j overlap');
              }
            }
            // 有长释义的语言：那条释义确实被找到并检查过一次。
            expect(shownLongGlosses,
                allLongGlosses[id]?.containsKey(language) == true ? 1 : 0);
          });
        }
      }
    }

    // 意大利语词在乌尔都语（RTL）界面中也按原顺序显示，例如“A.B.S.”的句点仍在末尾。
    for (final id in [
      '6913',
      '4159',
      '4220',
      ...longTerms.keys,
      ...longGlosses.keys,
      ...batch8Questions.keys,
      ...batch10Questions.keys,
      ...batch11Questions.keys,
      ...batch12Questions.keys,
      ...batch13Questions.keys,
      ...batch14Questions.keys,
      ...batch16Questions.keys
    ]) {
      testWidgets('Italian terms of $id keep their reading order in Urdu',
          (tester) async {
        await pumpQuestion(tester,
            language: 'ur',
            size: const Size(320, 640),
            scale: 1.0,
            question: byId(id));
        await tester.tap(find.byIcon(Icons.translate));
        await tester.pump(const Duration(milliseconds: 400));
        final chips = chipFinder.evaluate().toList();
        expect(chips, isNotEmpty);
        for (final chip in chips) {
          final paragraph = find
              .descendant(
                  of: find.byElementPredicate((e) => e == chip),
                  matching: find.byType(RichText))
              .evaluate()
              .first
              .renderObject as RenderParagraph;
          final text = paragraph.text.toPlainText();
          // 整个词都在从左到右的文字段里；RTL 段落会把末尾的句点、括号画到最左边。
          final boxes = paragraph.getBoxesForSelection(
              TextSelection(baseOffset: 0, extentOffset: text.length));
          expect(boxes.every((b) => b.direction == TextDirection.ltr), isTrue,
              reason: '"$text" is drawn out of order in RTL');
          expect(paragraph.textDirection, TextDirection.ltr, reason: text);
        }
      });
    }
  });
}

Map<String, Question> _fixtures(String path) {
  final list = (jsonDecode(File(path).readAsStringSync())
      as Map<String, dynamic>)['questions'] as List;
  return {
    for (final q in list.cast<Map<String, dynamic>>())
      q['id'] as String: Question(
        id: q['id'] as String,
        imageName: q['image_name'] as String?,
        answer: q['answer'] as bool,
        translations: Map<String, String>.from(q['translations'] as Map),
        explanations: const {},
        keywordsJson: q['keywords_json'] as String?,
      ),
  };
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
    final loader = FontLoader('MaterialIcons')
      ..addFont(Future.value(ByteData.sublistView(iconFont.readAsBytesSync())));
    await loader.load();
  }
}
