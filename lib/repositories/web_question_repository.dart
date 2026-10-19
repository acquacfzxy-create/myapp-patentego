import 'dart:convert';
import 'dart:math';

import 'package:flutter/services.dart';

import '../models/question.dart';
import 'question_repository.dart';

/// Loads a small manifest first, then caches chapter bundles on demand.
class WebQuestionRepository implements QuestionRepository {
  WebQuestionRepository({
    AssetBundle? bundle,
    this.manifestPath = 'assets/web/questions/manifest.json',
  }) : _bundle = bundle ?? rootBundle;

  final AssetBundle _bundle;
  final String manifestPath;

  QuestionBankMetadata? _metadata;
  Map<int?, String> _bundleNames = const {};
  final Map<int?, Future<List<Question>>> _chapterLoads = {};
  final Map<String, Question> _loadedQuestionsById = {};

  @override
  bool get isInitialized => _metadata != null;

  List<String> get supportedLanguages => _metadata?.languages ?? const [];

  /// Total bank size from the manifest, not just the currently cached bundles.
  int get questionCount => _metadata?.totalQuestionCount ?? 0;

  int get loadedQuestionCount => _loadedQuestionsById.length;

  @override
  Future<void> initialize() async {
    if (isInitialized) return;
    final source = await _bundle.loadString(manifestPath);
    _loadManifest(jsonDecode(source));
  }

  @override
  Future<QuestionBankMetadata> getMetadata() async {
    await initialize();
    return _metadata!;
  }

  @override
  Future<List<String>> getAllQuestionIds() async {
    final metadata = await getMetadata();
    return List.unmodifiable(metadata.questionChapters.keys);
  }

  @override
  Future<List<Question>> getQuestionsByChapter(
    int chapter, {
    String? language,
  }) async {
    if (chapter <= 0) {
      throw ArgumentError.value(
          chapter, 'chapter', 'must be greater than zero');
    }
    await initialize();
    if (!_bundleNames.containsKey(chapter)) return const [];
    return _localized(await _loadChapter(chapter), language);
  }

  @override
  Future<List<Question>> getUnclassifiedQuestions({String? language}) async {
    await initialize();
    if (!_bundleNames.containsKey(null)) return const [];
    return _localized(await _loadChapter(null), language);
  }

  @override
  Future<List<Question>> getAllQuestions({String? language}) async {
    final metadata = await getMetadata();
    final questions = <Question>[];
    for (final chapter in metadata.availableChapters) {
      questions.addAll(await _loadChapter(chapter));
    }
    if (metadata.unclassifiedCount > 0) {
      questions.addAll(await _loadChapter(null));
    }
    return _localized(questions, language);
  }

  @override
  Future<Question?> getQuestionById(
    String id, {
    String? language,
  }) async {
    final metadata = await getMetadata();
    if (!metadata.containsQuestion(id)) return null;
    final chapter = metadata.chapterForQuestion(id);
    await _loadChapter(chapter);
    final question = _loadedQuestionsById[id];
    if (question == null) {
      throw FormatException('Manifest points to a missing question: $id');
    }
    return _forLanguage(question, language);
  }

  @override
  Future<List<Question>> getRandomQuestions(
    int count, {
    int? chapter,
    bool unclassifiedOnly = false,
    bool includeUnclassified = true,
    String? language,
    int? seed,
  }) async {
    if (count < 0) {
      throw ArgumentError.value(count, 'count', 'must not be negative');
    }
    if (chapter != null && chapter <= 0) {
      throw ArgumentError.value(
          chapter, 'chapter', 'must be greater than zero');
    }
    if (chapter != null && unclassifiedOnly) {
      throw ArgumentError(
        'chapter and unclassifiedOnly cannot both be selected',
      );
    }
    if (count == 0) return const [];

    final metadata = await getMetadata();
    final candidates = metadata.questionChapters.entries
        .where((entry) {
          if (unclassifiedOnly) return entry.value == null;
          if (chapter != null) return entry.value == chapter;
          return includeUnclassified || entry.value != null;
        })
        .map((entry) => entry.key)
        .toList();
    candidates.shuffle(seed == null ? Random() : Random(seed));
    final selected = candidates.take(min(count, candidates.length)).toList();

    final requiredChapters =
        selected.map((id) => metadata.chapterForQuestion(id)).toSet();
    await Future.wait(requiredChapters.map(_loadChapter));

    return selected.map((id) {
      final question = _loadedQuestionsById[id];
      if (question == null) {
        throw FormatException('Manifest points to a missing question: $id');
      }
      return _forLanguage(question, language);
    }).toList(growable: false);
  }

  void _loadManifest(Object? decoded) {
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Question manifest root must be an object.');
    }
    if (decoded['schema_version'] != 1) {
      throw FormatException(
        'Unsupported question manifest schema: ${decoded['schema_version']}',
      );
    }

    final dataVersion = decoded['data_version'];
    final totalQuestionCount = decoded['total_question_count'];
    final rawLanguages = decoded['languages'];
    final rawCounts = decoded['chapter_counts'];
    final rawBundles = decoded['bundles'];
    final rawQuestionChapters = decoded['question_chapters'];
    if (dataVersion is! int || dataVersion <= 0) {
      throw const FormatException('Manifest data_version must be positive.');
    }
    if (totalQuestionCount is! int || totalQuestionCount < 0) {
      throw const FormatException('Manifest total count must not be negative.');
    }
    if (rawLanguages is! List ||
        rawCounts is! Map ||
        rawBundles is! Map ||
        rawQuestionChapters is! Map) {
      throw const FormatException(
          'Question manifest is missing required maps.');
    }

    final languages = rawLanguages.map((value) => value.toString()).toList();
    if (!languages.contains('it')) {
      throw const FormatException('Question manifest must contain Italian.');
    }

    final chapterCounts = <int, int>{};
    var unclassifiedCount = 0;
    for (final entry in rawCounts.entries) {
      final key = entry.key.toString();
      final count = entry.value;
      if (count is! int || count < 0) {
        throw FormatException('Invalid chapter count: $key');
      }
      if (key == 'unclassified') {
        unclassifiedCount = count;
        continue;
      }
      final chapter = int.tryParse(key);
      if (chapter == null || chapter <= 0) {
        throw FormatException('Invalid chapter key: $key');
      }
      chapterCounts[chapter] = count;
    }
    final sortedCounts = Map<int, int>.fromEntries(
      chapterCounts.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
    );

    final bundleNames = <int?, String>{};
    for (final entry in rawBundles.entries) {
      final key = entry.key.toString();
      final filename = entry.value?.toString() ?? '';
      if (filename.isEmpty || filename.contains('..')) {
        throw FormatException('Invalid bundle name for chapter $key.');
      }
      if (key == 'unclassified') {
        bundleNames[null] = filename;
        continue;
      }
      final chapter = int.tryParse(key);
      if (chapter == null || chapter <= 0) {
        throw FormatException('Invalid bundle chapter: $key');
      }
      bundleNames[chapter] = filename;
    }

    final questionChapters = <String, int?>{};
    final actualCounts = <int?, int>{};
    for (final entry in rawQuestionChapters.entries) {
      final id = entry.key.toString();
      final rawChapter = entry.value;
      if (id.isEmpty || (rawChapter != null && rawChapter is! int)) {
        throw FormatException('Invalid question index entry: $id');
      }
      final chapter = rawChapter as int?;
      if (chapter != null && chapter <= 0) {
        throw FormatException('Invalid question chapter for $id.');
      }
      questionChapters[id] = chapter;
      actualCounts[chapter] = (actualCounts[chapter] ?? 0) + 1;
    }

    if (questionChapters.length != totalQuestionCount) {
      throw const FormatException('Manifest total count does not match index.');
    }
    if (sortedCounts.values.fold<int>(0, (sum, count) => sum + count) +
            unclassifiedCount !=
        totalQuestionCount) {
      throw const FormatException(
          'Manifest chapter counts do not match total.');
    }
    for (final entry in sortedCounts.entries) {
      if (actualCounts[entry.key] != entry.value ||
          !bundleNames.containsKey(entry.key)) {
        throw FormatException('Manifest chapter ${entry.key} is inconsistent.');
      }
    }
    if (actualCounts[null] != unclassifiedCount ||
        (unclassifiedCount > 0 && !bundleNames.containsKey(null))) {
      throw const FormatException(
          'Unclassified question index is inconsistent.');
    }

    _bundleNames = Map.unmodifiable(bundleNames);
    _metadata = QuestionBankMetadata(
      schemaVersion: 1,
      dataVersion: dataVersion,
      languages: List.unmodifiable(languages),
      totalQuestionCount: totalQuestionCount,
      chapterCounts: Map.unmodifiable(sortedCounts),
      unclassifiedCount: unclassifiedCount,
      questionChapters: Map.unmodifiable(questionChapters),
    );
  }

  Future<List<Question>> _loadChapter(int? chapter) {
    final existing = _chapterLoads[chapter];
    if (existing != null) return existing;
    final load = _loadChapterAsset(chapter);
    _chapterLoads[chapter] = load;
    return load;
  }

  Future<List<Question>> _loadChapterAsset(int? chapter) async {
    final filename = _bundleNames[chapter];
    if (filename == null) {
      throw FormatException('Manifest has no bundle for chapter $chapter.');
    }
    final separator = manifestPath.lastIndexOf('/');
    final directory = separator < 0 ? '' : manifestPath.substring(0, separator);
    final path = directory.isEmpty ? filename : '$directory/$filename';
    final source = await _bundle.loadString(path);
    final decoded = jsonDecode(source);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Question bundle root must be an object.');
    }
    if (decoded['schema_version'] != 1) {
      throw FormatException(
        'Unsupported question bundle schema: ${decoded['schema_version']}',
      );
    }
    if (decoded['chapter'] != chapter) {
      throw FormatException('Question bundle chapter does not match $chapter.');
    }

    final rawLanguages = decoded['languages'];
    final rawQuestions = decoded['questions'];
    final declaredQuestionCount = decoded['question_count'];
    if (rawLanguages is! List || rawQuestions is! List) {
      throw const FormatException(
        'Question bundle must contain languages and questions arrays.',
      );
    }
    if (rawLanguages.map((value) => value.toString()).toList().join(',') !=
        supportedLanguages.join(',')) {
      throw const FormatException(
          'Question bundle languages do not match manifest.');
    }
    final expectedCount = chapter == null
        ? _metadata!.unclassifiedCount
        : _metadata!.chapterCounts[chapter];
    if (declaredQuestionCount is! int ||
        declaredQuestionCount != rawQuestions.length ||
        declaredQuestionCount != expectedCount) {
      throw const FormatException('Question bundle count does not match data.');
    }

    final questions = rawQuestions.map(_parseQuestion).toList(growable: false);
    final localIds = <String>{};
    for (final question in questions) {
      if (!localIds.add(question.id)) {
        throw FormatException('Duplicate question id: ${question.id}');
      }
      if (!_metadata!.containsQuestion(question.id) ||
          _metadata!.chapterForQuestion(question.id) != chapter) {
        throw FormatException(
          'Question ${question.id} does not match the manifest.',
        );
      }
      final previous = _loadedQuestionsById[question.id];
      if (previous != null && previous.chapter != question.chapter) {
        throw FormatException(
            'Question ${question.id} appears in two bundles.');
      }
      _loadedQuestionsById[question.id] = question;
    }
    return List.unmodifiable(questions);
  }

  Question _parseQuestion(Object? rawQuestion) {
    if (rawQuestion is! Map<String, dynamic>) {
      throw const FormatException('Question entry must be an object.');
    }

    final id = rawQuestion['id']?.toString() ?? '';
    final chapter = rawQuestion['chapter'];
    final answer = rawQuestion['answer'];
    if (id.isEmpty || (chapter != null && chapter is! int) || answer is! bool) {
      throw FormatException('Invalid question entry: $id');
    }

    final translations = _stringMap(rawQuestion['translations']);
    final explanations = _stringMap(rawQuestion['explanations']);
    for (final language in supportedLanguages) {
      if ((translations[language] ?? '').trim().isEmpty) {
        throw FormatException('Question $id is missing $language text.');
      }
      if (language != 'it' && (explanations[language] ?? '').trim().isEmpty) {
        throw FormatException('Question $id is missing $language explanation.');
      }
    }

    return Question(
      id: id,
      imageName: rawQuestion['image_name']?.toString(),
      answer: answer,
      translations: Map.unmodifiable(translations),
      explanations: Map.unmodifiable(explanations),
      chapter: chapter as int?,
      keywordsJson: rawQuestion['keywords_json']?.toString(),
    );
  }

  Map<String, String> _stringMap(Object? value) {
    if (value is! Map) return const {};
    return value.map(
      (key, item) => MapEntry(key.toString(), item?.toString() ?? ''),
    );
  }

  List<Question> _localized(List<Question> questions, String? language) =>
      questions
          .map((question) => _forLanguage(question, language))
          .toList(growable: false);

  Question _forLanguage(Question question, String? language) {
    if (language == null) return question;

    Map<String, String> select(Map<String, String> source) {
      return {
        if (source.containsKey('it')) 'it': source['it']!,
        if (language != 'it' && source.containsKey(language))
          language: source[language]!,
      };
    }

    return Question(
      id: question.id,
      imageName: question.imageName,
      answer: question.answer,
      translations: Map.unmodifiable(select(question.translations)),
      explanations: Map.unmodifiable(select(question.explanations)),
      chapter: question.chapter,
      keywordsJson: question.keywordsJson,
    );
  }
}
