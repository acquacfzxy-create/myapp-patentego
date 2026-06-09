import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../services/database_service.dart';
import '../services/firebase_status.dart';
import '../models/question.dart';
import '../config/app_strings.dart';
import '../providers/user_state_provider.dart';
import '../widgets/question_widget.dart';
import 'subscription_page.dart';

/// 練習模式頁面
/// 支持順序練習，顯示題目、圖片、解析等功能
class PracticeScreen extends StatefulWidget {
  final bool skipMastered;
  final int? chapterId; // 章節ID（可選），如果提供則只顯示該章節的題目
  final List<Question>? questions; // 預設題目列表（可選），用於錯題複習模式
  final bool isMistakeMode; // 是否為錯題複習模式

  const PracticeScreen({
    super.key,
    this.skipMastered = false,
    this.chapterId,
    this.questions,
    this.isMistakeMode = false,
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
    if (widget.questions != null && widget.questions!.isNotEmpty) {
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
      Navigator.of(context).pop();
    }
  }

  /// 處理答案選擇
  Future<void> _onAnswerSelected(bool selectedAnswer) async {
    if (_currentQuestion == null || _isAnswered) return; // 防止重复点击

    final isCorrect = selectedAnswer == _currentQuestion!.answer;

    // **在答題前查詢題目是否已經精通**
    final userStateProvider =
        Provider.of<UserStateProvider>(context, listen: false);
    final wasAlreadyMastered = await DatabaseService.isQuestionMastered(
      _currentQuestion!.id,
      userId: userStateProvider.effectiveUserId,
    );

    // 保存答案狀態
    _answerStates[_currentQuestion!.id] = selectedAnswer;

    // **錯題模式特殊處理：如果答對了，減少錯誤次數**
    bool mistakeEliminated = false;
    if (widget.isMistakeMode && isCorrect) {
      final remainingWrongCount = await DatabaseService.decreaseErrorCount(
        _currentQuestion!.id,
        userId: userStateProvider.effectiveUserId,
      );
      // 如果 wrong_count 降到 0，標記為已徹底消滅
      mistakeEliminated = remainingWrongCount == 0;

      // 刷新錯題統計（用於返回時更新列表）
      userStateProvider.refreshMistakeCount();
    }

    // 使用統一的進度更新方法
    // 注意：updateQuestionProgress 已經使用事務，且查詢只針對單個題目（WHERE question_id = ?），性能良好
    // 使用 PRIMARY KEY 索引，查詢速度很快
    final newlyMastered = await userStateProvider.updateQuestionProgress(
      _currentQuestion!.id,
      isCorrect,
    );

    // 優化：延遲批量更新掌握度統計（避免頻繁掃描整個 user_progress 表）
    // 只在距離上次更新超過一定時間，或者剛剛達成掌握時才更新
    final now = DateTime.now();
    final shouldUpdateStats = newlyMastered ||
        _lastMasteryStatsUpdate == null ||
        now.difference(_lastMasteryStatsUpdate!) > _masteryStatsUpdateInterval;

    if (shouldUpdateStats && mounted) {
      _lastMasteryStatsUpdate = now;
      // 在後台異步更新，不阻塞UI
      userStateProvider.refreshMasteryStats().catchError((_) {});
    }

    // **精通提示邏輯優化**
    // 1. 如果剛剛達成掌握（連續答對第三次），只顯示"已精通"氣泡，不顯示"正確"氣泡
    // 2. 如果題目已經精通且本次答對，只顯示"已精通"氣泡，不顯示"正確"氣泡
    // 3. 如果答錯，顯示"錯誤"氣泡（不顯示精通氣泡）
    // **關鍵：在設置 isCorrect 的同時就設置 hideCorrectBadge，避免中間狀態顯示"正確"氣泡**
    final shouldHideCorrectBadge =
        isCorrect && (newlyMastered || wasAlreadyMastered);

    // 设置答题状态（用于 UI 反馈）
    // 一次性設置所有狀態，避免中間狀態導致"正確"氣泡閃現
    setState(() {
      _isAnswered = true;
      _isCorrect = isCorrect;
      _userChoice = selectedAnswer;
      _mistakeEliminated = mistakeEliminated; // 設置錯題消滅狀態

      // **新邏輯：使用會話記錄來防止重複統計**
      // 記錄當前題目的答題結果（如果用戶返回上一題並重新點擊，會更新該記錄，但不會重複累加）
      _sessionRecords[_currentIndex] = isCorrect;

      // **精通提示邏輯：在設置 isCorrect 的同時就設置 hideCorrectBadge**
      if (shouldHideCorrectBadge) {
        // 答對且（剛剛達成掌握 或 已經精通），只顯示精通氣泡，隱藏"正確"氣泡
        _showMasteredBadge = true;
        _hideCorrectBadge = true; // 標記隱藏"正確"氣泡
        HapticFeedback.lightImpact();
      } else if (isCorrect) {
        // 答對但未精通，顯示"正確"氣泡（不顯示精通氣泡）
        _showMasteredBadge = false;
        _hideCorrectBadge = false; // 顯示"正確"氣泡
        // 如果錯題已消滅，觸發震動反饋
        if (mistakeEliminated) {
          HapticFeedback.mediumImpact();
        }
      } else {
        // 答錯，顯示"錯誤"氣泡（不顯示精通氣泡）
        _showMasteredBadge = false;
        _hideCorrectBadge = false; // 顯示"錯誤"氣泡（isCorrect 為 false）
      }
    });

    // 检查是否已收藏，显示收藏气泡
    final isFav = await DatabaseService.isFavorite(
      _currentQuestion!.id,
      userId: userStateProvider.effectiveUserId,
    );
    if (isFav) {
      setState(() {
        _showFavoriteBadge = true;
      });
    }

    // 0.8 秒延迟后自动切换到下一题（让用户看清反馈）
    await Future.delayed(const Duration(milliseconds: 800));
    if (mounted) {
      _nextQuestion();
    }
  }

  /// 顯示刷題限額彈窗（Paywall）
  /// 關閉時若用戶選擇「返回首頁」或點擊關閉按鈕，則 popUntil 回到首頁，避免留在空白練習頁
  Future<void> _showQuizLimitDialog() async {
    if (!mounted) return;
    setState(() => _quotaExceeded = true);
    final isLoggedIn = FirebaseStatus.isSignedIn;
    final lang = _currentLanguage;
    final message = isLoggedIn
        ? AppStrings.getWithLanguage(lang, 'quiz_limit_body_logged_in')
        : AppStrings.getWithLanguage(lang, 'quiz_limit_body_guest');

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false, // 不可點擊外部關閉，強制用戶選擇
      builder: (dialogContext) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.lock, color: Colors.amber, size: 28),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                AppStrings.getWithLanguage(lang, 'quiz_limit_reached'),
                style:
                    const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
            ),
            IconButton(
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
              backgroundColor: Colors.amber,
              foregroundColor: Colors.black,
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
          Navigator.of(context).popUntil((route) => route.isFirst);
        }
      }
    } else {
      // result == false 或 null：返回首頁，避免留在空白練習頁
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  /// 構建功能列表項（用於限額彈窗）
  Widget _buildFeatureItem(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 20, color: Colors.amber),
        const SizedBox(width: 12),
        Expanded(child: Text(text, style: const TextStyle(fontSize: 14))),
      ],
    );
  }

  /// 切換到下一題（優化：章節練習使用索引切換，不重新查詢數據庫）
  /// 檢查刷題限額：非VIP用戶每日限額30題
  Future<void> _nextQuestion() async {
    // 重置答题状态（用于 UI 反馈）
    setState(() {
      _isAnswered = false;
      _isCorrect = null;
      _userChoice = null;
      _showFavoriteBadge = false;
      _showMasteredBadge = false;
      _hideCorrectBadge = false; // 重置隱藏"正確"氣泡標記
      _mistakeEliminated = false; // 重置錯題消滅狀態
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

    if (widget.chapterId != null && _chapterQuestions != null) {
      // 章節練習模式：從預加載的列表中切換（不查詢數據庫）
      setState(() {
        _currentIndex++;

        // 如果已經到最後一題，循環回到第一題
        if (_currentIndex >= _chapterQuestions!.length) {
          // 如果跳過已掌握，重新加載列表（可能有新掌握的題目被排除）
          if (_skipMastered) {
            _loadChapterQuestions();
          } else {
            _currentIndex = 0;
            _currentQuestion = _chapterQuestions![_currentIndex];
          }
        } else {
          _currentQuestion = _chapterQuestions![_currentIndex];
        }
      });
    } else {
      // 隨機模式：優先從內存列表獲取
      if (_currentIndex < _questionHistory.length - 1) {
        // 內存中有下一題，直接切換（無需數據庫查詢，非常快）
        setState(() {
          _currentIndex++;
          _currentQuestion = _questionHistory[_currentIndex];
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
    // 重置答题状态（用于 UI 反馈）
    setState(() {
      _isAnswered = false;
      _isCorrect = null;
      _userChoice = null;
      _showFavoriteBadge = false;
      _showMasteredBadge = false;
      _hideCorrectBadge = false; // 重置隱藏"正確"氣泡標記
      _mistakeEliminated = false; // 重置錯題消滅狀態
    });

    if (widget.chapterId != null && _chapterQuestions != null) {
      // 章節練習模式
      if (_currentIndex > 0) {
        setState(() {
          _currentIndex--;
          _currentQuestion = _chapterQuestions![_currentIndex];
        });
      }
    } else {
      // 隨機模式
      if (_currentIndex > 0) {
        setState(() {
          _currentIndex--;
          _currentQuestion = _questionHistory[_currentIndex];
        });
      }
    }
  }

  /// 檢查是否有上一題
  bool get _hasPreviousQuestion => _currentIndex > 0;

  /// 檢查是否有下一題（章節模式：檢查是否為最後一題；隨機模式：總是返回true，因為可以加載新題）
  bool get _hasNextQuestion {
    if (widget.chapterId != null && _chapterQuestions != null) {
      return _currentIndex < _chapterQuestions!.length - 1;
    } else {
      // 隨機模式：總是有下一題（可以加載新題）
      return true;
    }
  }

  /// 獲取當前題目的總數（章節模式返回實際數量，隨機模式返回歷史數量）
  int? get _totalQuestions {
    if (widget.chapterId != null && _chapterQuestions != null) {
      return _chapterQuestions!.length;
    } else {
      return _questionHistory.length;
    }
  }

  /// 构建顶部统计栏（玻璃态效果）
  Widget _buildStatsHeader(BuildContext context) {
    // **新邏輯：從會話記錄中計算統計數字，確保準確性**
    // 已答數量：會話記錄的唯一題目數量
    final answeredCount = _sessionRecords.length;
    // 正確數量：會話記錄中答對的題目數量
    final correctCount = _sessionRecords.values.where((v) => v == true).length;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.4),
        border: Border(
          bottom: BorderSide(
            color: Colors.black.withOpacity(0.05),
            width: 0.5,
          ),
        ),
      ),
      child: ClipRRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: SafeArea(
            bottom: false,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // 返回按钮
                IconButton(
                  icon: const Icon(Icons.arrow_back_ios_new,
                      size: 20, color: Color(0xFF475569)),
                  onPressed: () => Navigator.of(context).pop(),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
                // 统计信息
                Row(
                  children: [
                    Row(
                      children: [
                        Text(
                          AppStrings.getWithLanguage(
                              _currentLanguage, 'stats_session_answered'),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: Colors.grey[600],
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '$answeredCount',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1E293B),
                          ),
                        ),
                      ],
                    ),
                    Container(
                      width: 1,
                      height: 12,
                      margin: const EdgeInsets.symmetric(horizontal: 20),
                      color: Colors.grey[300],
                    ),
                    Row(
                      children: [
                        Text(
                          AppStrings.getWithLanguage(
                              _currentLanguage, 'correct'),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: Colors.grey[600],
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '$correctCount',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF27AE60), // stats-green
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                // 占位（保持布局平衡）
                const SizedBox(width: 40),
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
    return Consumer<UserStateProvider>(
      builder: (context, userStateProvider, child) {
        // 檢查 VIP 狀態是否從 false 變為 true
        final currentIsVip = userStateProvider.isVip;

        // 如果 VIP 狀態從 false 變為 true，則重新加載題目
        if (_previousIsVip == false && currentIsVip == true) {
          // 立即更新記錄的 VIP 狀態，避免重複觸發
          _previousIsVip = currentIsVip;

          // VIP 狀態變更，在下一幀重新初始化題目
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              _initializeQuestions();
            }
          });
        } else if (_previousIsVip != currentIsVip) {
          // 其他狀態變化（例如從 true 變為 false），也更新記錄
          _previousIsVip = currentIsVip;
        }

        return Scaffold(
          backgroundColor: Colors.transparent,
          body: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFFE8F0F8), // 左上角：浅灰蓝（增加饱和度）
                  Color(0xFFF2F6FA), // 中间：浅灰蓝（增加饱和度）
                  Color(0xFFE8F0F8), // 右下角：浅灰蓝（增加饱和度）
                ],
                stops: [0.0, 0.5, 1.0],
              ),
            ),
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
                              color: _quotaExceeded
                                  ? Colors.grey[700]
                                  : Colors.grey[600],
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
                              showQuestionCounter:
                                  widget.chapterId != null, // 章節練習顯示，隨機刷題隱藏
                              // 答题状态（用于 UI 反馈）
                              isAnswered: _isAnswered,
                              isCorrect: _isCorrect,
                              userChoice: _userChoice,
                              showFavoriteBadge: _showFavoriteBadge,
                              showMasteredBadge: _showMasteredBadge,
                              hideCorrectBadge: _hideCorrectBadge,
                              mistakeEliminated: _mistakeEliminated,
                            ),
                          ),
                        ],
                      ),
          ),
        );
      },
    );
  }
}
