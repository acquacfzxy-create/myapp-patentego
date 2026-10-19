import '../models/question.dart';

/// Lightweight index for the immutable, versioned question-bank assets.
class QuestionBankMetadata {
  const QuestionBankMetadata({
    required this.schemaVersion,
    required this.dataVersion,
    required this.languages,
    required this.totalQuestionCount,
    required this.chapterCounts,
    required this.unclassifiedCount,
    required this.questionChapters,
  });

  final int schemaVersion;
  final int dataVersion;
  final List<String> languages;
  final int totalQuestionCount;
  final Map<int, int> chapterCounts;
  final int unclassifiedCount;

  /// A null value means that the question is not assigned to a chapter.
  final Map<String, int?> questionChapters;

  List<int> get availableChapters => chapterCounts.keys.toList(growable: false);

  bool containsQuestion(String id) => questionChapters.containsKey(id);

  int? chapterForQuestion(String id) => questionChapters[id];
}

/// Platform-neutral read API for the immutable driving-theory question bank.
abstract interface class QuestionRepository {
  bool get isInitialized;

  Future<void> initialize();

  Future<QuestionBankMetadata> getMetadata();

  Future<List<String>> getAllQuestionIds();

  Future<List<Question>> getQuestionsByChapter(
    int chapter, {
    String? language,
  });

  Future<List<Question>> getUnclassifiedQuestions({String? language});

  /// Explicitly loads every chapter bundle. Prefer narrower queries on Web.
  Future<List<Question>> getAllQuestions({String? language});

  Future<Question?> getQuestionById(
    String id, {
    String? language,
  });

  /// Selects unique IDs from the manifest before loading only required bundles.
  ///
  /// With neither [chapter] nor [unclassifiedOnly], samples the whole bank.
  Future<List<Question>> getRandomQuestions(
    int count, {
    int? chapter,
    bool unclassifiedOnly = false,
    bool includeUnclassified = true,
    String? language,
    int? seed,
  });
}
