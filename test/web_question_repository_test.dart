import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lingua_patente/repositories/web_question_repository.dart';

void main() {
  group('WebQuestionRepository', () {
    test('initialize loads only manifest and exposes complete metadata',
        () async {
      final assets = _MemoryAssetBundle(_validAssets);
      final repository = WebQuestionRepository(bundle: assets);

      await repository.initialize();
      final metadata = await repository.getMetadata();

      expect(assets.loadedKeys, ['assets/web/questions/manifest.json']);
      expect(repository.isInitialized, isTrue);
      expect(repository.questionCount, 4);
      expect(repository.loadedQuestionCount, 0);
      expect(repository.supportedLanguages, ['it', 'zh', 'en']);
      expect(metadata.dataVersion, 12);
      expect(metadata.chapterCounts, {1: 2, 2: 1});
      expect(metadata.unclassifiedCount, 1);
      expect(await repository.getAllQuestionIds(), ['5', '6', '7', '8']);
    });

    test('loads and caches one chapter with requested language', () async {
      final assets = _MemoryAssetBundle(_validAssets);
      final repository = WebQuestionRepository(bundle: assets);

      final questions =
          await repository.getQuestionsByChapter(1, language: 'zh');
      await repository.getQuestionsByChapter(1, language: 'en');

      expect(questions, hasLength(2));
      expect(questions.first.id, '5');
      expect(questions.first.translations, {
        'it': 'Domanda italiana 5',
        'zh': '中文题目 5',
      });
      expect(questions.first.explanations, {
        'zh': '{"detailed_description":"说明 5"}',
      });
      expect(repository.loadedQuestionCount, 2);
      expect(
        assets.loadedKeys.where((key) => key.endsWith('chapter_01.json')),
        hasLength(1),
      );
    });

    test('loads unclassified questions as a first-class selection', () async {
      final repository = WebQuestionRepository(
        bundle: _MemoryAssetBundle(_validAssets),
      );

      final questions = await repository.getUnclassifiedQuestions();

      expect(questions.single.id, '8');
      expect(questions.single.chapter, isNull);
    });

    test('finds a question by manifest id and avoids loading for unknown id',
        () async {
      final assets = _MemoryAssetBundle(_validAssets);
      final repository = WebQuestionRepository(bundle: assets);

      final question = await repository.getQuestionById('7', language: 'en');
      final loadCount = assets.loadedKeys.length;

      expect(question?.translations['en'], 'English question 7');
      expect(await repository.getQuestionById('missing'), isNull);
      expect(assets.loadedKeys, hasLength(loadCount));
      expect(repository.loadedQuestionCount, 1);
    });

    test('random selection is unique and loads only involved bundles',
        () async {
      final assets = _MemoryAssetBundle(_validAssets);
      final repository = WebQuestionRepository(bundle: assets);

      final questions = await repository.getRandomQuestions(2, seed: 19);

      expect(questions.map((question) => question.id).toSet(), hasLength(2));
      final loadedBundleCount = assets.loadedKeys
          .where((key) => key != 'assets/web/questions/manifest.json')
          .length;
      expect(loadedBundleCount, questions.map((q) => q.chapter).toSet().length);
    });

    test('random selection supports chapter and unclassified filters',
        () async {
      final repository = WebQuestionRepository(
        bundle: _MemoryAssetBundle(_validAssets),
      );

      final chapter = await repository.getRandomQuestions(99, chapter: 1);
      final unclassified = await repository.getRandomQuestions(
        99,
        unclassifiedOnly: true,
      );

      expect(chapter.map((question) => question.id).toSet(), {'5', '6'});
      expect(unclassified.single.id, '8');
    });

    test('explicit all query loads every bundle', () async {
      final repository = WebQuestionRepository(
        bundle: _MemoryAssetBundle(_validAssets),
      );

      final questions = await repository.getAllQuestions(language: 'it');

      expect(questions, hasLength(4));
      expect(repository.loadedQuestionCount, 4);
    });

    test('rejects a mismatched manifest total', () async {
      final assets = Map<String, String>.from(_validAssets);
      final decoded =
          jsonDecode(assets[_manifestPath]!) as Map<String, dynamic>;
      decoded['total_question_count'] = 99;
      assets[_manifestPath] = jsonEncode(decoded);
      final repository = WebQuestionRepository(
        bundle: _MemoryAssetBundle(assets),
      );

      expect(repository.initialize, throwsFormatException);
    });

    test('rejects duplicate question ids inside a bundle', () async {
      final assets = Map<String, String>.from(_validAssets);
      final decoded =
          jsonDecode(assets[_chapter1Path]!) as Map<String, dynamic>;
      final questions = decoded['questions'] as List<dynamic>;
      (questions[1] as Map<String, dynamic>)['id'] = '5';
      assets[_chapter1Path] = jsonEncode(decoded);
      final repository = WebQuestionRepository(
        bundle: _MemoryAssetBundle(assets),
      );

      expect(
        () => repository.getQuestionsByChapter(1),
        throwsFormatException,
      );
    });
  });
}

class _MemoryAssetBundle extends CachingAssetBundle {
  _MemoryAssetBundle(this.assets);

  final Map<String, String> assets;
  final List<String> loadedKeys = [];

  @override
  Future<ByteData> load(String key) async {
    loadedKeys.add(key);
    final source = assets[key];
    if (source == null) throw StateError('Missing test asset: $key');
    final bytes = Uint8List.fromList(utf8.encode(source));
    return bytes.buffer.asByteData();
  }
}

const _manifestPath = 'assets/web/questions/manifest.json';
const _chapter1Path = 'assets/web/questions/chapter_01.json';

final _validAssets = <String, String>{
  _manifestPath: '''
{
  "schema_version": 1,
  "data_version": 12,
  "languages": ["it", "zh", "en"],
  "total_question_count": 4,
  "chapter_counts": {"1": 2, "2": 1, "unclassified": 1},
  "bundles": {
    "1": "chapter_01.json",
    "2": "chapter_02.json",
    "unclassified": "unclassified.json"
  },
  "question_chapters": {"5": 1, "6": 1, "7": 2, "8": null}
}
''',
  _chapter1Path: _bundle(1, [
    _question('5', 1),
    _question('6', 1),
  ]),
  'assets/web/questions/chapter_02.json': _bundle(2, [
    _question('7', 2),
  ]),
  'assets/web/questions/unclassified.json': _bundle(null, [
    _question('8', null),
  ]),
};

String _bundle(int? chapter, List<Map<String, Object?>> questions) =>
    jsonEncode({
      'schema_version': 1,
      'chapter': chapter,
      'languages': ['it', 'zh', 'en'],
      'question_count': questions.length,
      'questions': questions,
    });

Map<String, Object?> _question(String id, int? chapter) => {
      'id': id,
      'image_name': null,
      'answer': id == '6',
      'chapter': chapter,
      'keywords_json': null,
      'translations': {
        'it': 'Domanda italiana $id',
        'zh': '中文题目 $id',
        'en': 'English question $id',
      },
      'explanations': {
        'zh': '{"detailed_description":"说明 $id"}',
        'en': 'English explanation $id',
      },
    };
