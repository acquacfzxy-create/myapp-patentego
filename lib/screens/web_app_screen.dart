import 'dart:async';
import 'dart:math';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/app_config.dart';
import '../config/app_strings.dart';
import '../config/content_direction.dart';
import '../config/locale_format.dart';
import '../config/user_error_copy.dart';
import '../config/app_theme.dart';
import '../config/chapter_config.dart';
import '../config/mock_test_config.dart';
import '../models/question.dart';
import '../models/chapter_capability.dart';
import '../models/daily_goal_plan.dart';
import '../models/user_state.dart';
import '../models/web_practice_mode.dart';
import '../providers/user_state_provider.dart';
import '../repositories/web_progress_repository.dart';
import '../repositories/web_exam_history_repository.dart';
import '../repositories/question_repository.dart';
import '../repositories/web_question_repository.dart';
import '../services/firebase_status.dart';
import '../services/access_policy.dart';
import '../services/question_speech_service.dart';
import '../services/web_exam_session.dart';
import '../services/web_practice_session.dart';
import '../widgets/question_widget.dart';

/// Web-first shell for the first usable browser vertical slice.
class WebAppScreen extends StatefulWidget {
  const WebAppScreen({super.key});

  @override
  State<WebAppScreen> createState() => _WebAppScreenState();
}

enum _WebArea {
  home,
  chapterSelection,
  practice,
  mistakeReview,
  favoriteReview,
  settings,
  masteryReport,
  dailyPlan,
  exam,
  examResult,
  examReview,
}

class _WebAppScreenState extends State<WebAppScreen> {
  final WebQuestionRepository _questionRepository = WebQuestionRepository();
  QuestionBankMetadata? _metadata;
  WebPracticeSession? _practiceSession;
  WebProgressRepository? _progressRepository;
  WebExamHistoryRepository? _examHistoryRepository;
  StreamSubscription<User?>? _authSubscription;
  Timer? _examTimer;
  List<Question> _questions = const [];
  int _currentIndex = 0;
  _WebArea _area = _WebArea.home;
  int _chapterTab = 0;
  bool _loading = true;
  bool _syncing = false;
  bool _cloudSyncUnavailable = false;
  bool? _selectedAnswer;
  bool _showTranslation = false;
  bool _isSpeakingQuestion = false;
  bool _isPreparingSpeech = false;
  bool _isAnswering = false;
  bool _showMasteredFeedback = false;
  bool _showMistakeResolvedFeedback = false;
  int _speechSession = 0;
  int _navigationSession = 0;
  final Map<String, bool> _sessionAnswers = {};
  int _newlyMasteredCount = 0;
  int _mistakesResolvedCount = 0;
  final QuestionSpeechService _speechService = QuestionSpeechService();
  final Map<String, bool> _examAnswers = {};
  WebExamSession? _examSession;
  int _examSecondsRemaining = MockTestConfig.timeLimitSeconds;
  int _examTimeUsedSeconds = 0;
  bool _examSubmitting = false;
  bool? _examPassed;
  int _examCorrectCount = 0;
  int _examWrongCount = 0;
  String? _error;

  User? get _currentUser => FirebaseStatus.auth?.currentUser;
  Question? get _currentQuestion =>
      _questions.isEmpty ? null : _questions[_currentIndex];

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    _examTimer?.cancel();
    _speechSession++;
    _speechService.dispose();
    super.dispose();
  }

  Future<void> _initialize() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      final progressRepository = WebProgressRepository(
        preferences: preferences,
        auth: FirebaseStatus.auth,
        firestore: FirebaseStatus.firestore,
      );
      final examHistoryRepository = WebExamHistoryRepository(
        preferences: preferences,
        auth: FirebaseStatus.auth,
        firestore: FirebaseStatus.firestore,
      );
      await _questionRepository.initialize();
      final metadata = await _questionRepository.getMetadata();
      var cloudSyncUnavailable = false;
      try {
        await progressRepository.initialize();
        await examHistoryRepository.initialize();
      } catch (_) {
        // A temporary network or Firestore rules problem must not block the
        // offline-first Web experience. The repository has already loaded the
        // signed-in account's browser snapshot before attempting cloud sync.
        cloudSyncUnavailable = true;
      }
      if (!mounted) return;
      setState(() {
        _metadata = metadata;
        _progressRepository = progressRepository;
        _examHistoryRepository = examHistoryRepository;
        // The home hub only needs manifest metadata. Question bundles stay
        // lazy and are fetched when a learning mode is opened.
        _questions = const [];
        _cloudSyncUnavailable = cloudSyncUnavailable;
        _loading = false;
      });

      final auth = FirebaseStatus.auth;
      if (auth != null) {
        _authSubscription = auth.authStateChanges().listen((_) async {
          try {
            await progressRepository.switchToCurrentUser();
            await examHistoryRepository.switchToCurrentUser();
            if (mounted) {
              setState(() => _cloudSyncUnavailable = false);
            }
          } catch (_) {
            if (mounted) {
              setState(() => _cloudSyncUnavailable = true);
            }
          }
        });
      }
    } catch (error) {
      if (!mounted) return;
      debugPrint('[web] question bank load failed: ${error.runtimeType}');
      setState(() {
        _error = AppStrings.get('load_question_failed');
        _loading = false;
      });
    }
  }

  Future<void> _reloadLanguage(String language) async {
    final currentQuestionId = _currentQuestion?.id;
    _navigationSession++;
    _speechSession++;
    await _speechService.stop();
    if (!mounted) return;
    await context.read<UserStateProvider>().changeLanguage(language);
    final localizedQuestions = await Future.wait(
      _questions.map(
        (question) => _questionRepository.getQuestionById(
          question.id,
          language: language,
        ),
      ),
    );
    if (!mounted) return;

    final localizedById = {
      for (final question in localizedQuestions.whereType<Question>())
        question.id: question,
    };
    final orderedQuestions = <Question>[];
    final usedIds = <String>{};
    for (final question in _questions) {
      final localized = localizedById[question.id];
      if (localized != null) {
        orderedQuestions.add(localized);
        usedIds.add(localized.id);
      }
    }
    // Keep a malformed/partially updated bundle usable without changing the
    // established order of IDs that are already in the session.
    for (final question in localizedQuestions.whereType<Question>()) {
      if (usedIds.add(question.id)) orderedQuestions.add(question);
    }
    final nextIndex = currentQuestionId == null
        ? _currentIndex
        : orderedQuestions
            .indexWhere((question) => question.id == currentQuestionId);
    setState(() {
      _questions = orderedQuestions;
      _currentIndex = orderedQuestions.isEmpty
          ? 0
          : nextIndex >= 0
              ? nextIndex
              : _currentIndex.clamp(0, orderedQuestions.length - 1);
      _resetQuestionState();
    });
  }

  Future<void> _answer(bool answer) async {
    final question = _currentQuestion;
    final progress = _progressRepository;
    if (question == null ||
        progress == null ||
        _selectedAnswer != null ||
        _isAnswering) {
      return;
    }

    final userState = context.read<UserStateProvider>();
    await userState.checkAndResetDailyCounters();
    if (!mounted || !userState.canPractice()) {
      if (mounted) _showQuizLimitMessage(userState.currentLanguage);
      return;
    }

    final navigationSession = _navigationSession;
    final questionId = question.id;
    final before = progress.progressFor(questionId);
    final isCorrect = answer == question.answer;
    if (mounted) {
      setState(() {
        _isAnswering = true;
        _selectedAnswer = answer;
      });
    }

    try {
      final after = await progress.recordAnswer(
        questionId,
        isCorrect: isCorrect,
      );
      // Count a valid answer in the same place as the App. The repository
      // records progress first; the provider owns today's free quota.
      await userState.incrementDailyQuizCount(
        isNewQuestion: before.totalAttempts == 0,
      );

      final newlyMastered = !before.isMastered && after.isMastered;
      final mistakeResolved = before.wrongCount > 0 && after.wrongCount == 0;
      try {
        _practiceSession?.answerCurrent(
          isCorrect: isCorrect,
          becameMastered: newlyMastered,
          mistakeResolved: mistakeResolved,
        );
      } on StateError {
        // UI guards the single-answer rule; tolerate a restored/rebuilt
        // session that has already seen this question.
      }
      if (mounted) {
        final isCurrentQuestion = navigationSession == _navigationSession &&
            _currentQuestion?.id == questionId;
        setState(() {
          _sessionAnswers[questionId] = isCorrect;
          if (newlyMastered) _newlyMasteredCount++;
          if (mistakeResolved) _mistakesResolvedCount++;
          if (isCurrentQuestion) {
            _isAnswering = false;
            _showMasteredFeedback = isCorrect &&
                (newlyMastered || before.isMastered || after.isMastered);
            _showMistakeResolvedFeedback = mistakeResolved;
          }
        });
      }
      if (progress.canSync) unawaited(_sync(silent: true));

      // Keep the App's short feedback window. A manual move, language change,
      // or leaving the session invalidates this pending transition.
      await Future<void>.delayed(const Duration(milliseconds: 800));
      if (!mounted ||
          navigationSession != _navigationSession ||
          _currentQuestion?.id != questionId ||
          _selectedAnswer != answer) {
        return;
      }
      _advanceAfterAnswer();
    } catch (error) {
      if (!mounted) return;
      if (navigationSession == _navigationSession &&
          _currentQuestion?.id == questionId) {
        setState(() {
          _isAnswering = false;
          _selectedAnswer = null;
        });
      }
      _showMessage('${AppStrings.get('failed_to_load')}: $error');
    }
  }

  Future<void> _toggleFavorite() async {
    final question = _currentQuestion;
    final progress = _progressRepository;
    if (question == null || progress == null) return;
    await progress.toggleFavorite(question.id);
    if (mounted) setState(() {});
    if (progress.canSync) unawaited(_sync(silent: true));
  }

  Future<void> _sync({bool silent = false}) async {
    final progress = _progressRepository;
    if (progress == null || !progress.canSync || _syncing) return;
    setState(() => _syncing = true);
    try {
      await progress.sync();
      if (!mounted) return;
      setState(() => _cloudSyncUnavailable = false);
      if (!silent) _showMessage(AppStrings.get('sync_success'));
    } catch (error) {
      if (mounted) {
        setState(() => _cloudSyncUnavailable = true);
        if (!silent) {
          _showMessage(
            UserErrorCopy.sync(error, language: AppStrings.getLanguage()),
          );
        }
      }
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  Future<void> _signIn() async {
    if (!mounted) return;
    final language = context.read<UserStateProvider>().currentLanguage;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _text(language, 'chooseSignInMethod'),
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () {
                Navigator.of(sheetContext).pop();
                unawaited(_completeSignIn(useApple: false));
              },
              icon: const Icon(Icons.g_mobiledata_rounded, size: 28),
              label: Text(
                AppStrings.getWithLanguage(language, 'auth_google'),
              ),
            ),
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: () {
                Navigator.of(sheetContext).pop();
                unawaited(_completeSignIn(useApple: true));
              },
              style: FilledButton.styleFrom(backgroundColor: Colors.black),
              icon: const Icon(Icons.apple_rounded),
              label: Text(
                AppStrings.getWithLanguage(language, 'auth_apple'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _completeSignIn({required bool useApple}) async {
    try {
      final userState = context.read<UserStateProvider>();
      if (useApple) {
        await userState.signInWithApple();
      } else {
        await userState.signInWithGoogle();
      }
      await _progressRepository?.switchToCurrentUser();
      await _examHistoryRepository?.switchToCurrentUser();
      if (!mounted) return;
      setState(() => _cloudSyncUnavailable = false);
      await _maybeMergeGuestProgress();
    } catch (error) {
      if (mounted) {
        setState(() => _cloudSyncUnavailable = _currentUser != null);
        _showMessage(
          UserErrorCopy.auth(error, language: AppStrings.getLanguage()),
        );
      }
    }
  }

  Future<void> _maybeMergeGuestProgress() async {
    final progress = _progressRepository;
    if (progress == null || !progress.hasGuestProgress || !mounted) return;

    final language = context.read<UserStateProvider>().currentLanguage;
    final shouldMerge = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          AppStrings.getWithLanguage(language, 'merge_progress_title'),
        ),
        content: Text(
          AppStrings.getWithLanguage(language, 'merge_progress_message'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(
              AppStrings.getWithLanguage(language, 'merge_progress_later'),
            ),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(
              AppStrings.getWithLanguage(language, 'merge_progress_confirm'),
            ),
          ),
        ],
      ),
    );
    if (shouldMerge != true || !mounted) return;

    try {
      await progress.mergeGuestIntoCurrentUser();
      if (!mounted) return;
      setState(() {});
      _showMessage(
        AppStrings.getWithLanguage(language, 'merge_progress_success'),
      );
    } catch (error) {
      if (!mounted) return;
      _showMessage(
        '${AppStrings.getWithLanguage(language, 'merge_progress_failed')} '
        '($error)',
      );
    }
  }

  Future<void> _signOut() async {
    await FirebaseStatus.auth?.signOut();
    await _progressRepository?.switchToCurrentUser();
    await _examHistoryRepository?.switchToCurrentUser();
    if (mounted) setState(() {});
  }

  Future<void> _showExplanation(Question question, String language) async {
    await QuestionWidget.showRichExplanation(
      context,
      question: question,
      currentLanguage: language,
    );
  }

  Future<void> _toggleQuestionSpeech() async {
    final question = _currentQuestion;
    if (question == null) return;

    if (_isPreparingSpeech || _isSpeakingQuestion) {
      _speechSession++;
      await _speechService.stop();
      if (mounted) {
        setState(() {
          _isPreparingSpeech = false;
          _isSpeakingQuestion = false;
        });
      }
      return;
    }

    final session = ++_speechSession;
    if (mounted) setState(() => _isPreparingSpeech = true);

    try {
      var stoppedBeforeStartReturned = false;
      var speechErrorReported = false;
      final started = await _speechService.speakItalian(
        question.translations['it'] ?? '',
        questionId: question.id,
        // Stream the exact MP3 used by the App. The speech service falls back
        // to the browser's Italian system voice when the network is unavailable.
        preferNaturalAudio: true,
        onStart: () {
          if (mounted && session == _speechSession) {
            setState(() {
              _isPreparingSpeech = false;
              _isSpeakingQuestion = true;
            });
          }
        },
        onStop: () {
          stoppedBeforeStartReturned = true;
          if (mounted && session == _speechSession) {
            setState(() {
              _isPreparingSpeech = false;
              _isSpeakingQuestion = false;
            });
          }
        },
        onError: (_) {
          speechErrorReported = true;
          if (mounted && session == _speechSession) {
            setState(() {
              _isPreparingSpeech = false;
              _isSpeakingQuestion = false;
            });
            _showSpeechUnavailable();
          }
        },
      );

      if (!mounted || session != _speechSession) return;
      if (started && !stoppedBeforeStartReturned) {
        setState(() {
          _isPreparingSpeech = false;
          _isSpeakingQuestion = true;
        });
      } else if (!started) {
        setState(() {
          _isPreparingSpeech = false;
          _isSpeakingQuestion = false;
        });
        if (!speechErrorReported) _showSpeechUnavailable();
      }
    } catch (_) {
      if (mounted && session == _speechSession) {
        setState(() {
          _isPreparingSpeech = false;
          _isSpeakingQuestion = false;
        });
        _showSpeechUnavailable();
      }
    }
  }

  void _showSpeechUnavailable() {
    final language = context.read<UserStateProvider>().currentLanguage;
    _showMessage(
      AppStrings.getWithLanguage(language, 'speech_unavailable'),
    );
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  void _showQuizLimitMessage(String language) {
    final key = _currentUser == null
        ? 'quiz_limit_body_guest'
        : 'quiz_limit_body_logged_in';
    _showMessage(AppStrings.getWithLanguage(language, key));
  }

  void _resetQuestionState() {
    _selectedAnswer = null;
    _showTranslation = false;
    _isSpeakingQuestion = false;
    _isPreparingSpeech = false;
    _isAnswering = false;
    _showMasteredFeedback = false;
    _showMistakeResolvedFeedback = false;
  }

  void _advanceAfterAnswer() {
    if (_questions.isEmpty) return;
    _speechSession++;
    unawaited(_speechService.stop());
    setState(() {
      _currentIndex = (_currentIndex + 1) % _questions.length;
      _practiceSession?.goToIndex(_currentIndex);
      _resetQuestionState();
    });
  }

  void _startPractice() {
    if (_questions.isEmpty) return;
    _navigationSession++;
    _speechSession++;
    unawaited(_speechService.stop());
    setState(() {
      _area = _WebArea.practice;
      _currentIndex = 0;
      _practiceSession?.goToIndex(0);
      _sessionAnswers.clear();
      _newlyMasteredCount = 0;
      _mistakesResolvedCount = 0;
      _resetQuestionState();
    });
  }

  void _finishPractice() {
    _navigationSession++;
    _speechSession++;
    unawaited(_speechService.stop());
    setState(() {
      _area = _WebArea.home;
      _currentIndex = 0;
      _sessionAnswers.clear();
      _newlyMasteredCount = 0;
      _mistakesResolvedCount = 0;
      _resetQuestionState();
    });
  }

  Future<void> _handleOverviewPressed() async {
    // Invalidate an answer's pending 800ms transition before opening the
    // sheet. Choosing “continue” then resumes on the same question.
    _navigationSession++;
    _speechSession++;
    unawaited(_speechService.stop());
    if (_sessionAnswers.isEmpty) {
      if (mounted) _finishPractice();
      return;
    }

    final language = context.read<UserStateProvider>().currentLanguage;
    final shouldFinish = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) {
        final answeredCount = _sessionAnswers.length;
        final correctCount =
            _sessionAnswers.values.where((value) => value).length;

        Widget metric(String label, int value, {Color? valueColor}) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(child: Text(label)),
                const SizedBox(width: 16),
                Text(
                  '$value',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: valueColor ?? AppTheme.ink,
                  ),
                ),
              ],
            ),
          );
        }

        return Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                AppStrings.getWithLanguage(
                  language,
                  'growth_session_summary_title',
                ),
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.ink,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              metric(
                AppStrings.getWithLanguage(
                  language,
                  'growth_session_answered',
                ),
                answeredCount,
              ),
              metric(
                AppStrings.getWithLanguage(
                  language,
                  'growth_session_correct',
                ),
                correctCount,
                valueColor: AppTheme.roadGreen,
              ),
              metric(
                AppStrings.getWithLanguage(
                  language,
                  'growth_newly_mastered',
                ),
                _newlyMasteredCount,
              ),
              metric(
                AppStrings.getWithLanguage(
                  language,
                  'growth_mistakes_resolved',
                ),
                _mistakesResolvedCount,
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: () => Navigator.of(sheetContext).pop(false),
                icon: const Icon(Icons.play_arrow),
                label: Text(
                  AppStrings.getWithLanguage(
                    language,
                    'growth_continue_practice',
                  ),
                ),
              ),
              const SizedBox(height: 8),
              ElevatedButton.icon(
                onPressed: () => Navigator.of(sheetContext).pop(true),
                icon: const Icon(Icons.check),
                label: Text(
                  AppStrings.getWithLanguage(
                    language,
                    'growth_finish_session',
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
    if (shouldFinish == true && mounted) _finishPractice();
  }

  void _move(int delta) {
    final next = (_currentIndex + delta).clamp(0, _questions.length - 1);
    if (next == _currentIndex) return;
    _navigationSession++;
    _speechSession++;
    unawaited(_speechService.stop());
    setState(() {
      _currentIndex = next;
      _practiceSession?.goToIndex(next);
      _resetQuestionState();
    });
  }

  String get _actorId => _currentUser?.uid ?? 'guest_user';

  Future<bool> _ensurePracticeAllowed() async {
    final userState = context.read<UserStateProvider>();
    await userState.checkAndResetDailyCounters();
    if (!mounted) return false;
    if (!userState.canPractice()) {
      _showQuizLimitMessage(userState.currentLanguage);
      return false;
    }
    return true;
  }

  Future<void> _startRandomPractice() async {
    if (!await _ensurePracticeAllowed()) return;
    if (!mounted) return;
    try {
      final language = context.read<UserStateProvider>().currentLanguage;
      var questions = await _questionRepository.getRandomQuestions(
        30,
        language: language,
      );
      if (!mounted) return;
      if (context.read<UserStateProvider>().skipMastered) {
        questions = questions
            .where(
              (question) =>
                  !_progressRepository!.progressFor(question.id).isMastered,
            )
            .toList(growable: false);
      }
      if (questions.isEmpty) {
        _showMessage(AppStrings.getWithLanguage(language, 'no_questions'));
        return;
      }
      final practiceSession = WebPracticeSession.create(
        mode: WebPracticeMode.random,
        questionIds: questions.map((question) => question.id),
        actorId: _actorId,
        dataVersion: _metadata!.dataVersion,
      );
      final byId = {for (final question in questions) question.id: question};
      final orderedQuestions = practiceSession.questionIds
          .map((id) => byId[id]!)
          .toList(growable: false);
      setState(() {
        _questions = orderedQuestions;
        _practiceSession = practiceSession;
      });
      _startPractice();
    } catch (error) {
      if (mounted) _showMessage('${AppStrings.get('failed_to_load')}: $error');
    }
  }

  Future<void> _startChapterPractice(int chapter) async {
    final userState = context.read<UserStateProvider>();
    if (userState.isChapterLocked(chapter)) {
      _showMessage(
        AppStrings.getWithLanguage(
          userState.currentLanguage,
          'chapter_locked_message',
        ),
      );
      return;
    }
    if (!await _ensurePracticeAllowed()) return;
    try {
      var questions = await _questionRepository.getQuestionsByChapter(
        chapter,
        language: userState.currentLanguage,
      );
      if (!mounted) return;
      if (userState.skipMastered) {
        questions = questions
            .where(
              (question) =>
                  !_progressRepository!.progressFor(question.id).isMastered,
            )
            .toList(growable: false);
      }
      if (questions.isEmpty) {
        _showMessage(
          AppStrings.getWithLanguage(
            userState.currentLanguage,
            'no_questions_in_chapter',
          ),
        );
        return;
      }
      final shuffled = List<Question>.from(questions)..shuffle();
      final practiceSession = WebPracticeSession.create(
        mode: WebPracticeMode.chapter,
        questionIds: shuffled.map((question) => question.id),
        actorId: _actorId,
        dataVersion: _metadata!.dataVersion,
      );
      setState(() {
        _questions = shuffled;
        _practiceSession = practiceSession;
      });
      _startPractice();
    } catch (error) {
      if (mounted) _showMessage('${AppStrings.get('failed_to_load')}: $error');
    }
  }

  Future<void> _openMistakes() async {
    setState(() => _area = _WebArea.mistakeReview);
  }

  Future<List<Question>> _loadMistakeQuestions(String language) async {
    final mistakeIds = _progressRepository!.records.values
        .where((item) => item.wrongCount > 0)
        .map((item) => item.questionId)
        .toList(growable: false);
    final questions = await Future.wait(
      mistakeIds.map(
        (id) => _questionRepository.getQuestionById(id, language: language),
      ),
    );
    return questions.whereType<Question>().toList(growable: false);
  }

  Future<void> _startMistakePractice() async {
    if (!await _ensurePracticeAllowed()) return;
    if (!mounted) return;
    final language = context.read<UserStateProvider>().currentLanguage;
    final questions = await _loadMistakeQuestions(language);
    if (!mounted) return;
    if (questions.isEmpty) {
      _showMessage(AppStrings.getWithLanguage(language, 'no_mistakes'));
      return;
    }
    final practiceSession = WebPracticeSession.create(
      mode: WebPracticeMode.mistakes,
      questionIds: questions.map((question) => question.id),
      actorId: _actorId,
      dataVersion: _metadata!.dataVersion,
    );
    setState(() {
      _questions = questions;
      _practiceSession = practiceSession;
    });
    _startPractice();
  }

  Future<void> _startExam() async {
    final userState = context.read<UserStateProvider>();
    await userState.checkAndResetDailyCounters();
    if (!mounted) return;
    try {
      final language = userState.currentLanguage;
      WebExamSession? session;
      List<Question> questions = const [];
      final saved = await _examHistoryRepository?.loadSession();
      if (saved != null) {
        final savedMap = Map<String, dynamic>.from(saved);
        final rawIds = savedMap['question_ids'];
        if (rawIds is List && rawIds.length == WebExamSession.questionCount) {
          final restoredQuestions = await Future.wait(
            rawIds.map(
              (id) => _questionRepository.getQuestionById(
                id.toString(),
                language: language,
              ),
            ),
          );
          questions = restoredQuestions.whereType<Question>().toList();
          if (questions.length == WebExamSession.questionCount) {
            session = WebExamSession.tryRestore(
              savedMap,
              expectedActorId: _actorId,
              expectedDataVersion: _metadata!.dataVersion,
              correctAnswers: {
                for (final question in questions) question.id: question.answer,
              },
            );
          }
        }
        if (session?.isSubmitted == true) session = null;
      }

      if (session == null) {
        if (!userState.canStartExam()) {
          _showMessage(
            AppStrings.getWithLanguage(language, 'exam_limit_reached'),
          );
          return;
        }
        questions = await _questionRepository.getRandomQuestions(
          WebExamSession.questionCount,
          language: language,
        );
        if (questions.length < WebExamSession.questionCount) return;
        session = WebExamSession.create(
          questionIds: questions.map((item) => item.id),
          correctAnswers: {for (final item in questions) item.id: item.answer},
          actorId: _actorId,
          dataVersion: _metadata!.dataVersion,
          now: DateTime.now(),
        );
        final byId = {for (final item in questions) item.id: item};
        questions = session.questionIds.map((id) => byId[id]!).toList();
        await userState.setExamUsedToday(true);
      }
      await _saveExamSession(session);
      if (!mounted) return;
      setState(() {
        _examSession = session;
        _examAnswers
          ..clear()
          ..addAll(session!.selectedAnswers);
        _questions = questions;
        _currentIndex = session.currentIndex;
        _examSecondsRemaining = session.remainingSeconds(DateTime.now());
        _examPassed = null;
        _area = _WebArea.exam;
      });
      _startExamTimer();
    } catch (error) {
      if (mounted) {
        _showMessage(
          '${AppStrings.getWithLanguage(userState.currentLanguage, 'start_mock_test_failed')}: $error',
        );
      }
    }
  }

  void _startExamTimer() {
    _examTimer?.cancel();
    _examTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final session = _examSession;
      if (!mounted || session == null || _area != _WebArea.exam) return;
      final remaining = session.remainingSeconds(DateTime.now());
      setState(() => _examSecondsRemaining = remaining);
      if (remaining == 0) unawaited(_submitExam());
    });
  }

  Future<void> _saveExamSession(WebExamSession session) async {
    try {
      await _examHistoryRepository?.saveSession(session.toMap());
    } catch (_) {
      if (mounted) setState(() => _cloudSyncUnavailable = true);
    }
  }

  Future<void> _selectExamAnswer(bool answer) async {
    final session = _examSession;
    if (session == null || !session.canChangeAnswers(DateTime.now())) return;
    session.selectCurrentAnswer(answer, now: DateTime.now());
    if (mounted) {
      setState(() {
        _examAnswers
          ..clear()
          ..addAll(session.selectedAnswers);
      });
    }
    unawaited(_saveExamSession(session));
  }

  Future<void> _moveExam(int delta) async {
    final session = _examSession;
    if (session == null) return;
    final moved = delta < 0 ? session.movePrevious() : session.moveNext();
    if (!moved) return;
    if (mounted) setState(() => _currentIndex = session.currentIndex);
    unawaited(_saveExamSession(session));
  }

  Future<void> _submitExam() async {
    final session = _examSession;
    final progress = _progressRepository;
    if (session == null || progress == null || _examSubmitting) return;
    _examTimer?.cancel();
    setState(() => _examSubmitting = true);
    final result = session.submit(now: DateTime.now());
    for (final item in result.questions) {
      if (item.selectedAnswer == null) {
        await progress.recordExamMistake(item.questionId);
      } else {
        await progress.recordAnswer(
          item.questionId,
          isCorrect: item.isCorrect,
        );
      }
    }
    final completedAtMs = DateTime.now().millisecondsSinceEpoch;
    final timeUsedSeconds = MockTestConfig.timeLimitSeconds -
        _examSecondsRemaining.clamp(0, MockTestConfig.timeLimitSeconds);
    await _examHistoryRepository?.addAttempt(
      WebExamAttempt(
        id: '${_actorId}_$completedAtMs',
        completedAtMs: completedAtMs,
        totalQuestions: result.totalQuestions,
        correctCount: result.correctCount,
        wrongCount: result.wrongCount,
        timeUsedSeconds: timeUsedSeconds,
        passed: result.passed,
        questionIds: session.questionIds,
        selectedAnswers: session.selectedAnswers,
      ),
    );
    await _examHistoryRepository?.clearSession();
    if (progress.canSync) unawaited(_sync(silent: true));
    if (!mounted) return;
    setState(() {
      _examSubmitting = false;
      _examPassed = result.passed;
      _examCorrectCount = result.correctCount;
      _examWrongCount = result.wrongCount;
      _examTimeUsedSeconds = timeUsedSeconds;
      _area = _WebArea.examResult;
    });
  }

  void _leaveToHome() {
    _examTimer?.cancel();
    _navigationSession++;
    _speechSession++;
    unawaited(_speechService.stop());
    setState(() {
      _area = _WebArea.home;
      _resetQuestionState();
    });
  }

  @override
  Widget build(BuildContext context) {
    final language = context.watch<UserStateProvider>().currentLanguage;
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FB),
      appBar: _buildAppBar(language),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _buildError()
              : _buildArea(language),
    );
  }

  Widget _buildArea(String language) {
    switch (_area) {
      case _WebArea.home:
        return _buildLanding(language);
      case _WebArea.chapterSelection:
        return _buildChapterSelection(language);
      case _WebArea.practice:
        return _buildPractice(language);
      case _WebArea.mistakeReview:
        return _buildMistakeReview(language);
      case _WebArea.favoriteReview:
        return _buildFavoriteReview(language);
      case _WebArea.settings:
        return _buildSettings(language);
      case _WebArea.masteryReport:
        return _buildMasteryReport(language);
      case _WebArea.dailyPlan:
        return _buildDailyPlan(language);
      case _WebArea.exam:
        return _buildExam(language);
      case _WebArea.examResult:
        return _buildExamResult(language);
      case _WebArea.examReview:
        return _buildExamReview(language);
    }
  }

  Widget _buildSignInAction(String language, bool isCompact) {
    final label = _text(language, 'signIn');
    // 窄屏（如 320px）上按钮文字会挤压左侧标志，改为仅图标；文案保留在提示与读屏标签中。
    if (isCompact && MediaQuery.sizeOf(context).width < 400) {
      return IconButton.filled(
        onPressed: _signIn,
        tooltip: label,
        icon: const Icon(Icons.login),
      );
    }
    if (isCompact) {
      return FilledButton.icon(
        onPressed: _signIn,
        icon: const Icon(Icons.login),
        label: Text(label),
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          minimumSize: const Size(0, 40),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: VisualDensity.compact,
        ),
      );
    }
    return FilledButton.icon(
      onPressed: _signIn,
      icon: const Icon(Icons.login, size: 18),
      label: Text(label),
    );
  }

  PreferredSizeWidget _buildAppBar(String language) {
    final isCompact = _isCompactLayout(context);
    return AppBar(
      toolbarHeight: isCompact ? 60 : 72,
      backgroundColor: Colors.white.withOpacity(0.96),
      surfaceTintColor: Colors.white,
      elevation: 0,
      titleSpacing: isCompact ? 12 : null,
      title: Tooltip(
        message: AppStrings.getWithLanguage(language, 'return_home'),
        child: Semantics(
          button: true,
          label: AppStrings.getWithLanguage(language, 'return_home'),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              key: const ValueKey('web-home-logo-button'),
              onTap: _leaveToHome,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(isCompact ? 10 : 12),
                      child: Image.asset(
                        'assets/images/app_icon.png',
                        width: isCompact ? 36 : 42,
                        height: isCompact ? 36 : 42,
                        fit: BoxFit.cover,
                      ),
                    ),
                    if (!isCompact) ...[
                      const SizedBox(width: 12),
                      Text(
                        AppStrings.get('app_title'),
                        style: const TextStyle(
                          color: AppTheme.ink,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
      actions: [
        IconButton(
          tooltip: AppStrings.getWithLanguage(language, 'settings'),
          onPressed: () => setState(() => _area = _WebArea.settings),
          icon: const Icon(Icons.settings_outlined),
        ),
        if (isCompact)
          PopupMenuButton<String>(
            tooltip: _languageLabel(language),
            icon: const Icon(Icons.language),
            onSelected: _reloadLanguage,
            itemBuilder: (_) => UserState.supportedLanguages
                .map(
                  (code) => PopupMenuItem(
                    value: code,
                    child: Row(
                      children: [
                        if (code == language) const Icon(Icons.check, size: 18),
                        if (code == language) const SizedBox(width: 8),
                        Text(_languageLabel(code)),
                      ],
                    ),
                  ),
                )
                .toList(),
          )
        else
          DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: language,
              borderRadius: BorderRadius.circular(14),
              items: UserState.supportedLanguages
                  .map(
                    (code) => DropdownMenuItem(
                      value: code,
                      child: Text(_languageLabel(code)),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                if (value != null) _reloadLanguage(value);
              },
            ),
          ),
        if (!isCompact) const SizedBox(width: 12),
        Padding(
          padding: EdgeInsetsDirectional.only(end: isCompact ? 8 : 20),
          child: _currentUser == null
              ? _buildSignInAction(language, isCompact)
              : PopupMenuButton<String>(
                  tooltip: _currentUser?.email ?? '',
                  onSelected: (value) {
                    if (value == 'sync') _sync();
                    if (value == 'logout') _signOut();
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: 'sync',
                      child: Text(AppStrings.get('sync_now')),
                    ),
                    PopupMenuItem(
                      value: 'logout',
                      child: Text(_text(language, 'signOut')),
                    ),
                  ],
                  child: CircleAvatar(
                    backgroundColor: AppTheme.primarySoft,
                    child: Text(
                      (_currentUser?.email ?? 'U')
                          .substring(0, 1)
                          .toUpperCase(),
                      style: const TextStyle(
                        color: AppTheme.primary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildLanding(String language) {
    final progress = _progressRepository!;
    final records = progress.records.values;
    final attempted = records.where((item) => item.totalAttempts > 0).length;
    final mastered = records.where((item) => item.isMastered).length;
    final mistakes = records.where((item) => item.wrongCount > 0).length;
    final favorites = records.where((item) => item.isFavorite).length;
    final total = _questionRepository.questionCount;
    final coverage = total == 0 ? 0.0 : (attempted / total).clamp(0.0, 1.0);

    final features = <Widget>[
      _HubFeatureCard(
        icon: Icons.shuffle_rounded,
        iconColor: AppTheme.primary,
        iconBackground: AppTheme.primarySoft,
        title: AppStrings.getWithLanguage(language, 'random_practice'),
        subtitle: _text(language, 'randomPracticeDescription'),
        onTap: _startRandomPractice,
      ),
      _HubFeatureCard(
        icon: Icons.menu_book_rounded,
        iconColor: AppTheme.roadGreen,
        iconBackground: AppTheme.roadGreenSoft,
        title: AppStrings.getWithLanguage(language, 'chapter_practice'),
        subtitle: _text(language, 'chapterPracticeDescription'),
        onTap: () => setState(() => _area = _WebArea.chapterSelection),
      ),
      _HubFeatureCard(
        icon: Icons.timer_rounded,
        iconColor: const Color(0xFFE28619),
        iconBackground: const Color(0xFFFFF4E5),
        title: AppStrings.getWithLanguage(language, 'official_mock_test'),
        subtitle: _text(language, 'examDescription'),
        onTap: _startExam,
      ),
      _HubFeatureCard(
        icon: Icons.report_problem_rounded,
        iconColor: AppTheme.danger,
        iconBackground: const Color(0xFFFFECEE),
        title: AppStrings.getWithLanguage(language, 'mistake_review'),
        subtitle: mistakes == 0
            ? _text(language, 'noMistakeDescription')
            : _text(language, 'mistakeDescription')
                .replaceAll('{count}', '$mistakes'),
        badge: mistakes == 0 ? null : '$mistakes',
        onTap: _openMistakes,
      ),
      _HubFeatureCard(
        icon: Icons.favorite_rounded,
        iconColor: AppTheme.danger,
        iconBackground: const Color(0xFFFFECEE),
        title: AppStrings.getWithLanguage(language, 'favorite_questions'),
        subtitle: favorites == 0
            ? _text(language, 'noFavoriteDescription')
            : _text(language, 'favoriteDescription')
                .replaceAll('{count}', '$favorites'),
        badge: favorites == 0 ? null : '$favorites',
        onTap: () => setState(() => _area = _WebArea.favoriteReview),
      ),
      _HubFeatureCard(
        icon: Icons.insights_rounded,
        iconColor: const Color(0xFF7C3AED),
        iconBackground: const Color(0xFFF3E8FF),
        title: AppStrings.getWithLanguage(language, 'mastery_report_title'),
        subtitle: _text(language, 'masteryReportDescription'),
        onTap: () => setState(() => _area = _WebArea.masteryReport),
      ),
      _HubFeatureCard(
        icon: Icons.flag_rounded,
        iconColor: const Color(0xFF0F8A5F),
        iconBackground: const Color(0xFFE8FFF5),
        title: AppStrings.getWithLanguage(language, 'daily_goal_manage_title'),
        subtitle: _text(language, 'dailyPlanDescription'),
        onTap: () => setState(() => _area = _WebArea.dailyPlan),
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = _isCompactLayout(context);
        final columns = constraints.maxWidth >= 920 ? 4 : 2;
        final width =
            (constraints.maxWidth - (compact ? 32 : 48) - (columns - 1) * 14) /
                columns;
        return SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            compact ? 16 : 24,
            compact ? 24 : 40,
            compact ? 16 : 24,
            36,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1160),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    AppStrings.getWithLanguage(language, 'home_greeting'),
                    style: TextStyle(
                      fontSize: compact ? 28 : 36,
                      fontWeight: FontWeight.w900,
                      color: AppTheme.ink,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _text(language, 'hubSubtitle'),
                    style: const TextStyle(
                      color: Color(0xFF627084),
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 22),
                  Card(
                    elevation: 0,
                    color: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24),
                      side: const BorderSide(color: Color(0xFFE3EAF3)),
                    ),
                    child: Padding(
                      padding: EdgeInsets.all(compact ? 18 : 24),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: _HomeMetric(
                                  label: AppStrings.getWithLanguage(
                                    language,
                                    'questions_answered',
                                  ),
                                  value: '$attempted',
                                ),
                              ),
                              Expanded(
                                child: _HomeMetric(
                                  label: AppStrings.getWithLanguage(
                                    language,
                                    'mastered_questions',
                                  ),
                                  value: '$mastered',
                                  color: AppTheme.roadGreen,
                                ),
                              ),
                              Expanded(
                                child: _HomeMetric(
                                  label: AppStrings.getWithLanguage(
                                    language,
                                    'errors',
                                  ),
                                  value: '$mistakes',
                                  color: AppTheme.danger,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 18),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  _text(language, 'bankCoverage'),
                                  style: const TextStyle(
                                    color: Color(0xFF627084),
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              Text(
                                '$attempted / $total',
                                style: const TextStyle(
                                  color: AppTheme.primary,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(99),
                            child: LinearProgressIndicator(
                              minHeight: 9,
                              value: coverage,
                              backgroundColor: const Color(0xFFE7EEF7),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Wrap(
                    spacing: 14,
                    runSpacing: 14,
                    children: features
                        .map(
                            (feature) => SizedBox(width: width, child: feature))
                        .toList(growable: false),
                  ),
                  const SizedBox(height: 18),
                  _CloudStatusBanner(
                    signedIn: _currentUser != null,
                    unavailable: _cloudSyncUnavailable,
                    text: _currentUser == null
                        ? _text(language, 'guestSaved')
                        : _cloudSyncUnavailable
                            ? _text(language, 'syncUnavailable')
                            : _text(language, 'cloudSaved'),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // Kept as a compact fallback/reference while the full-bank hub settles.
  // ignore: unused_element
  Widget _buildLegacyLanding(String language) {
    final progress = _progressRepository;
    final questionIds = _questions.map((question) => question.id).toSet();
    final chapterRecords = progress?.records.values
            .where((record) => questionIds.contains(record.questionId))
            .toList(growable: false) ??
        const <WebQuestionProgress>[];
    final totalQuestions = _questions.length;
    final attemptedCount =
        chapterRecords.where((record) => record.totalAttempts > 0).length;
    final masteredCount =
        chapterRecords.where((record) => record.isMastered).length;
    final mistakeCount =
        chapterRecords.where((record) => record.wrongCount > 0).length;
    final favoriteCount =
        chapterRecords.where((record) => record.isFavorite).length;
    final coverage = totalQuestions == 0
        ? 0.0
        : (attemptedCount / totalQuestions).clamp(0.0, 1.0).toDouble();
    final hasStarted = attemptedCount > 0;
    final greeting = AppStrings.getWithLanguage(language, 'home_greeting');
    final accountName = _currentUser?.displayName?.trim().isNotEmpty == true
        ? _currentUser!.displayName!.trim()
        : _currentUser?.email?.split('@').first.trim();
    final greetingText = accountName == null || accountName.isEmpty
        ? greeting
        : '$greeting，$accountName';

    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = _isCompactLayout(context);
        final isWide = constraints.maxWidth >= 900 && !isCompact;
        final horizontalPadding = isCompact ? 16.0 : 24.0;
        final featureHints = [
          _FeatureHint(
            icon: Icons.volume_up_outlined,
            label: _text(language, 'hintListen'),
          ),
          _FeatureHint(
            icon: Icons.translate_outlined,
            label: _text(language, 'hintTranslate'),
          ),
          _FeatureHint(
            icon: Icons.menu_book_outlined,
            label: _text(language, 'hintExplanation'),
          ),
          _FeatureHint(
            icon: Icons.devices_outlined,
            label: _text(language, 'hintSync'),
          ),
        ];

        final intro = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Pill(
              icon: Icons.directions_car_filled,
              text: AppStrings.getWithLanguage(language, 'app_title'),
            ),
            const SizedBox(height: 20),
            Text(
              greetingText,
              style: TextStyle(
                fontSize: isCompact ? 28 : 34,
                height: 1.12,
                fontWeight: FontWeight.w900,
                color: AppTheme.ink,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              _text(language, 'landingSubhead'),
              style: TextStyle(
                fontSize: isCompact ? 16 : 18,
                height: 1.55,
                color: const Color(0xFF526174),
              ),
            ),
            const SizedBox(height: 20),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: _currentUser == null || _cloudSyncUnavailable
                    ? const Color(0xFFFFF7ED)
                    : const Color(0xFFECFDF3),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: _currentUser == null || _cloudSyncUnavailable
                      ? const Color(0xFFFED7AA)
                      : const Color(0xFFBBF7D0),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    _currentUser == null || _cloudSyncUnavailable
                        ? Icons.cloud_off_rounded
                        : Icons.cloud_done_rounded,
                    size: 20,
                    color: _currentUser == null || _cloudSyncUnavailable
                        ? const Color(0xFFEA580C)
                        : const Color(0xFF159A55),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _currentUser == null
                          ? _text(language, 'guestSaved')
                          : _cloudSyncUnavailable
                              ? _text(language, 'syncUnavailable')
                              : _text(language, 'cloudSaved'),
                      style: const TextStyle(
                        color: AppTheme.ink,
                        fontWeight: FontWeight.w600,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            Text(
              _text(language, 'availableTools'),
              style: const TextStyle(
                color: Color(0xFF6B7788),
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: featureHints
                  .map(
                    (hint) => _FeatureHintChip(
                      icon: hint.icon,
                      label: hint.label,
                    ),
                  )
                  .toList(),
            ),
          ],
        );

        final chapterCard = Card(
          elevation: 0,
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
            side: const BorderSide(color: Color(0xFFE3EAF3)),
          ),
          child: Padding(
            padding: EdgeInsets.all(isCompact ? 20 : 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: AppTheme.primarySoft,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(
                        Icons.signpost_outlined,
                        color: AppTheme.primary,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _text(language, 'chapterOne'),
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              color: AppTheme.ink,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            AppStrings.getWithLanguage(
                              language,
                              'web_chapter_question_count',
                            ).replaceAll('{count}', '$totalQuestions'),
                            style: const TextStyle(
                              color: Color(0xFF6B7788),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _text(language, 'chapterProgress'),
                        style: const TextStyle(
                          color: Color(0xFF526174),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Text(
                      '$attemptedCount / $totalQuestions',
                      style: const TextStyle(
                        color: AppTheme.primary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 9),
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: LinearProgressIndicator(
                    value: coverage,
                    minHeight: 10,
                    backgroundColor: const Color(0xFFE7EEF7),
                    valueColor:
                        const AlwaysStoppedAnimation<Color>(AppTheme.primary),
                  ),
                ),
                const SizedBox(height: 22),
                _MetricRow(
                  icon: Icons.task_alt,
                  label: AppStrings.getWithLanguage(
                    language,
                    'questions_answered',
                  ),
                  value: '$attemptedCount',
                ),
                const SizedBox(height: 15),
                _MetricRow(
                  icon: Icons.workspace_premium_outlined,
                  label: AppStrings.getWithLanguage(
                    language,
                    'mastered_questions',
                  ),
                  value: '$masteredCount',
                ),
                const SizedBox(height: 15),
                _MetricRow(
                  icon: Icons.error_outline,
                  label: AppStrings.getWithLanguage(language, 'errors'),
                  value: '$mistakeCount',
                ),
                const SizedBox(height: 15),
                _MetricRow(
                  icon: Icons.bookmark_border_rounded,
                  label: AppStrings.getWithLanguage(language, 'favorite'),
                  value: '$favoriteCount',
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _startPractice,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 17),
                    ),
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: Text(
                      _text(
                        language,
                        hasStarted ? 'continueChapter' : 'startChapter',
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );

        return SingleChildScrollView(
          padding: EdgeInsets.symmetric(
            horizontal: horizontalPadding,
            vertical: isCompact ? 28 : 48,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1120),
              child: SizedBox(
                width: double.infinity,
                child: isWide
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: intro),
                          const SizedBox(width: 36),
                          Expanded(child: chapterCard),
                        ],
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          intro,
                          const SizedBox(height: 28),
                          chapterCard,
                        ],
                      ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildChapterSelection(String language) {
    final chapters = _chapterTab == 0
        ? ChapterConfig.principalChapters
        : ChapterConfig.secondaryChapters;
    final records = _progressRepository!.records;
    return _WebPageFrame(
      title: AppStrings.getWithLanguage(language, 'select_chapter'),
      onBack: _leaveToHome,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SegmentedButton<int>(
            segments: [
              ButtonSegment(
                value: 0,
                label: Text(
                  AppStrings.getWithLanguage(language, 'principal_chapters'),
                ),
              ),
              ButtonSegment(
                value: 1,
                label: Text(
                  AppStrings.getWithLanguage(language, 'secondary_chapters'),
                ),
              ),
            ],
            selected: {_chapterTab},
            onSelectionChanged: (value) {
              setState(() => _chapterTab = value.first);
            },
          ),
          const SizedBox(height: 18),
          ...chapters.map((chapter) {
            final total = _metadata!.chapterCounts[chapter.id] ?? 0;
            final ids = _metadata!.questionChapters.entries
                .where((entry) => entry.value == chapter.id)
                .map((entry) => entry.key)
                .toList(growable: false);
            final practiced =
                ids.where((id) => (records[id]?.totalAttempts ?? 0) > 0).length;
            final mastered =
                ids.where((id) => records[id]?.isMastered == true).length;
            final locked =
                context.read<UserStateProvider>().isChapterLocked(chapter.id);
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _ChapterCard(
                chapterNumber: chapter.id,
                title: chapter.titleIt,
                translation: chapter.getTitle(language),
                total: total,
                practiced: practiced,
                mastered: mastered,
                locked: locked,
                onTap: () => _startChapterPractice(chapter.id),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildMistakeReview(String language) {
    return FutureBuilder<List<Question>>(
      future: _loadMistakeQuestions(language),
      builder: (context, snapshot) {
        final questions = snapshot.data;
        return _WebPageFrame(
          title: AppStrings.getWithLanguage(language, 'mistake_review'),
          onBack: _leaveToHome,
          child: snapshot.connectionState != ConnectionState.done
              ? const Center(child: CircularProgressIndicator())
              : questions == null || questions.isEmpty
                  ? _EmptyState(
                      icon: Icons.task_alt_rounded,
                      title: AppStrings.getWithLanguage(
                        language,
                        'empty_mistakes_title',
                      ),
                      message: AppStrings.getWithLanguage(
                        language,
                        'empty_mistakes_description',
                      ),
                      action: FilledButton.icon(
                        onPressed: _startExam,
                        icon: const Icon(Icons.timer_rounded),
                        label: Text(
                          AppStrings.getWithLanguage(
                            language,
                            'start_mock_exam_now',
                          ),
                        ),
                      ),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        FilledButton.icon(
                          onPressed: _startMistakePractice,
                          icon: const Icon(Icons.play_arrow_rounded),
                          label: Text(
                            _text(language, 'startMistakePractice')
                                .replaceAll('{count}', '${questions.length}'),
                          ),
                        ),
                        const SizedBox(height: 16),
                        ...questions.asMap().entries.map((entry) {
                          final question = entry.value;
                          final record =
                              _progressRepository!.progressFor(question.id);
                          return _MistakeListCard(
                            number: entry.key + 1,
                            italian: question.translations['it'] ?? '',
                            translation: question.translations[language],
                            wrongCount: record.wrongCount,
                            onPractice: () {
                              setState(() {
                                _questions = [question];
                                _practiceSession = WebPracticeSession.create(
                                  mode: WebPracticeMode.mistakes,
                                  questionIds: [question.id],
                                  actorId: _actorId,
                                  dataVersion: _metadata!.dataVersion,
                                );
                              });
                              _startPractice();
                            },
                            onClear: () async {
                              await _progressRepository!
                                  .clearMistake(question.id);
                              if (mounted) setState(() {});
                            },
                          );
                        }),
                      ],
                    ),
        );
      },
    );
  }

  Future<List<Question>> _loadFavoriteQuestions(String language) async {
    final favoriteIds = _progressRepository!.records.values
        .where((item) => item.isFavorite)
        .map((item) => item.questionId)
        .toList(growable: false);
    final questions = await Future.wait(
      favoriteIds.map(
        (id) => _questionRepository.getQuestionById(id, language: language),
      ),
    );
    return questions.whereType<Question>().toList(growable: false);
  }

  List<ChapterCapability> _buildChapterCapabilities() {
    final metadata = _metadata!;
    final records = _progressRepository!.records;
    return metadata.availableChapters.map((chapter) {
      final ids = metadata.questionChapters.entries
          .where((entry) => entry.value == chapter)
          .map((entry) => entry.key)
          .toList(growable: false);
      final practiced =
          ids.where((id) => (records[id]?.totalAttempts ?? 0) > 0).length;
      final mastered =
          ids.where((id) => records[id]?.isMastered == true).length;
      final mistakes =
          ids.where((id) => (records[id]?.wrongCount ?? 0) > 0).length;
      final lastPracticed = ids.fold<int>(0, (latest, id) {
        final timestamp = records[id]?.lastPracticedMs ?? 0;
        return max(latest, timestamp);
      });
      return ChapterCapability(
        chapterId: chapter,
        total: metadata.chapterCounts[chapter] ?? ids.length,
        practiced: practiced,
        mastered: mastered,
        mistakes: mistakes,
        lastPracticed: lastPracticed,
      );
    }).toList(growable: false);
  }

  Widget _buildMasteryReport(String language) {
    final records = _progressRepository!.records.values;
    final total = _metadata!.totalQuestionCount;
    final attempted = records.where((item) => item.totalAttempts > 0).length;
    final mastered = records.where((item) => item.isMastered).length;
    final mistakes = records.where((item) => item.wrongCount > 0).length;
    final favorites = records.where((item) => item.isFavorite).length;
    final capabilities = _buildChapterCapabilities()
      ..sort((a, b) {
        int priority(ChapterCapabilityState state) => switch (state) {
              ChapterCapabilityState.needsAttention => 0,
              ChapterCapabilityState.learning => 1,
              ChapterCapabilityState.notStarted => 2,
              ChapterCapabilityState.stable => 3,
            };
        final byState = priority(a.state).compareTo(priority(b.state));
        return byState != 0
            ? byState
            : b.mistakeDensity.compareTo(a.mistakeDensity);
      });
    final attempts = _examHistoryRepository?.attempts ?? const [];
    final passedAttempts = attempts.where((attempt) => attempt.passed).length;

    return _WebPageFrame(
      title: AppStrings.getWithLanguage(language, 'mastery_report_title'),
      onBack: _leaveToHome,
      maxWidth: 980,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            elevation: 0,
            color: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(22),
              side: const BorderSide(color: Color(0xFFE3EAF3)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(22),
              child: Column(
                children: [
                  Wrap(
                    spacing: 28,
                    runSpacing: 18,
                    alignment: WrapAlignment.center,
                    children: [
                      _ResultMetric(
                        label: AppStrings.getWithLanguage(
                          language,
                          'questions_answered',
                        ),
                        value: '$attempted',
                      ),
                      _ResultMetric(
                        label: AppStrings.getWithLanguage(
                          language,
                          'mastered_questions',
                        ),
                        value: '$mastered',
                        color: AppTheme.roadGreen,
                      ),
                      _ResultMetric(
                        label: AppStrings.getWithLanguage(language, 'errors'),
                        value: '$mistakes',
                        color: AppTheme.danger,
                      ),
                      _ResultMetric(
                        label: AppStrings.getWithLanguage(
                          language,
                          'favorite',
                        ),
                        value: '$favorites',
                        color: const Color(0xFFE28619),
                      ),
                    ],
                  ),
                  const SizedBox(height: 22),
                  _ReportProgress(
                    label: _text(language, 'bankCoverage'),
                    value: total == 0 ? 0 : attempted / total,
                    detail: '$attempted / $total',
                    color: AppTheme.primary,
                  ),
                  const SizedBox(height: 14),
                  _ReportProgress(
                    label: AppStrings.getWithLanguage(
                      language,
                      'mastered_questions',
                    ),
                    value: total == 0 ? 0 : mastered / total,
                    detail: '$mastered / $total',
                    color: AppTheme.roadGreen,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),
          Card(
            elevation: 0,
            color: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(22),
              side: const BorderSide(color: Color(0xFFE3EAF3)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          AppStrings.getWithLanguage(
                            language,
                            'mock_exam_trend_title',
                          ),
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      Text(
                        attempts.isEmpty
                            ? '--'
                            : '${(passedAttempts / attempts.length * 100).round()}%',
                        style: const TextStyle(
                          color: AppTheme.primary,
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (attempts.isEmpty)
                    Text(
                      AppStrings.getWithLanguage(language, 'no_exam_data'),
                      style: const TextStyle(color: Color(0xFF627084)),
                    )
                  else
                    ...attempts.take(10).map(
                          (attempt) => _ExamHistoryRow(
                            attempt: attempt,
                            passedLabel: AppStrings.getWithLanguage(
                              language,
                              attempt.passed ? 'passed' : 'failed',
                            ),
                          ),
                        ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),
          Text(
            AppStrings.getWithLanguage(language, 'chapter_capability_title'),
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w900,
              color: AppTheme.ink,
            ),
          ),
          const SizedBox(height: 10),
          ...capabilities.map(
            (capability) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _ChapterCapabilityCard(
                capability: capability,
                title: ChapterConfig.getChapterById(capability.chapterId)
                        ?.getTitle(language) ??
                    '${AppStrings.getWithLanguage(language, 'chapter')} ${capability.chapterId}',
                status: _capabilityLabel(capability.state, language),
                detail:
                    '${capability.practiced}/${capability.total} · ${AppStrings.getWithLanguage(language, 'mastered_questions')} ${capability.mastered} · ${AppStrings.getWithLanguage(language, 'errors')} ${capability.mistakes}',
                locked: context
                    .read<UserStateProvider>()
                    .isChapterLocked(capability.chapterId),
                onTap: () => _startChapterPractice(capability.chapterId),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _capabilityLabel(ChapterCapabilityState state, String language) {
    final key = switch (state) {
      ChapterCapabilityState.notStarted => 'chapter_capability_not_started',
      ChapterCapabilityState.learning => 'chapter_capability_learning',
      ChapterCapabilityState.needsAttention =>
        'chapter_capability_needs_attention',
      ChapterCapabilityState.stable => 'chapter_capability_stable',
    };
    return AppStrings.getWithLanguage(language, key);
  }

  DailyPlanAllocation _webDailyAllocation(int goal) {
    final attempted = _progressRepository!.attemptedCount;
    return DailyGoalPlan.allocateTotalGoal(
      totalGoal: goal,
      remainingQuestions: DailyGoalPlan.remainingQuestions(attempted),
      attemptedQuestions: attempted,
    );
  }

  Widget _buildDailyPlan(String language) {
    final userState = context.watch<UserStateProvider>();
    final allocation = _webDailyAllocation(userState.dailyStudyGoal);
    final completedNew =
        min(userState.dailyNewQuestionCount, allocation.newGoal);
    final completedReview =
        min(userState.dailyReviewQuestionCount, allocation.reviewGoal);
    final totalCompleted = completedNew + completedReview;
    final totalGoal = allocation.totalGoal;
    final remaining = max(0, totalGoal - totalCompleted);

    return _WebPageFrame(
      title: AppStrings.getWithLanguage(language, 'daily_goal_manage_title'),
      onBack: _leaveToHome,
      maxWidth: 760,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            elevation: 0,
            color: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(22),
              side: const BorderSide(color: Color(0xFFE3EAF3)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    _text(language, 'chooseDailyGoal'),
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [10, 20, 30, 50, 100].map((goal) {
                      return ChoiceChip(
                        label: Text('$goal'),
                        selected: userState.dailyStudyGoal == goal,
                        onSelected: (_) => _setWebDailyGoal(goal),
                      );
                    }).toList(growable: false),
                  ),
                  const SizedBox(height: 22),
                  _ReportProgress(
                    label: _text(language, 'todayPlanProgress'),
                    value: totalGoal == 0 ? 0 : totalCompleted / totalGoal,
                    detail: '$totalCompleted / $totalGoal',
                    color: AppTheme.primary,
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: _PlanMetric(
                          icon: Icons.fiber_new_rounded,
                          label: _text(language, 'newQuestions'),
                          value: '$completedNew / ${allocation.newGoal}',
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _PlanMetric(
                          icon: Icons.refresh_rounded,
                          label: _text(language, 'reviewQuestions'),
                          value: '$completedReview / ${allocation.reviewGoal}',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  FilledButton.icon(
                    onPressed: remaining == 0 ? null : _startWebDailyPlan,
                    icon: Icon(
                      remaining == 0
                          ? Icons.check_circle_rounded
                          : Icons.play_arrow_rounded,
                    ),
                    label: Text(
                      remaining == 0
                          ? _text(language, 'todayPlanComplete')
                          : _text(language, 'startTodayPlan')
                              .replaceAll('{count}', '$remaining'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _setWebDailyGoal(int goal) async {
    final attempted = _progressRepository!.attemptedCount;
    final targetDate = DailyGoalPlan.targetDateForTotalGoal(
      remainingQuestions: DailyGoalPlan.remainingQuestions(attempted),
      attemptedQuestions: attempted,
      totalGoal: goal,
    );
    await context.read<UserStateProvider>().setDailyStudyGoal(
          goal,
          targetDate: targetDate,
        );
  }

  Future<void> _startWebDailyPlan() async {
    if (!await _ensurePracticeAllowed() || !mounted) return;
    final userState = context.read<UserStateProvider>();
    final allocation = _webDailyAllocation(userState.dailyStudyGoal);
    var newNeeded = max(
      0,
      allocation.newGoal - userState.dailyNewQuestionCount,
    );
    var reviewNeeded = max(
      0,
      allocation.reviewGoal - userState.dailyReviewQuestionCount,
    );
    var totalNeeded = newNeeded + reviewNeeded;
    if (!userState.isVip) {
      totalNeeded = min(
        totalNeeded,
        AccessPolicy.freeDailyQuizLimit - userState.dailyQuizCount,
      );
    } else {
      totalNeeded = min(totalNeeded, 300);
    }
    if (totalNeeded <= 0) return;

    newNeeded = min(newNeeded, totalNeeded);
    reviewNeeded = min(reviewNeeded, totalNeeded - newNeeded);
    final records = _progressRepository!.records;
    final random = Random();
    final unseenIds = _metadata!.questionChapters.keys
        .where((id) => (records[id]?.totalAttempts ?? 0) == 0)
        .toList()
      ..shuffle(random);
    final reviewIds =
        records.values.where((record) => record.totalAttempts > 0).toList()
          ..sort((a, b) {
            final byMistakes = b.wrongCount.compareTo(a.wrongCount);
            return byMistakes != 0
                ? byMistakes
                : a.lastPracticedMs.compareTo(b.lastPracticedMs);
          });
    final selectedIds = <String>[
      ...unseenIds.take(newNeeded),
      ...reviewIds.take(reviewNeeded).map((record) => record.questionId),
    ];
    if (selectedIds.isEmpty) return;

    final language = userState.currentLanguage;
    final loaded = await Future.wait(
      selectedIds.map(
        (id) => _questionRepository.getQuestionById(id, language: language),
      ),
    );
    final questions = loaded.whereType<Question>().toList(growable: false);
    if (!mounted || questions.isEmpty) return;
    final session = WebPracticeSession.create(
      mode: WebPracticeMode.random,
      questionIds: questions.map((question) => question.id),
      actorId: _actorId,
      dataVersion: _metadata!.dataVersion,
    );
    final byId = {for (final question in questions) question.id: question};
    setState(() {
      _questions = session.questionIds.map((id) => byId[id]!).toList();
      _practiceSession = session;
    });
    _startPractice();
  }

  Widget _buildFavoriteReview(String language) {
    return FutureBuilder<List<Question>>(
      future: _loadFavoriteQuestions(language),
      builder: (context, snapshot) {
        final questions = snapshot.data;
        return _WebPageFrame(
          title: AppStrings.getWithLanguage(language, 'favorite_questions'),
          onBack: _leaveToHome,
          child: snapshot.connectionState != ConnectionState.done
              ? const Center(child: CircularProgressIndicator())
              : questions == null || questions.isEmpty
                  ? _EmptyState(
                      icon: Icons.favorite_border_rounded,
                      title: _text(language, 'emptyFavoritesTitle'),
                      message: _text(language, 'emptyFavoritesDescription'),
                      action: FilledButton.icon(
                        onPressed: _startRandomPractice,
                        icon: const Icon(Icons.shuffle_rounded),
                        label: Text(
                          AppStrings.getWithLanguage(
                            language,
                            'random_practice',
                          ),
                        ),
                      ),
                    )
                  : Column(
                      children: questions.asMap().entries.map((entry) {
                        final question = entry.value;
                        return _FavoriteListCard(
                          number: entry.key + 1,
                          italian: question.translations['it'] ?? '',
                          translation: question.translations[language],
                          practiceLabel: AppStrings.getWithLanguage(
                            language,
                            'start_practice',
                          ),
                          explanationLabel: AppStrings.getWithLanguage(
                            language,
                            'btn_explanation',
                          ),
                          onPractice: () {
                            setState(() {
                              _questions = [question];
                              _practiceSession = WebPracticeSession.create(
                                mode: WebPracticeMode.random,
                                questionIds: [question.id],
                                actorId: _actorId,
                                dataVersion: _metadata!.dataVersion,
                              );
                            });
                            _startPractice();
                          },
                          onExplanation: () =>
                              _showExplanation(question, language),
                          onRemove: () async {
                            await _progressRepository!
                                .toggleFavorite(question.id);
                            if (_progressRepository!.canSync) {
                              unawaited(_sync(silent: true));
                            }
                            if (mounted) setState(() {});
                          },
                        );
                      }).toList(growable: false),
                    ),
        );
      },
    );
  }

  Widget _buildSettings(String language) {
    final userState = context.watch<UserStateProvider>();
    return _WebPageFrame(
      title: AppStrings.getWithLanguage(language, 'settings'),
      onBack: _leaveToHome,
      maxWidth: 760,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SettingsCard(
            icon: Icons.language_rounded,
            title: AppStrings.getWithLanguage(language, 'language'),
            subtitle: _languageLabel(language),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: UserState.supportedLanguages.map((code) {
                return ChoiceChip(
                  label: Text(_languageLabel(code)),
                  selected: code == language,
                  onSelected: code == language
                      ? null
                      : (_) => unawaited(_reloadLanguage(code)),
                );
              }).toList(growable: false),
            ),
          ),
          const SizedBox(height: 12),
          _SettingsCard(
            icon: Icons.filter_list_rounded,
            title: AppStrings.getWithLanguage(
              language,
              'skip_mastered_questions',
            ),
            subtitle: _text(language, 'skipMasteredDescription'),
            trailing: Switch(
              value: userState.skipMastered,
              onChanged: userState.setSkipMastered,
            ),
          ),
          const SizedBox(height: 12),
          _SettingsCard(
            icon: Icons.cloud_sync_rounded,
            title: AppStrings.getWithLanguage(language, 'sync_now'),
            subtitle: _currentUser == null
                ? _text(language, 'signInToSync')
                : AppStrings.getWithLanguage(language, 'cloud_sync'),
            onTap: _currentUser == null ? _signIn : () => _sync(),
            trailing: _syncing
                ? const SizedBox.square(
                    dimension: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.chevron_right_rounded),
          ),
          const SizedBox(height: 12),
          _SettingsCard(
            icon: Icons.record_voice_over_rounded,
            title: _text(language, 'browserVoiceTitle'),
            subtitle: _text(language, 'browserVoiceDescription'),
          ),
          const SizedBox(height: 12),
          _SettingsCard(
            icon: Icons.offline_bolt_rounded,
            title: _text(language, 'offlineTitle'),
            subtitle: _text(language, 'offlineDescription'),
          ),
          const SizedBox(height: 12),
          _SettingsCard(
            icon: Icons.privacy_tip_outlined,
            title: AppStrings.getWithLanguage(language, 'privacy_and_terms'),
            subtitle:
                '${AppStrings.getWithLanguage(language, 'sub_privacy_policy')} / ${AppStrings.getWithLanguage(language, 'sub_service_terms')}',
            child: Wrap(
              spacing: 10,
              children: [
                TextButton.icon(
                  onPressed: () => _openExternalUrl(
                    AppConfig.privacyPolicyUrl,
                    language,
                  ),
                  icon: const Icon(Icons.privacy_tip_outlined),
                  label: Text(
                    AppStrings.getWithLanguage(
                      language,
                      'sub_privacy_policy',
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: () => _openExternalUrl(
                    AppConfig.termsOfServiceUrl,
                    language,
                  ),
                  icon: const Icon(Icons.description_outlined),
                  label: Text(
                    AppStrings.getWithLanguage(
                      language,
                      'sub_service_terms',
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _SettingsCard(
            icon: Icons.support_agent_rounded,
            title: AppStrings.getWithLanguage(language, 'support'),
            subtitle: AppStrings.getWithLanguage(language, 'support_subtitle'),
            onTap: () =>
                _openExternalUrl(AppConfig.supportContactUrl, language),
            trailing: const Icon(Icons.open_in_new_rounded),
          ),
          const SizedBox(height: 12),
          _SettingsCard(
            icon: Icons.info_outline_rounded,
            title: AppStrings.getWithLanguage(language, 'about'),
            subtitle:
                '${AppStrings.getWithLanguage(language, 'version')} ${AppConfig.appVersion}',
          ),
          const SizedBox(height: 12),
          _SettingsCard(
            icon: Icons.delete_forever_rounded,
            iconColor: AppTheme.danger,
            title: AppStrings.getWithLanguage(language, 'reset_progress'),
            subtitle: _text(language, 'resetProgressDescription'),
            onTap: () => _confirmResetProgress(language),
            trailing: const Icon(
              Icons.chevron_right_rounded,
              color: AppTheme.danger,
            ),
          ),
          if (_currentUser != null) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _signOut,
              icon: const Icon(Icons.logout_rounded),
              label: Text(_text(language, 'signOut')),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _openExternalUrl(String source, String language) async {
    final uri = Uri.parse(source);
    if (!await launchUrl(uri, mode: LaunchMode.platformDefault) && mounted) {
      _showMessage(_text(language, 'openLinkFailed'));
    }
  }

  Future<void> _confirmResetProgress(String language) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          AppStrings.getWithLanguage(language, 'reset_confirm_title'),
        ),
        content: Text(
          AppStrings.getWithLanguage(language, 'reset_confirm_content'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(AppStrings.getWithLanguage(language, 'cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(backgroundColor: AppTheme.danger),
            child: Text(AppStrings.getWithLanguage(language, 'confirm')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final userState = context.read<UserStateProvider>();
    try {
      await _progressRepository!.clearAllProgress();
      await userState.resetWebLearningCounters();
      await _examHistoryRepository?.clearSession();
      await _examHistoryRepository?.clearHistory();
      if (!mounted) return;
      setState(() {
        _questions = const [];
        _practiceSession = null;
        _examSession = null;
        _examAnswers.clear();
      });
      _showMessage(
        AppStrings.getWithLanguage(language, 'reset_progress_success'),
      );
    } catch (error) {
      if (mounted) {
        _showMessage(
          '${AppStrings.getWithLanguage(language, 'reset_progress_failed')}: $error',
        );
      }
    }
  }

  Widget _buildExam(String language) {
    final session = _examSession!;
    final question = _questions[_currentIndex];
    final selected = _examAnswers[question.id];
    return _WebPageFrame(
      title: AppStrings.getWithLanguage(language, 'mock_test_title'),
      onBack: _leaveToHome,
      trailing: _ExamTimer(seconds: _examSecondsRemaining),
      maxWidth: 900,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                '${AppStrings.getWithLanguage(language, 'question')} ${_currentIndex + 1} / ${_questions.length}',
                style: const TextStyle(
                  color: AppTheme.primary,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Spacer(),
              Text('${session.answeredCount} / ${_questions.length}'),
            ],
          ),
          const SizedBox(height: 10),
          LinearProgressIndicator(
            value: (_currentIndex + 1) / _questions.length,
            minHeight: 8,
            borderRadius: BorderRadius.circular(99),
          ),
          const SizedBox(height: 20),
          _ExamQuestionCard(
            question: question,
            language: language,
            selected: selected,
            imagePath: question.imageName == null
                ? null
                : _imageAssetPath(question.imageName!),
            onSelect: _selectExamAnswer,
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _currentIndex == 0 ? null : () => _moveExam(-1),
                  icon: const Icon(Icons.arrow_back_rounded),
                  label: Text(
                    AppStrings.getWithLanguage(language, 'previous_question'),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _currentIndex == _questions.length - 1
                    ? FilledButton.icon(
                        onPressed: _examSubmitting ? null : _confirmSubmitExam,
                        icon: const Icon(Icons.check_rounded),
                        label: Text(
                          AppStrings.getWithLanguage(language, 'submit_exam'),
                        ),
                      )
                    : FilledButton.icon(
                        onPressed: () => _moveExam(1),
                        icon: const Icon(Icons.arrow_forward_rounded),
                        label: Text(
                          AppStrings.getWithLanguage(language, 'next_question'),
                        ),
                      ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          OutlinedButton(
            onPressed: _examSubmitting ? null : _confirmSubmitExam,
            child: Text(
              AppStrings.getWithLanguage(language, 'submit_exam'),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmSubmitExam() async {
    final language = context.read<UserStateProvider>().currentLanguage;
    final unanswered = _questions.length - _examAnswers.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(AppStrings.getWithLanguage(language, 'submit_exam')),
        content: Text(
          _text(language, 'submitExamConfirmation')
              .replaceAll('{count}', '$unanswered'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(AppStrings.getWithLanguage(language, 'cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(AppStrings.getWithLanguage(language, 'submit_exam')),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) await _submitExam();
  }

  Widget _buildExamResult(String language) {
    final passed = _examPassed == true;
    return _WebPageFrame(
      title: AppStrings.getWithLanguage(language, 'mock_test_completed'),
      onBack: _leaveToHome,
      maxWidth: 720,
      child: Card(
        elevation: 0,
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(26),
          side: const BorderSide(color: Color(0xFFE3EAF3)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            children: [
              Icon(
                passed ? Icons.verified_rounded : Icons.cancel_rounded,
                size: 72,
                color: passed ? AppTheme.roadGreen : AppTheme.danger,
              ),
              const SizedBox(height: 14),
              Text(
                AppStrings.getWithLanguage(
                  language,
                  passed ? 'passed' : 'failed',
                ),
                style: const TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w900,
                  color: AppTheme.ink,
                ),
              ),
              const SizedBox(height: 22),
              Wrap(
                spacing: 30,
                runSpacing: 16,
                alignment: WrapAlignment.center,
                children: [
                  _ResultMetric(
                    label: _text(language, 'correctAnswers'),
                    value: '$_examCorrectCount',
                    color: AppTheme.roadGreen,
                  ),
                  _ResultMetric(
                    label: AppStrings.getWithLanguage(language, 'errors'),
                    value: '$_examWrongCount',
                    color: AppTheme.danger,
                  ),
                  _ResultMetric(
                    label: AppStrings.getWithLanguage(language, 'time_used'),
                    value: _formatDuration(_examTimeUsedSeconds),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: () => setState(() => _area = _WebArea.examReview),
                icon: const Icon(Icons.fact_check_outlined),
                label: Text(_text(language, 'reviewExam')),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: _leaveToHome,
                icon: const Icon(Icons.home_outlined),
                label: Text(_text(language, 'backHome')),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildExamReview(String language) {
    return _WebPageFrame(
      title: _text(language, 'reviewExam'),
      onBack: () => setState(() => _area = _WebArea.examResult),
      child: Column(
        children: _questions.asMap().entries.map((entry) {
          final question = entry.value;
          final selected = _examAnswers[question.id];
          final correct = selected != null && selected == question.answer;
          return _ExamReviewCard(
            number: entry.key + 1,
            question: question,
            language: language,
            selected: selected,
            correct: correct,
          );
        }).toList(growable: false),
      ),
    );
  }

  String _formatDuration(int seconds) {
    final minutes = seconds ~/ 60;
    final rest = seconds % 60;
    return '$minutes:${rest.toString().padLeft(2, '0')}';
  }

  Widget _buildPractice(String language) {
    final question = _currentQuestion!;
    final progress = _progressRepository!.progressFor(question.id);
    final isCompact = _isCompactLayout(context);
    final isCorrect =
        _selectedAnswer == null ? null : _selectedAnswer == question.answer;
    final translation = question.translations[language];
    final hasTranslation =
        language != 'it' && translation?.trim().isNotEmpty == true;

    final questionCard = Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: const BorderSide(color: Color(0xFFE3EAF3)),
      ),
      child: Padding(
        padding: EdgeInsets.all(isCompact ? 20 : 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  '${AppStrings.get('question')} ${_currentIndex + 1} / ${_questions.length}',
                  style: const TextStyle(
                    color: AppTheme.primary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const Spacer(),
                IconButton(
                  tooltip: progress.isFavorite
                      ? AppStrings.get('unfavorite')
                      : AppStrings.get('favorite'),
                  onPressed: _toggleFavorite,
                  icon: Icon(
                    progress.isFavorite
                        ? Icons.bookmark_rounded
                        : Icons.bookmark_border_rounded,
                    color: progress.isFavorite
                        ? const Color(0xFFF59E0B)
                        : const Color(0xFF8290A3),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Text(
              question.translations['it'] ?? '',
              textDirection: TextDirection.ltr,
              style: const TextStyle(
                fontSize: 25,
                height: 1.42,
                fontWeight: FontWeight.w700,
                color: AppTheme.ink,
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: _toggleQuestionSpeech,
                  icon: Icon(
                    _isPreparingSpeech
                        ? Icons.hourglass_top_rounded
                        : _isSpeakingQuestion
                            ? Icons.stop_circle_outlined
                            : Icons.volume_up_outlined,
                  ),
                  label: Text(
                    AppStrings.getWithLanguage(
                      language,
                      _isPreparingSpeech
                          ? 'speech_preparing'
                          : _isSpeakingQuestion
                              ? 'speech_stop'
                              : 'listen_question',
                    ),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: hasTranslation
                      ? () {
                          setState(() {
                            _showTranslation = !_showTranslation;
                          });
                        }
                      : null,
                  icon: Icon(
                    _showTranslation
                        ? Icons.visibility_off_outlined
                        : Icons.translate,
                  ),
                  label: Text(
                    AppStrings.getWithLanguage(
                      language,
                      _showTranslation
                          ? 'hide_translation'
                          : 'show_translation',
                    ),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: () => _showExplanation(question, language),
                  icon: const Icon(Icons.menu_book_outlined),
                  label: Text(
                    AppStrings.getWithLanguage(language, 'btn_explanation'),
                  ),
                ),
              ],
            ),
            if (_showTranslation && hasTranslation) ...[
              const SizedBox(height: 12),
              _TranslationPanel(text: translation ?? ''),
            ],
            if (question.imageName?.isNotEmpty == true) ...[
              const SizedBox(height: 22),
              Center(
                child: SizedBox(
                  height: 190,
                  child: Image.asset(
                    _imageAssetPath(question.imageName!),
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const Icon(
                      Icons.image_not_supported_outlined,
                      size: 72,
                      color: Color(0xFF9AA7B7),
                    ),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 28),
            Row(
              children: [
                Expanded(
                  child: _AnswerButton(
                    label: 'Vero',
                    answer: true,
                    selectedAnswer: _selectedAnswer,
                    correctAnswer: question.answer,
                    onPressed: () => _answer(true),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: _AnswerButton(
                    label: 'Falso',
                    answer: false,
                    selectedAnswer: _selectedAnswer,
                    correctAnswer: question.answer,
                    onPressed: () => _answer(false),
                  ),
                ),
              ],
            ),
            if (isCorrect != null && !_isAnswering) ...[
              const SizedBox(height: 20),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _showMasteredFeedback
                      ? const Color(0xFFEFF6FF)
                      : isCorrect
                          ? const Color(0xFFECFDF3)
                          : const Color(0xFFFFF1F2),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final feedbackColor = _showMasteredFeedback
                        ? const Color(0xFF2563EB)
                        : isCorrect
                            ? const Color(0xFF159A55)
                            : const Color(0xFFE5484D);
                    final message = Row(
                      children: [
                        Icon(
                          _showMasteredFeedback
                              ? Icons.workspace_premium_rounded
                              : isCorrect
                                  ? Icons.check_circle
                                  : Icons.cancel,
                          color: feedbackColor,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            AppStrings.getWithLanguage(
                              language,
                              _showMasteredFeedback
                                  ? 'question_mastered'
                                  : isCorrect
                                      ? 'correct_answer'
                                      : 'wrong_answer',
                            ),
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    );
                    return message;
                  },
                ),
              ),
              if (_showMistakeResolvedFeedback) ...[
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF7ED),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.celebration_rounded,
                        color: Color(0xFFEA580C),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          AppStrings.getWithLanguage(
                            language,
                            'mistake_cleared_celebration',
                          ),
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
            const SizedBox(height: 20),
            LayoutBuilder(
              builder: (context, constraints) {
                final previousButton = OutlinedButton.icon(
                  onPressed: _currentIndex == 0 ? null : () => _move(-1),
                  icon: const Icon(Icons.arrow_back_rounded),
                  label: Flexible(
                    child: Text(
                      AppStrings.get('previous_question'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                );
                final nextButton = FilledButton.icon(
                  onPressed: _currentIndex == _questions.length - 1
                      ? null
                      : () => _move(1),
                  icon: const Icon(Icons.arrow_forward_rounded),
                  label: Flexible(
                    child: Text(
                      AppStrings.get('next_question'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                );
                if (constraints.maxWidth < 500) {
                  return Row(
                    children: [
                      Expanded(child: previousButton),
                      const SizedBox(width: 10),
                      Expanded(child: nextButton),
                    ],
                  );
                }
                return Row(
                  children: [
                    previousButton,
                    const Spacer(),
                    nextButton,
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );

    final sidePanel = Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: const BorderSide(color: Color(0xFFE3EAF3)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextButton.icon(
              onPressed: _handleOverviewPressed,
              icon: const Icon(Icons.home_outlined),
              label: Text(_text(language, 'overview')),
            ),
            const SizedBox(height: 18),
            LinearProgressIndicator(
              value: (_currentIndex + 1) / _questions.length,
              minHeight: 9,
              borderRadius: BorderRadius.circular(10),
            ),
            const SizedBox(height: 22),
            _MetricRow(
              icon: Icons.task_alt,
              label: AppStrings.get('questions_answered'),
              value: '${_progressRepository!.attemptedCount}',
            ),
            const SizedBox(height: 16),
            _MetricRow(
              icon: Icons.error_outline,
              label: AppStrings.get('errors'),
              value: '${_progressRepository!.mistakeCount}',
            ),
            const SizedBox(height: 16),
            _MetricRow(
              icon: _syncing ? Icons.sync : Icons.cloud_done_outlined,
              label: _text(language, 'sync'),
              value: _currentUser == null || _cloudSyncUnavailable
                  ? _text(language, 'local')
                  : _syncing
                      ? AppStrings.get('syncing')
                      : _text(language, 'active'),
            ),
          ],
        ),
      ),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide =
            constraints.maxWidth >= 900 && !_isCompactLayout(context);
        return SingleChildScrollView(
          padding: EdgeInsets.symmetric(
            horizontal: isWide ? 24 : 16,
            vertical: isWide ? 24 : 16,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1120),
              child: SizedBox(
                width: double.infinity,
                child: isWide
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(width: 260, child: sidePanel),
                          const SizedBox(width: 24),
                          Expanded(child: questionCard),
                        ],
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          questionCard,
                          const SizedBox(height: 18),
                          sidePanel,
                        ],
                      ),
              ),
            ),
          ),
        );
      },
    );
  }

  bool _isCompactLayout(BuildContext context) {
    final platform = Theme.of(context).platform;
    return MediaQuery.sizeOf(context).width < 700 ||
        platform == TargetPlatform.android ||
        platform == TargetPlatform.iOS;
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 54, color: Colors.redAccent),
            const SizedBox(height: 14),
            Text(_error ?? AppStrings.get('load_question_failed')),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () {
                setState(() {
                  _loading = true;
                  _error = null;
                });
                _initialize();
              },
              child: Text(AppStrings.get('retry')),
            ),
          ],
        ),
      ),
    );
  }

  String _imageAssetPath(String imageName) {
    final normalized =
        imageName.startsWith('/') ? imageName.substring(1) : imageName;
    return normalized.startsWith('img_sign/')
        ? 'images/$normalized'
        : normalized;
  }

  String _languageLabel(String code) {
    const labels = {
      'zh': '简体中文',
      'en': 'English',
      'ru': 'Русский',
      'uk': 'Українська',
      'pa': 'ਪੰਜਾਬੀ',
      'ur': 'اردو',
    };
    return labels[code] ?? code.toUpperCase();
  }

  /// 网页端文案统一由 [AppStrings] 提供，六种界面语言与 App 保持一致。
  static const Map<String, String> _webStringKeys = {
    'signIn': 'web_sign_in',
    'signOut': 'sign_out',
    'startChapter': 'web_start_chapter',
    'continueChapter': 'web_continue_chapter',
    'guestSaved': 'web_guest_saved',
    'cloudSaved': 'web_cloud_saved',
    'syncUnavailable': 'web_sync_unavailable',
    'chapterOne': 'web_chapter_one',
    'chapterProgress': 'web_chapter_progress',
    'landingSubhead': 'web_landing_subhead',
    'availableTools': 'web_available_tools',
    'hintListen': 'web_hint_listen',
    'hintTranslate': 'web_hint_translate',
    'hintExplanation': 'web_hint_explanation',
    'hintSync': 'web_hint_sync',
    'sync': 'web_sync_label',
    'local': 'web_sync_local',
    'active': 'web_sync_active',
    'overview': 'web_overview',
    'hubSubtitle': 'web_hub_subtitle',
    'randomPracticeDescription': 'web_random_practice_description',
    'chapterPracticeDescription': 'web_chapter_practice_description',
    'examDescription': 'web_exam_description',
    'mistakeDescription': 'web_mistake_description',
    'noMistakeDescription': 'web_no_mistake_description',
    'favoriteDescription': 'web_favorite_description',
    'noFavoriteDescription': 'web_no_favorite_description',
    'emptyFavoritesTitle': 'empty_favorites_title',
    'emptyFavoritesDescription': 'web_empty_favorites_description',
    'skipMasteredDescription': 'web_skip_mastered_description',
    'signInToSync': 'web_sign_in_to_sync',
    'resetProgressDescription': 'web_reset_progress_description',
    'openLinkFailed': 'open_link_failed',
    'masteryReportDescription': 'web_mastery_report_description',
    'dailyPlanDescription': 'web_daily_plan_description',
    'chooseDailyGoal': 'web_choose_daily_goal',
    'todayPlanProgress': 'web_today_plan_progress',
    'newQuestions': 'daily_goal_new_questions',
    'reviewQuestions': 'daily_goal_review_questions',
    'todayPlanComplete': 'web_today_plan_complete',
    'startTodayPlan': 'web_start_today_plan',
    'bankCoverage': 'web_bank_coverage',
    'startMistakePractice': 'web_start_mistake_practice',
    'submitExamConfirmation': 'web_submit_exam_confirmation',
    'correctAnswers': 'correct',
    'reviewExam': 'web_review_exam',
    'backHome': 'return_home',
    'chooseSignInMethod': 'web_choose_sign_in_method',
    'browserVoiceTitle': 'web_browser_voice_title',
    'browserVoiceDescription': 'web_browser_voice_description',
    'offlineTitle': 'web_offline_title',
    'offlineDescription': 'web_offline_description',
  };

  String _text(String language, String key) =>
      AppStrings.getWithLanguage(language, _webStringKeys[key] ?? key);
}

class _FeatureHint {
  const _FeatureHint({required this.icon, required this.label});

  final IconData icon;
  final String label;
}

class _FeatureHintChip extends StatelessWidget {
  const _FeatureHintChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFE3EAF3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: AppTheme.primary),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF526174),
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        color: AppTheme.primarySoft,
        borderRadius: BorderRadius.circular(30),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 17, color: AppTheme.primary),
          const SizedBox(width: 8),
          Text(
            text,
            style: const TextStyle(
              color: AppTheme.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricRow extends StatelessWidget {
  const _MetricRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 21, color: AppTheme.primary),
        const SizedBox(width: 12),
        Expanded(child: Text(label)),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w800)),
      ],
    );
  }
}

class _TranslationPanel extends StatelessWidget {
  const _TranslationPanel({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.primarySoft,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        text,
        textDirection: contentTextDirection(
          text,
          fallback: Directionality.of(context),
        ),
        style: const TextStyle(fontSize: 17, height: 1.5),
      ),
    );
  }
}

class _AnswerButton extends StatelessWidget {
  const _AnswerButton({
    required this.label,
    required this.answer,
    required this.selectedAnswer,
    required this.correctAnswer,
    required this.onPressed,
  });

  final String label;
  final bool answer;
  final bool? selectedAnswer;
  final bool correctAnswer;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    Color? background;
    Color foreground = AppTheme.ink;
    if (selectedAnswer != null) {
      if (answer == correctAnswer) {
        background = const Color(0xFFDCFCE7);
        foreground = const Color(0xFF167A45);
      } else if (selectedAnswer == answer) {
        background = const Color(0xFFFFE4E6);
        foreground = const Color(0xFFBE3344);
      }
    }

    return FilledButton(
      onPressed: selectedAnswer == null ? onPressed : null,
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(58),
        backgroundColor: background ?? const Color(0xFFF0F4F9),
        disabledBackgroundColor: background ?? const Color(0xFFF0F4F9),
        foregroundColor: foreground,
        disabledForegroundColor: foreground,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
      child: Text(
        label,
        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
      ),
    );
  }
}

class _HubFeatureCard extends StatelessWidget {
  const _HubFeatureCard({
    required this.icon,
    required this.iconColor,
    required this.iconBackground,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.badge,
  });

  final IconData icon;
  final Color iconColor;
  final Color iconBackground;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: const BorderSide(color: Color(0xFFE3EAF3)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: iconBackground,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(icon, color: iconColor),
                  ),
                  const Spacer(),
                  if (badge != null)
                    CircleAvatar(
                      radius: 16,
                      backgroundColor: AppTheme.danger,
                      child: Text(
                        badge!,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.ink,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                subtitle,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Color(0xFF627084), height: 1.35),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HomeMetric extends StatelessWidget {
  const _HomeMetric({required this.label, required this.value, this.color});
  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) => Column(
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 25,
              fontWeight: FontWeight.w900,
              color: color ?? AppTheme.primary,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12, color: Color(0xFF627084)),
          ),
        ],
      );
}

class _CloudStatusBanner extends StatelessWidget {
  const _CloudStatusBanner({
    required this.signedIn,
    required this.unavailable,
    required this.text,
  });
  final bool signedIn;
  final bool unavailable;
  final String text;

  @override
  Widget build(BuildContext context) {
    final healthy = signedIn && !unavailable;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: healthy ? const Color(0xFFECFDF3) : const Color(0xFFFFF7ED),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(
            healthy ? Icons.cloud_done_rounded : Icons.cloud_off_rounded,
            color: healthy ? AppTheme.roadGreen : const Color(0xFFE28619),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}

class _WebPageFrame extends StatelessWidget {
  const _WebPageFrame({
    required this.title,
    required this.onBack,
    required this.child,
    this.trailing,
    this.maxWidth = 1000,
  });
  final String title;
  final VoidCallback onBack;
  final Widget child;
  final Widget? trailing;
  final double maxWidth;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        padding:
            EdgeInsets.all(MediaQuery.sizeOf(context).width < 700 ? 16 : 24),
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    IconButton(
                      tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                      onPressed: onBack,
                      icon: const Icon(Icons.arrow_back_rounded),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                          color: AppTheme.ink,
                        ),
                      ),
                    ),
                    if (trailing != null) trailing!,
                  ],
                ),
                const SizedBox(height: 20),
                child,
              ],
            ),
          ),
        ),
      );
}

class _ChapterCard extends StatelessWidget {
  const _ChapterCard({
    required this.chapterNumber,
    required this.title,
    required this.translation,
    required this.total,
    required this.practiced,
    required this.mastered,
    required this.locked,
    required this.onTap,
  });
  final int chapterNumber;
  final String title;
  final String translation;
  final int total;
  final int practiced;
  final int mastered;
  final bool locked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
        margin: EdgeInsets.zero,
        elevation: 0,
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: Color(0xFFE3EAF3)),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CircleAvatar(
                      backgroundColor: AppTheme.primarySoft,
                      child: Text('$chapterNumber'),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              color: AppTheme.ink,
                            ),
                          ),
                          Text(
                            translation,
                            style: const TextStyle(color: Color(0xFF627084)),
                          ),
                        ],
                      ),
                    ),
                    if (locked)
                      const Icon(Icons.lock_rounded, color: Color(0xFFE28619))
                    else
                      const Icon(Icons.chevron_right_rounded),
                  ],
                ),
                const SizedBox(height: 14),
                LinearProgressIndicator(
                  value: total == 0 ? 0 : practiced / total,
                  minHeight: 7,
                  borderRadius: BorderRadius.circular(99),
                ),
                const SizedBox(height: 8),
                Text(
                  '$practiced / $total · ${AppStrings.get('chapter_stat_mastered').replaceAll('{count}', '$mastered')}',
                  style:
                      const TextStyle(fontSize: 12, color: Color(0xFF627084)),
                ),
              ],
            ),
          ),
        ),
      );
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.message,
    required this.action,
  });
  final IconData icon;
  final String title;
  final String message;
  final Widget action;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 70),
        child: Column(
          children: [
            Icon(icon, size: 64, color: AppTheme.roadGreen),
            const SizedBox(height: 16),
            Text(
              title,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 20),
            action,
          ],
        ),
      );
}

class _MistakeListCard extends StatelessWidget {
  const _MistakeListCard({
    required this.number,
    required this.italian,
    required this.translation,
    required this.wrongCount,
    required this.onPractice,
    required this.onClear,
  });
  final int number;
  final String italian;
  final String? translation;
  final int wrongCount;
  final VoidCallback onPractice;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) => Card(
        elevation: 0,
        color: Colors.white,
        child: ListTile(
          onTap: onPractice,
          leading: CircleAvatar(child: Text('$number')),
          title: Text(
            italian,
            textDirection: TextDirection.ltr,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            '${translation ?? ''}\n× $wrongCount',
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: IconButton(
            tooltip: AppStrings.get('remove_from_mistakes'),
            onPressed: onClear,
            icon: const Icon(Icons.delete_outline_rounded),
          ),
        ),
      );
}

class _FavoriteListCard extends StatelessWidget {
  const _FavoriteListCard({
    required this.number,
    required this.italian,
    required this.translation,
    required this.practiceLabel,
    required this.explanationLabel,
    required this.onPractice,
    required this.onExplanation,
    required this.onRemove,
  });

  final int number;
  final String italian;
  final String? translation;
  final String practiceLabel;
  final String explanationLabel;
  final VoidCallback onPractice;
  final VoidCallback onExplanation;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) => Card(
        elevation: 0,
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFFE3EAF3)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(child: Text('$number')),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      italian,
                      textDirection: TextDirection.ltr,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    if (translation?.trim().isNotEmpty == true) ...[
                      const SizedBox(height: 6),
                      SizedBox(
                        width: double.infinity,
                        child: Text(
                          translation!,
                          textDirection: contentTextDirection(
                            translation!,
                            fallback: Directionality.of(context),
                          ),
                          style: const TextStyle(color: Color(0xFF627084)),
                        ),
                      ),
                    ],
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        TextButton.icon(
                          onPressed: onPractice,
                          icon: const Icon(Icons.play_arrow_rounded, size: 18),
                          label: Text(practiceLabel),
                        ),
                        TextButton.icon(
                          onPressed: onExplanation,
                          icon: const Icon(Icons.menu_book_outlined, size: 18),
                          label: Text(explanationLabel),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: AppStrings.get('unfavorite'),
                onPressed: onRemove,
                icon: const Icon(Icons.favorite_rounded),
                color: AppTheme.danger,
              ),
            ],
          ),
        ),
      );
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({
    required this.icon,
    required this.title,
    this.subtitle,
    this.iconColor = AppTheme.primary,
    this.trailing,
    this.child,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Color iconColor;
  final Widget? trailing;
  final Widget? child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Card(
        margin: EdgeInsets.zero,
        elevation: 0,
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: Color(0xFFE3EAF3)),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(icon, color: iconColor),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              color: AppTheme.ink,
                            ),
                          ),
                          if (subtitle?.isNotEmpty == true) ...[
                            const SizedBox(height: 3),
                            Text(
                              subtitle!,
                              style: const TextStyle(
                                color: Color(0xFF627084),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (trailing != null) trailing!,
                  ],
                ),
                if (child != null) ...[
                  const SizedBox(height: 14),
                  child!,
                ],
              ],
            ),
          ),
        ),
      );
}

class _ReportProgress extends StatelessWidget {
  const _ReportProgress({
    required this.label,
    required this.value,
    required this.detail,
    required this.color,
  });

  final String label;
  final double value;
  final String detail;
  final Color color;

  @override
  Widget build(BuildContext context) => Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              Text(
                detail,
                style: TextStyle(color: color, fontWeight: FontWeight.w800),
              ),
            ],
          ),
          const SizedBox(height: 7),
          LinearProgressIndicator(
            value: value.clamp(0, 1),
            minHeight: 9,
            borderRadius: BorderRadius.circular(99),
            color: color,
            backgroundColor: const Color(0xFFE7EEF7),
          ),
        ],
      );
}

class _PlanMetric extends StatelessWidget {
  const _PlanMetric({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFFF4F7FB),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          children: [
            Icon(icon, color: AppTheme.primary),
            const SizedBox(height: 6),
            Text(label, textAlign: TextAlign.center),
            const SizedBox(height: 3),
            Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ],
        ),
      );
}

class _ChapterCapabilityCard extends StatelessWidget {
  const _ChapterCapabilityCard({
    required this.capability,
    required this.title,
    required this.status,
    required this.detail,
    required this.locked,
    required this.onTap,
  });

  final ChapterCapability capability;
  final String title;
  final String status;
  final String detail;
  final bool locked;
  final VoidCallback onTap;

  Color get _color => switch (capability.state) {
        ChapterCapabilityState.notStarted => const Color(0xFF8290A3),
        ChapterCapabilityState.learning => AppTheme.primary,
        ChapterCapabilityState.needsAttention => AppTheme.danger,
        ChapterCapabilityState.stable => AppTheme.roadGreen,
      };

  @override
  Widget build(BuildContext context) => Card(
        margin: EdgeInsets.zero,
        elevation: 0,
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: Color(0xFFE3EAF3)),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: _color.withOpacity(0.12),
                      foregroundColor: _color,
                      child: Text('${capability.chapterId}'),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                          Text(status, style: TextStyle(color: _color)),
                        ],
                      ),
                    ),
                    if (locked)
                      const Icon(Icons.lock_rounded, color: Color(0xFFE28619))
                    else
                      const Icon(Icons.play_arrow_rounded),
                  ],
                ),
                const SizedBox(height: 12),
                LinearProgressIndicator(
                  value: capability.coverageRatio.clamp(0, 1),
                  minHeight: 7,
                  borderRadius: BorderRadius.circular(99),
                  color: _color,
                  backgroundColor: const Color(0xFFE7EEF7),
                ),
                const SizedBox(height: 7),
                Text(
                  detail,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF627084),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}

class _ExamHistoryRow extends StatelessWidget {
  const _ExamHistoryRow({required this.attempt, required this.passedLabel});

  final WebExamAttempt attempt;
  final String passedLabel;

  @override
  Widget build(BuildContext context) {
    final date = DateTime.fromMillisecondsSinceEpoch(attempt.completedAtMs);
    final dateLabel = LocaleFormat.date(AppStrings.getLanguage(), date);
    final minutes = attempt.timeUsedSeconds ~/ 60;
    final seconds = attempt.timeUsedSeconds % 60;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(
            attempt.passed ? Icons.check_circle_rounded : Icons.cancel_rounded,
            color: attempt.passed ? AppTheme.roadGreen : AppTheme.danger,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  passedLabel,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                Text(
                  '$dateLabel · $minutes:${seconds.toString().padLeft(2, '0')}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF627084),
                  ),
                ),
              ],
            ),
          ),
          Text(
            '${attempt.correctCount}/${attempt.totalQuestions}',
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
        ],
      ),
    );
  }
}

class _ExamTimer extends StatelessWidget {
  const _ExamTimer({required this.seconds});
  final int seconds;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: seconds < 60 ? const Color(0xFFFFECEE) : AppTheme.primarySoft,
          borderRadius: BorderRadius.circular(99),
        ),
        child: Text(
          '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}',
          style: TextStyle(
            fontWeight: FontWeight.w900,
            color: seconds < 60 ? AppTheme.danger : AppTheme.primary,
          ),
        ),
      );
}

class _ExamQuestionCard extends StatelessWidget {
  const _ExamQuestionCard({
    required this.question,
    required this.language,
    required this.selected,
    required this.onSelect,
    this.imagePath,
  });
  final Question question;
  final String language;
  final bool? selected;
  final ValueChanged<bool> onSelect;
  final String? imagePath;

  @override
  Widget build(BuildContext context) => Card(
        elevation: 0,
        color: Colors.white,
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                question.translations['it'] ?? '',
                textDirection: TextDirection.ltr,
                style: const TextStyle(fontSize: 22, height: 1.45),
              ),
              if (imagePath != null) ...[
                const SizedBox(height: 16),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 260),
                  child: Image.asset(imagePath!, fit: BoxFit.contain),
                ),
              ],
              if (language != 'it' &&
                  question.translations[language]?.isNotEmpty == true) ...[
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: Text(
                    question.translations[language]!,
                    textDirection: contentTextDirection(
                      question.translations[language]!,
                      fallback: Directionality.of(context),
                    ),
                    style: const TextStyle(color: Color(0xFF627084)),
                  ),
                ),
              ],
              const SizedBox(height: 22),
              SegmentedButton<bool>(
                emptySelectionAllowed: true,
                segments: const [
                  ButtonSegment(value: true, label: Text('VERO')),
                  ButtonSegment(value: false, label: Text('FALSO')),
                ],
                selected: selected == null ? {} : {selected!},
                onSelectionChanged: (value) => onSelect(value.first),
              ),
            ],
          ),
        ),
      );
}

class _ResultMetric extends StatelessWidget {
  const _ResultMetric({required this.label, required this.value, this.color});
  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) => Column(
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w900,
              color: color ?? AppTheme.ink,
            ),
          ),
          Text(label, style: const TextStyle(color: Color(0xFF627084))),
        ],
      );
}

class _ExamReviewCard extends StatelessWidget {
  const _ExamReviewCard({
    required this.number,
    required this.question,
    required this.language,
    required this.selected,
    required this.correct,
  });
  final int number;
  final Question question;
  final String language;
  final bool? selected;
  final bool correct;

  @override
  Widget build(BuildContext context) => Card(
        elevation: 0,
        color: Colors.white,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    backgroundColor: correct
                        ? AppTheme.roadGreenSoft
                        : const Color(0xFFFFECEE),
                    child: Icon(
                      correct ? Icons.check : Icons.close,
                      color: correct ? AppTheme.roadGreen : AppTheme.danger,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text('#$number',
                      style: const TextStyle(fontWeight: FontWeight.w800)),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                question.translations['it'] ?? '',
                textDirection: TextDirection.ltr,
              ),
              if (language != 'it') ...[
                const SizedBox(height: 6),
                SizedBox(
                  width: double.infinity,
                  child: Text(
                    question.translations[language] ?? '',
                    textDirection: contentTextDirection(
                      question.translations[language] ?? '',
                      fallback: Directionality.of(context),
                    ),
                    style: const TextStyle(color: Color(0xFF627084)),
                  ),
                ),
              ],
              const SizedBox(height: 10),
              Text(
                '${AppStrings.getWithLanguage(language, 'web_your_answer')}: ${selected == null ? '—' : selected! ? 'VERO' : 'FALSO'} · ${AppStrings.getWithLanguage(language, 'modal_correct_answer_label')}: ${question.answer ? 'VERO' : 'FALSO'}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
      );
}
