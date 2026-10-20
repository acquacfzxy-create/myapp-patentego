import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../services/database_service.dart';
import '../services/firebase_status.dart';
import '../services/practice_auto_advance.dart';
import '../models/chapter_capability.dart';
import '../models/question.dart';
import '../config/app_strings.dart';
import '../config/app_theme.dart';
import '../providers/user_state_provider.dart';
import '../widgets/question_widget.dart';
import '../widgets/session_mistake_review_sheet.dart';
import 'subscription_page.dart';

/// 練習模式頁面
/// 支持順序練習，顯示題目、圖片、解析等功能
/// 會員狀態恢復 / 升級後練習頁該做什麼。
enum PracticeVipAction { none, clearQuotaBlock, initialize }

/// 訂閱同步不得重置練習：已有題目時保留當前題、答案與進度，只解除額度攔截；
/// 只有確實沒有已載入的練習內容（且不在載入中）時才初始化。
@visibleForTesting
PracticeVipAction practiceActionAfterVipGained({
  required bool hasLoadedQuestion,
  required bool isLoading,
  required bool quotaExceeded,
}) {
  if (hasLoadedQuestion) {
    return quotaExceeded ? PracticeVipAction.clearQuotaBlock : PracticeVipAction.none;
  }
  return isLoading ? PracticeVipAction.none : PracticeVipAction.initialize;
}

class PracticeScreen extends StatefulWidget {
  final bool skipMastered;
  final int? chapterId; // 章節ID（可選），如果提供則只顯示該章節的題目
  final List<Question>? questions; // 預設題目列表（可選），用於錯題複習模式
  final bool isMistakeMode; // 是否為錯題複習模式
  final ChapterCapability? strengtheningStart;
  final int strengtheningQuestionLimit;

  const PracticeScreen({
    super.key,
    this.skipMastered = false,
    this.chapterId,
    this.questions,
    this.isMistakeMode = false,
    this.strengtheningStart,
    this.strengtheningQuestionLimit = 10,
  });

  @override
  State<PracticeScreen> createState() => _PracticeScreenState();
}

class _PracticeScreenState extends State<PracticeScreen> {
  Question? _currentQuestion;
  bool _isLoading = true;

  // 會話記錄：記錄本次練習中每道題的答題結果（Key: 題目索引, Value: 是否答對）
  // 使用此 Map 來防止重複統計，確保統計數字準確
  final Map<int, bool> _sessionRecords = {};
  final Map<String, SessionMistake> _sessionMistakes = {};
  final _autoAdvance = PracticeAutoAdvance();
  bool _isSessionReviewOpen = false;
  int _newlyMasteredCount = 0;
  int _mistakesResolvedCount = 0;

  // 返回處理狀態，避免 bottom sheet 或程式化 pop 觸發遞迴
  bool _isExitSummaryOpen = false;
  bool _isStrengtheningSummaryOpen = false;
  bool _isLeaving = false;

  late bool _skipMastered; // 使用 State 變量來管理，以便在運行時切換

  // 章節練習模式：預加載的題目列表（優化性能，避免每次都查詢數據庫）
  List<Question>? _chapterQuestions;
  int _currentIndex = 0; // 當前題目在列表中的索引

  // 答案狀態管理：存儲每道題的用戶選擇（questionId -> selectedAnswer, null表示未選擇）
  final Map<String, bool?> _answerStates = {};

  // 答题状态相关（仅用于 UI 反馈）
  bool _isAnswered = false; // 是否已点击答案
  bool? _isCorrect; // 答案是否正确
  bool? _userChoice; // 用户选的是 Vero 还是 Falso
  bool _showFavoriteBadge = false; // 是否显示收藏气泡
  bool _showMasteredBadge = false; // 是否显示精通气泡
  bool _hideCorrectBadge = false; // 是否隐藏"正确"气泡（当显示精通气泡时）
  bool _mistakeEliminated = false; // 错题是否已彻底消灭（wrong_count 降到 0）
  int _sessionCorrectStreak = 0; // 本次練習連續答對題數
  int _questionMasteryStep = 0; // 當前題目的掌握進度（0-3）
  bool _isProcessingAnswer = false; // 防止資料寫入期間重複作答

  // 隨機模式：題目預加載列表（用於導航和性能優化）
  final List<Question> _questionHistory = [];

  // 預加載標記，防止重複預加載
  bool _isPreloadingRandomQuestions = false;

  // 掌握度統計更新延遲（避免頻繁查詢數據庫）
  DateTime? _lastMasteryStatsUpdate;
  static const Duration _masteryStatsUpdateInterval = Duration(seconds: 2);

  // 記錄上一次的 VIP 狀態（用於檢測狀態變化）
  bool? _previousIsVip;

  // 標記是否已初始化（避免 didChangeDependencies 重複初始化）
  bool _hasInitialized = false;

  /// 是否因免費額度用盡而無法加載題目（用於顯示友好占位文案，避免白屏生硬提示）
  bool _quotaExceeded = false;

  // 當前語言（從 Provider 獲取，向後兼容 AppStrings）
  String get _currentLanguage =>
      Provider.of<UserStateProvider>(context, listen: false).currentLanguage;

  bool get _isStrengtheningMode => widget.strengtheningStart != null;

  bool get _usesFixedQuestionList =>
      widget.chapterId != null || widget.questions != null;

  /// 所有練習模式都以本次會話的第一次選擇為準。
  /// 主題切換只能重建畫面，不得讓已答題回到可編輯狀態。
  void _syncAnswerStateForCurrentQuestion() {
    _autoAdvance.cancel();
    _autoAdvance.resume('reading');
    final question = _currentQuestion;
    final hasRecordedAnswer =
        question != null && _answerStates.containsKey(question.id);
    final recordedChoice =
        hasRecordedAnswer ? _answerStates[question.id] : null;

    _isAnswered = hasRecordedAnswer;
    _isCorrect = hasRecordedAnswer ? recordedChoice == question.answer : null;
    _userChoice = recordedChoice;
    _showFavoriteBadge = false;
    _showMasteredBadge = false;
    // 回看時只保留當時選項，不重新播放答題氣泡。
    _hideCorrectBadge = hasRecordedAnswer;
    _mistakeEliminated = false;
    _questionMasteryStep = 0;
  }

  @override
  void dispose() {
    _autoAdvance.dispose();
    super.dispose();
  }

  void _onReadingChanged(bool reading) {
    if (reading) {
      _autoAdvance.pause('reading');
    } else {
      _autoAdvance.resume('reading');
    }
  }

  Future<void> _showSessionReview() async {
    if (!mounted || _isSessionReviewOpen || _sessionMistakes.isEmpty) return;
    _isSessionReviewOpen = true;
    _autoAdvance.pause('review');
    try {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => SessionMistakeReviewSheet(
          mistakes: List.unmodifiable(_sessionMistakes.values),
          language: _currentLanguage,
        ),
      );
    } finally {
      _isSessionReviewOpen = false;
      if (mounted) _autoAdvance.resume('review');
    }
  }

  @override
  void initState() {
    super.initState();
    _skipMastered = widget.skipMastered;
    // 不在 initState 中使用 Provider，移到 didChangeDependencies
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    // 只在第一次調用時初始化；延遲到下一幀執行，避免點擊「練習」時阻塞導航
    if (!_hasInitialized) {
      _hasInitialized = true;
      final userStateProvider =
          Provider.of<UserStateProvider>(context, listen: false);
      _previousIsVip = userStateProvider.isVip;
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (mounted) _initializeQuestions();
      });
    }
  }

  /// 初始化題目列表（章節練習模式預加載，隨機模式動態加載）
  Future<void> _initializeQuestions() async {
    if (_isStrengtheningMode && widget.chapterId != null) {
      await _loadStrengtheningQuestions();
    } else if (widget.questions != null && widget.questions!.isNotEmpty) {
      // 錯題複習模式：使用傳入的題目列表
      setState(() {
        _chapterQuestions = List.from(widget.questions!);
        _currentIndex = 0;
        _currentQuestion =
            _chapterQuestions!.isNotEmpty ? _chapterQuestions![0] : null;
        _isLoading = false;
      });
    } else if (widget.chapterId != null) {
      // 章節練習模式：預加載整個章節的題目列表
      await _loadChapterQuestions();
    } else {
      // 隨機模式：預加載一批題目（100道）
      _preloadRandomQuestionsBatch();
    }
  }

  Future<void> _loadStrengtheningQuestions() async {
    final userStateProvider =
        Provider.of<UserStateProvider>(context, listen: false);
    await userStateProvider.checkAndResetDailyCounters();
    if (!mounted) return;
    if (!userStateProvider.canPractice()) {
      setState(() => _isLoading = false);
      _showQuizLimitDialog();
      return;
    }

    setState(() => _isLoading = true);
    try {
      final questions = await DatabaseService.getChapterStrengtheningQuestions(
        chapterId: widget.chapterId!,
        userId: userStateProvider.effectiveUserId,
        translationLang: _currentLanguage != 'it' ? _currentLanguage : 'it',
        limit: widget.strengtheningQuestionLimit,
      );
      if (!mounted) return;
      setState(() {
        _chapterQuestions = questions;
        _currentIndex = 0;
        _currentQuestion = questions.isEmpty ? null : questions.first;
        _isLoading = false;
      });
      if (questions.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppStrings.get('no_questions_in_chapter'))),
        );
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${AppStrings.get('failed_to_load')}: $error')),
      );
    }
  }

  /// 預加載章節題目列表（只在初始化時調用一次）
  Future<void> _loadChapterQuestions() async {
    // 檢查刷題限額（非VIP用戶每日限額30題）
    final userStateProvider =
        Provider.of<UserStateProvider>(context, listen: false);
    final effectiveUserId = userStateProvider.effectiveUserId;
    await userStateProvider.checkAndResetDailyCounters();
    if (!userStateProvider.canPractice()) {
      // 達到限額，顯示訂閱引導彈窗
      setState(() {
        _isLoading = false;
      });
      _showQuizLimitDialog();
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final questions = await DatabaseService.getQuestionsByChapter(
        widget.chapterId!,
        skipMastered: _skipMastered,
        translationLang: _currentLanguage != 'it' ? _currentLanguage : 'it',
        userId: effectiveUserId,
      );

      if (questions.isEmpty) {
        if (mounted) {
          if (_skipMastered) {
            _showAllMasteredDialog();
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(AppStrings.get('no_questions_in_chapter')),
                duration: const Duration(seconds: 2),
              ),
            );
          }
        }
        setState(() {
          _isLoading = false;
        });
        return;
      }

      // 隨機打亂題目順序
      questions.shuffle();

      setState(() {
        _chapterQuestions = questions;
        _currentIndex = 0;
        _currentQuestion = questions.isNotEmpty ? questions[0] : null;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${AppStrings.get('failed_to_load')}: $e')),
        );
      }
    }
  }

  /// 加載題目（使用意大利語）
  /// 檢查刷題限額：非VIP用戶每日限額30題
  Future<void> _loadQuestion() async {
    // 檢查刷題限額（非VIP用戶每日限額30題）
    final userStateProvider =
        Provider.of<UserStateProvider>(context, listen: false);
    final effectiveUserId = userStateProvider.effectiveUserId;
    await userStateProvider.checkAndResetDailyCounters();
    if (!userStateProvider.canPractice()) {
      // 達到限額，顯示訂閱引導彈窗
      setState(() {
        _isLoading = false;
      });
      _showQuizLimitDialog();
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      Question? questionIt;

      // 如果指定了章節ID，使用章節練習模式
      if (widget.chapterId != null) {
        questionIt = await DatabaseService.getRandomQuestionFromChapter(
          widget.chapterId!,
          skipMastered: _skipMastered,
          translationLang: 'it',
          userId: effectiveUserId,
        );
      } else {
        // 隨機模式：先獲取意大利語題目，再獲取翻譯
        // 使用 getQuestions 並傳遞 skipMastered 參數
        final allQuestions = await DatabaseService.getQuestions(
          lang: 'it',
          skipMastered: _skipMastered,
          userId: effectiveUserId,
        );

        if (allQuestions.isEmpty) {
          setState(() {
            _isLoading = false;
          });

          if (mounted) {
            // 如果是跳過已掌握模式且沒有題目，顯示對話框
            if (_skipMastered) {
              _showAllMasteredDialog();
            } else {
              // 如果不是跳過模式，顯示普通錯誤提示
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(AppStrings.get('failed_to_load_question')),
                  duration: const Duration(seconds: 2),
                ),
              );
            }
          }
          return;
        }

        // 隨機選擇一道題目
        allQuestions.shuffle();
        questionIt = allQuestions.first;
      }

      // 如果題目不存在
      if (questionIt == null) {
        setState(() {
          _isLoading = false;
        });

        if (mounted) {
          // 如果是跳過已掌握模式且沒有題目，顯示對話框
          if (_skipMastered) {
            _showAllMasteredDialog();
          } else {
            // 如果不是跳過模式，顯示普通錯誤提示
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(widget.chapterId != null
                    ? AppStrings.get('no_questions_in_chapter')
                    : AppStrings.get('failed_to_load_question')),
                duration: const Duration(seconds: 2),
              ),
            );
          }
        }
        return;
      }

      // 獲取翻譯（如果需要的話）
      // 注意：如果 chapterId 不為 null，getRandomQuestionFromChapter 已經返回了翻譯
      Question question;
      if (_currentLanguage != 'it') {
        // 檢查 questionIt 是否已經包含當前語言的翻譯
        if (questionIt.translations.containsKey(_currentLanguage)) {
          // 已經有翻譯，直接使用
          question = questionIt;
        } else {
          // 需要獲取翻譯
          final translatedQuestion = await DatabaseService.getQuestionById(
            questionIt.id,
            lang: _currentLanguage,
          );
          if (translatedQuestion != null) {
            question = questionIt.mergeLanguages(translatedQuestion);
          } else {
            question = questionIt;
          }
        }
      } else {
        question = questionIt;
      }

      // 題目加載成功
      setState(() {
        _currentQuestion = question;
        _isLoading = false;

        // 隨機模式：將題目添加到歷史列表（如果還沒有）
        if (widget.chapterId == null) {
          final existingIndex =
              _questionHistory.indexWhere((q) => q.id == question.id);
          if (existingIndex >= 0) {
            // 如果題目已存在，切換到該索引
            _currentIndex = existingIndex;
          } else {
            // 新題目，添加到歷史列表
            _questionHistory.add(question);
            _currentIndex = _questionHistory.length - 1;
          }
        }
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${AppStrings.get('failed_to_load')}: $e')),
        );
      }
    }
  }

  /// 預加載隨機題目批次（100道題，優化性能）
  Future<void> _preloadRandomQuestionsBatch() async {
    // 防止重複預加載
    if (_isPreloadingRandomQuestions || widget.chapterId != null) return;

    _isPreloadingRandomQuestions = true;

    // 如果是第一次加載或列表已空，顯示加載圈
    final isFirstLoad = _questionHistory.isEmpty;
    if (isFirstLoad) {
      setState(() {
        _isLoading = true;
      });
    }

    try {
      final userStateProvider =
          Provider.of<UserStateProvider>(context, listen: false);
      final effectiveUserId = userStateProvider.effectiveUserId;

      // 檢查刷題限額
      await userStateProvider.checkAndResetDailyCounters();
      if (!userStateProvider.canPractice()) {
        if (isFirstLoad) {
          setState(() {
            _isLoading = false;
          });
        }
        _showQuizLimitDialog();
        _isPreloadingRandomQuestions = false;
        return;
      }

      // 獲取已存在的題目ID，避免重複
      final existingIds = _questionHistory.map((q) => q.id).toSet();

      // 預加載100道題目（一次性批量查詢，性能更好）
      final preloadedQuestions = await DatabaseService.getRandomQuestionsBatch(
        count: 100,
        translationLang: _currentLanguage != 'it' ? _currentLanguage : 'it',
        skipMastered: _skipMastered,
        userId: effectiveUserId,
        excludeIds: existingIds,
      );

      if (preloadedQuestions.isNotEmpty && mounted) {
        setState(() {
          // 將預加載的題目添加到歷史列表
          // 注意：題目已經在 DatabaseService 中被打亂，這裡直接添加即可
          _questionHistory.addAll(preloadedQuestions);

          // 如果是第一次加載，設置當前題目
          if (isFirstLoad) {
            _currentQuestion = _questionHistory.first;
            _currentIndex = 0;
          }

          _isLoading = false;
        });
      } else if (preloadedQuestions.isEmpty && mounted) {
        // 沒有更多題目了
        setState(() {
          _isLoading = false;
        });

        if (_skipMastered && _questionHistory.isEmpty) {
          _showAllMasteredDialog();
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        if (isFirstLoad) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text(
                    '${AppStrings.getWithLanguage(_currentLanguage, 'failed_to_load')}: $e')),
          );
        }
      }
    } finally {
      _isPreloadingRandomQuestions = false;
    }
  }

  /// 顯示全部已掌握對話框
  Future<void> _showAllMasteredDialog() async {
    if (!mounted) return;

    final result = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(AppStrings.getWithLanguage(
              _currentLanguage, 'all_questions_mastered')),
          content: Text(AppStrings.getWithLanguage(
              _currentLanguage, 'all_questions_mastered')),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(false); // 取消，返回上一頁
              },
              child:
                  Text(AppStrings.getWithLanguage(_currentLanguage, 'cancel')),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop(true); // 確認，切換到重溫模式
              },
              child: Text(AppStrings.getWithLanguage(
                  _currentLanguage, 'review_mastered')),
            ),
          ],
        );
      },
    );

    if (result == true && mounted) {
      // 用戶選擇切換到重溫模式
      setState(() {
        _skipMastered = false;
      });
      // 重新加載題目
      _loadQuestion();
    } else if (result == false && mounted) {
      // 用戶選擇取消，返回上一頁
      _leavePractice();
    }
  }

  /// 處理答案選擇
  Future<void> _onAnswerSelected(bool selectedAnswer) async {
    if (_currentQuestion == null ||
        _isAnswered ||
        _isProcessingAnswer ||
        _answerStates.containsKey(_currentQuestion!.id)) {
      return;
    }

    _isProcessingAnswer = true;
    final answeredQuestion = _currentQuestion!;
    final answeredIndex = _currentIndex;
    final isCorrect = selectedAnswer == answeredQuestion.answer;

    try {
      // 同時取得答題前狀態；掌握進度沿用既有「連對 3 次」規則。
      final userStateProvider =
          Provider.of<UserStateProvider>(context, listen: false);
      final wasAlreadyMasteredFuture = DatabaseService.isQuestionMastered(
        answeredQuestion.id,
        userId: userStateProvider.effectiveUserId,
      );
      final questionCorrectStreakFuture =
          DatabaseService.getQuestionCorrectStreak(
        answeredQuestion.id,
        userId: userStateProvider.effectiveUserId,
      );
      final strengtheningWrongCountFuture = _isStrengtheningMode
          ? DatabaseService.getWrongCount(
              answeredQuestion.id,
              userId: userStateProvider.effectiveUserId,
            )
          : Future<int>.value(0);

      final wasAlreadyMastered = await wasAlreadyMasteredFuture;
      final questionCorrectStreak = await questionCorrectStreakFuture;
      final strengtheningWrongCount = await strengtheningWrongCountFuture;
      if (!mounted || _currentQuestion?.id != answeredQuestion.id) return;

      // 保存答案狀態
      _answerStates[answeredQuestion.id] = selectedAnswer;

      // **錯題模式特殊處理：如果答對了，減少錯誤次數**
      bool mistakeEliminated = false;
      if (widget.isMistakeMode && isCorrect) {
        final remainingWrongCount = await DatabaseService.decreaseErrorCount(
          answeredQuestion.id,
          userId: userStateProvider.effectiveUserId,
        );
        // 如果 wrong_count 降到 0，標記為已徹底消滅
        mistakeEliminated = remainingWrongCount == 0;

        // 刷新錯題統計（用於返回時更新列表）
        userStateProvider.refreshMistakeCount();
      } else if (_isStrengtheningMode && isCorrect) {
        // 一般進度更新會把 wrong_count 減 1；原值為 1 代表本題將被消除。
        mistakeEliminated = strengtheningWrongCount == 1;
      }

      // 使用統一的進度更新方法
      final newlyMastered = await userStateProvider.updateQuestionProgress(
        answeredQuestion.id,
        isCorrect,
        mistakeResolved: mistakeEliminated,
      );
      if (!mounted || _currentQuestion?.id != answeredQuestion.id) return;

      // 優化：延遲批量更新掌握度統計（避免頻繁掃描整個 user_progress 表）
      final now = DateTime.now();
      final shouldUpdateStats = newlyMastered ||
          _lastMasteryStatsUpdate == null ||
          now.difference(_lastMasteryStatsUpdate!) >
              _masteryStatsUpdateInterval;

      if (shouldUpdateStats) {
        _lastMasteryStatsUpdate = now;
        userStateProvider.refreshMasteryStats().catchError((_) {});
      }

      final shouldHideCorrectBadge =
          isCorrect && (newlyMastered || wasAlreadyMastered);
      final nextMasteryStep = isCorrect
          ? (newlyMastered || wasAlreadyMastered)
              ? 3
              : (questionCorrectStreak + 1).clamp(0, 3).toInt()
          : 0;

      // 一次性設置所有狀態，避免「正確」與「已掌握」氣泡交替閃現。
      setState(() {
        _isAnswered = true;
        _isCorrect = isCorrect;
        _userChoice = selectedAnswer;
        _mistakeEliminated = mistakeEliminated;
        _questionMasteryStep = nextMasteryStep;
        _sessionCorrectStreak = isCorrect ? _sessionCorrectStreak + 1 : 0;
        if (newlyMastered) _newlyMasteredCount++;
        if (mistakeEliminated) _mistakesResolvedCount++;

        // 記錄當前題目的答題結果，返回重做時不重複增加結算題數。
        _sessionRecords[answeredIndex] = isCorrect;
        if (!isCorrect) {
          _sessionMistakes.putIfAbsent(
            answeredQuestion.id,
            () => SessionMistake(
              question: answeredQuestion,
              selectedAnswer: selectedAnswer,
            ),
          );
        }

        if (shouldHideCorrectBadge) {
          _showMasteredBadge = true;
          _hideCorrectBadge = true;
        } else {
          _showMasteredBadge = false;
          _hideCorrectBadge = false;
        }
      });

      // 普通答對保持輕量；真正達成掌握或消除錯題時才加強觸感。
      if (newlyMastered || mistakeEliminated) {
        HapticFeedback.mediumImpact();
      } else if (isCorrect) {
        HapticFeedback.lightImpact();
      } else {
        HapticFeedback.selectionClick();
      }

      // 检查是否已收藏，显示收藏气泡
      final isFav = await DatabaseService.isFavorite(
        answeredQuestion.id,
        userId: userStateProvider.effectiveUserId,
      );
      if (isFav && mounted && _currentQuestion?.id == answeredQuestion.id) {
        setState(() => _showFavoriteBadge = true);
      }

      // 閱讀、回看和結算期間暫停；關閉後重新給足原有的回饋時間。
      _autoAdvance.schedule(() {
        if (!mounted || _isLeaving ||
            _currentQuestion?.id != answeredQuestion.id) {
          return;
        }
        if (widget.questions != null && !_hasNextQuestion) {
          unawaited(_handleExitRequest());
        } else {
          unawaited(_nextQuestion());
        }
      });
    } finally {
      _isProcessingAnswer = false;
    }
  }

  /// 顯示刷題限額彈窗（Paywall）
  /// 關閉時若用戶選擇「返回首頁」或點擊關閉按鈕，則 popUntil 回到首頁，避免留在空白練習頁
  Future<void> _showQuizLimitDialog() async {
    if (!mounted) return;
    setState(() => _quotaExceeded = true);
    final isLoggedIn = FirebaseStatus.isSignedIn;
    final lang = _currentLanguage;
    final colorScheme = Theme.of(context).colorScheme;
    final primaryColor = AppTheme.primaryFor(context);
    final message = isLoggedIn
        ? AppStrings.getWithLanguage(lang, 'quiz_limit_body_logged_in')
        : AppStrings.getWithLanguage(lang, 'quiz_limit_body_guest');

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false, // 不可點擊外部關閉，強制用戶選擇
      builder: (dialogContext) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.lock, color: primaryColor, size: 28),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                AppStrings.getWithLanguage(lang, 'quiz_limit_reached'),
                style:
                    const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
            ),
            IconButton(
              tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
              icon: const Icon(Icons.close, size: 20),
              onPressed: () {
                Navigator.of(dialogContext)
                    .pop(false); // 與「返回首頁」一致，關閉後 popUntil
              },
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(message, style: const TextStyle(fontSize: 16)),
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 16),
              _buildFeatureItem(Icons.all_inclusive,
                  AppStrings.getWithLanguage(lang, 'unlock_all_chapters')),
              const SizedBox(height: 8),
              _buildFeatureItem(Icons.star,
                  AppStrings.getWithLanguage(lang, 'ad_free_experience')),
              const SizedBox(height: 8),
              _buildFeatureItem(Icons.trending_up,
                  AppStrings.getWithLanguage(lang, 'detailed_stats')),
            ],
          ),
        ),
        actions: [
          if (_sessionMistakes.isNotEmpty)
            TextButton.icon(
              key: const Key('session_quota_review'),
              onPressed: _showSessionReview,
              icon: const Icon(Icons.history),
              label: Text(AppStrings.getWithLanguage(
                lang, 'session_mistakes_review',
              ).replaceAll('{count}', '${_sessionMistakes.length}')),
            ),
          TextButton(
            onPressed: () {
              Navigator.of(dialogContext).pop(false);
            },
            child: Text(AppStrings.getWithLanguage(lang, 'return_home')),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(dialogContext).pop(true);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: primaryColor,
              foregroundColor: colorScheme.onPrimary,
            ),
            child:
                Text(AppStrings.getWithLanguage(lang, 'go_subscribe_unlock')),
          ),
        ],
      ),
    );

    if (!mounted) return;

    if (result == true) {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => const SubscriptionPage(),
        ),
      );
      if (mounted) {
        final updatedProvider =
            Provider.of<UserStateProvider>(context, listen: false);
        if (!updatedProvider.isVip) {
          _leavePractice(toRoot: true);
        }
      }
    } else {
      // result == false 或 null：返回首頁，避免留在空白練習頁
      _leavePractice(toRoot: true);
    }
  }

  /// 直接離開練習頁，供限額或無題目等既有流程使用。
  void _leavePractice({bool toRoot = false, Object? result}) {
    if (!mounted || _isLeaving) return;
    _autoAdvance.cancel();
    setState(() => _isLeaving = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (toRoot) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      } else {
        Navigator.of(context).pop(result);
      }
    });
  }

  /// 顯示本次練習結算；繼續練習只關閉 bottom sheet，結束才離開頁面。
  Future<void> _handleExitRequest() async {
    if (!mounted || _isLeaving || _isExitSummaryOpen) return;
    if (_sessionRecords.isEmpty) {
      _leavePractice();
      return;
    }

    _isExitSummaryOpen = true;
    _autoAdvance.pause('summary');
    final language = _currentLanguage;
    final shouldFinish = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) {
        final colorScheme = Theme.of(sheetContext).colorScheme;
        final answeredCount = _sessionRecords.length;
        final correctCount =
            _sessionRecords.values.where((value) => value).length;
        final systemBottomInset = MediaQuery.viewPaddingOf(sheetContext).bottom;
        final bottomPadding =
            systemBottomInset > 0 ? systemBottomInset + 16 : 24.0;

        return Padding(
          padding: EdgeInsets.fromLTRB(24, 20, 24, bottomPadding),
          child: SingleChildScrollView(child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (AppTheme.usesRoadPalette && !AppTheme.isRetroFor(context))
                ..._buildRoadSummaryHeader(
                  sheetContext,
                  language: language,
                  answeredCount: answeredCount,
                  correctCount: correctCount,
                )
              else ...[
              Text(
                AppStrings.getWithLanguage(
                    language, 'growth_session_summary_title'),
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: colorScheme.onSurface,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              _buildSummaryMetric(
                AppStrings.getWithLanguage(language, 'growth_session_answered'),
                answeredCount,
              ),
              _buildSummaryMetric(
                AppStrings.getWithLanguage(language, 'growth_session_correct'),
                correctCount,
                valueColor: AppTheme.successTextFor(context),
              ),
              _buildSummaryMetric(
                AppStrings.getWithLanguage(language, 'growth_newly_mastered'),
                _newlyMasteredCount,
              ),
              _buildSummaryMetric(
                AppStrings.getWithLanguage(
                    language, 'growth_mistakes_resolved'),
                _mistakesResolvedCount,
              ),
              ],
              const SizedBox(height: 16),
              if (_sessionMistakes.isNotEmpty) ...[
                FilledButton.icon(
                  key: const Key('session_summary_review'),
                  onPressed: _showSessionReview,
                  icon: const Icon(Icons.history),
                  label: Text(AppStrings.getWithLanguage(
                    language, 'session_mistakes_review',
                  ).replaceAll('{count}', '${_sessionMistakes.length}')),
                ),
                const SizedBox(height: 8),
              ],
              if (!(widget.questions != null && !_hasNextQuestion)) ...[
                OutlinedButton.icon(
                  onPressed: () => Navigator.of(sheetContext).pop(false),
                  icon: const Icon(Icons.play_arrow),
                  label: Text(AppStrings.getWithLanguage(
                      language, 'growth_continue_practice')),
                ),
                const SizedBox(height: 8),
              ],
              ElevatedButton.icon(
                onPressed: () => Navigator.of(sheetContext).pop(true),
                icon: const Icon(Icons.check),
                label: Text(AppStrings.getWithLanguage(
                    language, 'growth_finish_session')),
              ),
            ],
          )),
        );
      },
    );
    _isExitSummaryOpen = false;

    if (shouldFinish == true && mounted) {
      _leavePractice();
    } else if (mounted) {
      _autoAdvance.resume('summary');
    }
  }

  /// 道路主題的練習結算頭部：按正確率給一句鼓勵、大號正確率、
  /// 四格成績，以及本次獲得的貼紙（新掌握／消滅錯題）。
  List<Widget> _buildRoadSummaryHeader(
    BuildContext context, {
    required String language,
    required int answeredCount,
    required int correctCount,
  }) {
    String t(String key) => AppStrings.getWithLanguage(language, key);
    final ink = AppTheme.inkFor(context);
    final muted = AppTheme.mutedFor(context);
    final rate =
        answeredCount == 0 ? 0 : (correctCount * 100 / answeredCount).round();
    final cheerKey = rate >= 90
        ? 'session_cheer_great'
        : rate >= 70
            ? 'session_cheer_good'
            : 'session_cheer_keep';

    Widget tile(String label, int value, Color color) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: AppTheme.surfaceFor(context),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppTheme.lineFor(context), width: 1.5),
        ),
        child: Column(
          children: [
            Text(
              '$value',
              style: TextStyle(
                fontSize: 26,
                height: 1.1,
                fontWeight: FontWeight.w900,
                color: color,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: muted),
            ),
          ],
        ),
      );
    }

    Widget sticker(IconData icon, String text, Color color, double angle) {
      return Transform.rotate(
        angle: angle,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: AppTheme.surfaceFor(context),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: ink, width: 1.5),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 20, color: color),
              const SizedBox(width: 6),
              Text(
                text,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: ink,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final stickers = <Widget>[
      if (_newlyMasteredCount > 0)
        sticker(
          Icons.workspace_premium_rounded,
          '${t('growth_newly_mastered')} +$_newlyMasteredCount',
          AppTheme.warningTextFor(context),
          -0.035,
        ),
      if (_mistakesResolvedCount > 0)
        sticker(
          Icons.cleaning_services_rounded,
          '${t('growth_mistakes_resolved')} +$_mistakesResolvedCount',
          AppTheme.successFor(context),
          0.035,
        ),
    ];

    return [
      Text(
        t(cheerKey),
        key: const Key('session_summary_cheer'),
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w900,
          color: ink,
        ),
      ),
      const SizedBox(height: 4),
      Text(
        t('growth_session_summary_title'),
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 13, color: muted),
      ),
      const SizedBox(height: 14),
      Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
          decoration: BoxDecoration(
            color: AppTheme.accentFor(context),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: AppTheme.roadInk, width: 2),
          ),
          child: Text(
            '$rate%',
            style: TextStyle(
              fontSize: 30,
              height: 1.1,
              fontWeight: FontWeight.w900,
              color: AppTheme.onAccentFor(context),
            ),
          ),
        ),
      ),
      const SizedBox(height: 16),
      GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 1.9,
        children: [
          tile(t('growth_session_answered'), answeredCount, ink),
          tile(t('growth_session_correct'), correctCount,
              AppTheme.successTextFor(context)),
          tile(t('growth_newly_mastered'), _newlyMasteredCount,
              AppTheme.warningTextFor(context)),
          tile(t('growth_mistakes_resolved'), _mistakesResolvedCount,
              AppTheme.successTextFor(context)),
        ],
      ),
      if (stickers.isNotEmpty) ...[
        const SizedBox(height: 14),
        Wrap(
          key: const Key('session_summary_stickers'),
          alignment: WrapAlignment.center,
          spacing: 10,
          runSpacing: 10,
          children: stickers,
        ),
      ],
    ];
  }

  Widget _buildSummaryMetric(String label, int value, {Color? valueColor}) {
    final colorScheme = Theme.of(context).colorScheme;
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
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: valueColor ?? colorScheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _completeStrengtheningSession() async {
    if (!mounted || _isStrengtheningSummaryOpen || _isLeaving) return;
    _isStrengtheningSummaryOpen = true;

    final start = widget.strengtheningStart!;
    var updated = start;
    try {
      final userStateProvider =
          Provider.of<UserStateProvider>(context, listen: false);
      final stats = await DatabaseService.getChapterCapabilityStats(
        userId: userStateProvider.effectiveUserId,
      );
      for (final entry in stats) {
        if (entry['chapter'] == start.chapterId) {
          updated = ChapterCapability.fromMap(entry);
          break;
        }
      }
    } catch (_) {
      // 結算查詢失敗時仍允許結束任務，地圖返回後會再次刷新。
    }
    if (!mounted) return;

    final language = _currentLanguage;
    await showModalBottomSheet<void>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => SingleChildScrollView(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            24,
            20,
            24,
            MediaQuery.viewPaddingOf(sheetContext).bottom + 16,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(
                Icons.auto_graph,
                color: Theme.of(sheetContext).colorScheme.secondary,
                size: 32,
              ),
              const SizedBox(height: 10),
              Text(
                AppStrings.getWithLanguage(
                  language,
                  'chapter_strengthening_completed',
                ),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: Theme.of(sheetContext).colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 18),
              _buildSummaryChange(
                AppStrings.getWithLanguage(
                  language,
                  'chapter_strengthening_mastered_change',
                ),
                '${start.mastered}',
                '${updated.mastered}',
              ),
              _buildSummaryChange(
                AppStrings.getWithLanguage(
                  language,
                  'chapter_strengthening_mistakes_change',
                ),
                '${start.mistakes}',
                '${updated.mistakes}',
              ),
              _buildSummaryChange(
                AppStrings.getWithLanguage(
                  language,
                  'chapter_strengthening_state_change',
                ),
                _chapterCapabilityStateLabel(start.state, language),
                _chapterCapabilityStateLabel(updated.state, language),
              ),
              const SizedBox(height: 18),
              if (_sessionMistakes.isNotEmpty) ...[
                FilledButton.icon(
                  key: const Key('session_strengthening_review'),
                  onPressed: _showSessionReview,
                  icon: const Icon(Icons.history),
                  label: Text(AppStrings.getWithLanguage(
                    language, 'session_mistakes_review',
                  ).replaceAll('{count}', '${_sessionMistakes.length}')),
                ),
                const SizedBox(height: 8),
              ],
              ElevatedButton.icon(
                onPressed: () => Navigator.of(sheetContext).pop(),
                icon: const Icon(Icons.map_outlined),
                label: Text(
                  AppStrings.getWithLanguage(
                    language,
                    'chapter_strengthening_back_to_map',
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    _isStrengtheningSummaryOpen = false;
    if (mounted) {
      _leavePractice(result: start.chapterId);
    }
  }

  Widget _buildSummaryChange(
    String label,
    String before,
    String after,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(label),
          const SizedBox(height: 5),
          Row(
            children: [
              Expanded(
                child: Text(
                  before,
                  textAlign: TextAlign.end,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Icon(
                  Icons.arrow_forward,
                  size: 16,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              Expanded(
                child: Text(
                  after,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: AppTheme.successTextFor(context),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _chapterCapabilityStateLabel(
    ChapterCapabilityState state,
    String language,
  ) {
    switch (state) {
      case ChapterCapabilityState.notStarted:
        return AppStrings.getWithLanguage(
          language,
          'chapter_capability_not_started',
        );
      case ChapterCapabilityState.learning:
        return AppStrings.getWithLanguage(
          language,
          'chapter_capability_learning',
        );
      case ChapterCapabilityState.needsAttention:
        return AppStrings.getWithLanguage(
          language,
          'chapter_capability_needs_attention',
        );
      case ChapterCapabilityState.stable:
        return AppStrings.getWithLanguage(
          language,
          'chapter_capability_stable',
        );
    }
  }

  /// 構建功能列表項（用於限額彈窗）
  Widget _buildFeatureItem(IconData icon, String text) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(icon, size: 20, color: AppTheme.primaryFor(context)),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 14,
              color: colorScheme.onSurface,
            ),
          ),
        ),
      ],
    );
  }

  /// 切換到下一題（優化：章節練習使用索引切換，不重新查詢數據庫）
  /// 檢查刷題限額：非VIP用戶每日限額30題
  Future<void> _nextQuestion() async {
    _autoAdvance.cancel();
    if (_isStrengtheningMode &&
        _chapterQuestions != null &&
        _chapterQuestions!.isNotEmpty &&
        _currentIndex >= _chapterQuestions!.length - 1) {
      if (_sessionRecords.length >= _chapterQuestions!.length) {
        await _completeStrengtheningSession();
        return;
      }

      final unansweredIndex = List<int>.generate(
        _chapterQuestions!.length,
        (index) => index,
      ).firstWhere(
        (index) => !_sessionRecords.containsKey(index),
        orElse: () => -1,
      );
      if (unansweredIndex >= 0) {
        setState(() {
          _currentIndex = unansweredIndex;
          _currentQuestion = _chapterQuestions![unansweredIndex];
          _syncAnswerStateForCurrentQuestion();
        });
        return;
      }
    }

    // 重置答题状态（用于 UI 反馈）
    setState(() {
      _syncAnswerStateForCurrentQuestion();
    });

    // 檢查刷題限額（非VIP用戶每日限額30題）
    final userStateProvider =
        Provider.of<UserStateProvider>(context, listen: false);
    await userStateProvider.checkAndResetDailyCounters();
    if (!userStateProvider.canPractice()) {
      // 達到限額，顯示訂閱引導彈窗
      _showQuizLimitDialog();
      return;
    }

    if (_usesFixedQuestionList && _chapterQuestions != null) {
      // 章節練習模式：從預加載的列表中切換（不查詢數據庫）
      setState(() {
        _currentIndex++;

        // 章節練習沿用循環；每日計畫等傳入題組保持有限清單。
        if (_currentIndex >= _chapterQuestions!.length) {
          if (widget.questions != null) {
            _currentIndex = _chapterQuestions!.length - 1;
            _currentQuestion = _chapterQuestions![_currentIndex];
          } else if (_skipMastered) {
            _loadChapterQuestions();
          } else {
            _currentIndex = 0;
            _currentQuestion = _chapterQuestions![_currentIndex];
          }
        } else {
          _currentQuestion = _chapterQuestions![_currentIndex];
        }
        _syncAnswerStateForCurrentQuestion();
      });
    } else {
      // 隨機模式：優先從內存列表獲取
      if (_currentIndex < _questionHistory.length - 1) {
        // 內存中有下一題，直接切換（無需數據庫查詢，非常快）
        setState(() {
          _currentIndex++;
          _currentQuestion = _questionHistory[_currentIndex];
          _syncAnswerStateForCurrentQuestion();
        });

        // 異步預加載：當做到第80題時，預加載下一批（確保用戶感覺不到數據庫查詢）
        if (_currentIndex >= 80 && !_isPreloadingRandomQuestions) {
          _preloadRandomQuestionsBatch();
        }
      } else {
        // 內存中沒有下一題，顯示加載圈並預加載下一批
        _preloadRandomQuestionsBatch();
      }
    }
  }

  /// 切換到上一題
  void _previousQuestion() {
    _autoAdvance.cancel();
    if (_usesFixedQuestionList && _chapterQuestions != null) {
      // 章節練習模式
      if (_currentIndex > 0) {
        setState(() {
          _currentIndex--;
          _currentQuestion = _chapterQuestions![_currentIndex];
          _syncAnswerStateForCurrentQuestion();
        });
      }
    } else {
      // 隨機模式
      if (_currentIndex > 0) {
        setState(() {
          _currentIndex--;
          _currentQuestion = _questionHistory[_currentIndex];
          _syncAnswerStateForCurrentQuestion();
        });
      }
    }
  }

  /// 檢查是否有上一題
  bool get _hasPreviousQuestion => _currentIndex > 0;

  /// 檢查是否有下一題（章節模式：檢查是否為最後一題；隨機模式：總是返回true，因為可以加載新題）
  bool get _hasNextQuestion {
    if (_usesFixedQuestionList && _chapterQuestions != null) {
      return _currentIndex < _chapterQuestions!.length - 1;
    } else {
      // 隨機模式：總是有下一題（可以加載新題）
      return true;
    }
  }

  /// 獲取當前題目的總數（章節模式返回實際數量，隨機模式返回歷史數量）
  int? get _totalQuestions {
    if (_usesFixedQuestionList && _chapterQuestions != null) {
      return _chapterQuestions!.length;
    } else {
      return _questionHistory.length;
    }
  }

  /// 构建顶部统计栏（玻璃态效果）
  Widget _buildStatsHeader(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final correct = _sessionRecords.values.where((value) => value).length;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.usesRoadPalette && !AppTheme.isRetroFor(context)
            ? AppTheme.headerBackgroundFor(context)
            : colors.surface.withOpacity(0.4),
        border: Border(bottom: BorderSide(
          color: colors.outline.withOpacity(0.2), width: 0.5,
        )),
      ),
      child: ClipRRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: SafeArea(
            bottom: false,
            child: Row(
              children: [
                IconButton(
                  tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                  icon: const Icon(Icons.arrow_back_ios_new, size: 20),
                  onPressed: _handleExitRequest,
                ),
                Expanded(
                  child: Wrap(
                    spacing: 12,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text('${AppStrings.getWithLanguage(_currentLanguage, 'stats_session_answered')} ${_sessionRecords.length}',
                        style: TextStyle(fontSize: 12, color: colors.onSurface)),
                      Text('${AppStrings.getWithLanguage(_currentLanguage, 'correct')} $correct',
                        style: TextStyle(fontSize: 12, color: colors.secondary)),
                      if (_sessionMistakes.isNotEmpty)
                        TextButton.icon(
                          key: const Key('session_mistakes_button'),
                          onPressed: _showSessionReview,
                          icon: const Icon(Icons.history, size: 16),
                          label: Text(AppStrings.getWithLanguage(
                            _currentLanguage, 'session_mistakes_button',
                          ).replaceAll('{count}', '${_sessionMistakes.length}')),
                        ),
                    ],
                  ),
                ),
                if (_usesFixedQuestionList && (_totalQuestions ?? 0) > 0)
                  SizedBox(
                    width: 40,
                    child: Semantics(
                      label: '${_currentIndex + 1} / $_totalQuestions',
                      child: FittedBox(
                        key: const Key('practice_question_counter'),
                        fit: BoxFit.scaleDown,
                        child: Text('${_currentIndex + 1}/$_totalQuestions'),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 使用 Consumer 監聽 UserStateProvider 的變化，特別是 isVip 狀態
    return PopScope(
      canPop: _isLeaving,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _handleExitRequest();
      },
      child: Consumer<UserStateProvider>(
        builder: (context, userStateProvider, child) {
          // 檢查 VIP 狀態是否從 false 變為 true
          final currentIsVip = userStateProvider.isVip;

          // VIP 狀態從 false 變為 true：只解除額度攔截，不重載正在進行的練習
          if (_previousIsVip == false && currentIsVip == true) {
            // 立即更新記錄的 VIP 狀態，避免重複觸發
            _previousIsVip = currentIsVip;

            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              switch (practiceActionAfterVipGained(
                hasLoadedQuestion: _currentQuestion != null,
                isLoading: _isLoading,
                quotaExceeded: _quotaExceeded,
              )) {
                case PracticeVipAction.initialize:
                  setState(() => _quotaExceeded = false);
                  _initializeQuestions();
                case PracticeVipAction.clearQuotaBlock:
                  setState(() => _quotaExceeded = false);
                case PracticeVipAction.none:
                  break;
              }
            });
          } else if (_previousIsVip != currentIsVip) {
            // 其他狀態變化（例如從 true 變為 false），也更新記錄
            _previousIsVip = currentIsVip;
          }

          return Scaffold(
            // 頁面底色由主題提供，內容較短時也不會露出黑色窗口底。
            backgroundColor: Theme.of(context).scaffoldBackgroundColor,
            body: Container(
              decoration: AppTheme.pageDecorationFor(context),
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _currentQuestion == null
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 24),
                            child: Text(
                              _quotaExceeded
                                  ? AppStrings.getWithLanguage(_currentLanguage,
                                      'practice_quota_placeholder')
                                  : AppStrings.getWithLanguage(_currentLanguage,
                                      'failed_to_load_question'),
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 15,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                            ),
                          ),
                        )
                      : Column(
                          children: [
                            // 顶部统计栏（玻璃态效果）
                            _buildStatsHeader(context),
                            // 題目內容
                            Expanded(
                              child: QuestionWidget(
                                question: _currentQuestion!,
                                onAnswerSelected: _onAnswerSelected,
                                onReadingChanged: _onReadingChanged,
                                currentLanguage: _currentLanguage,
                                isExamMode: false, // 練習模式
                                currentIndex: _currentIndex,
                                totalQuestions: _totalQuestions,
                                selectedAnswer:
                                    _answerStates[_currentQuestion!.id],
                                hasPreviousQuestion: _hasPreviousQuestion,
                                hasNextQuestion: _hasNextQuestion,
                                onPreviousQuestion: _previousQuestion,
                                onNextQuestion: _nextQuestion,
                                showQuestionCounter: _usesFixedQuestionList,
                                // 答题状态（用于 UI 反馈）
                                isAnswered: _isAnswered,
                                isCorrect: _isCorrect,
                                userChoice: _userChoice,
                                showFavoriteBadge: _showFavoriteBadge,
                                showMasteredBadge: _showMasteredBadge,
                                hideCorrectBadge: _hideCorrectBadge,
                                mistakeEliminated: _mistakeEliminated,
                                sessionCorrectStreak: _sessionCorrectStreak,
                                questionMasteryStep: _questionMasteryStep,
                              ),
                            ),
                          ],
                        ),
            ),
          );
        },
      ),
    );
  }
}
