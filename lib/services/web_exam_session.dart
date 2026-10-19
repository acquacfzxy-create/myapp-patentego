import 'dart:math';

class WebExamQuestionResult {
  const WebExamQuestionResult({
    required this.questionId,
    required this.selectedAnswer,
    required this.correctAnswer,
  });

  final String questionId;
  final bool? selectedAnswer;
  final bool correctAnswer;

  bool get isAnswered => selectedAnswer != null;
  bool get isCorrect => isAnswered && selectedAnswer == correctAnswer;
}

class WebExamResult {
  const WebExamResult({required this.questions});

  final List<WebExamQuestionResult> questions;

  int get totalQuestions => questions.length;
  int get answeredCount => questions.where((item) => item.isAnswered).length;
  int get unansweredCount => totalQuestions - answeredCount;
  int get correctCount => questions.where((item) => item.isCorrect).length;
  int get wrongCount => totalQuestions - correctCount;
  bool get passed => wrongCount <= WebExamSession.maximumWrongAnswers;
}

/// A restorable, platform-neutral 30-question Web exam.
class WebExamSession {
  WebExamSession._({
    required this.actorId,
    required this.dataVersion,
    required this.randomSeed,
    required List<String> questionIds,
    required Map<String, bool> correctAnswers,
    required this.startedAtMs,
    required this.deadlineMs,
    required Map<String, bool> selectedAnswers,
    required int currentIndex,
    required int? submittedAtMs,
  })  : questionIds = List.unmodifiable(questionIds),
        _correctAnswers = Map.unmodifiable(correctAnswers),
        _selectedAnswers = selectedAnswers,
        _currentIndex = currentIndex,
        _submittedAtMs = submittedAtMs;

  static const int storageSchemaVersion = 1;
  static const int questionCount = 30;
  static const int maximumWrongAnswers = 3;
  static const Duration duration = Duration(minutes: 20);

  factory WebExamSession.create({
    required Iterable<String> questionIds,
    required Map<String, bool> correctAnswers,
    required String actorId,
    required int dataVersion,
    required DateTime now,
    int? randomSeed,
  }) {
    _validateIdentity(actorId: actorId, dataVersion: dataVersion);
    final pool = _uniqueQuestionIds(questionIds);
    if (pool.length < questionCount) {
      throw ArgumentError.value(
        pool.length,
        'questionIds',
        'At least $questionCount unique questions are required.',
      );
    }
    _requireCorrectAnswers(pool, correctAnswers);

    final seed = randomSeed ?? now.microsecondsSinceEpoch;
    pool.shuffle(Random(seed));
    final selectedIds = pool.take(questionCount).toList(growable: false);
    final selectedCorrectAnswers = {
      for (final id in selectedIds) id: correctAnswers[id]!,
    };
    final startedAtMs = now.millisecondsSinceEpoch;
    return WebExamSession._(
      actorId: actorId,
      dataVersion: dataVersion,
      randomSeed: seed,
      questionIds: selectedIds,
      correctAnswers: selectedCorrectAnswers,
      startedAtMs: startedAtMs,
      deadlineMs: startedAtMs + duration.inMilliseconds,
      selectedAnswers: {},
      currentIndex: 0,
      submittedAtMs: null,
    );
  }

  factory WebExamSession.fromMap(
    Map<String, dynamic> map, {
    required String expectedActorId,
    required int expectedDataVersion,
    required Map<String, bool> correctAnswers,
  }) {
    if (_asInt(map['schema_version']) != storageSchemaVersion) {
      throw const FormatException('Unsupported exam session schema.');
    }
    if (map['actor_id']?.toString() != expectedActorId) {
      throw const FormatException('Exam session belongs to another actor.');
    }
    if (_asInt(map['data_version']) != expectedDataVersion) {
      throw const FormatException('Exam session data version is stale.');
    }
    _validateIdentity(
      actorId: expectedActorId,
      dataVersion: expectedDataVersion,
    );

    final rawQuestionIds = map['question_ids'];
    if (rawQuestionIds is! List) {
      throw const FormatException('Exam question order is missing.');
    }
    final ids = rawQuestionIds.map((item) => item.toString()).toList();
    if (ids.length != questionCount || ids.toSet().length != questionCount) {
      throw const FormatException(
        'Exam must contain exactly 30 unique questions.',
      );
    }
    _requireCorrectAnswers(ids, correctAnswers, formatError: true);

    final startedAtMs = _requiredInt(map, 'started_at_ms');
    final deadlineMs = _requiredInt(map, 'deadline_ms');
    if (deadlineMs - startedAtMs != duration.inMilliseconds) {
      throw const FormatException('Exam deadline is invalid.');
    }
    final currentIndex = _requiredInt(map, 'current_index');
    if (currentIndex < 0 || currentIndex >= questionCount) {
      throw const FormatException('Exam current index is invalid.');
    }

    final rawSelectedAnswers = map['selected_answers'];
    if (rawSelectedAnswers is! Map) {
      throw const FormatException('Exam selected answers are invalid.');
    }
    final selectedAnswers = <String, bool>{};
    for (final entry in rawSelectedAnswers.entries) {
      final id = entry.key.toString();
      if (!ids.contains(id) || entry.value is! bool) {
        throw const FormatException('Exam contains an invalid answer.');
      }
      selectedAnswers[id] = entry.value as bool;
    }

    final rawSubmittedAtMs = map['submitted_at_ms'];
    final submittedAtMs =
        rawSubmittedAtMs == null ? null : _strictInt(rawSubmittedAtMs);
    if (rawSubmittedAtMs != null && submittedAtMs == null) {
      throw const FormatException('Exam submission time is invalid.');
    }

    return WebExamSession._(
      actorId: expectedActorId,
      dataVersion: expectedDataVersion,
      randomSeed: _requiredInt(map, 'random_seed'),
      questionIds: ids,
      correctAnswers: {for (final id in ids) id: correctAnswers[id]!},
      startedAtMs: startedAtMs,
      deadlineMs: deadlineMs,
      selectedAnswers: selectedAnswers,
      currentIndex: currentIndex,
      submittedAtMs: submittedAtMs,
    );
  }

  static WebExamSession? tryRestore(
    Map<String, dynamic>? map, {
    required String expectedActorId,
    required int expectedDataVersion,
    required Map<String, bool> correctAnswers,
  }) {
    if (map == null) return null;
    try {
      return WebExamSession.fromMap(
        map,
        expectedActorId: expectedActorId,
        expectedDataVersion: expectedDataVersion,
        correctAnswers: correctAnswers,
      );
    } on FormatException {
      return null;
    } on ArgumentError {
      return null;
    }
  }

  final String actorId;
  final int dataVersion;
  final int randomSeed;
  final List<String> questionIds;
  final Map<String, bool> _correctAnswers;
  final Map<String, bool> _selectedAnswers;
  final int startedAtMs;
  final int deadlineMs;
  int _currentIndex;
  int? _submittedAtMs;

  int get currentIndex => _currentIndex;
  String get currentQuestionId => questionIds[_currentIndex];
  Map<String, bool> get selectedAnswers => Map.unmodifiable(_selectedAnswers);
  bool? answerFor(String questionId) => _selectedAnswers[questionId];
  int get answeredCount => _selectedAnswers.length;
  int get unansweredCount => questionCount - answeredCount;
  bool get isSubmitted => _submittedAtMs != null;
  int? get submittedAtMs => _submittedAtMs;

  int remainingSeconds(DateTime now) {
    final remainingMs = deadlineMs - now.millisecondsSinceEpoch;
    if (remainingMs <= 0) return 0;
    final seconds = (remainingMs + 999) ~/ 1000;
    return min(duration.inSeconds, seconds);
  }

  bool isExpired(DateTime now) => remainingSeconds(now) == 0;
  bool canChangeAnswers(DateTime now) => !isSubmitted && !isExpired(now);

  void selectAnswer(String questionId, bool answer, {required DateTime now}) {
    if (!questionIds.contains(questionId)) {
      throw ArgumentError.value(questionId, 'questionId', 'Not in this exam.');
    }
    if (isSubmitted) {
      throw StateError('This exam has already been submitted.');
    }
    if (isExpired(now)) {
      throw StateError('The exam deadline has passed.');
    }
    _selectedAnswers[questionId] = answer;
  }

  void selectCurrentAnswer(bool answer, {required DateTime now}) {
    selectAnswer(currentQuestionId, answer, now: now);
  }

  void goToIndex(int index) {
    if (index < 0 || index >= questionCount) {
      throw RangeError.range(index, 0, questionCount - 1, 'index');
    }
    _currentIndex = index;
  }

  bool movePrevious() {
    if (_currentIndex == 0) return false;
    _currentIndex--;
    return true;
  }

  bool moveNext() {
    if (_currentIndex == questionCount - 1) return false;
    _currentIndex++;
    return true;
  }

  WebExamResult submit({required DateTime now}) {
    _submittedAtMs ??= now.millisecondsSinceEpoch;
    return result!;
  }

  WebExamResult? get result {
    if (!isSubmitted) return null;
    return WebExamResult(
      questions: List.unmodifiable(
        questionIds.map(
          (id) => WebExamQuestionResult(
            questionId: id,
            selectedAnswer: _selectedAnswers[id],
            correctAnswer: _correctAnswers[id]!,
          ),
        ),
      ),
    );
  }

  Map<String, dynamic> toMap() => {
        'schema_version': storageSchemaVersion,
        'data_version': dataVersion,
        'actor_id': actorId,
        'random_seed': randomSeed,
        'question_ids': List<String>.from(questionIds),
        'selected_answers': Map<String, bool>.from(_selectedAnswers),
        'started_at_ms': startedAtMs,
        'deadline_ms': deadlineMs,
        'current_index': _currentIndex,
        'submitted_at_ms': _submittedAtMs,
      };
}

List<String> _uniqueQuestionIds(Iterable<String> source) {
  final seen = <String>{};
  final result = <String>[];
  for (final rawId in source) {
    final id = rawId.trim();
    if (id.isNotEmpty && seen.add(id)) result.add(id);
  }
  return result;
}

void _validateIdentity({required String actorId, required int dataVersion}) {
  if (actorId.trim().isEmpty) {
    throw ArgumentError.value(actorId, 'actorId', 'Must not be empty.');
  }
  if (dataVersion <= 0) {
    throw ArgumentError.value(dataVersion, 'dataVersion', 'Must be positive.');
  }
}

void _requireCorrectAnswers(
  Iterable<String> questionIds,
  Map<String, bool> correctAnswers, {
  bool formatError = false,
}) {
  for (final id in questionIds) {
    if (!correctAnswers.containsKey(id)) {
      if (formatError) {
        throw FormatException('Correct answer is unavailable for $id.');
      }
      throw ArgumentError('Correct answer is unavailable for $id.');
    }
  }
}

int _requiredInt(Map<String, dynamic> map, String key) {
  final value = _strictInt(map[key]);
  if (value == null) throw FormatException('Exam $key is invalid.');
  return value;
}

int _asInt(Object? value) => _strictInt(value) ?? -1;

int? _strictInt(Object? value) {
  if (value is int) return value;
  if (value is num && value.isFinite && value == value.roundToDouble()) {
    return value.toInt();
  }
  return int.tryParse(value?.toString() ?? '');
}
