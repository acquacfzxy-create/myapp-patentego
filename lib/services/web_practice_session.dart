import 'dart:math';

import '../models/web_practice_mode.dart';

class WebPracticeAnswer {
  const WebPracticeAnswer({
    required this.questionId,
    required this.isCorrect,
    required this.becameMastered,
    required this.mistakeResolved,
  });

  final String questionId;
  final bool isCorrect;
  final bool becameMastered;
  final bool mistakeResolved;
}

class WebPracticeStats {
  const WebPracticeStats({
    required this.totalQuestions,
    required this.answeredCount,
    required this.correctCount,
    required this.newlyMasteredCount,
    required this.mistakesResolvedCount,
  });

  final int totalQuestions;
  final int answeredCount;
  final int correctCount;
  final int newlyMasteredCount;
  final int mistakesResolvedCount;

  int get wrongCount => answeredCount - correctCount;
  int get remainingCount => totalQuestions - answeredCount;
  bool get isComplete => totalQuestions > 0 && remainingCount == 0;
  double get accuracy => answeredCount == 0 ? 0 : correctCount / answeredCount;
}

/// The synchronous state machine behind a Web practice page.
///
/// Persistence and the 800 ms feedback delay intentionally stay in the UI.
/// This object owns the stable question order, one-answer rule and session
/// statistics only.
class WebPracticeSession {
  WebPracticeSession._({
    required this.mode,
    required this.actorId,
    required this.dataVersion,
    required List<String> questionIds,
    required this.randomSeed,
  })  : questionIds = List.unmodifiable(questionIds),
        _currentIndex = questionIds.isEmpty ? -1 : 0;

  factory WebPracticeSession.create({
    required WebPracticeMode mode,
    required Iterable<String> questionIds,
    required String actorId,
    required int dataVersion,
    int? randomSeed,
  }) {
    _validateIdentity(actorId: actorId, dataVersion: dataVersion);
    final uniqueIds = _uniqueQuestionIds(questionIds);
    final seed = randomSeed ?? DateTime.now().microsecondsSinceEpoch;
    if (mode == WebPracticeMode.random) {
      uniqueIds.shuffle(Random(seed));
    }
    return WebPracticeSession._(
      mode: mode,
      actorId: actorId,
      dataVersion: dataVersion,
      questionIds: uniqueIds,
      randomSeed: seed,
    );
  }

  final WebPracticeMode mode;
  final String actorId;
  final int dataVersion;
  final List<String> questionIds;
  final int randomSeed;
  final Map<String, WebPracticeAnswer> _answers = {};
  int _currentIndex;

  int get currentIndex => _currentIndex;
  String? get currentQuestionId =>
      _currentIndex < 0 ? null : questionIds[_currentIndex];
  Map<String, WebPracticeAnswer> get answers => Map.unmodifiable(_answers);
  bool get hasQuestions => questionIds.isNotEmpty;
  bool get hasPrevious => _currentIndex > 0;
  bool get hasNext =>
      _currentIndex >= 0 && _currentIndex < questionIds.length - 1;
  bool get isCurrentAnswered {
    final id = currentQuestionId;
    return id != null && _answers.containsKey(id);
  }

  WebPracticeStats get stats {
    final values = _answers.values;
    return WebPracticeStats(
      totalQuestions: questionIds.length,
      answeredCount: values.length,
      correctCount: values.where((answer) => answer.isCorrect).length,
      newlyMasteredCount:
          values.where((answer) => answer.becameMastered).length,
      mistakesResolvedCount:
          values.where((answer) => answer.mistakeResolved).length,
    );
  }

  WebPracticeAnswerResult answerCurrent({
    required bool isCorrect,
    bool becameMastered = false,
    bool mistakeResolved = false,
  }) {
    final questionId = currentQuestionId;
    if (questionId == null) {
      throw StateError('Cannot answer an empty practice session.');
    }
    if (_answers.containsKey(questionId)) {
      throw StateError('Question $questionId has already been answered.');
    }

    final answer = WebPracticeAnswer(
      questionId: questionId,
      isCorrect: isCorrect,
      becameMastered: becameMastered,
      mistakeResolved: mistakeResolved,
    );
    _answers[questionId] = answer;
    return WebPracticeAnswerResult(
      answer: answer,
      answeredIndex: _currentIndex,
      recommendedNextIndex: _findNextUnansweredIndex(_currentIndex),
      stats: stats,
    );
  }

  void goToIndex(int index) {
    if (index < 0 || index >= questionIds.length) {
      throw RangeError.range(index, 0, questionIds.length - 1, 'index');
    }
    _currentIndex = index;
  }

  bool movePrevious() {
    if (!hasPrevious) return false;
    _currentIndex--;
    return true;
  }

  bool moveNext() {
    if (!hasNext) return false;
    _currentIndex++;
    return true;
  }

  int? _findNextUnansweredIndex(int afterIndex) {
    if (_answers.length == questionIds.length) return null;
    for (var offset = 1; offset <= questionIds.length; offset++) {
      final index = (afterIndex + offset) % questionIds.length;
      if (!_answers.containsKey(questionIds[index])) return index;
    }
    return null;
  }
}

class WebPracticeAnswerResult {
  const WebPracticeAnswerResult({
    required this.answer,
    required this.answeredIndex,
    required this.recommendedNextIndex,
    required this.stats,
  });

  final WebPracticeAnswer answer;
  final int answeredIndex;

  /// The next unanswered question, wrapping once at the end of the order.
  /// The UI may navigate here after its feedback delay. Null means complete.
  final int? recommendedNextIndex;
  final WebPracticeStats stats;
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
